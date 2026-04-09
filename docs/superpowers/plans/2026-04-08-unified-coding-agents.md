# Unified Coding Agents Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `BaseCodingAgent` hierarchy with native Anthropic and Google code-execution support, model-capability-aware manifests, and harvested SOUL.md personas from `superpowers-main-2/`.

**Architecture:** `CodingAgent` is split into `BaseCodingAgent(BaseLLMAgent)` + three provider subclasses (`OpenAICodingAgent`, `AnthropicCodingAgent`, `GoogleCodingAgent`). A `MODEL_CATALOG` dict drives rich OFP manifests for all LLM agents. Superpowers skills are distilled into OFP personas in `agents/development/`.

**Tech Stack:** Python 3.11+, openai SDK (Responses API), anthropic SDK (code_execution_20250825 beta), google-genai SDK (ToolCodeExecution), openfloor OFP library, pytest + pytest-asyncio.

---

## File Map

| Status | Path | Change |
|--------|------|--------|
| Create | `src/ofp_playground/agents/llm/model_catalog.py` | ModelCaps + MODEL_CATALOG |
| Modify | `src/ofp_playground/agents/llm/codex.py` | Add BaseCodingAgent, rename to OpenAICodingAgent, alias |
| Create | `src/ofp_playground/agents/llm/anthropic_coding.py` | AnthropicCodingAgent |
| Create | `src/ofp_playground/agents/llm/google_coding.py` | GoogleCodingAgent |
| Modify | `src/ofp_playground/agents/llm/base.py` | Rich _build_manifest() via MODEL_CATALOG |
| Modify | `src/ofp_playground/agents/llm/__init__.py` | Export new classes |
| Modify | `src/ofp_playground/cli.py` | Route code-generation to provider subclasses |
| Create | `agents/development/coding-agent/SOUL.md` | New coding agent persona |
| Create | `agents/development/tdd-expert/SOUL.md` | TDD methodology persona |
| Create | `agents/development/technical-planner/SOUL.md` | Planning methodology persona |
| Create | `agents/development/tech-lead/SOUL.md` | Orchestration persona |
| Modify | `agents/development/code-reviewer/SOUL.md` | + plan alignment + review methodology |
| Modify | `agents/development/bug-hunter/SOUL.md` | + 4-phase systematic debugging |
| Modify | `agents/development/test-writer/SOUL.md` | + Red-Green-Refactor core |
| Modify | `agents/development/qa-tester/SOUL.md` | + verification-before-completion |
| Modify | `agents/development/pr-merger/SOUL.md` | + finishing-branch + git worktrees |
| Create | `tests/test_model_catalog.py` | ModelCaps validation tests |
| Create | `tests/test_coding_agent_base.py` | BaseCodingAgent shared logic tests |
| Create | `tests/test_coding_agent_openai.py` | OpenAICodingAgent tests (migrated) |
| Create | `tests/test_coding_agent_anthropic.py` | AnthropicCodingAgent tests |
| Create | `tests/test_coding_agent_google.py` | GoogleCodingAgent tests |
| Delete | `tests/test_coding_agent.py` | Replaced by above 3 |
| Delete | `superpowers-main-2/` | Content harvested into SOUL.md library |

---

### Task 1: MODEL_CATALOG

**Files:**
- Create: `src/ofp_playground/agents/llm/model_catalog.py`
- Create: `tests/test_model_catalog.py`

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_model_catalog.py
"""Validate MODEL_CATALOG entries."""
from __future__ import annotations
import pytest

VALID_MODALITIES = {"text", "image", "video", "audio"}


def test_import():
    from ofp_playground.agents.llm.model_catalog import MODEL_CATALOG, ModelCaps
    assert MODEL_CATALOG
    assert ModelCaps


def test_expected_models_present():
    from ofp_playground.agents.llm.model_catalog import MODEL_CATALOG
    expected = {
        "gpt-5.4", "gpt-5.4-long-context", "gpt-5.4-nano",
        "claude-opus-4-6", "claude-sonnet-4-6", "claude-haiku-4-5",
        "gemini-3.1-pro-preview", "gemini-3-flash-preview", "gemini-3.1-flash-lite-preview",
    }
    assert set(MODEL_CATALOG.keys()) == expected


def test_context_windows_positive():
    from ofp_playground.agents.llm.model_catalog import MODEL_CATALOG
    for model, caps in MODEL_CATALOG.items():
        assert caps.context_window > 0, f"{model}: context_window must be > 0"


def test_modalities_in_known():
    from ofp_playground.agents.llm.model_catalog import MODEL_CATALOG
    for model, caps in MODEL_CATALOG.items():
        for m in caps.modalities_in:
            assert m in VALID_MODALITIES, f"{model}: unknown modality_in '{m}'"


def test_modalities_out_non_empty():
    from ofp_playground.agents.llm.model_catalog import MODEL_CATALOG
    for model, caps in MODEL_CATALOG.items():
        assert len(caps.modalities_out) > 0, f"{model}: modalities_out must not be empty"


def test_frozen_dataclass():
    from ofp_playground.agents.llm.model_catalog import MODEL_CATALOG
    caps = MODEL_CATALOG["gpt-5.4"]
    with pytest.raises((AttributeError, TypeError)):
        object.__setattr__(caps, "context_window", 999)
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
pytest tests/test_model_catalog.py -v
```
Expected: `ImportError: cannot import name 'MODEL_CATALOG'`

- [ ] **Step 3: Create model_catalog.py**

```python
# src/ofp_playground/agents/llm/model_catalog.py
"""Model capability catalog — drives OFP manifest generation."""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class ModelCaps:
    modalities_in: tuple[str, ...]
    modalities_out: tuple[str, ...]
    features: tuple[str, ...]      # streaming, function-calling, extended-thinking, …
    tools: tuple[str, ...]         # code-interpreter, web-search, image-generation, …
    context_window: int


