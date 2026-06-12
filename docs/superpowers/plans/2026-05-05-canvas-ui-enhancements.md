# Canvas UI Enhancements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add six canvas improvements: fix input focus stealing, slug/model suggestion lists, agent type field, artifact graph nodes (IMAGE/CODE/PHASE/MUSIC), and animated talking-edge glow.

**Architecture:** React context breaks the prop-drilling cycle that causes `nodeTypes` to rebuild on every render. A custom `GlowEdge` edge type handles all edge styling. Backend gains two list endpoints (`/agents/list`, `/models/list`). A `_on_artifact_saved` callback on `FloorManager` lets the canvas receive artifact events over WebSocket without polling.

**Tech Stack:** React 18 + TypeScript, `@xyflow/react`, FastAPI, pytest, `httpx` (test client)

---

## File Map

### New frontend files
| File | Responsibility |
|------|---------------|
| `canvas/frontend/src/context/CanvasContext.tsx` | Shared callbacks (onRun/onStop/onFloorChange/onKick/onSend/sessionRunning) |
| `canvas/frontend/src/edges/GlowEdge.tsx` | Custom ReactFlow edge — static dashed + animated glow when active |
| `canvas/frontend/src/hooks/useSlugs.ts` | Fetch `/agents/list` once on mount |
| `canvas/frontend/src/hooks/useModels.ts` | Fetch `/models/list` once on mount |
| `canvas/frontend/src/components/SlugCombobox.tsx` | Input that shows slug suggestion list after `@` |
| `canvas/frontend/src/nodes/ImageArtifactNode.tsx` | Purple image artifact node with lightbox |
| `canvas/frontend/src/nodes/CodeArtifactNode.tsx` | Green code/file artifact node |
| `canvas/frontend/src/nodes/PhaseArtifactNode.tsx` | Blue phase/markdown artifact node |
| `canvas/frontend/src/nodes/MusicArtifactNode.tsx` | Orange music artifact node with audio player |

### Modified frontend files
| File | Changes |
|------|---------|
| `canvas/frontend/src/types.ts` | Add `ArtifactNodeData`, `agentType` on `AgentNodeData`, `GlowEdgeData` |
| `canvas/frontend/src/App.tsx` | Context provider, stable NODE_TYPES/EDGE_TYPES, artifact node events, glow wiring, agent type form field, remove floating cards |
| `canvas/frontend/src/nodes/FloorNode.tsx` | Drop callback props, use `useCanvas()` |
| `canvas/frontend/src/nodes/AgentNode.tsx` | Drop `onKick` prop, use `useCanvas()`, show type badge |
| `canvas/frontend/src/nodes/HumanNode.tsx` | Drop `onSend`/`sessionRunning` props, use `useCanvas()` |

### Deleted frontend files
`canvas/frontend/src/cards/ArtifactCard.tsx`, `ImageCard.tsx`, `MemoryCard.tsx`

### Modified backend files
| File | Changes |
|------|---------|
| `canvas/backend/main.py` | Add `/agents/list`, `/models/list`, `agentType` on `NodeData`+`AddAgentRequest`, wire `_on_artifact_saved` |
| `src/ofp_playground/floor/manager.py` | Add `_on_artifact_saved` callback attribute + 3 call sites |

---

## Task 1: Backend list endpoints + agentType field

**Files:**
- Modify: `canvas/backend/main.py`
- Modify: `tests/test_canvas_api.py`

- [ ] **Step 1: Write failing tests**

Add to `tests/test_canvas_api.py`:

```python
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
                }
            ],
            "edges": [],
        }
        response = await client.post("/session/start", json=payload)
    # Just check it doesn't 422 — agentType must be accepted
    assert response.status_code != 422
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
pytest tests/test_canvas_api.py::test_agents_list_returns_sorted_entries tests/test_canvas_api.py::test_models_list_returns_grouped_providers tests/test_canvas_api.py::test_agent_type_field_accepted_in_start -v
```

Expected: 3 FAILs (endpoints missing, field rejected)

- [ ] **Step 3: Add endpoints and agentType field to main.py**

In `canvas/backend/main.py`, add to `NodeData`:
```python
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
    agentType: str = ""          # ← add this
```

Add to `AddAgentRequest`:
```python
class AddAgentRequest(BaseModel):
    provider: str
    name: str
    model: str = ""
    systemPrompt: str = ""
    slug: str = ""
    agentType: str = ""          # ← add this
```

Update `_spawn_agent_for_canvas` signature and call site:
```python
async def _spawn_agent_for_canvas(
    provider: str,
    name: str,
    description: str,
    model: str,
    agent_type: str,             # ← add parameter
    floor: FloorManager,
    bus: MessageBus,
    registry: AgentRegistry,
    renderer: TerminalRenderer,
    settings: Settings,
    bridge: SessionBridge,
) -> None:
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
```

Update all call sites of `_spawn_agent_for_canvas` (in `_run_canvas_session` and `agent_add`) to pass `agent_type=d.agentType` or `agent_type=req.agentType`.

Inside `build_app()` after the Session lifecycle routes, add the two new endpoints:

```python
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
```

- [ ] **Step 4: Run tests and confirm they pass**

```bash
pytest tests/test_canvas_api.py::test_agents_list_returns_sorted_entries tests/test_canvas_api.py::test_models_list_returns_grouped_providers tests/test_canvas_api.py::test_agent_type_field_accepted_in_start -v
```

Expected: 3 PASSes

- [ ] **Step 5: Confirm no regressions**

```bash
pytest tests/test_canvas_api.py -v
```

Expected: all pass

- [ ] **Step 6: Commit**

```bash
git add canvas/backend/main.py tests/test_canvas_api.py
git commit -m "feat(canvas): add /agents/list, /models/list endpoints and agentType field"
```

---

## Task 2: FloorManager artifact callback hook

**Files:**
- Modify: `src/ofp_playground/floor/manager.py`
- Modify: `tests/test_floor_manager_extended.py`

- [ ] **Step 1: Write the failing test**

Add to `tests/test_floor_manager_extended.py`:

```python
async def test_on_artifact_saved_callback_invoked() -> None:
    """_on_artifact_saved is called after _save_character_memory_blocks."""
    bus = MessageBus()
    floor = FloorManager(bus)

    received: list[dict] = []
    floor._on_artifact_saved = received.append

    text = "=== CHARACTER MEMORY: Raphael ===\nHe is brave.\n=== END ==="
    floor._save_character_memory_blocks(text, "MemoryKeeper")

    assert len(received) == 1
    evt = received[0]
    assert evt["type"] == "artifact_saved"
    assert evt["slug"] == "character-memory-raphael"
    assert evt["agent"] == "MemoryKeeper"
    assert evt["kind"] == "phase"
    assert "He is brave." in evt["preview"]


async def test_on_artifact_saved_not_called_when_none() -> None:
    """No error when _on_artifact_saved is None (the default)."""
    bus = MessageBus()
    floor = FloorManager(bus)
    # Default is None — must not raise
    text = "=== CHARACTER MEMORY: Test ===\ncontent\n=== END ==="
    floor._save_character_memory_blocks(text, "Agent")  # should not raise
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
pytest tests/test_floor_manager_extended.py::test_on_artifact_saved_callback_invoked tests/test_floor_manager_extended.py::test_on_artifact_saved_not_called_when_none -v
```

Expected: `test_on_artifact_saved_callback_invoked` FAILS (callback never called), `test_on_artifact_saved_not_called_when_none` PASSES (None default already true)

- [ ] **Step 3: Add `_on_artifact_saved` attribute to FloorManager.__init__**

In `src/ofp_playground/floor/manager.py`, inside `__init__` after the other `None`-defaulted attributes (around line 137):

```python
self._on_artifact_saved: Optional[callable] = None  # set by canvas bridge
```

- [ ] **Step 4: Wire callback in `_save_character_memory_blocks`**

Find the `for m in pattern.finditer(text):` loop in `_save_character_memory_blocks` (around line 588). Change:

```python
            self._artifact_store.save(
                agent_name=agent_name,
                content=char_content,
                slug=slug,
                summary=f"Character memory for {char_name}",
            )
            logger.debug("Saved per-character artifact: %s", slug)
```

To:

```python
            artifact = self._artifact_store.save(
                agent_name=agent_name,
                content=char_content,
                slug=slug,
                summary=f"Character memory for {char_name}",
            )
            logger.debug("Saved per-character artifact: %s", slug)
            if self._on_artifact_saved:
                self._on_artifact_saved({
                    "type": "artifact_saved",
                    "slug": artifact.slug,
                    "agent": agent_name,
                    "kind": "phase",
                    "preview": char_content[:120],
                })
```

- [ ] **Step 5: Wire callback in the `[ACCEPT]` directive handler**

Find the `[ACCEPT]` save block (around line 939). Change:

```python
                    self._artifact_store.save(
                        agent_name=self._last_worker_name or "unknown",
                        content=self._last_worker_text,
                    )
```

To:

```python
                    _accepted_artifact = self._artifact_store.save(
                        agent_name=self._last_worker_name or "unknown",
                        content=self._last_worker_text,
                    )
                    if self._on_artifact_saved:
                        self._on_artifact_saved({
                            "type": "artifact_saved",
                            "slug": _accepted_artifact.slug,
                            "agent": self._last_worker_name or "unknown",
                            "kind": "phase",
                            "preview": self._last_worker_text[:120],
                        })
```

- [ ] **Step 6: Wire callback in the breakout transcript save**

