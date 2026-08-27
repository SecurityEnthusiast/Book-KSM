#!/bin/sh
set -e

# This entrypoint sleeps, like ca01's, and for a third distinct reason.
#
# ca01 sleeps because it is an operator's workstation and does its work when
# a human runs a command. hsm01 sleeps because the process it exists to run
# is started by hand, OT-009. This machine sleeps because it is not supposed
# to be running at all.
#
# Everything a container does while it is up is attack surface, so the goal
# here is for `docker ps` to show nothing and `docker ps -a` to show
# `Exited`. The container is started for the length of a ceremony and
# stopped again in the same procedure, and PROC-04 ends with the stop for
# the same reason a safe is closed after the document comes out.
#
# If you ever find this container running and cannot say which ceremony is
# in progress, that is the finding.

exec sleep infinity
