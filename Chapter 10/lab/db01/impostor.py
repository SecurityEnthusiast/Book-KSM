#!/usr/bin/env python3
"""A machine pretending to be SVC-01 paymentsdb.

It does not implement PostgreSQL. It implements exactly the first two things
a PostgreSQL client does, which turns out to be enough:

  1. answer the SSLRequest with "S", meaning "yes, I speak TLS"
  2. present a certificate and complete a TLS handshake

Then it prints whatever the client sends next and hangs up. What arrives is
the startup message: the database name and the username the client is about
to authenticate as. Chapter 04 section 7 is about which sslmode settings let
this happen.
"""

import socket
import ssl
import sys

LISTEN = ("0.0.0.0", 5432)
SSL_REQUEST = b"\x00\x00\x00\x08\x04\xd2\x16/"     # length 8, code 80877103


def main(certfile, keyfile):
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(certfile, keyfile)

    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(LISTEN)
    srv.listen(5)
    print(f"impostor listening on {LISTEN[0]}:{LISTEN[1]}", flush=True)

    while True:
        raw, peer = srv.accept()
        try:
            first = raw.recv(8)
            if first != SSL_REQUEST:
                print(f"{peer[0]} sent {first!r} in the clear, no TLS asked for", flush=True)
                print(f"  ...and then: {raw.recv(256)!r}", flush=True)
                raw.close()
                continue
            raw.sendall(b"S")                       # "yes, let us do TLS"
            with ctx.wrap_socket(raw, server_side=True) as tls:
                print(f"TLS handshake COMPLETED with {peer[0]}", flush=True)
                print(f"  the client told me: {tls.recv(256)!r}", flush=True)
        except ssl.SSLError as exc:
            print(f"client refused me: {exc.reason}", flush=True)
        except OSError as exc:
            print(f"connection dropped: {exc}", flush=True)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