Find the breakout transcript `self._artifact_store.save(...)` (around line 1170). Change:

```python
                self._artifact_store.save(
                    agent_name="BreakoutSession",
                    content=transcript_content,
                    slug=beat_slug,
                    summary=f"Breakout transcript for beat {self._breakout_artifact_count}: {topic[:80]}",
                )
```

To:

```python
                _breakout_artifact = self._artifact_store.save(
                    agent_name="BreakoutSession",
                    content=transcript_content,
                    slug=beat_slug,
                    summary=f"Breakout transcript for beat {self._breakout_artifact_count}: {topic[:80]}",
                )
                if self._on_artifact_saved:
                    self._on_artifact_saved({
                        "type": "artifact_saved",
                        "slug": _breakout_artifact.slug,
                        "agent": "BreakoutSession",
                        "kind": "phase",
                        "preview": transcript_content[:120],
                    })
```

- [ ] **Step 7: Wire in canvas `_run_canvas_session`**

In `canvas/backend/main.py`, in `_run_canvas_session`, after `floor = FloorManager(bus, ...)` is constructed:

```python
    floor._on_artifact_saved = bridge.push_raw
```

- [ ] **Step 8: Run tests**

```bash
pytest tests/test_floor_manager_extended.py::test_on_artifact_saved_callback_invoked tests/test_floor_manager_extended.py::test_on_artifact_saved_not_called_when_none -v
```

Expected: both PASS

- [ ] **Step 9: Full test suite**

```bash
pytest tests/ -v --tb=short
```

Expected: all pass

- [ ] **Step 10: Commit**

```bash
git add src/ofp_playground/floor/manager.py canvas/backend/main.py tests/test_floor_manager_extended.py
git commit -m "feat(canvas): add _on_artifact_saved callback to FloorManager"
```

---

## Task 3: TypeScript types

**Files:**
- Modify: `canvas/frontend/src/types.ts`

- [ ] **Step 1: Add new types**

Replace the full contents of `canvas/frontend/src/types.ts` with:

```typescript
// canvas/frontend/src/types.ts

export type FloorPolicy =
  | 'SEQUENTIAL'
  | 'ROUND_ROBIN'
  | 'MODERATED'
  | 'FREE_FOR_ALL'
  | 'SHOWRUNNER_DRIVEN'

export type AgentProvider = 'anthropic' | 'openai' | 'google' | 'huggingface'

export type SessionState = 'idle' | 'running' | 'stopped'

export type AgentFloorState = 'speaking' | 'waiting' | 'requesting' | 'error' | 'spawning'

export type ArtifactKind = 'image' | 'code' | 'phase' | 'music'

export interface Message {
  id: string
  sender: string
  text: string
  ts: number
  media?: { type: string; url: string } | null
}

export interface FloorNodeData {
  policy: FloorPolicy
  topic: string
  maxTurns: number | null
  showFloorEvents: boolean
  noHuman: boolean
  humanName: string
  sessionState: SessionState
  sessionId: string | null
  turnCount: number
  elapsedSecs: number
}

export interface AgentNodeData {
  provider: AgentProvider
  name: string
  model: string
  systemPrompt: string
  slug: string
  agentType: string          // maps to TASK_SUBTYPES, '' = text-generation
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
  policy: string
  topic: string
  turnCount: number
}

export interface ArtifactNodeData {
  kind: ArtifactKind
  agentName: string
  slug?: string
  label: string        // filename or slug
  preview: string      // first ~120 chars, or image URL
  url?: string         // direct URL for images / audio
}

export interface GlowEdgeData {
  active: boolean      // true while the source agent holds the floor
  color: string        // stroke color
  dashed: boolean      // true for artifact edges
}

// ── WebSocket event union ─────────────────────────────────────────────────────

export type WSEvent =
  | { type: 'utterance'; sender: string; sender_uri: string; text: string; media: { type: string; url: string } | null }
  | { type: 'floor_grant'; to: string }
  | { type: 'floor_revoke'; from: string }
  | { type: 'floor_request'; from: string }
  | { type: 'artifact_saved'; slug: string; kind: string; agent: string; preview: string }
  | { type: 'image_saved'; agent: string; url: string }
  | { type: 'memory_saved'; category: string; content: string; agent: string | null }
  | { type: 'agent_joined'; name: string; provider: string }
  | { type: 'agent_kicked'; name: string }
  | { type: 'agent_spawning'; name: string; provider: string }
  | { type: 'error'; agent: string; message: string; retryable: boolean }
  | { type: 'session_ended' }

// ── Agent library entry ───────────────────────────────────────────────────────

export interface SlugEntry {
  slug: string
  display_name: string
  category: string
}
```

- [ ] **Step 2: Type-check**

```bash
cd canvas/frontend && npx tsc --noEmit 2>&1 | head -30
```

Expected: errors only from files that import the deleted types (will be fixed in later tasks)

- [ ] **Step 3: Commit**

```bash
cd canvas/frontend && git add src/types.ts && cd ../..
git add canvas/frontend/src/types.ts
git commit -m "feat(canvas): add ArtifactNodeData, GlowEdgeData, agentType, SlugEntry types"
```

---

## Task 4: CanvasContext

**Files:**
- Create: `canvas/frontend/src/context/CanvasContext.tsx`

- [ ] **Step 1: Create CanvasContext**

```typescript
// canvas/frontend/src/context/CanvasContext.tsx
import { createContext, useContext } from 'react'
import type { FloorNodeData } from '../types'

export interface CanvasCallbacks {
  onRun: () => void
  onStop: () => void
  onFloorChange: (patch: Partial<FloorNodeData>) => void
  onKick: (name: string) => void
  onSend: (text: string) => void
  sessionRunning: boolean
}

const CanvasContext = createContext<CanvasCallbacks | null>(null)

export function useCanvas(): CanvasCallbacks {
  const ctx = useContext(CanvasContext)
  if (!ctx) throw new Error('useCanvas must be used inside CanvasContext.Provider')
  return ctx
}

export { CanvasContext }
```

- [ ] **Step 2: Type-check**

```bash
cd canvas/frontend && npx tsc --noEmit 2>&1 | head -20
```

Expected: no new errors from `context/CanvasContext.tsx`

- [ ] **Step 3: Commit**

```bash
git add canvas/frontend/src/context/CanvasContext.tsx
git commit -m "feat(canvas): add CanvasContext for stable node callback references"
```

---

## Task 5: Update FloorNode, AgentNode, HumanNode to use CanvasContext

**Files:**
- Modify: `canvas/frontend/src/nodes/FloorNode.tsx`
- Modify: `canvas/frontend/src/nodes/AgentNode.tsx`
- Modify: `canvas/frontend/src/nodes/HumanNode.tsx`

- [ ] **Step 1: Rewrite FloorNode.tsx**

```typescript
// canvas/frontend/src/nodes/FloorNode.tsx
import { Handle, Position } from '@xyflow/react'
import { useCanvas } from '../context/CanvasContext'
import type { FloorNodeData, FloorPolicy } from '../types'

const POLICIES: FloorPolicy[] = [
  'SEQUENTIAL', 'ROUND_ROBIN', 'MODERATED', 'FREE_FOR_ALL', 'SHOWRUNNER_DRIVEN',
]

const SESSION_STATE_COLOR: Record<string, string> = {
  idle: '#4a5568',
  running: '#38a169',
  stopped: '#e53e3e',
}

export function FloorNode({ data }: { data: FloorNodeData }) {
  const { onRun, onStop, onFloorChange } = useCanvas()
  const stateColor = SESSION_STATE_COLOR[data.sessionState] ?? '#4a5568'
  const isRunning = data.sessionState === 'running'

  return (
    <div style={{
      background: 'linear-gradient(135deg, #1a2332 0%, #0d1520 100%)',
      border: `2px solid ${stateColor}`,
      borderRadius: 12,
      padding: '14px 16px',
      minWidth: 260,
      color: '#e6edf5',
      fontFamily: 'ui-sans-serif, system-ui, sans-serif',
      fontSize: 13,
      boxShadow: `0 0 20px ${stateColor}44`,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 12 }}>
        <div style={{
          width: 10, height: 10, borderRadius: '50%',
          background: stateColor, boxShadow: `0 0 6px ${stateColor}`,
        }} />
        <span style={{ fontWeight: 700, fontSize: 14 }}>Floor</span>
        <span style={{
          marginLeft: 'auto', fontSize: 11, background: `${stateColor}33`,
          color: stateColor, borderRadius: 4, padding: '1px 6px',
        }}>
          {data.sessionState}
        </span>
      </div>

      <label style={{ display: 'block', marginBottom: 8 }}>
        <div style={{ color: '#93a4b8', fontSize: 11, marginBottom: 3 }}>Policy</div>
        <select
          value={data.policy}
          onChange={(e) => onFloorChange({ policy: e.target.value as FloorPolicy })}
          disabled={isRunning}
          style={{
            width: '100%', background: '#0d1520', color: '#e6edf5',
            border: '1px solid #2a3a4c', borderRadius: 6, padding: '4px 8px', fontSize: 12,
          }}
        >
          {POLICIES.map((p) => <option key={p} value={p}>{p}</option>)}
        </select>
      </label>

      <label style={{ display: 'block', marginBottom: 8 }}>
        <div style={{ color: '#93a4b8', fontSize: 11, marginBottom: 3 }}>Topic</div>
        <input
          type="text"
          value={data.topic}
          onChange={(e) => onFloorChange({ topic: e.target.value })}
          disabled={isRunning}
          placeholder="Optional starting topic…"
          style={{
            width: '100%', background: '#0d1520', color: '#e6edf5',
            border: '1px solid #2a3a4c', borderRadius: 6, padding: '4px 8px',
            fontSize: 12, boxSizing: 'border-box',
          }}
        />
      </label>

      <div style={{ display: 'flex', gap: 8, marginBottom: 10 }}>
        <label style={{ flex: 1 }}>
          <div style={{ color: '#93a4b8', fontSize: 11, marginBottom: 3 }}>Max turns</div>
          <input
            type="number"
            value={data.maxTurns ?? ''}
            min={1}
            onChange={(e) => onFloorChange({ maxTurns: e.target.value ? Number(e.target.value) : null })}
            disabled={isRunning}
            placeholder="∞"
            style={{
              width: '100%', background: '#0d1520', color: '#e6edf5',
              border: '1px solid #2a3a4c', borderRadius: 6, padding: '4px 8px',
              fontSize: 12, boxSizing: 'border-box',
            }}
          />
        </label>
        <label style={{ display: 'flex', alignItems: 'flex-end', gap: 5, paddingBottom: 4 }}>
          <input
            type="checkbox"
            checked={data.noHuman}
            onChange={(e) => onFloorChange({ noHuman: e.target.checked })}
            disabled={isRunning}
          />
          <span style={{ color: '#93a4b8', fontSize: 11 }}>No human</span>
        </label>
      </div>

      {isRunning && (
        <div style={{ display: 'flex', gap: 10, marginBottom: 10, fontSize: 11, color: '#93a4b8' }}>
          <span>Turns: <b style={{ color: '#58a6ff' }}>{data.turnCount}</b></span>
          <span>Elapsed: <b style={{ color: '#58a6ff' }}>{data.elapsedSecs}s</b></span>
        </div>
      )}

      <button
        onClick={isRunning ? onStop : onRun}
        style={{
          width: '100%', padding: '7px 0',
          background: isRunning ? '#6b2121' : '#1a4731',
          color: isRunning ? '#fc8181' : '#68d391',
          border: `1px solid ${isRunning ? '#fc818166' : '#68d39166'}`,
          borderRadius: 7, fontWeight: 600, fontSize: 13, cursor: 'pointer',
        }}
      >
        {isRunning ? '■ Stop' : '▶ Run'}
      </button>

      <Handle type="source" position={Position.Right} style={{ background: stateColor }} />
    </div>
  )
}
```

