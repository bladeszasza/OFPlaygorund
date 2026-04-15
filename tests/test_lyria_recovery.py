"""Tests for truncated-ASSIGN auto-expansion and Lyria prompt recovery."""

from __future__ import annotations

import pytest

from ofp_playground.agents.llm.google_music import _recover_lyria_prompt_from_manuscript
from ofp_playground.floor.manager import FloorManager


# ---------------------------------------------------------------------------
# Realistic fixtures derived from actual session runs
# ---------------------------------------------------------------------------

# LyriaComposer's full output (as accepted by the manuscript).
LYRIA_FULL_OUTPUT = (
    "PROMPT:\n"
    "Create a funky punk rock song at 106 BPM in C major. "
    "1974 Precision Bass (flatwound, bridge-picked) provides a rhythmic \"clack\" "
    "and 16th-note ghost notes; Fender Mustang guitar with dry, jagged stabs; "
    "Gretsch kit with tight wood-hoop snare (no reverb) and closed hi-hats. "
    "Production is raw, basement-style, humid, and close-mic'd with heavy "
    "mid-range focus. Instrumental feel is unhurried, walking swagger.\n\n"
    "[0:00 - 0:20] Intro: Bass solo riff establishes the groove. "
    "Guitar enters at [0:10] with rhythmic muted scratches.\n"
    "[0:20 - 0:50] Verse 1: Groove locks in. Bass and drums only on the downbeat.\n"
    "[0:50 - 1:10] Pre-Chorus: Guitar shifts to insistent chugging on F chord.\n"
    "[1:10 - 1:40] Chorus: Full ensemble. Am chord emphasizes the bail.\n"
    "[1:40 - 2:10] Verse 2: Percussive intensity increases.\n"
    "[2:10 - 2:40] Bridge: Drums drop hi-hats. Bass maintains backbone.\n"
    "[2:40 - 3:00] Outro: Driving C-F riff returns. Ends abruptly on G chord.\n\n"
    "[Verse 1]\nKick-push.\nUrethane hums on the cracked concrete.\n\n"
    "[Chorus]\nCatch the wheel bite, shoulder meets the street\n\n"
    "STYLE NOTES:\n"
    "Vocal style: Conversational, intimate."
)

# Showrunner's truncated ASSIGN task (only first line pasted).
TRUNCATED_TASK = (
    "Generate this music \u2014 PROMPT: "
    "Create a funky punk rock song at 106 BPM in C major. 197"
)

# Showrunner pasting the full content (good run).
FULL_TASK = (
    "Generate this music \u2014 PROMPT: "
    "Create a funky punk rock song at 106 BPM in C major. "
    "1974 Precision Bass (flatwound, bridge-picked) provides a rhythmic \"clack\" "
    "and 16th-note ghost notes; Fender Mustang guitar with dry, jagged stabs; "
    "Gretsch kit with tight wood-hoop snare (no reverb) and closed hi-hats. "
    "Production is raw, basement-style, humid, and close-mic'd with heavy "
    "mid-range focus. Instrumental feel is unhurried, walking swagger.\n\n"
    "[0:00 - 0:20] Intro: Bass solo riff establishes the groove.\n"
    "[0:20 - 0:50] Verse 1: Groove locks in.\n"
    "[0:50 - 1:10] Pre-Chorus: chugging on F chord.\n"
    "[1:10 - 1:40] Chorus: Full ensemble.\n"
    "[1:40 - 2:10] Verse 2: Intensity increases.\n"
    "[2:10 - 2:40] Bridge: Drums drop hi-hats.\n"
    "[2:40 - 3:00] Outro: Driving C-F riff returns.\n\n"
    "[Verse 1]\nKick-push.\n\n"
    "[Chorus]\nCatch the wheel bite.\n\n"
    "STYLE NOTES:\nVocal style: Conversational."
)

