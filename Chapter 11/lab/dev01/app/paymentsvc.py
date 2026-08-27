#!/usr/bin/env python3
"""APP-01 paymentsvc, answers 'what is the status of payment X?'

Chapter 04 change: SVC-01 now lives on its own machine, so the database
connection crosses a network. It is made with TLS and the server
certificate is verified against a pinned copy, which is what stops anything
that answers on port 5432 from being handed our queries.

The credential still comes from SVC-02 over a Unix socket on this host, and
this process still stores no credential of its own.
"""

import http.client
import json
import logging
import os
import pwd
import socket
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import psycopg2
import yaml
from psycopg2.extras import RealDictCursor

CONFIG_PATH = os.environ.get("PAYMENTSVC_CONFIG", "/opt/paymentsvc/config.yaml")

logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[
        logging.FileHandler("/var/log/paymentsvc.log"),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger("paymentsvc")


def load_config(path):
    log.info("loading configuration from %s", path)
    with open(path) as fh:
        cfg = yaml.safe_load(fh)
    log.debug("effective configuration: %s", cfg)
    return cfg


class UnixHTTPConnection(http.client.HTTPConnection):
    """An HTTP client that speaks over a Unix domain socket.

    The only difference from an ordinary HTTPConnection is where connect()
    points. Everything above it, requests, status codes, headers, is
    unchanged, which is why moving SVC-02 off TCP cost so little here.
    """

    def __init__(self, socket_path, timeout=5):
        super().__init__("localhost", timeout=timeout)
        self.socket_path = socket_path

    def connect(self):
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(self.timeout)
        sock.connect(self.socket_path)
        self.sock = sock


def fetch_credential(socket_path, secret_name):
    """Ask SVC-02 for the current database credential.

    We present no token and assert no identity. The kernel tells the store
    our uid when we connect, and the store applies POL-01 to it. If it says
    no, we get a 403 and fail loudly, being refused is not something to
    paper over.
    """
    conn = UnixHTTPConnection(socket_path)
    try:
        conn.request("GET", f"/v1/secrets/{secret_name}")
        resp = conn.getresponse()
        body = resp.read().decode()
        if resp.status == 403:
            raise PermissionError(
                f"secretstore refused this process: {json.loads(body).get('detail')}"
            )
        if resp.status != 200:
            raise RuntimeError(f"secretstore returned {resp.status}: {body}")
        payload = json.loads(body)
    finally:
        conn.close()
    cred = json.loads(payload["value"])
    log.info("fetched %s version %s as user %s",
             secret_name, payload["version"], cred["user"])
    return cred["user"], cred["password"], payload["version"]


def check_crl_usable(path):
    """Refuse to start rather than run with revocation checking silently off.

    THIS FUNCTION EXISTS BECAUSE libpq FAILS OPEN, AND IT WAS MEASURED.

    Naming a CRL is supposed to turn revocation checking on. libpq only turns
    it on if the file loads; if it cannot, the flags are never set, the
    connection succeeds, and a revoked certificate is accepted exactly as
    before. Four ways of being unusable were tested against PostgreSQL 15 and
    all four connected: the file missing, the file unreadable, the file
    containing something that is not a CRL, and the file empty.

    None of them warned. The last is the one that happens in real life: a
    fetch that failed and left a zero-byte file behind, after which the
    estate stops checking revocation and nothing anywhere says so.

    So the application checks on the platform's behalf, and refuses to start
    when the answer is no. That is D-011: a service configured to require a
    protection should fail loudly rather than run without it. A crash at
    startup is a page; a silently disabled security control is a year of
    believing something that is not true.

    Note what is NOT checked here: whether the file carries a list from every
    authority in the chain. libpq fails CLOSED on that one, refusing healthy
    certificates, so it is already loud and needs no help.
    """
    if not os.path.exists(path):
        raise SystemExit(f"sslcrl is set to {path}, which does not exist. "
                         "Refusing to start: revocation checking would be off.")
    if not os.access(path, os.R_OK):
        raise SystemExit(f"sslcrl is set to {path}, which is not readable by "
                         f"{pwd.getpwuid(os.getuid()).pw_name}. Refusing to start.")
    if os.path.getsize(path) == 0:
        raise SystemExit(f"sslcrl is set to {path}, which is empty. "
                         "Refusing to start: a failed download looks exactly like this.")

    # Parse every list in the file and report the issuers, so the log says
    # what is actually being enforced rather than that a setting is spelled.
    proc = subprocess.run(["openssl", "crl", "-in", path, "-noout", "-issuer"],
                          capture_output=True, text=True)
    if proc.returncode != 0:
        raise SystemExit(f"sslcrl is set to {path}, which openssl cannot parse. "
                         "Refusing to start.")
    log.info("CRL file %s parses, first issuer %s", path, proc.stdout.strip())


class Database:
    """Owns the connection and the credential it was made with."""

    def __init__(self, cfg):
        self.cfg = cfg
        self.conn = None
        self.user = None
        self.version = None
        self.connect()

    def connect(self):
        db = self.cfg["database"]
        store = self.cfg["secret_store"]
        user, password, version = fetch_credential(
            store["socket"], store["secret_name"]
        )
        conn_args = dict(
            host=db["host"], port=db["port"], dbname=db["name"],
            user=user, password=password,
            # sslmode=verify-full is the whole point of Chapter 04.
            # `require` would encrypt and verify nothing, which buys a
            # confidential conversation with whoever happens to answer.
            sslmode=db["sslmode"],
        )
        # The anchor is optional, and leaving it out is not neutral. libpq
        # verifies the server certificate whenever a root CA file is
        # present, even under sslmode=require, so naming one here makes a
        # weak-looking config stronger than it reads. Section 7 is what
        # happens when the line is missing and nobody noticed it mattered.
        if db.get("sslrootcert"):
            conn_args["sslrootcert"] = db["sslrootcert"]
        # Chapter 09. Naming a CRL turns revocation checking ON, and that is
        # not a small switch: libpq then refuses any certificate it cannot
        # check, not merely the ones that were revoked. A missing file, an
        # unreadable one, or a list whose nextUpdate has passed all stop this
        # application from starting. That is correct and it is expensive, and
        # section 7 is what it looks like when nobody refreshed the list.
        if db.get("sslcrl"):
            check_crl_usable(db["sslcrl"])
            conn_args["sslcrl"] = db["sslcrl"]
        self.conn = psycopg2.connect(**conn_args)
        self.conn.autocommit = True
        self.user, self.version = user, version
        log.info("connected to %s@%s:%s/%s (credential version %s, sslmode %s, crl %s)",
                 user, db["host"], db["port"], db["name"], version, db["sslmode"],
                 "on" if db.get("sslcrl") else "off")

    def query(self, sql, args):
        """Run a query; on a connection-level failure, re-fetch and retry once."""
        try:
            return self._query(sql, args)
        except psycopg2.OperationalError as exc:
            log.warning("connection failed (%s), re-fetching credential", exc)
            self.connect()
            return self._query(sql, args)

    def _query(self, sql, args):
        with self.conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(sql, args)
            return cur.fetchone()


cfg = load_config(CONFIG_PATH)
database = Database(cfg)


class Handler(BaseHTTPRequestHandler):
    server_version = "paymentsvc/0.4"

    def _json(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/healthz":
            # CHAPTER 11: THIS ENDPOINT FINALLY ANSWERS A QUESTION.
            #
            # Until now it returned a hardcoded ok, and the book complained
            # about it twice: Chapter 08 section 10 found it reporting healthy
            # while the application could not reach its database at all, and
            # Chapter 10 section 0 warned against using it as a state check.
            #
            # It is not being given a database probe. That was the right call
            # and stays: a health endpoint that opens a connection turns every
            # poll into load, and Chapter 08's complaint was that it claimed
            # more than it knew, not that it knew too little.
            #
            # What it reports now is the one thing about this process that
            # degrades silently and takes the estate down with it: how much
            # life is left in the revocation list. Measured in Chapter 11, a
            # cron job that stops working leaves no trace anywhere, so the job
            # cannot be the thing that is watched. The artefact can.
            #
            # It shells out to crl-status rather than reimplementing it, for
            # the reason SVC-03 shells out to sign-leaf: two copies of a rule
            # about expiry is one copy too many, and the one that drifts will
            # be the one nobody runs by hand.
            crl = cfg["database"].get("sslcrl")
            if not crl:
                return self._json(200, {"status": "ok", "crl_checking": False})
            proc = subprocess.run(
                ["/usr/local/bin/crl-status", "--crl", crl,
                 "--warn-days", str(cfg.get("crl", {}).get("warn_days", 2))],
                capture_output=True, text=True)
            detail = [ln for ln in proc.stdout.splitlines() if ln.strip()]
            if proc.returncode == 0:
                return self._json(200, {"status": "ok", "crl": detail})
            # 503, not 200 with a flag. A monitoring system reads the status
            # line; a field inside a 200 is a thing somebody has to remember
            # to look at, which is the failure this whole chapter is about.
            return self._json(503, {"status": "degraded", "crl": detail})

        if self.path == "/credinfo":
            return self._json(200, {
                "db_user": database.user,
                "secret_name": cfg["secret_store"]["secret_name"],
                "credential_version": database.version,
                "running_as": pwd.getpwuid(os.getuid()).pw_name,
                "uid": os.getuid(),
                "db_host": cfg["database"]["host"],
                "sslmode": cfg["database"]["sslmode"],
                # Chapter 09: whether this client is checking revocation at
                # all. Worth exposing, because the difference between
                # checking and not checking is invisible from the outside
                # and is the difference between refusing a revoked
                # certificate and accepting one.
                # Effect, not intent. Reporting that a setting is spelled
                # would be the Chapter 08 /healthz defect again: with an
                # unusable file libpq checks nothing while the config still
                # says sslcrl. The process refuses to start in that case, so
                # if this says true it is true.
                "crl_checking": bool(cfg["database"].get("sslcrl")),
            })

        parts = self.path.strip("/").split("/")
        if len(parts) == 3 and parts[0] == "payments" and parts[2] == "status":
            try:
                payment_id = int(parts[1])
            except ValueError:
                return self._json(400, {"error": "payment id must be an integer"})
            row = database.query(
                "SELECT id, reference, amount_cents, currency, status "
                "FROM payments WHERE id = %s",
                (payment_id,),
            )
            if row is None:
                return self._json(404, {"error": "no such payment"})
            return self._json(200, dict(row))

        return self._json(404, {"error": "not found"})

    def log_message(self, fmt, *args):
        log.info("%s %s", self.address_string(), fmt % args)


if __name__ == "__main__":
    host, _, port = cfg["server"]["listen"].rpartition(":")
    srv = ThreadingHTTPServer((host, int(port)), Handler)
    log.info("listening on %s", cfg["server"]["listen"])
    srv.serve_forever()
