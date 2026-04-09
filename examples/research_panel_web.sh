#!/usr/bin/env bash
set -euo pipefail

# OFP Playground — Multi-Model Image Concept Studio | Policy: showrunner_driven
# Usage: bash examples/research_panel_web.sh "your concept brief"
# Keys: GOOGLE_API_KEY, HF_API_KEY

CONCEPT_BRIEF="${1:-multiple manga inspired fashion outfit costume. for a fashion show, runwzy sketches of models wearing outfits that blend traditional japanese clothing with futuristic cyberpunk elements. the setting is a neon-lit urban runway at night, with rain-slicked streets reflecting vibrant lights. the mood is edgy and avant-garde, showcasing bold silhouettes, intricate patterns, and a mix of textures like flowing silk and sharp metallics. the color palette}"



assign_var() {
  local var_name="$1"
  local value
  IFS= read -r -d '' value || true
  printf -v "$var_name" '%s' "$value"
}

# ─────────────────────────────────────────────
# ORCHESTRATION
# ─────────────────────────────────────────────

assign_var DIRECTOR_MISSION <<'DIRECTOR_MISSION_EOF'
You are Rudy, the orchestrator of a multi-model visual concept studio. You receive a concept brief and run 10 themed image bursts — one theme at a time — across all seven image agents. Think of each burst as a focused session: you call the theme, every agent generates their version of it, then you move to the next theme.

Image agents in your studio:
  Google (Gemini Image):
    Aurora — gemini-3.1-flash-image-preview
    Vertex — gemini-3-pro-image-preview
    Nova   — gemini-2.5-flash-image
  HuggingFace (may fail — skip gracefully):
    QwenImg — Qwen/Qwen-Image
    ZVis    — Tongyi-MAI/Z-Image
    Hunyuan — tencent/HunyuanImage-3.0
    Flux2   — black-forest-labs/FLUX.2-dev

WORKFLOW — 10 THEMED BURSTS:

For each burst N of 10, do the following in order:

1. Choose a unique thematic angle derived from the concept brief. Each burst must be distinct:
   vary artistic style (photorealistic, painterly, manga sketch, watercolor, noir, cinematic),
   subject framing (wide runway establishing shot, tight fabric detail, model portrait, full silhouette),
   lighting mood (neon-lit, backlit, dramatic shadow, diffused rain-glow), or cultural influence.
   Give the burst a short label, e.g. "Neon Silk Close-up" or "Rain-Slicked Runway Wide".

2. Compose a rich image prompt for this theme — vivid, cinematic, specific. Include subject,
   composition, lighting, color palette, and atmosphere.

3. Fire all seven image agents simultaneously with a single parallel directive:

   [ASSIGN_PARALLEL Aurora, Vertex, Nova, QwenImg, ZVis, Hunyuan, Flux2]: <your composed prompt>

   All seven generate in true parallel. You will receive auto-accept notifications as each
   image arrives. The floor returns to you automatically once all agents have responded
   (HF agents that are unavailable will time out and be skipped). Do not issue any further
   directives until the floor is returned.

After the floor returns, announce: "Burst N complete — [label]."
Then move immediately to the next burst.

After all 10 bursts, issue [TASK_COMPLETE].

Rules:
- Use [ASSIGN_PARALLEL] for all image bursts — never assign image agents one-by-one.
- Never repeat a theme label across bursts.
- Never generate image content yourself — only direct.
DIRECTOR_MISSION_EOF

# ─────────────────────────────────────────────
# IMAGE AGENT PROMPTS
# ─────────────────────────────────────────────

assign_var AURORA_PROMPT <<'AURORA_PROMPT_EOF'
You are Aurora, powered by Gemini 3.1 Flash Image. Bring atmospheric luminosity and painterly warmth — rich ambient light, soft gradients, natural depth. After generating, output one sentence: "Aurora rendered: [brief description]."
AURORA_PROMPT_EOF

assign_var VERTEX_PROMPT <<'VERTEX_PROMPT_EOF'
You are Vertex, powered by Gemini 3 Pro Image. Produce professional-grade cinematic imagery with high dynamic range, precise geometry, and sophisticated color grading. After generating, output one sentence: "Vertex rendered: [brief description]."
VERTEX_PROMPT_EOF

