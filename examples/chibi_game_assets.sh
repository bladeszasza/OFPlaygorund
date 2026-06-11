#!/bin/bash
# chibi_game_assets.sh
# Chibi game asset generation pipeline — GPT-5.4 orchestrator + GPT Image 2 painter
#
# Generates a complete set of chibi-style humanoid game asset sheets:
#   - Hero + Heroine (front + back, T-pose)
#   - Plushy animal characters x5 (humanoid bipeds, front + back)
#   - Lizard animal characters x5 (humanoid bipeds, front + back)
#   - Houses, fences, trees (props, orchestrator decides views)
#   - Side characters / extras as GPT-5.4 sees fit
#
# All character assets are humanoid bipeds in T-pose for single-skeleton rigging.
# Style: 3D chibi toon, big head small body, vibrant colors, white background.
#
# Agents:
#   - openai:orchestrator    → ChibiOrchestrator  (gpt-5.4)
#   - openai:text-generation → AssetVisioneer     (gpt-5.4, @creative/game-asset-visioneer)
#   - openai:text-to-image   → ChibiPainter       (gpt-image-2-2026-04-21, @ofp-images/chibi-game-asset-painter)
#
# Pipeline:
#   Phase 1:  AssetVisioneer designs the world bible + full asset manifest
#   Phase 2+: ChibiOrchestrator loops through manifest, dispatching paint jobs
#             Characters/creatures → 2 images via (1)/(2) compound prompt:
#               (1) front T-pose  (2) back T-pose; back view references front image
#             Props/non-humanoids → 1 beauty-shot image from front
#   Final:    [TASK_COMPLETE] — all images saved to result/<session>/images/
#
# Usage:
#   bash examples/chibi_game_assets.sh
#   bash examples/chibi_game_assets.sh "enchanted forest world, pastel palette"
#
# Requirements:
#   - OPENAI_API_KEY
#   - ofp-playground CLI installed (pip install -e ".[dev]")

set -e

THEME="${1:-vibrant fantasy world with a warm sunset palette}"

ORCHESTRATOR_PROMPT="You are ChibiOrchestrator, the creative director of a chibi game asset generation pipeline.

TEAM: AssetVisioneer, ChibiPainter.

WORLD THEME HINT: ${THEME}

MISSION: Generate a complete, coherent set of chibi-style 3D game assets. Characters are humanoid bipeds in T-pose. Style: big head, small body, vibrant colors, white background.

ASSET BRIEF (minimum — expand freely based on AssetVisioneer's world design):
- Hero x1 (humanoid, front+back)
- Heroine x1 (humanoid, front+back)
- Plushy animal characters x5 (humanoid biped)
- Lizard animal characters x5 (humanoid biped)
- Side characters / extras as AssetVisioneer deems fitting
- Houses x7 (various styles)
- Fences (1 set)
- Trees x6 (various types)
- Additional props as AssetVisioneer sees fit

PIPELINE:

Phase 1: [ASSIGN AssetVisioneer]
Task: Design the full world bible — game world theme, master color palette, and a complete asset manifest with a plain-language visual brief for every asset.

Phase 2+: After reading AssetVisioneer's manifest via read_artifact, loop through every asset:
  For each CHARACTER or CREATURE asset (humanoid biped):
    [ASSIGN ChibiPainter]
    (1) 3D game character in T pose, chibi, humanoid, big head, [plain 1-sentence description], front view, white background
    (2) 3D game character in T pose, chibi, humanoid, big head, [same plain description], back view, white background

  For each PROP asset (house, tree, fence, object — non-humanoid):
    [ASSIGN ChibiPainter]
    3D game prop, chibi style, [plain 1-sentence description], white background

[TASK_COMPLETE] after all assets from the manifest are rendered.

PROMPT RULES — CRITICAL:
- Keep every ChibiPainter prompt SHORT. Plain language only. No keyword lists.
- Characters get 2 separate images via the (1)/(2) compound format — front view then back view
- The painter automatically uses the front render as a reference when generating the back view
- Props get 1 image — a clean beauty shot, no (1)/(2) needed
- Do NOT write 'game asset sheet', 'centered', 'symmetrical', 'full body visible', or any style keyword list
  — those phrases cause the model to generate annotated wiki-style character sheets, not clean renders
- Use read_artifact to access AssetVisioneer's phase output before starting image generation
- Render EVERY asset in the manifest — do not skip any"

ofp-playground start \
  --policy SHOWRUNNER_DRIVEN \
  --topic "Chibi game asset library — humanoid T-pose characters and props, toon 3D style, vibrant colors, white background" \
  --max-turns 200 \
  --no-human \
  --agent "-provider openai -type orchestrator -name ChibiOrchestrator -model gpt-5.4 -system ${ORCHESTRATOR_PROMPT}" \
  --agent "-provider openai -name AssetVisioneer -model gpt-5.4 -system @creative/game-asset-visioneer" \
  --agent "-provider openai -type text-to-image -name ChibiPainter -model gpt-image-2-2026-04-21 -system @ofp-images/chibi-game-asset-painter"
