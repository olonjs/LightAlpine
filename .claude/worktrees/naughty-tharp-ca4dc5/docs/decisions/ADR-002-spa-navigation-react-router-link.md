# ADR-002: Internal navigation uses React Router `Link`, not plain `<a>`

## Status

Accepted

## Date

2026-05-03

## Context

The tenant runs as a **single-page application (SPA)** behind React Router. Menu items, logo links, and CTAs in the global header are driven by configurable `href` strings (e.g. from JSON / CMS).

Using a plain **`<a href="/path">`** for in-app routes causes a **full document navigation**: the browser reloads the page, React state is torn down, and the user sees a flash plus unnecessary network cost. That contradicts SPA expectations and breaks smooth transitions (e.g. Framer Motion) tied to route changes.

## Decision

In `src/components/header/View.tsx`:

1. **`isInAppPathHref(href)`** classifies whether an `href` should be handled by the client router:
   - **In-app:** non-empty, trimmed string that **starts with `/`**, and is **not** an obvious non-document URL (`http:`, `https:`, `mailto:`, `tel:`, protocol-relative `//`, `javascript:`, `data:`).
   - **Not in-app:** everything else → render as **`<a href={...}>`** (or `<a>` with appropriate attributes for download/target when applicable elsewhere).

2. For in-app targets, use **`Link`** from `react-router-dom` (and **`motion(Link)`** where entrance/scroll-linked motion is required) with **`to={href}`**, so navigation is **client-side** (history API, no full reload).

3. Keep a **short inline comment** next to `isInAppPathHref` pointing to this ADR so future edits do not “simplify” everything back to `<a>`.

## Alternatives Considered

### A. Always use `<a>` and intercept clicks globally

Rejected: fragile (event ordering, middle-click, modifier keys, accessibility), harder to reason about than using the library’s `Link`.

### B. Always use `<Link>` for every menu item

Rejected: breaks legitimate **external** URLs if they are stored without a scheme, or special schemes; external links must remain real anchors for correct semantics and browser behavior (new tab, copy link, etc.).

### C. `<a href onClick={(e) => { e.preventDefault(); navigate(...) }}>`

Rejected: more boilerplate, duplicates router behavior, easier to mishandle keyboard and accessibility compared to `Link`.

## Consequences

- Content authors should use **root-relative paths** (`/about`, `/accommodations`) for internal pages so `isInAppPathHref` returns true.
- If the app is ever deployed under a **non-root base path**, this ADR should be revisited: `Link` must receive paths consistent with the router `basename`, and the heuristic may need to account for prefixed paths.
- Other components that render configurable `href` lists should follow the **same pattern** (or a shared helper) to avoid reintroducing full reloads.

## References

- Implementation: `src/components/header/View.tsx` — `isInAppPathHref`, `Link`, `MotionLink`.
