"""Post-processor — deterministic file renamer for run result directories.

Reads manifest.txt to determine the order and type of every accepted artifact,
then renames timestamp-named files to semantic names:

  images/20260325_172901_nanobananpainter.png  →  images/character_01.png
                                                   images/chapter_01_a.png  etc.
  web/chapter_01.html                           →  (already named correctly)
  music/chapter_01_music.wav                    →  (already named correctly)

No LLM calls. No API keys required.

Usage (CLI):
    ofp-playground postprocess result/20260325_182519_ff7f8e14 [--dry-run]
"""
from __future__ import annotations

import logging
import re
import shutil
from pathlib import Path

logger = logging.getLogger(__name__)

# Kept for CLI backwards compatibility (--model flag is accepted but ignored)
DEFAULT_MODEL = "none"
DEFAULT_TASK = "deterministic-rename"


class PostProcessorAgent:
    """Deterministic file organiser for run result directories.

    Parsing strategy
    ────────────────
    manuscript.txt has one entry per accepted output, separated by blank lines.
    Media entries look like:
        [image by NanoBananPainter]: /abs/path/to/file.png
        [audio by Composer]: /abs/path/to/file.wav

    Text entries are the raw chapter / plan text written by StoryWriter.

    Order of image entries in the manuscript reflects generation order:
      1. All character portraits  (before the first "CHAPTER N:" text entry)
      2. Per chapter: scene_a, scene_b  (two images per chapter)
         Optionally followed by a cutscene image (one extra between chapter pairs)
    """

    def __init__(
        self,
        result_dir: Path,
        # api_key / model kept for signature compatibility — not used
        api_key: str = "",
        model: str = DEFAULT_MODEL,
        task: str = DEFAULT_TASK,
        dry_run: bool = False,
    ):
        self._result_dir = result_dir.resolve()
        self._dry_run = dry_run
        self._actions: list[str] = []

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _safe_path(self, p: Path) -> Path:
        resolved = p.resolve()
        if not str(resolved).startswith(str(self._result_dir)):
            raise ValueError(f"Path escape attempt: {p}")
        return resolved

    def _rename(self, src: Path, dst: Path) -> None:
        src = self._safe_path(src)
        dst = self._safe_path(dst)
        if not src.exists():
            logger.warning("[PostProcessor] source not found: %s", src)
            return
        if src == dst:
            return
        label = f"rename  {src.relative_to(self._result_dir)}  →  {dst.relative_to(self._result_dir)}"
        if not self._dry_run:
            dst.parent.mkdir(parents=True, exist_ok=True)
            if dst.exists():
                logger.warning("[PostProcessor] destination exists, skipping: %s", dst)
                return
            src.rename(dst)
        self._actions.append(("DRY " if self._dry_run else "") + label)
        logger.info("[PostProcessor] %s", label)

    # ------------------------------------------------------------------
    # Manuscript parsing
    # ------------------------------------------------------------------

    def _parse_manuscript(self) -> tuple[list[Path], list[Path], int]:
        """Return (image_paths_in_order, audio_paths_in_order, chapter_start_image_index).

        chapter_start_image_index is the index of the first chapter-scene image
        (images before it are character portraits).
        """
        manuscript = self._result_dir / "manuscript.txt"
        if not manuscript.exists():
            return [], [], 0

        text = manuscript.read_text(encoding="utf-8", errors="replace")
        entries = re.split(r"\n{2,}", text.strip())

        image_paths: list[Path] = []
        audio_paths: list[Path] = []
        chapter_start_idx: int | None = None  # image index where chapters begin

        for entry in entries:
            entry = entry.strip()
            if not entry:
                continue

            # Media entry: [image by Agent]: /path  OR  [audio by Agent]: /path
            img_m = re.match(r"\[image by [^\]]+\]:\s*(.+)", entry, re.IGNORECASE)
            if img_m:
                p = Path(img_m.group(1).strip())
                if p.exists() or (self._result_dir / p).exists():
                    image_paths.append(p if p.is_absolute() else self._result_dir / p)
                continue

            audio_m = re.match(r"\[audio by [^\]]+\]:\s*(.+)", entry, re.IGNORECASE)
            if audio_m:
                p = Path(audio_m.group(1).strip())
                if p.exists() or (self._result_dir / p).exists():
                    audio_paths.append(p if p.is_absolute() else self._result_dir / p)
                continue

            # Text entry from StoryWriter — detect first chapter
            if chapter_start_idx is None and re.search(r"^CHAPTER\s+\d+", entry, re.MULTILINE):
                chapter_start_idx = len(image_paths)

        if chapter_start_idx is None:
            chapter_start_idx = 0

        return image_paths, audio_paths, chapter_start_idx

    # ------------------------------------------------------------------
    # Rename images
    # ------------------------------------------------------------------

    def _rename_images(self, images: list[Path], chapter_start_idx: int) -> None:
        """Rename timestamped images to semantic names.

        Before chapter_start_idx : character_01.png, character_02.png, …
        After (chapter illustrations): chapter_01_a.png, chapter_01_b.png,
                                        chapter_01_cutscene.png (if present — odd extra),
                                        chapter_02_a.png, …
        """
        img_dir = self._result_dir / "images"

        # Character portraits
        for i, src in enumerate(images[:chapter_start_idx], start=1):
            dst = img_dir / f"character_{i:02d}{src.suffix}"
            self._rename(src, dst)

        # Chapter illustrations — consume in pairs (a, b), with optional cutscene
        chapter_imgs = images[chapter_start_idx:]
        chapter_num = 1
        idx = 0
        while idx < len(chapter_imgs):
            scene_a = chapter_imgs[idx]
            idx += 1
            dst_a = img_dir / f"chapter_{chapter_num:02d}_a{scene_a.suffix}"
            self._rename(scene_a, dst_a)

            if idx < len(chapter_imgs):
                scene_b = chapter_imgs[idx]
                idx += 1
                dst_b = img_dir / f"chapter_{chapter_num:02d}_b{scene_b.suffix}"
                self._rename(scene_b, dst_b)

            # Cutscene: a single extra image before the next pair
            # Heuristic: if the next image would start another incomplete pair
            # at the end, treat it as a cutscene for this chapter.
            remaining = len(chapter_imgs) - idx
            if remaining == 1:
                cutscene = chapter_imgs[idx]
                idx += 1
                dst_c = img_dir / f"chapter_{chapter_num:02d}_cutscene{cutscene.suffix}"
                self._rename(cutscene, dst_c)

            chapter_num += 1

    # ------------------------------------------------------------------
    # Scan for any leftover timestamped files not in manuscript
    # ------------------------------------------------------------------

    def _rename_orphan_images(self, already_processed: set[Path]) -> None:
        """Rename any remaining timestamp-slug images not captured in the manuscript.

        These are sorted by name (which encodes the timestamp) and appended
        to the tail of the chapter sequence.
        """
        img_dir = self._result_dir / "images"
        if not img_dir.exists():
            return

        orphans = sorted(
            p for p in img_dir.glob("*.png")
            if p.resolve() not in already_processed
            and re.match(r"\d{8}_\d{6}_", p.name)  # timestamp pattern
        )
        if not orphans:
            return

        # Find highest chapter number already assigned
        existing = sorted(img_dir.glob("chapter_*_a.png"))
        if existing:
            m = re.search(r"chapter_(\d+)_", existing[-1].name)
            next_chapter = int(m.group(1)) + 1 if m else 1
        else:
            next_chapter = 1

        idx = 0
        chapter_num = next_chapter
        while idx < len(orphans):
            dst_a = img_dir / f"chapter_{chapter_num:02d}_a.png"
            self._rename(orphans[idx], dst_a)
            idx += 1
            if idx < len(orphans):
                dst_b = img_dir / f"chapter_{chapter_num:02d}_b.png"
                self._rename(orphans[idx], dst_b)
                idx += 1
            chapter_num += 1

    # ------------------------------------------------------------------
    # Public entry point
    # ------------------------------------------------------------------

    async def run(self) -> list[str]:
        """Rename artifacts deterministically. Returns list of actions taken."""
        image_paths, _audio_paths, chapter_start_idx = self._parse_manuscript()

        if image_paths:
            self._rename_images(image_paths, chapter_start_idx)

        # Handle any images that weren't in the manuscript (session interrupted early, etc.)
        processed = {p.resolve() for p in image_paths}
        self._rename_orphan_images(processed)

        # Music and HTML files are already named correctly by their agents
        # (google_music.py extracts chapter number; web_page.py uses === FILE: === directive)
        # Nothing to do for those.

        if not self._actions:
            logger.info("[PostProcessor] No timestamped images to rename — nothing to do.")

        return self._actions
