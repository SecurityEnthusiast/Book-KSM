# Chapter 06, The key that cannot be copied

**System before this chapter.** Three machines. `HOST-01 dev01` runs `APP-01 paymentsvc` and
`SVC-02 secretstore`; `HOST-02 db01` runs `SVC-01 paymentsdb` and presents `CERT-03`;
`HOST-03 ca01` holds `KEY-02` and `CERT-02` and signs certificates on request. `APP-01`
verifies the database against the authority rather than against the database, so a server
certificate can be re-issued without touching any client.

**The pressure.** `OT-021`. That authority is a file.

> `KEY-02` can sign a certificate for any name in the estate, and what stands between an attacker
> and it is mode `0600` on a container. Root reads it. Anyone with Docker on the laptop reads it,
> because `docker exec -u 0` is a root shell. A backup of `/var/lib` captures it. And it is
> readable while in use, because signing means handing the key to a process.

Chapter 01 hit this wall and named it: file modes are enforced by a kernel that has an
exception for root. Narrowing the mode moves nothing. The problem is not that the permission is
too wide. The problem is that the key is a file that can be read at all.

**What you'll have working by the end of this chapter.**

- A forged certificate for a host you do not own, made in three commands from a stolen key
  file, which is the pressure measured rather than asserted.
- `KEY-03`, generated inside a PKCS#11 token, which the token will describe as
  `sensitive, always sensitive, never extractable, local`.
- A signing operation that moves to the key instead of the key moving to the operation.
  `openssl` produces certificates with a private key it is never given.
- `CERT-04`, a root signed by a key that has never existed as bytes anywhere.
- A migration onto that new root with **no downtime and no window**, using the same trick
  `PROC-01` used for credentials.
- A precise account of what a software token buys, and of the one attacker it does not stop.

---

## 0. If your output differs

Machine-specific values will differ: certificate serials, dates, process IDs, and in particular
**PKCS#11 slot numbers**. SoftHSM assigns a slot at random every time a token is initialised,
so yours will not match and nothing in this chapter refers to one. Tokens are addressed by
label throughout, and that is a rule rather than a convenience.

The PINs in this chapter are `5678` and `1234`. They are lab values written down in a book,
which tells you exactly how seriously to take them, and §12 is about that.

Work in this chapter's `lab/` folder:

```bash
cd "chapters/Chapter 06/lab"
ls
```

Expected: `docker-compose.yml`, and the directories `dev01/`, `db01/` and `ca01/`.

### The lab in full

What **this** chapter writes is marked ★:

```
lab/
├── docker-compose.yml              ★ changed: ca01 retagged, it is rebuilt here
├── dev01/
│   ├── Dockerfile                    Chapter 01
│   ├── entrypoint.sh                 Chapter 01
│   ├── initdb.sql                    Chapter 01, seed for dev01 only, never re-run
│   ├── app/
│   │   ├── config.yaml               Chapter 05, unchanged: the anchor path is the same
│   │   └── paymentsvc.py             Chapter 04
│   └── secretstore/
│       ├── secretstore.py            Chapter 03
│       ├── secretstore-set.py        Chapter 02
│       └── policy.json               Chapter 03
├── db01/
│   ├── Dockerfile                    Chapter 04
│   ├── entrypoint.sh                 Chapter 04
│   └── impostor.py                   Chapter 04
└── ca01/
    ├── Dockerfile                  ★ changed: a token, and no key file
    ├── entrypoint.sh                 Chapter 05
    ├── hsm-init.sh                 ★ new: PROC-03, the key ceremony
    └── sign-leaf.sh                ★ changed: signs through the token
```

**`config.yaml` does not change, and that is worth a moment.** The anchor is still
`/opt/paymentsvc/ca.crt`. What changes is the bytes in that file, twice, and the application
has no opinion about either change. A client that verifies against an authority is insulated
from everything that happens to the authority's key, which is the property Chapter 05 bought
and this chapter spends.

**A note on the Dockerfiles.** `dev01/Dockerfile` is still Chapter 01's, and does not create
the accounts later chapters added. Those arrived as chapter work. The folder shows every file
the running system uses; the `dev01` image does not build that system from scratch.

### Before you start: this chapter continues an existing lab

`dev01` is built once in Chapter 01, `db01` once in Chapter 04, `ca01` once in Chapter 05. This
folder carries every file the running system uses, so you can read the whole thing in one
place, but **building from here does not give you this chapter's starting state.** That state
is what running the earlier chapters leaves behind.

A `healthy` container tells you PostgreSQL is accepting connections and **nothing about the
application**, which is started by hand because these hosts have no service manager.

If you have not worked the earlier chapters, start at Chapter 01. If you have, check that the
lab is where this chapter expects it:

```bash
sudo docker exec ca01 ls -l /var/lib/ca/ca.key /var/lib/ca/ca.crt
sudo docker exec dev01 openssl x509 -in /opt/paymentsvc/ca.crt -noout -subject
curl -s http://127.0.0.1:8080/credinfo
```

Expected: `ca.key` at mode `-rw-------` owned by `ca`, and `ca.crt` beside it; an anchor on
`dev01` whose subject is `CN = Simurgh Lab Root CA`; and a `credinfo` reply with
`"sslmode": "verify-full"`.

If the containers are stopped, start everything first. `db01` comes up before `APP-01`, and
`SVC-02` before it too, which is `OT-012`:

```bash
sudo docker start db01 ca01 dev01
sudo docker exec dev01 sh -c '
  for i in $(seq 1 30); do pg_isready -q -h 127.0.0.1 -p 5432 && break; sleep 1; done
  pg_ctlcluster 15 main stop'
sudo docker exec -d -u secretstore dev01 \
    sh -c 'python3 /opt/secretstore/secretstore.py >>/var/log/secretstore.out 2>&1'
sleep 1
sudo docker exec -d -u paymentsvc dev01 \
    sh -c 'python3 /opt/paymentsvc/paymentsvc.py >>/var/log/paymentsvc.out 2>&1'
```

Expected: `{"status": "ok"}` from a `curl` to `/healthz`, and the state check above passing.

**If the state check still fails after that**, the containers are not in this chapter's
starting state. Take everything down and work forward from Chapter 01:

```bash
sudo docker compose down
cd "../../Chapter 01/lab" && sudo docker compose up -d --build dev01
```

---

## 1. Steal the key, and become anyone

`OT-021` says `KEY-02` can forge any identity in the estate. Chapter 05 asserted that. Measure
it, because the migration ahead costs a new root and every client, and nobody should pay that
on an assertion.

You are root on `ca01`, which in this lab you always are, and in a real estate is one exploited
service away. Take the key:

```bash
sudo docker exec ca01 cat /var/lib/ca/ca.key > /tmp/stolen-ca.key
sudo docker exec ca01 cat /var/lib/ca/ca.crt > /tmp/stolen-ca.crt
ls -l /tmp/stolen-ca.key
head -1 /tmp/stolen-ca.key
```

Expected: a file of a few hundred bytes beginning `-----BEGIN PRIVATE KEY-----`. The authority
for this entire build is now on your laptop, and nothing recorded that it left.

Now forge. Pick a name you have no business speaking for:

```bash
openssl ecparam -name prime256v1 -genkey -noout -out /tmp/forged.key
openssl req -new -key /tmp/forged.key -out /tmp/forged.csr \
  -subj "/CN=vault01.lab.simurgh.example"
printf "subjectAltName=DNS:vault01.lab.simurgh.example\nbasicConstraints=critical,CA:FALSE\nextendedKeyUsage=serverAuth\n" > /tmp/forged.ext
openssl x509 -req -in /tmp/forged.csr \
  -CA /tmp/stolen-ca.crt -CAkey /tmp/stolen-ca.key -CAcreateserial \
  -days 90 -sha256 -extfile /tmp/forged.ext -out /tmp/forged.crt 2>/dev/null
openssl x509 -in /tmp/forged.crt -noout -subject -issuer
```

