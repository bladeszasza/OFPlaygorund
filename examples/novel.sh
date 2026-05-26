#!/bin/bash
# example_novel.sh
# Zeroverse illustrated novel pipeline - structure-first, pivot-breakout,
# ink-wash action illustrated
#
# Agent roster (10 named agents + dynamic breakout cast):
#
#   Orchestrator:
#   - anthropic:orchestrator -> SeriesDirector (claude-sonnet-4-6)
#
#   Architecture pipeline:
#   - openai:text-generation -> CharacterArchitect
#     (@creative/character-architect, gpt-5.4)
#   - anthropic:text-generation -> NarrativePacingArchitect
#     (@creative/narrative-pacing-architect, claude-sonnet-4-6)
#   - openai:text-generation -> VerseArchitect
#     (@creative/verse-architect, gpt-5.4)
#   - anthropic:text-generation -> LoreContinuityGuardian
#     (inline Zeroverse continuity + originality audit)
#   - anthropic:text-generation -> FightChoreographer
#     (inline battle-manga set-piece design)
#
#   Writing pipeline:
#   - anthropic:text-generation -> ProseNovelist
#     (@creative/prose-novelist, claude-sonnet-4-6)
#   - anthropic:text-generation -> RevisionEditor
#     (inline surgical manuscript revision brief)
#   - anthropic:text-generation -> AquarellePainter
#     (@creative/aquarelle-painter, claude-sonnet-4-6)
#   - openai:text-to-image -> IllustrationGen (default GPT Image model)
#
#   Breakout cast (dynamic, spawned per [BREAKOUT_AGENT] directive):
#   - mixed anthropic/openai text agents for the small set of characters active
#     at each pivot
#
# Pipeline phases (15 core phases + image generation):
#   1.  SeriesDirector (self)    - Series Bible + Story Brief
#   2.  CharacterArchitect       - Character Blueprint
#   3.  AquarellePainter         - Character anchor image briefs
#   4.  IllustrationGen x N      - Character anchor reference images
#   5.  NarrativePacingArchitect - Story Spine (10 chapter beats, 4 Zero Verse beats)
#   6.  VerseArchitect           - Zero Verse Thread Manifest (4 fragments)
#   7.  LoreContinuityGuardian   - Originality + power-system audit
#   8.  FightChoreographer       - Major action set pieces
#   9.  Breakout 1               - Tournament collapse voice discovery
#   10. Accept breakout 1
#   11. Breakout 2               - Possession / Zeroverse voice discovery
#   12. Accept breakout 2
#   13. Breakout 3               - Endgame / cliffhanger voice discovery
#   14. Accept breakout 3
#   15. ProseNovelist            - Draft manuscript ~10,000 words
#   16. RevisionEditor           - Surgical revision brief
#   17. ProseNovelist            - Revised final manuscript
#   18. AquarellePainter         - Illustration briefs (10-12 beats)
#   19+. IllustrationGen x N     - Ink-wash action images using anchor refs
#
# Output: result/<session>/manuscript.txt + breakout/ + images/ + phases/
#         + trace.html
#
# Usage:
#   bash example_novel.sh   # uses the built-in Zeroverse saga preset
#   bash example_novel.sh "STORY" "CHARACTER" "CREST"
#
# Requirements:
#   - ANTHROPIC_API_KEY, OPENAI_API_KEY, GOOGLE_API_KEY
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
  echo "Illustrated Zeroverse Novel Generator"
  echo "-------------------------------------"
  echo "Using built-in Zeroverse saga preset."
  echo "Pass STORY CHARACTER CREST as three arguments to override."
  echo ""
  STORY="original dark-edged cosmic martial-arts saga set three years after the last great peace, opening at a world tournament that collapses when a fallen spellmaker returns under the command of Jaitai, ruler of the Zeroverse"
  CHARACTER="Repa: joyful battle mentor with untamed black storm-spiked hair, bottomless appetite, tactical innocence, and a vanished aura-current after a Zeroverse blast; Oru: gentle successor whose purity is twisted into a grotesque void champion; Veya: fierce young fighter who unlocks a forbidden star-flare awakening; Brak and Toma: teen rivals whose reckless collision creates an unstable combined warrior; Hercan Vale: comic celebrity champion forced into real heroic fights; Bavik: fallen spellmaker demoted to servant; Jaitai: eldritch Zeroverse sovereign and shadow-counterpart to the cosmic guardians"
  CREST="Power without self-knowledge becomes a doorway for possession; pride turns monstrous when it refuses humility, and real strength begins when the hero can fight after the aura is gone."
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
Your role: translate raw user inputs into one strong shonen-cosmic action novel, then delegate
with a small number of high-value [ASSIGN] and [BREAKOUT] directives. Never write
prose, verse, or illustration prompts yourself - that is downstream work.
Optimize for output quality, not process legibility. Prefer the fewest phases that
preserve craft, coherence, and reusable illustration planning.

