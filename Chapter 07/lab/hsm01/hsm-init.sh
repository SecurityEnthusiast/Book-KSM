#!/bin/sh
# PROC-03, the key ceremony. Run once, as the `ca` user, on ca01.
#
#   hsm-init
#
# Creates the token, generates KEY-04 inside it, and proves the key cannot
# come back out. It never writes a private key to disk, because there is no
# point in the process at which one exists outside the token.
#
# Everything here is deliberately noisy. A key ceremony whose output nobody
# reads is a ceremony, in the pejorative sense.

set -eu

MODULE=/usr/lib/softhsm/libsofthsm2.so
TOKEN=ca-token
LABEL=ca-key
PIN_FILE=/var/lib/ca/pin          # SEC-04, the user PIN
SO_PIN_FILE=/var/lib/ca/so-pin    # SEC-05, the security officer PIN

[ -r "$PIN_FILE" ]    || { echo "hsm-init: cannot read $PIN_FILE. Run as the 'signd' user." >&2; exit 1; }
[ -r "$SO_PIN_FILE" ] || { echo "hsm-init: cannot read $SO_PIN_FILE." >&2; exit 1; }
PIN=$(cat "$PIN_FILE")
SO_PIN=$(cat "$SO_PIN_FILE")

echo "== 1. initialise the token =="
# --free takes the first uninitialised slot. The slot NUMBER it returns is
# assigned at random and differs on every machine, so nothing after this
# line refers to a slot. Tokens are addressed by label, always.
softhsm2-util --init-token --free --label "$TOKEN" \
              --so-pin "$SO_PIN" --pin "$PIN"

echo
echo "== 2. generate KEY-04 inside the token =="
# There is no --out. That is the whole point: the key is created in the
# token and the command has nowhere to put a copy even if it wanted one.
pkcs11-tool --module "$MODULE" --token-label "$TOKEN" --login --pin "$PIN" \
            --keypairgen --key-type EC:prime256v1 --label "$LABEL" --id 01

echo
echo "== 3. what the token says about it =="
pkcs11-tool --module "$MODULE" --token-label "$TOKEN" --login --pin "$PIN" \
            --list-objects

echo
echo "== 4. prove it cannot be extracted =="
# pkcs11-tool refuses to read a private key and STILL EXITS 0, so the exit
# status proves nothing. Check for the absence of the file instead. This is
# the same shape as Chapter 01 section 5.2: a measurement that cannot tell
# success from failure is not a measurement.
rm -f /tmp/extraction-attempt
pkcs11-tool --module "$MODULE" --token-label "$TOKEN" --login --pin "$PIN" \
            --read-object --type privkey --label "$LABEL" \
            -o /tmp/extraction-attempt 2>&1 || true
if [ -s /tmp/extraction-attempt ]; then
    echo "FAIL: something was written. The key is extractable and this token is useless." >&2
    rm -f /tmp/extraction-attempt
    exit 1
fi
rm -f /tmp/extraction-attempt
echo "OK: no key material was produced."

echo
echo "== 5. record what was created =="
date -u +"%Y-%m-%dT%H:%M:%SZ  KEY-04 generated in token $TOKEN, label $LABEL" \
    >> /var/lib/ca/ceremony.log
cat /var/lib/ca/ceremony.log
