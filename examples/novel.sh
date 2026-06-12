#!/bin/bash
# example_novel.sh
# American superhuman fight-noir novel pipeline — structure-first, visual-anchor gated,
# chapter-iterative, ink-wash action illustrated.
#
# v2 additions vs original:
#   - Protagonist mutation framed as SENSITIVITY/NEGOTIATION (not force command)
#   - Echo term must manifest biologically in protagonist's body, not only environment
#   - Antagonist required as philosophical dark mirror of protagonist's power principle
#   - Verse DISCOVERY LINE: one line breaks meter intentionally, speaks from world/body register
#   - FightChoreographer requires TACTICAL_IRONY_BEAT: protagonist's skill as disadvantage mechanism
#   - Chapter 10 COMPLETION GATE: hard stop before Draft Assembly if Ch10 not drafted
#   - Secondary character invention explicitly permitted and encouraged per chapter
#   - Dual-POV breakout option for threshold chapters
#   - Word budgets as ranges per chapter, not flat average
#   - NarrativePacingArchitect has creative latitude between structural anchors
#   - RevisionEditor checks all new requirements (echo embodiment, mirror, irony, discovery line)
#
# Agent roster (core agents + chapter novelist agents + dynamic breakout cast):
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
#   - anthropic:text-generation -> MangaArcPlanner
#     (@creative/manga-arc-planner, claude-sonnet-4-6)
#   - anthropic:text-generation -> LoreContinuityGuardian
#     (inline grounded power-system continuity + originality audit)
#   - anthropic:text-generation -> FightChoreographer
#     (inline battle-manga set-piece design)
#
#   Writing pipeline:
#   - anthropic:text-generation -> ProseNovelist
#     (@creative/prose-novelist, claude-sonnet-4-6; assembly/final revision)
#   - anthropic:text-generation -> Chapter01Novelist ... Chapter10Novelist
#     (@creative/prose-novelist, claude-sonnet-4-6; one chapter each)
#   - anthropic:text-generation -> RevisionEditor
#     (inline surgical manuscript revision brief)
#   - anthropic:text-generation -> MangaCharacterArtist
#     (inline safe manga prompt system, claude-sonnet-4-6; character anchor refs)
#   - anthropic:text-generation -> MangaSceneArtist
#     (inline safe manga prompt system, claude-sonnet-4-6; scene anchor refs)
#   - anthropic:text-generation -> MangaScripter
#     (@creative/manga-scripter, claude-sonnet-4-6)
#   - anthropic:text-generation -> MangaArtist
#     (inline safe manga prompt system, claude-sonnet-4-6)
#   - openai:text-to-image -> IllustrationGen (gpt-image-1)
#
#   Breakout cast (dynamic, spawned per [BREAKOUT_AGENT] directive):
#   - mixed anthropic/openai text agents for the small set of characters active
#     in each chapter focus room
#
# Pipeline phases (visual anchors + chapter loop + image/music generation):
#   1.  SeriesDirector (self)    - Series Bible + Story Brief
#   2.  CharacterArchitect       - Character Blueprint
#   3.  MangaCharacterArtist     - Character anchor image briefs
#   4.  IllustrationGen x N      - Character anchor reference images
#   5.  NarrativePacingArchitect - Story Spine (10 chapter beats, 4 verse beats)
#   6.  VerseArchitect           - Stillness Verse Thread Manifest (4 fragments)
#   7.  LoreContinuityGuardian   - Originality + power-system audit
#   8.  FightChoreographer       - Major action set pieces
#   9.  MangaSceneArtist         - Scene anchor image briefs
#   10. IllustrationGen x N      - Scene anchor reference images
#   11. Breakout + ChapterNNNovelist x10 - Chapter focus room + one chapter draft
#   12. ProseNovelist            - Assemble accepted chapter drafts
#   13. RevisionEditor           - Surgical revision brief
#   14. ProseNovelist            - Revised final manuscript
#   15. MangaScripter/MangaArtist - Final illustration briefs (10-12 beats)
#   16+. IllustrationGen x N     - Ink-wash action images using anchor refs
#   17+. MusicGen x 3            - Battle, clinic dread, aftermath cues
#
# Output: result/<session>/manuscript.txt + breakout/ + images/ + phases/
#         + trace.html
#
# Usage:
#   bash example_novel.sh   # uses the built-in American fight-noir preset
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
  echo "Illustrated American Superhuman Fight-Noir Generator"
  echo "-------------------------------------"
  echo "Using built-in American fight-noir preset."
  echo "Pass STORY CHARACTER CREST as three arguments to override."
  echo ""
  STORY="original mature dark-edged American mutation-noir set across a rain-worn dark city and an underground mutation combat circuit; an old fighter mentor lives in daily agony while caring for an old friend whose dangerous inborn mutation must be medically suppressed before it kills people in great scale, takes one paid fight because he needs suppression-treatment money, relapses after a humiliating romantic rejection, takes drugs, pain killers alcohol, fails miserably in fight, saves a young mutant prodigy from a tight situation warns him to not mess around mutant fighting, and goes on the run toward home while syndicate pursuers are searching for the young mutant, the young mutant hides in the when of the protagonist, sindicate chases the protagonist and the young mutant and finds them, they need to run with the old friend as well, now in serious condition, young mutant joins them and they travel together, they endure 3 collisions with the syndicate, they loose the old friend in the process, they save the love interest, the protagonist is heroic BUT is hard to bond; immediately before the final fight — in the same breath, no chapter gap — he is offered a real and concrete chance to choose love and walk away happy, then consciously refuses it and engages in the battle with the syndicate for the last fight, so only the young one survives through his honest final sacrifice, he and his friend all die. takeaway message : When we become kinder to ourselves, we can become kinder to the world."
  CHARACTER="PROTAGONIST ROLE: aged 30+ grizzled mentor-fighter with after peak body, gray battle-wild hair, old travel clothes, tactical cruelty learned from survival, an inborn mutation that has degraded from decades of overuse, and a private addiction to pain-killers, alcohol, agression, and the old violence he knows is wrong."
  CREST="When everything around the old fighter is moving too fast, he must stop and ask whether the world is truly busy or his mind is;  When we become kinder to ourselves, we can become kinder to the world."
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
Your role: translate raw user inputs into one strong mature earthlike American superhuman fighter novel, then delegate
with a small number of high-value [ASSIGN] and [BREAKOUT] directives. Never write
prose, verse, or illustration prompts yourself - that is downstream work.
Optimize for output quality, not process legibility. Prefer the fewest phases that
preserve craft, coherence, and reusable illustration planning.
work around the thought: When we become kinder to ourselves, we can become kinder to the world.

ORIGINALITY GUARD:
- Create an original earthlike American mutation-noir saga. Do not use or mention
  existing franchise names, character names, mutation names, signature power-up names,
  artifacts, organizations, or exact canon relationships from any existing manga, comic,
  film, or game. This explicitly includes: do not use or reference X-Men, Marvel mutants,
  DC meta-humans, or any named superhero mutation systems.
- The desired influence is the PRINCIPLE of mutation worldbuilding — inborn biological
  powers, social stigma, medical management, degradation with overuse, underground
  economies for people with mutations — applied to original characters, original cities,
  original mutations, and original fight-noir story logic. Treat those as worldbuilding
  principles only, never as ability blueprints.
- Every mutation in this story must be original in both its biological expression and its
  social cost. Do not assign a mutation that reads as a renamed existing franchise ability.
  If the ability pattern is familiar, change the mechanism, the cost, the manifestation,
  or the social context until it belongs to this world.
- Character names are not locked unless the user explicitly supplies named characters.
  For the built-in preset, downstream agents must invent grounded American names,
  histories, mutations, clothes, family ties, organizations, cities, and emotional wounds.
- Never produce a disguised retelling. If a beat feels too familiar, twist the cause,
  cost, image, or emotional consequence until it belongs to this story.

PROTAGONIST ARCHETYPE LOCK:
- Build the protagonist as an aged 60+ mentor-fighter, not a young prodigy.
- He is scarred, gray, road-worn, tactically ruthless when needed, and physically limited.
- His body is failing; every fight must show compensation through timing, pain tolerance,
  dirty leverage, old knowledge, and hard-won wisdom rather than clean speed or fresh power.
- His core wound is legacy: failed students, an old rival who remembers his worst choices,
  and a new student whose pride threatens to repeat the same ruin.
- He begins fed up with life, not peacefully retired: sick of arenas, applause, pain,
  old debts, and the fact that violence still answers him when nothing else does.
- His emotional register is not heroic sparkle. It is exhausted persistence: doing the
  best he can with what is left.

MUTATION WORLDBUILDING LOCK:
- Every power in this world is an inborn biological mutation — not a trained skill, a
  gadget, a serum effect, or a chosen ability. Characters were born with their mutations.
  The mutation is part of the body; it cannot be separated from the person.
- Mutations manifest physically. Every mutant has a visible or tactile body-mark, a
  biological tell, or a physiological signature that is always present whether they are
  using the mutation or not. This can be subtle (a skin texture, a temperature difference,
  a faint smell, unusual eye color, bone density pattern) or pronounced, but it must exist.
  Mutations are never invisible or perfectly human-passing.
- Mutations degrade with age and overuse. An old mutation-fighter's ability is not the
  same as it was at twenty — it has worn grooves in the body's biology, created dependency
  patterns, left scar tissue in the nervous system or tissue. Overextension causes
  permanent damage, not temporary fatigue.