assign_var NOVA_PROMPT <<'NOVA_PROMPT_EOF'
You are Nova, powered by Gemini 2.5 Flash Image. Combine speed with vivid color saturation and expressive energy — vibrant, immediate, visually striking. After generating, output one sentence: "Nova rendered: [brief description]."
NOVA_PROMPT_EOF

assign_var QWENIMG_PROMPT <<'QWENIMG_PROMPT_EOF'
You are QwenImg, powered by Qwen/Qwen-Image on HuggingFace. Bring detailed, fine-line rendering with a calm compositional philosophy. If your model is unavailable, respond only with the single word: FAILED. Otherwise, after generating, output one sentence: "QwenImg rendered: [brief description]."
QWENIMG_PROMPT_EOF

assign_var ZVIS_PROMPT <<'ZVIS_PROMPT_EOF'
You are ZVis, powered by Tongyi-MAI/Z-Image on HuggingFace. Produce stylized, imaginative imagery with bold interpretations and creative visual metaphors. If your model is unavailable, respond only with the single word: FAILED. Otherwise, after generating, output one sentence: "ZVis rendered: [brief description]."
ZVIS_PROMPT_EOF

assign_var HUNYUAN_PROMPT <<'HUNYUAN_PROMPT_EOF'
You are Hunyuan, powered by tencent/HunyuanImage-3.0 on HuggingFace. Excel at photorealistic scenes with natural textures, environmental depth, and harmonious visual balance. If your model is unavailable, respond only with the single word: FAILED. Otherwise, after generating, output one sentence: "Hunyuan rendered: [brief description]."
HUNYUAN_PROMPT_EOF

assign_var FLUX2_PROMPT <<'FLUX2_PROMPT_EOF'
You are Flux2, powered by black-forest-labs/FLUX.2-dev on HuggingFace. Generate images with extraordinary sharpness, cinematic detail, and professional-grade photorealism. If your model is unavailable, respond only with the single word: FAILED. Otherwise, after generating, output one sentence: "Flux2 rendered: [brief description]."
FLUX2_PROMPT_EOF

# ─────────────────────────────────────────────
# WEB BUILDER
# ─────────────────────────────────────────────

assign_var WEBBUILDER_PROMPT <<'WEBBUILDER_PROMPT_EOF'

save your file as index.html!!!
your images will in ./images/
You are WebBuilder, the frontend coding agent for the multi-model image studio. You build and maintain a rich showcase page at ofp-code/showcase.html. Images are in ofp-images/ one level up — reference them as ../ofp-images/filename.

INITIAL BUILD: Create a fully self-contained HTML file with:

Data model (top of script block):
  const DATA = [];
  // Each entry: { src, displayModel, provider, round, topic, prompt }

Layout:
  - Body: background #0d0d0d, text #e0e0e0, font system-sans-serif
  - Fixed left sidebar 240px + scrollable right image grid
  - Grid: auto-fill columns min 220px with gap

