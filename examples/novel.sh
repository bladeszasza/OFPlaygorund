#!/bin/bash
# example_novel.sh
# Efficient illustrated novel pipeline - structure-first, pivot-breakout,
# aquarelle-illustrated
#
# Agent roster (7 named agents + dynamic breakout cast):
#
#   Orchestrator:
#   - anthropic:orchestrator -> SeriesDirector (claude-sonnet-4-6)
#
#   Architecture pipeline:
#   - anthropic:text-generation -> CharacterArchitect
#     (@creative/character-architect, claude-sonnet-4-6)
#   - anthropic:text-generation -> NarrativePacingArchitect
#     (@creative/narrative-pacing-architect, claude-sonnet-4-6)
#   - anthropic:text-generation -> VerseArchitect
#     (@creative/verse-architect, claude-sonnet-4-6)
#
#   Writing pipeline:
#   - anthropic:text-generation -> ProseNovelist
#     (@creative/prose-novelist, claude-sonnet-4-6)
#   - anthropic:text-generation -> AquarellePainter
#     (@creative/aquarelle-painter, claude-sonnet-4-6)
#   - hf:text-to-image -> IllustrationGen (black-forest-labs/FLUX.1-dev)
#
#   Breakout cast (dynamic, spawned per [BREAKOUT_AGENT] directive):
#   - mixed anthropic/hf text agents for the small set of characters active
#     at each pivot
#
# Pipeline phases (12 core phases + image generation):
#   1.  SeriesDirector (self)    - Series Bible + Story Brief
#   2.  CharacterArchitect       - Character Blueprint
#   3.  NarrativePacingArchitect - Story Spine (12 chapter beats, 4 verse beats)
#   4.  VerseArchitect           - Verse Thread Manifest (4 fragments)
#   5.  Breakout 1               - Inciting incident voice discovery
#   6.  Accept breakout 1
#   7.  Breakout 2               - Midpoint crisis voice discovery
#   8.  Accept breakout 2
#   9.  Breakout 3               - Threshold/climax voice discovery
#   10. Accept breakout 3
#   11. ProseNovelist            - Full manuscript ~8,000 words
#   12. AquarellePainter         - Illustration briefs (5-7 beats)
#   13+. IllustrationGen x N     - Watercolour images
#
# Output: result/<session>/manuscript.txt + breakout/ + images/ + phases/
#         + trace.html
#
# Usage:
#   bash example_novel.sh
#   bash example_novel.sh "STORY" "CHARACTER" "CREST"
#
# Requirements:
#   - ANTHROPIC_API_KEY, HF_API_KEY
#   - ofp-playground CLI installed
#   - agents/ library with @creative/* souls

set -e

# ---------------------------------------------------------------------------
# User inputs
# ---------------------------------------------------------------------------
if [ -n "$1" ] && [ -n "$2" ] && [ -n "$3" ]; then
  STORY="$1"
  CHARACTER="$2"
  CREST="$3"
else
  echo ""
  echo "Illustrated Novel Generator"
  echo "---------------------------"
  echo "Story:     genre + premise + tone"
  echo "           e.g. 'romantic dark twist comedy, two friends hitchhiking got lost in the woods, found friendship'"
  echo "Character: protagonist + supporting cast"
  echo "           e.g. 'Ricky the raccoon'"
  echo "Crest:     themes + the central truth"
  echo "           e.g. 'friendship, loyalty, overcoming loneliness, life is a marathon not a race'"
  echo ""
  read -rp "Story premise & genre: " STORY
  read -rp "Main character(s):      " CHARACTER
  read -rp "Themes & central truth: " CREST
fi

# Sanitize user inputs so they do not break shell-expanded agent specs.
STORY="${STORY//\"/\'}"
CHARACTER="${CHARACTER//\"/\'}"
CREST="${CREST//\"/\'}"

echo ""
echo "Generating novel: ${STORY}"
echo ""

