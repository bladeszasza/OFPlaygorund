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
#   - openai:text-to-image   → ChibiPainter       (gpt-image-2)
#
# Pipeline:
#   Phase 1:  AssetVisioneer designs the world bible + full asset manifest
#   Phase 2+: ChibiOrchestrator loops through manifest, dispatching paint jobs
#             Characters → 2 assigns (front view + back view)
#             Props → 1 assign (or sheet, orchestrator decides)
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

MISSION: Generate a complete, coherent set of chibi-style game assets. All characters are humanoid bipeds in T-pose, riggable with a single skeleton. Style: 3D toon chibi — big head, small body, vibrant colors, clean white background.

ASSET BRIEF (minimum — expand freely based on AssetVisioneer's world design):
- Hero x1 (humanoid, front+back)
- Heroine x1 (humanoid, front+back)
- Plushy animal characters x5 (round, soft, big eyes — humanoid biped)
- Lizard animal characters x5 (scaled, sleek — humanoid biped)
- Side characters / extras as AssetVisioneer deems fitting
- Houses x7 (various styles, props)
- Fences (1 set or sheet, props)
- Trees x6 (various types, props)
- Additional props as AssetVisioneer sees fit

PIPELINE:

Phase 1: [ASSIGN AssetVisioneer]
Task: Design the full world bible — game world theme, master color palette, and a complete asset manifest with visual briefs for every asset. Expand beyond the minimum if the world calls for more characters or prop variants.

Phase 2+: After reading AssetVisioneer's manifest via read_artifact, loop through every asset:
  For each CHARACTER asset (type=character):
    Step A: [ASSIGN ChibiPainter]
    chibi 3D toon render, big head small body proportions, vibrant saturated colors, clean white background, front facing, T-pose, full body visible, centered, symmetrical, game character asset sheet, [visual brief from manifest], key colors: [hex values from world palette]

    Step B: [ASSIGN ChibiPainter]
    chibi 3D toon render, big head small body proportions, vibrant saturated colors, clean white background, back view, rear facing, T-pose, full body visible, centered, symmetrical, game character asset sheet, [same character visual brief], key colors: [hex values]

  For each PROP asset (type=prop):
    [ASSIGN ChibiPainter]
    chibi 3D toon render, vibrant saturated colors, clean white background, [single/sheet/front view as specified in manifest], clean silhouette, game prop asset, [visual brief from manifest], key colors: [hex values]

[TASK_COMPLETE] after all assets from the manifest are rendered.

RULES:
- Use read_artifact to access AssetVisioneer's phase output before starting image generation
- Render EVERY asset in the manifest — do not skip any
- Characters always get both front AND back view renders
- Craft each prompt to encode the specific palette and visual brief from the manifest
- Props: use your judgment on views — symmetric props need only one; asymmetric props may benefit from two"

ofp-playground start \
  --policy SHOWRUNNER_DRIVEN \
  --topic "Chibi game asset library — humanoid T-pose characters and props, toon 3D style, vibrant colors, white background" \
  --max-turns 200 \
  --no-human \
  --agent "-provider openai -type orchestrator -name ChibiOrchestrator -model gpt-5.4 -system ${ORCHESTRATOR_PROMPT}" \
  --agent "-provider openai -name AssetVisioneer -model gpt-5.4 -system @creative/game-asset-visioneer" \
  --agent "-provider openai -type text-to-image -name ChibiPainter -model gpt-image-2 -system chibi 3D toon render, big head small body proportions, vibrant saturated colors, clean white background, game asset sheet, full body visible, centered"
