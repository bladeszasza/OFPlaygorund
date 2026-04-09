# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Install for development
pip install -e ".[dev]"

# Run all tests
pytest

# Run a single test file
pytest tests/test_message_bus.py -v

# Run a specific test
pytest -k "test_name"

# Lint (ruff)
ruff check src/

# Type check
mypy src/
# Note: mypy 1.x does not yet support Python 3.14 — the cli.py syntax error is pre-existing noise

# Run the CLI
ofp-playground start --help
ofp-playground agents        # List available agent slugs from agents/ library
ofp-playground validate      # Validate configuration
```

## Architecture

The system implements multi-agent conversations over the [Open Floor Protocol (OFP)](https://github.com/open-voice-interoperability/openfloor-python). All messaging is async and in-process via `asyncio.Queue`.

### Message Flow

```
Human/LLM Agents → MessageBus → target agent queues
                              → FloorManager queue (always receives a copy)
```

- **[MessageBus](src/ofp_playground/bus/message_bus.py)** routes OFP `Envelope` objects. If an event has no `to` field it broadcasts to all registered agents. The floor manager always receives a copy of every message.
- **[FloorManager](src/ofp_playground/floor/manager.py)** is the central coordinator. It holds conversation history, manages which agent holds the floor, and drives turn-taking via `FloorController`. It processes all OFP event types: utterances, floor requests/yields, manifest publications, and invite/bye/decline.
- **[FloorController](src/ofp_playground/floor/policy.py)** implements the 5 floor policies: `SEQUENTIAL`, `ROUND_ROBIN`, `MODERATED`, `FREE_FOR_ALL`, `SHOWRUNNER_DRIVEN`.

### Agent Hierarchy

```
BasePlaygroundAgent
├── HumanAgent          — reads stdin, writes stdout
├── WebHumanAgent       — Gradio web UI counterpart
├── RemoteOFPAgent      — proxies to a remote HTTP OFP endpoint
└── BaseLLMAgent
    ├── AnthropicAgent / AnthropicVisionAgent
    ├── OpenAIAgent / OpenAIImageAgent
    ├── GoogleAgent / GoogleImageAgent / GoogleMusicAgent / GoogleVideoAgent
    ├── HuggingFaceTextAgent / HFImageAgent / HFVideoAgent
    ├── DirectorAgent    — narrative director (ROUND_ROBIN); grants turn per agent each round
    ├── PerceptionBase subclasses (classifier, detector, ocr, ner, multimodal)
    ├── ShowrunnerAgent  — orchestrator that drives SHOWRUNNER_DRIVEN policy
    └── BaseCodingAgent(ABC)  — code generation base; task defaults _timeout=300s, _max_retries=2
        ├── OpenAICodingAgent   — Responses API + code_interpreter (default: gpt-5.4-long-context)
        ├── AnthropicCodingAgent — code_execution_20250825 beta (default: claude-opus-4-6)
        └── GoogleCodingAgent   — ToolCodeExecution (default: gemini-3-flash-preview)
```

All agents extend [`BasePlaygroundAgent`](src/ofp_playground/agents/base.py) which provides:
- `send_envelope()` / `send_private_utterance()` helpers
- `request_floor()` / `yield_floor()` with anti-duplicate logic
- `_call_with_retry()` — timeout + exponential backoff (handles 429s, 5xx, timeouts; non-retryable errors are raised immediately)
- `_build_manifest()` / `_publish_manifest()` for OFP capability advertisement

`BaseLLMAgent._build_manifest()` uses [`model_catalog.py`](src/ofp_playground/agents/llm/model_catalog.py) (`ModelCaps` frozen dataclass) to publish rich OFP manifests (modalities + features + tools keyphrases) for 9 known models (3 OpenAI, 3 Anthropic, 3 Google). Unknown models fall back to a minimal text-in/text-out manifest.

### Coding Agents

CLI subtype `code-generation` routes to provider-specific subclasses:

| CLI | Class | Native tool |
|-----|-------|-------------|
| `openai:code-generation` | `OpenAICodingAgent` | `code_interpreter` via Responses API |
| `anthropic:code-generation` | `AnthropicCodingAgent` | `code_execution_20250825` beta |
| `google:code-generation` | `GoogleCodingAgent` | `ToolCodeExecution` |
| `hf:code-generation` | — | Unsupported (prints message) |

`BaseCodingAgent` is in `codex.py`. The Anthropic and Google subclasses are in `anthropic_coding.py` and `google_coding.py`. `CodingAgent = OpenAICodingAgent` is a backward-compat alias in `codex.py`.

Progress is sent as private utterances to the floor manager during the loop. Final result + `yieldFloor` are bundled in one envelope. Output files are saved to `result/<session>/code/`.

### Showrunner / Orchestrator Pattern

When `SHOWRUNNER_DRIVEN` policy is active, one agent acts as orchestrator. It receives the floor, emits structured directives in its utterance text:

| Directive | Action |
|-----------|--------|
| `[ASSIGN AgentName]: task` | Grant floor to that agent with a task |
| `[ACCEPT]` | Accept the last worker's output |
| `[REJECT AgentName]: reason` | Ask agent to redo |
| `[KICK AgentName]` | Remove agent from session |
| `[SPAWN spec]` | Dynamically create a new agent |
| `[TASK_COMPLETE]` | End the session |

The FloorManager parses these directives in `_handle_orchestrator_directives()` and accumulates accepted outputs into a shared manuscript.

**Media auto-accept**: When a media agent (image/video/audio/3d) produces output in `showrunner_driven` mode, the FloorManager auto-accepts it (appends to manuscript, returns floor to orchestrator) without waiting for `[ACCEPT]`. The orchestrator receives `[auto-accepted {type} output]: {text}` in its context so it doesn't re-issue the same `[ASSIGN]`.

**Remote agent cascade prevention**: `RemoteOFPAgent._should_respond()` blocks responses to other remote agents (`remote-` in sender URI) to prevent exponential cascade loops. It also filters floor manager messages to only react to `[DIRECTIVE for <name>]` directives.

### Agent Library (@slug syntax)

`agents/` at the repo root is a library of 200+ agent personas across 24 domains. Each is a `SOUL.md` file — a structured system prompt — addressable by `@category/agent-name` slug.

```bash
# Use a persona as the system prompt
-provider anthropic -name Alice -system @development/code-reviewer
anthropic:Alice:@creative/brand-designer     # colon format also works

