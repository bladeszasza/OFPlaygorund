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

    html = f"""<!doctype html>
<html lang=\"en\">
<head>
  <meta charset=\"utf-8\" />
  <meta name=\"viewport\" content=\"width=device-width,initial-scale=1\" />
  <title>OFP Trace Timeline</title>
  <style>
    :root {{
      --bg: #0f1720;
      --panel: #17222d;
      --muted: #93a4b8;
      --text: #e6edf5;
      --accent: #58a6ff;
      --grid: #2a3a4c;
    }}
    html, body {{ margin: 0; height: 100%; overflow: hidden; background: radial-gradient(circle at 20% 10%, #1b2a3a 0%, #0f1720 60%); color: var(--text); font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, sans-serif; }}
    .shell {{ display: grid; grid-template-columns: minmax(0, 1fr) 380px; height: 100vh; overflow: hidden; }}
    .main {{ display: grid; grid-template-rows: auto auto minmax(0, 1fr); gap: 10px; padding: 14px; height: 100vh; overflow: hidden; box-sizing: border-box; }}
    .header {{ background: var(--panel); border: 1px solid #223244; border-radius: 10px; padding: 10px 12px; flex-shrink: 0; }}
    .header h1 {{ margin: 0 0 6px; font-size: 18px; font-weight: 650; }}
    .meta {{ color: var(--muted); font-size: 12px; }}
    .controls {{ display: flex; flex-wrap: wrap; gap: 12px; align-items: center; background: var(--panel); border: 1px solid #223244; border-radius: 10px; padding: 10px 12px; flex-shrink: 0; }}
    .legend {{ display: flex; flex-wrap: wrap; gap: 8px 12px; }}
    .legend-item {{ display: inline-flex; align-items: center; gap: 6px; font-size: 12px; color: var(--muted); }}
    .swatch {{ width: 12px; height: 12px; border-radius: 3px; border: 1px solid #334455; }}
    .canvas-wrap {{ overflow: auto; border: 1px solid #223244; border-radius: 10px; background: linear-gradient(180deg, #111a24, #0d141d); min-height: 0; }}
    @keyframes dotPulse {{
      0%   {{ transform: scale(1);   opacity: 0.7; }}
      100% {{ transform: scale(4.5); opacity: 0; }}
    }}
    .pulse-ring {{ fill: none; stroke-width: 1.5; animation: dotPulse 1.5s ease-out infinite; pointer-events: none; transform-box: fill-box; transform-origin: center; }}
    .event-dot.selected {{ stroke: #ffffff; stroke-width: 2.5; filter: drop-shadow(0 0 5px rgba(255,255,255,0.6)); }}
    .lane-line.selected {{ stroke: var(--accent); opacity: 0.8; stroke-width: 2; }}
    .lane-floor.selected {{ stroke: var(--accent); opacity: 1; stroke-width: 5; }}
    .lane-label {{ fill: #c8d6e5; font-size: 12px; font-weight: 600; }}
    .lane-line {{ stroke: #2f4154; stroke-width: 1; }}
    .lane-floor {{ stroke: #6ea8d9; stroke-width: 4; opacity: 0.85; }}
    .event-dot {{ stroke: #0e1620; stroke-width: 1.5; cursor: pointer; }}
    .route {{ fill: none; stroke-width: 2; opacity: 0.75; }}
    .route.private {{ stroke-dasharray: 6 4; }}
    .grid-line {{ stroke: var(--grid); stroke-width: 1; opacity: 0.35; }}
    .ts-label {{ fill: #8ea2b7; font-size: 10px; }}
    .sidebar {{ position: sticky; top: 0; height: 100vh; border-left: 1px solid #223244; background: #111a24; padding: 14px; overflow-y: auto; box-sizing: border-box; }}
    .detail-title {{ margin: 0 0 6px; font-size: 16px; font-weight: 650; }}
    .detail-meta {{ color: var(--muted); font-size: 12px; margin-bottom: 10px; }}
    pre {{ margin: 0; padding: 10px; background: #0b121a; border: 1px solid #223244; border-radius: 8px; overflow: auto; font-size: 12px; line-height: 1.45; color: #dce8f5; }}
    .pill {{ display: inline-block; font-size: 11px; border: 1px solid #304459; padding: 2px 6px; border-radius: 999px; color: #a9bfd6; margin-right: 6px; }}
    .tooltip {{ position: fixed; z-index: 5; background: rgba(10, 16, 23, 0.95); color: #dce8f5; border: 1px solid #32465c; border-radius: 8px; padding: 8px 10px; pointer-events: none; font-size: 12px; max-width: 400px; }}
    select {{ background: #0d1520; color: #dce8f5; border: 1px solid #2a3f53; border-radius: 8px; padding: 5px 8px; }}
  </style>
</head>
<body>
  <div class=\"shell\">
    <section class=\"main\">
      <div class=\"header\">
        <h1>OFP Conversation Trace</h1>
        <div class=\"meta\">conversation: <span id=\"conv\"></span> | events: <span id=\"count\"></span> | generated: {generated_at}</div>
      </div>

      <div class=\"controls\">
        <label>Sender:
          <select id=\"senderFilter\"></select>
        </label>
        <div class=\"legend\" id=\"legend\"></div>
      </div>

      <div class=\"canvas-wrap\">
        <svg id=\"timeline\"></svg>
      </div>
    </section>

    <aside class=\"sidebar\">
      <h2 class=\"detail-title\">Event Details</h2>
      <div class=\"detail-meta\" id=\"detailMeta\">Select an event dot to inspect full OFP envelope JSON.</div>
      <div id=\"detailPills\"></div>
      <pre id=\"detailJson\">{{}}</pre>
    </aside>
  </div>

  <script src=\"https://cdn.jsdelivr.net/npm/d3@7\"></script>
  <script>
    const TRACE_DATA = {payload_json};
    const EVENT_COLORS = {colors_json};

    const floorUri = "tag:ofp-playground.local,2025:floor-manager";
    const breakoutFloorUri = "tag:ofp-playground.local,2025:breakout-floor-manager";

    const events = [...TRACE_DATA.events].sort((a, b) => a.timestamp - b.timestamp || a.index - b.index);
    document.getElementById("conv").textContent = TRACE_DATA.conversation_id;
    document.getElementById("count").textContent = events.length;

    const agentMap = new Map(TRACE_DATA.agents.map(a => [a.uri, a.name]));
    for (const evt of events) {{
      if (!agentMap.has(evt.sender_uri)) agentMap.set(evt.sender_uri, evt.sender_name || evt.sender_uri);
      for (const uri of evt.route_uris || []) {{
        if (!agentMap.has(uri)) agentMap.set(uri, uri.split(":").pop());
      }}
    }}

    const allUris = [...agentMap.keys()];
    const nonFloor = allUris.filter(u => u !== floorUri && u !== breakoutFloorUri).sort((a, b) => (agentMap.get(a) || a).localeCompare(agentMap.get(b) || b));
    const lanes = [floorUri, ...nonFloor];

    const senderFilter = document.getElementById("senderFilter");
    senderFilter.innerHTML = '<option value="__all__">All senders</option>' + lanes.map(uri => `<option value="${{uri}}">${{agentMap.get(uri) || uri}}</option>`).join("");

    const legendEl = document.getElementById("legend");
    const eventTypes = [...new Set(events.map(e => e.event_type))].sort();
    const typeState = new Map(eventTypes.map(t => [t, true]));
    legendEl.innerHTML = eventTypes.map(t => `
      <label class=\"legend-item\">
        <input type=\"checkbox\" data-type=\"${{t}}\" checked />
        <span class=\"swatch\" style=\"background:${{EVENT_COLORS[t] || '#888'}}\"></span>
        <span>${{t}}</span>
      </label>
    `).join("");

    legendEl.querySelectorAll("input[type=checkbox]").forEach(cb => {{
      cb.addEventListener("change", () => {{
        typeState.set(cb.dataset.type, cb.checked);
        draw();
      }});
    }});

    senderFilter.addEventListener("change", draw);

    const tooltip = document.createElement("div");
    tooltip.className = "tooltip";
    tooltip.style.display = "none";
    document.body.appendChild(tooltip);

    let selectedEventIndex = null;

    const svg = d3.select("#timeline");
    const baseMargins = {{ top: 64, right: 50, bottom: 30, left: 90 }};
    const laneGap = 210;
    const rowGap = 38;

    function filteredEvents() {{
      const selectedSender = senderFilter.value;
      return events.filter(e => typeState.get(e.event_type) && (selectedSender === "__all__" || e.sender_uri === selectedSender));
    }}

    function laneX(uri) {{
      return baseMargins.left + lanes.indexOf(uri) * laneGap;
    }}

    function colorFor(evt) {{
      if (evt.directive) return "#FF6B35";
      return EVENT_COLORS[evt.event_type] || "#888";
    }}

    function routeTargets(evt) {{
      const routes = (evt.route_uris || []).filter(u => u !== evt.sender_uri);
      if (routes.length) return routes;
      if (evt.explicit_target_uris && evt.explicit_target_uris.length) return evt.explicit_target_uris;
      return [];
    }}

    function draw() {{
      const data = filteredEvents();
      const width = Math.max(1200, baseMargins.left + baseMargins.right + Math.max(1, lanes.length - 1) * laneGap);
      const height = Math.max(700, baseMargins.top + baseMargins.bottom + Math.max(1, data.length) * rowGap);

      svg.attr("width", width).attr("height", height);
      svg.selectAll("*").remove();

      const defs = svg.append("defs");
      defs.append("marker")
        .attr("id", "arrow")
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

      // Breakout bands (visual nesting by breakout conversation id)
      const breakoutRows = new Map();
      data.forEach((d, i) => {{
        if (!d.breakout_id) return;
        if (!breakoutRows.has(d.breakout_id)) breakoutRows.set(d.breakout_id, []);
        breakoutRows.get(d.breakout_id).push(i);
      }});
      for (const [breakoutId, rows] of breakoutRows.entries()) {{
        const first = rows[0];
        const last = rows[rows.length - 1];
        const y0 = baseMargins.top + first * rowGap - 14;
        const y1 = baseMargins.top + last * rowGap + 14;
        g.append("rect")
          .attr("x", 22)
          .attr("y", y0)
          .attr("width", width - 44)
          .attr("height", Math.max(24, y1 - y0))
          .attr("fill", "#1a2a3d")
          .attr("opacity", 0.25)
          .attr("rx", 8);
        g.append("text")
          .attr("x", 30)
          .attr("y", y0 + 12)
          .attr("fill", "#88a8c7")
          .attr("font-size", 11)
          .text(`breakout: ${{breakoutId}}`);
      }}

      // Horizontal time grid
      for (let i = 0; i < data.length; i += 2) {{
        const y = baseMargins.top + i * rowGap;
        g.append("line")
          .attr("class", "grid-line")
          .attr("x1", 20)
          .attr("x2", width - 20)
          .attr("y1", y)
          .attr("y2", y);
      }}

      // Lanes
      lanes.forEach((uri, idx) => {{
        const x = laneX(uri);
        const cls = uri === floorUri || uri === breakoutFloorUri ? "lane-floor" : "lane-line";

        g.append("line")
          .attr("class", cls)
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
          .text(agentMap.get(uri) || uri);
      }});

      const rows = g.selectAll("g.row")
        .data(data)
        .join("g")
        .attr("class", "row")
        .attr("transform", (d, i) => `translate(0, ${{baseMargins.top + i * rowGap}})`);

      rows.append("text")
        .attr("class", "ts-label")
        .attr("x", 8)
        .attr("y", 4)
        .text((d) => new Date(d.wall_time * 1000).toLocaleTimeString());

      rows.each(function(d) {{
        const row = d3.select(this);
        const sx = laneX(d.sender_uri);
        const sy = 0;
        const targets = routeTargets(d);
        const color = colorFor(d);

        for (const targetUri of targets) {{
          const tx = laneX(targetUri);
          if (Number.isNaN(tx)) continue;
          const mx = (sx + tx) / 2;
          row.append("path")
            .attr("class", `route ${{d.is_private ? 'private' : ''}}`)
            .attr("d", `M${{sx}},${{sy}} C ${{mx}},${{sy-16}} ${{mx}},${{sy+16}} ${{tx}},${{sy}}`)
            .attr("stroke", color)
            .attr("marker-end", "url(#arrow)");
        }}

        row.append("circle")
          .attr("class", "event-dot")
          .attr("cx", sx)
          .attr("cy", sy)
          .attr("r", d.directive ? 6 : 5)
          .attr("fill", color)
          .on("mouseover", (ev) => {{
            tooltip.style.display = "block";
            tooltip.innerHTML = `<strong>${{d.event_type}}</strong> ${{d.is_private ? '(private)' : ''}}<br/>${{d.sender_name}}<br/>${{d.summary || ''}}`;
          }})
          .on("mousemove", (ev) => {{
            tooltip.style.left = (ev.clientX + 12) + "px";
            tooltip.style.top = (ev.clientY + 12) + "px";
          }})
          .on("mouseout", () => {{
            tooltip.style.display = "none";
          }})
          .on("click", () => selectEvent(d));
      }});

      if (selectedEventIndex !== null) highlightSelected();
    }}

    function highlightSelected() {{
      const data = filteredEvents();
      const selectedEvt = data.find(e => e.index === selectedEventIndex);
      if (!selectedEvt) return;

      // Highlight the lane vertical line
      svg.selectAll(".lane-line, .lane-floor")
        .classed("selected", function() {{
          return this.getAttribute("data-lane-uri") === selectedEvt.sender_uri;
        }});

      // Highlight the dot and add pulse ring
      svg.selectAll("g.row")
        .each(function(d) {{
          if (d.index !== selectedEvt.index) return;
          const row = d3.select(this);
          const dot = row.select("circle.event-dot");
          dot.classed("selected", true);
          const cx = +dot.attr("cx");
          const cy = +dot.attr("cy");
          const color = dot.attr("fill");
          row.append("circle")
            .attr("class", "pulse-ring")
            .attr("cx", cx)
            .attr("cy", cy)
            .attr("r", d.directive ? 6 : 5)
            .attr("stroke", color);
        }});
    }}

    function clearSelection() {{
      svg.selectAll(".lane-line, .lane-floor").classed("selected", false);
      svg.selectAll("circle.event-dot").classed("selected", false);
      svg.selectAll(".pulse-ring").remove();
    }}

    function selectEvent(evt) {{
      clearSelection();
      selectedEventIndex = evt.index;
      highlightSelected();

      const meta = [
        `type: ${{evt.event_type}}`,
        `sender: ${{evt.sender_name}}`,
        `route: ${{(evt.route_names || []).join(', ') || '(none)'}}`,
        evt.breakout_id ? `breakout: ${{evt.breakout_id}}` : null,
      ].filter(Boolean).join(" | ");

      document.getElementById("detailMeta").textContent = meta;
      document.getElementById("detailPills").innerHTML = `
        <span class=\"pill\">${{evt.is_private ? 'private' : 'shared'}}</span>
        <span class=\"pill\">${{evt.directive || 'no-directive'}}</span>
        <span class=\"pill\">${{evt.media_type || 'text-only'}}</span>
      `;
      document.getElementById("detailJson").textContent = evt.envelope_json || "{{}}";
    }}

    draw();
  </script>
</body>
</html>
"""

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(html, encoding="utf-8")
    return output_path
