"""Authenticated HTTP workflows against the real, systemd-confined fixture."""
import base64
import http.client
import io
import json
import zipfile


def request(path, *, auth=True, method="GET", headers=None):
    headers = dict(headers or {})
    if auth:
        headers["Authorization"] = "Basic " + base64.b64encode(
            b"fixture:fixture-password"
        ).decode()
    connection = http.client.HTTPConnection("127.0.0.1", 8087, timeout=10)
    try:
        connection.request(method, path, headers=headers)
        response = connection.getresponse()
        return response.status, response.read()
    finally:
        connection.close()


for path in ["/", "/?q=Track&json", "/Films/Album/?zip", "/Films/Album/Track.txt"]:
    assert request(path, auth=False)[0] == 401, path
status, body = request("/?json")
assert status == 200 and [p["name"] for p in json.loads(body)["paths"]] == ["Films"]
track = "/Films/Album/Track.txt"
status, body = request(track)
assert status == 200 and body == b"fixture-track"
assert request(track, method="HEAD")[0] == 200
assert request(track, headers={"Range": "bytes=0-6"}) == (206, b"fixture")
status, body = request("/Films/?q=Track&json")
assert status == 200 and any(p["name"].endswith("Track.txt") for p in json.loads(body)["paths"])
status, body = request("/Films/Album/?zip")
assert status == 200
with zipfile.ZipFile(io.BytesIO(body)) as archive:
    assert [archive.read(n) for n in archive.namelist() if not n.endswith("/")] == [b"fixture-track"]
for method in ["PUT", "DELETE", "MKCOL"]:
    assert request(track, method=method)[0] in (403, 405), method
print("PASS: authenticated listing, read, HEAD, range, search, ZIP, and forbidden writes")
