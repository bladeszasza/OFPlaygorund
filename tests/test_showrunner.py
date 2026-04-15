from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest

from ofp_playground.agents.llm.showrunner import (
    ORCHESTRATOR_MAX_OUTPUT_TOKENS,
    OpenAIOrchestratorAgent,
)
from ofp_playground.bus.message_bus import MessageBus
from ofp_playground.memory.store import MemoryStore


def _make_openai_orchestrator() -> OpenAIOrchestratorAgent:
    return OpenAIOrchestratorAgent(
        name="Showrunner",
        mission="Ship the scene.",
        bus=MessageBus(),
        conversation_id="conv:test-showrunner",
        api_key="test-key",
        model="gpt-5.4",
    )


def _message_item(text: str) -> SimpleNamespace:
    return SimpleNamespace(
        type="message",
        content=[SimpleNamespace(text=text)],
    )


@pytest.mark.asyncio
async def test_openai_orchestrator_skips_malformed_tool_arguments_first_pass():
    agent = _make_openai_orchestrator()
    response = SimpleNamespace(
        output=[
            SimpleNamespace(
                type="function_call",
                name="create_coding_session",
                arguments='{"policy":"round_robin',
                call_id="call-1",
            ),
            _message_item("[TASK_COMPLETE]"),
        ]
    )

    mock_client = MagicMock()
    mock_client.responses.create = MagicMock(return_value=response)
    agent._get_client = MagicMock(return_value=mock_client)

    result = await agent._generate_response([])

    assert result == "[TASK_COMPLETE]"
    assert mock_client.responses.create.call_count == 1
    assert (
        mock_client.responses.create.call_args.kwargs["max_output_tokens"]
        == ORCHESTRATOR_MAX_OUTPUT_TOKENS
    )


@pytest.mark.asyncio
async def test_openai_orchestrator_skips_malformed_tool_arguments_second_pass():
    agent = _make_openai_orchestrator()
    agent._memory_store = MemoryStore()

    response1 = SimpleNamespace(
        output=[
            SimpleNamespace(
                type="function_call",
                name="recall_memory",
                arguments="{}",
                call_id="call-recall",
            ),
        ]
    )
    response2 = SimpleNamespace(
        output=[
            SimpleNamespace(
                type="function_call",
                name="create_coding_session",
                arguments='{"policy":"round_robin',
                call_id="call-2",
            ),
            _message_item("Continue to the next phase."),
        ]
    )

    mock_client = MagicMock()
    mock_client.responses.create = MagicMock(side_effect=[response1, response2])
    agent._get_client = MagicMock(return_value=mock_client)

    result = await agent._generate_response([])

    assert result == "Continue to the next phase."
    assert mock_client.responses.create.call_count == 2