Expected: subject `CN = vault01.lab.simurgh.example`, issuer `CN = Simurgh Lab Root CA`.

Now the part that matters. Ask the client whether it would believe it:

```bash
sudo docker cp /tmp/forged.crt dev01:/tmp/forged.crt
sudo docker exec dev01 openssl verify -CAfile /opt/paymentsvc/ca.crt \
    -verify_hostname vault01.lab.simurgh.example /tmp/forged.crt
```

Expected: `/tmp/forged.crt: OK`.

`APP-01` would accept that certificate for a host that does not exist yet, presented by
anything that answers to the name. There is no host called `vault01` in this build. There will
be, and the certificate for it is already sitting in `/tmp` on your laptop, valid for ninety
days, signed by the authority every client trusts.

**Read what the theft cost.** Two `cat` commands. No exploit, no privilege escalation, nothing
that would look unusual in a shell history, and no record anywhere that the key was read.
Chapter 05 §12 said a file mode was all that protected this. That is what a file mode is worth
against somebody who is root, which is the same sentence Chapter 01 §8 ended on, arriving one
level up and considerably more expensive.

Clean up the evidence, and notice that you cannot clean up the consequence:

```bash
rm -f /tmp/stolen-ca.key /tmp/stolen-ca.crt /tmp/forged.key /tmp/forged.csr /tmp/forged.ext
sudo docker exec dev01 rm -f /tmp/forged.crt
```

The forged certificate is deleted here because this is a lab. In an incident it would not be,
and you would have no way to know it existed. That is `OT-022`, revocation, still open and now
with a concrete reason to care.

---

## 2. Moving the operation to the key

Every protection this build has used works by deciding **who may open a file**. File modes,
ownership, `POL-01`, peer credentials: all of them answer "may this identity read this thing".
Root is the exception to all of them, and §1 is what that exception is worth.

A different arrangement is possible, and it is the last one available. Stop letting the key be
read at all, by anyone, and make the operations that need it happen **where it lives**:

> The application does not get the key and use it. The application sends the thing to be signed
> to the place the key is, and gets back a signature. The key never moves, so there is no read to
> permit or forbid.

That is a **cryptographic boundary**, the category Chapter 00's visual language reserved and
this build has never been allowed to draw. Its defining property is not that the key is well
protected. It is that **there is no interface that returns the key**, not for an attacker and
not for its legitimate owner either.

```mermaid
flowchart LR
    subgraph BEFORE["Until Chapter 05: the key travels"]
        direction TB
        F{{"KEY-02 ca.key 0600<br/>a file"}}:::secret
        P1["openssl process<br/>holds the key in memory"]:::app
        C1{{"certificate"}}:::secret
        F ==>|"read(2). Anyone who can<br/>read the file can do this"| P1
        P1 -->|"signs, using the key it holds"| C1
    end

    subgraph AFTER["From Chapter 06: the work travels"]
        direction TB
        P2["openssl process<br/>never holds the key"]:::app
        T["KEY-03 inside the token<br/>no interface returns it"]:::crypto
        C2{{"certificate"}}:::secret
        P2 -->|"1. here are the bytes to sign"| T
        T -->|"2. here is the signature"| P2
        P2 -->|"3. assembles"| C2
    end

    style BEFORE fill:#fef2f2,stroke:#b91c1c,stroke-width:1px,stroke-dasharray:4 3
    style AFTER fill:#f0fdf4,stroke:#15803d,stroke-width:2px

    classDef app fill:#e5e7eb,stroke:#6b7280,stroke-width:1px,color:#111827
    classDef crypto fill:#fee2e2,stroke:#b91c1c,stroke-width:4px,color:#450a0a
    classDef secret fill:#fef3c7,stroke:#b45309,stroke-width:2px,color:#451a03
```

**Figure 6.1, the inversion.** Read the direction of the thick edge, which is the notation's
mark for key material crossing. On the left it crosses, once per signature, into a process that
then holds it for as long as it runs. On the right there is no thick edge at all: what crosses
is a digest going in and a signature coming back, and neither is secret.

Everything else follows from that. A backup cannot capture what is not a file. A compromised
signing process yields a handle rather than bytes. An operator has nothing to attach to an
email. And the property survives the process being wrong, which no file mode has managed,
because the protection no longer depends on who is allowed to read.

### The vocabulary, kept to what this chapter uses

**PKCS#11** is the standard interface for talking to such a thing. It is a C API, and every
hardware security module, smartcard and cloud key service either speaks it or provides a shim
that does. Learning it is not learning a product.

A **token** is one keystore. A **slot** is where a token sits, and slot numbers are assigned by
the implementation, so we address tokens by **label** and never by slot.

An **object** in a token is a key, a certificate or a data blob, addressed by a label and an
ID. Objects carry **attributes**, and four of them are the whole subject of §5.

A **PIN** authorises use of the token. It is a secret, it protects a key, and if that sounds
like a problem this build has met before, it is. `OT-025`.

**SoftHSM** is a PKCS#11 token implemented in software. It enforces the API contract faithfully
and stores the token in a directory. We start here for two reasons: it is free and it is
honest. A real HSM enforces the same contract with hardware that resists physical attack, and
§9 is precisely about the gap between those two sentences.

---

## 3. Rebuild `ca01`

`ca01` gains three packages, so its image changes and the container is replaced. Every chapter
so far has warned against rebuilding. This is the one case where it is correct, and the reason
is worth stating: **everything on `ca01` is being retired anyway.** `KEY-02` is the object we
are removing from the world, and `CERT-02` is replaced in §6. There is no accumulated state on
that host worth keeping.

Note what this does **not** disturb. `dev01` and `db01` are untouched, `CERT-02` survives as
the anchor on `dev01` and as the issuer of the leaf `db01` presents, and the application keeps
serving throughout this chapter. The old chain stays valid until §8 replaces it deliberately.

`ca01/Dockerfile`:

```dockerfile
# HOST-03 ca01, the certificate authority.
#
# Compare this with db01/Dockerfile. That machine runs a database and needs
# a database's dependencies. This one signs things, so it carries openssl,
# a PKCS#11 token, and nothing else. Every package installed here is
# another way to reach the signing key.
FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

# Chapter 06 adds three packages and they are worth naming separately:
#
#   softhsm2                  the token itself, a PKCS#11 implementation in
#                             software. Honest about being software, which
#                             is exactly why we start here.
#   opensc                    gives us pkcs11-tool, the way to talk to a
#                             token directly rather than through openssl.
#   libengine-pkcs11-openssl  the bridge. Lets openssl use a key it cannot
#                             read, by asking the token to sign instead.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      openssl \
      ca-certificates \
      softhsm2 \
      opensc \
      libengine-pkcs11-openssl \
 && rm -rf /var/lib/apt/lists/*

# ACC-08. The identity that owns the token and is the only one that may use
# it. System account, no login shell, exactly as ACC-03 and ACC-04.
RUN useradd --system --home-dir /var/lib/ca --shell /usr/sbin/nologin ca \
 && usermod -aG softhsm ca

# The softhsm2 package gates /etc/softhsm and /var/lib/softhsm on the
# `softhsm` GROUP, mode 0750 and 2770, not on ownership. Chowning them to
# `ca` would fight the package and break on the next upgrade. Joining the
# group is how the platform intends this to work, and it is worth noticing
# what that means: membership of a Unix group is the access control on the
# signing key. That is OT-025.

# /var/lib/ca          CERT-04 and the record of what has been issued
# /var/lib/ca/issued   a copy of every certificate this CA has ever signed
# The token itself lives under /var/lib/softhsm/tokens, which the package
# owns and which `ca` reaches through group membership above. The PINs live
# in /var/lib/ca, which `ca` owns outright, rather than in /etc/softhsm,
# which it does not.
#
# Note what is no longer here: there is no ca.key. From Chapter 06 the
# private key is not a file this Dockerfile could create, chmod or copy.
RUN mkdir -p /var/lib/ca/issued \
 && chown -R ca:ca /var/lib/ca \
 && chmod 0700 /var/lib/ca /var/lib/ca/issued

COPY hsm-init.sh   /usr/local/bin/hsm-init
COPY sign-leaf.sh  /usr/local/bin/sign-leaf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# Pinned rather than inherited from your umask, for the same reason
# Chapter 01 pinned the modes on dev01: a file mode that depends on who
# built the image is not a file mode anyone chose.
RUN chmod 0755 /usr/local/bin/hsm-init /usr/local/bin/sign-leaf \
               /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
```

