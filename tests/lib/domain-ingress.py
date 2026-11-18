"""Exercise real domain routes with Caddy and disposable HTTP backends.

Only listeners, TLS, administrative API, storage, and logging are adapted for
the build sandbox. Domain matchers, route order, and handlers remain unchanged.
The Caddy VM check separately covers TLS and systemd sandbox enforcement.
"""

import contextlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, build_opener, ProxyHandler


class Backend(BaseHTTPRequestHandler):
    def do_GET(self):
        body = f"backend:{self.command}:{self.path}".encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    do_POST = do_GET

    def log_message(self, *args):
        pass


opener = build_opener(ProxyHandler({}))
caddy = os.environ["DOMAIN_CADDY"]


def request(port, host, path, method="GET", headers=None):
    req = Request(f"http://127.0.0.1:{port}{path}", method=method,
                  headers={"Host": host, **(headers or {})},
                  data=b"" if method == "POST" else None)
    try:
        response = opener.open(req, timeout=2)
    except HTTPError as error:
        response = error
    with response:
        return response.status, response.read().decode()


@contextlib.contextmanager
def serving(source):
    # Adapt the actual NixOS-generated Caddyfile before changing transport.
    config = json.loads(subprocess.check_output([caddy, "adapt", "--config", source]))
    with tempfile.TemporaryDirectory(prefix="domain-ingress-") as directory:
        root = Path(directory)
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            port = probe.getsockname()[1]
        servers = config["apps"]["http"]["servers"]
        # The primary HTTPS listener has every domain; the separate federation
        # listener repeats only Matrix. Adapt both, run the full route set.
        server = max(servers.values(), key=lambda entry: len(entry.get("routes", [])))
        server["listen"] = [f"127.0.0.1:{port}"]
        server["automatic_https"] = {"disable": True}
        server.pop("tls_connection_policies", None)
        config["apps"]["http"]["servers"] = {"fixture": server}
        config["admin"] = {"disabled": True}
        config["storage"] = {"module": "file_system", "root": str(root / "state")}
        config["logging"] = {"logs": {"default": {"writer": {"output": "stderr"}}}}
        path = root / "caddy.json"
        path.write_text(json.dumps(config))
        validation = subprocess.run([caddy, "validate", "--config", str(path)],
                                    capture_output=True, text=True, timeout=15)
        assert validation.returncode == 0, (validation.stdout, validation.stderr)
        with (root / "caddy.log").open("w+") as log:
            process = subprocess.Popen([caddy, "run", "--config", str(path)], stdout=log, stderr=log)
            try:
                deadline = time.monotonic() + 10
                while True:
                    try:
                        if request(port, "0x04.cc", "/") == (200, "static-fixture"):
                            break
                    except (URLError, TimeoutError):
                        pass
                    if process.poll() is not None or time.monotonic() > deadline:
                        raise AssertionError("Domain Caddy did not become ready")
                    time.sleep(0.05)
                yield port
            except BaseException:
                log.flush()
                print((root / "caddy.log").read_text())
                raise
            finally:
                process.terminate()
                process.wait(timeout=10)


backend = ThreadingHTTPServer(("127.0.0.1", 18581), Backend)
thread = threading.Thread(target=backend.serve_forever, daemon=True)
thread.start()
try:
    for name, source in json.loads(os.environ["DOMAIN_CONFIGS"]).items():
        with serving(source) as port:
            for path in ["/admin", "/admin/", "/admin/settings"]:
                status, body = request(port, "headscale.0x04.cc", path)
                assert status == (200 if name == "allowed" else 403), (name, path, status, body)
                assert body.startswith("backend:") == (name == "allowed"), (name, path, body)
            assert request(port, "headscale.0x04.cc", "/machine/register") == (200, "backend:GET:/machine/register")
            if name != "allowed":
                # Spoof an address inside the other fixture's allowlist, not
                # merely another denied address.
                assert request(port, "headscale.0x04.cc", "/admin/", headers={"X-Forwarded-For": "192.0.2.10"})[0] == 403
            if name == "denied":
                for path, method in [
                    ("/owner/repo/info/refs?service=git-upload-pack", "GET"),
                    ("/owner/repo/git-upload-pack", "POST"),
                    ("/owner/repo/git-receive-pack", "POST"),
                    ("/owner/repo/info/lfs", "GET"),
                    ("/owner/repo/info/lfs/objects/batch", "POST"),
                    ("/api/v1/version", "GET"),
                ]:
                    assert request(port, "git.0x04.cc", path, method) == (200, f"backend:{method}:{path}"), path
                for path in ["/owner/repo", "/api/v10/version", "/owner/repo/info/lfs-not"]:
                    status, body = request(port, "git.0x04.cc", path)
                    assert status == 200 and "Cerberus" in body and not body.startswith("backend:"), path
                for path in ["/_matrix/client/versions", "/_matrix/federation/v1/version", "/_synapse/client/session"]:
                    assert request(port, "matrix.0x04.cc", path) == (200, f"backend:GET:{path}"), path
                assert "Cerberus" in request(port, "matrix.0x04.cc", "/")[1]
                status, body = request(port, "0x04.cc", "/.well-known/matrix/server")
                assert status == 200 and json.loads(body) == {"m.server": "matrix.0x04.cc:8448"}
                status, body = request(port, "0x04.cc", "/.well-known/matrix/client")
                assert status == 200 and json.loads(body)["m.homeserver"]["base_url"] == "https://matrix.0x04.cc"
            print(f"PASS: production domain routes, admin allowlist={name}")
finally:
    backend.shutdown()
    backend.server_close()
    thread.join(timeout=5)
