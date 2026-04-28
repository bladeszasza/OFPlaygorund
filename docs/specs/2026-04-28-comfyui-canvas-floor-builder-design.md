# Canvas Floor Builder — Design Spec
*Date: 2026-04-28*

## Overview

A ComfyUI-inspired visual node canvas for building and running OFP multi-agent floors. It is a completely separate surface from the existing Gradio web UI and CLI — a new `ofp-playground canvas` command launches it. The canvas reuses the existing Python runtime (FloorManager, MessageBus, all agent classes) without duplication; new code is limited to a thin FastAPI bridge and the React frontend.

## Goals

- Visually compose a floor by dragging agent nodes onto a canvas and wiring them to a central Floor node
- Start the session from the canvas and watch it come alive in real time (conversation bubbles, floor-state animations, artifact cards)
- Add or kick agents mid-session
- See a live version of the existing D3 trace timeline embedded in a ConversationNode (and poppable into its own tab)
- Artifact/image/memory outputs surface as floating cards anchored near their source agent

## Non-Goals

- Replacing the CLI or Gradio web UI
- Persisting canvas layouts to disk (out of scope for v1)
- Mobile / responsive support

---

## Architecture

```
CLI          →  _run_session()  →  FloorManager + MessageBus
Gradio web   →  _run_session()  →  FloorManager + MessageBus
Canvas       →  FastAPI bridge  →  _run_session()  →  FloorManager + MessageBus
                     ↕ WebSocket
                  React canvas (React Flow)
```

The `session_bridge.py` module installs itself as the `MessageBus` collector via the existing `set_collector()` hook (same mechanism used by `EventCollector` today). It serialises every routed envelope to a JSON WebSocket event and broadcasts to connected clients. For the live trace, it additionally calls through to the real `EventCollector` so `trace.html` live-mode gets the same events.

### Project Layout

```
canvas/
├── backend/
│   ├── main.py              ← FastAPI: /api, /ws, /media, static file serving
│   ├── session_bridge.py    ← MessageBus event tap → WebSocket broadcast
│   └── requirements.txt     ← fastapi, uvicorn, websockets
└── frontend/
    ├── src/
    │   ├── nodes/
    │   │   ├── FloorNode.tsx
    │   │   ├── AgentNode.tsx
    │   │   ├── HumanNode.tsx
    │   │   └── ConversationNode.tsx
    │   ├── cards/
    │   │   ├── ArtifactCard.tsx
    │   │   ├── ImageCard.tsx
    │   │   └── MemoryCard.tsx
    │   ├── hooks/
    │   │   └── useSession.ts    ← WebSocket state + event dispatch
    │   └── App.tsx              ← React Flow canvas + sidebar palette
    ├── package.json
    └── vite.config.ts
```

The compiled frontend (`canvas/frontend/dist/`) is committed to the repo so no npm step is required at runtime.

---

## CLI Command

```bash
ofp-playground canvas [--port 8765] [--host localhost] [--open]
```

Starts uvicorn serving both the API and the compiled React app. `--open` (default true) opens the browser automatically. Runtime dependencies: `fastapi`, `uvicorn` — no new Python deps beyond what FastAPI brings.

---

## Node Types

### FloorNode (one per canvas)
- **Builder:** policy dropdown (SEQUENTIAL / ROUND_ROBIN / MODERATED / FREE_FOR_ALL / SHOWRUNNER_DRIVEN), topic input, max-turns spinner, show-floor-events toggle, Run / Stop button
- **Runtime:** turn counter, elapsed time, session status badge

### AgentNode (one per agent)
- **Builder:** provider badge (colour-coded), agent name, model selector, system prompt field (collapsed/expandable), `@slug` picker for the agent library
- **Runtime:**
  - Edge to FloorNode pulses while speaking, glows amber while holding the floor, dims while idle
  - Scrollable conversation bubble list (last 5 messages, expandable)
  - Floor-state chip: `speaking` / `waiting` / `requesting`
  - Kick button appears on hover
- **Artifacts:** ImageCards, ArtifactCards, and MemoryCards spawn as small draggable cards anchored near the node

### HumanNode (optional, one per session)
- Text input + Send button during run
- Sent messages render as chat bubbles

