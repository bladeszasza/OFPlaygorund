# Teaching AI Agents to Build Their Own Game

*How a two-word prompt — "space, astronaut" — becomes a playable Three.js browser game through a pipeline of specialist agents.*

---

There is a question I kept coming back to while building OFP Playground: what happens when you give a multi-agent system a creative problem that genuinely requires multiple disciplines?

Writing a story is one thing. Different agents handle plot, prose, and illustration — the disciplines are separable and the handoffs are clean. But making a game is different. A game requires visual design, game mechanics, code architecture, and asset production — all of which are deeply interdependent. A mechanic that seems sensible in prose falls apart when you actually see it rendered. An asset that looks great in isolation breaks the palette of the world it belongs to. The code that implements a physics constant only works if the level design respects it.

I wanted to see if a multi-agent pipeline could hold all of that together. The result was a procedural endless runner that generates itself from two words.

---

## The Idea

Type two words — a theme and a hero. Press enter. Wait.

What you get back is a complete, playable browser game: a Three.js endless runner with custom 3D blocky characters, procedural obstacle spawning, three-lane movement, a score system, and SFX. The game runs by opening `index.html` directly from your filesystem — no server, no build step, no dependencies to install.

The theme and hero you enter shape everything: the visual style of every asset, the color palette, the atmosphere of the environment, the names of obstacles and collectibles. Type "space" and "astronaut" and you get a debris field with tumbling asteroids and drifting satellites. Type "jungle" and "fox" and you get root bumps and diving toucans.

The game mechanics — physics, spawning, collision, difficulty curve, scoring — are constant across all themes. That's the design insight that makes the whole thing tractable: separate what changes (the theme) from what doesn't (how the game works).

---

## Why This Needs New Agents

OFP Playground already had specialists for Three.js development and 3D visual direction. What it was missing was understanding of the *problem space* — what a game like this actually needs, and how to translate a theme into concrete deliverables.

Before writing a single line of the pipeline, I spent time designing two new agents from scratch. The process of doing that taught me something about what makes a good specialist agent.

### `@creative/theme-asset-director` — knowing what exists

The first gap was between "space theme" and "here are the specific assets to build." Someone needs to make that translation — and it is not a trivial job. A game world needs exactly the right inventory of pieces: not too many (the coding session has a limited context window and a deadline), not too few (the world feels empty). The pieces need to complement each other visually. They need to serve the game mechanics — a ground obstacle and an aerial obstacle are structurally different things, and both are required.

The Theme Asset Director's job is to produce a manifest: exactly 6 assets, structured as a table, each with a visual brief concrete enough that a designer can act on it immediately. One hero, two obstacles (one ground, one aerial), one collectible, one platform tile, one background prop. Every row also specifies the key hex colors — not "warm orange" but `#cc4400`. The whole manifest shares one coherent palette.

What I learned building this: the most important constraint in the SOUL wasn't about creativity — it was structural. The rule that aerial obstacles must be at a specific Y height, that the ground obstacle must be jumpable, that the background prop must be placeable at a specific Z depth — these constraints exist because the Platformer Architect will later specify exact physics constants that the designer needs to respect. The creative agent needs to know the game's rules even though it never writes game code.

### `@development/platformer-architect` — knowing how the game works

The second gap was between "endless runner" and "here are the exact constants to implement one." This is where I see a lot of multi-agent game pipelines fail: they get a description of a game and try to let the coding agents figure out the physics. The result is usually wrong — jump heights that feel floaty, obstacles that are impossible to dodge, difficulty curves that spike without warning.

The Platformer Architect produces implementation-ready numbers. Not "the player should feel snappy" — but `gravity: -22`, `jumpForce: 11`, `maxFallSpeed: -22`. Not "obstacles spawn periodically" — but the exact spawn interval decay formula, the pattern unlock schedule keyed to elapsed time, the despawn distance behind the player. Not "there's a score" — but the exact HUD element list, the localStorage key for the high score, the per-frame distance calculation.

The spec also bakes in constraints derived from the physics model. `jumpForce² / (2 × |gravity|)` gives you the max jump height at the initial scroll speed — and that calculation directly constrains what heights aerial obstacles can be placed at. If an aerial obstacle's base is at Y=1.8, the standing player clears it (head at Y=1.5), and the jumping player sails over it (peak at Y=4.25). That relationship has to be explicit in the spec or the coding agents will break it.

---

## The Visual Design Pipeline

