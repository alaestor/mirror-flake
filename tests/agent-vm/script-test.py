import json
import os
import pathlib
import socket
import subprocess
import sys
import threading

session, stop, restart, bash = sys.argv[1:]
root = pathlib.Path.cwd()
environment = os.environ | {"XDG_RUNTIME_DIR": str(root / "runtime"),
                           "RECORD_LOG": str(root / "commands")}
pathlib.Path(environment["XDG_RUNTIME_DIR"]).mkdir()


def invoke(executable, *args, status=0, **extra):
    pathlib.Path(environment["RECORD_LOG"]).write_text("")
    result = subprocess.run([executable, *args], env=environment | extra,
                            capture_output=True, text=True, timeout=10)
    assert result.returncode == status, (result.returncode, result.stdout, result.stderr)
    calls = [json.loads(line) for line in pathlib.Path(environment["RECORD_LOG"]).read_text().splitlines()]
    return result, calls


# Startup failure must propagate and must not call SSH at all.
_, calls = invoke(session, "--", "printf", "unused", status=67, RECORD_START_STATUS="67")
assert not any(name == "ssh" for name, _ in calls), calls

# A successful system-manager start without a listener must time out visibly.
result, calls = invoke(session, "--", "printf", "unused", status=1)
assert "did not become reachable within 2s" in result.stderr
assert not any(name == "ssh" for name, _ in calls), calls

with socket.socket() as listener:
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", 33333))
    listener.listen()
    def accept():
        with listener.accept()[0]:
            pass
    thread = threading.Thread(target=accept)
    thread.start()
    original = ["printf", "%s\\0", "two words", "", "a\nline", "'\";$()\\"]
    _, calls = invoke(session, "--forward", "8080:localhost:80", "--reverse-forward",
                      "9000:localhost:90", "--", *original, status=41, RECORD_SSH_STATUS="41")
    thread.join(timeout=3)
    assert not thread.is_alive()
ssh = next(args for name, args in calls if name == "ssh")
assert ["-L", "8080:localhost:80", "-R", "9000:localhost:90"] == ssh[ssh.index("-L"):ssh.index("-L") + 4]
assert "StrictHostKeyChecking=yes" in ssh and "ExitOnForwardFailure=yes" in ssh
assert ssh[-3:-1] == ["fixture@localhost", "--"], ssh
decoded = subprocess.check_output([bash, "-c", ssh[-1]])
assert decoded == b"".join(value.encode() + b"\0" for value in original[2:]), decoded
assert ["systemctl", ["--no-ask-password", "start", "--no-block", "microvm@fixture.service"]] in calls

# Stop preserves references. Recovery names only the fixed installed services.
_, calls = invoke(stop, RECORD_SCOPES="agent-vm-session-fixture-123.scope active\n")
assert not any(name == "systemctl" and "--no-ask-password" in args for name, args in calls)
assert (root / "runtime/agent-vm-fixture/stop-requested").exists()
_, calls = invoke(restart)
assert [args for name, args in calls if name == "systemctl"] == [
    ["--no-ask-password", "stop", "microvm@fixture.service"],
    ["--no-ask-password", "stop", "microvm-virtiofsd@fixture.service"]]
assert not (root / "runtime/agent-vm-fixture/stop-requested").exists()
invoke(session, "--forward", status=2)