### ConversationNode (one per canvas)
- **At rest:** session metadata (policy, topic, turn count)
- **Runtime:** iframe embedding live-mode `trace.html?live=<session_id>` — same D3 swimlane timeline, updating in real time
- Full-screen button pops it into a new browser tab

---

## Artifact Cards

Three card types, all draggable and pinnable on the canvas:

| Card | Content | Trigger |
|------|---------|---------|
| `ImageCard` | Thumbnail → click for full-screen | `image_saved` WS event |
| `ArtifactCard` | Collapsed Markdown preview → click to expand | `artifact_saved` WS event |
| `MemoryCard` | Tag + value pill | `memory_saved` WS event |

Cards spawn near the agent that produced them and are connected with a faint dashed line.

---

## WebSocket Protocol

Single connection per session at `ws://host:port/ws/<session_id>`. Server sends JSON events:

```json
{ "type": "utterance",    "sender": "Alice", "sender_uri": "...", "text": "...", "media": null }
{ "type": "floor_grant",  "to": "Alice" }
{ "type": "floor_revoke", "from": "Alice" }
{ "type": "floor_request","from": "Bob" }
{ "type": "artifact_saved","slug": "phase-1", "kind": "markdown", "agent": "Alice", "preview": "..." }
{ "type": "image_saved",  "agent": "Alice", "url": "/media/images/x.png" }
{ "type": "memory_saved", "category": "decisions", "content": "...", "agent": "Alice" }  ← agent may be null (FloorManager-issued [REMEMBER])
{ "type": "agent_joined", "name": "Carol", "uri": "..." }
{ "type": "agent_kicked", "name": "Bob" }
{ "type": "session_ended" }
```

The server keeps a ring buffer of the last 200 events. On WebSocket reconnect, missed events are replayed so the canvas stays consistent after a brief disconnect.

---

## REST API

```
POST   /session/start              ← body: graph JSON (nodes + edges config)
DELETE /session/stop
POST   /session/agent/add          ← body: agent spec
DELETE /session/agent/<name>       ← kick
POST   /session/message            ← human utterance
GET    /media/<path>               ← serve result/ files
GET    /trace/live?session=<id>    ← serves trace.html in live mode
```

---

## Live Trace

`trace.html` gains a `?live=<session_id>` query parameter. When present:
1. It does not render from the embedded static JSON blob
2. Instead it opens a WebSocket to the backend and appends `TraceEvent` objects to the D3 timeline as they arrive

At session end the finalised static `trace.html` is still written to `result/<session>/trace.html` exactly as today — no regression to existing behaviour.

The change to `trace.html` / `renderer.py` is approximately 30 lines: a conditional WebSocket bootstrap at the top of the generated script.

---

## Runtime Interactions

| Action | How | Backend |
|--------|-----|---------|
| Add agent mid-session | `+ Agent` sidebar button → config panel | `POST /session/agent/add` → FloorManager `/spawn` |
| Kick agent | Hover node → Kick button | `DELETE /session/agent/<name>` → FloorManager kick |
| Send human message | HumanNode input + Send | `POST /session/message` |
| Open trace fullscreen | ConversationNode button | Opens `trace.html?live=<id>` in new tab |
| Drag artifact card | Direct drag on canvas | Client-side only |

---

## Error Handling

- WebSocket disconnect mid-session: canvas shows reconnecting banner; on reconnect replays buffered events
- Agent API error (429, 5xx): red error badge on the AgentNode; hover for message
- Session start failure (bad config): inline error on FloorNode Run button

---

## Testing Approach

- Backend unit tests: `session_bridge.py` event serialisation, REST endpoint contracts
- Frontend: React Testing Library for node rendering, Playwright for canvas interaction (wire nodes, click Run, assert WS events render)
- Integration: start a canvas session with two AnthropicAgents in SEQUENTIAL policy, assert conversation bubbles appear on both nodes and an artifact card spawns if a phase is accepted

---

## Dependencies

**Backend (new):** `fastapi`, `uvicorn[standard]`
**Frontend:** React 18, React Flow, Vite, TypeScript — devDependencies only; the compiled `dist/` is committed so end-users need no Node.js.
