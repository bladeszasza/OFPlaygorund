# Canvas Floor Builder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an `ofp-playground canvas` command that opens a ComfyUI-style node canvas where users build a floor visually, run the session, and watch conversation bubbles, floor events, and artifact cards appear on the nodes in real time.

**Architecture:** A thin FastAPI backend (in `canvas/backend/`) wraps the existing OFP runtime via a `SessionBridge` that taps `MessageBus` using the existing `set_collector()` hook and fans events out over a WebSocket. A React + React Flow frontend (in `canvas/frontend/`) renders nodes and cards driven entirely by those WebSocket events. Zero duplication of FloorManager / MessageBus / agent code.

**Tech Stack:** Python: FastAPI, uvicorn. Frontend: React 18, React Flow (@xyflow/react), dagre, Vite, TypeScript.

---

## File Map

**New files:**
```
canvas/
├── backend/
│   ├── __init__.py
│   ├── main.py              ← FastAPI app
│   ├── session_bridge.py    ← asyncio.Queue event bridge + WS broadcast
│   └── requirements.txt
└── frontend/
    ├── index.html
    ├── package.json
    ├── tsconfig.json
    ├── vite.config.ts
    └── src/
        ├── main.tsx
        ├── App.tsx           ← React Flow canvas + sidebar palette
        ├── types.ts          ← shared TS types
        ├── hooks/
        │   └── useSession.ts ← WS connection + event dispatch
        ├── nodes/
        │   ├── FloorNode.tsx
        │   ├── AgentNode.tsx
        │   ├── HumanNode.tsx
        │   └── ConversationNode.tsx
        └── cards/
            ├── ArtifactCard.tsx
            ├── ImageCard.tsx
            └── MemoryCard.tsx

tests/
├── test_session_bridge.py   ← new
└── test_canvas_api.py       ← new
```

**Modified files:**
```
src/ofp_playground/cli.py             ← add `canvas` subcommand
src/ofp_playground/trace/renderer.py  ← add ?live= mode to generated trace.html
pyproject.toml                         ← add [canvas] optional dep group
```

---

## Task 1: Project scaffold

**Files:**
- Create: `canvas/backend/__init__.py`
- Create: `canvas/backend/requirements.txt`
- Create: `canvas/__init__.py` (empty)

- [ ] **Step 1: Create the canvas package structure**

```bash
mkdir -p canvas/backend canvas/frontend/src/nodes canvas/frontend/src/cards canvas/frontend/src/hooks
touch canvas/__init__.py canvas/backend/__init__.py
```

- [ ] **Step 2: Write requirements.txt**

```
# canvas/backend/requirements.txt
fastapi>=0.111.0
uvicorn[standard]>=0.29.0
httpx>=0.27.0
```

- [ ] **Step 3: Add canvas optional dep group to pyproject.toml**

In `pyproject.toml`, after the existing `dev = [...]` block:

```toml
canvas = [
    "fastapi>=0.111.0",
    "uvicorn[standard]>=0.29.0",
]
```

- [ ] **Step 4: Install canvas deps**

```bash
pip install -e ".[canvas]"
```

Expected: installs without errors.

- [ ] **Step 5: Commit**

```bash
git add canvas/ pyproject.toml
git commit -m "chore: scaffold canvas package structure"
```

---

## Task 2: session_bridge.py — event serialization + async bridge

`SessionBridge` implements the same `record()` interface as `EventCollector` so it can be passed to `MessageBus.set_collector()`. It puts events on an `asyncio.Queue` (sync→async safe), keeps a full session event log for replay, and calls through to the real `EventCollector` so `trace.html` still works.

**Files:**
- Create: `canvas/backend/session_bridge.py`
- Create: `tests/test_session_bridge.py`

- [ ] **Step 1: Write failing tests**

```python
# tests/test_session_bridge.py
import asyncio
from unittest.mock import MagicMock
import pytest
from canvas.backend.session_bridge import SessionBridge, _serialize_envelope


def _make_utterance_envelope(speaker_uri: str, text: str) -> MagicMock:
    """Minimal mock of an OFP utterance envelope."""
    token = MagicMock()
    token.value = text
    text_feat = MagicMock()
    text_feat.tokens = [token]
    features = {"text": text_feat}
    de = MagicMock()
    de.features = features
    event = MagicMock()
    event.eventType = "utterance"
    event.dialogEvent = de
    envelope = MagicMock()
    envelope.sender = MagicMock()
    envelope.sender.speakerUri = speaker_uri
    envelope.events = [event]
    return envelope


def _make_floor_envelope(control_type: str, to_uri: str) -> MagicMock:
    event = MagicMock()
    event.eventType = "floorControlEvent"
    event.controlType = control_type
    event.to = MagicMock()
    event.to.speakerUri = to_uri
    envelope = MagicMock()
    envelope.sender = MagicMock()
    envelope.sender.speakerUri = "tag:ofp-playground.local,2025:floor-manager"
    envelope.events = [event]
    return envelope


def test_serialize_utterance():
    env = _make_utterance_envelope("tag:ofp-playground.local,2025:llm-Alice", "Hello world")
    result = _serialize_envelope(env, {"tag:ofp-playground.local,2025:llm-Alice": "Alice"})
    assert result["type"] == "utterance"
    assert result["sender"] == "Alice"
    assert result["text"] == "Hello world"
    assert result["media"] is None


def test_serialize_floor_grant():
    env = _make_floor_envelope("grantFloor", "tag:ofp-playground.local,2025:llm-Bob")
    result = _serialize_envelope(env, {"tag:ofp-playground.local,2025:llm-Bob": "Bob"})
    assert result["type"] == "floor_grant"
    assert result["to"] == "Bob"


def test_serialize_floor_request():
    env = _make_floor_envelope("requestFloor", "tag:ofp-playground.local,2025:floor-manager")
    env.sender.speakerUri = "tag:ofp-playground.local,2025:llm-Carol"
    result = _serialize_envelope(env, {"tag:ofp-playground.local,2025:llm-Carol": "Carol"})
    assert result["type"] == "floor_request"
    assert result["from"] == "Carol"


def test_serialize_unknown_event_returns_none():
    event = MagicMock()
    event.eventType = "inviteEvent"
    envelope = MagicMock()
    envelope.sender = MagicMock()
    envelope.sender.speakerUri = "tag:ofp-playground.local,2025:floor-manager"
    envelope.events = [event]
    result = _serialize_envelope(envelope, {})
    assert result is None


async def test_bridge_queues_and_logs_events():
    bridge = SessionBridge()
    env = _make_utterance_envelope("tag:ofp-playground.local,2025:llm-Alice", "Hi")
    bridge.register_agent("tag:ofp-playground.local,2025:llm-Alice", "Alice")
    bridge.record(env, recipients=set(), is_private=False)
    assert len(bridge.event_log) == 1
    assert bridge.event_log[0]["type"] == "utterance"
    assert not bridge._queue.empty()


async def test_bridge_reset_clears_log():
    bridge = SessionBridge()
    env = _make_utterance_envelope("tag:ofp-playground.local,2025:llm-Alice", "Hi")
    bridge.record(env, recipients=set(), is_private=False)
    bridge.reset()
    assert bridge.event_log == []
    assert bridge._queue.empty()
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
pytest tests/test_session_bridge.py -v
```

Expected: `ImportError` — `canvas.backend.session_bridge` does not exist yet.

- [ ] **Step 3: Implement session_bridge.py**