ORIGINALITY GUARD:
- Create an original Zeroverse saga. Do not use or mention existing franchise names,
  character names, species names, tournament names, planet names, techniques,
  transformation names, artifacts, or exact canon relationships from any existing manga.
- The desired influence is broad battle-manga energy: tournament pressure, cosmic stakes,
  joyful martial courage, monstrous possession, rival teamwork, and impossible last stands.
  Treat those as archetypes only. Make names, histories, powers, costumes, family ties,
  organizations, and emotional wounds distinct.
- Repa may be cheerful, hungry, battle-innocent, and visually wild-haired, but he must
  have original history, combat philosophy, powers, flaws, relationships, and stakes.
- Never produce a disguised retelling. If a beat feels too familiar, twist the cause,
  cost, image, or emotional consequence until it belongs to this story.
MISSIONEOF

read -r -d '' PHASES_1_4 <<'PHASESEOF' || true

--- PIPELINE PHASES ---
Execute phases IN ORDER. Do not skip ahead. Copy specs verbatim to workers.

ZERO SAGA LOCK:
Unless the user supplied different arguments, build a 10-chapter original Zeroverse
illustrated novel with these required landmarks: tournament chaos; Bavik's return as
Jaitai's servant; Oru's possession and grotesque void-champion transformation; the
Zeroverse reveal; Repa losing his aura-current after deflecting a Zeroverse blast;
Veya's star-flare awakening; Brak and Toma forming an unstable combined warrior by
collision; Hercan Vale winning meaningful fights despite his comic vanity; Jaitai's
rebirth; and a deliberate cliffhanger with two cosmic elders leaving to confront him.
The novel should feel darker and sharper than a cheerful adventure while remaining
readable for 12-15-year-olds. No gore, no nihilism, no franchise references.

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
Register: 12-15-year-old action-adventure audience -- character complexity should be
real but navigable. Give every major fighter an original aura-current signature, combat
limitation, visual silhouette, and emotional cost.
Use read_artifact('series-bible') to retrieve Phase 1 output.
After CharacterArchitect responds: [ACCEPT plan]

PHASE 2A -- CHARACTER ANCHOR IMAGE BRIEFS:
[ASSIGN AquarellePainter]: Create the character anchor image briefs for all recurring
major characters before the novel is drafted.
Call read_artifact('series-bible') and read_artifact('character-blueprint').
Make one anchor block for every named recurring fighter or major presence in the cast,
including Repa, Oru, Veya, Brak, Toma, Hercan Vale, Bavik, and Jaitai when present.
Each anchor must be a clean, reusable character reference image: full figure or
three-quarter portrait, original costume silhouette, aura-current signature, face,
hair, color notes, and one unique visual motif. No action scene, no readable text,
no logos, no franchise resemblance.
For each anchor, output exactly this block:
  CHARACTER_ANCHOR: [name]
  PROMPT: [single-character reference image prompt in dynamic ink-wash watercolour
    battle-manga style; neutral parchment or simple atmospheric background; include
    exact silhouette, costume, hair, face, aura-current, palette, age impression,
    and emotional posture; no readable text]
  NEGATIVE PROMPT: [photorealistic, smooth digital render, readable text, text overlay,
    legible words, existing franchise costume, existing franchise insignia]
  CONTINUITY NOTE: [how later illustrations should keep this character consistent]
