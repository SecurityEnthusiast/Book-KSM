# HOST-04 hsm01, the machine that holds the key and signs.
#
# This is the smallest machine in the build and that is the point. It holds
# KEY-04 and answers one question: "sign this". Everything a general purpose
# host carries is another way to reach the key, so nothing a general purpose
# host carries is installed. There is no application, no database, no secret
# store, no curl and no editor.
#
# Compare it with ca01 as Chapter 06 left it. That machine held the key AND
# ran the issuing procedure AND was where an operator worked. Chapter 07
# splits those, because OT-026 is about what root on a busy host can take.
FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

# Chapter 06 adds three packages and they are worth naming separately:
#
#   softhsm2                  the token itself, a PKCS#11 implementation in
#                             software. Honest about being software, which
#                             is exactly why we start here.
#   opensc                    gives us pkcs11-tool, the way to talk to a
#                             token directly rather than through openssl.
#   libengine-pkcs11-openssl  the bridge. Lets openssl use a key it cannot
#                             read, by asking the token to sign instead.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      openssl \
      ca-certificates \
      softhsm2 \
      opensc \
      libengine-pkcs11-openssl \
      python3 \
      cron \
 && rm -rf /var/lib/apt/lists/*

# ACC-09. The identity that owns the token on THIS host and runs SVC-03.
# ACC-08 stays behind on ca01 and no longer has a key to own.
RUN useradd --system --home-dir /var/lib/ca --shell /usr/sbin/nologin signd \
 && usermod -aG softhsm signd

# The softhsm2 package gates /etc/softhsm and /var/lib/softhsm on the
# `softhsm` GROUP, mode 0750 and 2770, not on ownership. Chowning them to
# `ca` would fight the package and break on the next upgrade. Joining the
# group is how the platform intends this to work, and it is worth noticing
# what that means: membership of a Unix group is the access control on the
# signing key. That is OT-025.

# /var/lib/ca          CERT-04 and the record of what has been issued
# /var/lib/ca/issued   a copy of every certificate this CA has ever signed
# /var/lib/ca/requests incoming CSRs. Not /tmp: a CSR is public, so this is
#                      not about secrecy, it is that /tmp is world-writable
#                      and anything local could swap a request between it
#                      being written and being signed. On the machine that
#                      holds the key, do not hand the signer a file every
#                      process on the host can replace.
# The token itself lives under /var/lib/softhsm/tokens, which the package
# owns and which `ca` reaches through group membership above. The PINs live
# in /var/lib/ca, which `ca` owns outright, rather than in /etc/softhsm,
# which it does not.
#
# Note what is no longer here: there is no ca.key. From Chapter 06 the
# private key is not a file this Dockerfile could create, chmod or copy.
# db/ is the authority's register, added in Chapter 09. index.txt records what
# has been taken back and crlnumber is the monotonic counter that makes a
# replayed list detectable. Both start empty and neither can be reconstructed,
# which is why this directory is created and not populated.
RUN mkdir -p /var/lib/ca/issued /var/lib/ca/requests /var/lib/ca/db /etc/signd \
 && chown -R signd:signd /var/lib/ca /etc/signd \
 && chmod 0700 /var/lib/ca /var/lib/ca/issued /var/lib/ca/requests \
 && touch /var/log/signd-audit.log /var/log/signd.out \
 && chown signd:signd /var/log/signd-audit.log /var/log/signd.out \
 && chmod 0600 /var/log/signd-audit.log \
 && chmod 0644 /var/log/signd.out

# signd.out has to exist and be owned by ACC-09 BEFORE anything starts.
# /var/log is root-owned 0755, so `signd` cannot create a file in it, and
# the shell performs `>>/var/log/signd.out` as that user. If the file is
# missing the redirect fails, the process never starts, and docker exec -d
# returns success while telling you nothing. Chapter 01 hit this for
# paymentsvc.out and Chapter 02 section 4.4 hit it for secretstore.out.

COPY hsm-init.sh     /usr/local/bin/hsm-init
COPY ica-init.sh     /usr/local/bin/ica-init
COPY sign-leaf.sh    /usr/local/bin/sign-leaf
COPY signd.py        /usr/local/bin/signd
COPY stop-signd.sh   /usr/local/bin/stop-signd
COPY crl-refresh.sh  /usr/local/bin/crl-refresh
COPY revoke-cert.sh  /usr/local/bin/revoke-cert
COPY policy.json     /etc/signd/policy.json
COPY ca.cnf          /var/lib/ca/ca.cnf
COPY crontab         /var/lib/ca/crontab
COPY entrypoint.sh   /usr/local/bin/entrypoint.sh

# Pinned rather than inherited from your umask, for the same reason
# Chapter 01 pinned the modes on dev01: a file mode that depends on who
# built the image is not a file mode anyone chose.
# POL-02 is 0644 for the same reason POL-01 is: a policy holds rules, not
# values, and a rule nobody can read is a rule nobody can review. D-028.
RUN chmod 0755 /usr/local/bin/hsm-init /usr/local/bin/sign-leaf \
               /usr/local/bin/signd /usr/local/bin/entrypoint.sh \
 && chmod 0644 /etc/signd/policy.json

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
