#!/usr/bin/env node
/**
 * Extract Lighthouse embedded JSON from HTML (one-line __LIGHTHOUSE_JSON__).
 * Brace/bracket depth with JSON string awareness — no fragile </script> slice.
 */
import fs from "node:fs";
import path from "node:path";

function endOfJsonValue(s, start) {
  if (s[start] !== "{") throw new Error("expected { at start");
  let depth = 1;
  let inString = false;
  let escape = false;
  for (let i = start + 1; i < s.length; i++) {
    const c = s[i];
    if (inString) {
      if (escape) {
        escape = false;
        continue;
      }
      if (c === "\\") {
        escape = true;
        continue;
      }
      if (c === '"') {
        inString = false;
        continue;
      }
      continue;
    }
    if (c === '"') {
      inString = true;
      continue;
    }
    if (c === "{" || c === "[") depth++;
    else if (c === "}" || c === "]") {
      depth--;
      if (depth === 0) return i + 1;
    }
  }
  throw new Error("unclosed JSON");
}

const report = path.resolve(process.argv[2] || "");
const outPath = process.argv[3] || path.join(path.dirname(report), "lh-summary.txt");
if (!report) {
  console.error("usage: node scan-lh-json.mjs <report.html> [out.txt]");
  process.exit(1);
}

const text = fs.readFileSync(report, "utf8");
const key = "window.__LIGHTHOUSE_JSON__ = ";
const ki = text.indexOf(key);
if (ki < 0) {
  console.error("missing", key);
  process.exit(1);
}
const jsonStart = text.indexOf("{", ki);
const jsonEnd = endOfJsonValue(text, jsonStart);
const data = JSON.parse(text.slice(jsonStart, jsonEnd));

const perf = data.categories?.performance?.score;
const audits = data.audits || {};
const core = [
  "first-contentful-paint",
  "largest-contentful-paint",
  "total-blocking-time",
  "cumulative-layout-shift",
  "speed-index",
  "interactive",
];

const lines = [];
lines.push(`URL: ${data.requestedUrl}`);
lines.push(`Lighthouse: ${data.lighthouseVersion}`);
lines.push(
  `Performance score: ${typeof perf === "number" ? Math.round(perf * 100) : "n/a"}`
);
lines.push("");
lines.push("--- Core ---");
for (const aid of core) {
  const a = audits[aid] || {};
  lines.push(
    `${aid}: ${a.displayValue ?? a.numericValue ?? ""} | score ${a.score}`
  );
}

const skip = new Set([
  ...core,
  "max-potential-fid",
  "metrics",
  "screenshot-thumbnails",
  "final-screenshot",
  "diagnostics",
  "network-requests",
  "network-rtt",
  "network-server-latency",
  "mainthread-work-breakdown",
  "bootup-time",
  "script-treemap-data",
  "resource-summary",
  "screenshots",
  "full-page-screenshot",
]);

const rows = [];
for (const [aid, a] of Object.entries(audits)) {
  if (skip.has(aid)) continue;
  const sc = a.score;
  if (sc == null || sc >= 1) continue;
  const det = a.details || {};
  const ms = Number(det.overallSavingsMs || 0);
  const b = Number(det.overallSavingsBytes || 0);
  if (ms < 1 && b < 5000) continue;
  rows.push([ms, b, aid, a.title || aid, sc]);
}
rows.sort((x, y) => y[0] - x[0] || y[1] - x[1]);
lines.push("");
lines.push("--- Opportunities (top) ---");
for (const [ms, b, aid, title, sc] of rows.slice(0, 18)) {
  lines.push(
    `[${aid}] ${title} | ~${Math.round(ms)}ms | ~${Math.round(b / 1024)} KiB | score ${Number(sc).toFixed(3)}`
  );
}

const out = lines.join("\n") + "\n";
fs.writeFileSync(outPath, out, "utf8");
process.stdout.write(out);