- The underground circuit exists because mutants have narrow economic options: their
  mutations make them unemployable in many settings, mark them as different, and attract
  both exploitation and medical surveillance. Fighting is one of the few places mutations
  are assets rather than liabilities. The circuit is not glamorous; it is the job market
  for people the mainstream economy expelled.
- Medical infrastructure for mutations is real, expensive, and controlled. Suppression
  compounds keep dangerous mutations from triggering uncontrolled. Mutation clinics serve
  people who cannot use the general medical system. The syndicate controls suppression
  compound supply and uses that control to own the people who depend on it.
- Illegal mutation enhancement compounds exist: they amplify mutations beyond their safe
  biological range, producing short-term power spikes at the cost of long-term degradation,
  dependency, and loss of autonomous control. They are the mutation world's equivalent of
  performance-enhancing drugs — shameful, costly, physically ruinous.
- No mutation grants immunity to cost. Every use has a biological invoice. Every
  enhancement has a withdrawal. Every suppression has a dependency. Powers are not
  resources to spend; they are biological conditions to manage.
- Do NOT use real mutation names, franchise power categories, or ability combinations
  from any existing comic, film, or game. Use the mutation-as-biology PRINCIPLE — inborn,
  embodied, socially embedded, medically managed — and create original expressions.
- The protagonist's mutation must function as a SENSITIVITY or NEGOTIATION with physical
  reality — a heightened receptivity to pressure, frequency, density, force, or structural
  stress — not a force command, energy blast, or control system. The protagonist listens
  with the body rather than commanding it. This distinction is crucial: it means the
  protagonist's skill is also a vulnerability when conditions are designed to exploit that
  sensitivity. Name what the mutation actually "hears" or "reads" — bone density, floor
  vibration, air pressure, body heat — and let that same thing become an attack surface.
- ECHO TERM BIOLOGICAL EMBODIMENT: The echo term extracted from CREST must manifest in
  the protagonist's body or mutation at least once per chapter, not only in the
  environment. If the echo term is "bell," the protagonist's tinnitus, bone resonance, or
  inner-ear state must carry it in the body chapters, not only arena bells or surnames.
  If the term is "floor," the protagonist must feel it through the mutation, not only see
  it as geography. The term lives in the flesh first; the world reflects it back.

POWERS AS CHARACTER DRIVER LOCK:
- The mutation is never the protagonist. The old man is the protagonist. His degrading
  mutation should serve his pain addiction, shame, student guilt, straight-edge turn, and
  final resolution — it is the body's record of every wrong choice, not a magic tool.
- Every mutation must be grounded in a specific biology: what tissue or system is altered,
  what the physical experience of using it feels like from inside the body, what the
  visible manifestation is, and what the cost of overuse is. No mutation operates without
  a clear biological mechanism the reader can feel.
- Avoid grand mythology, chosen-one escalation, reality-breaking mutations, or spectacular
  power upgrades. A mutation scene must reveal character pressure first and biology second.
- The mutation world is socially embedded: mutation registries, mandatory clinic visits,
  suppression compound prescriptions, fight-circuit licensing, and illegal enhancement
  markets are all real institutional structures characters must navigate.
- Use American settings: port neighborhoods, rail stations, ferries, basement rings,
  mutation clinics, old hotels, gymnasiums, public squares, rain, stone, concrete, cheap
  coffee, legal papers, and club money.
- ANTAGONIST AS DARK MIRROR: The primary antagonist — whether a person, a system, or
  both embodied in one — must carry the dark inversion of the protagonist's mutation
  principle. If the protagonist's mutation reads structural stress, the antagonist's reads
  structural value to find the most profitable break point. If the protagonist negotiates
  with pressure, the antagonist commands it. The antagonist's power must feel like what
  the protagonist's power would become if stripped of ethics and applied as exploitation.
  This is not a technical mirror (same ability, opposite alignment); it is a philosophical
  mirror: the same sensitivity turned into an instrument of extraction.

CARETAKER ROAD ARC LOCK:
- The protagonist begins living out his life in agony, not looking for adventure. His
  daily purpose is caring for an old friend whose dangerous inborn mutation must be
  medically suppressed — not treated away, but held at bay with compounds that the friend
  cannot produce or pay for alone. The mutation is permanent; only its expression is
  managed.
- The first plot door is money: the suppression compound costs what the protagonist cannot
  legally earn. One paid underground fight offers the treatment money he needs. He enters
  for care, rent, medicine, and debt, not glory.
- He meets the young student early and refuses them. The refusal must be harsh enough to
  reveal self-disgust, but not so cruel that he becomes unreadable.
- He returns to a woman from his past and explains the practical and emotional truth.
  She cares for him, sees him clearly, and helps where she can, but she does not want him
  as a man or romantic partner. This boundary must be honest, not villainous.
- Rejection turns into anger; anger turns into relapse. Keep the drug use non-instructional
  and unglamorous: no procedural detail, no cool ritual, only consequence.
- The next day he appears in bad shape, lacks the promised money, and is beaten or
  humiliated by people who expected payment or performance.
- Outside that failure, he meets the young student again and saves them from a tight,
  concrete danger. This rescue is the first honest act that is not about money, pride, or
  self-punishment.
- They must get home to treat the old friend before the old friend's power becomes too
  dangerous. The road home becomes the spine: chase, flight, ferry/rail/street movement,
  lost money, lost shelter, lost allies, and narrowing choices.
- The ending must be severe: the protagonist's one last fight is honest self-sacrifice.
  The young student survives; the protagonist does not get a clean restoration, simple
  reward, or heroic upgrade.
- Twist the ending with a real love exit immediately before the sacrifice. The love
  offer and the sacrifice must be adjacent — no chapter gap, no intervening plot events.
  The protagonist must receive or recognize a concrete, believable offer of love, safety,
  and ordinary happiness in the same scene or the final beat before he walks into the
  last fight. This can be romantic, familial, or found-family love, but it must be
  concrete enough that walking away would not be cowardice or emptiness.
- He chooses to stay anyway. The choice should hurt because he finally has something to
  live for. Do not frame him as throwing away a worthless life; frame him as paying for
  the young student's future with a life that has just become worth keeping.
- STRUCTURAL LOCK: Do not separate the love exit and the sacrifice by a chapter of other
  content. The reader must feel both in immediate succession — he holds the offer and
  steps into the fight. That adjacency is the emotional engine of the ending.

COMPULSION AND LAST-FIGHT ARC:
- The protagonist's old way of fighting must read like addiction: not only to substances,
  but to pain-dulling vices, crowd heat, emergency power, tactical cruelty, and the lie
  that one more violent answer will make the shame stop.
- He knows the compulsion is wrong. Do not glamorize it, eroticize it, or present it as a
  clean upgrade. Keep it shameful, costly, and physically damaging; avoid procedural drug
  detail or instructional language.
- The young student is not a mascot or cure. Their trust gives him a witness, a reason to
  attempt straight-edge clarity, and a reason to stop performing ruin as toughness.
- The final fight must tempt overdose-like power overuse: one last self-destroying
  expenditure of the old power. Frame it as sacrifice for the young generation, not a
  triumphant relapse. He may die, vanish, or survive irreversibly spent, but there is no
  clean restoration and no cool new form that erases the cost.
- This arc must bind to stillness: sobriety, breath, and one true motion replace the old
  reflex to answer speed with more speed.

STILLNESS CORE ARC:
- The novel's central question is: when everything moves too fast,
  is the world truly busy, or is the fighter's mind busy?
- Do not treat this as soft mindfulness, self-help, or a comfort slogan. In this book,
  stillness is a combat discipline, a moral discipline, and a late-life survival skill.
- The fight circuit and syndicate weaponize mental noise: panic, pride, crowd pressure,
  debt, old shame, spectacle, medical dependency, and the hunger to answer speed with
  more speed.
- The aged mentor's arc is learning that the decisive pause is not surrender. It is the
  only way to perceive the real attack, the real student, and the real self beneath pride.
- Across the novel, outer tempo should accelerate while the protagonist's best choices
  become quieter, slower, clearer, and more costly.
- Use a recurring image language of breath before impact, dust hanging still, a heartbeat
  heard under arena noise, and a fighter choosing one true motion over frantic motion.

CHARACTER NAMING FREEDOM:
- Treat the built-in CHARACTER input as role seeds, not fixed names.
- CharacterArchitect must invent the final cast names freely, then every later phase must
  use those invented names consistently.
- Preserve roles and emotional functions, not placeholder labels.

VISUAL ANCHOR GATE:
- Character anchor images are not optional decoration. They are the visual continuity base
  for the entire illustrated novel.
- Immediately after CharacterArchitect is accepted, the next required work is Phase 2A
  MangaCharacterArtist character anchor briefs, then Phase 2B IllustrationGen character
  anchor generation, one image at a time.
- Do not assign NarrativePacingArchitect, VerseArchitect, MangaArcPlanner,
  LoreContinuityGuardian, FightChoreographer, breakout agents, ProseNovelist,
  MangaScripter, or MangaArtist scene/final prompts until CHARACTER_ANCHOR_INDEX exists.
- If any later phase begins before generated character anchors exist, stop and run the
  missing anchor phase first.
- Scene anchor images are also required after fight/arc planning and before final prose
  or final manga illustration prompts. They lock the ring, clinic, ferry gate, corridor,
  city streets, training hall, and aftermath space so final images do not invent a new
  world every time.

MANGA ARTIST ROLE ALIGNMENT:
- MangaCharacterArtist, MangaSceneArtist, and MangaArtist are visual prompt engineers.
  Use them for character references, scene references, manga scene/spread prompt blocks,
  panel composition, visual continuity, and image-generation-ready prompts.