```python
# canvas/backend/session_bridge.py
"""Bridges MessageBus events to WebSocket clients.

Implements the same record() interface as EventCollector so it can be
passed to MessageBus.set_collector(). Uses asyncio.Queue for the
sync→async handoff (record() is called synchronously from MessageBus.send()).
"""
from __future__ import annotations

import asyncio
import logging
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from openfloor import Envelope
    from fastapi import WebSocket

logger = logging.getLogger(__name__)


def _extract_agent_name(uri: str, agent_names: dict[str, str]) -> str:
    if uri in agent_names:
        return agent_names[uri]
    # fallback: last segment after final colon
    return uri.split(":")[-1].replace("llm-", "").replace("human-", "")


def _serialize_envelope(envelope: "Envelope", agent_names: dict[str, str]) -> dict | None:
    """Convert an OFP envelope to a WS event dict. Returns None for non-displayable events."""
    sender_uri: str = envelope.sender.speakerUri if envelope.sender else "unknown"
    sender_name = _extract_agent_name(sender_uri, agent_names)

    for event in (envelope.events or []):
        event_type = getattr(event, "eventType", type(event).__name__)

        if event_type == "utterance":
            de = getattr(event, "dialogEvent", None)
            text = ""
            media_type = None
            media_url = None
            if de and de.features:
                tf = de.features.get("text")
                if tf and tf.tokens:
                    text = " ".join(t.value for t in tf.tokens if t.value)
                for key in ("image", "video", "audio", "3d"):
                    feat = de.features.get(key)
                    if feat and feat.tokens and feat.tokens[0].value:
                        media_type = key
                        media_url = feat.tokens[0].value
                        break
            return {
                "type": "utterance",
                "sender": sender_name,
                "sender_uri": sender_uri,
                "text": text,
                "media": {"type": media_type, "url": media_url} if media_type else None,
            }

        if event_type == "floorControlEvent":
            control = getattr(event, "controlType", "")
            to_uri = ""
            if hasattr(event, "to") and event.to:
                to_uri = getattr(event.to, "speakerUri", "")
            to_name = _extract_agent_name(to_uri, agent_names) if to_uri else ""

            if control == "grantFloor":
                return {"type": "floor_grant", "to": to_name, "to_uri": to_uri}
            if control == "revokeFloor":
                return {"type": "floor_revoke", "from": sender_name, "from_uri": sender_uri}
            if control == "requestFloor":
                return {"type": "floor_request", "from": sender_name, "from_uri": sender_uri}
            if control == "yieldFloor":
                return {"type": "floor_revoke", "from": sender_name, "from_uri": sender_uri}

        if event_type in ("inviteEvent", "byeEvent", "declineEvent"):
            return None  # handled via agent_joined / agent_kicked REST responses

    return None


class SessionBridge:
    """Collector-compatible bridge from MessageBus to WebSocket clients."""

    def __init__(self) -> None:
        self._agent_names: dict[str, str] = {}
        self._queue: asyncio.Queue = asyncio.Queue()
        self._clients: list["WebSocket"] = []
        self._event_log: list[dict] = []
        self._inner_collector = None  # set to real EventCollector when session starts

    # ── Public API ─────────────────────────────────────────────────────────────

    def reset(self) -> None:
        """Clear state between sessions."""
        self._agent_names = {}
        self._event_log = []
        self._clients = []
        self._queue = asyncio.Queue()
        self._inner_collector = None

    def register_agent(self, uri: str, name: str) -> None:
        self._agent_names[uri] = name
        if self._inner_collector is not None:
            self._inner_collector.register_agent(uri, name)

    def set_inner_collector(self, collector) -> None:
        self._inner_collector = collector

    @property
    def event_log(self) -> list[dict]:
        return list(self._event_log)

    def push_raw(self, event: dict) -> None:
        """Push a pre-built event dict (used for agent_joined, agent_kicked, error, session_ended)."""
        self._event_log.append(event)
        self._queue.put_nowait(event)

    # ── EventCollector interface ────────────────────────────────────────────────

    def record(
        self,
        envelope: "Envelope",
        recipients: set,
        is_private: bool,
        breakout_id=None,
        *,
        scope_id=None,
        scope_kind=None,
        parent_conversation_id=None,
    ) -> None:
        if self._inner_collector is not None:
            self._inner_collector.record(
                envelope=envelope,
                recipients=recipients,
                is_private=is_private,
                breakout_id=breakout_id,
                scope_id=scope_id,
                scope_kind=scope_kind,
                parent_conversation_id=parent_conversation_id,
            )
        event = _serialize_envelope(envelope, self._agent_names)
        if event is not None:
            self._event_log.append(event)
            self._queue.put_nowait(event)

    # ── WebSocket management ───────────────────────────────────────────────────

    async def connect(self, websocket: "WebSocket") -> None:
        await websocket.accept()
        self._clients.append(websocket)
        for event in self._event_log:
            try:
                await websocket.send_json(event)
            except Exception:
                break

    def disconnect(self, websocket: "WebSocket") -> None:
        self._clients = [c for c in self._clients if c is not websocket]

    async def broadcast_loop(self) -> None:
        """Drain the queue and broadcast to all connected clients. Run as asyncio Task."""
        while True:
            event = await self._queue.get()
            dead = []
            for ws in list(self._clients):
                try:
                    await ws.send_json(event)
                except Exception:
                    dead.append(ws)
            for ws in dead:
                self.disconnect(ws)
```

- [ ] **Step 4: Run tests**

```bash
pytest tests/test_session_bridge.py -v
```

Expected: all 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add canvas/backend/session_bridge.py tests/test_session_bridge.py
git commit -m "feat(canvas): add SessionBridge — async event bridge from MessageBus to WebSocket"
```

---

## Task 3: main.py — FastAPI app, REST API, WebSocket

The FastAPI app owns one `SessionBridge` instance and one optional running session task. All handlers are `async def` so they run on the same event loop as the session.

**Files:**
- Create: `canvas/backend/main.py`
- Create: `tests/test_canvas_api.py`

- [ ] **Step 1: Write failing tests**

```python
# tests/test_canvas_api.py
import pytest
from httpx import AsyncClient, ASGITransport


@pytest.fixture
def app():
    from canvas.backend.main import build_app
    return build_app()


async def test_session_start_and_stop(app):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        # Valid minimal graph: one floor node only, no-human mode
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
        r = await client.post("/session/start", json=payload)
        assert r.status_code == 200
        session_id = r.json()["session_id"]
        assert session_id

        r = await client.delete("/session/stop")
        assert r.status_code == 200


async def test_media_path_traversal_rejected(app):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        r = await client.get("/media/../../../etc/passwd")
        assert r.status_code in (400, 404)


async def test_session_status_no_session(app):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        r = await client.get("/session/status")
        assert r.status_code == 200
        assert r.json()["running"] is False
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
pytest tests/test_canvas_api.py -v
```

Expected: `ImportError` — `canvas.backend.main` does not exist yet.

- [ ] **Step 3: Implement main.py**

```python
# canvas/backend/main.py
"""FastAPI application for the OFP Canvas backend."""
from __future__ import annotations

import asyncio
import logging
import os
import sys
from pathlib import Path
from typing import Any, Optional

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

# Make the main ofp_playground package importable when running canvas/
_repo_src = Path(__file__).resolve().parents[2] / "src"
if str(_repo_src) not in sys.path:
    sys.path.insert(0, str(_repo_src))

from ofp_playground.config.settings import Settings
from ofp_playground.floor.policy import FloorPolicy
from canvas.backend.session_bridge import SessionBridge

logger = logging.getLogger(__name__)

RESULT_DIR = Path("result").resolve()

# ── Path safety ────────────────────────────────────────────────────────────────

def _safe_media_path(rel: str) -> Path:
    """Resolve rel inside RESULT_DIR; raise HTTPException 400 on traversal."""
    import os
    if os.path.isabs(rel):
        raise HTTPException(status_code=400, detail="Absolute paths not allowed")
    normed = os.path.normpath(rel)
    if normed.startswith("..") or "/.." in normed:
        raise HTTPException(status_code=400, detail="Path traversal not allowed")
    resolved = (RESULT_DIR / normed).resolve()
    if not str(resolved).startswith(str(RESULT_DIR)):
        raise HTTPException(status_code=400, detail="Path outside result dir")
    return resolved


# ── Request / Response models ──────────────────────────────────────────────────

class NodeData(BaseModel):
    policy: str = "SEQUENTIAL"
    topic: str = ""
    maxTurns: Optional[int] = None
    showFloorEvents: bool = False
    noHuman: bool = True
    # AgentNode fields
    provider: str = ""
    name: str = ""
    model: str = ""
    systemPrompt: str = ""
    slug: str = ""
    # HumanNode fields
    humanName: str = "User"


class CanvasNode(BaseModel):
    id: str
    type: str  # "FloorNode" | "AgentNode" | "HumanNode"
    data: NodeData


class CanvasEdge(BaseModel):
    source: str
    target: str


class StartRequest(BaseModel):
    nodes: list[CanvasNode]
    edges: list[CanvasEdge]


class AddAgentRequest(BaseModel):
    provider: str
    name: str
    model: str = ""
    systemPrompt: str = ""
    slug: str = ""


class HumanMessageRequest(BaseModel):
    text: str


# ── App factory ────────────────────────────────────────────────────────────────