Filter Sidebar:
  Title: "Filters" with a Reset button
  Section "Provider" — three checkboxes, all checked by default:
    OpenAI (#10a37f), Google (#4285f4), HuggingFace (#ff6b35)
  Section "Model" — one checkbox per model, all checked, grouped by provider:
    OpenAI: GPT Image 1.5, GPT Image 1, GPT Image 1 Mini
    Google: Gemini 3.1 Flash, Gemini 3 Pro, Gemini 2.5 Flash
    HuggingFace: Qwen Image, Z-Image, HunyuanImage 3.0, FLUX.2 Dev
  Section "Round" — ten toggle buttons labeled 1–10, all active by default
  Status line: "Showing N of M images"

Image Cards:
  - Card background #1a1a1a, border-radius 8px, overflow hidden
  - Thumbnail fills card top (aspect-ratio 1/1, object-fit cover, lazy loading)
  - Colored provider badge top-left (pill, color by provider)
  - Model name badge top-right (dark pill)
  - Card footer: round badge left ("Round N"), topic text right (truncated, title tooltip)
  - Hover: scale(1.02) transition, box-shadow

Lightbox:
  - Click any image → full-screen overlay (#000 90% opacity)
  - Shows: full image, model name, provider, round number, topic, prompt text
  - Close on overlay click or Escape key

Filter Logic:
  function render() filters DATA by active providers + models + rounds, rerenders grid, updates status count.
  Provider checkbox toggles all its model checkboxes.
  Round buttons toggle individual rounds.
  Reset restores all to active.

No external dependencies — pure vanilla HTML/CSS/JS.

UPDATES: When given new entries (src, displayModel, provider, round, topic, prompt), append them to DATA and output the COMPLETE updated HTML. End with: "Showcase updated: N images loaded."

FINAL POLISH: Add a sticky header bar showing the concept brief. Verify all filters work. Confirm entry count matches. End with: "Final showcase: N images, all filters operational."
 <!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>OFP Model Showcase</title>
  <style>
    :root {
      --bg: #0d0d0d;
      --panel: #141414;
      --card: #1a1a1a;
      --text: #e0e0e0;
      --muted: #a8a8a8;
      --border: #2a2a2a;
      --openai: #10a37f;
      --google: #4285f4;
      --huggingface: #ff6b35;
    }

    * { box-sizing: border-box; }

    html, body {
      margin: 0;
      height: 100%;
      background: var(--bg);
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    }

    .app {
      min-height: 100vh;
    }

    .sidebar {
      position: fixed;
      left: 0;
      top: 0;
      bottom: 0;
      width: 240px;
      overflow-y: auto;
      background: var(--panel);
      border-right: 1px solid var(--border);
      padding: 16px 14px 18px;
    }

    .sidebar-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 14px;
    }

    .sidebar h2 {
      font-size: 18px;
      margin: 0;
    }

    .reset-btn {
      background: #242424;
      color: var(--text);
      border: 1px solid #333;
      border-radius: 6px;
      padding: 6px 10px;
      font-size: 12px;
      cursor: pointer;
    }

    .reset-btn:hover {
      background: #2c2c2c;
    }

    .filter-section {
      border-top: 1px solid var(--border);
      padding-top: 12px;
      margin-top: 12px;
    }

    .filter-section h3 {
      margin: 0 0 10px;
      color: #cfcfcf;
      font-size: 13px;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }

    .check-row {
      display: flex;
      align-items: center;
      gap: 8px;
      margin-bottom: 8px;
      font-size: 13px;
    }

    .provider-dot {
      width: 10px;
      height: 10px;
      border-radius: 50%;
      display: inline-block;
      flex-shrink: 0;
    }

    .model-group {
      margin-bottom: 8px;
      padding-left: 2px;
    }

    .model-group-title {
      font-size: 12px;
      margin: 8px 0 6px;
      color: var(--muted);
      font-weight: 700;
    }

    .model-check {
      margin-left: 8px;
      margin-bottom: 6px;
      font-size: 12px;
      color: #d6d6d6;
    }

    .round-grid {
      display: grid;
      grid-template-columns: repeat(5, 1fr);
      gap: 6px;
    }

    .round-btn {
      border: 1px solid #383838;
      border-radius: 6px;
      background: #1f1f1f;
      color: #d4d4d4;
      padding: 6px 0;
      font-size: 12px;
      cursor: pointer;
    }

    .round-btn.active {
      background: #303030;
      border-color: #5a5a5a;
      color: #fff;
    }

    .status-line {
      margin-top: 12px;
      font-size: 12px;
      color: var(--muted);
      border-top: 1px solid var(--border);
      padding-top: 12px;
    }

    .main {
      margin-left: 240px;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
    }

    .topbar {
      position: sticky;
      top: 0;
      z-index: 10;
      background: rgba(13, 13, 13, 0.95);
      backdrop-filter: blur(4px);
      border-bottom: 1px solid var(--border);
      padding: 12px 18px;
    }

    .topbar-title {
      margin: 0;
      font-size: 14px;
      font-weight: 700;
      color: #f0f0f0;
    }

    .topbar-sub {
      margin: 4px 0 0;
      font-size: 12px;
      color: var(--muted);
    }

    .content {
      flex: 1;
      overflow-y: auto;
      padding: 16px;
    }

    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
      gap: 14px;
      align-items: start;
    }

    .card {
      background: var(--card);
      border-radius: 8px;
      overflow: hidden;
      border: 1px solid #262626;
      transition: transform 0.18s ease, box-shadow 0.18s ease;
      cursor: pointer;
      position: relative;
    }

    .card:hover {
      transform: scale(1.02);
      box-shadow: 0 10px 26px rgba(0,0,0,0.45);
    }

    .thumb-wrap {
      position: relative;
      width: 100%;
      aspect-ratio: 1 / 1;
      background: #101010;
    }

    .thumb {
      width: 100%;
      height: 100%;
      object-fit: cover;
      display: block;
    }

    .provider-badge {
      position: absolute;
      top: 8px;
      left: 8px;
      padding: 4px 8px;
      border-radius: 999px;
      font-size: 11px;
      color: #fff;
      font-weight: 700;
      box-shadow: 0 2px 10px rgba(0,0,0,0.28);
    }

    .model-badge {
      position: absolute;
      top: 8px;
      right: 8px;
      max-width: 65%;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      padding: 4px 8px;
      border-radius: 999px;
      font-size: 11px;
      color: #f2f2f2;
      background: rgba(15, 15, 15, 0.85);
      border: 1px solid rgba(80, 80, 80, 0.6);
    }

    .card-footer {
      display: flex;
      align-items: center;
      gap: 8px;
      justify-content: space-between;
      padding: 10px;
    }

    .round-pill {
      padding: 3px 8px;
      border-radius: 999px;
      font-size: 11px;
      border: 1px solid #404040;
      color: #dcdcdc;
      background: #202020;
      flex-shrink: 0;
    }

    .topic {
      font-size: 12px;
      color: #c8c8c8;
      min-width: 0;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      text-align: right;
    }

    .placeholder {
      border: 1px dashed #444;
      border-radius: 8px;
      padding: 24px 16px;
      text-align: center;
      color: var(--muted);
      background: #141414;
      grid-column: 1 / -1;
      font-size: 14px;
    }

    .lightbox {
      position: fixed;
      inset: 0;
      background: rgba(0, 0, 0, 0.9);
      display: none;
      z-index: 100;
      align-items: center;
      justify-content: center;
      padding: 20px;
    }

    .lightbox.open {
      display: flex;
    }

    .lightbox-panel {
      width: min(1100px, 100%);
      max-height: 95vh;
      overflow: auto;
      background: #111;
      border-radius: 10px;
      border: 1px solid #2a2a2a;
      padding: 14px;
    }

    .lightbox-close {
      border: 1px solid #444;
      background: #1e1e1e;
      color: #e0e0e0;
      border-radius: 6px;
      padding: 6px 10px;
      float: right;
      cursor: pointer;
      font-size: 12px;
    }

    .lightbox-image {
      width: 100%;
      max-height: 70vh;
      object-fit: contain;
      background: #000;
      border-radius: 8px;
      margin-top: 8px;
    }

    .lightbox-meta {
      margin-top: 12px;
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(170px, 1fr));
      gap: 8px;
      font-size: 13px;
      color: #d6d6d6;
    }

    .meta-item {
      background: #191919;
      border: 1px solid #2d2d2d;
      border-radius: 6px;
      padding: 8px;
    }

    .meta-label {
      color: #a7a7a7;
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: 0.04em;
      margin-bottom: 4px;
    }

    .prompt-box {
      margin-top: 10px;
      border: 1px solid #2f2f2f;
      border-radius: 8px;
      background: #161616;
      padding: 10px;
      font-size: 13px;
      color: #d4d4d4;
      white-space: pre-wrap;
      line-height: 1.45;
    }
  </style>
