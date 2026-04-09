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


class BaseCodingAgent(BaseLLMAgent, abc.ABC):
    """Abstract base for all coding agents.

    Shared: directive parsing, _send_progress, _send_final_and_yield,
            _build_context, output dir, task defaults, SOUL loading.
    Abstract: _run_code_loop(context) -> tuple[str, list[Path]]
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
        # Task defaults — code execution is expensive and slow
        self._timeout = 300.0
        self._max_retries = 2
        self._task_directive: str = ""
        self._output_dir: Path = OUTPUT_DIR

    @property
    def task_type(self) -> str:
        return "code-generation"

    async def _generate_response(self, participants):
        raise NotImplementedError("CodingAgent subclasses override _handle_grant_floor directly")

    async def _quick_check(self, prompt: str) -> str:
        return "NO"

    @abc.abstractmethod
    async def _run_code_loop(self, context: str) -> tuple[str, list[Path]]:
        """Provider-specific code-execution loop. Returns (output_text, saved_files)."""

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
                request_kwargs["tools"] = [{"type": "code_interpreter", "container": CODE_INTERPRETER_CONTAINER}]  # type: ignore[assignment]
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
        self._output_dir.mkdir(parents=True, exist_ok=True)
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
