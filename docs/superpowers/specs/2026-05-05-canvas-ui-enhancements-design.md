# Canvas UI Enhancements — Design Spec

**Date:** 2026-05-05  
**Status:** Approved  
**Scope:** `canvas/frontend/` and `canvas/backend/` only — no changes to core OFP runtime outside the FloorManager artifact callback hook.

---

## Overview

Six improvements to the visual canvas floor builder:

1. **Fix input focus stealing** — stable `nodeTypes` via React context
2. **Slug autocomplete** — small suggestion list after `@` prefix
3. **Model autocomplete** — provider-filtered suggestion list on focus
4. **Agent Type field** — subtype dropdown mapped to CLI `TASK_SUBTYPES`
5. **Artifact nodes** — IMAGE / CODE / PHASE / MUSIC nodes in the graph, chained Floor → Agent → Artifact
6. **Talking edge glow** — animated glow on the Floor→Agent edge of the speaking agent

---

## 1. Fix: Input Focus Stealing

### Problem

`nodeTypes` is redefined on every render of `App` because it contains closures over `handleRun`, `handleStop`, `patchNode`, `sendMessage`, `kickAgent`. ReactFlow detects a changed component reference and unmounts/remounts the node, destroying DOM focus on every keystroke.

### Solution

**New file: `canvas/frontend/src/context/CanvasContext.tsx`**

```ts
interface CanvasCallbacks {
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

**`App.tsx` changes:**
- Remove `nodeTypes` from inside `App`. Define it at module level as a plain constant:
  ```ts
  const NODE_TYPES: NodeTypes = {
    FloorNode, AgentNode, HumanNode, ConversationNode,
    ImageArtifactNode, CodeArtifactNode, PhaseArtifactNode, MusicArtifactNode,
  }
  ```
- Wrap `<ReactFlow>` in `<CanvasContext.Provider value={callbacks}>`.
- `callbacks` object is memoized with `useMemo` over its stable `useCallback` dependencies. This prevents context consumers from re-rendering unless an actual callback identity changes.
- **Important:** Context value changes do NOT cause node remounts — they cause re-renders of consumers only. The key fix is that `NODE_TYPES` is now a stable module-level reference, so ReactFlow never sees a new component map.

**Node components** (`FloorNode`, `AgentNode`, `HumanNode`): replace props for callbacks with `useCanvas()` call. All other props remain ReactFlow-standard.

---

## 2. Slug Autocomplete

### Backend

**New endpoint in `canvas/backend/main.py`:**

```
GET /agents/list
→ [{ slug: str, display_name: str, category: str }]
```

Calls `library.load()` (already cached per process). Returns all 224+ entries sorted by slug.

### Frontend

**New file: `canvas/frontend/src/hooks/useSlugs.ts`**  
Fetches `/agents/list` once on mount, returns `SlugEntry[]`.

**New file: `canvas/frontend/src/components/SlugCombobox.tsx`**  
Reusable combobox for the system-prompt / slug field:
- Renders a normal `<input>`.
- While value starts with `@`, filters `slugs` by the text after `@` (case-insensitive substring match on slug + display_name), shows top 5 as a floating list below the input.
- Keyboard: `↑` / `↓` to navigate, `Enter` or `Tab` to accept (replaces input value with full slug), `Escape` to dismiss.
- When value does not start with `@`, behaves as a plain text input (free-form system prompt).
- List disappears on blur (with 150 ms delay to allow click).

**Usage:** Replace the current plain `<input>` for `@slug or system prompt` in the Add Agent sidebar panel with `<SlugCombobox>`. Same `value`/`onChange` API.

---

## 3. Model Autocomplete

### Backend

**New endpoint in `canvas/backend/main.py`:**

```
GET /models/list
→ { anthropic: string[], openai: string[], google: string[], huggingface: string[] }
```

Built from `MODEL_CATALOG` keys, grouped by provider prefix. HuggingFace list is empty (no catalog entries).

### Frontend

**New file: `canvas/frontend/src/hooks/useModels.ts`**  
Fetches `/models/list` once on mount, returns `Record<string, string[]>`.

**Model field behavior:**
- On focus, show a suggestion list filtered to the currently selected provider (up to 3 items from catalog, filtered further if text is non-empty).
- Same keyboard navigation as `SlugCombobox`.
- Accepts free-form input (user can type any model string).
- Implemented inline in the Add Agent form (not a separate component — model field is simpler than slug field).

---

## 4. Agent Type Field

### Frontend-only changes

**`types.ts`:** Add `agentType: string` to `AgentNodeData` (default `''` = standard text-generation).

**Add Agent sidebar panel:** Add a `<select>` between Provider and Name with options from `TASK_SUBTYPES`:

```
(default)         — blank, maps to text-generation
showrunner
orchestrator
code-generation
text-to-image
text-to-video
text-to-music
image-to-text
image-text-to-text
text-classification
summarization
(+ remaining subtypes)
```

**Pydantic models (`canvas/backend/main.py`):** Add `agentType: str = ""` field to both `NodeData` and `AddAgentRequest`.

**`_spawn_agent_for_canvas`:** When `agentType` is non-empty, pass `agent_type=f"{provider}:{agentType}"` to `_spawn_llm_agent` instead of just `provider`. When empty, pass just `provider` (defaults to `text-generation` internally). This maps directly to the CLI colon format already handled by `_spawn_llm_agent`'s `.split(":", 1)` logic.

**`AgentNode` display:** Show the type badge if `agentType` is set (e.g. `SHOWRUNNER` in amber, `CODE-GEN` in cyan) below the provider badge.

---

## 5. Artifact Nodes

### Node types

Four new ReactFlow node types, all with a single `target` Handle on the left:

| Type | File | Border color | WS event trigger |
|------|------|-------------|-----------------|
| `ImageArtifactNode` | `nodes/ImageArtifactNode.tsx` | `#8b5cf6` (purple) | `image_saved` |
| `CodeArtifactNode` | `nodes/CodeArtifactNode.tsx` | `#10a37f` (green) | `artifact_saved` where kind ∈ {`code`, `file`} |
| `PhaseArtifactNode` | `nodes/PhaseArtifactNode.tsx` | `#58a6ff` (blue) | `artifact_saved` where kind ∈ {`markdown`, `phase`} |
| `MusicArtifactNode` | `nodes/MusicArtifactNode.tsx` | `#f97316` (orange) | `artifact_saved` where kind = `music` |