- [ ] **Step 2: Rewrite AgentNode.tsx**

```typescript
// canvas/frontend/src/nodes/AgentNode.tsx
import { useState } from 'react'
import { Handle, Position } from '@xyflow/react'
import { useCanvas } from '../context/CanvasContext'
import type { AgentNodeData, AgentFloorState } from '../types'

const PROVIDER_COLOR: Record<string, string> = {
  anthropic: '#d4a843',
  openai: '#10a37f',
  google: '#4285f4',
  huggingface: '#ff7b00',
}

const STATE_COLOR: Record<AgentFloorState, string> = {
  speaking: '#38a169',
  waiting: '#4a5568',
  requesting: '#d69e2e',
  error: '#e53e3e',
  spawning: '#805ad5',
}

const STATE_LABEL: Record<AgentFloorState, string> = {
  speaking: '🎙 speaking',
  waiting: '⏳ waiting',
  requesting: '✋ requesting',
  error: '❌ error',
  spawning: '⚙ spawning',
}

const TYPE_COLOR: Record<string, string> = {
  showrunner: '#d4a843',
  orchestrator: '#d4a843',
  'code-generation': '#00bcd4',
  'text-to-image': '#8b5cf6',
  'text-to-music': '#f97316',
  'text-to-video': '#e53e3e',
}

export function AgentNode({ data }: { data: AgentNodeData }) {
  const { onKick } = useCanvas()
  const [hovered, setHovered] = useState(false)
  const [expanded, setExpanded] = useState(false)
  const providerColor = PROVIDER_COLOR[data.provider] ?? '#58a6ff'
  const stateColor = STATE_COLOR[data.floorState] ?? '#4a5568'
  const isSpeaking = data.floorState === 'speaking'
  const isSpawning = data.floorState === 'spawning'
  const typeColor = data.agentType ? (TYPE_COLOR[data.agentType] ?? '#58a6ff') : null

  return (
    <div
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      style={{
        background: 'linear-gradient(135deg, #161f2e 0%, #0d1520 100%)',
        border: `2px solid ${isSpeaking ? stateColor : '#2a3a4c'}`,
        borderRadius: 10, padding: '12px 14px',
        minWidth: 220, maxWidth: 300,
        color: '#e6edf5', fontFamily: 'ui-sans-serif, system-ui, sans-serif', fontSize: 12,
        position: 'relative', transition: 'border-color 0.2s, box-shadow 0.2s',
        boxShadow: isSpeaking ? `0 0 18px ${stateColor}55` : undefined,
        opacity: isSpawning ? 0.6 : 1,
      }}
    >
      <Handle type="target" position={Position.Left} style={{ background: providerColor }} />

      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
        <span style={{
          background: `${providerColor}22`, color: providerColor,
          borderRadius: 4, padding: '1px 6px', fontSize: 10, fontWeight: 700,
          textTransform: 'uppercase',
        }}>
          {data.provider}
        </span>
        {typeColor && data.agentType && (
          <span style={{
            background: `${typeColor}22`, color: typeColor,
            borderRadius: 4, padding: '1px 6px', fontSize: 9, fontWeight: 700,
            textTransform: 'uppercase',
          }}>
            {data.agentType.replace('-', ' ')}
          </span>
        )}
        <span style={{ fontWeight: 700, fontSize: 13, flex: 1 }}>{data.name}</span>
        <span style={{
          fontSize: 10, background: `${stateColor}22`, color: stateColor,
          borderRadius: 4, padding: '1px 6px',
        }}>
          {STATE_LABEL[data.floorState]}
        </span>
      </div>

      {data.model && (
        <div style={{ color: '#93a4b8', fontSize: 10, marginBottom: 6 }}>{data.model}</div>
      )}

      {data.floorState === 'error' && data.errorMessage && (
        <div style={{
          background: '#2d1515', border: '1px solid #e53e3e44',
          borderRadius: 5, padding: '4px 7px', fontSize: 11,
          color: '#fc8181', marginBottom: 6,
        }}>
          {data.errorMessage}
        </div>
      )}

      {data.messages.length > 0 && (
        <div style={{ marginTop: 4 }}>
          <div
            onClick={() => setExpanded(!expanded)}
            style={{ cursor: 'pointer', fontSize: 10, color: '#93a4b8', marginBottom: 4, userSelect: 'none' }}
          >
            {expanded ? '▾' : '▸'} {data.messages.length} message{data.messages.length !== 1 ? 's' : ''}
          </div>
          {expanded && (
            <div style={{ maxHeight: 180, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 4 }}>
              {data.messages.slice(-8).map((msg) => (
                <div key={msg.id} style={{
                  background: '#0d1520', borderRadius: 6, padding: '5px 8px',
                  fontSize: 11, lineHeight: 1.4, color: '#c9d1d9',
                  wordBreak: 'break-word', border: '1px solid #2a3a4c',
                }}>
                  {msg.media && (
                    <div style={{ marginBottom: 4 }}>
                      {msg.media.type === 'image' ? (
                        <img src={msg.media.url} alt="output" style={{ maxWidth: '100%', borderRadius: 4 }} />
                      ) : (
                        <a href={msg.media.url} target="_blank" rel="noreferrer" style={{ color: '#58a6ff' }}>
                          [{msg.media.type}]
                        </a>
                      )}
                    </div>
                  )}
                  {msg.text}
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {hovered && (
        <button
          onClick={() => onKick(data.name)}
          style={{
            position: 'absolute', top: 8, right: 8,
            background: '#6b2121', color: '#fc8181',
            border: '1px solid #fc818166',
            borderRadius: 4, fontSize: 10, padding: '2px 6px', cursor: 'pointer',
          }}
        >
          Kick
        </button>
      )}
    </div>
  )
}
```

- [ ] **Step 3: Rewrite HumanNode.tsx**

Read the current HumanNode.tsx first, then replace the props interface and add `useCanvas()`:

```typescript
// canvas/frontend/src/nodes/HumanNode.tsx
import { useState } from 'react'
import { Handle, Position } from '@xyflow/react'
import { useCanvas } from '../context/CanvasContext'
import type { HumanNodeData } from '../types'

export function HumanNode({ data }: { data: HumanNodeData }) {
  const { onSend, sessionRunning } = useCanvas()
  const [input, setInput] = useState('')

  const submit = () => {
    if (!input.trim() || !sessionRunning) return
    onSend(input.trim())
    setInput('')
  }

  return (
    <div style={{
      background: 'linear-gradient(135deg, #1a2a1a 0%, #0d1520 100%)',
      border: '2px solid #38a169',
      borderRadius: 10, padding: '12px 14px',
      minWidth: 220, maxWidth: 300,
      color: '#e6edf5', fontFamily: 'ui-sans-serif, system-ui, sans-serif', fontSize: 12,
    }}>
      <Handle type="target" position={Position.Left} style={{ background: '#38a169' }} />

      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
        <span style={{
          background: '#38a16922', color: '#68d391',
          borderRadius: 4, padding: '1px 6px', fontSize: 10, fontWeight: 700,
        }}>HUMAN</span>
        <span style={{ fontWeight: 700, fontSize: 13 }}>{data.humanName}</span>
      </div>

      {data.messages.length > 0 && (
        <div style={{
          maxHeight: 120, overflowY: 'auto',
          display: 'flex', flexDirection: 'column', gap: 4, marginBottom: 8,
        }}>
          {data.messages.slice(-4).map((msg) => (
            <div key={msg.id} style={{
              background: '#0d1520', borderRadius: 6, padding: '4px 8px',
              fontSize: 11, color: '#c9d1d9', wordBreak: 'break-word',
              border: '1px solid #2a3a4c',
            }}>
              {msg.text}
            </div>
          ))}
        </div>
      )}

      {sessionRunning && (
        <div style={{ display: 'flex', gap: 6 }}>
          <input
            type="text"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && submit()}
            placeholder="Type a message…"
            style={{
              flex: 1, background: '#0d1520', color: '#e6edf5',
              border: '1px solid #2a3a4c', borderRadius: 6, padding: '4px 8px',
              fontSize: 11, boxSizing: 'border-box',
            }}
          />
          <button onClick={submit} style={{
            background: '#1a4731', color: '#68d391',
            border: '1px solid #68d39166',
            borderRadius: 6, padding: '4px 10px', cursor: 'pointer', fontSize: 11,
          }}>Send</button>
        </div>
      )}
    </div>
  )
}
```

- [ ] **Step 4: Type-check**

```bash
cd canvas/frontend && npx tsc --noEmit 2>&1 | head -30
```

Expected: errors only from App.tsx (still passes old props; fixed in Task 10)

- [ ] **Step 5: Commit**

```bash
git add canvas/frontend/src/nodes/FloorNode.tsx canvas/frontend/src/nodes/AgentNode.tsx canvas/frontend/src/nodes/HumanNode.tsx
git commit -m "feat(canvas): refactor node callbacks to useCanvas() context"
```

---

## Task 6: GlowEdge custom edge

**Files:**
- Create: `canvas/frontend/src/edges/GlowEdge.tsx`

- [ ] **Step 1: Create GlowEdge**

```typescript
// canvas/frontend/src/edges/GlowEdge.tsx
import { getBezierPath, type EdgeProps } from '@xyflow/react'
import type { GlowEdgeData } from '../types'

export function GlowEdge({
  id,
  sourceX, sourceY, targetX, targetY,
  sourcePosition, targetPosition,
  data,
}: EdgeProps<Record<string, unknown>>) {
  const edgeData = data as unknown as GlowEdgeData
  const [edgePath] = getBezierPath({ sourceX, sourceY, sourcePosition, targetX, targetY, targetPosition })
  const color = edgeData?.color ?? '#2a3a4c'
  const active = edgeData?.active ?? false
  const dashed = edgeData?.dashed ?? false

  return (
    <>
      <style>{`
        @keyframes dashTravel {
          from { stroke-dashoffset: 300; }
          to   { stroke-dashoffset: 0;   }
        }
      `}</style>

      {/* Base path */}
      <path
        id={id}
        className="react-flow__edge-path"
        d={edgePath}
        style={{
          stroke: color,
          strokeWidth: active ? 2.5 : 1.5,
          strokeDasharray: dashed ? '5 4' : undefined,
          fill: 'none',
        }}
      />

      {/* Animated glow overlay — only when active */}
      {active && (
        <path
          d={edgePath}
          style={{
            stroke: color,
            strokeWidth: 3,
            strokeDasharray: '10 8',
            fill: 'none',
            filter: `drop-shadow(0 0 5px ${color})`,
            animation: 'dashTravel 1.0s linear infinite',
            pointerEvents: 'none',
          }}
        />
      )}
    </>
  )
}
```

- [ ] **Step 2: Type-check**

```bash
cd canvas/frontend && npx tsc --noEmit 2>&1 | head -20
```

Expected: no new errors from `edges/GlowEdge.tsx`

- [ ] **Step 3: Commit**

```bash
git add canvas/frontend/src/edges/GlowEdge.tsx
git commit -m "feat(canvas): add GlowEdge custom edge with animated dash-travel glow"
```

---

## Task 7: Artifact node components

**Files:**
- Create: `canvas/frontend/src/nodes/ImageArtifactNode.tsx`
- Create: `canvas/frontend/src/nodes/CodeArtifactNode.tsx`
- Create: `canvas/frontend/src/nodes/PhaseArtifactNode.tsx`
- Create: `canvas/frontend/src/nodes/MusicArtifactNode.tsx`

- [ ] **Step 1: Create ImageArtifactNode.tsx**

```typescript
// canvas/frontend/src/nodes/ImageArtifactNode.tsx
import { useState } from 'react'
import { Handle, Position } from '@xyflow/react'
import type { ArtifactNodeData } from '../types'

export function ImageArtifactNode({ data }: { data: ArtifactNodeData }) {
  const [lightbox, setLightbox] = useState(false)

  return (
    <div style={{
      background: 'linear-gradient(135deg, #1a1230 0%, #0d1520 100%)',
      border: '2px solid #8b5cf6',
      borderRadius: 10, padding: '10px 12px',
      minWidth: 160, maxWidth: 200,
      color: '#e6edf5', fontFamily: 'ui-sans-serif, system-ui, sans-serif', fontSize: 11,
    }}>
      <Handle type="target" position={Position.Left} style={{ background: '#8b5cf6' }} />
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 8 }}>
        <span style={{
          background: '#8b5cf622', color: '#c4b5fd',
          border: '1px solid #8b5cf644', borderRadius: 4,
          padding: '1px 5px', fontSize: 9, fontWeight: 700,
        }}>IMAGE</span>
        <span style={{ color: '#93a4b8', fontSize: 10, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
          {data.label}
        </span>
      </div>
      {data.url && (
        <img
          src={data.url}
          alt={data.label}
          onClick={() => setLightbox(true)}
          style={{ width: '100%', borderRadius: 5, cursor: 'pointer', display: 'block' }}
        />
      )}
      {lightbox && (
        <dialog
          open
          onClick={() => setLightbox(false)}
          style={{
            position: 'fixed', inset: 0, margin: 0,
            width: '100vw', height: '100vh',
            background: '#000000cc', border: 'none', zIndex: 9999,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}
        >
          <img
            src={data.url}
            alt={data.label}
            style={{ maxWidth: '90vw', maxHeight: '90vh', borderRadius: 8 }}
          />
        </dialog>
      )}
    </div>
  )
}
```

- [ ] **Step 2: Create CodeArtifactNode.tsx**

```typescript
// canvas/frontend/src/nodes/CodeArtifactNode.tsx
import { useState } from 'react'
import { Handle, Position } from '@xyflow/react'
import type { ArtifactNodeData } from '../types'

export function CodeArtifactNode({ data }: { data: ArtifactNodeData }) {
  const [expanded, setExpanded] = useState(false)

  return (
    <div style={{
      background: 'linear-gradient(135deg, #0d1a18 0%, #0d1520 100%)',
      border: '2px solid #10a37f',
      borderRadius: 10, padding: '10px 12px',
      minWidth: 160, maxWidth: 220,
      color: '#e6edf5', fontFamily: 'ui-sans-serif, system-ui, sans-serif', fontSize: 11,
    }}>
      <Handle type="target" position={Position.Left} style={{ background: '#10a37f' }} />
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 6 }}>
        <span style={{
          background: '#10a37f22', color: '#6ee7b7',
          border: '1px solid #10a37f44', borderRadius: 4,
          padding: '1px 5px', fontSize: 9, fontWeight: 700,
        }}>CODE</span>
        <span style={{ color: '#93a4b8', fontSize: 10, flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
          {data.label}
        </span>
        <span
          onClick={() => setExpanded(e => !e)}
          style={{ cursor: 'pointer', color: '#4a5568', fontSize: 10, flexShrink: 0 }}
        >
          {expanded ? '▾' : '▸'}
        </span>
      </div>
      {expanded && (
        <pre style={{
          background: '#0d1520', borderRadius: 5, padding: '5px 7px',
          fontFamily: 'monospace', fontSize: 9, color: '#68d391',
          margin: 0, maxHeight: 120, overflowY: 'auto',
          whiteSpace: 'pre-wrap', wordBreak: 'break-all',
        }}>
          {data.preview}
        </pre>
      )}
    </div>
  )
}
```

- [ ] **Step 3: Create PhaseArtifactNode.tsx**

```typescript
// canvas/frontend/src/nodes/PhaseArtifactNode.tsx
import { useState } from 'react'
import { Handle, Position } from '@xyflow/react'
import type { ArtifactNodeData } from '../types'

export function PhaseArtifactNode({ data }: { data: ArtifactNodeData }) {
  const [expanded, setExpanded] = useState(false)

  return (
    <div style={{
      background: 'linear-gradient(135deg, #0d1520 0%, #0d1117 100%)',
      border: '2px solid #58a6ff',
      borderRadius: 10, padding: '10px 12px',
      minWidth: 160, maxWidth: 220,
      color: '#e6edf5', fontFamily: 'ui-sans-serif, system-ui, sans-serif', fontSize: 11,
    }}>
      <Handle type="target" position={Position.Left} style={{ background: '#58a6ff' }} />
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 6 }}>
        <span style={{
          background: '#58a6ff22', color: '#90cdf4',
          border: '1px solid #58a6ff44', borderRadius: 4,
          padding: '1px 5px', fontSize: 9, fontWeight: 700,
        }}>PHASE</span>
        <span style={{ color: '#93a4b8', fontSize: 10, flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
          {data.label}
        </span>
        <span
          onClick={() => setExpanded(e => !e)}
          style={{ cursor: 'pointer', color: '#4a5568', fontSize: 10, flexShrink: 0 }}
        >
          {expanded ? '▾' : '▸'}
        </span>
      </div>
      {expanded && (
        <div style={{
          background: '#0d1520', borderRadius: 5, padding: '5px 7px',
          fontSize: 10, color: '#90cdf4', lineHeight: 1.5,
          maxHeight: 120, overflowY: 'auto',
        }}>
          {data.preview}
        </div>
      )}
    </div>
  )
}
```