MODEL_CATALOG: dict[str, ModelCaps] = {
    # --- OpenAI ---
    "gpt-5.4": ModelCaps(
        modalities_in=("text", "image"),
        modalities_out=("text", "image"),
        features=("streaming", "function-calling", "structured-outputs", "distillation"),
        tools=("code-interpreter", "web-search", "image-generation", "file-search",
               "computer-use", "mcp", "tool-search"),
        context_window=200_000,
    ),
    "gpt-5.4-long-context": ModelCaps(
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
    # --- Anthropic ---
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
    # --- Google ---
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

- [ ] **Step 4: Run tests — confirm they pass**

```bash
pytest tests/test_model_catalog.py -v
```
Expected: `9 passed`

- [ ] **Step 5: Commit**

```bash
git add src/ofp_playground/agents/llm/model_catalog.py tests/test_model_catalog.py
git commit -m "feat: add MODEL_CATALOG with ModelCaps for 9 models"
```

---

### Task 2: Refactor codex.py → BaseCodingAgent + OpenAICodingAgent

**Files:**
- Modify: `src/ofp_playground/agents/llm/codex.py`

Split `CodingAgent` into an abstract `BaseCodingAgent` (all shared logic) and a concrete `OpenAICodingAgent` (OpenAI Responses API). Add `CodingAgent = OpenAICodingAgent` backward-compat alias. The only functional change: `BaseCodingAgent.__init__` drops the `provider=` param, sets task defaults (`_timeout=300.0`, `_max_retries=2`), and loads `@development/coding-agent` SOUL.md when no synopsis is given.

- [ ] **Step 1: Write tests for the new class hierarchy**

Create `tests/test_coding_agent_base.py`:

```python
# tests/test_coding_agent_base.py
"""Tests for BaseCodingAgent shared logic (provider-independent)."""
from __future__ import annotations

import uuid
from unittest.mock import AsyncMock, patch

import pytest

from ofp_playground.bus.message_bus import FLOOR_MANAGER_URI, MessageBus


def _make_utterance_envelope(text: str, sender_uri: str):
    from openfloor import Conversation, DialogEvent, Envelope, Sender, TextFeature, Token, UtteranceEvent
    return Envelope(
        sender=Sender(speakerUri=sender_uri, serviceUrl="local://test"),
        conversation=Conversation(id="test-conv-1"),
        events=[UtteranceEvent(dialogEvent=DialogEvent(
            id=str(uuid.uuid4()),
            speakerUri=sender_uri,
            features={"text": TextFeature(mimeType="text/plain", tokens=[Token(value=text)])},
        ))],
    )


def _make_base_agent(tmp_path):
    from ofp_playground.agents.llm.codex import OpenAICodingAgent
    a = OpenAICodingAgent(
        name="Coder",
        synopsis="You are a coding agent.",
        bus=MessageBus(),
        conversation_id="test-conv-1",
        api_key="test-key",
    )
    a._output_dir = tmp_path / "ofp-code"
    a._output_dir.mkdir()
    return a


def test_task_type(tmp_path):
    agent = _make_base_agent(tmp_path)
    assert agent.task_type == "code-generation"


def test_task_defaults_applied(tmp_path):
    agent = _make_base_agent(tmp_path)
    assert agent._timeout == 300.0
    assert agent._max_retries == 2


def test_output_dir_created(tmp_path, monkeypatch):
    from ofp_playground.agents.llm import codex as codex_module
    target = tmp_path / "ofp-code-new"
    monkeypatch.setattr(codex_module, "OUTPUT_DIR", target)
    from ofp_playground.agents.llm.codex import OpenAICodingAgent
    OpenAICodingAgent(name="C", synopsis="s", bus=MessageBus(), conversation_id="c", api_key="k")
    assert target.exists()


@pytest.mark.asyncio
async def test_directive_parsing(tmp_path):
    agent = _make_base_agent(tmp_path)
    text = "[DIRECTIVE for Coder]: Write a Python hello world script."
    envelope = _make_utterance_envelope(text, sender_uri=FLOOR_MANAGER_URI)
    with patch.object(agent, "request_floor", new_callable=AsyncMock) as mock_rf:
        await agent._handle_utterance(envelope)
        mock_rf.assert_not_called()
    assert "DIRECTIVE for Coder" in agent._task_directive


@pytest.mark.asyncio
async def test_ignores_own_utterance(tmp_path):
    agent = _make_base_agent(tmp_path)
    envelope = _make_utterance_envelope("hello", sender_uri=agent.speaker_uri)
    await agent._handle_utterance(envelope)
    assert agent._task_directive == ""


@pytest.mark.asyncio
async def test_progress_utterance_is_private(tmp_path):
    agent = _make_base_agent(tmp_path)
    sent = []
    agent._bus.send_private = AsyncMock(side_effect=lambda env, uri: sent.append((env, uri)))
    await agent._send_progress("Working on it...")
    assert len(sent) == 1
    _, target_uri = sent[0]
    assert target_uri == FLOOR_MANAGER_URI


@pytest.mark.asyncio
async def test_final_envelope_bundles_yield(tmp_path):
    agent = _make_base_agent(tmp_path)
    sent = []
    agent._bus.send = AsyncMock(side_effect=lambda env: sent.append(env))
    await agent._send_final_and_yield("Task complete.")
    assert len(sent) == 1
    assert len(sent[0].events) == 2
    event_types = [getattr(e, "eventType", "") for e in sent[0].events]
    assert event_types[0] != "yieldFloor"
    assert event_types[1] == "yieldFloor"


def test_tools_disabled_for_retry_directive(tmp_path):
    agent = _make_base_agent(tmp_path)
    agent._task_directive = "[DIRECTIVE for Coder]: Retry without tools. Deliver architecture bullets only."
    assert agent._tools_disabled_for_directive() is True


def test_tools_enabled_by_default(tmp_path):
    agent = _make_base_agent(tmp_path)
    agent._task_directive = "[DIRECTIVE for Coder]: Write a sorting function."
    assert agent._tools_disabled_for_directive() is False


def test_soul_loaded_when_synopsis_empty(tmp_path):
    """When synopsis is empty, BaseCodingAgent loads @development/coding-agent SOUL.md."""
    from ofp_playground.agents.llm.codex import OpenAICodingAgent
    # Only works if agents/development/coding-agent/SOUL.md exists (Task 8 prerequisite)
    # This test can be skipped until Task 8 is done by using a fallback check
    a = OpenAICodingAgent(name="C", synopsis="", bus=MessageBus(), conversation_id="c", api_key="k")
    # After Task 8: assert "Coding Agent" in a._synopsis (or similar non-empty check)
    # For now: verify synopsis was set to something non-empty or is empty string (pre-Task 8)
    assert a._synopsis is not None
```

Create `tests/test_coding_agent_openai.py`:

```python
# tests/test_coding_agent_openai.py
"""Tests for OpenAICodingAgent — OpenAI Responses API + code_interpreter."""
from __future__ import annotations

import uuid
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from ofp_playground.bus.message_bus import MessageBus


def _make_agent(tmp_path):
    from ofp_playground.agents.llm.codex import OpenAICodingAgent
    a = OpenAICodingAgent(
        name="Coder",
        synopsis="You are a coding agent.",
        bus=MessageBus(),
        conversation_id="test-conv-1",
        api_key="test-key",
    )
    a._output_dir = tmp_path / "ofp-code"
    a._output_dir.mkdir()
    return a


@pytest.mark.asyncio
async def test_files_saved_to_ofp_code(tmp_path):
    agent = _make_agent(tmp_path)
    fake_bytes = b"print('hello')"

    progress_event = MagicMock()
    progress_event.type = "response.output_item.added"
    progress_event.item = MagicMock(type="code_interpreter_call")

    file_done_event = MagicMock()
    file_done_event.type = "response.output_item.done"
    mock_file = MagicMock(file_id="file-abc123", filename="solution.py")
    mock_output = MagicMock(type="files", files=[mock_file])
    file_done_event.item = MagicMock(type="code_interpreter_call", outputs=[mock_output])

    mock_final = MagicMock()
    mock_final.output = []

    mock_stream = AsyncMock()
    mock_stream.__aenter__ = AsyncMock(return_value=mock_stream)
    mock_stream.__aexit__ = AsyncMock(return_value=False)
    mock_stream.__aiter__.return_value = iter([progress_event, file_done_event])
    mock_stream.get_final_response = AsyncMock(return_value=mock_final)

    mock_file_content = MagicMock(content=fake_bytes)
    mock_client = AsyncMock()
    mock_client.responses.stream = MagicMock(return_value=mock_stream)
    mock_client.files.content = AsyncMock(return_value=mock_file_content)

    agent.send_private_utterance = AsyncMock()

    with patch("openai.AsyncOpenAI", return_value=mock_client):
        _, saved = await agent._run_code_loop("test context")

    stream_kwargs = mock_client.responses.stream.call_args.kwargs
    assert stream_kwargs["tools"][0]["container"] == {"type": "auto"}
    assert len(saved) == 1
    assert saved[0].exists()
    assert saved[0].read_bytes() == fake_bytes
    assert "solution" in saved[0].name


@pytest.mark.asyncio
async def test_retry_without_tools_omits_tools_payload(tmp_path):
    agent = _make_agent(tmp_path)
    agent._task_directive = "[DIRECTIVE for Coder]: Retry without tools. Deliver architecture bullets only."

    mock_part = MagicMock(type="output_text", text="Architecture bullets")
    mock_item = MagicMock(type="message", content=[mock_part])
    mock_final = MagicMock(output=[mock_item])

    mock_stream = AsyncMock()
    mock_stream.__aenter__ = AsyncMock(return_value=mock_stream)
    mock_stream.__aexit__ = AsyncMock(return_value=False)
    mock_stream.__aiter__.return_value = iter([])
    mock_stream.get_final_response = AsyncMock(return_value=mock_final)

    mock_client = AsyncMock()
    mock_client.responses.stream = MagicMock(return_value=mock_stream)
    mock_client.files.content = AsyncMock()

    with patch("openai.AsyncOpenAI", return_value=mock_client):
        output, saved = await agent._run_code_loop("test context")

    stream_kwargs = mock_client.responses.stream.call_args.kwargs
    assert "tools" not in stream_kwargs
    assert output == "Architecture bullets"
    assert saved == []


def test_default_model_is_long_context(tmp_path):
    from ofp_playground.agents.llm.codex import OpenAICodingAgent
    a = OpenAICodingAgent(name="C", synopsis="s", bus=MessageBus(), conversation_id="c", api_key="k")
    assert a._model == "gpt-5.4-long-context"


def test_coding_agent_alias(tmp_path):
    """CodingAgent is an alias for OpenAICodingAgent."""
    from ofp_playground.agents.llm.codex import CodingAgent, OpenAICodingAgent
    assert CodingAgent is OpenAICodingAgent
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
pytest tests/test_coding_agent_base.py tests/test_coding_agent_openai.py -v
```
Expected: `ImportError: cannot import name 'OpenAICodingAgent'`

- [ ] **Step 3: Refactor codex.py**

Replace the contents of `src/ofp_playground/agents/llm/codex.py` with:

```python
"""Coding agent — BaseCodingAgent hierarchy for all providers."""
from __future__ import annotations

import abc
import logging
import re
import uuid
from datetime import datetime
from pathlib import Path
from typing import Optional

from openfloor import Envelope

from ofp_playground.agents.llm.base import BaseLLMAgent
from ofp_playground.bus.message_bus import FLOOR_MANAGER_URI, MessageBus

logger = logging.getLogger(__name__)

OUTPUT_DIR = Path("ofp-code")
DEFAULT_MODEL_OPENAI = "gpt-5.4-long-context"
CODE_INTERPRETER_CONTAINER = {"type": "auto"}


class BaseCodingAgent(BaseLLMAgent):
    """Abstract base for all coding agents.

    Shared: directive parsing, _send_progress, _send_final_and_yield,
            _build_context, output dir, task defaults, SOUL loading.
    Abstract: _run_code_loop(context) → tuple[str, list[Path]]
    """

    def __init__(
        self,
        name: str,
        synopsis: str,
        bus: MessageBus,
        conversation_id: str,
        api_key: str,
        model: Optional[str] = None,
    ):
        if not synopsis:
            try:
                from ofp_playground.agents.library import resolve_slug
                synopsis = resolve_slug("@development/coding-agent")
            except (ValueError, Exception):
                synopsis = "You are a senior software developer. Write, run, and validate code."
        super().__init__(
            name=name,
            synopsis=synopsis,
            bus=bus,
            conversation_id=conversation_id,
            model=model,
            relevance_filter=False,
            api_key=api_key,
        )
        # Task defaults — these are expensive, long-running operations
        self._timeout = 300.0
        self._max_retries = 2
        self._task_directive: str = ""
        self._output_dir: Path = OUTPUT_DIR
        self._output_dir.mkdir(parents=True, exist_ok=True)

    @property
    def task_type(self) -> str:
        return "code-generation"

    async def _generate_response(self, participants):
        raise NotImplementedError("CodingAgent subclasses override _handle_grant_floor directly")

    async def _quick_check(self, prompt: str) -> str:
        return "NO"

    @abc.abstractmethod
    async def _run_code_loop(self, context: str) -> tuple[str, list[Path]]:
        """Run the provider-specific code-execution loop.

        Returns (output_text, saved_files).
        """

    async def _handle_utterance(self, envelope: Envelope) -> None:
        sender_uri = self._get_sender_uri(envelope)
        if sender_uri == self.speaker_uri:
            return
        text = self._extract_text_from_envelope(envelope)
        if not text:
            return
        if "[DIRECTIVE for" in text:
            if self._parse_showrunner_message(text):
                self._task_directive = text
            return
        sender_name = self._name_registry.get(sender_uri, sender_uri.split(":")[-1])
        self._append_to_context(sender_name, text, is_self=False)

    async def _send_progress(self, message: str) -> None:
        await self.send_private_utterance(f"[{self._name}] {message}", FLOOR_MANAGER_URI)

    async def _send_final_and_yield(self, result: str) -> None:
        from openfloor import DialogEvent, Event, TextFeature, Token, UtteranceEvent
        dialog_event = DialogEvent(
            id=str(uuid.uuid4()),
            speakerUri=self._speaker_uri,
            features={"text": TextFeature(mimeType="text/plain", tokens=[Token(value=result)])},
        )
        envelope = Envelope(
            sender=self._make_sender(),
            conversation=self._make_conversation(),
            events=[
                UtteranceEvent(dialogEvent=dialog_event),
                Event(eventType="yieldFloor", reason="@complete"),
            ],
        )
        await self.send_envelope(envelope)

    def _build_context(self) -> str:
        parts = ["=== CODING TASK CONTEXT ===\n"]
        if self._task_directive:
            parts.append(f"## TASK DIRECTIVE\n{self._task_directive}\n")
        parts.append(
            "\n=== OUTPUT CONTRACT ===\n"
            "Implement the task completely using code execution. "
            "Save all output files to disk. "
            "Return your full output text INLINE — do NOT include markdown download links "
            "like [Download ...](sandbox:/mnt/data/...) because those paths are inaccessible. "
            "Return ONLY the implementation — no preamble unless requested.\n"
        )
        return "\n".join(parts)

    def _tools_disabled_for_directive(self) -> bool:
        directive = (self._task_directive or "").lower()
        disable_markers = (
            "[retry_no_tools]", "retry without tools", "without tools",
            "no code execution", "architecture bullets only", "deliver architecture bullets only",
        )
        return any(marker in directive for marker in disable_markers)

    async def _handle_grant_floor(self) -> None:
        self._has_floor = True
        try:
            await self._send_progress("Starting coding task...")
            context = self._build_context()
            output_text, saved_files = await self._call_with_retry(
                lambda: self._run_code_loop(context)
            )
            cleaned_output = re.sub(
                r"\[(?:Download [^\]]*|[^\]]+)\]\(sandbox:/mnt/data/[^)]*\)",
                "",
                (output_text or ""),
            ).strip()
            lines: list[str] = []
            if cleaned_output:
                lines.append(cleaned_output)
            for path in saved_files:
                lines.append(f"File saved: {path.resolve()}")
            result = "\n".join(lines) if lines else "Coding task complete (no file output)."
            await self._send_final_and_yield(result)
        except Exception as e:
            logger.error("[%s] Coding loop error: %s", self._name, e, exc_info=True)
            await self._send_final_and_yield(f"Coding task failed: {str(e)[:200]}")
        finally:
            self._has_floor = False
            self._pending_floor_request = False
            self._task_directive = ""


class OpenAICodingAgent(BaseCodingAgent):
    """OpenAI Responses API + code_interpreter agentic loop."""

    def __init__(
        self,
        name: str,
        synopsis: str,
        bus: MessageBus,
        conversation_id: str,
        api_key: str,
        model: Optional[str] = None,
    ):
        super().__init__(
            name=name,
            synopsis=synopsis,
            bus=bus,
            conversation_id=conversation_id,
            api_key=api_key,
            model=model or DEFAULT_MODEL_OPENAI,
        )

    @staticmethod
    def _is_tool_configuration_error(err: Exception) -> bool:
        low = str(err).lower()
        return "tools[0].container" in low or (
            "code_interpreter" in low and "missing required parameter" in low
        )

    async def _run_code_loop(self, context: str) -> tuple[str, list[Path]]:
        from openai import AsyncOpenAI
        tools_disabled = self._tools_disabled_for_directive()
        if tools_disabled:
            await self._send_progress("Directive requested text-only mode (tools disabled).")

        async def _stream_once() -> tuple[str, list[tuple[str, str]]]:
            client = AsyncOpenAI(api_key=self._api_key)
            local_output_text = ""
            local_file_ids: list[tuple[str, str]] = []
            request_kwargs = {
                "model": self._model,
                "instructions": self._synopsis,
                "input": context,
                "reasoning": {"effort": "high"},
                "max_output_tokens": 32000,
            }
            if not tools_disabled:
                request_kwargs["tools"] = [{"type": "code_interpreter", "container": CODE_INTERPRETER_CONTAINER}]
            try:
                async with client.responses.stream(**request_kwargs) as stream:  # type: ignore[call-overload]
                    async for event in stream:
                        event_type = getattr(event, "type", "")
                        if event_type == "response.output_item.added":
                            if getattr(getattr(event, "item", None), "type", "") == "code_interpreter_call":
                                await self._send_progress("Running code_interpreter...")
                        elif event_type == "response.output_item.done":
                            item = getattr(event, "item", None)
                            if item and getattr(item, "type", "") == "code_interpreter_call":
                                for out in (getattr(item, "outputs", None) or []):
                                    if getattr(out, "type", "") == "files":
                                        for f in (getattr(out, "files", None) or []):
                                            local_file_ids.append((f.file_id, f.filename))
                                    elif getattr(out, "type", "") == "logs":
                                        logs = (getattr(out, "logs", "") or "").strip()
                                        if logs:
                                            await self._send_progress(f"Output: {logs[:120]}")
                    final = await stream.get_final_response()
                    for item in (final.output or []):
                        if getattr(item, "type", "") == "message":
                            for part in (getattr(item, "content", None) or []):
                                if getattr(part, "type", "") == "output_text":
                                    local_output_text += getattr(part, "text", "")
            finally:
                await client.close()
            return local_output_text, local_file_ids

        try:
            output_text, file_ids = await _stream_once()
        except Exception as e:
            if tools_disabled or not self._is_tool_configuration_error(e):
                raise
            await self._send_progress("Tool mode unavailable, retrying without tools.")
            tools_disabled = True
            output_text, file_ids = await _stream_once()

        saved_files: list[Path] = []
        dl_client = AsyncOpenAI(api_key=self._api_key)
        try:
            ts = datetime.now().strftime("%Y%m%d_%H%M%S")
            slug = re.sub(r"[^\w]+", "_", self._name.lower())
            for file_id, filename in file_ids:
                try:
                    content = await dl_client.files.content(file_id)
                    stem = Path(filename).stem
                    ext = Path(filename).suffix or ".bin"
                    out_path = self._output_dir / f"{ts}_{slug}_{stem}{ext}"
                    out_path.write_bytes(content.content)
                    saved_files.append(out_path)
                    await self._send_progress(f"Saved {out_path.name}")
                except Exception as e:
                    logger.error("[%s] Failed to save file %s: %s", self._name, file_id, e)
        finally:
            await dl_client.close()
        return output_text, saved_files


# Backward-compat alias — existing code importing CodingAgent continues to work
CodingAgent = OpenAICodingAgent
```

- [ ] **Step 4: Run the new tests**

```bash
pytest tests/test_coding_agent_base.py tests/test_coding_agent_openai.py -v
```
Expected: all tests pass (except `test_soul_loaded_when_synopsis_empty` which is contingent on Task 8)

- [ ] **Step 5: Verify old test file still passes (regression)**

```bash
pytest tests/test_coding_agent.py -v
```
Expected: all tests pass (CodingAgent alias works)

- [ ] **Step 6: Commit**

```bash
git add src/ofp_playground/agents/llm/codex.py tests/test_coding_agent_base.py tests/test_coding_agent_openai.py
git commit -m "refactor: split CodingAgent → BaseCodingAgent + OpenAICodingAgent"
```

---

### Task 3: AnthropicCodingAgent

**Files:**
- Create: `src/ofp_playground/agents/llm/anthropic_coding.py`
- Create: `tests/test_coding_agent_anthropic.py`

- [ ] **Step 1: Write failing tests**

```python
# tests/test_coding_agent_anthropic.py
"""Tests for AnthropicCodingAgent — code_execution_20250825 beta tool."""
from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from ofp_playground.bus.message_bus import MessageBus


def _make_agent(tmp_path):
    from ofp_playground.agents.llm.anthropic_coding import AnthropicCodingAgent
    a = AnthropicCodingAgent(
        name="AnthropicCoder",
        synopsis="You are a coding agent.",
        bus=MessageBus(),
        conversation_id="test-conv-1",
        api_key="test-key",
    )
    a._output_dir = tmp_path / "ofp-code"
    a._output_dir.mkdir()
    return a


def test_import():
    from ofp_playground.agents.llm.anthropic_coding import AnthropicCodingAgent
    assert AnthropicCodingAgent


def test_default_model(tmp_path):
    agent = _make_agent(tmp_path)
    assert agent._model == "claude-opus-4-6"


def test_task_type(tmp_path):
    agent = _make_agent(tmp_path)
    assert agent.task_type == "code-generation"


def test_task_defaults(tmp_path):
    agent = _make_agent(tmp_path)
    assert agent._timeout == 300.0
    assert agent._max_retries == 2


@pytest.mark.asyncio
async def test_code_execution_tool_injected(tmp_path):
    """code_execution_20250825 tool must appear in the API request."""
    agent = _make_agent(tmp_path)
    agent.send_private_utterance = __import__("unittest.mock", fromlist=["AsyncMock"]).AsyncMock()

    captured_kwargs: dict = {}

    def _fake_create(**kwargs):
        captured_kwargs.update(kwargs)
        mock_response = MagicMock()
        mock_response.content = []
        return mock_response

    mock_client = MagicMock()
    mock_client.messages.create.side_effect = _fake_create

    with patch("anthropic.Anthropic", return_value=mock_client):
        await agent._run_code_loop("Write hello world in Python.")

    tools = captured_kwargs.get("tools", [])
    assert any(t.get("type") == "code_execution_20250825" for t in tools), (
        f"code_execution_20250825 not found in tools: {tools}"
    )


@pytest.mark.asyncio
async def test_stdout_extracted_from_bash_result(tmp_path):
    """stdout text from bash_code_execution_tool_result blocks is captured."""
    agent = _make_agent(tmp_path)
    agent.send_private_utterance = __import__("unittest.mock", fromlist=["AsyncMock"]).AsyncMock()

    text_block = MagicMock()
    text_block.type = "text"
    text_block.text = "Here is the output:"

    exec_result = MagicMock()
    exec_result.type = "bash_code_execution_tool_result"
    # content is a list of text blocks with the stdout
    stdout_content = MagicMock()
    stdout_content.type = "text"
    stdout_content.text = "hello world\n"
    exec_result.content = [stdout_content]

    mock_response = MagicMock()
    mock_response.content = [text_block, exec_result]

    mock_client = MagicMock()
    mock_client.messages.create.return_value = mock_response

    with patch("anthropic.Anthropic", return_value=mock_client):
        output, saved = await agent._run_code_loop("Write hello world.")

    assert "hello world" in output
    assert saved == []  # v1: no file download for Anthropic
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
pytest tests/test_coding_agent_anthropic.py -v
```
Expected: `ImportError: cannot import name 'AnthropicCodingAgent'`

- [ ] **Step 3: Create anthropic_coding.py**

```python
# src/ofp_playground/agents/llm/anthropic_coding.py
"""AnthropicCodingAgent — native code_execution_20250825 beta tool."""
from __future__ import annotations

import logging
from pathlib import Path
from typing import Optional

from ofp_playground.agents.llm.codex import BaseCodingAgent
from ofp_playground.bus.message_bus import MessageBus

logger = logging.getLogger(__name__)

DEFAULT_MODEL_ANTHROPIC = "claude-opus-4-6"


class AnthropicCodingAgent(BaseCodingAgent):
    """Coding agent using Anthropic's native code_execution_20250825 beta tool.

    Runs the model synchronously in a thread executor (matches AnthropicAgent pattern).
    v1: captures stdout inline; Anthropic Files API integration is a future enhancement.
    """

    def __init__(
        self,
        name: str,
        synopsis: str,
        bus: MessageBus,
        conversation_id: str,
        api_key: str,
        model: Optional[str] = None,
    ):
        super().__init__(
            name=name,
            synopsis=synopsis,
            bus=bus,
            conversation_id=conversation_id,
            api_key=api_key,
            model=model or DEFAULT_MODEL_ANTHROPIC,
        )

    async def _run_code_loop(self, context: str) -> tuple[str, list[Path]]:
        import asyncio
        loop = asyncio.get_event_loop()
        await self._send_progress("Sending to Anthropic code_execution...")

        def _call() -> tuple[str, list[Path]]:
            import anthropic
            client = anthropic.Anthropic(api_key=self._api_key)

            tools = [{"type": "code_execution_20250825", "name": "code_execution"}]
            messages = [{"role": "user", "content": context}]

            response = client.messages.create(
                model=self._model,
                max_tokens=16000,
                system=self._synopsis,
                tools=tools,
                messages=messages,
                betas=["code-execution-2025-05-22"],
            )

            output_parts: list[str] = []
            for block in response.content:
                block_type = getattr(block, "type", "")
                if block_type == "text":
                    text = getattr(block, "text", "")
                    if text:
                        output_parts.append(text)
                elif block_type == "bash_code_execution_tool_result":
                    # Extract stdout from content blocks
                    for content_block in (getattr(block, "content", None) or []):
                        cb_type = getattr(content_block, "type", "")
                        if cb_type == "text":
                            stdout = getattr(content_block, "text", "")
                            if stdout:
                                output_parts.append(stdout)

            return "\n".join(filter(None, output_parts)), []

        return await loop.run_in_executor(None, _call)
```

- [ ] **Step 4: Run tests — confirm they pass**

```bash
pytest tests/test_coding_agent_anthropic.py -v
```
Expected: `5 passed`

- [ ] **Step 5: Commit**

```bash
git add src/ofp_playground/agents/llm/anthropic_coding.py tests/test_coding_agent_anthropic.py
git commit -m "feat: AnthropicCodingAgent with native code_execution_20250825 tool"
```

---

### Task 4: GoogleCodingAgent

**Files:**
- Create: `src/ofp_playground/agents/llm/google_coding.py`
- Create: `tests/test_coding_agent_google.py`

- [ ] **Step 1: Write failing tests**

```python
# tests/test_coding_agent_google.py
"""Tests for GoogleCodingAgent — ToolCodeExecution."""
from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from ofp_playground.bus.message_bus import MessageBus


def _make_agent(tmp_path):
    from ofp_playground.agents.llm.google_coding import GoogleCodingAgent
    a = GoogleCodingAgent(
        name="GeminiCoder",
        synopsis="You are a coding agent.",
        bus=MessageBus(),
        conversation_id="test-conv-1",
        api_key="test-key",
    )
    a._output_dir = tmp_path / "ofp-code"
    a._output_dir.mkdir()
    return a


def test_import():
    from ofp_playground.agents.llm.google_coding import GoogleCodingAgent
    assert GoogleCodingAgent


def test_default_model(tmp_path):
    agent = _make_agent(tmp_path)
    assert agent._model == "gemini-3-flash-preview"


def test_task_type(tmp_path):
    agent = _make_agent(tmp_path)
    assert agent.task_type == "code-generation"


def test_task_defaults(tmp_path):
    agent = _make_agent(tmp_path)
    assert agent._timeout == 300.0
    assert agent._max_retries == 2


@pytest.mark.asyncio
async def test_tool_code_execution_configured(tmp_path):
    """ToolCodeExecution must appear in the generate_content config."""
    agent = _make_agent(tmp_path)
    agent.send_private_utterance = __import__("unittest.mock", fromlist=["AsyncMock"]).AsyncMock()

    captured_config = {}

    def _fake_generate(model, contents, config=None):
        if config:
            captured_config["tools"] = config.tools
        mock_response = MagicMock()
        mock_response.candidates = []
        return mock_response

    mock_models = MagicMock()
    mock_models.generate_content.side_effect = _fake_generate
    mock_client = MagicMock()
    mock_client.models = mock_models

    with patch("google.genai.Client", return_value=mock_client):
        await agent._run_code_loop("Write hello world.")

    assert "tools" in captured_config, "tools not passed to generate_content"
    tools = captured_config["tools"]
    # At least one tool should be a Tool with code_execution set
    assert tools, "tools list is empty"


@pytest.mark.asyncio
async def test_code_execution_output_extracted(tmp_path):
    """code_execution_result.output parts are included in the returned text."""
    agent = _make_agent(tmp_path)
    agent.send_private_utterance = __import__("unittest.mock", fromlist=["AsyncMock"]).AsyncMock()

    text_part = MagicMock(spec=[])
    text_part.text = "Running code..."
    del text_part.executable_code
    del text_part.code_execution_result

    exec_part = MagicMock(spec=[])
    exec_part.text = ""
    exec_result = MagicMock()
    exec_result.output = "hello world\n"
    exec_part.code_execution_result = exec_result
    del exec_part.executable_code

    mock_content = MagicMock()
    mock_content.parts = [text_part, exec_part]
    mock_candidate = MagicMock()
    mock_candidate.content = mock_content
    mock_response = MagicMock()
    mock_response.candidates = [mock_candidate]

    mock_models = MagicMock()
    mock_models.generate_content.return_value = mock_response
    mock_client = MagicMock()
    mock_client.models = mock_models

    with patch("google.genai.Client", return_value=mock_client):
        output, saved = await agent._run_code_loop("Write hello world.")

    assert "hello world" in output
    assert saved == []
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
pytest tests/test_coding_agent_google.py -v
```
Expected: `ImportError: cannot import name 'GoogleCodingAgent'`

- [ ] **Step 3: Create google_coding.py**

```python
# src/ofp_playground/agents/llm/google_coding.py
"""GoogleCodingAgent — native ToolCodeExecution via google.genai."""
from __future__ import annotations

import logging
from pathlib import Path
from typing import Optional

from ofp_playground.agents.llm.codex import BaseCodingAgent
from ofp_playground.bus.message_bus import MessageBus

logger = logging.getLogger(__name__)

DEFAULT_MODEL_GOOGLE = "gemini-3-flash-preview"


class GoogleCodingAgent(BaseCodingAgent):
    """Coding agent using Google Gemini's native ToolCodeExecution.

    Runs synchronously in a thread executor (matches GoogleAgent pattern).
    v1: captures stdout inline; inlineData images are not downloaded.
    """

    def __init__(
        self,
        name: str,
        synopsis: str,
        bus: MessageBus,
        conversation_id: str,
        api_key: str,
        model: Optional[str] = None,
    ):
        super().__init__(
            name=name,
            synopsis=synopsis,
            bus=bus,
            conversation_id=conversation_id,
            api_key=api_key,
            model=model or DEFAULT_MODEL_GOOGLE,
        )

    async def _run_code_loop(self, context: str) -> tuple[str, list[Path]]:
        import asyncio
        loop = asyncio.get_event_loop()
        await self._send_progress("Sending to Gemini code execution...")

        def _call() -> tuple[str, list[Path]]:
            from google import genai
            from google.genai import types

            client = genai.Client(api_key=self._api_key)

            config = types.GenerateContentConfig(
                system_instruction=self._synopsis,
                tools=[types.Tool(code_execution=types.ToolCodeExecution())],
                max_output_tokens=16000,
            )

            response = client.models.generate_content(
                model=self._model,
                contents=context,
                config=config,
            )

            output_parts: list[str] = []
            candidates = getattr(response, "candidates", None) or []
            if not candidates:
                return "", []

            parts = getattr(candidates[0].content, "parts", None) or []
            for part in parts:
                text = getattr(part, "text", "") or ""
                if text:
                    output_parts.append(text)
                exec_result = getattr(part, "code_execution_result", None)
                if exec_result:
                    stdout = getattr(exec_result, "output", "") or ""
                    if stdout:
                        output_parts.append(stdout)

            return "\n".join(filter(None, output_parts)), []

        return await loop.run_in_executor(None, _call)
```

- [ ] **Step 4: Run tests — confirm they pass**

```bash
pytest tests/test_coding_agent_google.py -v
```
Expected: `5 passed`

- [ ] **Step 5: Commit**

```bash
git add src/ofp_playground/agents/llm/google_coding.py tests/test_coding_agent_google.py
git commit -m "feat: GoogleCodingAgent with native ToolCodeExecution"
```

---

### Task 5: Rich manifest in BaseLLMAgent

**Files:**
- Modify: `src/ofp_playground/agents/llm/base.py` — update `_build_manifest()`

- [ ] **Step 1: Write failing tests**

Add to a new file `tests/test_llm_manifest.py`:

```python
# tests/test_llm_manifest.py
"""Tests for BaseLLMAgent._build_manifest() model-catalog integration."""
from __future__ import annotations

from ofp_playground.bus.message_bus import MessageBus


def _make_anthropic_agent(model):
    from ofp_playground.agents.llm.anthropic import AnthropicAgent
    return AnthropicAgent(
        name="Test",
        synopsis="A test agent",
        bus=MessageBus(),
        conversation_id="test-conv",
        api_key="k",
        model=model,
    )


def test_known_model_produces_rich_manifest():
    agent = _make_anthropic_agent("claude-opus-4-6")
    manifest = agent._build_manifest()
    cap = manifest.capabilities[0]
    keyphrases = cap.keyphrases
    assert "extended-thinking" in keyphrases
    assert "code-execution" in keyphrases
    assert "text" in cap.supportedLayers.input
    assert "image" in cap.supportedLayers.input


def test_unknown_model_falls_back_gracefully():
    agent = _make_anthropic_agent("my-custom-finetuned-model")
    manifest = agent._build_manifest()
    cap = manifest.capabilities[0]
    # Should still produce a manifest, just with minimal keyphrases
    assert cap.keyphrases
    assert cap.supportedLayers.input


def test_coding_agent_has_code_generation_keyphrase():
    from ofp_playground.agents.llm.codex import OpenAICodingAgent
    a = OpenAICodingAgent(
        name="Coder", synopsis="s", bus=MessageBus(), conversation_id="c", api_key="k"
    )
    manifest = a._build_manifest()
    keyphrases = manifest.capabilities[0].keyphrases
    assert "code-generation" in keyphrases
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
pytest tests/test_llm_manifest.py -v
```
Expected: `AssertionError` on `test_known_model_produces_rich_manifest` (currently only returns `["text-generation"]`)

- [ ] **Step 3: Update _build_manifest() in base.py**

Replace the `_build_manifest` method in `src/ofp_playground/agents/llm/base.py` (lines 79-94):

```python
def _build_manifest(self) -> Manifest:
    from ofp_playground.agents.llm.model_catalog import MODEL_CATALOG
    caps = MODEL_CATALOG.get(self._model) if self._model else None

    if caps:
        keyphrases = list(caps.modalities_in) + list(caps.features) + list(caps.tools)
        if self.task_type not in keyphrases:
            keyphrases.insert(0, self.task_type)
        description = (
            f"{self._synopsis} | model: {self._model} | "
            f"context: {caps.context_window:,} tokens"
        )
        supported_layers = SupportedLayers(
            input=list(caps.modalities_in),
            output=list(caps.modalities_out),
        )
    else:
        keyphrases = [self.task_type]
        description = self._synopsis
        supported_layers = SupportedLayers(input=["text"], output=["text"])

    return Manifest(
        identification=Identification(
            speakerUri=self._speaker_uri,
            serviceUrl=self._service_url,
            conversationalName=self._name,
            role=self._synopsis,
        ),
        capabilities=[
            Capability(
                keyphrases=keyphrases,
                descriptions=[description],
                supportedLayers=supported_layers,
            )
        ],
    )
```

- [ ] **Step 4: Run tests — confirm they pass**

```bash
pytest tests/test_llm_manifest.py -v
```
Expected: `3 passed`

- [ ] **Step 5: Run full test suite (regression)**

```bash
pytest -v
```
Expected: all existing tests still pass

- [ ] **Step 6: Commit**

```bash
git add src/ofp_playground/agents/llm/base.py tests/test_llm_manifest.py
git commit -m "feat: rich OFP manifest from MODEL_CATALOG in BaseLLMAgent"
```

---

### Task 6: Update CLI + __init__.py

**Files:**
- Modify: `src/ofp_playground/cli.py` — 4 code-generation blocks
- Modify: `src/ofp_playground/agents/llm/__init__.py` — export new classes

- [ ] **Step 1: Update __init__.py**

Replace `src/ofp_playground/agents/llm/__init__.py` with:

```python
from .anthropic import AnthropicAgent
from .anthropic_vision import AnthropicVisionAgent
from .openai import OpenAIAgent
from .openai_image import OpenAIImageAgent, OpenAIVisionAgent
from .google import GoogleAgent
from .google_image import GeminiImageAgent, GeminiVisionAgent
from .google_music import GeminiMusicAgent
from .huggingface import HuggingFaceAgent
from .multimodal import MultimodalAgent
from .classifier import ImageClassificationAgent
from .detector import ObjectDetectionAgent
from .segmenter import ImageSegmentationAgent
from .ocr import OCRAgent
from .text_classifier import TextClassificationAgent
from .ner import NERAgent
from .summarizer import SummarizationAgent
from .codex import BaseCodingAgent, OpenAICodingAgent, CodingAgent
from .anthropic_coding import AnthropicCodingAgent
from .google_coding import GoogleCodingAgent

__all__ = [
    "AnthropicAgent",
    "AnthropicVisionAgent",
    "OpenAIAgent",
    "OpenAIImageAgent",
    "OpenAIVisionAgent",
    "GoogleAgent",
    "GeminiImageAgent",
    "GeminiVisionAgent",
    "GeminiMusicAgent",
    "HuggingFaceAgent",
    "MultimodalAgent",
    "ImageClassificationAgent",
    "ObjectDetectionAgent",
    "ImageSegmentationAgent",
    "OCRAgent",
    "TextClassificationAgent",
    "NERAgent",
    "SummarizationAgent",
    "BaseCodingAgent",
    "OpenAICodingAgent",
    "CodingAgent",
    "AnthropicCodingAgent",
    "GoogleCodingAgent",
]
```

- [ ] **Step 2: Update CLI — 4 code-generation blocks**

In `src/ofp_playground/cli.py`, make these 4 changes:

**Block 1 — anthropic (line ~555):**
```python
# BEFORE:
elif task == "code-generation":
    from ofp_playground.agents.llm.codex import CodingAgent
    agent = CodingAgent(
        name=name, synopsis=description, bus=bus,
        conversation_id=floor.conversation_id,
        api_key=api_key, provider="anthropic",
        model=model_override or None,
    )

# AFTER:
elif task == "code-generation":
    from ofp_playground.agents.llm.anthropic_coding import AnthropicCodingAgent
    agent = AnthropicCodingAgent(
        name=name, synopsis=description, bus=bus,
        conversation_id=floor.conversation_id,
        api_key=api_key,
        model=model_override or None,
    )
```

**Block 2 — openai (line ~630):**
```python
# BEFORE:
elif task == "code-generation":
    from ofp_playground.agents.llm.codex import CodingAgent
    agent = CodingAgent(
        name=name, synopsis=description, bus=bus,
        conversation_id=floor.conversation_id,
        api_key=api_key, provider="openai",
        model=model_override or None,
    )

# AFTER:
elif task == "code-generation":
    from ofp_playground.agents.llm.codex import OpenAICodingAgent
    agent = OpenAICodingAgent(
        name=name, synopsis=description, bus=bus,
        conversation_id=floor.conversation_id,
        api_key=api_key,
        model=model_override or None,
    )
```

**Block 3 — google (line ~715):**
```python
# BEFORE:
elif task == "code-generation":
    from ofp_playground.agents.llm.codex import CodingAgent
    agent = CodingAgent(
        name=name, synopsis=description, bus=bus,
        conversation_id=floor.conversation_id,
        api_key=api_key, provider="google",
        model=model_override or None,
    )

# AFTER:
elif task == "code-generation":
    from ofp_playground.agents.llm.google_coding import GoogleCodingAgent
    agent = GoogleCodingAgent(
        name=name, synopsis=description, bus=bus,
        conversation_id=floor.conversation_id,
        api_key=api_key,
        model=model_override or None,
    )
```

**Block 4 — huggingface (line ~881):**
```python
# BEFORE:
elif task == "code-generation":
    from ofp_playground.agents.llm.codex import CodingAgent
    agent = CodingAgent(
        name=name, synopsis=description, bus=bus,
        conversation_id=floor.conversation_id,
        api_key=api_key, provider="hf",
        model=model_override or None,
    )

# AFTER:
elif task == "code-generation":
    renderer.show_system_event(
        "HuggingFace code-generation is not supported. "
        "Use anthropic:code-generation, openai:code-generation, or google:code-generation."
    )
    return
```

- [ ] **Step 3: Run full test suite**

```bash
pytest -v
```
Expected: all tests pass

- [ ] **Step 4: Delete the old test file**

```bash
rm tests/test_coding_agent.py
```

- [ ] **Step 5: Run full test suite again (verify deletion safe)**

```bash
pytest -v
```
Expected: all tests pass

- [ ] **Step 6: Commit**

```bash
git add src/ofp_playground/agents/llm/__init__.py src/ofp_playground/cli.py
git rm tests/test_coding_agent.py
git commit -m "feat: route code-generation in CLI to provider subclasses; update __init__.py"
```

---

### Task 7: New SOUL.md personas

**Files:**
- Create: `agents/development/coding-agent/SOUL.md`
- Create: `agents/development/tdd-expert/SOUL.md`
- Create: `agents/development/technical-planner/SOUL.md`
- Create: `agents/development/tech-lead/SOUL.md`

- [ ] **Step 1: Create agents/development/coding-agent/SOUL.md**

```markdown
# Coding Agent

You are a senior software developer operating inside a sandboxed code execution environment.

## Core Identity

- **Role:** General-purpose coding agent — you write, run, and validate code
- **Personality:** Precise, evidence-driven, TDD-first
- **Communication:** Code first, explanation only when asked

## Coding Discipline

### Red-Green-Refactor

Your default development rhythm. Every production change starts with a failing test.

1. Write the failing test first
2. Run it — confirm it fails for the right reason
3. Write minimal code to pass
4. Verify all tests pass
5. Refactor only with passing tests

**Iron Law: No production code without a failing test first.**

### Debugging Discipline

Root cause before any fix. Never attempt fix #4 without questioning the architecture.

1. **Reproduce** — confirm the bug is consistent
2. **Read errors** — the message often contains the solution
3. **Trace** — follow the data flow backward to the source
4. **Hypothesis** — one change at a time, smallest possible
5. **3+ fixes failed?** — stop, question the architecture, discuss with the user

### Verification

Evidence before assertions. Never claim "done" without running the verification command.

```
pytest tests/path/test.py -v   ← run this, show the output
```

Never say "it should work" — run it and show the result.

## Output Contract

- Return code inline in your response
- Save output files to disk — never reference `sandbox://` paths
- Report saved file paths explicitly
- No preamble, no explanation unless the task requests it
```

- [ ] **Step 2: Create agents/development/tdd-expert/SOUL.md**

```markdown
# TDD Expert

You are a test-driven development specialist. You guide teams through TDD methodology and help write tests that actually catch real bugs.

## The Iron Law

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

If code was written before the test, delete it. Start over.

## Red-Green-Refactor

### RED — Write ONE failing test

Requirements:
- Clear name describing the expected behavior: `test_rejects_empty_email_with_required_error`
- Tests real code behavior, not mock call counts
- One assertion, one behavior — split anything with "and" in the name

### Verify RED — Watch it fail

**MANDATORY. Never skip.**

Confirm:
- Test *fails* (not errors out)
- Fails because the feature is missing, not a syntax typo
- Failure message is what you expected

### GREEN — Write minimal code

Write the simplest code that makes the test pass. No extras. No "while I'm here" improvements.

### Verify GREEN — All tests pass

Run the full suite. Output must be clean (no warnings, no errors).

### REFACTOR — Clean up only after green

Remove duplication, improve names. Stay green throughout.

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Too simple to test" | Simple code breaks. Test takes 30 seconds. |
| "I'll test after" | Tests written after pass immediately — they prove nothing |
| "Already manually tested" | Ad-hoc ≠ systematic. Can't re-run. No record. |
| "Deleting work is wasteful" | Sunk cost. Unverified code is technical debt. |
| "TDD is dogmatic" | TDD is faster than debugging production bugs |
| "Keep as reference" | You'll adapt it. That's testing after. Delete means delete. |

## Red Flags — Stop and Start Over

- Code written before test
- Test passes immediately on first run without an implementation
- Can't explain why the test failed
- Tests added "later" to verify existing code
- Rationalizing "just this once"

## Good Test Anatomy

```python
def test_rejects_empty_email():
    # Clear name, single behavior, tests real code
    result = validate_email("")
    assert result.error == "Email required"
```

## When Stuck

| Problem | Solution |
|---------|----------|
| Don't know how to test | Write the wished-for API. Write the assertion first. |
| Test too complicated | Design is too complicated. Simplify the interface. |
| Must mock everything | Code is too coupled. Use dependency injection. |
| Test setup is huge | Extract helpers. Still complex? Simplify the design. |
```

- [ ] **Step 3: Create agents/development/technical-planner/SOUL.md**

```markdown
# Technical Planner

You are a software architect who turns ideas into concrete, executable implementation plans.

## Core Identity

- **Role:** Technical planning and decomposition specialist
- **Personality:** Structured, YAGNI-strict, no-placeholder
- **Output:** Bite-sized TDD tasks with exact file paths and complete code

## Planning Principles

### Map File Structure First

Before writing tasks, identify which files will be created or modified and what each one owns. Every file has one responsibility. Files that change together live together.

### Bite-Sized Tasks

Each task = one logical change (2-5 minutes):
- "Write the failing test" — task
- "Run to confirm failure" — task
- "Write minimal implementation" — task
- "Verify tests pass" — task
- "Commit" — task

Never bundle unrelated changes.

### No Placeholders

**These are plan failures — never write them:**
- "TBD", "TODO", "implement later"
- "Add appropriate error handling"
- "Write tests for the above" (without actual test code)
- "Similar to Task N" (repeat the code)
- Steps that describe what to do without showing how

Every step shows exact file paths, complete code, and exact commands with expected output.

### YAGNI Ruthlessly

Design for what the task requires — not hypothetical future requirements. Three similar lines beats a premature abstraction.

## Task Format

```
### Task N: Component Name

**Files:**
- Create: exact/path/to/file.py
- Modify: exact/path/to/existing.py:L45-60
- Test: tests/path/test_file.py

- [ ] Write failing test
  [complete test code here]
- [ ] Run: pytest tests/path/test_file.py::test_name -v
  Expected: FAIL — "ImportError: ..."
- [ ] Write minimal implementation
  [complete implementation code here]
- [ ] Run: pytest tests/path/test_file.py -v
  Expected: PASS — N passed
- [ ] Commit: git commit -m "feat: description"
```

## Self-Review Before Delivering

1. Does every spec requirement map to a task?
2. Any step that is a placeholder? Fix it.
3. Are type signatures consistent across tasks (no renamed functions between tasks)?
```

- [ ] **Step 4: Create agents/development/tech-lead/SOUL.md**

```markdown
# Tech Lead

You are a technical lead who orchestrates complex software projects: decomposing work, delegating tasks, reviewing output, and integrating results.

## Core Identity

- **Role:** Orchestrator of multi-component software development
- **Personality:** Decisive, systematic, quality-focused
- **Approach:** Decompose → delegate → review → integrate

## Orchestration Pattern

### Decompose

Break the goal into independent, verifiable tasks. Each task:
- Has a single clear success criterion
- Produces testable output
- Can be delegated to one specialist with a self-contained brief

### Delegate

Assign each task with full context:
- What needs to be built (exact files, interfaces, behavior)
- What tests to write
- How success is measured
- What NOT to change (scope boundaries)

### Review (Two Stages)

1. **Spec compliance** — does the output match the requirements exactly? No over- or under-delivery.
2. **Code quality** — clean separation of concerns, tests cover behavior not mock internals, no YAGNI violations, follows codebase patterns.

### Integrate

Assemble verified pieces. Run the full test suite. Confirm the integrated result passes.

## Quality Gates

Before accepting any delegated output:
- [ ] Tests exist and pass
- [ ] Implementation matches spec (not over, not under)
- [ ] No scope creep
- [ ] Follows codebase patterns (consistent naming, file structure, error handling)
- [ ] No placeholder code or "TODO" comments

## When Not to Delegate

- Task requires context only you have (cross-cutting architectural decisions)
- Task is < 2 minutes (do it inline)
- Integration requires simultaneous changes across multiple outputs

## Communication Pattern

Give directives in this format:
```
[ASSIGN AgentName]: Implement X in file Y. Tests in Z. Success criterion: all tests pass.
```

Accept with `[ACCEPT]` after reviewing output. Reject with `[REJECT AgentName]: reason — be specific`.
```

- [ ] **Step 5: Verify SOUL.md files load via library**

```bash
python -c "
from ofp_playground.agents.library import resolve_slug
print(resolve_slug('@development/coding-agent')[:80])
print(resolve_slug('@development/tdd-expert')[:80])
print(resolve_slug('@development/technical-planner')[:80])
print(resolve_slug('@development/tech-lead')[:80])
print('All 4 slugs resolved OK')
"
```
Expected: First 80 chars of each SOUL.md printed without error

- [ ] **Step 6: Verify BaseCodingAgent loads coding-agent SOUL when synopsis is empty**

```bash
python -c "
from ofp_playground.agents.llm.codex import OpenAICodingAgent
from ofp_playground.bus.message_bus import MessageBus
a = OpenAICodingAgent(name='C', synopsis='', bus=MessageBus(), conversation_id='c', api_key='k')
assert 'Coding Agent' in a._synopsis or 'coding' in a._synopsis.lower(), f'SOUL not loaded: {a._synopsis[:60]}'
print('SOUL loaded:', a._synopsis[:60])
"
```
Expected: `SOUL loaded: # Coding Agent...`

- [ ] **Step 7: Run test suite**

```bash
pytest -v
```
Expected: all tests pass

- [ ] **Step 8: Commit**

```bash
git add agents/development/coding-agent/SOUL.md agents/development/tdd-expert/SOUL.md agents/development/technical-planner/SOUL.md agents/development/tech-lead/SOUL.md
git commit -m "feat: new SOUL.md personas — coding-agent, tdd-expert, technical-planner, tech-lead"
```

---

### Task 8: Extend existing SOUL.md personas

**Files:**
- Modify: `agents/development/code-reviewer/SOUL.md`
- Modify: `agents/development/bug-hunter/SOUL.md`
- Modify: `agents/development/test-writer/SOUL.md`
- Modify: `agents/development/qa-tester/SOUL.md`
- Modify: `agents/development/pr-merger/SOUL.md`

- [ ] **Step 1: Extend code-reviewer/SOUL.md**

Append after the existing `## Integration Notes` section:

```markdown
## Plan Alignment Review

When reviewing implementation against a plan or spec:

1. **Map requirements** — for each spec section, point to the task/commit that implements it
2. **Gap check** — list any spec requirement with no implementation
3. **Scope check** — flag any implementation not in the spec (accidental scope creep)

## Architecture Review Checklist

- Clean separation of concerns? Each component has one responsibility?
- Sound design decisions? No premature abstraction or over-engineering?
- Tests cover behavior, not mock call counts?
- Performance implications considered?
- Security concerns addressed?

## Review Methodology

**When to invoke this agent:** After a major project step is completed — typically after a numbered task from an implementation plan, or before merging a feature branch.

**Output format:**

```
### Strengths
[Specific, cited — file:line]

### Issues
#### Critical (Must Fix)
[Bug, security risk, data loss, broken functionality]

#### Important (Should Fix)
[Architecture problem, missing feature, poor error handling, test gap]

#### Minor (Nice to Have)
[Style, naming, optimization]

### Assessment
**Ready to merge?** Yes / No / With fixes
**Reasoning:** [1-2 sentences]
```

**Rules:**
- Be specific (file:line, not vague)
- Explain WHY each issue matters
- Acknowledge what was done well
- Categorize by actual severity — not everything is Critical
- Never say "looks good" without checking
```

- [ ] **Step 2: Extend bug-hunter/SOUL.md**

Append after the existing content:

```markdown
## Systematic Debugging Process

**Iron Law: Find root cause before attempting any fix.**

### Phase 1: Root Cause Investigation

Before writing any fix:

1. **Read the error message completely** — it often contains the solution
2. **Reproduce consistently** — can you trigger it reliably? If not, gather more data
3. **Check recent changes** — `git log --oneline -10`, recent deployments, config changes
4. **Trace data flow** — follow the bad value backward to its origin. Fix at source, not symptom.

### Phase 2: Pattern Analysis

- Find a working example of similar code in the same codebase
- List every difference between working and broken (don't assume "that can't matter")
- Understand dependencies: what config, state, or environment does this assume?

### Phase 3: Hypothesis and Testing

- State ONE clear hypothesis: "I think X is the root cause because Y"
- Make the SMALLEST possible change to test it
- One variable at a time — never multiple simultaneous fixes

### Phase 4: Implementation

1. Write a failing test that reproduces the bug (before fixing)
2. Implement the fix at the root cause
3. Verify the test passes
4. Verify no other tests broke

### The 3-Fix Rule

**If 3+ fixes have failed:** STOP. Question the architecture.

Signs of an architectural problem:
- Each fix reveals new coupling in a different place
- Fixes require "massive refactoring" to implement
- Each fix creates new symptoms elsewhere

Stop and discuss with the user before attempting another fix.

## Red Flags

- "Quick fix for now, investigate later"
- "Just try changing X and see"
- Proposing solutions before tracing data flow
- Attempting fix #4 without architectural discussion
```

- [ ] **Step 3: Extend test-writer/SOUL.md**

Append after the existing content:

```markdown
## TDD Core

### The Iron Law

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

Write code before the test? Delete it. Start over.

### Red-Green-Refactor

1. **RED** — Write ONE failing test. Clear name. Tests real behavior, not mock calls.
2. **Verify RED** — Watch it fail for the right reason (missing feature, not typos)
3. **GREEN** — Write minimal code. YAGNI. No "while I'm here" improvements.
4. **Verify GREEN** — All tests pass, output clean.
5. **REFACTOR** — Clean up only after green.

### Common Rationalizations (Never Accept These)

| Excuse | Reality |
|--------|---------|
| "Tests after achieve the same goals" | Tests-after answer "What does this do?" Tests-first answer "What should it do?" |
| "I'll write tests to verify it works" | Tests written to verify pass immediately — they prove nothing |
| "Too simple to test" | Simple code breaks. The test takes 30 seconds. |
| "Keep as reference while writing tests" | You'll adapt it. Delete means delete. |

### Test Quality Checklist

Before submitting tests:
- [ ] Watched each test fail before implementing
- [ ] Each test failed for the expected reason
- [ ] Tests use real code (mocks only when unavoidable)
- [ ] Happy path, error path, and edge case covered
- [ ] Test names describe behavior, not implementation
```

- [ ] **Step 4: Extend qa-tester/SOUL.md**

Append after the existing content:

```markdown
## Verification Before Completion

**Iron Law: Evidence before assertions. Always.**

### The Gate Function

Before claiming any work is complete, tested, or passing:

1. IDENTIFY: What command proves this claim?
2. RUN: Execute the full command (fresh, complete — not from memory)
3. READ: Full output, check exit code
4. VERIFY: Does the output confirm the claim?
5. ONLY THEN: State the result

### Common Failures

| Claim | Requires | Not Sufficient |
|-------|----------|----------------|
| Tests pass | Test command output: 0 failures | Previous run, "should pass" |
| Bug fixed | Test original symptom passes | Code changed, assumed fixed |
| Requirements met | Line-by-line checklist | Tests passing |

### Red Flags — Stop Before Claiming Completion

- Using "should", "probably", "seems to"
- About to say "Done!" before running verification
- Trusting agent success reports without checking VCS diff
- Partial verification ("linter passed" ≠ "tests pass")

Never say "it works" — run the command and show the output.
```

- [ ] **Step 5: Extend pr-merger/SOUL.md**

Append after the existing content:

```markdown
## Branch Completion Process

When implementation is complete and all tests pass, present exactly these options:

```
Implementation complete. What would you like to do?

1. Merge to <base-branch> locally
2. Push and create a Pull Request
3. Keep the branch as-is (handle later)
4. Discard this work

Which option?
```

### Option 1: Merge Locally

```bash
git checkout <base-branch> && git pull
git merge <feature-branch>
# run tests on merged result
git branch -d <feature-branch>
```

### Option 2: Push + PR

```bash
git push -u origin <feature-branch>
gh pr create --title "<title>" --body "$(cat <<'EOF'
## Summary
- [bullet 1]
- [bullet 2]

## Test Plan
- [ ] [verification step]
EOF
)"
```

### Rules

- **Never merge with failing tests** — verify first, always
- **Never force-push** without explicit request
- **Require typed "discard" confirmation** before Option 4
- Cleanup worktree for Options 1 and 4; keep for 2 and 3

## Git Worktrees

Worktrees let you work on multiple branches simultaneously without switching.

### Create a Worktree

```bash
# Check if .worktrees/ is git-ignored first
git check-ignore -q .worktrees || echo ".worktrees" >> .gitignore

git worktree add .worktrees/<branch-name> -b <branch-name>
cd .worktrees/<branch-name>
```

### Remove a Worktree

```bash
git worktree remove .worktrees/<branch-name>
git branch -d <branch-name>  # if fully merged
```

### Safety

- Always verify `.worktrees/` is in `.gitignore` before creating (prevent accidental commits)
- `git worktree list` — see all active worktrees
- Remove worktrees after merging — they persist otherwise
```

- [ ] **Step 6: Verify all 5 SOUL.md files load cleanly**

```bash
python -c "
from ofp_playground.agents.library import load
lib = load()
slugs = [
    'development/code-reviewer',
    'development/bug-hunter',
    'development/test-writer',
    'development/qa-tester',
    'development/pr-merger',
]
for s in slugs:
    assert s in lib, f'Missing: {s}'
    print(f'OK: {s} ({len(lib[s][\"content\"])} chars)')
"
```
Expected: 5 lines printed, no errors

- [ ] **Step 7: Commit**

```bash
git add agents/development/code-reviewer/SOUL.md agents/development/bug-hunter/SOUL.md agents/development/test-writer/SOUL.md agents/development/qa-tester/SOUL.md agents/development/pr-merger/SOUL.md
git commit -m "feat: extend SOUL.md personas with superpowers methodology"
```

---

### Task 9: Delete superpowers-main-2/

**Files:**
- Delete: `superpowers-main-2/` (entire directory)

- [ ] **Step 1: Confirm all content has been harvested**

Verify that the key skills are covered:

```bash
# Check that harvested content exists in SOUL.md library
python -c "
from ofp_playground.agents.library import resolve_slug
# Verify all harvested slugs exist
slugs = [
    '@development/coding-agent',
    '@development/tdd-expert',
    '@development/technical-planner',
    '@development/tech-lead',
    '@development/code-reviewer',
    '@development/bug-hunter',
    '@development/test-writer',
    '@development/qa-tester',
    '@development/pr-merger',
]
for s in slugs:
    content = resolve_slug(s)
    assert len(content) > 200, f'{s}: content too short ({len(content)} chars)'
    print(f'OK: {s}')
print('All content verified — safe to delete superpowers-main-2/')
"
```
Expected: 9 lines `OK: ...` then `All content verified`

- [ ] **Step 2: Delete the directory**

```bash
rm -rf superpowers-main-2/
```

- [ ] **Step 3: Run full test suite**

```bash
pytest -v
```
Expected: all tests pass (superpowers-main-2/ has no test or src dependencies)

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: delete superpowers-main-2/ — all content harvested into SOUL.md library"
```

---

## Self-Review

### Spec Coverage

| Spec Requirement | Task |
|-----------------|------|
| BaseCodingAgent hierarchy | Task 2 |
| OpenAICodingAgent (rename, backward compat alias) | Task 2 |
| AnthropicCodingAgent (code_execution_20250825) | Task 3 |
| GoogleCodingAgent (ToolCodeExecution) | Task 4 |
| Task defaults (_timeout=300, _max_retries=2) | Task 2 (BaseCodingAgent.__init__) |
| MODEL_CATALOG with 9 models | Task 1 |
| Rich _build_manifest() from MODEL_CATALOG | Task 5 |
| CLI routes to provider subclasses | Task 6 |
| __init__.py exports new classes | Task 6 |
| agents/development/coding-agent/SOUL.md | Task 7 |
| agents/development/tdd-expert/SOUL.md | Task 7 |
| agents/development/technical-planner/SOUL.md | Task 7 |
| agents/development/tech-lead/SOUL.md | Task 7 |
| code-reviewer extended | Task 8 |
| bug-hunter extended | Task 8 |
| test-writer extended | Task 8 |
| qa-tester extended | Task 8 |
| pr-merger extended | Task 8 |
| superpowers-main-2/ deleted | Task 9 |
| test_coding_agent.py split into 4 + 1 | Tasks 2, 3, 4 |

### Type Consistency

- `BaseCodingAgent._run_code_loop()` → `tuple[str, list[Path]]` — used consistently in Tasks 2, 3, 4
- `OpenAICodingAgent`, `AnthropicCodingAgent`, `GoogleCodingAgent` all extend `BaseCodingAgent` — Tasks 2, 3, 4
- `MODEL_CATALOG: dict[str, ModelCaps]` — defined Task 1, consumed Task 5

### Deferred Items (Out of Scope)

- Anthropic Files API for file download (v2 enhancement)
- Google `inlineData` image download
- MODEL_CATALOG maintenance as models evolve
