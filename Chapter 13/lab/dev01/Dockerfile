FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        postgresql-15 \
        python3 python3-yaml python3-psycopg2 \
        procps psmisc iproute2 tcpdump curl less nano ca-certificates \
        cron \
    && rm -rf /var/lib/apt/lists/*

# `cron` arrived in Chapter 11, installed into the running container because
# hsm01 could not be rebuilt and the estate had to stay consistent. It is in
# the recipe now. That is the whole point of the reconciliation pass: a
# Dockerfile that does not build the machine it names is documentation of a
# system that does not exist.

# belt and braces: the Debian package normally creates the main cluster on
# install, but that step relies on an init system we do not have in a build
# container. Create it if it is missing.
RUN pg_lsclusters | grep -q '^15 *main' || pg_createcluster 15 main

# the identity the application will eventually run as. It exists from the
# start because the log file needs an owner; nothing runs as it until §7.
RUN useradd --system --home-dir /opt/paymentsvc --shell /usr/sbin/nologin paymentsvc

# ACC-04 and ACC-07, created in Chapters 02 and 03 and absent from this file
# until now. ACC-07 runs nothing and exists so that Chapter 03 can prove the
# store tells two plausible service identities apart; a policy that has never
# refused anybody has not been tested.
RUN useradd --system --home-dir /var/lib/secretstore --shell /usr/sbin/nologin secretstore \
 && useradd --system --home-dir /nonexistent --shell /usr/sbin/nologin reportsvc

COPY app/paymentsvc.py /opt/paymentsvc/paymentsvc.py
COPY app/config.yaml   /opt/paymentsvc/config.yaml
COPY initdb.sql        /opt/paymentsvc/initdb.sql
COPY entrypoint.sh     /usr/local/bin/entrypoint.sh

# SVC-02, from Chapter 02. This directory has been in lab/dev01/ since that
# chapter and this file has never copied it, which is the complaint OT-020
# was raised for.
COPY secretstore/secretstore.py     /opt/secretstore/secretstore.py
COPY secretstore/secretstore-set.py /usr/local/bin/secretstore-set
COPY secretstore/policy.json        /etc/secretstore/policy.json

# The revocation agent, Chapter 10, and the thing that asks whether its
# output is any good, Chapter 11.
COPY fetch-crl.py  /usr/local/bin/fetch-crl
COPY crl-status.py /usr/local/bin/crl-status
COPY crontab       /opt/paymentsvc/crontab

# COPY reproduces whatever mode the file had on your laptop, and that is
# decided by your umask: 0644 under the common 022, 0664 under 002. Pin it,
# so section 3.1 shows you the same thing it shows everyone else. An image
# whose file modes depend on who built it is a bad image regardless.
# Directories the workload OWNS, as opposed to directories it merely reads.
#
# /opt/paymentsvc is root-owned so APP-01 cannot rewrite its own
# configuration, which has been true since Chapter 01. Anything the workload
# must CREATE or REPLACE therefore lives elsewhere: an atomic replace needs
# write permission on the directory, not on the file. Chapter 10 found this
# with the CRL and Chapter 12 found it again with the client key.
RUN mkdir -p /var/lib/fetch-crl /var/lib/paymentsvc /var/lib/secretstore /etc/secretstore \
 && chown paymentsvc:paymentsvc /var/lib/fetch-crl /var/lib/paymentsvc \
 && chown secretstore:secretstore /var/lib/secretstore \
 && chmod 0755 /var/lib/fetch-crl \
 && chmod 0700 /var/lib/paymentsvc \
 && chmod 0700 /var/lib/secretstore \
 && touch /var/log/secretstore.out /var/log/secretstore-access.log \
 && chown secretstore:secretstore /var/log/secretstore.out /var/log/secretstore-access.log \
 && chmod 0644 /var/log/secretstore.out \
 && chmod 0600 /var/log/secretstore-access.log

RUN chmod 0755 /usr/local/bin/fetch-crl /usr/local/bin/crl-status \
               /usr/local/bin/secretstore-set \
 && chmod 0644 /opt/secretstore/secretstore.py /etc/secretstore/policy.json \
 && chown paymentsvc:paymentsvc /opt/paymentsvc/crontab

RUN chmod 0644 /opt/paymentsvc/paymentsvc.py \
               /opt/paymentsvc/config.yaml \
               /opt/paymentsvc/initdb.sql \
 && chmod 0755 /usr/local/bin/entrypoint.sh

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
