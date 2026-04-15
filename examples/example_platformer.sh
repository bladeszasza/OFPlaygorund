#!/bin/bash
# example_platformer.sh
# Procedural Blocky Endless Runner — theme-driven, Three.js, file://-safe
#
# Agent roster (9 total):
#
#   Orchestrator:
#   - openai:orchestrator           → Showrunner        (gpt-5.4-2026-03-05)
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
#   Coding session (round-robin, 6 rounds):
#   - openai:code-generation        → DevAlpha           (@development/threejs-developer)
#   - openai:code-generation        → DevBeta          (@development/geometry-builder)
#
# Pipeline phases:
#   1.  AssetDirector  — manifest: 9 assets (hero, 2 obstacles, collectible, tile, bg-prop, deco-a/b/c with rich NPC decor)
#   2.  CharDesigner   — parts tables for all 9 assets, with richer decorative NPC silhouettes
#   3.  GameArchitect  — game mechanics + showcase + HUD/DOM contract
#   4.  GeomBuilder    — all buildXxx() Three.js functions in one block
#   5.  TextureDir     — canvas2D texture recipes prompts for platform, ground, hero surface
#   6.  TextureGen     — generates 2-3 texture images + base64 data URLs for coding agents
#   7.  SceneComposer  — lighting + atmosphere spec for the theme
#   8.  [CODING_SESSION]  — DevAlpha + DevBeta build the complete file://-safe game in the sandbox (6 rounds; DevAlpha emits [CODING_COMPLETE] when playable)
#
# Output:  result/<session>/sandbox/  →  index.html + main.js + style.css
#          Open index.html directly in any browser — no server required
#
# Usage:
#   bash example_platformer.sh
#   bash example_platformer.sh space astronaut      # skip prompts
#
# Requirements:
#   - OPENAI_API_KEY
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

Execute the following phases IN ORDER. Do not skip ahead. For normal [ASSIGN] tasks, copy the COMPLETE specification text verbatim — workers do not have access to this system prompt. For create_coding_session, keep topic short and use artifact_refs/context_files to point at the mirrored markdown files instead of pasting long specs into the tool call.

After EVERY [ASSIGN] or TextureGen call, wait for the worker response and then emit [ACCEPT] before moving to the next phase. Never reference an artifact in read_artifact() or artifact_refs until it appears in the artifact index. Use these canonical artifact slugs when reading or passing refs: asset-director, char-designer, game-architect, geom-builder, texture-dir, scene-composer.

--- PHASE 1: ASSET MANIFEST ---
[ASSIGN AssetDirector]: Design the asset manifest for a blocky endless runner with theme "${THEME}" and hero "${HERO}".

Produce exactly 9 assets in your parts manifest table:
- 1 hero (the player character — will be displayed on the home screen showcase, spinning on a pedestal)
- 1 obstacle-ground (blocks at ground level, player jumps over)
- 1 obstacle-aerial (floats at head height, player stays low to avoid)
- 1 collectible (small, bright, rewarding to grab)
- 1 platform-tile (repeating ground block)
- 1 background-prop (decorative, non-interactive, far field; preferably an NPC or crowd figure)
- 1 deco-a (foreground decorative NPC at lane edge X ±3–4, never interactive)
- 1 deco-b (midfield decorative NPC, animated — slow rotate or bob, never interactive)
- 1 deco-c (atmospheric/distant NPC cluster or large character element, never interactive)

IMPORTANT: the world should feel populated. At least 3 of the 4 non-interactive decorative assets (background-prop, deco-a, deco-b, deco-c) must be character-like NPCs rather than signs or furniture. Give them distinct silhouettes, one memorable accessory or costume detail each, and make them feel like inhabitants of the "${THEME}" world.

For each asset include: slug (snake_case), role, visual brief, key colors (hex), blocky notes.
Also define the world palette (5–6 colors) and a 2–3 sentence world visualization.

--- PHASE 2: CHARACTER DESIGN ---
[ASSIGN CharDesigner]: Design blocky character parts for ALL 9 assets listed below in ONE response.

For EACH asset, produce:
1. A 2–3 sentence visualization narration for this specific part
2. The complete parts table: Part | Geometry | W×H×D | Position x,y,z | Color hex | Notes

NPC QUALITY BAR:
- Treat background-prop, deco-a, deco-b, and deco-c as richer NPC crowd characters whenever the manifest allows it.
- For NPC-style assets, push silhouette clarity: layered clothing, hats, hair masses, bags, tools, banners, lanterns, tails, masks, or other readable accessories.
- Decorative NPCs should feel more detailed than a generic prop: give each one a specific attitude, costume read, and at least one memorable charm detail.

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

Use read_artifact('asset-director') to retrieve the Phase 1 output and include all 9 asset rows in this directive.

