#!/bin/sh
# Record what every machine in this estate actually contains.
#
#   ./capture-state.sh [output-file]
#
# Run from this chapter's lab/ folder, against the running lab. Writes a
# report to state-capture.txt unless told otherwise.
#
# WHY THIS EXISTS. Chapter 14 moves workloads onto a new substrate, and a
# machine that is rebuilt starts from its image with none of the accounts,
# file modes, database rows, tokens, issued certificates or deliberate debris
# the chapters put inside it. Before that happens the build needs a record of
# what is there.
#
# WHY IT IS A TOOL AND NOT A DOCUMENT. A hand-written inventory is a guess
# about a system nobody measured, which is D-040's exact shape and the
# mistake this build has made more than once. This reads the machines.
#
# WHAT IT IS CAREFUL ABOUT.
#
# It is READ ONLY. Nothing here writes to a container, starts a process, or
# touches the token. `rootca` is deliberately left Exited: a capture that
# starts the offline root to look inside it has opened the window OT-029 is
# about, for a report.
#
# It records ABSENCE as well as presence. A missing file is a fact, and a
# report that only lists what it found cannot be used to check a rebuild.
#
# It NEVER prints a secret. PINs, private keys and the secret store's values
# are recorded by path, mode, owner and size, never by content. A state
# capture that leaks the estate's PINs into a text file has traded one
# problem for a worse one.

set -u

OUT="${1:-state-capture.txt}"
MACHINES="dev01 db01 ca01 hsm01 pub01 rootca"

# Paths worth recording per machine: what the chapters created, and what
# would have to exist again after a rebuild.
paths_for() {
    case "$1" in
    dev01)  echo "/opt/paymentsvc /opt/paymentsvc/config.yaml /opt/paymentsvc/paymentsvc.py \
                  /opt/paymentsvc/ca.crt /opt/paymentsvc/ca-bundle.pem /opt/paymentsvc/crontab \
                  /var/lib/paymentsvc /var/lib/paymentsvc/client.crt /var/lib/paymentsvc/client.key \
                  /var/lib/fetch-crl /var/lib/fetch-crl/crl.pem /var/lib/fetch-crl/state.json \
                  /opt/secretstore/secretstore.py /etc/secretstore/policy.json \
                  /var/lib/secretstore/secrets.json /var/log/paymentsvc.log" ;;
    db01)   echo "/etc/postgresql/15/main/server.crt /etc/postgresql/15/main/server.key \
                  /etc/postgresql/15/main/ca-bundle.pem /etc/postgresql/15/main/pg_hba.conf \
                  /var/lib/postgresql/crl/crl.pem /var/lib/postgresql/crontab" ;;
    ca01)   echo "/opt/ca-client/ca.crt /opt/ca-client/ca01.crt /opt/ca-client/ca01.key \
                  /opt/ca-client/issued /opt/ca-client/requests" ;;
    hsm01)  echo "/var/lib/ca/ica.crt /var/lib/ca/ca.crt /var/lib/ca/signd.crt \
                  /var/lib/ca/signd.key /var/lib/ca/ica-pin /var/lib/ca/ica-so-pin \
                  /var/lib/ca/ca.cnf /var/lib/ca/db/index.txt /var/lib/ca/db/crlnumber \
                  /var/lib/ca/crl.pem /var/lib/ca/root-crl.pem /var/lib/ca/issued \
                  /etc/signd/policy.json /var/log/signd-audit.log" ;;
    pub01)  echo "/srv/pub/crl.pem /srv/pub/ca-bundle.pem /srv/pub/crontab" ;;
    rootca) echo "/var/lib/rootca/root.crt /var/lib/rootca/pin /var/lib/rootca/so-pin \
                  /var/lib/rootca/root.cnf /var/lib/rootca/root-crl.pem \
                  /var/lib/rootca/ceremony.log" ;;
    esac
}

running() {
    docker ps --filter "name=^$1$" --format '{{.Names}}' 2>/dev/null | grep -qx "$1"
}

section() { printf '\n========== %s ==========\n' "$1"; }

