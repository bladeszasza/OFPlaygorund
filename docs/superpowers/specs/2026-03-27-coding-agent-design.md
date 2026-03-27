# CodingAgent Design Spec
**Date**: 2026-03-27
**Status**: Approved
**Replaces**: `web_page.py` / `WebPageAgent`

---

## Overview

Replace `WebPageAgent` (HTML-specific, provider-agnostic) with a general-purpose `CodingAgent` (`codex.py`) backed by OpenAI's Responses API with the `code_interpreter` tool. The agent participates in `SHOWRUNNER_DRIVEN` floors, holds the floor through a full agentic coding loop, and saves generated files to `ofp-code/`.

Other providers (Anthropic, Google, HuggingFace) are stubbed with `NotImplementedError` and will be filled in iteratively.

---

## Files Changed

### Created
- `src/ofp_playground/agents/llm/codex.py` — `CodingAgent` class

### Deleted
- `src/ofp_playground/agents/llm/web_page.py`
- `src/ofp_playground/agents/llm/web_showcase.py`

### Updated (code)
- `src/ofp_playground/agents/llm/__init__.py` — replace `WebPageAgent`/`WebShowcaseAgent` with `CodingAgent`
- `src/ofp_playground/cli.py` — rename task `web-page-generation` → `code-generation` for all 4 providers; wire OpenAI to `CodingAgent`, others to `NotImplementedError`

### Updated (tests)
- `tests/test_coding_agent.py` — new test file (see Testing section)

### Updated (docs)
- `docs/agents.md` — replace `WebPageAgent` section with `CodingAgent`
- `docs/architecture.md` — update agent hierarchy and output directory
- `docs/cli.md` — replace `web-page-generation` task type entry with `code-generation`
- `docs/orchestration.md` — update example agent types in tables
- `docs/output.md` — replace web-page output section with code output section
- `docs/ofp-protocol.md` — update capability keyphrases table
- `docs/configuration.md` — update default model table rows for CodingAgent

### Updated (scripts / CLAUDE.md)
- `examples/showcase_web.sh` — `anthropic:web-page-generation:FrontendDev` → `openai:code-generation:FrontendDev`
- `CLAUDE.md` — update output directory list (`ofp-code/` replaces `ofp-web/`), update agent type table

---

## Architecture

### Class hierarchy

```
BaseLLMAgent
└── CodingAgent          (codex.py)
```

Same inheritance pattern as `web_page.py`. Overrides `_handle_utterance` and `_handle_grant_floor` directly. `_generate_response` and `_quick_check` are stubs (never called).

### Constructor signature

```python
CodingAgent(
    name: str,
    synopsis: str,          # system prompt / role description
    bus: MessageBus,
    conversation_id: str,
    api_key: str,
    provider: str,          # "openai" | "anthropic" | "google" | "hf"
    model: Optional[str] = None,
)
```

Default model by provider:
| Provider | Default |
|---|---|
| `openai` | `gpt-5.4-long-context` |
| `anthropic` | `NotImplementedError` |
| `google` | `NotImplementedError` |
| `hf` | `NotImplementedError` |

### Task type

`task_type` property returns `"code-generation"` (used in OFP manifest keyphrases).

### Output directory

`ofp-code/` (created on init, mirroring `ofp-images/`, `ofp-videos/`, `ofp-music/`).

---

## Message Flow

```
Orchestrator → [DIRECTIVE for CodingAgent]: build index.html with sections...
        ↓
_handle_utterance:
    detects "[DIRECTIVE for" in text
    calls _parse_showrunner_message → stores _task_directive
    FloorManager sends grantFloor next (no request_floor() needed)
        ↓
_handle_grant_floor:
    1. Build context string (directive + session manuscript from _task_directive)
    2. _run_coding_loop(context)  → async generator of (kind, payload)
       ├── "progress"  → send private utterance to floor manager (liveness signal)
       ├── "output"    → accumulate final text
       └── "file"      → (file_id, filename) to download
    3. Download files from code_interpreter → ofp-code/<ts>_<name>.<ext>
    4. Bundle final public utterance + yieldFloor in one envelope
```

---

## OFP Floor Protocol

Per OFP v1.1.0:
- **No yield mid-loop**: hold the floor through the entire agentic coding loop
- **Progress utterances** (private, `to: floor-manager, private: true`): sent on each `code_interpreter_call` start/end event to prevent `revokeFloor @timedOut`
- **Final envelope**: bundles the result utterance + `yieldFloor` (reason: `@complete`) in one envelope — floor manager processes result before registering yield

---

## OpenAI Implementation

