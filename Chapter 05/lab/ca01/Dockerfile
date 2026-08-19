# HOST-03 ca01, the certificate authority.
#
# Compare this with db01/Dockerfile. That machine runs a database and needs
# a database's dependencies. This one signs things. It has openssl and it
# has nothing else, because every package installed here is another way to
# reach KEY-02, and KEY-02 forges any identity in the estate.
FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      openssl \
      ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# ACC-08. The identity that owns KEY-02 and is the only one that may use it.
# System account, no login shell, exactly as ACC-03 and ACC-04 were created.
RUN useradd --system --home-dir /var/lib/ca --shell /usr/sbin/nologin ca

# /var/lib/ca   the authority's own state: KEY-02, CERT-02, the serial file
# /var/lib/ca/issued  a copy of every certificate this CA has ever signed
#
# 0700 on both. A CA that cannot say what it has issued cannot answer the
# only question that matters after a compromise, which is "what is out
# there signed by me".
RUN mkdir -p /var/lib/ca/issued \
 && chown -R ca:ca /var/lib/ca \
 && chmod 0700 /var/lib/ca /var/lib/ca/issued

COPY sign-leaf.sh  /usr/local/bin/sign-leaf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# Pinned rather than inherited from your umask, for the same reason
# Chapter 01 pinned the modes on dev01: a file mode that depends on who
# built the image is not a file mode anyone chose.
RUN chmod 0755 /usr/local/bin/sign-leaf /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