def build_app() -> FastAPI:
    app = FastAPI(title="OFP Canvas")
    bridge = SessionBridge()
    settings = Settings()

    # Runtime state
    state: dict[str, Any] = {
        "session_task": None,
        "session_id": None,
        "floor": None,
        "bus": None,
        "registry": None,
        "broadcast_task": None,
    }

    # ── WebSocket ──────────────────────────────────────────────────────────────

    @app.websocket("/ws/{session_id}")
    async def ws_endpoint(websocket: WebSocket, session_id: str):
        await bridge.connect(websocket)
        try:
            while True:
                await websocket.receive_text()  # keep alive; we only send
        except WebSocketDisconnect:
            bridge.disconnect(websocket)

    # ── Session lifecycle ──────────────────────────────────────────────────────

    @app.post("/session/start")
    async def session_start(req: StartRequest):
        if state["session_task"] and not state["session_task"].done():
            raise HTTPException(status_code=409, detail="Session already running")

        floor_node = next((n for n in req.nodes if n.type == "FloorNode"), None)
        if not floor_node:
            raise HTTPException(status_code=422, detail="Missing FloorNode")

        fd = floor_node.data
        policy = _parse_policy(fd.policy)

        agent_nodes = [n for n in req.nodes if n.type == "AgentNode"]
        human_nodes = [n for n in req.nodes if n.type == "HumanNode"]
        no_human = fd.noHuman and not human_nodes

        bridge.reset()

        # Start broadcast loop
        if state["broadcast_task"] and not state["broadcast_task"].done():
            state["broadcast_task"].cancel()
        state["broadcast_task"] = asyncio.create_task(bridge.broadcast_loop())

        # Build agent_specs tuple for _start_canvas_session
        agent_specs: list[str] = []
        for node in agent_nodes:
            d = node.data
            desc = d.slug or d.systemPrompt or ""
            model_part = f":{d.model}" if d.model else ""
            agent_specs.append(f"{d.provider}:{d.name}:{desc}{model_part}")

        human_name = human_nodes[0].data.humanName if human_nodes else "User"

        import uuid
        session_id = str(uuid.uuid4())[:8]
        state["session_id"] = session_id

        state["session_task"] = asyncio.create_task(
            _run_canvas_session(
                bridge=bridge,
                settings=settings,
                policy=policy,
                agent_specs=tuple(agent_specs),
                topic=fd.topic or None,
                max_turns=fd.maxTurns,
                no_human=no_human,
                human_name=human_name,
                show_floor_events=fd.showFloorEvents,
                state=state,
                session_id=session_id,
            )
        )
        return {"session_id": session_id}

    @app.delete("/session/stop")
    async def session_stop():
        if state["floor"]:
            await state["floor"].stop()
        if state["session_task"] and not state["session_task"].done():
            state["session_task"].cancel()
        bridge.push_raw({"type": "session_ended"})
        return {"ok": True}

    @app.get("/session/status")
    async def session_status():
        running = bool(state["session_task"] and not state["session_task"].done())
        return {
            "running": running,
            "session_id": state["session_id"],
        }

    # ── Agent management ────────────────────────────────────────────────────────

    @app.post("/session/agent/add")
    async def agent_add(req: AddAgentRequest):
        if not state["floor"] or not state["bus"]:
            raise HTTPException(status_code=409, detail="No active session")
        from ofp_playground.cli import _spawn_llm_agent
        from ofp_playground.agents.registry import AgentRegistry
        registry = state["registry"] or AgentRegistry()
        desc = req.slug or req.systemPrompt or ""
        await _spawn_llm_agent(
            agent_type=req.provider,
            name=req.name,
            description=desc,
            floor=state["floor"],
            bus=state["bus"],
            registry=registry,
            renderer=state["renderer"],
            settings=settings,
            model_override=req.model or None,
        )
        bridge.push_raw({"type": "agent_joined", "name": req.name, "uri": ""})
        return {"ok": True}

    @app.delete("/session/agent/{name}")
    async def agent_kick(name: str):
        if not state["floor"]:
            raise HTTPException(status_code=409, detail="No active session")
        await state["floor"].kick_agent(name)
        bridge.push_raw({"type": "agent_kicked", "name": name})
        return {"ok": True}

    # ── Human message ───────────────────────────────────────────────────────────

    @app.post("/session/message")
    async def human_message(req: HumanMessageRequest):
        if not state.get("human_agent"):
            raise HTTPException(status_code=409, detail="No human agent in session")
        await state["human_agent"].inject_message(req.text)
        return {"ok": True}

    # ── Media serving ────────────────────────────────────────────────────────────

    @app.get("/media/{path:path}")
    async def serve_media(path: str):
        resolved = _safe_media_path(path)
        if not resolved.exists():
            raise HTTPException(status_code=404, detail="File not found")
        return FileResponse(resolved)

    # ── Live trace ───────────────────────────────────────────────────────────────

    @app.get("/trace/live")
    async def trace_live(session: str = ""):
        from ofp_playground.trace.renderer import render_trace_html
        from ofp_playground.trace.collector import EventCollector
        collector = state.get("collector")
        if not collector:
            return {"error": "no session"}
        html = render_trace_html(collector, live_session_id=session)
        from fastapi.responses import HTMLResponse
        return HTMLResponse(html)

    # ── Static frontend ──────────────────────────────────────────────────────────
    dist = Path(__file__).parent.parent / "frontend" / "dist"
    if dist.exists():
        app.mount("/", StaticFiles(directory=str(dist), html=True), name="static")

    return app


def _parse_policy(s: str) -> FloorPolicy:
    try:
        return FloorPolicy[s.upper()]
    except KeyError:
        return FloorPolicy.SEQUENTIAL


async def _run_canvas_session(
    bridge: SessionBridge,
    settings: Settings,
    policy: FloorPolicy,
    agent_specs: tuple[str, ...],
    topic: str | None,
    max_turns: int | None,
    no_human: bool,
    human_name: str,
    show_floor_events: bool,
    state: dict,
    session_id: str,
) -> None:
    """Start an OFP session reusing the same code path as the CLI."""
    from ofp_playground.bus.message_bus import MessageBus
    from ofp_playground.floor.manager import FloorManager
    from ofp_playground.renderer.terminal import TerminalRenderer
    from ofp_playground.agents.registry import AgentRegistry
    from ofp_playground.trace.collector import EventCollector
    from ofp_playground.cli import _spawn_llm_agent, _attach_floor_callbacks, _seed_topic
    from rich.console import Console

    console = Console(quiet=True)  # suppress terminal output in canvas mode
    renderer = TerminalRenderer(console, show_floor_events=show_floor_events)

    bus = MessageBus()
    floor = FloorManager(bus, policy=policy, renderer=renderer)

    collector = EventCollector(floor.conversation_id)
    bridge.set_inner_collector(collector)
    bus.set_collector(bridge)  # bridge proxies to collector

    state["floor"] = floor
    state["bus"] = bus
    state["renderer"] = renderer
    state["collector"] = collector

    registry = AgentRegistry()
    state["registry"] = registry

    await _attach_floor_callbacks(floor, bus, registry, settings, renderer)

    tasks = [floor.run()]

    # Spawn LLM agents from spec
    for spec in agent_specs:
        parts = spec.split(":", 2)
        provider = parts[0]
        name = parts[1] if len(parts) > 1 else "Agent"
        desc = parts[2] if len(parts) > 2 else ""
        bridge.register_agent(f"tag:ofp-playground.local,2025:llm-{name}", name)
        await _spawn_llm_agent(
            agent_type=provider,
            name=name,
            description=desc,
            floor=floor,
            bus=bus,
            registry=registry,
            renderer=renderer,
            settings=settings,
        )
        bridge.push_raw({"type": "agent_joined", "name": name, "uri": f"tag:ofp-playground.local,2025:llm-{name}"})

    if not no_human:
        from ofp_playground.agents.human import HumanAgent
        human = HumanAgent(
            name=human_name,
            bus=bus,
            conversation_id=floor.conversation_id,
            renderer=renderer,
            floor_policy=policy.value,
        )
        floor.register_agent(human.speaker_uri, human.name)
        registry.register(human)
        state["human_agent"] = human
        tasks.append(human.run())

    if topic:
        await _seed_topic(topic, floor, bus)

    if max_turns:
        floor.max_turns = max_turns

    try:
        await asyncio.gather(*tasks)
    finally:
        bridge.push_raw({"type": "session_ended"})
        # Write final trace
        from ofp_playground.trace.renderer import render_trace_html
        from ofp_playground.config.output import SessionOutputManager
        out = SessionOutputManager(floor.conversation_id)
        html = render_trace_html(collector)
        (out.session_dir / "trace.html").write_text(html)
```

- [ ] **Step 4: Run tests**

```bash
pytest tests/test_canvas_api.py -v
```

Expected: all 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add canvas/backend/main.py tests/test_canvas_api.py
git commit -m "feat(canvas): add FastAPI backend with REST API and WebSocket endpoint"
```

---

## Task 4: CLI canvas subcommand

**Files:**
- Modify: `src/ofp_playground/cli.py` (add `canvas` command near the `web` command, ~line 1325)

- [ ] **Step 1: Write failing test**

```python
# Add to tests/test_cli_agent_specs.py or a new test file
from click.testing import CliRunner
from ofp_playground.cli import main

def test_canvas_command_exists():
    runner = CliRunner()
    result = runner.invoke(main, ["canvas", "--help"])
    assert result.exit_code == 0
    assert "--port" in result.output
```

- [ ] **Step 2: Run to confirm failure**

```bash
pytest -k "test_canvas_command_exists" -v
```

Expected: FAIL — `No such command 'canvas'`.

- [ ] **Step 3: Add canvas command to cli.py**

Find the `web` command (around line 1325). After its closing block, add:

```python
@main.command("canvas")
@click.option("--port", default=8765, show_default=True, help="Port for the canvas server.")
@click.option("--host", default="localhost", show_default=True, help="Host to bind.")
@click.option("--open/--no-open", "open_browser", default=True, show_default=True)
@click.pass_context
def canvas(ctx: click.Context, port: int, host: str, open_browser: bool) -> None:
    """Launch the ComfyUI-style visual canvas for building and running floors."""
    import sys
    from pathlib import Path

    # Ensure canvas package is importable
    canvas_dir = Path(__file__).resolve().parents[2] / "canvas"
    if str(canvas_dir.parent) not in sys.path:
        sys.path.insert(0, str(canvas_dir.parent))

    try:
        import uvicorn
        from canvas.backend.main import build_app
    except ImportError:
        raise click.ClickException(
            "Canvas dependencies not installed. Run: pip install -e '.[canvas]'"
        )

    app = build_app()
    url = f"http://{host}:{port}"

    if open_browser:
        import threading, webbrowser
        threading.Timer(1.0, lambda: webbrowser.open(url)).start()

    click.echo(f"Canvas running at {url}")
    uvicorn.run(app, host=host, port=port, log_level="warning")
```

