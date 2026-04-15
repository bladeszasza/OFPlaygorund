#!/bin/bash
# example_platformer.sh
# Procedural Blocky Endless Runner — theme-driven, Three.js, file://-safe
#
# Agent roster (9 total):
#
#   Orchestrator:
#   - anthropic:orchestrator        → Showrunner        (claude-haiku-4-5)
#
#   Design pipeline:
#   - openai:text-generation        → AssetDirector     (@creative/theme-asset-director)
#   - openai:text-generation        → CharDesigner      (@creative/blocky-character-designer)
#   - openai:text-generation        → GeomBuilder       (@development/geometry-builder)
#   - openai:text-generation        → TextureDir        (@creative/texture-director)
#   - openai:text-to-image          → TextureGen        (generates canvas2D textures)
#   - openai:text-generation        → GameArchitect     (@development/platformer-architect)
#   - openai:text-generation        → SceneComposer     (@creative/3d-scene-composer)
#
#   Coding session (round-robin, 14 rounds):
#   - anthropic:code-generation     → DevAlpha           (@development/threejs-developer)
#   - openai:code-generation        → DevBeta          (@development/geometry-builder)
#
# Pipeline phases:
#   1.  AssetDirector  — manifest: 9 assets (hero, 2 obstacles, collectible, tile, bg-prop, deco-a/b/c)
#   2.  CharDesigner   — parts tables for all 9 assets (sequential [ASSIGN]s)
#   3.  GeomBuilder    — all buildXxx() Three.js functions in one block
#   4.  TextureDir     — canvas2D texture recipes prompts for platform, ground, hero surface
#   5.  TextureGen     — generates 2-3 texture images + base64 data URLs for coding agents
#   6.  GameArchitect  — game mechanics + showcase home screen spec
#   7.  SceneComposer  — lighting + atmosphere spec for the theme
#   8.  [ASSIGN DevAlpha]  — builds complete main.js on the main floor (warm-up, 10-20 turns)
#   9.  [CODING_SESSION]  — 2 agents refine the game (6 rounds; DevAlpha emits [CODING_COMPLETE] when playable)
#
# Output:  result/<session>/sandbox/  →  index.html + main.js + style.css
#          Open index.html directly in any browser — no server required
#
# Usage:
#   bash example_platformer.sh
#   bash example_platformer.sh space astronaut      # skip prompts
#
# Requirements:
#   - ANTHROPIC_API_KEY, OPENAI_API_KEY
#   - ofp-playground CLI installed
#   - agents/ library available (for @soul references)

set -e

# ---------------------------------------------------------------------------
# Theme + hero input
# ---------------------------------------------------------------------------
if [ -n "$1" ] && [ -n "$2" ]; then
  THEME="$1"
  HERO="$2"
else
  echo ""
  echo "Procedural Blocky Platformer Generator"
  echo "--------------------------------------"
  echo "Themes:  space, jungle, medieval, cyberpunk, underwater, desert, arctic"
  echo "Heroes:  astronaut, fox, knight, robot, fish, mummy, penguin, ninja"
  echo ""
  read -rp "Enter game theme: " THEME
  read -rp "Enter hero character: " HERO
fi

echo ""
echo "Generating: ${THEME} theme — ${HERO} hero"
echo ""

# ---------------------------------------------------------------------------
# Showrunner mission brief
# ---------------------------------------------------------------------------
read -r -d '' SHOWRUNNER <<MISSION || true
You are the game development director for a procedural endless runner built in Three.js. Your mission: orchestrate a team of specialists to design and implement a playable browser game with theme "${THEME}" and hero "${HERO}".

The final output must run when the user opens index.html directly from file:// in a browser. No bundler, no local HTTP server, no build step.

