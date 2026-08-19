# Chapter 01, Who can read the password, and where has it already gone?

**System before this Chapter.** One machine, `HOST-01 dev01`. On it: a small HTTP service,
`APP-01 paymentsvc`, and a PostgreSQL database, `SVC-01 paymentsdb`. The app logs in to the
database as role `ACC-02 paymentsvc` using a password, `SEC-01 paymentsvc-db-password`,
which sits as ordinary readable text on line 4 of `/opt/paymentsvc/config.yaml`. You,
`ACC-01`, are the developer, operator, DBA, security team and auditor all at once. There is
no cryptography anywhere in the system, no component that decides who may have the password,
and no record of anyone ever reading it.

**The pressure.** `OT-001`. That password is sitting in a readable file. Two questions have
never been asked, and until they are, nothing else we build is anything but guesswork:

1. **Who can read it right now?** Not who *should*, who *can*.
2. **Where has it already gone?** A secret written down once does not stay in one place. It
   gets copied by mechanisms nobody chose, nobody configured and nobody watches.

**What you'll have working by the end of this Chapter.**

- A standing lab: `dev01` running as a Linux host with PostgreSQL and `paymentsvc`,
  which every later Chapter builds on.
- Seven distinct copies of `SEC-01` that you found yourself, on a machine where you believed
  there was one.
- A packet capture of your app authenticating, and a surprising result about what
  is and is not on the wire.
- A dedicated OS identity for the app, a locked-down config file, and a broken service that
  you diagnose and fix.
- A map of what file permissions closed, what they cannot touch, and why the only
  real remedy for a leaked credential is one we currently have no way to perform.

---

## 0. If your output differs

Machine-specific values, process IDs, timestamps, container IDs, byte counts, appear as
placeholders like `<pid>`.

Otherwise your output should match what is shown. If it does not, that is worth a minute
rather than a shrug; the two usual causes are a different PostgreSQL major version (check with
`sudo docker exec dev01 psql --version`) and a different Docker storage driver. Both are noted at
the points where they matter.

---

## 1. Standing up `dev01`

Chapter 00 gave `HOST-01 dev01` a name and a commitment. Now it becomes a running machine.

Everything you need is already next to this chapter, in its `lab/` folder. Work there, every
command in this chapter assumes that is your working directory:

```bash
cd "Chapter 01/lab"
ls
```

Expected: `docker-compose.yml` and a `dev01/` directory.

That folder is yours to break. You will edit files in it, commit them to a git repository you
create in §4.2, and leave debris in it deliberately. The copy you downloaded is the pristine
starting state; if you ever want it back, download the chapter again.

**The container outlives this chapter.** The lab is not the folder; it is the `dev01`
container the folder builds. It keeps running between chapters and accumulates state, and no
later chapter recreates it. Chapter 02 works from *its* own `lab/` folder and deploys into this
same container.

### 1.1 Why the app and database share one container

Chapter 00's ledger says `paymentsvc` and `paymentsdb` both run on `HOST-01`. That is
deliberate and it is what a real side project looks like: one box, everything on it, all of
it trusted because it is all *yours*. So `dev01` is one container running a full Debian
userland with PostgreSQL installed the ordinary way, not the official `postgres` image,
which gives you a database but not a *machine*. We need a machine, with users, processes, a
process table, log files and a network stack, because the entire point of this Chapter is to
walk around inside one and find things.

A **container** here is doing the job of a small server: an isolated Linux userland with its
own filesystem, its own process table and its own network interfaces, sharing the laptop's
kernel. It is not a security boundary we are relying on, several later Chapters are about the
ways that boundary leaks, it is a cheap way to have a machine.

One deliberate omission: we are **not** bind-mounting the app directory from your laptop
into the container. On macOS, Docker Desktop rewrites file ownership across that boundary,
which would quietly falsify every permission experiment in this chapter. Everything the
container does to its own files happens inside its own filesystem, so `ls -l` tells the
truth on every platform.

### 1.2 The files

Every file below is already in the `lab/` folder you are standing in. Nothing to create, and
nothing to retype. Read them here regardless: several details in them are the subject of this
chapter, and a couple are deliberate traps.

`dev01/app/config.yaml` is `SEC-01`'s home, exactly as Chapter 00 described it:

```yaml
# /opt/paymentsvc/config.yaml
database:
  host: localhost
  port: 5432
  user: paymentsvc
  password: hunter2-payments-prod          # <-- SEC-01
  name: paymentsdb
server:
  listen: 0.0.0.0:8080
```

`dev01/app/paymentsvc.py`, the application. About eighty lines: read the config,
open one database connection, serve two endpoints.

```python
#!/usr/bin/env python3
"""APP-01 paymentsvc, answers 'what is the status of payment X?'"""

import json
import logging
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import psycopg2
import yaml
from psycopg2.extras import RealDictCursor

CONFIG_PATH = os.environ.get("PAYMENTSVC_CONFIG", "/opt/paymentsvc/config.yaml")

logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[
        logging.FileHandler("/var/log/paymentsvc.log"),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger("paymentsvc")


def load_config(path):
    log.info("loading configuration from %s", path)
    with open(path) as fh:
        cfg = yaml.safe_load(fh)
    # NOTE (Chapter 01): this one line is deliberate, and it is extremely common
    # in real codebases. Chapter 01 shows you exactly what it costs.
    log.debug("effective configuration: %s", cfg)
    return cfg


cfg = load_config(CONFIG_PATH)
db = cfg["database"]

conn = psycopg2.connect(
    host=db["host"],
    port=db["port"],
    user=db["user"],
    password=db["password"],
    dbname=db["name"],
)
conn.autocommit = True
log.info("connected to %s@%s:%s/%s", db["user"], db["host"], db["port"], db["name"])


class Handler(BaseHTTPRequestHandler):
    server_version = "paymentsvc/0.1"

    def _json(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/healthz":
            return self._json(200, {"status": "ok"})

        parts = self.path.strip("/").split("/")
        if len(parts) == 3 and parts[0] == "payments" and parts[2] == "status":
            try:
                payment_id = int(parts[1])
            except ValueError:
                return self._json(400, {"error": "payment id must be an integer"})
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    "SELECT id, reference, amount_cents, currency, status "
                    "FROM payments WHERE id = %s",
                    (payment_id,),
                )
                row = cur.fetchone()
            if row is None:
                return self._json(404, {"error": "no such payment"})
            return self._json(200, dict(row))

        return self._json(404, {"error": "not found"})

    def log_message(self, fmt, *args):
        log.info("%s %s", self.address_string(), fmt % args)


if __name__ == "__main__":
    host, _, port = cfg["server"]["listen"].rpartition(":")
    srv = ThreadingHTTPServer((host, int(port)), Handler)
    log.info("listening on %s", cfg["server"]["listen"])
    srv.serve_forever()
```

Two things in that file matter more than they look.

`log.debug("effective configuration: %s", cfg)` logs the entire parsed config, including
`SEC-01`, whenever the log level is `DEBUG`. I did not put that there to trap you. It is in
an enormous number of codebases, for the entirely reasonable purpose of being able to
see what configuration a service actually loaded when it misbehaves at 03:00. We will watch
it leak in §3.4.

`psycopg2.connect(...)` takes the password as a **function argument**, which means it never
appears in the process's command line. That is the correct way to do it, and §3.3 shows what
happens when a tired human takes the other route.

`dev01/initdb.sql`, the database, its role and three payments:

```sql
CREATE ROLE paymentsvc LOGIN PASSWORD 'hunter2-payments-prod';
CREATE DATABASE paymentsdb OWNER paymentsvc;

\connect paymentsdb

CREATE TABLE payments (
    id           integer PRIMARY KEY,
    reference    text    NOT NULL,
    amount_cents integer NOT NULL,
    currency     char(3) NOT NULL,
    status       text    NOT NULL
);

INSERT INTO payments (id, reference, amount_cents, currency, status) VALUES
  (1001, 'INV-2026-0001', 249900, 'EUR', 'settled'),
  (1002, 'INV-2026-0002',  18050, 'EUR', 'pending'),
  (1003, 'INV-2026-0003', 990000, 'GBP', 'failed');

ALTER TABLE payments OWNER TO paymentsvc;
```

Note, without doing anything about it yet, that `SEC-01` now exists in a **second** file. It
had to: something has to tell PostgreSQL what the password is. That is copy number two and
we have not even started.

`dev01/entrypoint.sh`:

```sh
#!/bin/sh
set -e

pg_ctlcluster 15 main start

# wait for the cluster to accept connections
i=0
while [ $i -lt 30 ]; do
    su postgres -c "psql -tAc 'SELECT 1'" >/dev/null 2>&1 && break
    i=$((i + 1))
    sleep 1
done

if [ ! -f /var/lib/postgresql/.initialised ]; then
    su postgres -c "psql -v ON_ERROR_STOP=1 -f /opt/paymentsvc/initdb.sql"
    touch /var/lib/postgresql/.initialised
fi

# the application's log file, with the permissions an application log
# almost always has in the real world
touch /var/log/paymentsvc.log /var/log/paymentsvc.out
chown paymentsvc:paymentsvc /var/log/paymentsvc.log /var/log/paymentsvc.out
chmod 0644 /var/log/paymentsvc.log /var/log/paymentsvc.out

echo "dev01 ready, PostgreSQL is up."
exec sleep infinity
```

`pg_ctlcluster 15 main start` is Debian's way of starting a PostgreSQL cluster. Debian can
run several PostgreSQL versions side by side, so a cluster is identified by version and name,
here, version `15`, cluster `main`. Its configuration lives in `/etc/postgresql/15/main/`
and its data in `/var/lib/postgresql/15/main/`. You will use both paths later in this
chapter.

`exec sleep infinity` at the end is what keeps the container alive. A container exits when
its main process exits; we want a machine that sits there, so the main process is a sleep
and we do our work with `docker exec`.

