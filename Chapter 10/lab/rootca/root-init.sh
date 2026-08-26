#!/bin/sh
# PROC-05, the root ceremony. Run once, as the `rootca` user, on rootca.
#
#   root-init
#
# Creates the token, generates KEY-05 inside it, self-signs CERT-08, and
# proves the key cannot come back out. It is Chapter 07's hsm-init with two
# differences, and both are the chapter.
#
# FIRST: it produces the certificate as well as the key. On hsm01 those were
# separate steps because the key was generated in one chapter and the root
# certificate in another. Here they are one ceremony, because splitting them
# would mean starting this container twice.
#
# SECOND, and this is the one that matters: pathlen:1 rather than pathlen:0.
# Chapter 05 wrote pathlen:0 and said it "costs nothing" because we were not
# building an intermediate. It cost this root. A pathlen:0 authority may sign
# leaves and may not sign other authorities, so the moment we wanted a CA
# beneath the root, the root itself had to be replaced. D-062.
#
# pathlen:1 says: one CA may follow me in a path, and no more. It permits the
# intermediate and forbids the intermediate from having children.

set -eu

MODULE=/usr/lib/softhsm/libsofthsm2.so
TOKEN=root-token
LABEL=root-key
DIR=/var/lib/rootca
PIN_FILE=$DIR/pin           # SEC-06, the user PIN
SO_PIN_FILE=$DIR/so-pin     # SEC-07, the security officer PIN
DAYS=3650                   # ten years. D-046, unchanged.

[ -r "$PIN_FILE" ]    || { echo "root-init: cannot read $PIN_FILE. Run as the 'rootca' user." >&2; exit 1; }
[ -r "$SO_PIN_FILE" ] || { echo "root-init: cannot read $SO_PIN_FILE." >&2; exit 1; }
PIN=$(cat "$PIN_FILE")
SO_PIN=$(cat "$SO_PIN_FILE")

echo "== 1. initialise the token =="
softhsm2-util --init-token --free --label "$TOKEN" \
              --so-pin "$SO_PIN" --pin "$PIN"

echo
echo "== 2. generate KEY-05 inside the token =="
# No --out, on the machine where that matters most. This is the key that,
# if it leaves, makes every certificate in the estate forgeable.
pkcs11-tool --module "$MODULE" --token-label "$TOKEN" --login --pin "$PIN" \
            --keypairgen --key-type EC:prime256v1 --label "$LABEL" --id 01

echo
echo "== 3. what the token says about it =="
pkcs11-tool --module "$MODULE" --token-label "$TOKEN" --login --pin "$PIN" \
            --list-objects

echo
echo "== 4. prove it cannot be extracted =="
# The refusal exits 0, so check for the absence of the file and not the
# status. Chapter 06 measured this and it has not stopped being true.
rm -f "$DIR/extraction-attempt"
pkcs11-tool --module "$MODULE" --token-label "$TOKEN" --login --pin "$PIN" \
            --read-object --type privkey --label "$LABEL" \
            -o "$DIR/extraction-attempt" 2>&1 || true
if [ -s "$DIR/extraction-attempt" ]; then
    echo "FAIL: something was written. The key is extractable and this root is worthless." >&2
    rm -f "$DIR/extraction-attempt"
    exit 1
fi
rm -f "$DIR/extraction-attempt"
echo "OK: no key material was produced."

echo
echo "== 5. self-sign CERT-08, the root that permits one CA below it =="
KEY_URI="pkcs11:token=$TOKEN;object=$LABEL;type=private?pin-value=$PIN"

openssl req -new -x509 \
    -engine pkcs11 -keyform engine -key "$KEY_URI" \
    -out "$DIR/root.crt" -days "$DAYS" -sha256 \
    -subj "/CN=Simurgh Lab Root CA" \
    -addext "basicConstraints=critical,CA:TRUE,pathlen:1" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -addext "subjectKeyIdentifier=hash" 2>/dev/null

chmod 0644 "$DIR/root.crt"

echo "  the field this chapter exists because of:"
openssl x509 -in "$DIR/root.crt" -noout -ext basicConstraints,keyUsage
openssl x509 -in "$DIR/root.crt" -noout -subject -dates

echo
echo "== 6. record what was created =="
date -u +"%Y-%m-%dT%H:%M:%SZ  KEY-05 generated in token $TOKEN, label $LABEL; CERT-08 self-signed, pathlen:1" \
    >> "$DIR/ceremony.log"
cat "$DIR/ceremony.log"
