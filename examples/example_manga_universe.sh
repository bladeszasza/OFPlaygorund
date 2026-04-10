#!/bin/bash
# example_manga_universe.sh
# Demonstration: Manga Universe Creator — showrunner-driven full creative pipeline
#
# Agents used (leveraging ./agents library):
#   - google:orchestrator           → Creative Showrunner (coordinates all phases)
#   - google:text-generation        → ArcPlanner          (@creative/manga-arc-planner)
#   - google:text-generation        → Scripter            (@creative/manga-scripter)
#   - google:text-generation        → MangaArtist         (@creative/manga-artist)
#   - google:text-generation        → CubistPainter       (@creative/cubist-painter)
#   - google:text-generation        → ImpressionistPainter(@creative/impressionist-painter)
#   - google:text-to-image          → ImageGen  (generic executor — renders prompts from artists)
#   - google:text-generation        → Composer  (@creative/lyria-composer — writes Lyria prompt)
#   - google:text-to-music          → MusicGen  (generic executor — generates music from Composer's prompt)
#
# Two-step creative pattern (same for both image and music):
#   Persona agent (text-gen) → writes a richly styled prompt in their creative language
#   Generic executor (text-to-image / text-to-music) → renders that prompt verbatim
#
#   This decouples creative intent from model execution. The persona agents are prompt engineers;
#   the executor agents are dumb renderers. The Showrunner copies the prompt block verbatim —
#   no paraphrasing, no interpretation.
#
# Pipeline:
#   1. Showrunner kicks off a 4-round round-robin BREAKOUT with 3 story agents
#      who brainstorm key story elements (characters, world, themes, conflict)
#   2. ArcPlanner designs the full 6-chapter manga arc from the breakout output
#   3. Scripter writes Chapter 1 as a 3-page panel script preview
#   4. Each artist (MangaArtist / CubistPainter / ImpressionistPainter) writes their cover
#      prompt → Showrunner relays the exact prompt to ImageGen for rendering
#   5. Composer writes a Lyria prompt → Showrunner relays it verbatim to MusicGen
#
# Usage:
#   bash example_manga_universe.sh [topic]
#   bash example_manga_universe.sh "A street artist whose graffiti tags summon ancient spirits"
#
# Requirements:
#   - GOOGLE_API_KEY set (all agents are Google)
#   - ofp-playground CLI installed
#   - ./agents library available

set -e

TOPIC="${1:-No man could understand
My power is in my own hand
Ooh, ooh, ooh, ooh, people talk about you
People say you\'ve had your day
I\'m a man that will go far
Fly the moon and reach for the stars
With my sword and head held high
Got to pass the test first time, yeah
I know that people talk about me, I hear it every day
But I can prove them wrong \'cause I\'m right first time.}"

echo "Starting Manga Universe Creator"
echo "   Topic: $TOPIC"
echo ""

# ---------------------------------------------------------------------------
# Showrunner mission brief
# ---------------------------------------------------------------------------
read -r -d '' SHOWRUNNER <<MISSION || true
You are the creative director of a manga universe project. Your mission: bring the following concept to life as a complete manga universe.

Topic: ${TOPIC}

Execute the following phases IN ORDER. Do not skip ahead. Wait for each agent to complete before moving on.

--- PHASE 1: STORY BRAINSTORM ---
First, launch a breakout room where three specialists collaborate to explore the story's foundations. Output the following block exactly:

[BREAKOUT policy=round_robin max_rounds=16 topic=Brainstorm key story elements for a manga — protagonist, antagonist, world, central conflict, themes, emotional tone, and first-chapter hook — for: ${TOPIC}]
[BREAKOUT_AGENT -provider hf -name Archie -system @creative/manga-arc-planner]
[BREAKOUT_AGENT -provider hf -name Scriptus -system @creative/manga-scripter]
[BREAKOUT_AGENT -provider google -name Storyboooo -system @creative/storyboard-writer]
[BREAKOUT_AGENT -provider google -name Brandie -system @creative/brand-designer]