Two lines in that file are the chapter.

**`usermod -aG softhsm ca`** rather than `chown`. The `softhsm2` package gates its directories
on a group, so joining it is how the platform expects to be used, and chowning package-owned
paths would break on the next upgrade. It also tells you where the access control actually is,
and it is not where you would guess: **a Unix group now decides who may sign certificates.**
Anyone added to `softhsm` can use the key, and the token cannot tell them apart. `OT-025`.

**The absence of a `ca.key`.** There is no line creating one, no `chmod` protecting one, and no
`COPY` placing one. From this chapter the private key is not a thing a Dockerfile could
produce.

The compose file changes in one line, because an image tag names the chapter that builds it and
that is now this one. `docker-compose.yml`, in full:

```yaml
# The lab substrate: one container per "machine" in the ledger.
#
# Bring each machine up ONCE, in the chapter that introduces it, naming the
# service so you only build that one:
#     Chapter 01:  docker compose up -d --build dev01
#     Chapter 04:  docker compose up -d --build db01
#     Chapter 05:  docker compose up -d --build ca01
#     Chapter 06:  docker compose up -d --build ca01   (rebuild: ca01 gains a token)
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

    # tcpdump needs this to put an interface into the mode it wants.
    cap_add:
      - NET_ADMIN

    # Reap zombies and forward signals. The entrypoint ends in
    # `sleep infinity`, which is not a real init.
    init: true

    # Substrate only: reports, gates nothing.
    healthcheck:
      test: ["CMD", "pg_isready", "-q", "-h", "127.0.0.1", "-p", "5432"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 20s

    stop_grace_period: 5s

  db01:                                     # HOST-02, the database, added in Chapter 04
    build:
      context: ./db01
      dockerfile: Dockerfile
    image: ksm/db01:chapter04
    container_name: db01
    hostname: db01.lab.simurgh.example

    # The name the certificate is issued for, and the name APP-01 connects
    # to. Compose resolves the service name `db01` by default; this alias
    # adds the fully qualified name so `sslmode=verify-full` has something
    # to match against.
    networks:
      default:
        aliases:
          - db01.lab.simurgh.example

    # No `ports:` at all. The database is reachable from dev01 across the
    # lab network and from nowhere else. Chapter 01 published 8080 because
    # you need to curl it; nothing outside the lab has any business
    # reaching 5432.

    cap_add:
      - NET_ADMIN

    init: true

    healthcheck:
      test: ["CMD", "pg_isready", "-q", "-h", "127.0.0.1", "-p", "5432"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 20s

    stop_grace_period: 5s

  ca01:                                     # HOST-03, the certificate authority, added in Chapter 05
    build:
      context: ./ca01
      dockerfile: Dockerfile
    image: ksm/ca01:chapter06
    container_name: ca01
    hostname: ca01.lab.simurgh.example

    # No ports, and no network alias. Nothing connects to this machine.
    # An authority that answers requests is a service with an attack
    # surface and an issuance policy; this one is a key, a procedure and
    # an operator, which is all OT-017 asked for. When something needs to
    # request a certificate without a human, that is its own chapter.

    init: true

    # No healthcheck. There is no process to be healthy: the CA is files
    # on a disk and a script somebody runs. `docker compose ps` will show
    # it as running because the entrypoint sleeps, and that is the whole
    # truth about it.

    stop_grace_period: 5s
```

Build it, and name the service:

```bash
sudo docker compose up -d --build ca01
sudo docker compose ps
```

Expected: `dev01` and `db01` untouched and still running, and a fresh `ca01`.

Confirm the application is still serving, because it should be and it will keep doing so until
§8:

```bash
curl -s http://127.0.0.1:8080/payments/1001/status
```

Expected: the payment record.

---

## 4. `PROC-03`, the key ceremony

A **key ceremony** is a procedure performed once, with witnesses, whose output is a key nobody
present can produce again and nobody can copy. The word sounds grand for what is about to be
four commands, and the formality exists for a reason: this is the only moment at which the
key's properties are decided, and there is no second attempt that does not mean replacing
everything signed by the first.

Set the PINs. `SEC-04` authorises use of the key; `SEC-05` authorises administration of the
token, including resetting `SEC-04`:

```bash
sudo docker exec ca01 sh -c '
  printf "5678" > /var/lib/ca/pin
  printf "1234" > /var/lib/ca/so-pin
  chown ca:ca /var/lib/ca/pin /var/lib/ca/so-pin
  chmod 0400 /var/lib/ca/pin /var/lib/ca/so-pin'
sudo docker exec ca01 ls -l /var/lib/ca/
```

Expected: both files at `-r--------` owned by `ca`.

They are in `/var/lib/ca`, which `ca` owns, rather than in `/etc/softhsm`, which belongs to the
package and is readable only by the `softhsm` group. Put them in the wrong place and the
ceremony fails with a permission error that names the file rather than the directory above it,
which is Chapter 01 §3.1 waiting six chapters to catch you. `namei -l` is still how you find
it.

`ca01/hsm-init.sh` is the ceremony, installed as `/usr/local/bin/hsm-init`:

```bash
#!/bin/sh
# PROC-03, the key ceremony. Run once, as the `ca` user, on ca01.
#
#   hsm-init
#
# Creates the token, generates KEY-03 inside it, and proves the key cannot
# come back out. It never writes a private key to disk, because there is no
# point in the process at which one exists outside the token.
#
# Everything here is deliberately noisy. A key ceremony whose output nobody
# reads is a ceremony, in the pejorative sense.

set -eu

MODULE=/usr/lib/softhsm/libsofthsm2.so
TOKEN=ca-token
LABEL=ca-key
PIN_FILE=/var/lib/ca/pin          # SEC-04, the user PIN
SO_PIN_FILE=/var/lib/ca/so-pin    # SEC-05, the security officer PIN

[ -r "$PIN_FILE" ]    || { echo "hsm-init: cannot read $PIN_FILE. Run as the 'ca' user." >&2; exit 1; }
[ -r "$SO_PIN_FILE" ] || { echo "hsm-init: cannot read $SO_PIN_FILE." >&2; exit 1; }
PIN=$(cat "$PIN_FILE")
SO_PIN=$(cat "$SO_PIN_FILE")

echo "== 1. initialise the token =="
# --free takes the first uninitialised slot. The slot NUMBER it returns is
# assigned at random and differs on every machine, so nothing after this
# line refers to a slot. Tokens are addressed by label, always.
softhsm2-util --init-token --free --label "$TOKEN" \
              --so-pin "$SO_PIN" --pin "$PIN"

echo
echo "== 2. generate KEY-03 inside the token =="
# There is no --out. That is the whole point: the key is created in the
# token and the command has nowhere to put a copy even if it wanted one.
pkcs11-tool --module "$MODULE" --token-label "$TOKEN" --login --pin "$PIN" \
            --keypairgen --key-type EC:prime256v1 --label "$LABEL" --id 01

echo
echo "== 3. what the token says about it =="
pkcs11-tool --module "$MODULE" --token-label "$TOKEN" --login --pin "$PIN" \
            --list-objects

echo
echo "== 4. prove it cannot be extracted =="
# pkcs11-tool refuses to read a private key and STILL EXITS 0, so the exit
# status proves nothing. Check for the absence of the file instead. This is
# the same shape as Chapter 01 section 5.2: a measurement that cannot tell
# success from failure is not a measurement.
rm -f /tmp/extraction-attempt
pkcs11-tool --module "$MODULE" --token-label "$TOKEN" --login --pin "$PIN" \
            --read-object --type privkey --label "$LABEL" \
            -o /tmp/extraction-attempt 2>&1 || true
if [ -s /tmp/extraction-attempt ]; then
    echo "FAIL: something was written. The key is extractable and this token is useless." >&2
    rm -f /tmp/extraction-attempt
    exit 1
fi
rm -f /tmp/extraction-attempt
echo "OK: no key material was produced."

echo
echo "== 5. record what was created =="
date -u +"%Y-%m-%dT%H:%M:%SZ  KEY-03 generated in token $TOKEN, label $LABEL" \
    >> /var/lib/ca/ceremony.log
cat /var/lib/ca/ceremony.log
```