- [ ] **Step 4: Create MusicArtifactNode.tsx**

```typescript
// canvas/frontend/src/nodes/MusicArtifactNode.tsx
import { Handle, Position } from '@xyflow/react'
import type { ArtifactNodeData } from '../types'

export function MusicArtifactNode({ data }: { data: ArtifactNodeData }) {
  return (
    <div style={{
      background: 'linear-gradient(135deg, #1a1005 0%, #0d1520 100%)',
      border: '2px solid #f97316',
      borderRadius: 10, padding: '10px 12px',
      minWidth: 160, maxWidth: 200,
      color: '#e6edf5', fontFamily: 'ui-sans-serif, system-ui, sans-serif', fontSize: 11,
    }}>
      <Handle type="target" position={Position.Left} style={{ background: '#f97316' }} />
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 8 }}>
        <span style={{
          background: '#f9731622', color: '#fdba74',
          border: '1px solid #f9731644', borderRadius: 4,
          padding: '1px 5px', fontSize: 9, fontWeight: 700,
        }}>MUSIC</span>
        <span style={{ color: '#93a4b8', fontSize: 10, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
          {data.label}
        </span>
      </div>
      {data.url ? (
        <audio controls src={data.url} style={{ width: '100%', height: 30 }} />
      ) : (
        <div style={{
          background: '#0d1520', borderRadius: 5, padding: '8px',
          textAlign: 'center', color: '#f97316', fontSize: 20,
        }}>
          ♪
        </div>
      )}
    </div>
  )
}
```

- [ ] **Step 5: Type-check all four**

```bash
cd canvas/frontend && npx tsc --noEmit 2>&1 | head -30
```

Expected: no new errors from the four new files

- [ ] **Step 6: Commit**

```bash
git add canvas/frontend/src/nodes/ImageArtifactNode.tsx \
        canvas/frontend/src/nodes/CodeArtifactNode.tsx \
        canvas/frontend/src/nodes/PhaseArtifactNode.tsx \
        canvas/frontend/src/nodes/MusicArtifactNode.tsx
git commit -m "feat(canvas): add ImageArtifactNode, CodeArtifactNode, PhaseArtifactNode, MusicArtifactNode"
```

---

## Task 8: SlugCombobox (useSlugs + SlugCombobox)

**Files:**
- Create: `canvas/frontend/src/hooks/useSlugs.ts`
- Create: `canvas/frontend/src/components/SlugCombobox.tsx`

- [ ] **Step 1: Create useSlugs.ts**

```typescript
// canvas/frontend/src/hooks/useSlugs.ts
import { useEffect, useState } from 'react'
import type { SlugEntry } from '../types'

export function useSlugs(): SlugEntry[] {
  const [slugs, setSlugs] = useState<SlugEntry[]>([])

  useEffect(() => {
    fetch('/agents/list')
      .then(r => r.json())
      .then((data: SlugEntry[]) => setSlugs(data))
      .catch(() => {/* server not up yet — silent fail */})
  }, [])

  return slugs
}
```

- [ ] **Step 2: Create SlugCombobox.tsx**

```typescript
// canvas/frontend/src/components/SlugCombobox.tsx
import { useRef, useState } from 'react'
import type { SlugEntry } from '../types'

interface SlugComboboxProps {
  value: string
  onChange: (value: string) => void
  slugs: SlugEntry[]
  placeholder?: string
  style?: React.CSSProperties
}

export function SlugCombobox({ value, onChange, slugs, placeholder, style }: SlugComboboxProps) {
  const [activeIndex, setActiveIndex] = useState(-1)
  const [open, setOpen] = useState(false)
  const closeTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  const isSlugMode = value.startsWith('@')
  const query = isSlugMode ? value.slice(1).toLowerCase() : ''

  const filtered = isSlugMode && query.length > 0
    ? slugs
        .filter(s =>
          s.slug.toLowerCase().includes(query) ||
          s.display_name.toLowerCase().includes(query)
        )
        .slice(0, 5)
    : []

  const showList = open && filtered.length > 0

  const accept = (slug: string) => {
    onChange(`@${slug}`)
    setOpen(false)
    setActiveIndex(-1)
  }

  const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (!showList) return
    if (e.key === 'ArrowDown') {
      e.preventDefault()
      setActiveIndex(i => Math.min(i + 1, filtered.length - 1))
    } else if (e.key === 'ArrowUp') {
      e.preventDefault()
      setActiveIndex(i => Math.max(i - 1, 0))
    } else if ((e.key === 'Enter' || e.key === 'Tab') && activeIndex >= 0) {
      e.preventDefault()
      accept(filtered[activeIndex].slug)
    } else if (e.key === 'Escape') {
      setOpen(false)
    }
  }

  return (
    <div style={{ position: 'relative' }}>
      <input
        type="text"
        value={value}
        onChange={e => { onChange(e.target.value); setOpen(true); setActiveIndex(-1) }}
        onFocus={() => setOpen(true)}
        onBlur={() => { closeTimer.current = setTimeout(() => setOpen(false), 150) }}
        onKeyDown={handleKeyDown}
        placeholder={placeholder ?? '@slug or system prompt'}
        style={style}
      />
      {showList && (
        <div style={{
          position: 'absolute', top: 'calc(100% + 3px)', left: 0, right: 0,
          background: '#1a2332', border: '1px solid #2a4060', borderRadius: 6,
          zIndex: 100, overflow: 'hidden', boxShadow: '0 4px 16px #00000077',
        }}>
          {filtered.map((entry, i) => (
            <div
              key={entry.slug}
              onMouseDown={() => {
                if (closeTimer.current) clearTimeout(closeTimer.current)
                accept(entry.slug)
              }}
              style={{
                padding: '5px 10px', fontSize: 11, cursor: 'pointer',
                background: i === activeIndex ? '#1a3a5a' : 'transparent',
                color: i === activeIndex ? '#e6edf5' : '#93a4b8',
                display: 'flex', alignItems: 'center', gap: 8,
              }}
            >
              <span>@{entry.slug}</span>
              <span style={{ fontSize: 9, color: '#4a5568', marginLeft: 'auto' }}>{entry.category}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
```

- [ ] **Step 3: Type-check**

```bash
cd canvas/frontend && npx tsc --noEmit 2>&1 | head -20
```

Expected: no new errors

- [ ] **Step 4: Commit**

```bash
git add canvas/frontend/src/hooks/useSlugs.ts canvas/frontend/src/components/SlugCombobox.tsx
git commit -m "feat(canvas): add useSlugs hook and SlugCombobox with @ prefix filtering"
```

---

## Task 9: useModels hook

**Files:**
- Create: `canvas/frontend/src/hooks/useModels.ts`

- [ ] **Step 1: Create useModels.ts**

```typescript
// canvas/frontend/src/hooks/useModels.ts
import { useEffect, useState } from 'react'

export function useModels(): Record<string, string[]> {
  const [models, setModels] = useState<Record<string, string[]>>({
    anthropic: [], openai: [], google: [], huggingface: [],
  })

  useEffect(() => {
    fetch('/models/list')
      .then(r => r.json())
      .then((data: Record<string, string[]>) => setModels(data))
      .catch(() => {/* silent fail */})
  }, [])

  return models
}
```

- [ ] **Step 2: Type-check**

```bash
cd canvas/frontend && npx tsc --noEmit 2>&1 | head -20
```

Expected: no new errors

- [ ] **Step 3: Commit**

```bash
git add canvas/frontend/src/hooks/useModels.ts
git commit -m "feat(canvas): add useModels hook for provider-filtered model suggestions"
```

---

## Task 10: App.tsx full wiring

**Files:**
- Modify: `canvas/frontend/src/App.tsx`
- Delete: `canvas/frontend/src/cards/ArtifactCard.tsx`, `canvas/frontend/src/cards/ImageCard.tsx`, `canvas/frontend/src/cards/MemoryCard.tsx`

This task rewrites `App.tsx` in full. Read the current file carefully before replacing.

- [ ] **Step 1: Delete the three floating card components**

```bash
rm canvas/frontend/src/cards/ArtifactCard.tsx \
   canvas/frontend/src/cards/ImageCard.tsx \
   canvas/frontend/src/cards/MemoryCard.tsx
```

- [ ] **Step 2: Write the new App.tsx**

