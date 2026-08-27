#!/bin/sh
set -e

# Sleeps, like every other machine here, and for the ordinary reason: the
# processes on it are started by hand because this build has no service
# manager on any host. OT-009, on a sixth machine.
#
# Two things will be started on this one: pubd, which serves /srv/pub, and
# pull-artifacts, which fills it. Neither is running yet, and a container
# reporting healthy while serving nothing is exactly the shape Chapter 08
# section 0 warns about.

exec sleep infinity
