import { renderToString } from 'react-dom/server';
import { StaticRouter } from 'react-router-dom/server';
import { ConfigProvider, PageRenderer, StudioProvider, resolveRuntimeConfig } from '@olonjs/core';
import type { JsonPagesConfig, PageConfig, SiteConfig, ThemeConfig } from '@/types';
import { ThemeProvider } from '@/components/ThemeProvider';
import { ComponentRegistry } from '@/lib/ComponentRegistry';
import { SECTION_SCHEMAS } from '@/lib/schemas';
import { menuConfig, pages, refDocuments, siteConfig, themeConfig } from '@/runtime';
import tenantRemoteCss from '@/fonts.css?inline';
import tenantCss from '@/index.css?inline';
import { extractLeadingRemoteCssImports } from '@/lib/extractLeadingRemoteCssImports';

const tenantCssBundled = `${tenantRemoteCss}\n${tenantCss}`;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function normalizeSlug(input: string): string {
  return input.trim().toLowerCase().replace(/\\/g, '/').replace(/^\/+|\/+$/g, '');
}

function getSortedSlugs(): string[] {
  return Object.keys(pages).sort((a, b) => a.localeCompare(b));
}

function resolvePage(slug: string): { slug: string; page: PageConfig } {
  const normalized = normalizeSlug(slug);
  if (normalized && pages[normalized]) {
    return { slug: normalized, page: pages[normalized] };
  }

  const slugs = getSortedSlugs();
  if (slugs.length === 0) {
    throw new Error('[SSG_CONFIG_ERROR] No pages found under src/data/pages');
  }

  const home = slugs.find((item) => item === 'home');
  const fallbackSlug = home ?? slugs[0];
  return { slug: fallbackSlug, page: pages[fallbackSlug] };
}

function flattenThemeTokens(
  input: unknown,
  pathSegments: string[] = [],
  out: Array<{ name: string; value: string }> = []
): Array<{ name: string; value: string }> {
  if (typeof input === 'string') {
    const cleaned = input.trim();
    if (cleaned.length > 0 && pathSegments.length > 0) {
      out.push({ name: `--theme-${pathSegments.join('-')}`, value: cleaned });
    }
    return out;
  }

  if (!isRecord(input)) return out;

  const entries = Object.entries(input).sort(([a], [b]) => a.localeCompare(b));
  for (const [key, value] of entries) {
    flattenThemeTokens(value, [...pathSegments, key], out);
  }
  return out;
}

function buildThemeCssFromSot(theme: ThemeConfig): string {
  const root: Record<string, unknown> = isRecord(theme) ? theme : {};
  const tokens = root['tokens'];
  const flattened = flattenThemeTokens(tokens);
  if (flattened.length === 0) return '';
  const serialized = flattened.map((item) => `${item.name}:${item.value}`).join(';');
  return `:root{${serialized}}`;
}

function resolveTenantId(): string {
  const site: Record<string, unknown> = isRecord(siteConfig) ? siteConfig : {};
  const identityRaw = site['identity'];
  const identity: Record<string, unknown> = isRecord(identityRaw) ? identityRaw : {};
  const titleRaw = typeof identity.title === 'string' ? identity.title : '';
  const title = titleRaw.trim();
  if (title.length > 0) {
    const normalized = title.toLowerCase().replace(/[^a-z0-9-]+/g, '-').replace(/^-+|-+$/g, '');
    if (normalized.length > 0) return normalized;
  }

  const slugs = getSortedSlugs();
  if (slugs.length === 0) {
    throw new Error('[SSG_CONFIG_ERROR] Cannot resolve tenantId without site.identity.title or pages');
  }
  return slugs[0].replace(/\//g, '-');
}

export function render(slug: string): string {
  const resolved = resolvePage(slug);
  const location = resolved.slug === 'home' ? '/' : `/${resolved.slug}`;
  const resolvedRuntime = resolveRuntimeConfig({
    pages,
    siteConfig,
    themeConfig,
    menuConfig,
    refDocuments,
  });
  const resolvedPage = resolvedRuntime.pages[resolved.slug] ?? resolved.page;

  return renderToString(
    <StaticRouter location={location}>
      <ConfigProvider
        config={{
          registry: ComponentRegistry as JsonPagesConfig['registry'],
          schemas: SECTION_SCHEMAS as unknown as JsonPagesConfig['schemas'],
          tenantId: resolveTenantId(),
        }}
      >
        <StudioProvider mode="visitor">
          <ThemeProvider>
            <PageRenderer
              pageConfig={resolvedPage}
              siteConfig={resolvedRuntime.siteConfig}
              menuConfig={resolvedRuntime.menuConfig}
            />
          </ThemeProvider>
        </StudioProvider>
      </ConfigProvider>
    </StaticRouter>
  );
}

/** Tenant bundle first so any leading @import stays valid; theme flatten after (ADR-001). */
export function getCss(): string {
  const themeCss = buildThemeCssFromSot(themeConfig);
  const { rest } = extractLeadingRemoteCssImports(tenantCssBundled);
  if (!themeCss) return rest;
  return `${rest}\n${themeCss}`;
}

export function getRemoteStylesheets(): string[] {
  return extractLeadingRemoteCssImports(tenantCssBundled).hrefs;
}

export function getPageMeta(slug: string): { title: string; description: string } {
  const resolved = resolvePage(slug);
  const rawMeta = isRecord((resolved.page as unknown as { meta?: unknown }).meta)
    ? ((resolved.page as unknown as { meta?: Record<string, unknown> }).meta as Record<string, unknown>)
    : {};

  const title = typeof rawMeta.title === 'string' ? rawMeta.title : resolved.slug;
  const description = typeof rawMeta.description === 'string' ? rawMeta.description : '';
  return { title, description };
}

export function getWebMcpBuildState(): {
  pages: Record<string, PageConfig>;
  schemas: JsonPagesConfig['schemas'];
  siteConfig: SiteConfig;
} {
  return {
    pages,
    schemas: SECTION_SCHEMAS as unknown as JsonPagesConfig['schemas'],
    siteConfig,
  };
}