- [ ] **Step 4: Run test**

```bash
pytest -k "test_canvas_command_exists" -v
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/ofp_playground/cli.py
git commit -m "feat(canvas): add canvas CLI subcommand"
```

---

## Task 5: Live trace mode in renderer.py

Add a `live_session_id` parameter to `render_trace_html`. When set, the generated HTML bootstraps a WebSocket connection to `/ws/<session_id>` and appends events to the D3 timeline instead of rendering the static blob.

**Files:**
- Modify: `src/ofp_playground/trace/renderer.py`

- [ ] **Step 1: Find the render function signature**

```bash
grep -n "def render_trace_html" src/ofp_playground/trace/renderer.py
```

Note the line number. The function currently takes `(collector: EventCollector)` or similar.

- [ ] **Step 2: Add live_session_id parameter**

In `renderer.py`, find `def render_trace_html(` and add the optional parameter:

```python
def render_trace_html(collector: EventCollector, live_session_id: str | None = None) -> str:
```

- [ ] **Step 3: Inject live-mode bootstrap into the generated HTML**

After the function builds the `html` string (before the final `return html`), insert:

```python
    if live_session_id:
        live_script = f"""
<script>
(function() {{
  var WS_SESSION = "{live_session_id}";
  var ws = new WebSocket("ws://" + location.host + "/ws/" + WS_SESSION);
  ws.onmessage = function(ev) {{
    try {{
      var event = JSON.parse(ev.data);
      if (typeof window._appendLiveEvent === "function") {{
        window._appendLiveEvent(event);
      }}
    }} catch(e) {{}}
  }};
}})();
</script>"""
        # Insert before closing </body>
        html = html.replace("</body>", live_script + "\n</body>")
    return html
```

Also add a stub `window._appendLiveEvent` near the end of the existing D3 JS (just before `</script>`) so the canvas can call it once the D3 graph is initialised:

```javascript
// Live mode hook — canvas/backend/main.py populates this when ?live= is set
window._appendLiveEvent = function(event) {
  // Minimal live append: re-render with updated data
  // Full implementation: push to traceData array and call renderTimeline()
  console.log("[live]", event);
};
```

- [ ] **Step 4: Verify existing tests still pass**

```bash
pytest tests/ -v --tb=short
```

Expected: all existing tests pass (the new parameter is optional with default `None`).

- [ ] **Step 5: Commit**

```bash
git add src/ofp_playground/trace/renderer.py
git commit -m "feat(canvas): add live_session_id param to render_trace_html for live D3 trace"
```

---

## Task 6: Frontend scaffold

**Files:**
- Create: `canvas/frontend/package.json`
- Create: `canvas/frontend/tsconfig.json`
- Create: `canvas/frontend/vite.config.ts`
- Create: `canvas/frontend/index.html`
- Create: `canvas/frontend/src/main.tsx`

- [ ] **Step 1: Write package.json**

```json
{
  "name": "ofp-canvas",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc && vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "@xyflow/react": "^12.3.0",
    "dagre": "^0.8.5",
    "react": "^18.3.1",
    "react-dom": "^18.3.1"
  },
  "devDependencies": {
    "@types/dagre": "^0.8.3",
    "@types/react": "^18.3.1",
    "@types/react-dom": "^18.3.1",
    "@vitejs/plugin-react": "^4.3.1",
    "typescript": "^5.4.5",
    "vite": "^5.4.0"
  }
}
```

- [ ] **Step 2: Write tsconfig.json**

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "isolatedModules": true,
    "moduleDetection": "force",
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true
  },
  "include": ["src"]
}
```

- [ ] **Step 3: Write vite.config.ts**

```typescript
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/ws': { target: 'ws://localhost:8765', ws: true },
      '/session': 'http://localhost:8765',
      '/media': 'http://localhost:8765',
      '/trace': 'http://localhost:8765',
    }
  }
})
```

- [ ] **Step 4: Write index.html**

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>OFP Canvas</title>
    <style>
      * { margin: 0; padding: 0; box-sizing: border-box; }
      html, body, #root { width: 100%; height: 100%; background: #1a1a2e; color: #e0e0e0; font-family: system-ui, sans-serif; }
    </style>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```

- [ ] **Step 5: Write src/main.tsx**

```tsx
import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'
import '@xyflow/react/dist/style.css'

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
)
```

- [ ] **Step 6: Install deps and verify build**

```bash
cd canvas/frontend
npm install
npm run build
```

Expected: `dist/` created with no TypeScript errors.

- [ ] **Step 7: Commit**

```bash
cd ../..
git add canvas/frontend/package.json canvas/frontend/tsconfig.json canvas/frontend/vite.config.ts canvas/frontend/index.html canvas/frontend/src/main.tsx
git commit -m "feat(canvas): scaffold React + React Flow frontend"
```

---

## Task 7: Shared types + useSession hook

**Files:**
- Create: `canvas/frontend/src/types.ts`
- Create: `canvas/frontend/src/hooks/useSession.ts`

- [ ] **Step 1: Write types.ts**

```typescript
// canvas/frontend/src/types.ts

export type FloorPolicy =
  | 'SEQUENTIAL' | 'ROUND_ROBIN' | 'MODERATED' | 'FREE_FOR_ALL' | 'SHOWRUNNER_DRIVEN'

export type AgentProvider = 'anthropic' | 'openai' | 'google' | 'huggingface'

export type SessionState = 'idle' | 'running' | 'stopped'

export type AgentFloorState = 'speaking' | 'waiting' | 'requesting' | 'error' | 'spawning'

export interface Message {
  text: string
  timestamp: string
  media?: { type: string; url: string } | null
}

export interface FloorNodeData {
  policy: FloorPolicy
  topic: string
  maxTurns: number | null
  showFloorEvents: boolean
  noHuman: boolean
  sessionState: SessionState
  turnCount: number
  elapsedSeconds: number
  sessionId: string | null
}

export interface AgentNodeData {
  provider: AgentProvider
  name: string
  model: string
  systemPrompt: string
  slug: string
  floorState: AgentFloorState
  messages: Message[]
  errorMessage?: string
}

export interface HumanNodeData {
  humanName: string
  messages: Message[]
}

export interface ConversationNodeData {
  sessionId: string | null
  policy: FloorPolicy | null
  topic: string
  turnCount: number
}

export interface ArtifactCardData {
  id: string
  kind: 'markdown' | 'image' | 'memory'
  agent: string
  slug?: string
  preview?: string
  url?: string
  category?: string
  content?: string
  x: number
  y: number
}

// WebSocket event union
export type WSEvent =
  | { type: 'utterance'; sender: string; sender_uri: string; text: string; media: { type: string; url: string } | null }
  | { type: 'floor_grant'; to: string; to_uri: string }
  | { type: 'floor_revoke'; from: string; from_uri: string }
  | { type: 'floor_request'; from: string; from_uri: string }
  | { type: 'artifact_saved'; slug: string; kind: string; agent: string; preview: string }
  | { type: 'image_saved'; agent: string; url: string }
  | { type: 'memory_saved'; category: string; content: string; agent: string | null }
  | { type: 'agent_joined'; name: string; uri: string }
  | { type: 'agent_kicked'; name: string }
  | { type: 'error'; agent: string; message: string; retryable: boolean }
  | { type: 'session_ended' }
```

- [ ] **Step 2: Write useSession.ts**

```typescript
// canvas/frontend/src/hooks/useSession.ts
import { useEffect, useRef, useCallback, useState } from 'react'
import type { WSEvent } from '../types'

export interface UseSessionOptions {
  sessionId: string | null
  onEvent: (event: WSEvent) => void
}

export function useSession({ sessionId, onEvent }: UseSessionOptions) {
  const wsRef = useRef<WebSocket | null>(null)
  const [connected, setConnected] = useState(false)
  const onEventRef = useRef(onEvent)
  onEventRef.current = onEvent

  useEffect(() => {
    if (!sessionId) return

    function connect() {
      const ws = new WebSocket(`ws://${location.host}/ws/${sessionId}`)
      wsRef.current = ws

      ws.onopen = () => setConnected(true)

      ws.onmessage = (ev) => {
        try {
          const event: WSEvent = JSON.parse(ev.data)
          onEventRef.current(event)
        } catch {
          // ignore malformed frames
        }
      }

      ws.onclose = () => {
        setConnected(false)
        // Reconnect after 2s
        setTimeout(connect, 2000)
      }

      ws.onerror = () => ws.close()
    }

    connect()
    return () => {
      wsRef.current?.close()
    }
  }, [sessionId])

  const sendMessage = useCallback(async (text: string) => {
    await fetch('/session/message', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text }),
    })
  }, [])

  const kickAgent = useCallback(async (name: string) => {
    await fetch(`/session/agent/${encodeURIComponent(name)}`, { method: 'DELETE' })
  }, [])

  return { connected, sendMessage, kickAgent }
}
```

- [ ] **Step 3: Verify TypeScript compiles**

```bash
cd canvas/frontend && npm run build
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
cd ../..
git add canvas/frontend/src/types.ts canvas/frontend/src/hooks/useSession.ts
git commit -m "feat(canvas): add shared TS types and useSession WebSocket hook"
```

---

## Task 8: FloorNode component

**Files:**
- Create: `canvas/frontend/src/nodes/FloorNode.tsx`

- [ ] **Step 1: Write FloorNode.tsx**

```tsx
// canvas/frontend/src/nodes/FloorNode.tsx
import { Handle, Position, NodeProps } from '@xyflow/react'
import type { FloorNodeData, FloorPolicy } from '../types'

