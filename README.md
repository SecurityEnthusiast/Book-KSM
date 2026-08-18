# Key and Secret Management: built, not described
<img src="assets/cover.png.png" alt="Book Cover" width="500" height="750">


You learn this subject by building one system, from a password in a config file on a single
laptop to a hybrid, multi-cloud, multi-tenant platform, and never skipping a wire.

> **There is exactly one system. It is never restarted. Every chapter it grows by exactly as
> much as the next real problem requires, no more, no less.**

That rule is the whole method. There is no chapter called "Introduction to Public Key
Infrastructure". There is a chapter where two services must talk without a third party reading
or impersonating the conversation, and certificates appear because that is the thing that
solves it. Several chapters later, enough certificates have accumulated that renewing them by
hand has already burned us once, and *that* is when we build a certificate authority.

Almost every component in an enterprise platform exists because something specific stopped
working without it. Taught as a list of topics, you memorise what an HSM is. Taught as a
sequence of forced moves, you know *when* an HSM is the right answer and when it is forty
thousand euros of expensive theatre. That difference is the distance between an engineer and
an architect.

The cost: we live with early bad decisions until a pressure justifies fixing them. That is
uncomfortable, and it is exactly what a real system feels like.

---

## Chapters

Each chapter is a folder holding the chapter and everything needed to run its lab.

| # | Chapter | The pressure that drove it | What you end up with |
|---|---|---|---|
| **00** | [One laptop, one app, one password](Chapter%2000/Chapter%2000.md) | *(none, this is the origin)* | The starting system, the naming that becomes law, and the visual language every later diagram uses. Builds nothing on purpose. |
| **01** | [Who can read the password, and where has it already gone?](Chapter%2001/Chapter%2001.md) | That password sits in a readable file. Who can read it, not who *should*, and where has it already been copied? | A running lab; sixteen locations holding one password, eight of them demonstrated by you; a packet capture with a genuinely surprising result; and the discovery that the only real fix is one you have no way to perform. |
| **02** | [Rotating a credential that six systems are holding](Chapter%2002/Chapter%2002.md) | Rotation is manual, breaks things, cannot be verified, and you have no inventory of who holds copies. | A proof that no ordering of two writes avoids an outage; one authoritative place holding the credential; zero-downtime rotation with a verification step; and sixteen leaked copies rendered worthless without deleting any of them. |
| **03** | [Who is asking?](Chapter%2003/Chapter%2003.md) | The store answers anyone who can open a socket to it, and the "consumer" in its audit log is a string the caller wrote about itself. | A store that learns who is calling from the kernel rather than from the caller, refuses everything else against a written policy, and records every decision as fact. The application ends up holding no credential at all. |
| **04** | [The database moves out](Chapter%2004/Chapter%2004.md) | The data and every control protecting it are on one machine, so root there bypasses all of it. Moving the database opens the connection to the network. | A second host added as a compose service; the first key pair and certificate this build owns; and a demonstration that `sslmode=require` gives you an encrypted conversation with the attacker, while two other words refuse it before saying a thing. |

*More chapters are published as they are finished. Work them in order: both the system and
the lab accumulate.*

---

## Before you start

**Prerequisites** — install these before Chapter 01:

| Tool | Why | Verify |
|---|---|---|
| Docker Desktop / Docker Engine / Podman + `podman-compose` | Each "machine" is one Linux container | `docker --version`, `docker compose version` |
| Git | Everything here is text, and Chapter 01 makes use of the history | `git --version` |
| A terminal and a text editor | — | — |

Roughly 8 GB of disk and 6 GB of RAM once everything is standing. Chapter 01 needs a fraction
of that. Apple Silicon, Intel Mac, Linux and WSL2 all work.

Every `docker` command in these chapters is written with `sudo`, which is what a stock Docker
Engine install needs, because the daemon socket is owned by root. If your user is in the
`docker` group, or you are on Docker Desktop, drop the `sudo` and everything else is identical.

---

## Running the labs

Start in Chapter 01. Every chapter is run from its own `lab/` folder, and there is no separate
scratch directory to create and nothing to copy anywhere:

```bash
cd "Chapter 01/lab"
sudo docker compose up -d --build
```

Every relative path in a chapter, every `docker cp dev01/...`, resolves from that folder.

The rest of this section is why the labs are shaped the way they are. You can start Chapter 01
without it and come back when something surprises you.

### The lab lives in the containers

`dev01` is created in Chapter 01 and `db01` in Chapter 04, each once, and neither is recreated
afterwards. Later chapters work from their own folders and deploy into those running containers
with `docker cp`. When a chapter does add a machine it builds only that one, by name:
`sudo docker compose up -d --build db01`.

This is why chapters from 02 onward open with a state check. Building from a later chapter's
folder gives you a container that reports `healthy` and is not in that chapter's starting state,
because the state is accounts, file modes and database rows that no image carries. The check
catches it on the first command and tells you what to do.

### Each `lab/` holds the whole lab at that chapter

Open Chapter 03's folder and you see every file needed to run the system, at the version that
chapter leaves them. Each chapter opens with a manifest of that tree marking what it wrote with
a ★, so you can still tell at a glance what is new and what arrived three chapters ago.

Keeping a full copy per chapter also preserves the lineage. Chapter 01's `config.yaml`, the one
with the password sitting in it, stays exactly where it is, because it is an exhibit later
chapters refer back to.

The compose file is identical across chapters until one adds a machine, so
`docker compose up -d` from any folder is a no-op on machines already running.

### Always name the service when you build

As in `sudo docker compose up -d --build db01`. An unnamed `--build` rebuilds every machine, and
a rebuilt container starts from its chapter's image again, losing the accounts, file modes,
database rows and log files that later chapters create inside it. That is a reset rather than a
disaster: if you need one, rebuild and work the chapters forward again from where the machine
was introduced.

### The folder is yours to break

You will edit files in it, put it under version control, and leave debris in it deliberately.
What you downloaded is the pristine starting state; download the chapter again if you want it
back.

---

## How to read a chapter

Each one is self-contained and follows the same shape:

- **The system before this chapter**, and **the pressure**, the specific thing that is broken.
- **The build**, with every command and its expected output. Run them; the chapters are written
  to be executed, not skimmed.
- **A deliberate failure**, since every chapter breaks something on purpose and diagnoses it
  with real commands. The diagnosis is usually the lesson.
- **What changed in the architecture**, as a diagram in a notation fixed in Chapter 00 and
  obeyed forever: shape and border carry category, line style carries protection level, and
  colour never carries meaning on its own.
- **Decisions**, each with the options considered and *what would flip it*.
- **Where this still hurts**, the cost of what was just built, including the ways it made
  things worse. This section is why the next chapter exists.
- **Prove it to yourself**, questions with full answers.

Two conventions worth knowing before you start:

**Everything is named, and names never change.** `HOST-01`, `APP-01`, `SEC-01`, `ACC-03`. The
ID stays fixed even when the thing it names is transformed, so you can always trace any
component back to the chapter and the pressure that created it.

**Nothing is claimed that is not shown.** Where a chapter demonstrates something, you run it.
Where it enumerates something it has not demonstrated, it says so plainly and names the
mechanism so you can verify it yourself.