</head>
<body>
  <div class="app">
    <aside class="sidebar">
      <div class="sidebar-header">
        <h2>Filters</h2>
        <button id="resetBtn" class="reset-btn" type="button">Reset</button>
      </div>

      <section class="filter-section">
        <h3>Provider</h3>
        <div id="providerFilters"></div>
      </section>

      <section class="filter-section">
        <h3>Model</h3>
        <div id="modelFilters"></div>
      </section>

      <section class="filter-section">
        <h3>Round</h3>
        <div id="roundFilters" class="round-grid"></div>
      </section>

      <div id="statusLine" class="status-line">Showing 0 of 0 images</div>
    </aside>

    <main class="main">
      <header class="topbar">
        <p class="topbar-title">Concept Brief</p>
        <p class="topbar-sub">a kind ninja pooh encounters a giant clumpy crystal maiden.</p>
      </header>

      <section class="content">
        <div id="galleryGrid" class="grid"></div>
      </section>
    </main>
  </div>

  <div id="lightbox" class="lightbox" aria-hidden="true">
    <div class="lightbox-panel" role="dialog" aria-modal="true">
      <button id="lightboxClose" class="lightbox-close" type="button">Close</button>
      <img id="lightboxImage" class="lightbox-image" alt="" />
      <div class="lightbox-meta">
        <div class="meta-item"><div class="meta-label">Model</div><div id="lbModel"></div></div>
        <div class="meta-item"><div class="meta-label">Provider</div><div id="lbProvider"></div></div>
        <div class="meta-item"><div class="meta-label">Round</div><div id="lbRound"></div></div>
        <div class="meta-item"><div class="meta-label">Topic</div><div id="lbTopic"></div></div>
      </div>
      <div class="prompt-box">
        <div class="meta-label">Prompt</div>
        <div id="lbPrompt"></div>
      </div>
    </div>
  </div>

  <script>
    const DATA = [];
    // Each entry: { src, displayModel, provider, round, topic, prompt }

    const PROVIDERS = [
      { name: "OpenAI", color: "#10a37f" },
      { name: "Google", color: "#4285f4" },
      { name: "HuggingFace", color: "#ff6b35" }
    ];

    const MODELS_BY_PROVIDER = {
      OpenAI: ["GPT Image 1.5", "GPT Image 1", "GPT Image 1 Mini"],
      Google: ["Gemini 3.1 Flash", "Gemini 3 Pro", "Gemini 2.5 Flash"],
      HuggingFace: ["Qwen Image", "Z-Image", "HunyuanImage 3.0", "FLUX.2 Dev"]
    };

    const providerFiltersEl = document.getElementById("providerFilters");
    const modelFiltersEl = document.getElementById("modelFilters");
    const roundFiltersEl = document.getElementById("roundFilters");
    const galleryGridEl = document.getElementById("galleryGrid");
    const statusLineEl = document.getElementById("statusLine");
    const resetBtn = document.getElementById("resetBtn");

    const lightbox = document.getElementById("lightbox");
    const lightboxClose = document.getElementById("lightboxClose");
    const lbImage = document.getElementById("lightboxImage");
    const lbModel = document.getElementById("lbModel");
    const lbProvider = document.getElementById("lbProvider");
    const lbRound = document.getElementById("lbRound");
    const lbTopic = document.getElementById("lbTopic");
    const lbPrompt = document.getElementById("lbPrompt");

    const state = {
      providers: new Set(PROVIDERS.map(p => p.name)),
      models: new Set(Object.values(MODELS_BY_PROVIDER).flat()),
      rounds: new Set(Array.from({ length: 10 }, (_, i) => i + 1))
    };

    function providerColor(provider) {
      const found = PROVIDERS.find(p => p.name === provider);
      return found ? found.color : "#666";
    }

    function createCheckbox(id, labelText, checked = true, className = "") {
      const row = document.createElement("label");
      row.className = "check-row " + className;

      const input = document.createElement("input");
      input.type = "checkbox";
      input.id = id;
      input.checked = checked;

      const text = document.createElement("span");
      text.textContent = labelText;

      row.appendChild(input);
      row.appendChild(text);
      return { row, input };
    }

    function initFilters() {
      providerFiltersEl.innerHTML = "";
      modelFiltersEl.innerHTML = "";
      roundFiltersEl.innerHTML = "";

      PROVIDERS.forEach(provider => {
        const { row, input } = createCheckbox(
          "provider-" + provider.name,
          provider.name,
          true
        );

        const dot = document.createElement("span");
        dot.className = "provider-dot";
        dot.style.background = provider.color;
        row.insertBefore(dot, row.children[1]);

        input.addEventListener("change", () => {
          const models = MODELS_BY_PROVIDER[provider.name];
          if (input.checked) {
            state.providers.add(provider.name);
            models.forEach(m => state.models.add(m));
          } else {
            state.providers.delete(provider.name);
            models.forEach(m => state.models.delete(m));
          }

          models.forEach(model => {
            const modelInput = document.getElementById("model-" + cssSafe(model));
            if (modelInput) modelInput.checked = input.checked;
          });

          render();
          syncProviderIndeterminate(provider.name);
        });

        providerFiltersEl.appendChild(row);
      });

      Object.entries(MODELS_BY_PROVIDER).forEach(([provider, models]) => {
        const group = document.createElement("div");
        group.className = "model-group";

        const title = document.createElement("div");
        title.className = "model-group-title";
        title.textContent = provider;
        group.appendChild(title);

        models.forEach(model => {
          const safeId = "model-" + cssSafe(model);
          const { row, input } = createCheckbox(safeId, model, true, "model-check");
          input.addEventListener("change", () => {
            if (input.checked) state.models.add(model);
            else state.models.delete(model);
            syncProviderFromModels(provider);
            render();
          });
          group.appendChild(row);
        });

        modelFiltersEl.appendChild(group);
      });

      for (let i = 1; i <= 10; i++) {
        const btn = document.createElement("button");
        btn.type = "button";
        btn.className = "round-btn active";
        btn.textContent = String(i);
        btn.dataset.round = String(i);
        btn.addEventListener("click", () => {
          if (state.rounds.has(i)) {
            state.rounds.delete(i);
            btn.classList.remove("active");
          } else {
            state.rounds.add(i);
            btn.classList.add("active");
          }
          render();
        });
        roundFiltersEl.appendChild(btn);
      }

      resetBtn.addEventListener("click", resetFilters);
    }

    function cssSafe(text) {
      return text.replace(/[^a-zA-Z0-9_-]/g, "-");
    }

    function syncProviderFromModels(provider) {
      const models = MODELS_BY_PROVIDER[provider];
      const checkedCount = models.reduce((n, m) => {
        const input = document.getElementById("model-" + cssSafe(m));
        return n + (input && input.checked ? 1 : 0);
      }, 0);

      const providerInput = document.getElementById("provider-" + provider);
      if (!providerInput) return;

      if (checkedCount === models.length) {
        providerInput.checked = true;
        providerInput.indeterminate = false;
        state.providers.add(provider);
      } else if (checkedCount === 0) {
        providerInput.checked = false;
        providerInput.indeterminate = false;
        state.providers.delete(provider);
      } else {
        providerInput.checked = true;
        providerInput.indeterminate = true;
        state.providers.add(provider);
      }
    }

    function syncProviderIndeterminate(provider) {
      const providerInput = document.getElementById("provider-" + provider);
      if (providerInput) providerInput.indeterminate = false;
    }

    function resetFilters() {
      state.providers = new Set(PROVIDERS.map(p => p.name));
      state.models = new Set(Object.values(MODELS_BY_PROVIDER).flat());
      state.rounds = new Set(Array.from({ length: 10 }, (_, i) => i + 1));

      PROVIDERS.forEach(p => {
        const input = document.getElementById("provider-" + p.name);
        if (input) {
          input.checked = true;
          input.indeterminate = false;
        }
      });

      Object.values(MODELS_BY_PROVIDER).flat().forEach(model => {
        const input = document.getElementById("model-" + cssSafe(model));
        if (input) input.checked = true;
      });

      Array.from(roundFiltersEl.children).forEach(btn => btn.classList.add("active"));

      render();
    }

    function filteredData() {
      return DATA.filter(item =>
        state.providers.has(item.provider) &&
        state.models.has(item.displayModel) &&
        state.rounds.has(Number(item.round))
      );
    }

    function cardElement(item) {
      const card = document.createElement("article");
      card.className = "card";

      const wrap = document.createElement("div");
      wrap.className = "thumb-wrap";

      const img = document.createElement("img");
      img.className = "thumb";
      img.loading = "lazy";
      img.src = item.src;
      img.alt = item.topic || item.displayModel || "Generated image";
      wrap.appendChild(img);

      const providerBadge = document.createElement("span");
      providerBadge.className = "provider-badge";
      providerBadge.textContent = item.provider;
      providerBadge.style.background = providerColor(item.provider);
      wrap.appendChild(providerBadge);

      const modelBadge = document.createElement("span");
      modelBadge.className = "model-badge";
      modelBadge.textContent = item.displayModel;
      wrap.appendChild(modelBadge);

      const footer = document.createElement("div");
      footer.className = "card-footer";

      const roundPill = document.createElement("span");
      roundPill.className = "round-pill";
      roundPill.textContent = "Round " + item.round;

      const topic = document.createElement("span");
      topic.className = "topic";
      topic.textContent = item.topic || "";
      topic.title = item.topic || "";

      footer.appendChild(roundPill);
      footer.appendChild(topic);

      card.appendChild(wrap);
      card.appendChild(footer);

      card.addEventListener("click", () => openLightbox(item));
      return card;
    }

    function openLightbox(item) {
      lbImage.src = item.src;
      lbImage.alt = item.topic || item.displayModel || "Image";
      lbModel.textContent = item.displayModel || "";
      lbProvider.textContent = item.provider || "";
      lbRound.textContent = "Round " + (item.round ?? "");
      lbTopic.textContent = item.topic || "";
      lbPrompt.textContent = item.prompt || "";
      lightbox.classList.add("open");
      lightbox.setAttribute("aria-hidden", "false");
    }

    function closeLightbox() {
      lightbox.classList.remove("open");
      lightbox.setAttribute("aria-hidden", "true");
      lbImage.src = "";
    }

    function render() {
      const allCount = DATA.length;
      const shown = filteredData();

      galleryGridEl.innerHTML = "";

      if (allCount === 0) {
        const placeholder = document.createElement("div");
        placeholder.className = "placeholder";
        placeholder.textContent = "No images loaded yet. Add entries to DATA to populate the gallery.";
        galleryGridEl.appendChild(placeholder);
      } else if (shown.length === 0) {
        const placeholder = document.createElement("div");
        placeholder.className = "placeholder";
        placeholder.textContent = "No images match current filters.";
        galleryGridEl.appendChild(placeholder);
      } else {
        shown.forEach(item => galleryGridEl.appendChild(cardElement(item)));
      }

      statusLineEl.textContent = `Showing ${shown.length} of ${allCount} images`;
    }

    lightbox.addEventListener("click", (e) => {
      if (e.target === lightbox) closeLightbox();
    });

    lightboxClose.addEventListener("click", closeLightbox);

    window.addEventListener("keydown", (e) => {
      if (e.key === "Escape") closeLightbox();
    });

    initFilters();
    render();
  </script>
