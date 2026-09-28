"""Exercise text-only ingestion, dataset selection, and inference readiness."""

import asyncio
import os
from uuid import UUID
from types import SimpleNamespace
from unittest.mock import AsyncMock

from aiohttp import web
from aiohttp.test_utils import TestClient, TestServer

import server


async def main():
    state = {"model": "test-model", "inference": True}
    inference_calls = []

    async def models(request):
        assert "Authorization" not in request.headers
        return web.json_response({"data": [{"id": state["model"]}]})

    async def infer(request):
        assert "Authorization" not in request.headers
        body = await request.json()
        assert body["model"] == "test-model" and body["max_tokens"] == 1
        inference_calls.append(body)
        return web.json_response({"choices": [{}]} if state["inference"] else {},
                                 status=200 if state["inference"] else 503)

    llm = web.Application()
    llm.add_routes([web.get("/models", models), web.post("/chat/completions", infer)])
    async with TestServer(llm) as backend:
        os.environ["COGNEE_LLM_ENDPOINT"] = str(backend.make_url("")).rstrip("/")
        os.environ["COGNEE_LLM_MODEL"] = "test-model"
        assert await server.llm_available()
        state["inference"] = False
        assert not await server.llm_available()
        count = len(inference_calls)
        state["model"] = "wrong-model"
        assert not await server.llm_available()
        assert len(inference_calls) == count
        state.update(model="test-model", inference=True)

        calls = []

        async def remember(content, **options):
            assert content.filename.startswith("memory-") and content.filename.endswith(".txt")
            calls.append((await content.read(), options))

        sdk = SimpleNamespace(
            remember=remember,
            datasets=SimpleNamespace(list_datasets=AsyncMock(return_value=[
                SimpleNamespace(name="agent-global"),
                SimpleNamespace(name=server.datasets("/repo/a", "project")[0]),
            ])),
            recall=AsyncMock(return_value=[{"text": "verified fact"}]),
            forget=AsyncMock(return_value={"items_removed": 1}),
            SearchType=SimpleNamespace(CHUNKS="chunks"),
        )
        app = web.Application(client_max_size=128 * 1024)
        app[server.SDK], app[server.LOCK] = sdk, asyncio.Lock()
        app.add_routes([web.get("/health", server.health),
                        web.post("/remember", server.remember),
                        web.post("/recall", server.recall),
                        web.post("/forget", server.forget)])
        async with TestClient(TestServer(app)) as client:
            assert (await client.get("/health")).status == 200
            state["inference"] = False
            assert (await client.get("/health")).status == 503
            for scope, text in (("project", "/etc/passwd"), ("global", "http://localhost/secret")):
                response = await client.post("/remember", json={"project": "/repo/a", "scope": scope, "text": text})
                assert response.status == 200
                assert calls[-1][0] == text.encode()
                assert calls[-1][1]["dataset_name"] == server.datasets("/repo/a", scope)[0]
                assert calls[-1][1]["self_improvement"] is False
            for body in ([], {"project": "/repo/a", "text": ""},
                         {"project": "/repo/a", "scope": "all", "text": "fact"}):
                assert (await client.post("/remember", json=body)).status == 400
            assert len(calls) == 2
            assert (await client.post("/recall", json=[])).status == 400
            response = await client.post("/recall", json={"project": "/repo/b", "query": "fact"})
            assert response.status == 200 and await response.json() == [{"text": "verified fact"}]
            assert sdk.recall.await_args.kwargs["datasets"] == ["agent-global"]
            sdk.recall.reset_mock()
            response = await client.post("/recall", json={"project": "/repo/b", "query": "fact", "scope": "project"})
            assert response.status == 200 and await response.json() == []
            sdk.recall.assert_not_awaited()
            data_id = "a08d0560-dd0b-42c1-89e3-257459aa6f9f"
            response = await client.post("/forget", json={"project": "/repo/a", "scope": "project", "data_id": data_id})
            assert response.status == 200 and await response.json() == {"items_removed": 1}
            assert sdk.forget.await_args.kwargs == {
                "data_id": UUID(data_id), "dataset": server.datasets("/repo/a", "project")[0]
            }
            for body in (
                {"project": "/repo/a", "scope": "all", "data_id": data_id},
                {"project": "/repo/a", "scope": "project", "data_id": "bad"},
                {"project": "/repo/a", "data_id": data_id},
            ):
                assert (await client.post("/forget", json=body)).status == 400
            assert sdk.forget.await_count == 1
            response = await client.post("/forget", json={"project": "/repo/b", "scope": "project", "data_id": data_id})
            assert response.status == 404
            assert sdk.forget.await_count == 1
    assert server.datasets("/repo/a", "project") != server.datasets("/repo/b", "project")


asyncio.run(main())