Run it, as `ca`:

```bash
sudo docker exec -u ca ca01 hsm-init
```

Expected: a token initialised and reassigned to some slot number, a key pair generated, the
object listing, `OK: no key material was produced.`, and a line in the ceremony log.

Your slot number will not match anything printed in this chapter, and nothing depends on it.

---

## 5. What the token says, and the check that lies

Step 2 of the ceremony printed four words that are the whole of `OT-021`'s answer:

```
Private Key Object; EC
  label:      ca-key
  Usage:      decrypt, sign, unwrap, derive
  Access:     sensitive, always sensitive, never extractable, local
```

Each is a separate claim and it is worth taking them one at a time.

**`sensitive`** means the token will not reveal the value through the API. This is the one
people mean when they say a key is "in an HSM".

**`always sensitive`** means it has never been otherwise, for the whole life of the object. A
key that was briefly readable and then marked sensitive would say `false` here, and would be
worth nothing, because the moment it was readable is the moment it may have been read.

**`never extractable`** closes the other door. `sensitive` stops you reading the value; this
stops you *wrapping* it, which is the legitimate mechanism for moving a key from one token to
another under encryption. A key that is extractable can be exported to a token you control and
read there.

**`local`** means the key was generated **inside this token** rather than imported into it.
This is the closest thing to attestation available here, and it is why §3 could not simply load
`KEY-02` into the token and carry on. An imported key would report `local: false`, and every
promise in this chapter would be about a key that had already spent a year as a file on a
container. **You cannot retrofit provenance.**

### Try to steal it, the way §1 did

The point of the whole chapter is that §1 is now impossible. Test it, first through the API:

```bash
sudo docker exec -u ca ca01 sh -c '
  pkcs11-tool --module /usr/lib/softhsm/libsofthsm2.so --token-label ca-token \
              --login --pin "$(cat /var/lib/ca/pin)" \
              --read-object --type privkey --label ca-key -o /tmp/stolen.key
  echo "exit=$?"
  ls -l /tmp/stolen.key 2>&1'
```

Expected: `sorry, reading private keys not (yet) supported`, then **`exit=0`**, then
`No such file or directory`.

**Read those three lines together, because the middle one is a trap.** The tool refused and
reported success. A verification written the obvious way,

```
pkcs11-tool ... --read-object ... && echo "extraction refused"
```

prints `extraction refused` whether the key was extracted or not. It is a check that cannot
fail, guarding the one property this chapter exists to establish. Chapter 01 §5.2 had the
identical shape: `grep -c` returning `0` meant either "the password is not in the capture" or
"the capture is empty", and those are opposite conclusions from identical output.

That is why `hsm-init` tests for the **absence of the output file** and never looks at the exit
status. When you are checking that something failed, check for the artifact, not the return
code.

And the direct route, as root, the one that worked in §1:

```bash
sudo docker exec ca01 ls -l /var/lib/ca/ca.key
```

Expected: `No such file or directory`. There is no file to copy. `KEY-02` does not exist on
this machine and `KEY-03` never took that form.

---

## 6. `CERT-04`, a root signed by a key that is not there

The authority needs a self-signed root certificate, and signing it requires the private key.
`openssl` does not have the private key and cannot be given it. It gets the signature instead:

```bash
sudo docker exec -u ca ca01 sh -c '
  openssl req -new -x509 -days 3650 -sha256 \
    -engine pkcs11 -keyform engine \
    -key "pkcs11:token=ca-token;object=ca-key;type=private?pin-value=$(cat /var/lib/ca/pin)" \
    -subj "/CN=Simurgh Lab Root CA" \
    -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -out /var/lib/ca/ca.crt'
sudo docker exec ca01 openssl x509 -in /var/lib/ca/ca.crt -noout \
    -subject -issuer -dates -ext basicConstraints,keyUsage
```

Expected: `Engine "pkcs11" set.` on stderr, then subject and issuer both
`CN = Simurgh Lab Root CA`, ten years of validity, `CA:TRUE, pathlen:0` marked critical, and
`Certificate Sign, CRL Sign`.

That is `CERT-04`. Three things in the command carry weight.

**`-engine pkcs11 -keyform engine`** tells `openssl` that what follows the `-key` flag is not a
file to read but a key to *use*. The bridge package installed in §3 turns each signing
operation into a call into the token.

**The `pkcs11:` URI must be quoted.** It contains `;` and `?`, and an unquoted one is
dismembered by the shell into something unrecognisable. It names the token by label, the object
by label, and supplies the PIN.

**`pin-value=` on a command line is a lab convenience and nothing more.** Chapter 01 §3.3
showed that `/proc/<pid>/cmdline` is world-readable, so for the life of that `openssl` process
the PIN is visible to every account on the host. It is on one line in this chapter so that you
can see the whole operation at once; `sign-leaf` reads it from a `0400` file, and §12 explains
why even that is not enough.

---

## 7. `sign-leaf`, without a key

`ca01/sign-leaf.sh` changes in exactly one respect, and reading the diff is the fastest way to
see what this chapter did:

```bash
#!/bin/sh
# PROC-02, the issuing half. Signs a certificate request with KEY-03.
#
#   sign-leaf <csr-file> <fqdn> [additional-dns-name ...]
#
# Chapter 06 changed one thing and it is the only thing worth noticing:
# there is no CA_KEY variable any more. The key is not a file this script
# could read, so it does not read one. It hands the request to the token
# and the token hands back a signature.
#
# What this script exists to prevent is still the failure in Chapter 05
# section 6: a certificate signed with a Subject Alternative Name that does
# not contain the name the client actually dials. The Common Name is not
# consulted when a SAN is present, so a leaf whose CN is perfect and whose
# SAN is wrong is rejected, and the error says nothing about the CN.

set -eu

CA_DIR=/var/lib/ca
CA_CRT="$CA_DIR/ca.crt"          # CERT-04, public, an ordinary file
ISSUED="$CA_DIR/issued"
DAYS=90                          # leaves are short-lived; the root is not

MODULE=/usr/lib/softhsm/libsofthsm2.so
TOKEN=ca-token
LABEL=ca-key
PIN_FILE=/var/lib/ca/pin        # SEC-04

if [ $# -lt 2 ]; then
    echo "usage: sign-leaf <csr-file> <fqdn> [additional-dns-name ...]" >&2
    exit 2
fi

CSR="$1"; FQDN="$2"; shift 2

[ -r "$CSR" ]      || { echo "sign-leaf: cannot read CSR: $CSR" >&2; exit 1; }
[ -r "$CA_CRT" ]   || { echo "sign-leaf: cannot read CERT-04: $CA_CRT" >&2; exit 1; }
[ -r "$PIN_FILE" ] || { echo "sign-leaf: cannot read the PIN. Run as the 'ca' user." >&2; exit 1; }
PIN=$(cat "$PIN_FILE")

# The token is addressed by label, never by slot: SoftHSM assigns slot
# numbers at random on every init, so a hard-coded slot works once, on one
# machine. The URI must be quoted or the shell eats the ; and the ?.
KEY_URI="pkcs11:token=$TOKEN;object=$LABEL;type=private?pin-value=$PIN"

# The FQDN is always the first SAN entry. Extra names are appended, which is
# how db01 keeps answering to the short name compose gives it as well as to
# the name the ledger assigned it.
SAN="DNS:$FQDN"
for name in "$@"; do
    SAN="$SAN,DNS:$name"
done

EXT=$(mktemp)
trap 'rm -f "$EXT"' EXIT
cat > "$EXT" <<EOF
subjectAltName=$SAN
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
EOF

OUT="$ISSUED/$FQDN.crt"

# -CAkeyform engine is what redirects the signature into the token. The
# private key never enters this process; openssl sends the bytes to be
# signed and gets a signature back.
openssl x509 -req \
    -in "$CSR" \
    -CA "$CA_CRT" \
    -engine pkcs11 -CAkeyform engine -CAkey "$KEY_URI" \
    -CAcreateserial \
    -days "$DAYS" -sha256 \
    -extfile "$EXT" \
    -out "$OUT" 2>/dev/null

chmod 0644 "$OUT"

# Print what was actually produced rather than reporting success. The SAN is
# the field that decides whether any client will accept this certificate, so
# it is the field the operator has to see.
echo "issued: $OUT"
openssl x509 -in "$OUT" -noout -serial -subject -dates
openssl x509 -in "$OUT" -noout -ext subjectAltName
```

