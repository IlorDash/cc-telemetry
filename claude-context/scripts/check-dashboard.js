// Runs every variable and panel query of every grafana/dashboards/*.json through Grafana's
// /api/ds/query and prints ok/FAIL per query. Reads the Grafana password from .env (never prints it).
// Usage (repo root): node claude-context/scripts/check-dashboard.js [--project p] [--session id]
//                    [--actor a] [--skill s] [--from now-24h] [--url http://localhost:3000]
// Exit code: 0 all ok, 1 any failure.
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..", "..");
const args = process.argv.slice(2);
const opt = (name, def) => {
  const i = args.indexOf("--" + name);
  return i >= 0 && args[i + 1] ? args[i + 1] : def;
};
const vals = {
  project: opt("project", "__all"),
  session: opt("session", "__all"),
  actor: opt("actor", "__all"),
  skill: opt("skill", "__all"),
};
const from = opt("from", "now-24h");
const url = opt("url", "http://localhost:3000");

const envText = fs.readFileSync(path.join(root, ".env"), "utf8");
const pass = (envText.match(/^GRAFANA_ADMIN_PASSWORD=(.*)$/m) || [])[1];
if (!pass) {
  console.error("GRAFANA_ADMIN_PASSWORD not found in .env");
  process.exit(1);
}
const auth = "Basic " + Buffer.from("admin:" + pass.trim()).toString("base64");

const dashDir = path.join(root, "grafana", "dashboards");
const interp = (s) =>
  s.replace(/\$\{(\w+)(?::\w+)?\}|\$(project|session|actor|skill)\b/g, (m, a, b) => vals[a || b] ?? m);

const items = [];
const uids = [];
const files = fs.readdirSync(dashDir).filter((f) => f.endsWith(".json")).sort();
for (const file of files) {
  const dash = JSON.parse(fs.readFileSync(path.join(dashDir, file), "utf8"));
  const tag = dash.uid + " ";
  for (const v of dash.templating.list) {
    if (v.type === "query") {
      items.push({ name: tag + "var " + v.name, sql: typeof v.query === "string" ? v.query : v.query.rawSql, fmt: 1, qt: "table" });
    }
  }
  const walk = (panels) => {
    for (const p of panels) {
      if (p.panels) walk(p.panels);
      for (const t of p.targets || []) {
        items.push({ name: `${tag}panel ${p.id} ${p.title}`, sql: t.rawSql, fmt: t.format, qt: t.queryType });
      }
    }
  };
  walk(dash.panels);
  uids.push(dash.uid);
}

(async () => {
  let failed = 0;
  // Provisioning: every file's uid is served by Grafana; the home page is the dashboard uid cc-usage.
  const get = async (p) => {
    try {
      const r = await fetch(url + p, { headers: { Authorization: auth } });
      return r.ok ? await r.json() : null;
    } catch (e) {
      return null;
    }
  };
  for (const uid of uids) {
    const d = await get("/api/dashboards/uid/" + uid);
    if (!d) failed++;
    console.log((d ? "ok   " : "FAIL ") + `dashboard ${uid}`.padEnd(58) + (d ? `version=${d.dashboard.version}` : "not provisioned"));
  }
  const home = await get("/api/dashboards/home");
  const homeOk = home && home.dashboard && home.dashboard.uid === "cc-usage";
  if (!homeOk) failed++;
  console.log((homeOk ? "ok   " : "FAIL ") + "home dashboard".padEnd(58) + (homeOk ? "cc-usage" : "not cc-usage"));
  for (const it of items) {
    const body = {
      from,
      to: "now",
      queries: [{
        refId: "A",
        datasource: { type: "grafana-clickhouse-datasource", uid: "clickhouse" },
        rawSql: interp(it.sql),
        format: it.fmt,
        queryType: it.qt,
        editorType: "sql",
        intervalMs: 60000,
        maxDataPoints: 1000,
      }],
    };
    let line;
    try {
      const r = await fetch(url + "/api/ds/query", {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: auth },
        body: JSON.stringify(body),
      });
      const j = await r.json();
      const res = j.results && j.results.A;
      const err = (res && res.error) || (!r.ok && `HTTP ${r.status}`);
      const rows = res && res.frames ? res.frames.reduce((n, f) => n + ((f.data && f.data.values && f.data.values[0]) || []).length, 0) : 0;
      if (err) failed++;
      line = (err ? "FAIL " : "ok   ") + it.name.padEnd(58) + (err ? String(err).slice(0, 300) : `rows=${rows}`);
    } catch (e) {
      failed++;
      line = "FAIL " + it.name.padEnd(58) + "request failed: " + e.message;
    }
    console.log(line);
  }
  console.log(failed ? `${failed} FAILED (of ${items.length} queries + ${uids.length + 1} provisioning checks)` : `all ok (${items.length} queries + ${uids.length + 1} provisioning checks)`);
  process.exit(failed ? 1 : 0);
})();
