#!/bin/sh
set -e

# There is still nothing to start here, and the reason has changed.
#
# In Chapter 05 and Chapter 06 this host slept because the authority was a
# key, a script and a procedure, and nothing needed an answer from it at
# run time. In Chapter 07 the authority is a service, and it is not here:
# it runs on HOST-04 and this machine is one of its clients.
#
# So ca01 sleeps for a smaller reason than before. It is an operator's
# workstation with a client credential on it, and it does its work when a
# human runs request-cert. Nothing listens, nothing holds a key, and
# nothing is lost if this container is destroyed except a certificate that
# SVC-03 would happily issue again.
#
# That last sentence is the measure of what Chapter 07 moved.

exec sleep infinity