```typescript
// canvas/frontend/src/App.tsx
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import {
  ReactFlow,
  Background,
  Controls,
  MiniMap,
  addEdge,
  useNodesState,
  useEdgesState,
  type Node,
  type Edge,
  type Connection,
  type NodeTypes,
  type EdgeTypes,
  BackgroundVariant,
} from '@xyflow/react'
import dagre from 'dagre'

import { CanvasContext } from './context/CanvasContext'
import type { CanvasCallbacks } from './context/CanvasContext'
import { FloorNode } from './nodes/FloorNode'
import { AgentNode } from './nodes/AgentNode'
import { HumanNode } from './nodes/HumanNode'
import { ConversationNode } from './nodes/ConversationNode'
import { ImageArtifactNode } from './nodes/ImageArtifactNode'
import { CodeArtifactNode } from './nodes/CodeArtifactNode'
import { PhaseArtifactNode } from './nodes/PhaseArtifactNode'
import { MusicArtifactNode } from './nodes/MusicArtifactNode'
import { GlowEdge } from './edges/GlowEdge'
import { SlugCombobox } from './components/SlugCombobox'
import { useSlugs } from './hooks/useSlugs'
import { useModels } from './hooks/useModels'
import { useSession } from './hooks/useSession'

import type {
  FloorNodeData, AgentNodeData, HumanNodeData, ConversationNodeData,
  ArtifactNodeData, GlowEdgeData, WSEvent, FloorPolicy, AgentFloorState, Message,
} from './types'

// ── Stable module-level constants — never recreated on render ─────────────────

const NODE_TYPES: NodeTypes = {
  FloorNode,
  AgentNode,
  HumanNode,
  ConversationNode,
  ImageArtifactNode,
  CodeArtifactNode,
  PhaseArtifactNode,
  MusicArtifactNode,
}

const EDGE_TYPES: EdgeTypes = { glow: GlowEdge }

const TASK_SUBTYPES = [
  '', 'showrunner', 'orchestrator', 'code-generation',
  'text-to-image', 'text-to-video', 'text-to-music',
  'image-to-text', 'image-text-to-text',
  'text-generation', 'text-classification', 'summarization',
  'image-classification', 'object-detection', 'image-segmentation',
  'token-classification',
]

const ARTIFACT_COLOR: Record<string, string> = {
  image: '#8b5cf6', code: '#10a37f', file: '#10a37f',
  phase: '#58a6ff', markdown: '#58a6ff', music: '#f97316',
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function artifactNodeType(kind: string): string {
  if (kind === 'image') return 'ImageArtifactNode'
  if (kind === 'code' || kind === 'file') return 'CodeArtifactNode'
  if (kind === 'music') return 'MusicArtifactNode'
  return 'PhaseArtifactNode'
}

function nextArtifactPosition(
  currentNodes: Node[],
  agentNodeId: string,
): { x: number; y: number } {
  const agentNode = currentNodes.find(n => n.id === agentNodeId)
  const agentName = (agentNode?.data as AgentNodeData | undefined)?.name ?? ''
  const baseX = (agentNode?.position.x ?? 400) + 260
  const baseY = agentNode?.position.y ?? 100
  const agentArtifactCount = currentNodes.filter(n =>
    (n.type?.includes('ArtifactNode') ?? false) &&
    (n.data as ArtifactNodeData)?.agentName === agentName
  ).length
  return { x: baseX, y: baseY + agentArtifactCount * 140 }
}

function glowEdge(
  id: string, source: string, target: string,
  opts: Partial<GlowEdgeData> = {},
): Edge {
  return {
    id,
    source,
    target,
    type: 'glow',
    data: { active: false, color: '#2a3a4c', dashed: false, ...opts } satisfies GlowEdgeData,
  }
}

function applyDagreLayout(nodes: Node[], edges: Edge[]): Node[] {
  const g = new dagre.graphlib.Graph()
  g.setGraph({ rankdir: 'LR', ranksep: 80, nodesep: 40 })
  g.setDefaultEdgeLabel(() => ({}))
  nodes.forEach((n) => g.setNode(n.id, { width: 280, height: 200 }))
  edges.forEach((e) => g.setEdge(e.source, e.target))
  dagre.layout(g)
  return nodes.map((n) => {
    const pos = g.node(n.id)
    return { ...n, position: { x: pos.x - 140, y: pos.y - 100 } }
  })
}

// ── Constants ─────────────────────────────────────────────────────────────────

const FLOOR_ID = 'floor-main'
const CONV_ID = 'conv-main'
const LAYOUT_KEY = 'ofp-canvas-layout-v3'   // bumped: glow edge data shape changed
const API = ''

// ── Typed data accessors ──────────────────────────────────────────────────────

function asFloor(data: unknown): FloorNodeData { return data as FloorNodeData }
function asAgent(data: unknown): AgentNodeData { return data as AgentNodeData }
function asConv(data: unknown): ConversationNodeData { return data as ConversationNodeData }

// ── Initial nodes ─────────────────────────────────────────────────────────────

function makeInitialNodes(): Node[] {
  return applyDagreLayout(
    [
      {
        id: FLOOR_ID, type: 'FloorNode', position: { x: 0, y: 0 },
        data: {
          policy: 'SEQUENTIAL', topic: '', maxTurns: null,
          showFloorEvents: false, noHuman: true, humanName: 'User',
          sessionState: 'idle', sessionId: null, turnCount: 0, elapsedSecs: 0,
        } satisfies FloorNodeData,
      },
      {
        id: CONV_ID, type: 'ConversationNode', position: { x: 0, y: 0 },
        data: {
          sessionId: null, policy: '', topic: '', turnCount: 0,
        } satisfies ConversationNodeData,
      },
    ],
    [glowEdge(`e-${FLOOR_ID}-${CONV_ID}`, FLOOR_ID, CONV_ID)]
  )
}

// ── App ───────────────────────────────────────────────────────────────────────

export default function App() {
  const [nodes, setNodes, onNodesChange] = useNodesState(makeInitialNodes())
  const [edges, setEdges, onEdgesChange] = useEdgesState([
    glowEdge(`e-${FLOOR_ID}-${CONV_ID}`, FLOOR_ID, CONV_ID),
  ])
  const [sessionId, setSessionId] = useState<string | null>(null)
  const [connected, setConnectedState] = useState(false)
  const [errorBanner, setErrorBanner] = useState<string | null>(null)
  const [showAddAgent, setShowAddAgent] = useState(false)
  const [modelOpen, setModelOpen] = useState(false)
  const startedAt = useRef<number>(0)
  const elapsedTimer = useRef<ReturnType<typeof setInterval> | null>(null)

  const slugs = useSlugs()
  const models = useModels()

  // ── Restore layout ──────────────────────────────────────────────────────────
  useEffect(() => {
    try {
      const saved = localStorage.getItem(LAYOUT_KEY)
      if (saved) {
        const positions: Record<string, { x: number; y: number }> = JSON.parse(saved)
        setNodes((nds) => nds.map((n) => positions[n.id] ? { ...n, position: positions[n.id] } : n))
      }
    } catch { /* ignore */ }
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    try {
      const positions: Record<string, { x: number; y: number }> = {}
      nodes.forEach((n) => { positions[n.id] = n.position })
      localStorage.setItem(LAYOUT_KEY, JSON.stringify(positions))
    } catch { /* quota exceeded */ }
  }, [nodes])

  // ── Helpers ─────────────────────────────────────────────────────────────────
  const patchNode = useCallback(<T extends object>(id: string, patch: Partial<T>) => {
    setNodes((nds) => nds.map((n) => n.id === id ? { ...n, data: { ...n.data, ...patch } } : n))
  }, [setNodes])

  const isRunning = asFloor(nodes.find((n) => n.id === FLOOR_ID)?.data)?.sessionState === 'running'

  // ── WS event handler ────────────────────────────────────────────────────────
  const handleEvent = useCallback((event: WSEvent) => {
    switch (event.type) {
      case 'utterance': {
        const msg: Message = {
          id: `${Date.now()}-${Math.random()}`,
          sender: event.sender, text: event.text, ts: Date.now(), media: event.media,
        }
        setNodes((nds) => nds.map((n) => {
          if (n.type === 'AgentNode' && asAgent(n.data).name === event.sender) {
            const nd = asAgent(n.data)
            return { ...n, data: { ...nd, messages: [...nd.messages, msg] } }
          }
          if (n.type === 'HumanNode' && (n.data as HumanNodeData).humanName === event.sender) {
            const nd = n.data as HumanNodeData
            return { ...n, data: { ...nd, messages: [...nd.messages, msg] } }
          }
          return n
        }))
        patchNode<ConversationNodeData>(CONV_ID, {
          turnCount: (asConv(nodes.find((n) => n.id === CONV_ID)?.data))?.turnCount + 1 || 1,
        })
        // Image utterance → create ImageArtifactNode
        if (event.media?.type === 'image') {
          const agentNodeId = `agent-${event.sender}`
          const artifactId = `artifact-img-${Date.now()}`
          setNodes((nds) => {
            const artNode: Node = {
              id: artifactId, type: 'ImageArtifactNode',
              position: nextArtifactPosition(nds, agentNodeId),
              data: {
                kind: 'image', agentName: event.sender,
                label: 'image', preview: event.media!.url, url: event.media!.url,
              } satisfies ArtifactNodeData,
            }
            return [...nds, artNode]
          })
          setEdges((eds) => [...eds, glowEdge(
            `e-${agentNodeId}-${artifactId}`,
            agentNodeId, artifactId,
            { color: '#8b5cf6', dashed: true },
          )])
        }
        break
      }

      case 'floor_grant': {
        setNodes((nds) => nds.map((n) => {
          if (n.type !== 'AgentNode') return n
          const nd = asAgent(n.data)
          const state: AgentFloorState = nd.name === event.to ? 'speaking' : 'waiting'
          return { ...n, data: { ...nd, floorState: state } }
        }))
        const targetAgentId = `agent-${event.to}`
        setEdges((eds) => eds.map((e) => ({
          ...e,
          data: {
            ...(e.data as GlowEdgeData),
            active: e.source === FLOOR_ID && e.target === targetAgentId,
          },
        })))
        break
      }

      case 'floor_revoke': {
        setNodes((nds) => nds.map((n) => {
          if (n.type !== 'AgentNode') return n
          const nd = asAgent(n.data)
          if (nd.name === event.from) return { ...n, data: { ...nd, floorState: 'waiting' as AgentFloorState } }
          return n
        }))
        setEdges((eds) => eds.map((e) => ({ ...e, data: { ...(e.data as GlowEdgeData), active: false } })))
        break
      }

      case 'floor_request': {
        setNodes((nds) => nds.map((n) => {
          if (n.type !== 'AgentNode') return n
          const nd = asAgent(n.data)
          if (nd.name === event.from) return { ...n, data: { ...nd, floorState: 'requesting' as AgentFloorState } }
          return n
        }))
        break
      }

      case 'agent_spawning': {
        setNodes((nds) => {
          const exists = nds.find((n) => n.type === 'AgentNode' && asAgent(n.data).name === event.name)
          if (exists) {
            return nds.map((n) =>
              n.id === exists.id ? { ...n, data: { ...n.data, floorState: 'spawning' as AgentFloorState } } : n
            )
          }
          const newId = `agent-${event.name}`
          const newNode: Node = {
            id: newId, type: 'AgentNode',
            position: { x: 400, y: 100 + nds.filter((n) => n.type === 'AgentNode').length * 220 },
            data: {
              provider: event.provider as AgentNodeData['provider'],
              name: event.name, model: '', systemPrompt: '', slug: '',
              agentType: '', floorState: 'spawning', messages: [],
            } satisfies AgentNodeData,
          }
          setEdges((eds) => [...eds, glowEdge(`e-${FLOOR_ID}-${newId}`, FLOOR_ID, newId)])
          return [...nds, newNode]
        })
        break
      }

      case 'agent_joined': {
        setNodes((nds) => nds.map((n) => {
          if (n.type === 'AgentNode' && asAgent(n.data).name === event.name)
            return { ...n, data: { ...n.data, floorState: 'waiting' as AgentFloorState } }
          return n
        }))
        break
      }

      case 'agent_kicked': {
        const kickedId = `agent-${event.name}`
        setNodes((nds) => nds.filter((n) => n.id !== kickedId))
        setEdges((eds) => eds.filter((e) => e.target !== kickedId))
        break
      }

      case 'artifact_saved': {
        const agentNodeId = `agent-${event.agent}`
        const artifactId = `artifact-${event.slug ?? Date.now()}`
        const color = ARTIFACT_COLOR[event.kind] ?? '#58a6ff'
        const nodeType = artifactNodeType(event.kind)
        setNodes((nds) => {
          const artNode: Node = {
            id: artifactId, type: nodeType,
            position: nextArtifactPosition(nds, agentNodeId),
            data: {
              kind: event.kind as ArtifactNodeData['kind'],
              agentName: event.agent,
              slug: event.slug,
              label: event.slug ?? 'artifact',
              preview: event.preview,
            } satisfies ArtifactNodeData,
          }
          return [...nds, artNode]
        })
        setEdges((eds) => [...eds, glowEdge(
          `e-${agentNodeId}-${artifactId}`,
          agentNodeId, artifactId,
          { color, dashed: true },
        )])
        break
      }

      case 'error': {
        setNodes((nds) => nds.map((n) => {
          if (n.type === 'AgentNode' && asAgent(n.data).name === event.agent)
            return { ...n, data: { ...n.data, floorState: 'error' as AgentFloorState, errorMessage: event.message } }
          return n
        }))
        break
      }

      case 'session_ended': {
        patchNode<FloorNodeData>(FLOOR_ID, { sessionState: 'stopped' })
        patchNode<ConversationNodeData>(CONV_ID, { sessionId: null })
        setEdges((eds) => eds.map((e) => ({ ...e, data: { ...(e.data as GlowEdgeData), active: false } })))
        if (elapsedTimer.current) clearInterval(elapsedTimer.current)
        break
      }
    }
  }, [nodes, patchNode, setEdges, setNodes])

  // ── Session control ──────────────────────────────────────────────────────────
  const handleRun = useCallback(async () => {
    setErrorBanner(null)
    const floorNode = nodes.find((n) => n.id === FLOOR_ID)
    if (!floorNode) return
    const fd = asFloor(floorNode.data)
    const graphNodes = nodes.map((n) => ({ id: n.id, type: n.type, data: n.data }))
    const graphEdges = edges.map((e) => ({ source: e.source, target: e.target }))
    try {
      const res = await fetch(`${API}/session/start`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ nodes: graphNodes, edges: graphEdges }),
      })
      if (!res.ok) {
        const detail = await res.json().then((d: { detail?: string }) => d.detail).catch(() => res.statusText)
        setErrorBanner(`Start failed: ${detail}`)
        return
      }
      const { session_id } = await res.json() as { session_id: string }
      setSessionId(session_id)
      startedAt.current = Date.now()
      patchNode<FloorNodeData>(FLOOR_ID, { sessionState: 'running', sessionId: session_id, turnCount: 0, elapsedSecs: 0 })
      patchNode<ConversationNodeData>(CONV_ID, { sessionId: session_id, policy: fd.policy, topic: fd.topic, turnCount: 0 })
      elapsedTimer.current = setInterval(() => {
        patchNode<FloorNodeData>(FLOOR_ID, { elapsedSecs: Math.floor((Date.now() - startedAt.current) / 1000) })
      }, 1000)
    } catch (e) {
      setErrorBanner(`Network error: ${e}`)
    }
  }, [nodes, edges, patchNode])

  const handleStop = useCallback(async () => {
    await fetch(`${API}/session/stop`, { method: 'DELETE' }).catch(() => {})
    patchNode<FloorNodeData>(FLOOR_ID, { sessionState: 'stopped' })
    setEdges((eds) => eds.map((e) => ({ ...e, data: { ...(e.data as GlowEdgeData), active: false } })))
    if (elapsedTimer.current) clearInterval(elapsedTimer.current)
  }, [patchNode, setEdges])

  // ── WS ───────────────────────────────────────────────────────────────────────
  const { connected: wsConnected, sendMessage, kickAgent } = useSession({ sessionId, onEvent: handleEvent })
  useEffect(() => setConnectedState(wsConnected), [wsConnected])

  // ── Add agent ─────────────────────────────────────────────────────────────
  const [newAgent, setNewAgent] = useState({
    provider: 'anthropic', name: '', model: '', systemPrompt: '', slug: '', agentType: '',
  })
  const [modelQuery, setModelQuery] = useState('')
  const providerModels = (models[newAgent.provider] ?? []).filter(m =>
    modelQuery === '' || m.includes(modelQuery)
  )

  const handleAddAgent = useCallback(async () => {
    if (!newAgent.name.trim()) return
    if (isRunning) {
      await fetch(`${API}/session/agent/add`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(newAgent),
      }).catch(() => {})
    } else {
      const newId = `agent-${newAgent.name}`
      const newNode: Node = {
        id: newId, type: 'AgentNode',
        position: { x: 400, y: 100 + nodes.filter((n) => n.type === 'AgentNode').length * 220 },
        data: {
          provider: newAgent.provider as AgentNodeData['provider'],
          name: newAgent.name, model: newAgent.model,
          systemPrompt: newAgent.systemPrompt, slug: newAgent.slug,
          agentType: newAgent.agentType, floorState: 'waiting', messages: [],
        } satisfies AgentNodeData,
      }
      setNodes((nds) => [...nds, newNode])
      setEdges((eds) => [...eds, glowEdge(`e-${FLOOR_ID}-${newId}`, FLOOR_ID, newId)])
    }
    setNewAgent({ provider: 'anthropic', name: '', model: '', systemPrompt: '', slug: '', agentType: '' })
    setModelQuery('')
    setShowAddAgent(false)
  }, [newAgent, isRunning, nodes, setNodes, setEdges])

  // ── Context value ─────────────────────────────────────────────────────────
  const callbacks = useMemo<CanvasCallbacks>(() => ({
    onRun: handleRun,
    onStop: handleStop,
    onFloorChange: (patch) => patchNode<FloorNodeData>(FLOOR_ID, patch),
    onKick: kickAgent,
    onSend: sendMessage,
    sessionRunning: isRunning,
  }), [handleRun, handleStop, patchNode, kickAgent, sendMessage, isRunning])

  const onConnect = useCallback(
    (connection: Connection) => setEdges((eds) => addEdge(
      { ...connection, type: 'glow', data: { active: false, color: '#2a3a4c', dashed: false } },
      eds,
    )),
    [setEdges]
  )

  return (
    <div style={{ width: '100vw', height: '100vh', display: 'flex', background: '#0d1117' }}>
      {/* ── Sidebar ─────────────────────────────────────────────────────────── */}
      <div style={{
        width: 220, background: '#161b22', borderRight: '1px solid #21262d',
        display: 'flex', flexDirection: 'column', padding: '14px 10px',
        gap: 8, flexShrink: 0, overflowY: 'auto',
      }}>
        <div style={{ color: '#58a6ff', fontWeight: 700, fontSize: 14, marginBottom: 6 }}>OFP Canvas</div>

        <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 11, color: '#93a4b8' }}>
          <div style={{ width: 7, height: 7, borderRadius: '50%', background: connected ? '#38a169' : '#e53e3e' }} />
          {connected ? 'Connected' : 'Disconnected'}
        </div>

        <hr style={{ border: 'none', borderTop: '1px solid #21262d' }} />

        <div style={{ color: '#93a4b8', fontSize: 10, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 1 }}>
          Add Agent
        </div>

        <button
          onClick={() => setShowAddAgent(!showAddAgent)}
          style={{
            background: '#1a2a3a', color: '#58a6ff', border: '1px solid #58a6ff44',
            borderRadius: 6, padding: '7px 0', fontSize: 12, cursor: 'pointer', fontWeight: 600,
          }}
        >
          + Agent
        </button>

        {showAddAgent && (
          <div style={{
            background: '#0d1520', border: '1px solid #2a3a4c', borderRadius: 7, padding: 10,
            display: 'flex', flexDirection: 'column', gap: 6, fontSize: 11,
          }}>
            {/* Provider */}
            <select
              value={newAgent.provider}
              onChange={(e) => setNewAgent((a) => ({ ...a, provider: e.target.value }))}
              style={inputStyle}
            >
              <option value="anthropic">Anthropic</option>
              <option value="openai">OpenAI</option>
              <option value="google">Google</option>
              <option value="huggingface">HuggingFace</option>
            </select>

            {/* Type */}
            <select
              value={newAgent.agentType}
              onChange={(e) => setNewAgent((a) => ({ ...a, agentType: e.target.value }))}
              style={inputStyle}
            >
              {TASK_SUBTYPES.map((t) => (
                <option key={t} value={t}>{t === '' ? '(default)' : t}</option>
              ))}
            </select>

            {/* Name */}
            <input
              type="text"
              placeholder="Name (required)"
              value={newAgent.name}
              onChange={(e) => setNewAgent((a) => ({ ...a, name: e.target.value }))}
              style={inputStyle}
            />

            {/* Model with suggestions */}
            <div style={{ position: 'relative' }}>
              <input
                type="text"
                placeholder="Model (optional)"
                value={newAgent.model}
                onChange={(e) => { setNewAgent((a) => ({ ...a, model: e.target.value })); setModelQuery(e.target.value) }}
                onFocus={() => setModelOpen(true)}
                onBlur={() => setTimeout(() => setModelOpen(false), 150)}
                style={inputStyle}
              />
              {modelOpen && providerModels.length > 0 && (
                <div style={{
                  position: 'absolute', top: 'calc(100% + 3px)', left: 0, right: 0,
                  background: '#1a2332', border: '1px solid #2a4060', borderRadius: 6,
                  zIndex: 100, overflow: 'hidden', boxShadow: '0 4px 16px #00000077',
                }}>
                  {providerModels.map((m) => (
                    <div
                      key={m}
                      onMouseDown={() => { setNewAgent((a) => ({ ...a, model: m })); setModelOpen(false) }}
                      style={{ padding: '5px 10px', fontSize: 10, cursor: 'pointer', color: '#93a4b8' }}
                    >
                      {m}
                    </div>
                  ))}
                </div>
              )}
            </div>

            {/* Slug/system prompt with autocomplete */}
            <SlugCombobox
              value={newAgent.systemPrompt || newAgent.slug}
              onChange={(v) => setNewAgent((a) => ({
                ...a,
                systemPrompt: v.startsWith('@') ? '' : v,
                slug: v.startsWith('@') ? v : '',
              }))}
              slugs={slugs}
              style={inputStyle}
            />

            <button
              onClick={handleAddAgent}
              style={{
                background: '#1a4731', color: '#68d391', border: '1px solid #68d39166',
                borderRadius: 5, padding: '5px 0', cursor: 'pointer', fontSize: 11,
              }}
            >
              Add
            </button>
          </div>
        )}

        <hr style={{ border: 'none', borderTop: '1px solid #21262d' }} />

        {errorBanner && (
          <div style={{
            background: '#2d1515', border: '1px solid #e53e3e44',
            borderRadius: 5, padding: '6px 8px', color: '#fc8181', fontSize: 11,
          }}>
            {errorBanner}
            <button
              onClick={() => setErrorBanner(null)}
              style={{ float: 'right', background: 'none', border: 'none', color: '#fc8181', cursor: 'pointer' }}
            >×</button>
          </div>
        )}
      </div>

      {/* ── Canvas ──────────────────────────────────────────────────────────── */}
      <CanvasContext.Provider value={callbacks}>
        <div style={{ flex: 1, position: 'relative' }}>
          <ReactFlow
            nodes={nodes}
            edges={edges}
            onNodesChange={onNodesChange}
            onEdgesChange={onEdgesChange}
            onConnect={onConnect}
            nodeTypes={NODE_TYPES}
            edgeTypes={EDGE_TYPES}
            fitView
            proOptions={{ hideAttribution: true }}
            style={{ background: '#0d1117' }}
          >
            <Background color="#1a2332" variant={BackgroundVariant.Dots} gap={20} size={1} />
            <Controls style={{ background: '#161b22', border: '1px solid #21262d' }} />
            <MiniMap
              style={{ background: '#161b22', border: '1px solid #21262d' }}
              nodeColor="#2a3a4c"
            />
          </ReactFlow>
        </div>
      </CanvasContext.Provider>
    </div>
  )
}

const inputStyle: React.CSSProperties = {
  width: '100%', background: '#0d1520', color: '#e6edf5',
  border: '1px solid #2a3a4c', borderRadius: 5, padding: '4px 7px',
  fontSize: 11, boxSizing: 'border-box', fontFamily: 'inherit',
}
```

