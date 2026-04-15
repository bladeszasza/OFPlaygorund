# tests/test_coding_agent_openai.py
"""Tests for OpenAICodingAgent — OpenAI Responses API + code_interpreter."""
from __future__ import annotations

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