const POLICIES: FloorPolicy[] = [
  'SEQUENTIAL', 'ROUND_ROBIN', 'MODERATED', 'FREE_FOR_ALL', 'SHOWRUNNER_DRIVEN'
]

const STATE_COLOR: Record<string, string> = {
  idle: '#555',
  running: '#4caf50',
  stopped: '#f44336',
}

interface Props extends NodeProps {
  data: FloorNodeData
  onRun: () => void
  onStop: () => void
  onChange: (patch: Partial<FloorNodeData>) => void
}

export function FloorNode({ data, onRun, onStop, onChange }: Props) {
  const color = STATE_COLOR[data.sessionState]
  return (
    <div style={{
      background: '#16213e', border: `2px solid ${color}`,
      borderRadius: 12, padding: 16, minWidth: 260, color: '#e0e0e0',
    }}>
      <div style={{ fontWeight: 700, fontSize: 14, marginBottom: 10, color }}>
        Floor  <span style={{ fontSize: 11, opacity: 0.6 }}>{data.sessionState}</span>
      </div>

      <label style={{ fontSize: 11, opacity: 0.7 }}>Policy</label>
      <select
        value={data.policy}
        onChange={e => onChange({ policy: e.target.value as FloorPolicy })}
        disabled={data.sessionState === 'running'}
        style={{ width: '100%', marginBottom: 8, background: '#0f3460', color: '#e0e0e0', border: '1px solid #333', borderRadius: 4, padding: 4 }}
      >
        {POLICIES.map(p => <option key={p}>{p}</option>)}
      </select>

      <label style={{ fontSize: 11, opacity: 0.7 }}>Topic / seed prompt</label>
      <input
        value={data.topic}
        onChange={e => onChange({ topic: e.target.value })}
        disabled={data.sessionState === 'running'}
        placeholder="Optional opening message…"
        style={{ width: '100%', marginBottom: 8, background: '#0f3460', color: '#e0e0e0', border: '1px solid #333', borderRadius: 4, padding: 4 }}
      />

      <label style={{ fontSize: 11, opacity: 0.7 }}>Max turns</label>
      <input
        type="number"
        value={data.maxTurns ?? ''}
        onChange={e => onChange({ maxTurns: e.target.value ? Number(e.target.value) : null })}
        disabled={data.sessionState === 'running'}
        placeholder="Unlimited"
        style={{ width: '100%', marginBottom: 8, background: '#0f3460', color: '#e0e0e0', border: '1px solid #333', borderRadius: 4, padding: 4 }}
      />

      <label style={{ fontSize: 11 }}>
        <input
          type="checkbox"
          checked={data.noHuman}
          onChange={e => onChange({ noHuman: e.target.checked })}
          disabled={data.sessionState === 'running'}
          style={{ marginRight: 4 }}
        />
        Fully autonomous (no human input)
      </label>

      {data.sessionState === 'running' && (
        <div style={{ marginTop: 8, fontSize: 11, opacity: 0.7 }}>
          Turn {data.turnCount}  ·  {data.elapsedSeconds}s
        </div>
      )}

      <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
        {data.sessionState !== 'running' ? (
          <button onClick={onRun} style={{ flex: 1, background: '#4caf50', color: '#fff', border: 'none', borderRadius: 6, padding: '6px 0', cursor: 'pointer', fontWeight: 700 }}>
            ▶ Run
          </button>
        ) : (
          <button onClick={onStop} style={{ flex: 1, background: '#f44336', color: '#fff', border: 'none', borderRadius: 6, padding: '6px 0', cursor: 'pointer', fontWeight: 700 }}>
            ■ Stop
          </button>
        )}
      </div>

      <Handle type="source" position={Position.Right} style={{ background: color }} />
    </div>
  )
}
```

- [ ] **Step 2: Build to verify no TS errors**

```bash
cd canvas/frontend && npm run build
```

- [ ] **Step 3: Commit**

```bash
cd ../..
git add canvas/frontend/src/nodes/FloorNode.tsx
git commit -m "feat(canvas): add FloorNode component"
```

---

## Task 9: AgentNode component

**Files:**
- Create: `canvas/frontend/src/nodes/AgentNode.tsx`

- [ ] **Step 1: Write AgentNode.tsx**

```tsx
// canvas/frontend/src/nodes/AgentNode.tsx
import { useState } from 'react'
import { Handle, Position, NodeProps } from '@xyflow/react'
import type { AgentNodeData } from '../types'

const PROVIDER_COLOR: Record<string, string> = {
  anthropic: '#d4a843',
  openai: '#10a37f',
  google: '#4285f4',
  huggingface: '#ff7b00',
}

const STATE_COLOR: Record<string, string> = {
  speaking: '#4caf50',
  waiting: '#555',
  requesting: '#ff9800',
  error: '#f44336',
  spawning: '#9c27b0',
}

const STATE_LABEL: Record<string, string> = {
  speaking: '🎙 speaking',
  waiting: '⏳ waiting',
  requesting: '✋ requesting',
  error: '⚠ error',
  spawning: '⚙ spawning',
}

interface Props extends NodeProps {
  data: AgentNodeData
  onKick: (name: string) => void
}

