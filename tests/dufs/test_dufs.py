"""Exercise the generated Dufs command and the account startup guard."""

import base64
import http.client
import io
import json
import os
from pathlib import Path
import shlex
import socket
import subprocess
import tempfile
import time
import zipfile


password = "fixture-password"
hashed = subprocess.run(
    ["openssl", "passwd", "-6", "-stdin"],
    input=password,
    text=True,
    capture_output=True,
    check=True,
).stdout.strip()
rule = f"fixture:{hashed}@/:ro"
environment = dict(os.environ, DUFS_AUTH=rule)
validator = os.environ["DUFS_TEST_VALIDATOR"]

for value in [rule, f"{rule}|second:{hashed}@/:ro"]:
    subprocess.run([validator], env=dict(environment, DUFS_AUTH=value), check=True)
for invalid in [
    "",
    "@/",
    "fixture:plaintext@/:ro",
    rule.replace("/:ro", "/:rw"),
    f"{rule}|@/",
    f"{rule}|",
    f"|{rule}",
    f"{rule}||{rule}",
    f"{rule}\n@/",
    f"{rule}\r@/",
]:
    result = subprocess.run(
        [validator], env=dict(environment, DUFS_AUTH=invalid), capture_output=True
    )
    assert result.returncode != 0, "Unsafe account configuration accepted"
missing = dict(environment)
missing.pop("DUFS_AUTH")
assert subprocess.run([validator], env=missing, capture_output=True).returncode != 0

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    media = root / "media"
    for share in ["Anime", "Movies", "Music"]:
        (media / share).mkdir(parents=True)
    album = media / "Music" / "Album"
    (album / "Disc").mkdir(parents=True)
    track = b"fixture music content"
    nested = b"nested track bytes"
    (album / "Track.txt").write_bytes(track)
    (album / "Disc" / "Nested.bin").write_bytes(nested)
    unshared = root / "unshared.txt"
    unshared.write_text("not exposed")
    (media / "Anime" / "escape").symlink_to(unshared)
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        port = reservation.getsockname()[1]
    command = shlex.split(os.environ["DUFS_TEST_COMMAND"]) + [
        "--bind", "127.0.0.1", "--port", str(port), str(media)
    ]
    authorization = "Basic " + base64.b64encode(f"fixture:{password}".encode()).decode()

    def request(path="/", *, authenticated=False, method="GET", headers=None):
        headers = dict(headers or {})
        if authenticated:
            headers["Authorization"] = authorization
        connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
        try:
            connection.request(method, path, headers=headers)
            response = connection.getresponse()
            return response.status, response.read(), dict(response.getheaders())
        finally:
            connection.close()

    with (root / "server.log").open("w+") as log:
        process = subprocess.Popen(command, env=environment, stdout=log, stderr=log)
        try:
            for _ in range(100):
                try:
                    assert request()[0] == 401
                    break
                except OSError:
                    if process.poll() is not None:
                        raise AssertionError("Dufs exited before becoming ready")
                    time.sleep(0.05)
            else:
                raise AssertionError("Dufs startup timed out")

            for path in [
                "/", "/Music", "/Music/", "/Music/?json", "/?simple",
                "/?q=Track&json", "/Music/Album/?zip", "/Music/Album/Track.txt",
                "/missing/", "/Anime/escape",
            ]:
                for method in ["GET", "HEAD"]:
                    status, body, headers = request(path, method=method)
                    assert status == 401, (path, method, status)
                    assert "Location" not in headers
                    assert not any(name in body for name in [b"Anime", b"Movies", b"Music", b"Track"])
            assert request(headers={"Authorization": "Basic Zml4dHVyZTp3cm9uZw=="})[0] == 401

            status, body, _ = request("/?json", authenticated=True)
            index = json.loads(body)
            assert status == 200 and {p["name"] for p in index["paths"]} == {"Anime", "Movies", "Music"}
            assert index["allow_search"] and index["allow_archive"]
            assert not index["allow_upload"] and not index["allow_delete"]
            assert request("/unshared.txt", authenticated=True)[0] == 404
            assert request("/Anime/escape", authenticated=True)[0] in (403, 404)
            for path in ["/../unshared.txt", "/%2e%2e/unshared.txt"]:
                assert request(path, authenticated=True)[0] == 400

            sample = "/Music/Album/Track.txt"
            assert request(sample, authenticated=True)[1] == track
            assert request(sample, authenticated=True, method="HEAD")[0] == 200
            status, body, _ = request(sample, authenticated=True, headers={"Range": "bytes=0-6"})
            assert status == 206 and body == track[:7]
            for method in ["PUT", "PATCH", "POST", "DELETE", "MKCOL", "MOVE", "COPY"]:
                assert request(sample, authenticated=True, method=method)[0] in (403, 405)
            assert (album / "Track.txt").read_bytes() == track

            status, body, _ = request("/Music/?q=Track&json", authenticated=True)
            assert status == 200
            assert any(p["name"].endswith("Track.txt") for p in json.loads(body)["paths"])
            status, body, _ = request("/Music/Album/?zip", authenticated=True)
            assert status == 200
            with zipfile.ZipFile(io.BytesIO(body)) as archive:
                names = archive.namelist()
                assert all(not name.startswith("/") and ".." not in name.split("/") for name in names)
                assert {archive.read(name) for name in names if not name.endswith("/")} == {track, nested}
        except BaseException:
            log.flush()
            log.seek(0)
            print(log.read())
            raise
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()

print("PASS: Dufs account guard, authenticated reads/search/ZIPs, and forbidden operations")
