# Design: Unified Coding Agents + Rich Manifest + SOUL Library Expansion

**Date:** 2026-04-08  
**Branch:** feature/coding-agents  
**Status:** Approved — ready for implementation

---

## Problem

1. `CodingAgent` only works with OpenAI. Calling `anthropic:code-generation` or `google:code-generation` raises `NotImplementedError`.
2. All OFP agents publish a minimal manifest (text in/out only) regardless of what the underlying model actually supports. GPT-5.4 can do image input, code execution, web search, image generation — none of that is declared.
3. `superpowers-main-2/` is a local snapshot of the superpowers plugin with valuable methodology content. It should be harvested into the `agents/` SOUL library and deleted.
4. The `agents/development/` library is missing key personas: TDD expert, technical planner, tech lead.

---

## Decisions

- **Approach B:** `CodingAgent` becomes a hierarchy — `BaseCodingAgent` + one provider subclass each.
- **Skills → SOUL.md:** Superpowers skill methodology distilled into OFP personas. Behavioural meta-skills (brainstorming, dispatching-parallel-agents, etc.) are skipped — they are Claude Code process skills, not OFP conversation personas.
- **Model catalog:** A static `MODEL_CATALOG` dict maps model name → full capability set. `_build_manifest()` uses it to publish a model-card-quality manifest.

---

## Architecture

### 1. CodingAgent Hierarchy

```
BaseCodingAgent(BaseLLMAgent)
│  Shared: directive parsing, _send_progress, _send_final_and_yield,
│          _build_context, output dir, soul loading (@development/coding-agent)
│  Abstract: _run_code_loop(context) → tuple[str, list[Path]]
│
├── OpenAICodingAgent     — Responses API + code_interpreter (current logic, renamed)
├── AnthropicCodingAgent  — Messages API + code_execution_20250825
└── GoogleCodingAgent     — generateContent + ToolCodeExecution
```

**File locations:**
- `src/ofp_playground/agents/llm/codex.py` — split: base + OpenAI subclass stay here
- `src/ofp_playground/agents/llm/anthropic_coding.py` — new
- `src/ofp_playground/agents/llm/google_coding.py` — new

**Registry additions:**
```python
"anthropic:code-generation" → AnthropicCodingAgent
"google:code-generation"    → GoogleCodingAgent
"openai:code-generation"    → OpenAICodingAgent   # was CodingAgent
```

**Task defaults** (applied at construction in registry):
```python
_TASK_DEFAULTS = {
    "code-generation": {"_timeout": 300.0, "_max_retries": 2},
}
```

### 2. Provider Implementation Details

**`AnthropicCodingAgent._run_code_loop()`:**
- Uses `anthropic.Anthropic` (sync, run in executor — matches existing `AnthropicAgent` pattern)
- Request: `tools=[{"type": "code_execution_20250825", "name": "code_execution"}]`
- Response parsing: scan for `bash_code_execution_tool_result` blocks, extract `stdout`/`stderr`/`return_code`
- File output: v1 captures stdout inline. Files API integration is a future enhancement.
- Default model: `claude-opus-4-6`

**`GoogleCodingAgent._run_code_loop()`:**
- Uses `google.genai` client (matches existing `GoogleAgent`)
- Config: `tools=[types.Tool(code_execution=types.ToolCodeExecution)]`
- Response parsing: iterate `response.candidates[0].content.parts`, collect `executable_code.code` + `code_execution_result.output`
- Must pass back `id` + `thought_signature` fields for multi-turn (handled by SDK automatically when using chat)
- Default model: `gemini-3-flash-preview`

**`OpenAICodingAgent`** — zero functional change from current `CodingAgent`. Rename only. `codex.py` exports `CodingAgent = OpenAICodingAgent` as a backward-compat alias; the test split will update all direct imports.

### 3. Model Capability Catalog

New file: `src/ofp_playground/agents/llm/model_catalog.py`

```python
@dataclass(frozen=True)
class ModelCaps:
    modalities_in: tuple[str, ...]
    modalities_out: tuple[str, ...]
    features: tuple[str, ...]      # streaming, function-calling, extended-thinking, etc.
    tools: tuple[str, ...]         # code-interpreter, web-search, image-generation, etc.
    context_window: int

MODEL_CATALOG: dict[str, ModelCaps] = {
    # OpenAI
    "gpt-5.4": ModelCaps(
        modalities_in=("text", "image"),
        modalities_out=("text", "image"),
        features=("streaming", "function-calling", "structured-outputs", "distillation"),
        tools=("code-interpreter", "web-search", "image-generation", "file-search",
               "computer-use", "mcp", "tool-search"),
        context_window=200_000,
    ),
    "gpt-5.4-long-context": ModelCaps(  # alias used by CodingAgent
        modalities_in=("text", "image"),
        modalities_out=("text", "image"),
        features=("streaming", "function-calling", "structured-outputs"),
        tools=("code-interpreter", "web-search", "image-generation"),
        context_window=1_000_000,
    ),
    "gpt-5.4-nano": ModelCaps(
        modalities_in=("text", "image"),
        modalities_out=("text",),
        features=("streaming", "function-calling", "structured-outputs"),
        tools=(),
        context_window=128_000,
    ),
    # Anthropic
    "claude-opus-4-6": ModelCaps(
        modalities_in=("text", "image"),
        modalities_out=("text",),
        features=("streaming", "function-calling", "structured-outputs", "extended-thinking"),
        tools=("code-execution", "computer-use"),
        context_window=200_000,
    ),
    "claude-sonnet-4-6": ModelCaps(
        modalities_in=("text", "image"),
        modalities_out=("text",),
        features=("streaming", "function-calling", "structured-outputs", "extended-thinking"),
        tools=("code-execution", "computer-use"),
        context_window=200_000,
    ),
    "claude-haiku-4-5": ModelCaps(
        modalities_in=("text", "image"),
        modalities_out=("text",),
        features=("streaming", "function-calling", "structured-outputs"),
        tools=(),
        context_window=200_000,
    ),
    # Google
    "gemini-3.1-pro-preview": ModelCaps(
        modalities_in=("text", "image", "video", "audio"),
        modalities_out=("text",),
        features=("streaming", "function-calling", "structured-outputs", "thinking"),
        tools=("code-execution", "google-search", "url-context", "computer-use"),
        context_window=1_000_000,
    ),
    "gemini-3-flash-preview": ModelCaps(
        modalities_in=("text", "image", "video", "audio"),
        modalities_out=("text",),
        features=("streaming", "function-calling", "structured-outputs", "thinking"),
        tools=("code-execution", "google-search", "url-context"),
        context_window=1_000_000,
    ),
    "gemini-3.1-flash-lite-preview": ModelCaps(
        modalities_in=("text", "image"),
        modalities_out=("text",),
        features=("streaming", "function-calling", "structured-outputs"),
        tools=("code-execution", "google-search"),
        context_window=1_000_000,
    ),
}
```

