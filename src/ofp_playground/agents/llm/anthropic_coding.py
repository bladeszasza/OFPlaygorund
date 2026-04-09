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