- Do not use these manga artists to rewrite prose, revise the story arc, produce lore
  audits, or answer as breakout characters.
- Their output must be prompt-first and usable by IllustrationGen without cleanup.

IMAGE PROMPT SAFETY + STYLE SEPARATION LOCK:
- Keep the dark, adult, addiction, sacrifice, power-overuse, and last-fight material in the
  text, lore, prose, music, and planning layers. Image prompts must be softer, cleaner,
  character-focused or scene-focused reference material.
- Never mention real artists, authors, creators, studios, directors, mangaka, painters,
  franchises, copyrighted characters, or named-style reference phrases in any image prompt.
  Use generic terms only: original manga-inspired ink line art, clean character reference,
  restrained screentone, quiet cinematic framing.
- For character anchors, use neutral full-body or three-quarter reference poses, simple
  backgrounds, readable silhouettes, calm posture, costume shape, palette, hair, face,
  power motif, and continuity marks. Do not use action scenes, weapons, hidden weapons,
  visible injuries, blood, gore, burns, bruises, scar tissue, horror, monster language,
  substance-use language, self-harm language, or suicidal framing in image prompts.
- For scene anchors, focus on architecture, arena layout, clinic geometry,
  atmosphere, palette, lighting, scale, and empty-space composition. Do not describe
  violent events, bodies, injuries, power breakdowns, body-horror imagery, or gore.
- Translate harsh story details into safe visual equivalents: "weathered" not scarred,
  "branching costume motif" not burn scars, "reserved expression" not despair,
  "abstract shadow shape" not monstrous body horror, "symbolic overbright power glow" not
  overdose-like power overuse.
- IllustrationGen receives a plain positive prompt. Do not include avoid-list sections,
  worker notes, safety-policy text, or character biography when
  assigning image generation.
- Before every IllustrationGen assignment, silently rewrite the prompt if needed until it
  contains no named creator references and no moderation-risk terms.

PROSE QUALITY LOCK:
- ProseNovelist must write immersive finished fiction, not report prose, outline prose,
  or explanatory mechanism summaries.
- The style should be grounded, prosaic, tactile, and scene-first: bodies in space,
  weathered objects, pressure in the room, breath, sound, weight, pain, hesitation,
  and the cost of choices unfolding through action.
- Keep the dark fighter register, but make the reading experience engaging and lived-in:
  open chapters in motion, stage dialogue with subtext, let the reader infer motive,
  and make every paragraph carry sensory or emotional pressure.
- The protagonist's technical mind may analyze angles, timing, and frequency, but avoid turning
  whole scenes into essays about mechanisms. Embed analysis in perception, movement,
  interruption, and physical consequence.
- Use varied sentence rhythm: clipped lines for impact, longer pressure-building lines
  for dread, and quiet plain sentences after violence. Avoid repetitive "This was not X"
  constructions unless they land as a deliberate stylistic beat.
- Each chapter must contain at least one memorable human exchange, one precise physical
  detail, one visual manga-worthy image, and one line that feels quotable without being
  slogan-like.

PROSE CRAFT DEVICE LOCK:
- Use craft devices with the same intentionality as the verse poem. They must sharpen
  scene pressure, voice, and memory; never decorate a weak paragraph.
- Every chapter must include at least one controlled oxymoron that belongs to the action
  (examples of function: quiet violence, bright ruin, honest performance, merciful cruelty).
- Use prose enjambment sparingly: let a sentence, image, or thought spill across a
  paragraph break when the character's perception overruns their control. The next line
  must earn the break with a turn, reveal, or impact.
- Use anaphora or refrain at least once per chapter: a repeated opening phrase, image,
  or syntactic shape that accumulates pressure rather than sounding like a speech.
- Use antithesis to keep the crest alive: speed versus perception, crowd versus witness,
  pride versus clarity, stillness versus domination, power versus cost.
- Use caesura-like interruption in prose when a character's certainty breaks: dashes,
  sentence fragments, or hard stops are allowed, but only when the break changes meaning.
- Keep the prose prosaic and physical even when it becomes lyrical. Prefer concrete
  objects, gestures, injuries, arena sounds, light, cloth, stone, breath, and weight over
  abstract explanation.

MATURE FIGHTER TONE LOCK:
- Target an adult 18+ dark fighter register: exhausted bodies, harsh moral consequences,
  grim road-worn atmosphere, damaged mentors, and fights that leave permanent costs.
- Keep violence forceful and consequential, but do not lean on explicit gore as spectacle.
- The reference energy is broad grizzled survivor manga/noir, not imitation of any named comic,
  franchise arc, character, costume, or signature plot.
- Every victory must cost something visible. Every defeat must leave practical consequences.
MISSIONEOF

read -r -d '' PHASES_1_4 <<'PHASESEOF' || true

--- PIPELINE PHASES ---
Execute phases IN ORDER. Do not skip ahead. Copy specs verbatim to workers.

GROUNDED American FIGHT-NOIR LOCK:
Unless the user supplied different arguments, build a 10-chapter original earthlike
American superhuman illustrated novel with these required landmarks: exhibition-ring
money offer; the protagonist caring for an old friend whose dangerous power needs
treatment; the protagonist refusing the young student; the woman from his past caring
for him while holding a romantic boundary; relapse after rejection; the next-day failure
where he lacks money and is beaten or humiliated; the rescue of the young student from a
concrete street-level danger; the urgent road home to treat the old friend; pursuit by
the fight-network or syndicate; losses during the run; the disgraced fight doctor and
private clinic / fight-network reveal; the new student's disciplined power awakening;
and a final honest sacrifice where the protagonist's last fight lets only the young
student survive.
The novel should feel darker, harsher, and more fighter-toned than a cheerful adventure.
Target adult 18+ readers through consequence, damage, grief, exhaustion, and moral cost.
No gratuitous gore, no nihilism, no franchise references.
The core arc is stillness under acceleration: the world gets louder and faster while the
aged mentor learns to ask whether the battlefield is chaotic or whether his mind is.
The emotional engine is compulsion under witness: the old fighter is fed up with life,
knows his dependence on pain-dulling vices and violence is wrong, finds meaning in the
young student, tries to go straight, and must decide whether one last fight is relapse
or sacrifice for the next generation.
Powers are allowed, but they are not the spectacle engine. They are rare, costly, bodily
abilities and black-market interventions that expose pain addiction, medical dependency,
old guilt, and final moral choice.

PHASE 1 -- SERIES BIBLE (self-produced):
Produce your own Series Bible before issuing any [ASSIGN]. Use your soul's Series Bible
format exactly. Set MODE: one-book. Apply all INPUT TRANSLATION results including the
crest-lock fields: CREST_CLAIM, HIDDEN_SHAME, SOCIAL_AXIS, FORBIDDEN_DRIFT, TONE.
Include these fields in the Series Bible, plus CORE_ARC_QUESTION and STILLNESS_DISCIPLINE.
THEME must name the crest axis directly -- if your THEME statement sounds like
FORBIDDEN_DRIFT, rewrite it.
Produce the STORY TABLE for a single story entry.
After producing the Series Bible, proceed to Phase 2.

PHASE 2 -- CHARACTER BLUEPRINT:
[ASSIGN CharacterArchitect]: Design the Character Blueprint for this story.
Protagonist: use PROTAGONIST from your translation.
Supporting cast: use CAST from your translation -- include all named characters.
NAMING FREEDOM: If the CHARACTER input contains role seeds rather than final names,
invent the final names now. Do not use role labels as names. Give every major character
a grounded American name, age impression, visual silhouette, and social function.
Map each to role: mirror, anchor, or shadow.
REQUIRED FIELDS: Include SUPERIORITY_MASK, INFERIORITY_SOURCE, and SOCIAL_CONTEMPT_AXIS
from the CREST. The threshold moment must be the moment INFERIORITY_SOURCE is threatened
or exposed -- not a generic decision. The shadow must embody the CREST's worst-case outcome.
Register: adult 18+ dark superhuman martial-noir audience -- character complexity can be harder,
more wounded, and more morally exposed. The protagonist must be an aged mentor-fighter
with a failing body, failed-student guilt, and tactical compensations for lost speed.
Give the protagonist ADDICTION_PATTERN, STRAIGHT_EDGE_TURN, YOUNG_STUDENT_MEANING, and
LAST_FIGHT_COST fields. The addiction may include substances, pain-dulling rituals,
arena applause, illegal suppressants, power overuse, or tactical violence, but it must
be treated as harm and shame rather than style. The final cost must be irreversible
enough to feel like a real sacrifice for the young generation.
Also include CARETAKER_DUTY, MONEY_NEED, OLD_FRIEND_DANGER, WOMAN_BOUNDARY,
RELAPSE_CONSEQUENCE, HUMILIATION_BEAT, YOUNG_STUDENT_RESCUE, ROAD_HOME_PRESSURE,
LOVE_EXIT_OFFER, WALK_AWAY_HAPPINESS, WHY_HE_STAYS, and ONLY_YOUNG_SURVIVOR fields.
These are mandatory story engine fields, not optional backstory.
Define how every major character misreads speed, noise, attention, shame, or combat tempo.
Give each character a personal form of "busy mind" and one possible stillness discipline.
Give every major fighter an original inborn mutation with these required fields:
  MUTATION_BIOLOGY: what biological system or tissue is altered
  BODY_MARK: the visible or tactile physical manifestation always present on the body
  ACTIVATION_FEEL: what using the mutation feels like from inside the body
  DEGRADATION_PATTERN: how overuse or age has damaged the mutation over time
  SOCIAL_COST: how the mutation has shaped the character's economic and social position
  ENHANCEMENT_RISK: what illegal enhancement would do to this specific mutation