The existing `@creative/blocky-character-designer` and `@development/geometry-builder` agents were already built for exactly this problem. A blocky character designer that thinks in Crossy Road proportions — big heads, stubby legs, everything a box — and a geometry builder that translates parts tables into `buildChicken()` functions returning `THREE.Group`.

What changed was that they now work inside a larger pipeline, called sequentially by the Showrunner. After the Theme Asset Director produces the manifest, the Showrunner issues one `[ASSIGN CharDesigner]` per asset — six sequential calls, each one getting a single manifest row and producing a complete parts table. Then the Geometry Builder receives all six tables at once and outputs all six `buildXxx()` functions in a single code block.

The separation matters. The character designer thinks spatially — proportions, visual identity, charm — and never touches Three.js. The geometry builder thinks mechanically — geometry reuse, material sharing, disposal — and never makes aesthetic decisions. The handoff format between them is a shared vocabulary: `box`, `slab`, `edge-highlight`, `bilateral`, `shared: <partname>`. Both agents know these terms and use them the same way.

---

## Orchestrating It All

The shell script that runs the pipeline asks for two words and then does the rest:

```bash
bash example_platformer.sh
# Enter game theme: space
# Enter hero character: astronaut
```

Seven agents, six pipeline phases, one coding session with two developer agents running round-robin for twelve turns. The Showrunner — running in `SHOWRUNNER_DRIVEN` mode — coordinates everything.

The phase sequence:

1. **Asset manifest** — Theme Asset Director produces the 6-asset table
2. **Character design** — Blocky Character Designer runs once per asset
3. **Geometry code** — Geometry Builder produces all six `buildXxx()` functions
4. **Game mechanics** — Platformer Architect produces the physics/spawner/collision spec
5. **Atmosphere** — 3D Scene Composer produces the lighting and fog values
6. **Coding session** — Two developer agents build the game from everything above

The coding session is where the manuscript becomes a game. DevAlpha (Anthropic, `@development/threejs-developer`) architects the game loop, state machine, input handling, and renderer setup. DevBeta (OpenAI, `@development/geometry-builder`) handles the asset integration — wiring the `buildXxx()` functions into the spawner, managing object pooling, and the disposal lifecycle. Twelve round-robin turns. The full manuscript — every geometry function, every physics constant, every hex color — is in their shared context from the start.

The result is written to `result/<session>/sandbox/`: three files, open `index.html` in a browser.

---

## The CORS Problem (and How the Agents Know About It)

There is a specific failure mode that bit us early: CORS. The game runs from `file://`, and browsers block local file access from that context. A coding agent that naively writes `new THREE.TextureLoader().load('./grass.png')` produces a game that silently breaks on every user's machine.

The fix lives in the `@development/threejs-developer` SOUL — a CORS prevention section that enumerates exactly which patterns are blocked and what to use instead. Textures become `THREE.CanvasTexture` (procedurally generated). Models are always procedural geometry — never loaded `.glb` files. Audio is Web Audio API oscillators, never `AudioLoader`. Data is inlined as `const` declarations.

The agent knows this not because it was told "be careful about CORS" but because it has a specific table listing the four triggers and their corresponding fixes. When it writes code, it writes CORS-safe code by default — not because it remembered a warning but because the pattern is part of how it thinks.

---

## What the Output Actually Looks Like

Open `index.html`. A Three.js scene fills the viewport: a dark debris field receding into indigo fog, a chunky white astronaut standing in the center lane. Press Space. The astronaut jumps. Asteroids roll toward you at ground level. A satellite drifts in from the right at head height. You switch lanes with arrow keys. A gold oxygen canister hovers in the center lane — you run through it, a boop plays, +10 to score.

The geometry is chunky and intentional — the MeshToonMaterial gives everything a flat-shaded graphic novel quality. The lighting is a single cool directional light from above-left with a subtle blue ambient fill, specified by the Scene Composer to evoke orbital vacuum. The fog matches the scene background exactly, so the horizon is seamless.

It runs at 60fps on a laptop. It runs directly from the filesystem. Two words produced it.

---

## The Versatility Point

The game itself is not the point. The point is the pattern.

The same pipeline — same Showrunner, same six phases, same coding session structure — runs equally well for "jungle, fox" or "medieval, knight" or "cyberpunk, robot". The mechanics spec doesn't change. The Three.js architecture doesn't change. The only things that change are the outputs of Phase 1 through Phase 5: the asset shapes, the hex colors, the lighting, the atmosphere.

