"""FastAPI app for the canvas backend."""
from __future__ import annotations

import asyncio
import io
import logging
import os
import sys
import uuid
from contextlib import asynccontextmanager, suppress
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from rich.console import Console

_REPO_ROOT = Path(__file__).resolve().parents[2]
_SRC_ROOT = _REPO_ROOT / "src"
if str(_SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(_SRC_ROOT))

from canvas.backend.session_bridge import SessionBridge  # noqa: E402
from ofp_playground.agents.registry import AgentRegistry  # noqa: E402
from ofp_playground.bus.message_bus import MessageBus  # noqa: E402
from ofp_playground.config.settings import Settings  # noqa: E402
from ofp_playground.floor.manager import FloorManager  # noqa: E402
from ofp_playground.floor.policy import FloorPolicy  # noqa: E402
from ofp_playground.renderer.terminal import TerminalRenderer  # noqa: E402

logger = logging.getLogger(__name__)

RESULT_DIR = (_REPO_ROOT / "result").resolve()
_DIST_DIR = Path(__file__).resolve().parent.parent / "frontend" / "dist"


# ── Request / Response models ──────────────────────────────────────────────────

class NodeData(BaseModel):
    policy: str = "SEQUENTIAL"
    topic: str = ""
    maxTurns: int | None = None
    showFloorEvents: bool = False
    noHuman: bool = True
    provider: str = ""
    name: str = ""
    model: str = ""
    systemPrompt: str = ""
    slug: str = ""
    humanName: str = "User"
    agentType: str = ""


class CanvasNode(BaseModel):
    id: str
    type: str
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
    agentType: str = ""


class HumanMessageRequest(BaseModel):
    text: str


# ── Helpers ────────────────────────────────────────────────────────────────────

def _safe_media_path(rel_path: str) -> Path:
    if os.path.isabs(rel_path):
        raise HTTPException(status_code=400, detail="Absolute paths not allowed")

    normed = os.path.normpath(rel_path)
    if normed == ".." or normed.startswith("../") or "/../" in normed:
        raise HTTPException(status_code=400, detail="Path traversal not allowed")

    resolved = (RESULT_DIR / normed).resolve()
    if not str(resolved).startswith(str(RESULT_DIR)):
        raise HTTPException(status_code=400, detail="Path outside result dir")
    return resolved


def _parse_policy(value: str) -> FloorPolicy:
    try:
        return FloorPolicy[value.upper()]
    except KeyError:
        return FloorPolicy.SEQUENTIAL


async def _cancel_task(task: asyncio.Task[Any] | None) -> None:
    if task is None:
        return
    task.cancel()
    with suppress(asyncio.CancelledError):
        await task


async def _spawn_agent_for_canvas(
    provider: str,
    name: str,
    description: str,
    model: str,
    agent_type: str,
    floor: FloorManager,
    bus: MessageBus,
    registry: AgentRegistry,
    renderer: TerminalRenderer,
    settings: Settings,
    bridge: SessionBridge,
) -> None:
    """Spawn an LLM agent and register it on the running floor."""
    # Lazy import to avoid circular deps at module load time
    from ofp_playground.cli import _spawn_llm_agent

    bridge.push_raw({"type": "agent_spawning", "name": name, "provider": provider})
    try:
        resolved_type = f"{provider}:{agent_type}" if agent_type else provider
        await _spawn_llm_agent(
            agent_type=resolved_type,
            name=name,
            description=description or f"I am {name}, an AI assistant.",
            floor=floor,
            bus=bus,
            registry=registry,
            renderer=renderer,
            settings=settings,
            model_override=model or None,
        )
        bridge.register_agent(f"tag:ofp-playground.local,2025:llm-{name}", name)
        bridge.push_raw({"type": "agent_joined", "name": name, "provider": provider})
    except Exception as exc:
        logger.error("Failed to spawn agent %s: %s", name, exc)
        bridge.push_raw({"type": "error", "agent": name, "message": str(exc), "retryable": False})
        raise


