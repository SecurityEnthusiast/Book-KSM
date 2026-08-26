#!/bin/sh
# The signing half of PROC-04, the intermediate issuance ceremony. Signs one
# certificate authority with KEY-05.
#
#   sign-ca <csr-file> <common-name>
#
# This is the only signing tool on this machine, and it can only produce a
# CA. There is no flag to make it emit a leaf and no sign-leaf beside it to
# borrow. That is deliberate: the root's job is to sign exactly one thing
# every few years, and a tool that can only do that job cannot be talked
# into doing another one at three in the morning. hsm01 has the mirror,
# where sign-leaf stamps CA:FALSE and cannot mint an authority. D-063.
#
# WHY -extfile AND NOT -addext. `openssl x509 -req` has no -addext; it
# rejects the option outright with "Extra (unknown) options". Extensions on
# a signed certificate come from an extension file, which is also why
# sign-leaf has always used one. It is worth knowing because the two
# subcommands look interchangeable and are not: `req` takes -addext,
# `x509 -req` takes -extfile.
#
# WHAT THE INTERMEDIATE GETS, and why it is not what the root has:
#
#   pathlen:0   The intermediate may sign leaves and may not sign another
#               authority. The root is pathlen:1, meaning one CA may follow
#               it. Together those two numbers say "exactly this hierarchy
#               and no deeper", and a certificate that says so is a
#               certificate that cannot be extended by whoever holds it.

set -eu

DIR=/var/lib/rootca
ROOT_CRT="$DIR/root.crt"        # CERT-08, public, an ordinary file
ISSUED="$DIR/issued"
DAYS=1825                       # five years: longer than a leaf because
                                # replacing it is a project, shorter than
                                # the root because replacing it is possible.
                                # D-065.

MODULE=/usr/lib/softhsm/libsofthsm2.so
TOKEN=root-token
LABEL=root-key
PIN_FILE=$DIR/pin               # SEC-06

if [ $# -ne 2 ]; then
    echo "usage: sign-ca <csr-file> <common-name>" >&2
    exit 2
fi
CSR="$1"; CN="$2"

[ -r "$CSR" ]      || { echo "sign-ca: cannot read CSR: $CSR" >&2; exit 1; }
[ -r "$ROOT_CRT" ] || { echo "sign-ca: cannot read CERT-08: $ROOT_CRT. Run root-init first." >&2; exit 1; }
[ -r "$PIN_FILE" ] || { echo "sign-ca: cannot read the PIN. Run as the 'rootca' user." >&2; exit 1; }
PIN=$(cat "$PIN_FILE")

# Refuse a request whose subject is not the name we were told to sign. The
# root signs so rarely that every field is worth checking by hand, and this
# check is what stops a ceremony from signing the wrong request because two
# CSRs were in the directory.
CSR_CN=$(openssl req -in "$CSR" -noout -subject -nameopt multiline \
         | sed -n 's/ *commonName *= *//p')
if [ "$CSR_CN" != "$CN" ]; then
    echo "sign-ca: the request says CN=$CSR_CN, you asked for CN=$CN. Refusing." >&2
    exit 1
fi

KEY_URI="pkcs11:token=$TOKEN;object=$LABEL;type=private?pin-value=$PIN"

EXT=$(mktemp)
trap 'rm -f "$EXT"' EXIT
cat > "$EXT" <<EOF
basicConstraints=critical,CA:TRUE,pathlen:0
keyUsage=critical,keyCertSign,cRLSign
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always
EOF

OUT="$ISSUED/$CN.crt"

openssl x509 -req \
    -in "$CSR" \
    -CA "$ROOT_CRT" \
    -engine pkcs11 -CAkeyform engine -CAkey "$KEY_URI" \
    -CAcreateserial \
    -days "$DAYS" -sha256 \
    -extfile "$EXT" \
    -out "$OUT" 2>/dev/null

chmod 0644 "$OUT"

# Print the fields, not a success message. The two extensions below are the
# entire difference between an intermediate and a very long-lived leaf, and
# an operator who signs one certificate every five years should read them.
echo "issued: $OUT"
openssl x509 -in "$OUT" -noout -serial -subject -issuer -dates
openssl x509 -in "$OUT" -noout -ext basicConstraints,keyUsage

date -u +"%Y-%m-%dT%H:%M:%SZ  signed CA $CN, serial $(openssl x509 -in "$OUT" -noout -serial | cut -d= -f2)" \
    >> "$DIR/ceremony.log"