# Bad-run raw directive text (task truncated + STORY SO FAR with full PROMPT).
BAD_RUN_RAW = (
    "[DIRECTIVE for MusicGen]: " + TRUNCATED_TASK
    + "\n\n--- STORY SO FAR (2400 words) ---\n"
    "TITLE: Concrete Syntax\n\n"
    "STORY: The song maps the ritual of a night session.\n\n"
    + LYRIA_FULL_OUTPUT
    + "\n\n[audio by MusicGen]: /path/to/music.mp3\n\n"
    "VISUAL WORLD\n\n"
    "PROMPT:\n"
    "oil on canvas, Van Gogh impasto style, 3 AM urban parking lot scene.\n\n"
    "NEGATIVE PROMPT:\nphotorealism.\n"
    "--- END OF STORY SO FAR ---\n"
    "Continue directly from where the story left off."
)


# ===================================================================
# Tests for FloorManager._expand_truncated_assign
# ===================================================================

class TestExpandTruncatedAssign:
    """Unit tests for the FloorManager truncation-detection logic."""

    def test_expands_truncated_task(self):
        """When task is a prefix of acceptedtext, return the full accepted text."""
        result = FloorManager._expand_truncated_assign(TRUNCATED_TASK, LYRIA_FULL_OUTPUT)
        assert result == LYRIA_FULL_OUTPUT

    def test_no_expansion_when_task_already_full(self):
        """When task is already >= accepted text length, return unchanged."""
        result = FloorManager._expand_truncated_assign(FULL_TASK, LYRIA_FULL_OUTPUT)
        assert result == FULL_TASK

    def test_no_expansion_when_no_accepted(self):
        """Empty accepted text → return original task."""
        result = FloorManager._expand_truncated_assign(TRUNCATED_TASK, "")
        assert result == TRUNCATED_TASK

    def test_no_expansion_when_different_content(self):
        """If accepted text is about something completely different, no expansion."""
        other = (
            "PROMPT:\nCreate a jazz ballad at 80 BPM in Bb minor. "
            "Upright bass with soft plucking.\n\n"
            "[0:00 - 0:30] Intro: Piano solo."
        )
        result = FloorManager._expand_truncated_assign(TRUNCATED_TASK, other)
        assert result == TRUNCATED_TASK

    def test_strips_generate_wrapper(self):
        """The Showrunner's 'Generate this music — PROMPT:' wrapper is handled."""
        task = "Generate this music \u2014 PROMPT: Create a funky punk rock song at 106 BPM"
        accepted = (
            "PROMPT:\n"
            "Create a funky punk rock song at 106 BPM in C major. Full details.\n\n"
            "[0:00 - 0:20] Intro: Bass groove.\n"
            "[0:20 - 0:50] Verse: Guitar enters.\n"
        )
        result = FloorManager._expand_truncated_assign(task, accepted)
        assert result == accepted
        assert "[0:00 - 0:20]" in result

    def test_no_expansion_when_similar_length(self):
        """If accepted is only marginally longer (within 1.5×), skip expansion."""
        task = "Create a funky punk rock song at 106 BPM in C major."
        accepted = "Create a funky punk rock song at 106 BPM in C major. Short."
        result = FloorManager._expand_truncated_assign(task, accepted)
        assert result == task


# ===================================================================
# Tests for _recover_lyria_prompt_from_manuscript
# ===================================================================

