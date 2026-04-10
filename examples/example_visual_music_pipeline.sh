#!/bin/bash
# example_visual_music_pipeline.sh
# Visual-first pipeline: painting → image → music from image → website
#
# Agents:
#   - google:orchestrator           → Showrunner (coordinates all phases)
#   - google:text-generation        → VisualConcepter (creative theme, palette, emotional core)
#   - google:text-generation        → CoverArtist (@creative/impressionist-painter)
#   - google:text-to-image          → ImageGen (renders the cover painting)
#   - google:text-generation        → LyriaComposer (@creative/lyria-composer — music prompt engineer)
#   - google:text-to-music          → MusicGen (generates from text prompt + cover image via Lyria Pro)
#   - google:code-generation        → WebDev (single-page website with cover art + audio player)
#
# Key difference from example_song_production.sh:
#   The pipeline starts from a visual concept, not a musical one.
#   The cover image is generated FIRST. MusicGen (Lyria 3 Pro) then receives both
#   the LyriaComposer's text prompt AND the generated cover image as multimodal
#   input — Lyria translates the painting's palette, brushwork, and emotional
#   temperature directly into sound.
#
#   This is powered by the Lyria 3 Pro image-to-music API:
#     contents = [text_prompt, image_part]  →  generate_content("lyria-3-pro-preview")
#
# Pipeline:
#   1. VisualConcepter: title, visual theme, color language, atmosphere, emotional core,
#      sonic hint (what the painting "sounds like" in abstract terms)
#   2. CoverArtist: Van Gogh impressionist oil painting prompt (PROMPT / NEGATIVE PROMPT /
#      PAINTER'S NOTE format) informed by VisualConcepter's world
#   3. ImageGen: renders the cover art at full resolution
#   4. LyriaComposer: writes the Lyria 3 Pro text prompt (genre, BPM, key, instruments,
#      timestamp structure) to COMPLEMENT the image — Lyria sees both
#   5. MusicGen: generates the track using text prompt + cover image as Lyria visual input
#   6. WebDev: single-page HTML site with cover art hero, audio player, visual concept notes
#
# Usage:
#   bash example_visual_music_pipeline.sh [visual topic]
#   bash example_visual_music_pipeline.sh "Fog over Kyoto's bamboo groves at dawn"
#
# Requirements:
#   - GOOGLE_API_KEY (all generation agents)
#   - ANTHROPIC_API_KEY (WebDev coding agent)
#   - ofp-playground CLI installed
#   - ./agents library available

set -e

TOPIC="${1:-kids skating in barcelona enjoying the session, high velocity high impact hight reward.}"

echo "Starting Visual-First Music Pipeline"
echo "   Topic: $TOPIC"
echo ""

# ---------------------------------------------------------------------------
# Showrunner mission brief
# ---------------------------------------------------------------------------
read -r -d '' SHOWRUNNER <<MISSION || true
You are the creative director of a visual-first music production pipeline. Your mission: produce a complete visual and musical artwork for this theme: ${TOPIC}

