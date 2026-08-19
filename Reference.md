<!-- Generated. Do not edit by hand: edit the chapter that defines the entry. -->

# Reference: every open thread and every decision

An index, not an explanation. Each entry is stated in full in the chapter that created
it, and this page tells you which chapter that is.

**`OT-`** is an open thread: a problem this build knows about and has not solved. A
chapter names the ones it creates at the end, under *Where this still hurts*.
**`D-`** is a decision, recorded with the options considered and what would reverse it,
under *Decisions we made*. **`AR-`** is a risk accepted on purpose rather than a problem
awaiting a fix. Chapter 00 §4 sets the rules, and the object prefixes (`HOST-`, `ACC-`,
`SEC-`, `KEY-`, `CERT-`, `POL-`, `PROC-`) are defined there too.

---

## Open threads (16)

In the order that decides what gets built next. The top entry is the next chapter's
pressure.

| # | ID | What is wrong | Raised |
|---|---|---|---|
| 1 | `OT-021` | `KEY-02` forges any identity in the estate, and a file mode is what stops it | Chapter 05 §12 |
| 2 | `OT-022` | Nothing can be revoked | Chapter 05 §12 |
| 3 | `OT-023` | Nothing decides who may be issued a certificate for which name | Chapter 05 §12 |
| 4 | `OT-018` | `CERT-01` expires in a year and nothing knows | Chapter 04 §10 |
| 5 | `OT-011` | `SVC-02` is a single point of total compromise, in plaintext | Chapter 02 §10 |
| 6 | `OT-014` | Peer credentials do not cross a machine boundary | Chapter 03 §9 |
| 7 | `OT-004` | Root reads everything | Chapter 01 §8 |
| 8 | `OT-006` | `SEC-01` is immortal in process memory | Chapter 01 §6 |
| 9 | `OT-007` | Nothing expires | Chapter 01 §11 |
| 10 | `OT-015` | The store audits itself | Chapter 03 §11 |
| 11 | `OT-016` | `POL-01` is a static allow-list, hand-edited on the host | Chapter 03 §11 |
| 12 | `OT-019` | The database still authenticates the application with a password | Chapter 04 §12 |
| 13 | `OT-012` | `APP-01` cannot start without `SVC-02`, and nothing manages that | Chapter 02 §5.4 |
| 14 | `OT-008` | The application can still write `SEC-01` into its own log | Chapter 01 §3.4 |
| 15 | `OT-009` | Nothing restarts after a reboot | Chapter 01 §14 |
| 16 | `OT-020` | The per-chapter `Dockerfile` has not kept up with the lab it ships beside |  |

---

## Closed threads (7)

Kept because the lineage is the point: you can trace any part of the final system back
to the problem that forced it.

| ID | What it was | Raised | Closed |
|---|---|---|---|
| `OT-001` | The password is in a readable file | Chapter 00 | Chapter 01 |
| `OT-002` | Rotation is impossible to do safely, and we do not know who holds copies | Chapter 01 §8.1 | Chapter 02 |
| `OT-003` | Nothing decides, and nothing is recorded | Chapter 01 §9 | Chapter 03 |
| `OT-005` | No transport encryption, and no server authentication | Chapter 01 §5 | Chapter 04 |
| `OT-010` | The store hands the secret to anything that can open a socket | Chapter 02 §10 | Chapter 03 |
| `OT-013` | The credential crosses the wire in plain HTTP | Chapter 02 §10 | Chapter 03, on one host |
| `OT-017` | The trust anchor is hand-copied, and pinning does not survive renewal | Chapter 04 §10 | Chapter 05 |

---

## Decisions (36)

Every one records the alternatives and what would reverse it. Where a later chapter
overturned an earlier decision, both are kept. Decisions about how the book itself is
written are not listed here.

| ID | Decision | Chapter |
|---|---|---|
| `D-001` | The lab runs on one Linux container per "machine", on your own laptop | Chapter 00 |
| `D-002` | Names are allocated with the endgame in mind, and are never changed | Chapter 00 |
| `D-003` | One visual language, defined before the first figure | Chapter 00 |
| `D-004` | Output is Markdown with inline Mermaid, one self-contained chapter each | Chapter 00 |
| `D-005` | The system is never restarted, only evolved | Chapter 00 |
| `D-006` | `dev01` is one container running a full Debian userland, not the official `postgres` image | Chapter 01 |
| `D-007` | No bind mounts between the laptop and the container | Chapter 01 |
| `D-008` | The application gets its own OS identity (`ACC-03`) and runs as it | Chapter 01 |
| `D-009` | Mode `0400`, not `0600` | Chapter 01 |
| `D-010` | Keep PostgreSQL's `scram-sha-256`; do not fall back to `md5` or `password` | Chapter 01 |
| `D-011` | Correct Chapter 00's "password sent in the clear" openly rather than leave it standing | Chapter 01 |
| `D-013` | Update `dev01` with `docker cp`, never `docker compose up --build` | Chapter 02 |
| `D-014` | Build the smallest possible secret store ourselves rather than deploy an existing one | Chapter 02 |
| `D-015` | The store's HTTP surface is read-only; writes are local and gated by a file permission | Chapter 02 |
| `D-016` | The credential is fetched at run time and re-fetched on failure; never written to a file | Chapter 02 |
| `D-017` | Overlap via two login roles under a `NOLOGIN` group role; `ACC-02` keeps its ID | Chapter 02 |
| `D-018` | The consumer inventory is derived from observed reads, with its limits in the API response | Chapter 02 |
| `D-019` | Accept plaintext at rest in the store, and record it as an accepted risk | Chapter 02 |
| `D-020` | Retire `SEC-01` by disabling the credential, not by chasing its copies | Chapter 02 |
| `D-024` | Authenticate callers with kernel-supplied peer credentials, not a shared token | Chapter 03 |
| `D-025` | `SVC-02` moves from a TCP port to a Unix socket at `/run/secretstore/sock` | Chapter 03 |
| `D-026` | The socket is mode `0666`; `POL-01` is the access boundary | Chapter 03 |
| `D-027` | Do not also gate the socket by group, even though a reviewer would ask for it | Chapter 03 |
| `D-028` | `policy.json` is world-readable; `secrets.json` stays `0600` | Chapter 03 |
| `D-034` | The database moves to `HOST-02 db01` now | Chapter 04 |
| `D-035` | A self-signed certificate pinned by the client, not a certificate authority | Chapter 04 |
| `D-036` | The private key is generated on `db01` and never copied | Chapter 04 |
| `D-037` | `sslmode=verify-full` on the client and `hostssl` on the server | Chapter 04 |
| `D-038` | ECDSA P-256 rather than RSA | Chapter 04 |
| `D-042` | Build a private CA rather than automate anchor distribution | Chapter 05 |
| `D-043` | The authority gets its own host, `HOST-03 ca01` | Chapter 05 |
| `D-044` | `KEY-01` stays on `db01`; only a CSR travels | Chapter 05 |
| `D-045` | The root signs leaves directly; no intermediate | Chapter 05 |
| `D-046` | Ten-year root, ninety-day leaves | Chapter 05 |
| `D-047` | The Subject Alternative Name is the name; the Common Name is decoration | Chapter 05 |
| `D-048` | Chapter 05 discloses the `dev01/Dockerfile` divergence rather than resolving it | Chapter 05 |
