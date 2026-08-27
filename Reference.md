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

## Open threads (25)

In the order that decides what gets built next. The top entry is the next chapter's
pressure.

| # | ID | What is wrong | Raised |
|---|---|---|---|
| 1 | `OT-011` | `SVC-02` is a single point of total compromise, in plaintext | Chapter 02 §10 |
| 2 | `OT-041` | `db01` cannot report on the dependency it just acquired | Chapter 12 §4.2 |
| 3 | `OT-030` | Nothing distributes `CERT-09` | Chapter 08 §9.4 |
| 4 | `OT-042` | The issuance policy governs names, not usages | Chapter 12 §3.1 |
| 5 | `OT-018` | `CERT-01` expires in a year and nothing knows | Chapter 04 §10 |
| 6 | `OT-039` | Nothing watches the deadline | Chapter 10 §9 |
| 7 | `OT-043` | The capture has no expiry and nothing checks it | Chapter 13 §8 |
| 8 | `OT-035` | The intermediate cannot be revoked in useful time | Chapter 09 §5.4 |
| 9 | `OT-027` | One person can sign anything | Chapter 06 §12 |
| 10 | `OT-016` | `POL-01` is a static allow-list, hand-edited on the host | Chapter 03 §11 |
| 11 | `OT-023` | Nothing decides who may be issued a certificate for which name | Chapter 05 §12 |
| 12 | `OT-025` | A Unix group and a shared PIN guard the signing key | Chapter 06 §12 |
| 13 | `OT-036` | Nothing verifies that a security control is actually running | Chapter 09 §8 |
| 14 | `OT-038` | The publication point is a single point of availability failure | Chapter 10 §9 |
| 15 | `OT-014` | Peer credentials do not cross a machine boundary | Chapter 03 §9 |
| 16 | `OT-015` | The store audits itself | Chapter 03 §11 |
| 17 | `OT-007` | Nothing expires | Chapter 01 §11 |
| 18 | `OT-031` | Three anchors by hand, and now the chains too | Chapter 08 §9.1 |
| 19 | `OT-009` | Nothing restarts after a reboot | Chapter 01 §14 |
| 20 | `OT-040` | Nothing asks | Chapter 11 §5 |
| 21 | `OT-044` | Dead code on a credential path | Chapter 14 |
| 22 | `OT-024` | `NET-01` is one flat network | Chapter 06 §12 |
| 23 | `OT-004` | Root reads everything | Chapter 01 §8 |
| 24 | `OT-026` | The token is a library, and root takes the whole box | Chapter 06 §12 |
| 25 | `OT-029` | The root is offline by convention, not by control | Chapter 08 §5 |

---

## Closed threads (18)

Kept because the lineage is the point: you can trace any part of the final system back
to the problem that forced it.

| ID | What it was | Raised | Closed |
|---|---|---|---|
| `OT-001` | The password is in a readable file | Chapter 00 | Chapter 01 |
| `OT-002` | Rotation is impossible to do safely, and we do not know who holds copies | Chapter 01 §8.1 | Chapter 02 |
| `OT-003` | Nothing decides, and nothing is recorded | Chapter 01 §9 | Chapter 03 |
| `OT-005` | No transport encryption, and no server authentication | Chapter 01 §5 | Chapter 04 |
| `OT-006` | `SEC-01` is immortal in process memory | Chapter 01 §6 | Chapter 14 |
| `OT-008` | The application can still write `SEC-01` into its own log | Chapter 01 §3.4 | Chapter 14 |
| `OT-010` | The store hands the secret to anything that can open a socket | Chapter 02 §10 | Chapter 03 |
| `OT-012` | `APP-01` cannot start without `SVC-02`, and nothing manages that | Chapter 02 §5.4 | Chapter 14 |
| `OT-013` | The credential crosses the wire in plain HTTP | Chapter 02 §10 | Chapter 03, on one host |
| `OT-017` | The trust anchor is hand-copied, and pinning does not survive renewal | Chapter 04 §10 | Chapter 05 |
| `OT-019` | The database still authenticates the application with a password | Chapter 04 §12 | Chapter 12 |
| `OT-020` | The per-chapter `Dockerfile` has not kept up with the lab it ships beside | Chapter 05 | Chapter 13 |
| `OT-021` | `KEY-02` forges any identity in the estate, and a file mode is what stops it | Chapter 05 §12 | Chapter 06 |
| `OT-022` | Nothing can be revoked | Chapter 05 §12 | Chapter 09 |
| `OT-028` | Three roots in three chapters, because custody keeps being decided late | Chapter 07 §9 | Chapter 08 |
| `OT-032` | Nothing distributes `CRL-01`, and it expires | Chapter 09 §7 | Chapter 10 |
| `OT-033` | Revocation is an availability dependency, and nothing keeps it fed | Chapter 09 §5.4 | Chapter 11 |
| `OT-037` | The verifiers do not agree with each other | Chapter 09 §9 | Chapter 14 |

