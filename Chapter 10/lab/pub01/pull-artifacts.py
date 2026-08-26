#!/usr/bin/env python3
"""Fill /srv/pub from the authority. Run as ACC-11 on HOST-06 pub01.

    pull-artifacts --from http://hsm01.lab.simurgh.example:8080 [--once]

Fetches the public artefacts from SVC-03 and writes them where pubd serves
them. That is the whole job.

WHAT IT DOES NOT CHECK, AND WHY THAT IS THE DESIGN. It does not verify a
signature, an issuer, a date or a crlNumber. It cannot: this machine holds no
anchor and is not trusted by anybody. If it validated, the estate would grow a
second opinion about what is current, and two opinions that can disagree are
worse than one. The client verifies. This moves bytes.

THE ONE THING IT IS CAREFUL ABOUT is not making things worse. A fetch that
fails must leave the previously published file exactly where it was, because a
client that finds a truncated CRL turns revocation checking off without saying
so, which Chapter 09 section 8 measured. So every write is to a temporary file
in the same directory followed by an atomic rename, and a failed fetch writes
nothing at all.

Serving yesterday's list is a known and bounded problem: it expires, and the
client refuses it. Serving half a list is an unbounded one: the client stops
checking. When those are the two options, keep the old file.
"""
import argparse
import os
import sys
import tempfile
import time
import urllib.request
from datetime import datetime, timezone

ROOT = "/srv/pub"
ARTEFACTS = ["crl.pem", "ca-bundle.pem"]


def stamp():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def fetch_one(base, name):
    """Return (changed, message). Never raises, never leaves a partial file."""
    url = f"{base.rstrip('/')}/{name}"
    try:
        with urllib.request.urlopen(url, timeout=15) as resp:
            if resp.status != 200:
                return False, f"{name}: upstream said {resp.status}, keeping what we have"
            body = resp.read()
    except Exception as exc:
        return False, f"{name}: {exc}, keeping what we have"

    if not body.strip():
        return False, f"{name}: upstream served an empty file, keeping what we have"

    dest = os.path.join(ROOT, name)
    try:
        with open(dest, "rb") as fh:
            if fh.read() == body:
                return False, f"{name}: unchanged, {len(body)} bytes"
    except OSError:
        pass

    # Same directory, so the rename is atomic. A client reading mid-write would
    # otherwise get a parse error, and to a verifier failing closed a parse
    # error is an outage.
    try:
        with tempfile.NamedTemporaryFile("wb", dir=ROOT, delete=False) as tmp:
            tmp.write(body)
            staged = tmp.name
        os.chmod(staged, 0o644)
        os.replace(staged, dest)
    except OSError as exc:
        return False, f"{name}: cannot publish: {exc}"
    return True, f"{name}: published, {len(body)} bytes"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="base", required=True)
    ap.add_argument("--interval", type=int, default=300,
                    help="seconds between polls. Not a schedule: this process "
                         "is started by hand like everything else here, and if "
                         "nobody starts it nothing is published. OT-009")
    ap.add_argument("--once", action="store_true")
    args = ap.parse_args()

    if not os.path.isdir(ROOT):
        print(f"pull-artifacts: {ROOT} does not exist", file=sys.stderr)
        return 1

    while True:
        for name in ARTEFACTS:
            changed, msg = fetch_one(args.base, name)
            print(f"{stamp()}  {'*' if changed else ' '} {msg}", flush=True)
        if args.once:
            return 0
        time.sleep(args.interval)


if __name__ == "__main__":
    sys.exit(main())
