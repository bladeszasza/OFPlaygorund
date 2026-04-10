#!/bin/bash
# example_song_production.sh
# Full song production pipeline: concept → lyrics → music → cover art → website
#
# Agents:
#   - google:orchestrator           → Showrunner (coordinates all phases)
#   - google:text-generation        → UXResearcher (@creative/ux-researcher — listener profile)
#   - google:text-generation        → SongConcepter (song theme, structure, instruments)
#   - google:text-generation        → Lyricist (writes full song lyrics)
#   - google:text-generation        → MusicProducer (@creative/music-producer — production brief)
#   - google:text-generation        → AudioProducer (@creative/audio-producer — mix & technical notes)
#   - google:text-generation        → LyriaComposer (@creative/lyria-composer — Lyria prompt engineer)
#   - google:text-to-music          → MusicGen (renders the Lyria prompt verbatim)
#   - google:text-generation        → CoverArtist (@creative/impressionist-painter)
#   - google:text-to-image          → ImageGen (renders the cover art prompt verbatim)
#   - google:code-generation        → WebDev (builds the final website)
#
# Two-step pattern for both music and image (same as manga example):
#   Persona agent (text-gen) → writes a richly styled prompt in their creative language
#   Generic executor (text-to-music / text-to-image) → renders that prompt verbatim
#
# Pipeline:
#   1. SongConcepter: song title, emotional story, themes, structure, instruments, BPM, key
#   2. Lyricist: complete lyrics with [Verse 1] [Chorus] [Bridge] etc. section labels
#   3. MusicProducer: production brief — arrangement approach, sound references, instrument character
#   4. AudioProducer: technical mix notes — signal chain character, sonic texture, processing vision
#   5. LyriaComposer: Lyria 3 Pro prompt enriched with all above context
#   6. MusicGen: generates the audio
#   7. UXResearcher: listener profile informed by the finished song — guides cover art + website aesthetic
#   8. CoverArtist: Van Gogh impressionist prompt guided by UXResearcher's visual world
#   9. ImageGen: renders the cover art
#  10. WebDev: single-page HTML site — cover art hero, audio player, lyrics, song story
#      Design aesthetic driven by UXResearcher's website feel notes
#      Uses relative paths: ../images/<file> and ../music/<file> from result/code/
#
# Usage:
#   bash example_song_production.sh [topic]
#   bash example_song_production.sh "The bittersweet joy of leaving home for the first time"
#
# Requirements:
#   - GOOGLE_API_KEY (all generation agents)
#   - ANTHROPIC_API_KEY (WebDev coding agent)
#   - ofp-playground CLI installed
#   - ./agents library available

set -e

TOPIC="${1:-Chord progression: C — F — C — F — Am — G — F — G (C major key). \
C and F are the warm grounded backbone. Am brings emotional dip — melancholy and vulnerability. \
G is the tension chord resolving back to C, giving gentle forward pull. \
The loop is smooth and cyclical, like breathing. \
Genre: melodic Rock ballad. Tempo: mid-tempo, unhurried, reflective. \
Duration target: ~3.5 minutes. Likely acoustic guitar-driven with soft intimate production. \
The C–F–Am–G pattern mirrors campfire songs, bedroom recordings, late-night conversations. \
Lyrical theme: quiet loyal friendship — steady presence without drama. \
C→F feels like gentle reassurance, a hand on the shoulder. \
Am drop mirrors heavier emotional moments — loss, shadow, endurance. \
G→C resolution feels like exhaling — coming back to safety, back to the friend beside you.}"

echo "Starting Song Production Pipeline"
echo "   Topic: $TOPIC"
echo ""

# ---------------------------------------------------------------------------
# Showrunner mission brief
# ---------------------------------------------------------------------------
read -r -d '' SHOWRUNNER <<MISSION || true
You are the creative director of a full song production pipeline. Your mission: produce a complete, publication-ready song for this topic: ${TOPIC}

Execute the following phases IN ORDER. Do not skip ahead. Wait for each agent to complete before moving on. Copy prompts VERBATIM — never paraphrase, summarize, or modify creative agent outputs when relaying them to executor agents.

--- PHASE 1: SONG CONCEPT ---
[ASSIGN SongConcepter]: Think deeply about a song for this topic: ${TOPIC}

