# HOST-06 pub01, the publication point.
#
# The smallest machine in the build, and the first one whose compromise costs
# nothing at all. It holds no key, no certificate, no PIN and no token. Every
# file it serves is public by construction and signed by somebody else.
#
# WHY IT EXISTS, given that hsm01 already serves these files. So that nothing
# except this machine ever has to reach hsm01. A publication point is read by
# every client in the estate, on a schedule, forever; the machine holding the
# signing key should not be the one absorbing that. In a real estate this is a
# CDN or a bucket, and the CA pushes to it and runs no listener at all.
#
# WHY IT VALIDATES NOTHING. It is a cache. If it checked signatures, somebody
# would eventually rely on the fact that it checked, and the whole design rests
# on clients verifying content rather than trusting a channel or a host. A
# publication point that is trusted is a publication point that has to be
# secured; this one does not, which is why it can be thrown away and rebuilt at
# any time without a ceremony.
FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

# python3 for the two scripts, ca-certificates because Debian is unhappy
# without it. No openssl: this machine has no reason to inspect what it
# serves, and not installing the tool is the clearest way to say so.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      python3 \
      ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# ACC-11. Runs SVC-04 and owns what it publishes. It cannot write to the
# scripts it runs, which is the same split every other service here has.
RUN useradd --system --home-dir /srv/pub --shell /usr/sbin/nologin pub

# /srv/pub is world readable on purpose. Everything in it is public: a
# revocation list, a root certificate and an intermediate. A file mode
# protecting a published certificate would be a mode protecting nothing while
# suggesting otherwise.
RUN mkdir -p /srv/pub \
 && chown -R pub:pub /srv/pub \
 && chmod 0755 /srv/pub \
 && touch /var/log/pubd.out /var/log/pull-artifacts.out \
 && chown pub:pub /var/log/pubd.out /var/log/pull-artifacts.out \
 && chmod 0644 /var/log/pubd.out /var/log/pull-artifacts.out

# Both log files exist and are owned before anything starts, because the
# shell performs `>>/var/log/...` as the unprivileged user and /var/log is
# root owned. Chapter 01, Chapter 02 section 4.4 and Chapter 07 all lost time
# to this; it is written into the image here so a fourth chapter does not.

COPY pubd.py            /usr/local/bin/pubd
COPY pull-artifacts.py  /usr/local/bin/pull-artifacts
COPY entrypoint.sh      /usr/local/bin/entrypoint.sh

RUN chmod 0755 /usr/local/bin/pubd /usr/local/bin/pull-artifacts \
               /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
