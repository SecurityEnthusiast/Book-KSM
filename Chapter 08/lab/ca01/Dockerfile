# HOST-03 ca01, the machine that requests certificates.
#
# Read this against the Chapter 06 version, because the diff is the chapter.
# That image installed softhsm2, opensc and the PKCS#11 engine, created a
# token directory, and joined the `softhsm` group. None of that is here.
#
# The key, the PIN and the signing all moved to HOST-04 in Chapter 07, so
# what is left on this host is a client: openssl to build a request, curl to
# send it, and a certificate proving who is asking. Root here can read all
# of that, which is enough to ASK for a certificate and not enough to issue
# one. That difference is what OT-026 was about.
FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      openssl \
      ca-certificates \
      curl \
 && rm -rf /var/lib/apt/lists/*

# ACC-08, unchanged in name and reduced in power. It owned a signing key in
# Chapter 06 and owns a client credential now. The ID stays because the
# identity is the same one, which is D-002 doing its job: what changed is
# what it can do, not who it is.
RUN useradd --system --home-dir /opt/ca-client --shell /usr/sbin/nologin ca

# /opt/ca-client   CERT-05 (the anchor we verify the service against),
#                  CERT-07 and its key (what we present to prove who we are).
#
# 0755, and only the key is restricted. Everything else here is a
# certificate, and a certificate is public by construction.
RUN mkdir -p /opt/ca-client/requests \
 && chown -R ca:ca /opt/ca-client \
 && chmod 0755 /opt/ca-client /opt/ca-client/requests

COPY request-cert.sh /usr/local/bin/request-cert
COPY entrypoint.sh   /usr/local/bin/entrypoint.sh

# Pinned rather than inherited from your umask, for the same reason
# Chapter 01 pinned the modes on dev01: a file mode that depends on who
# built the image is not a file mode anyone chose.
RUN chmod 0755 /usr/local/bin/request-cert /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