After AquarellePainter responds: [ACCEPT image]

PHASE 2B -- CHARACTER ANCHOR IMAGE GENERATION:
Generate the character anchors before continuing to the Story Spine.
For each CHARACTER_ANCHOR block from AquarellePainter, issue ONE assignment at a time:

[ASSIGN IllustrationGen]: Generate character anchor image -- PROMPT: <paste that anchor PROMPT verbatim>
Wait for the image to be auto-accepted before issuing the next [ASSIGN IllustrationGen].
After every anchor image is generated, copy each absolute image path from the
auto-accepted [image by IllustrationGen] manuscript entry into a working
CHARACTER_ANCHOR_INDEX keyed by character name. Use these exact paths later in every
story illustration request.

PHASE 3 -- STORY SPINE:
[ASSIGN NarrativePacingArchitect]: Design the Story Spine.
REQUIRED FIELDS: Include TONE_CONTRACT (from CREST TONE) and CREST_AXIS (the
superiority/inferiority dynamic). Beat descriptions must name the crest axis when active.
CRITICAL CONSTRAINT: Divide the story into EXACTLY 10 numbered chapter beats.
Map them to the 5 phases: Tournament Setup = chapters 1-2, Possession War = 3-5,
Zeroverse Descent = 6-7, Cosmic Endgame = 8-9, Cliffhanger Resolution = 10.
Total word budget: 10000 words. Average chapter: 1000 words.
Place EXACTLY 4 Zero Verse fragment discovery beats across the 10 chapters.
Required landmark coverage: tournament chaos, Oru's transformation, Zeroverse reveal,
Repa losing aura-current, Veya's star-flare awakening, Brak/Toma collision-combination,
Hercan Vale's serious fight, Jaitai's rebirth, and the unresolved elder confrontation.
For each chapter: title, beat description (1-2 sentences), word budget, phase label,
verse fragment number (if applicable), tension level (1-10), and the 2-4 characters
under the greatest emotional pressure in that beat.
MIDDLE-GAME CONSTRAINT: chapters 4-8 must not sag into a flat plateau. You may use one
false-relief dip, but tension must re-escalate after it. Do not repeat the same tension
value more than twice in a row.
If TONE = dark-comic: each beat description must include the comic mechanism alongside
emotional pressure. Name the irony or obliviousness -- do not describe only the pain.
Use read_artifact('series-bible') and read_artifact('character-blueprint').
After NarrativePacingArchitect responds: [ACCEPT plan]

PHASE 4 -- ZERO VERSE THREAD MANIFEST:
[ASSIGN VerseArchitect]: Design the Verse Thread Manifest.
CRITICAL: Exactly 4 Zero Verse fragments -- one for each discovery beat from the Story Spine.
Each fragment must use a distinct meter or cadence strategy.
The assembled poem must prove the CREST axis -- not comfort the reader, but illuminate
the pride/possession mechanism from the inside.
IMAGE_TEXT_POLICY: fragments must not appear as readable text in any illustration prompt;
describe as carved marks or visual traces only.
Use read_artifact('story-spine') and read_artifact('character-blueprint').
After VerseArchitect responds: [ACCEPT plan]

PHASE 4A -- LORE + ORIGINALITY AUDIT:
[ASSIGN LoreContinuityGuardian]: Audit the Zeroverse lore, power system, and originality.
Call read_artifact('series-bible'), read_artifact('character-blueprint'),
read_artifact('story-spine'), and read_artifact('verse-thread-manifest').
OUTPUT EXACTLY THESE SECTIONS:
  ZERO RULES: 5-8 laws governing aura-current, Zeroverse energy, possession, and loss.
  CONTINUITY RISKS: contradictions or weak causal links, with fixes.
  ORIGINALITY RISKS: anything too close to existing franchise canon, with replacement ideas.
  MUST-PRESERVE: the strongest original names, images, costs, and emotional rules.
  DOWNSTREAM ORDERS: short instructions ProseNovelist and AquarellePainter must obey.
