# docs-demo

A throwaway stack with made-up telemetry, used only to take the screenshots of the guide.
All accounts, projects, prompts and numbers are invented; it never touches the real stack.

- Start (repo root, Docker inside WSL): `wsl -d Ubuntu -- bash tools/docs-demo/demo.sh up`
- Open <http://localhost:13000> (admin / demo-grafana). Data covers the last 30 days up to the start.
- Check every dashboard query: `node tools/docs-demo/check.js --from now-30d`
- Stop and remove it: `wsl -d Ubuntu -- bash tools/docs-demo/demo.sh down`
- Re-take the screenshots: `demo.sh up`, then from the repo root run `screenshots.js` with a Playwright
  runner that passes `page` (e.g. the Playwright MCP "run code" tool); it writes `docs/assets/*.png`. Then `demo.sh down`.
- Files: `screenshots.js` (the screenshot script), `generate.py` (deterministic synthetic rows), `otel_logs.sql` (the table the views read).
- It uses containers `cc-demo-*`, network `cc-demo-net`, port 13000 and no volumes.