class TestRecoverLyriaPrompt:
    """Unit tests for the manuscript-based recovery function."""

    def test_recovers_full_prompt_from_bad_run(self):
        """When the task is truncated, recover the full PROMPT block from the manuscript."""
        result = _recover_lyria_prompt_from_manuscript(BAD_RUN_RAW)
        assert result is not None
        assert "[0:00 - 0:20]" in result
        assert "[2:40 - 3:00]" in result
        assert "106 BPM" in result
        assert "Kick-push" in result
        assert "[Chorus]" in result

    def test_does_not_include_style_notes(self):
        """The recovered prompt must stop before STYLE NOTES: boundary."""
        result = _recover_lyria_prompt_from_manuscript(BAD_RUN_RAW)
        assert result is not None
        assert "STYLE NOTES" not in result
        assert "Vocal style" not in result

    def test_does_not_include_image_prompt(self):
        """The recovered prompt must not contain the image PROMPT content."""
        result = _recover_lyria_prompt_from_manuscript(BAD_RUN_RAW)
        assert result is not None
        assert "oil on canvas" not in result
        assert "Van Gogh impasto" not in result

    def test_returns_none_when_no_story_so_far(self):
        """No STORY SO FAR section → None."""
        text = "[DIRECTIVE for Lyria]: PROMPT: Create a song.\n\nSome other text."
        assert _recover_lyria_prompt_from_manuscript(text) is None

    def test_returns_none_when_no_prompt_in_manuscript(self):
        """STORY SO FAR exists but contains no PROMPT: line → None."""
        text = (
            "some task\n\n--- STORY SO FAR (100 words) ---\n"
            "Just some story content with no prompt block.\n"
            "--- END OF STORY SO FAR ---\n"
        )
        assert _recover_lyria_prompt_from_manuscript(text) is None

    def test_returns_none_for_image_only_prompt(self):
        """Manuscript has a PROMPT: but it's for an image (no [0:xx] timestamps)."""
        text = (
            "task\n\n--- STORY SO FAR (200 words) ---\n"
            "PROMPT:\n"
            "oil on canvas, Van Gogh impasto style, moody lighting.\n\n"
            "NEGATIVE PROMPT:\nphotorealism.\n"
            "--- END OF STORY SO FAR ---\n"
        )
        assert _recover_lyria_prompt_from_manuscript(text) is None

    def test_picks_last_music_prompt_among_multiple(self):
        """When multiple PROMPT: blocks exist, pick the last one with timestamps."""
        text = (
            "task\n\n--- STORY SO FAR (500 words) ---\n"
            "PROMPT:\nFirst attempt, no timestamps here.\n\n"
            "PROMPT:\nSecond attempt at 106 BPM.\n\n"
            "[0:00 - 0:15] Intro: Bass riff.\n"
            "[0:15 - 0:30] Verse: Guitar enters.\n\n"
            "STYLE NOTES:\nSome notes.\n"
            "--- END OF STORY SO FAR ---\n"
        )
        result = _recover_lyria_prompt_from_manuscript(text)
        assert result is not None
        assert "Second attempt" in result
        assert "[0:00 - 0:15]" in result
        assert "First attempt" not in result

    def test_strips_markdown_bold(self):
        """Markdown **bold** markers are removed from the recovered text."""
        text = (
            "task\n\n--- STORY SO FAR (200 words) ---\n"
            "PROMPT:\nCreate a **funky** punk rock song.\n\n"
            "[0:00 - 0:20] **Intro**: Bass groove.\n\n"
            "STYLE NOTES:\nend.\n"
            "--- END OF STORY SO FAR ---\n"
        )
        result = _recover_lyria_prompt_from_manuscript(text)
        assert result is not None
        assert "**" not in result
        assert "funky" in result

    def test_audio_marker_terminates_block(self):
        """[audio by ...] marker terminates the PROMPT block."""
        text = (
            "task\n\n--- STORY SO FAR (300 words) ---\n"
            "PROMPT:\nCreate a song.\n\n"
            "[0:00 - 0:15] Intro.\n"
            "[0:15 - 0:30] Verse.\n\n"
            "[audio by MusicGen]: /path/to/file.mp3\n\n"
            "VISUAL WORLD\nblah\n"
            "--- END OF STORY SO FAR ---\n"
        )
        result = _recover_lyria_prompt_from_manuscript(text)
        assert result is not None
        assert "[audio" not in result
        assert "[0:00 - 0:15]" in result

    def test_handles_missing_end_marker(self):
        """Recovery works even if --- END OF STORY SO FAR --- is missing."""
        text = (
            "task\n\n--- STORY SO FAR (200 words) ---\n"
            "PROMPT:\nCreate a song at 100 BPM.\n\n"
            "[0:00 - 0:10] Intro: Drums.\n"
            "[0:10 - 0:30] Verse: Guitar.\n"
        )
        result = _recover_lyria_prompt_from_manuscript(text)
        assert result is not None
        assert "[0:00 - 0:10]" in result