Keep it compact and actionable. Do not rewrite the story.
After LoreContinuityGuardian responds: [ACCEPT plan]

PHASE 4B -- FIGHT CHOREOGRAPHY:
[ASSIGN FightChoreographer]: Design the major action set pieces.
Call read_artifact('story-spine'), read_artifact('character-blueprint'), and
read_artifact('lore-continuity-guardian').
Design only the fights needed by the 10-chapter spine. For each fight, provide:
  SET PIECE: chapter / location / participants
  WANT: what each side wants besides winning
  EXCHANGE LADDER: 5-7 escalating beats, each changing tactics or stakes
  COST: physical, emotional, social, or spiritual price
  MONEY SHOT: one exact illustration-worthy image
  ORIGINALITY CHECK: how this avoids copied moves, forms, or canon dynamics
Required fights: tournament derailment, Oru's void-champion reveal, Repa's aura-current
loss, Veya's star-flare awakening, Brak/Toma collision-combination, Hercan Vale's real
fight, and Jaitai's rebirth/cliffhanger pressure.
After FightChoreographer responds: [ACCEPT plan]
PHASESEOF

read -r -d '' VOICE_AND_PROSE <<'VOICEEOF' || true

--- VOICE DISCOVERY (Breakout Phases) ---
Run EXACTLY 3 breakout sessions. These are for voice discovery, not plot generation.
Keep them compact: one emotionally specific turn per speaker. No alternate branches,
no multiple possible outcomes, no summary paragraphs, no scene rewrites.

Before each breakout:
- Call read_artifact('character-blueprint'), read_artifact('story-spine'),
  read_artifact('lore-continuity-guardian'), and read_artifact('fight-choreographer').
- Limit the cast to the protagonist plus the 2-3 characters under the greatest pressure
  in that pivot. Do not include the whole cast by default.
- Build concise system prompts from Character Blueprint + Story Spine for the relevant
  chapter range. Include each character's SUPERIORITY_MASK, INFERIORITY_SOURCE, want,
  fear, misreading, and relationship strain.
- The breakout must engage the CREST axis. Contempt, shame, and the performance of
  superiority should be present in the voices, not erased in favour of niceness.
- Breakouts must preserve originality: no existing franchise names, no direct move names,
  no copied relationships, and no winked references.

MODEL MIX:
- Use a mixed cast in every breakout.
- Use only Anthropic and OpenAI breakout agents.
- Do not specify -model in [BREAKOUT_AGENT] lines; let provider defaults apply.
- Assign the protagonist and the most emotionally central mirror to Anthropic.
- Assign the shadow, anchor, or uncanny secondary voices to OpenAI for tonal contrast.
- If more than 4 speakers are necessary, alternate providers to avoid one-model sameness.

PHASE 5 -- BREAKOUT: TOURNAMENT COLLAPSE (chapters 1-2):
[BREAKOUT policy=round_robin max_rounds=5 topic="Pivot breakout 1: chapters 1-2. Characters speak in first person from the instant the world tournament stops being sport and becomes supernatural siege. Focus on baseline fear, public bravado, Repa's cheerful misread, Oru's first inner fracture, Bavik's return, and what each fighter misunderstands about the Zeroverse threat. Stay inside one emotional moment. Do not narrate beyond this pivot."]
[BREAKOUT_AGENT -provider anthropic -name <Emotionally central character> -system <concise character-specific prompt built from Character Blueprint + Story Spine for chapters 1-2; include SUPERIORITY_MASK, INFERIORITY_SOURCE, and TONE>]
[BREAKOUT_AGENT -provider openai -name <Contrasting character> -system <concise character-specific prompt built from Character Blueprint + Story Spine for chapters 1-2>]
[one line per participating cast member; mix providers]

PHASE 6 -- ACCEPT breakout 1 transcript:
[ACCEPT plan]

