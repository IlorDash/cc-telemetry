#!/usr/bin/env node
// Builds the Russian copies grafana/dashboards/ru/<file>.json from the English dashboards and the
// dictionary grafana/i18n/ru.json.
// Usage (no dependencies; any folder):  node grafana/i18n/build-ru.js [--check]
//   (no flag)  write the RU files that differ from what the generator produces
//   --check    write nothing; exit 1 if any RU file differs
// Pipeline after editing an English dashboard: node grafana/rail/sync-rail.js, then this script.
// Strict: a translatable string without a dictionary entry -> exit 1 with the list, nothing written.
// Dictionary entries that no file uses -> warning. Idempotent: a second run changes nothing.
//
// ru.json: { "files": ["overview.json", ...], "strings": { "English": "Russian", ... } }
//   files    = the English dashboards that get a RU copy (top-level files of grafana/dashboards/)
//   strings  = one flat map; text of text panels is looked up node by node (text between tags, trimmed)
// Translated (allowlist): dashboard title; timepicker quick range display; variable label; panel
// title and description; displayName (defaults and overrides, and options.sortBy[].displayName, which
// must equal the column's translated name); title of panel links and data links; text nodes of text
// panels (HTML by tag, markdown by line / table cell). Everything else (SQL, ids, ${...}, markup) is copied as it is.
// Also translated: panel/field noValue (when it has a letter), value-mapping texts (type value /
// special / range: only "text"; matched values stay), custom variable options (query text parts,
// options[].text, current.text; values stay).
// SQL (RU copy only; panel targets[].rawSql and variable query/definition), from ru.json "sql":
//   "literals":  { "<text between the quotes>": "<Russian>" }  every quoted literal that equals the key
//                is replaced as a whole; a literal that is not listed stays (filters, ids, event names)
//   "fragments": { "<exact SQL text>": "<replacement SQL text>" }  for what a literal cannot do
//                (plurals: reorder to "label: N"; the tips link rewrite to /d/<uid>-ru); applied first
//   Strict: a literal or fragment that no RU file uses -> exit 1 (stale entry or changed SQL).
// A fixed-width table column whose header or value-mapping text got longer in Russian is widened to fit
// it (8 px per letter + 40 for a header, + 25 for a cell).
// RU copy: uid <uid>-ru, same panel ids; every /d/<uid> link to a dashboard that has a RU copy
// becomes /d/<uid>-ru; the EN/RU switch link (links[]) points back to the English dashboard.
const fs = require("fs");
const path = require("path");

const check = process.argv.includes("--check");
const dashDir = path.resolve(__dirname, "..", "dashboards");
const ruDir = path.join(dashDir, "ru");
const dict = JSON.parse(fs.readFileSync(path.join(__dirname, "ru.json"), "utf8"));
const strings = dict.strings;

const sqlLit = (dict.sql && dict.sql.literals) || {};
const sqlFrag = (dict.sql && dict.sql.fragments) || {};
const sqlUsed = new Set();
const has = (o, k) => Object.prototype.hasOwnProperty.call(o, k);

const SWITCH_TOOLTIP_RU = "Английская версия";

const used = new Set();
const missing = new Set();

// Dictionary lookup of one string; records usage / absence.
function tr(s) {
  if (typeof s !== "string" || s.trim() === "") return s;
  if (!/[A-Za-z]/.test(s.replace(/\$\{[^}]*\}|\$\w+/g, ""))) return s; // only $var / ${...} / symbols: nothing to translate
  if (Object.prototype.hasOwnProperty.call(strings, s)) {
    used.add(s);
    return strings[s];
  }
  missing.add(s);
  return s;
}