**`ArtifactNodeData` (added to `types.ts`):**
```ts
interface ArtifactNodeData {
  kind: 'image' | 'code' | 'phase' | 'music'
  agentName: string
  slug?: string
  label: string       // filename or slug display
  preview: string     // first ~120 chars of content, or URL for image
  url?: string        // direct URL for image / audio playback
}
```

**Node anatomy (all four types share the same structure):**
- Colored border matching type.
- Type badge (`IMAGE`, `CODE`, `PHASE`, `MUSIC`) + label (filename / slug).
- Content preview area (thumbnail for images, monospace snippet for code, prose excerpt for phase, waveform placeholder for music).
- Clicking expands to show full content or opens image in a native `<dialog>` lightbox.

**Edges to artifact nodes:** Use `type: 'glow'` with `data: { active: false, color: <artColor> }`. The GlowEdge component renders inactive edges as dashed lines using `data.color`. Do not pass a bare `style` — let GlowEdge handle styling consistently.

### App.tsx event handling

Replace the `artifact_saved` / `image_saved` / `memory_saved` cases in `handleEvent` — instead of pushing to the `cards` state, create a new ReactFlow node + edge:

```ts
function nodeTypeFor(event: WSEvent): string {
  if (event.type === 'image_saved') return 'ImageArtifactNode'
  if (event.type === 'memory_saved') return 'PhaseArtifactNode'  // memory as phase node
  const kind = (event as any).kind ?? 'phase'
  if (kind === 'code' || kind === 'file') return 'CodeArtifactNode'
  if (kind === 'music') return 'MusicArtifactNode'
  return 'PhaseArtifactNode'
}

function colorFor(event: WSEvent): string {
  if (event.type === 'image_saved') return '#8b5cf6'
  const kind = (event as any).kind ?? 'phase'
  if (kind === 'code' || kind === 'file') return '#10a37f'
  if (kind === 'music') return '#f97316'
  return '#58a6ff'
}

const artifactId = `artifact-${event.slug ?? Date.now()}`
const agentNodeId = `agent-${event.agent}`
const newNode: Node = {
  id: artifactId,
  type: nodeTypeFor(event),
  position: nextArtifactPosition(nodes, agentNodeId),
  data: { /* ArtifactNodeData from event */ },
}
const newEdge: Edge = {
  id: `e-${agentNodeId}-${artifactId}`,
  source: agentNodeId,
  target: artifactId,
  type: 'glow',
  data: { active: false, color: colorFor(event) },
}
setNodes(nds => [...nds, newNode])
setEdges(eds => [...eds, newEdge])
```