`CA_KEY` is gone. `-CAkeyform engine` took its place, and everything else in the script, the
SAN handling, the extensions, the record in `issued/`, is exactly as Chapter 05 left it. A tool
that signs with an unreadable key looks almost identical to one that signs with a file, which
is the practical argument for PKCS#11: the interface is the same shape, so the migration is one
line.

`db01` still has `KEY-01` and the CSR it made in Chapter 05. Issue it a leaf under the new
root:

```bash
sudo docker exec db01 sh -c '
  openssl req -new -key /etc/postgresql/15/main/server.key \
    -out /tmp/db01.csr -subj "/CN=db01.lab.simurgh.example"'
sudo docker cp db01:/tmp/db01.csr /tmp/db01.csr
sudo docker cp /tmp/db01.csr ca01:/tmp/db01.csr
sudo docker exec ca01 chown ca:ca /tmp/db01.csr
sudo docker exec -u ca ca01 sign-leaf /tmp/db01.csr db01.lab.simurgh.example db01
```

Expected: `issued: /var/lib/ca/issued/db01.lab.simurgh.example.crt`, a serial, ninety days, and
`DNS:db01.lab.simurgh.example, DNS:db01`.

Nothing about that output tells you the signature came from a token, and nothing should. A
certificate is a certificate. Where the signing key lives is a property of the issuer's
operation, not of the artifact.

---

## 8. Two roots at once

`db01` is still presenting the old leaf and `dev01` still trusts `CERT-02`. Install the new
leaf and clients break; swap the anchor first and clients break. Two systems must agree,
nothing spans them, and by now that sentence should be familiar: it is Chapter 02 §2 and
Chapter 05 §1 in a third costume.

It also has the same answer. Chapter 02 solved it by having **two credentials valid at once**.
A trust anchor is a *bundle*, so a client can trust two roots at once, and the migration
acquires an overlap in exactly the same way.

```mermaid
flowchart TB
    subgraph S1["Start: one root, old leaf"]
        direction LR
        A1["anchor on dev01<br/>CERT-02"]:::secret
        L1["db01 presents<br/>leaf under CERT-02"]:::secret
        A1 -->|"verifies"| L1
    end
    subgraph S2["★ Step 1: trust both. Nothing has moved"]
        direction LR
        A2["anchor on dev01<br/>CERT-02 + CERT-04"]:::best
        L2["db01 presents<br/>leaf under CERT-02"]:::secret
        A2 -->|"verifies"| L2
    end
    subgraph S3["★ Step 2: move the server. Both still verify"]
        direction LR
        A3["anchor on dev01<br/>CERT-02 + CERT-04"]:::best
        L3["db01 presents<br/>leaf under CERT-04"]:::secret
        A3 -->|"verifies"| L3
    end
    subgraph S4["★ Step 3: drop the old root"]
        direction LR
        A4["anchor on dev01<br/>CERT-04"]:::secret
        L4["db01 presents<br/>leaf under CERT-04"]:::secret
        A4 -->|"verifies"| L4
    end

    S1 --> S2 --> S3 --> S4

    style S1 fill:#f8fafc,stroke:#475569,stroke-width:1px
    style S2 fill:#f0fdf4,stroke:#15803d,stroke-width:2px
    style S3 fill:#f0fdf4,stroke:#15803d,stroke-width:2px
    style S4 fill:#f8fafc,stroke:#475569,stroke-width:1px

    classDef secret fill:#fef3c7,stroke:#b45309,stroke-width:2px,color:#451a03
    classDef best fill:#dcfce7,stroke:#15803d,stroke-width:3px,color:#052e16
```

**Figure 6.2, why there is no window.** Every row verifies, and that is the whole claim. Check
it against the alternative: delete the two green rows, go straight from the first to the last,
and there is a moment when the anchor names one root while the server presents a leaf from
another. Every reconnect in that moment fails.

The green anchors are the overlap. While two roots are trusted, **both** chains are acceptable,
so the server can move at a time of its choosing rather than at the same instant as the client.
Compare Chapter 05 §1, where the anchor *was* the server's certificate: those two states were
mutually exclusive, so no such row existed and no ordering avoided the outage.

**Step 1, trust both.** Append `CERT-04` to the anchor without removing `CERT-02`:

```bash
sudo docker cp ca01:/var/lib/ca/ca.crt /tmp/ca-new.crt
sudo docker exec dev01 cp /opt/paymentsvc/ca.crt /tmp/ca-old.crt
sudo docker cp /tmp/ca-new.crt dev01:/tmp/ca-new.crt
sudo docker exec dev01 sh -c 'cat /tmp/ca-old.crt /tmp/ca-new.crt > /opt/paymentsvc/ca.crt'
sudo docker exec dev01 chmod 0444 /opt/paymentsvc/ca.crt
sudo docker exec dev01 grep -c 'BEGIN CERTIFICATE' /opt/paymentsvc/ca.crt
```

Expected: `2`.

Nothing has broken, because nothing has moved. Confirm the application is still serving on the
old chain:

```bash
curl -s http://127.0.0.1:8080/payments/1001/status
```

Expected: the payment record.

**Step 2, move the server.** Now `db01` can switch, because the client already trusts what it
is about to present:

```bash
sudo docker cp ca01:/var/lib/ca/issued/db01.lab.simurgh.example.crt /tmp/db01-new.crt
sudo docker cp /tmp/db01-new.crt db01:/etc/postgresql/15/main/server.crt
sudo docker exec db01 sh -c '
  chown postgres:postgres /etc/postgresql/15/main/server.crt
  chmod 0644 /etc/postgresql/15/main/server.crt'
sudo docker exec db01 pg_ctlcluster 15 main restart
sudo docker exec dev01 pkill -f paymentsvc.py || true
sleep 1
sudo docker exec -d -u paymentsvc dev01 \
    sh -c 'python3 /opt/paymentsvc/paymentsvc.py >>/var/log/paymentsvc.out 2>&1'
sleep 3
curl -s http://127.0.0.1:8080/payments/1001/status
```

Expected: the payment record. The client verified a certificate from an authority it had never
seen until step 1, and neither the config file nor `sslmode` changed.

**Step 3, drop the old root.** The overlap has served its purpose, and leaving it means
continuing to trust an authority whose key is on your laptop from §1:

