#!/bin/sh
# PROC-02, the issuing half. Signs a certificate request with KEY-02.
#
#   sign-leaf <csr-file> <fqdn> [additional-dns-name ...]
#
# What this script exists to prevent is the failure in Chapter 05 §6: a
# certificate signed with a Subject Alternative Name that does not contain
# the name the client actually dials. The Common Name is not consulted when
# a SAN is present, so a leaf whose CN is perfect and whose SAN is wrong is
# rejected, and the error says nothing about the CN. Doing this by hand is
# how that mistake gets made. Here the FQDN is a required argument and goes
# into the SAN before anything else can.
#
# It never reads, prints or copies KEY-02, and it never sees the subject's
# private key, which stayed on the subject's own host. Only a CSR arrives.

set -eu

CA_DIR=/var/lib/ca
CA_KEY="$CA_DIR/ca.key"          # KEY-02
CA_CRT="$CA_DIR/ca.crt"          # CERT-02
ISSUED="$CA_DIR/issued"
DAYS=90                          # leaves are short-lived; the root is not

if [ $# -lt 2 ]; then
    echo "usage: sign-leaf <csr-file> <fqdn> [additional-dns-name ...]" >&2
    exit 2
fi

CSR="$1"; FQDN="$2"; shift 2

[ -r "$CSR" ]    || { echo "sign-leaf: cannot read CSR: $CSR" >&2; exit 1; }
[ -r "$CA_KEY" ] || { echo "sign-leaf: cannot read KEY-02. Run as the 'ca' user." >&2; exit 1; }

# The FQDN is always the first SAN entry. Extra names are appended, which is
# how db01 keeps answering to the short name compose gives it as well as to
# the name the ledger assigned it.
SAN="DNS:$FQDN"
for name in "$@"; do
    SAN="$SAN,DNS:$name"
done

EXT=$(mktemp)
trap 'rm -f "$EXT"' EXIT
cat > "$EXT" <<EOF
subjectAltName=$SAN
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
EOF

OUT="$ISSUED/$FQDN.crt"

openssl x509 -req \
    -in "$CSR" \
    -CA "$CA_CRT" -CAkey "$CA_KEY" -CAcreateserial \
    -days "$DAYS" -sha256 \
    -extfile "$EXT" \
    -out "$OUT" 2>/dev/null

# Every certificate this CA signs is kept. A CA that cannot enumerate what
# it has issued cannot answer the first question asked after a compromise.
chmod 0644 "$OUT"

# Print what was actually produced rather than reporting success. The SAN is
# the field that decides whether a client will accept this, so it is the
# field the operator has to see.
echo "issued: $OUT"
openssl x509 -in "$OUT" -noout -serial -subject -dates
openssl x509 -in "$OUT" -noout -ext subjectAltName