ofp-playground agents     # list all available slugs
```

Loaded via [`src/ofp_playground/agents/library.py`](src/ofp_playground/agents/library.py), cached per process. Full documentation, category breakdown, and how to add new personas: [`docs/agents-library.md`](docs/agents-library.md).

**`@development/coding-agent`** is auto-loaded by `BaseCodingAgent` when no synopsis is provided. Other key coding personas: `@development/code-reviewer`, `@development/bug-hunter`, `@development/tdd-expert`, `@development/technical-planner`, `@development/tech-lead`, `@development/test-writer`, `@development/qa-tester`, `@development/pr-merger`.

### Breakout Sessions

An orchestrator can spin up an isolated sub-floor conversation via the `create_breakout_session` tool. Key details:

- Each breakout gets its own `MessageBus` and `BreakoutFloorManager` (URI: `tag:ofp-playground.local,2025:breakout-floor-manager`).
- Ends when `max_rounds` utterances are exchanged or any agent emits `[BREAKOUT_COMPLETE]`.
- Results are saved under `result/<session>/breakout/` as structured Markdown and a compact notification is returned to the parent orchestrator.
- Hard timeout: 300 seconds. Only one nesting level is permitted.

### In-Session Memory Store

`memory/store.py` provides an ephemeral `MemoryStore` scoped to one conversation. It is not persisted to disk. Categories (priority order for summaries): `goals`, `tasks`, `breakouts`, `decisions`, `lessons`, `agent_profiles`, `preferences`. The store is injected into LLM system prompts each turn via `get_summary()`.

### Web UI (Gradio)

Pass `--web` to `ofp-playground start` to launch the Gradio interface instead of the terminal renderer. The `WebHumanAgent` replaces `HumanAgent`; it accepts user input from the browser and streams agent utterances back as chat bubbles. Media (images/video/audio) renders inline.

### Configuration & API Keys

API keys are resolved from `.env` (project root) or `~/.ofp-playground/config.toml`. Relevant vars: `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GOOGLE_API_KEY`, `HF_API_KEY`.

### Agent Spec Formats (CLI)

Two formats are accepted by `--agent`:

```bash
# Colon format
type:name
type:name:description
type:subtype:name:description:model

# Flag format
-provider anthropic -name Alice -system "You are..." -model claude-opus-4-6 -timeout 30 -max-retries 2
```

`type` maps to a provider (`anthropic`, `openai`, `google`, `huggingface`) and optionally a task subtype (`image`, `vision`, `music`, `orchestrator`, `classifier`, `code-generation`, etc.).

### URIs (constants)

- Floor manager: `tag:ofp-playground.local,2025:floor-manager`
- Human agents: `tag:ofp-playground.local,2025:human-{name}`
- LLM agents: `tag:ofp-playground.local,2025:llm-{name}`

### In-conversation slash commands

`/help`, `/agents`, `/floor`, `/history`, `/spawn <spec>`, `/kick <name>`, `/quit`

### Session Output

All generated media is saved under a session-scoped directory:

```
result/<timestamp>_<session-id>/
├── images/     — generated images
├── videos/     — generated videos
├── music/      — generated audio
├── code/       — generated code files (CodingAgents)
├── breakout/   — breakout session transcripts
├── manuscript.txt
└── memory.json
```

### Artifact Model

`models/artifact.py` defines `Utterance` and `ArtifactFeature` — the internal typed representation of OFP `dialogEvent.features`. Every utterance has a mandatory `text` feature (verbalizable fallback) plus optional extended keys (`image`, `video`, `3d`, `audio`). Factory methods: `Utterance.from_text()`, `.from_image()`, `.from_video()`.