PHASE 7 -- BREAKOUT: POSSESSION / ZEROVERSE REVEAL (chapters 5-6):
[BREAKOUT policy=round_robin max_rounds=5 topic="Pivot breakout 2: chapters 5-6. Characters speak in first person from the moment Oru's old self is almost unreachable and the Zeroverse is revealed as a living wound behind reality. Focus on pride as a doorway for possession, the shame of helpless masters, Repa losing aura-current, blame, loyalty, and what each character now understands incorrectly but more dangerously than before. Stay inside one emotional moment."]
[BREAKOUT_AGENT -provider anthropic -name <Emotionally central character> -system <concise character-specific prompt built from Character Blueprint + Story Spine for chapters 5-6; include SUPERIORITY_MASK, INFERIORITY_SOURCE, and TONE>]
[BREAKOUT_AGENT -provider openai -name <Contrasting character> -system <concise character-specific prompt built from Character Blueprint + Story Spine for chapters 5-6>]
[one line per participating cast member; mix providers]

PHASE 8 -- ACCEPT breakout 2 transcript:
[ACCEPT plan]

PHASE 9 -- BREAKOUT: ENDGAME / CLIFFHANGER (chapters 9-10):
[BREAKOUT policy=round_robin max_rounds=5 topic="Pivot breakout 3: chapters 9-10. Characters speak in first person at the point of no return: Veya's star-flare awakening, Brak and Toma's collision-combination, Hercan Vale's real fight, Jaitai's rebirth, and the cosmic elders choosing to confront him. Focus on what breaks, what is chosen, and what can no longer be outsourced to destiny, fame, raw aura, or a master's rescue. Stay inside one emotional moment. No alternate actions."]
[BREAKOUT_AGENT -provider anthropic -name <Emotionally central character> -system <concise character-specific prompt built from Character Blueprint + Story Spine for chapters 9-10; include SUPERIORITY_MASK, INFERIORITY_SOURCE, and TONE>]
[BREAKOUT_AGENT -provider openai -name <Contrasting character> -system <concise character-specific prompt built from Character Blueprint + Story Spine for chapters 9-10>]
[one line per participating cast member; mix providers]

PHASE 10 -- ACCEPT breakout 3 transcript:
[ACCEPT plan]

--- PHASE 11 -- DRAFT MANUSCRIPT ---
[ASSIGN ProseNovelist]: Write the complete draft manuscript.
Before writing a single word, call ALL of these artifacts:
  read_artifact('series-bible')
  read_artifact('character-blueprint')
  read_artifact('story-spine')
  read_artifact('verse-thread-manifest')
  read_artifact('lore-continuity-guardian')
  read_artifact('fight-choreographer')
  read_artifact('breakout-beat-1')
  read_artifact('breakout-beat-2')
  read_artifact('breakout-beat-3')

CRITICAL INSTRUCTIONS:
- The CREST axis is the backbone. CREST_CLAIM, HIDDEN_SHAME, and SOCIAL_AXIS must be
  active in the prose. Show the protagonist performing superiority. Show the shame
  beneath it. Do not let the story drift into kindness discourse or acceptance themes.
- This is an original Zeroverse action novel. Do not use protected franchise names,
  direct move names, copied transformation labels, copied species names, copied planet
  names, or exact canon relationships. Make every set piece belong to this lore.
- TONE = use the TONE_CONTRACT from the Story Spine. If dark-comic: the protagonist's
  obliviousness must produce reader-visible irony. The laugh arrives before the wound.
- The Story Spine controls plot. The breakout transcripts control interior texture at
  the three pivots.
- The FightChoreographer controls action readability. Every major fight must change
  tactics, stakes, or emotion every few paragraphs.
- The LoreContinuityGuardian controls Zeroverse rules and originality guardrails.
- Interpolate between the pivots; do not force every chapter to behave like a breakout.
- Use the breakout transcripts as emotional calibration, not source dialogue.
- Preserve the 4 Zero Verse fragment discovery beats exactly as specified in the Manifest.
- Write one coherent novel, not stitched scene studies.
- OUTPUT: prose and production notes ONLY. No planning headers, no blueprint tables,
  no illustration material. Your response is the manuscript.

