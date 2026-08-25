#!/bin/sh
set -e

# There is nothing to start. ca01 runs no service, listens on no port and
# answers no request. It exists so that KEY-02 has somewhere to live that
# is neither the application host nor the database host.
#
# Chapter 03's secret store is a process because something had to answer
# APP-01 at run time. Nothing needs an answer from the CA at run time: a
# certificate is requested by a human, once, and is then valid for ninety
# days. Building an issuance API before anything needs one would mean
# designing its authentication and its issuance policy against no pressure
# at all, which is D-005.
#
# So the container sleeps, and the CA is a key, a script and a procedure.

exec sleep infinity
