"""Recording stand-ins for cheap generated-script tests, not isolation proof."""
import json
import os
import pathlib
import sys
import socket

name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["RECORD_LOG"], "a") as log:
    log.write(json.dumps([name, args]) + "\n")
if name == "systemd-run":
    assert args[:4] == ["--user", "--scope", "--collect", "--quiet"], args
    command = args[args.index("--") + 1:]
    os.execvpe(command[0], command, os.environ)
elif name == "systemctl":
    if args[:2] == ["is-failed", "--quiet"]:
        sys.exit(1)
    if args[:2] == ["--no-ask-password", "start"]:
        sys.exit(int(os.environ.get("RECORD_START_STATUS", "0")))
    if args[:2] == ["--user", "list-units"]:
        sys.stdout.write(os.environ.get("RECORD_SCOPES", ""))
elif name == "ssh":
    sys.exit(int(os.environ.get("RECORD_SSH_STATUS", "0")))
elif name == "ssh-keyscan":
    try:
        with socket.create_connection(("127.0.0.1", 33333), timeout=1):
            pass
    except OSError:
        sys.exit(1)
else:
    raise AssertionError(name)
