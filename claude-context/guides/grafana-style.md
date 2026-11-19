# Grafana style guide — how panels look

One look for every dashboard. Read before adding or changing a panel; it wins over the design
mock where they differ. Layout rules (grid, rail) are here too; JSON editing rules are in
`conventions.md`.

## What Grafana lets us set

- **Fixed by the theme, not per panel:** panel title font and size, table cell font and size,
  axis and legend font, the ⓘ description icon. Do not try to change them (no CSS injection).
- **Per panel:** stat and bar gauge text sizes (`options.text.titleSize` / `valueSize`), table
  `cellHeight`, column width and alignment, colours, units, decimals.
- Text panels render HTML, but the sanitizer strips `line-height`, `overflow` and scripts.

## Grid

- Rail at x0 w3 (ids 300–399, synced by `grafana/rail/sync-rail.js`); content at x3, w21.
- One grid unit is about 38 px high. Supported screens: Full HD (1920 px) and wider; check
  every layout at 1920 px. Narrower windows (1280 px) are not supported (user's decision).
- Panels in one row have the same `y` and `h`; rows have no gaps.
- **No scroll in fixed-size panels:** a panel whose row count does not depend on the data
  (static list, fixed categories, `LIMIT n`, markdown) is tall enough to show everything at
  1920 px, sized for the full set. Data-dependent tables may scroll.
- Do not leave a large empty area inside a panel to match a neighbour; rearrange instead.

## Titles and descriptions

- **Title = name**, optionally `· <action hint>` when the panel is clickable:
  `Sessions · click a row to open its timeline`. One hint at most, lower case after `·`.
- Everything else — what the numbers mean, the scope ("7 days", "time range"), how rows are
  sorted, definitions — goes into `description` (the ⓘ tooltip).
- Units in titles only when the name is the metric itself (`cost_usd`, `Median cost_usd`).
- **Dashboard hint row:** the first content panel is a text panel x3 y0 w21 h1, transparent,
  the hint in its title, empty content.
- **Section header:** the same kind of text panel (h1, transparent, title only), as
  `Name · scope note` when the section ignores the time range or variables.

## Stat tiles (one number)

Common options: `textMode value_and_name`, `colorMode value`, `graphMode none`,
`justifyMode auto`, `wideLayout false`, `orientation vertical`. The caption line comes from the
query (display name), sits above the number; Grafana centres the content vertically.

| Level | Where | `titleSize` / `valueSize` | `h` |
| --- | --- | --- | --- |
| Main | the KPI row at the top of a dashboard or section | 13 / 42 | 4 |
| Secondary | details of one selected item (e.g. the selected session) | 13 / 30 | 3 |

- A KPI row is 4 tiles: w5, w5, w5, w6 (5 tiles: w4 ×4 + w5).
- **Exception (user's decision):** Efficiency Tips (w3) and Affected (w4) share a row with
  Affected tokens by category (w14), which needs h8 to show all five categories. So these two
  tiles keep their own design, outside the levels above: h8, `titleSize 15`, `valueSize 56`, no `wideLayout`, and the scope in
  the title (`Tips · 7d`, `Affected · 7d`).
- Colour: a fixed colour or thresholds on the value, never `background`.
- Units: money `currencyUSD` 2 decimals; counts `locale` 0 decimals; tokens `short` 1–2
  decimals; rates `percent`; durations `s` (Grafana scales to min / h).

## Horizontal bars (bar gauge)

- `displayMode gradient` (solid look; `basic` is translucent), `orientation horizontal`,
  `valueMode text`, `showUnfilled true`.
- `namePlacement top`, `titleSize 15`, `valueSize 14`, `sizing manual`,
  `minVizHeight 16`, `maxVizHeight 34`.
- Per-row colour or unit: a column from the query plus `rowsToFields`. The name text itself
  cannot be coloured.
- Size the panel for the full set of bars (no-scroll rule).

## Tables

- `cellHeight sm`, header on, `minWidth 50`, column filters off (`filterable false`: the filter
  icon eats header width and cuts names in narrow columns). No row background colours (`applyToRow` repaints
  every cell's text).
- Columns, left to right: the main name (link), text columns, numbers. Numbers right-aligned
  with a fixed `width` (70–100); the name column gets `minWidth` and takes the rest.
- Dates: unit `time:MM-DD HH:mm`, width 130, grey text.
- Secondary text (ids, dates, notes): `color-text` with `#8e8e9e`.
- A value bar inside a cell: `gauge` with `mode gradient`, fixed colour `#5794F2`.
- Rates with good / bad levels: `color-text` with thresholds `#F2495C` → `#FADE2A` → `#73BF69`.
- Links use Grafana's default link colour; a selected row is marked with `▶ ` in the name.
- Hidden helper fields (`sid`, `from_ms`, `to_ms`, `open`): `custom.hidden true`.

## Charts

- Time series: legend at the bottom as a list; money on a `currencyUSD` axis; a second
  metric goes on the right axis.
- Vertical bar charts: `barWidth 0.8`, `showValue always`, legend off when there is one series.
  With values on the bars, hide the y axis (`axisPlacement hidden`). Axis labels must not overlap: short labels from the query, or a wider panel.
- State timeline: `rowHeight 0.8`, `showValue never`, legend off.
- Pie / donut: legend on the right with values.

## Colours

| Meaning | Colour |
| --- | --- |
| Opus / Main · API | `#B877D9` |
| Sonnet, money bars, gauges | `#5794F2` |
| Haiku, ok | `#73BF69` |
| Branch, subagents | `#FF9830` |
| Warning | `#FADE2A` |
| Error | `#F2495C` |
| Secondary text | `#8e8e9e` |

Use the same colour for the same thing on every dashboard (a model, a phase, a tip category).
