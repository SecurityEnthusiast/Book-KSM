#!/usr/bin/env python3
"""APP-01 paymentsvc, answers 'what is the status of payment X?'"""

import json
import logging
import os
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
    # NOTE (Chapter 01): this one line is deliberate, and it is extremely common
    # in real codebases. Chapter 01 shows you exactly what it costs.
    log.debug("effective configuration: %s", cfg)
    return cfg


cfg = load_config(CONFIG_PATH)
db = cfg["database"]

conn = psycopg2.connect(
    host=db["host"],
    port=db["port"],
    user=db["user"],
    password=db["password"],
    dbname=db["name"],
)
conn.autocommit = True
log.info("connected to %s@%s:%s/%s", db["user"], db["host"], db["port"], db["name"])


class Handler(BaseHTTPRequestHandler):
    server_version = "paymentsvc/0.1"

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

        parts = self.path.strip("/").split("/")
        if len(parts) == 3 and parts[0] == "payments" and parts[2] == "status":
            try:
                payment_id = int(parts[1])
            except ValueError:
                return self._json(400, {"error": "payment id must be an integer"})
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    "SELECT id, reference, amount_cents, currency, status "
                    "FROM payments WHERE id = %s",
                    (payment_id,),
                )
                row = cur.fetchone()
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