async def _run_canvas_session(
    *,
    bridge: SessionBridge,
    nodes: list[CanvasNode],
    policy: FloorPolicy,
    topic: str,
    max_turns: int | None,
    show_floor_events: bool,
    no_human: bool,
    human_name: str,
    settings: Settings,
    state: dict[str, Any],
) -> None:
    """Start a full OFP session from a canvas graph."""
    null_console = Console(file=io.StringIO(), force_terminal=False, color_system=None)
    renderer = TerminalRenderer(console=null_console, show_floor_events=show_floor_events)

    bus = MessageBus()
    floor = FloorManager(bus, policy=policy, renderer=renderer)
    floor._on_artifact_saved = bridge.push_raw

    bridge.set_inner_collector(floor.trace_collector)
    bus.set_collector(bridge)

    registry = AgentRegistry()

    # Attach spawn/breakout callbacks so orchestrators can spawn agents
    from ofp_playground.cli import _attach_floor_callbacks
    await _attach_floor_callbacks(floor, bus, registry, settings, renderer)

    state["bus"] = bus
    state["floor"] = floor
    state["registry"] = registry
    state["collector"] = floor.trace_collector

    try:
        # Spawn agents from the graph before starting the floor loop
        agent_nodes = [n for n in nodes if n.type == "AgentNode"]
        human_nodes = [n for n in nodes if n.type == "HumanNode"]

        spawn_tasks = []
        for node in agent_nodes:
            d = node.data
            if not d.provider or not d.name:
                continue
            description = d.systemPrompt or d.slug or f"I am {d.name}, an AI assistant."
            spawn_tasks.append(
                _spawn_agent_for_canvas(
                    provider=d.provider,
                    name=d.name,
                    description=description,
                    model=d.model,
                    agent_type=d.agentType,
                    floor=floor,
                    bus=bus,
                    registry=registry,
                    renderer=renderer,
                    settings=settings,
                    bridge=bridge,
                )
            )

        if spawn_tasks:
            results = await asyncio.gather(*spawn_tasks, return_exceptions=True)
            errors = [r for r in results if isinstance(r, Exception)]
            if errors:
                await bridge.push_raw(
                    {
                        "type": "error",
                        "message": f"Failed to spawn {len(errors)} agent(s); aborting session.",
                    }
                )
                return

        # Human agent (WebHumanAgent queue-based, not stdin)
        if not no_human and human_nodes:
            from ofp_playground.agents.web_human import WebHumanAgent
            human_name_val = human_nodes[0].data.humanName or human_name
            human = WebHumanAgent(
                name=human_name_val,
                bus=bus,
                conversation_id=floor.conversation_id,
            )
            floor.register_agent(human.speaker_uri, human.name)
            registry.register(human)
            state["human_agent"] = human
            bridge.register_agent(human.speaker_uri, human.name)
            bridge.push_raw({"type": "agent_joined", "name": human.name, "provider": "human"})
            asyncio.create_task(human.run())

        # Seed topic + max_turns watchdog + initial floor kick-start.
        # Always run _orchestrate so the floor is kick-started even without a topic.
        human_agent = state.get("human_agent")

        async def _orchestrate() -> None:
            await asyncio.sleep(1.0)
            if topic:
                floor._memory_store.seed_goal(topic)
                from ofp_playground.cli import _seed_topic as _st
                await _st(topic, floor, bus)
                # If the human holds the floor in sequential mode, yield it so
                # agents can respond to the seeded topic; human re-queues for next turn.
                if human_agent is not None and floor.floor_holder == human_agent.speaker_uri:
                    human_agent._has_floor = False
                    await human_agent.yield_floor()
                    await human_agent.request_floor()
                await asyncio.sleep(0.2)

            # Grant floor to the orchestrator / director / first agent so the
            # conversation kicks off even without an initial human message.
            if floor._orchestrator_uri:
                await floor.grant_to(floor._orchestrator_uri)
            elif floor._director_uri and not floor._showrunner_uri:
                await floor.grant_to(floor._director_uri)
            elif no_human and not topic:
                # Autonomous session with no topic: grant to the first registered
                # agent so the conversation can start on its own.
                first_uri = next(iter(floor._agents), None)
                if first_uri:
                    await floor.grant_to(first_uri)

            if max_turns:
                while floor.history.__len__() < max_turns:
                    await asyncio.sleep(2.0)
                floor.stop()

        asyncio.create_task(_orchestrate())

        await floor.run()
    finally:
        bridge.push_raw({"type": "session_ended"})


