// Runs claude-context/scripts/check-dashboard.js against the demo Grafana (the original reads the
// real password from .env). It builds a temp copy with the fixed demo password and points it at the
// repo's dashboards. Usage (repo root): node tools/docs-demo/check.js [check-dashboard.js options]
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

const repo = path.resolve(__dirname, "..", "..");
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "cc-demo-check-"));
fs.mkdirSync(path.join(tmp, "claude-context", "scripts"), { recursive: true });
fs.copyFileSync(path.join(repo, "claude-context", "scripts", "check-dashboard.js"),
  path.join(tmp, "claude-context", "scripts", "check-dashboard.js"));
fs.writeFileSync(path.join(tmp, ".env"), "GRAFANA_ADMIN_PASSWORD=demo-grafana\n");
const r = spawnSync(process.execPath, [
  path.join(tmp, "claude-context", "scripts", "check-dashboard.js"),
  "--url", "http://localhost:13000", "--dashboards", path.join(repo, "grafana", "dashboards"),
  ...process.argv.slice(2),
], { stdio: "inherit" });
fs.rmSync(tmp, { recursive: true, force: true });
process.exit(r.status === null ? 1 : r.status);