</body>
</html>

WEBBUILDER_PROMPT_EOF

# ─────────────────────────────────────────────
# LAUNCH
# ─────────────────────────────────────────────

ofp-playground start \
  --no-human \
  --policy showrunner_driven \
  --max-turns 60 \
  --topic "${CONCEPT_BRIEF}" \
  --agent "hf:orchestrator:Rudy:${DIRECTOR_MISSION}" \
  --agent "google:text-to-image:Aurora:${AURORA_PROMPT}:gemini-3.1-flash-image-preview" \
  --agent "google:text-to-image:Vertex:${VERTEX_PROMPT}:gemini-3-pro-image-preview" \
  --agent "google:text-to-image:Nova:${NOVA_PROMPT}:gemini-2.5-flash-image" \
  --agent "hf:text-to-image:QwenImg:${QWENIMG_PROMPT}:Qwen/Qwen-Image" \
  --agent "hf:text-to-image:ZVis:${ZVIS_PROMPT}:Tongyi-MAI/Z-Image" \
  --agent "hf:text-to-image:Hunyuan:${HUNYUAN_PROMPT}:tencent/HunyuanImage-3.0" \
  --agent "hf:text-to-image:Flux2:${FLUX2_PROMPT}:fal/FLUX.2-dev-Turbo"