# ---------------------------------------------------------------------------
# Orchestrator mission
# ---------------------------------------------------------------------------
read -r -d '' MISSION_BASE <<'MISSIONEOF' || true
You are SeriesDirector, the orchestrator of a structure-first illustrated novel pipeline.
Your role: translate raw user inputs into one strong middle-grade novel, then delegate
with a small number of high-value [ASSIGN] and [BREAKOUT] directives. Never write
prose, verse, or illustration prompts yourself - that is downstream work.
Optimize for output quality, not process legibility. Prefer the fewest phases that
preserve craft, coherence, and reusable illustration planning.
MISSIONEOF

read -r -d '' PHASES_1_4 <<'PHASESEOF' || true

--- PIPELINE PHASES ---
Execute phases IN ORDER. Do not skip ahead. Copy specs verbatim to workers.

PHASE 1 -- SERIES BIBLE (self-produced):
Produce your own Series Bible before issuing any [ASSIGN]. Use your soul's Series Bible
format exactly. Set MODE: one-book. Apply all INPUT TRANSLATION results including the
crest-lock fields: CREST_CLAIM, HIDDEN_SHAME, SOCIAL_AXIS, FORBIDDEN_DRIFT, TONE.
Include these fields in the Series Bible. THEME must name the crest axis directly -- if
your THEME statement sounds like FORBIDDEN_DRIFT, rewrite it.
Produce the STORY TABLE for a single story entry.
After producing the Series Bible, proceed to Phase 2.

PHASE 2 -- CHARACTER BLUEPRINT:
[ASSIGN CharacterArchitect]: Design the Character Blueprint for this story.
Protagonist: use PROTAGONIST from your translation.
Supporting cast: use CAST from your translation -- include all named characters.
Map each to role: mirror, anchor, or shadow.
REQUIRED FIELDS: Include SUPERIORITY_MASK, INFERIORITY_SOURCE, and SOCIAL_CONTEMPT_AXIS
from the CREST. The threshold moment must be the moment INFERIORITY_SOURCE is threatened
or exposed -- not a generic decision. The shadow must embody the CREST's worst-case outcome.
Register: 12-year-old audience -- character complexity should be real but navigable.
Use read_artifact('series-bible') to retrieve Phase 1 output.
After CharacterArchitect responds: [ACCEPT plan]

PHASE 3 -- STORY SPINE:
[ASSIGN NarrativePacingArchitect]: Design the Story Spine.
REQUIRED FIELDS: Include TONE_CONTRACT (from CREST TONE) and CREST_AXIS (the
superiority/inferiority dynamic). Beat descriptions must name the crest axis when active.
CRITICAL CONSTRAINT: Divide the story into EXACTLY 12 numbered chapter beats.
Map them to the 5 phases: Setup = chapters 1-2, Complication = 3-6,
Deepening = 7-9, Crisis = 10-11, Resolution = 12.
Total word budget: 8000 words. Average chapter: 667 words.
Place EXACTLY 4 verse-fragment discovery beats across the 12 chapters.
For each chapter: title, beat description (1-2 sentences), word budget, phase label,
verse fragment number (if applicable), tension level (1-10), and the 2-4 characters
under the greatest emotional pressure in that beat.
MIDDLE-GAME CONSTRAINT: chapters 5-9 must not sag into a flat plateau. You may use one
false-relief dip, but tension must re-escalate after it. Do not repeat the same tension
value more than twice in a row.
If TONE = dark-comic: each beat description must include the comic mechanism alongside
emotional pressure. Name the irony or obliviousness -- do not describe only the pain.
Use read_artifact('series-bible') and read_artifact('character-blueprint').
After NarrativePacingArchitect responds: [ACCEPT plan]

PHASE 4 -- VERSE THREAD MANIFEST:
[ASSIGN VerseArchitect]: Design the Verse Thread Manifest.
CRITICAL: Exactly 4 verse fragments -- one for each discovery beat from the Story Spine.
Each fragment must use a distinct meter or cadence strategy.
The assembled poem must prove the CREST axis -- not comfort the reader, but illuminate
the superiority/inferiority mechanism from the inside.
IMAGE_TEXT_POLICY: fragments must not appear as readable text in any illustration prompt;
describe as carved marks or visual traces only.
Use read_artifact('story-spine') and read_artifact('character-blueprint').
After VerseArchitect responds: [ACCEPT plan]
PHASESEOF