`dev01/Dockerfile`:

```dockerfile
FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        postgresql-15 \
        python3 python3-yaml python3-psycopg2 \
        procps psmisc iproute2 tcpdump curl less nano ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# belt and braces: the Debian package normally creates the main cluster on
# install, but that step relies on an init system we do not have in a build
# container. Create it if it is missing.
RUN pg_lsclusters | grep -q '^15 *main' || pg_createcluster 15 main

# the identity the application will eventually run as. It exists from the
# start because the log file needs an owner; nothing runs as it until §7.
RUN useradd --system --home-dir /opt/paymentsvc --shell /usr/sbin/nologin paymentsvc

COPY app/paymentsvc.py /opt/paymentsvc/paymentsvc.py
COPY app/config.yaml   /opt/paymentsvc/config.yaml
COPY initdb.sql        /opt/paymentsvc/initdb.sql
COPY entrypoint.sh     /usr/local/bin/entrypoint.sh

# COPY reproduces whatever mode the file had on your laptop, and that is
# decided by your umask: 0644 under the common 022, 0664 under 002. Pin it,
# so section 3.1 shows you the same thing it shows everyone else. An image
# whose file modes depend on who built it is a bad image regardless.
RUN chmod 0644 /opt/paymentsvc/paymentsvc.py \
               /opt/paymentsvc/config.yaml \
               /opt/paymentsvc/initdb.sql \
 && chmod 0755 /usr/local/bin/entrypoint.sh

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
```

Every package there earns its place: `postgresql-15` is the database; `python3-yaml` and
`python3-psycopg2` are the app's two dependencies, installed as Debian packages so there is
no `pip`, no compiler and no network at runtime; `procps` gives us `ps` and `pkill`;
`tcpdump` and `iproute2` are for §5; `curl` is for testing.

`docker-compose.yml`:

```yaml
# The lab substrate: one container per "machine" in the ledger.
#
# Bring each machine up ONCE, in the chapter that introduces it, naming the
# service so you only build that one:
#     Chapter 01:  docker compose up -d --build dev01
#     Chapter 04:  docker compose up -d --build db01
#
# After that, chapters deploy into the running container with `docker cp`.
# Rebuilding is not forbidden, it is a reset: a rebuilt dev01 starts from
# Chapter 01's image again and loses everything the later chapters built
# inside it, which is OS accounts, file modes, database rows and some
# deliberately left log lines. If you do rebuild, you are starting the lab
# over and need to work the chapters forward again.
#
# This file is identical in every chapter's lab/ folder until a chapter
# adds a machine, so `docker compose up -d` from any of them is a no-op on
# a lab that is already running.
#
# Processes inside the containers are still started by hand. That is not an
# oversight: these hosts have no service manager, and giving them one is a
# chapter of its own.

name: lab

services:
  dev01:                                    # HOST-01, where the app and the secret store live
    build:
      context: ./dev01
      dockerfile: Dockerfile
    image: ksm/dev01:chapter01              # named for the chapter that builds it
    container_name: dev01
    hostname: dev01.lab.simurgh.example

    # Published on the laptop's loopback only, never on the network. The
    # difference between 127.0.0.1:8080:8080 and 8080:8080 is the difference
    # between a service your laptop can reach and one the coffee shop can.
    ports:
      - "127.0.0.1:8080:8080"

    # tcpdump needs this to put the loopback interface into the mode it
    # wants. Chapter 01 section 5 uses it.
    cap_add:
      - NET_ADMIN

    # Reap zombies and forward signals. The entrypoint ends in
    # `sleep infinity`, which is not a real init.
    init: true

    # Substrate only: tells you whether PostgreSQL is accepting connections,
    # so `docker compose ps` means something. It deliberately gates nothing,
    # because nothing in this build starts automatically yet.
    healthcheck:
      test: ["CMD", "pg_isready", "-q", "-h", "127.0.0.1", "-p", "5432"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 20s

    stop_grace_period: 5s
```

Compose, rather than a hand-rolled `docker run`, is the interface to the lab for the whole
build. It is the readable place to say what a machine *is*, and when later chapters need a
second machine they will add a service here rather than invent another command to remember.

Four lines deserve a note. `ports: "127.0.0.1:8080:8080"` publishes the app only on your
laptop's loopback interface, not on your Wi-Fi; the difference between that and `8080:8080` is
the difference between a service your laptop can reach and a service the coffee shop can reach.
`cap_add: NET_ADMIN` lets `tcpdump` inside the container put the loopback interface into the
mode section 5 needs. `init: true` gives the container a real init to reap zombies and forward
signals, because our entrypoint ends in `sleep infinity`, which is not one. And the
`healthcheck` tells you whether PostgreSQL is accepting connections, so `docker compose ps`
reports something meaningful.

Note what the healthcheck deliberately does **not** do: gate anything. Compose can start
services in dependency order and restart them when they die, and this build does not use either
feature, because nothing inside the container starts automatically. `HOST-01` has no service
manager. That is a gap, it will bite in a later chapter, and papering over it here with a
compose feature would hide the pressure that eventually fixes it properly.

### 1.3 Bring it up

From this chapter's `lab/` folder, the one holding `docker-compose.yml`:

```bash
sudo docker compose up -d --build dev01
```

Naming the service is a habit worth forming now, while there is only one to name.

The build takes a few minutes the first time, it is downloading Debian and PostgreSQL.
Then:

```bash
sudo docker compose ps
sudo docker exec dev01 pg_lsclusters
```

Expected: one container named `dev01`, and one cluster reported as `15 main ... online`. The
container's state goes from `starting` to `healthy` within about half a minute, once PostgreSQL
is accepting connections; if it stays `starting`, the cluster did not come up and
`sudo docker compose logs dev01` will say why.

Start the application. `docker exec -d` runs it detached, the way a service would run:

```bash
sudo docker exec -d dev01 sh -c 'python3 /opt/paymentsvc/paymentsvc.py >>/var/log/paymentsvc.out 2>&1'
```

### 1.4 Prove it works

```bash
curl -s http://127.0.0.1:8080/healthz
curl -s http://127.0.0.1:8080/payments/1001/status
curl -s http://127.0.0.1:8080/payments/9999/status
```

Expected:

```json
{"status": "ok"}
{"id": 1001, "reference": "INV-2026-0001", "amount_cents": 249900, "currency": "EUR", "status": "settled"}
{"error": "no such payment"}
```

That is the whole system from Chapter 00, now running. Figure 1.1 shows what you just built.

```mermaid
flowchart TB
    subgraph LAP["your laptop"]
        direction TB
        subgraph LAB["★ NET-01 lab, HOST-01 dev01 container (trusted entirely by assumption)"]
            direction TB
            CFG{{"SEC-01 in /opt/paymentsvc/config.yaml<br/>mode 0644, owner root:root"}}:::secret
            SQL{{"★ SEC-01 again, in /opt/paymentsvc/initdb.sql<br/>mode 0644, owner root:root"}}:::secret
            APP["APP-01 paymentsvc<br/>python3, running as root<br/>listening 0.0.0.0:8080"]:::app
            DB[("SVC-01 paymentsdb<br/>PostgreSQL 15, 127.0.0.1:5432")]:::store
            LOG[("★ /var/log/paymentsvc.log<br/>mode 0644")]:::store
        end
        U(["ACC-01 you"]):::human
    end

    U -.->|"docker exec, local socket, no protection"| LAB
    CFG -.->|"password bytes, file read at startup, no protection"| APP
    SQL -.->|"password bytes, read once at first boot, no protection"| DB
    APP -.->|"login as ACC-02, PostgreSQL 5432, nothing verifies the server"| DB
    APP -.->|"whatever it decides to write, file append, no protection"| LOG

    style LAP fill:#fffbeb,stroke:#b45309,stroke-width:2px,stroke-dasharray:6 4
    style LAB fill:#f8fafc,stroke:#475569,stroke-width:1px

    classDef human fill:#ffffff,stroke:#4b5563,stroke-width:2px,stroke-dasharray:4 3,color:#111827
    classDef app fill:#e5e7eb,stroke:#6b7280,stroke-width:1px,color:#111827
    classDef control fill:#dbeafe,stroke:#1d4ed8,stroke-width:2px,color:#0b1f4b
    classDef crypto fill:#fee2e2,stroke:#b91c1c,stroke-width:4px,color:#450a0a
    classDef store fill:#e2e8f0,stroke:#475569,stroke-width:1px,color:#0f172a
    classDef secret fill:#fef3c7,stroke:#b45309,stroke-width:2px,color:#451a03
    classDef best fill:#dcfce7,stroke:#15803d,stroke-width:3px,color:#052e16
    classDef retired fill:#f8fafc,stroke:#cbd5e1,stroke-width:1px,stroke-dasharray:2 4,color:#94a3b8
    classDef new stroke-width:3px,stroke-dasharray:6 3
```

**Figure 1.1, `dev01` as actually built.** Chapter 00's Figure 0.1 drawn against a running
machine. Two things changed by the mere act of making it real, both marked ★. First, there
are now **two** amber hexagons, not one: `SEC-01` is in `config.yaml` for the app and in
`initdb.sql` for the database, because something had to tell PostgreSQL what the password
is. Second, there is a log file, which nobody designed but which every service has. Note
also that your laptop is now drawn as an **untrusted zone** (dashed amber): the container is
the machine we are reasoning about, and everything outside it, your laptop's disk, its
backups, its cloud sync, is outside the boundary we are pretending to control. Every edge
is still dotted. Nothing here is protected by anything.

---

## 2. Two words we need before we start hunting

We are about to talk about who can read a file, so:

**Ownership and mode.** Every file on a Unix system has an owning **user**, an owning
**group**, and a nine-bit **mode** that grants read/write/execute separately to the owner,
the group, and *everyone else*. `0644` means: owner may read and write; group may read;
everyone else may read. That last clause is the one that matters. It is the default for
almost every file anything creates, and it means "every account on this machine".

**Authentication and confidentiality are different properties.** Authentication answers *who
is at the other end of this connection?* Confidentiality answers *can a third party read what
we are saying?* You can have either without the other. A system can prove your identity
perfectly and then discuss your salary at full volume in a crowded room. Hold on to that
distinction, §5 turns on it.

---

## 3. The hunt, part A: copies on this machine, right now

Everything in this section you will *demonstrate*. §6 lists the vectors that are real but
that we enumerate rather than run, and says so plainly, so you always know what you have
proven versus what you have been told.

Get a shell on the machine:

```bash
sudo docker exec -it dev01 bash
```

Everything in §3 runs inside that shell.

### 3.1 Copy 1 and 2, the files themselves

```bash
ls -l /opt/paymentsvc/
stat -c '%A %U:%G %s %n' /opt/paymentsvc/config.yaml /opt/paymentsvc/initdb.sql
```

Expected:

```
-rw-r--r-- root:root  196 /opt/paymentsvc/config.yaml
-rw-r--r-- root:root  612 /opt/paymentsvc/initdb.sql
```

`-rw-r--r--` is `0644`: readable by every account on the machine.

One note on how it got that way, because it makes the point rather than weakening it. The
Dockerfile pins these modes with an explicit `chmod`, so that the line above matches on your
machine as well as on mine. Left alone, `COPY` reproduces whatever mode the file happened to
have on your laptop, and that is decided by your **umask**: `0644` under the common `022`,
`0664` under the `002` that plenty of setups use. If you rebuild without the pin you may well
see `-rw-rw-r--` instead, which is world-readable *and* group-writable.

That variability is the lesson rather than an inconvenience. The permission on your production
credential was set by a shell default nobody in your organisation has looked at since the
machine was installed. Nobody chose `0644`, and nobody chose `0664` either. `cp` produces one
of them, your editor produces one of them, `git checkout` produces one of them, and the
overwhelming majority of secrets that have ever leaked out of a config file leaked out of a
file whose mode was inherited from something nobody was thinking about.

Check the whole path, because a file is only as private as the directories above it:

```bash
namei -l /opt/paymentsvc/config.yaml
```

Expected:

```
f: /opt/paymentsvc/config.yaml
 drwxr-xr-x root root /
 drwxr-xr-x root root opt
 drwxr-xr-x root root paymentsvc
 -rw-r--r-- root root config.yaml
```

Every directory is `r-x` for everyone, so every account can traverse down to the file, and
the file itself is `r--` for everyone. There is no gate anywhere on that path.

### 3.2 Copy 3, proving "everyone else" means everyone

`nobody` is the most powerless account a Linux system has. It owns nothing, it is in no
interesting groups, and it exists precisely so that things which need no privileges can run
without any. If `nobody` can read `SEC-01`, then every account on the machine can.

```bash
su -s /bin/sh nobody -c 'cat /opt/paymentsvc/config.yaml'
```

Expected: the entire config file, password included.

`su -s /bin/sh nobody` runs a command as `nobody`, overriding that account's usual
non-shell. There is no trick here and no privilege escalation: this is the ordinary,
designed behaviour of a file with mode `0644`.

Stop and let that land. Any process on this machine, a monitoring agent, a log shipper, a
crash reporter, a package post-install script, a compromised dependency in an unrelated
service, a colleague's debugging one-liner, reads `SEC-01` without touching anything
privileged and without leaving a trace anywhere.

### 3.3 Copy 4, the process table

`psycopg2.connect()` takes the password as an argument, so it never appears in the app's
command line. Now do what a tired human does at 03:00 when they want to check something
directly:

```bash
psql "postgresql://paymentsvc:hunter2-payments-prod@127.0.0.1:5432/paymentsdb" \
     -c 'SELECT pg_sleep(120)' &
```

While that runs, from the *least* privileged account on the box:

```bash
su -s /bin/sh nobody -c 'ps auxww' | grep 'postgresql://'
```

Expected: the full connection URI, password and all, printed by an account with no
privileges whatsoever.

This works because on Linux every process's command line is exposed through
`/proc/<pid>/cmdline`, and that file is world-readable by default. Anything you put in
`argv` is public to every account on the machine, for as long as the process lives, with no
way to redact it after the fact.

Look at it directly:

```bash
pgrep -f 'postgresql://' | head -1 | xargs -I{} sh -c 'tr "\0" " " < /proc/{}/cmdline; echo'
```

The same is true of a process's **environment**: `/proc/<pid>/environ`. That one is readable
by the process owner and by root rather than by everyone, which makes environment variables
*better* than command-line arguments and still a long way from good. We will return to
environment variables properly in a later Chapter, because they are the single most common
place secrets live in containerised systems.

Clean up:

```bash
pkill -f 'postgresql://' || true
```

### 3.4 Copy 5, the application's own log

Restart the app the way you would when you are debugging it:

```bash
exit                                  # leave the container shell
sudo docker exec dev01 pkill -f paymentsvc.py || true
sudo docker exec -d -e LOG_LEVEL=debug dev01 \
    sh -c 'python3 /opt/paymentsvc/paymentsvc.py >>/var/log/paymentsvc.out 2>&1'
sleep 2
sudo docker exec dev01 grep -n 'effective configuration' /var/log/paymentsvc.log
```

Expected: a `DEBUG` line containing the entire parsed configuration dictionary, with
`'password': 'hunter2-payments-prod'` in the middle of it.

Now check who can read that log:

```bash
sudo docker exec dev01 stat -c '%A %U:%G %n' /var/log/paymentsvc.log
sudo docker exec dev01 su -s /bin/sh nobody -c 'grep -c password /var/log/paymentsvc.log'
```

Expected: mode `-rw-r--r--`, and `nobody` counting the matches happily.

This is the vector that ruins people, and it is worth understanding exactly why it is so
hard to stamp out. The log line is *useful*. When a service connects to the wrong database
at 03:00, "what configuration did it actually load?" is the first question and this line is
the fastest possible answer. It was written by someone competent, for a good reason. And it
took a single environment variable, one that gets set during an incident, by someone under
pressure, and forgotten, to convert it into a permanent plaintext copy of your production
credential in a file that ships to your log aggregator, gets indexed, gets retained for
seven years for compliance reasons, and is searchable by everyone in the company.

Log aggregation is *worse* than the local file: the secret leaves the machine, is copied to
storage you did not configure, replicated for durability, and made searchable. There is no
`chmod` that reaches it.

Put the log level back:

```bash
sudo docker exec dev01 pkill -f paymentsvc.py || true
sudo docker exec -d dev01 sh -c 'python3 /opt/paymentsvc/paymentsvc.py >>/var/log/paymentsvc.out 2>&1'
```

Note carefully what you did *not* just do: the DEBUG line is still in
`/var/log/paymentsvc.log`. Turning the tap off does not empty the bucket.

### 3.5 Copy 6, what your tools leave behind

Make an innocuous edit to the config, say you want a longer connection timeout, using the
most ordinary command in the world:

```bash
sudo docker exec dev01 sed -i.bak 's/^  port: 5432/  port: 5432   # default/' /opt/paymentsvc/config.yaml
sudo docker exec dev01 ls -l /opt/paymentsvc/
```

Expected: a new file, `config.yaml.bak`, mode `0644`, owner `root:root`, containing the
previous version of the file, password included.

`sed -i.bak` is one example of a very large family. `vim` writes `.config.yaml.swp` while
you edit and `config.yaml~` when you save. Emacs writes `config.yaml~` and `#config.yaml#`.
`patch` writes `.orig` and `.rej`. Editors that crash leave the swap file behind forever.
Every one of these has mode `0644` and none of them is in anybody's mental model of "where
the secret lives".

This one matters far beyond the laptop: a `.bak` or `.swp` file left in a web server's
document root is served as plain text rather than executed, which is a bug class that has
been leaking database credentials to the open internet for twenty-five years and has not
stopped.

Leave the `.bak` file where it is for now. We come back to it in §8.

---

## 4. The hunt, part B: copies that have already left the machine

Copies 1 through 6 are all on `dev01`. In principle you could delete them. This section is
about the copies you cannot.

### 4.1 Copy 7, the backup

```bash
sudo docker exec dev01 tar czf /tmp/opt-backup.tar.gz /opt
sudo docker exec dev01 sh -c 'zcat /tmp/opt-backup.tar.gz | grep -a -c hunter2'
```

Expected: a `tar: Removing leading '/'` notice, then a non-zero count.

Nothing about that backup command is wrong. It is what every backup agent, every disaster
recovery job and every "let me snapshot this before I touch it" instinct does. And a backup
is a *particularly* bad place for a secret, because backups are deliberately engineered to
be durable, replicated, long-retained and restorable by people who are not you. A secret
that reaches your backup system has been given the strongest persistence guarantees your
organisation is capable of providing.

Rotating the password does not clean the backup. Deleting the file does not clean the
backup. That copy is valid until the retention policy expires it, which for a regulated
business is measured in years.

### 4.2 Copy 8, version control, and why this one is different

Everything so far you could, in principle, chase down and delete. Now for the one you
cannot.

On your laptop, not in the container. Put this chapter's `lab/` folder under version control,
exactly as you would with any project you were building:

```bash
git init
git config user.email "you@simurgh.example"
git config user.name  "you"
git add .
git commit -m "paymentsvc: initial lab environment"
```

*(If you obtained this chapter by cloning a repository, `git init` here creates a second,
independent repository nested inside it. That is harmless, the outer repository ignores it,
and it keeps this exhibit entirely yours. If you would rather not nest, copy the `lab/` folder
somewhere else first and run the rest of this section there.)*

Now realise your mistake and fix it properly:

