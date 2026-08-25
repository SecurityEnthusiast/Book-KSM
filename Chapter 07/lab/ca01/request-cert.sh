#!/bin/sh
# PROC-02, rewritten. Requests a certificate from SVC-03 on hsm01.
#
#   request-cert <csr-file> <fqdn> [additional-dns-name ...]
#
# Chapter 06's version of this script signed. This one asks. Everything that
# touches KEY-04 now happens on a machine this one cannot log in to, so what
# is left here is a client: build a request, present a certificate proving
# who we are, and receive a certificate or a refusal.
#
# Note what ca01 no longer has, because it is the point of the chapter. No
# token, no PIN, no softhsm group, no signing key of any kind. Root here can
# read CERT-07 and its key, which is enough to ASK, and POL-02 decides what
# asking gets you. It is not enough to sign anything.

set -eu

SIGND=https://hsm01.lab.simurgh.example:8443/v1/sign
ANCHOR=/opt/ca-client/ca.crt        # CERT-05, so we verify the service
CLIENT_CRT=/opt/ca-client/ca01.crt  # CERT-07, so the service can verify us
CLIENT_KEY=/opt/ca-client/ca01.key

if [ $# -lt 2 ]; then
    echo "usage: request-cert <csr-file> <fqdn> [additional-dns-name ...]" >&2
    exit 2
fi
CSR="$1"; FQDN="$2"; shift 2

[ -r "$CSR" ]        || { echo "request-cert: cannot read CSR: $CSR" >&2; exit 1; }
[ -r "$CLIENT_KEY" ] || { echo "request-cert: cannot read CERT-07's key. Run as 'ca'." >&2; exit 1; }

# Build the JSON body without a JSON library, because this host has python3
# for the application and this script should not depend on it. The CSR is
# PEM, so the only escaping needed is the newlines.
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

# Pull the PEM out of the JSON reply. sed rather than a parser, for the same
# reason as above; the field is the last one and the format is ours.
printf '%s' "$RESP" | sed -n 's/.*"certificate": "\(.*\)", "issued_for".*/\1/p' \
  | sed 's/\\n/\n/g'