This is what multi-agent coordination actually buys you: the ability to separate disciplines so completely that each one can vary independently. A traditional code generator would have to hold the entire creative and technical problem in a single context window. Here, each agent holds one part of the problem — and holds it well, because its SOUL was designed specifically for that part.

The agents I built for this pipeline — Theme Asset Director and Platformer Architect — didn't exist before I needed them. Neither did the blocky character designer or the geometry builder. Each was designed to solve a specific translation problem in a specific pipeline. That is what the agent library is: a growing vocabulary of specialists, each built for a problem that turned out to be real.

---

## Running It Yourself

```bash
git clone https://github.com/bladeszasza/OFPlayground
cd OFPlayground
pip install -e .

# Set ANTHROPIC_API_KEY and OPENAI_API_KEY

bash examples/example_platformer.sh
# Enter game theme: underwater
# Enter hero character: fish
```

The result lands in `result/<session>/sandbox/`. Open `index.html`. Play.

If you want to understand what happened: `result/<session>/trace.html` is an interactive D3 timeline of every OFP envelope routed during the session — every agent utterance, every floor grant, every directive. You can watch the manuscript build up phase by phase.

---

## First Real Run: Hungarian Dimetrodon

The first pipeline run that actually completed end-to-end was not "space, astronaut." It was "hungarian, dimetrodon."

A dimetrodon is a prehistoric synapsid — not a dinosaur, despite the common assumption — best known for the dramatic neural spine sail running the length of its back. Pairing it with Hungarian folk art as the visual theme was not something I planned. It came out of wanting to test with a combination that was genuinely strange, not a safe choice.

What the agents produced was coherent in a way I didn't expect.

### The palette held together

The Theme Asset Director settled on five colors: walnut brown `#6b4a2f`, paprika red `#b63a2b`, wheat gold `#d4a437`, cream `#f2e6cf`, and Magyar blue `#2f5c8a`. Every subsequent agent — the character designer, the geometry builder, the texture director, the scene composer — worked within that palette without being told to. The Geometry Builder doesn't know what colors the Theme Asset Director chose; it receives a parts table, and the parts table specifies the hex values. The palette propagates through the handoff format, not through shared state.

The Texture Director generated three Canvas2D textures — platform tiles with walnut-brown flagstone and gold embellishment marks, a ground surface with wheat-colored soil and paprika-red folk dot motifs, a hero body texture with cream belly stripes and red banding. All `THREE.CanvasTexture` — no external file loads, no CORS. The game renders the same way whether opened from a USB drive or a local folder.

### The Dimetrodon

The hero geometry is a quadruped with a chunky body, stubby legs, and three stacked sail fins — `sail_back`, `sail_mid`, `sail_front` — rising above the spine. The tall middle sail (`0.16 × 1.02 × 0.26`) flanked by shorter ones on either end gives it a silhouette that's immediately readable even at small screen sizes.

The coding agents added a sail color feedback system on their own initiative: at combo ×3 and above, the sail fins oscillate between the base paprika red and a warm golden highlight. The sine wave frequency scales with the combo multiplier. At ×5 the whole spine is pulsing gold. It wasn't in the spec — the Platformer Architect's manuscript said nothing about sail animation. The coder read the character geometry, noticed the sail meshes were stored in `hero.userData.sails`, and wired them into the combo system.

### The collectibles

Paprika bundles. Three plump red pepper boxes tied with a gold ribbon at the top. They spin on the Y axis and bob on a per-index staggered sine wave so they never all move in unison. Running through one plays a short boop and adds 10 points — or up to 50 with the combo multiplier active.

### The decoratives

The background props are a folk village: cream-walled cottages with blue roofs and red chimneys at Z=-14, and lining both sides of the road, ribbon pinwheels — a stick, a hub, and four blades in the folk palette (red, blue, gold, cream). The pinwheels are not static. Their rotation speed scales with `scrollSpeed`, so as the game accelerates and obstacles come faster, the village pinwheels spin faster too. A small touch. The geometry builder coded it without being asked.

### Two coding sessions

The pipeline ran two separate breakout coding sessions rather than one long one. The first session (three rounds, DevAlpha + DevBeta) built the core game: renderer, physics, spawner, collision, geometry functions, all nine assets wired in, scoring, and a working game loop. The second session took the completed game and added the polish layer: the combo multiplier system, squash-and-stretch on landing, the bobbing collectibles, the parallax background scroll, and the pinwheel wind sync.

Splitting into two passes turned out to work well. The first pass produced a complete, correct game — a known-good baseline. The second pass had the full game in context and could add to it without breaking what was already working. A single 14-round session would have carried more risk of mid-session regressions.

