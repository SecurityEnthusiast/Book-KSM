#!/bin/sh
# Stop SVC-03, on a machine that has no process tools.
#
#   stop-signd
#
# WHY THIS EXISTS. Every other chapter stops a process with `pkill -f`, and
# every one of those runs on dev01 or db01, which install `procps`. hsm01
# does not. There is no ps here, no pgrep and no pkill, because D-054 says
# this machine carries nothing a general purpose host carries and that was
# not a slogan. The first command in Chapter 08 that assumed otherwise got:
#
#   OCI runtime exec failed: ... exec: "pkill": executable file not found
#
# followed, one line later, by the consequence:
#
#   OSError: [Errno 98] Address already in use
#
# because the old service was still holding 8443 when the new one started.
# A stop that silently does nothing is worse than no stop at all.
#
# WHAT IT USES INSTEAD. /proc, which is the kernel and cannot be uninstalled,
# read by the python3 that is here only because SVC-03 is written in it.
#
# Two things keep it from killing the wrong process, and it is worth being
# exact about which does what, because one of them is weaker than it looks.
#
#   The PID check skips this process. That is what stops the searcher from
#   killing itself, and it is the load-bearing one.
#
#   The match is on a whole argv entry rather than a substring. That rules
#   out lookalikes such as /usr/local/bin/signd-old, and it rules out this
#   script's own shell, whose argv holds /usr/local/bin/stop-signd. It does
#   NOT rule out a process that merely has the exact path as an argument:
#   `grep /usr/local/bin/signd` would still match. There is no such process
#   here because this reads /proc directly instead of shelling out to grep,
#   which is the actual reason the pipeline-searching-for-itself problem
#   does not arise.

set -eu

exec python3 - <<'PY'
import os
import signal
import sys
import time

TARGET = "/usr/local/bin/signd"


def pids_running():
    """Every PID whose argv contains TARGET as a whole argument, except ours."""
    me = os.getpid()
    out = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        pid = int(entry)
        if pid == me:
            continue
        try:
            with open("/proc/%d/cmdline" % pid, "rb") as fh:
                argv = fh.read().decode("utf-8", "replace").split("\0")
        except OSError:
            # The process exited between listdir and open. Normal, not an error.
            continue
        if TARGET in argv:
            out.append(pid)
    return out


targets = pids_running()
if not targets:
    print("stop-signd: nothing running")
    sys.exit(0)

for pid in targets:
    print("stop-signd: sending TERM to %d" % pid)
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError as exc:
        print("stop-signd: cannot signal %d: %s" % (pid, exc))

# Wait for it to actually go, rather than assuming. The next thing the
# chapter does is bind 8443 again, and a `sleep 1` that happens to be long
# enough on this laptop is not a check.
for _ in range(50):
    if not pids_running():
        print("stop-signd: stopped, 8443 released")
        sys.exit(0)
    time.sleep(0.1)

print("stop-signd: still running after 5s, sending KILL")
for pid in pids_running():
    try:
        os.kill(pid, signal.SIGKILL)
    except OSError:
        pass
time.sleep(0.5)
sys.exit(0 if not pids_running() else 1)
PY