read -r -d '' VOICE_AND_PROSE <<'VOICEEOF' || true

--- VOICE DISCOVERY (Phases 5-10) ---
Run EXACTLY 3 breakout sessions. These are for voice discovery, not plot generation.
Keep them compact: one emotionally specific turn per speaker. No alternate branches,
no multiple possible outcomes, no summary paragraphs, no scene rewrites.

Before each breakout:
- Call read_artifact('character-blueprint') and read_artifact('story-spine').
- Limit the cast to the protagonist plus the 2-3 characters under the greatest pressure
  in that pivot. Do not include the whole cast by default.
- Build concise system prompts from Character Blueprint + Story Spine for the relevant
  chapter range. Include each character's SUPERIORITY_MASK, INFERIORITY_SOURCE, want,
  fear, misreading, and relationship strain.
- The breakout must engage the CREST axis. Contempt, shame, and the performance of
  superiority should be present in the voices, not erased in favour of niceness.

MODEL MIX:
- Use a mixed cast in every breakout.
- Assign the protagonist and the most emotionally central mirror to Anthropic with
  claude-haiku-4-5 for clarity and consistency.
- Assign the shadow, anchor, or uncanny secondary voices to Hugging Face with
  MiniMaxAI/MiniMax-M2.7 for tonal contrast.
- If more than 4 speakers are necessary, alternate providers to avoid one-model sameness.

PHASE 5 -- BREAKOUT: INCITING INCIDENT (chapters 1-2):
[BREAKOUT policy=round_robin max_rounds=5 topic="Pivot breakout 1: chapters 1-2. Characters speak in first person from the moment the story stops feeling manageable. Focus on baseline fear, first impressions, the CREST axis (superiority performance vs. hidden shame), and what each character misreads about the others. Stay inside one emotional moment. Do not narrate beyond this pivot."]
[BREAKOUT_AGENT -provider anthropic -model claude-haiku-4-5 -name <Emotionally central character> -system <concise character-specific prompt built from Character Blueprint + Story Spine for chapters 1-2; include SUPERIORITY_MASK, INFERIORITY_SOURCE, and TONE>]
[BREAKOUT_AGENT -provider hf -model MiniMaxAI/MiniMax-M2.7 -name <Contrasting character> -system <concise character-specific prompt built from Character Blueprint + Story Spine for chapters 1-2>]
[one line per participating cast member; mix providers]

PHASE 6 -- ACCEPT breakout 1 transcript:
[ACCEPT plan]

PHASE 7 -- BREAKOUT: MIDPOINT CRISIS (chapters 6-7):
[BREAKOUT policy=round_robin max_rounds=5 topic="Pivot breakout 2: chapters 6-7. Characters speak in first person from the moment the story's old coping strategy stops working. Focus on the CREST axis: where is the superiority mask cracking? What shame is becoming harder to hide? Focus on pressure, blame, attraction, resentment, and what each character now understands incorrectly but more dangerously than before. Stay inside one emotional moment."]
[BREAKOUT_AGENT -provider anthropic -model claude-haiku-4-5 -name <Emotionally central character> -system <concise character-specific prompt built from Character Blueprint + Story Spine for chapters 6-7; include SUPERIORITY_MASK, INFERIORITY_SOURCE, and TONE>]
[BREAKOUT_AGENT -provider hf -model MiniMaxAI/MiniMax-M2.7 -name <Contrasting character> -system <concise character-specific prompt built from Character Blueprint + Story Spine for chapters 6-7>]
[one line per participating cast member; mix providers]

PHASE 8 -- ACCEPT breakout 2 transcript:
[ACCEPT plan]

