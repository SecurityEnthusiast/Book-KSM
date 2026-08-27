#!/bin/sh
# Tell PostgreSQL to re-read its revocation list. Run as `postgres` on HOST-02.
#
#   reload-crl
#
# WHY THIS IS NOT PART OF fetch-crl. fetch-crl runs on every client in the
# estate and knows nothing about what consumes the file it installs. On
# HOST-01 the consumer is a process that re-reads on each connection; here it
# is a server that caches until told otherwise. The knowledge of how a
# particular consumer notices belongs beside that consumer.
#
# WHY IT IS NEEDED AT ALL, measured in Chapter 14: PostgreSQL reads
# ssl_crl_file at startup and at reload, and not per connection. A revoked
# certificate presented on a NEW connection was accepted while the current
# list sat unread on disk. From Chapter 12 until Chapter 14 this machine
# fetched revocations every thirty minutes and honoured none of them.
#
# WHAT A RELOAD DOES NOT DO, also measured: it does not end sessions that are
# already open. A connection established before the revocation keeps working
# afterwards. Ending those is a separate act and a deliberate one, because it
# disconnects innocent clients too. See PROC-13.

set -eu

CRL=/var/lib/postgresql/crl/crl.pem

[ -r "$CRL" ] || { echo "reload-crl: no list at $CRL, nothing to load" >&2; exit 1; }

# Refuse to load something unusable. PostgreSQL will not start or reload with
# a malformed ssl_crl_file, and finding that out during a reload is finding it
# out at the worst moment.
openssl crl -in "$CRL" -noout >/dev/null 2>&1 || {
    echo "reload-crl: $CRL does not parse as a CRL. Not reloading." >&2
    exit 1
}

BEFORE=$(psql -tAc "SELECT pg_conf_load_time()" 2>/dev/null || echo unknown)
pg_ctlcluster 15 main reload
AFTER=$(psql -tAc "SELECT pg_conf_load_time()" 2>/dev/null || echo unknown)

echo "reload-crl: $(date -u +%Y-%m-%dT%H:%M:%SZ) reloaded"
echo "  config load time before: $BEFORE"
echo "  config load time after:  $AFTER"
echo "  lists in $CRL: $(grep -c 'BEGIN X509 CRL' "$CRL")"
