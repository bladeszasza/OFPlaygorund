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
    # Should still produce a manifest with minimal keyphrases
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
