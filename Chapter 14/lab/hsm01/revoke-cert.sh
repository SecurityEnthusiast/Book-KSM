#!/bin/sh
# PROC-07, the revoking half. Run as the `signd` user on hsm01.
#
#   revoke-cert <certificate-file> [reason]
#
# Adds a certificate to the register as revoked, then republishes CRL-01 so
# the decision reaches anybody who is checking. Both steps, always: a
# revocation that is recorded and not published has changed nothing at all,
# and that is the failure mode worth designing against, because it looks like
# success on the machine where you typed it.
#
# WHAT YOU HAND IT is the certificate, not a serial. The serial is what ends
# up in the list, but a human reading a serial cannot tell whether it is the
# right one, and revoking the wrong certificate is an outage you then have to
# diagnose without the thing that would have told you. So the tool takes the
# file, prints its subject and serial, and lets you see what you are about to
# take back.
#
# ON `reason`. X509 CRLs carry an optional reason code, and it is not
# decoration: `keyCompromise` and `cessationOfOperation` mean genuinely
# different things to anybody reading the list later, and only one of them
# means the certificate must never be trusted again for any period. Default
# here is unspecified, because guessing is worse than saying nothing.
#
# Valid reasons, from `openssl ca`:
#   unspecified, keyCompromise, CACompromise, affiliationChanged,
#   superseded, cessationOfOperation, certificateHold, removeFromCRL

set -eu

DIR=/var/lib/ca
CNF="$DIR/ca.cnf"

MODULE=/usr/lib/softhsm/libsofthsm2.so
TOKEN=ica-token
LABEL=ica-key
PIN_FILE=$DIR/ica-pin               # SEC-08

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "usage: revoke-cert <certificate-file> [reason]" >&2
    exit 2
fi
CERT="$1"
REASON="${2:-unspecified}"

[ -r "$CERT" ]     || { echo "revoke-cert: cannot read $CERT" >&2; exit 1; }
[ -r "$CNF" ]      || { echo "revoke-cert: cannot read $CNF" >&2; exit 1; }
[ -r "$PIN_FILE" ] || { echo "revoke-cert: cannot read the PIN. Run as the 'signd' user." >&2; exit 1; }
PIN=$(cat "$PIN_FILE")

# Refuse a certificate this authority did not sign. Without this check the
# register would happily accept anything: `openssl ca -revoke` adds unknown
# certificates to the database on sight, which is what makes the retrofit in
# section 4 possible and also means the tool has no opinion of its own about
# what belongs. Revoking a certificate we never issued would publish a serial
# that means nothing, and mean the real one is still trusted.
if ! openssl verify -partial_chain -CAfile "$DIR/ica.crt" "$CERT" >/dev/null 2>&1; then
    echo "revoke-cert: $CERT was not issued by CERT-09. Refusing." >&2
    echo "  its issuer: $(openssl x509 -in "$CERT" -noout -issuer)" >&2
    exit 1
fi

echo "== about to revoke =="
openssl x509 -in "$CERT" -noout -subject -serial -dates
echo "reason: $REASON"
echo

KEY_URI="pkcs11:token=$TOKEN;object=$LABEL;type=private?pin-value=$PIN"

echo "== 1. record it in the register =="
openssl ca -config "$CNF" \
    -engine pkcs11 -keyform engine -keyfile "$KEY_URI" \
    -revoke "$CERT" -crl_reason "$REASON" 2>&1 | grep -v "^Engine" || true

echo
echo "== 2. publish, because step 1 on its own changes nothing =="
crl-refresh

echo
echo "== 3. the register now says =="
cat "$DIR/db/index.txt"