---

## Decisions (84)

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
| `D-049` | SoftHSM now, hardware later | Chapter 06 |
| `D-050` | Generate a new key rather than import `KEY-02` | Chapter 06 |
| `D-051` | Address tokens by label, never by slot | Chapter 06 |
| `D-052` | The OpenSSL engine, not the provider | Chapter 06 |
| `D-053` | Join the `softhsm` group rather than chown the package's directories | Chapter 06 |
| `D-054` | Give the key its own host rather than harden `ca01` | Chapter 07 |
| `D-055` | `SVC-03` is a network service, not a shared filesystem or an SSH command | Chapter 07 |
| `D-056` | Identity comes from the client certificate, never from the request | Chapter 07 |
| `D-057` | `sign-leaf` gains `--client` rather than issuing both usages by default | Chapter 07 |
| `D-058` | Generate `KEY-04` on `hsm01` rather than move the token | Chapter 07 |
| `D-059` | A fourth root, and it is the last | Chapter 08 |
| `D-060` | Offline means no network and not running, and not a safe | Chapter 08 |
| `D-061` | A second token with a new label, not a re-initialised `ca-token` | Chapter 08 |
| `D-062` | The root is `pathlen:1` and the intermediate is `pathlen:0` | Chapter 08 |
| `D-063` | Each machine's tools can only do that machine's job | Chapter 08 |
| `D-064` | The chain travels with the certificate, from `sign-leaf` outward | Chapter 08 |
| `D-065` | A five-year intermediate | Chapter 08 |
| `D-066` | A CRL, not OCSP | Chapter 09 |
| `D-067` | The PIN stays on the command line; the CA configuration holds no secret | Chapter 09 |
| `D-068` | `CRL-` becomes an identifier prefix | Chapter 09 |
| `D-069` | The register is for revocation; issuance is unchanged | Chapter 09 |
| `D-070` | Seven days for the intermediate's list | Chapter 09 |
| `D-071` | The application refuses to start on an unusable CRL | Chapter 09 |
| `D-072` | Ten years for the root's list | Chapter 09 |
| `D-073` | Fetch over plain HTTP; verify the content, not the channel | Chapter 10 |
| `D-074` | The publication point verifies nothing | Chapter 10 |
| `D-075` | A separate machine publishes, and `hsm01` keeps a listener anyway | Chapter 10 |
| `D-076` | The client remembers the highest `crlNumber` it has installed | Chapter 10 |
| `D-077` | Every list in the bundle is checked, not the file | Chapter 10 |
| `D-078` | `crlDistributionPoints` is documentation, not a mechanism | Chapter 10 |
| `D-079` | Six hours for `crl-refresh`, which sets both the lag and the margin | Chapter 11 |
| `D-080` | Thirty minutes for `fetch-crl`, deliberately faster than it needs to be | Chapter 11 |
| `D-081` | Watch the artefact, not the job | Chapter 11 |
| `D-082` | `cron`, installed into running containers | Chapter 11 |
| `D-083` | `/healthz` returns `503`, and still does not touch the database | Chapter 11 |
| `D-084` | The certificate names the workload, not the host | Chapter 12 |
| `D-085` | `db01` verifies clients, which makes it the estate's second verifier | Chapter 12 |
| `D-086` | One login role, not two | Chapter 12 |
| `D-087` | `SVC-02` stays, with nothing in it | Chapter 12 |
| `D-088` | The image tags stay wrong, because moving them recreates containers | Chapter 13 |
| `D-089` | The capture is a tool, read only, and never prints a secret | Chapter 13 |
| `D-090` | The registers are created empty by the recipe | Chapter 13 |
| `D-091` | Bound the connection's age, not the credential's life | Chapter 14 |
| `D-092` | The reload lives beside the consumer, not inside the agent | Chapter 14 |
| `D-093` | `signd` rebuilds per connection rather than reloading | Chapter 14 |
| `D-094` | Three threads become accepted risks before Stage 4 | Chapter 14 |
| `D-095` | An open thread is re-measured before a stage boundary, not re-read | Chapter 14 |
| `D-096` | The gate checks that claims are true, not only that references resolve | Chapter 14 |
