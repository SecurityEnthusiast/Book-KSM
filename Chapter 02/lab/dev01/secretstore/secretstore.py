#!/usr/bin/env python3
"""SVC-02 secretstore, one authoritative place to hold a secret.

Chapter 02. This is deliberately the smallest thing that solves OT-002, and no
more. It does NOT encrypt anything, and it does NOT check who is asking.
Both of those are Chapters of their own.

Read-only over HTTP. The only way to CHANGE a value is secretstore-set,
which runs on this host as this service's own OS user and writes the file
directly. A network client cannot write.
"""

import json
import os
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

STORE_PATH = os.environ.get("SECRETSTORE_DB", "/var/lib/secretstore/secrets.json")
ACCESS_LOG = os.environ.get("SECRETSTORE_ACCESS_LOG", "/var/log/secretstore-access.log")
LISTEN_HOST = os.environ.get("SECRETSTORE_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("SECRETSTORE_PORT", "8300"))


def load_store():
    with open(STORE_PATH) as fh:
        return json.load(fh)


def audit(client_ip, client_port, consumer, name, version, outcome):
    """Append one line per read. This is the entire audit story in Chapter 02.

    `consumer` is whatever the caller PUT IN A HEADER about itself. It is a
    claim, not a fact. Nothing here verifies it.
    """
    line = "\t".join([
        time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        f"{client_ip}:{client_port}",
        consumer,
        name,
        str(version),
        outcome,
    ])
    with open(ACCESS_LOG, "a") as fh:
        fh.write(line + "\n")


def consumers_for(name):
    """Reconstruct 'who holds a copy of this secret' from observed reads.

    This can only ever see consumers that have actually asked us. A copy in
    a tarball, in git, or on a host that has not fetched since we started
    logging is invisible here. Chapter 02 says so out loud.
    """
    seen = {}
    try:
        with open(ACCESS_LOG) as fh:
            for raw in fh:
                parts = raw.rstrip("\n").split("\t")
                if len(parts) != 6:
                    continue
                ts, peer, consumer, sec_name, version, outcome = parts
                if sec_name != name or outcome != "served":
                    continue
                seen[consumer] = {
                    "consumer": consumer,
                    "last_peer": peer,
                    "last_seen": ts,
                    "last_version_served": int(version),
                }
    except FileNotFoundError:
        pass
    return sorted(seen.values(), key=lambda c: c["consumer"])


class Handler(BaseHTTPRequestHandler):
    server_version = "secretstore/0.1"

    def _json(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        peer_ip, peer_port = self.client_address[0], self.client_address[1]
        # Self-declared. Unverified. See section 10.
        consumer = self.headers.get("X-Consumer", "-")

        if self.path == "/healthz":
            return self._json(200, {"status": "ok"})

        parts = self.path.strip("/").split("/")

        if len(parts) == 3 and parts[0] == "v1" and parts[1] == "secrets":
            name = parts[2]
            store = load_store()
            if name not in store:
                audit(peer_ip, peer_port, consumer, name, -1, "not_found")
                return self._json(404, {"error": "no such secret"})
            entry = store[name]
            audit(peer_ip, peer_port, consumer, name, entry["version"], "served")
            return self._json(200, {
                "name": name,
                "version": entry["version"],
                "updated": entry["updated"],
                "value": entry["value"],
            })

        if (len(parts) == 4 and parts[0] == "v1" and parts[1] == "secrets"
                and parts[3] == "consumers"):
            name = parts[2]
            store = load_store()
            if name not in store:
                return self._json(404, {"error": "no such secret"})
            return self._json(200, {
                "name": name,
                "current_version": store[name]["version"],
                "consumers": consumers_for(name),
                "caveat": "derived from observed reads only; a consumer that "
                          "never asks us is invisible here",
            })

        return self._json(404, {"error": "not found"})

    def do_PUT(self):
        return self._json(405, {"error": "this store is read-only over HTTP"})

    do_POST = do_PUT
    do_DELETE = do_PUT

    def log_message(self, fmt, *args):
        sys.stdout.write("%s %s\n" % (self.address_string(), fmt % args))
        sys.stdout.flush()


if __name__ == "__main__":
    srv = ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler)
    print(f"secretstore listening on {LISTEN_HOST}:{LISTEN_PORT}, db={STORE_PATH}")
    sys.stdout.flush()
    srv.serve_forever()
