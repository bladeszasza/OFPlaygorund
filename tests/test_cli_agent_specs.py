from __future__ import annotations

from ofp_playground import cli


def test_resolve_agent_slug_with_trailing_instructions(monkeypatch):
    import ofp_playground.agents.library as library

    def fake_resolve_slug(ref: str) -> str:
        if ref == "@development/threejs-developer":
            return "BASE SOUL"
        raise ValueError(f"Agent not found: {ref}")

    monkeypatch.setattr(library, "resolve_slug", fake_resolve_slug)

    resolved = cli._resolve_agent_slug(
        "@development/threejs-developer. Write actual workspace files index.html and main.js."
    )

    assert resolved == (
        "BASE SOUL\n\n"
        "Additional instructions:\n"
        "Write actual workspace files index.html and main.js."
    )


def test_parse_agent_spec_allows_slug_prefix_with_extra_text(monkeypatch):
    import ofp_playground.agents.library as library

    def fake_resolve_slug(ref: str) -> str:
        if ref == "@development/threejs-developer":
            return "BASE SOUL"
        raise ValueError(f"Agent not found: {ref}")

    monkeypatch.setattr(library, "resolve_slug", fake_resolve_slug)

    agent_type, name, description, model_override, _, _, _ = cli._parse_agent_spec(
        "-provider openai -name DevGamma -system @development/threejs-developer. Keep hero.z at 0. -model gpt-5.4"
    )

    assert agent_type == "openai"
    assert name == "DevGamma"
    assert description.startswith("BASE SOUL\n\nAdditional instructions:\nKeep hero.z at 0.")
    assert model_override == "gpt-5.4"