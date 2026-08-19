#!/bin/sh
set -e

pg_ctlcluster 15 main start

# wait for the cluster to accept connections
i=0
while [ $i -lt 30 ]; do
    su postgres -c "psql -tAc 'SELECT 1'" >/dev/null 2>&1 && break
    i=$((i + 1))
    sleep 1
done

if [ ! -f /var/lib/postgresql/.initialised ]; then
    su postgres -c "psql -v ON_ERROR_STOP=1 -f /opt/paymentsvc/initdb.sql"
    touch /var/lib/postgresql/.initialised
fi

# the application's log file, with the permissions an application log
# almost always has in the real world
touch /var/log/paymentsvc.log /var/log/paymentsvc.out
chown paymentsvc:paymentsvc /var/log/paymentsvc.log /var/log/paymentsvc.out
chmod 0644 /var/log/paymentsvc.log /var/log/paymentsvc.out

echo "dev01 ready, PostgreSQL is up."
exec sleep infinity
