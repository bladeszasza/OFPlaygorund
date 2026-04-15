# tests/test_coding_agent_anthropic.py
"""Tests for AnthropicCodingAgent — code_execution_20250825 beta tool."""
from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock, patch

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


def _make_mock_client(response=None):
    """Build an AsyncAnthropic mock matching client.beta.messages.create()."""
    if response is None:
        response = MagicMock()
        response.content = []
        response.stop_reason = "end_turn"
    mock_beta_messages = MagicMock()
    mock_beta_messages.create = AsyncMock(return_value=response)
    mock_beta = MagicMock()
    mock_beta.messages = mock_beta_messages
    mock_client = MagicMock()
    mock_client.beta = mock_beta
    mock_client.close = AsyncMock()
    return mock_client


@pytest.mark.asyncio
async def test_code_execution_tool_injected(tmp_path):
    """code_execution_20250825 tool must appear in the API request."""
    agent = _make_agent(tmp_path)
    agent.send_private_utterance = AsyncMock()

    captured_kwargs: dict = {}
    original_return = MagicMock()
    original_return.content = []
    original_return.stop_reason = "end_turn"

    async def _fake_create(**kwargs):
        captured_kwargs.update(kwargs)
        return original_return

    mock_client = _make_mock_client()
    mock_client.beta.messages.create = AsyncMock(side_effect=_fake_create)

    with patch("anthropic.AsyncAnthropic", return_value=mock_client):
        await agent._run_code_loop("Write hello world in Python.")

    tools = captured_kwargs.get("tools", [])
    assert any(t.get("type") == "code_execution_20250825" for t in tools), (
        f"code_execution_20250825 not found in tools: {tools}"
    )


@pytest.mark.asyncio
async def test_file_tools_injected(tmp_path):
    """File tools (list_workspace, read_file, write_file, edit_file) are injected."""
    agent = _make_agent(tmp_path)
    agent.send_private_utterance = AsyncMock()

    captured_kwargs: dict = {}
    original_return = MagicMock()
    original_return.content = []
    original_return.stop_reason = "end_turn"

    async def _fake_create(**kwargs):
        captured_kwargs.update(kwargs)
        return original_return

    mock_client = _make_mock_client()
    mock_client.beta.messages.create = AsyncMock(side_effect=_fake_create)

    with patch("anthropic.AsyncAnthropic", return_value=mock_client):
        await agent._run_code_loop("Write hello world.")

    tools = captured_kwargs.get("tools", [])
    tool_names = {t.get("name") for t in tools}
    for expected in ("list_workspace", "read_file", "write_file", "edit_file"):
        assert expected in tool_names, f"{expected} missing from tools: {tool_names}"


@pytest.mark.asyncio
async def test_stdout_extracted_from_bash_result(tmp_path):
    """stdout text from bash_code_execution_tool_result blocks is captured."""
    agent = _make_agent(tmp_path)
    agent.send_private_utterance = AsyncMock()

    text_block = MagicMock()
    text_block.type = "text"
    text_block.text = "Here is the output:"

    exec_result = MagicMock()
    exec_result.type = "bash_code_execution_tool_result"
    stdout_content = MagicMock()
    stdout_content.type = "text"
    stdout_content.text = "hello world\n"
    exec_result.content = [stdout_content]

    mock_response = MagicMock()
    mock_response.content = [text_block, exec_result]
    mock_response.stop_reason = "end_turn"

    mock_client = _make_mock_client(mock_response)

    with patch("anthropic.AsyncAnthropic", return_value=mock_client):
        output, saved = await agent._run_code_loop("Write hello world.")

    assert "hello world" in output
