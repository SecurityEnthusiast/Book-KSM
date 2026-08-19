#!/usr/bin/env python3
"""secretstore-set, the ONLY way to change a value in SVC-02.

Deliberately not an HTTP endpoint. Writing runs on this host, as this
service's own OS user, gated by a file permission. That keeps the network
surface read-only: something that can reach the port can read a secret, but
cannot replace one.

Usage:  secretstore-set <name> <value>
        secretstore-set --show <name>      # metadata only, never the value
"""

import json
import os
import sys
import time

STORE_PATH = os.environ.get("SECRETSTORE_DB", "/var/lib/secretstore/secrets.json")


def load():
    with open(STORE_PATH) as fh:
        return json.load(fh)


def save(store):
    """Write via a temporary file and rename, so a reader never sees a
    half-written file. rename(2) is atomic within a filesystem."""
    tmp = STORE_PATH + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(store, fh, indent=2, sort_keys=True)
        fh.write("\n")
    os.chmod(tmp, 0o600)
    os.replace(tmp, STORE_PATH)


def main(argv):
    if len(argv) == 3 and argv[1] == "--show":
        store = load()
        name = argv[2]
        if name not in store:
            print(f"no such secret: {name}", file=sys.stderr)
            return 1
        e = store[name]
        print(f"name={name} version={e['version']} updated={e['updated']} "
              f"bytes={len(e['value'])}")
        return 0

    if len(argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    name, value = argv[1], argv[2]
    store = load()
    prev = store.get(name, {"version": 0})
    store[name] = {
        "version": prev["version"] + 1,
        "value": value,
        "updated": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    }
    save(store)
    # Never print the value back. The terminal is a place secrets go to die
    # slowly, in a scrollback buffer and a shell history file.
    print(f"{name}: version {prev['version']} -> {store[name]['version']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