export function AgentNode({ data, onKick }: Props) {
  const [hovered, setHovered] = useState(false)
  const [expanded, setExpanded] = useState(false)
  const providerColor = PROVIDER_COLOR[data.provider] || '#888'
  const stateColor = STATE_COLOR[data.floorState] || '#555'

  return (
    <div
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      style={{
        background: '#16213e',
        border: `2px solid ${stateColor}`,
        borderRadius: 10,
        padding: 12,
        minWidth: 220,
        maxWidth: 280,
        color: '#e0e0e0',
        transition: 'border-color 0.2s',
      }}
    >
      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
        <span style={{
          background: providerColor, color: '#000', fontSize: 10, fontWeight: 700,
          padding: '1px 6px', borderRadius: 4, textTransform: 'uppercase',
        }}>
          {data.provider}
        </span>
        <span style={{ fontWeight: 700, fontSize: 13, flex: 1 }}>{data.name}</span>
        {hovered && (
          <button
            onClick={() => onKick(data.name)}
            title="Kick agent"
            style={{ background: '#f44336', border: 'none', color: '#fff', borderRadius: 4, padding: '2px 6px', cursor: 'pointer', fontSize: 11 }}
          >
            kick
          </button>
        )}
      </div>

      {/* Floor state chip */}
      <div style={{ fontSize: 11, color: stateColor, marginBottom: 6 }}>
        {STATE_LABEL[data.floorState]}
        {data.floorState === 'error' && data.errorMessage && (
          <span title={data.errorMessage}> ⓘ</span>
        )}
      </div>

      {/* System prompt (collapsed) */}
      {data.systemPrompt && (
        <div
          onClick={() => setExpanded(!expanded)}
          style={{ fontSize: 10, opacity: 0.6, cursor: 'pointer', marginBottom: 6, whiteSpace: expanded ? 'pre-wrap' : 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}
        >
          {expanded ? data.systemPrompt : `📋 ${data.systemPrompt.slice(0, 40)}…`}
        </div>
      )}

      {/* Conversation bubbles */}
      <div style={{ maxHeight: 140, overflowY: 'auto' }}>
        {data.messages.slice(-5).map((msg, i) => (
          <div key={i} style={{
            background: '#0f3460', borderRadius: 6, padding: '4px 8px',
            marginBottom: 4, fontSize: 11, lineHeight: 1.4,
          }}>
            {msg.text.slice(0, 120)}{msg.text.length > 120 ? '…' : ''}
            {msg.media && (
              <div style={{ marginTop: 4 }}>
                {msg.media.type === 'image' && (
                  <img src={`/media/${msg.media.url}`} alt="" style={{ maxWidth: '100%', borderRadius: 4 }} />
                )}
                {msg.media.type !== 'image' && (
                  <a href={`/media/${msg.media.url}`} target="_blank" style={{ color: '#4caf50', fontSize: 10 }}>
                    📎 {msg.media.type}
                  </a>
                )}
              </div>
            )}
          </div>
        ))}
      </div>

      <Handle type="target" position={Position.Left} />
      <Handle type="source" position={Position.Right} />
    </div>
  )
}
```

- [ ] **Step 2: Build**

```bash
cd canvas/frontend && npm run build
```

- [ ] **Step 3: Commit**

```bash
cd ../..
git add canvas/frontend/src/nodes/AgentNode.tsx
git commit -m "feat(canvas): add AgentNode with floor-state badge, conversation bubbles, kick button"
```

---

## Task 10: HumanNode + ConversationNode

**Files:**
- Create: `canvas/frontend/src/nodes/HumanNode.tsx`
- Create: `canvas/frontend/src/nodes/ConversationNode.tsx`

- [ ] **Step 1: Write HumanNode.tsx**

```tsx
// canvas/frontend/src/nodes/HumanNode.tsx
import { useState, KeyboardEvent } from 'react'
import { Handle, Position, NodeProps } from '@xyflow/react'
import type { HumanNodeData } from '../types'

interface Props extends NodeProps {
  data: HumanNodeData
  onSend: (text: string) => void
  sessionRunning: boolean
}

export function HumanNode({ data, onSend, sessionRunning }: Props) {
  const [text, setText] = useState('')

  function send() {
    if (!text.trim()) return
    onSend(text.trim())
    setText('')
  }

  function onKey(e: KeyboardEvent<HTMLTextAreaElement>) {
    if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send() }
  }

  return (
    <div style={{ background: '#16213e', border: '2px solid #4a90d9', borderRadius: 10, padding: 12, minWidth: 220, color: '#e0e0e0' }}>
      <div style={{ fontWeight: 700, fontSize: 13, marginBottom: 8 }}>👤 {data.humanName}</div>

      <div style={{ maxHeight: 100, overflowY: 'auto', marginBottom: 8 }}>
        {data.messages.slice(-3).map((msg, i) => (
          <div key={i} style={{ background: '#0f3460', borderRadius: 6, padding: '4px 8px', marginBottom: 4, fontSize: 11 }}>
            {msg.text}
          </div>
        ))}
      </div>

      {sessionRunning && (
        <div style={{ display: 'flex', gap: 6 }}>
          <textarea
            value={text}
            onChange={e => setText(e.target.value)}
            onKeyDown={onKey}
            rows={2}
            placeholder="Type a message… (Enter to send)"
            style={{ flex: 1, background: '#0f3460', color: '#e0e0e0', border: '1px solid #333', borderRadius: 4, padding: 4, resize: 'none', fontSize: 11 }}
          />
          <button onClick={send} style={{ background: '#4a90d9', border: 'none', color: '#fff', borderRadius: 6, padding: '0 12px', cursor: 'pointer', fontWeight: 700 }}>
            ➤
          </button>
        </div>
      )}
      <Handle type="target" position={Position.Left} />
    </div>
  )
}
```

- [ ] **Step 2: Write ConversationNode.tsx**

```tsx
// canvas/frontend/src/nodes/ConversationNode.tsx
import { NodeProps } from '@xyflow/react'
import type { ConversationNodeData } from '../types'

interface Props extends NodeProps {
  data: ConversationNodeData
}

export function ConversationNode({ data }: Props) {
  const liveUrl = data.sessionId ? `/trace/live?session=${data.sessionId}` : null

  function openFullscreen() {
    if (liveUrl) window.open(liveUrl, '_blank')
  }

  return (
    <div style={{ background: '#16213e', border: '2px solid #8b6bb1', borderRadius: 10, padding: 0, minWidth: 340, color: '#e0e0e0', overflow: 'hidden' }}>
      <div style={{ display: 'flex', alignItems: 'center', padding: '8px 12px', borderBottom: '1px solid #333' }}>
        <span style={{ fontWeight: 700, fontSize: 13, flex: 1 }}>🗂 Conversation Trace</span>
        <span style={{ fontSize: 11, opacity: 0.6, marginRight: 8 }}>
          {data.policy}  ·  turn {data.turnCount}
        </span>
        {liveUrl && (
          <button onClick={openFullscreen} title="Open in new tab" style={{ background: 'none', border: '1px solid #8b6bb1', color: '#8b6bb1', borderRadius: 4, padding: '2px 8px', cursor: 'pointer', fontSize: 11 }}>
            ↗
          </button>
        )}
      </div>

      {liveUrl ? (
        <iframe
          src={liveUrl}
          style={{ width: '100%', height: 320, border: 'none' }}
          title="Live trace"
        />
      ) : (
        <div style={{ padding: 20, textAlign: 'center', opacity: 0.5, fontSize: 12 }}>
          Start a session to see the live trace
        </div>
      )}
    </div>
  )
}
```

- [ ] **Step 3: Build**

```bash
cd canvas/frontend && npm run build
```

- [ ] **Step 4: Commit**

```bash
cd ../..
git add canvas/frontend/src/nodes/HumanNode.tsx canvas/frontend/src/nodes/ConversationNode.tsx
git commit -m "feat(canvas): add HumanNode and ConversationNode with live trace iframe"
```

---

## Task 11: Artifact cards

**Files:**
- Create: `canvas/frontend/src/cards/ArtifactCard.tsx`
- Create: `canvas/frontend/src/cards/ImageCard.tsx`
- Create: `canvas/frontend/src/cards/MemoryCard.tsx`

- [ ] **Step 1: Write ArtifactCard.tsx**

```tsx
// canvas/frontend/src/cards/ArtifactCard.tsx
import { useState } from 'react'
import type { ArtifactCardData } from '../types'

interface Props {
  card: ArtifactCardData
  style?: React.CSSProperties
}

