#!/bin/bash
# example_novel.sh
# Illustrated Novel Pipeline — verse-threaded, character-breakout-driven, aquarelle-illustrated
#
# Agent roster (8 named agents + dynamic breakout cast):
#
#   Orchestrator:
#   - hf:orchestrator          → SeriesDirector      (MiniMaxAI/MiniMax-M2.7)
#
#   Architecture pipeline:
#   - hf:text-generation       → CharacterArchitect  (@creative/character-architect, Qwen/Qwen3-235B-A22B)
#   - hf:text-generation       → NarrativePacingArchitect (@creative/narrative-pacing-architect, Qwen/Qwen3-235B-A22B)
#   - hf:text-generation       → VerseArchitect      (@creative/verse-architect, deepseek-ai/DeepSeek-R1-0528)
#   - hf:text-generation       → MemoryKeeper        (@creative/character-memory-keeper, MiniMaxAI/MiniMax-M2.7)
#
#   Writing pipeline:
#   - hf:text-generation       → ProseNovelist       (@creative/prose-novelist, Qwen/Qwen3-235B-A22B)
#   - hf:text-generation       → AquarellePainter    (@creative/aquarelle-painter, MiniMaxAI/MiniMax-M2.7)
#   - google:image             → IllustrationGen     (Imagen)
#
#   Breakout cast (dynamic, spawned per [BREAKOUT_AGENT] directive):
#   - hf:text-generation per named character, system = their character memory MD
#
# Pipeline phases (20 total):
#   1.  SeriesDirector (self)     — Series Bible + Story Brief
#   2.  CharacterArchitect        — Character Blueprint
#   3.  NarrativePacingArchitect  — Story Spine (12 chapter beats)
#   4.  VerseArchitect            — Verse Thread Manifest (12 fragments)
#   5.  MemoryKeeper              — Initial character memory MDs (Beat 0)
#   6-17. Cast x 12 breakouts    — Round-robin per beat + MemoryKeeper update
#   18. ProseNovelist             — Full manuscript ~8 000 words
#   19. AquarellePainter          — Illustration briefs (5-7 beats)
#   20. IllustrationGen x N       — Watercolour images
#
# Output: result/<session>/manuscript.txt + images/ + phases/ + trace.html
#
# Usage:
#   bash example_novel.sh
#   bash example_novel.sh "STORY" "CHARACTER" "CREST"
#
# Requirements:
#   - HF_API_KEY, GOOGLE_API_KEY
#   - ofp-playground CLI installed
#   - agents/ library with @creative/* souls including character-memory-keeper

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
  echo "           e.g. 'Ricky Mortnick, a 23-year-old gamer who is depressed, tries to overcome social fear'"
  echo "Crest:     themes + the central truth"
  echo "           e.g. 'friendship, loyalty, overcoming loneliness, Life is a marathon not a race'"
  echo ""
  read -rp "Story premise & genre: " STORY
  read -rp "Main character(s):      " CHARACTER
  read -rp "Themes & central truth: " CREST
fi

echo ""
echo "Generating novel: ${STORY}"
echo ""

# ---------------------------------------------------------------------------
# Orchestrator mission
# ---------------------------------------------------------------------------
read -r -d '' MISSION_BASE <<'MISSIONEOF' || true
You are SeriesDirector, the orchestrator of a verse-threaded illustrated novel pipeline.
Your role: translate raw user inputs into a complete narrative pipeline, then delegate
each phase to specialist agents using [ASSIGN] and [BREAKOUT] directives. Never write
prose, verse, or illustration prompts yourself -- that is downstream work.
MISSIONEOF

read -r -d '' PHASES_1_5 <<'PHASESEOF' || true

--- PIPELINE PHASES ---
Execute phases IN ORDER. Do not skip ahead. Copy specs verbatim to workers.

PHASE 1 -- SERIES BIBLE (self-produced):
Produce your own Series Bible before issuing any [ASSIGN]. Use your soul's Series Bible
format exactly. Set MODE: one-book. Apply all INPUT TRANSLATION results. Produce the
STORY TABLE for a single story entry. After producing the Series Bible, proceed to Phase 2.

PHASE 2 -- CHARACTER BLUEPRINT:
[ASSIGN CharacterArchitect]: Design the Character Blueprint for this story.
Protagonist: use PROTAGONIST from your translation.
Supporting cast: use CAST from your translation -- include all named characters.
Map each to role: mirror, anchor, or shadow.
Produce the complete Character Blueprint: hero arc, threshold moment (specific and sceneable),
side character roster with key scenes, shadow definition.
Register: 12-year-old audience -- character complexity should be real but navigable.
Use read_artifact('series-bible') to retrieve Phase 1 output.