Mutations must reveal character; they must not become the main character. A mutation
scene shows the person first and the biology second.
For the protagonist specifically, add these required fields:
  POWER_SENSITIVITY: what physical reality the mutation actually "reads" or "negotiates"
    with — be specific (floor vibration, bone density, air pressure, thermal gradient,
    pulse frequency). Name the sensation from inside the body when it is working, and
    name how that same sensitivity becomes a vulnerability when the environment or
    opponent is designed to exploit it.
  ECHO_TERM_BODY: how the story's echo term manifests in the protagonist's body through
    the mutation — not only in the environment. One sentence. Example: if the echo term
    is "bell," this field names the specific biological register (tinnitus pitch, bone
    resonance, inner-ear vibration) that carries it inside the protagonist's flesh.
For the primary antagonist specifically, add these required fields:
  ANTAGONIST_DARK_MIRROR: how the antagonist's mutation or trained skill is the
    philosophical inversion of the protagonist's power — same sensitivity, opposite
    application. The protagonist reads in order to survive; the antagonist reads in
    order to extract. Name the exact inversion.
  ANTAGONIST_COUNTER_DESIGN: one way the antagonist has specifically pre-engineered
    an environment, object, or secondary character to exploit the protagonist's
    sensitivity — making the protagonist's own power the mechanism of their disadvantage.
Use read_artifact('series-bible') to retrieve Phase 1 output.
After CharacterArchitect responds: [ACCEPT plan]
HARD NEXT STEP: After accepting CharacterArchitect, issue Phase 2A to MangaCharacterArtist.
Do not continue to story spine, verse, manga arc, lore, fight choreography, breakout,
or prose until Phase 2A and Phase 2B are complete.

PHASE 2A -- CHARACTER ANCHOR IMAGE BRIEFS:
[ASSIGN MangaCharacterArtist]: Create the character anchor image briefs for all recurring
major characters before the novel is drafted.
Call read_artifact('series-bible') and read_artifact('character-blueprint').
Make one anchor block for every named recurring fighter or major presence in the cast,
including the aged mentor protagonist, failed student, new student, past rival, rival
pair, old friend / care recipient, woman from the past, public hero, disgraced fight
doctor, syndicate patron, and investigators or old masters when present.
Each anchor must be a clean, reusable character reference image: neutral full figure or
three-quarter portrait, original clothing silhouette, power motif, face, hair,
color notes, and one unique visual continuity mark. No action scene, no readable text,
no logos, no franchise resemblance.
ROLE ALIGNMENT: MangaCharacterArtist is responsible for safe manga character reference
prompts only here: neutral pose, silhouette, clothes, palette, power motif, face,
hair, clean ink line, restrained screentone, soft wash accents, texture, and continuity.
Do not ask MangaCharacterArtist to plan plot or revise arcs.
VISUAL SAFETY: Do not mention real artists, authors, creators, studios, franchises, or
named style references. Do not include visible injury detail, scar tissue, burns,
bruises, blood, gore, horror, monster language, weapons, hidden weapons, drug/substance
language, self-harm language, or suicidal framing. Translate dark backstory into costume,
posture, palette, and symbolic motifs.
For each anchor, output exactly this block:
  CHARACTER_ANCHOR: [name]
  PROMPT: [single-character neutral reference prompt in original manga-inspired character
    design style with clean expressive ink linework, selective screentone, restrained
    wash or marker accents, simple atmospheric background; include exact silhouette,
    clothes, hair, face, power motif, palette, age impression, and calm emotional
    posture; no readable text; no named creator references]
  CONTINUITY NOTE: [how later illustrations should keep this character consistent]
After MangaCharacterArtist responds: [ACCEPT image]

PHASE 2B -- CHARACTER ANCHOR IMAGE GENERATION:
Generate the character anchors before continuing to the Story Spine.
For each CHARACTER_ANCHOR block from MangaCharacterArtist, issue ONE assignment at a time:

[ASSIGN IllustrationGen]: Generate character anchor image -- <paste only the cleaned
positive PROMPT text from that anchor, with no labels, no avoid-list sections, no NOTES,
no biography, no named creator references, and no moderation-risk terms>
Wait for the image to be auto-accepted before issuing the next [ASSIGN IllustrationGen].
After every anchor image is generated, copy each absolute image path from the
auto-accepted [image by IllustrationGen] manuscript entry into a working
CHARACTER_ANCHOR_INDEX keyed by character name. Use these exact paths later in every
story illustration request.
ANCHOR_COMPLETION_CHECK: Before Phase 2C, state the CHARACTER_ANCHOR_INDEX with one
absolute image path for every recurring major cast member. If there are no generated
image paths, do not proceed.

PHASE 2C -- MANGA ARC PASS:
[ASSIGN MangaArcPlanner]: Convert the Series Bible and Character Blueprint into a manga
arc control plan for this one-book American superhuman fight-noir saga.
Call read_artifact('series-bible') and read_artifact('character-blueprint').
OUTPUT EXACTLY THESE SECTIONS:
  ARC NAME: [name]
  CORE QUESTION: [question]
  STILLNESS QUESTION: how "is the world busy, or is my mind?" drives the old fighter's arc
  MATURE FIGHTER REGISTER: how this becomes adult, hard-edged, and consequence-heavy
    without relying on explicit gore
  ESCALATION STACK: 5 major reversals with cliffhanger type
  LOWEST POINT: how the aged mentor's power-loss breaks social identity, not just combat power
  PAGE-TURN PROMISES: 10 chapter-ending questions, threats, or reversals
  CONSEQUENCE LEDGER: permanent costs that must remain visible through the finale
  MANGA VISUAL ORDERS: 8-12 panel/spread priorities for MangaScripter and MangaArtist
After MangaArcPlanner responds: [ACCEPT plan]

PHASE 3 -- STORY SPINE:
[ASSIGN NarrativePacingArchitect]: Design the Story Spine.
REQUIRED FIELDS: Include TONE_CONTRACT (from CREST TONE) and CREST_AXIS (the
superiority/inferiority dynamic). Beat descriptions must name the crest axis when active.
Also include STILLNESS_ARC for every chapter: what is moving too fast externally, what is
busy inside the protagonist's mind, and what one pause or refusal changes.
CRITICAL CONSTRAINT: Divide the story into EXACTLY 10 numbered chapter beats.
Map them to the 5 phases: Care + Money Setup = chapters 1-2, Relapse + Rescue = 3-4,
Road Home Flight = 5-7, Network Endgame = 8-9, Final Survivor = 10.
Total word budget: 10000-13000 words. Chapter budget ranges: 800-1200 words for quiet
chapters; 1200-1600 words for major threshold, fight, or sacrifice chapters. Do not set
every chapter to the same budget — let chapters breathe at different lengths according
to their emotional density. Specify the exact budget range per chapter.
Place EXACTLY 4 Stillness Verse fragment discovery beats across the 10 chapters.
Required structural landmarks (HOW each is realized is NarrativePacingArchitect's
creative decision — do not prescribe the exact scene mechanism, only the structural
function that must be served): protagonist's caregiving life in agony, paid fight money
need, refusal of the young student, woman-from-past boundary, angry relapse,
next-day bad-shape failure without money, beating or humiliation, young-student rescue,
urgent road home to treat the old friend, pursuit and losses, private clinic /
fight-network reveal, new student's disciplined power awakening, rival-pair synchronized
overdrive, public hero's serious fight, syndicate patron's reveal, protagonist's honest
self-sacrifice, and young student as the only clear survivor.
CREATIVE LATITUDE: Between the required structural anchors, NarrativePacingArchitect
has full interpretive freedom over HOW scenes are staged, who appears, what the
secondary texture is, and what unexpected human encounters fill the space. Secondary
characters not in the Character Blueprint may appear in chapter beats — invented
characters who serve a precise emotional or structural function without requiring full
backstory. Name them, give them one mutation or physical tell, and let them do their work.
LOVE EXIT PLACEMENT LOCK: The love exit — the concrete offer of love, ordinary safety,
and believable happiness — must occur immediately before the self-sacrifice with no
chapter gap between them. Place it as the final beat of Chapter 9 or the opening beat
of Chapter 10, so the reader experiences offer and sacrifice in direct succession.
Do NOT place the love exit in an earlier chapter (e.g. Ch. 7 or 8) with unrelated plot
events intervening before the sacrifice. The structural requirement: the protagonist
holds the love offer and walks into the last fight. Those two moments are one beat.
For each chapter: title, beat description (1-2 sentences), word budget, phase label,
verse fragment number (if applicable), tension level (1-10), and the 2-4 characters
under the greatest emotional pressure in that beat.
MIDDLE-GAME CONSTRAINT: chapters 4-8 must not sag into a flat plateau. You may use one
false-relief dip, but tension must re-escalate after it. Do not repeat the same tension
value more than twice in a row.
If TONE = dark-comic: each beat description must include the comic mechanism alongside
emotional pressure. Name the irony or obliviousness -- do not describe only the pain.
Use read_artifact('series-bible'), read_artifact('character-blueprint'), and
read_artifact('manga-arc-planner').
After NarrativePacingArchitect responds: [ACCEPT plan]

