#!/bin/sh
set -e

# db01 carries no application and seeds no data. Chapter 04 migrates the
# database here from dev01 with pg_dump, so this only has to bring an empty
# cluster up and leave it accepting connections. Nothing here re-runs
# initdb.sql: that file would recreate paymentsvc as a LOGIN role holding
# the credential Chapter 02 retired.

pg_ctlcluster 15 main start

i=0
while [ $i -lt 30 ]; do
    su postgres -c "psql -tAc 'SELECT 1'" >/dev/null 2>&1 && break
    i=$((i + 1))
    sleep 1
done

echo "db01 ready, PostgreSQL is up."
exec sleep infinity
