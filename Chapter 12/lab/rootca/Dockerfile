# HOST-05 rootca, the machine that holds the root key and is almost never
# running.
#
# Compare it with hsm01, which is already the smallest machine in the build.
# This one is smaller. hsm01 holds a key AND answers a network request AND
# runs a policy engine, because something has to issue certificates all day.
# This machine issues one certificate every few years, so it needs none of
# that: no python3, no service, no listening socket, and in the compose file
# no network at all.
#
# The interesting property is not in this file. It is that the container
# built from it spends its life in state `Exited`, and is started only for
# the length of a ceremony. That is what "offline" can honestly mean when
# every machine in the lab is a container on one laptop, and D-060 is where
# the limits of that claim are written down.
FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

# The same three packages Chapter 06 introduced, and nothing else. There is
# deliberately no curl and no python3: this host has nothing to talk to.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      openssl \
      ca-certificates \
      softhsm2 \
      opensc \
      libengine-pkcs11-openssl \
 && rm -rf /var/lib/apt/lists/*

# ACC-10. A third account that owns a token, on a third machine, and the
# reason it is not ACC-09 is D-002: this is a different principal on a
# different host, and the whole point of the chapter is that the two are
# not the same and must not be able to act for each other.
RUN useradd --system --home-dir /var/lib/rootca --shell /usr/sbin/nologin rootca \
 && usermod -aG softhsm rootca

# /var/lib/rootca          CERT-08 and the ceremony log
# /var/lib/rootca/issued   every CA certificate this root has ever signed.
#                          There will be one. That is the measure of the
#                          chapter: a root that signs once is a root whose
#                          log you can read in full.
# /var/lib/rootca/requests incoming CSRs, for the reason hsm01's Dockerfile
#                          gives: a request that arrives in a world-writable
#                          directory can be swapped between landing and
#                          being signed.
RUN mkdir -p /var/lib/rootca/issued /var/lib/rootca/requests \
 && chown -R rootca:rootca /var/lib/rootca \
 && chmod 0700 /var/lib/rootca /var/lib/rootca/issued /var/lib/rootca/requests

COPY root-init.sh  /usr/local/bin/root-init
COPY sign-ca.sh    /usr/local/bin/sign-ca
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod 0755 /usr/local/bin/root-init /usr/local/bin/sign-ca \
               /usr/local/bin/entrypoint.sh

# There is no sign-leaf here, and its absence is a control rather than an
# omission. The only tool this machine has stamps CA:TRUE on everything it
# signs, so the root cannot issue a server certificate by accident even if
# somebody starts the container and asks it to. hsm01 has the mirror of
# this: sign-leaf stamps CA:FALSE and has no way to produce an authority.
# D-063.

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