--- PHASE 3: GAME MECHANICS ---
[ASSIGN GameArchitect]: Design the mechanics spec for a 2.5D three-lane endless runner with theme "${THEME}". The spec must be implementation-ready. Include the SHOWCASE HOME SCREEN specification.

Produce ALL of the following with exact values:

PHYSICS: gravity constant, jumpForce, maxFallSpeed, laneWidth, laneSnapSpeed, playerGroundY
SCROLL: initial speed (units/s), max speed, ramp rate (units/s per second)
SPAWN: aheadDistance, despawnBehind, initialInterval (s), minInterval (s), intervalDecay
PATTERNS: describe the 4 obstacle patterns (A/B/C/D) with unlock times
NPC_DECOR: sidewalk placement bands, cluster size, idle bob amplitude, idle turn rate, parallax factor
COLLISION: AABB box sizes for player hitbox, obstacle hitbox, collectible trigger
SCORING: distance score rate, collectible bonus, localStorage high score key
CAMERA: position (x,y,z) and lookAt target — fixed, no follow logic needed
AUDIO: three oscillator calls for jump, collectible, game-over (freq, duration, type)
STATE MACHINE: showcase → playing → game_over, with fade transitions between each
HUD: DOM element ids for #app, #score, #hiscore, #startScreen, #gameTitle, #statusText, #startBtn, and optional #fadeLayer

SHOWCASE HOME SCREEN — specify all of the following:
- Showcase camera position (x,y,z) and lookAt target — close, cinematic, three-quarter angle
- Two showcase lights: key light (color hex, intensity, position) + rim light (cool color, position)
- Hero rotation speed (rad/s on Y axis) and idle bob amplitude
- Pedestal dimensions (flat box under hero)
- Fade transition timing (ms for fade-out, same for fade-in)
- Title text to display (theme-specific, e.g. "SPACE RUN", "JUNGLE DASH")
- Button click behavior for #startBtn and SPACE key behavior for showcase/game-over transitions
- What happens on game-over: after 1.5s delay, fade back to showcase

Your response must be a SINGLE javascript code block containing exact constants, state variables, DOM wiring expectations, and complete function patterns. No placeholder comments, ellipses, or TODOs.

--- PHASE 4: GEOMETRY CODE ---
[ASSIGN GeomBuilder]: You will receive 9 parts tables (one per game asset). For each table, generate a complete buildXxx() function that returns a THREE.Group. All 9 functions must go in a single code block.

Rules:
- Default material: THREE.MeshToonMaterial with flatShading: true
- Share material instances by hex color (one const mat_RRGGBB per unique color, declared at top of each function)
- Reuse geometry instances for bilateral/identical parts
- Add a one-line comment above each mesh with the part name
- Function names: buildHero(), buildObstacleGround(), buildObstacleAerial(), buildCollectible(), buildPlatformTile(), buildBackgroundProp(), buildDecoA(), buildDecoB(), buildDecoC()
- No import/export syntax — these functions will be pasted directly into main.js

Use read_artifact('char-designer') to retrieve the Phase 2 output and include all 9 parts tables in this directive.

--- PHASE 5: TEXTURE DESIGN ---
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

--- PHASE 6: TEXTURE GENERATION ---
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

--- PHASE 8: CODING SESSION ---
Use the create_coding_session tool for this phase. Do NOT use [ASSIGN DevAlpha] on the main floor — that path is brittle for workspace file creation and leads to partial or empty runs.

Launch ONE comprehensive build session with:
  topic: short objective only (<= 300 chars). Require a complete playable file://-safe endless runner in the sandbox.
  artifact_refs:
    - asset-director
    - game-architect
    - geom-builder
    - texture-dir
    - scene-composer
  context_files:
    - memory/browser-sandbox-delivery.md
    - textures_data.js   # include only if the file exists in the sandbox
  policy: round_robin
  max_rounds: 6
  agents:
    - name: DevAlpha, provider: openai, model: gpt-5.4-2026-03-05, system: @development/threejs-developer, timeout: 1200
    - name: DevBeta, provider: openai, model: gpt-5.4-2026-03-05, system: @development/geometry-builder, timeout: 1200

