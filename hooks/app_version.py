"""MkDocs hook: stamp the version from the VERSION file on the site.

The version lives in exactly one place (VERSION at the repo root) and is read at
build time, so `mkdocs serve` shows the same version the pipeline publishes.

- appends " v<version>" to the site title, so every page states which release it
  documents;
- replaces `{{ app_version }}` in every Markdown page;
- sets config.copyright to "cc-telemetry v<version>" (no translatable text, so it
  reads the same in both language trees).
"""

import re
from pathlib import Path

from mkdocs.exceptions import PluginError

_VERSION_FILE = Path(__file__).resolve().parent.parent / "VERSION"
_PLACEHOLDER = re.compile(r"\{\{\s*app_version\s*\}\}")


def _read_version():
    try:
        version = _VERSION_FILE.read_text(encoding="utf-8").strip()
    except OSError as exc:
        raise PluginError(f"cannot read {_VERSION_FILE}: {exc}") from exc
    if not version:
        raise PluginError(f"{_VERSION_FILE} is empty")
    return version


def on_config(config):
    config.copyright = f"cc-telemetry v{_read_version()}"
    return config


def on_page_markdown(markdown, page, config, files):
    return _PLACEHOLDER.sub(_read_version(), markdown)


def on_page_context(context, page, config, nav):
    # Appended here, not in on_config: mkdocs-static-i18n replaces site_name with
    # the per-language one after the config event, so on_config would reach the
    # English tree only. The same config object is reused for every page of a
    # language, hence the guard against appending twice.
    suffix = f" v{_read_version()}"
    if not config.site_name.endswith(suffix):
        config.site_name += suffix
    return context