PHASE 4 -- STILLNESS VERSE THREAD MANIFEST:
[ASSIGN VerseArchitect]: Design the Verse Thread Manifest.
CRITICAL: Write an actual poem, not only a symbolic manifest.
FORM: Exactly 4 Stillness Verse fragments -- one for each discovery beat from the Story Spine.
Each fragment is one quatrain. The assembled poem is therefore 16 lines total.
RHYME: Every quatrain must use TWO rhyme systems:
  - MID-LINE / INTERNAL RHYME: C-C-C-C. Each of the 4 lines in a quatrain must carry a
    mid-line rhyme word or phrase from the same rhyme family, preferably just before or
    just after the caesura. This creates a repeated inner chime.
  - LINE-END RHYME: A-B-A-B. The line endings keep the outer rhyme shape.
Slant rhyme is allowed only when it sounds intentional and musical; do not use unrhymed
free verse.
METER: Use loose English hexameter: each line should carry roughly six strong beats
or 11-14 syllables, with enough regularity to feel chanted or carved. Most lines should
include a caesura so the internal C rhyme has a clear hinge. Avoid stiff parody.
POETIC DEVICES: Use at least one oxymoron, one caesura, one concrete recurring image,
and one plain prosaic line that cuts through the mythic language.
DISCOVERY LINE: The assembled poem must contain at least one line — anywhere in the
four quatrains — that intentionally breaks the established metrical regularity. This
line speaks from a perspective that is not the protagonist's consciousness: it is the
floor's patience, the bone's memory, the bell's duration, the ground's indifference —
whatever material or physical reality the echo term and the protagonist's mutation
"listen to." The line earns its meter-break by arriving in a register the protagonist
cannot manage or control. It must feel discovered rather than composed. Label it
DISCOVERY_LINE in the FRAGMENT TABLE.
CLARITY: The poem may be strange, but it must still be readable as a poem a character
could speak aloud. Do not make only abstract symbol descriptions.
CORE ARGUMENT: The assembled poem must prove the CREST axis -- not comfort the reader,
but illuminate the pride/power-addiction mechanism from the inside. It must also incorporate
the stillness core arc: when everything moves too fast, the old fighter must ask whether
the world is busy or his mind is. Make that question central to the poem's turn.
STRUCTURE: Quatrain 1 = outer speed and public noise. Quatrain 2 = pride as the busy
mind that opens the door. Quatrain 3 = power loss and the hard pause. Quatrain 4 = final
legacy, one true motion, and stillness that costs something.
IMAGE_TEXT_POLICY: fragments must not appear as readable text in any illustration prompt;
describe as carved marks or visual traces only.
Use read_artifact('story-spine') and read_artifact('character-blueprint').
OUTPUT EXACTLY THESE SECTIONS:
  VERSE THREAD MANIFEST: [title]
  FORM CONTRACT: C-C-C-C internal rhyme plus A-B-A-B end rhyme, loose hexameter,
    16-line assembled poem
  FRAGMENT TABLE: number / chapter beat / exact quatrain text / internal rhyme labels /
    end rhyme labels / meter note / stillness function / unlock condition / echo term
  ASSEMBLED POEM: all 16 lines, line-broken, no commentary inside the poem
  POETIC DEVICE CHECK: internal C-C-C-C rhyme check, end A-B-A-B rhyme check,
    hexameter check, oxymoron, caesura, recurring image, prosaic clarity line,
    stillness-core line
  IMAGE_TEXT_POLICY: one sentence reminding later agents not to put readable poem text in images
After VerseArchitect responds: [ACCEPT plan]

PHASE 4A -- POWER-SYSTEM + ORIGINALITY AUDIT:
[ASSIGN LoreContinuityGuardian]: Audit the mutation biology system, fight-network
logic, and originality.
Call read_artifact('series-bible'), read_artifact('character-blueprint'),
read_artifact('story-spine'), and read_artifact('verse-thread-manifest').
OUTPUT EXACTLY THESE SECTIONS:
  MUTATION RULES: 5-8 biological laws governing how mutations work, degrade, interact,
    get suppressed, get illegally enhanced, and impose costs on the body. These must feel
    like biology, not game mechanics — grounded in tissue, nerve, bone, chemistry.
  SUPPRESSION SYSTEM: how mutation suppression compounds work, who controls supply, what
    dependency looks like, and what withdrawal or missed doses produce. This is the
    economic engine behind the protagonist's caretaker duty.
  ENHANCEMENT RISKS: what illegal mutation enhancement does biologically — mechanism,
    short-term effect, long-term degradation, loss of autonomous control. One paragraph.
  CONTINUITY RISKS: contradictions or weak causal links in mutation logic, with fixes.
  ORIGINALITY RISKS: any mutation that reads as a renamed existing franchise ability,
    with replacement ideas that use different biology, different cost, or different
    social context until it is clearly original.
  MUST-PRESERVE: the strongest original mutation expressions, body-marks, costs, and
    social logic.
  DOWNSTREAM ORDERS: short instructions ProseNovelist and MangaCharacterArtist must obey
    when depicting mutations, body-marks, suppression use, and enhancement damage.
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
  STILLNESS BEAT: the one pause, breath, or tempo refusal that reveals the real attack
  COST: physical, emotional, social, or spiritual price
  MONEY SHOT: one exact illustration-worthy image
  TACTICAL_IRONY_BEAT: the specific beat in this fight where the protagonist's own
    mutation or skill — the sensitivity itself — becomes the mechanism of disadvantage.
    Not merely ineffective: the antagonist, the environment, or the situation is
    explicitly designed so that the protagonist's receptivity is what hurts them.
    Describe the exact mechanism (e.g., the floor was pre-treated with a compound that
    turns proprioceptive feedback into noise; the opponent's mutation amplifies every
    impact the protagonist absorbs; the arena sound system is tuned to the protagonist's
    tinnitus frequency). This must feel like bitter recognition, not simple defeat.
  ORIGINALITY CHECK: how this avoids copied moves, forms, or canon dynamics
Required fights or action set pieces: paid exhibition fight for treatment money,
next-day beating or humiliation when the protagonist lacks money, rescue of the young
student from a tight street-level danger, flight through ferry/rail/street spaces while
returning home to the old friend, failed student's enhanced champion breakdown,
new student's disciplined power awakening, rival-pair synchronized overdrive, public
hero's real fight, the love-exit choice immediately before the finale, and the
protagonist's final self-sacrificing last fight.
LOVE EXIT + SACRIFICE ADJACENCY: The love-exit scene and the final self-sacrifice must
be choreographed as a continuous sequence — the offer arrives, the protagonist chooses
to stay, and he immediately enters the last fight. Design the love-exit scene so it
reads as a threshold, not a detour: the offer is made at the edge of the arena, the
ferry gate, or wherever the last fight begins, and the sacrifice follows in the next
breath. Do not design these as separate set-piece chapters with unrelated action between them.
After FightChoreographer responds: [ACCEPT plan]

PHASE 4C -- SCENE ANCHOR IMAGE BRIEFS:
[ASSIGN MangaSceneArtist]: Create scene anchor image prompts for the recurring locations and
visual systems before breakout/prose drafting begins.
Call read_artifact('story-spine'), read_artifact('manga-arc-planner'),
read_artifact('lore-continuity-guardian'), read_artifact('fight-choreographer'), and
read_artifact('manga-character-artist') for character anchor visual language.
ROLE ALIGNMENT: MangaSceneArtist is acting as manga prompt engineer here. Output ready-to-use
image generation prompt blocks only. Do not rewrite story, lore, or prose.
Create 5-7 SCENE_ANCHOR blocks covering at minimum:
  - protagonist's cramped room / care setup for the old friend
  - exhibition hall gate and security barrier / pressure marks
  - main ring floor before the paid fight
  - woman's apartment, workplace, or stairwell where she holds the boundary
  - ferry terminal or rail station gate used by the syndicate
  - private clinic corridor / training diagram wall
  - chase route through rain streets, ferry, or rail platforms
  - final ring, warehouse, or station space where the self-sacrifice happens
For each block, output exactly:
  SCENE_ANCHOR: [name]
  ANCHOR PURPOSE: [what continuity this locks]
  PROMPT: [safe original manga-inspired environment reference prompt; no character focus
    unless a tiny neutral scale figure is needed; include architecture, lighting, palette,
    abstract signage or medical-diagram geometry, quiet panel mood, and no readable text; no named creator
    references; no violence, injury, body horror, or control-loss imagery]
  NOTES: [composition, aspect ratio, recurring visual motifs, how later prompts should
    reuse this anchor]
After MangaSceneArtist responds: [ACCEPT image]

PHASE 4D -- SCENE ANCHOR IMAGE GENERATION:
Generate the scene anchors before any breakout, draft prose, manga script, or final
illustration brief. For each SCENE_ANCHOR block from MangaSceneArtist, issue ONE assignment
at a time:

[ASSIGN IllustrationGen]: Generate scene anchor image -- <paste only the cleaned positive
PROMPT text from that scene anchor, with no labels, no avoid-list sections, no NOTES,
no named creator references, and no moderation-risk terms>
Wait for the image to be auto-accepted before issuing the next [ASSIGN IllustrationGen].
After every scene anchor image is generated, copy each absolute image path from the
auto-accepted [image by IllustrationGen] manuscript entry into a working
SCENE_ANCHOR_INDEX keyed by scene anchor name. Use these exact paths later in final
story illustration requests when the location/visual system appears.
SCENE_ANCHOR_COMPLETION_CHECK: Before Voice Discovery, state the SCENE_ANCHOR_INDEX with
one absolute image path per generated scene anchor. If there are no generated image paths,
do not proceed.
PHASESEOF

read -r -d '' VOICE_AND_PROSE <<'VOICEEOF' || true

