# tests/test_coding_agent_google.py
"""Tests for GoogleCodingAgent — ToolCodeExecution."""
from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock, patch

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
    agent.send_private_utterance = AsyncMock()

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
    assert tools, "tools list is empty"


@pytest.mark.asyncio
async def test_code_execution_output_extracted(tmp_path):
    """code_execution_result.output parts are included in the returned text."""
    agent = _make_agent(tmp_path)
    agent.send_private_utterance = AsyncMock()

    # Create parts that simulate Gemini response
    text_part = MagicMock()
    text_part.text = "Running code..."
    # Make sure hasattr checks work correctly
    del text_part.code_execution_result

    exec_part = MagicMock()
    exec_part.text = ""
    exec_result = MagicMock()
    exec_result.output = "hello world\n"
    exec_part.code_execution_result = exec_result

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
