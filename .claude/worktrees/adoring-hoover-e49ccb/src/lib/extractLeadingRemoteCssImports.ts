/**
 * Pulls leading remote @import rules off tenant CSS so the client can inject them as <link rel="stylesheet">.
 *
 * Bundlers may minify to forms like `@import"https://..."` (no `url(`). If this fails to match, remote imports
 * can end up after other rules in the injected sheet and browsers will ignore them (fonts break).
 *
 * @see docs/decisions/ADR-001-tenant-remote-fonts-and-css-import-order.md
 */

function isRemoteStylesheetHref(value: string): boolean {
  return /^https?:\/\//i.test(value.trim());
}

type ImportHit = { href: string; consumed: number };

function matchLeadingRemoteImport(rest: string): ImportHit | null {
  const patterns: RegExp[] = [
    /^@import\s*url\(\s*(['"])(https?:\/\/[^'"]+)\1\s*\)\s*;/i,
    /^@import\s*url\(\s*(https?:\/\/[^)\s]+)\s*\)\s*;/i,
    /^@import\s*(['"])(https?:\/\/[^'"]+)\1\s*;/i,
  ];

  for (const re of patterns) {
    const m = rest.match(re);
    if (!m) continue;
    const href = (m[2] ?? m[1] ?? '').trim();
    if (isRemoteStylesheetHref(href)) {
      return { href, consumed: m[0].length };
    }
  }
  return null;
}

export function extractLeadingRemoteCssImports(cssText: string): { hrefs: string[]; rest: string } {
  const hrefs = new Set<string>();
  const leadingTriviaPattern = /^(?:\s+|\/\*[\s\S]*?\*\/)*/;
  let rest = cssText;

  for (;;) {
    const trivia = rest.match(leadingTriviaPattern);
    if (trivia?.[0]) {
      rest = rest.slice(trivia[0].length);
    }

    const hit = matchLeadingRemoteImport(rest);
    if (!hit) break;

    hrefs.add(hit.href);
    rest = rest.slice(hit.consumed);
  }

  return { hrefs: Array.from(hrefs), rest };
}
