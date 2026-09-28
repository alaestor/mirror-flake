"""Stdio MCP client for the host's text-only memory API."""

import argparse
import os
import subprocess
from typing import Literal

import httpx
from mcp.server.fastmcp import FastMCP


def project_root():
    result = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    return os.path.realpath(result.stdout.strip() if result.returncode == 0 else os.getcwd())


def make_server(url, project):
    server = FastMCP("cognee-memory")

    async def call(operation, **values):
        async with httpx.AsyncClient(timeout=300, trust_env=False) as client:
            response = await client.post(f"{url}/{operation}", json={"project": project, **values})
            response.raise_for_status()
            return response.json()

    @server.tool()
    async def remember(text: str, scope: Literal["project", "global"] = "project") -> dict:
        """Save a concise verified fact or decision. Project is the current repo; global is shared across repos and harnesses. Never store secrets."""
        return await call("remember", text=text, scope=scope)

    @server.tool()
    async def recall(query: str, scope: Literal["project", "global", "all"] = "all") -> list:
        """Retrieve relevant prior facts and decisions. By default search this project and global memory, shared by Claude and Codex."""
        return await call("recall", query=query, scope=scope)

    @server.tool()
    async def forget(data_id: str, scope: Literal["project", "global"]) -> dict:
        """Permanently delete one memory item by its recall data_id from the explicit project or global scope. Never deletes a whole scope."""
        return await call("forget", data_id=data_id, scope=scope)

    return server


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    args = parser.parse_args()
    project = os.path.realpath(os.environ.get("COGNEE_MEMORY_PROJECT") or project_root())
    make_server(args.url, project).run(transport="stdio")
