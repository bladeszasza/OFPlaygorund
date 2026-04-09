# src/ofp_playground/agents/llm/google_coding.py
"""GoogleCodingAgent — native ToolCodeExecution via google.genai."""
from __future__ import annotations

import logging
import re
from datetime import datetime
from pathlib import Path
from typing import Optional

from ofp_playground.agents.llm.codex import BaseCodingAgent
from ofp_playground.bus.message_bus import MessageBus

logger = logging.getLogger(__name__)

DEFAULT_MODEL_GOOGLE = "gemini-3-flash-preview"

_CODE_BLOCK_RE = re.compile(r"```(\w+)?\n(.*?)```", re.DOTALL)
_EXT_MAP = {
    "html": ".html",
    "python": ".py", "py": ".py",
    "javascript": ".js", "js": ".js",
    "typescript": ".ts", "ts": ".ts",
    "css": ".css",
    "sql": ".sql",
    "bash": ".sh", "sh": ".sh",
    "json": ".json",
    "xml": ".xml",
    "yaml": ".yaml", "yml": ".yml",
}


def _save_code_blocks(text: str, output_dir: Path, agent_name: str) -> list[Path]:
    """Extract fenced code blocks from *text* and write each to *output_dir*."""
    saved: list[Path] = []
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    slug = re.sub(r"[^\w]+", "_", agent_name.lower())
    output_dir.mkdir(parents=True, exist_ok=True)
    for i, m in enumerate(_CODE_BLOCK_RE.finditer(text)):
        lang = (m.group(1) or "").lower().strip()
        code = m.group(2).strip()
        if not code:
            continue
        ext = _EXT_MAP.get(lang, ".txt")
        suffix = f"_{i + 1}" if i > 0 else ""
        path = output_dir / f"{ts}_{slug}{suffix}{ext}"
        path.write_text(code, encoding="utf-8")
        saved.append(path)
    return saved


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
        loop = asyncio.get_running_loop()
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
                model=self._model or DEFAULT_MODEL_GOOGLE,
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

            output_text = "\n".join(filter(None, output_parts))
            saved = _save_code_blocks(output_text, self._output_dir, self._name)
            return output_text, saved

        return await loop.run_in_executor(None, _call)