const decode = (s) => s.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&amp;/g, "&");
const encode = (s) =>
  s.replace(/&(?!(?:[a-zA-Z]+|#\d+);)/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

// A text node is translated when it has a letter outside ${...}.
function trNode(raw) {
  const m = raw.match(/^(\s*)([\s\S]*?)(\s*)$/);
  if (m[2] === "" || !/[A-Za-z]/.test(m[2].replace(/\$\{[^}]*\}/g, ""))) return raw;
  return m[1] + encode(tr(decode(m[2]))) + m[3];
}

function trHtml(content) {
  return content
    .split(/(<[^>]*>)/)
    .map((part, i) => (i % 2 === 0 ? trNode(part) : part))
    .join("");
}

// Markdown text panel: a line is looked up as a whole; a table row ("| a | b |") cell by cell (trimmed).
function trMdText(raw) {
  const m = raw.match(/^(\s*)([\s\S]*?)(\s*)$/);
  if (m[2] === "" || !/[A-Za-z]/.test(m[2])) return raw;
  return m[1] + tr(m[2]) + m[3];
}
function trMd(content) {
  return content
    .split("\n")
    .map((line) => (line.trimStart().startsWith("|") ? line.split("|").map(trMdText).join("|") : trMdText(line)))
    .join("\n");
}

// Source dashboards that have a RU copy: uid -> true
const srcFiles = dict.files;
const ruUids = new Set();
const sources = srcFiles.map((file) => {
  const dash = JSON.parse(fs.readFileSync(path.join(dashDir, file), "utf8"));
  ruUids.add(dash.uid);
  return { file, dash };
});

// /d/<uid> of a dashboard with a RU copy -> /d/<uid>-ru
const relink = (url) =>
  url.replace(/\/d\/([A-Za-z0-9_-]+)/g, (m, uid) => (ruUids.has(uid) ? "/d/" + uid + "-ru" : m));

// SQL labels: fragments first, then whole quoted literals (a literal is never matched inside another one)
function trSql(sql) {
  if (typeof sql !== "string") return sql;
  let s = sql;
  for (const k of Object.keys(sqlFrag)) {
    if (s.includes(k)) {
      sqlUsed.add("fragment " + JSON.stringify(k));
      s = s.split(k).join(sqlFrag[k]);
    }
  }
  return s.replace(/'((?:[^'\\]|\\[\s\S]|'')*)'/g, (m, c) => {
    if (!has(sqlLit, c)) return m;
    sqlUsed.add("literal " + JSON.stringify(c));
    return "'" + sqlLit[c] + "'";
  });
}

// value mappings: only the display text is translated; the matched values and colours stay
function trMappings(list) {
  for (const m of list || []) {
    const o = m.options || {};
    if (m.type === "value") {
      for (const k of Object.keys(o)) if (o[k] && o[k].text) o[k].text = tr(o[k].text);
    } else if (o.result && o.result.text) {
      o.result.text = tr(o.result.text);
    }
  }
}

// display texts of value mappings (the same places trMappings translates)
function mappingTexts(list) {
  const out = [];
  for (const m of list || []) {
    const o = m.options || {};
    if (m.type === "value") {
      for (const k of Object.keys(o)) if (o[k] && o[k].text) out.push(o[k].text);
    } else if (o.result && o.result.text) out.push(o.result.text);
  }
  return out;
}

function trLinks(list) {
  for (const l of list || []) {
    if (l.title) l.title = tr(l.title);
    if (l.url) l.url = relink(l.url);
  }
}

function trPanel(p) {
  if (p.title) p.title = tr(p.title);
  if (p.description) p.description = tr(p.description);
  trLinks(p.links);
  for (const t of p.targets || []) if (t.rawSql) t.rawSql = trSql(t.rawSql);
  // table sort refers to the column by its display name, so it follows the translated displayName
  for (const s of (p.options && p.options.sortBy) || []) if (s.displayName) s.displayName = tr(s.displayName);
  const fc = p.fieldConfig;
  if (fc) {
    if (fc.defaults) {
      if (fc.defaults.displayName) fc.defaults.displayName = tr(fc.defaults.displayName);
      if (fc.defaults.noValue) fc.defaults.noValue = tr(fc.defaults.noValue);
      trMappings(fc.defaults.mappings);
      trLinks(fc.defaults.links);
    }
    for (const o of fc.overrides || []) {
      let before = null; // the English column name, to see whether the header got longer
      const mapTexts = []; // mapping texts that changed in translation (cells can get longer too)
      for (const prop of o.properties || []) {
        if (prop.id === "displayName") {
          before = prop.value;
          prop.value = tr(prop.value);
        } else if (prop.id === "noValue") prop.value = tr(prop.value);
        else if (prop.id === "mappings") {
          const en = JSON.stringify(prop.value);
          trMappings(prop.value);
          if (JSON.stringify(prop.value) !== en) mapTexts.push(...mappingTexts(prop.value));
        }
        else if (prop.id === "links") trLinks(prop.value);
      }
      // table column with a fixed width: widen it when the translated header or a translated mapping text
      // would be cut (~8 px per letter; a header also needs the sort arrow and padding, a cell only padding)
      const dn = (o.properties || []).find((x) => x.id === "displayName");
      const w = (o.properties || []).find((x) => x.id === "custom.width");
      if (p.type === "table" && w) {
        let need = 0;
        if (dn && dn.value !== before) need = dn.value.length * 8 + 40;
        for (const t of mapTexts) need = Math.max(need, t.length * 8 + 25);
        need = Math.ceil(need / 5) * 5;
        if (w.value < need) w.value = need;
      }
    }
  }
  if (p.type === "text" && p.options && typeof p.options.content === "string") {
    p.options.content = p.options.mode === "markdown" ? trMd(relink(p.options.content)) : trHtml(relink(p.options.content));
  }
  for (const sub of p.panels || []) trPanel(sub);
}