{
printf 'STATE CAPTURE  %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'Read only. No container is started, stopped or modified.\n'
printf 'No secret value is recorded: PINs and keys appear by path, mode and size only.\n'

section "containers"
docker ps -a --format '{{.Names}}\t{{.Status}}\t{{.Image}}' 2>/dev/null | sort

for m in $MACHINES; do
    section "$m"
    if ! running "$m"; then
        printf 'NOT RUNNING. Nothing below was measured.\n'
        if [ "$m" = "rootca" ]; then
            printf 'This is correct for rootca: Exited is its steady state, and starting it\n'
            printf 'to take a census would open the window OT-029 exists to keep shut.\n'
            printf 'What it contains is recorded in the ledger and in its ceremony log,\n'
            printf 'which is the one place this capture trusts a document over a measurement.\n'
        fi
        continue
    fi

    printf -- '--- packages ---\n'
    docker exec "$m" sh -c 'dpkg-query -W -f="${Package} ${Version}\n" 2>/dev/null | sort' \
        2>/dev/null | head -60

    printf -- '--- accounts (non-system logins and service accounts) ---\n'
    docker exec "$m" sh -c \
        'awk -F: "\$3 >= 100 && \$1 != \"nobody\" {print \$1, \$3, \$4, \$6, \$7}" /etc/passwd' 2>/dev/null
    printf -- '--- group membership that matters ---\n'
    docker exec "$m" sh -c 'getent group softhsm ssl-cert 2>/dev/null' 2>/dev/null

    printf -- '--- paths ---\n'
    for p in $(paths_for "$m"); do
        docker exec "$m" sh -c "
            if [ -e '$p' ]; then
                stat -c '%n  %A  %U:%G  %s bytes' '$p'
            else
                echo '$p  ABSENT'
            fi" 2>/dev/null
    done

    printf -- '--- processes started by hand ---\n'
    docker exec "$m" sh -c '
        for d in /proc/[0-9]*; do
            [ -r "$d/cmdline" ] || continue
            c=$(tr "\0" " " < "$d/cmdline")
            case "$c" in
              *paymentsvc.py*|*secretstore.py*|*signd*|*pubd*|*pull-artifacts*|*cron*|*postgres*)
                echo "  ${d#/proc/}  $c" ;;
            esac
        done' 2>/dev/null | sort -k2 | head -20

    printf -- '--- scheduled work ---\n'
    docker exec "$m" sh -c '
        for u in paymentsvc postgres signd pub; do
            out=$(crontab -l -u "$u" 2>/dev/null | grep -v "^#" | grep -v "^$")
            [ -n "$out" ] && echo "  [$u] $out"
        done' 2>/dev/null

    printf -- '--- certificates held ---\n'
    for p in $(paths_for "$m"); do
        case "$p" in *.crt|*.pem)
            docker exec "$m" sh -c "
                if [ -r '$p' ] && grep -q 'BEGIN CERTIFICATE' '$p' 2>/dev/null; then
                    printf '  %s\n' '$p'
                    openssl x509 -in '$p' -noout -subject -issuer -enddate 2>/dev/null \
                      | sed 's/^/      /'
                fi" 2>/dev/null ;;
        esac
    done
done

section "PKCS#11 tokens"
printf 'Recorded by label and object attributes. No PIN is printed and no key is touched.\n'
if running hsm01; then
    docker exec -u signd hsm01 sh -c '
        softhsm2-util --show-slots 2>/dev/null | grep -E "^Slot|    Label:" | sed "s/^/  /"
        echo "  --- objects in ica-token ---"
        pkcs11-tool --module /usr/lib/softhsm/libsofthsm2.so --token-label ica-token \
            --login --pin "$(cat /var/lib/ca/ica-pin)" --list-objects 2>/dev/null \
            | grep -E "label|Access|ID" | sed "s/^/    /"' 2>/dev/null
else
    printf 'hsm01 not running.\n'
fi
printf 'rootca holds root-token with KEY-05. Not measured: the machine is Exited\n'
printf 'and starting it for a census is not a good enough reason.\n'

section "database"
if running db01; then
    docker exec db01 su postgres -c \
        "psql -tAc \"SELECT rolname, rolcanlogin, rolpassword IS NOT NULL AS has_password \
         FROM pg_authid WHERE oid > 16383 ORDER BY rolname\"" 2>/dev/null | sed 's/^/  role  /'
    docker exec db01 su postgres -c \
        "psql -d paymentsdb -tAc \"SELECT count(*) FROM payments\"" 2>/dev/null \
        | sed 's/^/  payments rows  /'
    docker exec db01 grep -E '^(host|hostssl|local)' /etc/postgresql/15/main/pg_hba.conf \
        2>/dev/null | sed 's/^/  pg_hba  /'
else
    printf 'db01 not running.\n'
fi

section "the deliberate debris"
printf 'Things the chapters left on purpose, which a rebuild would silently clean up.\n'
if running dev01; then
    docker exec dev01 sh -c '
        if [ -r /var/log/paymentsvc.log ]; then
            n=$(grep -c "SEC-01\|hunter2\|password=" /var/log/paymentsvc.log 2>/dev/null || echo 0)
            echo "  /var/log/paymentsvc.log: $n line(s) matching the Chapter 01 leak pattern"
        else
            echo "  /var/log/paymentsvc.log ABSENT"
        fi' 2>/dev/null
fi

section "end"
printf 'What this capture CANNOT record, and Chapter 13 section 6 is about:\n'
printf '  the private keys themselves, which is the point of them;\n'
printf '  what is inside a token, beyond the attributes above;\n'
printf '  and therefore the estate cannot be rebuilt from this file alone.\n'
} > "$OUT" 2>&1

echo "wrote $OUT ($(wc -l < "$OUT") lines)"
echo "Nothing was started, stopped or modified."
