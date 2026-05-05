from __future__ import annotations

import pytest
from httpx import ASGITransport, AsyncClient

from canvas.backend.main import build_app


@pytest.fixture
def app():
    return build_app()


async def test_session_start_and_stop(app) -> None:
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        payload = {
            "nodes": [
                {
                    "id": "floor-1",
                    "type": "FloorNode",
                    "data": {
                        "policy": "SEQUENTIAL",
                        "topic": "test topic",
                        "maxTurns": 1,
                        "showFloorEvents": False,
                        "noHuman": True,
                    },
                }
            ],
            "edges": [],
        }

        response = await client.post("/session/start", json=payload)
        assert response.status_code == 200
        assert response.json()["session_id"]

        status_response = await client.get("/session/status")
        assert status_response.status_code == 200
        assert status_response.json()["running"] is True

        stop_response = await client.delete("/session/stop")
        assert stop_response.status_code == 200

        final_status_response = await client.get("/session/status")
        assert final_status_response.status_code == 200
        assert final_status_response.json()["running"] is False


async def test_media_path_traversal_rejected(app) -> None:
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/media/../../../etc/passwd")
        assert response.status_code in (400, 404)


async def test_session_status_no_session(app) -> None:
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/session/status")
        assert response.status_code == 200
        assert response.json()["running"] is False


async def test_agents_list_returns_sorted_entries(app) -> None:
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/agents/list")
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list)
    assert len(data) > 0
    first = data[0]
    assert {"slug", "display_name", "category"} <= first.keys()
    slugs = [item["slug"] for item in data]
    assert slugs == sorted(slugs)


async def test_models_list_returns_grouped_providers(app) -> None:
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/models/list")
    assert response.status_code == 200
    data = response.json()
    assert {"anthropic", "openai", "google", "huggingface"} <= data.keys()
    assert any("claude" in m for m in data["anthropic"])
    assert any("gpt" in m for m in data["openai"])
    assert any("gemini" in m for m in data["google"])
    assert data["huggingface"] == []


async def test_agent_type_field_accepted_in_start(app) -> None:
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        payload = {
            "nodes": [
                {
                    "id": "floor-1",
                    "type": "FloorNode",
                    "data": {
                        "policy": "SEQUENTIAL",
                        "topic": "",
                        "maxTurns": 1,
                        "showFloorEvents": False,
                        "noHuman": True,
                        "agentType": "",
                    },
                },
                {
                    "id": "agent-1",
                    "type": "AgentNode",
                    "data": {
                        "provider": "anthropic",
                        "name": "Writer",
                        "system": "You are a writer.",
                        "model": "",
                        "agentType": "code-generation",
                    },
                },
            ],
            "edges": [],
        }
        response = await client.post("/session/start", json=payload)
    # Just check it doesn't 422 — agentType must be accepted
    assert response.status_code != 422
