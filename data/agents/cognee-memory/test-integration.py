"""Offline preflight and MCP transport tests against a fake host memory API."""

import asyncio
import http.server
import json
import os
from pathlib import Path
import subprocess
import sys
import threading

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

unavailable = False
wrong_model = False
wrong_health = False
requests = []


class API(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        assert self.headers.get("Authorization") is None
        self.send_response(503 if unavailable else 200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        result = {"data": [{"id": "wrong-model" if wrong_model else "test-model"}]} if self.path == "/v1/models" else {"ready": not unavailable and not wrong_health}
        self.wfile.write(json.dumps(result).encode())

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        requests.append((self.path, body))
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        result = {"stored": True} if self.path == "/remember" else [{"text": "Cedar Labs is in Oslo"}]
        self.wfile.write(json.dumps(result).encode())

    def log_message(self, *args):
        pass


def prepare(**environment):
    return subprocess.run([sys.argv[1]], env={**os.environ, **environment}, capture_output=True, text=True, timeout=40)


async def mcp_test():
    environment = {**os.environ, "COGNEE_MEMORY_PROJECT": "/fixture/repository"}
    async with stdio_client(StdioServerParameters(command=sys.argv[2], env=environment)) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            assert {tool.name for tool in (await session.list_tools()).tools} == {"remember", "recall"}
            for scope in ("project", "global"):
                result = await session.call_tool("remember", {"text": "A verified fact", "scope": scope})
                assert not result.isError, result
            result = await session.call_tool("recall", {"query": "Where is Cedar Labs?"})
            assert not result.isError, result
            assert "Oslo" in str(result)
            count = len(requests)
            result = await session.call_tool("remember", {"text": "test", "scope": "all"})
            assert result.isError
            assert len(requests) == count


servers = [http.server.ThreadingHTTPServer(("127.0.0.1", port), API) for port in (48010, 48011)]
try:
    for server in servers:
        threading.Thread(target=server.serve_forever, daemon=True).start()
    assert prepare().returncode == 0
    assert Path("events").read_text().splitlines() == ["start"]
    assert prepare().returncode == 0
    assert Path("events").read_text().splitlines() == ["start"]
    Path("running").unlink()
    assert prepare(AGENT_TEST_TRANSIENT="1").returncode == 0
    assert Path("events").read_text().splitlines() == ["start", "transient"]
    assert prepare(COGNEE_MEMORY_REMOTE="1", COGNEE_MEMORY_URL="http://127.0.0.1:48010").returncode == 0
    before = Path("events").read_text()
    wrong_model = True
    result = prepare()
    assert result.returncode == 1 and "local LLM unavailable" in result.stderr
    wrong_model = False
    unavailable = True
    for environment in ({}, {"COGNEE_MEMORY_REMOTE": "1"}):
        result = prepare(**environment)
        assert result.returncode == 1 and "local LLM unavailable" in result.stderr
    assert Path("events").read_text() == before
    unavailable = False
    wrong_health = True
    result = prepare(COGNEE_MEMORY_REMOTE="1")
    assert result.returncode == 1 and "memory service unavailable" in result.stderr
    wrong_health = False
    asyncio.run(mcp_test())
    assert all(body["project"] == "/fixture/repository" for _, body in requests)
    assert [body["scope"] for path, body in requests if path == "/remember"] == ["project", "global"]
    assert requests[-1][1]["scope"] == "all"
finally:
    for server in servers:
        server.shutdown()