Output a complete song concept document with these sections:
- TITLE: The song title
- STORY: The emotional journey a listener goes on from first to last note (3-4 sentences)
- THEMES: 3-5 vivid, concrete images or metaphors that will recur throughout the song
- STRUCTURE: Intro / Verse 1 / Pre-Chorus / Chorus / Verse 2 / Bridge / Outro — one sentence per section describing its emotional purpose
- INSTRUMENTS: 4-6 specific instruments and why each serves the emotional arc
- SONIC PROFILE: BPM, musical key, overall sonic character (warm/cold, dense/sparse, etc.)
- LISTENER IMPACT: The exact emotional state you want the listener to feel at the final note

--- PHASE 2: LYRICS ---
[ASSIGN Lyricist]: Using SongConcepter's concept, write complete song lyrics.

Format each section with a label on its own line:
[Intro]
[Verse 1]
[Pre-Chorus]
[Chorus]
[Verse 2]
[Bridge]
[Outro]

Write lyrics that are emotionally resonant with vivid imagery, internal rhyme, and a clear emotional arc. The chorus must be immediately memorable. Never use clichés — find the specific, surprising image.

--- PHASE 3: PRODUCTION BRIEF ---
Step 3a — MusicProducer defines the arrangement:
[ASSIGN MusicProducer]: Based on the song concept and lyrics from the previous agents, write a detailed production brief for this song. Output:
- ARRANGEMENT: How the song builds and breathes from intro to outro (density, layers, dynamics arc)
- INSTRUMENTATION SPEC: Each instrument's exact role, playing style, and position in the mix (e.g. "acoustic guitar: fingerpicked, panned 10% left, intimate dry room sound")
- SOUND REFERENCES: 2-3 real reference tracks (artist — track title) that capture the sonic direction
- PRODUCTION CHARACTER: The overall production philosophy (bedroom recording warmth? radio-ready polish? live-room rawness?)
- TEMPO & FEEL: Exact BPM, feel (straight/swung), and how the rhythm section locks

Step 3b — AudioProducer defines the technical mix vision:
[ASSIGN AudioProducer]: Based on MusicProducer's production brief and the song concept, write the technical audio production notes. Output:
- SIGNAL CHAIN CHARACTER: How each main instrument should be processed (EQ curve character, compression approach, any notable effects)
- MIX VISION: Where each element sits in the stereo field and frequency spectrum
- REVERB & SPACE: What kind of space this song lives in (dry and close? a specific room? plate reverb on the vocals?)
- DYNAMIC RANGE: Target loudness feel (intimate whisper to full drop ratio), whether the song breathes or stays dense
- SONIC TEXTURE NOTES: Any specific sonic details that must come through (vinyl crackle, breath before a phrase, string rosin, etc.)

--- PHASE 4: LYRIA MUSIC PROMPT ---
Step 4a — LyriaComposer writes the music generation prompt:
[ASSIGN LyriaComposer]: Using the song concept, lyrics, MusicProducer's production brief, and AudioProducer's mix vision, craft a Lyria 3 Pro music generation prompt that precisely captures this song. Embed the complete lyrics using the section tags from the Lyricist. Follow your prompt format exactly:

PROMPT: (genre, BPM, key, 4-6 specific instruments with role description informed by MusicProducer's spec, timestamp structure covering ~3.5 minutes with section-by-section description, embedded lyrics per section, mood and texture descriptors informed by AudioProducer's notes)
STYLE NOTES: (vocal style, production character, any specific sonic details)

Step 4b — After LyriaComposer responds, immediately assign:
[ASSIGN MusicGen]: Generate this music — PROMPT: <paste LyriaComposer's exact PROMPT section content here verbatim — do not add or change anything>

