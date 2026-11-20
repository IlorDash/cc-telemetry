#!/usr/bin/env node
// Injects the side rail (grafana/rail/rail.json) into every grafana/dashboards/*.json.
// Usage (no dependencies; any folder):  node grafana/rail/sync-rail.js [--check]
//   (no flag)  rewrite the dashboards whose rail differs from the source
//   --check    write nothing; exit 1 if any dashboard's rail differs from the source
// Idempotent: a second run changes nothing. See the _doc lines of rail.json for the id scheme.
const fs = require("fs");
const path = require("path");

const check = process.argv.includes("--check");
const dashDir = path.resolve(__dirname, "..", "dashboards");
const rail = JSON.parse(fs.readFileSync(path.join(__dirname, "rail.json"), "utf8"));

const ID_MIN = 300; // the rail owns ids 300-399
const ID_MAX = 399;
const isRail = (p) => p.id >= ID_MIN && p.id <= ID_MAX;
const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

// One compact link per dashboard; the active one gets the background and the orange left bar.
function navHtml(activeUid) {
  const items = rail.nav.map((n) => {
    const on = n.uid === activeUid;
    const style =
      "display:block;padding:2px 8px;margin:0 0 1px 0;text-decoration:none;line-height:1.25;border-left:3px solid " +
      (on ? "#F46800" : "transparent") + ";background:" + (on ? "#22252b" : "transparent");
    return (
      '<a href="/d/' + n.uid + "?${__url_time_range}&${__all_variables}" + '" style="' + style + '">' +
      '<span style="display:block;color:#ccccdc;font-size:15px;font-weight:500">' + esc(n.title) + "</span>" +
      '<span style="display:block;color:#8e8e9e;font-size:13px">' + esc(n.hint) + "</span></a>"
    );
  });
  return items.join("");
}

function buildRail(entry) {
  let y = 0;
  return rail.panels.map((tpl) => {
    const { idOffset, gridPos, ...rest } = tpl;
    const h = gridPos && gridPos.h;
    if (!Number.isInteger(h) || h <= 0) throw new Error("rail panel idOffset " + idOffset + ": gridPos.h must be a positive integer");
    const panel = JSON.parse(JSON.stringify({ id: entry.idBase + idOffset, ...rest }));
    if (panel.options && panel.options.content === "@nav") panel.options.content = navHtml(entry.uid);
    // keep gridPos next to the other layout keys: put it right after the description / datasource
    const out = {};
    for (const k of Object.keys(panel)) {
      out[k] = panel[k];
      if (k === "datasource" || (k === "description" && !panel.datasource)) {
        out.gridPos = { x: 0, y, w: rail.railW, h };
      }
    }
    if (!out.gridPos) out.gridPos = { x: 0, y, w: rail.railW, h };
    y += h;
    return out;
  });
}

for (const entry of rail.nav) {
  if (!Number.isInteger(entry.idBase) || entry.idBase < ID_MIN || entry.idBase + 9 > ID_MAX)
    throw new Error("nav " + entry.uid + ": idBase must be in 300-390");
}
if (new Set(rail.nav.map((n) => n.idBase)).size !== rail.nav.length) throw new Error("nav: duplicate idBase");

// Phase 1: build and validate every dashboard (any throw happens before anything is written).
// Phase 2: write the ones that differ.
const results = [];
const files = fs.readdirSync(dashDir).filter((f) => f.endsWith(".json")).sort();
for (const file of files) {
  const full = path.join(dashDir, file);
  const before = fs.readFileSync(full, "utf8");
  const dash = JSON.parse(before);
  const entry = rail.nav.find((n) => n.uid === dash.uid);
  if (!entry) throw new Error(file + ": uid '" + dash.uid + "' is not in rail.json nav (add it)");

  const content = dash.panels.filter((p) => !isRail(p));
  for (const p of content) {
    if (p.type === "row") throw new Error(file + ": row panel " + p.id + " would cut the rail (use a text header)");
    if (p.gridPos.x < rail.railW) throw new Error(file + ": panel " + p.id + " overlaps the rail column (x < " + rail.railW + ")");
  }
  dash.panels = [...buildRail(entry), ...content];

  results.push({ file, full, before, after: JSON.stringify(dash, null, 2) + "\n" });
}

let differs = 0;
for (const r of results) {
  if (r.after === r.before) {
    console.log("unchanged  " + r.file);
    continue;
  }
  differs++;
  if (check) {
    console.log("DIFFERS    " + r.file);
  } else {
    fs.writeFileSync(r.full, r.after);
    console.log("updated    " + r.file);
  }
}

if (check && differs > 0) {
  console.error(differs + " dashboard(s) differ from grafana/rail/rail.json: run node grafana/rail/sync-rail.js");
  process.exit(1);
}