- [ ] **Step 3: Type-check**

```bash
cd canvas/frontend && npx tsc --noEmit 2>&1
```

Expected: zero errors. Fix any that appear before continuing.

- [ ] **Step 4: Commit**

```bash
git add canvas/frontend/src/App.tsx
git rm canvas/frontend/src/cards/ArtifactCard.tsx \
        canvas/frontend/src/cards/ImageCard.tsx \
        canvas/frontend/src/cards/MemoryCard.tsx
git commit -m "feat(canvas): wire context, GlowEdge, artifact nodes, agent type field; remove floating cards"
```

---

## Task 11: Build and manual verification

**Files:**
- Build output: `canvas/frontend/dist/`

- [ ] **Step 1: Full TypeScript check**

```bash
cd canvas/frontend && npx tsc --noEmit
```

Expected: zero errors

- [ ] **Step 2: Build the frontend**

```bash
cd canvas/frontend && npm run build
```

Expected: `dist/` updated with no build errors

- [ ] **Step 3: Run all backend tests**

```bash
cd /Users/bolyos/Development/ofpPlaygorund && pytest tests/ -v --tb=short
```

Expected: all pass

- [ ] **Step 4: Start canvas and verify focus fix**

```bash
pip install -e ".[canvas]"
ofp-playground canvas
```

