#!/bin/sh
# PROC-02, rewritten. Requests a certificate from SVC-03 on hsm01.
#
#   request-cert <csr-file> <fqdn> [additional-dns-name ...]
#
# Chapter 06's version of this script signed. Chapter 07's asked. Everything
# that touches the signing key happens on a machine this one cannot log in
# to, so what is left here is a client: build a request, present a
# certificate proving who we are, and receive a certificate or a refusal.
#
# Note what ca01 does not have, because it is the point of Chapter 07. No
# token, no PIN, no softhsm group, no signing key of any kind. Root here can
# read CERT-07 and its key, which is enough to ASK, and POL-02 decides what
# asking gets you. It is not enough to sign anything.
#
# CHAPTER 08 STOPS PRINTING THE CERTIFICATE TO STDOUT, and the reason is the
# hierarchy rather than taste. There used to be one file to install. There
# are now two, the leaf and the chain, and a script that prints one of them
# to a pipe is a script whose caller loses the other one without being told.
# So this writes both, next to each other, and prints where they went.
#
# Install the CHAIN, not the leaf. Every failure this chapter demonstrates
# comes from someone installing the leaf on its own.

set -eu

SIGND=https://hsm01.lab.simurgh.example:8443/v1/sign
DIR=/opt/ca-client
ANCHOR=$DIR/ca.crt              # CERT-08, so we verify the service
CLIENT_CRT=$DIR/ca01.crt        # CERT-07 followed by CERT-09: our own chain.
                                # A client presents a chain for the same
                                # reason a server does, and gets the same
                                # unhelpful error when it does not.
CLIENT_KEY=$DIR/ca01.key
ISSUED=$DIR/issued

if [ $# -lt 2 ]; then
    echo "usage: request-cert <csr-file> <fqdn> [additional-dns-name ...]" >&2
    exit 2
fi
CSR="$1"; FQDN="$2"; shift 2

[ -r "$CSR" ]        || { echo "request-cert: cannot read CSR: $CSR" >&2; exit 1; }
[ -r "$CLIENT_KEY" ] || { echo "request-cert: cannot read CERT-07's key. Run as 'ca'." >&2; exit 1; }

# Build the JSON body without a JSON library, because this host has no
# python3 and this script should not be the reason it acquires one. The CSR
# is PEM, so the only escaping needed is the newlines.
ALT=""
for n in "$@"; do ALT="$ALT\"$n\","; done
ALT=$(printf '%s' "$ALT" | sed 's/,$//')
BODY=$(printf '{"csr": "%s", "fqdn": "%s", "alt_names": [%s]}' \
  "$(sed ':a;N;$!ba;s/\n/\\n/g' "$CSR")" "$FQDN" "$ALT")

# --cacert is not optional. Without it this client would hand a request to
# anything answering on that name, which is Chapter 04 section 7 in reverse:
# there, the app trusted an impostor database; here, we would trust an
# impostor authority and take back a certificate it signed.
RESP=$(curl -sS --fail-with-body \
  --cacert "$ANCHOR" --cert "$CLIENT_CRT" --key "$CLIENT_KEY" \
  -H 'Content-Type: application/json' \
  -X POST "$SIGND" -d "$BODY") || {
    echo "request-cert: refused or unreachable:" >&2
    echo "$RESP" >&2
    exit 1
  }

# Pull the two PEMs out of the JSON reply. sed rather than a parser, for the
# same reason as above; the fields are ours and their order is fixed.
mkdir -p "$ISSUED"
printf '%s' "$RESP" | sed -n 's/.*"certificate": "\(.*\)", "chain".*/\1/p' \
  | sed 's/\\n/\n/g' > "$ISSUED/$FQDN.crt"
printf '%s' "$RESP" | sed -n 's/.*"chain": "\(.*\)", "issued_for".*/\1/p' \
  | sed 's/\\n/\n/g' > "$ISSUED/ica.crt"

cat "$ISSUED/$FQDN.crt" "$ISSUED/ica.crt" > "$ISSUED/$FQDN.chain.crt"
chmod 0644 "$ISSUED/$FQDN.crt" "$ISSUED/ica.crt" "$ISSUED/$FQDN.chain.crt"

echo "leaf:  $ISSUED/$FQDN.crt"
echo "chain: $ISSUED/$FQDN.chain.crt   <- install this one"
openssl x509 -in "$ISSUED/$FQDN.crt" -noout -subject -issuer -dates