export function ArtifactCard({ card, style }: Props) {
  const [expanded, setExpanded] = useState(false)
  return (
    <div
      onClick={() => setExpanded(!expanded)}
      style={{
        position: 'absolute', left: card.x, top: card.y,
        background: '#0d2137', border: '1px dashed #4a90d9',
        borderRadius: 8, padding: 10, minWidth: 180, maxWidth: 280,
        cursor: 'pointer', fontSize: 11, color: '#c0d8f0',
        boxShadow: '0 2px 8px rgba(0,0,0,0.5)',
        zIndex: 1000,
        ...style,
      }}
    >
      <div style={{ fontWeight: 700, marginBottom: 4, fontSize: 12 }}>
        📄 {card.slug || 'artifact'}
        <span style={{ float: 'right', opacity: 0.5 }}>from {card.agent}</span>
      </div>
      <div style={{ opacity: 0.8, whiteSpace: expanded ? 'pre-wrap' : 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
        {card.preview}
      </div>
    </div>
  )
}
```

- [ ] **Step 2: Write ImageCard.tsx**

```tsx
// canvas/frontend/src/cards/ImageCard.tsx
import { useState } from 'react'
import type { ArtifactCardData } from '../types'

interface Props { card: ArtifactCardData }

export function ImageCard({ card }: Props) {
  const [fullscreen, setFullscreen] = useState(false)
  const src = card.url ? `/media/${card.url.replace(/^result\/[^/]+\//, '')}` : ''

  return (
    <>
      <div
        onClick={() => setFullscreen(true)}
        style={{
          position: 'absolute', left: card.x, top: card.y,
          background: '#0d2137', border: '1px dashed #e8954a',
          borderRadius: 8, padding: 6, cursor: 'zoom-in',
          boxShadow: '0 2px 8px rgba(0,0,0,0.5)', zIndex: 1000,
        }}
      >
        <div style={{ fontSize: 10, opacity: 0.6, marginBottom: 4 }}>🎨 {card.agent}</div>
        <img src={src} alt="" style={{ maxWidth: 160, maxHeight: 120, borderRadius: 4, display: 'block' }} />
      </div>

      {fullscreen && (
        <div
          onClick={() => setFullscreen(false)}
          style={{
            position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.85)',
            display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 9999, cursor: 'zoom-out',
          }}
        >
          <img src={src} alt="" style={{ maxWidth: '90vw', maxHeight: '90vh', borderRadius: 8 }} />
        </div>
      )}
    </>
  )
}
```

- [ ] **Step 3: Write MemoryCard.tsx**

```tsx
// canvas/frontend/src/cards/MemoryCard.tsx
import type { ArtifactCardData } from '../types'

interface Props { card: ArtifactCardData }

export function MemoryCard({ card }: Props) {
  return (
    <div style={{
      position: 'absolute', left: card.x, top: card.y,
      background: '#0d2137', border: '1px dashed #5ba85b',
      borderRadius: 8, padding: 8, minWidth: 160, maxWidth: 240,
      fontSize: 11, color: '#b0e0b0',
      boxShadow: '0 2px 8px rgba(0,0,0,0.5)', zIndex: 1000,
    }}>
      <div style={{ fontWeight: 700, marginBottom: 4 }}>
        🧠 {card.category}
        <span style={{ float: 'right', opacity: 0.5, fontSize: 10 }}>{card.agent || 'floor'}</span>
      </div>
      <div style={{ opacity: 0.85 }}>{card.content}</div>
    </div>
  )
}
```

- [ ] **Step 4: Build**

```bash
cd canvas/frontend && npm run build
```

- [ ] **Step 5: Commit**

```bash
cd ../..
git add canvas/frontend/src/cards/
git commit -m "feat(canvas): add ArtifactCard, ImageCard, MemoryCard floating card components"
```

---

## Task 12: App.tsx — canvas + sidebar palette + dagre layout + event dispatch

This is the main component. It owns the React Flow node state, the artifact card list, the session state, and dispatches all WebSocket events to the right nodes.

**Files:**
- Create: `canvas/frontend/src/App.tsx`

- [ ] **Step 1: Write App.tsx**

```tsx
// canvas/frontend/src/App.tsx
import { useCallback, useEffect, useRef, useState } from 'react'
import {
  ReactFlow, Background, Controls, MiniMap,
  addEdge, useNodesState, useEdgesState,
  type Node, type Edge, type Connection,
} from '@xyflow/react'
import dagre from 'dagre'

import { FloorNode } from './nodes/FloorNode'
import { AgentNode } from './nodes/AgentNode'
import { HumanNode } from './nodes/HumanNode'
import { ConversationNode } from './nodes/ConversationNode'
import { ArtifactCard } from './cards/ArtifactCard'
import { ImageCard } from './cards/ImageCard'
import { MemoryCard } from './cards/MemoryCard'
import { useSession } from './hooks/useSession'

import type {
  FloorNodeData, AgentNodeData, HumanNodeData, ConversationNodeData,
  ArtifactCardData, WSEvent, FloorPolicy,
} from './types'

// ── Dagre auto-layout ──────────────────────────────────────────────────────────

function applyDagreLayout(nodes: Node[], edges: Edge[]): Node[] {
  const g = new dagre.graphlib.Graph()
  g.setDefaultEdgeLabel(() => ({}))
  g.setGraph({ rankdir: 'LR', ranksep: 80, nodesep: 60 })
  nodes.forEach(n => g.setNode(n.id, { width: 260, height: 200 }))
  edges.forEach(e => g.setEdge(e.source, e.target))
  dagre.layout(g)
  return nodes.map(n => {
    const { x, y } = g.node(n.id)
    return { ...n, position: { x: x - 130, y: y - 100 } }
  })
}

// ── Node types registration ────────────────────────────────────────────────────

const FLOOR_ID = 'floor-main'
const CONV_ID = 'conversation-main'

const nodeTypes = {
  FloorNode: (props: any) => <FloorNode {...props} onRun={() => {}} onStop={() => {}} onChange={() => {}} />,
  AgentNode: (props: any) => <AgentNode {...props} onKick={() => {}} />,
  HumanNode: (props: any) => <HumanNode {...props} onSend={() => {}} sessionRunning={false} />,
  ConversationNode: (props: any) => <ConversationNode {...props} />,
}

// ── Initial canvas state ───────────────────────────────────────────────────────

function makeInitialNodes(): Node[] {
  return applyDagreLayout(
    [
      {
        id: FLOOR_ID, type: 'FloorNode', position: { x: 0, y: 0 },
        data: {
          policy: 'SEQUENTIAL', topic: '', maxTurns: null, showFloorEvents: false,
          noHuman: true, sessionState: 'idle', turnCount: 0, elapsedSeconds: 0, sessionId: null,
        } satisfies FloorNodeData,
      },
      {
        id: CONV_ID, type: 'ConversationNode', position: { x: 0, y: 0 },
        data: { sessionId: null, policy: null, topic: '', turnCount: 0 } satisfies ConversationNodeData,
      },
    ],
    []
  )
}

// ── Main App ──────────────────────────────────────────────────────────────────

export default function App() {
  const [nodes, setNodes, onNodesChange] = useNodesState(makeInitialNodes())
  const [edges, setEdges, onEdgesChange] = useEdgesState([])
  const [cards, setCards] = useState<ArtifactCardData[]>([])
  const [sessionId, setSessionId] = useState<string | null>(null)
  const turnCountRef = useRef(0)
  const startTimeRef = useRef<number | null>(null)
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null)

  // ── Helpers ────────────────────────────────────────────────────────────────

  function patchNode<T>(id: string, patch: Partial<T>) {
    setNodes(nds => nds.map(n => n.id === id ? { ...n, data: { ...n.data, ...patch } } : n))
  }

  function nodeIdForAgent(name: string): string | null {
    return nodes.find(n => n.type === 'AgentNode' && n.data.name === name)?.id ?? null
  }

  function appendMessage(nodeId: string, text: string, media: WSEvent extends { type: 'utterance' } ? any : null) {
    setNodes(nds => nds.map(n => {
      if (n.id !== nodeId) return n
      const msgs = [...(n.data.messages as any[]), { text, timestamp: new Date().toISOString(), media }]
      return { ...n, data: { ...n.data, messages: msgs } }
    }))
  }

  function spawnCard(card: ArtifactCardData) {
    setCards(cs => [...cs, card])
  }

  function cardPositionForAgent(agentName: string): { x: number; y: number } {
    const node = nodes.find(n => n.data.name === agentName)
    if (node) return { x: node.position.x + 290, y: node.position.y + cards.filter(c => c.agent === agentName).length * 80 }
    return { x: 600, y: cards.length * 80 }
  }

  // ── WebSocket event dispatch ────────────────────────────────────────────────

  const handleEvent = useCallback((event: WSEvent) => {
    if (event.type === 'utterance') {
      turnCountRef.current++
      const nodeId = event.sender.startsWith('human') || event.sender_uri.includes('human')
        ? nodes.find(n => n.type === 'HumanNode')?.id ?? null
        : nodeIdForAgent(event.sender)
      if (nodeId) appendMessage(nodeId, event.text, event.media ?? null)
      patchNode<ConversationNodeData>(CONV_ID, { turnCount: turnCountRef.current })
    }

    if (event.type === 'floor_grant') {
      setNodes(nds => nds.map(n => {
        if (n.type !== 'AgentNode') return n
        return { ...n, data: { ...n.data, floorState: n.data.name === event.to ? 'speaking' : 'waiting' } }
      }))
    }

    if (event.type === 'floor_request') {
      const nodeId = nodeIdForAgent(event.from)
      if (nodeId) patchNode<AgentNodeData>(nodeId, { floorState: 'requesting' })
    }

    if (event.type === 'floor_revoke') {
      const nodeId = nodeIdForAgent(event.from)
      if (nodeId) patchNode<AgentNodeData>(nodeId, { floorState: 'waiting' })
    }

    if (event.type === 'artifact_saved') {
      const pos = cardPositionForAgent(event.agent)
      spawnCard({ id: `artifact-${Date.now()}`, kind: 'markdown', agent: event.agent, slug: event.slug, preview: event.preview, ...pos })
    }

    if (event.type === 'image_saved') {
      const pos = cardPositionForAgent(event.agent)
      spawnCard({ id: `image-${Date.now()}`, kind: 'image', agent: event.agent, url: event.url, ...pos })
    }

    if (event.type === 'memory_saved') {
      const agent = event.agent || 'floor'
      const pos = cardPositionForAgent(agent)
      spawnCard({ id: `mem-${Date.now()}`, kind: 'memory', agent, category: event.category, content: event.content, ...pos })
    }

    if (event.type === 'error') {
      const nodeId = nodeIdForAgent(event.agent)
      if (nodeId) patchNode<AgentNodeData>(nodeId, { floorState: 'error', errorMessage: event.message })
    }

    if (event.type === 'agent_kicked') {
      setNodes(nds => nds.filter(n => !(n.type === 'AgentNode' && n.data.name === event.name)))
    }

    if (event.type === 'session_ended') {
      patchNode<FloorNodeData>(FLOOR_ID, { sessionState: 'stopped' })
      if (timerRef.current) clearInterval(timerRef.current)
    }
  }, [nodes])

  const { connected, sendMessage, kickAgent } = useSession({ sessionId, onEvent: handleEvent })

  // ── Run / Stop ─────────────────────────────────────────────────────────────

  async function handleRun() {
    const floorNode = nodes.find(n => n.id === FLOOR_ID)
    if (!floorNode) return

    const payload = {
      nodes: nodes.map(n => ({ id: n.id, type: n.type, data: n.data })),
      edges: edges.map(e => ({ source: e.source, target: e.target })),
    }

    const res = await fetch('/session/start', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    })
    const { session_id } = await res.json()
    setSessionId(session_id)
    setCards([])
    turnCountRef.current = 0
    startTimeRef.current = Date.now()

    patchNode<FloorNodeData>(FLOOR_ID, { sessionState: 'running', sessionId: session_id, turnCount: 0, elapsedSeconds: 0 })
    patchNode<ConversationNodeData>(CONV_ID, { sessionId: session_id, policy: floorNode.data.policy as FloorPolicy, topic: floorNode.data.topic, turnCount: 0 })

    timerRef.current = setInterval(() => {
      if (startTimeRef.current) {
        patchNode<FloorNodeData>(FLOOR_ID, { elapsedSeconds: Math.floor((Date.now() - startTimeRef.current) / 1000) })
      }
    }, 1000)
  }

  async function handleStop() {
    await fetch('/session/stop', { method: 'DELETE' })
    patchNode<FloorNodeData>(FLOOR_ID, { sessionState: 'stopped' })
    if (timerRef.current) clearInterval(timerRef.current)
  }

  // ── Palette ────────────────────────────────────────────────────────────────

  function addAgentNode() {
    const id = `agent-${Date.now()}`
    const newNode: Node = {
      id, type: 'AgentNode', position: { x: 400, y: nodes.length * 140 },
      data: {
        provider: 'anthropic', name: `Agent${nodes.filter(n => n.type === 'AgentNode').length + 1}`,
        model: '', systemPrompt: '', slug: '',
        floorState: 'waiting', messages: [],
      } satisfies AgentNodeData,
    }
    const newEdge: Edge = { id: `e-${id}`, source: id, target: FLOOR_ID }
    setNodes(nds => applyDagreLayout([...nds, newNode], [...edges, newEdge]))
    setEdges(eds => addEdge(newEdge, eds))
  }

  function addHumanNode() {
    const id = `human-${Date.now()}`
    const newNode: Node = {
      id, type: 'HumanNode', position: { x: 400, y: 0 },
      data: { humanName: 'User', messages: [] } satisfies HumanNodeData,
    }
    const newEdge: Edge = { id: `e-${id}`, source: id, target: FLOOR_ID }
    setNodes(nds => applyDagreLayout([...nds, newNode], [...edges, newEdge]))
    setEdges(eds => addEdge(newEdge, eds))
  }

  const onConnect = useCallback((params: Connection) => setEdges(eds => addEdge(params, eds)), [])

  // ── Override node callbacks in nodeTypes ────────────────────────────────────
  // (Passed via data to avoid React Flow re-render issues with stale closures)
  const resolvedNodeTypes = {
    FloorNode: (props: any) => <FloorNode {...props}
      onRun={handleRun} onStop={handleStop}
      onChange={(patch: Partial<FloorNodeData>) => patchNode<FloorNodeData>(FLOOR_ID, patch)}
    />,
    AgentNode: (props: any) => <AgentNode {...props} onKick={kickAgent} />,
    HumanNode: (props: any) => <HumanNode {...props} onSend={sendMessage}
      sessionRunning={nodes.find(n => n.id === FLOOR_ID)?.data.sessionState === 'running'}
    />,
    ConversationNode: (props: any) => <ConversationNode {...props} />,
  }

  return (
    <div style={{ width: '100vw', height: '100vh', display: 'flex', flexDirection: 'column' }}>
      {/* Top bar */}
      <div style={{ height: 44, background: '#0d1b2a', borderBottom: '1px solid #333', display: 'flex', alignItems: 'center', gap: 12, padding: '0 16px' }}>
        <span style={{ fontWeight: 800, fontSize: 15, color: '#4a90d9' }}>OFP Canvas</span>
        <span style={{ fontSize: 11, opacity: 0.5 }}>|</span>
        <button onClick={addAgentNode} style={{ background: '#0f3460', border: '1px solid #4a90d9', color: '#4a90d9', borderRadius: 6, padding: '4px 12px', cursor: 'pointer', fontSize: 12 }}>
          + Agent
        </button>
        <button onClick={addHumanNode} style={{ background: '#0f3460', border: '1px solid #5ba85b', color: '#5ba85b', borderRadius: 6, padding: '4px 12px', cursor: 'pointer', fontSize: 12 }}>
          + Human
        </button>
        <div style={{ marginLeft: 'auto', fontSize: 11, opacity: 0.5 }}>
          {connected ? '● connected' : '○ disconnected'}
        </div>
      </div>

      {/* Canvas */}
      <div style={{ flex: 1, position: 'relative' }}>
        <ReactFlow
          nodes={nodes}
          edges={edges}
          onNodesChange={onNodesChange}
          onEdgesChange={onEdgesChange}
          onConnect={onConnect}
          nodeTypes={resolvedNodeTypes}
          fitView
        >
          <Background color="#1a1a2e" gap={20} />
          <Controls />
          <MiniMap nodeColor="#0f3460" maskColor="rgba(10,15,30,0.7)" />
        </ReactFlow>

        {/* Artifact cards overlay */}
        {cards.map(card => {
          if (card.kind === 'image') return <ImageCard key={card.id} card={card} />
          if (card.kind === 'memory') return <MemoryCard key={card.id} card={card} />
          return <ArtifactCard key={card.id} card={card} />
        })}
      </div>
    </div>
  )
}
```

- [ ] **Step 2: Build**

```bash
cd canvas/frontend && npm run build
```

Expected: builds with no errors. (TS may warn about `satisfies` — needs TS 4.9+; already in package.json as `^5.4.5` so fine.)

- [ ] **Step 3: Commit**

```bash
cd ../..
git add canvas/frontend/src/App.tsx
git commit -m "feat(canvas): main App with React Flow canvas, sidebar palette, event dispatch, dagre layout"
```

---

## Task 13: localStorage layout persistence

**Files:**
- Modify: `canvas/frontend/src/App.tsx` (add save/restore logic)

- [ ] **Step 1: Add save on node position change**

At the top of `App`, after the `useNodesState` and `useEdgesState` lines:

```typescript
const LAYOUT_KEY = 'ofp-canvas-layout'

