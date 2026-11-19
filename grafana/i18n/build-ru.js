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
// title and description; displayName (defaults and overrides); title of panel links and data links;
// text nodes of text panels. Everything else (SQL, ids, ${...}, markup) is copied as it is.
// RU copy: uid <uid>-ru, same panel ids; every /d/<uid> link to a dashboard that has a RU copy
// becomes /d/<uid>-ru; the EN/RU switch link (links[]) points back to the English dashboard.
const fs = require("fs");
const path = require("path");

const check = process.argv.includes("--check");
const dashDir = path.resolve(__dirname, "..", "dashboards");
const ruDir = path.join(dashDir, "ru");
const dict = JSON.parse(fs.readFileSync(path.join(__dirname, "ru.json"), "utf8"));
const strings = dict.strings;

const SWITCH_TOOLTIP_RU = "English version";

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
  const fc = p.fieldConfig;
  if (fc) {
    if (fc.defaults) {
      if (fc.defaults.displayName) fc.defaults.displayName = tr(fc.defaults.displayName);
      trLinks(fc.defaults.links);
    }
    for (const o of fc.overrides || []) {
      for (const prop of o.properties || []) {
        if (prop.id === "displayName") prop.value = tr(prop.value);
        else if (prop.id === "links") trLinks(prop.value);
      }
    }
  }
  if (p.type === "text" && p.options && typeof p.options.content === "string") {
    p.options.content = trHtml(relink(p.options.content));
  }
  for (const sub of p.panels || []) trPanel(sub);
}

const isSwitch = (l) => l && l.type === "link" && /^\/d\/[A-Za-z0-9_-]+$/.test(l.url || "");

function build(src) {
  const dash = JSON.parse(JSON.stringify(src.dash));
  const enUid = dash.uid;
  dash.uid = enUid + "-ru";
  dash.title = tr(dash.title);
  for (const q of (dash.timepicker && dash.timepicker.quick_ranges) || []) q.display = tr(q.display);
  for (const v of (dash.templating && dash.templating.list) || []) if (v.label && v.label !== v.name) v.label = tr(v.label); // label == name: hidden technical variable
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
