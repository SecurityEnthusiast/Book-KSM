FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        postgresql-15 \
        openssl \
        procps iproute2 tcpdump curl less nano ca-certificates \
        python3 cron \
    && rm -rf /var/lib/apt/lists/*

# Same belt-and-braces as dev01: the Debian package normally creates the
# main cluster on install, but that step relies on an init system a build
# container does not have.
RUN pg_lsclusters | grep -q '^15 *main' || pg_createcluster 15 main

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 5432
# Chapter 12: db01 became the estate's second verifier, so it needs the
# revocation agent, somewhere to keep what it fetches, and a clock. python3
# and cron were installed into the running container at the time, for the
# reason everything else in this pass was: hsm01 cannot be rebuilt, so nothing
# is, so the recipes drifted.
COPY crontab /var/lib/postgresql/crontab

RUN mkdir -p /var/lib/postgresql/crl \
 && chown postgres:postgres /var/lib/postgresql/crl /var/lib/postgresql/crontab \
 && chmod 0755 /var/lib/postgresql/crl

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