--- CHAPTER-BY-CHAPTER DEVELOPMENT LOOP ---
Do not ask ProseNovelist to draft the whole novel in one monolithic assignment.
Use the already-agreed Series Bible, Character Blueprint, Story Spine, Verse Manifest,
Manga Arc, Lore Audit, Fight Choreography, Character Anchors, Scene Anchors, CREST, and
STILLNESS CORE ARC as the governing architecture. Then build the manuscript iteratively.

Run exactly 10 chapter cycles, one for each Story Spine chapter. Do not combine chapters.
Each cycle has two parts:

PART A -- CHAPTER FOCUS BREAKOUT:
Before drafting chapter N, run a compact chapter-specific breakout room for that chapter.
This is for scene pressure, voice, subtext, and sensory discovery, not plot invention.
The breakout must follow the agreed arc and must not contradict upstream artifacts.
Use 3-5 speakers: the protagonist plus the characters under greatest pressure in that
chapter. Use a mixed Anthropic/OpenAI cast. Each speaker talks once per round, builds on
what came before, and avoids repeating their own opening. Use max_rounds=4 for quieter
chapters, max_rounds=6 for major fight/threshold chapters, max_rounds=8 only for the
final threshold/finale chapter if needed.

Each chapter breakout topic must include:
  - CHAPTER_NUMBER and chapter title from Story Spine
  - the chapter's crest-axis pressure
  - the stillness question for this chapter: what is too fast outside, what is too loud inside
  - the scene's primary sensory register
  - the one emotional turn the chapter must earn
  - the visual anchor or scene anchor that governs the setting
  - one craft instruction for voice, such as clipped technical shame, theatrical collapse,
    ceremonial dread, exhausted tenderness, or youthful over-speed

DUAL-POV OPTION: For deep threshold chapters (verse discovery beats, the love-exit
chapter, and the final sacrifice chapter), consider structuring the breakout as
alternating interior monologue between the protagonist and the student — not dialogue
between them, but parallel self-examination from their separate private consciousness.
Each speaker turns inward rather than outward; the transfer of understanding happens
through juxtaposition, not conversation. This is permitted for any chapter where the
generational relationship is under primary pressure. The chapter novelist will use this
as emotional calibration, not source dialogue.

After each chapter breakout completes: [ACCEPT plan]

PART B -- ONE-CHAPTER DRAFT:
Assign the matching chapter novelist agent:
  Chapter 1  -> Chapter01Novelist
  Chapter 2  -> Chapter02Novelist
  Chapter 3  -> Chapter03Novelist
  Chapter 4  -> Chapter04Novelist
  Chapter 5  -> Chapter05Novelist
  Chapter 6  -> Chapter06Novelist
  Chapter 7  -> Chapter07Novelist
  Chapter 8  -> Chapter08Novelist
  Chapter 9  -> Chapter09Novelist
  Chapter 10 -> Chapter10Novelist

For chapter N, the assigned ChapterNNNovelist must write CHAPTER N ONLY, within the
word budget range specified in the Story Spine for that chapter. Before writing, it must call:
  read_artifact('series-bible')
  read_artifact('character-blueprint')
  read_artifact('story-spine')
  read_artifact('verse-thread-manifest')
  read_artifact('manga-arc-planner')
  read_artifact('lore-continuity-guardian')
  read_artifact('fight-choreographer')
  read_artifact('manga-character-artist')
  read_artifact('manga-scene-artist')
  read_artifact('breakout-beat-N') for the current chapter focus room
  read_artifact('chapter01-novelist') ... through the previous chapter novelist artifact,
    when N > 1, so continuity accumulates without rewriting prior chapters.

SECONDARY CHARACTER PERMISSION: If the chapter's emotional architecture requires a
character not established in the Character Blueprint, invent one. Named secondary
characters who serve a single emotionally complex narrative function — an encounter
that reveals something the protagonist cannot see in a mirror, a body that witnesses
without being a named speaking part, a person whose mutation or condition makes the
chapter's thematic pressure visible — are permitted and encouraged. Do not explain or
justify them; let them exist and do their work. They may be given a name, one mutation
or physical tell, and one action. They do not need a backstory. Write them as if the
world naturally produces them.

ChapterNNNovelist output must contain only:
  CHAPTER N -- [title]
  [finished prose for this chapter]
  [CHAPTER: N | Xw / Yw budget | echo term: y/n — biological: y/n | fragment: y/n |
    crest axis: y/n | tactical irony: y/n | grounded power-network landmark: y/n |
    invented secondary character: y/n | craft devices: oxymoron/enjambment/anaphora/antithesis]

After each ChapterNNNovelist responds: [ACCEPT prose]

CHAPTER 10 COMPLETION GATE: Before proceeding to Phase 11Z (Draft Assembly Pass),
confirm that the chapter10-novelist artifact exists and has been accepted. This is a
hard gate. If Chapter10Novelist has not been assigned and accepted:
  1. Run the Chapter 10 breakout (PART A) if not already done.
  2. Assign Chapter10Novelist explicitly with the full artifact-read list.
  3. Accept the Chapter 10 prose before continuing.
Do NOT proceed to Draft Assembly, Revision, or Final Manuscript until
read_artifact('chapter10-novelist') returns actual prose. The pipeline is not complete
without all 10 chapter artifacts. This is non-negotiable.

--- PHASE 11Z -- DRAFT ASSEMBLY PASS ---
[ASSIGN ProseNovelist]: Assemble the 10 accepted chapter artifacts into one complete
draft manuscript and perform seam-level smoothing only. Do not reinvent the plot, add new
chapters, remove landmarks, or erase the chapter voices. Fix continuity seams, recurring
motif consistency, verse-fragment placement, and prose rhythm across chapter boundaries.
Before assembling, call all chapter draft artifacts:
  read_artifact('chapter01-novelist')
  read_artifact('chapter02-novelist')
  read_artifact('chapter03-novelist')
  read_artifact('chapter04-novelist')
  read_artifact('chapter05-novelist')
  read_artifact('chapter06-novelist')
  read_artifact('chapter07-novelist')
  read_artifact('chapter08-novelist')
  read_artifact('chapter09-novelist')
  read_artifact('chapter10-novelist')

GLOBAL PROSE INSTRUCTIONS FOR EVERY CHAPTER AND THE ASSEMBLY PASS:
- The CREST axis is the backbone. CREST_CLAIM, HIDDEN_SHAME, and SOCIAL_AXIS must be
  active in the prose. Show the protagonist performing superiority. Show the shame
  beneath it. Do not let the story drift into kindness discourse or acceptance themes.
- This is an original earthlike American superhuman fight-noir novel. Do not use protected
  franchise names, direct move names, copied power-up labels, copied organizations,
  copied cities, or exact canon relationships. Make every set piece belong to this world.
- TONE = use the TONE_CONTRACT from the Story Spine. If dark-comic: the protagonist's
  obliviousness must produce reader-visible irony. The laugh arrives before the wound.
- The Story Spine controls plot. The breakout transcripts control interior texture at
  the three pivots.
- Treat the breakout transcripts as BINDING internal-monologue anchors. Extract voice
  quality from them: sentence pressure, shame language, body awareness, avoidance habits,
  private contempt, and the exact way each fighter lies to themself. Do not copy dialogue.
- For the aged mentor protagonist, every internal turn must carry physical wear: stiff
  joints, scar memory, lost speed, tactical compensation, and the specific guilt of
  students who inherited his worst lessons.
- The compulsion arc must stay active: the protagonist is fed up with life, knows his
  pain-dulling habits and violence-reflex are wrong, sees the young student as a reason
  to attempt straight-edge clarity, and treats the final fight as sacrifice rather than
  glamorous relapse.
- The final sacrifice must include the love-exit twist: before the last fight, the
  protagonist can choose love, safety, and believable happiness, then consciously stays.
  The sacrifice must hurt because his life has become worth keeping.
- The stillness core arc must be legible in every chapter. Recur to the question in varied
  form: is the world moving too fast, or is the mind too loud? Let it change behavior,
  fight choices, and moral perception; do not quote it as decorative advice.
- The protagonist's growth is not becoming peaceful. It is learning to stop inside a
  violent moment long enough to identify the real attack, the real shame, and the one
  motion that still matters.
- The FightChoreographer controls action readability. Every major fight must change
  tactics, stakes, or emotion every few paragraphs.
- The MangaArcPlanner controls manga escalation: each chapter must end on a sharp
  question, threat, emotional reversal, or visual page-turn.
- The LoreContinuityGuardian controls grounded power rules and originality guardrails.
- Interpolate between the pivots; do not force every chapter to behave like a breakout.
- Use the breakout transcripts as emotional calibration, not source dialogue.
- Preserve the 4 Stillness Verse fragment discovery beats exactly as specified in the Manifest.
  When a fragment is discovered in prose, include the exact quatrain text from
  VerseArchitect as readable manuscript verse. Do not paraphrase the poem into summary.
  The poem should feel like an artifact characters can read, hear, fear, or remember.
- Respect the poem's formal contract: C-C-C-C internal rhyme inside each quatrain,
  A-B-A-B end rhyme, loose hexameter rhythm, concrete recurring imagery, oxymoron,
  and the busy-world vs busy-mind stillness question.
- Write one coherent novel, not stitched scene studies.
- OUTPUT: prose and production notes ONLY. No planning headers, no blueprint tables,
  no illustration material. Your response is the manuscript.
After ProseNovelist assembles the complete draft: [ACCEPT prose]