// Custom variable: query is "text : value,text : value"; options[].text and current.text follow; values stay.
function trCustomVar(v) {
  if (typeof v.query === "string") {
    v.query = v.query
      .split(",")
      .map((part) => {
        const i = part.lastIndexOf(" : ");
        return i < 0 ? tr(part) : tr(part.slice(0, i)) + part.slice(i);
      })
      .join(",");
  }
  for (const o of v.options || []) o.text = tr(o.text);
  if (v.current && v.current.text !== undefined) {
    v.current.text = Array.isArray(v.current.text) ? v.current.text.map((t) => tr(t)) : tr(v.current.text);
  }
}

// The language switch on an English dashboard: type "link", title "RU", url /d/<any uid>-ru (any, so a
// switch left over from a renamed uid is still recognised and replaced). The title is checked too, so a
// hand-added plain link (other title, url without -ru, query params) is kept; a hand-edited switch title
// cannot be recognised by design. Same rule as in grafana/rail/sync-rail.js - keep the two in sync.
const isSwitch = (l) => !!l && l.type === "link" && l.title === "RU" && /^\/d\/[A-Za-z0-9_-]+-ru$/.test(l.url);

function build(src) {
  const dash = JSON.parse(JSON.stringify(src.dash));
  const enUid = dash.uid;
  dash.uid = enUid + "-ru";
  dash.title = tr(dash.title);
  for (const q of (dash.timepicker && dash.timepicker.quick_ranges) || []) q.display = tr(q.display);
  for (const v of (dash.templating && dash.templating.list) || []) {
    if (v.label && v.label !== v.name) v.label = tr(v.label); // label == name: hidden technical variable
    if (v.type === "custom") trCustomVar(v);
    if (v.type === "query") {
      v.query = trSql(v.query);
      if (v.definition) v.definition = trSql(v.definition);
    }
  }
  trLinks(dash.links.filter((l) => !isSwitch(l)));
  dash.links = [
    ...dash.links.filter((l) => !isSwitch(l)),
    { type: "link", title: "EN", tooltip: SWITCH_TOOLTIP_RU, url: "/d/" + enUid, keepTime: true, includeVars: true },
  ];
  for (const p of dash.panels) trPanel(p);
  return JSON.stringify(dash, null, 2) + "\n";
}

const results = sources.map((s) => ({ file: s.file, out: build(s) }));

if (missing.size > 0) {
  console.error("Missing translations (add them to grafana/i18n/ru.json \"strings\"):");
  for (const s of [...missing].sort()) console.error("  " + JSON.stringify(s));
  console.error(missing.size + " string(s) missing; nothing written");
  process.exit(1);
}

const sqlUnused = [
  ...Object.keys(sqlLit).map((k) => "literal " + JSON.stringify(k)),
  ...Object.keys(sqlFrag).map((k) => "fragment " + JSON.stringify(k)),
].filter((k) => !sqlUsed.has(k));
if (sqlUnused.length > 0) {
  console.error("ru.json \"sql\" entries found in no RU file (the SQL changed, or a typo); nothing written:");
  for (const k of sqlUnused) console.error("  " + k);
  process.exit(1);
}

for (const k of Object.keys(strings)) {
  if (!used.has(k)) console.warn("warning: unused dictionary entry " + JSON.stringify(k));
}
if (fs.existsSync(ruDir)) {
  for (const f of fs.readdirSync(ruDir).filter((f) => f.endsWith(".json")))
    if (!srcFiles.includes(f)) console.warn("warning: ru/" + f + " is not in ru.json \"files\" (stale?)");
}

let differs = 0;
for (const r of results) {
  const full = path.join(ruDir, r.file);
  const before = fs.existsSync(full) ? fs.readFileSync(full, "utf8") : null;
  if (before === r.out) {
    console.log("unchanged  ru/" + r.file);
    continue;
  }
  differs++;
  if (check) {
    console.log("DIFFERS    ru/" + r.file);
  } else {
    fs.mkdirSync(ruDir, { recursive: true });
    fs.writeFileSync(full, r.out);
    console.log("updated    ru/" + r.file);
  }
}

if (check && differs > 0) {
  console.error(differs + " RU dashboard(s) differ: run node grafana/i18n/build-ru.js");
  process.exit(1);
}
