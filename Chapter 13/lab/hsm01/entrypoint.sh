#!/bin/sh
set -e

# hsm01 runs one thing, and unlike ca01 it does have something to start.
#
# Chapter 05 gave ca01 an entrypoint that slept, because a CA that nobody
# calls is a key and a procedure. Chapter 07 gives the authority a caller,
# so there is now a process that has to be listening. That process is the
# whole reason this host exists, and it is the only thing installed here.
#
# It is still started by hand, like every other process in this build.
# HOST-04 has no service manager either, which is OT-009 acquiring a
# fourth machine to be true on.

exec sleep infinity