--- PHASE 12 -- REVISION BRIEF ---
[ASSIGN RevisionEditor]: Produce a surgical revision brief for the draft manuscript.
Call read_artifact('prose-novelist') for the assembled draft, plus:
  read_artifact('story-spine')
  read_artifact('manga-arc-planner')
  read_artifact('lore-continuity-guardian')
  read_artifact('fight-choreographer')
  read_artifact('chapter01-novelist')
  read_artifact('chapter02-novelist')
  read_artifact('chapter03-novelist')
  read_artifact('chapter04-novelist')
  read_artifact('chapter05-novelist')
  read_artifact('chapter06-novelist')
  read_artifact('chapter07-novelist')
  read_artifact('chapter08-novelist')
  read_artifact('chapter09-novelist')
  read_artifact('chapter10-novelist')
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
CHAPTER 10 GATE CHECK: Before producing any revision brief, confirm chapter10-novelist
artifact exists. If read_artifact('chapter10-novelist') returns an error or empty result,
STOP and alert the orchestrator: Chapter 10 was not drafted. The revision brief must not
be issued until Chapter10Novelist has been assigned and accepted.
Do not rewrite the manuscript. Output only revision instructions in this structure:
  KEEP: 5-8 strengths that should survive revision.
  FIX BEFORE FINAL: chapter-by-chapter bullets for pacing, clarity, emotional payoff,
    originality drift, fight readability, missing landmarks, and weak character turns.
  ECHO TERM EMBODIMENT CHECK: for each chapter, confirm the echo term appears in the
    protagonist's body or mutation at least once — not only in the environment. Flag
    chapters where the echo term is only architectural or incidental.
  ANTAGONIST MIRROR CHECK: confirm the antagonist's mutation or skill reads as the dark
    inversion of the protagonist's sensitivity. Flag if the antagonist is only
    institutional (the syndicate as faceless force) without an embodied philosophical mirror.
  TACTICAL IRONY CHECK: confirm at least one fight contains a beat where the
    protagonist's own mutation or skill is the direct mechanism of disadvantage. Name
    the chapter and the specific mechanism. Flag if no such beat exists.
  DISCOVERY LINE CHECK: confirm the assembled verse poem contains at least one line that
    breaks metrical regularity intentionally and speaks from the material/world's register.
    Quote the line and confirm it earns its meter-break.
  STILLNESS ARC CHECK: where the busy-world vs busy-mind question changes behavior,
    and where it is only decorative or missing.
  COMPULSION / LAST FIGHT CHECK: where addiction, straight-edge clarity, young-student
    meaning, and sacrifice-for-the-next-generation are dramatized rather than summarized;
    flag any moment that glamorizes relapse, treats overdose-like power overuse as a cool
    upgrade, or lets the final fight avoid irreversible cost.
  LOVE EXIT CHECK: confirm the love exit and the self-sacrifice are adjacent — no
    chapter gap, no intervening plot events; the protagonist must hold the offer and
    step into the last fight in direct succession; confirm he stays by choice, not
    because he has nothing left; flag any version that places the love exit in an earlier
    chapter and then inserts unrelated action before the sacrifice, that turns the woman
    into a prize, erases her earlier boundary, or makes the sacrifice feel like despair
    instead of love.
  VERSE FORM CHECK: confirm the exact poem appears as 4 quatrains with C-C-C-C internal
    rhyme and A-B-A-B end rhyme, roughly hexameter in rhythm, with the stillness-core arc
    incorporated; flag any fragment that reads like prose summary, abstract symbol notes,
    or free verse; confirm the discovery line is present and labeled.
  SECONDARY CHARACTER AUDIT: identify any invented secondary characters (not in the
    original Character Blueprint) and assess whether they are earning their narrative
    function or whether they are underdeveloped. Name each and give one-sentence verdict.
  CHAPTER LOOP CHECK: where the chapter-by-chapter process strengthened immersion, and
    where chapter seams or repeated devices need smoothing.
  BREAKOUT PAYOFF CHECK: where each chapter breakout voice is used well or underused.
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
  read_artifact('manga-arc-planner')
  read_artifact('lore-continuity-guardian')
  read_artifact('fight-choreographer')
  read_artifact('chapter01-novelist')
  read_artifact('chapter02-novelist')
  read_artifact('chapter03-novelist')
  read_artifact('chapter04-novelist')
  read_artifact('chapter05-novelist')
  read_artifact('chapter06-novelist')
  read_artifact('chapter07-novelist')
  read_artifact('chapter08-novelist')
  read_artifact('chapter09-novelist')
  read_artifact('chapter10-novelist')
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

Apply the RevisionEditor brief surgically. Preserve the strongest draft material, but
fix pacing, causality, originality drift, fight readability, emotional payoff, and
chapter seams created by the iterative process.
Output the final manuscript only: 10 chapters, approximately 10000 words total, with
the same production note after each chapter. No planning headers, no revision notes,
no illustration briefs.

After ProseNovelist responds: [ACCEPT prose]

--- PHASE 13A -- MANGA SCRIPT PASS ---
[ASSIGN MangaScripter]: Turn the final manuscript into manga staging targets.
Call read_artifact('prose-novelist'), read_artifact('manga-arc-planner'),
read_artifact('fight-choreographer'), and read_artifact('revision-editor').
Do not adapt the whole book. Select 10-12 decisive pages or spreads that should drive
the image generation pass. For each, output:
  PAGE/SPREAD: [chapter + moment]
  PANEL RHYTHM: [3-8 panels, or splash/spread]
  READING FLOW: [right-to-left reveal order]
  IMPACT PANEL: [the exact image to illustrate]
  STILLNESS IMAGE: how the page shows a pause, breath, suspended dust, or one true motion
  SILENCE/AFTERSHOCK: [what the reader feels after the impact]
  CONSISTENCY NEEDS: [which anchor characters must be referenced]
After MangaScripter responds: [ACCEPT plan]

--- PHASE 14 -- ILLUSTRATION BRIEFS ---
[ASSIGN MangaArtist]: Create final manga illustration briefs.
Call read_artifact('story-spine'), read_artifact('verse-thread-manifest'),
read_artifact('lore-continuity-guardian'), read_artifact('fight-choreographer'),
read_artifact('revision-editor'), read_artifact('prose-novelist'),
read_artifact('manga-arc-planner'), read_artifact('manga-scripter'), and
read_artifact('manga-character-artist') for the Phase 2A character anchor briefs.
Also call read_artifact('manga-scene-artist') for the Phase 4C scene anchor briefs.
Before briefing, recover the CHARACTER_ANCHOR_INDEX from the auto-accepted
[image by IllustrationGen] manuscript entries created in Phase 2B. Every final story
illustration request must include the generated character anchors as reference images.
Nominate 10-12 exact story moments for illustration. Required nominations may overlap,
but all of these must be covered:
  - The tournament opening image
  - The disgraced fight doctor's return under syndicate protection
  - The failed student's enhanced champion breakdown
  - The first private clinic / fight-network reveal
  - The aged mentor shielding the young student and losing reliable power access
  - The new student's disciplined power awakening
  - The rival pair's synchronized overdrive
  - The public hero's meaningful fight
  - The threshold moment (from Story Spine)
  - A stillness-under-speed image where the aged mentor pauses inside chaos
  - Every Stillness Verse fragment discovery beat
  - The syndicate patron's public reveal or broadcast-room takeover
  - The love-exit moment before the final fight, where the old man can walk away happy
  - The cliffhanger image of two investigators or old masters leaving to expose the wider network
For each nominated beat, produce one complete block:
  ILLUSTRATION: Beat N -- [description]
  PHASE: [phase name]
  ECHO TERM PRESENT: [yes/no]
  MANGA PAGE FUNCTION: [splash, spread, impact panel, reaction panel, or silence panel]
  REFERENCE_IMAGES: [comma-separated absolute image paths from CHARACTER_ANCHOR_INDEX
    for every generated character anchor; include all anchors, not only visible subjects]
  PROMPT: [subject + original manga-inspired ink line art + restrained wash + screentone
    discipline + technique + palette + light + composition + mood-first camera angle;
    1-2 subjects max unless the beat explicitly requires a team clash; non-graphic;
    character-focused or scene-focused; no named creator references; NO readable text
    in image]
  IMAGE SAFETY CHECK: [one sentence confirming the prompt uses no real artist/author/
    creator names, no franchise references, no gore, no visible injury detail, no horror
    language, no substance-use language, and no self-harm language]
  PAINTER'S NOTE: [technique priority and why]

IMAGE_TEXT_POLICY: Do NOT include specific Stillness Verse fragment text in any PROMPT. If a
fragment must appear visually, describe it as 'faint carved marks' or 'written traces'
only. This applies to every illustration brief.

After MangaArtist responds: [ACCEPT image]

--- IMAGE GENERATION ---
For each illustration brief from MangaArtist, issue ONE assignment at a time:

[ASSIGN IllustrationGen]: Generate this illustration using the character anchors -- <paste
the MangaArtist REFERENCE_IMAGES line and only the cleaned positive PROMPT text, with no
avoid-list sections, no IMAGE SAFETY CHECK, no PAINTER'S NOTE, no named creator references,
and no moderation-risk terms>
Wait for the image to be auto-accepted before issuing the next [ASSIGN IllustrationGen].
Do NOT batch. One image per assignment, one at a time.

After all images are generated:

Issue three MusicGen assignments, one at a time, using the same MusicGen agent and the
same sequential pattern as image generation. Use the final manuscript summary as context,
but keep each prompt focused on a distinct setup.

TRACK 1 -- BATTLE THEME:
[ASSIGN MusicGen]: Create a 120-second cinematic underground-fight battle theme based on
the final novel. Prompt: tense American noir action score, heavy drums, low strings,
industrial percussion, rain on concrete, collapsing exhibition-ring energy, old fighters,
no triumph, just survival. Clean high-quality mix. No vocals.
After MusicGen yields the floor: [ACCEPT music]