`nextArtifactPosition`: places artifact to the right of the producing agent node, staggered vertically by count of existing artifacts for that agent (x + 260, y + index * 130).

**Remove:** `cards` state, `ArtifactCard`, `ImageCard`, `MemoryCard` floating overlay renders. The three card components can be deleted.

**`memory_saved` events:** Rendered as `PhaseArtifactNode` with `kind: 'phase'` and `label` set to the memory category. This reuses the existing node type rather than adding a fifth artifact variant.

### Backend: artifact event hook

**`src/ofp_playground/floor/manager.py`:**  
Add optional attribute `_on_artifact_saved: Callable[[dict], None] | None = None`.

`ArtifactStore.save()` returns a `PhaseArtifact` object — the callback must capture this return value to access `.slug`:

Call it after each `self._artifact_store.save(...)` using the kind appropriate to the call site:

1. **`[ACCEPT]` directive handler** (accepted worker output): kind = `"phase"`
2. **`_save_character_memory_blocks`**: kind = `"phase"`  
3. **Breakout transcript save**: kind = `"phase"`

```python
artifact = self._artifact_store.save(
    agent_name=agent_name,
    content=content,
    slug=slug,
)
if self._on_artifact_saved:
    self._on_artifact_saved({
        "type": "artifact_saved",
        "slug": artifact.slug,
        "agent": agent_name,
        "kind": "phase",                # or whichever kind applies at this site
        "preview": content[:120],
    })
```

4. **After saving media** (image/video/audio output path):
   ```python
   if self._on_artifact_saved:
       self._on_artifact_saved({"type": "image_saved", "agent": agent_name, "url": f"/media/{rel_path}"})
   ```
   Use `"type": "image_saved"` for images; extend similarly for video/audio with their own event types if needed.

**`canvas/backend/main.py` — `_run_canvas_session`:**  
After `floor` is constructed:
```python
floor._on_artifact_saved = bridge.push_raw
```

**`canvas/backend/session_bridge.py`:** No changes needed — `push_raw` already handles arbitrary dicts.

---

## 6. Talking Edge Glow (GlowEdge)

### Types (added to `types.ts`)

```ts
interface GlowEdgeData {
  active: boolean
  color: string  // CSS color for the glow/stroke
}
```

### New file: `canvas/frontend/src/edges/GlowEdge.tsx`

Custom ReactFlow edge component. Renders the standard bezier path plus — when `data.active` is true — an animated overlay path with:
- `stroke-dasharray: 10 8`
- `@keyframes dashTravel { from { stroke-dashoffset: 300 } to { stroke-dashoffset: 0 } }`
- `animation: dashTravel 1.0s linear infinite`
- `filter: drop-shadow(0 0 5px <color>)`

Color is the target agent's provider color (amber for Anthropic, etc.) when active.

**Register edge type:** Add `edgeTypes` constant at module level (alongside `NODE_TYPES`):
```ts
const EDGE_TYPES = { glow: GlowEdge }
```
Pass to `<ReactFlow edgeTypes={EDGE_TYPES}>`.

**Default edge creation:** All edges created by App use `type: 'glow'` with `data: { active: false, color: '#2a3a4c' }`. Set provider color at creation time when the provider is known.

**Edge creation updates:** Existing edge creation code (in `agent_spawning` handler and `handleAddAgent`) must be updated to include `type` and `data`:
```ts
const newEdge: Edge = {
  id: `e-${FLOOR_ID}-${newId}`,
  source: FLOOR_ID,
  target: newId,
  type: 'glow',
  data: { active: false, color: providerColor(provider) },
}
```

Where `providerColor` maps providers to brand colors:
```ts
function providerColor(provider: string): string {
  switch (provider) {
    case 'anthropic': return '#d97706'  // amber
    case 'openai': return '#10a37f'     // green
    case 'google': return '#4285f4'     // blue
    default: return '#6b7280'           // gray
  }
}
```

**`floor_grant` handler in `handleEvent`:** 
```ts
setEdges(eds => eds.map(e => {
  const targetAgentId = `agent-${event.to}`
  const isActive = e.source === FLOOR_ID && e.target === targetAgentId
  return { ...e, data: { ...e.data, active: isActive } }
}))
```