Write all 10 chapters sequentially. Total word budget: 10000 words. Target audience:
12-15-year-olds.
After each chapter add a production note:
[CHAPTER: N | Xw / Yw budget | echo term: y/n | fragment: y/n | crest axis: y/n | zeroverse landmark: y/n]

After ProseNovelist responds: [ACCEPT plan]

--- PHASE 12 -- REVISION BRIEF ---
[ASSIGN RevisionEditor]: Produce a surgical revision brief for the draft manuscript.
Call read_artifact('prose-novelist'), read_artifact('story-spine'),
read_artifact('lore-continuity-guardian'), read_artifact('fight-choreographer'), and
read_artifact('breakout-beat-1'), read_artifact('breakout-beat-2'), read_artifact('breakout-beat-3').
Do not rewrite the manuscript. Output only revision instructions in this structure:
  KEEP: 5-8 strengths that should survive revision.
  FIX BEFORE FINAL: chapter-by-chapter bullets for pacing, clarity, emotional payoff,
    originality drift, fight readability, missing landmarks, and weak character turns.
  BREAKOUT PAYOFF CHECK: where each breakout voice is used well or underused.
  IMAGE MOMENT CHECK: 10-12 exact moments the painter should be able to brief.
  FINAL ORDERS: 8-12 concise instructions for ProseNovelist.
After RevisionEditor responds: [ACCEPT plan]

--- PHASE 13 -- FINAL MANUSCRIPT ---
[ASSIGN ProseNovelist]: Revise the draft into the final complete manuscript.
Call ALL of these artifacts before writing:
  read_artifact('prose-novelist')
  read_artifact('revision-editor')
  read_artifact('series-bible')
  read_artifact('character-blueprint')
  read_artifact('story-spine')
  read_artifact('verse-thread-manifest')
  read_artifact('lore-continuity-guardian')
  read_artifact('fight-choreographer')
  read_artifact('breakout-beat-1')
  read_artifact('breakout-beat-2')
  read_artifact('breakout-beat-3')

Apply the RevisionEditor brief surgically. Preserve the strongest draft material, but
fix pacing, causality, originality drift, fight readability, and emotional payoff.
Output the final manuscript only: 10 chapters, approximately 10000 words total, with
the same production note after each chapter. No planning headers, no revision notes,
no illustration briefs.

After ProseNovelist responds: [ACCEPT prose]

--- PHASE 14 -- ILLUSTRATION BRIEFS ---
[ASSIGN AquarellePainter]: Create illustration briefs.
Call read_artifact('story-spine'), read_artifact('verse-thread-manifest'),
read_artifact('lore-continuity-guardian'), read_artifact('fight-choreographer'),
read_artifact('revision-editor'), read_artifact('prose-novelist'), and
read_artifact('aquarelle-painter') for the Phase 2A character anchor briefs.
Before briefing, recover the CHARACTER_ANCHOR_INDEX from the auto-accepted
[image by IllustrationGen] manuscript entries created in Phase 2B. Every final story
illustration request must include the generated character anchors as reference images.
Nominate 10-12 exact story moments for illustration. Required nominations may overlap,
but all of these must be covered:
  - The tournament opening image
  - Bavik's return under Jaitai's command
  - Oru's grotesque void-champion transformation
  - The first Zeroverse reveal
  - Repa deflecting the blast and losing aura-current
  - Veya's star-flare awakening
  - Brak and Toma's collision-combination
  - Hercan Vale's meaningful fight
  - The threshold moment (from Story Spine)
  - Every Zero Verse fragment discovery beat
  - Jaitai's rebirth
  - The cliffhanger image of two cosmic elders leaving to confront him