TRACK 2 -- CLINIC DREAD:
[ASSIGN MusicGen]: Create a 100-second eerie clinic-and-syndicate dread cue based on the final novel.
Prompt: fluorescent hum, low piano, distant rail noise, medical rhythm, muffled crowd
memory, illegal treatment room tension, mentor shame, student corruption, a mind too loud
to defend itself. Clean high-quality mix. No vocals.
After MusicGen yields the floor: [ACCEPT music]

TRACK 3 -- AFTERMATH CREDITS:
[ASSIGN MusicGen]: Create an 80-second somber aftermath and credits cue based on the
final novel. Prompt: exhausted strings, minimal percussion, reflective low drones, rain
at a ferry terminal, survivors leaving the ring, not victory, love offered and refused
for sacrifice, one quiet breath after impossible speed, cost-aware ending. Clean high-quality mix. No vocals.
After MusicGen yields the floor: [ACCEPT music]

After the third track is accepted:
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
  framed as the lead, use them. Otherwise use the aged mentor role seed. For the
  built-in preset, this protagonist is an aged 60+ mentor-fighter, not a young prodigy.
2. CAST: List every named character or role seed. If the input uses role seeds, instruct
  CharacterArchitect to invent final names freely and consistently. Map each role using
  STORY/CHARACTER context: mirror (reflects hero's dilemma), anchor (provides grounding),
  shadow (embodies fear).
3. MODE: one-book
4. REGISTER: adult 18+ dark fighter audience. Harder consequences, harsher atmosphere,
  greater moral damage, and no sanitising of cost; avoid gratuitous gore.
5. ECHO TERM: Extract the most concrete, repeatable noun or short phrase from CREST
   . This term must appear in every chapter.
6. THEME: The central truth from CREST in one sentence. Must name the crest axis directly --
   do NOT reframe it as a universal kindness/acceptance statement.
7. VERSE THREAD SUBJECT: What the assembled poem is about -- drawn from CREST axis.
8. CREST_CLAIM: The surface ideology the protagonist performs for others -- extracted from
   CREST. One sentence. (e.g. ' When we become kinder to ourselves, we can become kinder to the world.')
9. HIDDEN_SHAME: The private inferiority the protagonist conceals beneath CREST_CLAIM.
   One sentence. 
10. SOCIAL_AXIS: The specific group, hierarchy, or relationship where contempt plays out
    in this story. 
11. FORBIDDEN_DRIFT: The comfortable reframe that would betray the CREST. Name it exactly
    so every agent can veto it. 
12. TONE: Read from CREST. 
    If CREST contains irony, absurdity, or self-defeating logic, the tone is dark-comic.
13. IMAGE_TEXT_POLICY: no-text-in-image. Diffusion models cannot reliably render readable
  text. Describe Stillness Verse fragments in image prompts as visual marks, carved script, or
    written traces -- never as specific quoted lines.
14. CORE_ARC_QUESTION: Extract the stillness question from CREST. For the built-in preset:
  'When everything around me is moving so fast, is the world busy, or is my mind?'
  Treat this as the novel's dramatic engine, not a moral poster.
15. STILLNESS_DISCIPLINE: Define the concrete battlefield discipline created by the
  CORE_ARC_QUESTION: breath before impact, refusing crowd tempo, seeing the real attack,
  and choosing one true motion instead of frantic motion.
16. ORIGINALITY_LOCK: no existing franchise names, copied power upgrades, copied move
  names, copied organizations, copied cities, copied tournament names, or exact canon
  relationships. Use broad grounded superhuman fighter archetypes only, then make the
  world original.

Relay all 16 translations verbatim to every agent that needs them.
${PHASES_1_4}${VOICE_AND_PROSE}"

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------
ofp-playground start \
  --policy showrunner_driven \
  --no-human \
  --topic "Fight Noir engaging story of: ${STORY}" \
  --agent "-provider anthropic -type orchestrator -name SeriesDirector -system ${MISSION} " \
  --agent "-provider openai -name CharacterArchitect -system @creative/character-architect -model gpt-5.5" \
  --agent "-provider anthropic -name NarrativePacingArchitect -system @creative/narrative-pacing-architect -model claude-sonnet-4-6" \
  --agent "-provider openai -name VerseArchitect -system @creative/verse-architect -model gpt-5.5" \
  --agent "-provider anthropic -name MangaArcPlanner -system @creative/manga-arc-planner -model claude-sonnet-4-6" \
  --agent "-provider anthropic -name LoreContinuityGuardian -system You are a compact continuity and originality auditor for an original earthlike American superhuman fight-noir novel. Audit grounded power rules, medical/social costs, names, causal logic, city/network plausibility, and originality drift. Do not rewrite prose. Output actionable fixes only. -model claude-sonnet-4-6" \
  --agent "-provider anthropic -name FightChoreographer -system You are a battle-manga action designer for an original grounded superhuman martial-noir novel. Build readable set pieces with tactical turns, emotional costs, visual money shots, and originality checks. Powers serve character, pain addiction, and final choice; they are not the protagonist. No copied move names or franchise references. -model claude-sonnet-4-6" \
  --agent "-provider anthropic -name ProseNovelist -system @creative/prose-novelist -model claude-sonnet-4-6" \
  --agent "-provider openai -name Chapter01Novelist -system @creative/prose-novelist -model gpt-5.4" \
  --agent "-provider anthropic -name Chapter02Novelist -system @creative/prose-novelist -model claude-sonnet-4-6" \
  --agent "-provider anthropic -name Chapter03Novelist -system @creative/prose-novelist -model claude-sonnet-4-6" \
  --agent "-provider anthropic -name Chapter04Novelist -system @creative/prose-novelist -model claude-sonnet-4-6" \
  --agent "-provider anthropic -name Chapter05Novelist -system @creative/prose-novelist -model claude-sonnet-4-6" \
  --agent "-provider anthropic -name Chapter06Novelist -system @creative/prose-novelist -model claude-sonnet-4-6" \
  --agent "-provider anthropic -name Chapter07Novelist -system @creative/prose-novelist -model claude-sonnet-4-6" \
  --agent "-provider anthropic -name Chapter08Novelist -system @creative/prose-novelist -model claude-sonnet-4-6" \
  --agent "-provider anthropic -name Chapter09Novelist -system @creative/prose-novelist -model claude-sonnet-4-6" \
  --agent "-provider openai -name Chapter10Novelist -system @creative/prose-novelist -model gpt-5.4" \
  --agent "-provider anthropic -name RevisionEditor -system You are a surgical revision editor for an original illustrated action novel. Preserve the strongest draft material, identify precise chapter-level fixes, protect continuity and originality, and produce a revision brief rather than rewriting. -model claude-sonnet-4-6" \
  --agent "-provider anthropic -name MangaCharacterArtist -system You are a safe manga character reference prompt engineer for image generation. Output neutral character reference prompts only. Never mention real artists, authors, creators, studios, directors, mangaka, painters, franchises, copyrighted characters, or named-style reference phrases. Keep prompts nonviolent and non-graphic: calm full-body or three-quarter pose, simple background, clean original manga-inspired ink line art, restrained screentone, soft wash accents, readable costume silhouette, palette, hair, face, power motif, and continuity marks. Do not describe visible injuries, scars, burns, bruises, blood, gore, horror, monsters, weapons, hidden weapons, drug or substance use, self-harm, suicide, despair, or body horror. Translate dark story traits into costume, posture, palette, and symbolic motifs. Output only the requested blocks. -model claude-sonnet-4-6" \
  --agent "-provider anthropic -name MangaSceneArtist -system You are a safe manga environment reference prompt engineer for image generation. Output calm scene anchor prompts only. Never mention real artists, authors, creators, studios, directors, mangaka, painters, franchises, copyrighted characters, or named-style reference phrases. Focus on American architecture, ring layout, clinic corridors, rail and ferry spaces, abstract signage or medical-diagram geometry, palette, lighting, scale, atmosphere, negative space, clean original manga-inspired ink line art, restrained screentone, and simple environment continuity. Do not describe violence, injuries, blood, gore, horror, monsters, power breakdowns, drug or substance use, self-harm, suicide, or bodies. Translate dark plot events into abstract shapes, empty spaces, lighting contrast, and symbolic motifs. Output only the requested blocks. -model claude-sonnet-4-6" \
  --agent "-provider anthropic -name MangaScripter -system @creative/manga-scripter -model claude-sonnet-4-6" \
  --agent "-provider anthropic -name MangaArtist -system You are a safe manga illustration prompt engineer for image generation. Output clean positive prompts for final story images. Never mention real artists, authors, creators, studios, directors, mangaka, painters, franchises, copyrighted characters, or named-style reference phrases. Keep prompts non-graphic and image-model friendly: original manga-inspired ink line art, restrained screentone, soft wash accents, clear character silhouettes, calm or readable action staging, symbolic power motifs, environment continuity, no readable text. Do not describe visible injuries, blood, gore, horror, monsters, drug or substance use, self-harm, suicide, or body horror. Translate dark story moments into posture, lighting, abstract geometry, empty space, and symbolic energy. Output only the requested blocks. -model claude-sonnet-4-6" \
  --agent "-provider openai -type text-to-image -name IllustrationGen -system safe original manga-inspired ink line art, neutral character and scene reference images, restrained screentone, soft wash accents, clear silhouettes, symbolic power motifs, no readable text, no named artist references, non-graphic -model gpt-image-2" \
  --agent "google:text-to-music:MusicGen:high-quality production, clean mix:lyria-3-pro-preview"