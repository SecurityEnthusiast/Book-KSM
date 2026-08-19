#!/usr/bin/env python3
"""APP-01 paymentsvc, answers 'what is the status of payment X?'

Chapter 02 change: the database credential is no longer in config.yaml. The app
asks SVC-02 secretstore for it at run time, and asks again when a connection
fails. That is what makes rotation possible without editing a file on a host.
"""

import json
import logging
import os
import sys
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import psycopg2
import yaml
from psycopg2.extras import RealDictCursor

CONFIG_PATH = os.environ.get("PAYMENTSVC_CONFIG", "/opt/paymentsvc/config.yaml")
CONSUMER_ID = os.environ.get("PAYMENTSVC_CONSUMER", "paymentsvc@dev01")

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
    # Chapter 01 left this line in place deliberately (OT-008). It is now far
    # less dangerous than it was, for one reason only: as of Chapter 02 there is
    # no longer a secret in this file for it to print. The line is unchanged;
    # what changed is what it has access to.
    log.debug("effective configuration: %s", cfg)
    return cfg


def fetch_credential(store_url, secret_name, consumer=CONSUMER_ID, timeout=5):
    """Ask SVC-02 for the current database credential.

    Returns (user, password, version). Raises on any failure, an app that
    cannot get its credential must fail loudly, not start up half-working.
    """
    url = f"{store_url.rstrip('/')}/v1/secrets/{secret_name}"
    req = urllib.request.Request(url)
    # We tell the store who we are. Chapter 02 note: this is a claim about
    # ourselves that nothing verifies. It is good enough to build an
    # inventory from and nowhere near good enough to make a decision on.
    req.add_header("X-Consumer", consumer)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        payload = json.loads(resp.read().decode())
    cred = json.loads(payload["value"])
    log.info("fetched %s version %s from %s as user %s",
             secret_name, payload["version"], store_url, cred["user"])
    return cred["user"], cred["password"], payload["version"]


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
        user, password, version = fetch_credential(
            self.cfg["secret_store"]["url"], self.cfg["secret_store"]["secret_name"]
        )
        self.conn = psycopg2.connect(
            host=db["host"], port=db["port"], dbname=db["name"],
            user=user, password=password,
        )
        self.conn.autocommit = True
        self.user, self.version = user, version
        log.info("connected to %s@%s:%s/%s (credential version %s)",
                 user, db["host"], db["port"], db["name"], version)

    def query(self, sql, args):
        """Run a query; on a connection-level failure, re-fetch and retry once.

        This single retry is the entire propagation mechanism. It is why a
        rotation does not require anyone to restart this service.
        """
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
    server_version = "paymentsvc/0.2"

    def _json(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/healthz":
            return self._json(200, {"status": "ok"})

        # Chapter 02: lets you see WHICH credential this process is actually
        # using, without revealing it. Rotation you cannot observe is
        # rotation you cannot verify.
        if self.path == "/credinfo":
            return self._json(200, {
                "db_user": database.user,
                "secret_name": cfg["secret_store"]["secret_name"],
                "credential_version": database.version,
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