For each nominated beat, produce one complete block:
  ILLUSTRATION: Beat N -- [description]
  PHASE: [phase name]
  ECHO TERM PRESENT: [yes/no]
  REFERENCE_IMAGES: [comma-separated absolute image paths from CHARACTER_ANCHOR_INDEX
    for every generated character anchor; include all anchors, not only visible subjects]
  PROMPT: [subject + dynamic ink-wash watercolour battle-manga style + technique +
    palette + light + composition + mood-first camera angle; 1-2 subjects max unless
    the beat explicitly requires a team clash; NO readable text in image]
  NEGATIVE PROMPT: [what to suppress; always include: photorealistic, smooth digital
    render, readable text, text overlay, legible words]
  PAINTER'S NOTE: [technique priority and why]

IMAGE_TEXT_POLICY: Do NOT include specific Zero Verse fragment text in any PROMPT. If a
fragment must appear visually, describe it as 'faint carved marks' or 'written traces'
only. This applies to every illustration brief.

After AquarellePainter responds: [ACCEPT image]

--- IMAGE GENERATION ---
For each illustration brief from AquarellePainter, issue ONE assignment at a time:

[ASSIGN IllustrationGen]: Generate this illustration using the character anchors -- <paste the AquarellePainter REFERENCE_IMAGES and PROMPT lines verbatim>
Wait for the image to be auto-accepted before issuing the next [ASSIGN IllustrationGen].
Do NOT batch. One image per assignment, one at a time.

After all images are generated:

Assign MusicGen to create a 2-minute cinematic martial-cosmic theme based on the max
500 word summary of the novel.

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
4. REGISTER: 12-15-year-old action-adventure audience. Accessible vocabulary. Moderate sentence complexity.
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
    text. Describe Zero Verse fragments in image prompts as visual marks, carved script, or
    written traces -- never as specific quoted lines.
14. ORIGINALITY_LOCK: no existing franchise names, copied transformations, copied move
    names, copied species, copied planets, copied tournament names, or exact canon
    relationships. Use broad martial-cosmic archetypes only, then make the lore original.

Relay all 14 translations verbatim to every agent that needs them.
${PHASES_1_4}${VOICE_AND_PROSE}"

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------
ofp-playground start \
  --policy showrunner_driven \
  --no-human \
  --topic "Zeroverse illustrated novel: ${STORY}" \
  --agent "-provider anthropic -type orchestrator -name SeriesDirector -system ${MISSION} " \
  --agent "-provider openai -name CharacterArchitect -system @creative/character-architect -model gpt-5.4" \
  --agent "-provider anthropic -name NarrativePacingArchitect -system @creative/narrative-pacing-architect -model claude-sonnet-4-6" \
  --agent "-provider openai -name VerseArchitect -system @creative/verse-architect -model gpt-5.4" \
  --agent "-provider anthropic -name LoreContinuityGuardian -system You are a compact continuity and originality auditor for an original Zeroverse action novel. Audit lore rules, power costs, names, causal logic, and originality drift. Do not rewrite prose. Output actionable fixes only. -model claude-sonnet-4-6" \
  --agent "-provider anthropic -name FightChoreographer -system You are a battle-manga action designer for an original martial-cosmic novel. Build readable set pieces with tactical turns, emotional costs, visual money shots, and originality checks. No copied move names or franchise references. -model claude-sonnet-4-6" \
  --agent "-provider anthropic -name ProseNovelist -system @creative/prose-novelist -model claude-sonnet-4-6" \
  --agent "-provider anthropic -name RevisionEditor -system You are a surgical revision editor for an original illustrated action novel. Preserve the strongest draft material, identify precise chapter-level fixes, protect continuity and originality, and produce a revision brief rather than rewriting. -model claude-sonnet-4-6" \
  --agent "-provider anthropic -name AquarellePainter -system @creative/aquarelle-painter" \
  --agent "-provider openai -type text-to-image -name IllustrationGen -system dynamic manga-inspired ink-wash watercolour key art, kinetic martial action, sharp silhouettes, luminous cosmic washes, no readable text" \
  --agent "google:text-to-music:MusicGen:high-quality production, clean mix:lyria-3-pro-preview"