```bash
sed -i.tmp 's/^  password: .*/  password: ${PAYMENTSVC_DB_PASSWORD}/' dev01/app/config.yaml
rm -f dev01/app/config.yaml.tmp
git add -A
git commit -m "paymentsvc: stop committing the database password"
```

The current file is clean. Verify it:

```bash
grep password dev01/app/config.yaml
```

Expected: `  password: ${PAYMENTSVC_DB_PASSWORD}`, no secret.

Now ask git:

```bash
git log --oneline
git show HEAD~1:dev01/app/config.yaml | grep password
```

Expected: the original line, with `hunter2-payments-prod` in it.

And the general form, which is how an attacker with a clone of your repository does
it, search every object in the entire history at once:

```bash
git grep -n hunter2 $(git rev-list --all) -- dev01/app/config.yaml
```

Expected: at least one hit, naming the commit that still contains it.

**Why this copy is categorically different.** Git is not a filesystem with a history; it is a
content-addressed object store where every version of every file is a permanent, immutable
object identified by a hash of its contents. "Removing" the password added a *new* object.
The old one is still there, reachable from the old commit, and it will be copied verbatim
into every clone anyone ever makes. If this repository has ever been pushed anywhere, then:

- every clone anyone has taken contains it, forever, offline, beyond your reach;
- your hosting provider's servers contain it, in backups and in caches you cannot enumerate;
- if the repository was ever public for even a few minutes, automated scrapers watching the
  public commit firehose have it. There is a well-established industry of exactly that, and
  the median time from a credential appearing in a public repository to it being used is
  measured in **minutes**, not days.

Actually removing it means rewriting history with a tool like `git filter-repo`, which
changes every commit hash after the affected commit, force-pushing, having every collaborator
re-clone, and then asking your hosting provider to garbage-collect the unreferenced objects
and expire their caches, and even then, any clone taken before you started still has it.

Which is why the honest answer to "we committed a secret" is never "we removed it from the
repository". It is: **that credential is compromised, change it.**

Hold that sentence. It is where this whole Chapter is going.

---

## 5. The hunt, part C: what is actually on the wire

Chapter 00's Figure 0.1 labelled the app-to-database edge as unprotected. Let us stop
describing it and look at it.

### 5.1 Capture it

```bash
sudo docker exec -d dev01 sh -c 'tcpdump -U -i lo -s 0 -w /tmp/pg-default.pcap tcp port 5432'
sleep 2
sudo docker exec dev01 pkill -f paymentsvc.py || true
sudo docker exec -d -e PGSSLMODE=disable dev01 \
    sh -c 'python3 /opt/paymentsvc/paymentsvc.py >>/var/log/paymentsvc.out 2>&1'
sleep 3
curl -s http://127.0.0.1:8080/payments/1001/status
sleep 1
sudo docker exec dev01 pkill tcpdump || true
```

Expected: the payment record for 1001, printed by that `curl`.

```json
{"id": 1001, "reference": "INV-2026-0001", "amount_cents": 249900, "currency": "EUR", "status": "settled"}
```

`tcpdump` is a packet capture tool: `-i lo` listens on the loopback interface (the app and
the database are on the same host, so their traffic never touches a physical NIC), `-s 0`
captures whole packets rather than truncating them, and `-w` writes a `.pcap` file. `-U`
writes each packet to the file as it arrives instead of buffering, so that killing `tcpdump`
cannot lose the last few seconds of the capture. We restart the app in the middle so that a
**fresh login** happens while we are watching, authentication only occurs when a connection is
established.

That `curl` is not decoration. If it printed a payment record, a query crossed the wire while
we were watching, and everything in the next section is about a capture that contains
something.

### 5.2 First, prove the capture is not empty

This step exists because of the shape of what we are about to find, and skipping it would let
you draw a conclusion from nothing:

```bash
sudo docker exec dev01 sh -c 'tcpdump -r /tmp/pg-default.pcap 2>/dev/null | wc -l'
```

Expected: a few dozen packets. The exact number varies; what matters is that it is not zero.

**If it is zero, stop here.** Everything below would appear to confirm the chapter and would
be measuring an empty file. The two things that cause it:

- **The application did not come back up**, so nothing ever connected. The `curl` above would
  have printed nothing rather than a payment record. Check `docker exec dev01 tail -5
  /var/log/paymentsvc.out`, fix whatever it says, and re-run section 5.1.
- **`tcpdump` never started**, usually because the previous run is still holding the file.
  `sudo docker exec dev01 pkill tcpdump`, then re-run section 5.1.

### 5.3 The surprising half

Look for the password:

```bash
sudo docker exec dev01 grep -a -c 'hunter2-payments-prod' /tmp/pg-default.pcap
```

Expected: `0`.

Read that number against the packet count you just took. On its own, `0` means either "the
password is not in this capture" or "there is nothing in this capture", and those are opposite
conclusions from identical output. A security measurement can come out clean because the
measurement failed, and the count in 5.2 is what stops that happening here.

It is not there. Now look for what the query returned:

```bash
sudo docker exec dev01 grep -a -o 'INV-2026-[0-9]*' /tmp/pg-default.pcap | sort -u
sudo docker exec dev01 sh -c "grep -a -o 'SELECT id, reference[^\"]*' /tmp/pg-default.pcap | head -1"
```

Expected: `INV-2026-0001`, and the full text of the query.

Read the two results together. **The credential was protected on the wire. The data was not.**

### 5.4 Why the password was not there

PostgreSQL 14 and later default to an authentication method called `scram-sha-256`. Confirm
it:

```bash
sudo docker exec dev01 grep -v '^#' /etc/postgresql/15/main/pg_hba.conf | grep -v '^$'
sudo docker exec dev01 su postgres -c "psql -tAc \"SELECT rolname, left(rolpassword,14) FROM pg_authid WHERE rolname='paymentsvc'\""
```

Expected: the `host ... 127.0.0.1/32 ... scram-sha-256` line, and a stored value beginning
`SCRAM-SHA-256`.

What SCRAM does, without yet opening up the mathematics: instead of sending the password, the
two sides exchange random values and each proves it knows the password by computing a value
that could only be produced by someone who knows it. An eavesdropper sees the random values
and the proofs, and can derive neither the password nor a token that would let them log in
later. The server never stores the password either, only a **verifier**, which is enough to
check a proof and not enough to produce one.

That is the first cryptography in this build, and note how it arrived: not
because we chose it, but because it was the default. Defaults are doing more security work in
your systems than your decisions are, which cuts both ways.

### 5.5 Why the data was not protected

Because nothing asked it to. The setting that decides is called **`sslmode`**, it belongs to
the client, and `disable` means no encryption. The capture in 5.1 started the application with
`PGSSLMODE=disable` in its environment, which is the same setting reached a different way, so
that this measurement gives you the same answer it gives everyone regardless of what your
distribution decided.

Nothing in `config.yaml` mentions `sslmode` at all, and that is the realistic part. An enormous
number of production systems have never written the line down, and their transport security is
therefore whatever a library default and a package default happen to agree on that week.

Confirm what the server thinks of the connection you just captured:

```bash
sudo docker exec dev01 su postgres -c "psql -tAc \"SELECT a.usename, s.ssl \
  FROM pg_stat_ssl s JOIN pg_stat_activity a USING (pid) WHERE a.usename = 'paymentsvc'\""
```

Expected: `paymentsvc|f`. The `f` is the whole of section 5.3's second result.

Turning it on is not the end of the story and is why this is not a two-line fix. Encryption
without verification protects you from someone **listening** and not at all from someone who
can **answer**, and the settings that do each are different. Chapter 04 takes that apart with a
working impostor, once there is a network between these two components worth attacking.

Figure 1.2 shows what an eavesdropper on that loopback interface sees today.

```mermaid
sequenceDiagram
    autonumber
    participant App as APP-01 paymentsvc
    participant Tap as tcpdump on lo
    participant DB as SVC-01 paymentsdb

    Note over App,DB: connection setup, sslmode=disable, no TLS is negotiated
    App->>DB: StartupMessage: user=paymentsvc, database=paymentsdb
    Tap-->>Tap: sees the USERNAME in plaintext
    DB-->>App: AuthenticationSASL: mechanism SCRAM-SHA-256
    App->>DB: client-first: nonce
    DB-->>App: server-first: combined nonce, salt, iteration count
    App->>DB: client-final: client proof
    Tap-->>Tap: sees nonces, salt, proof, NOT the password
    DB-->>App: server-final: server signature, AuthenticationOk

    Note over App,DB: session, everything below is plaintext
    App->>DB: Query: SELECT id, reference, amount_cents ... WHERE id = 1001
    Tap-->>Tap: sees the FULL SQL in plaintext
    DB-->>App: DataRow: 1001, INV-2026-0001, 249900, EUR, settled
    Tap-->>Tap: sees the PAYMENT RECORD in plaintext
```

**Figure 1.2, what the tap sees.** Time flows downward. During authentication (steps 1 to 8)
the eavesdropper collects the username, two nonces, a salt, an iteration count and a proof, and
can reconstruct the password from none of them. From step 9 onward there is no protection of
any kind: the full text of every query and every row of every result is readable. The credential
was defended; the payment records were handed over. Note also what is *missing* from the whole
exchange, the app never verified that the thing it connected to was really its database.
Nothing here would stop something else answering on port 5432.

Two consequences follow immediately, and they matter more than the password question:

**Confidentiality.** Every payment record this service ever reads crosses that connection in
readable form. On loopback the audience is small. The moment the database moves to a different
machine, which is Stage 2 and is coming, the audience is everyone on the network path.

**Server authentication.** SCRAM proves the *client* knows the password. Nothing in that
exchange proves the *server* is the real database. Anything that can occupy port 5432 first, or
answer a DNS query for the database's hostname, becomes the database. It will be handed every
query, including ones that reveal data, and can return whatever answers it likes. This is the
hole that TLS server certificates exist to close, and it is precisely the pressure that will
introduce certificates into this build, because we will *need* them, not because they are the
next topic.

