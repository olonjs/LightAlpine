# ADR-001: Tenant theme CSS order and remote `@import` handling

## Status

Accepted

## Date

2026-05-03

## Context

Tenant styles are bundled from `fonts.css` and `index.css` (via `?inline`), then passed to `@olonjs/core` as `themeCss.tenant` and also injected into a `<style id="jp-theme-tenant">` block. Google Fonts are loaded with a leading `@import` of an `https://fonts.googleapis.com/...` stylesheet.

In production, two issues appeared:

1. **CSS `@import` rules must appear at the very beginning of a stylesheet** (before any other rules except `@charset` and empty `@layer`). If we prepend `:root { ... }` (theme font variables or flattened theme tokens) ahead of the tenant bundle, the browser **ignores** subsequent `@import` statements. Web fonts then never load, and typography falls back to system fonts.

2. **Bundlers minify `@import`** in ways that break naive parsers—for example `@import"https://..."` without `url(...)` and with no space after `@import`. A regex that only recognized `@import url('...')` failed to strip those imports into `<link rel="stylesheet">`, leaving invalid `@import` positions inside the injected block.

SSR (`entry-ssg.tsx`) concatenates flattened theme CSS with the tenant bundle; the same ordering bug applied there.

## Decision

1. **Single implementation** of `extractLeadingRemoteCssImports` in `src/lib/extractLeadingRemoteCssImports.ts`, imported by both `App.tsx` and `entry-ssg.tsx`. Patterns must cover minified forms: `@import` + optional whitespace + `url("...")` / `url('...')` / unquoted URL, and `@import"https://..."` / `@import'https://...'`.

2. **Concatenation order** when merging generated theme CSS with the tenant CSS remainder:
   - **Client (`App.tsx`):** `[tenantCssParts.rest, buildThemeFontVarsCss(themeConfig)]` so any `@import` that remains in `rest` stays at the top of the injected sheet; font variables follow.
   - **SSR (`getCss`):** `${rest}\n${themeCss}` so flattened `:root` theme variables never precede leading `@import` in `rest`.

3. **Promotion to `<link>`:** Leading remote `http(s)` imports are still extracted in the client and emitted as `<link rel="stylesheet" data-jp-tenant-remote-css>` in `document.head`, which avoids `@import` ordering constraints for those resources entirely when extraction succeeds.

## Alternatives Considered

### A. Only fix the regex, keep theme CSS before tenant CSS

Rejected: even with correct extraction, any `@import` left inside `rest` (e.g. future local imports) would still be invalid after prepended `:root` rules. Ordering must be correct regardless.

### B. Put Google Fonts only in `index.html` as static `<link>` tags

Pros: no parser or bundle-shape dependency.  
Cons: duplicates the font URL (must stay in sync with `theme.json` / `fonts.css`), easy to drift.  
Not chosen as the primary fix; could be added later as an optional hardening layer.

### C. Inline `@font-face` with self-hosted font files

Pros: no third-party `@import`, full control.  
Cons: larger repo, licensing/hosting overhead, out of scope for the immediate regression.

## Consequences

- Anyone changing how tenant CSS is assembled must **preserve** remote imports at the start of the string passed to `extractLeadingRemoteCssImports`, or rely on extraction + `<link>` injection.
- Changes to the minifier output may require extending `matchLeadingRemoteImport` if new `@import` syntax variants appear.
- Agents and humans should read this ADR before reordering `themeCss` / `resolvedTenantCss` or duplicating import-parsing logic.

## References

- CSS 2.1 / CSS Cascading: `@import` must precede other rules in a stylesheet.
- Implementation: `src/lib/extractLeadingRemoteCssImports.ts`, `src/App.tsx` (`resolvedTenantCss`, `tenantCssBundled`), `src/entry-ssg.tsx` (`getCss`, `getRemoteStylesheets`).