# ── App factory ────────────────────────────────────────────────────────────────

def build_app(initial_config: dict | None = None) -> FastAPI:
    bridge = SessionBridge()
    settings = Settings()
    state: dict[str, Any] = {
        "session_id": None,
        "session_task": None,
        "broadcast_task": None,
        "floor": None,
        "bus": None,
        "registry": None,
        "collector": None,
        "human_agent": None,
        "initial_config": initial_config,
    }

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        try:
            yield
        finally:
            floor: FloorManager | None = state.get("floor")
            if floor is not None:
                floor.stop()

            session_task: asyncio.Task[Any] | None = state.get("session_task")
            if session_task is not None and not session_task.done():
                with suppress(asyncio.TimeoutError, asyncio.CancelledError):
                    await asyncio.wait_for(session_task, timeout=2.0)
            await _cancel_task(state.get("broadcast_task"))

    app = FastAPI(title="OFP Canvas", lifespan=lifespan)

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["http://localhost:8765", "http://127.0.0.1:8765",
                       "http://localhost:5173", "http://127.0.0.1:5173"],
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # ── WebSocket ──────────────────────────────────────────────────────────────

    @app.websocket("/ws/{session_id}")
    async def ws_endpoint(websocket: WebSocket, session_id: str) -> None:
        active_session_id = state.get("session_id")
        if active_session_id is not None and session_id != active_session_id:
            await websocket.close(code=1008, reason="Unknown session")
            return

        await bridge.connect(websocket)
        try:
            while True:
                await websocket.receive_text()
        except WebSocketDisconnect:
            bridge.disconnect(websocket)

    # ── Session lifecycle ──────────────────────────────────────────────────────

    @app.get("/session/status")
    async def session_status() -> dict[str, Any]:
        session_task: asyncio.Task[Any] | None = state.get("session_task")
        return {
            "running": bool(session_task and not session_task.done()),
            "session_id": state.get("session_id"),
        }

    @app.get("/session/initial")
    async def session_initial() -> dict | None:
        return state.get("initial_config")

    @app.post("/session/start")
    async def session_start(req: StartRequest) -> dict[str, str]:
        session_task: asyncio.Task[Any] | None = state.get("session_task")
        if session_task is not None and not session_task.done():
            raise HTTPException(status_code=409, detail="Session already running")

        floor_node = next((node for node in req.nodes if node.type == "FloorNode"), None)
        if floor_node is None:
            raise HTTPException(status_code=422, detail="Missing FloorNode")

        await _cancel_task(state.get("broadcast_task"))
        bridge.reset()

        session_id = uuid.uuid4().hex[:8]
        state["session_id"] = session_id
        state["human_agent"] = None
        state["broadcast_task"] = asyncio.create_task(bridge.broadcast_loop())
        state["session_task"] = asyncio.create_task(
            _run_canvas_session(
                bridge=bridge,
                nodes=req.nodes,
                policy=_parse_policy(floor_node.data.policy),
                topic=floor_node.data.topic,
                max_turns=floor_node.data.maxTurns,
                show_floor_events=floor_node.data.showFloorEvents,
                no_human=floor_node.data.noHuman,
                human_name=floor_node.data.humanName or "User",
                settings=settings,
                state=state,
            )
        )

        return {"session_id": session_id}

    @app.delete("/session/stop")
    async def session_stop() -> dict[str, bool]:
        floor: FloorManager | None = state.get("floor")
        if floor is not None:
            floor.stop()

        session_task: asyncio.Task[Any] | None = state.get("session_task")
        if session_task is not None and not session_task.done():
            try:
                await asyncio.wait_for(session_task, timeout=2.0)
            except asyncio.TimeoutError:
                await _cancel_task(session_task)

        state["session_task"] = None
        state["floor"] = None
        state["bus"] = None
        state["registry"] = None
        state["human_agent"] = None
        return {"ok": True}

    # ── Agent management ────────────────────────────────────────────────────────

    @app.post("/session/agent/add")
    async def agent_add(req: AddAgentRequest) -> dict[str, str]:
        floor: FloorManager | None = state.get("floor")
        bus: MessageBus | None = state.get("bus")
        registry: AgentRegistry | None = state.get("registry")

        if floor is None or bus is None or registry is None:
            raise HTTPException(status_code=409, detail="No active session")

        null_console = Console(file=io.StringIO(), force_terminal=False, color_system=None)
        renderer = TerminalRenderer(console=null_console, show_floor_events=False)
        description = req.systemPrompt or f"I am {req.name}, an AI assistant."

        try:
            await _spawn_agent_for_canvas(
                provider=req.provider,
                name=req.name,
                description=description,
                model=req.model,
                agent_type=req.agentType,
                floor=floor,
                bus=bus,
                registry=registry,
                renderer=renderer,
                settings=settings,
                bridge=bridge,
            )
        except Exception as exc:
            raise HTTPException(status_code=500, detail=str(exc)) from exc

        return {"name": req.name}

    @app.delete("/session/agent/{name}")
    async def agent_kick(name: str) -> dict[str, str]:
        floor: FloorManager | None = state.get("floor")
        registry: AgentRegistry | None = state.get("registry")

        if floor is None or registry is None:
            raise HTTPException(status_code=409, detail="No active session")

        # Resolve URI by name
        agent_uri = floor._resolve_agent_uri_by_name(name)
        if agent_uri is None:
            raise HTTPException(status_code=404, detail=f"Agent '{name}' not found")

        agent = registry.get(agent_uri)
        if agent is not None:
            agent.stop()
            registry.unregister(agent_uri)

        floor.unregister_agent(agent_uri)
        bridge.push_raw({"type": "agent_kicked", "name": name})
        return {"name": name}

    @app.post("/session/message")
    async def session_message(req: HumanMessageRequest) -> dict[str, bool]:
        human = state.get("human_agent")
        if human is None:
            raise HTTPException(status_code=409, detail="No human agent in this session")

        await human.input_queue.put(req.text)
        return {"ok": True}

    # ── Live trace ─────────────────────────────────────────────────────────────

    @app.get("/trace/live")
    async def trace_live(session: str = "") -> HTMLResponse:
        from ofp_playground.trace.renderer import render_trace_html
        from ofp_playground.trace.collector import EventCollector
        collector: EventCollector | None = state.get("collector")
        if collector is None:
            collector = EventCollector()
        import tempfile
        with tempfile.NamedTemporaryFile(suffix=".html", delete=False) as tmp:
            tmp_path = Path(tmp.name)
        render_trace_html(collector, tmp_path, live_session_id=session or None)
        content = tmp_path.read_text(encoding="utf-8")
        tmp_path.unlink(missing_ok=True)
        return HTMLResponse(content=content)

    # ── Media serving ──────────────────────────────────────────────────────────

    @app.get("/media/{path:path}")
    async def serve_media(path: str) -> FileResponse:
        resolved = _safe_media_path(path)
        if not resolved.exists():
            raise HTTPException(status_code=404, detail="File not found")
        return FileResponse(resolved)

    # ── Agent library & model catalog ─────────────────────────────────────────

    @app.get("/agents/list")
    async def agents_list() -> list[dict]:
        from ofp_playground.agents.library import load as _load_agents
        library = _load_agents()
        return sorted(
            [
                {
                    "slug": slug,
                    "display_name": entry["display_name"],
                    "category": entry["category"],
                }
                for slug, entry in library.items()
            ],
            key=lambda x: x["slug"],
        )

    @app.get("/models/list")
    async def models_list() -> dict[str, list[str]]:
        from ofp_playground.agents.llm.model_catalog import MODEL_CATALOG
        result: dict[str, list[str]] = {
            "anthropic": [], "openai": [], "google": [], "huggingface": [],
        }
        for model_id in MODEL_CATALOG:
            if model_id.startswith("claude"):
                result["anthropic"].append(model_id)
            elif model_id.startswith("gpt"):
                result["openai"].append(model_id)
            elif model_id.startswith("gemini"):
                result["google"].append(model_id)
        return result

    # ── Static frontend (must be last) ────────────────────────────────────────

    if _DIST_DIR.exists():
        app.mount("/", StaticFiles(directory=str(_DIST_DIR), html=True), name="static")

    return app