### 5.6 The same system, configured the way many real ones are

`scram-sha-256` is the modern default. A great many production `pg_hba.conf` files still say
`md5`, because they were written years ago and copied forward, and some say `password`, which
sends the credential in the clear. This is not a contrivance; it is what you find when you go
and look.

Watch what one word costs:

```bash
# take a byte-for-byte copy first, reverting a regex is how labs end up
# silently running with weakened authentication for the next ten Chapters
sudo docker exec dev01 cp /etc/postgresql/15/main/pg_hba.conf /root/pg_hba.conf.orig

sudo docker exec dev01 sed -i -E 's/^(host[[:space:]].*[[:space:]])scram-sha-256([[:space:]]*)$/\1password\2/' \
    /etc/postgresql/15/main/pg_hba.conf
sudo docker exec dev01 grep -E '^(host|local)' /etc/postgresql/15/main/pg_hba.conf
sudo docker exec dev01 pg_ctlcluster 15 main reload

sudo docker exec -d dev01 sh -c 'tcpdump -U -i lo -s 0 -w /tmp/pg-plain.pcap tcp port 5432'
sleep 2
sudo docker exec dev01 pkill -f paymentsvc.py || true
sudo docker exec -d -e PGSSLMODE=disable dev01 \
    sh -c 'python3 /opt/paymentsvc/paymentsvc.py >>/var/log/paymentsvc.out 2>&1'
sleep 3
sudo docker exec dev01 pkill tcpdump || true

sudo docker exec dev01 grep -a -c 'hunter2-payments-prod' /tmp/pg-plain.pcap
```

Expected: a non-zero count. Your credential, in ASCII, on the wire.

Notice what had to be true for you to see it. The authentication method had to be downgraded
**and** the connection had to be unencrypted. Either one alone would have hidden it, which
means each of them is silently covering for the other. That is a comfortable position right up
to the day one of them is not there.

Put it back before you forget, by restoring the copy, not by inverting the regex:

```bash
sudo docker exec dev01 cp /root/pg_hba.conf.orig /etc/postgresql/15/main/pg_hba.conf
sudo docker exec dev01 pg_ctlcluster 15 main reload
sudo docker exec dev01 pkill -f paymentsvc.py || true
sudo docker exec -d dev01 sh -c 'python3 /opt/paymentsvc/paymentsvc.py >>/var/log/paymentsvc.out 2>&1'
```

That last command starts the application **without** `PGSSLMODE`, so the encryption setting
goes back to the library default and the lab is not left weakened by a measurement.

Now verify, and verify **every** authentication line, not just the ones you touched:

```bash
sudo docker exec dev01 grep -E '^(host|local)' /etc/postgresql/15/main/pg_hba.conf
```

Expected, check each line against this, because a half-reverted `pg_hba.conf` is a lab that
quietly runs with weakened authentication for the rest of the build:

| Line type | Correct method | What it means |
|---|---|---|
| `local ...` | `peer` | Unix-socket connections are authenticated by the OS uid at the other end of the socket. No password involved. Leave these alone. |
| `host ... 127.0.0.1/32 ...` | `scram-sha-256` | TCP connections, including the app's. This is the line 5.6 changed. |
| `host ... ::1/128 ...` | `scram-sha-256` | The IPv6 equivalent. |

This is why we copied the file rather than writing a clever inverse `sed`. A global substitution
is easy to apply and hard to undo exactly: it would also have rewritten the `local` lines and
the commented documentation block, and an anchored revert would have missed lines with trailing
whitespace. Restoring a known-good copy cannot half-apply. Prefer that shape of operation for
anything that changes an authentication policy. This is a habit worth forming now, because by
Stage 4 the equivalent mistake takes down a cluster.

---

## 6. The hunt, part D: enumerated, not demonstrated

`OT-001` asks for an honest enumeration, not a demonstration of everything. These vectors
are real and each has cost organisations real money. We are not running them here,
some need a kernel setting we cannot change from inside a container, some differ by Docker
version, and some would take longer to set up than they are worth right now. Each one names
its mechanism so you can verify it yourself on a machine you own.

| # | Vector | Mechanism | What it defeats |
|---|---|---|---|
| 9 | **Process memory** | `SEC-01` lives in the app's heap for the life of the process. `/proc/<pid>/mem`, a debugger, or `gcore` reads it. | Every file permission. The file could be deleted entirely and the secret is still there. |
| 10 | **Core dumps** | A crash writes the full heap to disk, at a path set by the host-wide `/proc/sys/kernel/core_pattern`, often with a wider mode than the config had, and often piped straight to a crash-reporting service. | File permissions, and your network boundary. |
| 11 | **Swap and hibernation** | Under memory pressure the kernel writes anonymous pages, including the heap holding `SEC-01`, to swap. Hibernation writes *all* of RAM to disk. Neither is encrypted unless you configured it. | File permissions, process isolation, and process lifetime, it outlives the process. |
| 12 | **Container image layers** | `COPY app/config.yaml` wrote `SEC-01` into an immutable image layer. Deleting the file in a later layer adds a whiteout marker; the original layer still contains the bytes and ships with the image to every registry and every host that pulls it. Inspect with `docker save` and unpack the layer archives, the exact layout differs between Docker's classic and containerd image stores, which is why we are not scripting it here. | Deletion. Same immutability problem as git, with worse distribution. |
| 13 | **PostgreSQL's own logs** | With `log_statement = 'all'` or on a connection error, the server may log queries and connection details. `ALTER ROLE ... PASSWORD` in particular can land in the server log in plaintext. | Your application's hygiene, this is the *other* side's log. |
| 14 | **Monitoring, APM and log shippers** | Agents that scrape process arguments, environment blocks, config files or stack traces, and forward them off-host to a system with its own retention and its own access model. | Every boundary on the machine. |
| 15 | **Human channels** | The password in a ticket, a chat message, a runbook, a wiki page, a screenshot, a screen share, a recorded video call, an email to a vendor. | All technical controls, completely. Usually the largest single vector, and the one nobody inventories. |
| 16 | **Deleted-file remnants** | `rm` unlinks; it does not erase. The blocks holding the old `config.yaml` remain readable to anyone with raw device access until reused, and on copy-on-write and log-structured filesystems, and on SSDs with wear levelling, "until reused" can be a very long time. | Deletion, again. |

Vector 15 deserves a moment. It is the one with no technical fix, it is almost always the
biggest, and the reason it is so large is *structural*: right now, if a colleague needs
access to `paymentsdb`, the only thing you can possibly give them is the password itself,
because the password is the only form the access comes in. The mechanism forces the leak. No
amount of training fixes a system whose only sharing primitive is "send them the secret".
That observation is the seed of a great deal of what we build later.

Figure 1.3 collects the whole surface.

```mermaid
flowchart TB
    SEC{{"SEC-01<br/>one password<br/>you thought there was one copy"}}:::secret

    subgraph ONHOST["on dev01, demonstrated in §3"]
        direction TB
        F1["1. config.yaml, mode 0644"]:::app
        F2["2. initdb.sql, mode 0644"]:::app
        F3["3. readable by nobody, i.e. every account"]:::app
        F4["4. process argv, world-readable via /proc"]:::app
        F5["5. app DEBUG log, mode 0644"]:::app
        F6["6. config.yaml.bak from sed -i"]:::app
    end

    subgraph GONE["already off the host, demonstrated in §4"]
        direction TB
        G1["7. backup tarball"]:::app
        G2["8. git history, in every clone, forever"]:::app
    end

    subgraph WIRE["on the wire, demonstrated in §5"]
        direction TB
        W1["password: NOT exposed, SCRAM-SHA-256"]:::best
        W2["payment records: fully exposed, sslmode=disable"]:::app
        W3["server identity: never verified"]:::app
    end

    subgraph ENUM["enumerated in §6, not run here"]
        direction TB
        E1["9-11. process memory, core dumps, swap"]:::app
        E2["12. container image layers"]:::app
        E3["13-14. server logs, monitoring agents"]:::app
        E4["15. tickets, chat, screenshots, email"]:::app
        E5["16. deleted-file remnants on disk"]:::app
    end

    SEC -.-> ONHOST
    SEC -.-> GONE
    SEC -.-> WIRE
    SEC -.-> ENUM

    style ONHOST fill:#f8fafc,stroke:#475569,stroke-width:1px
    style GONE fill:#fffbeb,stroke:#b45309,stroke-width:2px,stroke-dasharray:6 4
    style WIRE fill:#f8fafc,stroke:#475569,stroke-width:1px
    style ENUM fill:#fffbeb,stroke:#b45309,stroke-width:2px,stroke-dasharray:6 4

    classDef human fill:#ffffff,stroke:#4b5563,stroke-width:2px,stroke-dasharray:4 3,color:#111827
    classDef app fill:#e5e7eb,stroke:#6b7280,stroke-width:1px,color:#111827
    classDef control fill:#dbeafe,stroke:#1d4ed8,stroke-width:2px,color:#0b1f4b
    classDef crypto fill:#fee2e2,stroke:#b91c1c,stroke-width:4px,color:#450a0a
    classDef store fill:#e2e8f0,stroke:#475569,stroke-width:1px,color:#0f172a
    classDef secret fill:#fef3c7,stroke:#b45309,stroke-width:2px,color:#451a03
    classDef best fill:#dcfce7,stroke:#15803d,stroke-width:3px,color:#052e16
    classDef retired fill:#f8fafc,stroke:#cbd5e1,stroke-width:1px,stroke-dasharray:2 4,color:#94a3b8
    classDef new stroke-width:3px,stroke-dasharray:6 3
```

