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

# CHAPTER 14: BREAK GLASS.
#
# SVC-03 checks revocation on every connection. This host holds the only
# credential SVC-03 accepts, so revoking it removes the only way to ask for
# a replacement. Chapter 14 section 6 demonstrates exactly that, and the way
# back was a human on hsm01 signing by hand.
#
# CERT-12 is a SEPARATE IDENTITY, ca01-bg.lab.simurgh.example, and not a
# second certificate for this one. That distinction is the whole design.
#
# POL-02 grants it exactly one power: request ca01.lab.simurgh.example.
# It cannot ask for db01, it cannot ask for paymentsvc, and it cannot ask
# for itself. The only thing it can do is put the operator back.
#
# WHY NOT JUST LET ca01 REQUEST ITS OWN NAME. Because then revoking the
# operator's certificate would stop meaning anything: a compromised ca01
# would simply issue itself a fresh one. Revocation of an operator has to
# be able to actually remove that operator, so self-renewal is the one
# grant POL-02 must never make.
#
# Being a separate identity, break-glass can also be revoked on its own,
# which is what gives you a real lockout on the day you want one.
#
# WHAT THIS DOES NOT BUY. The break-glass key lives on this host beside the
# primary, so anyone who compromises ca01 gets both. It closes the lockout,
# which is an availability problem. It does nothing for compromise. A real
# one lives somewhere this host cannot reach, and that is the same gap
# AR-004 records about "offline".

# Chapter 12 adds --client, mirroring the flag sign-leaf has had since
# Chapter 07. It was never reachable from here, so every certificate this
# API has ever issued has been a server certificate, and the first client
# one requested through it was refused by PostgreSQL with `sslv3 alert
# unsupported certificate`.
USAGE=server
while [ $# -gt 0 ]; do
    case "${1:-}" in
    --client)
        USAGE=client; shift ;;
    --break-glass)
        # See BREAK GLASS above. Order does not matter: this loop takes the
        # flags in either order, because an operator reaching for this one is
        # having a bad day already.
        CLIENT_CRT=$DIR/break-glass/ca01-bg.crt
        CLIENT_KEY=$DIR/break-glass/ca01-bg.key
        shift
        echo "request-cert: USING THE BREAK-GLASS CREDENTIAL (CERT-12)." >&2
        echo "  Issue a replacement for the primary, then stop using this one." >&2 ;;
    --*)
        echo "request-cert: unknown option $1" >&2; exit 2 ;;
    *)
        break ;;
    esac
done

if [ $# -lt 2 ]; then
    echo "usage: request-cert [--client] [--break-glass] <csr-file> <fqdn> [dns-name ...]" >&2
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
BODY=$(printf '{"csr": "%s", "fqdn": "%s", "alt_names": [%s], "usage": "%s"}' \
  "$(sed ':a;N;$!ba;s/\n/\\n/g' "$CSR")" "$FQDN" "$ALT" "$USAGE")

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

echo "usage: $USAGE"
echo "leaf:  $ISSUED/$FQDN.crt"
echo "chain: $ISSUED/$FQDN.chain.crt   <- install this one"
openssl x509 -in "$ISSUED/$FQDN.crt" -noout -subject -issuer -dates
