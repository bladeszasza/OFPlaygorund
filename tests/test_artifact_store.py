"""Tests for the Phase Artifact Store and artifact tools."""
from __future__ import annotations

import pytest
from pathlib import Path
from ofp_playground.memory.artifact_store import ArtifactStore, _slugify, _generate_summary
from ofp_playground.memory.artifact_tools import (
    build_artifact_tools,
    execute_artifact_tool,
)


# ── Helpers ──────────────────────────────────────────────────────────────────


class TestSlugify:
    def test_camel_case(self):
        assert _slugify("GeomBuilder") == "geom-builder"

    def test_spaces(self):
        assert _slugify("Asset Director") == "asset-director"

    def test_already_lowered(self):
        assert _slugify("texture-gen") == "texture-gen"

    def test_empty(self):
        assert _slugify("") == "phase"


class TestGenerateSummary:
    def test_first_line(self):
        content = "## Asset Manifest\n\nThis is the manifest for 9 assets."
        summary = _generate_summary(content)
        assert "9 assets" in summary

    def test_skips_headers(self):
        content = "# Phase 1\n---\nThe actual content starts here."
        summary = _generate_summary(content)
        assert summary.startswith("The actual content")

    def test_truncates_long(self):
        content = "A" * 200
        summary = _generate_summary(content, max_chars=50)
        assert len(summary) <= 50
        assert summary.endswith("...")

    def test_skips_table_separators(self):
        content = "| --- | --- |\n| A | B |"
        summary = _generate_summary(content)
        assert "---" not in summary


# ── ArtifactStore ────────────────────────────────────────────────────────────


class TestArtifactStore:
    @pytest.fixture
    def store(self, tmp_path):
        return ArtifactStore(tmp_path)

    def test_save_creates_file(self, store, tmp_path):
        art = store.save(
            agent_name="AssetDirector",
            content="9 assets defined.",
            summary="Asset manifest with 9 entries",
        )
        assert art.phase_num == 1
        assert art.slug == "asset-director"
        assert art.file_path.exists()
        assert "9 assets defined." in art.file_path.read_text()

    def test_save_auto_increments(self, store):
        store.save(agent_name="A", content="first")
        store.save(agent_name="B", content="second")
        assert store.phase_count == 2
        arts = store.all_artifacts()
        assert arts[0].phase_num == 1
        assert arts[1].phase_num == 2

    def test_save_auto_summary(self, store):
        art = store.save(agent_name="X", content="Hello world, this is the output.")
        assert art.summary  # non-empty
        assert "Hello world" in art.summary

    def test_save_custom_slug(self, store):
        art = store.save(agent_name="X", content="c", slug="custom-slug")
        assert art.slug == "custom-slug"
        assert "custom-slug" in art.file_path.name

    def test_read_by_slug(self, store):
        store.save(agent_name="GeomBuilder", content="function buildHero() {}")
        result = store.read("geom-builder")
        assert result == "function buildHero() {}"

    def test_read_by_phase_number(self, store):
        store.save(agent_name="A", content="alpha")
        store.save(agent_name="B", content="beta")
        assert store.read("2") == "beta"

    def test_read_by_substring(self, store):
        store.save(agent_name="TextureDir", content="canvas2D textures")
        assert store.read("texture") == "canvas2D textures"

    def test_read_not_found(self, store):
        assert store.read("nonexistent") is None

    def test_get_index_empty(self, store):
        assert store.get_index() == ""

    def test_get_index_format(self, store):
        store.save(agent_name="AssetDirector", content="9 assets")
        store.save(agent_name="GeomBuilder", content="build functions")
        index = store.get_index()
        assert "PHASE ARTIFACTS (2 completed)" in index
        assert "AssetDirector" in index
        assert "GeomBuilder" in index
        assert "read_artifact" in index

    def test_latest(self, store):
        store.save(agent_name="A", content="first")
        store.save(agent_name="B", content="second")
        latest = store.latest()
        assert latest.agent_name == "B"

    def test_latest_empty(self, store):
        assert store.latest() is None

    def test_frontmatter_written(self, store):
        art = store.save(agent_name="X", content="payload", summary="test summary")
        text = art.file_path.read_text()
        assert "---" in text
        assert 'summary: "test summary"' in text
        assert "phase: 1" in text

    def test_read_with_header(self, store):
        store.save(agent_name="X", content="payload")
        full = store.read_with_header("1")
        assert full.startswith("---")
        assert "payload" in full


# ── Artifact Tools ───────────────────────────────────────────────────────────


class TestArtifactTools:
    def test_tool_definitions(self):
        tools = build_artifact_tools()
        assert len(tools) == 2
        names = [t["name"] for t in tools]
        assert "read_artifact" in names
        assert "list_artifacts" in names

    def test_read_artifact_tool(self, tmp_path):
        store = ArtifactStore(tmp_path)
        store.save(agent_name="GeomBuilder", content="function buildHero() {}")
        result = execute_artifact_tool("read_artifact", {"query": "geom"}, store)
        assert "function buildHero()" in result

    def test_read_artifact_not_found(self, tmp_path):
        store = ArtifactStore(tmp_path)
        result = execute_artifact_tool("read_artifact", {"query": "nope"}, store)
        assert "No artifact found" in result

    def test_read_artifact_missing_query(self, tmp_path):
        store = ArtifactStore(tmp_path)
        result = execute_artifact_tool("read_artifact", {}, store)
        assert "missing" in result

    def test_list_artifacts_tool(self, tmp_path):
        store = ArtifactStore(tmp_path)
        store.save(agent_name="A", content="alpha")
        result = execute_artifact_tool("list_artifacts", {}, store)
        assert "PHASE ARTIFACTS" in result

    def test_list_artifacts_empty(self, tmp_path):
        store = ArtifactStore(tmp_path)
        result = execute_artifact_tool("list_artifacts", {}, store)
        assert "No phase artifacts" in result

    def test_unknown_tool(self, tmp_path):
        store = ArtifactStore(tmp_path)
        result = execute_artifact_tool("bad_tool", {}, store)
        assert "Unknown" in result


# ── Compound prompt splitting ────────────────────────────────────────────────


class TestSplitCompoundPrompt:
    def test_parenthesized_numbers(self):
        from ofp_playground.agents.llm.openai_image import _split_compound_prompt
        prompt = "(1) Urban sidewalk texture (2) Dark asphalt with lane markers (3) Hoodie fabric"
        parts = _split_compound_prompt(prompt)
        assert len(parts) == 3
        assert "Urban sidewalk" in parts[0]
        assert "asphalt" in parts[1]
        assert "Hoodie" in parts[2]

    def test_dotted_numbers(self):
        from ofp_playground.agents.llm.openai_image import _split_compound_prompt
        prompt = "1. First texture\n2. Second texture\n3. Third texture"
        parts = _split_compound_prompt(prompt)
        assert len(parts) == 3

    def test_single_prompt_unchanged(self):
        from ofp_playground.agents.llm.openai_image import _split_compound_prompt
        prompt = "A beautiful sunset over mountains"
        parts = _split_compound_prompt(prompt)
        assert parts == [prompt]

    def test_empty_prompt(self):
        from ofp_playground.agents.llm.openai_image import _split_compound_prompt
        assert _split_compound_prompt("") == [""]