```bash
sudo docker exec dev01 sh -c 'cat /tmp/ca-new.crt > /opt/paymentsvc/ca.crt'
sudo docker exec dev01 chmod 0444 /opt/paymentsvc/ca.crt
sudo docker exec dev01 grep -c 'BEGIN CERTIFICATE' /opt/paymentsvc/ca.crt
sudo docker exec dev01 pkill -f paymentsvc.py || true
sleep 1
sudo docker exec -d -u paymentsvc dev01 \
    sh -c 'python3 /opt/paymentsvc/paymentsvc.py >>/var/log/paymentsvc.out 2>&1'
sleep 3
curl -s http://127.0.0.1:8080/payments/1001/status
```

Expected: `1`, then the payment record.

**Step 4, confirm the forgery is dead.** The certificate you made in §1 was signed by
`CERT-02`, which nothing trusts any more. If you kept a copy, it now fails; and the general
check is that the old root no longer verifies anything:

```bash
sudo docker exec dev01 openssl verify -CAfile /opt/paymentsvc/ca.crt /tmp/ca-old.crt
```

Expected: a verification failure. `CERT-02` is not trusted by this client and neither is
anything it signed.

**Count what that migration cost.** Three writes, none of which broke a running service, and no
window in which a correct client could fail. Compare Chapter 05 §1, where re-issuing a *pinned*
certificate broke the client immediately and no ordering avoided it. The difference is that a
client can hold two anchors and cannot hold two opinions about one pinned certificate. Overlap
is the same answer this build reached for credentials in Chapter 02, and it works here for the
same reason: **make the disagreement harmless rather than trying to make it brief.**

Retire the old objects in the ledger's sense, which is to make them useless rather than to
chase them:

```bash
rm -f /tmp/ca-new.crt /tmp/db01-new.crt /tmp/db01.csr
sudo docker exec dev01 rm -f /tmp/ca-old.crt /tmp/ca-new.crt
```

---

## 9. What this bought, and the attacker it does not stop

Repeat §1 exactly. Become root on `ca01` and take the key:

```bash
sudo docker exec ca01 ls -l /var/lib/ca/ca.key
sudo docker exec ca01 find /var/lib/ca -name '*.key'
```

Expected: nothing. There is no key file on the machine.

So try the token instead:

```bash
sudo docker exec ca01 find /var/lib/softhsm -type f
```

Expected: a directory named for a UUID, containing `.object` files, a `generation` file and
some locks.

**Copy them.** All of them:

```bash
sudo docker exec ca01 tar -cf /tmp/token.tar -C /var/lib/softhsm tokens
sudo docker exec ca01 ls -l /tmp/token.tar
```

Expected: a tar file of a few tens of kilobytes.

That archive contains the token, and the token contains `KEY-03`. Restore it into another
SoftHSM on a machine you control, supply the PIN, and you can sign. The API refused to hand
over the key and the filesystem handed over the box it lives in.

**So state precisely what changed, because it is real and it is narrower than it looks.**

| Attack | Chapter 05 | Now |
|---|---|---|
| A backup of `/var/lib` captures the key | Yes | **Yes**, the token is in there |
| Root on `ca01` copies it | Two `cat` commands | A `tar` and a PIN |
| A signing script leaks it by accident | Yes, it reads the key | **No**, there is no read |
| A `docker cp` or shell history exposes it | Yes | **No** |
| A compromised process using the key steals it | Yes, it holds the bytes | **No**, it holds a handle |
| An operator emails it to a colleague | Yes | **No**, there is nothing to attach |

Five of six closed. The class this chapter eliminates is **accidental disclosure and disclosure
through the legitimate path**, which is most of how key material actually escapes, and Chapter
01 spent sixteen locations proving that. What remains is a determined attacker with root on the
host, who now needs the token *and* the PIN, and who leaves a `tar` in the shell history rather
than a `cat`.

**Why a real HSM is different, in one sentence.** SoftHSM is a library reading files that root
can read; a hardware module is a separate device that performs the operation and has no
interface, physical or logical, that emits the key, so the equivalent attack requires
possession of the device and defeats its tamper response. This chapter buys the API contract.
It does not buy the boundary, and calling it an HSM would be the first dishonest thing in this
book. `OT-026`.

---

## 10. What just changed in the architecture

```mermaid
flowchart LR
    subgraph LAB["NET-01 lab, one flat network: OT-024"]
        direction TB

        subgraph H1["HOST-01 dev01"]
            APP["APP-01 paymentsvc<br/>sslmode=verify-full"]:::app
            STORE("SVC-02 secretstore"):::control
            ANCH{{"★ CERT-04 copy<br/>/opt/paymentsvc/ca.crt 0444"}}:::secret
        end

        subgraph H3["HOST-03 ca01"]
            TOK["★ KEY-03 in PKCS#11 token<br/>sensitive, never extractable, local<br/>no interface returns it"]:::crypto
            CAC{{"★ CERT-04 root<br/>self-signed by the token, 10 years"}}:::secret
            PIN{{"★ SEC-04 PIN 0400<br/>and the softhsm group"}}:::secret
            OLD["✕ KEY-02 ca.key<br/>gone, and its root with it"]:::retired
        end

        subgraph H2["HOST-02 db01"]
            DB[("SVC-01 paymentsdb")]:::store
            K1["KEY-01 server.key 0600"]:::crypto
            C3{{"★ CERT-03 re-issued<br/>under CERT-04, 90 days"}}:::secret
        end
    end

    ROOT(["ACC-01 root on ca01"]):::human

    TOK ==>|"★ signs. The key does not move"| CAC
    TOK ==>|"★ signs"| C3
    CAC -.->|"copied once, by hand"| ANCH
    K1 -.->|"CSR, public"| CAC
    APP -->|"SCRAM over TLS, verified against CERT-04"| DB
    C3 -.->|"presented"| DB
    PIN -.->|"authorises use"| TOK
    ROOT -.->|"★ cannot read the key, CAN tar the token: OT-026"| TOK

    style LAB fill:#f8fafc,stroke:#475569,stroke-width:1px,stroke-dasharray:6 3
    style H1 fill:#ffffff,stroke:#475569,stroke-width:1px
    style H2 fill:#ffffff,stroke:#475569,stroke-width:1px
    style H3 fill:#fff7ed,stroke:#b45309,stroke-width:2px,stroke-dasharray:6 3

    classDef human fill:#ffffff,stroke:#4b5563,stroke-width:2px,stroke-dasharray:4 3,color:#111827
    classDef app fill:#e5e7eb,stroke:#6b7280,stroke-width:1px,color:#111827
    classDef control fill:#dbeafe,stroke:#1d4ed8,stroke-width:2px,color:#0b1f4b
    classDef crypto fill:#fee2e2,stroke:#b91c1c,stroke-width:4px,color:#450a0a
    classDef store fill:#e2e8f0,stroke:#475569,stroke-width:1px,color:#0f172a
    classDef secret fill:#fef3c7,stroke:#b45309,stroke-width:2px,color:#451a03
    classDef retired fill:#f8fafc,stroke:#cbd5e1,stroke-width:1px,stroke-dasharray:2 4,color:#94a3b8
```

**Figure 6.3, the architecture after Chapter 06.** `KEY-03` is drawn as a heavy red double-
barred node, and this is the first time in six chapters that the shape has been used. Chapter
00 reserved it for key material that is created and used inside a boundary and cannot be
extracted, and said we would spend a long time earning it.

**Read the qualification next to it.** The node earns the shape on the strength of what the API
does, and the edge from `ACC-01` says what the shape does not cover: root cannot read the key
and can copy the token whole. A notation that let us draw the same box for SoftHSM and for a
hardware module would be a notation that had stopped carrying information, which is why the
edge is drawn rather than left to the prose.

**`KEY-01` is still an ordinary red node.** It sits in a file on `db01`, exactly as Chapter 04
left it, and the difference between the two shapes in one figure is the difference this chapter
is about. Nothing has been done for the database's key, which is `OT-027`.

