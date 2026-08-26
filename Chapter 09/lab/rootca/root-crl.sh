#!/bin/sh
# The CRL half of the root ceremony. Run as the `rootca` user, on rootca,
# while the machine is briefly started.
#
#   root-crl
#
# Publishes the root's revocation list. It revokes nothing: at the time of
# writing CERT-08 has signed exactly one certificate, CERT-09, and that one
# is fine. The list is empty and it is still mandatory, which is the part
# worth understanding.
#
# WHY AN EMPTY LIST IS NOT A NO-OP. libpq sets CRL_CHECK_ALL, so a client
# checking revocation demands a list from every authority in the chain. Given
# only the intermediate's list it refuses a healthy certificate, because it
# cannot establish the root's opinion at all. An empty CRL is that opinion:
# "I have revoked nothing, and here is my signature saying so, valid until
# nextUpdate."
#
# The absence of a list and a list saying nothing are completely different
# statements, and only one of them lets the estate work.
#
# This runs inside PROC-04's window, between `docker start` and `docker stop`.
# It is the second thing the root does in its life and, if nothing is ever
# compromised, the last.

set -eu

DIR=/var/lib/rootca
CNF="$DIR/root.cnf"
OUT="$DIR/root-crl.pem"

MODULE=/usr/lib/softhsm/libsofthsm2.so
TOKEN=root-token
LABEL=root-key
PIN_FILE=$DIR/pin           # SEC-06

[ -r "$CNF" ]      || { echo "root-crl: cannot read $CNF" >&2; exit 1; }
[ -r "$PIN_FILE" ] || { echo "root-crl: cannot read the PIN. Run as the 'rootca' user." >&2; exit 1; }
PIN=$(cat "$PIN_FILE")

mkdir -p "$DIR/db"
[ -f "$DIR/db/index.txt" ] || : > "$DIR/db/index.txt"
[ -f "$DIR/db/crlnumber" ] || echo 1000 > "$DIR/db/crlnumber"

KEY_URI="pkcs11:token=$TOKEN;object=$LABEL;type=private?pin-value=$PIN"

openssl ca -config "$CNF" \
    -engine pkcs11 -keyform engine -keyfile "$KEY_URI" \
    -gencrl -out "$OUT" 2>/dev/null

chmod 0644 "$OUT"

echo "published: $OUT"
openssl crl -in "$OUT" -noout -issuer -crlnumber -lastupdate -nextupdate

echo
echo "This file is public and must reach every client in the estate. Until it"
echo "does, any client configured to check revocation refuses everything."

date -u +"%Y-%m-%dT%H:%M:%SZ  root CRL published, nextUpdate $(openssl crl -in "$OUT" -noout -nextupdate | cut -d= -f2)" \
    >> "$DIR/ceremony.log"
