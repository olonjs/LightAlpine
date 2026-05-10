import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { webmcp } from '@olonjs/core';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, '..');
const { buildLlmsTxt } = webmcp;

const pagesDir = path.join(rootDir, 'src', 'data', 'pages');
const siteConfig = JSON.parse(fs.readFileSync(path.join(rootDir, 'src', 'data', 'config', 'site.json'), 'utf-8'));

function listJsonFilesRecursive(dir) {
  const items = fs.readdirSync(dir, { withFileTypes: true });
  const files = [];
  for (const item of items) {
    const fullPath = path.join(dir, item.name);
    if (item.isDirectory()) {
      files.push(...listJsonFilesRecursive(fullPath));
      continue;
    }
    if (item.isFile() && item.name.toLowerCase().endsWith('.json')) files.push(fullPath);
  }
  return files;
}

const pages = {};
for (const fullPath of listJsonFilesRecursive(pagesDir)) {
  const slug = path.relative(pagesDir, fullPath).replace(/\\/g, '/').replace(/\.json$/i, '');
  pages[slug] = JSON.parse(fs.readFileSync(fullPath, 'utf-8'));
}

const llmsTxt = buildLlmsTxt({ pages, schemas: {}, siteConfig });

const outPath = path.join(rootDir, 'public', 'llms.txt');
fs.writeFileSync(outPath, llmsTxt, 'utf-8');
console.log('[generate-llms-txt] Written -> public/llms.txt');