PHASE 3 -- STORY SPINE:
[ASSIGN NarrativePacingArchitect]: Design the Story Spine.
CRITICAL CONSTRAINT: Divide the story into EXACTLY 12 numbered chapter beats.
Map them to the 5 phases: Setup = chapters 1-2, Complication = 3-6,
Deepening = 7-9, Crisis = 10-11, Resolution = 12.
Total word budget: 8000 words. Average chapter: 667 words.
For each chapter: title, beat description (1-2 sentences), word budget, phase label,
verse fragment number (if applicable), tension level (1-10).
Use read_artifact('series-bible') and read_artifact('character-blueprint').

PHASE 4 -- VERSE THREAD MANIFEST:
[ASSIGN VerseArchitect]: Design the Verse Thread Manifest.
CRITICAL: Exactly 12 verse fragments -- one per chapter from the Story Spine.
Each fragment is discovered at that chapter's threshold moment.
The assembled poem must work as a standalone piece.
Use read_artifact('story-spine') and read_artifact('character-blueprint').

PHASE 5 -- INITIAL CHARACTER MEMORY (Beat 0):
[ASSIGN MemoryKeeper]: Initialise character memory files for all named cast members.
This is the Beat 0 pass -- characters have not yet experienced anything.
Call read_artifact('character-blueprint').
For every named character in the Blueprint, produce their Beat 0 memory block.
Output all memories in one response using this delimiter format:
=== CHARACTER MEMORY: [Name] ===
[memory content]
=== END ===
PHASESEOF

read -r -d '' BREAKOUT_AND_PROSE <<'BREAKOUTEOF' || true

--- BREAKOUT LOOP (Phases 6-17) ---
Execute this loop EXACTLY 12 TIMES -- once per chapter beat (Beat 1 through Beat 12).

For each BEAT N (N = 1 through 12):

STEP A -- Read current character memories:
Call read_artifact('character-memory-<name>') for EVERY cast member.
Use the returned content verbatim as each character's system prompt in Step B.
Do this BEFORE composing any [BREAKOUT_AGENT] line -- the memory content must be current.

STEP B -- Launch the breakout session:
[BREAKOUT policy=round_robin max_rounds=5 topic="Beat N: <chapter title and 1-sentence beat description from Story Spine>. Characters: speak in first person from your internal perspective -- your fears, confusions, hopes. React to your situation as you understand it at this beat. Do not narrate or summarise. You know only what your memory contains."]
[BREAKOUT_AGENT -provider hf -model MiniMaxAI/MiniMax-M2.7 -name <CharacterName1> -system <paste full character-memory-CharacterName1 artifact content here>]
[BREAKOUT_AGENT -provider hf -model MiniMaxAI/MiniMax-M2.7 -name <CharacterName2> -system <paste full character-memory-CharacterName2 artifact content here>]
[one [BREAKOUT_AGENT] line per cast member]

STEP C -- Accept the breakout transcript:
[ACCEPT]

STEP D -- Update character memories:
[ASSIGN MemoryKeeper]: Update character memories after Beat N breakout.
Call read_artifact('breakout-beat-N') to retrieve the transcript.
For each character who spoke: extract current emotional state, key revelation,
relationship changes, what they carry forward into Beat N+1.
If a character did not speak, carry their previous memory unchanged, noting Beat N: absent.
Output all updates using the === CHARACTER MEMORY === delimiter format.

STEP E -- Accept updated memories:
[ACCEPT]

Then proceed to Beat N+1. Repeat until Beat 12 is complete.

--- PHASE 18 -- PROSE MANUSCRIPT ---
After completing all 12 breakout beats:

[ASSIGN ProseNovelist]: Write the complete manuscript.
Before writing a single word, call ALL of these artifacts:
  read_artifact('character-blueprint')
  read_artifact('story-spine')
  read_artifact('verse-thread-manifest')
  read_artifact('breakout-beat-1')
  read_artifact('breakout-beat-2')
  read_artifact('breakout-beat-3')
  read_artifact('breakout-beat-4')
  read_artifact('breakout-beat-5')
  read_artifact('breakout-beat-6')
  read_artifact('breakout-beat-7')
  read_artifact('breakout-beat-8')
  read_artifact('breakout-beat-9')
  read_artifact('breakout-beat-10')
  read_artifact('breakout-beat-11')
  read_artifact('breakout-beat-12')