**The lab zone is now dashed.** Every machine here reaches every other, including the one
holding the signing token, and that has been true since Chapter 04 without being drawn.
`OT-024`.

### Current one-line state

Three machines; the authority signs with a key that has no file, no export path and no
interface that returns it, generated in place and proven `never extractable`; clients were
migrated onto its root with three writes and no outage; and root on that host can still carry
the whole token away in a tar file.

---

## 11. Decisions we made (and what would change them)

| # | Decision | Options | Chosen | Why | What would flip it |
|---|---|---|---|---|---|
| D-049 | SoftHSM now, hardware later | (a) buy or emulate a hardware HSM; (b) a cloud KMS; (c) SoftHSM, a software PKCS#11 token | (c) | The lesson is the **interface** and the property, not the device. PKCS#11 is the same API for a smartcard, an appliance and a cloud service, so what you learn here transfers to all of them. (a) cannot run in a container on a laptop. (b) moves the key to somebody else's computer, which is a real answer and a different chapter, and it would teach an API owned by one vendor. SoftHSM is also honest: it never claims to resist an attacker with root. | A chapter whose subject is the hardware boundary itself, tamper response, or key custody across an organisation. That needs the real thing, or a convincing account of why the simulation is enough. |
| D-050 | Generate a new key rather than import `KEY-02` | (a) import the existing key into the token and keep `CERT-02`; (b) generate `KEY-03` in the token and re-root the estate | (b) | Measured: a generated key reports `local` and `always sensitive`; an imported one cannot. Importing would mean claiming a property about a key that spent a year as a file on a container, which is a claim we would have no basis for. **Provenance cannot be retrofitted.** The cost is a new root and a client migration, which §8 shows is three writes and no outage while the estate is this size. | Nothing. The alternative is a weaker claim dressed as the same one. |
| D-051 | Address tokens by label, never by slot | (a) use the slot number the init prints; (b) `--token-label` everywhere | (b) | Measured across two runs: SoftHSM assigned slot `1492972387` and then `1152029365` for the same operation. A slot number is valid on one machine until the next initialisation. A chapter that printed one would fail on every reader's machine. | Nothing. |
| D-052 | The OpenSSL **engine**, not the provider | (a) `pkcs11-provider`, the OpenSSL 3 mechanism; (b) `libengine-pkcs11-openssl`, the older engine API | (b) | The provider is the modern interface and is not packaged in Debian 12, which is the platform this build runs on. Engines are deprecated in OpenSSL 3 and work, measured in both `req -x509` and `x509 -req`. Choosing the packaged thing over the fashionable thing is usually right when both work. | A base image whose OpenSSL ships `pkcs11-provider`. The migration is a flag change, not a redesign, which is the argument for PKCS#11 in the first place. |
| D-053 | Join the `softhsm` group rather than chown the package's directories | (a) `chown -R ca /var/lib/softhsm`; (b) `usermod -aG softhsm ca` | (b) | The package ships `/etc/softhsm` at `0750 root:softhsm` and the token store at `2770 root:softhsm`, so group membership is the access model it was designed around. Chowning fights the package manager and reverts on upgrade. It also surfaces the real control, which is worth seeing: a Unix group decides who may sign. | A deployment where the token store belongs to one service and nothing else, where a dedicated user is cleaner. Then own it outright, and record that the group no longer means anything. |

---

## 12. Where this still hurts

**Root on `ca01` copies the token, and the PIN with it.** The API refuses to export `KEY-03`
and the filesystem hands over the directory it lives in. `SEC-04` is a `0400` file on the same
host, so an attacker who takes one takes both. This is the honest limit of a software token,
and the distance between it and a hardware module is the distance between an API contract and a
physical boundary. `OT-026`.

**A Unix group is the access control on the signing key.** Anyone in `softhsm` can use the
token, and the token cannot distinguish them: it authenticates a PIN, not a person. `POL-01`
taught the store to ask the kernel who was calling; the CA asks nothing and logs nothing.
`OT-025`.

**Nothing is recorded when the key is used.** `SVC-02` writes an audit line for every secret it
serves. The authority signs certificates and writes only the certificate. There is no record of
who invoked `sign-leaf`, when, or for what name, beyond the artifact in `issued/`.

**One person can sign anything.** A real key ceremony splits authority so that no single human
can use the key alone: `m` of `n` custodians, split PINs, separate roles for the security
officer and the operator. `SEC-05` exists and is a second file next to the first, owned by the
same account, so the separation is nominal. `OT-027`.

**Everything on `NET-01` can reach `ca01`.** The lab has been one flat network since Chapter
04, and it now contains a machine holding a signing token. Nothing prevents `dev01`, `db01` or
a future host from opening a connection to it. Today the CA listens on nothing, so this is
potential rather than actual, and the moment anything on it accepts a request that stops being
true. `OT-024`.

**Nothing decides who may be issued a certificate.** Unchanged from Chapter 05. `sign-leaf`
signs what it is handed, and the control is that a human runs it. `OT-023`.

**Nothing can be revoked.** Unchanged, and §1 gave it a face: a forged certificate for
`vault01.lab.simurgh.example`, valid ninety days, that this chapter defeated only by destroying
the authority that signed it. That is not revocation, it is amputation. `OT-022`.

**Nothing tracks expiry**, and there is now a ten-year root whose replacement will be harder
than this one, because next time the old key will be in a token you cannot copy forward.
`OT-018`.

**Root reads everything, on three hosts.** `OT-004`, unchanged in character, and now including
a token archive.

---

## 13. Chapter recap

- A file mode cannot protect a key from root. Chapter 01 established that for a config file and
  §1 measured it for a certificate authority: two `cat` commands and a forged certificate for a
  host that does not exist.
- The only remaining move is to stop the key being readable at all, by anyone, and make the
  operation happen where the key is. **The operation travels to the key, not the key to the
  operation.**
- PKCS#11 is the standard interface for that, and it is the same interface for a smartcard, an
  appliance and a cloud service. What you learn here is not a product.
- A key generated in a token reports `sensitive, always sensitive, never extractable, local`,
  and each word is a separate claim. `local` is provenance, and it is why an existing key
  cannot be imported and described the same way. **Provenance cannot be retrofitted.**
- `pkcs11-tool` refuses to export a private key **and exits 0**. When you verify that something
  failed, check for the artifact, never the return code.
- Slot numbers are assigned at random on every initialisation. Address tokens by label.
- `openssl` signs with a key it is never given: `-engine pkcs11 -keyform engine` for a self-
  signed root, `-CAkeyform engine` for someone else's request. The tool looks almost
  unchanged, which is the practical case for a standard interface.
- A trust anchor is a bundle, so a client can trust two roots at once. Migrating to a new
  root is therefore three writes with no window, which is Chapter 02's overlap answer
  arriving in a third costume: **make the disagreement harmless rather than brief.**
- A software token buys the API contract and not the boundary. It closes accidental disclosure,
  disclosure through the legitimate path, backups of a key file, shell history and a compromised
  signing process. It does not stop root taking a tar of the token.
- Calling that an HSM would be the first dishonest sentence in this book. The heavy red node in
  Figure 6.1 is drawn with the edge that says what it does not cover.

---

## 14. Prove it to yourself

**Q1. §1 took two commands and produced a certificate for a host that does not exist. Which of
this build's existing controls should have stopped it, and why did none of them?**

None of them could, and that is the point. `POL-01` governs the secret store, not the CA. The
`0600` mode on `ca.key` grants read to its owner and root is the kernel's documented exception
to mode checks, which Chapter 01 §8 established and Chapter 03 §6.3 repeated when the store
refused root at the socket while root read the backing file directly. Every control this build
had was a rule about **who may open a file**, and the attacker in §1 is the one identity all of
them exempt. That is why the answer had to change category rather than get stricter.

**Q2. Why could `KEY-02` not simply be imported into the token?**

