#!/bin/sh
# Publish CRL-01. Run as the `signd` user on hsm01.
#
#   crl-refresh
#
# Regenerates the certificate revocation list from the register and writes it
# where clients collect it. It takes no arguments and revokes nothing: this is
# the routine half of revocation, and the one that has to keep happening after
# everybody has forgotten there was an incident.
#
# WHY A SEPARATE TOOL FROM revoke-cert. A CRL expires. Past its nextUpdate a
# verifier that is checking revocation refuses every certificate it is shown,
# including healthy ones, with `error 12: CRL has expired`. So the list has to
# be republished on a schedule whether or not anything was revoked, and a
# procedure that only runs when something goes wrong will not do that.
#
# Nothing on this host runs it on a schedule. That is OT-009 acquiring a
# consequence it did not have before: until Chapter 09 an unstarted process
# meant a service was down, and now an unrun command means the estate stops
# trusting itself. OT-033.
#
# WHY THE OUTPUT IS TWO LISTS IN ONE FILE. libpq sets CRL_CHECK_ALL and
# demands a list from every authority in the chain. Measured: given only this
# authority's CRL it refuses a healthy certificate, and given only the
# root's it does the same. Both together, concatenated, and it connects.
#
# So the artefact clients need is not the list this machine produces, it is
# that list plus the root's. Assembling it here means there is exactly one
# file to distribute and it is the one that works, which is D-064 applied to
# revocation: produce the correct thing at the point of production rather
# than asking every holder to assemble it.

set -eu

DIR=/var/lib/ca
CNF="$DIR/ca.cnf"
ICA_CRL="$DIR/ica-crl.pem"          # what this authority signs
ROOT_CRL="$DIR/root-crl.pem"        # what the ceremony on rootca produced
OUT="$DIR/crl.pem"                  # CRL-01, the two of them, for clients

MODULE=/usr/lib/softhsm/libsofthsm2.so
TOKEN=ica-token
LABEL=ica-key
PIN_FILE=$DIR/ica-pin               # SEC-08

[ -r "$CNF" ]      || { echo "crl-refresh: cannot read $CNF" >&2; exit 1; }
[ -r "$PIN_FILE" ] || { echo "crl-refresh: cannot read the PIN. Run as the 'signd' user." >&2; exit 1; }
[ -r "$ROOT_CRL" ] || {
    echo "crl-refresh: no root CRL at $ROOT_CRL." >&2
    echo "  Publishing without it produces a file that every client refuses," >&2
    echo "  including for healthy certificates. Run root-crl on rootca first." >&2
    exit 1
}
PIN=$(cat "$PIN_FILE")

# The key is named here rather than in ca.cnf, so that SEC-08 is not written
# into a file that persists. Both forms were measured and both work; this one
# does not leave the PIN on disk. D-067.
KEY_URI="pkcs11:token=$TOKEN;object=$LABEL;type=private?pin-value=$PIN"

# Written to a temporary file and moved into place. A client that reads
# crl.pem while it is half-written gets a parse error rather than a CRL, and
# on a verifier that is failing closed a parse error is an outage. mv within
# one filesystem is atomic; `>` is not.
TMP=$(mktemp "$DIR/crl.XXXXXX")
trap 'rm -f "$TMP"' EXIT

openssl ca -config "$CNF" \
    -engine pkcs11 -keyform engine -keyfile "$KEY_URI" \
    -gencrl -out "$ICA_CRL" 2>/dev/null
chmod 0644 "$ICA_CRL"

cat "$ICA_CRL" "$ROOT_CRL" > "$TMP"
mv "$TMP" "$OUT"
chmod 0644 "$OUT"
trap - EXIT

# Print both lists. The serial entries matter to verifiers; the dates matter
# to whoever is on call, and the EARLIER of the two nextUpdate values is the
# one that takes the estate down.
echo "published: $OUT"
for f in "$ICA_CRL" "$ROOT_CRL"; do
    printf '  %s\n' "$(openssl crl -in "$f" -noout -issuer | cut -d= -f2-)"
    openssl crl -in "$f" -noout -crlnumber -lastupdate -nextupdate | sed 's/^/    /'
done
echo "revoked entries here: $(grep -c '^R' "$DIR/db/index.txt" 2>/dev/null || echo 0)"