Uses `AsyncOpenAI` (native async, no `run_in_executor` needed) via the streaming Responses API:

```python
from openai import AsyncOpenAI

async with client.responses.stream(
    model=self._model,
    instructions=self._synopsis,
    input=context,
    tools=[{"type": "code_interpreter"}],
    reasoning={"effort": "high"},
    max_output_tokens=32000,
) as stream:
    async for event in stream:
        if event.type == "response.output_item.added":
            if getattr(event.item, "type", "") == "code_interpreter_call":
                await self._send_progress(f"Running code_interpreter...")
        elif event.type == "response.output_item.done":
            # accumulate text / file references
    final = await stream.get_final_response()
```

### File download

`code_interpreter` produces files accessible via `client.files.content(file_id)`. Files are saved to `ofp-code/<timestamp>_<agentname>_<filename>`.

### Reasoning effort

Default `"high"`. The synopsis / task description may specify `"medium"` for simpler tasks. Not exposed as a constructor argument in v1 — can be a follow-up.

---

## Context Building

`_build_context()` assembles:
1. **Task directive** — full text of `[DIRECTIVE for Name]: ...` including any injected manuscript from FloorManager
2. **Output contract** — instructs the model to produce file output via code_interpreter, follow the GPT-5.4 output contract pattern
3. **Instruction** — `"Return ONLY the requested files. No preamble. No explanation unless requested."`

This mirrors `web_page.py`'s `_build_context()` structure.

---

## Testing

New file: `tests/test_coding_agent.py`

### Required tests

| Test | What it verifies |
|---|---|
| `test_task_type` | `CodingAgent.task_type == "code-generation"` |
| `test_directive_parsing` | `_handle_utterance` extracts `[DIRECTIVE for Name]:` and stores `_task_directive`; does not call `request_floor` (FloorManager grants directly) |
| `test_ignores_own_utterance` | Agent does not process envelopes from its own URI |
| `test_unsupported_provider_raises` | Constructing with provider `"anthropic"` and calling `_handle_grant_floor` raises `NotImplementedError` |
| `test_output_dir_created` | `ofp-code/` directory is created on init |
| `test_progress_utterance_is_private` | Progress utterances during loop target floor-manager URI with `private: True` |
| `test_final_envelope_bundles_yield` | Final envelope contains utterance event + yieldFloor event |
| `test_files_saved_to_ofp_code` | Mock `code_interpreter` file output → file written to `ofp-code/` with correct naming |

Mock strategy: mock `AsyncOpenAI.responses.stream` to return a synthetic event sequence (progress event → code_interpreter_call done → final text + file_id). No real API calls in tests.

---

## CLI Changes

### Task type rename

Old: `web-page-generation` (aliases: `web-page`, `web-showcase`)
New: `code-generation` (no aliases needed)

### Per-provider wiring

```python
elif task == "code-generation":
    # openai
    from ofp_playground.agents.llm.codex import CodingAgent
    agent = CodingAgent(name=name, synopsis=description, bus=bus,
                        conversation_id=floor.conversation_id,
                        api_key=api_key, provider="openai",
                        model=model_override or None)
    # anthropic / google / hf → same but provider= set accordingly,
    # NotImplementedError raised inside CodingAgent on floor grant
```

### Help text update

All four provider `else` branches in `cli.py` update their error message strings from `web-page-generation` → `code-generation`.

---

## Docs Update Checklist

- [ ] `docs/agents.md` — replace `WebPageAgent` section (lines ~260–282) with `CodingAgent` section
- [ ] `docs/architecture.md` — update agent tree line + output dir from `web/` to `code/`
- [ ] `docs/cli.md` — replace task type table rows 135–137; update code example line 83
- [ ] `docs/orchestration.md` — update lines 288–289 (ChapterBuilder/IndexBuilder examples)
- [ ] `docs/output.md` — replace HTML/base64 output section with `ofp-code/` section
- [ ] `docs/ofp-protocol.md` — update keyphrases table row for this agent
- [ ] `docs/configuration.md` — update model defaults table (lines 93–96)
- [ ] `CLAUDE.md` — update output directories list, agent hierarchy diagram

---

## Invariants / Hard Rules

- `CodingAgent` never calls `request_floor()` — it only responds to explicit `grantFloor` from the FloorManager (same as `web_page.py`)
- Floor is never yielded mid-loop
- Progress utterances are always `private: true` targeting floor manager URI
- Final utterance + `yieldFloor` always sent in one envelope
- `_task_directive` and file list are cleared in `finally` block after each floor grant
- Non-OpenAI providers raise `NotImplementedError` at floor-grant time, not at construction time
