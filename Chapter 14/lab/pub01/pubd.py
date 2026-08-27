#!/usr/bin/env python3
"""SVC-04 pubd, the publication point on HOST-06 pub01.

Serves the contents of /srv/pub over plain HTTP and does nothing else. No
authentication, no TLS, no write path, and no opinion about what it is
serving.

THREE THINGS IT DELIBERATELY DOES NOT DO.

DOES NOT verify anything. Every file here is signed by an authority the client
already trusts, so the client checks it. If this service checked too, somebody
would eventually rely on the fact that it checked, and a publication point that
is trusted is a publication point that has to be defended. This one does not:
it can be destroyed and rebuilt in a minute with no ceremony, which is the
property that makes it a safe place to absorb every client's polling.

DOES NOT serve TLS. The reflex is that everything should be encrypted, and here
it buys nothing. A CRL is signed, numbered and dated. An attacker who controls
the channel cannot forge one, cannot alter one, and cannot strip one without the
client noticing that its file has stopped arriving. What they CAN do is replay
an old and genuine list, and TLS would not stop that either, because the file
would be authentic. That is fixed at the client with crlNumber, not here.

DOES NOT accept writes. pull-artifacts puts files here by writing to the
filesystem as ACC-11. There is no upload endpoint, so there is no upload
endpoint to get wrong.

WHAT IT IS FOR. Nothing in the estate should have to reach hsm01 to collect a
public file. Every client polls this instead, forever, and the machine holding
the signing key never sees them.
"""
import http.server
import os
import sys

LISTEN = ("0.0.0.0", 80)
ROOT = "/srv/pub"

# An allow-list of names, not a directory listing and not a path the caller
# supplies. `GET /../../etc/shadow` is the oldest bug in static file serving,
# and the way not to have it is to never join a caller's string onto a path.
FILES = {
    "/crl.pem": "crl.pem",
    "/ca-bundle.pem": "ca-bundle.pem",
}


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "pubd/1.0"

    def _send(self, code, body, ctype="text/plain"):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        # A client that caches a CRL past its nextUpdate stops verifying
        # anything, so say plainly that this is not to be cached.
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/healthz":
            # Reports on the files, not on the process. A publication point
            # that answers "ok" while serving nothing is the Chapter 08
            # /healthz defect, and this service exists to be polled.
            present = {n: os.path.getsize(os.path.join(ROOT, f))
                       for n, f in FILES.items()
                       if os.path.exists(os.path.join(ROOT, f))}
            if len(present) != len(FILES):
                return self._send(503, f"missing: "
                                       f"{sorted(set(FILES) - set(present))}\n")
            return self._send(200, "".join(f"{n} {s} bytes\n"
                                           for n, s in sorted(present.items())))

        name = FILES.get(self.path)
        if name is None:
            return self._send(404, "not found\n")
        path = os.path.join(ROOT, name)
        try:
            with open(path, "rb") as fh:
                body = fh.read()
        except OSError:
            # Nothing has been published yet, or the pull is mid-flight. 503
            # rather than 404: the resource exists, this server just cannot
            # hand it over, and a client should retry rather than conclude the
            # URL is wrong.
            return self._send(503, "not published yet\n")
        if not body:
            return self._send(503, "published file is empty\n")
        return self._send(200, body, "application/x-pem-file")

    def do_POST(self):
        return self._send(405, "read only\n")

    do_PUT = do_DELETE = do_PATCH = do_POST

    def log_message(self, fmt, *args):
        print(f"{self.address_string()} {fmt % args}", flush=True)


def main():
    if not os.path.isdir(ROOT):
        print(f"pubd: {ROOT} does not exist", file=sys.stderr)
        return 1
    srv = http.server.ThreadingHTTPServer(LISTEN, Handler)
    print(f"pubd serving {ROOT} on {LISTEN[0]}:{LISTEN[1]}, read only, no TLS",
          flush=True)
    srv.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
