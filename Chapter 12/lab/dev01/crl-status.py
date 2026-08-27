#!/usr/bin/env python3
"""Report how much life is left in the installed revocation list.

    crl-status --crl /var/lib/fetch-crl/crl.pem [--warn-days 2] [--quiet]

Exits 0 while every list in the bundle has more than --warn-days left, and 1
the moment any of them does not. Exits 1 if the file is missing, unreadable or
unparseable, because all of those mean the same thing operationally: this
client is about to stop verifying, or has already.

WHY THIS EXISTS SEPARATELY FROM fetch-crl.

fetch-crl answers "did the fetch work". This answers "is the estate all right",
and they are not the same question. Measured on Debian 12: a cron job that
fails writes to nowhere. There is no MTA and no syslog in these containers, so
stderr is discarded, and cron keeps no log of having run anything. Redirecting
to a file captures what the job SAID and still loses whether it FAILED.

So a scheduled fetch-crl that quietly stops working looks exactly like one that
is working, right up until the list expires and every certificate in the estate
is refused at once.

The way out is not a better log. It is to stop asking about the job and start
asking about the artefact. A fetch that ran, exited zero and installed nothing
useful is indistinguishable from a fetch that never ran, unless something looks
at what should have changed.

WHAT THIS DOES NOT SOLVE, and the chapter says so rather than pretending. This
program is itself a thing that can stop running. Something outside has to ask
it, which is why APP-01 serves the answer on /healthz and why the last link in
the chain is a human or a monitoring system with a curl. The regress does not
terminate inside the machine.
"""
import argparse
import os
import re
import subprocess
import sys
from datetime import datetime, timezone

BEGIN = "-----BEGIN X509 CRL-----"
END = "-----END X509 CRL-----"


def split_blocks(text):
    """Every PEM CRL in the file, in order.

    The same boundary walk fetch-crl does, and for the same measured reason:
    `openssl crl -in` on a two-list bundle reads the FIRST block and exits 0,
    so a single call reports on half the file and calls it healthy.
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


def field(pem, flag, pattern):
    proc = subprocess.run(["openssl", "crl", "-noout", flag],
                          input=pem, capture_output=True, text=True)
    if proc.returncode != 0:
        return None
    m = re.search(pattern, proc.stdout + proc.stderr)
    return m.group(1).strip() if m else None


def report(crl_path, warn_days):
    """Return (ok, lines). Never raises: a monitor that crashes reports nothing."""
    if not os.path.exists(crl_path):
        return False, [f"MISSING {crl_path}"]
    try:
        with open(crl_path) as fh:
            text = fh.read()
    except OSError as exc:
        return False, [f"UNREADABLE {crl_path}: {exc}"]

    blocks = split_blocks(text)
    if not blocks:
        return False, [f"NOT A CRL BUNDLE {crl_path}"]

    now = datetime.now(timezone.utc)
    ok, lines = True, []
    for pem in blocks:
        issuer = field(pem, "-issuer", r"issuer=(.*)") or "unknown issuer"
        nextup = field(pem, "-nextupdate", r"nextUpdate=(.*)")
        number = field(pem, "-crlnumber", r"crlNumber=(\S+)") or "?"
        if not nextup:
            ok = False
            lines.append(f"NO nextUpdate  {issuer}")
            continue
        try:
            expires = datetime.strptime(nextup, "%b %d %H:%M:%S %Y %Z").replace(
                tzinfo=timezone.utc)
        except ValueError:
            ok = False
            lines.append(f"BAD nextUpdate {issuer}: {nextup!r}")
            continue
        left = (expires - now).total_seconds() / 86400.0
        if left <= 0:
            ok = False
            state = "EXPIRED"
        elif left < warn_days:
            ok = False
            state = "EXPIRING"
        else:
            state = "ok"
        lines.append(f"{state:8} {issuer}  crlNumber {number}  "
                     f"{left:.2f} days left  (nextUpdate {nextup})")
    return ok, lines


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--crl", default="/var/lib/fetch-crl/crl.pem")
    ap.add_argument("--warn-days", type=float, default=2.0,
                    help="fail while any list has less than this left. The "
                         "default is under a third of the intermediate's seven "
                         "days, so two consecutive missed refreshes are needed "
                         "before it complains, and one missed refresh is not "
                         "an incident")
    ap.add_argument("--quiet", action="store_true",
                    help="print nothing, just set the exit status")
    args = ap.parse_args()

    ok, lines = report(args.crl, args.warn_days)
    if not args.quiet:
        for line in lines:
            print(line)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
