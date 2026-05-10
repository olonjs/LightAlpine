import fs from 'node:fs';
import path from 'node:path';

const reportPath =
  process.argv[2] ||
  '//wsl.localhost/Ubuntu/home/dev/olon.it_2026-05-03_22-40-10.report.html';

const h = fs.readFileSync(reportPath, 'utf8');
const prefix = 'window.__LIGHTHOUSE_JSON__ = ';
const i = h.indexOf(prefix);
if (i < 0) {
  console.error('No __LIGHTHOUSE_JSON__ in file:', reportPath);
  process.exit(1);
}
const start = i + prefix.length;
const end = h.indexOf('</script>', start);
let s = h.slice(start, end).trim();
if (s.endsWith(';')) s = s.slice(0, -1);

const j = JSON.parse(s);
const perfScore = j.categories?.performance?.score;
console.log('URL:', j.requestedUrl);
console.log('Lighthouse:', j.lighthouseVersion);
console.log('Performance score:', perfScore != null ? Math.round(perfScore * 100) : 'n/a');

const core = [
  'first-contentful-paint',
  'largest-contentful-paint',
  'total-blocking-time',
  'cumulative-layout-shift',
  'speed-index',
  'interactive',
];
console.log('\n--- Core timings (display) ---');
for (const id of core) {
  const a = j.audits[id];
  if (!a) continue;
  console.log(id + ':', a.displayValue ?? String(a.numericValue), '| score:', a.score);
}

console.log('\n--- Audits con score < 1 e risparmio stimato (priorità) ---');
const skip = new Set([
  ...core,
  'max-potential-fid',
  'first-meaningful-paint',
  'estimated-input-latency',
  'metrics',
  'screenshot-thumbnails',
  'final-screenshot',
  'diagnostics',
  'network-requests',
  'network-rtt',
  'network-server-latency',
  'mainthread-work-breakdown',
  'bootup-time',
  'script-treemap-data',
  'resource-summary',
  'screenshots',
  'full-page-screenshot',
]);

const rows = [];
for (const [id, a] of Object.entries(j.audits || {})) {
  if (a.score === null || a.score === undefined || a.score >= 1) continue;
  if (skip.has(id)) continue;
  const ms = a.details?.overallSavingsMs ?? 0;
  const bytes = a.details?.overallSavingsBytes ?? 0;
  if (ms < 1 && bytes < 5000) continue;
  rows.push({ id, title: a.title, ms, bytes, score: a.score });
}
rows.sort((a, b) => (b.ms || 0) - (a.ms || 0) || (b.bytes || 0) - (a.bytes || 0));
for (const r of rows.slice(0, 15)) {
  console.log(
    `- [${r.id}] ${r.title} | ~${Math.round(r.ms)}ms JS equiv | ~${Math.round(r.bytes / 1024)} KiB | score ${r.score?.toFixed(2)}`,
  );
}

const outPath = path.join(path.dirname(reportPath), 'lh-summary.txt');
const lines = [];
lines.push(`URL: ${j.requestedUrl}`);
lines.push(`Performance: ${perfScore != null ? Math.round(perfScore * 100) : 'n/a'}`);
for (const id of core) {
  const a = j.audits[id];
  if (a) lines.push(`${id}: ${a.displayValue ?? a.numericValue} (score ${a.score})`);
}
for (const r of rows.slice(0, 20)) {
  lines.push(`OPP ${r.id}: ${r.title} | savingsMs=${Math.round(r.ms)} | savingsKiB=${Math.round(r.bytes / 1024)} | score=${r.score?.toFixed(3)}`);
}
fs.writeFileSync(outPath, lines.join('\n'), 'utf8');
console.log('\nWrote', outPath);