--- PHASE 5: LISTENER PROFILE ---
Now that the song exists, profile the audience it will reach.
[ASSIGN UXResearcher]: The song has been composed. Based on the complete song concept, lyrics, production brief, and audio notes in the manuscript, profile the ideal listener for this song. Output a LISTENER PROFILE with:
- WHO: demographic and psychographic sketch (age range, life situation, when and where they'd hear this)
- EMOTIONAL STATE: what they are feeling when they press play — the wound or longing this song speaks to
- WHAT THEY NEED: what this song does for them emotionally — catharsis, validation, company, courage?
- VISUAL WORLD: what imagery, palette, and aesthetic resonates with this listener (this will guide the cover art)
- WEBSITE FEEL: what design language speaks to this listener (rough and handmade? clean and minimal? cinematic?)
- SUCCESS METRIC: how you would know this song landed — one specific sentence describing their reaction

--- PHASE 6: COVER ART ---
Step 6a — CoverArtist writes the painting prompt:
[ASSIGN CoverArtist]: Using the song concept and UXResearcher's VISUAL WORLD notes, create a Van Gogh impressionist oil painting cover art image generation prompt. The painting must embody the song's emotional core — its palette, motion, and atmosphere should make someone feel the song before hearing it. Follow your format exactly:

PROMPT: (subject, Van Gogh period reference, dominant palette with specific pigment names, brushwork direction for each surface, composition and focal point, emotional temperature, "oil on canvas, thick impasto")
NEGATIVE PROMPT: (what to suppress)
PAINTER'S NOTE: (period, dominant emotion, technical priority)

Step 6b — After CoverArtist responds, immediately assign:
[ASSIGN ImageGen]: Generate this image — PROMPT: <paste CoverArtist's exact PROMPT section content here verbatim>

--- PHASE 7: WEBSITE ---
[ASSIGN WebDev]: Build a complete single-page HTML website for this song.

The manuscript above contains all the song data. Extract from it:
- Song title (from SongConcepter's TITLE)
- Song story/concept (from SongConcepter's STORY and THEMES)
- Complete lyrics (from Lyricist's output, all sections with labels)
- Cover image path: look for a path ending in .png or .jpg — use only the filename, not the full path. Reference it as: ../images/<filename>
- Audio path: look for a path ending in .mp3 or .wav — use only the filename. Reference it as: ../music/<filename>
- Design direction: use UXResearcher's WEBSITE FEEL notes to guide the aesthetic

Design requirements:
- Full-bleed cover art hero at top with the song title overlaid in large typography
- HTML5 audio player styled to match the theme (custom CSS, not default browser UI)
- Lyrics section: each section label ([Verse 1] etc.) in an accent color, lyrics in a readable serif font, generous line-height
- Song story section with the concept and themes
- Responsive and mobile-first
- Use Tailwind CSS via CDN
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
  --agent "hf:text-generation:UXResearcher:@creative/ux-researcher" \
  --agent "google:text-generation:SongConcepter:You are a creative music director and song architect. You think about songs as emotional experiences with a beginning, middle, and end. You develop complete song concepts: title, emotional story arc, thematic imagery, section-by-section structure with purpose, instrument selection with rationale, tempo, key, and intended listener impact. Be specific and evocative — name instruments precisely, describe emotions concretely, think about how every sonic choice serves the story." \
  --agent "google:text-generation:Lyricist:You are a professional lyricist and poet. You write songs with emotional depth, vivid imagery, and memorable hooks. You understand song structure deeply and how to serve a song's emotional arc with words. You use internal rhyme, slant rhyme, and concrete specificity. You never use clichés — you find the unexpected, true image. Output lyrics with clear section labels on their own lines: [Intro], [Verse 1], [Pre-Chorus], [Chorus], [Verse 2], [Bridge], [Outro].:gemini-3.1-pro-preview" \
  --agent "hf:text-generation:MusicProducer:@creative/music-producer" \
  --agent "google:text-generation:AudioProducer:@creative/audio-producer" \
  --agent "google:text-generation:LyriaComposer:@creative/lyria-composer" \
  --agent "google:text-to-music:MusicGen::lyria-3-pro-preview" \
  --agent "google:text-generation:CoverArtist:@creative/impressionist-painter" \
  --agent "google:text-to-image:ImageGen:You are a professional image generation specialist. When assigned an image prompt, generate the image exactly as described. Do not alter, summarize, or interpret the prompt — render it precisely." \
  --agent "google:code-generation:WebDev:You are an expert web developer specializing in music and media web experiences. When assigned, create a complete single-page HTML website. Use Tailwind CSS via CDN for styling. Design for dark atmospheric music aesthetics. Output the complete HTML as a single self-contained file wrapped in a markdown code block.:gemini-3.1-pro-preview"
