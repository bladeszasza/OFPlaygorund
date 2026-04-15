"""Render collected trace events as a standalone interactive HTML timeline."""
from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path

from ofp_playground.trace.collector import EventCollector

_EVENT_COLORS = {
    "utterance": "#4A90D9",
    "requestFloor": "#F5A623",
    "yieldFloor": "#7ED321",
    "grantFloor": "#50E3C2",
    "revokeFloor": "#D0021B",
    "publishManifests": "#9013FE",
    "invite": "#4ECDC4",
    "acceptInvite": "#4ECDC4",
    "declineInvite": "#9B9B9B",
    "bye": "#9B9B9B",
}


def render_trace_html(collector: EventCollector, output_path: Path) -> Path:
    """Write a self-contained timeline graph (HTML) for the captured trace."""
    payload = collector.to_dict()
    # Escape </ so </script> inside string values doesn't terminate the <script> block.
    payload_json = json.dumps(payload).replace("</", "<\\/")
    colors_json = json.dumps(_EVENT_COLORS)
    generated_at = datetime.now().isoformat(timespec="seconds")

    template = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>OFP Trace Timeline</title>
  <style>
    :root {
      --bg: #0f1720;
      --panel: #17222d;
      --panel-2: #101923;
      --panel-3: #0d141d;
      --muted: #93a4b8;
      --text: #e6edf5;
      --accent: #58a6ff;
      --accent-soft: rgba(88, 166, 255, 0.18);
      --grid: #2a3a4c;
      --border: #223244;
      --chip: #102030;
      --chip-hover: #183049;
      --shadow: 0 18px 40px rgba(0, 0, 0, 0.22);
    }
    html, body {
      margin: 0;
      min-height: 100%;
      background: radial-gradient(circle at 20% 10%, #1b2a3a 0%, #0f1720 60%);
      color: var(--text);
      font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, sans-serif;
    }
    body {
      overflow: hidden;
    }
    .shell {
      display: grid;
      grid-template-columns: minmax(0, 1fr) 380px;
      height: 100vh;
      overflow: hidden;
    }
    .main {
      padding: 14px;
      overflow-y: auto;
      box-sizing: border-box;
      display: flex;
      flex-direction: column;
      gap: 12px;
    }
    .header,
    .trace-section,
    .nested-block,
    .empty-card {
      background: var(--panel);
      border: 1px solid var(--border);
      border-radius: 12px;
      box-sizing: border-box;
      box-shadow: var(--shadow);
    }
    .header {
      padding: 12px 14px;
    }
    .header h1,
    .nested-header h2,
    .detail-title,
    .section-title {
      margin: 0 0 6px;
      font-size: 18px;
      font-weight: 650;
    }
    .nested-header h2,
    .section-title {
      font-size: 16px;
      margin-bottom: 4px;
    }
    .meta,
    .detail-meta,
    .section-subtitle,
    .session-summary,
    .session-copy,
    .empty-copy {
      color: var(--muted);
      font-size: 12px;
      line-height: 1.5;
    }
    .trace-section {
      padding: 12px;
    }
    .trace-section.main-section {
      background:
        radial-gradient(circle at top right, rgba(88, 166, 255, 0.1), transparent 32%),
        var(--panel);
    }
    .section-top {
      display: flex;
      justify-content: space-between;
      gap: 12px;
      align-items: flex-start;
      flex-wrap: wrap;
      margin-bottom: 10px;
    }
    .section-actions {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
      justify-content: flex-end;
    }
    .summary-strip {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      margin-top: 10px;
    }
    .session-chip {
      border: 1px solid #2b4259;
      background: linear-gradient(180deg, #122235, #102030);
      color: #d7e6f7;
      padding: 8px 10px;
      border-radius: 999px;
      cursor: pointer;
      font-size: 12px;
      line-height: 1.2;
      transition: background 120ms ease, border-color 120ms ease, transform 120ms ease, box-shadow 120ms ease;
      box-shadow: inset 0 1px 0 rgba(255,255,255,0.04);
    }
    .session-chip:hover {
      background: var(--chip-hover);
      border-color: #466789;
      transform: translateY(-1px);
      box-shadow: 0 10px 18px rgba(0,0,0,0.22);
    }
    .section-controls {
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      align-items: flex-start;
      margin-bottom: 10px;
    }
    .filter-group {
      display: flex;
      flex-wrap: wrap;
      gap: 8px 12px;
      align-items: center;
    }
    .legend {
      display: flex;
      flex-wrap: wrap;
      gap: 8px 12px;
    }
    .legend-item {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      font-size: 12px;
      color: var(--muted);
      white-space: nowrap;
    }
    .swatch {
      width: 12px;
      height: 12px;
      border-radius: 3px;
      border: 1px solid #334455;
      display: inline-block;
      flex: none;
    }
    .canvas-wrap {
      overflow: auto;
      border: 1px solid var(--border);
      border-radius: 10px;
      background: linear-gradient(180deg, #111a24, #0d141d);
      min-height: 260px;
    }
    .canvas-wrap.main-canvas {
      min-height: 420px;
    }
    .nested-block {
      padding: 12px;
      display: flex;
      flex-direction: column;
      gap: 10px;
      background:
        linear-gradient(180deg, rgba(88, 166, 255, 0.06), transparent 26%),
        var(--panel);
    }
    .nested-header {
      display: flex;
      justify-content: space-between;
      gap: 12px;
      align-items: flex-start;
      flex-wrap: wrap;
    }
    .session-list {
      display: flex;
      flex-direction: column;
      gap: 10px;
    }
    .session-panel {
      background:
        linear-gradient(180deg, rgba(255,255,255,0.03), transparent 24%),
        var(--panel-2);
      border: 1px solid var(--border);
      border-radius: 12px;
      overflow: hidden;
      transition: transform 140ms ease, border-color 140ms ease, box-shadow 140ms ease, background 140ms ease;
      box-shadow: inset 0 1px 0 rgba(255,255,255,0.03);
    }
    .session-panel:hover {
      transform: translateY(-1px);
      border-color: #33506b;
      box-shadow: 0 16px 30px rgba(0,0,0,0.22);
    }
    .session-panel[open] {
      border-color: #4b6c8d;
      background:
        linear-gradient(180deg, rgba(88, 166, 255, 0.09), transparent 22%),
        var(--panel-2);
    }
    .session-panel summary {
      list-style: none;
      cursor: pointer;
      padding: 14px;
      display: flex;
      justify-content: space-between;
      gap: 12px;
      align-items: stretch;
    }
    .session-panel summary::-webkit-details-marker {
      display: none;
    }
    .session-panel summary:focus-visible {
      outline: 2px solid var(--accent);
      outline-offset: -2px;
    }
    .session-heading {
      display: flex;
      flex-direction: column;
      gap: 6px;
      min-width: 0;
      flex: 1;
    }
    .session-title-row {
      display: flex;
      gap: 8px;
      align-items: center;
      flex-wrap: wrap;
    }
    .session-kind {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      border: 1px solid #35506b;
      border-radius: 999px;
      padding: 4px 8px;
      font-size: 11px;
      font-weight: 700;
      letter-spacing: 0.04em;
      text-transform: uppercase;
      color: #d7e6f7;
      background: #122235;
    }
    .session-panel[data-scope-kind="breakout"] .session-kind {
      background: rgba(79, 209, 197, 0.12);
      border-color: rgba(79, 209, 197, 0.34);
      color: #9ceee4;
    }
    .session-panel[data-scope-kind="coding"] .session-kind {
      background: rgba(250, 204, 21, 0.12);
      border-color: rgba(250, 204, 21, 0.30);
      color: #fde68a;
    }
    .session-title {
      font-weight: 650;
      font-size: 15px;
      color: var(--text);
    }
    .session-id {
      color: #aac2d9;
      font-size: 12px;
      word-break: break-all;
    }
    .session-preview {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
      gap: 8px;
    }
    .session-stat {
      background: rgba(255,255,255,0.025);
      border: 1px solid rgba(255,255,255,0.05);
      border-radius: 10px;
      padding: 8px 10px;
    }
    .session-stat-label {
      color: var(--muted);
      font-size: 10px;
      text-transform: uppercase;
      letter-spacing: 0.08em;
      margin-bottom: 4px;
    }
    .session-stat-value {
      font-size: 12px;
      color: #e6edf5;
      line-height: 1.4;
      word-break: break-word;
    }
    .session-toggle {
      display: flex;
      flex-direction: column;
      align-items: flex-end;
      justify-content: center;
      gap: 8px;
      min-width: 116px;
      flex: none;
    }
    .session-toggle-copy {
      font-size: 11px;
      font-weight: 700;
      letter-spacing: 0.05em;
      text-transform: uppercase;
      color: #c6d8ec;
    }
    .session-chevron {
      width: 36px;
      height: 36px;
      border-radius: 999px;
      border: 1px solid #34506b;
      background: linear-gradient(180deg, #16283b, #0f1d2c);
      display: inline-flex;
      align-items: center;
      justify-content: center;
      color: #d7e6f7;
      font-size: 18px;
      line-height: 1;
      transition: transform 140ms ease, background 140ms ease, border-color 140ms ease;
    }
    .session-panel[open] .session-chevron {
      transform: rotate(180deg);
      background: linear-gradient(180deg, #1a3350, #122235);
      border-color: #4b6c8d;
    }
    .session-badges {
      display: flex;
      gap: 6px;
      flex-wrap: wrap;
      justify-content: flex-end;
      align-self: flex-start;
    }
    .panel-body {
      padding: 0 14px 14px;
      border-top: 1px solid var(--border);
      background: linear-gradient(180deg, rgba(0,0,0,0.08), transparent 18%);
    }
    .empty-card {
      padding: 14px;
    }
    .sidebar {
      position: sticky;
      top: 0;
      height: 100vh;
      border-left: 1px solid var(--border);
      background: #111a24;
      padding: 14px;
      overflow-y: auto;
      box-sizing: border-box;
    }
    .detail-title {
      font-size: 16px;
    }
    .detail-meta {
      margin-bottom: 10px;
    }
    pre {
      margin: 0;
      padding: 10px;
      background: #0b121a;
      border: 1px solid var(--border);
      border-radius: 8px;
      overflow: auto;
      font-size: 12px;
      line-height: 1.45;
      color: #dce8f5;
      white-space: pre-wrap;
      word-break: break-word;
    }
    .pill {
      display: inline-block;
      font-size: 11px;
      border: 1px solid #304459;
      padding: 2px 6px;
      border-radius: 999px;
      color: #a9bfd6;
      margin: 0 6px 6px 0;
      background: #102030;
    }
    .tooltip {
      position: fixed;
      z-index: 10;
      background: rgba(10, 16, 23, 0.95);
      color: #dce8f5;
      border: 1px solid #32465c;
      border-radius: 8px;
      padding: 8px 10px;
      pointer-events: none;
      font-size: 12px;
      max-width: 420px;
      line-height: 1.45;
    }
    select,
    input[type="checkbox"] {
      accent-color: var(--accent);
    }
    select {
      background: #0d1520;
      color: #dce8f5;
      border: 1px solid #2a3f53;
      border-radius: 8px;
      padding: 5px 8px;
    }
    .lane-label {
      fill: #c8d6e5;
      font-size: 12px;
      font-weight: 600;
    }
    .lane-line {
      stroke: #2f4154;
      stroke-width: 1;
    }
    .lane-floor {
      stroke: #6ea8d9;
      stroke-width: 4;
      opacity: 0.85;
    }
    .lane-line.selected {
      stroke: var(--accent);
      opacity: 0.9;
      stroke-width: 2;
    }
    .lane-floor.selected {
      stroke: var(--accent);
      opacity: 1;
      stroke-width: 5;
    }
    .event-dot {
      stroke: #0e1620;
      stroke-width: 1.5;
      cursor: pointer;
    }
    .event-dot.selected {
      stroke: #ffffff;
      stroke-width: 2.5;
      filter: drop-shadow(0 0 5px rgba(255,255,255,0.6));
    }
    .route {
      fill: none;
      stroke-width: 2;
      opacity: 0.75;
    }
    .route.private {
      stroke-dasharray: 6 4;
    }
    .grid-line {
      stroke: var(--grid);
      stroke-width: 1;
      opacity: 0.35;
    }
    .ts-label {
      fill: #8ea2b7;
      font-size: 10px;
    }
    .empty-state {
      fill: #8ea2b7;
      font-size: 13px;
    }
    @keyframes dotPulse {
      0%   { transform: scale(1); opacity: 0.7; }
      100% { transform: scale(4.5); opacity: 0; }
    }
    .pulse-ring {
      fill: none;
      stroke-width: 1.5;
      animation: dotPulse 1.5s ease-out infinite;
      pointer-events: none;
      transform-box: fill-box;
      transform-origin: center;
    }
    @media (max-width: 1200px) {
      body {
        overflow: auto;
      }
      .shell {
        grid-template-columns: 1fr;
        height: auto;
      }
      .sidebar {
        position: static;
        height: auto;
        border-left: 0;
        border-top: 1px solid var(--border);
      }
      .session-panel summary {
        flex-direction: column;
      }
      .session-toggle {
        flex-direction: row;
        justify-content: space-between;
        align-items: center;
        min-width: 0;
      }
    }
  </style>
</head>
<body>
  <div class="shell">
    <section class="main">
      <div class="header">
        <h1>OFP Conversation Trace</h1>
        <div class="meta">conversation: <span id="conv"></span> | events: <span id="count"></span> | nested sessions: <span id="nestedCount"></span> | generated: <span id="generatedAt">__GENERATED_AT__</span></div>
      </div>

      <div id="mainSection"></div>

      <section class="nested-block">
        <div class="nested-header">
          <div>
            <h2>Nested Sessions</h2>
            <div class="meta">Breakout rooms and coding sessions render as separate conversations with their own local filters. Clicking any event still updates the shared Event Details sidebar.</div>
          </div>
        </div>
        <div id="nestedSessions" class="session-list"></div>
      </section>
    </section>

    <aside class="sidebar">
      <h2 class="detail-title">Event Details</h2>
      <div class="detail-meta" id="detailMeta">Select an event dot to inspect full OFP envelope JSON.</div>
      <div id="detailPills"></div>
      <pre id="detailJson">{}</pre>
    </aside>
  </div>

  <script src="https://cdn.jsdelivr.net/npm/d3@7"></script>
  <script>
    const TRACE_DATA = __PAYLOAD__;
    const EVENT_COLORS = __COLORS__;
    const ROOT_CONVERSATION_ID = TRACE_DATA.conversation_id;
    const MANAGER_URIS = new Set([
      "tag:ofp-playground.local,2025:floor-manager",
      "tag:ofp-playground.local,2025:breakout-floor-manager",
      "tag:ofp-playground.local,2025:coding-session-manager",
    ]);

    const tooltip = document.createElement("div");
    tooltip.className = "tooltip";
    tooltip.style.display = "none";
    document.body.appendChild(tooltip);

    let selectedEventIndex = null;
    const sectionControllers = [];
    const sessionPanelById = new Map();
    const renderedSessionScopes = new Set();

    const events = [...(TRACE_DATA.events || [])]
      .map(normalizeEvent)
      .sort((a, b) => a.timestamp - b.timestamp || a.index - b.index);

    const agentMap = new Map((TRACE_DATA.agents || []).map((agent) => [agent.uri, agent.name]));
    for (const evt of events) {
      if (!agentMap.has(evt.sender_uri)) {
        agentMap.set(evt.sender_uri, evt.sender_name || evt.sender_uri);
      }
      for (const [index, uri] of (evt.route_uris || []).entries()) {
        if (!agentMap.has(uri)) {
          agentMap.set(uri, (evt.route_names || [])[index] || uri.split(":").pop());
        }
      }
      for (const [index, uri] of (evt.explicit_target_uris || []).entries()) {
        if (!agentMap.has(uri)) {
          agentMap.set(uri, (evt.explicit_target_names || [])[index] || uri.split(":").pop());
        }
      }
    }

    const mainEvents = events.filter((evt) => evt.scope_kind === "main");
    const sessionGroups = buildSessionGroups(events.filter((evt) => evt.scope_kind !== "main"));

    document.getElementById("conv").textContent = ROOT_CONVERSATION_ID;
    document.getElementById("count").textContent = events.length;
    document.getElementById("nestedCount").textContent = sessionGroups.length;

    renderTimelineSection(document.getElementById("mainSection"), mainEvents, {
      title: "Main Conversation",
      subtitle: `${mainEvents.length} top-level events on the parent floor`,
      emphasize: true,
      emptyMessage: "No main conversation events in this trace.",
      summarySessions: sessionGroups,
    });
    renderSessionPanels();

    function normalizeEvent(evt) {
      const fallbackScopeId = evt.scope_id || evt.breakout_id || inferDefaultScopeId(evt);
      const fallbackScopeKind = evt.scope_kind || inferScopeKind(fallbackScopeId);
      const scopeKind = fallbackScopeKind === "main" ? "main" : fallbackScopeKind;
      const scopeId = scopeKind === "main" ? ROOT_CONVERSATION_ID : fallbackScopeId;
      return {
        ...evt,
        scope_id: scopeId,
        scope_kind: scopeKind,
        parent_conversation_id: evt.parent_conversation_id || (scopeKind === "main" ? null : ROOT_CONVERSATION_ID),
      };
    }

    function inferDefaultScopeId(evt) {
      if (evt.conversation_id && inferScopeKind(evt.conversation_id) !== "main") {
        return evt.conversation_id;
      }
      return ROOT_CONVERSATION_ID;
    }

    function inferScopeKind(scopeId) {
      if (!scopeId || scopeId === ROOT_CONVERSATION_ID) {
        return "main";
      }
      if (String(scopeId).startsWith("breakout:")) {
        return "breakout";
      }
      if (String(scopeId).startsWith("coding:")) {
        return "coding";
      }
      return "nested";
    }

    function labelForScope(kind) {
      switch (kind) {
        case "breakout":
          return "Breakout";
        case "coding":
          return "Coding Session";
        case "main":
          return "Main Conversation";
        default:
          return "Nested Session";
      }
    }

    function displayNameForUri(uri) {
      return agentMap.get(uri) || uri.split(":").pop();
    }

    function isManagerUri(uri) {
      return MANAGER_URIS.has(uri);
    }

    function managerWeight(uri) {
      if (uri === "tag:ofp-playground.local,2025:floor-manager") {
        return 0;
      }
      if (uri === "tag:ofp-playground.local,2025:breakout-floor-manager") {
        return 1;
      }
      if (uri === "tag:ofp-playground.local,2025:coding-session-manager") {
        return 2;
      }
      return 3;
    }

    function buildSessionGroups(nestedEvents) {
      const grouped = new Map();
      for (const evt of nestedEvents) {
        if (!grouped.has(evt.scope_id)) {
          grouped.set(evt.scope_id, []);
        }
        grouped.get(evt.scope_id).push(evt);
      }

      return [...grouped.entries()]
        .map(([scopeId, scopedEvents]) => {
          scopedEvents.sort((a, b) => a.timestamp - b.timestamp || a.index - b.index);
          const first = scopedEvents[0];
          const kickoff = scopedEvents.find((evt) => isManagerUri(evt.sender_uri) && evt.summary) || first;
          const participants = [...new Set(
            scopedEvents
              .flatMap((evt) => [evt.sender_uri, ...(evt.route_uris || [])])
              .filter((uri) => uri && !isManagerUri(uri))
              .map(displayNameForUri)
          )].sort((a, b) => a.localeCompare(b));

          return {
            scope_id: scopeId,
            scope_kind: first.scope_kind,
            label: labelForScope(first.scope_kind),
            summary: kickoff.summary || `${labelForScope(first.scope_kind)} conversation`,
            participants,
            event_count: scopedEvents.length,
            first_timestamp: scopedEvents[0].timestamp,
            last_timestamp: scopedEvents[scopedEvents.length - 1].timestamp,
            events: scopedEvents,
          };
        })
        .sort((a, b) => a.first_timestamp - b.first_timestamp);
    }

    function collectLaneUris(sectionEvents) {
      const uris = new Set();
      for (const evt of sectionEvents) {
        if (evt.sender_uri) {
          uris.add(evt.sender_uri);
        }
        for (const uri of evt.route_uris || []) {
          if (uri) {
            uris.add(uri);
          }
        }
        for (const uri of evt.explicit_target_uris || []) {
          if (uri) {
            uris.add(uri);
          }
        }
      }
      return [...uris].sort((left, right) => {
        const leftManager = isManagerUri(left);
        const rightManager = isManagerUri(right);
        if (leftManager && rightManager) {
          return managerWeight(left) - managerWeight(right);
        }
        if (leftManager) {
          return -1;
        }
        if (rightManager) {
          return 1;
        }
        return displayNameForUri(left).localeCompare(displayNameForUri(right));
      });
    }

    function colorFor(evt) {
      if (evt.directive) {
        return "#FF6B35";
      }
      return EVENT_COLORS[evt.event_type] || "#8a99ac";
    }

    function routeTargets(evt) {
      const routed = (evt.route_uris || []).filter((uri) => uri && uri !== evt.sender_uri);
      if (routed.length) {
        return routed;
      }
      return (evt.explicit_target_uris || []).filter((uri) => uri && uri !== evt.sender_uri);
    }

    function renderTimelineSection(host, sectionEvents, config) {
      host.innerHTML = "";

      const section = document.createElement("section");
      section.className = "trace-section";
      if (config.emphasize) {
        section.classList.add("main-section");
      }
      host.appendChild(section);

      const lanes = collectLaneUris(sectionEvents);
      const eventTypes = [...new Set(sectionEvents.map((evt) => evt.event_type))].sort((a, b) => a.localeCompare(b));
      const typeState = new Map(eventTypes.map((eventType) => [eventType, true]));
      const baseMargins = { top: 58, right: 40, bottom: 30, left: 90 };
      const laneGap = 210;
      const rowGap = 38;

      const top = document.createElement("div");
      top.className = "section-top";
      section.appendChild(top);

      const heading = document.createElement("div");
      top.appendChild(heading);

      const title = document.createElement("h2");
      title.className = "section-title";
      title.textContent = config.title;
      heading.appendChild(title);

      const subtitle = document.createElement("div");
      subtitle.className = "section-subtitle";
      subtitle.textContent = config.subtitle;
      heading.appendChild(subtitle);

      if (config.summarySessions && config.summarySessions.length) {
        const strip = document.createElement("div");
        strip.className = "summary-strip";
        heading.appendChild(strip);

        for (const session of config.summarySessions) {
          const button = document.createElement("button");
          button.type = "button";
          button.className = "session-chip";
          button.textContent = `${session.label} • ${session.event_count} events • ${session.scope_id}`;
          button.addEventListener("click", () => focusSessionPanel(session.scope_id));
          strip.appendChild(button);
        }
      }

      const controls = document.createElement("div");
      controls.className = "section-controls";
      section.appendChild(controls);

      const filterGroup = document.createElement("div");
      filterGroup.className = "filter-group";
      controls.appendChild(filterGroup);

      const senderLabel = document.createElement("label");
      senderLabel.textContent = "Sender: ";
      filterGroup.appendChild(senderLabel);

      const senderFilter = document.createElement("select");
      senderLabel.appendChild(senderFilter);

      appendOption(senderFilter, "__all__", "All senders");
      for (const uri of lanes) {
        appendOption(senderFilter, uri, displayNameForUri(uri));
      }

      const legend = document.createElement("div");
      legend.className = "legend";
      controls.appendChild(legend);

      for (const eventType of eventTypes) {
        const item = document.createElement("label");
        item.className = "legend-item";

        const checkbox = document.createElement("input");
        checkbox.type = "checkbox";
        checkbox.checked = true;
        checkbox.addEventListener("change", () => {
          typeState.set(eventType, checkbox.checked);
          draw();
        });

        const swatch = document.createElement("span");
        swatch.className = "swatch";
        swatch.style.background = EVENT_COLORS[eventType] || "#8a99ac";

        const text = document.createElement("span");
        text.textContent = eventType;

        item.appendChild(checkbox);
        item.appendChild(swatch);
        item.appendChild(text);
        legend.appendChild(item);
      }

      const canvasWrap = document.createElement("div");
      canvasWrap.className = `canvas-wrap${config.emphasize ? " main-canvas" : ""}`;
      section.appendChild(canvasWrap);

      const svgNode = document.createElementNS("http://www.w3.org/2000/svg", "svg");
      canvasWrap.appendChild(svgNode);
      const svg = d3.select(svgNode);

      senderFilter.addEventListener("change", draw);

      function filteredEvents() {
        return sectionEvents.filter((evt) => {
          const senderMatches = senderFilter.value === "__all__" || evt.sender_uri === senderFilter.value;
          return senderMatches && typeState.get(evt.event_type);
        });
      }

      function laneX(uri) {
        const index = lanes.indexOf(uri);
        return index < 0 ? NaN : baseMargins.left + index * laneGap;
      }

      function clearSelection() {
        svg.selectAll(".lane-line, .lane-floor").classed("selected", false);
        svg.selectAll("circle.event-dot").classed("selected", false);
        svg.selectAll(".pulse-ring").remove();
      }

      function applySelection() {
        clearSelection();
        if (selectedEventIndex === null) {
          return;
        }
        const selectedEvt = filteredEvents().find((evt) => evt.index === selectedEventIndex);
        if (!selectedEvt) {
          return;
        }

        svg.selectAll(".lane-line, .lane-floor")
          .classed("selected", function() {
            return this.getAttribute("data-lane-uri") === selectedEvt.sender_uri;
          });

        svg.selectAll("g.row")
          .each(function(rowEvt) {
            if (rowEvt.index !== selectedEvt.index) {
              return;
            }
            const row = d3.select(this);
            const dot = row.select("circle.event-dot");
            dot.classed("selected", true);
            const cx = +dot.attr("cx");
            const cy = +dot.attr("cy");
            row.append("circle")
              .attr("class", "pulse-ring")
              .attr("cx", cx)
              .attr("cy", cy)
              .attr("r", rowEvt.directive ? 6 : 5)
              .attr("stroke", dot.attr("fill"));
          });
      }

      function draw() {
        const data = filteredEvents();
        const width = Math.max(960, baseMargins.left + baseMargins.right + Math.max(1, lanes.length - 1) * laneGap);
        const height = Math.max(240, baseMargins.top + baseMargins.bottom + Math.max(1, data.length) * rowGap);

        svg.attr("width", width).attr("height", height);
        svg.selectAll("*").remove();

        const defs = svg.append("defs");
        defs.append("marker")
          .attr("id", `arrow-${config.title.replace(/\\s+/g, "-").toLowerCase()}`)
          .attr("viewBox", "0 -5 10 10")
          .attr("refX", 9)
          .attr("refY", 0)
          .attr("markerWidth", 6)
          .attr("markerHeight", 6)
          .attr("orient", "auto")
          .append("path")
          .attr("d", "M0,-5L10,0L0,5")
          .attr("fill", "#8aa6c1");

        const g = svg.append("g");

        if (!data.length) {
          g.append("text")
            .attr("class", "empty-state")
            .attr("x", 20)
            .attr("y", 36)
            .text(config.emptyMessage || "No events match the current filters.");
          return;
        }

        for (let i = 0; i < data.length; i += 2) {
          const y = baseMargins.top + i * rowGap;
          g.append("line")
            .attr("class", "grid-line")
            .attr("x1", 20)
            .attr("x2", width - 20)
            .attr("y1", y)
            .attr("y2", y);
        }

        lanes.forEach((uri) => {
          const x = laneX(uri);
          const laneClass = isManagerUri(uri) ? "lane-floor" : "lane-line";
          g.append("line")
            .attr("class", laneClass)
            .attr("data-lane-uri", uri)
            .attr("x1", x)
            .attr("x2", x)
            .attr("y1", baseMargins.top - 24)
            .attr("y2", height - baseMargins.bottom);

          g.append("text")
            .attr("class", "lane-label")
            .attr("x", x)
            .attr("y", 26)
            .attr("text-anchor", "middle")
            .text(displayNameForUri(uri));
        });

        const rows = g.selectAll("g.row")
          .data(data)
          .join("g")
          .attr("class", "row")
          .attr("transform", (_, index) => `translate(0, ${baseMargins.top + index * rowGap})`);

        rows.append("text")
          .attr("class", "ts-label")
          .attr("x", 8)
          .attr("y", 4)
          .text((evt) => new Date(evt.wall_time * 1000).toLocaleTimeString());

        rows.each(function(evt) {
          const row = d3.select(this);
          const sx = laneX(evt.sender_uri);
          if (Number.isNaN(sx)) {
            return;
          }

          const color = colorFor(evt);
          for (const targetUri of routeTargets(evt)) {
            const tx = laneX(targetUri);
            if (Number.isNaN(tx)) {
              continue;
            }
            const mx = (sx + tx) / 2;
            row.append("path")
              .attr("class", `route ${evt.is_private ? "private" : ""}`)
              .attr("d", `M${sx},0 C ${mx},-16 ${mx},16 ${tx},0`)
              .attr("stroke", color)
              .attr("marker-end", `url(#arrow-${config.title.replace(/\\s+/g, "-").toLowerCase()})`);
          }

          row.append("circle")
            .attr("class", "event-dot")
            .attr("cx", sx)
            .attr("cy", 0)
            .attr("r", evt.directive ? 6 : 5)
            .attr("fill", color)
            .on("mouseover", (domEvent) => {
              tooltip.style.display = "block";
              tooltip.innerHTML = `<strong>${evt.event_type}</strong> ${evt.is_private ? "(private)" : ""}<br/>${evt.sender_name}<br/>${evt.summary || ""}`;
              tooltip.style.left = `${domEvent.clientX + 12}px`;
              tooltip.style.top = `${domEvent.clientY + 12}px`;
            })
            .on("mousemove", (domEvent) => {
              tooltip.style.left = `${domEvent.clientX + 12}px`;
              tooltip.style.top = `${domEvent.clientY + 12}px`;
            })
            .on("mouseout", () => {
              tooltip.style.display = "none";
            })
            .on("click", () => selectEvent(evt));
        });

        applySelection();
      }

      draw();
      sectionControllers.push({ applySelection });
    }

    function appendOption(select, value, label) {
      const option = document.createElement("option");
      option.value = value;
      option.textContent = label;
      select.appendChild(option);
    }

    function renderSessionPanels() {
      const host = document.getElementById("nestedSessions");
      host.innerHTML = "";

      if (!sessionGroups.length) {
        const empty = document.createElement("div");
        empty.className = "empty-card";
        empty.innerHTML = '<div class="section-title">No Nested Sessions</div><div class="empty-copy">This trace only contains the main conversation.</div>';
        host.appendChild(empty);
        return;
      }

      for (const session of sessionGroups) {
        const panel = document.createElement("details");
        panel.className = "session-panel";
        panel.dataset.scopeId = session.scope_id;
        panel.dataset.scopeKind = session.scope_kind;
        sessionPanelById.set(session.scope_id, panel);

        const summary = document.createElement("summary");
        panel.appendChild(summary);

        const heading = document.createElement("div");
        heading.className = "session-heading";
        summary.appendChild(heading);

        const titleRow = document.createElement("div");
        titleRow.className = "session-title-row";
        heading.appendChild(titleRow);

        const kind = document.createElement("span");
        kind.className = "session-kind";
        kind.textContent = session.label;
        titleRow.appendChild(kind);

        const title = document.createElement("div");
        title.className = "session-title";
        title.textContent = session.summary || session.label;
        titleRow.appendChild(title);

        const sessionId = document.createElement("div");
        sessionId.className = "session-id";
        sessionId.textContent = session.scope_id;
        heading.appendChild(sessionId);

        const summaryCopy = document.createElement("div");
        summaryCopy.className = "session-summary";
        summaryCopy.textContent = session.participants.length
          ? `${session.event_count} events across ${session.participants.length} participants`
          : `${session.event_count} events in this nested session`;
        heading.appendChild(summaryCopy);

        const preview = document.createElement("div");
        preview.className = "session-preview";
        heading.appendChild(preview);

        const participantsText = session.participants.length
          ? session.participants.join(", ")
          : "No non-manager participants recorded";
        preview.appendChild(makeSessionStat("Participants", participantsText));
        preview.appendChild(makeSessionStat("Parent", session.events[0]?.parent_conversation_id || ROOT_CONVERSATION_ID));

        const badges = document.createElement("div");
        badges.className = "session-badges";
        const toggle = document.createElement("div");
        toggle.className = "session-toggle";

        const toggleCopy = document.createElement("div");
        toggleCopy.className = "session-toggle-copy";
        toggle.appendChild(toggleCopy);

        const chevron = document.createElement("div");
        chevron.className = "session-chevron";
        chevron.textContent = "⌄";
        toggle.appendChild(chevron);

        toggle.appendChild(badges);
        summary.appendChild(toggle);

        badges.appendChild(makePill(`${session.event_count} events`));
        badges.appendChild(makePill(`${session.participants.length} participants`));

        const body = document.createElement("div");
        body.className = "panel-body";
        panel.appendChild(body);

        panel.addEventListener("toggle", () => {
          toggleCopy.textContent = panel.open ? "Collapse Timeline" : "Expand Timeline";
          if (panel.open) {
            ensureSessionRendered(session.scope_id, body);
          }
        });

        toggleCopy.textContent = "Expand Timeline";

        host.appendChild(panel);
      }
    }

    function ensureSessionRendered(scopeId, body) {
      if (renderedSessionScopes.has(scopeId)) {
        return;
      }
      const session = sessionGroups.find((candidate) => candidate.scope_id === scopeId);
      if (!session) {
        return;
      }
      renderTimelineSection(body, session.events, {
        title: session.label,
        subtitle: `${session.scope_id} • ${session.event_count} events`,
        emptyMessage: "No events in this nested session.",
      });
      renderedSessionScopes.add(scopeId);
    }

    function focusSessionPanel(scopeId) {
      const panel = sessionPanelById.get(scopeId);
      if (!panel) {
        return;
      }
      panel.open = true;
      ensureSessionRendered(scopeId, panel.querySelector(".panel-body"));
      panel.scrollIntoView({ behavior: "smooth", block: "start" });
    }

    function makePill(text) {
      const pill = document.createElement("span");
      pill.className = "pill";
      pill.textContent = text;
      return pill;
    }

    function makeSessionStat(label, value) {
      const stat = document.createElement("div");
      stat.className = "session-stat";

      const statLabel = document.createElement("div");
      statLabel.className = "session-stat-label";
      statLabel.textContent = label;
      stat.appendChild(statLabel);

      const statValue = document.createElement("div");
      statValue.className = "session-stat-value";
      statValue.textContent = value;
      stat.appendChild(statValue);

      return stat;
    }

    function selectEvent(evt) {
      selectedEventIndex = evt.index;
      for (const controller of sectionControllers) {
        controller.applySelection();
      }

      const meta = [
        `type: ${evt.event_type}`,
        `sender: ${evt.sender_name}`,
        `conversation: ${evt.conversation_id}`,
        `scope: ${labelForScope(evt.scope_kind)}${evt.scope_kind === "main" ? "" : ` (${evt.scope_id})`}`,
        `route: ${(evt.route_names || []).join(", ") || "(none)"}`,
      ].join(" | ");

      const detailPills = document.getElementById("detailPills");
      detailPills.innerHTML = "";
      detailPills.appendChild(makePill(evt.is_private ? "private" : "shared"));
      detailPills.appendChild(makePill(evt.directive || "no-directive"));
      detailPills.appendChild(makePill(evt.media_type || "text-only"));
      detailPills.appendChild(makePill(labelForScope(evt.scope_kind)));

      document.getElementById("detailMeta").textContent = meta;
      document.getElementById("detailJson").textContent = evt.envelope_json || "{}";
    }
  </script>
</body>
</html>
"""

    html = (
        template.replace("__PAYLOAD__", payload_json)
        .replace("__COLORS__", colors_json)
        .replace("__GENERATED_AT__", generated_at)
    )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(html, encoding="utf-8")
    return output_path