**`BaseLLMAgent._build_manifest()` update:**
- Look up `MODEL_CATALOG.get(self._model)`
- If found: build rich `Capability` with full keyphrases (modalities + features + tools), full descriptions, and `SupportedLayers` matching actual modalities
- If not found (unknown/HF model): keep current minimal fallback
- All agents benefit automatically — no per-agent override needed unless task-specific keyphrases are desired (CodingAgents will still override to add `code-generation` keyphrases)

### 4. SOUL.md Library Changes

#### New files

| Path | Source |
|------|--------|
| `agents/development/coding-agent/SOUL.md` | New — shared by all 3 coding providers |
| `agents/development/tdd-expert/SOUL.md` | Distilled from `test-driven-development` skill |
| `agents/development/technical-planner/SOUL.md` | Distilled from `writing-plans` skill |
| `agents/development/tech-lead/SOUL.md` | Distilled from `subagent-driven-development` skill |

#### Extended files

| Path | Added from |
|------|-----------|
| `agents/development/code-reviewer/SOUL.md` | + superpowers code-reviewer (plan alignment, architecture review, when-to-invoke trigger) + requesting/receiving-code-review methodology |
| `agents/development/bug-hunter/SOUL.md` | + `systematic-debugging` (4-phase process, root cause before fix, 3-fix architectural trigger) |
| `agents/development/test-writer/SOUL.md` | + `test-driven-development` core (red-green-refactor, iron law, rationalizations table) |
| `agents/development/qa-tester/SOUL.md` | + `verification-before-completion` (evidence before assertions, verification checklist) |
| `agents/development/pr-merger/SOUL.md` | + `finishing-a-development-branch` + `using-git-worktrees` |

#### `agents/development/coding-agent/SOUL.md` key content
- Senior developer identity with sandboxed execution awareness
- **TDD distillation:** Red-Green-Refactor as default rhythm; no production code without failing test first
- **Debugging distillation:** Root cause before fix; never attempt fix #4 without questioning architecture
- **Verification distillation:** Evidence before assertions; run it before claiming done
- Output contract: return code inline, save files to disk, no `sandbox:/mnt/data/` links

#### Deleted
- `superpowers-main-2/` directory (entire) — all useful content harvested above

### 5. Tests

Split `tests/test_coding_agent.py` into:
- `tests/test_coding_agent_base.py` — `BaseCodingAgent` shared logic (directive parsing, progress whisper, final+yield bundle, context building, tools-disabled flag)
- `tests/test_coding_agent_openai.py` — `OpenAICodingAgent` (current tests, moved)
- `tests/test_coding_agent_anthropic.py` — `AnthropicCodingAgent` (new: code_execution tool injected, bash result parsing, stdout/stderr extraction)
- `tests/test_coding_agent_google.py` — `GoogleCodingAgent` (new: ToolCodeExecution config, executable_code + code_execution_result parsing)

Shared fixtures in module-level helpers (not conftest — keep test files self-contained per project convention).

Add `tests/test_model_catalog.py` — verify catalog entries have required fields, no unknown modality strings, context windows are positive.

---

## What Does NOT Change

- `HuggingFaceTextAgent`, `HFImageAgent`, `HFVideoAgent` — untouched
- `GoogleImageAgent`, `OpenAIImageAgent`, `OpenAIVideoAgent`, `GoogleVideoAgent` — untouched (Imagen/DALL-E/Veo/Sora are specialist APIs)
- `AnthropicVisionAgent` — untouched (vision is now implicit in `claude-opus-4-6` manifest; agent stays for explicit vision task routing)
- All floor management, memory store, breakout sessions — untouched
- `ShowrunnerAgent`, `DirectorAgent` — untouched
- Existing CLI spec parsing — untouched; `anthropic:code-generation` already routes correctly via the subtype mechanism

---

## Open Questions (deferred)

- **Anthropic file output v2:** Integrate Files API for `AnthropicCodingAgent` to download generated files (like OpenAI does with `files.content(file_id)`). Out of scope for this iteration.
- **Google file output:** Gemini code execution returns `inlineData` images only; full file download is not yet available. Capture stdout only for now.
- **Model catalog maintenance:** Models evolve rapidly. Catalog is a best-effort snapshot; unknown models fall back gracefully.
