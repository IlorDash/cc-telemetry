# Plan: user guide on GitHub Pages (MkDocs)

Status: approved 2026-11-19; branch `docs-site` from `develop`; site publishes from `main`.

## Goal

A user guide for cc-telemetry as a MkDocs Material site, built by GitHub Actions and published to
GitHub Pages from `main`. Model: `claude-context/assets/docs-site-prompt.md` (a GitLab Pages site
from another project) — same stack, layout, style rules and checks, adapted to GitHub and to this
project.

## Current state

- The only user documentation is `README.md` (588 lines, English): server setup (Windows, Linux),
  clients, dashboards and tips, maintenance, troubleshooting, what is sent.
- No `.github/`, no CI, no version number, no release tags, no images in the repo.
- Interface strings the docs quote: Grafana dashboard and panel titles, variable names
  (`grafana/dashboards/*.json`, `grafana/rail/rail.json`; English only, Grafana is not localized),
  setup script options and messages (`setup-server.*`, `client/setup-client.*`; English).
- The repo is public: every page and screenshot is public.

## Approach and decisions

- **Stack:** `mkdocs==1.6.1`, `mkdocs-material==9.5.49`, `mkdocs-static-i18n==1.2.3`, pinned in
  `docs/requirements.txt` with the Windows venv note from the model. `/site/` and `/.venv/` in
  `.gitignore`.
- **Layout:** `mkdocs.yml`, `docs/<page>.md` + `docs/<page>.ru.md` (suffix mode),
  `docs/stylesheets/extra.css`, `hooks/` only if needed, `.github/workflows/docs.yml`.
- **mkdocs.yml:** the model's template — Material, light/dark palette with `primary: custom`,
  no `navigation.instant` (breaks the language switcher), `validation` warnings + `--strict`,
  the Cyrillic `slugify`, i18n suffix mode with `nav_translations`. `site_dir: site`.
  Brand colour: Grafana orange `#F46800` (the rail's active-item colour).
- **GitHub Actions** (`.github/workflows/docs.yml`), replacing the GitLab jobs:
  - on `pull_request` touching `mkdocs.yml`, `docs/**`, `hooks/**`, the workflow: `mkdocs build
    --strict`, the built site uploaded as an artifact (the preview; Pages has no per-PR preview);
  - on `push` to `main` (same paths) and `workflow_dispatch`: build with `site_url` from
    `actions/configure-pages` (`base_url`), then `actions/upload-pages-artifact` +
    `actions/deploy-pages`; `permissions: pages: write, id-token: write`; `concurrency: pages`.
  - Actions pinned to major versions (`checkout@v4`, `setup-python@v5`, `configure-pages@v5`,
    `upload-pages-artifact@v3`, `deploy-pages@v4`), Python 3.12.
  - `site_url: !ENV [SITE_URL, ""]` in `mkdocs.yml`; the workflow sets `SITE_URL`.
- **Pages:** user guide for the person who installs and runs the stack and reads the dashboards
  (not a developer of the project), from the README content, re-shaped per the model's page
  shapes:
  - `index` — what it is, how data flows, what each dashboard answers, "Where to start";
  - `server` — install on Windows / Linux, options, both;
  - `clients` — Windows / Linux client, what the script changes, session titles, projects;
  - `dashboards` — the rail, variables, time range, clicks, one section per dashboard;
  - `tips` — what a tip is, the rules table, what to do;
  - `maintenance` — update (`--update`), backup/restore, rollback, views-init;
  - `troubleshooting` — tables Message | Cause | What to do, grouped by step;
  - `data` — what is sent and stored (privacy), turning prompt logging on/off.
- **Style:** section 9 of the model (behaviour not features, failure → what to do, second person,
  tables over prose, titled admonitions, ~95-column wrap). Panel and dashboard titles in **bold**
  exactly as in the JSON; commands, paths, options in backticks.
- **Russian pages:** twins of the English ones (same headings in the same order), idiomatic
  Russian; Grafana titles, script options and messages stay in English verbatim (the UI is
  English).
- **No personal data** on any page or screenshot (no e-mails, PC names, IPs, project names of the
  user, prompts).

## Decisions of the user (2026-11-19)

1. **Languages:** English + Russian.
2. **Version:** introduce one. A `VERSION` file at the repo root (single source), a hook
   `hooks/app_version.py` that stamps it on the site title, `{{ app_version }}` and the copyright
   (per the model: suffix in `on_page_context`, `PluginError` when unreadable); a Release notes
   section, newest first; `ci/check-release-markers.sh` and a workflow job that blocks a PR into
   `main` while a page carries the `<!-- unreleased` marker, and the deploy job runs it too.
3. **Screenshots:** from a throwaway stack with made-up data (no real e-mails, projects, prompts).
   Demo data generator and the screenshot script are tracked so the images can be redone; images
   live in `docs/assets/` (one copy, used by both languages).
4. **README:** shortened to what it is, a quick start and a link to the site; details only on the
   site.

## Still open

- First version number: `1.0.0` (agreed).
- Branch: `docs-site` from `develop` (grafana-redesign merged into develop); releases go
  develop → main, and the site publishes from `main` (agreed).

## Risks

- GitHub Pages must be switched to "GitHub Actions" as the source once, by the user
  (Settings → Pages); until then the deploy job fails.
- `mkdocs-static-i18n` against a newer Material — mitigated by the pinned versions.
- Two copies of the guide (README and site) drift — decided by question 4.
- Public content: a screenshot or example with personal data — checked by the reviewer per page.

## Verification

- Locally: `py -3 -m venv .venv`, install `docs/requirements.txt`, `mkdocs build --strict` exits 0
  with no warnings; `mkdocs serve` checked in the browser (both languages, switcher keeps the page,
  dark mode, search).
- Every quoted dashboard / panel title and script option grepped against the source.
- Workflow: YAML parses; the PR run is the first real check (the user pushes the branch).

## Stages

1. **Skeleton, CI and version.** `mkdocs.yml`, `docs/requirements.txt`, `extra.css`,
   `.gitignore`, `VERSION`, `hooks/app_version.py`, `ci/check-release-markers.sh`,
   `.github/workflows/docs.yml` (PR check, marker check, deploy), `index.md` + `index.ru.md`.
   Result: `mkdocs build --strict` exits 0 locally; the title shows the version in both
   languages; dark mode and the switcher work in `mkdocs serve`; the marker script exits 1 on a
   test page with the marker and 0 without.
2. **Installation.** `server`, `clients` (EN + RU). Result: strict build 0; every option and
   message quoted matches the scripts.
3. **Dashboards and tips.** `dashboards`, `tips` (EN + RU). Result: strict build 0; every title
   matches `grafana/dashboards/*.json` and `rail.json`; tips rules match `clickhouse/views.sql`.
4. **Maintenance, troubleshooting, data.** Result: strict build 0; commands match the scripts and
   compose file.
5. **Screenshots.** Demo data generator, throwaway stack (separate names and ports, no volumes,
   removed afterwards; the live stack untouched), screenshots at 1920 px into `docs/assets/`,
   placed on the pages. Result: strict build 0; images show only made-up data (checked by eye
   and by grep of the demo data).
6. **Release notes, README, publishing.** `release-1-0-0` (EN + RU) describing the current
   features; README shortened with a link to the site. The user enables Pages
   (Settings → Pages → Source: GitHub Actions) and merges; result: the deploy job publishes and
   the site opens at the Pages URL.
