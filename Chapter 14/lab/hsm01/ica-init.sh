#!/bin/sh
# PROC-06, the intermediate's key ceremony. Run once, as the `signd` user,
# on hsm01.
#
#   ica-init
#
# Generates KEY-06 inside a token on this machine and produces a certificate
# request for it. It does not produce a certificate, and cannot: the only
# thing that can turn this request into an authority is KEY-05, which is on
# a machine that is switched off.
#
# WHY A SECOND TOKEN AND NOT A SECOND KEY IN THE FIRST ONE. hsm01 already
# has `ca-token` holding KEY-04, the root this chapter retires. Two options
# were available and only one of them is safe:
#
#   Re-initialise ca-token. Destroys KEY-04 immediately, which sounds tidy
#   and means the old root is gone before the new hierarchy is proven to
#   work. There is no way back from that if the ceremony fails halfway.
#
#   A new token with a new label. KEY-04 stays addressable during the
#   overlap and is destroyed explicitly at the end of the chapter, once
#   nothing depends on it.
#
# The second, and note that both tokens must have DIFFERENT LABELS. Every
# tool here addresses tokens by label because SoftHSM assigns slot numbers
# at random, so two tokens sharing a label would make every later command
# ambiguous, and it would be ambiguous silently. D-061.

set -eu

MODULE=/usr/lib/softhsm/libsofthsm2.so
TOKEN=ica-token
LABEL=ica-key
DIR=/var/lib/ca
PIN_FILE=$DIR/ica-pin           # SEC-08
SO_PIN_FILE=$DIR/ica-so-pin     # SEC-09
CN="Simurgh Lab Issuing CA 1"   # quoted, and it has to be: without the quotes the
                                # shell reads this as CN=Simurgh followed by the
                                # command `Lab`, and `sh -n` accepts it happily
                                # because an assignment prefix before a command is
                                # valid syntax. It fails at run time with
                                # `Lab: not found`.

[ -r "$PIN_FILE" ]    || { echo "ica-init: cannot read $PIN_FILE. Run as the 'signd' user." >&2; exit 1; }
[ -r "$SO_PIN_FILE" ] || { echo "ica-init: cannot read $SO_PIN_FILE." >&2; exit 1; }
PIN=$(cat "$PIN_FILE")
SO_PIN=$(cat "$SO_PIN_FILE")

echo "== 1. initialise a SECOND token on this machine =="
# --free takes the first uninitialised slot, so this does not disturb
# ca-token. The label is what everything downstream will use.
softhsm2-util --init-token --free --label "$TOKEN" \
              --so-pin "$SO_PIN" --pin "$PIN"

echo
echo "== 2. both tokens, so you can see there are now two =="
softhsm2-util --show-slots | grep -E "^Slot|    Label:" | sed 's/^/  /'

echo
echo "== 3. generate KEY-06 inside the new token =="
pkcs11-tool --module "$MODULE" --token-label "$TOKEN" --login --pin "$PIN" \
            --keypairgen --key-type EC:prime256v1 --label "$LABEL" --id 01

echo
echo "== 4. what the token says about it =="
pkcs11-tool --module "$MODULE" --token-label "$TOKEN" --login --pin "$PIN" \
            --list-objects

echo
echo "== 5. build the certificate request =="
# A CSR is a public key, a proposed name, and a signature proving the
# requester holds the matching private key. That signature is made by the
# token, which is why this needs the engine: there is no key file to read.
#
# It carries no extensions. What this certificate is allowed to be is
# decided by the root when it signs, not by the applicant when it asks,
# which is the same principle as POL-02 refusing to read a name out of the
# request body.
KEY_URI="pkcs11:token=$TOKEN;object=$LABEL;type=private?pin-value=$PIN"

openssl req -new \
    -engine pkcs11 -keyform engine -key "$KEY_URI" \
    -out "$DIR/requests/ica.csr" -sha256 \
    -subj "/CN=$CN" 2>/dev/null

chmod 0644 "$DIR/requests/ica.csr"

echo "  the request, which is public and which you are about to carry by hand:"
openssl req -in "$DIR/requests/ica.csr" -noout -subject -verify 2>&1 | sed 's/^/  /'

echo
echo "== 6. record what was created =="
date -u +"%Y-%m-%dT%H:%M:%SZ  KEY-06 generated in token $TOKEN, label $LABEL; CSR written for CN=$CN" \
    >> "$DIR/ceremony.log"
tail -3 "$DIR/ceremony.log"
