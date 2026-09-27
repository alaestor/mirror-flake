"""Host-only text memory API. The agent never supplies a host file path."""

import asyncio
import hashlib
import io
import json
import os

from aiohttp import ClientSession, ClientTimeout, web
from starlette.datastructures import UploadFile


def datasets(project, scope):
    if not isinstance(project, str) or not project:
        raise web.HTTPBadRequest(text="project is required")
    local = "agent-project-" + hashlib.sha256(project.encode()).hexdigest()
    if scope == "project":
        return [local]
    if scope == "global":
        return ["agent-global"]
    if scope == "all":
        return [local, "agent-global"]
    raise web.HTTPBadRequest(text="invalid memory scope")


async def llm_available():
    try:
        endpoint = os.environ["COGNEE_LLM_ENDPOINT"]
        model = os.environ["COGNEE_LLM_MODEL"]
        async with ClientSession(timeout=ClientTimeout(total=10)) as client:
            async with client.get(endpoint + "/models") as response:
                response.raise_for_status()
                models = (await response.json())["data"]
            if not any(item["id"] == model for item in models):
                return False
            # A listed model can still be unloaded or unable to serve inference.
            async with client.post(endpoint + "/chat/completions", json={
                "model": model, "messages": [{"role": "user", "content": "Hi"}],
                "max_tokens": 1, "stream": False,
            }) as response:
                response.raise_for_status()
                return bool((await response.json()).get("choices"))
    except Exception:
        return False


async def health(request):
    available = await llm_available()
    return web.json_response({"ready": available}, status=200 if available else 503)


async def remember(request):
    body = await request.json()
    if not isinstance(body, dict):
        raise web.HTTPBadRequest(text="JSON object is required")
    selected = datasets(body.get("project"), body.get("scope", "project"))
    if len(selected) != 1:
        raise web.HTTPBadRequest(text="remember requires project or global scope")
    text = body.get("text")
    if not isinstance(text, str) or not text.strip():
        raise web.HTTPBadRequest(text="text is required")
    # Binary input forces text ingestion, even when the content is a URL or path.
    content = UploadFile(io.BytesIO(text.encode()), filename="memory.txt")
    async with request.app[LOCK]:
        await request.app[SDK].remember(
            content, dataset_name=selected[0], self_improvement=False, extractor="llm"
        )
    return web.json_response({"stored": True, "scope": body.get("scope", "project")})


async def recall(request):
    body = await request.json()
    if not isinstance(body, dict):
        raise web.HTTPBadRequest(text="JSON object is required")
    selected = datasets(body.get("project"), body.get("scope", "all"))
    query = body.get("query")
    if not isinstance(query, str) or not query.strip():
        raise web.HTTPBadRequest(text="query is required")
    sdk = request.app[SDK]
    async with request.app[LOCK]:
        existing = {dataset.name for dataset in await sdk.datasets.list_datasets()}
        selected = [name for name in selected if name in existing]
        results = await sdk.recall(
            query, datasets=selected, query_type=sdk.SearchType.CHUNKS, top_k=5
        ) if selected else []
    return web.json_response(json.loads(json.dumps(
        results, default=lambda value: value.model_dump(mode="json") if hasattr(value, "model_dump") else str(value)
    )))


SDK = web.AppKey("sdk", object)
LOCK = web.AppKey("lock", asyncio.Lock)


async def initialize(app):
    import cognee

    app[SDK] = cognee
    app[LOCK] = asyncio.Lock()
    await cognee.run_migrations()


async def cleanup(app):
    await app[SDK].wait_for_background_tasks(timeout=8)
    from cognee.infrastructure.databases.graph.get_graph_engine import _create_graph_engine
    from cognee.infrastructure.databases.vector.create_vector_engine import _create_vector_engine

    _create_graph_engine.cache_clear()
    _create_vector_engine.cache_clear()
    await asyncio.gather(
        _create_graph_engine.cache_await_closed(),
        _create_vector_engine.cache_await_closed(),
    )


if __name__ == "__main__":
    app = web.Application(client_max_size=128 * 1024)
    app.add_routes([web.get("/health", health), web.post("/remember", remember), web.post("/recall", recall)])
    app.on_startup.append(initialize)
    app.on_cleanup.append(cleanup)
    web.run_app(app, host="127.0.0.1", port=int(os.environ["COGNEE_MEMORY_PORT"]), access_log=None)