TARGET PROJECT STRUCTURE (file://-safe runtime):
  index.html   — loads three.min.js from CDN as classic script, then <script src="./main.js" defer>
  main.js      — single bundled runtime: renderer, game loop, state machine, all buildXxx() functions, input, spawning, collision, HUD wiring; no import/export
  style.css    — HUD and overlay layout only; canvas is fixed at z-index 0

DOM CONTRACT for index.html:
- #app root for the renderer canvas
- #hud overlay with #score and #hiscore
- #startScreen overlay containing #gameTitle, #statusText, and #startBtn
- optional #fadeLayer element for fade transitions
- Wire #startBtn in JavaScript. Do NOT use inline onclick/onmouseover/onmouseout HTML attributes.

SESSION GOAL:
- Build the COMPLETE playable game in this one session — not a skeleton.
- Use GameArchitect as the gameplay contract, GeomBuilder as the geometry contract, TextureDir/textures_data.js for textures, and SceneComposer for lighting/atmosphere.
- If files already exist from an earlier attempt, improve them. If they do not exist, create them.
- main.js is not complete unless it contains a real showcase → playing → game_over loop, updateSpawner(), checkCollisions(), recycleTiles(), startGame(), endGame(), score updates, and working input.

PERFORMANCE RULES for coding agents (relay verbatim):
- Pre-allocate ALL Vector3/Color/Matrix objects used in the animation loop — no 'new THREE.*' inside the loop
- One material instance per distinct hex color — share references, never clone
- Collision: use pre-computed center+halfSize AABB — NEVER Box3.setFromObject inside the loop
- antialias: false — always; no exceptions
- renderer.toneMapping = THREE.NoToneMapping
- flatShading: true on all MeshToonMaterial instances
- scene.fog color MUST exactly match scene.background hex
- All texture creation must use THREE.CanvasTexture or data: URLs from textures_data.js — never local TextureLoader paths
- All audio must use AudioContext + OscillatorNode — never AudioLoader. NEVER create a separate audio.js file.
- HERO Z = 0 ALWAYS. Only obstacles and tiles move in +Z. If hero.position.z is ever modified, the code is wrong.
- SHOWCASE HOME SCREEN: game opens in 'showcase' state with hero rotating on a pedestal. On #startBtn click or SPACE: fadeOut() → startGame(). On game-over: after 1.5s delay, fade back to showcase.
- DECORATIVE NPCS (background-prop + deco-a/b/c): treat these as rich crowd characters. They must be visible in the world, stay off the playable lanes, NEVER go into the obstacles array, and only use idle/parallax motion. deco-b rotates or bobs slowly; deco-c sits far back (Z -25 to -35) and stays fixed or scrolls very slowly.
- START BUTTON: document.getElementById('startBtn').addEventListener('click', ...) must exist and PLAY/RETRY must work.

SESSION DISCIPLINE for coding agents (relay verbatim):
- Read EVERY referenced phase file and required context file before editing code.
- Do not stop at a static scene. The session is incomplete until movement, spawning, collision, score, start/retry flow, and game-over flow all exist.
- DevAlpha rounds: build or repair the gameplay systems, showcase transitions, HUD flow, and polish (animations, particles, combo system, squash-stretch).
- DevBeta rounds: verify geometry integration, material sharing, texture application, lane/spawn logic, DOM contract compliance, and performance cleanup.
- Use background-prop and deco assets as richer NPC crowd dressing on sidewalks / background bands so the world feels inhabited, not empty.
- After round 3, DevAlpha emits [CODING_COMPLETE] only if the game is already playable.
- Showcase hero spawn: ALWAYS set hero.position.y = PHYSICS.playerGroundY (= 0), never 1.8. The hero stands on the pedestal.
- Aerial obstacles: ALWAYS spawn at Y=1.8. Standing player (head at ~1.5) clears them. Never use Y=1.5.
- startGame() MUST reset tiles to their initial Z positions. Also reset bgGroup.position.z = 0 if a parallax group exists.

After the coding session returns, if the session summary does not explicitly confirm a working showcase → play → game_over loop, obstacle spawning, collision, score updates, and a wired PLAY/RETRY button, launch ONE more 2-round repair session focused only on the missing systems. If the project looks complete and file://-safe, emit [TASK_COMPLETE].
MISSION

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------
ofp-playground start \
  --policy showrunner_driven \
  --no-human \
  --topic "Procedural blocky endless runner — theme: ${THEME}, hero: ${HERO}" \
  --agent "-provider openai -type orchestrator -name Showrunner -system ${SHOWRUNNER} -model gpt-5.4-2026-03-05" \
  --agent "-provider openai -name AssetDirector -system @creative/theme-asset-director -model gpt-5.4-2026-03-05" \
  --agent "-provider openai -name CharDesigner -system @creative/blocky-character-designer -model gpt-5.4-2026-03-05" \
  --agent "-provider openai -name GeomBuilder -system @development/geometry-builder -model gpt-5.4-2026-03-05" \
  --agent "-provider openai -name TextureDir -system @creative/texture-director -model gpt-5.4-2026-03-05" \
  --agent "-provider openai -type text-to-image -name TextureGen" \
  --agent "-provider openai -name GameArchitect -system @development/platformer-architect -model gpt-5.4-2026-03-05" \
  --agent "-provider openai -name SceneComposer -system @creative/3d-scene-composer -model gpt-5.4-2026-03-05" \
  --agent "-provider openai -type code-generation -name DevAlpha -system @development/threejs-developer -model gpt-5.4-2026-03-05 -timeout 1200" \
  --agent "-provider openai -type code-generation -name DevBeta -system @development/geometry-builder -model gpt-5.4-2026-03-05 -timeout 1200"