**Figure 1.3, the exposure surface of one password.** One secret at the top, sixteen
identified copies or exposures below it, grouped by whether we demonstrated them (solid
slate boxes) or enumerated them (dashed amber). The two amber groups are the ones that
matter most, and they share a property: those copies have **left the machine**, so nothing
you do on the machine reaches them. The only green box in the figure is SCRAM protecting the
password on the wire, the one thing in this entire system that was already being done
right, and we did not do it.

---

## 7. Make it fail, then fix it

You now know the exposure. Do the obvious thing about the part of it that file permissions
can reach: stop letting every account on the machine read the config file.

Immediately you hit a question that turns out to be the whole of Stage 2 in miniature.

**`chmod 600` grants read access to the file's owner. Who is the owner supposed to be?**

The file is owned by `root`. The app runs as `root`. So `chmod 600` would change nothing at
all, root reads everything regardless of mode. To make a permission mean something, the app
needs an identity of its own, distinct from yours and distinct from root's.

That is what `ACC-03` is for. The `paymentsvc` OS user already exists in the image; nothing
has run as it yet.

### 7.1 Break it

Do the lock-down in the order that feels natural and is wrong:

```bash
sudo docker exec dev01 chmod 0600 /opt/paymentsvc/config.yaml
sudo docker exec dev01 ls -l /opt/paymentsvc/config.yaml
```

Expected: `-rw------- 1 root root ... config.yaml`. Good, `nobody` is locked out. Confirm:

```bash
sudo docker exec dev01 su -s /bin/sh nobody -c 'cat /opt/paymentsvc/config.yaml'
```

Expected: `cat: /opt/paymentsvc/config.yaml: Permission denied`.

Now stop running the app as root and run it as its own identity:

```bash
sudo docker exec dev01 pkill -f paymentsvc.py || true
sudo docker exec -u paymentsvc dev01 python3 /opt/paymentsvc/paymentsvc.py
```

It fails. Expected, ending with:

```
PermissionError: [Errno 13] Permission denied: '/opt/paymentsvc/config.yaml'
```

Note that we ran it in the **foreground** here on purpose. Had we used `docker exec -d`, the
app would have died silently and `curl` would simply have refused to connect, which is a far
worse debugging position and exactly how this failure presents itself in production.

### 7.2 Diagnose it

Do not guess. Work the actual path:

```bash
sudo docker exec dev01 id paymentsvc
sudo docker exec dev01 stat -c '%A %U:%G %n' /opt/paymentsvc/config.yaml
sudo docker exec dev01 namei -l /opt/paymentsvc/config.yaml
```

Expected: `paymentsvc` has its own uid and gid and is in no other groups; the file is
`-rw-------` owned by `root:root`; every directory above it is traversable.

The three facts compose to a complete answer. The file grants read to its owner only. Its
owner is `root`. The process is `paymentsvc`. `paymentsvc` is not `root` and is not in a
group that has been granted anything. Therefore: denied.

`Errno 13` is `EACCES`, and it is worth knowing its neighbour: `Errno 2` / `ENOENT` is "no
such file". If you see `ENOENT` you have a path problem; if you see `EACCES` the path is
right and the identity is wrong. That one distinction will save you hours over a career.

### 7.3 Fix it

The mode was right. The ownership was wrong:

```bash
sudo docker exec dev01 chown paymentsvc:paymentsvc /opt/paymentsvc/config.yaml
sudo docker exec dev01 chmod 0400 /opt/paymentsvc/config.yaml
sudo docker exec dev01 ls -l /opt/paymentsvc/config.yaml
```

Expected: `-r-------- 1 paymentsvc paymentsvc ... config.yaml`.

`0400` rather than `0600`, because the application only ever *reads* this file. Write access
it does not need is write access an attacker who compromises it gets for free. This is the
**principle of least privilege** in its smallest possible form: give exactly the access
required, of exactly the kind required, and no more.

While you are here, deal with the debris §3.5 created and lock down the other copy:

```bash
sudo docker exec dev01 rm -f /opt/paymentsvc/config.yaml.bak
sudo docker exec dev01 chmod 0400 /opt/paymentsvc/initdb.sql
sudo docker exec dev01 chown paymentsvc:paymentsvc /opt/paymentsvc/initdb.sql
```

Now start it properly:

```bash
sudo docker exec -d -u paymentsvc dev01 \
    sh -c 'python3 /opt/paymentsvc/paymentsvc.py >>/var/log/paymentsvc.out 2>&1'
sleep 2
curl -s http://127.0.0.1:8080/payments/1002/status
sudo docker exec dev01 ps -o user,pid,cmd -C python3
```

Expected: the payment record for `1002`, and a process table showing `python3` running as
**`paymentsvc`**, not `root`. That second check is the one that matters, a service that
still runs as root has gained nothing from any of this.

---

## 8. Re-run the hunt: what closed, and what did not

This step is what determines whether you improved anything.

```bash
# copy 3, every account on the machine
sudo docker exec dev01 su -s /bin/sh nobody -c 'cat /opt/paymentsvc/config.yaml' ; echo "exit=$?"

# copy 6, editor debris
sudo docker exec dev01 ls -l /opt/paymentsvc/

# copy 5, the DEBUG log line from §3.4
sudo docker exec dev01 grep -c 'effective configuration' /var/log/paymentsvc.log

# copy 7, the backup
sudo docker exec dev01 sh -c 'zcat /tmp/opt-backup.tar.gz | grep -a -c hunter2'

# copy 8, version control (run this in the lab folder, not the container)
git grep -c hunter2 $(git rev-list --all) -- dev01/app/config.yaml

# and root
sudo docker exec dev01 cat /opt/paymentsvc/config.yaml | grep password
```

| # | Copy | Before | After | Closed by `chmod`/`chown`? |
|---|---|---|---|---|
| 1 | `config.yaml` | 0644 root | 0400 paymentsvc | **Yes**, narrowed to one identity |
| 2 | `initdb.sql` | 0644 root | 0400 paymentsvc | **Yes** |
| 3 | Readable by every account | Yes | No | **Yes** |
| 4 | Process argv | World-readable | Unchanged | No, a discipline, not a permission |
| 5 | DEBUG log line | Present, 0644 | **Still present, still 0644** | No |
| 6 | `config.yaml.bak` | Present | Deleted | Yes, *this instance*, the next tool makes another |
| 7 | Backup tarball | Contains it | **Still contains it** | No, already off-host |
| 8 | Git history | Contains it | **Still contains it, in every clone** | No, immutable and distributed |
| — | **root** | Reads it | **Still reads it** | **No, and it never can** |
| — | Process memory (§6) | Contains it | Still contains it | No |
| — | Image layer (§6) | Contains it | Still contains it | No |
| — | On the wire | Data exposed | Still exposed | No |

Three of the sixteen locations are closed; the twelve most instructive
are shown above. That is not nothing: closing "every account on this machine" is a
cheap, correct improvement and you should always do it. But look at what is left,
and notice that the survivors are all in one of two categories:

**Copies that have left the machine.** Backups, git history, image layers, log aggregators,
tickets. File permissions are a property of a filesystem; these copies are not on it. There
is no command you can run on `dev01` that reaches them.

**Root.** `chmod` is enforced by the kernel and root is the kernel's exception. Anyone who
is root on this box, including anyone who becomes root by exploiting *any* service on it,
and including anyone with `docker` access on your laptop, since `docker exec -u 0` is a root
shell, reads every secret on it. On this machine that is you, so it feels fine. It stops
feeling fine the moment there is more than one person, and Stage 3 is largely about what you
do when "root can read everything" is no longer an acceptable answer.

And now the conclusion that this entire Chapter exists to force. You cannot recall the copies
that have left. The credential must therefore be treated as compromised. **The only real
remedy for a leaked credential is to change it.**

So change it.

### 8.1 Try to rotate it

Actually attempt it, and count what it costs:

```bash
# 1. change it in the database
sudo docker exec dev01 su postgres -c \
    "psql -c \"ALTER ROLE paymentsvc PASSWORD 'a-new-value-you-choose'\""

# 2. the app is now broken. Confirm it.
sudo docker exec dev01 pkill -f paymentsvc.py || true
sudo docker exec -u paymentsvc dev01 python3 /opt/paymentsvc/paymentsvc.py 2>&1 | tail -3
```

Expected: `psycopg2.OperationalError: ... password authentication failed for user "paymentsvc"`.

To recover you must hand-edit `/opt/paymentsvc/config.yaml` inside the container, a file
you just made `0400`, so you must widen it, edit it, and narrow it again, and restart the
service. Then you must remember `initdb.sql`. Then the copy in git. Then any copy in a
ticket or a chat message that you cannot enumerate.

Put it back so the lab keeps working:

```bash
sudo docker exec dev01 su postgres -c \
    "psql -c \"ALTER ROLE paymentsvc PASSWORD 'hunter2-payments-prod'\""
sudo docker exec -d -u paymentsvc dev01 \
    sh -c 'python3 /opt/paymentsvc/paymentsvc.py >>/var/log/paymentsvc.out 2>&1'
sleep 2
curl -s http://127.0.0.1:8080/healthz
```

Count what that cost:

- **Downtime.** The credential changed in one place and the consumer found out by failing.
- **Manual editing of a protected file**, which means temporarily un-protecting it.
- **Two writes that must agree**, in two systems, with no mechanism keeping them consistent.
- **No inventory.** You do not have a list of everything holding `SEC-01`. You made this
  system yourself, six copies deep, in one afternoon.
- **No verification.** Nothing tells you the rotation is complete. You find out weeks later
  when something you forgot breaks.

Rotation is the fundamental operation of secret management: it is the only response to
compromise, the only defence against a copy you do not know about, and the thing every
regulation asks about first. On this system it is a manual, breaking, unverifiable operation
with no inventory behind it.

That is Chapter 02.

---

