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
#             Characters → short plain-language prompt starting with
#               "front and back view of a: 3D game character in T pose, chibi features, ..."
#             Props → short plain-language prompt starting with
#               "3D game prop, chibi style, white background, ..."
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
  For each CHARACTER asset:
    [ASSIGN ChibiPainter]
    front and back view of a: 3D game character in T pose, chibi features, humanoid, big head, [1-2 sentence plain description of the character's appearance and colors from the manifest]

  For each PROP asset:
    [ASSIGN ChibiPainter]
    3D game prop, chibi style, white background, [1-2 sentence plain description of the prop from the manifest]

[TASK_COMPLETE] after all assets from the manifest are rendered.

PROMPT RULES — READ CAREFULLY:
- Keep every ChibiPainter prompt SHORT (under 40 words). Plain language only.
- For characters: always start with 'front and back view of a: 3D game character in T pose, chibi features, humanoid, big head,'
- Do NOT add style keywords, do NOT add 'game asset sheet', do NOT add 'centered symmetrical full body visible'
- Those extra keywords cause the model to generate annotated character sheets instead of clean renders
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