--- PHASE 2: ARC DESIGN ---
After the breakout results arrive, assign the arc architect:
[ASSIGN ArcPlanner]: Using the brainstorm output, design a complete 6-chapter manga arc. Include: arc name, core dramatic question, theme, inciting rupture, escalation stack (3 beats), lowest point, revelation, resolution, protagonist internal arc, antagonist mirror design, and the story seed this arc plants for a follow-on arc. Be specific — name characters, places, and the key rule of the story's world.

--- PHASE 3: CHAPTER 1 PREVIEW ---
[ASSIGN Scripter]: Using the arc plan, write the Chapter 1 panel script as a 3-page preview. Format each page with panel count, panel sizes (small/medium/large/splash), visual descriptions with camera angle and mood, all dialogue, sound effects, and staging notes. End page 3 on an irresistible cliffhanger that makes the reader need page 4.

--- PHASE 4: COVER ART — THREE INTERPRETATIONS ---
Each artist writes a styled image generation prompt. After each one responds, you copy their exact PROMPT block verbatim into an [ASSIGN ImageGen] directive to render the image. Do not paraphrase — relay the prompt exactly.

Step 4a:
[ASSIGN MangaArtist]: Write a manga-style cover image generation prompt for this manga. Follow your prompt format exactly: output a PROMPT: section with comma-separated positive terms (style, character, composition, lighting, screentone, atmosphere), a NEGATIVE PROMPT: section, and brief NOTES.

After MangaArtist responds, immediately assign:
[ASSIGN ImageGen]: Generate this image — <paste MangaArtist's exact PROMPT content here verbatim>

Step 4b:
[ASSIGN CubistPainter]: Write a Picasso Analytical Cubist cover image generation prompt for this manga. Output a PROMPT: section (fragmented planes, simultaneous viewpoints, ochre palette, oil on canvas), a NEGATIVE PROMPT: section, and brief STYLE NOTES.

After CubistPainter responds, immediately assign:
[ASSIGN ImageGen]: Generate this image — <paste CubistPainter's exact PROMPT content here verbatim>

Step 4c:
[ASSIGN ImpressionistPainter]: Write a Van Gogh impasto cover image generation prompt for this manga. Output a PROMPT: section (directional brushwork, Swirling motion, saturated complementary colors, oil on canvas), a NEGATIVE PROMPT: section, and brief PAINTER'S NOTE.

After ImpressionistPainter responds, immediately assign:
[ASSIGN ImageGen]: Generate this image — <paste ImpressionistPainter's exact PROMPT content here verbatim>

--- PHASE 5: INTRO THEME ---
Step 5a — Compose the Lyria prompt:
[ASSIGN Composer]: Write a Lyria 3 Pro music generation prompt for a 1-minute dynamic and joyful intro theme for this manga series. The theme should feel like an opening credits sequence — energetic, hopeful, with a memorable melodic hook that carries the protagonist's spirit. Follow your prompt format exactly: output a PROMPT: section (genre, BPM, key, instruments, timestamp structure, mood), a STYLE NOTES: section, and explicitly include "Instrumental only, no vocals."

After Composer responds, immediately assign:
[ASSIGN MusicGen]: Generate this music — <paste Composer's exact PROMPT content here verbatim>

[TASK_COMPLETE]
MISSION

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------
ofp-playground start \
  --policy showrunner_driven \
  --no-human \
  --topic "$TOPIC" \
  --agent "google:orchestrator:Showrunner:${SHOWRUNNER}" \
  --agent "google:text-generation:ArcPlanner:@creative/manga-arc-planner" \
  --agent "google:text-generation:Scripter:@creative/manga-scripter" \
  --agent "google:text-generation:MangaArtist:@creative/manga-artist" \
  --agent "google:text-generation:CubistPainter:@creative/cubist-painter" \
  --agent "google:text-generation:ImpressionistPainter:@creative/impressionist-painter" \
  --agent "google:text-to-image:ImageGen:You are a professional image generation specialist. When assigned an image prompt, generate the image exactly as described. Do not alter, summarize, or interpret the prompt — render it precisely." \
  --agent "google:text-generation:Composer:@creative/lyria-composer" \
  --agent "google:text-to-music:MusicGen:Generate this music:lyria-3-pro-preview"
