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
