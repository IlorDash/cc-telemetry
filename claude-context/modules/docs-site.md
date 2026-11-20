# Docs site — the public user guide (MkDocs, GitHub Pages)

The bilingual user guide built by MkDocs Material, its version stamp, CI and the demo stack that
makes its screenshots.

## Files

| Path | Role |
| --- | --- |
| `mkdocs.yml` | site config: Material theme, i18n plugin (suffix mode), `nav` + `nav_translations`, `validation`, hook list; `site_url: !ENV [SITE_URL, ""]` |
| `docs/<page>.md`, `docs/<page>.ru.md` | English page and its Russian twin (suffix mode: `/` and `/ru/`) |
| `docs/stylesheets/extra.css` | brand colours (`primary`/`accent: custom`; muted Grafana orange `#C27C57`), both schemes |
| `docs/assets/*.png` | screenshots, one copy for both languages; taken from demo data only |
| `docs/requirements.txt` | pinned `mkdocs==1.6.1`, `mkdocs-material==9.5.49`, `mkdocs-static-i18n==1.2.3`; excluded from the site (`exclude_docs`) |
| `VERSION` | single source of the version (`1.0.0`) |
| `hooks/app_version.py` | MkDocs hook: version on the title, `{{ app_version }}`, copyright |
| `ci/check-release-markers.sh` | fails when a `docs/**/*.md` still holds `<!-- unreleased` |
| `.github/workflows/docs.yml` | jobs `check`, `release-markers`, `build`, `deploy` |
| `tools/docs-demo/` | throwaway demo stack + screenshot script (not published) |
| `README.md` | short: intro, data flow, quick start, links to the site (EN and `/ru/`) |

## Build and publish

```text
feature branch ──PR──► develop ──PR──► main ──push──► build ──► deploy (GitHub Pages)
   PR (any base): check = pip install -r docs/requirements.txt; mkdocs build --strict
                  → artifact docs-preview (site/, 7 days) = the preview (Pages has no per-PR preview)
   PR into main : release-markers = bash ci/check-release-markers.sh docs
   push to main (paths mkdocs.yml, docs/**, hooks/**, VERSION, ci/**, the workflow)
   or workflow_dispatch on main: build (configure-pages → SITE_URL=base_url, marker check,
                  strict build, upload-pages-artifact) → deploy (deploy-pages, concurrency pages)
```

- Only `main` publishes: `build`/`deploy` are gated on `refs/heads/main`; a manual run from
  another branch does nothing.
- A push to `main` touching none of those paths does not redeploy → run the workflow by hand.
- Pages source must be "GitHub Actions" (Settings → Pages, set once by the owner).
- The script runs through `bash`, not executed: the exec bit gets lost on Windows.

## mkdocs.yml — decisions

| Setting | Why |
| --- | --- |
| no `navigation.instant` | with it the i18n language switcher always drops to the home page |
| `validation` all `warn` + `--strict` | dead links / anchors fail the build (CI and locally) |
| `toc.slugify` = `pymdownx.slugs.slugify` (lower) | keeps Cyrillic headings in anchors so links into RU pages resolve |
| `nav_translations` | matches nav **titles**: a new nav section or page with an English-only title needs an entry |
| `site_url` from env | empty locally (relative build); CI sets the Pages address for canonical / sitemap / hreflang |

## Version and release notes

- `hooks/app_version.py` reads `VERSION` on each event; missing or empty → `PluginError` (build
  fails). `on_config` sets `copyright = "cc-telemetry v<version>"`; `on_page_markdown` replaces
  `{{ app_version }}`; `on_page_context` appends `v<version>` (after a space) to `site_name` (not in `on_config`:
  i18n swaps the per-language `site_name` after it; guarded against appending twice).
- Release notes: nav section "Release notes", one `docs/release-X-Y-Z.md` + `.ru.md` per version,
  newest first; also a row in `index`'s "Where to start". A version still in preparation carries an
  "in preparation" banner tagged `<!-- unreleased` instead of a date — allowed on `develop`,
  blocks the PR into `main` and the `main` build. Set the date and remove both before the merge.

## Page → source of truth

| Page | Describes | Read from |
| --- | --- | --- |
| `index` | what it is, data flow, dashboard table, platforms, "Where to start" | whole repo; dashboard titles |
| `server` | Windows / Linux install, options, what the script does, failures | `setup-server.ps1`, `setup-server.sh` |
| `clients` | install, what the script changes (env keys), session titles, project | `client/setup-client.{ps1,sh}`, `client/*.json` |
| `dashboards` | rail, variables, time range, clicks, one section per dashboard | `grafana/dashboards/*.json`, `grafana/rail/rail.json` |
| `tips` | what a tip is, rules table, affected tokens/cost, links | `cc.tips` in `clickhouse/views.sql` |
| `maintenance` | check, `--update`, backup/restore, views-init, retention, settings, removal | `setup-server.*`, `linux-server-tools/*.sh`, `docker-compose.yml`, `.env.example` |
| `troubleshooting` | one table per step: `Message` (or `Symptom`) / `Cause` / `What to do` | the scripts' messages |
| `data` | what is sent / dropped, where it lives, prompt logging, deleting data | `otel-collector.yaml`, `client/*.json`, `clickhouse/views.sql` |
| `release-X-Y-Z` | features of that version | — |

A behaviour change updates `docs/<page>.md` **and** its `.ru.md` twin; `README.md` only when the
quick start (commands, requirements, ports) changes.

## Demo stack (`tools/docs-demo/`)

| File | Role |
| --- | --- |
| `generate.py` | made-up `otel.otel_logs` rows (JSONEachRow, stdout), fixed seed; `--now`, `--days 30`; stdlib only |
| `otel_logs.sql` | DDL of `otel.otel_logs` (the collector creates it on the real server) |
| `demo.sh up\|down` | containers `cc-demo-clickhouse`, `cc-demo-grafana`, network `cc-demo-net`; ClickHouse in tmpfs, not published; Grafana on `127.0.0.1:13000`; loads `clickhouse/views.sql` and the repo's dashboards; `down` removes exactly those |
| `check.js` | runs `check-dashboard.js` against the demo (temp copy with the fixed demo password) |
| `screenshots.js` | Playwright function (needs a runner passing `page`): 1920 px, dark theme, writes `docs/assets/*.png` |

- Run from the repo root: `wsl -d Ubuntu -- bash tools/docs-demo/demo.sh up`.
- The demo passwords in `demo.sh` are fixed throwaway values; it never touches the live stack.
- `demo.sh` hardcodes `clickhouse-server:25.8` and `grafana:12.1.0` — keep in step with
  `docker-compose.yml`.

## Local preview

- `py -3 -m venv .venv`, `.venv\Scripts\python.exe -m pip install -r docs/requirements.txt`
  (`.venv/`, `site/` git-ignored); not a bare `pip`: PATH may hold Python 2.7.
- `.venv/Scripts/python.exe -m mkdocs serve -a 127.0.0.1:8000`; `mkdocs build --strict` must exit 0.

## Do not

- List continuation inside a list item: indent **4** spaces (3 breaks the list in Python-Markdown).
- Trust a long-running `mkdocs serve` after adding a page: it may not pick up new files — restart
  it (observed 2026-11-19).
- RU pages: same headings in the same order as EN; Grafana dashboard / panel titles, options and
  script messages stay in English verbatim (Grafana is not localized).
- No personal data on any page or image (e-mails, PC names, IPs, the user's projects, prompts);
  screenshots only from `tools/docs-demo/` data. The site is public, like the README.