// Restore positions on mount
useEffect(() => {
  try {
    const saved = localStorage.getItem(LAYOUT_KEY)
    if (saved) {
      const posMap: Record<string, { x: number; y: number }> = JSON.parse(saved)
      setNodes(nds => nds.map(n => posMap[n.id] ? { ...n, position: posMap[n.id] } : n))
    }
  } catch { /* ignore corrupt storage */ }
}, [])

// Save positions when nodes move
useEffect(() => {
  try {
    const posMap: Record<string, { x: number; y: number }> = {}
    nodes.forEach(n => { posMap[n.id] = n.position })
    localStorage.setItem(LAYOUT_KEY, JSON.stringify(posMap))
  } catch { /* quota exceeded — ignore */ }
}, [nodes])
```

- [ ] **Step 2: Build and verify**

```bash
cd canvas/frontend && npm run build
```

- [ ] **Step 3: Commit**

```bash
cd ../..
git add canvas/frontend/src/App.tsx
git commit -m "feat(canvas): persist node positions to localStorage"
```

---

## Task 14: Build frontend into dist/ + integration smoke test

**Files:**
- Create: `canvas/frontend/.gitignore` (exclude node_modules, keep dist)

- [ ] **Step 1: Create .gitignore for frontend**

```
# canvas/frontend/.gitignore
node_modules/
*.local
```

Note: `dist/` is intentionally **not** gitignored — it's committed so runtime users don't need npm.

- [ ] **Step 2: Build production frontend**

```bash
cd canvas/frontend
npm run build
```

Expected: `canvas/frontend/dist/` is populated with `index.html`, `assets/` etc.

- [ ] **Step 3: Smoke test — canvas server starts and serves frontend**

```bash
# In terminal 1
ofp-playground canvas --no-open --port 8765 &
sleep 2

# In terminal 2
curl -s -o /dev/null -w "%{http_code}" http://localhost:8765/
# Expected: 200

curl -s http://localhost:8765/session/status | python3 -m json.tool
# Expected: {"running": false, "session_id": null}

curl -s -o /dev/null -w "%{http_code}" http://localhost:8765/media/../../../etc/passwd
# Expected: 400

kill %1
```

- [ ] **Step 4: Run full test suite**

```bash
pytest tests/ -v --tb=short
```

Expected: all tests PASS.

- [ ] **Step 5: Commit everything**

```bash
git add canvas/frontend/.gitignore canvas/frontend/dist/
git commit -m "feat(canvas): include built frontend dist; canvas command fully operational"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|------------------|------|
| `ofp-playground canvas` CLI command | Task 4 |
| FastAPI backend separate from Gradio | Task 3 |
| SessionBridge via `set_collector()` | Task 2 |
| asyncio.Queue sync→async bridge | Task 2 |
| Full event log replay on reconnect | Task 2, 3 |
| Path traversal protection on /media | Task 3 |
| Session lifecycle (run/stop/reset) | Task 3 |
| Graceful shutdown (session_ended event) | Task 3 |
| FloorNode with all controls | Task 8 |
| AgentNode with bubbles + floor state | Task 9 |
| `error` + `spawning` agent states | Task 9, types |
| HumanNode with input | Task 10 |
| ConversationNode with live trace iframe | Task 10 |
| ArtifactCard, ImageCard, MemoryCard | Task 11 |
| WebSocket hook with reconnect | Task 7 |
| dagre auto-layout | Task 12 |
| localStorage layout persistence | Task 13 |
| `?live=` trace mode | Task 5 |
| All WS event types including `error` | Task 2, types |
| `memory_saved` agent may be null | Task 2 |
| Backend tests | Tasks 2, 3 |
| Frontend builds from dist | Task 14 |

All spec requirements are covered. No TBDs or placeholders found.