Because the token would report it as `local: false`, and every claim built on it would be a
claim about a key that had already existed as a file for a year, readable by root, present in
any backup of that host, and possibly copied. `sensitive` and `never extractable` would
describe its future and say nothing about its past. The four attributes are only worth reading
together, and `local` is the one that makes the other three mean anything. Provenance is a
property of a key's whole life, and the only way to have it is to generate the key where it
will live.

**Q3. `pkcs11-tool --read-object --type privkey` printed a refusal and exited 0. Write the
verification correctly, and name the earlier chapter that made the same mistake.**

Check for the absence of the output file, not the exit status: run the command, then test
whether anything was written, and fail if it was. `hsm-init` does exactly that. The identical
shape is Chapter 01 §5.2, where `grep -c` over a packet capture returning `0` meant either "the
password is not in this capture" or "this capture is empty", two opposite conclusions from one
output, which is why that section counts packets first. The general rule is that a measurement
which produces the same result whether or not the thing under test worked has measured nothing.

**Q4. `openssl` signed a certificate without ever holding the private key. Describe what
actually crossed the boundary.**

The bytes to be signed went in and a signature came back. `openssl` prepared the certificate
structure, hashed it, and handed the digest to the engine; the engine passed it through PKCS#11
to the token; the token performed the ECDSA operation internally using a key it will not
release, and returned the signature; `openssl` assembled the certificate around it. At no point
did the process address space contain the private key. That inversion is the entire idea, and
it is why the property survives a compromise of the signing process, which would previously
have found the key in memory.

**Q5. Migrating to a new root took three writes and no outage, while Chapter 05 §1 showed a
certificate change breaking the client immediately. What is different?**

A client can trust two roots at the same time, because `sslrootcert` is a bundle, and it cannot
hold two opinions about a single pinned certificate. So the migration gains an overlap: trust
both roots, move the server, drop the old root. During the middle step both chains verify and
no correct client can fail. Chapter 05 §1 had no overlap available because the anchor *was* the
server's certificate, so the two states were mutually exclusive. This is the same answer
Chapter 02 reached for credentials, where two login roles were valid at once, and it is the
same underlying move: when two systems must disagree for a while, make the disagreement
harmless instead of trying to make it short.

**Q6. §9 copied the token with `tar` after the API refused to export the key. Has the chapter
achieved anything?**

Yes, and it is worth being precise rather than either overselling or dismissing it. Six ways a
key escapes were listed and five are closed: a signing script cannot leak what it never reads,
a `docker cp` has nothing to copy, an operator cannot attach it to an email, a compromised
process holds a handle rather than bytes, and a backup of the key file cannot capture a file
that does not exist. What survives is an attacker with root on that host, who now needs the
token archive and the PIN, and who leaves a different trace. Chapter 01 found sixteen locations
for one password and almost all of them were accidental rather than adversarial. This chapter
closes the accidental class, which is where key material actually goes.

**Q7. What would a hardware module add, stated as a property rather than as a product?**

That the operation is performed by a device with no interface, logical or physical, that emits
the key, and that attempts to reach it physically destroy it. SoftHSM enforces the same API
contract in software, so an attacker who cannot use the API can still read the files the
library reads. Hardware moves the boundary from "the library will not tell you" to "the silicon
cannot be made to tell you", which is why the equivalent attack requires possession of the
device rather than root on a host. Note what does not change: the PIN is still a secret, one
person with it can still sign, and nothing is recorded. Hardware answers exactly one of this
chapter's four remaining threads.

**Q8. The token authenticates a PIN. What can the audit trail therefore never tell you?**

Who signed. A PIN is a bearer credential, which is the distinction Chapter 03 §2 drew: it
identifies knowledge of a string rather than a principal, so anyone holding it is
indistinguishable from anyone else holding it. Since `SEC-04` sits in a file readable by an
account, and membership of the `softhsm` group determines who can reach the token at all, the
honest description of the authority's access control is "a Unix group and a shared secret".
Chapter 03 solved this for the secret store by asking the kernel for the caller's identity, and
nothing equivalent has been done here, which is `OT-025`.

**Q9. Figure 6.1 draws `KEY-03` with the heavy red double-barred shape and `KEY-01` without it.
Justify the difference, and justify the edge drawn from `ACC-01` to the token.**

`KEY-03` was generated inside a boundary and has no export path, which is the definition
Chapter 00 attached to that shape. `KEY-01` is a file on `db01` protected by mode `0600`, which
is the same arrangement this chapter just demonstrated is inadequate for a key that matters, so
it keeps the ordinary shape and stands as an open question. The edge from root exists because
the notation would otherwise say that SoftHSM and a hardware module are the same thing. They
differ in exactly one respect and it is the respect the shape is about, so the figure states
the exception rather than letting the shape overclaim.

**Q10. Ten years from now `CERT-04` expires. Why is that renewal harder than the one in §8, and
what should have been done about it today?**

In §8 the old key was a file, so the old root could keep signing while the new one was
introduced, and the overlap was free. `KEY-03` cannot be copied to a second machine, so the
next root transition needs a second token, and the two must be operated together during the
overlap. More awkwardly, a token that has been running for ten years is a token whose PIN has
been known to several generations of staff. The thing that should have been done today is the
thing every real PKI does and this build has not: issue an **intermediate** from the root, keep
the root offline, and let the intermediate do the signing, so that routine replacement never
touches the root at all. `D-045` in Chapter 05 recorded that deviation deliberately, and this
is the bill for it arriving.

---

## 15. Leaving the lab standing

**Leave it running.** Chapter 07 builds on this.

Three machines and three processes, in order:

```bash
sudo docker start db01 ca01 dev01
sudo docker exec dev01 sh -c '
  for i in $(seq 1 30); do pg_isready -q -h 127.0.0.1 -p 5432 && break; sleep 1; done
  pg_ctlcluster 15 main stop'
sudo docker exec -d -u secretstore dev01 \
    sh -c 'python3 /opt/secretstore/secretstore.py >>/var/log/secretstore.out 2>&1'
sleep 1
sudo docker exec -d -u paymentsvc dev01 \
    sh -c 'python3 /opt/paymentsvc/paymentsvc.py >>/var/log/paymentsvc.out 2>&1'
sleep 3
curl -s http://127.0.0.1:8080/healthz
curl -s http://127.0.0.1:8080/credinfo
```

Expected: `{"status": "ok"}`, then `"sslmode": "verify-full"`.

**The token survives a container restart and the ceremony is not repeated.** `hsm-init` is a
once-only operation, and running it again would initialise a second token, generate a second
key and leave you signing with something no client trusts. If you need to check the token is
still there:

```bash
sudo docker exec -u ca ca01 sh -c '
  pkcs11-tool --module /usr/lib/softhsm/libsofthsm2.so --token-label ca-token \
              --login --pin "$(cat /var/lib/ca/pin)" --list-objects | head -4'
```

Expected: the private key object, with its four attributes.

Five failure modes that look alike from outside:

- `URLError` or `Connection refused` in `paymentsvc.out`: the **secret store** is not running.
- `PermissionError ... POL-01 does not permit`: the store refused the app, which means it was
  started without `-u paymentsvc`.
- `certificate verify failed`: the anchor on `dev01` and the certificate `db01` presents
  disagree. After this chapter the anchor should hold exactly one certificate, `CERT-04`.
- `does not match host name`: the certificate is trusted and was issued for the wrong name,
  which is Chapter 05 §6.
- `Failed to enumerate slots` from anything on `ca01`: the token is missing or the account is
  not in the `softhsm` group. Check with `id ca`.

Nothing from this chapter is transient. The token, `CERT-04` and the ceremony log are standing
infrastructure.

**Full teardown**, only if you are abandoning the build:

```bash
sudo docker compose down
sudo docker rmi ksm/dev01:chapter01 ksm/db01:chapter04 ksm/ca01:chapter06
```
