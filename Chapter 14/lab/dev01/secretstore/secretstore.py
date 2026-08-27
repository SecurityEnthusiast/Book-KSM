#!/usr/bin/env python3
"""SVC-02 secretstore, now it asks the kernel who is calling, and decides.

Chapter 03. Two changes from Chapter 02, and they are the whole chapter:

  1. It listens on a Unix domain socket instead of a TCP port, so the kernel
     can tell it the uid of the process at the other end. That is not a claim
     the caller makes. It is the same authority that enforces file modes.
  2. It consults POL-01 and REFUSES requests it is not willing to serve.

It still does not encrypt anything (AR-001), and it still cannot help you
once the caller is on a different machine, see OT-014.
"""

import json
import os
import pwd
import socket
import struct
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

STORE_PATH = os.environ.get("SECRETSTORE_DB", "/var/lib/secretstore/secrets.json")
POLICY_PATH = os.environ.get("SECRETSTORE_POLICY", "/etc/secretstore/policy.json")
ACCESS_LOG = os.environ.get("SECRETSTORE_ACCESS_LOG", "/var/log/secretstore-access.log")
SOCKET_PATH = os.environ.get("SECRETSTORE_SOCKET", "/run/secretstore/sock")


def load_store():
    with open(STORE_PATH) as fh:
        return json.load(fh)


def load_policy():
    """POL-01, re-read on every request so an edit takes effect immediately.

    Cheap here, and it means a policy change does not need a restart. A real
    system caches this and invalidates deliberately.
    """
    with open(POLICY_PATH) as fh:
        return json.load(fh)


def peer_identity(conn):
    """Ask the kernel who is at the other end of this socket.

    SO_PEERCRED returns a `struct ucred`, pid, uid, gid, filled in by the
    kernel at connect(2) time from the peer's actual process credentials.
    The caller does not supply it and cannot influence it.

    This is Linux-specific, and it is the reason this store now listens on a
    Unix socket rather than a TCP port: there is no equivalent for TCP,
    because there is no shared kernel to ask.
    """
    raw = conn.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED,
                          struct.calcsize("3i"))
    pid, uid, gid = struct.unpack("3i", raw)
    return pid, uid, gid


def username_for(uid):
    try:
        return pwd.getpwuid(uid).pw_name
    except KeyError:
        return f"uid:{uid}"


def audit(pid, uid, name, secret, version, decision):
    """One line per request. Every field except `secret` now comes from the
    kernel or from our own policy evaluation. Nothing here is self-declared,
    which is the difference between this log and Chapter 02's.
    """
    line = "\t".join([
        time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        f"pid={pid}", f"uid={uid}", name, secret, str(version), decision,
    ])
    with open(ACCESS_LOG, "a") as fh:
        fh.write(line + "\n")


def consumers_for(secret):
    """Who holds a copy of this secret, now a list of verified identities.

    Same structural limit as Chapter 02: it can only see consumers that have
    actually asked us. What changed is that the names in it are facts.
    """
    seen = {}
    try:
        with open(ACCESS_LOG) as fh:
            for raw in fh:
                p = raw.rstrip("\n").split("\t")
                if len(p) != 7:
                    continue
                ts, pid, uid, name, sec, version, decision = p
                if sec != secret or decision != "allow":
                    continue
                seen[name] = {
                    "consumer": name,
                    "uid": int(uid.split("=", 1)[1]),
                    "last_seen": ts,
                    "last_version_served": int(version),
                }
    except FileNotFoundError:
        pass
    return sorted(seen.values(), key=lambda c: c["consumer"])


class Handler(BaseHTTPRequestHandler):
    server_version = "secretstore/0.2"

    # client_address is '' on AF_UNIX; the peer's identity comes from the
    # kernel instead, so the default implementation would be both useless
    # and slow (it tries a reverse DNS lookup).
    def address_string(self):
        return "unix"

    def _json(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        pid, uid, _gid = peer_identity(self.connection)
        name = username_for(uid)

        if self.path == "/healthz":
            return self._json(200, {"status": "ok"})

        parts = self.path.strip("/").split("/")

        if len(parts) == 3 and parts[0] == "v1" and parts[1] == "secrets":
            secret = parts[2]
            store = load_store()
            if secret not in store:
                audit(pid, uid, name, secret, -1, "not_found")
                return self._json(404, {"error": "no such secret"})

            allowed = load_policy().get(secret, [])
            if name not in allowed:
                audit(pid, uid, name, secret, store[secret]["version"], "deny")
                return self._json(403, {
                    "error": "denied",
                    "secret": secret,
                    "you_are": name,
                    "detail": "POL-01 does not permit this identity to read "
                              "this secret",
                })

            entry = store[secret]
            audit(pid, uid, name, secret, entry["version"], "allow")
            return self._json(200, {
                "name": secret,
                "version": entry["version"],
                "updated": entry["updated"],
                "value": entry["value"],
            })

        if (len(parts) == 4 and parts[0] == "v1" and parts[1] == "secrets"
                and parts[3] == "consumers"):
            secret = parts[2]
            store = load_store()
            if secret not in store:
                return self._json(404, {"error": "no such secret"})
            return self._json(200, {
                "name": secret,
                "current_version": store[secret]["version"],
                "consumers": consumers_for(secret),
                "caveat": "derived from observed reads only; a consumer that "
                          "never asks us is invisible here",
            })

        return self._json(404, {"error": "not found"})

    def do_PUT(self):
        return self._json(405, {"error": "this store is read-only over the socket"})

    do_POST = do_PUT
    do_DELETE = do_PUT

    def log_message(self, fmt, *args):
        sys.stdout.write((fmt % args) + "\n")
        sys.stdout.flush()


class UnixHTTPServer(ThreadingHTTPServer):
    address_family = socket.AF_UNIX

    def server_bind(self):
        # ThreadingHTTPServer.server_bind wants a host/port to derive a
        # server name from; there is neither on AF_UNIX.
        socket.socket.bind(self.socket, self.server_address)
        self.server_name = "localhost"
        self.server_port = 0


if __name__ == "__main__":
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)
    srv = UnixHTTPServer(SOCKET_PATH, Handler)
    # 0666 deliberately: anything may CONNECT, and the policy decides.
    # See Chapter 03 section 5, a narrower mode would make the filesystem
    # refuse callers silently, and we want every refusal in the audit log.
    os.chmod(SOCKET_PATH, 0o666)
    print(f"secretstore listening on {SOCKET_PATH}, policy={POLICY_PATH}")
    sys.stdout.flush()
    srv.serve_forever()
