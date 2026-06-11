#!/bin/bash
# chibi_game_assets.sh
# Chibi game asset generation pipeline — GPT-5.4 orchestrator + GPT Image 2 painter
#
# Generates a complete chibi game asset library:
#   - Hero + Heroine + 4-6 NPC side characters (front + back T-pose)
#   - 20-30 Pokémon/Digimon-style humanoid monster creatures (front + back T-pose)
#       Elemental roster: fire, water, grass, electric, ice, rock, dark, light,
#       dragon, mechanical, and wild-card types — all bipedal, skeleton-riggable
#   - Houses x7, fences, trees x6, extra props (beauty-shot renders)
#
# All character/monster assets get 2 separate renders (front + back T-pose).
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

HUMAN CHARACTERS:
- Hero x1 (humanoid, front+back)
- Heroine x1 (humanoid, front+back)
- Side characters / NPCs x4-6 as AssetVisioneer deems fitting

HUMANOID MONSTER ROSTER — 20 to 30 creatures total:
All monsters must be bipedal (2 legs, 2 arms) and mappable to a single humanoid skeleton.
Inspiration: Pokémon, Digimon, Yokai Watch — creative and original, NOT copies.
Cover a wide variety of archetypes across these categories:
  - Fire types x3: e.g. small flame lizard, lava bear cub, ember fox kit
  - Water types x3: e.g. bubble frog, wave otter, coral crab biped
  - Grass/Nature types x3: e.g. leaf gecko, mushroom gnome, vine salamander
  - Electric types x2: e.g. spark rodent, thunder bird biped, static jellyfish biped
  - Ice/Snow types x2: e.g. frost rabbit, blizzard wolf cub, snowflake imp
  - Rock/Earth types x2: e.g. crystal golem baby, stone armadillo biped
  - Dark/Shadow types x2: e.g. ghost cat, shadow bat biped, dusk slime biped
  - Light/Psychic types x2: e.g. starlight fairy biped, cosmic moth biped
  - Dragon types x3: e.g. small wyvern biped, ancient serpent biped, cloud dragon hatchling
  - Mechanical/Tech types x2: e.g. tiny robot creature, gear golem cub
  - Extra wild cards x2-4: AssetVisioneer invents freely (plant-dragon hybrids, candy demons, etc.)
Each creature must have a fun name, distinctive silhouette, and a clear elemental theme.

PROPS:
- Houses x7 (various styles matching world theme)
- Fences (1 set, 2-3 segment variants)
- Trees x6 (various types)
- Additional environmental props as AssetVisioneer sees fit

PIPELINE:

Phase 1: [ASSIGN AssetVisioneer]
Task: Design the full world bible and a complete asset manifest. The manifest MUST include ALL of the following categories — do not skip any:

  HUMAN CHARACTERS (required):
  - Hero x1, Heroine x1
  - Side characters / NPCs: 4-6 original designs

  HUMANOID MONSTER ROSTER — 20 to 30 creatures (REQUIRED, this is the core of the game):
  All must be bipedal (2 legs, 2 arms), original designs inspired by Pokémon/Digimon style.
  Must cover ALL these elemental categories:
  - Fire x3 (e.g. flame lizard, lava bear, ember fox)
  - Water x3 (e.g. bubble frog, wave otter, coral crab biped)
  - Grass/Nature x3 (e.g. leaf gecko, mushroom gnome, vine salamander)
  - Electric x2 (e.g. spark rodent, thunder bird biped)
  - Ice/Snow x2 (e.g. frost rabbit, blizzard wolf cub)
  - Rock/Earth x2 (e.g. crystal golem, stone armadillo biped)
  - Dark/Shadow x2 (e.g. ghost cat, shadow bat biped)
  - Light/Psychic x2 (e.g. starlight fairy biped, cosmic moth biped)
  - Dragon x3 (e.g. wyvern biped, serpent biped, cloud dragon hatchling)
  - Mechanical/Tech x2 (e.g. robot creature, gear golem cub)
  - Wild cards x2-4: invent freely (plant-dragon hybrid, candy demon, etc.)
  Give each creature a fun name, brief description, and hex colors.

  PROPS (required):
  - Houses x7 (varied styles)
  - Fences: 2-3 segment variants
  - Trees x6 (varied types)
  - Extra environmental props as you see fit

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
- SANITIZE POSE LANGUAGE: before writing any character prompt, strip these words from the description:
  waving, mid-step, running, dancing, crouching, dueling, stalking, leaping, dynamic pose, action pose,
  ready pose, welcoming pose, beckoning, striding, floating pose, raised arm, lifted foot — and any
  similar movement or stance word. Replace with nothing. The T-pose is enforced by the prompt structure.
- Use read_artifact to access AssetVisioneer's phase output before starting image generation
- Render EVERY asset in the manifest — do not skip any"

ofp-playground start \
  --policy SHOWRUNNER_DRIVEN \
  --topic "Chibi game asset library — humanoid T-pose characters and props, toon 3D style, vibrant colors, white background" \
  --max-turns 500 \
  --no-human \
  --agent "-provider openai -type orchestrator -name ChibiOrchestrator -model gpt-5.4 -system ${ORCHESTRATOR_PROMPT}" \
  --agent "-provider openai -name AssetVisioneer -model gpt-5.4 -system @creative/game-asset-visioneer" \
  --agent "-provider openai -type text-to-image -name ChibiPainter -model gpt-image-2-2026-04-21 -system @ofp-images/chibi-game-asset-painter"
