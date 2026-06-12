# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Directory Is

`agents/` is a library of 223 SOUL.md persona files — structured system prompts for AI agents — organized into 24 category subdirectories. There is no build system, tests, or executable code here. The only task is reading, writing, and maintaining `SOUL.md` files.

The library is loaded by `src/ofp_playground/agents/library.py`. Every `agents/<category>/<agent-name>/SOUL.md` is addressable as `@category/agent-name` without any registration step.

## Adding a New Persona

```
agents/<category>/<agent-name>/SOUL.md
```

The slug is `@<category>/<agent-name>` — the directory names are the slug. No registration needed; the loader rescans on next process start.

To verify it's discoverable:
```bash
ofp-playground agents | grep <agent-name>
```

## SOUL.md Format

Free-form Markdown. No required frontmatter. The loader extracts the display name from the first heading, stripping common prefixes (`# `, `# Agent: `, `# SOUL.md — `).

Three heading styles are in use across the library — pick the one that fits:

```markdown
# Agent: Name Here          ← most common (business/creative/etc.)
# Name Here                  ← terse style (development/*)
# SOUL.md — Name Here        ← older style (data/marketing/*)
```

Common section structure seen across the library:

```markdown
## Identity / Core Identity
## Responsibilities
## Skills / Capabilities
## Rules / Behavioral Guidelines
## Tone
## Example Interactions   ← optional but valuable
```

The `development/` category personas embed software methodology (TDD, debugging discipline, verification). Match that level of specificity when writing new development personas.

The 3D/XR personas (`@development/threejs-developer`, `@development/spatial-developer`, `@creative/3d-scene-composer`, `@creative/spatial-experience-designer`) form a cluster for immersive web work. Key conventions they share:
- `@development/threejs-developer` — WebGL/Three.js engineering rules (dispose everything, draw call budgets, instancing)
- `@development/spatial-developer` — WebXR Device API specialist (session setup, reference spaces, 72fps non-negotiable)
- `@creative/3d-scene-composer` — cinematography/lighting director; always specifies concrete values (Kelvin temps, PBR floats)
- `@creative/spatial-experience-designer` — UX/comfort/presence design; diegetic UI, spatial audio, motion sickness mitigation

When writing new 3D/XR personas, follow the same pattern: non-negotiable rules block at the top, concrete value tables, and per-frame performance budgets.

The blocky/voxel model cluster (`@creative/blocky-character-designer` + `@development/geometry-builder`) works as a two-agent pipeline with a shared vocabulary. The creative agent outputs a parts table (geometry term, W×H×D, position, hex color, notes flags); the dev agent translates that table into a `buildXxx()` Three.js function. The shared vocabulary terms — `box`, `slab`, `plane`, `edge-highlight`, `shared: <part>`, `bilateral` — are defined in both SOULs and must stay in sync if either is updated.

The procedural platformer cluster extends the blocky pipeline into a full game generation system:
- `@creative/theme-asset-director` — converts `{theme, hero}` into a 9-asset manifest (hero, obstacle-ground, obstacle-aerial, collectible, platform-tile, background-prop, deco-a, deco-b, deco-c) with hex palette; decoratives are atmospheric only
- `@creative/texture-director` — designs tileable textures in two forms: canvas2D procedural code (file:// safe, always) + DALL-E prompts; outputs `makeXxxTexture()` functions returning `THREE.CanvasTexture`; DALL-E images can be embedded as base64 `data:` URLs (no CORS)
- `@development/platformer-architect` — produces implementation-ready 2.5D endless runner specs: physics, scroll system, AABB collision, difficulty curve, Web Audio SFX, AND the showcase home screen (rotating hero on pedestal, fade transition, start button)
- All feed into `examples/example_platformer.sh` which runs 8 phases: ThemeAssetDirector → BlockyCharacterDesigner × 9 → GeometryBuilder → TextureDirector → DALL-E TextureGen → PlatformerArchitect → SceneComposer → coding session (14 rounds)

The illustrated fiction cluster (`@creative/series-director`, `@creative/character-architect`, `@creative/narrative-pacing-architect`, `@creative/verse-architect`, `@creative/prose-novelist`, `@creative/aquarelle-painter`) is a strict 6-soul pipeline for producing verse-threaded, illustrated narrative fiction. All six souls share a common vocabulary (`beat`, `phase`, `word budget`, `arc`, `seed`, `echo`, `payload`, `verse fragment`, `unlock condition`, `refrain`, `verse thread`, `threshold`, `mirror character`, `anchor character`, `shadow`) that must stay in sync if any soul is updated. Pipeline order:

```
SeriesDirector → CharacterArchitect → NarrativePacingArchitect → VerseArchitect → ProseNovelist → AquarellePainter
```

- `@creative/series-director` — orchestrator; produces Series Bible and Story Briefs; manages seeds/payoffs across 1–12 stories; mode-aware (one-book / anthology / shared-world / flexible)
- `@creative/character-architect` — hero arc design (hero's journey framework); side character roles (mirror/anchor/shadow); produces Character Blueprint
- `@creative/narrative-pacing-architect` — word budget allocation across 5 phases (Setup 10% / Complication 30% / Deepening 25% / Crisis 20% / Resolution 15%); beat lists; tension curves; produces Story Spine
- `@creative/verse-architect` — narrative poetry specialist; designs verse threads where each fragment is a quest artifact discovered at a beat; knows meter (anapestic/trochaic/iambic/accentual); produces Verse Thread Manifest
- `@creative/prose-novelist` — sole executor of finished prose; reads all three upstream specs before writing; inserts verse fragments verbatim; word budget tolerance ±15% per phase
- `@creative/aquarelle-painter` — watercolour illustration specialist; translates beats into image generation prompts; technique mapped to beat type (wet-on-wet for wonder, lost edge for threshold, paper white for verse fragment discovery); style references: Klee, Rackham, Dulac, Nielsen
- `@creative/character-memory-keeper` — condensed character state archivist; reads breakout transcripts and writes 150–200-word per-character memory MDs injected as system prompts in subsequent breakout sessions

## Categories

| Category | Count | Notes |
|---|---:|---|
| `marketing` | 28 | Largest category |
| `development` | 27 | Coding-methodology personas; `@development/coding-agent` auto-loaded by `BaseCodingAgent` |
| `business` | 14 | |
| `creative` | 31 | +6 illustrated fiction cluster + MemoryKeeper |
| `finance` | 10 | |
| `devops` | 10 | |
| `productivity` | 9 | |
| `data` | 9 | |
| `hr` | 8 | |
| `education` | 8 | |
| `personal` | 7 | |
| `healthcare` | 7 | |
| `ecommerce` | 7 | |
| `security` | 6 | |
| `saas` | 6 | |
| `legal` | 6 | |
| `automation` | 6 | |
| `real-estate` | 5 | |
| `freelance` | 4 | |
| `compliance` | 4 | |
| `voice` | 3 | |
| `supply-chain` | 3 | |
| `moltbook` | 3 | Agent-to-agent social network personas |
| `customer-success` | 2 | |

For complete documentation including Python loading API, see [`docs/agents-library.md`](../docs/agents-library.md).
