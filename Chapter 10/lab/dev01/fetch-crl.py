#!/usr/bin/env python3
"""Fetch CRL-01 from the publication point, check it, and install it.

Run on any client that verifies certificates. On HOST-01 that is:

    fetch-crl --url http://pub01.lab.simurgh.example/crl.pem \\
              --anchors /opt/paymentsvc/ca-bundle.pem \\
              --install /opt/paymentsvc/crl.pem \\
              --state   /var/lib/fetch-crl/state.json

WHY THIS IS NOT `curl -o /opt/paymentsvc/crl.pem`.

That one-liner is the obvious implementation and it is worse than doing nothing,
for three separate measured reasons.

FIRST, it writes to the live file. A fetch that fails halfway leaves a truncated
or empty crl.pem, and Chapter 09 section 8 measured what libpq does with an
unusable CRL: it turns revocation checking off and connects. Automating a
procedure that fails that way means it now fails that way every hour, unattended.

SECOND, a single `openssl crl -verify` on this file checks half of it. CRL-01
holds two lists, the intermediate's and the root's, and `openssl crl -in` reads
only the first block. It exits 0 having never looked at the second. So this
splits the bundle and checks every block.

THIRD, and this is the one that is an attack rather than an accident: an OLD
CRL is still a valid CRL. Every signature verifies. Serve a client the list
published before a revocation and the revoked certificate works again. OpenSSL
does not remember it has seen a higher crlNumber, so nothing in the stack
catches this and the check has to live here. That is what --state is for.

WHAT THIS DELIBERATELY DOES NOT DO: fetch over TLS. A CRL is signed, numbered
and dated by an authority whose key we already trust, so the transport adds
nothing a forger could defeat. Verifying the signature is the security control;
verifying the channel would be a second, weaker one. The publication point is
deliberately a dumb static server that holds no key at all.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.request
from datetime import datetime, timezone

BEGIN = "-----BEGIN X509 CRL-----"
END = "-----END X509 CRL-----"


def die(msg):
    print(f"fetch-crl: {msg}", file=sys.stderr)
    sys.exit(1)


def openssl(args, stdin_path):
    """Run `openssl crl` against one file and return (rc, stdout+stderr)."""
    proc = subprocess.run(["openssl", "crl", "-in", stdin_path, "-noout"] + args,
                          capture_output=True, text=True)
    return proc.returncode, (proc.stdout + proc.stderr).strip()


def split_blocks(text):
    """Every PEM CRL in the file, in order.

    Not a parser. The bundle is produced by crl-refresh with `cat`, so the
    blocks are whole and in order; this only has to find the boundaries. If it
    finds none, the file is not a CRL bundle and the caller stops.
    """
    out, cur = [], None
    for line in text.splitlines():
        if line.strip() == BEGIN:
            cur = [line]
        elif cur is not None:
            cur.append(line)
            if line.strip() == END:
                out.append("\n".join(cur) + "\n")
                cur = None
    return out


def field(path, flag, pattern):
    rc, text = openssl([flag], path)
    if rc != 0:
        return None
    m = re.search(pattern, text)
    return m.group(1).strip() if m else None


def parse_openssl_time(value):
    """`Sep  2 13:38:36 2026 GMT` as an aware datetime.

    Parsed here rather than shelled out to `date -d`, which is a GNU extension
    this build should not depend on, and which would put the comparison in a
    place no test can reach.
    """
    return datetime.strptime(value, "%b %d %H:%M:%S %Y %Z").replace(tzinfo=timezone.utc)


def inspect(path, anchors):
    """Everything we need to decide about one CRL, or a reason to refuse it."""
    rc, text = openssl(["-CAfile", anchors, "-verify"], path)
    if rc != 0:
        return None, f"signature check failed: {text.splitlines()[0] if text else 'no output'}"

    issuer = field(path, "-issuer", r"issuer=(.*)")
    number = field(path, "-crlnumber", r"crlNumber=(\S+)")
    nextup = field(path, "-nextupdate", r"nextUpdate=(.*)")
    if not issuer or not nextup:
        return None, "parses as a CRL but has no issuer or no nextUpdate"

    try:
        expires = parse_openssl_time(nextup)
    except ValueError:
        return None, f"cannot read nextUpdate {nextup!r}"

    now = datetime.now(timezone.utc)
    if expires <= now:
        return None, f"expired at {nextup}. Installing it would refuse every certificate"

    # crlNumber is optional in X.509 and mandatory for us: without it there is
    # no way to tell a current list from a replayed one.
    if number is None:
        return None, "has no crlNumber, so replay cannot be detected"
    return {"issuer": issuer, "number": int(number, 16 if number.lower().startswith("0x") else 10),
            "next_update": nextup, "expires": expires.isoformat()}, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--anchors", required=True,
                    help="CERT-08 and CERT-09, so both lists can be checked")
    ap.add_argument("--install", required=True)
    ap.add_argument("--state", required=True)
    ap.add_argument("--expect-lists", type=int, default=2,
                    help="how many authorities must be represented. libpq wants "
                         "one per CA in the chain and refuses everything otherwise")
    args = ap.parse_args()

    for path in (args.anchors,):
        if not os.path.exists(path):
            die(f"{path} does not exist. Nothing can be checked against nothing.")

    # Fetch into a temporary file. The live file is not touched until every
    # check has passed, so a failed download cannot disable revocation checking.
    tmpdir = tempfile.mkdtemp(prefix="fetch-crl.")
    fetched = os.path.join(tmpdir, "candidate.pem")
    try:
        with urllib.request.urlopen(args.url, timeout=15) as resp:
            if resp.status != 200:
                die(f"{args.url} answered {resp.status}")
            body = resp.read()
    except Exception as exc:
        die(f"cannot fetch {args.url}: {exc}")

    if not body.strip():
        die("the publication point served an empty file")
    with open(fetched, "wb") as fh:
        fh.write(body)

    blocks = split_blocks(body.decode("utf-8", "replace"))
    if not blocks:
        die("what was served is not a PEM CRL bundle")
    if len(blocks) < args.expect_lists:
        die(f"served {len(blocks)} list(s), expected at least {args.expect_lists}. "
            "A bundle missing one authority refuses every certificate, healthy included.")

    # Check EVERY block. `openssl crl -in bundle` would look at the first and
    # report success, which is the measurement that produced this loop.
    found = {}
    for i, pem in enumerate(blocks, 1):
        part = os.path.join(tmpdir, f"block{i}.pem")
        with open(part, "w") as fh:
            fh.write(pem)
        info, why = inspect(part, args.anchors)
        if info is None:
            die(f"list {i} of {len(blocks)}: {why}")
        found[info["issuer"]] = info

    if len(found) != len(blocks):
        die("two lists from the same issuer. One of them is not what it claims.")

    # Replay check. An older list is authentic and wrong.
    state = {}
    if os.path.exists(args.state):
        try:
            with open(args.state) as fh:
                state = json.load(fh)
        except (OSError, ValueError):
            state = {}
    seen = state.get("highest", {})

    for issuer, info in found.items():
        previous = seen.get(issuer)
        if previous is not None and info["number"] < previous:
            die(f"ROLLBACK REFUSED. {issuer} served crlNumber {info['number']}, "
                f"lower than {previous}, already installed. An old list is still a "
                "validly signed list, and installing it would un-revoke whatever "
                "was revoked in between.")

    # Everything passed. Install atomically: a client reading the file mid-write
    # gets a parse error, and to a verifier failing closed a parse error is an
    # outage.
    dest_dir = os.path.dirname(os.path.abspath(args.install)) or "."
    with tempfile.NamedTemporaryFile("wb", dir=dest_dir, delete=False) as out:
        out.write(body)
        staged = out.name
    os.chmod(staged, 0o644)
    os.replace(staged, args.install)

    os.makedirs(os.path.dirname(os.path.abspath(args.state)) or ".", exist_ok=True)
    state["highest"] = {i: v["number"] for i, v in found.items()}
    state["installed_from"] = args.url
    state["installed_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    with open(args.state, "w") as fh:
        json.dump(state, fh, indent=2, sort_keys=True)

    print(f"installed: {args.install}")
    for issuer, info in sorted(found.items()):
        print(f"  {issuer}")
        print(f"    crlNumber {info['number']}, nextUpdate {info['next_update']}")
    soonest = min(v["expires"] for v in found.values())
    print(f"  earliest expiry: {soonest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