## 9. What just changed in the architecture

Figure 1.4 is Chapter 00's Figure 0.1 redrawn against what is now true. Compare them
side by side, the differences are small, and that smallness is the point.

```mermaid
flowchart TB
    subgraph LAP["your laptop, untrusted zone (docker access here is root on dev01)"]
        direction TB
        subgraph LAB["NET-01 lab, HOST-01 dev01 (trusted by assumption; root still reads everything)"]
            direction TB
            ROOT(["ACC-01 you, as root"]):::human
            SVCU(["★ ACC-03 paymentsvc, OS user, no shell"]):::human
            CFG{{"SEC-01 in config.yaml<br/>★ mode 0400, owner paymentsvc"}}:::secret
            SQL{{"SEC-01 in initdb.sql<br/>★ mode 0400, owner paymentsvc"}}:::secret
            APP["APP-01 paymentsvc<br/>★ runs as ACC-03, not root"]:::app
            DB[("SVC-01 paymentsdb<br/>PostgreSQL 15, scram-sha-256")]:::store
            LOG[("/var/log/paymentsvc.log<br/>mode 0644, still holds a DEBUG copy")]:::store
        end
    end

    subgraph OUT["copies already beyond reach, nothing on dev01 touches these"]
        direction TB
        BK[("backup tarball")]:::store
        GIT[("git history, every clone")]:::store
        IMG[("container image layer")]:::store
    end

    ROOT -.->|"reads anything, kernel exception to file modes, unstoppable"| CFG
    SVCU -.->|"reads at startup, file read, mode 0400 to one identity"| APP
    CFG -.->|"password bytes, file read, restricted to ACC-03"| APP
    APP -.->|"login as ACC-02, PostgreSQL 5432, SCRAM protects the password, nothing verifies the server"| DB
    APP -.->|"DEBUG copy written earlier, file append, world-readable"| LOG
    CFG -.->|"copied before we locked it, no protection"| OUT

    style LAP fill:#fffbeb,stroke:#b45309,stroke-width:2px,stroke-dasharray:6 4
    style LAB fill:#f8fafc,stroke:#475569,stroke-width:1px
    style OUT fill:#fffbeb,stroke:#b45309,stroke-width:2px,stroke-dasharray:6 4

    classDef human fill:#ffffff,stroke:#4b5563,stroke-width:2px,stroke-dasharray:4 3,color:#111827
    classDef app fill:#e5e7eb,stroke:#6b7280,stroke-width:1px,color:#111827
    classDef control fill:#dbeafe,stroke:#1d4ed8,stroke-width:2px,color:#0b1f4b
    classDef crypto fill:#fee2e2,stroke:#b91c1c,stroke-width:4px,color:#450a0a
    classDef store fill:#e2e8f0,stroke:#475569,stroke-width:1px,color:#0f172a
    classDef secret fill:#fef3c7,stroke:#b45309,stroke-width:2px,color:#451a03
    classDef best fill:#dcfce7,stroke:#15803d,stroke-width:3px,color:#052e16
    classDef retired fill:#f8fafc,stroke:#cbd5e1,stroke-width:1px,stroke-dasharray:2 4,color:#94a3b8
    classDef new stroke-width:3px,stroke-dasharray:6 3
```

**Figure 1.4, the architecture after Chapter 01.** Three things are new (★): the OS identity
`ACC-03 paymentsvc`, the mode-`0400` ownership of both files, and the fact that `APP-01` no
longer runs as root. One thing is newly *drawn* rather than newly true: the amber group on
the right, holding the copies that have already left the machine, which existed before this
Chapter and which we had simply not admitted to. `ACC-01` still has an unstoppable edge
straight to the secret, because root is the kernel's exception to file permissions and no
`chmod` will ever change that. Every edge in the figure is still dotted. We have narrowed who
may read `SEC-01` on this one machine; we have not encrypted it, we have not given anything
the ability to *decide* whether a request for it should be granted, and we still have no
record of any read ever happening.

---

## 10. Decisions we made (and what would change them)

| # | Decision | Options | Chosen | Why | What would flip it |
|---|---|---|---|---|---|
| D-006 | `dev01` is one container running a full Debian userland with PostgreSQL installed normally | (a) official `postgres` image + separate app container; (b) one Debian container with both | (b) | Chapter 00's ledger puts both on `HOST-01`, and this Chapter needs a *machine* to walk around in, users, a process table, logs, a network stack. The official image gives a database, not a host. | Stage 2, when the ledger genuinely gains a second host. Then they separate, and that separation is the pressure, not a tidy-up. |
| D-007 | No bind mounts between laptop and container | (a) bind-mount `./app` for fast edits; (b) `COPY` into the image | (b) | Docker Desktop on macOS rewrites ownership across a bind mount, which would silently falsify every `ls -l` in this chapter. Correctness of the lesson beats convenience of editing. | A Chapter where fast iteration on app code matters more than file-ownership fidelity. Then we bind-mount and say so. |
| D-008 | The app gets its own OS identity (`ACC-03`) and runs as it | (a) keep running as root and rely on the container boundary; (b) dedicated unprivileged user | (b) | A file mode is meaningless without an identity to grant it to, that is the direct lesson of §7.1. It also caps the blast radius of a compromise of the app to what that one account can reach. | Nothing. This is a floor, not a preference. Later Chapters strengthen it (no shell, read-only filesystem, capability dropping); none of them undo it. |
| D-009 | `0400`, not `0600` | (a) `0600` owner read-write; (b) `0400` owner read-only | (b) | The app only reads. Write access it does not need is write access an attacker inheriting the process gets for free. | A design where the process legitimately rewrites its own config, which should itself be questioned. |
| D-010 | Keep `scram-sha-256`; do not switch to `md5` or `password` | (a) `md5` for compatibility with old clients; (b) `password`, simplest; (c) `scram-sha-256` | (c), the default | §5 measured it: SCRAM keeps the credential off the wire and stores a verifier rather than a password-equivalent. `md5` stores and transmits a value that *is* password-equivalent, steal it and you can authenticate. `password` puts the credential in ASCII on the network. | A client library too old to speak SCRAM. The correct response is to upgrade the client, not downgrade the server; if it is genuinely impossible, the connection must be wrapped in TLS and the exception recorded on the risk register with an owner and a date. |

---

## 11. Where this still hurts

**Rotation is manual, breaking and unverifiable.** Changing `SEC-01` means an outage, a
hand-edit of a protected file inside a container, a second edit somewhere else, and no way to
confirm you found every consumer. This is the top of the queue.

**There is no inventory.** You cannot answer "where does `SEC-01` live?" from any system. You
answered it in this chapter by *going and looking*, and you found six copies on one machine
you built yourself this afternoon. Now imagine four hundred machines and eleven years.

**Root reads everything, and `docker` access is root.** Anyone with Docker on your laptop has
a root shell on `dev01` via `docker exec -u 0`. No file permission touches this.

**Nothing decides, and nothing is recorded.** There is still no component anywhere that
grants or refuses a request for `SEC-01`, and no record that any read ever happened. If the
password appeared on a paste site tomorrow you could not begin to narrow down where it came
from.

**Nothing verifies the server, and the transport is nobody's decision.** SCRAM protects the
credential and nothing else. Whether anything encrypts the payment records is settled by a
client library default and a distribution default that no file in this project names, and §5.6
showed how little has to change for the entire conversation to become readable. Even when
encryption is in play it defends against someone listening, not against someone answering: the
app has no way to tell its database from anything that occupies port 5432. Today the audience is
loopback; the day there are two machines, it is the network.

**`SEC-01` is immortal in process memory.** It sits in the heap for the life of the process,
reachable by anything that can read that memory, surviving into core dumps, swap and
hibernation images. Files were the easy part.

**The secret's lifetime is unbounded.** It was created once, has never changed, and has no
expiry. Every one of the sixteen copies is valid forever. Nothing in this system has any
concept of a credential that stops working on its own.

---

## 12. Chapter recap

- A file's mode is `0644` by default and nobody chooses it. `0644` means every account on
  the machine.
- `nobody`, the most powerless account on Linux, could read your production database
  password. That is the ordinary designed behaviour of `0644`, not an exploit.
- Anything in a process's `argv` is world-readable through `/proc/<pid>/cmdline`. Never put a
  secret on a command line. Environment variables are better and still not good.
- A single `LOG_LEVEL=debug` set during an incident converts a helpful config-dump line into a
  permanent plaintext credential in a file that ships to your log aggregator and is retained
  for years. Turning the tap off does not empty the bucket.
- Your editor, `sed -i.bak`, `patch` and a crashed `vim` all leave `0644` copies of the old
  file that are in nobody's mental model.
- Backups and git history are categorically different from everything else: those copies have
  **left the machine**, git's object store is immutable and distributed, and no command you
  run locally reaches them.
- The honest response to "we committed a secret" is never "we removed it". It is "that
  credential is compromised, change it."
- On the wire, PostgreSQL's default `scram-sha-256` kept the password out of the capture, while
  every payment record crossed in plaintext. **Authentication and confidentiality are different
  properties**, and this connection has the first and not the second.
- `sslmode` is the setting that decides the second one, no file in this project names it, and
  an enormous number of production systems are in exactly that position: their transport
  security is whatever a library default and a package default happen to agree on.
- Nothing in that exchange authenticated the *server*. Anything that answers on port 5432
  becomes the database. That is the hole certificates will eventually close, and encryption on
  its own will not: protecting against someone listening and someone answering are different
  settings.
- Seeing the password in ASCII needed the authentication method downgraded **and** the
  connection unencrypted. Each was silently covering for the other.
- A file permission needs an identity to hang off. `chmod 600` on a root-owned file read by a
  root-run process changes nothing, which is why `ACC-03` had to exist before the fix could
  mean anything. `Errno 13` is the wrong identity; `Errno 2` is the wrong path.