Open http://localhost:8765. Click the FloorNode `Topic` field and type quickly. **Focus must not jump between keystrokes.** Also type in the Model field — same test.

- [ ] **Step 5: Verify slug autocomplete**

In the `+ Agent` sidebar panel, click the system-prompt field and type `@dev`. A list of up to 5 `development/...` slugs should appear. Press `↓` to navigate, `Enter` to accept. Type `@` alone — no list (query empty). Type without `@` — no list.

- [ ] **Step 6: Verify model suggestions**

Select `Anthropic` provider, click the Model field. Three Claude model names appear. Click one — it fills the field.

- [ ] **Step 7: Verify agent type field**

Select `showrunner` from the Type dropdown. Add the agent. The `AgentNode` on canvas should show a `SHOWRUNNER` badge below the provider badge.

- [ ] **Step 8: Verify glow edge**

Run a SEQUENTIAL session with two agents. Watch the Floor→Agent edge — it should animate with a glow when that agent is speaking, go static when it yields.

- [ ] **Step 9: Commit build artifacts**

```bash
git add canvas/frontend/dist/
git commit -m "build(canvas): rebuild frontend with all UI enhancements"
```

---

## Self-Review Checklist

- **Spec §1 Focus fix** → Task 4 (CanvasContext) + Task 5 (node updates) + Task 10 (NODE_TYPES constant + Provider wrap) ✓
- **Spec §2 Slug autocomplete** → Task 1 (`/agents/list`), Task 8 (`useSlugs` + `SlugCombobox`), Task 10 (wired in sidebar) ✓
- **Spec §3 Model autocomplete** → Task 1 (`/models/list`), Task 9 (`useModels`), Task 10 (inline model field) ✓
- **Spec §4 Agent type field** → Task 1 (backend `agentType`), Task 3 (`agentType` in types), Task 5 (badge in AgentNode), Task 10 (form field) ✓
- **Spec §5 Artifact nodes** → Task 2 (FloorManager hook), Task 3 (`ArtifactNodeData`), Task 7 (4 node components), Task 10 (event wiring + image utterance detection) ✓
- **Spec §6 GlowEdge** → Task 6 (component), Task 10 (`floor_grant`/`floor_revoke` handlers, `EDGE_TYPES`, all edges use `type: 'glow'`) ✓
- **Floating cards deleted** → Task 10 Step 1 ✓
- **`LAYOUT_KEY` bumped** → Task 10 (`v3`) ✓
- **`AddAgentRequest` gets `agentType`** → Task 1 ✓
