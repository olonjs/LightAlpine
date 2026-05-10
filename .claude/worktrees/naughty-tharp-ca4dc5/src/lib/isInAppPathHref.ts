/**
 * Returns true when `href` should be handled by the client-side router
 * (React Router `<Link>`), false when it must remain a real `<a>`.
 *
 * In-app: non-empty, trimmed, starts with `/`, no scheme prefix.
 * External: http/https, mailto, tel, protocol-relative, javascript, data URIs.
 *
 * @see docs/decisions/ADR-002-spa-navigation-react-router-link.md
 */
export function isInAppPathHref(href: string | undefined | null): boolean {
  if (!href) return false;
  const t = href.trim();
  if (!t) return false;
  const lower = t.toLowerCase();
  if (
    lower.startsWith('http://')
    || lower.startsWith('https://')
    || lower.startsWith('mailto:')
    || lower.startsWith('tel:')
    || lower.startsWith('//')
    || lower.startsWith('javascript:')
    || lower.startsWith('data:')
  ) {
    return false;
  }
  return t.startsWith('/');
}