CRITICAL DELIVERY CONSTRAINTS (non-negotiable — relay verbatim to every agent that writes code):
- Do NOT use importmap in the final artifact.
- Do NOT use <script type="module" src="./..."></script> with local files.
- Do NOT use bare imports like \`import * as THREE from 'three'\`.
- Runtime shape: index.html + main.js + optional style.css. Nothing else.
- index.html must load Three.js as a classic global script from CDN (unpkg.com/three@0.160.0/build/three.min.js), then load ./main.js with a regular deferred script tag.
- main.js must be the single bundled runtime entry with no import/export syntax. It may use window.THREE.
- NEVER load local files via TextureLoader, GLTFLoader, AudioLoader, or fetch() — CORS blocks all local file access from file:// protocol. All textures must be procedural (THREE.CanvasTexture) or from CDN URLs. All audio must be Web Audio API oscillators. All data must be inlined as JS constants.
- The renderer canvas must be visible: use a fixed full-viewport root or position the canvas fixed at z-index 0.

CRITICAL GAME ARCHITECTURE RULES (relay verbatim to coding agents):
- antialias: false — ALWAYS. This is non-negotiable for the stylized blocky look.
- HERO Z IS FIXED AT 0. The hero never moves in Z. Only obstacles and platform tiles move in +Z each frame. Do NOT move the hero in Z. Do NOT use a worldGroup offset trick.
- Spawn obstacles at Z = -(SPAWN.aheadDistance) = -40. They travel from -40 toward +5 past the hero at Z=0 and despawn when obj.position.z > 5. This is the ONLY correct pattern.
- Platform tiles MUST recycle: wrap a tile only after its Z exceeds the camera position (camera.position.z) plus a small buffer — e.g. frontZ = CAMERA.position.z + 2 = 14. Using heroZ + TILE.depth * 2 = 2 is WRONG — tiles at Z=2 are still fully visible to the player and will appear to pop out mid-screen. Never despawn tiles.
- Lane switching is a discrete TOGGLE on keydown edge — pressing left moves one lane and the player STAYS there. Do NOT snap back to center when the key is released.
- Pattern unlock uses elapsed seconds (not score). Randomly pick from all patterns unlocked so far — do not always pick the most recently unlocked pattern.
- No new THREE.* inside the animation loop. Pre-allocate all Vector3/Color objects before the loop.

Execute the following phases IN ORDER. Do not skip ahead. When assigning tasks, copy the COMPLETE specification text verbatim — workers do not have access to this system prompt.

--- PHASE 1: ASSET MANIFEST ---
[ASSIGN AssetDirector]: Design the asset manifest for a blocky endless runner with theme "${THEME}" and hero "${HERO}".

Produce exactly 9 assets in your parts manifest table:
- 1 hero (the player character — will be displayed on the home screen showcase, spinning on a pedestal)
- 1 obstacle-ground (blocks at ground level, player jumps over)
- 1 obstacle-aerial (floats at head height, player stays low to avoid)
- 1 collectible (small, bright, rewarding to grab)
- 1 platform-tile (repeating ground block)
- 1 background-prop (decorative, non-interactive, far field)
- 1 deco-a (foreground decorative, at lane edge X ±3–4, never interactive)
- 1 deco-b (midfield decorative, animated — slow rotate or bob, never interactive)
- 1 deco-c (atmospheric/distant element, large scale, never interactive)

For each asset include: slug (snake_case), role, visual brief, key colors (hex), blocky notes.
Also define the world palette (5–6 colors) and a 2–3 sentence world visualization.

--- PHASE 2: CHARACTER DESIGN ---
[ASSIGN CharDesigner]: Design blocky character parts for ALL 9 assets listed below in ONE response.

For EACH asset, produce:
1. A 2–3 sentence visualization narration for this specific part
2. The complete parts table: Part | Geometry | W×H×D | Position x,y,z | Color hex | Notes

Assets to design (copy rows verbatim from the AssetDirector manifest):
- hero
- obstacle-ground
- obstacle-aerial
- collectible
- platform-tile
- background-prop
- deco-a
- deco-b
- deco-c

Use read_artifact('asset-manifest') to retrieve the Phase 1 output and include all 9 asset rows in this directive.

--- PHASE 3: GEOMETRY CODE ---
[ASSIGN GeomBuilder]: You will receive 9 parts tables (one per game asset). For each table, generate a complete buildXxx() function that returns a THREE.Group. All 9 functions must go in a single code block.

Rules:
- Default material: THREE.MeshToonMaterial with flatShading: true
- Share material instances by hex color (one const mat_RRGGBB per unique color, declared at top of each function)
- Reuse geometry instances for bilateral/identical parts
- Add a one-line comment above each mesh with the part name
- Function names: buildHero(), buildObstacleGround(), buildObstacleAerial(), buildCollectible(), buildPlatformTile(), buildBackgroundProp(), buildDecoA(), buildDecoB(), buildDecoC()
- No import/export syntax — these functions will be pasted directly into main.js

Use read_artifact('char-design') to retrieve the Phase 2 output and include all 9 parts tables in this directive.

--- PHASE 4: TEXTURE DESIGN ---
[ASSIGN TextureDir]: Design canvas2D procedural textures for the "${THEME}" theme. The platform tile and ground surface both need tileable textures. The hero surface may benefit from a subtle pattern.

For each surface provide:
1. A canvas2D JavaScript function (64×64, returns THREE.CanvasTexture, uses THREE.RepeatWrapping)
2. A prompt for the same texture (if higher quality is desired, can be embedded as base64)
3. The Three.js material line that applies it

Required surfaces:
- Platform tile texture (most important — seen constantly)
- Ground/environment texture (for the static ground plane)
- Optional: hero body detail texture (subtle, should not obscure the blocky shape)

Use the world palette from Phase 1. Textures must feel stylized/toon — no photorealism.

--- PHASE 5: TEXTURE GENERATION ---
For each texture prompt from TextureDir, issue a SEPARATE [ASSIGN TextureGen] with exactly ONE prompt per assignment. The image agent generates ONE image per call — it CANNOT batch.

Example sequence:
  [ASSIGN TextureGen]: Generate this texture — PROMPT: <paste TextureDir's first gpt-image prompt verbatim>
  (wait for response, [ACCEPT])
  [ASSIGN TextureGen]: Generate this texture — PROMPT: <paste TextureDir's second gpt-image prompt verbatim>
  (wait for response, [ACCEPT])
  ... repeat for each texture ...

Each image should be 128×128 or 256×256 pixels. The image agent writes the base64 data URL directly into the coding workspace as textures_data.js — it does NOT put the raw base64 in the conversation. The agent response will say "Base64 pre-written to textures_data.js in the coding workspace (key: 'xxx')".

Your only job: note the key name(s) from each response and include them in the phase artifacts.

Do NOT [REJECT] the image agent. Do NOT ask for base64 in the conversation. Coding agents will call read_file('textures_data.js') to access the data themselves.

--- PHASE 6: GAME MECHANICS ---
[ASSIGN GameArchitect]: Design the mechanics spec for a 2.5D three-lane endless runner with theme "${THEME}". The spec must be implementation-ready. Include the SHOWCASE HOME SCREEN specification.

Produce ALL of the following with exact values:

PHYSICS: gravity constant, jumpForce, maxFallSpeed, laneWidth, laneSnapSpeed, playerGroundY
SCROLL: initial speed (units/s), max speed, ramp rate (units/s per second)
SPAWN: aheadDistance, despawnBehind, initialInterval (s), minInterval (s), intervalDecay
PATTERNS: describe the 4 obstacle patterns (A/B/C/D) with unlock times
COLLISION: AABB box sizes for player hitbox, obstacle hitbox, collectible trigger
SCORING: distance score rate, collectible bonus, localStorage high score key
CAMERA: position (x,y,z) and lookAt target — fixed, no follow logic needed
AUDIO: three oscillator calls for jump, collectible, game-over (freq, duration, type)
STATE MACHINE: showcase → playing → game_over, with fade transitions between each
HUD: DOM element list including the showcase start button and game title text

SHOWCASE HOME SCREEN — specify all of the following:
- Showcase camera position (x,y,z) and lookAt target — close, cinematic, three-quarter angle
- Two showcase lights: key light (color hex, intensity, position) + rim light (cool color, position)
- Hero rotation speed (rad/s on Y axis) and idle bob amplitude
- Pedestal dimensions (flat box under hero)
- Fade transition timing (ms for fade-out, same for fade-in)
- Title text to display (theme-specific, e.g. "SPACE RUN", "JUNGLE DASH")
- What happens on game-over: after 1.5s delay, fade back to showcase

--- PHASE 7: SCENE ATMOSPHERE ---
[ASSIGN SceneComposer]: Design the lighting and atmosphere for a "${THEME}" endless runner. The scene must complement the asset palette from Phase 1. Provide exact values for all of the following:

LIGHTS:
- DirectionalLight: color (hex), intensity, position (x, y, z)
- AmbientLight: color (hex), intensity
- Optional: 1 PointLight for thematic accent (position, color, distance, decay)

BACKGROUND + FOG:
- scene.background hex (must EXACTLY match fog color to prevent horizon seam)
- Fog type (THREE.Fog or THREE.FogExp2) and parameters

GROUND PLANE:
- PlaneGeometry dimensions (width × depth), material color (hex), flatShading: true, receiveShadow
- NOTE: ground plane is static (does not scroll); only worldGroup scrolls

ONE ATMOSPHERIC DETAIL:
A theme-specific visual touch implemented in Three.js (e.g., slow-rotating skybox element, particle drift, background parallax layer). Specify exactly how to implement it.

--- PHASE 8: INITIAL BUILD ---
[ASSIGN DevAlpha]: You are the lead Three.js developer. Build the COMPLETE playable game using the phase artifacts.

Deliver a single main.js file with all of the following:
1. All 9 buildXxx() geometry functions from Phase 3 (verbatim, no changes)
2. Canvas2D texture functions from TextureDir, applied via MeshToonMaterial({ map: makeXxxTexture(), flatShading: true })
3. Complete game loop: renderer setup, scene, camera, fog, lighting, input, physics, spawner, collision, scoring, HUD
4. All 4 obstacle patterns (A/B/C/D) with correct unlock timing
5. Platform tile recycling with frontZ = CAMERA.position.z + 2 (NOT heroZ + TILE.depth)
6. Showcase home screen: hero on pedestal, slow Y rotation, fade transition to gameplay
7. startGame() that resets tile positions AND bgGroup.position.z = 0

HARD CONSTRAINTS (any violation makes the game unplayable):
- index.html MUST use: <script src="https://unpkg.com/three@0.160.0/build/three.min.js"></script> then <script src="./main.js" defer></script>. NO <script type="module">. NO importmap.
- main.js MUST use window.THREE — no import/export syntax anywhere. NO separate .js files.
- NO TextureLoader with local paths — canvas2D textures only. NO AudioLoader — Web Audio API oscillators only.
- HERO Z = 0 always. Only obstacles and tiles move in +Z.
- Showcase hero: position.y = PHYSICS.playerGroundY (= 0). Aerial obstacles: Y = 1.8 always.

Use read_artifact to retrieve the key phase outputs. Include the geometry code (Phase 3), texture specs (Phase 4), mechanics (Phase 6), and atmosphere (Phase 7) specifications in this directive. Do NOT paste all phases verbatim — include only the implementation-critical specs.

--- PHASE 9: CODING SESSION (refinement) ---
After DevAlpha delivers main.js, use the create_coding_session tool to launch a refinement session.

Use read_artifact to compose a focused topic brief. Include the geometry code (Phase 3), texture specs (Phase 4), mechanics (Phase 6), and atmosphere (Phase 7) in the topic. Omit design-phase narrative — coding agents need only implementation specs.
  policy: round_robin
  max_rounds: 6
  agents:
    - name: DevAlpha,  provider: openai,    model: gpt-5.4-2026-03-05,      system: @development/threejs-developer
    - name: DevBeta,   provider: openai,    model: gpt-5.4-2026-03-05, system: @development/geometry-builder

TARGET PROJECT STRUCTURE (file://-safe runtime):
  index.html   — loads three.min.js from CDN as classic script, then <script src="./main.js" defer>
  main.js      — single bundled runtime: renderer, game loop, state machine, all buildXxx() functions, input, HUD wiring; no import/export
  style.css    — HUD positioning only (score, game-over overlay); canvas is fixed at z-index 0

PERFORMANCE RULES for coding agents (relay verbatim):
- Pre-allocate ALL Vector3/Color/Matrix objects used in the animation loop — no 'new THREE.*' inside setAnimationLoop
- One material instance per distinct hex color — share references, never clone
- Collision: use pre-computed center+halfSize AABB — NEVER Box3.setFromObject inside the loop
- antialias: false — always; no exceptions
- renderer.toneMapping = THREE.NoToneMapping
- flatShading: true on all MeshToonMaterial instances
- scene.fog color MUST exactly match scene.background hex
- All texture creation must use THREE.CanvasTexture — never TextureLoader with local paths
- All audio must use AudioContext + OscillatorNode — never AudioLoader. NEVER create a separate audio.js file.
- HERO Z = 0 ALWAYS. Only obstacles and tiles move in +Z. If hero.position.z is ever modified, the code is wrong.
- SHOWCASE HOME SCREEN: game opens in 'showcase' state with hero rotating on a pedestal. Implement buildShowcase() that adds hero + pedestal + showcase lights. On SPACE/button click: fadeOut() → clear showcase → startGame(). On game-over: after 1.5s delay, fadeOut() → rebuild showcase.
- DECORATIVES (deco-a/b/c): spawn these alongside obstacles but NEVER add them to the obstacles array. They scroll with the world in +Z but have no hitbox. deco-b rotates slowly (Y axis). deco-c is placed far back (Z -25 to -35) and stays fixed or scrolls very slowly.
- TEXTURES: canvas2D functions from TextureDir are the primary source. If the phase artifacts list texture keys for textures_data.js, call read_file('textures_data.js') at the start of your turn, then use: const tex = new THREE.TextureLoader().load(TEXTURES['key']) — data: URLs are CORS-safe on file://. Fall back to canvas2D if the file is absent.

SESSION DISCIPLINE for coding agents (relay verbatim):
- DevAlpha's main.js from Phase 8 is already in the workspace. READ it before writing anything.
- Build ON TOP of it. Do not rewrite from scratch.
- DevAlpha rounds: review what exists, add polish (animations, particles, combo system, squash-stretch).
- DevBeta rounds: geometry integration, material sharing, texture application, performance cleanup.
- After round 3, DevAlpha emits [CODING_COMPLETE] if the game is playable. Showrunner may launch another session for polish.
- Showcase hero spawn: ALWAYS set hero.position.y = PHYSICS.playerGroundY (= 0), never 1.8. The hero stands on the pedestal.
- Aerial obstacles: ALWAYS spawn at Y=1.8. Standing player (head at ~1.5) clears them. Never use Y=1.5.
- startGame() MUST reset tiles: for each tile, set tile.position.z back to its initial value. Also reset bgGroup.position.z = 0 if a parallax group exists.

After the coding session returns, check: does index.html use importmap or <script type="module" src="..."> or local import statements? If yes, launch another session to consolidate into root main.js using window.THREE. If the project looks complete and file://-safe, emit [TASK_COMPLETE].
MISSION

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------
ofp-playground start \
  --policy showrunner_driven \
  --no-human \
  --topic "Procedural blocky endless runner — theme: ${THEME}, hero: ${HERO}" \
  --agent "-provider anthropic -type orchestrator -name Showrunner -system ${SHOWRUNNER}" \
  --agent "-provider openai -name AssetDirector -system @creative/theme-asset-director -model gpt-5.4-2026-03-05" \
  --agent "-provider openai -name CharDesigner -system @creative/blocky-character-designer -model gpt-5.4-2026-03-05" \
  --agent "-provider openai -name GeomBuilder -system @development/geometry-builder -model gpt-5.4-2026-03-05" \
  --agent "-provider openai -name TextureDir -system @creative/texture-director -model gpt-5.4-2026-03-05" \
  --agent "-provider openai -type text-to-image -name TextureGen" \
  --agent "-provider openai -name GameArchitect -system @development/platformer-architect -model gpt-5.4-2026-03-05" \
  --agent "-provider openai -name SceneComposer -system @creative/3d-scene-composer -model gpt-5.4-2026-03-05" \
  --agent "anthropic:code-generation:DevAlpha:@development/threejs-developer:claude-sonnet-4-6" \
  --agent "openai:code-generation:DevBeta:@development/geometry-builder:gpt-5.4-2026-03-05"