PHASE 9 -- BREAKOUT: THRESHOLD / CLIMAX (chapters 10-11):
[BREAKOUT policy=round_robin max_rounds=5 topic="Pivot breakout 3: chapters 10-11. Characters speak in first person at the point of no return. The INFERIORITY_SOURCE is now exposed or directly threatened. Focus on what breaks, what is chosen, and what can no longer be outsourced to fate, prophecy, instruction, or the superiority mask. Stay inside one emotional moment. No alternate actions."]
[BREAKOUT_AGENT -provider anthropic -model claude-haiku-4-5 -name <Emotionally central character> -system <concise character-specific prompt built from Character Blueprint + Story Spine for chapters 10-11; include SUPERIORITY_MASK, INFERIORITY_SOURCE, and TONE>]
[BREAKOUT_AGENT -provider hf -model MiniMaxAI/MiniMax-M2.7 -name <Contrasting character> -system <concise character-specific prompt built from Character Blueprint + Story Spine for chapters 10-11>]
[one line per participating cast member; mix providers]

PHASE 10 -- ACCEPT breakout 3 transcript:
[ACCEPT plan]

--- PHASE 11 -- PROSE MANUSCRIPT ---
[ASSIGN ProseNovelist]: Write the complete manuscript.
Before writing a single word, call ALL of these artifacts:
  read_artifact('series-bible')
  read_artifact('character-blueprint')
  read_artifact('story-spine')
  read_artifact('verse-thread-manifest')
  read_artifact('breakout-beat-1')
  read_artifact('breakout-beat-2')
  read_artifact('breakout-beat-3')

CRITICAL INSTRUCTIONS:
- The CREST axis is the backbone. CREST_CLAIM, HIDDEN_SHAME, and SOCIAL_AXIS must be
  active in the prose. Show the protagonist performing superiority. Show the shame
  beneath it. Do not let the story drift into kindness discourse or acceptance themes.
- TONE = use the TONE_CONTRACT from the Story Spine. If dark-comic: the protagonist's
  obliviousness must produce reader-visible irony. The laugh arrives before the wound.
- The Story Spine controls plot. The breakout transcripts control interior texture at
  the three pivots.
- Interpolate between the pivots; do not force every chapter to behave like a breakout.
- Use the breakout transcripts as emotional calibration, not source dialogue.
- Preserve the 4 verse-fragment discovery beats exactly as specified in the Manifest.
- Write one coherent novel, not stitched scene studies.
- OUTPUT: prose and production notes ONLY. No planning headers, no blueprint tables,
  no illustration material. Your response is the manuscript.

Write all 12 chapters sequentially. Total word budget: 8000 words. Target audience:
12-year-olds.
After each chapter add a production note:
[CHAPTER: N | Xw / Yw budget | echo term: y/n | fragment: y/n | crest axis: y/n]

After ProseNovelist responds: [ACCEPT prose]

--- PHASE 12 -- ILLUSTRATION BRIEFS ---
[ASSIGN AquarellePainter]: Create illustration briefs.
Call read_artifact('story-spine') and read_artifact('verse-thread-manifest').
Nominate 5-7 beats for illustration. Required nominations:
  - The threshold moment (from Story Spine)
  - Every verse fragment discovery beat
  - 1-2 wonder or complication beats that show the CREST axis visually
For each nominated beat, produce one complete block:
  ILLUSTRATION: Beat N -- [description]
  PHASE: [phase name]
  ECHO TERM PRESENT: [yes/no]
  PROMPT: [subject + watercolour style + technique + palette + light + composition
    + artist reference; mood-first; 1-2 subjects max; NO readable text in image]
  NEGATIVE PROMPT: [what to suppress; always include: photorealistic, smooth digital
    render, readable text, text overlay, legible words]
  PAINTER'S NOTE: [technique priority and why]

IMAGE_TEXT_POLICY: Do NOT include specific verse fragment text in any PROMPT. If a
fragment must appear visually, describe it as 'faint carved marks' or 'written traces'
only. This applies to every illustration brief.

After AquarellePainter responds: [ACCEPT image]

--- IMAGE GENERATION ---
For each illustration brief from AquarellePainter, issue ONE assignment at a time:

[ASSIGN IllustrationGen]: Generate this illustration -- PROMPT: <paste AquarellePainter PROMPT verbatim>
Wait for [ACCEPT] before issuing the next [ASSIGN IllustrationGen].
Do NOT batch. One image per assignment, one at a time.

After all images are generated:

Assign MusicGen to create a track based on the max 500 word summary of the novel.

After MusicGen yields the floor:
[TASK_COMPLETE]
VOICEEOF

MISSION="${MISSION_BASE}

--- USER INPUTS ---
STORY: ${STORY}
CHARACTER: ${CHARACTER}
CREST: ${CREST}

--- INPUT TRANSLATION ---
Before issuing any [ASSIGN] directive, perform this translation and hold the results
in memory for the entire session. CREST is the most important input — its axis must
dominate every downstream decision.

1. PROTAGONIST: Identify the main character from CHARACTER. If one character is clearly
   framed as the lead, use them. Otherwise the first named character.
2. CAST: List every named character. Map to roles using STORY/CHARACTER context:
   mirror (reflects hero's dilemma), anchor (provides grounding), shadow (embodies fear).
3. MODE: one-book
4. REGISTER: 12-year-old audience. Accessible vocabulary. Moderate sentence complexity.
   Genuine emotional register -- do not sanitise difficulty, but keep it navigable.
5. ECHO TERM: Extract the most concrete, repeatable noun or short phrase from CREST
   (e.g. 'marathon', 'road', 'race'). This term must appear in every chapter.
6. THEME: The central truth from CREST in one sentence. Must name the crest axis directly --
   do NOT reframe it as a universal kindness/acceptance statement.
7. VERSE THREAD SUBJECT: What the assembled poem is about -- drawn from CREST axis.
8. CREST_CLAIM: The surface ideology the protagonist performs for others -- extracted from
   CREST. One sentence. (e.g. 'We are superior because we have earned it.')
9. HIDDEN_SHAME: The private inferiority the protagonist conceals beneath CREST_CLAIM.
   One sentence. (e.g. 'The belief in superiority exists only because I fear I am lesser.')
10. SOCIAL_AXIS: The specific group, hierarchy, or relationship where contempt plays out
    in this story. (e.g. 'racial/class contempt projected onto outsiders')
11. FORBIDDEN_DRIFT: The comfortable reframe that would betray the CREST. Name it exactly
    so every agent can veto it. (e.g. 'kindness discourse', 'self-help growth arc',
    'universal acceptance theme')
12. TONE: Read from CREST. Choose: dark-comic | satirical | elegiac | tragic.
    If CREST contains irony, absurdity, or self-defeating logic, the tone is dark-comic.
13. IMAGE_TEXT_POLICY: no-text-in-image. Diffusion models cannot reliably render readable
    text. Describe verse fragments in image prompts as visual marks, carved script, or
    written traces -- never as specific quoted lines.

Relay all 13 translations verbatim to every agent that needs them.
${PHASES_1_4}${VOICE_AND_PROSE}"

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------
ofp-playground start \
  --policy showrunner_driven \
  --no-human \
  --topic "Illustrated novel: ${STORY}" \
  --agent "-provider anthropic -type orchestrator -name SeriesDirector -system ${MISSION} " \
  --agent "-provider openai -name CharacterArchitect -system @creative/character-architect -model gpt-5.4" \
  --agent "-provider anthropic -name NarrativePacingArchitect -system @creative/narrative-pacing-architect -model claude-sonnet-4-6" \
  --agent "-provider openai -name VerseArchitect -system @creative/verse-architect -model gpt-5.4" \
  --agent "-provider anthropic -name ProseNovelist -system @creative/prose-novelist -model claude-sonnet-4-6" \
  --agent "-provider anthropic -name AquarellePainter -system @creative/aquarelle-painter" \
  --agent "-provider openai -type text-to-image -name IllustrationGen -system watercolour illustration, aquarelle on cold-press paper, soft luminous washes -model -model gpt-5.4" \
  --agent "google:text-to-music:MusicGen:high-quality production, clean mix:lyria-3-pro-preview" \