- Least privilege in its smallest form: `0400`, not `0600`, because the app never writes.
- Three of the sixteen recorded exposures closed. Everything that survived is either off the
  machine or is root, and root is the kernel's exception to file modes, permanently.
- Rotation is the fundamental operation of secret management, and on this system it is
  manual, causes an outage, requires un-protecting a protected file, and cannot be verified.

---

## 13. Prove it to yourself

**Q1. `nobody` has no privileges at all. Why could it read `SEC-01`? Was that a bug in Docker,
in Debian, or in PostgreSQL?**

None of them. It was the correct, designed behaviour of a file with mode `0644`, whose last
three bits grant read to "everyone else", and `nobody` is part of everyone else. No
component was at fault and nothing was misconfigured in the sense of deviating from its
default. That is exactly what makes this vector so durable: there is no error message, no
warning, and no audit finding, because from the system's point of view nothing went wrong.
The default *is* the vulnerability.

**Q2. `psycopg2.connect(password=...)` keeps the password out of `argv`. Why does that matter
more than it sounds, and why is `PGPASSWORD` in the environment better but still not good?**

`/proc/<pid>/cmdline` is world-readable on Linux, so anything in `argv` is visible to every
account on the machine for the whole life of the process, and you cannot redact it once the
process has started. `/proc/<pid>/environ` is readable only by the process's owner and root,
so the environment is a smaller audience. It is still not good because the
environment is inherited by every child process the app spawns (including a shell-out to a
tool that logs its environment on crash), it appears in most crash dumps and many APM
agents' captures, `docker inspect` prints container environment variables to anyone with
Docker access, and it is trivially dumped by anything that can already read the process. The
audience shrank; the mechanism did not improve.

**Q3. Turning `LOG_LEVEL` back to `INFO` stopped new leaks. Why was that not a fix, and what
makes log aggregation worse than the local file?**

Because the DEBUG line written during the incident is still in `/var/log/paymentsvc.log`,
still mode `0644`. Stopping the flow does not remove what already flowed. Aggregation is
worse in three ways at once: the secret leaves the host, so no local control reaches it; it
is deliberately replicated and long-retained, because that is what a log system is for; and
it is made *searchable* by everyone with access to the log platform, which in most
organisations is a far larger group than those who could log in to the server. A secret in a
log aggregator has been indexed, replicated and shared, three things you would never
consciously do to a credential.

**Q4. `git rm` the file, commit, and it is gone from the working tree. Why is it not gone,
and what is the difference between this and deleting the `.bak` file?**

Git is a content-addressed object store, not a filesystem with an undo log. Every version of
every file is an immutable object named by a hash of its contents, and commits reference
them. Removing the password created a *new* blob; the old one is still reachable from the
older commit, is copied into every clone, and is pushed to every remote. Deleting the `.bak`
file removed that copy, it was one file, on one filesystem, that you control.
Git's copy is immutable and has been *distributed*. Removing it requires rewriting history,
which changes every subsequent commit hash, forcing every collaborator to re-clone, plus
provider-side garbage collection, and still does not reach a clone someone took last
Tuesday.

**Q5. Your capture showed the payment records but not the password. Explain both halves, and
say which of the two you should be more worried about.**

The password was absent because PostgreSQL 14+ defaults to `scram-sha-256`: the client proves
knowledge of the password through a challenge-response exchange, so only nonces, a salt and a
proof cross the wire, and none of them yields the password or a reusable token. The records were
present because the capture ran with `PGSSLMODE=disable`, so no encryption was negotiated at
all, and once
authentication completed, every query and every result row travelled as plaintext. You should be
more worried about the records. The password protects access to the data; the data is the thing
you were protecting in the first place, and it is going across unprotected in bulk, every
second, forever. It is a common and expensive mistake to treat "credentials are safe" as "the
connection is safe".

**Q6. Nothing in the SCRAM exchange authenticated the server. What can an attacker who can
answer on port 5432 do, and which later Chapter closes this?**

They become the database. The app connects, the impostor speaks the PostgreSQL protocol, and
because the app has no way to verify what it is talking to, it proceeds: it sends its
username, completes SCRAM (the impostor cannot verify the proof, but it does not need to,
it just says "authentication OK"), and then sends every query it was going to send. The
impostor now sees which payments are being looked at and can return any answers it likes,
including ones that cause the application to make wrong decisions about real money. Reaching
this requires occupying the port first, poisoning DNS, or getting on the network path. The
fix is server authentication via TLS with a certificate the client actually verifies, which
is precisely the pressure that introduces certificates in Stage 2, because two machines that
must trust each other over a network is the problem certificates were invented for.

**Q7. Why did `chmod 0600` on the config file, on its own, change nothing?**

Because the file was owned by `root` and the process ran as `root`. `0600` grants read and
write to the *owner*, so root-owned-and-root-run means root reads it exactly as before, and
root would read it anyway, since root is the kernel's exception to file permission checks.
A permission bit is a statement about an identity. With only one identity in the picture,
and that identity being the one the rules do not apply to, the statement is empty. The
control only meant something once `ACC-03` existed and the process ran as it.

**Q8. You saw `PermissionError: [Errno 13]`. Walk the diagnosis, and say what `Errno 2` would
have meant instead.**

Three commands, three facts. `id paymentsvc` shows the process's identity and its groups.
`stat -c '%A %U:%G'` shows what the file grants and to whom. `namei -l` shows whether every
directory on the path is traversable. Compose them: the file grants read to owner only, the
owner is `root`, the process is `paymentsvc`, and `paymentsvc` is in no group that was
granted anything, therefore denied. `Errno 13` (`EACCES`) means the path resolved correctly
and the identity was refused. `Errno 2` (`ENOENT`) would mean the path did not resolve at
all: wrong filename, wrong directory, a mount that is not there, or a symlink pointing
nowhere. Access problem versus path problem, do not spend an hour checking permissions on a
file that is not there.

**Q9. Three of sixteen exposures closed. Group the survivors into two categories and say why
each is beyond the reach of `chmod`.**

**Copies that left the machine** — backups, git history and its clones, container image
layers, log aggregators, tickets and chat. File permissions are a property of one filesystem,
enforced by one kernel; these copies are on other systems, under other people's control,
with their own retention and access models. No command on `dev01` reaches them.
**Root** — because file mode checks are performed by the kernel and root is the documented
exception to them. This includes anyone who becomes root by exploiting any service on the
box, and anyone with Docker access on your laptop, since `docker exec -u 0 dev01 bash` is a
root shell. The first category needs a different *architecture*; the second needs a different
*trust model*, which is what hardware-backed key custody in Stage 3 is ultimately about.

**Q10. Why is rotation the fundamental operation of secret management, and name four specific
costs you measured when you tried it in §8.1.**

Because it is the only response to compromise that works. You cannot recall a copy;
you can only make every copy worthless, and changing the value is the only way to do that.
It is also the only defence against the copies you do not know about, which, as this Chapter
demonstrated, are the majority. The four costs: (1) **downtime**, the consumer discovered
the change by failing; (2) **un-protecting the protected file**, you had to widen `0400` to
edit it, restoring the exposure you had just closed; (3) **two writes that must agree** in
the database and in the config, with nothing keeping them consistent; (4) **no inventory and
no verification**, you had no list of consumers and nothing told you the rotation was
complete, so you would find out weeks later when something you forgot broke.

**Q11. Before §5 you would probably have guessed the password was the thing crossing in the
clear. It was not. Why does getting that backwards matter beyond pedantry?**

Because an architecture document is used to decide where to spend effort. Someone who believes
the password crosses in the clear prioritises the credential path and buys nothing, because
SCRAM already handled it, while the actual exposure, every payment record readable with no
server authentication, sits untouched. Overstating a weakness misdirects work exactly as
effectively as understating one, and it costs you the reader's trust in every other claim the
document makes. This is why §5 takes a capture instead of reasoning about the protocol: a
diagram is a claim about a system, and a claim nobody measured is a guess with a border
around it.

**Q12. This chapter demonstrated eight vectors and enumerated eight more. Why is enumeration
without demonstration acceptable here, and where is the line?**

Because `OT-001` asked *who can read this and where has it gone*, and an honest,
mechanism-level answer to that question is the deliverable, a complete map beats a partial
map with better props. The line is that every enumerated vector must name its **concrete
mechanism** (`/proc/<pid>/mem`, `core_pattern`, whiteout layers in an image, swap pages), so
you can verify any of them yourself on a machine you control, and the chapter must say
plainly which is which so you always know what you have proven versus what you have been
told. What is *not* acceptable is presenting an unrun command's invented output as a
captured session. That is the difference between a simplification and a fabrication.

---

## 14. Leaving the lab standing

**Leave it running.** Chapter 02 builds directly on this container.

```bash
sudo docker compose ps                 # should show dev01 running
curl -s http://127.0.0.1:8080/healthz
```

If you rebooted, bring it back:

```bash
sudo docker start dev01
sudo docker exec -d -u paymentsvc dev01 \
    sh -c 'python3 /opt/paymentsvc/paymentsvc.py >>/var/log/paymentsvc.out 2>&1'
```

Note that the app does **not** restart by itself. There is no service manager, so a reboot
means a manual start. That is a gap, and it will be fixed by a pressure rather than by
tidiness.

Optional housekeeping, the capture files hold payment data and one of them holds the
password in ASCII:

```bash
sudo docker exec dev01 rm -f /tmp/pg-default.pcap /tmp/pg-plain.pcap /tmp/opt-backup.tar.gz
```

Keep the git repository exactly as it is. The password in its history is now a permanent
exhibit, and later Chapters refer back to it.

**Full teardown**, only if you want to abandon the build (this destroys the database and
everything you did inside the container):

```bash
sudo docker rm -f dev01
sudo docker image rm ksm/dev01:chapter01
```