**`floor_revoke` handler:** Set all edges `data.active = false`.

Artifact edges (Agent→Artifact) also use `type: 'glow'` but `active` is never set to true for them — they just render as static dashed lines.

**Floor→Conversation edge:** The initial edge `e-floor-main-conv-main` also uses `type: 'glow'` with `data: { active: false, color: '#2a3a4c' }`. The `floor_grant` handler's condition (`e.source === FLOOR_ID && e.target === targetAgentId`) naturally excludes it since its target is `conv-main`, not an agent.

---

## Files Changed

### New frontend files
- `canvas/frontend/src/context/CanvasContext.tsx`
- `canvas/frontend/src/hooks/useSlugs.ts`
- `canvas/frontend/src/hooks/useModels.ts`
- `canvas/frontend/src/components/SlugCombobox.tsx`
- `canvas/frontend/src/nodes/ImageArtifactNode.tsx`
- `canvas/frontend/src/nodes/CodeArtifactNode.tsx`
- `canvas/frontend/src/nodes/PhaseArtifactNode.tsx`
- `canvas/frontend/src/nodes/MusicArtifactNode.tsx`
- `canvas/frontend/src/edges/GlowEdge.tsx`

### Modified frontend files
- `canvas/frontend/src/App.tsx` — context provider, stable NODE_TYPES, artifact node events, remove floating cards
- `canvas/frontend/src/types.ts` — add `ArtifactNodeData`, `GlowEdgeData`, `agentType` field
- `canvas/frontend/src/nodes/FloorNode.tsx` — use `useCanvas()` instead of props
- `canvas/frontend/src/nodes/AgentNode.tsx` — use `useCanvas()`, add type badge
- `canvas/frontend/src/nodes/HumanNode.tsx` — use `useCanvas()`

### Deleted frontend files
- `canvas/frontend/src/cards/ArtifactCard.tsx`
- `canvas/frontend/src/cards/ImageCard.tsx`
- `canvas/frontend/src/cards/MemoryCard.tsx`

### New backend files
_(none)_

### Modified backend files
- `canvas/backend/main.py` — add `/agents/list`, `/models/list` endpoints; add `agentType` to `NodeData` and `AddAgentRequest`; wire `floor._on_artifact_saved`
- `src/ofp_playground/floor/manager.py` — add `_on_artifact_saved` callback attribute and call sites

---

## Migration & Backwards Compatibility

- **localStorage**: Bump the layout key from `ofp-canvas-layout-v2` to `ofp-canvas-layout-v3`. Old saved layouts won't have `type: 'glow'` on edges or `agentType` on nodes — the app should gracefully handle missing fields (edges without `type`/`data` render as default ReactFlow edges until re-created).
- **Backend API**: New fields (`agentType`) default to empty string, so existing frontend builds that omit them still work via Pydantic defaults.
- **WebSocket events**: `artifact_saved` and `image_saved` events currently originate from `session_bridge._serialize_envelope()`. The new `_on_artifact_saved` callback is an additional source — ensure no duplicate events by checking that `_serialize_envelope` does NOT also emit `artifact_saved` for the same payload.

---

## Testing

- **Focus fix**: type rapidly in the Topic field — focus must not jump. Also test the Model and system-prompt fields.
- **Slug autocomplete**: type `@dev` → list shows `development/...` slugs. Tab accepts. Esc dismisses. Typing without `@` shows no list.
- **Model autocomplete**: select Anthropic provider → focus model field → three Claude model suggestions appear.
- **Type field**: select `showrunner` → run session → backend receives `provider:showrunner` spec.
- **Artifact nodes**: run an illustrated story pipeline → image nodes appear in graph connected to the producing agent.
- **Glow edge**: watch floor_grant events → the edge to the speaking agent glows and animates; it stops when that agent yields.
- **No regression**: existing session start/stop, agent add/kick, human message flows unchanged.
- **Edge glow deactivation**: stop a session mid-conversation → all glow edges should deactivate (no stuck active state).
- **Multiple artifacts same agent**: spawn an image agent that produces 3 images → all three artifact nodes positioned without overlap, all connected to the same agent node.
- **localStorage upgrade**: clear localStorage, start a session, verify new layout key is saved. Then reload — layout should restore correctly with glow edge types.
