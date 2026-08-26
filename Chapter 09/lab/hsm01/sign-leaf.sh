#!/bin/sh
# PROC-02, the issuing half. Signs a certificate request with KEY-06.
#
#   sign-leaf [--client] <csr-file> <fqdn> [additional-dns-name ...]
#
# Chapter 08 changes three lines and none of them are interesting on their
# own: the token label, the key label, and the certificate this signs
# against. What they add up to is that this script no longer touches a root.
# It signs with an intermediate, and the root that authorised that
# intermediate is on a machine that is switched off.
#
# That is the whole point of the hierarchy. If this host is compromised
# tomorrow, an attacker gets the ability to issue certificates under
# CERT-09 until CERT-09 is replaced, and replacing it is a ceremony on
# rootca that touches no client. Before Chapter 08 the same compromise got
# them the estate's trust anchor and every client had to be visited.
#
# --client, from Chapter 07: a certificate carries extendedKeyUsage, which
# states the one job it exists to do, and a client refuses a certificate
# issued for serverAuth exactly as firmly as it refuses an untrusted one.
# The error says `unsupported certificate` and mentions neither the field
# nor the purpose, which is why this is a flag and not something to
# remember.
#
# There is still no CA_KEY variable. The key is not a file this script could
# read, so it does not read one. It hands the request to the token and the
# token hands back a signature.
#
# What this script exists to prevent is still the failure in Chapter 05
# section 6: a certificate signed with a Subject Alternative Name that does
# not contain the name the client actually dials. The Common Name is not
# consulted when a SAN is present, so a leaf whose CN is perfect and whose
# SAN is wrong is rejected, and the error says nothing about the CN.
#
# And it can only ever produce CA:FALSE. There is no flag here that makes an
# authority, just as there is no flag on rootca's sign-ca that makes a leaf.
# D-063.

set -eu

CA_DIR=/var/lib/ca
CA_CRT="$CA_DIR/ica.crt"         # CERT-09, the intermediate. Public, an
                                 # ordinary file, and the thing every leaf
                                 # this script signs must be presented with.
ISSUED="$CA_DIR/issued"
DAYS=90                          # leaves are short-lived; the root is not

MODULE=/usr/lib/softhsm/libsofthsm2.so
TOKEN=ica-token
LABEL=ica-key
PIN_FILE=/var/lib/ca/ica-pin    # SEC-08

EKU=serverAuth
if [ "${1:-}" = "--client" ]; then
    EKU=clientAuth
    shift
fi

if [ $# -lt 2 ]; then
    echo "usage: sign-leaf [--client] <csr-file> <fqdn> [additional-dns-name ...]" >&2
    exit 2
fi

CSR="$1"; FQDN="$2"; shift 2

[ -r "$CSR" ]      || { echo "sign-leaf: cannot read CSR: $CSR" >&2; exit 1; }
[ -r "$CA_CRT" ]   || { echo "sign-leaf: cannot read CERT-09: $CA_CRT" >&2; exit 1; }
[ -r "$PIN_FILE" ] || { echo "sign-leaf: cannot read the PIN. Run as the 'signd' user." >&2; exit 1; }
PIN=$(cat "$PIN_FILE")

# The token is addressed by label, never by slot: SoftHSM assigns slot
# numbers at random on every init, so a hard-coded slot works once, on one
# machine. There are two tokens on this host during the overlap, which is
# exactly when addressing by slot would have picked the wrong one. The URI
# must be quoted or the shell eats the ; and the ?.
KEY_URI="pkcs11:token=$TOKEN;object=$LABEL;type=private?pin-value=$PIN"

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
extendedKeyUsage=$EKU
EOF

OUT="$ISSUED/$FQDN.crt"

# -CAkeyform engine is what redirects the signature into the token. The
# private key never enters this process; openssl sends the bytes to be
# signed and gets a signature back.
openssl x509 -req \
    -in "$CSR" \
    -CA "$CA_CRT" \
    -engine pkcs11 -CAkeyform engine -CAkey "$KEY_URI" \
    -CAcreateserial \
    -days "$DAYS" -sha256 \
    -extfile "$EXT" \
    -out "$OUT" 2>/dev/null

chmod 0644 "$OUT"

# Chapter 08 adds this file and it is the one operational cost of the
# hierarchy. A leaf signed by an intermediate does not verify against the
# root on its own: the verifier has to be given the intermediate as well.
# Writing the chain out here, next to the leaf, means the only file anyone
# has to remember to install is the one that already works.
cat "$OUT" "$CA_CRT" > "$ISSUED/$FQDN.chain.crt"
chmod 0644 "$ISSUED/$FQDN.chain.crt"

# Print what was actually produced rather than reporting success. The SAN is
# the field that decides whether any client will accept this certificate, so
# it is the field the operator has to see.
echo "issued: $OUT"
echo "chain:  $ISSUED/$FQDN.chain.crt"
openssl x509 -in "$OUT" -noout -serial -subject -issuer -dates
openssl x509 -in "$OUT" -noout -ext subjectAltName,extendedKeyUsage