The pipeline is IMAGE FIRST, MUSIC SECOND. The cover painting is generated before the music, and the music is generated DIRECTLY from the painting (Lyria reads the image's palette, brushwork, and emotional temperature and translates it into sound alongside your text prompt).

Execute the following phases IN ORDER. Do not skip ahead. Wait for each agent to complete before moving on. Copy prompts VERBATIM — never paraphrase, summarize, or modify creative agent outputs when relaying them to executor agents.

--- PHASE 1: VISUAL CONCEPT ---
[ASSIGN VisualConcepter]: Create the visual and emotional foundation for this theme: ${TOPIC}

Output these sections exactly:
- TITLE: The work's title (evocative, not explanatory)
- VISUAL THEME: The central image or scene in 2-3 sentences — what a viewer first sees
- COLOR LANGUAGE: 5-7 specific pigment names or color phrases (not generic "blue" — use "Prussian blue shadow", "raw sienna warmth", "titanium white haze")
- ATMOSPHERE: The physical sensation of being inside this visual — temperature, light quality, air, distance
- EMOTIONAL CORE: The single human feeling this work carries — one sentence, no abstractions
- SONIC HINT: What does this image sound like in abstract musical terms? (Not a music prompt — just a feeling: "the silence between two notes", "a cello held note at the edge of breaking", "water in a stone channel")

--- PHASE 2: COVER PAINTING ---
[ASSIGN CoverArtist]: Using VisualConcepter's world, create a Van Gogh impressionist oil painting prompt. The painting must make someone feel the theme before they hear a note of music. Follow your format exactly:

PROMPT: (subject with precise location in frame, Van Gogh period reference — Arles / Saint-Rémy / Auvers — dominant palette with specific pigment names, brushwork direction for each surface — sky / ground / midground / focal detail, composition and horizon, light source and shadow direction, emotional temperature, "oil on canvas, thick impasto")
NEGATIVE PROMPT: (what to suppress — be specific: "soft-focus", "digital gradients", "photorealistic", "flat color", "thin paint application", "symmetrical composition")
PAINTER'S NOTE: (what Van Gogh would have been feeling while making this — one sentence connecting the brushwork to the emotional state)

--- PHASE 3: GENERATE THE IMAGE ---
[ASSIGN ImageGen]: Generate this image — PROMPT: <paste CoverArtist's exact PROMPT section content here verbatim — do not add or change anything>

--- PHASE 4: LYRIA MUSIC PROMPT ---
[ASSIGN LyriaComposer]: Craft a Lyria 3 Pro music prompt for this work.

IMPORTANT CONTEXT: The cover image will be automatically passed to Lyria alongside your text prompt. Lyria reads the image's palette, light, texture, and emotional register as additional musical input. Your text prompt should COMPLEMENT the visual — give it genre, structure, BPM, and instruments. Do NOT re-describe what's in the painting; Lyria can see it.

Use this Lyria 3 Pro format:

PROMPT:
[Genre + BPM + key + 4-6 specific instruments with role description]

[0:00 - 0:xx] Intro: [arrangement description — no lyrics in timestamp lines]
[0:xx - 0:xx] Development: [...]
[0:xx - 1:xx] Core: [...]
[1:xx - 2:xx] Climax or turn: [...]
[2:xx - end] Resolution: [...]

[If you choose to include vocals — place lyric blocks here after the timestamps]
[If instrumental — write "Instrumental only, no vocals." at the end of the PROMPT]

STYLE NOTES:
[Vocal style if applicable / Production character / Spatial imaging / Dynamic arc]

The music can be purely instrumental or have lyrics inspired by the visual theme — your artistic choice as LyriaComposer.

--- PHASE 5: GENERATE MUSIC FROM IMAGE ---
After LyriaComposer responds, immediately assign:
[ASSIGN MusicGen]: Generate this music — PROMPT: <paste LyriaComposer's exact PROMPT section content here verbatim — do not add or change anything>

MusicGen will automatically detect the cover image from the session manuscript and pass it to Lyria as a second visual input alongside your text prompt.

--- PHASE 6: WEBSITE ---
[ASSIGN WebDev]: Build a complete single-page HTML website for this visual-music work.

The manuscript above contains all the data. Extract from it:
- Title (from VisualConcepter's TITLE)
- Visual concept (from VisualConcepter's VISUAL THEME and ATMOSPHERIC and EMOTIONAL CORE)
- Cover image path: look for a path ending in .png or .jpg — use only the filename. Reference as: ../images/<filename>
- Audio path: look for a path ending in .mp3 or .wav — use only the filename. Reference as: ../music/<filename>

Design requirements:
- Full-bleed cover art hero at top with the title overlaid — large, airy typography that doesn't fight the painting
- HTML5 audio player styled to match the visual palette (custom CSS, not default browser UI)
- Visual concept section: VISUAL THEME, ATMOSPHERE, EMOTIONAL CORE — in a calm, readable layout
- COLOR LANGUAGE section: display each color phrase as a visual swatch strip with label
- Responsive and mobile-first
- Use Tailwind CSS via CDN
- The aesthetic should feel like a gallery card for the painting — spare, contemplative, unhurried white space
- Output the COMPLETE HTML as a single self-contained file in a markdown code block

[TASK_COMPLETE]
MISSION

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------
ofp-playground start \
  --policy showrunner_driven \
  --no-human \
  --topic "$TOPIC" \
  --agent "google:orchestrator:Showrunner:${SHOWRUNNER}:gemini-3.1-pro-preview" \
  --agent "google:text-generation:VisualConcepter:You are a visual artist and art critic with deep knowledge of colour theory, painting traditions, and the relationship between visual and sonic art. You translate themes into precise visual language: specific pigment names, light conditions, atmospheric qualities, compositional energy. You think about paintings as emotional experiences that can be heard as much as seen. Be exact and evocative — name colours precisely, describe physical sensations concretely, avoid generic abstraction." \
  --agent "google:text-generation:CoverArtist:@creative/impressionist-painter" \
  --agent "google:text-to-image:ImageGen:You are a professional image generation specialist. When assigned an image prompt, generate the image exactly as described. Do not alter, summarize, or interpret the prompt — render it precisely.:gemini-3-pro-image-preview" \
  --agent "google:text-generation:LyriaComposer:@creative/lyria-composer" \
  --agent "google:text-to-music:MusicGen::lyria-3-pro-preview" \
  --agent "google:code-generation:WebDev:You are an expert web developer specializing in gallery and media web experiences. When assigned, create a complete single-page HTML website. Use Tailwind CSS via CDN for styling. Design for a contemplative gallery aesthetic — spare, typographic, white space with the painting as the hero. Output the complete HTML as a single self-contained file wrapped in a markdown code block.:gemini-3.1-pro-preview"