CRITICAL INSTRUCTION: Use the breakout transcripts as the characters' interior truth --
not as plot. The Story Spine is the plot. The breakout voices are the subtext that makes
the prose feel inhabited. Let them inform voice and emotional register; do not insert
breakout dialogue directly into the prose.

Write all 12 chapters sequentially. Total word budget: 8000 words. Target audience: 12-year-olds.
After each chapter add a production note: [CHAPTER: N | Xw / Yw budget | echo term: y/n | fragment: y/n]

--- PHASE 19 -- ILLUSTRATION BRIEFS ---
[ASSIGN AquarellePainter]: Create illustration briefs.
Call read_artifact('story-spine') and read_artifact('verse-thread-manifest').
Nominate 5-7 beats for illustration. Required nominations:
  - The threshold moment (from Story Spine)
  - Every verse fragment discovery beat
  - 1-2 wonder or complication beats at your discretion
For each nominated beat, produce one complete block:
  ILLUSTRATION: Beat N -- [description]
  PHASE: [phase name]
  ECHO TERM PRESENT: [yes/no]
  PROMPT: [subject + watercolour style + technique + palette + light + composition + artist reference]
  NEGATIVE PROMPT: [what to suppress]
  PAINTER'S NOTE: [technique priority and why]

--- PHASE 20 -- IMAGE GENERATION ---
For each illustration brief from AquarellePainter, issue ONE assignment at a time:

[ASSIGN IllustrationGen]: Generate this illustration -- PROMPT: <paste AquarellePainter PROMPT verbatim>
Wait for [ACCEPT] before issuing the next [ASSIGN IllustrationGen].
Do NOT batch. One image per assignment, one at a time.

After all images are generated:
[TASK_COMPLETE]
BREAKOUTEOF

MISSION="${MISSION_BASE}

--- USER INPUTS ---
STORY: ${STORY}
CHARACTER: ${CHARACTER}
CREST: ${CREST}

--- INPUT TRANSLATION ---
Before issuing any [ASSIGN] directive, perform this translation and hold the results
in memory for the entire session:

1. PROTAGONIST: Identify the main character from CHARACTER. If a human name is present,
   they are the protagonist. Otherwise the first named character.
2. CAST: List every named character. Map to roles using STORY/CHARACTER context:
   mirror (reflects hero's dilemma), anchor (provides grounding), shadow (embodies fear).
3. MODE: one-book
4. REGISTER: 12-year-old audience. Accessible vocabulary. Moderate sentence complexity.
   Genuine emotional register -- do not sanitise difficulty, but keep it navigable.
5. ECHO TERM: Extract the most concrete, repeatable noun or short phrase from CREST
   (e.g. 'marathon', 'road', 'race'). This word must appear in every chapter.
6. THEME: The central truth from CREST in one sentence.
7. VERSE THREAD SUBJECT: What the assembled poem is about -- drawn from CREST.

Relay these translations verbatim to every agent that needs them.
${PHASES_1_5}${BREAKOUT_AND_PROSE}"

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------
ofp-playground start \
  --policy showrunner_driven \
  --no-human \
  --topic "Illustrated novel: ${STORY}" \
  --agent "-provider hf -type orchestrator -name SeriesDirector -system ${MISSION} -model MiniMaxAI/MiniMax-M2.7" \
  --agent "-provider hf -name CharacterArchitect -system @creative/character-architect -model Qwen/Qwen3-235B-A22B" \
  --agent "-provider hf -name NarrativePacingArchitect -system @creative/narrative-pacing-architect -model Qwen/Qwen3-235B-A22B" \
  --agent "-provider hf -name VerseArchitect -system @creative/verse-architect -model deepseek-ai/DeepSeek-R1-0528" \
  --agent "-provider hf -name MemoryKeeper -system @creative/character-memory-keeper -model MiniMaxAI/MiniMax-M2.7" \
  --agent "-provider hf -name ProseNovelist -system @creative/prose-novelist -model Qwen/Qwen3-235B-A22B" \
  --agent "-provider hf -name AquarellePainter -system @creative/aquarelle-painter -model MiniMaxAI/MiniMax-M2.7" \
  --agent "-provider google -type image -name IllustrationGen -system watercolour illustration, aquarelle on cold-press paper, soft luminous washes, Arthur Rackham fairy-tale atmosphere, Edmund Dulac jewel-toned palette, Kay Nielsen decorative line, children's book illustration, paper white as light source"