### What didn't need fixing

The collision logic was correct on the first pass. The aerial obstacle sits at Y=1.8, the hero's head at ground level is at Y=1.5 — standing clears it. Jumping peaks at Y=4.25 — the jump sails over. The Platformer Architect's spec baked in the relationship explicitly (`jumpForce² / (2 × |gravity|) = 2.75` peak height), and the coding agent respected it. No collision tuning was required.

The CORS rules held. Every texture is Canvas2D. Every model is procedural. The Three.js library is loaded from a CDN `<script>` tag in the HTML. `index.html` opened directly from the filesystem — no server — and the game ran.

### The result

A playable Three.js endless runner: a blocky Dimetrodon sprinting through a Hungarian folk village, dodging barrel obstacles and gate arches, collecting paprika bundles, its sail fins flushing gold when you're on a streak. Open `index.html` in a browser.

The agents didn't know what a dimetrodon was in any meaningful sense. They knew what parts tables look like and what `buildHero()` functions should do. The theme shaped the inputs; the pipeline shaped the outputs. That's the pattern.

---

## Debugging What the Agents Got Wrong

A first run that actually completes is not a finished game. Opening the Hungarian Dimetrodon result in a browser revealed two bugs immediately.

### The blinking road

The road tiles at the far end of the visible track would briefly disappear and reappear. Not a flicker — a clean pop. Tiles were there, then gone, then back a fraction of a second later somewhere further back.

The bug was in the tile recycling logic. When a tile scrolls past a threshold `frontZ`, it wraps — jumps `count * tileDepth` units back to re-enter the scene ahead. The spec in the `@development/platformer-architect` SOUL had:

```javascript
const frontZ = SPAWN.heroZ + TILE.depth * 2;   // = 2
```

Two units ahead of the hero. The camera sits at Z=12 looking at Z=0. A tile at Z=2 is well inside the camera's frustum — visible to the player. The recycle was happening in full view. The tile vanished from the front of the road and reappeared at the back.

The fix is to wrap only after the tile has passed *behind the camera*, not past the player:

```javascript
const frontZ = CAMERA.position.z + 2;   // = 14 — safely behind the lens
```

With the camera at Z=12, a tile at Z=14 is 2 units behind the viewer. No tile at that position is visible. The pop disappears entirely.

The important thing: this wasn't a coding agent mistake. The agent followed the spec it was given. The spec in the Platformer Architect SOUL was wrong. The source of the bug was one line in a SOUL file, and so the fix had to be in the SOUL, not just in the output game.

### The broken restart

After a game over, pressing SPACE restarts. The score reset to zero. The obstacles cleared. The hero snapped back to position. But the road was wrong — tiles at arbitrary Z offsets, the scroll state mid-stride from wherever it was when the player died.

The issue: `startGame()` in the spec reset the physics variables and cleared obstacles and collectibles, but it never reset the tile positions. Tiles had been scrolling forward the entire run. On restart they were wherever they happened to be — not laid out from the start position. The game continued mid-scroll.

Two things were missing from `startGame()`:

```javascript
// Reset road tiles to initial layout
for (let i = 0; i < tiles.length; i++) {
  tiles[i].position.z = SPAWN.heroZ + TILE.depth - i * TILE.depth;
}
// Reset background parallax offset
bgGroup.position.z = 0;
```

Without the first block, every restart begins with the road in a broken state. Without the second, the background village drifts further forward with each run. Neither error is visible on the very first play — only on retry.

Again, the fix belonged in the spec, not the output. The State Machine section of the Platformer Architect SOUL now includes both resets in its `startGame()` template, with an explicit comment explaining why. The next run of the pipeline will generate a game that resets correctly from the first draft.

### What this says about the pipeline

Both bugs followed the same pattern: the coding agents did exactly what the spec said, the spec was incomplete, and the incompleteness only showed up at runtime. You can't catch these problems by reading the code. The code is correct — it correctly implements a flawed spec.

The fix for this kind of bug isn't to tell the coding agents to be more careful. It's to improve the spec agents. The Platformer Architect is the agent that owns tile recycling and game state resets. When it gets them wrong, every game it designs has the same bugs. When it gets them right, no future game has them at all.

That's the leverage in the agent library. A bug found in one run, fixed in the SOUL, is a bug that will never appear again regardless of theme.

---

*OFP Playground is open source. Built on the [Open Floor Protocol](https://openfloor.dev/introduction). Supports Anthropic, OpenAI, Google, and HuggingFace.*
