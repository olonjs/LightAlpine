#!/bin/bash
set -e # Termina se c'è un errore

echo "Inizio ricostruzione progetto..."

mkdir -p "src"
echo "Creating src/App.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/App.tsx"
/**
 * Thin Entry Point (Tenant).
 * Data from getHydratedData (file-backed or draft); assets from public/assets/images.
 * Supports Hybrid Persistence: Local Filesystem (Dev) or Cloud Bridge (Prod).
 */
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { JsonPagesEngine } from '@olonjs/core';
import type { JsonPagesConfig, LibraryImageEntry, ProjectState } from '@olonjs/core';
import { normalizeBasePath, withBasePath } from '@olonjs/core';
import { ComponentRegistry } from '@/lib/ComponentRegistry';
import { SECTION_SCHEMAS, SECTION_SUBMISSION_SCHEMAS } from '@/lib/schemas';
import { addSectionConfig } from '@/lib/addSectionConfig';
import { getHydratedData } from '@/lib/draftStorage';
import type { SiteConfig, ThemeConfig, MenuConfig, PageConfig } from '@/types';
import type { DeployPhase, StepId } from '@olonjs/core';
import { DEPLOY_STEPS } from '@olonjs/core';
import { startCloudSaveStream } from '@olonjs/core';
import siteData from '@/data/config/site.json';
import themeData from '@/data/config/theme.json';
import menuData from '@/data/config/menu.json';
import { getFilePages } from '@/lib/getFilePages';
import { DopaDrawer } from '@/components/save-drawer/DopaDrawer';
import { EmptyTenantView } from '@/components/empty-tenant';
import { Skeleton } from '@/components/ui/skeleton';
import { ThemeProvider } from '@/components/ThemeProvider';
import { useOlonForms } from '@/lib/useOlonForms';
import { OlonFormsContext } from '@olonjs/core';
import { iconMap } from '@/lib/IconResolver';

import tenantCss from './index.css?inline';

// Cloud Configuration (Injected by Vercel/Netlify Env Vars)
const CLOUD_API_URL =
  import.meta.env.VITE_OLONJS_CLOUD_URL ?? import.meta.env.VITE_JSONPAGES_CLOUD_URL;
const CLOUD_API_KEY =
  import.meta.env.VITE_OLONJS_API_KEY ?? import.meta.env.VITE_JSONPAGES_API_KEY;
const SAVE2REPO_ENABLED = import.meta.env.VITE_SAVE2REPO === 'true';
const APP_BASE_PATH = normalizeBasePath(import.meta.env.BASE_URL || '/');

const themeConfig = themeData as unknown as ThemeConfig;
const menuConfig = menuData as unknown as MenuConfig;
const refDocuments = {
  'menu.json': menuConfig,
  'config/menu.json': menuConfig,
  'src/data/config/menu.json': menuConfig,
} satisfies NonNullable<JsonPagesConfig['refDocuments']>;

const TENANT_ID = 'alpha';

const filePages = getFilePages();
const fileSiteConfig = siteData as unknown as SiteConfig;
const MAX_UPLOAD_SIZE_BYTES = 5 * 1024 * 1024;
const ASSET_UPLOAD_MAX_RETRIES = 2;
const ASSET_UPLOAD_TIMEOUT_MS = 20_000;
const ALLOWED_IMAGE_MIME_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/avif']);

interface CloudSaveUiState {
  isOpen: boolean;
  phase: DeployPhase;
  currentStepId: StepId | null;
  doneSteps: StepId[];
  progress: number;
  errorMessage?: string;
  deployUrl?: string;
}

type ContentMode = 'cloud' | 'error';
type ContentStatus = 'ok' | 'empty_namespace' | 'legacy_fallback';

type ContentResponse = {
  ok?: boolean;
  siteConfig?: unknown;
  pages?: unknown;
  items?: unknown;
  error?: string;
  code?: string;
  correlationId?: string;
  contentStatus?: ContentStatus;
  usedUnscopedFallback?: boolean;
  namespace?: string;
  namespaceMatchedKeys?: number;
};

type CachedCloudContent = {
  keyFingerprint: string;
  savedAt: number;
  siteConfig: unknown | null;
  pages: Record<string, unknown>;
};

const CLOUD_CACHE_KEY = 'jp_cloud_content_cache_v1';
const CLOUD_CACHE_TTL_MS = 5 * 60 * 1000;

function normalizeApiBase(raw: string): string {
  return raw.trim().replace(/\/+$/, '');
}

function buildApiCandidates(raw: string): string[] {
  const base = normalizeApiBase(raw);
  const withApi = /\/api\/v1$/i.test(base) ? base : `${base}/api/v1`;
  const candidates = [withApi, base];
  return Array.from(new Set(candidates.filter(Boolean)));
}

function getInitialData() {
  return getHydratedData(TENANT_ID, filePages, fileSiteConfig);
}

function getInitialCloudSaveUiState(): CloudSaveUiState {
  return {
    isOpen: false,
    phase: 'idle',
    currentStepId: null,
    doneSteps: [],
    progress: 0,
  };
}

function stepProgress(doneSteps: StepId[]): number {
  return Math.round((doneSteps.length / DEPLOY_STEPS.length) * 100);
}

function isObjectRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function asString(value: unknown, fallback: string): string {
  return typeof value === 'string' && value.trim() ? value : fallback;
}

function normalizeRouteSlug(value: string): string {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9/_-]/g, '-')
    .replace(/^\/+|\/+$/g, '') || 'home';
}

function coercePageConfig(slug: string, value: unknown): PageConfig | null {
  let input = value;
  if (typeof input === 'string') {
    try {
      input = JSON.parse(input) as unknown;
    } catch {
      return null;
    }
  }
  if (!isObjectRecord(input) || !Array.isArray(input.sections)) return null;

  const inputMeta = isObjectRecord(input.meta) ? input.meta : {};
  const normalizedSlug = asString(input.slug, slug);
  const normalizedId = asString(input.id, `${normalizedSlug}-page`);
  const title = asString(inputMeta.title, normalizedSlug);
  const description = asString(inputMeta.description, '');

  return {
    id: normalizedId,
    slug: normalizedSlug,
    meta: { title, description },
    sections: input.sections as PageConfig['sections'],
    ...(typeof input['global-header'] === 'boolean' ? { 'global-header': input['global-header'] } : {}),
  };
}

function coerceSiteConfig(value: unknown): SiteConfig | null {
  let input = value;
  if (typeof input === 'string') {
    try {
      input = JSON.parse(input) as unknown;
    } catch {
      return null;
    }
  }
  if (!isObjectRecord(input)) return null;
  if (!isObjectRecord(input.identity)) return null;

  return input as unknown as SiteConfig;
}

function toPagesRecord(value: unknown): Record<string, PageConfig> | null {
  const directPage = coercePageConfig('home', value);
  if (directPage) {
    const directSlug = normalizeRouteSlug(asString(directPage.slug, 'home'));
    return { [directSlug]: { ...directPage, slug: directSlug } };
  }

  if (!isObjectRecord(value)) return null;
  const next: Record<string, PageConfig> = {};
  for (const [rawKey, payload] of Object.entries(value)) {
    const rawKeyTrimmed = rawKey.trim();
    const slugFromNamespacedKey = rawKeyTrimmed.match(/^t_[a-z0-9-]+_page_(.+)$/i)?.[1];
    const slug = normalizeRouteSlug(slugFromNamespacedKey ?? rawKeyTrimmed);
    const page = coercePageConfig(slug, payload);
    if (!page) continue;
    next[slug] = { ...page, slug };
  }
  return next;
}

function normalizePageRegistry(value: unknown): Record<string, PageConfig> {
  if (!isObjectRecord(value)) return {};
  const normalized: Record<string, PageConfig> = {};

  for (const [registrySlug, rawPageValue] of Object.entries(value)) {
    const canonicalSlug = normalizeRouteSlug(registrySlug);
    const direct = coercePageConfig(canonicalSlug, rawPageValue);
    if (direct) {
      // Canonical key comes from registry/path, not from page JSON internal slug.
      normalized[canonicalSlug] = { ...direct, slug: canonicalSlug };
      continue;
    }

    const nested = toPagesRecord(rawPageValue);
    if (nested && Object.keys(nested).length > 0) {
      Object.assign(normalized, nested);
    }
  }

  return normalized;
}

function extractContentSources(payload: ContentResponse | Record<string, unknown>): {
  pagesSource: unknown;
  siteSource: unknown;
} {
  // Canonical contract: { pages, siteConfig }
  if (isObjectRecord(payload) && isObjectRecord(payload.pages)) {
    return { pagesSource: payload.pages, siteSource: payload.siteConfig };
  }

  // Edge public JSON contract: { digest, updatedAt, items: { ... } }
  if (isObjectRecord(payload) && isObjectRecord(payload.items)) {
    const items = payload.items;
    let siteSource: unknown = null;
    const pageEntries: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(items)) {
      if (/(_config_site|config_site|config:site)$/i.test(key)) {
        siteSource = value;
        continue;
      }
      if (/(_page_|^page_|page:)/i.test(key)) {
        pageEntries[key] = value;
      }
    }
    return { pagesSource: pageEntries, siteSource };
  }

  // Raw map fallback: treat payload object itself as page map.
  return { pagesSource: payload, siteSource: null };
}

type CloudLoadFailure = {
  reasonCode: string;
  message: string;
  correlationId?: string;
};

function isCloudLoadFailure(value: unknown): value is CloudLoadFailure {
  return (
    isObjectRecord(value) &&
    typeof value.reasonCode === 'string' &&
    typeof value.message === 'string'
  );
}

function toCloudLoadFailure(value: unknown): CloudLoadFailure {
  if (isCloudLoadFailure(value)) return value;
  if (value instanceof Error) {
    return { reasonCode: 'CLOUD_LOAD_FAILED', message: value.message };
  }
  return { reasonCode: 'CLOUD_LOAD_FAILED', message: 'Cloud content unavailable.' };
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isRetryableStatus(status: number): boolean {
  return status === 429 || status === 500 || status === 502 || status === 503 || status === 504;
}

function backoffDelayMs(attempt: number): number {
  const base = 250 * Math.pow(2, attempt);
  const jitter = Math.floor(Math.random() * 120);
  return base + jitter;
}

function logBootstrapEvent(event: string, details: Record<string, unknown>) {
  console.info('[boot]', { event, at: new Date().toISOString(), ...details });
}

function cloudFingerprint(apiBase: string, apiKey: string): string {
  return `${normalizeApiBase(apiBase)}::${apiKey.slice(-8)}`;
}

function normalizeSlugForCache(slug: string): string {
  return (
    slug
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9/_-]/g, '-')
      .replace(/^\/+|\/+$/g, '') || 'home'
  );
}

function buildPublishedPageHref(slug: string): string {
  return withBasePath(`/pages/${normalizeSlugForCache(slug)}.json`, APP_BASE_PATH);
}

async function loadPublishedStaticContent(
  knownSlugs: string[]
): Promise<{ pages: Record<string, PageConfig>; siteConfig: SiteConfig }> {
  const siteResponse = await fetch(withBasePath('/config/site.json', APP_BASE_PATH), { cache: 'no-store' });
  if (!siteResponse.ok) {
    throw new Error(`Static site config unavailable: ${siteResponse.status}`);
  }

  const sitePayload = (await siteResponse.json().catch(() => null)) as unknown;
  const nextSite = coerceSiteConfig(sitePayload);
  if (!nextSite) {
    throw new Error('Static site config is invalid.');
  }

  const pageEntries = await Promise.all(
    knownSlugs.map(async (slug) => {
      const response = await fetch(buildPublishedPageHref(slug), { cache: 'no-store' });
      if (!response.ok) {
        throw new Error(`Static page unavailable for slug "${slug}": ${response.status}`);
      }
      return [slug, (await response.json().catch(() => null)) as unknown] as const;
    })
  );

  const nextPages = normalizePageRegistry(Object.fromEntries(pageEntries));
  if (Object.keys(nextPages).length === 0) {
    throw new Error('Static published pages are empty.');
  }

  return {
    pages: nextPages,
    siteConfig: nextSite,
  };
}

function readCachedCloudContent(fingerprint: string): CachedCloudContent | null {
  try {
    const raw = localStorage.getItem(CLOUD_CACHE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as CachedCloudContent;
    if (!parsed || parsed.keyFingerprint !== fingerprint) return null;
    if (!parsed.savedAt || Date.now() - parsed.savedAt > CLOUD_CACHE_TTL_MS) return null;
    return parsed;
  } catch {
    return null;
  }
}

function writeCachedCloudContent(entry: CachedCloudContent): void {
  try {
    localStorage.setItem(CLOUD_CACHE_KEY, JSON.stringify(entry));
  } catch {
    // non-blocking cache path
  }
}

function buildThemeFontVarsCss(input: unknown): string {
  if (!isObjectRecord(input)) return '';
  const tokens = isObjectRecord(input.tokens) ? input.tokens : null;
  const typography = tokens && isObjectRecord(tokens.typography) ? tokens.typography : null;
  const fontFamily = typography && isObjectRecord(typography.fontFamily) ? typography.fontFamily : null;
  const primary = typeof fontFamily?.primary === 'string' ? fontFamily.primary : "'Instrument Sans', system-ui, sans-serif";
  const serif = typeof fontFamily?.serif === 'string' ? fontFamily.serif : "'Instrument Serif', Georgia, serif";
  const mono = typeof fontFamily?.mono === 'string' ? fontFamily.mono : "'JetBrains Mono', monospace";
  return `:root{--theme-font-primary:${primary};--theme-font-serif:${serif};--theme-font-mono:${mono};}`;
}

const REMOTE_CSS_LINK_ATTR = 'data-jp-tenant-remote-css';

function isRemoteStylesheetHref(value: string): boolean {
  return /^https?:\/\//i.test(value.trim());
}

function extractLeadingRemoteCssImports(cssText: string): { hrefs: string[]; rest: string } {
  const hrefs = new Set<string>();
  const leadingTriviaPattern = /^(?:\s+|\/\*[\s\S]*?\*\/)*/;
  const importPattern =
    /^@import\s+url\(\s*(?:'([^']+)'|"([^"]+)"|([^'")\s][^)]*))\s*\)\s*([^;]*);/i;
  let rest = cssText;

  for (;;) {
    const trivia = rest.match(leadingTriviaPattern);
    if (trivia && trivia[0]) {
      rest = rest.slice(trivia[0].length);
    }

    const match = rest.match(importPattern);
    if (!match) break;

    const href = (match[1] ?? match[2] ?? match[3] ?? '').trim();
    const trailingDirectives = (match[4] ?? '').trim();

    if (!isRemoteStylesheetHref(href) || trailingDirectives.length > 0) {
      break;
    }

    hrefs.add(href);
    rest = rest.slice(match[0].length);
  }

  return { hrefs: Array.from(hrefs), rest };
}

function setTenantPreviewReady(ready: boolean): void {
  if (typeof window !== 'undefined') {
    (window as Window & { __TENANT_PREVIEW_READY__?: boolean }).__TENANT_PREVIEW_READY__ = ready;
  }
  if (typeof document !== 'undefined' && document.body) {
    document.body.dataset.previewReady = ready ? '1' : '0';
  }
}

function App() {
  const { states: formStates } = useOlonForms();
  const isCloudMode = Boolean(CLOUD_API_URL && CLOUD_API_KEY);
  const isSave2RepoMode = isCloudMode && SAVE2REPO_ENABLED;
  const isHotSaveMode = isCloudMode && !isSave2RepoMode;
  const localInitialData = useMemo(() => (isCloudMode ? null : getInitialData()), [isCloudMode]);
  const localInitialPages = useMemo(() => {
    if (!localInitialData) return {};
    const normalized = normalizePageRegistry(localInitialData.pages as unknown);
    return Object.keys(normalized).length > 0 ? normalized : localInitialData.pages;
  }, [localInitialData]);
  const [pages, setPages] = useState<Record<string, PageConfig>>(localInitialPages);
  const [siteConfig, setSiteConfig] = useState<SiteConfig>(
    localInitialData?.siteConfig ?? fileSiteConfig
  );
  const [assetsManifest, setAssetsManifest] = useState<LibraryImageEntry[]>([]);
  const [cloudSaveUi, setCloudSaveUi] = useState<CloudSaveUiState>(getInitialCloudSaveUiState);
  const [contentMode, setContentMode] = useState<ContentMode>('cloud');
  const [contentFallback, setContentFallback] = useState<CloudLoadFailure | null>(null);
  const [showTopProgress, setShowTopProgress] = useState(false);
  const [hasInitialCloudResolved, setHasInitialCloudResolved] = useState(!isCloudMode);
  const [bootstrapRunId, setBootstrapRunId] = useState(0);
  const activeCloudSaveController = useRef<AbortController | null>(null);
  const contentLoadInFlight = useRef<Promise<void> | null>(null);
  const pendingCloudSave = useRef<{ state: ProjectState; slug: string } | null>(null);
  const cloudApiCandidates = useMemo(
    () => (isCloudMode && CLOUD_API_URL ? buildApiCandidates(CLOUD_API_URL) : []),
    [isCloudMode, CLOUD_API_URL]
  );

  const loadAssetsManifest = useCallback(async (): Promise<void> => {
    if (isCloudMode && CLOUD_API_URL && CLOUD_API_KEY) {
      const apiBases = cloudApiCandidates.length > 0 ? cloudApiCandidates : [normalizeApiBase(CLOUD_API_URL)];
      for (const apiBase of apiBases) {
        try {
          const res = await fetch(`${apiBase}/assets/list?limit=200`, {
            method: 'GET',
            headers: {
              Authorization: `Bearer ${CLOUD_API_KEY}`,
            },
          });
          const body = (await res.json().catch(() => ({}))) as { items?: LibraryImageEntry[] };
          if (!res.ok) continue;
          const items = Array.isArray(body.items) ? body.items : [];
          setAssetsManifest(items);
          return;
        } catch {
          // try next candidate
        }
      }
      setAssetsManifest([]);
      return;
    }

    fetch('/api/list-assets')
      .then((r) => (r.ok ? r.json() : []))
      .then((list: LibraryImageEntry[]) => setAssetsManifest(Array.isArray(list) ? list : []))
      .catch(() => setAssetsManifest([]));
  }, [isCloudMode, CLOUD_API_URL, CLOUD_API_KEY, cloudApiCandidates]);

  useEffect(() => {
    void loadAssetsManifest();
  }, [loadAssetsManifest]);

  useEffect(() => {
    return () => {
      activeCloudSaveController.current?.abort();
    };
  }, []);

  useEffect(() => {
    setTenantPreviewReady(false);
    return () => {
      setTenantPreviewReady(false);
    };
  }, []);

  useEffect(() => {
    if (!isCloudMode || !CLOUD_API_URL || !CLOUD_API_KEY) {
      setContentMode('cloud');
      setContentFallback(null);
      setShowTopProgress(false);
      setHasInitialCloudResolved(true);
      logBootstrapEvent('boot.local.ready', { mode: 'local' });
      return;
    }

    if (isSave2RepoMode) {
      if (contentLoadInFlight.current) {
        return;
      }

      setContentMode('cloud');
      setContentFallback(null);
      setShowTopProgress(true);
      setHasInitialCloudResolved(false);
      logBootstrapEvent('boot.start', { mode: 'save2repo-static', pageCount: Object.keys(filePages).length });

      let inFlight: Promise<void> | null = null;
      inFlight = loadPublishedStaticContent(Object.keys(filePages))
        .then(({ pages: nextPages, siteConfig: nextSite }) => {
          setPages(nextPages);
          setSiteConfig(nextSite);
          setContentMode('cloud');
          setContentFallback(null);
          setHasInitialCloudResolved(true);
          logBootstrapEvent('boot.save2repo.success', {
            mode: 'save2repo-static',
            pageCount: Object.keys(nextPages).length,
          });
        })
        .catch((error: unknown) => {
          const failure = toCloudLoadFailure(error);
          setContentMode('error');
          setContentFallback(failure);
          setHasInitialCloudResolved(true);
          logBootstrapEvent('boot.save2repo.error', {
            mode: 'save2repo-static',
            reasonCode: failure.reasonCode,
            correlationId: failure.correlationId ?? null,
          });
        })
        .finally(() => {
          setShowTopProgress(false);
          if (contentLoadInFlight.current === inFlight) {
            contentLoadInFlight.current = null;
          }
        });
      contentLoadInFlight.current = inFlight;
      return () => {
        contentLoadInFlight.current = null;
      };
    }

    if (contentLoadInFlight.current) {
      return;
    }

    const controller = new AbortController();
    const maxRetryAttempts = 2;
    const startedAt = Date.now();
    const primaryApiBase = cloudApiCandidates[0] ?? normalizeApiBase(CLOUD_API_URL);
    const fingerprint = cloudFingerprint(primaryApiBase, CLOUD_API_KEY);
    const cached = readCachedCloudContent(fingerprint);
    const cachedPages = cached ? toPagesRecord(cached.pages) : null;
    const cachedSite = cached ? coerceSiteConfig(cached.siteConfig) : null;
    const hasCachedFallback = Boolean((cachedPages && Object.keys(cachedPages).length > 0) || cachedSite);
    if (cached) {
      logBootstrapEvent('boot.cloud.cache_hit', { ageMs: Date.now() - cached.savedAt });
    }
    setContentMode('cloud');
    setContentFallback(null);
    setShowTopProgress(true);
    setHasInitialCloudResolved(false);
    logBootstrapEvent('boot.start', { mode: 'cloud', apiCandidates: cloudApiCandidates.length });

    const loadCloudContent = async () => {
      try {
        let payload: ContentResponse | null = null;
        let lastFailure: CloudLoadFailure | null = null;

        for (const apiBase of cloudApiCandidates) {
          for (let attempt = 0; attempt <= maxRetryAttempts; attempt += 1) {
            try {
              const res = await fetch(`${apiBase}/content`, {
                method: 'GET',
                cache: 'no-store',
                headers: {
                  Authorization: `Bearer ${CLOUD_API_KEY}`,
                },
                signal: controller.signal,
              });

              const contentType = (res.headers.get('content-type') || '').toLowerCase();
              if (!contentType.includes('application/json')) {
                lastFailure = {
                  reasonCode: 'NON_JSON_RESPONSE',
                  message: `Non-JSON response from ${apiBase}/content`,
                };
                break;
              }

              const parsed = (await res.json().catch(() => ({}))) as ContentResponse;
              if (!res.ok) {
                lastFailure = {
                  reasonCode: parsed.code || `HTTP_${res.status}`,
                  message: parsed.error || `Cloud content read failed: ${res.status} (${apiBase}/content)`,
                  correlationId: parsed.correlationId,
                };
                if (isRetryableStatus(res.status) && attempt < maxRetryAttempts) {
                  await sleep(backoffDelayMs(attempt));
                  continue;
                }
                break;
              }

              payload = parsed;
              break;
            } catch (error: unknown) {
              if (controller.signal.aborted) throw error;
              const message = error instanceof Error ? error.message : 'Network error';
              lastFailure = {
                reasonCode: 'NETWORK_TRANSIENT',
                message: `${message} (${apiBase}/content)`,
              };
              if (attempt < maxRetryAttempts) {
                await sleep(backoffDelayMs(attempt));
                continue;
              }
            }
          }
          if (payload) {
            break;
          }
        }

        if (!payload) {
          throw (
            lastFailure || {
              reasonCode: 'CLOUD_ENDPOINT_UNREACHABLE',
              message: 'Cloud content endpoint not reachable as JSON.',
            }
          );
        }

        const { pagesSource, siteSource } = extractContentSources(payload);
        const remotePages = toPagesRecord(pagesSource);
        const remoteSite = coerceSiteConfig(siteSource);
        const remotePageCount = remotePages ? Object.keys(remotePages).length : 0;
        if (remotePageCount === 0 && !remoteSite) {
          throw {
            reasonCode: payload.contentStatus === 'empty_namespace' ? 'EMPTY_NAMESPACE' : 'EMPTY_PAYLOAD',
            message: 'Cloud payload is empty for this tenant namespace.',
            correlationId: payload.correlationId,
          } satisfies CloudLoadFailure;
        }
        if (import.meta.env.DEV) {
          console.info('[content] cloud diagnostics', {
            contentStatus: payload.contentStatus ?? 'ok',
            namespace: payload.namespace,
            namespaceMatchedKeys: payload.namespaceMatchedKeys,
            usedUnscopedFallback: payload.usedUnscopedFallback,
            correlationId: payload.correlationId,
          });
        }
        if (remotePages && remotePageCount > 0) {
          setPages(remotePages);
        }
        if (remoteSite) {
          setSiteConfig(remoteSite);
        }
        writeCachedCloudContent({
          keyFingerprint: fingerprint,
          savedAt: Date.now(),
          siteConfig: remoteSite ?? null,
          pages: (remotePages ?? {}) as Record<string, unknown>,
        });
        setContentMode('cloud');
        setContentFallback(null);
        setHasInitialCloudResolved(true);
        logBootstrapEvent('boot.cloud.success', {
          mode: 'cloud',
          elapsedMs: Date.now() - startedAt,
          contentStatus: payload.contentStatus ?? 'ok',
          correlationId: payload.correlationId ?? null,
        });
      } catch (error: unknown) {
        if (controller.signal.aborted) return;
        const failure = toCloudLoadFailure(error);
        if (hasCachedFallback) {
          if (cachedPages && Object.keys(cachedPages).length > 0) {
            setPages(cachedPages);
          }
          if (cachedSite) {
            setSiteConfig(cachedSite);
          }
          setContentMode('cloud');
          setContentFallback({
            reasonCode: 'CLOUD_REFRESH_FAILED',
            message: failure.message,
            correlationId: failure.correlationId,
          });
          setHasInitialCloudResolved(true);
        } else {
          setContentMode('error');
          setContentFallback(failure);
          setHasInitialCloudResolved(true);
        }
        logBootstrapEvent('boot.cloud.error', {
          mode: 'cloud',
          elapsedMs: Date.now() - startedAt,
          reasonCode: failure.reasonCode,
          correlationId: failure.correlationId ?? null,
        });
      }
    };

    let inFlight: Promise<void> | null = null;
    inFlight = loadCloudContent().finally(() => {
      setShowTopProgress(false);
      if (contentLoadInFlight.current === inFlight) {
        contentLoadInFlight.current = null;
      }
    });
    contentLoadInFlight.current = inFlight;
    return () => controller.abort();
  }, [isCloudMode, isSave2RepoMode, CLOUD_API_KEY, CLOUD_API_URL, cloudApiCandidates, bootstrapRunId]);

  const runCloudSave = useCallback(
    async (
      payload: { state: ProjectState; slug: string },
      rejectOnError: boolean
    ): Promise<void> => {
      if (!CLOUD_API_URL || !CLOUD_API_KEY) {
        const noCloudError = new Error('Cloud mode is not configured.');
        if (rejectOnError) throw noCloudError;
        return;
      }

      pendingCloudSave.current = payload;
      activeCloudSaveController.current?.abort();
      const controller = new AbortController();
      activeCloudSaveController.current = controller;

      setCloudSaveUi({
        isOpen: true,
        phase: 'running',
        currentStepId: null,
        doneSteps: [],
        progress: 0,
      });

      try {
        await startCloudSaveStream({
          apiBaseUrl: CLOUD_API_URL,
          apiKey: CLOUD_API_KEY,
          path: `src/data/pages/${payload.slug}.json`,
          content: payload.state.page,
          message: `Content update for ${payload.slug} via Visual Editor`,
          signal: controller.signal,
          onStep: (event) => {
            setCloudSaveUi((prev) => {
              if (event.status === 'running') {
                return {
                  ...prev,
                  isOpen: true,
                  phase: 'running',
                  currentStepId: event.id,
                  errorMessage: undefined,
                };
              }

              if (prev.doneSteps.includes(event.id)) {
                return prev;
              }

              const nextDone = [...prev.doneSteps, event.id];
              return {
                ...prev,
                isOpen: true,
                phase: 'running',
                currentStepId: event.id,
                doneSteps: nextDone,
                progress: stepProgress(nextDone),
              };
            });
          },
          onDone: (event) => {
            const completed = DEPLOY_STEPS.map((step) => step.id);
            setCloudSaveUi({
              isOpen: true,
              phase: 'done',
              currentStepId: 'live',
              doneSteps: completed,
              progress: 100,
              deployUrl: event.deployUrl,
            });
          },
        });
      } catch (error: unknown) {
        const message = error instanceof Error ? error.message : 'Cloud save failed.';
        setCloudSaveUi((prev) => ({
          ...prev,
          isOpen: true,
          phase: 'error',
          errorMessage: message,
        }));
        if (rejectOnError) throw new Error(message);
      } finally {
        if (activeCloudSaveController.current === controller) {
          activeCloudSaveController.current = null;
        }
      }
    },
    []
  );

  const closeCloudDrawer = useCallback(() => {
    setCloudSaveUi(getInitialCloudSaveUiState());
  }, []);

  const retryCloudSave = useCallback(() => {
    if (!pendingCloudSave.current) return;
    void runCloudSave(pendingCloudSave.current, false);
  }, [runCloudSave]);

  const tenantCssParts = useMemo(() => extractLeadingRemoteCssImports(tenantCss), [tenantCss]);
  const resolvedTenantCss = useMemo(
    () => [buildThemeFontVarsCss(themeConfig), tenantCssParts.rest].filter(Boolean).join('\n'),
    [tenantCssParts],
  );

  useEffect(() => {
    if (typeof document === 'undefined') return undefined;

    const createdLinks: HTMLLinkElement[] = [];

    tenantCssParts.hrefs.forEach((href) => {
      const existing = Array.from(document.querySelectorAll('link[rel="stylesheet"]')).find(
        (link) => (link as HTMLLinkElement).href === href,
      ) as HTMLLinkElement | undefined;
      if (existing) return;

      const link = document.createElement('link');
      link.rel = 'stylesheet';
      link.href = href;
      link.setAttribute(REMOTE_CSS_LINK_ATTR, href);
      document.head.appendChild(link);
      createdLinks.push(link);
    });

    return () => {
      createdLinks.forEach((link) => {
        if (link.getAttribute(REMOTE_CSS_LINK_ATTR) !== link.href) return;
        if (link.parentNode) link.parentNode.removeChild(link);
      });
    };
  }, [tenantCssParts]);

  const config: JsonPagesConfig = {
    tenantId: TENANT_ID,
    basePath: APP_BASE_PATH,
    registry: ComponentRegistry as JsonPagesConfig['registry'],
    schemas: SECTION_SCHEMAS as unknown as JsonPagesConfig['schemas'],
    submissionSchemas: SECTION_SUBMISSION_SCHEMAS as unknown as JsonPagesConfig['submissionSchemas'],
    pages,
    siteConfig,
    themeConfig,
    menuConfig,
    refDocuments,
    iconRegistry: iconMap,
    themeCss: { tenant: resolvedTenantCss },
    addSection: addSectionConfig,
    webmcp: {
      enabled: true,
      namespace: typeof window !== 'undefined' ? window.location.href : '',
    },
    persistence: {
      async saveToFile(state: ProjectState, slug: string): Promise<void> {
        // 💻 LOCAL FILESYSTEM (development path)
        console.log(`💻 Saving ${slug} to Local Filesystem...`);
        const res = await fetch('/api/save-to-file', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ projectState: state, slug }),
        });
        
        const body = (await res.json().catch(() => ({}))) as { error?: string };
        if (!res.ok) throw new Error(body.error ?? `Save to file failed: ${res.status}`);
      },
      async hotSave(state: ProjectState, slug: string): Promise<void> {
        if (!isCloudMode || !CLOUD_API_URL || !CLOUD_API_KEY) {
          throw new Error('Cloud mode is not configured for hot save.');
        }
        const apiBase = CLOUD_API_URL.replace(/\/$/, '');
        const res = await fetch(`${apiBase}/hotSave`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${CLOUD_API_KEY}`,
          },
          body: JSON.stringify({
            slug,
            page: state.page,
            siteConfig: state.site,
          }),
        });
        const body = (await res.json().catch(() => ({}))) as { error?: string; code?: string };
        if (!res.ok) {
          throw new Error(body.error || body.code || `Hot save failed: ${res.status}`);
        }
        const keyFingerprint = cloudFingerprint(apiBase, CLOUD_API_KEY);
        const normalizedSlug = normalizeSlugForCache(slug);
        const existing = readCachedCloudContent(keyFingerprint);
        writeCachedCloudContent({
          keyFingerprint,
          savedAt: Date.now(),
          siteConfig: state.site ?? null,
          pages: {
            ...(existing?.pages ?? {}),
            [normalizedSlug]: state.page,
          },
        });
      },
      async coldSave(state: ProjectState, slug: string): Promise<void> {
        await runCloudSave({ state, slug }, true);
      },
      showLocalSave: !isCloudMode,
      showHotSave: isHotSaveMode,
      showColdSave: isSave2RepoMode,
    },
    assets: {
      assetsBaseUrl: withBasePath('/assets', APP_BASE_PATH),
      assetsManifest,
      async onAssetUpload(file: File): Promise<string> {
        if (!file.type.startsWith('image/')) throw new Error('Invalid file type.');
        if (!ALLOWED_IMAGE_MIME_TYPES.has(file.type)) {
          throw new Error('Unsupported image format. Allowed: jpeg, png, webp, gif, avif.');
        }
        if (file.size > MAX_UPLOAD_SIZE_BYTES) throw new Error(`File too large. Max ${MAX_UPLOAD_SIZE_BYTES / 1024 / 1024}MB.`);

        if (isCloudMode && CLOUD_API_URL && CLOUD_API_KEY) {
          const apiBases = cloudApiCandidates.length > 0 ? cloudApiCandidates : [normalizeApiBase(CLOUD_API_URL)];
          let lastError: Error | null = null;
          for (const apiBase of apiBases) {
            for (let attempt = 0; attempt <= ASSET_UPLOAD_MAX_RETRIES; attempt += 1) {
              try {
                const formData = new FormData();
                formData.append('file', file);
                formData.append('filename', file.name);
                const controller = new AbortController();
                const timeout = window.setTimeout(() => controller.abort(), ASSET_UPLOAD_TIMEOUT_MS);
                const res = await fetch(`${apiBase}/assets/upload`, {
                  method: 'POST',
                  headers: {
                    Authorization: `Bearer ${CLOUD_API_KEY}`,
                    'X-Correlation-Id': crypto.randomUUID(),
                  },
                  body: formData,
                  signal: controller.signal,
                }).finally(() => window.clearTimeout(timeout));
                const body = (await res.json().catch(() => ({}))) as { url?: string; error?: string; code?: string };
                if (res.ok && typeof body.url === 'string') {
                  await loadAssetsManifest().catch(() => undefined);
                  return body.url;
                }
                lastError = new Error(body.error || body.code || `Cloud upload failed: ${res.status}`);
                if (isRetryableStatus(res.status) && attempt < ASSET_UPLOAD_MAX_RETRIES) {
                  await sleep(backoffDelayMs(attempt));
                  continue;
                }
                break;
              } catch (error: unknown) {
                const message = error instanceof Error ? error.message : 'Cloud upload failed.';
                lastError = new Error(message);
                if (attempt < ASSET_UPLOAD_MAX_RETRIES) {
                  await sleep(backoffDelayMs(attempt));
                  continue;
                }
                break;
              }
            }
          }
          throw lastError ?? new Error('Cloud upload failed.');
        }

        const base64 = await new Promise<string>((resolve, reject) => {
          const reader = new FileReader();
          reader.onload = () => resolve((reader.result as string).split(',')[1] ?? '');
          reader.onerror = () => reject(reader.error);
          reader.readAsDataURL(file);
        });

        const res = await fetch('/api/upload-asset', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ filename: file.name, mimeType: file.type || undefined, data: base64 }),
        });
        const body = (await res.json().catch(() => ({}))) as { url?: string; error?: string };
        if (!res.ok) throw new Error(body.error || `Upload failed: ${res.status}`);
        if (typeof body.url !== 'string') throw new Error('Invalid server response: missing url');
        await loadAssetsManifest().catch(() => undefined);
        return body.url;
      },
    },
  };

  const shouldRenderEngine = !isCloudMode || hasInitialCloudResolved;
  const isTenantEmpty = Object.keys(pages).length === 0;

  useEffect(() => {
    if (!shouldRenderEngine) {
      setTenantPreviewReady(false);
      return;
    }
    let cancelled = false;
    let raf1 = 0;
    let raf2 = 0;
    raf1 = window.requestAnimationFrame(() => {
      raf2 = window.requestAnimationFrame(() => {
        if (!cancelled) setTenantPreviewReady(true);
      });
    });
    return () => {
      cancelled = true;
      window.cancelAnimationFrame(raf1);
      window.cancelAnimationFrame(raf2);
      setTenantPreviewReady(false);
    };
  }, [shouldRenderEngine, pages, siteConfig]);

  return (
    <ThemeProvider>
      <OlonFormsContext.Provider value={formStates}>
      <>
      {isCloudMode && showTopProgress ? (
        <>
          <style>
            {`@keyframes jp-top-progress-slide { 0% { transform: translateX(-120%); } 100% { transform: translateX(320%); } }`}
          </style>
          <div
            role="status"
            aria-live="polite"
            aria-label="Cloud loading progress"
            style={{
              position: 'fixed',
              top: 0,
              left: 0,
              right: 0,
              height: 2,
              zIndex: 1300,
              background: 'rgba(255,255,255,0.08)',
              overflow: 'hidden',
            }}
          >
            <div
              style={{
                width: '32%',
                height: '100%',
                background: 'linear-gradient(90deg, rgba(88,166,255,0.15) 0%, rgba(88,166,255,0.85) 50%, rgba(88,166,255,0.15) 100%)',
                animation: 'jp-top-progress-slide 1.15s ease-in-out infinite',
                willChange: 'transform',
              }}
            />
          </div>
        </>
      ) : null}
      {isCloudMode && !hasInitialCloudResolved ? (
        <div className="fixed inset-0 z-[1290] bg-background/80 backdrop-blur-sm">
          <div className="mx-auto w-full max-w-[1600px] p-6">
            <div className="grid gap-4 lg:grid-cols-[1fr_420px]">
              <div className="space-y-4">
                <Skeleton className="h-10 w-64" />
                <Skeleton className="h-[220px] w-full rounded-xl" />
                <Skeleton className="h-[220px] w-full rounded-xl" />
              </div>
              <div className="space-y-3 rounded-xl border border-border/50 bg-card/60 p-4">
                <Skeleton className="h-8 w-32" />
                <Skeleton className="h-5 w-full" />
                <Skeleton className="h-5 w-5/6" />
                <Skeleton className="h-5 w-4/6" />
                <Skeleton className="h-24 w-full rounded-lg" />
              </div>
            </div>
          </div>
        </div>
      ) : null}
     {shouldRenderEngine ? (isTenantEmpty ? <EmptyTenantView /> : <JsonPagesEngine config={config} />) : null}
      {isCloudMode && (contentMode === 'error' || contentFallback?.reasonCode === 'CLOUD_REFRESH_FAILED') ? (
        <div
          role="status"
          aria-live="polite"
          style={{
            position: 'fixed',
            top: 12,
            right: 12,
            zIndex: 1200,
            background: 'rgba(179, 65, 24, 0.92)',
            border: '1px solid rgba(255,255,255,0.18)',
            color: '#fff',
            padding: '8px 12px',
            borderRadius: 10,
            fontSize: 12,
            maxWidth: 360,
            boxShadow: '0 8px 24px rgba(0,0,0,0.25)',
          }}
        >
          {contentMode === 'error' ? 'Cloud content unavailable.' : 'Cloud refresh failed, showing cached content.'}
          {contentFallback ? (
            <div style={{ opacity: 0.85, marginTop: 4 }}>
              <div>{contentFallback.message}</div>
              <div style={{ marginTop: 2 }}>
                Reason: {contentFallback.reasonCode}
                {contentFallback.correlationId ? ` | Correlation: ${contentFallback.correlationId}` : ''}
              </div>
              <div style={{ marginTop: 8 }}>
                <button
                  type="button"
                  onClick={() => {
                    contentLoadInFlight.current = null;
                    setContentMode('cloud');
                    setContentFallback(null);
                    setHasInitialCloudResolved(false);
                    setShowTopProgress(true);
                    setBootstrapRunId((prev) => prev + 1);
                  }}
                  style={{
                    border: '1px solid rgba(255,255,255,0.3)',
                    borderRadius: 8,
                    padding: '4px 10px',
                    background: 'transparent',
                    color: '#fff',
                    cursor: 'pointer',
                    fontSize: 12,
                  }}
                >
                  Retry
                </button>
              </div>
            </div>
          ) : null}
        </div>
      ) : null}
      <DopaDrawer
        isOpen={cloudSaveUi.isOpen}
        phase={cloudSaveUi.phase}
        currentStepId={cloudSaveUi.currentStepId}
        doneSteps={cloudSaveUi.doneSteps}
        progress={cloudSaveUi.progress}
        errorMessage={cloudSaveUi.errorMessage}
        deployUrl={cloudSaveUi.deployUrl}
        onClose={closeCloudDrawer}
        onRetry={retryCloudSave}
      />
      </>
      </OlonFormsContext.Provider>
    </ThemeProvider>
  );
}

export default App;

END_OF_FILE_CONTENT
mkdir -p "src/components"
echo "Creating src/components/ThemeProvider.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/ThemeProvider.tsx"
import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'

type Theme = 'dark' | 'light'

interface ThemeContextValue {
  theme: Theme
  toggleTheme: () => void
  setTheme: (t: Theme) => void
}

const ThemeContext = createContext<ThemeContextValue>({
  theme: 'dark',
  toggleTheme: () => {},
  setTheme: () => {},
})

const STORAGE_KEY = 'olon:theme'

function isTheme(value: unknown): value is Theme {
  return value === 'dark' || value === 'light'
}

function resolveInitialTheme(): Theme {
  if (typeof window === 'undefined') return 'dark'

  const fromDom = document.documentElement.getAttribute('data-theme')
  if (isTheme(fromDom)) return fromDom

  const fromStorage = window.localStorage.getItem(STORAGE_KEY)
  if (isTheme(fromStorage)) return fromStorage

  const prefersLight = window.matchMedia?.('(prefers-color-scheme: light)').matches
  return prefersLight ? 'light' : 'dark'
}

export function ThemeProvider({ children }: { children: ReactNode }) {
  const [theme, setThemeState] = useState<Theme>(resolveInitialTheme)

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme)
    window.localStorage.setItem(STORAGE_KEY, theme)
  }, [theme])

  function setTheme(t: Theme) {
    setThemeState(t)
  }

  function toggleTheme() {
    setThemeState((prev) => (prev === 'dark' ? 'light' : 'dark'))
  }

  const value = useMemo(() => ({ theme, toggleTheme, setTheme }), [theme])

  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>
}

export function useTheme() {
  return useContext(ThemeContext)
}

END_OF_FILE_CONTENT
mkdir -p "src/components/accommodation-showcase"
echo "Creating src/components/accommodation-showcase/View.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/accommodation-showcase/View.tsx"
// Layout: Hero=A (SPLIT 60/40), Features=A (BENTO GRID)
import React from 'react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Check } from 'lucide-react';
import type { AccommodationShowcaseData, AccommodationShowcaseSettings } from './types';

export const AccommodationShowcase: React.FC<{ data: AccommodationShowcaseData; settings: AccommodationShowcaseSettings }> = ({ data }) => (
  <section
    style={{
      '--local-bg': 'var(--background)',
      '--local-text': 'var(--foreground)',
      '--local-text-muted': 'var(--muted-foreground)',
      '--local-accent': 'var(--accent)',
      '--local-surface': 'var(--card)',
      '--local-border': 'var(--border)',
      '--local-primary': 'var(--primary)',
      '--local-primary-foreground': 'var(--primary-foreground)',
      '--local-radius-lg': 'var(--theme-radius-lg)',
      '--local-radius-md': 'var(--theme-radius-md)',
    } as React.CSSProperties}
    className="relative z-0 py-28 bg-[var(--local-bg)]"
  >
    <div className="max-w-[1200px] mx-auto px-8">
      {data.label && (
        <div className="jp-section-label inline-flex items-center gap-2 text-[0.72rem] font-bold uppercase tracking-[0.12em] text-[var(--local-accent)] mb-4" data-jp-field="label">
          <span className="w-5 h-px bg-[var(--local-primary)]" />
          {data.label}
        </div>
      )}
      
      <h2 className="font-display font-black text-[clamp(2rem,4.5vw,3.8rem)] leading-[1.05] tracking-tight text-[var(--local-text)] mb-16" data-jp-field="title">
        {data.title}
      </h2>
      
      <div className="space-y-24">
        {data.accommodations.map((accommodation, idx) => (
          <div
            key={accommodation.id || `accommodation-${idx}`}
            className={`grid grid-cols-1 lg:grid-cols-2 gap-16 items-center ${idx % 2 === 1 ? 'lg:grid-flow-col-dense' : ''}`}
            data-jp-item-id={accommodation.id || `accommodation-${idx}`}
            data-jp-item-field="accommodations"
          >
            {/* Content */}
            <div className={idx % 2 === 1 ? 'lg:col-start-2' : ''}>
              {accommodation.subtitle && (
                <Badge variant="secondary" className="mb-4 bg-[var(--local-surface)] text-[var(--local-text)] border-[var(--local-border)]">
                  {accommodation.subtitle}
                </Badge>
              )}
              
              <h3 className="font-display font-bold text-[clamp(1.5rem,3vw,2.5rem)] leading-tight tracking-tight text-[var(--local-text)] mb-6">
                {accommodation.title}
              </h3>
              
              <p className="text-[var(--local-text-muted)] text-lg leading-relaxed mb-8">
                {accommodation.description}
              </p>
              
              {accommodation.features && accommodation.features.length > 0 && (
                <ul className="space-y-3 mb-8">
                  {accommodation.features.map((feature, featureIdx) => (
                    <li key={featureIdx} className="flex items-center gap-3 text-[var(--local-text)]">
                      <Check className="w-5 h-5 text-[var(--local-primary)] flex-shrink-0" />
                      <span>{feature}</span>
                    </li>
                  ))}
                </ul>
              )}
              
              {accommodation.cta && (
                <Button
                  asChild
                  className="inline-flex items-center gap-2 px-6 py-3 rounded-[var(--local-radius-md)] bg-[var(--local-primary)] text-[var(--local-primary-foreground)] font-semibold hover:opacity-90 transition-opacity"
                >
                  <a href={accommodation.cta.href}>{accommodation.cta.label}</a>
                </Button>
              )}
            </div>
            
            {/* Image */}
            <div className={`relative ${idx % 2 === 1 ? 'lg:col-start-1' : ''}`}>
              {accommodation.image?.url && (
                <div className="relative overflow-hidden rounded-[var(--local-radius-lg)]">
                  <img 
                    src={accommodation.image.url}
                    alt={accommodation.image.alt}
                    className="w-full h-[500px] object-cover hover:scale-105 transition-transform duration-700"
                  />
                  <div className="absolute inset-0 bg-gradient-to-t from-black/20 to-transparent" />
                </div>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  </section>
);

END_OF_FILE_CONTENT
echo "Creating src/components/accommodation-showcase/index.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/accommodation-showcase/index.ts"
export { AccommodationShowcase } from './View';
export { AccommodationShowcaseSchema } from './schema';
export type { AccommodationShowcaseData, AccommodationShowcaseSettings } from './types';

END_OF_FILE_CONTENT
echo "Creating src/components/accommodation-showcase/schema.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/accommodation-showcase/schema.ts"
import { z } from 'zod';
import { BaseSectionData, BaseArrayItem, ImageSelectionSchema, CtaSchema } from '@olonjs/core';

const AccommodationItemSchema = BaseArrayItem.extend({
  title: z.string().describe('ui:text'),
  subtitle: z.string().optional().describe('ui:text'),
  description: z.string().describe('ui:textarea'),
  image: ImageSelectionSchema.optional(),
  features: z.array(z.string()).optional().describe('ui:list'),
  cta: CtaSchema.optional(),
});

export const AccommodationShowcaseSchema = BaseSectionData.extend({
  label: z.string().optional().describe('ui:text'),
  title: z.string().describe('ui:text'),
  accommodations: z.array(AccommodationItemSchema).describe('ui:list'),
});

END_OF_FILE_CONTENT
echo "Creating src/components/accommodation-showcase/types.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/accommodation-showcase/types.ts"
import { z } from 'zod';
import { BaseSectionSettingsSchema } from '@olonjs/core';
import { AccommodationShowcaseSchema } from './schema';

export type AccommodationShowcaseData = z.infer<typeof AccommodationShowcaseSchema>;
export type AccommodationShowcaseSettings = z.infer<typeof BaseSectionSettingsSchema>;

END_OF_FILE_CONTENT
mkdir -p "src/components/alpine-hero"
echo "Creating src/components/alpine-hero/View.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/alpine-hero/View.tsx"
// Layout: Hero=C (FULLSCREEN CINEMATIC), Features=A (BENTO GRID)
import React from 'react';
import { Button } from '@/components/ui/button';
import { ChevronDown } from 'lucide-react';
import type { AlpineHeroData, AlpineHeroSettings } from './types';

export const AlpineHero: React.FC<{ data: AlpineHeroData; settings: AlpineHeroSettings }> = ({ data }) => (
  <section
    style={{
      '--local-bg': 'var(--background)',
      '--local-text': 'var(--foreground)',
      '--local-text-muted': 'var(--muted-foreground)',
      '--local-primary': 'var(--primary)',
      '--local-primary-foreground': 'var(--primary-foreground)',
      '--local-accent': 'var(--accent)',
      '--local-accent-soft': 'color-mix(in oklch, var(--accent) 10%, transparent)',
      '--local-border': 'var(--border)',
      '--local-radius-md': 'var(--theme-radius-md)',
      '--local-radius-lg': 'var(--theme-radius-lg)',
    } as React.CSSProperties}
    className="relative z-0 min-h-screen flex items-center justify-center bg-[var(--local-bg)] overflow-hidden"
  >
    {/* Cinematic Background */}
    <div className="absolute inset-0">
      <img 
        src="https://images.unsplash.com/photo-1551524164-687a55dd1126?w=2000&q=90"
        alt="Dramatic view of snow-capped Dolomites peaks at golden hour with luxury alpine resort nestled in the valley"
        className="w-full h-full object-cover"
      />
      <div className="absolute inset-0 bg-gradient-to-t from-[var(--local-bg)]/95 via-[var(--local-bg)]/40 to-[var(--local-bg)]/20" />
    </div>

    {/* Decorative Elements */}
    <div className="absolute top-0 left-1/2 -translate-x-1/2 w-[1100px] h-[650px] bg-[radial-gradient(ellipse_at_50%_0%,var(--local-accent-soft),transparent_65%)] pointer-events-none" />
    
    {/* Content */}
    <div className="relative z-10 max-w-[900px] mx-auto px-8 text-center">
      {data.badge && (
        <div className="inline-flex items-center gap-2 bg-[var(--local-accent-soft)] border border-[var(--local-border)] px-4 py-1.5 rounded-full text-[0.70rem] font-mono font-semibold text-[var(--local-accent)] tracking-widest uppercase mb-8 jp-animate-in" data-jp-field="badge">
          <span className="w-1.5 h-1.5 rounded-full bg-[var(--local-primary)] jp-pulse-dot" />
          {data.badge}
        </div>
      )}
      
      <h1 className="font-display font-black text-[clamp(3rem,6vw,5.5rem)] leading-[1.0] tracking-tight text-[var(--local-text)] mb-6 jp-animate-in jp-d1" data-jp-field="title">
        {data.title}
        {data.titleHighlight && (
          <> <em className="not-italic bg-gradient-to-br from-[var(--local-accent)] to-[var(--local-primary)] bg-clip-text text-transparent" data-jp-field="titleHighlight">
            {data.titleHighlight}
          </em></>
        )}
      </h1>
      
      <p className="text-[var(--local-text-muted)] text-lg leading-relaxed max-w-[600px] mx-auto mb-10 jp-animate-in jp-d2" data-jp-field="description">
        {data.description}
      </p>
      
      <div className="flex flex-col sm:flex-row gap-4 justify-center items-center jp-animate-in jp-d3">
        <Button
          asChild
          className="inline-flex items-center gap-2 px-8 py-4 rounded-[var(--local-radius-md)] bg-[var(--local-primary)] text-[var(--local-primary-foreground)] font-semibold hover:opacity-90 transition-opacity"
        >
          <a href={data.primaryCta.href}>{data.primaryCta.label}</a>
        </Button>
        
        {data.secondaryCta && (
          <Button
            asChild
            variant="outline"
            className="inline-flex items-center gap-2 px-8 py-4 rounded-[var(--local-radius-md)] border border-[var(--local-border)] text-[var(--local-text)] font-semibold hover:border-[var(--local-accent)] transition"
          >
            <a href={data.secondaryCta.href}>{data.secondaryCta.label}</a>
          </Button>
        )}
      </div>
    </div>
    
    {/* Scroll Indicator */}
    <div className="absolute bottom-8 left-1/2 -translate-x-1/2 flex flex-col items-center gap-2 text-[var(--local-text-muted)] jp-animate-in jp-d4">
      <span className="text-xs uppercase tracking-wide font-mono">Scroll</span>
      <ChevronDown className="w-4 h-4 animate-bounce" />
    </div>
  </section>
);
END_OF_FILE_CONTENT
echo "Creating src/components/alpine-hero/index.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/alpine-hero/index.ts"
export { AlpineHero } from './View';
export { AlpineHeroSchema } from './schema';
export type { AlpineHeroData, AlpineHeroSettings } from './types';

END_OF_FILE_CONTENT
echo "Creating src/components/alpine-hero/schema.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/alpine-hero/schema.ts"
import { z } from 'zod';
import { BaseSectionData, CtaSchema } from '@olonjs/core';

export const AlpineHeroSchema = BaseSectionData.extend({
  badge: z.string().optional().describe('ui:text'),
  title: z.string().describe('ui:text'),
  titleHighlight: z.string().optional().describe('ui:text'),
  description: z.string().describe('ui:textarea'),
  primaryCta: CtaSchema,
  secondaryCta: CtaSchema.optional(),
});

END_OF_FILE_CONTENT
echo "Creating src/components/alpine-hero/types.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/alpine-hero/types.ts"
import { z } from 'zod';
import { BaseSectionSettingsSchema } from '@olonjs/core';
import { AlpineHeroSchema } from './schema';

export type AlpineHeroData = z.infer<typeof AlpineHeroSchema>;
export type AlpineHeroSettings = z.infer<typeof BaseSectionSettingsSchema>;

END_OF_FILE_CONTENT
mkdir -p "src/components/culinary-showcase"
echo "Creating src/components/culinary-showcase/View.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/culinary-showcase/View.tsx"
// Layout: Hero=A (SPLIT 60/40), Features=A (BENTO GRID)
import React from 'react';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import type { CulinaryShowcaseData, CulinaryShowcaseSettings } from './types';

export const CulinaryShowcase: React.FC<{ data: CulinaryShowcaseData; settings: CulinaryShowcaseSettings }> = ({ data }) => (
  <section
    style={{
      '--local-bg': 'var(--background)',
      '--local-text': 'var(--foreground)',
      '--local-text-muted': 'var(--muted-foreground)',
      '--local-accent': 'var(--accent)',
      '--local-surface': 'var(--card)',
      '--local-border': 'var(--border)',
      '--local-primary': 'var(--primary)',
      '--local-radius-lg': 'var(--theme-radius-lg)',
    } as React.CSSProperties}
    className="relative z-0 py-28 bg-[var(--local-bg)]"
  >
    <div className="max-w-[1200px] mx-auto px-8">
      {data.label && (
        <div className="jp-section-label inline-flex items-center gap-2 text-[0.72rem] font-bold uppercase tracking-[0.12em] text-[var(--local-accent)] mb-4" data-jp-field="label">
          <span className="w-5 h-px bg-[var(--local-primary)]" />
          {data.label}
        </div>
      )}
      
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-16 items-center mb-16">
        <div>
          <h2 className="font-display font-black text-[clamp(2rem,4.5vw,3.8rem)] leading-[1.05] tracking-tight text-[var(--local-text)] mb-6" data-jp-field="title">
            {data.title}
          </h2>
          
          {data.description && (
            <p className="text-[var(--local-text-muted)] text-lg leading-relaxed" data-jp-field="description">
              {data.description}
            </p>
          )}
        </div>
        
        {data.items[0]?.image?.url && (
          <div className="relative">
            <img 
              src={data.items[0].image.url}
              alt={data.items[0].image.alt}
              className="w-full h-[400px] object-cover rounded-[var(--local-radius-lg)]"
            />
          </div>
        )}
      </div>
      
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
        {data.items.map((item, idx) => (
          <Card
            key={item.id || `culinary-${idx}`}
            className="group relative overflow-hidden bg-[var(--local-surface)] border border-[var(--local-border)] rounded-[var(--local-radius-lg)] hover:shadow-lg transition-all duration-300"
            data-jp-item-id={item.id || `culinary-${idx}`}
            data-jp-item-field="items"
          >
            {item.image?.url && (
              <div className="aspect-[4/3] overflow-hidden">
                <img 
                  src={item.image.url}
                  alt={item.image.alt}
                  className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
                />
              </div>
            )}
            
            <CardContent className="p-6">
              {item.badge && (
                <Badge variant="secondary" className="mb-3 bg-[var(--local-accent)]/10 text-[var(--local-accent)] border-[var(--local-accent)]/20">
                  {item.badge}
                </Badge>
              )}
              
              <h3 className="font-display font-bold text-[1.2rem] leading-tight tracking-tight text-[var(--local-text)] mb-3">
                {item.title}
              </h3>
              
              <p className="text-[var(--local-text-muted)] leading-relaxed">
                {item.description}
              </p>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  </section>
);

END_OF_FILE_CONTENT
echo "Creating src/components/culinary-showcase/index.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/culinary-showcase/index.ts"
export { CulinaryShowcase } from './View';
export { CulinaryShowcaseSchema } from './schema';
export type { CulinaryShowcaseData, CulinaryShowcaseSettings } from './types';

END_OF_FILE_CONTENT
echo "Creating src/components/culinary-showcase/schema.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/culinary-showcase/schema.ts"
import { z } from 'zod';
import { BaseSectionData, BaseArrayItem, ImageSelectionSchema } from '@olonjs/core';

const CulinaryItemSchema = BaseArrayItem.extend({
  title: z.string().describe('ui:text'),
  description: z.string().describe('ui:textarea'),
  image: ImageSelectionSchema.optional(),
  badge: z.string().optional().describe('ui:text'),
});

export const CulinaryShowcaseSchema = BaseSectionData.extend({
  label: z.string().optional().describe('ui:text'),
  title: z.string().describe('ui:text'),
  description: z.string().optional().describe('ui:textarea'),
  items: z.array(CulinaryItemSchema).describe('ui:list'),
});

END_OF_FILE_CONTENT
echo "Creating src/components/culinary-showcase/types.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/culinary-showcase/types.ts"
import { z } from 'zod';
import { BaseSectionSettingsSchema } from '@olonjs/core';
import { CulinaryShowcaseSchema } from './schema';

export type CulinaryShowcaseData = z.infer<typeof CulinaryShowcaseSchema>;
export type CulinaryShowcaseSettings = z.infer<typeof BaseSectionSettingsSchema>;

END_OF_FILE_CONTENT
mkdir -p "src/components/empty-tenant"
echo "Creating src/components/empty-tenant/View.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/empty-tenant/View.tsx"
import type { EmptyTenantData } from './types';

type EmptyTenantViewProps = {
  data?: EmptyTenantData;
};

export function EmptyTenantView({ data }: EmptyTenantViewProps) {
  const title = data?.title?.trim() || 'Your tenant is empty.';
  const description = data?.description?.trim() || 'Create your first page to start building your site.';

  return (
    <main className="min-h-screen flex items-center justify-center bg-background text-foreground px-6">
      <section className="w-full max-w-xl rounded-xl border border-border bg-card p-8 shadow-sm">
        <h1 className="text-2xl font-semibold tracking-tight">{title}</h1>
        <p className="mt-3 text-sm text-muted-foreground">{description}</p>
      </section>
    </main>
  );
}

END_OF_FILE_CONTENT
echo "Creating src/components/empty-tenant/index.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/empty-tenant/index.ts"
export * from './View';
export * from './schema';
export * from './types';

END_OF_FILE_CONTENT
echo "Creating src/components/empty-tenant/schema.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/empty-tenant/schema.ts"
import { z } from 'zod';
import { BaseSectionData } from '@olonjs/core';

export const EmptyTenantSchema = BaseSectionData.extend({
  title: z.string().optional().describe('ui:text'),
  description: z.string().optional().describe('ui:textarea'),
});

export const EmptyTenantSettingsSchema = z.object({});

END_OF_FILE_CONTENT
echo "Creating src/components/empty-tenant/types.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/empty-tenant/types.ts"
import { z } from 'zod';
import { EmptyTenantSchema, EmptyTenantSettingsSchema } from './schema';

export type EmptyTenantData = z.infer<typeof EmptyTenantSchema>;
export type EmptyTenantSettings = z.infer<typeof EmptyTenantSettingsSchema>;

END_OF_FILE_CONTENT
mkdir -p "src/components/experience-timeline"
echo "Creating src/components/experience-timeline/View.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/experience-timeline/View.tsx"
// Layout: Hero=F (MINIMAL HERO), Features=C (TIMELINE)
import React from 'react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Clock } from 'lucide-react';
import type { ExperienceTimelineData, ExperienceTimelineSettings } from './types';

export const ExperienceTimeline: React.FC<{ data: ExperienceTimelineData; settings: ExperienceTimelineSettings }> = ({ data }) => {
  const difficultyColors = {
    'Easy': 'text-green-400 bg-green-400/10 border-green-400/20',
    'Moderate': 'text-yellow-400 bg-yellow-400/10 border-yellow-400/20',
    'Challenging': 'text-orange-400 bg-orange-400/10 border-orange-400/20',
    'Expert': 'text-red-400 bg-red-400/10 border-red-400/20',
  };

  return (
    <section
      style={{
        '--local-bg': 'var(--background)',
        '--local-text': 'var(--foreground)',
        '--local-text-muted': 'var(--muted-foreground)',
        '--local-accent': 'var(--accent)',
        '--local-surface': 'var(--card)',
        '--local-border': 'var(--border)',
        '--local-primary': 'var(--primary)',
        '--local-primary-foreground': 'var(--primary-foreground)',
        '--local-radius-lg': 'var(--theme-radius-lg)',
        '--local-radius-md': 'var(--theme-radius-md)',
      } as React.CSSProperties}
      className="relative z-0 py-28 bg-[var(--local-bg)]"
    >
      <div className="max-w-[1000px] mx-auto px-8">
        {data.label && (
          <div className="jp-section-label inline-flex items-center gap-2 text-[0.72rem] font-bold uppercase tracking-[0.12em] text-[var(--local-accent)] mb-4" data-jp-field="label">
            <span className="w-5 h-px bg-[var(--local-primary)]" />
            {data.label}
          </div>
        )}
        
        <h2 className="font-display font-black text-[clamp(2rem,4.5vw,3.8rem)] leading-[1.05] tracking-tight text-[var(--local-text)] mb-6" data-jp-field="title">
          {data.title}
        </h2>
        
        {data.description && (
          <p className="text-[var(--local-text-muted)] text-lg leading-relaxed mb-16 max-w-[700px]" data-jp-field="description">
            {data.description}
          </p>
        )}
        
        {/* Timeline */}
        <div className="relative">
          {/* Timeline Line */}
          <div className="absolute left-8 top-0 bottom-0 w-px bg-gradient-to-b from-[var(--local-primary)] via-[var(--local-accent)] to-[var(--local-primary)]" />
          
          <div className="space-y-16">
            {data.experiences.map((experience, idx) => (
              <div
                key={experience.id || `experience-${idx}`}
                className={`relative flex ${idx % 2 === 0 ? 'lg:flex-row' : 'lg:flex-row-reverse'} flex-col gap-12 items-center`}
                data-jp-item-id={experience.id || `experience-${idx}`}
                data-jp-item-field="experiences"
              >
                {/* Timeline Dot */}
                <div className="absolute left-8 lg:left-8 w-4 h-4 bg-[var(--local-primary)] rounded-full border-4 border-[var(--local-bg)] z-10" />
                
                {/* Content */}
                <div className={`flex-1 ${idx % 2 === 0 ? 'lg:pr-16 lg:pl-24' : 'lg:pl-16 lg:pr-24'} pl-24`}>
                  <div className="bg-[var(--local-surface)] border border-[var(--local-border)] rounded-[var(--local-radius-lg)] p-8">
                    <div className="flex items-center gap-3 mb-4">
                      {experience.season && (
                        <Badge variant="secondary" className="bg-[var(--local-accent)]/10 text-[var(--local-accent)] border-[var(--local-accent)]/20">
                          {experience.season}
                        </Badge>
                      )}
                      {experience.difficulty && (
                        <Badge className={`text-xs ${difficultyColors[experience.difficulty]}`}>
                          {experience.difficulty}
                        </Badge>
                      )}
                    </div>
                    
                    <h3 className="font-display font-bold text-[1.5rem] leading-tight tracking-tight text-[var(--local-text)] mb-3">
                      {experience.title}
                    </h3>
                    
                    {experience.duration && (
                      <div className="flex items-center gap-2 text-[var(--local-text-muted)] mb-4">
                        <Clock className="w-4 h-4" />
                        <span className="text-sm">{experience.duration}</span>
                      </div>
                    )}
                    
                    <p className="text-[var(--local-text-muted)] leading-relaxed mb-6">
                      {experience.description}
                    </p>
                    
                    {experience.cta && (
                      <Button
                        asChild
                        variant="outline"
                        className="rounded-[var(--local-radius-md)] border-[var(--local-border)] text-[var(--local-text)] hover:border-[var(--local-accent)] transition"
                      >
                        <a href={experience.cta.href}>{experience.cta.label}</a>
                      </Button>
                    )}
                  </div>
                </div>
                
                {/* Image */}
                <div className={`flex-1 ${idx % 2 === 0 ? 'lg:pl-16' : 'lg:pr-16'}`}>
                  {experience.image?.url && (
                    <div className="relative overflow-hidden rounded-[var(--local-radius-lg)]">
                      <img 
                        src={experience.image.url}
                        alt={experience.image.alt}
                        className="w-full h-[300px] object-cover hover:scale-105 transition-transform duration-700"
                      />
                    </div>
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
};
END_OF_FILE_CONTENT
echo "Creating src/components/experience-timeline/index.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/experience-timeline/index.ts"
export { ExperienceTimeline } from './View';
export { ExperienceTimelineSchema } from './schema';
export type { ExperienceTimelineData, ExperienceTimelineSettings } from './types';

END_OF_FILE_CONTENT
echo "Creating src/components/experience-timeline/schema.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/experience-timeline/schema.ts"
import { z } from 'zod';
import { BaseSectionData, BaseArrayItem, ImageSelectionSchema, CtaSchema } from '@olonjs/core';

const ExperienceItemSchema = BaseArrayItem.extend({
  title: z.string().describe('ui:text'),
  season: z.string().optional().describe('ui:text'),
  difficulty: z.enum(['Easy', 'Moderate', 'Challenging', 'Expert']).optional().describe('ui:select'),
  duration: z.string().optional().describe('ui:text'),
  description: z.string().describe('ui:textarea'),
  image: ImageSelectionSchema.optional(),
  cta: CtaSchema.optional(),
});

export const ExperienceTimelineSchema = BaseSectionData.extend({
  label: z.string().optional().describe('ui:text'),
  title: z.string().describe('ui:text'),
  description: z.string().optional().describe('ui:textarea'),
  experiences: z.array(ExperienceItemSchema).describe('ui:list'),
});

END_OF_FILE_CONTENT
echo "Creating src/components/experience-timeline/types.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/experience-timeline/types.ts"
import { z } from 'zod';
import { BaseSectionSettingsSchema } from '@olonjs/core';
import { ExperienceTimelineSchema } from './schema';

export type ExperienceTimelineData = z.infer<typeof ExperienceTimelineSchema>;
export type ExperienceTimelineSettings = z.infer<typeof BaseSectionSettingsSchema>;

END_OF_FILE_CONTENT
mkdir -p "src/components/footer"
echo "Creating src/components/footer/View.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/footer/View.tsx"
// Layout: Footer with brand column, contact info, and links
import React from 'react';
import { Separator } from '@/components/ui/separator';
import { Mail, MapPin, Phone } from 'lucide-react';
import type { FooterData, FooterSettings } from './types';

export const Footer: React.FC<{ data: FooterData; settings: FooterSettings }> = ({ data }) => {
  const navItems = Array.isArray(data.menu) ? data.menu : [];

  return (
    <footer
      style={{
        '--local-bg': 'var(--card)',
        '--local-text': 'var(--foreground)',
        '--local-text-muted': 'var(--muted-foreground)',
        '--local-border': 'var(--border)',
        '--local-primary': 'var(--primary)',
        '--local-accent': 'var(--accent)',
      } as React.CSSProperties}
      className="relative z-0 border-t border-[var(--local-border)] bg-[var(--local-bg)] py-20"
    >
      <div className="max-w-[1200px] mx-auto px-8">
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-12 mb-12">
          {/* Brand Column */}
          <div className="lg:col-span-2">
            <div className="flex items-baseline gap-2 mb-4">
              <h3
                className="font-display text-2xl font-black tracking-tight text-[var(--local-text)]"
                style={{
                  fontFamily: '"Cormorant Garamond", Helvetica, Arial, sans-serif',
                  fontWeight: '600',
                  letterSpacing: '-0.04em'
                }}
                data-jp-field="brandText"
              >
                {data.brandText}
              </h3>
              {data.brandHighlight && (
                <span className="font-mono text-[0.72rem] uppercase tracking-[0.24em] text-[var(--local-primary)]" data-jp-field="brandHighlight">
                  {data.brandHighlight}
                </span>
              )}
            </div>
            
            {data.tagline && (
              <p className="text-[var(--local-text-muted)] text-lg leading-relaxed mb-6" data-jp-field="tagline">
                {data.tagline}
              </p>
            )}
          </div>
          
          {/* Contact Info */}
          <div>
            <h3 className="font-display font-bold text-[var(--local-text)] text-lg mb-6">Contact</h3>
            <div className="space-y-4">
              {data.address && (
                <div className="flex items-start gap-3">
                  <MapPin className="w-4 h-4 text-[var(--local-accent)] mt-1 flex-shrink-0" />
                  <address className="text-[var(--local-text-muted)] text-sm leading-relaxed not-italic" data-jp-field="address">
                    {data.address}
                  </address>
                </div>
              )}
              
              {data.phone && (
                <div className="flex items-center gap-3">
                  <Phone className="w-4 h-4 text-[var(--local-accent)]" />
                  <a href={`tel:${data.phone}`} className="text-[var(--local-text-muted)] text-sm hover:text-[var(--local-accent)] transition" data-jp-field="phone">
                    {data.phone}
                  </a>
                </div>
              )}
              
              {data.email && (
                <div className="flex items-center gap-3">
                  <Mail className="w-4 h-4 text-[var(--local-accent)]" />
                  <a href={`mailto:${data.email}`} className="text-[var(--local-text-muted)] text-sm hover:text-[var(--local-accent)] transition" data-jp-field="email">
                    {data.email}
                  </a>
                </div>
              )}
            </div>
          </div>
          
          {/* Links */}
          <div>
            <h3 className="font-display font-bold text-[var(--local-text)] text-lg mb-6">Links</h3>
            <nav className="space-y-3">
              {navItems.map((item, idx) => (
                <a
                  key={item.href + '-footer-' + idx}
                  href={item.href}
                  className="block text-[var(--local-text-muted)] text-sm hover:text-[var(--local-accent)] transition"
                  data-jp-item-id={`footer-link-${idx}`}
                  data-jp-item-field="menu"
                >
                  {item.label}
                </a>
              ))}
            </nav>
          </div>
        </div>
        
        <Separator className="bg-[var(--local-border)] mb-8" />
        
        <div className="text-center">
          <p className="text-[var(--local-text-muted)] text-sm" data-jp-field="copyright">
            {data.copyright}
          </p>
        </div>
      </div>
    </footer>
  );
};

END_OF_FILE_CONTENT
echo "Creating src/components/footer/index.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/footer/index.ts"
export { Footer } from './View';
export { FooterSchema } from './schema';
export type { FooterData, FooterSettings } from './types';

END_OF_FILE_CONTENT
echo "Creating src/components/footer/schema.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/footer/schema.ts"
import { z } from 'zod';
import { BaseSectionData } from '@olonjs/core';

const FooterMenuItemSchema = z.object({
  label: z.string(),
  href: z.string(),
});

export const FooterSchema = BaseSectionData.extend({
  brandText: z.string().describe('ui:text'),
  brandHighlight: z.string().optional().describe('ui:text'),
  tagline: z.string().optional().describe('ui:text'),
  address: z.string().optional().describe('ui:textarea'),
  phone: z.string().optional().describe('ui:text'),
  email: z.string().optional().describe('ui:text'),
  copyright: z.string().describe('ui:text'),
  menu: z.array(FooterMenuItemSchema).optional().describe('ui:list'),
});

END_OF_FILE_CONTENT
echo "Creating src/components/footer/types.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/footer/types.ts"
import { z } from 'zod';
import { BaseSectionSettingsSchema } from '@olonjs/core';
import { FooterSchema } from './schema';

export type FooterData = z.infer<typeof FooterSchema>;
export type FooterSettings = z.infer<typeof BaseSectionSettingsSchema>;

END_OF_FILE_CONTENT
mkdir -p "src/components/form-demo"
echo "Creating src/components/form-demo/View.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/form-demo/View.tsx"
import { Icon } from '@/lib/IconResolver';
import { useFormState } from '@olonjs/core';
import type { FormDemoData } from './types';

type FormDemoViewProps = {
  data: FormDemoData;
};

const missingEnv =
  !import.meta.env.VITE_JSONPAGES_CLOUD_URL &&
  !import.meta.env.VITE_OLONJS_CLOUD_URL;

function SetupGuide({ recipientEmail }: { recipientEmail?: string }) {
  const steps = [
    {
      done: !!recipientEmail,
      label: 'recipientEmail nel JSON della sezione',
      code: '"recipientEmail": "tu@esempio.it"',
    },
    {
      done: !missingEnv,
      label: 'VITE_JSONPAGES_CLOUD_URL nel file .env',
      code: 'VITE_JSONPAGES_CLOUD_URL=https://cloud.olonjs.io',
    },
    {
      done: !!import.meta.env.VITE_JSONPAGES_API_KEY || !!import.meta.env.VITE_OLONJS_API_KEY,
      label: 'VITE_JSONPAGES_API_KEY nel file .env',
      code: 'VITE_JSONPAGES_API_KEY=sk-...',
    },
  ];

  const allDone = steps.every((s) => s.done);
  if (allDone) return null;

  return (
    <div className="rounded-lg border border-border bg-muted/40 p-4 space-y-3 text-sm">
      <p className="font-medium text-foreground">Quasi pronto — completa questi passaggi</p>
      <ol className="space-y-2">
        {steps.map((step, i) => (
          <li key={i} className="flex items-start gap-2">
            <span className={step.done ? 'text-green-500' : 'text-muted-foreground'}>
              {step.done ? '✓' : `${i + 1}.`}
            </span>
            <span className={step.done ? 'text-muted-foreground line-through' : 'text-foreground'}>
              {step.label}
              {!step.done && (
                <code className="block mt-0.5 text-xs bg-background rounded px-1.5 py-0.5 font-mono text-muted-foreground border border-border">
                  {step.code}
                </code>
              )}
            </span>
          </li>
        ))}
      </ol>
    </div>
  );
}

export function FormDemoView({ data }: FormDemoViewProps) {
  const formId = data.anchorId?.trim() || 'form-demo';
  const { status, message } = useFormState(formId);

  return (
    <main className="min-h-screen flex items-center justify-center bg-background text-foreground px-6">
      <section className="w-full max-w-xl rounded-xl border border-border bg-card p-8 shadow-sm space-y-6">
        {data.icon && (
          <div data-jp-field="icon" className="mb-2">
            <Icon name={data.icon} size={24} />
          </div>
        )}
        {data.title && (
          <div>
            <h1
              data-jp-field="title"
              className="text-2xl font-semibold tracking-tight"
            >
              {data.title}
            </h1>
            {data.description && (
              <p
                data-jp-field="description"
                className="mt-3 text-sm text-muted-foreground"
              >
                {data.description}
              </p>
            )}
          </div>
        )}

        <SetupGuide recipientEmail={data.recipientEmail} />

        <form
          id={formId}
          data-olon-recipient={data.recipientEmail ?? ''}
          className="space-y-4"
        >
          <div>
            <label className="block text-xs font-medium text-muted-foreground mb-1">
              Nome
            </label>
            <input
              name="name"
              type="text"
              required
              className="w-full rounded-md border border-border bg-background px-3 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-primary"
            />
          </div>

          <div>
            <label className="block text-xs font-medium text-muted-foreground mb-1">
              Email
            </label>
            <input
              name="email"
              type="email"
              required
              className="w-full rounded-md border border-border bg-background px-3 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-primary"
            />
          </div>

          <div>
            <label className="block text-xs font-medium text-muted-foreground mb-1">
              Messaggio
            </label>
            <textarea
              name="message"
              required
              rows={4}
              className="w-full rounded-md border border-border bg-background px-3 py-2 text-sm resize-none focus:outline-none focus:ring-1 focus:ring-primary"
            />
          </div>

          {status === 'error' && (
            <p className="text-xs text-destructive">{message}</p>
          )}
          {status === 'success' && (
            <p className="text-xs text-green-600">
              {data.successMessage || message}
            </p>
          )}

          <button
            type="submit"
            disabled={status === 'submitting'}
            className="w-full rounded-md bg-primary text-primary-foreground px-4 py-2 text-sm font-medium hover:opacity-90 disabled:opacity-60 disabled:cursor-not-allowed transition-opacity"
          >
            {status === 'submitting' ? 'Invio...' : (data.submitLabel || 'Invia')}
          </button>
        </form>
      </section>
    </main>
  );
}

END_OF_FILE_CONTENT
echo "Creating src/components/form-demo/index.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/form-demo/index.ts"
export * from './View';
export * from './schema';
export * from './types';

END_OF_FILE_CONTENT
echo "Creating src/components/form-demo/schema.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/form-demo/schema.ts"
import { z } from 'zod';
import { BaseSectionData, WithFormRecipient } from '@olonjs/core';

export const FormDemoSchema = BaseSectionData.merge(WithFormRecipient).extend({
  icon: z.string().optional().describe('ui:icon-picker'),
  title: z.string().optional().describe('ui:text'),
  description: z.string().optional().describe('ui:textarea'),
  submitLabel: z.string().default('Invia').describe('ui:text'),
  successMessage: z.string().default('Richiesta inviata con successo.').describe('ui:text'),
});

export const FormDemoSettingsSchema = z.object({});

/**
 * Submission payload schema for the `form-demo` section.
 *
 * Describes the fields actually submitted by the rendered `<form>` in View.tsx
 * (name, email, message). Exposed via `JsonPagesConfig.submissionSchemas` so that
 * MCP agents can discover the submission contract for this section type without
 * scraping the DOM. See ADR-0002 (docs/decisions/ADR-0002-form-submission-schemas.md).
 */
export const FormDemoSubmissionSchema = z.object({
  name: z.string().min(1).describe('Full name of the person submitting the form'),
  email: z.string().email().describe('Contact email address where we will reply'),
  message: z.string().min(1).describe('Free-form message body'),
});

END_OF_FILE_CONTENT
echo "Creating src/components/form-demo/types.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/form-demo/types.ts"
import { z } from 'zod';
import { FormDemoSchema, FormDemoSettingsSchema } from './schema';

export type FormDemoData = z.infer<typeof FormDemoSchema>;
export type FormDemoSettings = z.infer<typeof FormDemoSettingsSchema>;

END_OF_FILE_CONTENT
mkdir -p "src/components/header"
echo "Creating src/components/header/View.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/header/View.tsx"
// Layout: Hero=F (MINIMAL HERO), Features=B (HORIZONTAL SCROLL)
import React from 'react';
import { Button } from '@/components/ui/button';
import {
  NavigationMenu,
  NavigationMenuItem,
  NavigationMenuLink,
  NavigationMenuList,
} from '@/components/ui/navigation-menu';
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetTrigger } from '@/components/ui/sheet';
import { Menu, Moon, Sun } from 'lucide-react';
import { useTheme } from '@/components/ThemeProvider';
import type { HeaderData, HeaderSettings } from './types';

export const Header: React.FC<{ data: HeaderData; settings: HeaderSettings }> = ({ data }) => {
  const navItems = Array.isArray(data.menu) ? data.menu : [];
  const { theme, toggleTheme } = useTheme();

  return (
    <header
      style={{
        '--local-bg': 'color-mix(in oklch, var(--background) 90%, transparent)',
        '--local-text': 'var(--foreground)',
        '--local-border': 'var(--border)',
        '--local-surface': 'color-mix(in oklch, var(--card) 88%, transparent)',
        '--local-primary': 'var(--primary)',
        '--local-primary-foreground': 'var(--primary-foreground)',
        '--local-radius-md': 'var(--theme-radius-md)',
        '--local-radius-lg': 'var(--theme-radius-lg)',
      } as React.CSSProperties}
      className="sticky top-0 z-10 border-b border-[var(--local-border)] bg-[var(--local-bg)]/95 backdrop-blur-xl"
    >
      <div className="max-w-[1200px] mx-auto px-8">
        {data.announcement && (
          <div className="border-b border-[var(--local-border)] py-2 text-center text-[0.72rem] font-mono uppercase tracking-[0.16em] text-[var(--local-text)]/70" data-jp-field="announcement">
            {data.announcement}
          </div>
        )}
        <div className="flex h-20 items-center justify-between gap-6">
          <a href="/" className="flex items-baseline gap-2">
            <span
              className="font-display text-2xl font-black tracking-tight text-[var(--local-text)]"
              style={{
                fontFamily: '"Cormorant Garamond", Helvetica, Arial, sans-serif',
                fontWeight: '600',
                letterSpacing: '-0.04em'
              }}
              data-jp-field="logoText"
            >
              {data.logoText}
            </span>
            {data.logoHighlight && (
              <span className="font-mono text-[0.72rem] uppercase tracking-[0.24em] text-[var(--local-primary)]" data-jp-field="logoHighlight">
                {data.logoHighlight}
              </span>
            )}
          </a>

          <div className="hidden items-center gap-4 lg:flex">
            <NavigationMenu>
              <NavigationMenuList className="gap-1">
                {navItems.map((item, idx) => (
                  <NavigationMenuItem key={item.href + '-' + idx}>
                    <NavigationMenuLink
                      href={item.href}
                      className="rounded-[var(--local-radius-md)] px-4 py-2 text-sm font-medium text-[var(--local-text)] transition hover:bg-[var(--local-surface)]"
                    >
                      {item.label}
                    </NavigationMenuLink>
                  </NavigationMenuItem>
                ))}
              </NavigationMenuList>
            </NavigationMenu>
            <Button
              type="button"
              variant="outline"
              onClick={toggleTheme}
              className="rounded-[var(--local-radius-md)] border-[var(--local-border)] bg-[var(--local-surface)] text-[var(--local-text)]"
            >
              {theme === 'dark' ? <Sun className="h-4 w-4" /> : <Moon className="h-4 w-4" />}
            </Button>
          </div>

          <div className="flex items-center gap-3 lg:hidden">
            <Button
              type="button"
              variant="outline"
              onClick={toggleTheme}
              className="rounded-[var(--local-radius-md)] border-[var(--local-border)] bg-[var(--local-surface)] text-[var(--local-text)]"
            >
              {theme === 'dark' ? <Sun className="h-4 w-4" /> : <Moon className="h-4 w-4" />}
            </Button>
            <Sheet>
              <SheetTrigger asChild>
                <Button variant="outline" className="rounded-[var(--local-radius-md)] border-[var(--local-border)] bg-[var(--local-surface)] text-[var(--local-text)]">
                  <Menu className="h-4 w-4" />
                </Button>
              </SheetTrigger>
              <SheetContent className="border-[var(--local-border)] bg-[var(--card)] text-[var(--foreground)]">
                <SheetHeader>
                  <SheetTitle className="font-display text-[var(--foreground)]">Navigation</SheetTitle>
                </SheetHeader>
                <div className="mt-8 flex flex-col gap-3">
                  {navItems.map((item, idx) => (
                    <a
                      key={item.href + '-mobile-' + idx}
                      href={item.href}
                      className="rounded-[var(--local-radius-md)] border border-[var(--local-border)] px-4 py-3 text-sm font-medium text-[var(--local-text)]"
                    >
                      {item.label}
                    </a>
                  ))}
                </div>
              </SheetContent>
            </Sheet>
          </div>
        </div>
      </div>
    </header>
  );
};

END_OF_FILE_CONTENT
echo "Creating src/components/header/index.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/header/index.ts"
export { Header } from './View';
export { HeaderSchema } from './schema';
export type { HeaderData, HeaderSettings } from './types';

END_OF_FILE_CONTENT
echo "Creating src/components/header/schema.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/header/schema.ts"
import { z } from 'zod';
import { BaseSectionData } from '@olonjs/core';

const HeaderMenuItemSchema = z.object({
  label: z.string(),
  href: z.string(),
});

export const HeaderSchema = BaseSectionData.extend({
  logoText: z.string().describe('ui:text'),
  logoHighlight: z.string().optional().describe('ui:text'),
  announcement: z.string().optional().describe('ui:text'),
  menu: z.array(HeaderMenuItemSchema).optional().describe('ui:list'),
});

END_OF_FILE_CONTENT
echo "Creating src/components/header/types.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/header/types.ts"
import { z } from 'zod';
import { BaseSectionSettingsSchema } from '@olonjs/core';
import { HeaderSchema } from './schema';

export type HeaderData = z.infer<typeof HeaderSchema>;
export type HeaderSettings = z.infer<typeof BaseSectionSettingsSchema>;

END_OF_FILE_CONTENT
mkdir -p "src/components/newsletter-cta"
echo "Creating src/components/newsletter-cta/View.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/newsletter-cta/View.tsx"
// Layout: Hero=F (MINIMAL HERO), Features=F (MINIMAL HERO)
import React from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import type { NewsletterCtaData, NewsletterCtaSettings } from './types';

export const NewsletterCta: React.FC<{ data: NewsletterCtaData; settings: NewsletterCtaSettings }> = ({ data }) => (
  <section
    style={{
      '--local-bg': 'color-mix(in oklch, var(--accent) 8%, var(--background))',
      '--local-text': 'var(--foreground)',
      '--local-text-muted': 'var(--muted-foreground)',
      '--local-accent': 'var(--accent)',
      '--local-primary': 'var(--primary)',
      '--local-primary-foreground': 'var(--primary-foreground)',
      '--local-border': 'var(--border)',
      '--local-surface': 'var(--card)',
      '--local-radius-md': 'var(--theme-radius-md)',
    } as React.CSSProperties}
    className="relative z-0 py-28 bg-[var(--local-bg)]"
  >
    <div className="max-w-[800px] mx-auto px-8 text-center">
      <h2 className="font-display font-black text-[clamp(3rem,7vw,6.5rem)] leading-[1.0] tracking-tight text-[var(--local-text)] mb-6" data-jp-field="title">
        {data.title}
      </h2>
      
      {data.description && (
        <p className="text-[var(--local-text-muted)] text-lg leading-relaxed mb-12 max-w-[600px] mx-auto" data-jp-field="description">
          {data.description}
        </p>
      )}
      
      <form className="flex flex-col sm:flex-row gap-4 max-w-[500px] mx-auto" onSubmit={(e) => e.preventDefault()}>
        <Input
          type="email"
          placeholder={data.placeholder || "Enter your email"}
          className="flex-1 bg-[var(--local-surface)] border-[var(--local-border)] text-[var(--local-text)] rounded-[var(--local-radius-md)]"
        />
        <Button
          type="submit"
          className="px-8 py-2 rounded-[var(--local-radius-md)] bg-[var(--local-primary)] text-[var(--local-primary-foreground)] font-semibold hover:opacity-90 transition-opacity"
        >
          {data.cta.label}
        </Button>
      </form>
    </div>
  </section>
);

END_OF_FILE_CONTENT
echo "Creating src/components/newsletter-cta/index.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/newsletter-cta/index.ts"
export { NewsletterCta } from './View';
export { NewsletterCtaSchema } from './schema';
export type { NewsletterCtaData, NewsletterCtaSettings } from './types';

END_OF_FILE_CONTENT
echo "Creating src/components/newsletter-cta/schema.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/newsletter-cta/schema.ts"
import { z } from 'zod';
import { BaseSectionData, CtaSchema } from '@olonjs/core';

export const NewsletterCtaSchema = BaseSectionData.extend({
  title: z.string().describe('ui:text'),
  description: z.string().optional().describe('ui:textarea'),
  placeholder: z.string().optional().describe('ui:text'),
  cta: CtaSchema,
});

END_OF_FILE_CONTENT
echo "Creating src/components/newsletter-cta/types.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/newsletter-cta/types.ts"
import { z } from 'zod';
import { BaseSectionSettingsSchema } from '@olonjs/core';
import { NewsletterCtaSchema } from './schema';

export type NewsletterCtaData = z.infer<typeof NewsletterCtaSchema>;
export type NewsletterCtaSettings = z.infer<typeof BaseSectionSettingsSchema>;

END_OF_FILE_CONTENT
mkdir -p "src/components/page-hero"
echo "Creating src/components/page-hero/View.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/page-hero/View.tsx"
import React from 'react';
import type { PageHeroData, PageHeroSettings } from './types';

export const PageHero: React.FC<{ data: PageHeroData; settings: PageHeroSettings }> = ({ data }) => (
  <section
    style={{
      '--local-bg': 'var(--background)',
      '--local-text': 'var(--foreground)',
      '--local-text-muted': 'var(--muted-foreground)',
      '--local-accent': 'var(--accent)',
      '--local-border': 'var(--border)',
    } as React.CSSProperties}
    className="relative z-0 py-24 bg-[var(--local-bg)]"
  >
    <div className="max-w-[1200px] mx-auto px-8">
      {data.breadcrumbs && data.breadcrumbs.length > 0 && (
        <nav className="flex items-center gap-2 text-sm text-[var(--local-text-muted)] mb-8">
          {data.breadcrumbs.map((crumb, idx) => (
            <React.Fragment key={crumb.id || `crumb-${idx}`}>
              <a href={crumb.href} className="hover:text-[var(--local-accent)] transition">
                {crumb.label}
              </a>
              {idx < (data.breadcrumbs?.length ?? 0) - 1 && <span>/</span>}
            </React.Fragment>
          ))}
        </nav>
      )}
      
      <h1 className="font-display font-black text-[clamp(2rem,4.5vw,3.8rem)] leading-[1.05] tracking-tight text-[var(--local-text)] mb-6" data-jp-field="title">
        {data.title}
      </h1>
      
      {data.description && (
        <p className="text-[var(--local-text-muted)] text-lg leading-relaxed max-w-[700px]" data-jp-field="description">
          {data.description}
        </p>
      )}
    </div>
  </section>
);
END_OF_FILE_CONTENT
echo "Creating src/components/page-hero/index.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/page-hero/index.ts"
export { PageHero } from './View';
export { PageHeroSchema } from './schema';
export type { PageHeroData, PageHeroSettings } from './types';

END_OF_FILE_CONTENT
echo "Creating src/components/page-hero/schema.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/page-hero/schema.ts"
import { z } from 'zod';
import { BaseSectionData } from '@olonjs/core';

export const PageHeroSchema = BaseSectionData.extend({
  title: z.string().describe('ui:text'),
  description: z.string().optional().describe('ui:textarea'),
  breadcrumbs: z.array(z.object({
    id: z.string(),
    label: z.string(),
    href: z.string(),
  })).optional().describe('ui:list'),
});

END_OF_FILE_CONTENT
echo "Creating src/components/page-hero/types.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/page-hero/types.ts"
import { z } from 'zod';
import { BaseSectionSettingsSchema } from '@olonjs/core';
import { PageHeroSchema } from './schema';

export type PageHeroData = z.infer<typeof PageHeroSchema>;
export type PageHeroSettings = z.infer<typeof BaseSectionSettingsSchema>;

END_OF_FILE_CONTENT
mkdir -p "src/components/resort-highlights"
echo "Creating src/components/resort-highlights/View.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/resort-highlights/View.tsx"
// Layout: Hero=C (FULLSCREEN CINEMATIC), Features=A (BENTO GRID)
import React from 'react';
import { Card, CardContent } from '@/components/ui/card';
import type { ResortHighlightsData, ResortHighlightsSettings } from './types';

export const ResortHighlights: React.FC<{ data: ResortHighlightsData; settings: ResortHighlightsSettings }> = ({ data }) => (
  <section
    style={{
      '--local-bg': 'var(--background)',
      '--local-text': 'var(--foreground)',
      '--local-text-muted': 'var(--muted-foreground)',
      '--local-accent': 'var(--accent)',
      '--local-surface': 'var(--card)',
      '--local-border': 'var(--border)',
      '--local-radius-lg': 'var(--theme-radius-lg)',
      '--local-primary': 'var(--primary)',
    } as React.CSSProperties}
    className="relative z-0 py-28 bg-[var(--local-bg)]"
  >
    <div className="max-w-[1200px] mx-auto px-8">
      {data.label && (
        <div className="jp-section-label inline-flex items-center gap-2 text-[0.72rem] font-bold uppercase tracking-[0.12em] text-[var(--local-accent)] mb-4" data-jp-field="label">
          <span className="w-5 h-px bg-[var(--local-primary)]" />
          {data.label}
        </div>
      )}
      
      <h2 className="font-display font-black text-[clamp(2rem,4.5vw,3.8rem)] leading-[1.05] tracking-tight text-[var(--local-text)] mb-16" data-jp-field="title">
        {data.title}
      </h2>
      
      {/* Bento Grid Layout */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 auto-rows-[300px]">
        {data.highlights.map((highlight, idx) => (
          <Card
            key={highlight.id || `highlight-${idx}`}
            className={`group relative overflow-hidden bg-[var(--local-surface)] border border-[var(--local-border)] rounded-[var(--local-radius-lg)] hover:shadow-2xl transition-all duration-500 ${
              idx === 0 ? 'lg:col-span-2 lg:row-span-1' : 
              idx === 1 ? 'lg:row-span-2' : 
              idx === 3 ? 'md:col-span-2 lg:col-span-1' : ''
            }`}
            data-jp-item-id={highlight.id || `highlight-${idx}`}
            data-jp-item-field="highlights"
          >
            {highlight.image?.url && (
              <div className="absolute inset-0">
                <img 
                  src={highlight.image.url}
                  alt={highlight.image.alt}
                  className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-700"
                />
                <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-black/20 to-transparent" />
              </div>
            )}
            
            <CardContent className="relative z-10 h-full flex flex-col justify-end p-8">
              {highlight.category && (
                <div className="inline-flex items-center px-3 py-1 bg-[var(--local-accent)]/20 border border-[var(--local-accent)]/30 rounded-full text-xs font-mono uppercase tracking-wide text-[var(--local-accent)] mb-4 self-start">
                  {highlight.category}
                </div>
              )}
              
              <h3 className="font-display font-bold text-[1.2rem] leading-tight tracking-tight text-white mb-3">
                {highlight.title}
              </h3>
              
              <p className="text-white/80 text-sm leading-relaxed">
                {highlight.description}
              </p>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  </section>
);

END_OF_FILE_CONTENT
echo "Creating src/components/resort-highlights/index.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/resort-highlights/index.ts"
export { ResortHighlights } from './View';
export { ResortHighlightsSchema } from './schema';
export type { ResortHighlightsData, ResortHighlightsSettings } from './types';

END_OF_FILE_CONTENT
echo "Creating src/components/resort-highlights/schema.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/resort-highlights/schema.ts"
import { z } from 'zod';
import { BaseSectionData, BaseArrayItem, ImageSelectionSchema } from '@olonjs/core';

const HighlightItemSchema = BaseArrayItem.extend({
  title: z.string().describe('ui:text'),
  description: z.string().describe('ui:textarea'),
  image: ImageSelectionSchema.optional(),
  category: z.string().optional().describe('ui:text'),
});

export const ResortHighlightsSchema = BaseSectionData.extend({
  label: z.string().optional().describe('ui:text'),
  title: z.string().describe('ui:text'),
  highlights: z.array(HighlightItemSchema).describe('ui:list'),
});

END_OF_FILE_CONTENT
echo "Creating src/components/resort-highlights/types.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/resort-highlights/types.ts"
import { z } from 'zod';
import { BaseSectionSettingsSchema } from '@olonjs/core';
import { ResortHighlightsSchema } from './schema';

export type ResortHighlightsData = z.infer<typeof ResortHighlightsSchema>;
export type ResortHighlightsSettings = z.infer<typeof BaseSectionSettingsSchema>;

END_OF_FILE_CONTENT
mkdir -p "src/components/save-drawer"
echo "Creating src/components/save-drawer/DeployConnector.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/save-drawer/DeployConnector.tsx"
import type { StepState } from '@olonjs/core';

interface DeployConnectorProps {
  fromState: StepState;
  toState: StepState;
  color: string;
}

export function DeployConnector({ fromState, toState, color }: DeployConnectorProps) {
  const filled = fromState === 'done' && toState === 'done';
  const filling = fromState === 'done' && toState === 'active';
  const lit = filled || filling;

  return (
    <div className="jp-drawer-connector">
      <div className="jp-drawer-connector-base" />

      <div
        className="jp-drawer-connector-fill"
        style={{
          background: `linear-gradient(90deg, ${color}cc, ${color}66)`,
          width: filled ? '100%' : filling ? '100%' : '0%',
          transition: filling ? 'width 2s cubic-bezier(0.4,0,0.2,1)' : 'none',
          boxShadow: lit ? `0 0 8px ${color}77` : 'none',
        }}
      />

      {filling && (
        <div
          className="jp-drawer-connector-orb"
          style={{
            background: color,
            boxShadow: `0 0 14px ${color}, 0 0 28px ${color}88`,
            animation: 'orb-travel 2s cubic-bezier(0.4,0,0.6,1) forwards',
          }}
        />
      )}
    </div>
  );
}


END_OF_FILE_CONTENT
echo "Creating src/components/save-drawer/DeployNode.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/save-drawer/DeployNode.tsx"
import type { CSSProperties } from 'react';
import type { DeployStep, StepState } from '@olonjs/core';

interface DeployNodeProps {
  step: DeployStep;
  state: StepState;
}

export function DeployNode({ step, state }: DeployNodeProps) {
  const isActive = state === 'active';
  const isDone = state === 'done';
  const isPending = state === 'pending';

  return (
    <div className="jp-drawer-node-wrap">
      <div
        className={`jp-drawer-node ${isPending ? 'jp-drawer-node-pending' : ''}`}
        style={
          {
            background: isDone ? step.color : isActive ? 'rgba(0,0,0,0.5)' : undefined,
            borderWidth: isDone ? 0 : 1,
            borderColor: isActive ? `${step.color}80` : undefined,
            boxShadow: isDone
              ? `0 0 20px ${step.color}55, 0 0 40px ${step.color}22`
              : isActive
                ? `0 0 14px ${step.color}33`
                : undefined,
            animation: isActive ? 'node-glow 2s ease infinite' : undefined,
            ['--glow-color' as string]: step.color,
          } as CSSProperties
        }
      >
        {isDone && (
          <svg className="h-5 w-5" viewBox="0 0 24 24" fill="none" aria-label="Done">
            <path
              className="stroke-dash-30 animate-check-draw"
              d="M5 13l4 4L19 7"
              stroke="#0a0f1a"
              strokeWidth="2.5"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          </svg>
        )}

        {isActive && (
          <span
            className="jp-drawer-node-glyph jp-drawer-node-glyph-active"
            style={{ color: step.color, animation: 'glyph-rotate 9s linear infinite' }}
            aria-hidden
          >
            {step.glyph}
          </span>
        )}

        {isPending && (
          <span className="jp-drawer-node-glyph jp-drawer-node-glyph-pending" aria-hidden>
            {step.glyph}
          </span>
        )}

        {isActive && (
          <span
            className="jp-drawer-node-ring"
            style={{
              inset: -7,
              borderColor: `${step.color}50`,
              animation: 'ring-expand 2s ease-out infinite',
            }}
          />
        )}
      </div>

      <span
        className="jp-drawer-node-label"
        style={{ color: isDone ? step.color : isActive ? 'rgba(255,255,255,0.85)' : 'rgba(255,255,255,0.18)' }}
      >
        {step.label}
      </span>
    </div>
  );
}


END_OF_FILE_CONTENT
echo "Creating src/components/save-drawer/DopaDrawer.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/save-drawer/DopaDrawer.tsx"
import { useEffect, useMemo, useState } from 'react';
import { createPortal } from 'react-dom';
import type { StepId, StepState } from '@olonjs/core';
import { DEPLOY_STEPS } from '@olonjs/core';
import fontsCss from '@/fonts.css?inline';
import saverStyleCss from './saverStyle.css?inline';
import { DeployNode } from './DeployNode';
import { DeployConnector } from './DeployConnector';
import { BuildBars, ElapsedTimer, Particles, SuccessBurst } from './Visuals';

interface DopaDrawerProps {
  isOpen: boolean;
  phase: 'idle' | 'running' | 'done' | 'error';
  currentStepId: StepId | null;
  doneSteps: StepId[];
  progress: number;
  errorMessage?: string;
  deployUrl?: string;
  onClose: () => void;
  onRetry: () => void;
}

export function DopaDrawer({
  isOpen,
  phase,
  currentStepId,
  doneSteps,
  progress,
  errorMessage,
  deployUrl,
  onClose,
  onRetry,
}: DopaDrawerProps) {
  const [shadowMount, setShadowMount] = useState<HTMLElement | null>(null);
  const [burst, setBurst] = useState(false);
  const [countdown, setCountdown] = useState(3);

  const isRunning = phase === 'running';
  const isDone = phase === 'done';
  const isError = phase === 'error';

  useEffect(() => {
    const host = document.createElement('div');
    host.setAttribute('data-jp-drawer-shadow-host', '');

    const shadowRoot = host.attachShadow({ mode: 'open' });
    const style = document.createElement('style');
    style.textContent = `${fontsCss}\n${saverStyleCss}`;

    const mount = document.createElement('div');
    shadowRoot.append(style, mount);

    document.body.appendChild(host);
    setShadowMount(mount);

    return () => {
      setShadowMount(null);
      host.remove();
    };
  }, []);

  useEffect(() => {
    if (!isOpen) {
      setBurst(false);
      setCountdown(3);
      return;
    }
    if (isDone) setBurst(true);
  }, [isDone, isOpen]);

  useEffect(() => {
    if (!isOpen || !isDone) return;
    setCountdown(3);
    const interval = window.setInterval(() => {
      setCountdown((prev) => {
        if (prev <= 1) {
          window.clearInterval(interval);
          onClose();
          return 0;
        }
        return prev - 1;
      });
    }, 1000);
    return () => window.clearInterval(interval);
  }, [isDone, isOpen, onClose]);

  const currentStep = useMemo(
    () => DEPLOY_STEPS.find((step) => step.id === currentStepId) ?? null,
    [currentStepId]
  );

  const activeColor = isDone ? '#34d399' : isError ? '#f87171' : (currentStep?.color ?? '#60a5fa');
  const particleCount = isDone ? 40 : doneSteps.length === 3 ? 28 : doneSteps.length === 2 ? 16 : doneSteps.length === 1 ? 8 : 4;

  const stepState = (index: number): StepState => {
    const step = DEPLOY_STEPS[index];
    if (doneSteps.includes(step.id)) return 'done';
    if (phase === 'running' && currentStepId === step.id) return 'active';
    return 'pending';
  };

  if (!shadowMount || !isOpen || phase === 'idle') return null;

  return createPortal(
    <div className="jp-drawer-root">
      <div
        className="jp-drawer-overlay animate-fade-in"
        onClick={isDone || isError ? onClose : undefined}
        aria-hidden
      />

      <div
        role="status"
        aria-live="polite"
        aria-label={isDone ? 'Deploy completed' : isError ? 'Deploy failed' : 'Deploying'}
        className="jp-drawer-shell animate-drawer-up"
        style={{ bottom: 'max(2.25rem, env(safe-area-inset-bottom))' }}
      >
        <div
          className="jp-drawer-card"
          style={{
            backgroundColor: 'hsl(222 18% 7%)',
            boxShadow: `0 0 0 1px rgba(255,255,255,0.04), 0 -20px 60px rgba(0,0,0,0.6), 0 0 80px ${activeColor}0d`,
            transition: 'box-shadow 1.2s ease',
          }}
        >
          <div
            className="jp-drawer-ambient"
            style={{
              background: `radial-gradient(ellipse 70% 60% at 50% 110%, ${activeColor}12 0%, transparent 65%)`,
              transition: 'background 1.5s ease',
              animation: 'ambient-pulse 3.5s ease infinite',
            }}
            aria-hidden
          />

          {isDone && (
            <div className="jp-drawer-shimmer" aria-hidden>
              <div
                className="jp-drawer-shimmer-bar"
                style={{
                  background: 'linear-gradient(90deg, transparent, rgba(255,255,255,0.04), transparent)',
                  animation: 'shimmer-sweep 1.4s 0.1s ease forwards',
                }}
              />
            </div>
          )}

          <Particles count={particleCount} color={activeColor} />
          {burst && <SuccessBurst />}

          <div className="jp-drawer-content">
            <div className="jp-drawer-header">
              <div className="jp-drawer-header-left">
                <div className="jp-drawer-status" style={{ color: activeColor }}>
                  <span
                    className="jp-drawer-status-dot"
                    style={{
                      background: activeColor,
                      boxShadow: `0 0 6px ${activeColor}`,
                      animation: isRunning ? 'ambient-pulse 1.5s ease infinite' : 'none',
                    }}
                    aria-hidden
                  />
                  {isDone ? 'Live' : isError ? 'Build failed' : currentStep?.verb ?? 'Saving'}
                </div>

                <div key={currentStep?.id ?? phase} className="jp-drawer-copy animate-text-in">
                  {isDone ? (
                    <div className="animate-success-pop">
                      <p className="jp-drawer-copy-title jp-drawer-copy-title-lg">Your content is live.</p>
                      <p className="jp-drawer-copy-sub">Deployed to production successfully</p>
                    </div>
                  ) : isError ? (
                    <>
                      <p className="jp-drawer-copy-title jp-drawer-copy-title-md">Deploy failed at build.</p>
                      <p className="jp-drawer-copy-sub jp-drawer-copy-sub-error">{errorMessage ?? 'Check your Vercel logs or retry below'}</p>
                    </>
                  ) : currentStep ? (
                    <>
                      <p className="jp-drawer-poem-line jp-drawer-poem-line-1">{currentStep.poem[0]}</p>
                      <p className="jp-drawer-poem-line jp-drawer-poem-line-2">{currentStep.poem[1]}</p>
                    </>
                  ) : null}
                </div>
              </div>

              <div className="jp-drawer-right">
                {isDone ? (
                  <div className="jp-drawer-countdown-wrap animate-fade-up">
                    <span className="jp-drawer-countdown-text" aria-live="polite">
                      Chiusura in {countdown}s
                    </span>
                    <div className="jp-drawer-countdown-track">
                      <div className="jp-drawer-countdown-bar countdown-bar" style={{ boxShadow: '0 0 6px #34d39988' }} />
                    </div>
                  </div>
                ) : (
                  <ElapsedTimer running={isRunning} />
                )}
              </div>
            </div>

            <div className="jp-drawer-track-row">
              {DEPLOY_STEPS.map((step, i) => (
                <div key={step.id} style={{ display: 'flex', alignItems: 'center', flex: i < DEPLOY_STEPS.length - 1 ? 1 : 'none' }}>
                  <DeployNode step={step} state={stepState(i)} />
                  {i < DEPLOY_STEPS.length - 1 && (
                    <DeployConnector fromState={stepState(i)} toState={stepState(i + 1)} color={DEPLOY_STEPS[i + 1].color} />
                  )}
                </div>
              ))}
            </div>

            <div className="jp-drawer-bars-wrap">
              <BuildBars active={stepState(2) === 'active'} />
            </div>

            <div className="jp-drawer-separator" />

            <div className="jp-drawer-footer">
              <div className="jp-drawer-progress">
                <div
                  className="jp-drawer-progress-indicator"
                  style={{
                    width: `${Math.max(0, Math.min(100, progress))}%`,
                    background: `linear-gradient(90deg, ${DEPLOY_STEPS[0].color}, ${activeColor})`,
                  }}
                />
              </div>

              <div className="jp-drawer-cta">
                {isDone && (
                  <div className="jp-drawer-btn-row animate-fade-up">
                    <button type="button" className="jp-drawer-btn jp-drawer-btn-secondary" onClick={onClose}>
                      Chiudi
                    </button>
                    <button
                      type="button"
                      className="jp-drawer-btn jp-drawer-btn-emerald"
                      onClick={() => {
                        if (deployUrl) window.open(deployUrl, '_blank', 'noopener,noreferrer');
                      }}
                      disabled={!deployUrl}
                    >
                      <span aria-hidden>↗</span> Open site
                    </button>
                  </div>
                )}

                {isError && (
                  <div className="jp-drawer-btn-row animate-fade-up">
                    <button type="button" className="jp-drawer-btn jp-drawer-btn-ghost" onClick={onClose}>
                      Annulla
                    </button>
                    <button type="button" className="jp-drawer-btn jp-drawer-btn-destructive" onClick={onRetry}>
                      Retry
                    </button>
                  </div>
                )}

                {isRunning && (
                  <span className="jp-drawer-running-step" aria-hidden>
                    {doneSteps.length + 1} / {DEPLOY_STEPS.length}
                  </span>
                )}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>,
    shadowMount
  );
}


END_OF_FILE_CONTENT
echo "Creating src/components/save-drawer/Visuals.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/save-drawer/Visuals.tsx"
import { useEffect, useRef, useState } from 'react';
import type { CSSProperties } from 'react';

interface Particle {
  id: number;
  x: number;
  y: number;
  size: number;
  dur: number;
  delay: number;
}

const PARTICLE_POOL: Particle[] = Array.from({ length: 44 }, (_, i) => ({
  id: i,
  x: 5 + Math.random() * 90,
  y: 15 + Math.random() * 70,
  size: 1.5 + Math.random() * 2.5,
  dur: 2.8 + Math.random() * 3.5,
  delay: Math.random() * 4,
}));

interface ParticlesProps {
  count: number;
  color: string;
}

export function Particles({ count, color }: ParticlesProps) {
  return (
    <div className="jp-drawer-particles" aria-hidden>
      {PARTICLE_POOL.slice(0, count).map((particle) => (
        <div
          key={particle.id}
          className="jp-drawer-particle"
          style={{
            left: `${particle.x}%`,
            bottom: `${particle.y}%`,
            width: particle.size,
            height: particle.size,
            background: color,
            boxShadow: `0 0 ${particle.size * 3}px ${color}`,
            opacity: 0,
            animation: `particle-float ${particle.dur}s ${particle.delay}s ease-out infinite`,
          }}
        />
      ))}
    </div>
  );
}

const BAR_H = [0.45, 0.75, 0.55, 0.9, 0.65, 0.8, 0.5, 0.72, 0.6, 0.85, 0.42, 0.7];

interface BuildBarsProps {
  active: boolean;
}

export function BuildBars({ active }: BuildBarsProps) {
  if (!active) return <div className="jp-drawer-bars-placeholder" />;

  return (
    <div className="jp-drawer-bars" aria-hidden>
      {BAR_H.map((height, i) => (
        <div
          key={i}
          className="jp-drawer-bar"
          style={{
            height: `${height * 100}%`,
            animation: `bar-eq ${0.42 + i * 0.06}s ${i * 0.04}s ease-in-out infinite alternate`,
          }}
        />
      ))}
    </div>
  );
}

const BURST_COLORS = ['#34d399', '#60a5fa', '#a78bfa', '#f59e0b', '#f472b6'];

export function SuccessBurst() {
  return (
    <div className="jp-drawer-burst" aria-hidden>
      {Array.from({ length: 16 }).map((_, i) => (
        <div
          key={i}
          className="jp-drawer-burst-dot"
          style={
            {
              background: BURST_COLORS[i % BURST_COLORS.length],
              ['--r' as string]: `${i * 22.5}deg`,
              animation: `burst-ray 0.85s ${i * 0.03}s cubic-bezier(0,0.6,0.5,1) forwards`,
              transform: `rotate(${i * 22.5}deg)`,
              transformOrigin: '50% 50%',
              opacity: 0,
            } as CSSProperties
          }
        />
      ))}
    </div>
  );
}

interface ElapsedTimerProps {
  running: boolean;
}

export function ElapsedTimer({ running }: ElapsedTimerProps) {
  const [elapsed, setElapsed] = useState(0);
  const startRef = useRef<number | null>(null);
  const rafRef = useRef<number | null>(null);

  useEffect(() => {
    if (!running) return;
    if (!startRef.current) startRef.current = performance.now();

    const tick = () => {
      if (!startRef.current) return;
      setElapsed(Math.floor((performance.now() - startRef.current) / 1000));
      rafRef.current = requestAnimationFrame(tick);
    };

    rafRef.current = requestAnimationFrame(tick);
    return () => {
      if (rafRef.current) cancelAnimationFrame(rafRef.current);
    };
  }, [running]);

  const sec = String(elapsed % 60).padStart(2, '0');
  const min = String(Math.floor(elapsed / 60)).padStart(2, '0');
  return <span className="jp-drawer-elapsed" aria-live="off">{min}:{sec}</span>;
}


END_OF_FILE_CONTENT
echo "Creating src/components/save-drawer/saverStyle.css..."
cat << 'END_OF_FILE_CONTENT' > "src/components/save-drawer/saverStyle.css"
/* Save Drawer strict_full isolated stylesheet */

.jp-drawer-root {
  --background: 222 18% 6%;
  --foreground: 210 20% 96%;
  --card: 222 16% 8%;
  --card-foreground: 210 20% 96%;
  --primary: 0 0% 95%;
  --primary-foreground: 222 18% 6%;
  --secondary: 220 14% 13%;
  --secondary-foreground: 210 20% 96%;
  --destructive: 0 72% 51%;
  --destructive-foreground: 0 0% 98%;
  --border: 220 14% 13%;
  --radius: 0.6rem;
  font-family: 'Geist', system-ui, sans-serif;
}

.jp-drawer-overlay {
  position: fixed;
  inset: 0;
  z-index: 2147483600;
  background: rgb(0 0 0 / 0.4);
  backdrop-filter: blur(2px);
}

.jp-drawer-shell {
  position: fixed;
  left: 0;
  right: 0;
  z-index: 2147483601;
  display: flex;
  justify-content: center;
  padding: 0 1rem;
}

.jp-drawer-card {
  position: relative;
  width: 100%;
  max-width: 31rem;
  overflow: hidden;
  border-radius: 1rem;
  border: 1px solid rgb(255 255 255 / 0.07);
}

.jp-drawer-ambient {
  position: absolute;
  inset: 0;
  pointer-events: none;
}

.jp-drawer-shimmer {
  position: absolute;
  inset: 0;
  overflow: hidden;
  pointer-events: none;
}

.jp-drawer-shimmer-bar {
  position: absolute;
  inset-block: 0;
  width: 35%;
}

.jp-drawer-content {
  position: relative;
  z-index: 10;
  padding: 2rem 2rem 1.75rem;
}

.jp-drawer-header {
  margin-bottom: 1.5rem;
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
}

.jp-drawer-header-left {
  display: flex;
  flex-direction: column;
  gap: 0.625rem;
}

.jp-drawer-status {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-size: 0.75rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.1em;
  transition: color 0.5s;
}

.jp-drawer-status-dot {
  width: 0.375rem;
  height: 0.375rem;
  border-radius: 9999px;
  display: inline-block;
}

.jp-drawer-copy {
  min-height: 52px;
}

.jp-drawer-copy-title {
  margin: 0;
  color: white;
  line-height: 1.25;
  font-weight: 600;
}

.jp-drawer-copy-title-lg {
  font-size: 1.125rem;
}

.jp-drawer-copy-title-md {
  font-size: 1rem;
}

.jp-drawer-copy-sub {
  margin: 0.125rem 0 0;
  color: rgb(255 255 255 / 0.4);
  font-size: 0.875rem;
}

.jp-drawer-copy-sub-error {
  color: rgb(255 255 255 / 0.35);
}

.jp-drawer-poem-line {
  margin: 0;
  font-size: 0.875rem;
  font-weight: 300;
  line-height: 1.5;
}

.jp-drawer-poem-line-1 {
  color: rgb(255 255 255 / 0.55);
}

.jp-drawer-poem-line-2 {
  color: rgb(255 255 255 / 0.3);
}

.jp-drawer-right {
  margin-left: 1.5rem;
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 0.5rem;
  flex-shrink: 0;
}

.jp-drawer-countdown-wrap {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 0.5rem;
}

.jp-drawer-countdown-text {
  font-family: 'Geist Mono', ui-monospace, SFMono-Regular, Menlo, monospace;
  font-size: 0.75rem;
  font-weight: 600;
  color: #34d399;
}

.jp-drawer-countdown-track {
  width: 6rem;
  height: 0.125rem;
  border-radius: 9999px;
  overflow: hidden;
  background: rgb(255 255 255 / 0.1);
}

.jp-drawer-countdown-bar {
  width: 100%;
  height: 100%;
  border-radius: 9999px;
  background: #34d399;
}

.jp-drawer-track-row {
  margin-bottom: 1rem;
  display: flex;
  align-items: center;
}

.jp-drawer-bars-wrap {
  margin-bottom: 1rem;
  display: flex;
  justify-content: center;
}

.jp-drawer-separator {
  margin-bottom: 1rem;
  height: 1px;
  width: 100%;
  border: 0;
  background: rgb(255 255 255 / 0.06);
}

.jp-drawer-footer {
  display: flex;
  align-items: center;
  gap: 1rem;
}

.jp-drawer-progress {
  flex: 1;
  height: 2px;
  border-radius: 9999px;
  overflow: hidden;
  background: rgb(255 255 255 / 0.06);
}

.jp-drawer-progress-indicator {
  height: 100%;
}

.jp-drawer-cta {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  flex-shrink: 0;
}

.jp-drawer-running-step {
  font-family: 'Geist Mono', ui-monospace, SFMono-Regular, Menlo, monospace;
  font-size: 0.75rem;
  color: rgb(255 255 255 / 0.2);
}

.jp-drawer-btn-row {
  display: flex;
  gap: 0.5rem;
}

.jp-drawer-btn {
  border: 1px solid transparent;
  border-radius: 0.375rem;
  font-size: 0.8125rem;
  font-weight: 500;
  line-height: 1;
  height: 2.25rem;
  padding: 0 0.75rem;
  cursor: pointer;
  transition: all 0.2s ease;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 0.375rem;
}

.jp-drawer-btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.jp-drawer-btn-secondary {
  background: hsl(var(--secondary));
  color: hsl(var(--secondary-foreground));
}

.jp-drawer-btn-secondary:hover {
  filter: brightness(1.08);
}

.jp-drawer-btn-emerald {
  background: #34d399;
  color: #18181b;
  font-weight: 600;
}

.jp-drawer-btn-emerald:hover {
  background: #6ee7b7;
}

.jp-drawer-btn-ghost {
  background: transparent;
  color: rgb(255 255 255 / 0.9);
}

.jp-drawer-btn-ghost:hover {
  background: rgb(255 255 255 / 0.08);
}

.jp-drawer-btn-destructive {
  background: hsl(var(--destructive));
  color: hsl(var(--destructive-foreground));
}

.jp-drawer-btn-destructive:hover {
  filter: brightness(1.06);
}

.jp-drawer-node-wrap {
  position: relative;
  z-index: 10;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.625rem;
}

.jp-drawer-node {
  position: relative;
  width: 3rem;
  height: 3rem;
  border-radius: 9999px;
  border: 1px solid transparent;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.5s;
}

.jp-drawer-node-pending {
  border-color: rgb(255 255 255 / 0.08);
  background: rgb(255 255 255 / 0.02);
}

.jp-drawer-node-glyph {
  font-size: 1.125rem;
  line-height: 1;
}

.jp-drawer-node-glyph-active {
  display: inline-block;
}

.jp-drawer-node-glyph-pending {
  color: rgb(255 255 255 / 0.15);
}

.jp-drawer-node-ring {
  position: absolute;
  border-radius: 9999px;
  border: 1px solid transparent;
}

.jp-drawer-node-label {
  font-size: 10px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.1em;
  transition: color 0.5s;
}

.jp-drawer-connector {
  position: relative;
  z-index: 0;
  flex: 1;
  height: 2px;
  margin-top: -24px;
}

.jp-drawer-connector-base {
  position: absolute;
  inset: 0;
  border-radius: 9999px;
  background: rgb(255 255 255 / 0.08);
}

.jp-drawer-connector-fill {
  position: absolute;
  left: 0;
  right: auto;
  top: 0;
  bottom: 0;
  border-radius: 9999px;
}

.jp-drawer-connector-orb {
  position: absolute;
  top: 50%;
  transform: translateY(-50%);
  width: 10px;
  height: 10px;
  border-radius: 9999px;
}

.jp-drawer-particles {
  position: absolute;
  inset: 0;
  overflow: hidden;
  pointer-events: none;
}

.jp-drawer-particle {
  position: absolute;
  border-radius: 9999px;
}

.jp-drawer-bars {
  height: 1.75rem;
  display: flex;
  align-items: flex-end;
  gap: 3px;
}

.jp-drawer-bars-placeholder {
  height: 1.75rem;
}

.jp-drawer-bar {
  width: 3px;
  border-radius: 2px;
  background: #f59e0b;
  transform-origin: bottom;
}

.jp-drawer-burst {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  pointer-events: none;
}

.jp-drawer-burst-dot {
  position: absolute;
  width: 5px;
  height: 5px;
  border-radius: 9999px;
}

.jp-drawer-elapsed {
  font-family: 'Geist Mono', ui-monospace, SFMono-Regular, Menlo, monospace;
  font-size: 0.75rem;
  letter-spacing: 0.1em;
  color: rgb(255 255 255 / 0.25);
}

/* Animation helper classes */
.animate-drawer-up { animation: drawer-up 0.45s cubic-bezier(0.22, 1, 0.36, 1) forwards; }
.animate-fade-in { animation: fade-in 0.25s ease forwards; }
.animate-fade-up { animation: fade-up 0.35s ease forwards; }
.animate-text-in { animation: text-in 0.3s ease forwards; }
.animate-success-pop { animation: success-pop 0.5s cubic-bezier(0.34, 1.56, 0.64, 1) forwards; }
.countdown-bar { animation: countdown-drain 3s linear forwards; }

.stroke-dash-30 {
  stroke-dasharray: 30;
  stroke-dashoffset: 30;
}

.animate-check-draw {
  animation: check-draw 0.4s 0.05s ease forwards;
}

@keyframes check-draw {
  to { stroke-dashoffset: 0; }
}

@keyframes drawer-up {
  from { transform: translateY(100%); opacity: 0; }
  to { transform: translateY(0); opacity: 1; }
}

@keyframes fade-in {
  from { opacity: 0; }
  to { opacity: 1; }
}

@keyframes fade-up {
  from { opacity: 0; transform: translateY(8px); }
  to { transform: translateY(0); opacity: 1; }
}

@keyframes text-in {
  from { opacity: 0; transform: translateX(-6px); }
  to { opacity: 1; transform: translateX(0); }
}

@keyframes success-pop {
  0% { transform: scale(0.88); opacity: 0; }
  60% { transform: scale(1.04); }
  100% { transform: scale(1); opacity: 1; }
}

@keyframes ambient-pulse {
  0%, 100% { opacity: 0.3; }
  50% { opacity: 0.65; }
}

@keyframes shimmer-sweep {
  from { transform: translateX(-100%); }
  to { transform: translateX(250%); }
}

@keyframes node-glow {
  0%, 100% { box-shadow: 0 0 12px var(--glow-color,#60a5fa55); }
  50% { box-shadow: 0 0 28px var(--glow-color,#60a5fa88), 0 0 48px var(--glow-color,#60a5fa22); }
}

@keyframes glyph-rotate {
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
}

@keyframes ring-expand {
  from { transform: scale(1); opacity: 0.7; }
  to { transform: scale(2.1); opacity: 0; }
}

@keyframes orb-travel {
  from { left: 0%; }
  to { left: calc(100% - 10px); }
}

@keyframes particle-float {
  0% { transform: translateY(0) scale(1); opacity: 0; }
  15% { opacity: 1; }
  100% { transform: translateY(-90px) scale(0.3); opacity: 0; }
}

@keyframes bar-eq {
  from { transform: scaleY(0.4); }
  to { transform: scaleY(1); }
}

@keyframes burst-ray {
  0% { transform: rotate(var(--r, 0deg)) translateX(0); opacity: 1; }
  100% { transform: rotate(var(--r, 0deg)) translateX(56px); opacity: 0; }
}

@keyframes countdown-drain {
  from { width: 100%; }
  to { width: 0%; }
}


END_OF_FILE_CONTENT
mkdir -p "src/components/spa-treatments"
echo "Creating src/components/spa-treatments/View.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/spa-treatments/View.tsx"
// Layout: Hero=F (MINIMAL HERO), Features=D (ACCORDION)
import React from 'react';
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from '@/components/ui/accordion';
import type { SpaTreatmentsData, SpaTreatmentsSettings } from './types';

export const SpaTreatments: React.FC<{ data: SpaTreatmentsData; settings: SpaTreatmentsSettings }> = ({ data }) => (
  <section
    style={{
      '--local-bg': 'var(--background)',
      '--local-text': 'var(--foreground)',
      '--local-text-muted': 'var(--muted-foreground)',
      '--local-accent': 'var(--accent)',
      '--local-primary': 'var(--primary)',
      '--local-surface': 'var(--card)',
      '--local-border': 'var(--border)',
      '--local-radius-lg': 'var(--theme-radius-lg)',
    } as React.CSSProperties}
    className="relative z-0 py-28 bg-[var(--local-bg)]"
  >
    <div className="max-w-[1000px] mx-auto px-8">
      {data.label && (
        <div className="jp-section-label inline-flex items-center gap-2 text-[0.72rem] font-bold uppercase tracking-[0.12em] text-[var(--local-accent)] mb-4" data-jp-field="label">
          <span className="w-5 h-px bg-[var(--local-primary)]" />
          {data.label}
        </div>
      )}
      
      <h2 className="font-display font-black text-[clamp(2rem,4.5vw,3.8rem)] leading-[1.05] tracking-tight text-[var(--local-text)] mb-6" data-jp-field="title">
        {data.title}
      </h2>
      
      {data.description && (
        <p className="text-[var(--local-text-muted)] text-lg leading-relaxed mb-16 max-w-[700px]" data-jp-field="description">
          {data.description}
        </p>
      )}
      
      <Accordion type="single" collapsible className="space-y-4">
        {data.treatments.map((treatment, idx) => (
          <AccordionItem
            key={treatment.id || `treatment-${idx}`}
            value={treatment.id || `treatment-${idx}`}
            className="border border-[var(--local-border)] rounded-[var(--local-radius-lg)] bg-[var(--local-surface)] overflow-hidden"
            data-jp-item-id={treatment.id || `treatment-${idx}`}
            data-jp-item-field="treatments"
          >
            <AccordionTrigger className="px-8 py-6 text-left hover:no-underline group">
              <div className="flex items-center justify-between w-full">
                <div>
                  <h3 className="font-display font-bold text-lg text-[var(--local-text)] mb-1">
                    {treatment.title}
                  </h3>
                  <div className="flex items-center gap-4 text-sm text-[var(--local-text-muted)]">
                    {treatment.duration && <span>{treatment.duration}</span>}
                    {treatment.price && (
                      <>
                        {treatment.duration && <span>•</span>}
                        <span className="font-mono text-[var(--local-accent)]">{treatment.price}</span>
                      </>
                    )}
                  </div>
                </div>
              </div>
            </AccordionTrigger>
            <AccordionContent className="px-8 pb-6">
              <p className="text-[var(--local-text-muted)] leading-relaxed">
                {treatment.description}
              </p>
            </AccordionContent>
          </AccordionItem>
        ))}
      </Accordion>
    </div>
  </section>
);

END_OF_FILE_CONTENT
echo "Creating src/components/spa-treatments/index.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/spa-treatments/index.ts"
export { SpaTreatments } from './View';
export { SpaTreatmentsSchema } from './schema';
export type { SpaTreatmentsData, SpaTreatmentsSettings } from './types';

END_OF_FILE_CONTENT
echo "Creating src/components/spa-treatments/schema.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/spa-treatments/schema.ts"
import { z } from 'zod';
import { BaseSectionData, BaseArrayItem } from '@olonjs/core';

const TreatmentItemSchema = BaseArrayItem.extend({
  title: z.string().describe('ui:text'),
  duration: z.string().optional().describe('ui:text'),
  price: z.string().optional().describe('ui:text'),
  description: z.string().describe('ui:textarea'),
});

export const SpaTreatmentsSchema = BaseSectionData.extend({
  label: z.string().optional().describe('ui:text'),
  title: z.string().describe('ui:text'),
  description: z.string().optional().describe('ui:textarea'),
  treatments: z.array(TreatmentItemSchema).describe('ui:list'),
});

END_OF_FILE_CONTENT
echo "Creating src/components/spa-treatments/types.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/spa-treatments/types.ts"
import { z } from 'zod';
import { BaseSectionSettingsSchema } from '@olonjs/core';
import { SpaTreatmentsSchema } from './schema';

export type SpaTreatmentsData = z.infer<typeof SpaTreatmentsSchema>;
export type SpaTreatmentsSettings = z.infer<typeof BaseSectionSettingsSchema>;

END_OF_FILE_CONTENT
mkdir -p "src/components/stats-band"
echo "Creating src/components/stats-band/View.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/stats-band/View.tsx"
// Layout: Hero=F (MINIMAL HERO), Features=A (BENTO GRID)
import React from 'react';
import type { StatsBandData, StatsBandSettings } from './types';

export const StatsBand: React.FC<{ data: StatsBandData; settings: StatsBandSettings }> = ({ data }) => (
  <section
    style={{
      '--local-bg': 'color-mix(in oklch, var(--card) 50%, var(--background))',
      '--local-text': 'var(--foreground)',
      '--local-text-muted': 'var(--muted-foreground)',
      '--local-accent': 'var(--accent)',
      '--local-border': 'var(--border)',
      '--local-primary': 'var(--primary)',
    } as React.CSSProperties}
    className="relative z-0 py-20 bg-[var(--local-bg)] border-y border-[var(--local-border)]"
  >
    <div className="max-w-[1200px] mx-auto px-8">
      {data.title && (
        <h2 className="font-display font-bold text-center text-[var(--local-text)] text-2xl mb-12" data-jp-field="title">
          {data.title}
        </h2>
      )}
      
      <div className="grid grid-cols-2 md:grid-cols-4 gap-8">
        {data.stats.map((stat, idx) => (
          <div
            key={stat.id || `stat-${idx}`}
            className="text-center"
            data-jp-item-id={stat.id || `stat-${idx}`}
            data-jp-item-field="stats"
          >
            <div className="font-display font-black text-[clamp(2rem,4vw,3.5rem)] leading-none text-[var(--local-primary)] mb-2">
              {stat.number}
              {stat.suffix && <span className="text-[var(--local-accent)]">{stat.suffix}</span>}
            </div>
            <div className="text-[var(--local-text-muted)] text-sm uppercase tracking-wide font-mono">
              {stat.label}
            </div>
          </div>
        ))}
      </div>
    </div>
  </section>
);

END_OF_FILE_CONTENT
echo "Creating src/components/stats-band/index.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/stats-band/index.ts"
export { StatsBand } from './View';
export { StatsBandSchema } from './schema';
export type { StatsBandData, StatsBandSettings } from './types';

END_OF_FILE_CONTENT
echo "Creating src/components/stats-band/schema.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/stats-band/schema.ts"
import { z } from 'zod';
import { BaseSectionData, BaseArrayItem } from '@olonjs/core';

const StatItemSchema = BaseArrayItem.extend({
  number: z.string().describe('ui:text'),
  label: z.string().describe('ui:text'),
  suffix: z.string().optional().describe('ui:text'),
});

export const StatsBandSchema = BaseSectionData.extend({
  title: z.string().optional().describe('ui:text'),
  stats: z.array(StatItemSchema).describe('ui:list'),
});

END_OF_FILE_CONTENT
echo "Creating src/components/stats-band/types.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/stats-band/types.ts"
import { z } from 'zod';
import { BaseSectionSettingsSchema } from '@olonjs/core';
import { StatsBandSchema } from './schema';

export type StatsBandData = z.infer<typeof StatsBandSchema>;
export type StatsBandSettings = z.infer<typeof BaseSectionSettingsSchema>;

END_OF_FILE_CONTENT
mkdir -p "src/components/testimonials"
echo "Creating src/components/testimonials/View.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/testimonials/View.tsx"
// Layout: Hero=F (MINIMAL HERO), Features=A (BENTO GRID)
import React from 'react';
import { Card, CardContent } from '@/components/ui/card';
import { Star } from 'lucide-react';
import type { TestimonialsData, TestimonialsSettings } from './types';

export const Testimonials: React.FC<{ data: TestimonialsData; settings: TestimonialsSettings }> = ({ data }) => (
  <section
    style={{
      '--local-bg': 'var(--background)',
      '--local-text': 'var(--foreground)',
      '--local-text-muted': 'var(--muted-foreground)',
      '--local-accent': 'var(--accent)',
      '--local-surface': 'var(--card)',
      '--local-border': 'var(--border)',
      '--local-primary': 'var(--primary)',
      '--local-radius-lg': 'var(--theme-radius-lg)',
    } as React.CSSProperties}
    className="relative z-0 py-28 bg-[var(--local-bg)]"
  >
    <div className="max-w-[1200px] mx-auto px-8">
      {data.label && (
        <div className="jp-section-label inline-flex items-center gap-2 text-[0.72rem] font-bold uppercase tracking-[0.12em] text-[var(--local-accent)] mb-4" data-jp-field="label">
          <span className="w-5 h-px bg-[var(--local-primary)]" />
          {data.label}
        </div>
      )}
      
      <h2 className="font-display font-black text-[clamp(2rem,4.5vw,3.8rem)] leading-[1.05] tracking-tight text-[var(--local-text)] mb-16" data-jp-field="title">
        {data.title}
      </h2>
      
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
        {data.testimonials.map((testimonial, idx) => (
          <Card
            key={testimonial.id || `testimonial-${idx}`}
            className="bg-[var(--local-surface)] border border-[var(--local-border)] rounded-[var(--local-radius-lg)] hover:shadow-lg transition-shadow duration-300"
            data-jp-item-id={testimonial.id || `testimonial-${idx}`}
            data-jp-item-field="testimonials"
          >
            <CardContent className="p-8">
              {testimonial.rating && (
                <div className="flex items-center gap-1 mb-6">
                  {Array.from({ length: testimonial.rating }).map((_, starIdx) => (
                    <Star key={starIdx} className="w-4 h-4 fill-[var(--local-accent)] text-[var(--local-accent)]" />
                  ))}
                </div>
              )}
              
              <blockquote className="text-[var(--local-text)] text-lg leading-relaxed mb-6">
                "{testimonial.quote}"
              </blockquote>
              
              <footer>
                <div className="font-display font-bold text-[var(--local-text)] mb-1">
                  {testimonial.author}
                </div>
                {testimonial.role && (
                  <div className="text-[var(--local-text-muted)] text-sm">
                    {testimonial.role}
                  </div>
                )}
                {testimonial.location && (
                  <div className="text-[var(--local-accent)] text-xs font-mono uppercase tracking-wide mt-1">
                    {testimonial.location}
                  </div>
                )}
              </footer>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  </section>
);

END_OF_FILE_CONTENT
echo "Creating src/components/testimonials/index.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/testimonials/index.ts"
export { Testimonials } from './View';
export { TestimonialsSchema } from './schema';
export type { TestimonialsData, TestimonialsSettings } from './types';

END_OF_FILE_CONTENT
echo "Creating src/components/testimonials/schema.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/testimonials/schema.ts"
import { z } from 'zod';
import { BaseSectionData, BaseArrayItem } from '@olonjs/core';

const TestimonialItemSchema = BaseArrayItem.extend({
  quote: z.string().describe('ui:textarea'),
  author: z.string().describe('ui:text'),
  role: z.string().optional().describe('ui:text'),
  location: z.string().optional().describe('ui:text'),
  rating: z.number().min(1).max(5).optional().describe('ui:number'),
});

export const TestimonialsSchema = BaseSectionData.extend({
  label: z.string().optional().describe('ui:text'),
  title: z.string().describe('ui:text'),
  testimonials: z.array(TestimonialItemSchema).describe('ui:list'),
});

END_OF_FILE_CONTENT
echo "Creating src/components/testimonials/types.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/testimonials/types.ts"
import { z } from 'zod';
import { BaseSectionSettingsSchema } from '@olonjs/core';
import { TestimonialsSchema } from './schema';

export type TestimonialsData = z.infer<typeof TestimonialsSchema>;
export type TestimonialsSettings = z.infer<typeof BaseSectionSettingsSchema>;

END_OF_FILE_CONTENT
mkdir -p "src/components/ui"
echo "Creating src/components/ui/OlonMark.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/ui/OlonMark.tsx"
import { cn } from '@olonjs/core'

interface OlonMarkProps {
  size?: number
  /** mono: uses currentColor — for single-colour print/emboss contexts */
  variant?: 'default' | 'mono'
  className?: string
}

export function OlonMark({ size = 32, variant = 'default', className }: OlonMarkProps) {
  const gid = `olon-ring-${size}`

  if (variant === 'mono') {
    return (
      <svg
        viewBox="0 0 100 100"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
        width={size}
        height={size}
        aria-label="Olon mark"
        className={cn('flex-shrink-0', className)}
      >
        <circle cx="50" cy="50" r="38" stroke="currentColor" strokeWidth="20"/>
        <circle cx="50" cy="50" r="15" fill="currentColor"/>
      </svg>
    )
  }

  return (
    <svg
      viewBox="0 0 100 100"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      width={size}
      height={size}
      aria-label="Olon mark"
      className={cn('flex-shrink-0', className)}
    >
      <defs>
        <linearGradient id={gid} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%"   stopColor="var(--olon-ring-top)"/>
          <stop offset="100%" stopColor="var(--olon-ring-bottom)"/>
        </linearGradient>
      </defs>
      <circle cx="50" cy="50" r="38" stroke={`url(#${gid})`} strokeWidth="20"/>
      <circle cx="50" cy="50" r="15" fill="var(--olon-nucleus)"/>
    </svg>
  )
}

interface OlonLogoProps {
  markSize?: number
  fontSize?: number
  variant?: 'default' | 'mono'
  className?: string
}

export function OlonLogo({
  markSize = 32,
  fontSize = 24,
  variant = 'default',
  className,
}: OlonLogoProps) {
  return (
    <div className={cn('flex items-center gap-3', className)}>
      <OlonMark size={markSize} variant={variant}/>
      <span
        style={{
          fontFamily: "'Instrument Sans', Helvetica, Arial, sans-serif",
          fontWeight: 700,
          fontSize,
          letterSpacing: '-0.02em',
          color: 'hsl(var(--foreground))',
          lineHeight: 1,
        }}
      >
        Olon
      </span>
    </div>
  )
}

END_OF_FILE_CONTENT
echo "Creating src/components/ui/accordion.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/ui/accordion.tsx"
import * as React from "react"
import { Accordion as AccordionPrimitive } from "radix-ui"

import { cn } from "@/lib/utils"
import { ChevronDownIcon, ChevronUpIcon } from "lucide-react"

function Accordion({
  className,
  ...props
}: React.ComponentProps<typeof AccordionPrimitive.Root>) {
  return (
    <AccordionPrimitive.Root
      data-slot="accordion"
      className={cn("flex w-full flex-col", className)}
      {...props}
    />
  )
}

function AccordionItem({
  className,
  ...props
}: React.ComponentProps<typeof AccordionPrimitive.Item>) {
  return (
    <AccordionPrimitive.Item
      data-slot="accordion-item"
      className={cn("not-last:border-b", className)}
      {...props}
    />
  )
}

function AccordionTrigger({
  className,
  children,
  ...props
}: React.ComponentProps<typeof AccordionPrimitive.Trigger>) {
  return (
    <AccordionPrimitive.Header className="flex">
      <AccordionPrimitive.Trigger
        data-slot="accordion-trigger"
        className={cn(
          "group/accordion-trigger relative flex flex-1 items-start justify-between rounded-lg border border-transparent py-2.5 text-left text-sm font-medium transition-all outline-none hover:underline focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:after:border-ring disabled:pointer-events-none disabled:opacity-50 **:data-[slot=accordion-trigger-icon]:ml-auto **:data-[slot=accordion-trigger-icon]:size-4 **:data-[slot=accordion-trigger-icon]:text-muted-foreground",
          className
        )}
        {...props}
      >
        {children}
        <ChevronDownIcon data-slot="accordion-trigger-icon" className="pointer-events-none shrink-0 group-aria-expanded/accordion-trigger:hidden" />
        <ChevronUpIcon data-slot="accordion-trigger-icon" className="pointer-events-none hidden shrink-0 group-aria-expanded/accordion-trigger:inline" />
      </AccordionPrimitive.Trigger>
    </AccordionPrimitive.Header>
  )
}

function AccordionContent({
  className,
  children,
  ...props
}: React.ComponentProps<typeof AccordionPrimitive.Content>) {
  return (
    <AccordionPrimitive.Content
      data-slot="accordion-content"
      className="overflow-hidden text-sm data-open:animate-accordion-down data-closed:animate-accordion-up"
      {...props}
    >
      <div
        className={cn(
          "h-(--radix-accordion-content-height) pt-0 pb-2.5 [&_a]:underline [&_a]:underline-offset-3 [&_a]:hover:text-foreground [&_p:not(:last-child)]:mb-4",
          className
        )}
      >
        {children}
      </div>
    </AccordionPrimitive.Content>
  )
}

export { Accordion, AccordionItem, AccordionTrigger, AccordionContent }

END_OF_FILE_CONTENT
echo "Creating src/components/ui/aspect-ratio.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/ui/aspect-ratio.tsx"
"use client"

import { AspectRatio as AspectRatioPrimitive } from "radix-ui"

function AspectRatio({
  ...props
}: React.ComponentProps<typeof AspectRatioPrimitive.Root>) {
  return <AspectRatioPrimitive.Root data-slot="aspect-ratio" {...props} />
}

export { AspectRatio }


END_OF_FILE_CONTENT
echo "Creating src/components/ui/avatar.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/ui/avatar.tsx"
"use client"

import * as React from "react"
import { Avatar as AvatarPrimitive } from "radix-ui"

import { cn } from "@/lib/utils"

function Avatar({
  className,
  size = "default",
  ...props
}: React.ComponentProps<typeof AvatarPrimitive.Root> & {
  size?: "default" | "sm" | "lg"
}) {
  return (
    <AvatarPrimitive.Root
      data-slot="avatar"
      data-size={size}
      className={cn(
        "group/avatar relative flex size-8 shrink-0 rounded-full select-none after:absolute after:inset-0 after:rounded-full after:border after:border-border after:mix-blend-darken data-[size=lg]:size-10 data-[size=sm]:size-6 dark:after:mix-blend-lighten",
        className
      )}
      {...props}
    />
  )
}

function AvatarImage({
  className,
  ...props
}: React.ComponentProps<typeof AvatarPrimitive.Image>) {
  return (
    <AvatarPrimitive.Image
      data-slot="avatar-image"
      className={cn(
        "aspect-square size-full rounded-full object-cover",
        className
      )}
      {...props}
    />
  )
}

function AvatarFallback({
  className,
  ...props
}: React.ComponentProps<typeof AvatarPrimitive.Fallback>) {
  return (
    <AvatarPrimitive.Fallback
      data-slot="avatar-fallback"
      className={cn(
        "flex size-full items-center justify-center rounded-full bg-muted text-sm text-muted-foreground group-data-[size=sm]/avatar:text-xs",
        className
      )}
      {...props}
    />
  )
}

function AvatarBadge({ className, ...props }: React.ComponentProps<"span">) {
  return (
    <span
      data-slot="avatar-badge"
      className={cn(
        "absolute right-0 bottom-0 z-10 inline-flex items-center justify-center rounded-full bg-primary text-primary-foreground bg-blend-color ring-2 ring-background select-none",
        "group-data-[size=sm]/avatar:size-2 group-data-[size=sm]/avatar:[&>svg]:hidden",
        "group-data-[size=default]/avatar:size-2.5 group-data-[size=default]/avatar:[&>svg]:size-2",
        "group-data-[size=lg]/avatar:size-3 group-data-[size=lg]/avatar:[&>svg]:size-2",
        className
      )}
      {...props}
    />
  )
}

function AvatarGroup({ className, ...props }: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="avatar-group"
      className={cn(
        "group/avatar-group flex -space-x-2 *:data-[slot=avatar]:ring-2 *:data-[slot=avatar]:ring-background",
        className
      )}
      {...props}
    />
  )
}

function AvatarGroupCount({
  className,
  ...props
}: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="avatar-group-count"
      className={cn(
        "relative flex size-8 shrink-0 items-center justify-center rounded-full bg-muted text-sm text-muted-foreground ring-2 ring-background group-has-data-[size=lg]/avatar-group:size-10 group-has-data-[size=sm]/avatar-group:size-6 [&>svg]:size-4 group-has-data-[size=lg]/avatar-group:[&>svg]:size-5 group-has-data-[size=sm]/avatar-group:[&>svg]:size-3",
        className
      )}
      {...props}
    />
  )
}

export {
  Avatar,
  AvatarImage,
  AvatarFallback,
  AvatarGroup,
  AvatarGroupCount,
  AvatarBadge,
}

END_OF_FILE_CONTENT
echo "Creating src/components/ui/badge.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/ui/badge.tsx"
import * as React from "react"
import { cva, type VariantProps } from "class-variance-authority"
import { Slot } from "radix-ui"

import { cn } from "@/lib/utils"

const badgeVariants = cva(
  "group/badge inline-flex h-5 w-fit shrink-0 items-center justify-center gap-1 overflow-hidden rounded-4xl border border-transparent px-2 py-0.5 text-xs font-medium whitespace-nowrap transition-all focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50 has-data-[icon=inline-end]:pr-1.5 has-data-[icon=inline-start]:pl-1.5 aria-invalid:border-destructive aria-invalid:ring-destructive/20 dark:aria-invalid:ring-destructive/40 [&>svg]:pointer-events-none [&>svg]:size-3!",
  {
    variants: {
      variant: {
        default: "bg-primary text-primary-foreground [a]:hover:bg-primary/80",
        secondary:
          "bg-secondary text-secondary-foreground [a]:hover:bg-secondary/80",
        destructive:
          "bg-destructive/10 text-destructive focus-visible:ring-destructive/20 dark:bg-destructive/20 dark:focus-visible:ring-destructive/40 [a]:hover:bg-destructive/20",
        outline:
          "border-border text-foreground [a]:hover:bg-muted [a]:hover:text-muted-foreground",
        ghost:
          "hover:bg-muted hover:text-muted-foreground dark:hover:bg-muted/50",
        link: "text-primary underline-offset-4 hover:underline",
      },
    },
    defaultVariants: {
      variant: "default",
    },
  }
)

function Badge({
  className,
  variant = "default",
  asChild = false,
  ...props
}: React.ComponentProps<"span"> &
  VariantProps<typeof badgeVariants> & { asChild?: boolean }) {
  const Comp = asChild ? Slot.Root : "span"

  return (
    <Comp
      data-slot="badge"
      data-variant={variant}
      className={cn(badgeVariants({ variant }), className)}
      {...props}
    />
  )
}

export { Badge, badgeVariants }

END_OF_FILE_CONTENT
echo "Creating src/components/ui/breadcrumb.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/ui/breadcrumb.tsx"
import * as React from "react"
import { Slot } from "radix-ui"

import { cn } from "@/lib/utils"
import { ChevronRightIcon, MoreHorizontalIcon } from "lucide-react"

function Breadcrumb({ className, ...props }: React.ComponentProps<"nav">) {
  return (
    <nav
      aria-label="breadcrumb"
      data-slot="breadcrumb"
      className={cn(className)}
      {...props}
    />
  )
}

function BreadcrumbList({ className, ...props }: React.ComponentProps<"ol">) {
  return (
    <ol
      data-slot="breadcrumb-list"
      className={cn(
        "flex flex-wrap items-center gap-1.5 text-sm wrap-break-word text-muted-foreground",
        className
      )}
      {...props}
    />
  )
}

function BreadcrumbItem({ className, ...props }: React.ComponentProps<"li">) {
  return (
    <li
      data-slot="breadcrumb-item"
      className={cn("inline-flex items-center gap-1", className)}
      {...props}
    />
  )
}

function BreadcrumbLink({
  asChild,
  className,
  ...props
}: React.ComponentProps<"a"> & {
  asChild?: boolean
}) {
  const Comp = asChild ? Slot.Root : "a"

  return (
    <Comp
      data-slot="breadcrumb-link"
      className={cn("transition-colors hover:text-foreground", className)}
      {...props}
    />
  )
}

function BreadcrumbPage({ className, ...props }: React.ComponentProps<"span">) {
  return (
    <span
      data-slot="breadcrumb-page"
      role="link"
      aria-disabled="true"
      aria-current="page"
      className={cn("font-normal text-foreground", className)}
      {...props}
    />
  )
}

function BreadcrumbSeparator({
  children,
  className,
  ...props
}: React.ComponentProps<"li">) {
  return (
    <li
      data-slot="breadcrumb-separator"
      role="presentation"
      aria-hidden="true"
      className={cn("[&>svg]:size-3.5", className)}
      {...props}
    >
      {children ?? (
        <ChevronRightIcon />
      )}
    </li>
  )
}

function BreadcrumbEllipsis({
  className,
  ...props
}: React.ComponentProps<"span">) {
  return (
    <span
      data-slot="breadcrumb-ellipsis"
      role="presentation"
      aria-hidden="true"
      className={cn(
        "flex size-5 items-center justify-center [&>svg]:size-4",
        className
      )}
      {...props}
    >
      <MoreHorizontalIcon
      />
      <span className="sr-only">More</span>
    </span>
  )
}

export {
  Breadcrumb,
  BreadcrumbList,
  BreadcrumbItem,
  BreadcrumbLink,
  BreadcrumbPage,
  BreadcrumbSeparator,
  BreadcrumbEllipsis,
}

END_OF_FILE_CONTENT
echo "Creating src/components/ui/button.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/ui/button.tsx"
import * as React from "react"
import { cva, type VariantProps } from "class-variance-authority"
import { Slot } from "radix-ui"

import { cn } from "@/lib/utils"

const buttonVariants = cva(
  "group/button inline-flex shrink-0 items-center justify-center rounded-lg border border-transparent bg-clip-padding text-sm font-medium whitespace-nowrap transition-all outline-none select-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 active:not-aria-[haspopup]:translate-y-px disabled:pointer-events-none disabled:opacity-50 aria-invalid:border-destructive aria-invalid:ring-3 aria-invalid:ring-destructive/20 dark:aria-invalid:border-destructive/50 dark:aria-invalid:ring-destructive/40 [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4",
  {
    variants: {
      variant: {
        default: "bg-primary text-primary-foreground [a]:hover:bg-primary/80",
        outline:
          "border-border bg-background hover:bg-muted hover:text-foreground aria-expanded:bg-muted aria-expanded:text-foreground dark:border-input dark:bg-input/30 dark:hover:bg-input/50",
        secondary:
          "bg-secondary text-secondary-foreground hover:bg-secondary/80 aria-expanded:bg-secondary aria-expanded:text-secondary-foreground",
        ghost:
          "hover:bg-muted hover:text-foreground aria-expanded:bg-muted aria-expanded:text-foreground dark:hover:bg-muted/50",
        destructive:
          "bg-destructive/10 text-destructive hover:bg-destructive/20 focus-visible:border-destructive/40 focus-visible:ring-destructive/20 dark:bg-destructive/20 dark:hover:bg-destructive/30 dark:focus-visible:ring-destructive/40",
        link: "text-primary underline-offset-4 hover:underline",
      },
      size: {
        default:
          "h-8 gap-1.5 px-2.5 has-data-[icon=inline-end]:pr-2 has-data-[icon=inline-start]:pl-2",
        xs: "h-6 gap-1 rounded-[min(var(--radius-md),10px)] px-2 text-xs in-data-[slot=button-group]:rounded-lg has-data-[icon=inline-end]:pr-1.5 has-data-[icon=inline-start]:pl-1.5 [&_svg:not([class*='size-'])]:size-3",
        sm: "h-7 gap-1 rounded-[min(var(--radius-md),12px)] px-2.5 text-[0.8rem] in-data-[slot=button-group]:rounded-lg has-data-[icon=inline-end]:pr-1.5 has-data-[icon=inline-start]:pl-1.5 [&_svg:not([class*='size-'])]:size-3.5",
        lg: "h-9 gap-1.5 px-2.5 has-data-[icon=inline-end]:pr-2 has-data-[icon=inline-start]:pl-2",
        icon: "size-8",
        "icon-xs":
          "size-6 rounded-[min(var(--radius-md),10px)] in-data-[slot=button-group]:rounded-lg [&_svg:not([class*='size-'])]:size-3",
        "icon-sm":
          "size-7 rounded-[min(var(--radius-md),12px)] in-data-[slot=button-group]:rounded-lg",
        "icon-lg": "size-9",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  }
)

function Button({
  className,
  variant = "default",
  size = "default",
  asChild = false,
  ...props
}: React.ComponentProps<"button"> &
  VariantProps<typeof buttonVariants> & {
    asChild?: boolean
  }) {
  const Comp = asChild ? Slot.Root : "button"

  return (
    <Comp
      data-slot="button"
      data-variant={variant}
      data-size={size}
      className={cn(buttonVariants({ variant, size, className }))}
      {...props}
    />
  )
}

export { Button, buttonVariants }

END_OF_FILE_CONTENT
echo "Creating src/components/ui/card.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/ui/card.tsx"
import * as React from "react"

import { cn } from "@/lib/utils"

function Card({
  className,
  size = "default",
  ...props
}: React.ComponentProps<"div"> & { size?: "default" | "sm" }) {
  return (
    <div
      data-slot="card"
      data-size={size}
      className={cn(
        "group/card flex flex-col gap-4 overflow-hidden rounded-xl bg-card py-4 text-sm text-card-foreground ring-1 ring-foreground/10 has-data-[slot=card-footer]:pb-0 has-[>img:first-child]:pt-0 data-[size=sm]:gap-3 data-[size=sm]:py-3 data-[size=sm]:has-data-[slot=card-footer]:pb-0 *:[img:first-child]:rounded-t-xl *:[img:last-child]:rounded-b-xl",
        className
      )}
      {...props}
    />
  )
}

function CardHeader({ className, ...props }: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="card-header"
      className={cn(
        "group/card-header @container/card-header grid auto-rows-min items-start gap-1 rounded-t-xl px-4 group-data-[size=sm]/card:px-3 has-data-[slot=card-action]:grid-cols-[1fr_auto] has-data-[slot=card-description]:grid-rows-[auto_auto] [.border-b]:pb-4 group-data-[size=sm]/card:[.border-b]:pb-3",
        className
      )}
      {...props}
    />
  )
}

function CardTitle({ className, ...props }: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="card-title"
      className={cn(
        "text-base leading-snug font-medium group-data-[size=sm]/card:text-sm",
        className
      )}
      {...props}
    />
  )
}

function CardDescription({ className, ...props }: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="card-description"
      className={cn("text-sm text-muted-foreground", className)}
      {...props}
    />
  )
}

function CardAction({ className, ...props }: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="card-action"
      className={cn(
        "col-start-2 row-span-2 row-start-1 self-start justify-self-end",
        className
      )}
      {...props}
    />
  )
}

function CardContent({ className, ...props }: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="card-content"
      className={cn("px-4 group-data-[size=sm]/card:px-3", className)}
      {...props}
    />
  )
}

function CardFooter({ className, ...props }: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="card-footer"
      className={cn(
        "flex items-center rounded-b-xl border-t bg-muted/50 p-4 group-data-[size=sm]/card:p-3",
        className
      )}
      {...props}
    />
  )
}

export {
  Card,
  CardHeader,
  CardFooter,
  CardTitle,
  CardAction,
  CardDescription,
  CardContent,
}

END_OF_FILE_CONTENT
echo "Creating src/components/ui/checkbox.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/ui/checkbox.tsx"
"use client"

import * as React from "react"
import { Checkbox as CheckboxPrimitive } from "radix-ui"

import { cn } from "@/lib/utils"
import { CheckIcon } from "lucide-react"

function Checkbox({
  className,
  ...props
}: React.ComponentProps<typeof CheckboxPrimitive.Root>) {
  return (
    <CheckboxPrimitive.Root
      data-slot="checkbox"
      className={cn(
        "peer relative flex size-4 shrink-0 items-center justify-center rounded-[4px] border border-input transition-colors outline-none group-has-disabled/field:opacity-50 after:absolute after:-inset-x-3 after:-inset-y-2 focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 disabled:cursor-not-allowed disabled:opacity-50 aria-invalid:border-destructive aria-invalid:ring-3 aria-invalid:ring-destructive/20 aria-invalid:aria-checked:border-primary dark:bg-input/30 dark:aria-invalid:border-destructive/50 dark:aria-invalid:ring-destructive/40 data-checked:border-primary data-checked:bg-primary data-checked:text-primary-foreground dark:data-checked:bg-primary",
        className
      )}
      {...props}
    >
      <CheckboxPrimitive.Indicator
        data-slot="checkbox-indicator"
        className="grid place-content-center text-current transition-none [&>svg]:size-3.5"
      >
        <CheckIcon
        />
      </CheckboxPrimitive.Indicator>
    </CheckboxPrimitive.Root>
  )
}

export { Checkbox }

END_OF_FILE_CONTENT
echo "Creating src/components/ui/dialog.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/ui/dialog.tsx"
import * as React from "react"
import { Dialog as DialogPrimitive } from "radix-ui"

import { cn } from "@/lib/utils"
import { Button } from "@/components/ui/button"
import { XIcon } from "lucide-react"

function Dialog({
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Root>) {
  return <DialogPrimitive.Root data-slot="dialog" {...props} />
}

function DialogTrigger({
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Trigger>) {
  return <DialogPrimitive.Trigger data-slot="dialog-trigger" {...props} />
}

function DialogPortal({
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Portal>) {
  return <DialogPrimitive.Portal data-slot="dialog-portal" {...props} />
}

function DialogClose({
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Close>) {
  return <DialogPrimitive.Close data-slot="dialog-close" {...props} />
}

function DialogOverlay({
  className,
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Overlay>) {
  return (
    <DialogPrimitive.Overlay
      data-slot="dialog-overlay"
      className={cn(
        "fixed inset-0 isolate z-50 bg-black/10 duration-100 supports-backdrop-filter:backdrop-blur-xs data-open:animate-in data-open:fade-in-0 data-closed:animate-out data-closed:fade-out-0",
        className
      )}
      {...props}
    />
  )
}

function DialogContent({
  className,
  children,
  showCloseButton = true,
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Content> & {
  showCloseButton?: boolean
}) {
  return (
    <DialogPortal>
      <DialogOverlay />
      <DialogPrimitive.Content
        data-slot="dialog-content"
        className={cn(
          "fixed top-1/2 left-1/2 z-50 grid w-full max-w-[calc(100%-2rem)] -translate-x-1/2 -translate-y-1/2 gap-4 rounded-xl bg-popover p-4 text-sm text-popover-foreground ring-1 ring-foreground/10 duration-100 outline-none sm:max-w-sm data-open:animate-in data-open:fade-in-0 data-open:zoom-in-95 data-closed:animate-out data-closed:fade-out-0 data-closed:zoom-out-95",
          className
        )}
        {...props}
      >
        {children}
        {showCloseButton && (
          <DialogPrimitive.Close data-slot="dialog-close" asChild>
            <Button
              variant="ghost"
              className="absolute top-2 right-2"
              size="icon-sm"
            >
              <XIcon
              />
              <span className="sr-only">Close</span>
            </Button>
          </DialogPrimitive.Close>
        )}
      </DialogPrimitive.Content>
    </DialogPortal>
  )
}

function DialogHeader({ className, ...props }: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="dialog-header"
      className={cn("flex flex-col gap-2", className)}
      {...props}
    />
  )
}

function DialogFooter({
  className,
  showCloseButton = false,
  children,
  ...props
}: React.ComponentProps<"div"> & {
  showCloseButton?: boolean
}) {
  return (
    <div
      data-slot="dialog-footer"
      className={cn(
        "-mx-4 -mb-4 flex flex-col-reverse gap-2 rounded-b-xl border-t bg-muted/50 p-4 sm:flex-row sm:justify-end",
        className
      )}
      {...props}
    >
      {children}
      {showCloseButton && (
        <DialogPrimitive.Close asChild>
          <Button variant="outline">Close</Button>
        </DialogPrimitive.Close>
      )}
    </div>
  )
}

function DialogTitle({
  className,
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Title>) {
  return (
    <DialogPrimitive.Title
      data-slot="dialog-title"
      className={cn(
        "text-base leading-none font-medium",
        className
      )}
      {...props}
    />
  )
}

function DialogDescription({
  className,
  ...props
}: React.ComponentProps<typeof DialogPrimitive.Description>) {
  return (
    <DialogPrimitive.Description
      data-slot="dialog-description"
      className={cn(
        "text-sm text-muted-foreground *:[a]:underline *:[a]:underline-offset-3 *:[a]:hover:text-foreground",
        className
      )}
      {...props}
    />
  )
}

export {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogOverlay,
  DialogPortal,
  DialogTitle,
  DialogTrigger,
}

END_OF_FILE_CONTENT
echo "Creating src/components/ui/dropdown-menu.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/ui/dropdown-menu.tsx"
import * as React from "react"
import { DropdownMenu as DropdownMenuPrimitive } from "radix-ui"

import { cn } from "@/lib/utils"
import { CheckIcon, ChevronRightIcon } from "lucide-react"

function DropdownMenu({
  ...props
}: React.ComponentProps<typeof DropdownMenuPrimitive.Root>) {
  return <DropdownMenuPrimitive.Root data-slot="dropdown-menu" {...props} />
}

function DropdownMenuPortal({
  ...props
}: React.ComponentProps<typeof DropdownMenuPrimitive.Portal>) {
  return (
    <DropdownMenuPrimitive.Portal data-slot="dropdown-menu-portal" {...props} />
  )
}

function DropdownMenuTrigger({
  ...props
}: React.ComponentProps<typeof DropdownMenuPrimitive.Trigger>) {
  return (
    <DropdownMenuPrimitive.Trigger
      data-slot="dropdown-menu-trigger"
      {...props}
    />
  )
}

function DropdownMenuContent({
  className,
  align = "start",
  sideOffset = 4,
  ...props
}: React.ComponentProps<typeof DropdownMenuPrimitive.Content>) {
  return (
    <DropdownMenuPrimitive.Portal>
      <DropdownMenuPrimitive.Content
        data-slot="dropdown-menu-content"
        sideOffset={sideOffset}
        align={align}
        className={cn("z-50 max-h-(--radix-dropdown-menu-content-available-height) w-(--radix-dropdown-menu-trigger-width) min-w-32 origin-(--radix-dropdown-menu-content-transform-origin) overflow-x-hidden overflow-y-auto rounded-lg bg-popover p-1 text-popover-foreground shadow-md ring-1 ring-foreground/10 duration-100 data-[side=bottom]:slide-in-from-top-2 data-[side=left]:slide-in-from-right-2 data-[side=right]:slide-in-from-left-2 data-[side=top]:slide-in-from-bottom-2 data-[state=closed]:overflow-hidden data-open:animate-in data-open:fade-in-0 data-open:zoom-in-95 data-closed:animate-out data-closed:fade-out-0 data-closed:zoom-out-95", className )}
        {...props}
      />
    </DropdownMenuPrimitive.Portal>
  )
}

function DropdownMenuGroup({
  ...props
}: React.ComponentProps<typeof DropdownMenuPrimitive.Group>) {
  return (
    <DropdownMenuPrimitive.Group data-slot="dropdown-menu-group" {...props} />
  )
}

function DropdownMenuItem({
  className,
  inset,
  variant = "default",
  ...props
}: React.ComponentProps<typeof DropdownMenuPrimitive.Item> & {
  inset?: boolean
  variant?: "default" | "destructive"
}) {
  return (
    <DropdownMenuPrimitive.Item
      data-slot="dropdown-menu-item"
      data-inset={inset}
      data-variant={variant}
      className={cn(
        "group/dropdown-menu-item relative flex cursor-default items-center gap-1.5 rounded-md px-1.5 py-1 text-sm outline-hidden select-none focus:bg-accent focus:text-accent-foreground not-data-[variant=destructive]:focus:**:text-accent-foreground data-inset:pl-7 data-[variant=destructive]:text-destructive data-[variant=destructive]:focus:bg-destructive/10 data-[variant=destructive]:focus:text-destructive dark:data-[variant=destructive]:focus:bg-destructive/20 data-disabled:pointer-events-none data-disabled:opacity-50 [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4 data-[variant=destructive]:*:[svg]:text-destructive",
        className
      )}
      {...props}
    />
  )
}

function DropdownMenuCheckboxItem({
  className,
  children,
  checked,
  inset,
  ...props
}: React.ComponentProps<typeof DropdownMenuPrimitive.CheckboxItem> & {
  inset?: boolean
}) {
  return (
    <DropdownMenuPrimitive.CheckboxItem
      data-slot="dropdown-menu-checkbox-item"
      data-inset={inset}
      className={cn(
        "relative flex cursor-default items-center gap-1.5 rounded-md py-1 pr-8 pl-1.5 text-sm outline-hidden select-none focus:bg-accent focus:text-accent-foreground focus:**:text-accent-foreground data-inset:pl-7 data-disabled:pointer-events-none data-disabled:opacity-50 [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4",
        className
      )}
      checked={checked}
      {...props}
    >
      <span
        className="pointer-events-none absolute right-2 flex items-center justify-center"
        data-slot="dropdown-menu-checkbox-item-indicator"
      >
        <DropdownMenuPrimitive.ItemIndicator>
          <CheckIcon
          />
        </DropdownMenuPrimitive.ItemIndicator>
      </span>
      {children}
    </DropdownMenuPrimitive.CheckboxItem>
  )
}

function DropdownMenuRadioGroup({
  ...props
}: React.ComponentProps<typeof DropdownMenuPrimitive.RadioGroup>) {
  return (
    <DropdownMenuPrimitive.RadioGroup
      data-slot="dropdown-menu-radio-group"
      {...props}
    />
  )
}

function DropdownMenuRadioItem({
  className,
  children,
  inset,
  ...props
}: React.ComponentProps<typeof DropdownMenuPrimitive.RadioItem> & {
  inset?: boolean
}) {
  return (
    <DropdownMenuPrimitive.RadioItem
      data-slot="dropdown-menu-radio-item"
      data-inset={inset}
      className={cn(
        "relative flex cursor-default items-center gap-1.5 rounded-md py-1 pr-8 pl-1.5 text-sm outline-hidden select-none focus:bg-accent focus:text-accent-foreground focus:**:text-accent-foreground data-inset:pl-7 data-disabled:pointer-events-none data-disabled:opacity-50 [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4",
        className
      )}
      {...props}
    >
      <span
        className="pointer-events-none absolute right-2 flex items-center justify-center"
        data-slot="dropdown-menu-radio-item-indicator"
      >
        <DropdownMenuPrimitive.ItemIndicator>
          <CheckIcon
          />
        </DropdownMenuPrimitive.ItemIndicator>
      </span>
      {children}
    </DropdownMenuPrimitive.RadioItem>
  )
}

function DropdownMenuLabel({
  className,
  inset,
  ...props
}: React.ComponentProps<typeof DropdownMenuPrimitive.Label> & {
  inset?: boolean
}) {
  return (
    <DropdownMenuPrimitive.Label
      data-slot="dropdown-menu-label"
      data-inset={inset}
      className={cn(
        "px-1.5 py-1 text-xs font-medium text-muted-foreground data-inset:pl-7",
        className
      )}
      {...props}
    />
  )
}

function DropdownMenuSeparator({
  className,
  ...props
}: React.ComponentProps<typeof DropdownMenuPrimitive.Separator>) {
  return (
    <DropdownMenuPrimitive.Separator
      data-slot="dropdown-menu-separator"
      className={cn("-mx-1 my-1 h-px bg-border", className)}
      {...props}
    />
  )
}

function DropdownMenuShortcut({
  className,
  ...props
}: React.ComponentProps<"span">) {
  return (
    <span
      data-slot="dropdown-menu-shortcut"
      className={cn(
        "ml-auto text-xs tracking-widest text-muted-foreground group-focus/dropdown-menu-item:text-accent-foreground",
        className
      )}
      {...props}
    />
  )
}

function DropdownMenuSub({
  ...props
}: React.ComponentProps<typeof DropdownMenuPrimitive.Sub>) {
  return <DropdownMenuPrimitive.Sub data-slot="dropdown-menu-sub" {...props} />
}

function DropdownMenuSubTrigger({
  className,
  inset,
  children,
  ...props
}: React.ComponentProps<typeof DropdownMenuPrimitive.SubTrigger> & {
  inset?: boolean
}) {
  return (
    <DropdownMenuPrimitive.SubTrigger
      data-slot="dropdown-menu-sub-trigger"
      data-inset={inset}
      className={cn(
        "flex cursor-default items-center gap-1.5 rounded-md px-1.5 py-1 text-sm outline-hidden select-none focus:bg-accent focus:text-accent-foreground not-data-[variant=destructive]:focus:**:text-accent-foreground data-inset:pl-7 data-open:bg-accent data-open:text-accent-foreground [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4",
        className
      )}
      {...props}
    >
      {children}
      <ChevronRightIcon className="ml-auto" />
    </DropdownMenuPrimitive.SubTrigger>
  )
}

function DropdownMenuSubContent({
  className,
  ...props
}: React.ComponentProps<typeof DropdownMenuPrimitive.SubContent>) {
  return (
    <DropdownMenuPrimitive.SubContent
      data-slot="dropdown-menu-sub-content"
      className={cn("z-50 min-w-[96px] origin-(--radix-dropdown-menu-content-transform-origin) overflow-hidden rounded-lg bg-popover p-1 text-popover-foreground shadow-lg ring-1 ring-foreground/10 duration-100 data-[side=bottom]:slide-in-from-top-2 data-[side=left]:slide-in-from-right-2 data-[side=right]:slide-in-from-left-2 data-[side=top]:slide-in-from-bottom-2 data-open:animate-in data-open:fade-in-0 data-open:zoom-in-95 data-closed:animate-out data-closed:fade-out-0 data-closed:zoom-out-95", className )}
      {...props}
    />
  )
}

export {
  DropdownMenu,
  DropdownMenuPortal,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuLabel,
  DropdownMenuItem,
  DropdownMenuCheckboxItem,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSeparator,
  DropdownMenuShortcut,
  DropdownMenuSub,
  DropdownMenuSubTrigger,
  DropdownMenuSubContent,
}

END_OF_FILE_CONTENT
echo "Creating src/components/ui/hover-card.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/ui/hover-card.tsx"
"use client"

import * as React from "react"
import { HoverCard as HoverCardPrimitive } from "radix-ui"

import { cn } from "@/lib/utils"

function HoverCard({
  ...props
}: React.ComponentProps<typeof HoverCardPrimitive.Root>) {
  return <HoverCardPrimitive.Root data-slot="hover-card" {...props} />
}

function HoverCardTrigger({
  ...props
}: React.ComponentProps<typeof HoverCardPrimitive.Trigger>) {
  return (
    <HoverCardPrimitive.Trigger data-slot="hover-card-trigger" {...props} />
  )
}

function HoverCardContent({
  className,
  align = "center",
  sideOffset = 4,
  ...props
}: React.ComponentProps<typeof HoverCardPrimitive.Content>) {
  return (
    <HoverCardPrimitive.Portal data-slot="hover-card-portal">
      <HoverCardPrimitive.Content
        data-slot="hover-card-content"
        align={align}
        sideOffset={sideOffset}
        className={cn(
          "z-50 w-64 origin-(--radix-hover-card-content-transform-origin) rounded-lg bg-popover p-2.5 text-sm text-popover-foreground shadow-md ring-1 ring-foreground/10 outline-hidden duration-100 data-[side=bottom]:slide-in-from-top-2 data-[side=left]:slide-in-from-right-2 data-[side=right]:slide-in-from-left-2 data-[side=top]:slide-in-from-bottom-2 data-open:animate-in data-open:fade-in-0 data-open:zoom-in-95 data-closed:animate-out data-closed:fade-out-0 data-closed:zoom-out-95",
          className
        )}
        {...props}
      />
    </HoverCardPrimitive.Portal>
  )
}

export { HoverCard, HoverCardTrigger, HoverCardContent }

END_OF_FILE_CONTENT
echo "Creating src/components/ui/input.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/ui/input.tsx"
import * as React from "react"

import { cn } from "@/lib/utils"

function Input({ className, type, ...props }: React.ComponentProps<"input">) {
  return (
    <input
      type={type}
      data-slot="input"
      className={cn(
        "h-8 w-full min-w-0 rounded-lg border border-input bg-transparent px-2.5 py-1 text-base transition-colors outline-none file:inline-flex file:h-6 file:border-0 file:bg-transparent file:text-sm file:font-medium file:text-foreground placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 disabled:pointer-events-none disabled:cursor-not-allowed disabled:bg-input/50 disabled:opacity-50 aria-invalid:border-destructive aria-invalid:ring-3 aria-invalid:ring-destructive/20 md:text-sm dark:bg-input/30 dark:disabled:bg-input/80 dark:aria-invalid:border-destructive/50 dark:aria-invalid:ring-destructive/40",
        className
      )}
      {...props}
    />
  )
}

export { Input }

END_OF_FILE_CONTENT
echo "Creating src/components/ui/label.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/ui/label.tsx"
"use client"

import * as React from "react"
import { Label as LabelPrimitive } from "radix-ui"

import { cn } from "@/lib/utils"

function Label({
  className,
  ...props
}: React.ComponentProps<typeof LabelPrimitive.Root>) {
  return (
    <LabelPrimitive.Root
      data-slot="label"
      className={cn(
        "flex items-center gap-2 text-sm leading-none font-medium select-none group-data-[disabled=true]:pointer-events-none group-data-[disabled=true]:opacity-50 peer-disabled:cursor-not-allowed peer-disabled:opacity-50",
        className
      )}
      {...props}
    />
  )
}

export { Label }

END_OF_FILE_CONTENT
echo "Creating src/components/ui/navigation-menu.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/ui/navigation-menu.tsx"
import * as React from "react"
import { cva } from "class-variance-authority"
import { NavigationMenu as NavigationMenuPrimitive } from "radix-ui"

import { cn } from "@/lib/utils"
import { ChevronDownIcon } from "lucide-react"

function NavigationMenu({
  className,
  children,
  viewport = true,
  ...props
}: React.ComponentProps<typeof NavigationMenuPrimitive.Root> & {
  viewport?: boolean
}) {
  return (
    <NavigationMenuPrimitive.Root
      data-slot="navigation-menu"
      data-viewport={viewport}
      className={cn(
        "group/navigation-menu relative flex max-w-max flex-1 items-center justify-center",
        className
      )}
      {...props}
    >
      {children}
      {viewport && <NavigationMenuViewport />}
    </NavigationMenuPrimitive.Root>
  )
}

function NavigationMenuList({
  className,
  ...props
}: React.ComponentProps<typeof NavigationMenuPrimitive.List>) {
  return (
    <NavigationMenuPrimitive.List
      data-slot="navigation-menu-list"
      className={cn(
        "group flex flex-1 list-none items-center justify-center gap-0",
        className
      )}
      {...props}
    />
  )
}

function NavigationMenuItem({
  className,
  ...props
}: React.ComponentProps<typeof NavigationMenuPrimitive.Item>) {
  return (
    <NavigationMenuPrimitive.Item
      data-slot="navigation-menu-item"
      className={cn("relative", className)}
      {...props}
    />
  )
}

const navigationMenuTriggerStyle = cva(
  "group/navigation-menu-trigger inline-flex h-9 w-max items-center justify-center rounded-lg px-2.5 py-1.5 text-sm font-medium transition-all outline-none hover:bg-muted focus:bg-muted focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-1 disabled:pointer-events-none disabled:opacity-50 data-popup-open:bg-muted/50 data-popup-open:hover:bg-muted data-open:bg-muted/50 data-open:hover:bg-muted data-open:focus:bg-muted"
)

function NavigationMenuTrigger({
  className,
  children,
  ...props
}: React.ComponentProps<typeof NavigationMenuPrimitive.Trigger>) {
  return (
    <NavigationMenuPrimitive.Trigger
      data-slot="navigation-menu-trigger"
      className={cn(navigationMenuTriggerStyle(), "group", className)}
      {...props}
    >
      {children}{" "}
      <ChevronDownIcon className="relative top-px ml-1 size-3 transition duration-300 group-data-popup-open/navigation-menu-trigger:rotate-180 group-data-open/navigation-menu-trigger:rotate-180" aria-hidden="true" />
    </NavigationMenuPrimitive.Trigger>
  )
}

function NavigationMenuContent({
  className,
  ...props
}: React.ComponentProps<typeof NavigationMenuPrimitive.Content>) {
  return (
    <NavigationMenuPrimitive.Content
      data-slot="navigation-menu-content"
      className={cn(
        "top-0 left-0 w-full p-1 ease-[cubic-bezier(0.22,1,0.36,1)] group-data-[viewport=false]/navigation-menu:top-full group-data-[viewport=false]/navigation-menu:mt-1.5 group-data-[viewport=false]/navigation-menu:overflow-hidden group-data-[viewport=false]/navigation-menu:rounded-lg group-data-[viewport=false]/navigation-menu:bg-popover group-data-[viewport=false]/navigation-menu:text-popover-foreground group-data-[viewport=false]/navigation-menu:shadow group-data-[viewport=false]/navigation-menu:ring-1 group-data-[viewport=false]/navigation-menu:ring-foreground/10 group-data-[viewport=false]/navigation-menu:duration-300 data-[motion=from-end]:slide-in-from-right-52 data-[motion=from-start]:slide-in-from-left-52 data-[motion=to-end]:slide-out-to-right-52 data-[motion=to-start]:slide-out-to-left-52 data-[motion^=from-]:animate-in data-[motion^=from-]:fade-in data-[motion^=to-]:animate-out data-[motion^=to-]:fade-out **:data-[slot=navigation-menu-link]:focus:ring-0 **:data-[slot=navigation-menu-link]:focus:outline-none md:absolute md:w-auto group-data-[viewport=false]/navigation-menu:data-open:animate-in group-data-[viewport=false]/navigation-menu:data-open:fade-in-0 group-data-[viewport=false]/navigation-menu:data-open:zoom-in-95 group-data-[viewport=false]/navigation-menu:data-closed:animate-out group-data-[viewport=false]/navigation-menu:data-closed:fade-out-0 group-data-[viewport=false]/navigation-menu:data-closed:zoom-out-95",
        className
      )}
      {...props}
    />
  )
}

function NavigationMenuViewport({
  className,
  ...props
}: React.ComponentProps<typeof NavigationMenuPrimitive.Viewport>) {
  return (
    <div
      className={cn(
        "absolute top-full left-0 isolate z-50 flex justify-center"
      )}
    >
      <NavigationMenuPrimitive.Viewport
        data-slot="navigation-menu-viewport"
        className={cn(
          "origin-top-center relative mt-1.5 h-(--radix-navigation-menu-viewport-height) w-full overflow-hidden rounded-lg bg-popover text-popover-foreground shadow ring-1 ring-foreground/10 duration-100 md:w-(--radix-navigation-menu-viewport-width) data-open:animate-in data-open:zoom-in-90 data-closed:animate-out data-closed:zoom-out-90",
          className
        )}
        {...props}
      />
    </div>
  )
}

function NavigationMenuLink({
  className,
  ...props
}: React.ComponentProps<typeof NavigationMenuPrimitive.Link>) {
  return (
    <NavigationMenuPrimitive.Link
      data-slot="navigation-menu-link"
      className={cn(
        "flex items-center gap-2 rounded-lg p-2 text-sm transition-all outline-none hover:bg-muted focus:bg-muted focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-1 in-data-[slot=navigation-menu-content]:rounded-md data-active:bg-muted/50 data-active:hover:bg-muted data-active:focus:bg-muted [&_svg:not([class*='size-'])]:size-4",
        className
      )}
      {...props}
    />
  )
}

function NavigationMenuIndicator({
  className,
  ...props
}: React.ComponentProps<typeof NavigationMenuPrimitive.Indicator>) {
  return (
    <NavigationMenuPrimitive.Indicator
      data-slot="navigation-menu-indicator"
      className={cn(
        "top-full z-1 flex h-1.5 items-end justify-center overflow-hidden data-[state=hidden]:animate-out data-[state=hidden]:fade-out data-[state=visible]:animate-in data-[state=visible]:fade-in",
        className
      )}
      {...props}
    >
      <div className="relative top-[60%] h-2 w-2 rotate-45 rounded-tl-sm bg-border shadow-md" />
    </NavigationMenuPrimitive.Indicator>
  )
}

export {
  NavigationMenu,
  NavigationMenuList,
  NavigationMenuItem,
  NavigationMenuContent,
  NavigationMenuTrigger,
  NavigationMenuLink,
  NavigationMenuIndicator,
  NavigationMenuViewport,
  navigationMenuTriggerStyle,
}

END_OF_FILE_CONTENT
echo "Creating src/components/ui/progress.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/ui/progress.tsx"
import * as React from "react"
import { Progress as ProgressPrimitive } from "radix-ui"

import { cn } from "@/lib/utils"

function Progress({
  className,
  value,
  ...props
}: React.ComponentProps<typeof ProgressPrimitive.Root>) {
  return (
    <ProgressPrimitive.Root
      data-slot="progress"
      className={cn(
        "relative flex h-1 w-full items-center overflow-x-hidden rounded-full bg-muted",
        className
      )}
      {...props}
    >
      <ProgressPrimitive.Indicator
        data-slot="progress-indicator"
        className="size-full flex-1 bg-primary transition-all"
        style={{ transform: `translateX(-${100 - (value || 0)}%)` }}
      />
    </ProgressPrimitive.Root>
  )
}

export { Progress }

END_OF_FILE_CONTENT
echo "Creating src/components/ui/scroll-area.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/ui/scroll-area.tsx"
import * as React from "react"
import { ScrollArea as ScrollAreaPrimitive } from "radix-ui"

import { cn } from "@/lib/utils"

function ScrollArea({
  className,
  children,
  ...props
}: React.ComponentProps<typeof ScrollAreaPrimitive.Root>) {
  return (
    <ScrollAreaPrimitive.Root
      data-slot="scroll-area"
      className={cn("relative", className)}
      {...props}
    >
      <ScrollAreaPrimitive.Viewport
        data-slot="scroll-area-viewport"
        className="size-full rounded-[inherit] transition-[color,box-shadow] outline-none focus-visible:ring-[3px] focus-visible:ring-ring/50 focus-visible:outline-1"
      >
        {children}
      </ScrollAreaPrimitive.Viewport>
      <ScrollBar />
      <ScrollAreaPrimitive.Corner />
    </ScrollAreaPrimitive.Root>
  )
}

function ScrollBar({
  className,
  orientation = "vertical",
  ...props
}: React.ComponentProps<typeof ScrollAreaPrimitive.ScrollAreaScrollbar>) {
  return (
    <ScrollAreaPrimitive.ScrollAreaScrollbar
      data-slot="scroll-area-scrollbar"
      data-orientation={orientation}
      orientation={orientation}
      className={cn(
        "flex touch-none p-px transition-colors select-none data-horizontal:h-2.5 data-horizontal:flex-col data-horizontal:border-t data-horizontal:border-t-transparent data-vertical:h-full data-vertical:w-2.5 data-vertical:border-l data-vertical:border-l-transparent",
        className
      )}
      {...props}
    >
      <ScrollAreaPrimitive.ScrollAreaThumb
        data-slot="scroll-area-thumb"
        className="relative flex-1 rounded-full bg-border"
      />
    </ScrollAreaPrimitive.ScrollAreaScrollbar>
  )
}

export { ScrollArea, ScrollBar }

END_OF_FILE_CONTENT
echo "Creating src/components/ui/select.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/ui/select.tsx"
import * as React from "react"
import { Select as SelectPrimitive } from "radix-ui"

import { cn } from "@/lib/utils"
import { ChevronDownIcon, CheckIcon, ChevronUpIcon } from "lucide-react"

function Select({
  ...props
}: React.ComponentProps<typeof SelectPrimitive.Root>) {
  return <SelectPrimitive.Root data-slot="select" {...props} />
}

function SelectGroup({
  className,
  ...props
}: React.ComponentProps<typeof SelectPrimitive.Group>) {
  return (
    <SelectPrimitive.Group
      data-slot="select-group"
      className={cn("scroll-my-1 p-1", className)}
      {...props}
    />
  )
}

function SelectValue({
  ...props
}: React.ComponentProps<typeof SelectPrimitive.Value>) {
  return <SelectPrimitive.Value data-slot="select-value" {...props} />
}

function SelectTrigger({
  className,
  size = "default",
  children,
  ...props
}: React.ComponentProps<typeof SelectPrimitive.Trigger> & {
  size?: "sm" | "default"
}) {
  return (
    <SelectPrimitive.Trigger
      data-slot="select-trigger"
      data-size={size}
      className={cn(
        "flex w-fit items-center justify-between gap-1.5 rounded-lg border border-input bg-transparent py-2 pr-2 pl-2.5 text-sm whitespace-nowrap transition-colors outline-none select-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 disabled:cursor-not-allowed disabled:opacity-50 aria-invalid:border-destructive aria-invalid:ring-3 aria-invalid:ring-destructive/20 data-placeholder:text-muted-foreground data-[size=default]:h-8 data-[size=sm]:h-7 data-[size=sm]:rounded-[min(var(--radius-md),10px)] *:data-[slot=select-value]:line-clamp-1 *:data-[slot=select-value]:flex *:data-[slot=select-value]:items-center *:data-[slot=select-value]:gap-1.5 dark:bg-input/30 dark:hover:bg-input/50 dark:aria-invalid:border-destructive/50 dark:aria-invalid:ring-destructive/40 [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4",
        className
      )}
      {...props}
    >
      {children}
      <SelectPrimitive.Icon asChild>
        <ChevronDownIcon className="pointer-events-none size-4 text-muted-foreground" />
      </SelectPrimitive.Icon>
    </SelectPrimitive.Trigger>
  )
}

function SelectContent({
  className,
  children,
  position = "item-aligned",
  align = "center",
  ...props
}: React.ComponentProps<typeof SelectPrimitive.Content>) {
  return (
    <SelectPrimitive.Portal>
      <SelectPrimitive.Content
        data-slot="select-content"
        data-align-trigger={position === "item-aligned"}
        className={cn("relative z-50 max-h-(--radix-select-content-available-height) min-w-36 origin-(--radix-select-content-transform-origin) overflow-x-hidden overflow-y-auto rounded-lg bg-popover text-popover-foreground shadow-md ring-1 ring-foreground/10 duration-100 data-[align-trigger=true]:animate-none data-[side=bottom]:slide-in-from-top-2 data-[side=left]:slide-in-from-right-2 data-[side=right]:slide-in-from-left-2 data-[side=top]:slide-in-from-bottom-2 data-open:animate-in data-open:fade-in-0 data-open:zoom-in-95 data-closed:animate-out data-closed:fade-out-0 data-closed:zoom-out-95", position ==="popper"&&"data-[side=bottom]:translate-y-1 data-[side=left]:-translate-x-1 data-[side=right]:translate-x-1 data-[side=top]:-translate-y-1", className )}
        position={position}
        align={align}
        {...props}
      >
        <SelectScrollUpButton />
        <SelectPrimitive.Viewport
          data-position={position}
          className={cn(
            "data-[position=popper]:h-(--radix-select-trigger-height) data-[position=popper]:w-full data-[position=popper]:min-w-(--radix-select-trigger-width)",
            position === "popper" && ""
          )}
        >
          {children}
        </SelectPrimitive.Viewport>
        <SelectScrollDownButton />
      </SelectPrimitive.Content>
    </SelectPrimitive.Portal>
  )
}

function SelectLabel({
  className,
  ...props
}: React.ComponentProps<typeof SelectPrimitive.Label>) {
  return (
    <SelectPrimitive.Label
      data-slot="select-label"
      className={cn("px-1.5 py-1 text-xs text-muted-foreground", className)}
      {...props}
    />
  )
}

function SelectItem({
  className,
  children,
  ...props
}: React.ComponentProps<typeof SelectPrimitive.Item>) {
  return (
    <SelectPrimitive.Item
      data-slot="select-item"
      className={cn(
        "relative flex w-full cursor-default items-center gap-1.5 rounded-md py-1 pr-8 pl-1.5 text-sm outline-hidden select-none focus:bg-accent focus:text-accent-foreground not-data-[variant=destructive]:focus:**:text-accent-foreground data-disabled:pointer-events-none data-disabled:opacity-50 [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4 *:[span]:last:flex *:[span]:last:items-center *:[span]:last:gap-2",
        className
      )}
      {...props}
    >
      <span className="pointer-events-none absolute right-2 flex size-4 items-center justify-center">
        <SelectPrimitive.ItemIndicator>
          <CheckIcon className="pointer-events-none" />
        </SelectPrimitive.ItemIndicator>
      </span>
      <SelectPrimitive.ItemText>{children}</SelectPrimitive.ItemText>
    </SelectPrimitive.Item>
  )
}

function SelectSeparator({
  className,
  ...props
}: React.ComponentProps<typeof SelectPrimitive.Separator>) {
  return (
    <SelectPrimitive.Separator
      data-slot="select-separator"
      className={cn("pointer-events-none -mx-1 my-1 h-px bg-border", className)}
      {...props}
    />
  )
}

function SelectScrollUpButton({
  className,
  ...props
}: React.ComponentProps<typeof SelectPrimitive.ScrollUpButton>) {
  return (
    <SelectPrimitive.ScrollUpButton
      data-slot="select-scroll-up-button"
      className={cn(
        "z-10 flex cursor-default items-center justify-center bg-popover py-1 [&_svg:not([class*='size-'])]:size-4",
        className
      )}
      {...props}
    >
      <ChevronUpIcon
      />
    </SelectPrimitive.ScrollUpButton>
  )
}

function SelectScrollDownButton({
  className,
  ...props
}: React.ComponentProps<typeof SelectPrimitive.ScrollDownButton>) {
  return (
    <SelectPrimitive.ScrollDownButton
      data-slot="select-scroll-down-button"
      className={cn(
        "z-10 flex cursor-default items-center justify-center bg-popover py-1 [&_svg:not([class*='size-'])]:size-4",
        className
      )}
      {...props}
    >
      <ChevronDownIcon
      />
    </SelectPrimitive.ScrollDownButton>
  )
}

export {
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectLabel,
  SelectScrollDownButton,
  SelectScrollUpButton,
  SelectSeparator,
  SelectTrigger,
  SelectValue,
}

END_OF_FILE_CONTENT
echo "Creating src/components/ui/select.txt..."
cat << 'END_OF_FILE_CONTENT' > "src/components/ui/select.txt"
import * as React from "react"
import { Select as SelectPrimitive } from "radix-ui"

import { cn } from "@/lib/utils"
import { ChevronDownIcon, CheckIcon, ChevronUpIcon } from "lucide-react"

function Select({
  ...props
}: React.ComponentProps<typeof SelectPrimitive.Root>) {
  return <SelectPrimitive.Root data-slot="select" {...props} />
}

function SelectGroup({
  className,
  ...props
}: React.ComponentProps<typeof SelectPrimitive.Group>) {
  return (
    <SelectPrimitive.Group
      data-slot="select-group"
      className={cn("scroll-my-1 p-1", className)}
      {...props}
    />
  )
}

function SelectValue({
  ...props
}: React.ComponentProps<typeof SelectPrimitive.Value>) {
  return <SelectPrimitive.Value data-slot="select-value" {...props} />
}

function SelectTrigger({
  className,
  size = "default",
  children,
  ...props
}: React.ComponentProps<typeof SelectPrimitive.Trigger> & {
  size?: "sm" | "default"
}) {
  return (
    <SelectPrimitive.Trigger
      data-slot="select-trigger"
      data-size={size}
      className={cn(
        "border-input data-placeholder:text-muted-foreground dark:bg-input/30 dark:hover:bg-input/50 focus-visible:border-ring focus-visible:ring-ring/50 aria-invalid:ring-destructive/20 dark:aria-invalid:ring-destructive/40 aria-invalid:border-destructive dark:aria-invalid:border-destructive/50 gap-1.5 rounded-lg border bg-transparent py-2 pr-2 pl-2.5 text-sm transition-colors select-none focus-visible:ring-3 aria-invalid:ring-3 data-[size=default]:h-8 data-[size=sm]:h-7 data-[size=sm]:rounded-[min(var(--radius-md),10px)] *:data-[slot=select-value]:gap-1.5 [&_svg:not([class*='size-'])]:size-4 flex w-full items-center justify-between whitespace-nowrap outline-none disabled:cursor-not-allowed disabled:opacity-50 *:data-[slot=select-value]:line-clamp-1 *:data-[slot=select-value]:flex *:data-[slot=select-value]:items-center [&_svg]:pointer-events-none [&_svg]:shrink-0",
        className
      )}
      {...props}
    >
      {children}
      <SelectPrimitive.Icon asChild>
        <ChevronDownIcon className="text-muted-foreground size-4 pointer-events-none" />
      </SelectPrimitive.Icon>
    </SelectPrimitive.Trigger>
  )
}

function SelectContent({
  className,
  children,
  position = "popper",
  align = "center",
  ...props
}: React.ComponentProps<typeof SelectPrimitive.Content>) {
  return (
    <SelectPrimitive.Portal>
      <SelectPrimitive.Content
        data-slot="select-content"
        data-align-trigger={position === "item-aligned"}
        className={cn(
          "bg-popover text-popover-foreground data-open:animate-in data-closed:animate-out data-closed:fade-out-0 data-open:fade-in-0 data-closed:zoom-out-95 data-open:zoom-in-95 data-[side=bottom]:slide-in-from-top-2 data-[side=left]:slide-in-from-right-2 data-[side=right]:slide-in-from-left-2 data-[side=top]:slide-in-from-bottom-2 ring-foreground/10 min-w-36 rounded-lg shadow-md ring-1 duration-100 relative z-[110] max-h-(--radix-select-content-available-height) origin-(--radix-select-content-transform-origin) overflow-x-hidden overflow-y-auto data-[align-trigger=true]:animate-none", 
          position === "popper" && "data-[side=bottom]:translate-y-1 data-[side=left]:-translate-x-1 data-[side=right]:translate-x-1 data-[side=top]:-translate-y-1", 
          className 
        )}
        position={position}
        align={align}
        {...props}
      >
        <SelectScrollUpButton />
        <SelectPrimitive.Viewport
          data-position={position}
          className={cn(
            "p-1",
            position === "popper" && "h-(--radix-select-trigger-height) w-full min-w-(--radix-select-trigger-width)"
          )}
        >
          {children}
        </SelectPrimitive.Viewport>
        <SelectScrollDownButton />
      </SelectPrimitive.Content>
    </SelectPrimitive.Portal>
  )
}

function SelectLabel({
  className,
  ...props
}: React.ComponentProps<typeof SelectPrimitive.Label>) {
  return (
    <SelectPrimitive.Label
      data-slot="select-label"
      className={cn("text-muted-foreground px-1.5 py-1 text-xs", className)}
      {...props}
    />
  )
}

function SelectItem({
  className,
  children,
  ...props
}: React.ComponentProps<typeof SelectPrimitive.Item>) {
  return (
    <SelectPrimitive.Item
      data-slot="select-item"
      className={cn(
        "focus:bg-accent focus:text-accent-foreground not-data-[variant=destructive]:focus:**:text-accent-foreground gap-1.5 rounded-md py-1 pr-8 pl-1.5 text-sm [&_svg:not([class*='size-'])]:size-4 *:[span]:last:flex *:[span]:last:items-center *:[span]:last:gap-2 relative flex w-full cursor-default items-center outline-hidden select-none data-disabled:pointer-events-none data-disabled:opacity-50 [&_svg]:pointer-events-none [&_svg]:shrink-0",
        className
      )}
      {...props}
    >
      <span className="pointer-events-none absolute right-2 flex size-4 items-center justify-center">
        <SelectPrimitive.ItemIndicator>
          <CheckIcon className="pointer-events-none" />
        </SelectPrimitive.ItemIndicator>
      </span>
      <SelectPrimitive.ItemText>{children}</SelectPrimitive.ItemText>
    </SelectPrimitive.Item>
  )
}

function SelectSeparator({
  className,
  ...props
}: React.ComponentProps<typeof SelectPrimitive.Separator>) {
  return (
    <SelectPrimitive.Separator
      data-slot="select-separator"
      className={cn("bg-border -mx-1 my-1 h-px pointer-events-none", className)}
      {...props}
    />
  )
}

function SelectScrollUpButton({
  className,
  ...props
}: React.ComponentProps<typeof SelectPrimitive.ScrollUpButton>) {
  return (
    <SelectPrimitive.ScrollUpButton
      data-slot="select-scroll-up-button"
      className={cn("bg-popover z-10 flex cursor-default items-center justify-center py-1 [&_svg:not([class*='size-'])]:size-4", className)}
      {...props}
    >
      <ChevronUpIcon />
    </SelectPrimitive.ScrollUpButton>
  )
}

function SelectScrollDownButton({
  className,
  ...props
}: React.ComponentProps<typeof SelectPrimitive.ScrollDownButton>) {
  return (
    <SelectPrimitive.ScrollDownButton
      data-slot="select-scroll-down-button"
      className={cn("bg-popover z-10 flex cursor-default items-center justify-center py-1 [&_svg:not([class*='size-'])]:size-4", className)}
      {...props}
    >
      <ChevronDownIcon />
    </SelectPrimitive.ScrollDownButton>
  )
}

export {
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectLabel,
  SelectScrollDownButton,
  SelectScrollUpButton,
  SelectSeparator,
  SelectTrigger,
  SelectValue,
}




END_OF_FILE_CONTENT
echo "Creating src/components/ui/separator.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/ui/separator.tsx"
import * as React from "react"
import { Separator as SeparatorPrimitive } from "radix-ui"

import { cn } from "@/lib/utils"

function Separator({
  className,
  orientation = "horizontal",
  decorative = true,
  ...props
}: React.ComponentProps<typeof SeparatorPrimitive.Root>) {
  return (
    <SeparatorPrimitive.Root
      data-slot="separator"
      decorative={decorative}
      orientation={orientation}
      className={cn(
        "shrink-0 bg-border data-horizontal:h-px data-horizontal:w-full data-vertical:w-px data-vertical:self-stretch",
        className
      )}
      {...props}
    />
  )
}

export { Separator }

END_OF_FILE_CONTENT
echo "Creating src/components/ui/sheet.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/ui/sheet.tsx"
"use client"

import * as React from "react"
import { Dialog as SheetPrimitive } from "radix-ui"

import { cn } from "@/lib/utils"
import { Button } from "@/components/ui/button"
import { XIcon } from "lucide-react"

function Sheet({ ...props }: React.ComponentProps<typeof SheetPrimitive.Root>) {
  return <SheetPrimitive.Root data-slot="sheet" {...props} />
}

function SheetTrigger({
  ...props
}: React.ComponentProps<typeof SheetPrimitive.Trigger>) {
  return <SheetPrimitive.Trigger data-slot="sheet-trigger" {...props} />
}

function SheetClose({
  ...props
}: React.ComponentProps<typeof SheetPrimitive.Close>) {
  return <SheetPrimitive.Close data-slot="sheet-close" {...props} />
}

function SheetPortal({
  ...props
}: React.ComponentProps<typeof SheetPrimitive.Portal>) {
  return <SheetPrimitive.Portal data-slot="sheet-portal" {...props} />
}

function SheetOverlay({
  className,
  ...props
}: React.ComponentProps<typeof SheetPrimitive.Overlay>) {
  return (
    <SheetPrimitive.Overlay
      data-slot="sheet-overlay"
      className={cn(
        "fixed inset-0 z-50 bg-black/10 duration-100 supports-backdrop-filter:backdrop-blur-xs data-open:animate-in data-open:fade-in-0 data-closed:animate-out data-closed:fade-out-0",
        className
      )}
      {...props}
    />
  )
}

function SheetContent({
  className,
  children,
  side = "right",
  showCloseButton = true,
  ...props
}: React.ComponentProps<typeof SheetPrimitive.Content> & {
  side?: "top" | "right" | "bottom" | "left"
  showCloseButton?: boolean
}) {
  return (
    <SheetPortal>
      <SheetOverlay />
      <SheetPrimitive.Content
        data-slot="sheet-content"
        data-side={side}
        className={cn(
          "fixed z-50 flex flex-col gap-4 bg-popover bg-clip-padding text-sm text-popover-foreground shadow-lg transition duration-200 ease-in-out data-[side=bottom]:inset-x-0 data-[side=bottom]:bottom-0 data-[side=bottom]:h-auto data-[side=bottom]:border-t data-[side=left]:inset-y-0 data-[side=left]:left-0 data-[side=left]:h-full data-[side=left]:w-3/4 data-[side=left]:border-r data-[side=right]:inset-y-0 data-[side=right]:right-0 data-[side=right]:h-full data-[side=right]:w-3/4 data-[side=right]:border-l data-[side=top]:inset-x-0 data-[side=top]:top-0 data-[side=top]:h-auto data-[side=top]:border-b data-[side=left]:sm:max-w-sm data-[side=right]:sm:max-w-sm data-open:animate-in data-open:fade-in-0 data-[side=bottom]:data-open:slide-in-from-bottom-10 data-[side=left]:data-open:slide-in-from-left-10 data-[side=right]:data-open:slide-in-from-right-10 data-[side=top]:data-open:slide-in-from-top-10 data-closed:animate-out data-closed:fade-out-0 data-[side=bottom]:data-closed:slide-out-to-bottom-10 data-[side=left]:data-closed:slide-out-to-left-10 data-[side=right]:data-closed:slide-out-to-right-10 data-[side=top]:data-closed:slide-out-to-top-10",
          className
        )}
        {...props}
      >
        {children}
        {showCloseButton && (
          <SheetPrimitive.Close data-slot="sheet-close" asChild>
            <Button
              variant="ghost"
              className="absolute top-3 right-3"
              size="icon-sm"
            >
              <XIcon
              />
              <span className="sr-only">Close</span>
            </Button>
          </SheetPrimitive.Close>
        )}
      </SheetPrimitive.Content>
    </SheetPortal>
  )
}

function SheetHeader({ className, ...props }: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="sheet-header"
      className={cn("flex flex-col gap-0.5 p-4", className)}
      {...props}
    />
  )
}

function SheetFooter({ className, ...props }: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="sheet-footer"
      className={cn("mt-auto flex flex-col gap-2 p-4", className)}
      {...props}
    />
  )
}

function SheetTitle({
  className,
  ...props
}: React.ComponentProps<typeof SheetPrimitive.Title>) {
  return (
    <SheetPrimitive.Title
      data-slot="sheet-title"
      className={cn(
        "text-base font-medium text-foreground",
        className
      )}
      {...props}
    />
  )
}

function SheetDescription({
  className,
  ...props
}: React.ComponentProps<typeof SheetPrimitive.Description>) {
  return (
    <SheetPrimitive.Description
      data-slot="sheet-description"
      className={cn("text-sm text-muted-foreground", className)}
      {...props}
    />
  )
}

export {
  Sheet,
  SheetTrigger,
  SheetClose,
  SheetContent,
  SheetHeader,
  SheetFooter,
  SheetTitle,
  SheetDescription,
}

END_OF_FILE_CONTENT
echo "Creating src/components/ui/skeleton.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/ui/skeleton.tsx"
import { cn } from "@/lib/utils"

function Skeleton({ className, ...props }: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="skeleton"
      className={cn("animate-pulse rounded-md bg-muted", className)}
      {...props}
    />
  )
}

export { Skeleton }

END_OF_FILE_CONTENT
echo "Creating src/components/ui/switch.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/ui/switch.tsx"
import * as React from "react"
import { Switch as SwitchPrimitive } from "radix-ui"

import { cn } from "@/lib/utils"

function Switch({
  className,
  size = "default",
  ...props
}: React.ComponentProps<typeof SwitchPrimitive.Root> & {
  size?: "sm" | "default"
}) {
  return (
    <SwitchPrimitive.Root
      data-slot="switch"
      data-size={size}
      className={cn(
        "peer group/switch relative inline-flex shrink-0 items-center rounded-full border border-transparent transition-all outline-none after:absolute after:-inset-x-3 after:-inset-y-2 focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 aria-invalid:border-destructive aria-invalid:ring-3 aria-invalid:ring-destructive/20 data-[size=default]:h-[18.4px] data-[size=default]:w-[32px] data-[size=sm]:h-[14px] data-[size=sm]:w-[24px] dark:aria-invalid:border-destructive/50 dark:aria-invalid:ring-destructive/40 data-checked:bg-primary data-unchecked:bg-input dark:data-unchecked:bg-input/80 data-disabled:cursor-not-allowed data-disabled:opacity-50",
        className
      )}
      {...props}
    >
      <SwitchPrimitive.Thumb
        data-slot="switch-thumb"
        className="pointer-events-none block rounded-full bg-background ring-0 transition-transform group-data-[size=default]/switch:size-4 group-data-[size=sm]/switch:size-3 group-data-[size=default]/switch:data-checked:translate-x-[calc(100%-2px)] group-data-[size=sm]/switch:data-checked:translate-x-[calc(100%-2px)] dark:data-checked:bg-primary-foreground group-data-[size=default]/switch:data-unchecked:translate-x-0 group-data-[size=sm]/switch:data-unchecked:translate-x-0 dark:data-unchecked:bg-foreground"
      />
    </SwitchPrimitive.Root>
  )
}

export { Switch }

END_OF_FILE_CONTENT
echo "Creating src/components/ui/table.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/ui/table.tsx"
import * as React from "react"

import { cn } from "@/lib/utils"

function Table({ className, ...props }: React.ComponentProps<"table">) {
  return (
    <div
      data-slot="table-container"
      className="relative w-full overflow-x-auto"
    >
      <table
        data-slot="table"
        className={cn("w-full caption-bottom text-sm", className)}
        {...props}
      />
    </div>
  )
}

function TableHeader({ className, ...props }: React.ComponentProps<"thead">) {
  return (
    <thead
      data-slot="table-header"
      className={cn("[&_tr]:border-b", className)}
      {...props}
    />
  )
}

function TableBody({ className, ...props }: React.ComponentProps<"tbody">) {
  return (
    <tbody
      data-slot="table-body"
      className={cn("[&_tr:last-child]:border-0", className)}
      {...props}
    />
  )
}

function TableFooter({ className, ...props }: React.ComponentProps<"tfoot">) {
  return (
    <tfoot
      data-slot="table-footer"
      className={cn(
        "border-t bg-muted/50 font-medium [&>tr]:last:border-b-0",
        className
      )}
      {...props}
    />
  )
}

function TableRow({ className, ...props }: React.ComponentProps<"tr">) {
  return (
    <tr
      data-slot="table-row"
      className={cn(
        "border-b transition-colors hover:bg-muted/50 has-aria-expanded:bg-muted/50 data-[state=selected]:bg-muted",
        className
      )}
      {...props}
    />
  )
}

function TableHead({ className, ...props }: React.ComponentProps<"th">) {
  return (
    <th
      data-slot="table-head"
      className={cn(
        "h-10 px-2 text-left align-middle font-medium whitespace-nowrap text-foreground [&:has([role=checkbox])]:pr-0",
        className
      )}
      {...props}
    />
  )
}

function TableCell({ className, ...props }: React.ComponentProps<"td">) {
  return (
    <td
      data-slot="table-cell"
      className={cn(
        "p-2 align-middle whitespace-nowrap [&:has([role=checkbox])]:pr-0",
        className
      )}
      {...props}
    />
  )
}

function TableCaption({
  className,
  ...props
}: React.ComponentProps<"caption">) {
  return (
    <caption
      data-slot="table-caption"
      className={cn("mt-4 text-sm text-muted-foreground", className)}
      {...props}
    />
  )
}

export {
  Table,
  TableHeader,
  TableBody,
  TableFooter,
  TableHead,
  TableRow,
  TableCell,
  TableCaption,
}

END_OF_FILE_CONTENT
echo "Creating src/components/ui/tabs.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/ui/tabs.tsx"
"use client"

import * as React from "react"
import { cva, type VariantProps } from "class-variance-authority"
import { Tabs as TabsPrimitive } from "radix-ui"

import { cn } from "@/lib/utils"

function Tabs({
  className,
  orientation = "horizontal",
  ...props
}: React.ComponentProps<typeof TabsPrimitive.Root>) {
  return (
    <TabsPrimitive.Root
      data-slot="tabs"
      data-orientation={orientation}
      className={cn(
        "group/tabs flex gap-2 data-horizontal:flex-col",
        className
      )}
      {...props}
    />
  )
}

const tabsListVariants = cva(
  "group/tabs-list inline-flex w-fit items-center justify-center rounded-lg p-[3px] text-muted-foreground group-data-horizontal/tabs:h-8 group-data-vertical/tabs:h-fit group-data-vertical/tabs:flex-col data-[variant=line]:rounded-none",
  {
    variants: {
      variant: {
        default: "bg-muted",
        line: "gap-1 bg-transparent",
      },
    },
    defaultVariants: {
      variant: "default",
    },
  }
)

function TabsList({
  className,
  variant = "default",
  ...props
}: React.ComponentProps<typeof TabsPrimitive.List> &
  VariantProps<typeof tabsListVariants>) {
  return (
    <TabsPrimitive.List
      data-slot="tabs-list"
      data-variant={variant}
      className={cn(tabsListVariants({ variant }), className)}
      {...props}
    />
  )
}

function TabsTrigger({
  className,
  ...props
}: React.ComponentProps<typeof TabsPrimitive.Trigger>) {
  return (
    <TabsPrimitive.Trigger
      data-slot="tabs-trigger"
      className={cn(
        "relative inline-flex h-[calc(100%-1px)] flex-1 items-center justify-center gap-1.5 rounded-md border border-transparent px-1.5 py-0.5 text-sm font-medium whitespace-nowrap text-foreground/60 transition-all group-data-vertical/tabs:w-full group-data-vertical/tabs:justify-start hover:text-foreground focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50 focus-visible:outline-1 focus-visible:outline-ring disabled:pointer-events-none disabled:opacity-50 has-data-[icon=inline-end]:pr-1 has-data-[icon=inline-start]:pl-1 dark:text-muted-foreground dark:hover:text-foreground group-data-[variant=default]/tabs-list:data-active:shadow-sm group-data-[variant=line]/tabs-list:data-active:shadow-none [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4",
        "group-data-[variant=line]/tabs-list:bg-transparent group-data-[variant=line]/tabs-list:data-active:bg-transparent dark:group-data-[variant=line]/tabs-list:data-active:border-transparent dark:group-data-[variant=line]/tabs-list:data-active:bg-transparent",
        "data-active:bg-background data-active:text-foreground dark:data-active:border-input dark:data-active:bg-input/30 dark:data-active:text-foreground",
        "after:absolute after:bg-foreground after:opacity-0 after:transition-opacity group-data-horizontal/tabs:after:inset-x-0 group-data-horizontal/tabs:after:bottom-[-5px] group-data-horizontal/tabs:after:h-0.5 group-data-vertical/tabs:after:inset-y-0 group-data-vertical/tabs:after:-right-1 group-data-vertical/tabs:after:w-0.5 group-data-[variant=line]/tabs-list:data-active:after:opacity-100",
        className
      )}
      {...props}
    />
  )
}

function TabsContent({
  className,
  ...props
}: React.ComponentProps<typeof TabsPrimitive.Content>) {
  return (
    <TabsPrimitive.Content
      data-slot="tabs-content"
      className={cn("flex-1 text-sm outline-none", className)}
      {...props}
    />
  )
}

export { Tabs, TabsList, TabsTrigger, TabsContent, tabsListVariants }

END_OF_FILE_CONTENT
echo "Creating src/components/ui/textarea.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/ui/textarea.tsx"
import * as React from "react"

import { cn } from "@/lib/utils"

function Textarea({ className, ...props }: React.ComponentProps<"textarea">) {
  return (
    <textarea
      data-slot="textarea"
      className={cn(
        "flex field-sizing-content min-h-16 w-full rounded-lg border border-input bg-transparent px-2.5 py-2 text-base transition-colors outline-none placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 disabled:cursor-not-allowed disabled:bg-input/50 disabled:opacity-50 aria-invalid:border-destructive aria-invalid:ring-3 aria-invalid:ring-destructive/20 md:text-sm dark:bg-input/30 dark:disabled:bg-input/80 dark:aria-invalid:border-destructive/50 dark:aria-invalid:ring-destructive/40",
        className
      )}
      {...props}
    />
  )
}

export { Textarea }

END_OF_FILE_CONTENT
echo "Creating src/components/ui/toggle-group.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/ui/toggle-group.tsx"
import * as React from "react"
import { type VariantProps } from "class-variance-authority"
import { ToggleGroup as ToggleGroupPrimitive } from "radix-ui"

import { cn } from "@/lib/utils"
import { toggleVariants } from "@/components/ui/toggle"

const ToggleGroupContext = React.createContext<
  VariantProps<typeof toggleVariants> & {
    spacing?: number
    orientation?: "horizontal" | "vertical"
  }
>({
  size: "default",
  variant: "default",
  spacing: 0,
  orientation: "horizontal",
})

function ToggleGroup({
  className,
  variant,
  size,
  spacing = 0,
  orientation = "horizontal",
  children,
  ...props
}: React.ComponentProps<typeof ToggleGroupPrimitive.Root> &
  VariantProps<typeof toggleVariants> & {
    spacing?: number
    orientation?: "horizontal" | "vertical"
  }) {
  return (
    <ToggleGroupPrimitive.Root
      data-slot="toggle-group"
      data-variant={variant}
      data-size={size}
      data-spacing={spacing}
      data-orientation={orientation}
      style={{ "--gap": spacing } as React.CSSProperties}
      className={cn(
        "group/toggle-group flex w-fit flex-row items-center gap-[--spacing(var(--gap))] rounded-lg data-[size=sm]:rounded-[min(var(--radius-md),10px)] data-vertical:flex-col data-vertical:items-stretch",
        className
      )}
      {...props}
    >
      <ToggleGroupContext.Provider
        value={{ variant, size, spacing, orientation }}
      >
        {children}
      </ToggleGroupContext.Provider>
    </ToggleGroupPrimitive.Root>
  )
}

function ToggleGroupItem({
  className,
  children,
  variant = "default",
  size = "default",
  ...props
}: React.ComponentProps<typeof ToggleGroupPrimitive.Item> &
  VariantProps<typeof toggleVariants>) {
  const context = React.useContext(ToggleGroupContext)

  return (
    <ToggleGroupPrimitive.Item
      data-slot="toggle-group-item"
      data-variant={context.variant || variant}
      data-size={context.size || size}
      data-spacing={context.spacing}
      className={cn(
        "shrink-0 group-data-[spacing=0]/toggle-group:rounded-none group-data-[spacing=0]/toggle-group:px-2 focus:z-10 focus-visible:z-10 group-data-[spacing=0]/toggle-group:has-data-[icon=inline-end]:pr-1.5 group-data-[spacing=0]/toggle-group:has-data-[icon=inline-start]:pl-1.5 group-data-horizontal/toggle-group:data-[spacing=0]:first:rounded-l-lg group-data-vertical/toggle-group:data-[spacing=0]:first:rounded-t-lg group-data-horizontal/toggle-group:data-[spacing=0]:last:rounded-r-lg group-data-vertical/toggle-group:data-[spacing=0]:last:rounded-b-lg group-data-horizontal/toggle-group:data-[spacing=0]:data-[variant=outline]:border-l-0 group-data-vertical/toggle-group:data-[spacing=0]:data-[variant=outline]:border-t-0 group-data-horizontal/toggle-group:data-[spacing=0]:data-[variant=outline]:first:border-l group-data-vertical/toggle-group:data-[spacing=0]:data-[variant=outline]:first:border-t",
        toggleVariants({
          variant: context.variant || variant,
          size: context.size || size,
        }),
        className
      )}
      {...props}
    >
      {children}
    </ToggleGroupPrimitive.Item>
  )
}

export { ToggleGroup, ToggleGroupItem }

END_OF_FILE_CONTENT
echo "Creating src/components/ui/toggle.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/ui/toggle.tsx"
"use client"

import * as React from "react"
import { cva, type VariantProps } from "class-variance-authority"
import { Toggle as TogglePrimitive } from "radix-ui"

import { cn } from "@/lib/utils"

const toggleVariants = cva(
  "group/toggle inline-flex items-center justify-center gap-1 rounded-lg text-sm font-medium whitespace-nowrap transition-all outline-none hover:bg-muted hover:text-foreground focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50 disabled:pointer-events-none disabled:opacity-50 aria-invalid:border-destructive aria-invalid:ring-destructive/20 aria-pressed:bg-muted data-[state=on]:bg-muted dark:aria-invalid:ring-destructive/40 [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4",
  {
    variants: {
      variant: {
        default: "bg-transparent",
        outline: "border border-input bg-transparent hover:bg-muted",
      },
      size: {
        default:
          "h-8 min-w-8 px-2.5 has-data-[icon=inline-end]:pr-2 has-data-[icon=inline-start]:pl-2",
        sm: "h-7 min-w-7 rounded-[min(var(--radius-md),12px)] px-2.5 text-[0.8rem] has-data-[icon=inline-end]:pr-1.5 has-data-[icon=inline-start]:pl-1.5 [&_svg:not([class*='size-'])]:size-3.5",
        lg: "h-9 min-w-9 px-2.5 has-data-[icon=inline-end]:pr-2 has-data-[icon=inline-start]:pl-2",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  }
)

function Toggle({
  className,
  variant = "default",
  size = "default",
  ...props
}: React.ComponentProps<typeof TogglePrimitive.Root> &
  VariantProps<typeof toggleVariants>) {
  return (
    <TogglePrimitive.Root
      data-slot="toggle"
      className={cn(toggleVariants({ variant, size, className }))}
      {...props}
    />
  )
}

export { Toggle, toggleVariants }

END_OF_FILE_CONTENT
echo "Creating src/components/ui/tooltip.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/ui/tooltip.tsx"
"use client"

import * as React from "react"
import { Tooltip as TooltipPrimitive } from "radix-ui"

import { cn } from "@/lib/utils"

function TooltipProvider({
  delayDuration = 0,
  ...props
}: React.ComponentProps<typeof TooltipPrimitive.Provider>) {
  return (
    <TooltipPrimitive.Provider
      data-slot="tooltip-provider"
      delayDuration={delayDuration}
      {...props}
    />
  )
}

function Tooltip({
  ...props
}: React.ComponentProps<typeof TooltipPrimitive.Root>) {
  return <TooltipPrimitive.Root data-slot="tooltip" {...props} />
}

function TooltipTrigger({
  ...props
}: React.ComponentProps<typeof TooltipPrimitive.Trigger>) {
  return <TooltipPrimitive.Trigger data-slot="tooltip-trigger" {...props} />
}

function TooltipContent({
  className,
  sideOffset = 0,
  children,
  ...props
}: React.ComponentProps<typeof TooltipPrimitive.Content>) {
  return (
    <TooltipPrimitive.Portal>
      <TooltipPrimitive.Content
        data-slot="tooltip-content"
        sideOffset={sideOffset}
        className={cn(
          "z-50 inline-flex w-fit max-w-xs origin-(--radix-tooltip-content-transform-origin) items-center gap-1.5 rounded-md bg-foreground px-3 py-1.5 text-xs text-background has-data-[slot=kbd]:pr-1.5 data-[side=bottom]:slide-in-from-top-2 data-[side=left]:slide-in-from-right-2 data-[side=right]:slide-in-from-left-2 data-[side=top]:slide-in-from-bottom-2 **:data-[slot=kbd]:relative **:data-[slot=kbd]:isolate **:data-[slot=kbd]:z-50 **:data-[slot=kbd]:rounded-sm data-[state=delayed-open]:animate-in data-[state=delayed-open]:fade-in-0 data-[state=delayed-open]:zoom-in-95 data-open:animate-in data-open:fade-in-0 data-open:zoom-in-95 data-closed:animate-out data-closed:fade-out-0 data-closed:zoom-out-95",
          className
        )}
        {...props}
      >
        {children}
        <TooltipPrimitive.Arrow className="z-50 size-2.5 translate-y-[calc(-50%_-_2px)] rotate-45 rounded-[2px] bg-foreground fill-foreground" />
      </TooltipPrimitive.Content>
    </TooltipPrimitive.Portal>
  )
}

export { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger }

END_OF_FILE_CONTENT
mkdir -p "src/components/wine-cellar"
echo "Creating src/components/wine-cellar/View.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/components/wine-cellar/View.tsx"
// Layout: Hero=A (SPLIT 60/40), Features=B (HORIZONTAL SCROLL)
import React from 'react';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { ScrollArea } from '@/components/ui/scroll-area';
import type { WineCellarData, WineCellarSettings } from './types';

export const WineCellar: React.FC<{ data: WineCellarData; settings: WineCellarSettings }> = ({ data }) => {
  const wineTypeColors = {
    red: 'text-red-400 bg-red-400/10 border-red-400/20',
    white: 'text-yellow-400 bg-yellow-400/10 border-yellow-400/20',
    sparkling: 'text-blue-400 bg-blue-400/10 border-blue-400/20',
    dessert: 'text-purple-400 bg-purple-400/10 border-purple-400/20',
  };

  return (
    <section
      style={{
        '--local-bg': 'var(--background)',
        '--local-text': 'var(--foreground)',
        '--local-text-muted': 'var(--muted-foreground)',
        '--local-accent': 'var(--accent)',
        '--local-surface': 'var(--card)',
        '--local-border': 'var(--border)',
        '--local-primary': 'var(--primary)',
        '--local-radius-lg': 'var(--theme-radius-lg)',
      } as React.CSSProperties}
      className="relative z-0 py-28 bg-[var(--local-bg)]"
    >
      <div className="max-w-[1200px] mx-auto px-8">
        {data.label && (
          <div className="jp-section-label inline-flex items-center gap-2 text-[0.72rem] font-bold uppercase tracking-[0.12em] text-[var(--local-accent)] mb-4" data-jp-field="label">
            <span className="w-5 h-px bg-[var(--local-primary)]" />
            {data.label}
          </div>
        )}
        
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-16 items-center mb-16">
          <div>
            <h2 className="font-display font-black text-[clamp(2rem,4.5vw,3.8rem)] leading-[1.05] tracking-tight text-[var(--local-text)] mb-6" data-jp-field="title">
              {data.title}
            </h2>
            
            {data.description && (
              <p className="text-[var(--local-text-muted)] text-lg leading-relaxed" data-jp-field="description">
                {data.description}
              </p>
            )}
          </div>
          
          {data.image?.url && (
            <div className="relative">
              <img 
                src={data.image.url}
                alt={data.image.alt}
                className="w-full h-[400px] object-cover rounded-[var(--local-radius-lg)]"
              />
            </div>
          )}
        </div>
        
        {/* Horizontal Scroll Wine List */}
        <ScrollArea className="w-full whitespace-nowrap">
          <div className="flex gap-6 pb-4">
            {data.wines.map((wine, idx) => (
              <Card
                key={wine.id || `wine-${idx}`}
                className="flex-shrink-0 w-[300px] bg-[var(--local-surface)] border border-[var(--local-border)] rounded-[var(--local-radius-lg)] hover:shadow-lg transition-shadow duration-300"
                data-jp-item-id={wine.id || `wine-${idx}`}
                data-jp-item-field="wines"
              >
                <CardContent className="p-6 whitespace-normal">
                  <div className="flex items-start justify-between mb-3">
                    <h3 className="font-display font-bold text-lg text-[var(--local-text)]">
                      {wine.name}
                    </h3>
                    {wine.type && (
                      <Badge className={`text-xs ${wineTypeColors[wine.type] || 'text-[var(--local-accent)] bg-[var(--local-accent)]/10 border-[var(--local-accent)]/20'}`}>
                        {wine.type}
                      </Badge>
                    )}
                  </div>
                  
                  <div className="flex items-center gap-2 text-sm text-[var(--local-text-muted)] mb-3">
                    {wine.vintage && <span className="font-mono">{wine.vintage}</span>}
                    {wine.vintage && wine.region && <span>•</span>}
                    {wine.region && <span>{wine.region}</span>}
                  </div>
                  
                  <p className="text-[var(--local-text-muted)] text-sm leading-relaxed">
                    {wine.description}
                  </p>
                </CardContent>
              </Card>
            ))}
          </div>
        </ScrollArea>
      </div>
    </section>
  );
};

END_OF_FILE_CONTENT
echo "Creating src/components/wine-cellar/index.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/wine-cellar/index.ts"
export { WineCellar } from './View';
export { WineCellarSchema } from './schema';
export type { WineCellarData, WineCellarSettings } from './types';

END_OF_FILE_CONTENT
echo "Creating src/components/wine-cellar/schema.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/wine-cellar/schema.ts"
import { z } from 'zod';
import { BaseSectionData, BaseArrayItem, ImageSelectionSchema } from '@olonjs/core';

const WineItemSchema = BaseArrayItem.extend({
  name: z.string().describe('ui:text'),
  vintage: z.string().optional().describe('ui:text'),
  region: z.string().optional().describe('ui:text'),
  description: z.string().describe('ui:textarea'),
  type: z.enum(['red', 'white', 'sparkling', 'dessert']).optional().describe('ui:select'),
});

export const WineCellarSchema = BaseSectionData.extend({
  label: z.string().optional().describe('ui:text'),
  title: z.string().describe('ui:text'),
  description: z.string().optional().describe('ui:textarea'),
  image: ImageSelectionSchema.optional(),
  wines: z.array(WineItemSchema).describe('ui:list'),
});

END_OF_FILE_CONTENT
echo "Creating src/components/wine-cellar/types.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/components/wine-cellar/types.ts"
import { z } from 'zod';
import { BaseSectionSettingsSchema } from '@olonjs/core';
import { WineCellarSchema } from './schema';

export type WineCellarData = z.infer<typeof WineCellarSchema>;
export type WineCellarSettings = z.infer<typeof BaseSectionSettingsSchema>;

END_OF_FILE_CONTENT
mkdir -p "src/data"
mkdir -p "src/data/config"
echo "Creating src/data/config/menu.json..."
cat << 'END_OF_FILE_CONTENT' > "src/data/config/menu.json"
{
  "main": [
    { "label": "Home", "href": "/" },
    { "label": "Accommodations", "href": "/accommodations" },
    { "label": "Wellness & Spa", "href": "/wellness" },
    { "label": "Culinary", "href": "/culinary" },
    { "label": "Experiences", "href": "/experiences" }
  ],
  "footer": [
    { "label": "About", "href": "/about" },
    { "label": "Privacy Policy", "href": "/privacy" },
    { "label": "Terms of Service", "href": "/terms" },
    { "label": "Contact", "href": "/contact" }
  ]
}

END_OF_FILE_CONTENT
echo "Creating src/data/config/menu_example_for_schema.json..."
cat << 'END_OF_FILE_CONTENT' > "src/data/config/menu_example_for_schema.json"
{
  "main": [
    { 
      "label": "Why",
      "href": "/why",
      "children": [
        {
          "label": "Overview",
          "href": "/platform/overview"
        },
        {
          "label": "Architecture",
          "href": "/platform/architecture"
        },
        {
          "label": "Security",
          "href": "/platform/security"
        },
        {
          "label": "Integrations",
          "href": "/platform/integrations"
        },
        {
          "label": "Roadmap",
          "href": "/platform/roadmap"
        }
      ]
    },
    {
      "label": "Solutions",
      "href": "/solutions"
    },
    {
      "label": "Pricing",
      "href": "/pricing"
    },
    {
      "label": "Resources",
      "href": "/resources"
    }
  ]
}
END_OF_FILE_CONTENT
echo "Creating src/data/config/site.json..."
cat << 'END_OF_FILE_CONTENT' > "src/data/config/site.json"
{
  "header": {
    "id": "global-header",
    "type": "header",
    "data": {
      "logoText": "Lumina Alpine Retreat",
      "logoHighlight": "",
      "announcement": "Winter Season 2024: Book Early & Save 20%",
      "menu": { "$ref": "../config/menu.json#/main" }
    },
    "settings": { "sticky": true }
  },
  "footer": {
    "id": "global-footer",
    "type": "footer",
    "data": {
      "brandText": "Lumina Alpine Retreat",
      "brandHighlight": "Est. 2018",
      "tagline": "Where luxury meets nature in the heart of the Dolomites.",
      "address": "Via Alta Quota 47\n39046 Ortisei, South Tyrol\nItaly",
      "phone": "+39 0471 123 456",
      "email": "concierge@luminaalpine.com",
      "copyright": "© 2024 Lumina Alpine Retreat. All rights reserved.",
      "menu": { "$ref": "../config/menu.json#/footer" }
    },
    "settings": { "showLogo": true }
  },
  "identity": { "title": "Lumina Alpine Retreat - Luxury Eco-Resort in the Dolomites" },
  "pages": []
}

END_OF_FILE_CONTENT
echo "Creating src/data/config/theme.json..."
cat << 'END_OF_FILE_CONTENT' > "src/data/config/theme.json"
{
  "name": "Lumina Alpine Retreat - Airy Edition",
  "version": "1.0.0",
  "tokens": {
    "colors": {
      "background": "#192620",
      "foreground": "#F4F7F5",
      "card": "#22332B",
      "card-foreground": "#F4F7F5",
      "elevated": "#2A3D34",
      "overlay": "#101A15",
      "popover": "#22332B",
      "popover-foreground": "#F4F7F5",
      "muted": "#2F453A",
      "muted-foreground": "#92B2A1",
      "placeholder": "#769E89",
      "primary": "#769E89",
      "primary-foreground": "#192620",
      "primary-light": "#92B2A1",
      "primary-dark": "#5C826F",
      "primary-50": "#F4F7F5",
      "primary-100": "#E4ECE7",
      "primary-200": "#C9D9D0",
      "primary-300": "#ADC5B8",
      "primary-400": "#92B2A1",
      "primary-500": "#769E89",
      "primary-600": "#5C826F",
      "primary-700": "#466354",
      "primary-800": "#2F453A",
      "primary-900": "#192620",
      "accent": "#D9B382",
      "accent-foreground": "#192620",
      "secondary": "#2F453A",
      "secondary-foreground": "#F4F7F5",
      "border": "#2F453A",
      "border-strong": "#466354",
      "input": "#2F453A",
      "ring": "#769E89",
      "destructive": "#E06C6C",
      "destructive-foreground": "#FFFFFF",
      "destructive-border": "#8F3A3A",
      "destructive-ring": "#E06C6C",
      "success": "#6DBA82",
      "success-foreground": "#192620",
      "success-border": "#3A7A4D",
      "success-indicator": "#6DBA82",
      "warning": "#E0B86C",
      "warning-foreground": "#192620",
      "warning-border": "#8F703A",
      "info": "#6C9CE0",
      "info-foreground": "#192620",
      "info-border": "#3A5C8F"
    },
    "modes": {
      "light": {
        "colors": {
          "background": "#FAFCFB",
          "foreground": "#192620",
          "card": "#FFFFFF",
          "card-foreground": "#192620",
          "elevated": "#F4F7F5",
          "overlay": "#E4ECE7",
          "popover": "#FFFFFF",
          "popover-foreground": "#192620",
          "muted": "#E4ECE7",
          "muted-foreground": "#5C826F",
          "placeholder": "#92B2A1",
          "primary": "#466354",
          "primary-foreground": "#FFFFFF",
          "primary-light": "#5C826F",
          "primary-dark": "#2F453A",
          "accent": "#C29B62",
          "accent-foreground": "#FFFFFF",
          "secondary": "#E4ECE7",
          "secondary-foreground": "#192620",
          "border": "#C9D9D0",
          "border-strong": "#ADC5B8",
          "input": "#C9D9D0",
          "ring": "#466354",
          "destructive": "#DC2626",
          "destructive-foreground": "#FFFFFF",
          "destructive-border": "#F87171",
          "destructive-ring": "#EF4444",
          "success": "#16A34A",
          "success-foreground": "#FFFFFF",
          "success-border": "#86EFAC",
          "success-indicator": "#22C55E",
          "warning": "#D97706",
          "warning-foreground": "#FFFFFF",
          "warning-border": "#FCD34D",
          "info": "#2563EB",
          "info-foreground": "#FFFFFF",
          "info-border": "#93C5FD"
        }
      }
    },
    "typography": {
      "fontFamily": {
        "primary": "\"Source Serif 4\", Helvetica, Arial, sans-serif",
        "mono": "\"IBM Plex Mono\", Helvetica, Arial, sans-serif",
        "display": "\"Cormorant Garamond\", Helvetica, Arial, sans-serif"
      },
      "wordmark": {
        "fontFamily": "\"Cormorant Garamond\", Helvetica, Arial, sans-serif",
        "weight": "600"
      },
      "scale": {
        "xs": "0.75rem",
        "sm": "0.875rem",
        "base": "1rem",
        "lg": "1.125rem",
        "xl": "1.25rem",
        "2xl": "1.5rem",
        "3xl": "1.875rem",
        "4xl": "2.25rem",
        "5xl": "3rem"
      },
      "tracking": {
        "tight": "-0.02em",
        "normal": "0em",
        "wide": "0.04em",
        "widest": "0.14em"
      },
      "leading": {
        "tight": "1.2",
        "normal": "1.5",
        "relaxed": "1.7"
      }
    },
    "borderRadius": {
      "sm": "0.25rem",
      "md": "0.5rem",
      "lg": "0.75rem",
      "xl": "1.25rem",
      "full": "9999px"
    },
    "spacing": {
      "container-max": "80rem",
      "section-y": "6rem",
      "header-h": "5rem"
    },
    "zIndex": {
      "base": "0",
      "elevated": "10",
      "dropdown": "20",
      "sticky": "40",
      "overlay": "50",
      "modal": "60",
      "toast": "100"
    }
  }
}

END_OF_FILE_CONTENT
mkdir -p "src/data/pages"
echo "Creating src/data/pages/accommodations.json..."
cat << 'END_OF_FILE_CONTENT' > "src/data/pages/accommodations.json"
{
  "id": "accommodations-page",
  "slug": "accommodations",
  "meta": {
    "title": "Luxury Accommodations - Lumina Alpine Retreat",
    "description": "Discover our collection of luxury suites featuring panoramic Dolomites views, premium amenities, and sustainable design in the heart of the Italian Alps."
  },
  "sections": [
    {
      "id": "accommodations-hero",
      "type": "page-hero",
      "data": {
        "title": "Luxury Alpine Suites",
        "description": "Each accommodation is thoughtfully designed to maximize your connection with the surrounding Dolomites landscape while providing the utmost in luxury and comfort.",
        "breadcrumbs": [
          { "id": "breadcrumb-home", "label": "Home", "href": "/" },
          { "id": "breadcrumb-accommodations", "label": "Accommodations", "href": "/accommodations" }
        ]
      },
      "settings": {}
    },
    {
      "id": "accommodations-showcase",
      "type": "accommodation-showcase",
      "data": {
        "label": "Premium Suites",
        "title": "Elevated Alpine Living",
        "accommodations": [
          {
            "id": "suite-panorama-loft",
            "title": "Alpine Panorama Loft",
            "subtitle": "Corner Suite • 85 sqm",
            "description": "Our signature corner suite offers 270-degree views of the Dolomites through floor-to-ceiling windows. Features include a private balcony with hot tub, wood-burning fireplace, and handcrafted furniture by local artisans.",
            "image": {
              "url": "https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?w=800&q=90",
              "alt": "Luxurious corner suite with panoramic mountain views, modern alpine decor, and floor-to-ceiling windows"
            },
            "features": [
              "270-degree mountain views",
              "Private balcony with hot tub",
              "Wood-burning fireplace",
              "Marble bathroom with rain shower",
              "Artisan-crafted furniture",
              "Complimentary spa access"
            ],
            "cta": { "id": "panorama-cta", "label": "Book Panorama Loft", "href": "/book?suite=panorama", "variant": "primary" }
          },
          {
            "id": "suite-forest-villa",
            "title": "Forest Villa Suite",
            "subtitle": "Ground Floor • 110 sqm",
            "description": "Immerse yourself in nature with direct forest access from your private terrace. This spacious ground-floor suite features natural materials, a standalone copper tub, and seamless indoor-outdoor living.",
            "image": {
              "url": "https://images.unsplash.com/photo-1584132967334-10e028bd69f7?w=800&q=90",
              "alt": "Ground floor suite with direct forest access, natural wood interiors, and private terrace"
            },
            "features": [
              "Direct forest access",
              "110 sqm living space",
              "Private garden terrace",
              "Copper soaking tub",
              "Natural stone finishes",
              "In-room wellness amenities"
            ],
            "cta": { "id": "forest-cta", "label": "Reserve Forest Villa", "href": "/book?suite=forest", "variant": "primary" }
          },
          {
            "id": "suite-peak-penthouse",
            "title": "Peak Penthouse",
            "subtitle": "Top Floor • 150 sqm",
            "description": "The ultimate alpine retreat featuring a private rooftop deck with 360-degree mountain views, dedicated concierge service, and exclusive access to our helicopter landing pad for scenic flights.",
            "image": {
              "url": "https://images.unsplash.com/photo-1571896349842-33c89424de2d?w=800&q=90",
              "alt": "Luxury penthouse with rooftop deck, panoramic mountain views, and premium alpine furnishings"
            },
            "features": [
              "360-degree rooftop deck",
              "150 sqm penthouse suite",
              "Dedicated concierge service",
              "Private helicopter access",
              "Wine cellar selection",
              "Butler service included"
            ],
            "cta": { "id": "penthouse-cta", "label": "Inquire About Penthouse", "href": "/book?suite=penthouse", "variant": "primary" }
          }
        ]
      },
      "settings": {}
    },
    {
      "id": "accommodations-newsletter",
      "type": "newsletter-cta",
      "data": {
        "title": "Ready to Experience Alpine Luxury?",
        "description": "Contact our reservations team to discuss the perfect suite for your mountain getaway.",
        "placeholder": "Your preferred dates",
        "cta": { "id": "booking-cta", "label": "Check Availability", "href": "/book", "variant": "primary" }
      },
      "settings": {}
    }
  ]
}

END_OF_FILE_CONTENT
echo "Creating src/data/pages/culinary.json..."
cat << 'END_OF_FILE_CONTENT' > "src/data/pages/culinary.json"
{
  "id": "culinary-page",
  "slug": "culinary",
  "meta": {
    "title": "Culinary Excellence - Lumina Alpine Retreat",
    "description": "Savor exceptional Michelin-starred cuisine featuring locally-sourced Alpine ingredients, artisanal preparations, and an award-winning wine cellar."
  },
  "sections": [
    {
      "id": "culinary-hero",
      "type": "page-hero",
      "data": {
        "title": "Culinary Excellence",
        "description": "Our Michelin-starred kitchen celebrates the rich culinary heritage of the Alps through innovative techniques and the finest local ingredients.",
        "breadcrumbs": [
          { "id": "breadcrumb-home", "label": "Home", "href": "/" },
          { "id": "breadcrumb-culinary", "label": "Culinary", "href": "/culinary" }
        ]
      },
      "settings": {}
    },
    {
      "id": "culinary-showcase",
      "type": "culinary-showcase",
      "data": {
        "label": "Dining Experiences",
        "title": "Alpine Gastronomy Redefined",
        "description": "Executive Chef Marco Steinbacher brings two Michelin stars to our mountain retreat, crafting menus that honor local traditions while pushing culinary boundaries.",
        "items": [
          {
            "id": "restaurant-alta",
            "title": "Alta Restaurant",
            "description": "Our flagship fine-dining restaurant offers a seven-course tasting menu that changes with the seasons. Each dish tells a story of the Dolomites through flavors, textures, and presentations inspired by the mountain landscape.",
            "badge": "2 Michelin Stars",
            "image": {
              "url": "https://images.unsplash.com/photo-1414235077428-338989a2e8c0?w=600&q=85",
              "alt": "Elegant fine dining restaurant with mountain view windows and artisanal place settings"
            }
          },
          {
            "id": "lounge-summit",
            "title": "Summit Lounge",
            "description": "Casual dining with panoramic views featuring locally-inspired small plates, artisanal cheeses, and craft cocktails made with Alpine botanicals. Perfect for après-ski or sunset dining.",
            "badge": "Rooftop Dining",
            "image": {
              "url": "https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=600&q=85",
              "alt": "Rooftop lounge with comfortable seating, mountain views, and artisanal cocktail service"
            }
          },
          {
            "id": "wine-cellar",
            "title": "Private Wine Cellar",
            "description": "Over 800 carefully selected wines from Alpine regions and renowned international vineyards. Enjoy private tastings with our sommelier in our temperature-controlled cellar carved into the mountain.",
            "badge": "800+ Wines",
            "image": {
              "url": "https://images.unsplash.com/photo-1510812431401-41d2bd2722f3?w=600&q=85",
              "alt": "Elegant wine cellar with stone walls, professional lighting, and extensive wine collection"
            }
          }
        ]
      },
      "settings": {}
    },
    {
      "id": "wine-cellar-detail",
      "type": "wine-cellar",
      "data": {
        "label": "Wine Collection",
        "title": "Curated Alpine Wines",
        "description": "Discover exceptional wines from the unique terroir of Alpine regions, personally selected by our head sommelier from small family producers.",
        "image": {
          "url": "https://images.unsplash.com/photo-1506377247377-2a5b3b417ebb?w=600&q=85",
          "alt": "Sommelier carefully selecting wine bottles in professional cellar environment"
        },
        "wines": [
          {
            "id": "wine-gewurztraminer",
            "name": "Gewürztraminer Gran Cuvée",
            "vintage": "2019",
            "region": "Alto Adige",
            "type": "white",
            "description": "Aromatic and complex white wine with notes of rose petals, lychee, and spice. Perfect pairing with our Alpine cheese selection."
          },
          {
            "id": "wine-lagrein",
            "name": "Lagrein Riserva",
            "vintage": "2017",
            "region": "South Tyrol",
            "type": "red",
            "description": "Full-bodied indigenous red with dark fruit flavors and hints of chocolate. Ideal companion to our house-cured speck and game dishes."
          },
          {
            "id": "wine-franciacorta",
            "name": "Franciacorta Brut",
            "vintage": "2018",
            "region": "Lombardy",
            "type": "sparkling",
            "description": "Elegant Italian sparkling wine with fine perlage and crisp minerality. Our sommelier's choice for celebrations and aperitifs."
          },
          {
            "id": "wine-dessert",
            "name": "Moscato Rosa Passito",
            "vintage": "2016",
            "region": "Trentino",
            "type": "dessert",
            "description": "Rare dessert wine with intense floral aromatics and honeyed sweetness. The perfect conclusion to our tasting menu."
          }
        ]
      },
      "settings": {}
    }
  ]
}

END_OF_FILE_CONTENT
echo "Creating src/data/pages/experiences.json..."
cat << 'END_OF_FILE_CONTENT' > "src/data/pages/experiences.json"
{
  "id": "experiences-page",
  "slug": "experiences",
  "meta": {
    "title": "Alpine Experiences - Lumina Alpine Retreat",
    "description": "Discover curated outdoor adventures in the Dolomites: world-class skiing, guided hiking, helicopter tours, and exclusive mountain experiences."
  },
  "sections": [
    {
      "id": "experiences-hero",
      "type": "page-hero",
      "data": {
        "title": "Alpine Adventures",
        "description": "Explore the breathtaking Dolomites through carefully curated experiences designed to showcase the natural beauty and cultural richness of this UNESCO World Heritage region.",
        "breadcrumbs": [
          { "id": "breadcrumb-home", "label": "Home", "href": "/" },
          { "id": "breadcrumb-experiences", "label": "Experiences", "href": "/experiences" }
        ]
      },
      "settings": {}
    },
    {
      "id": "experience-timeline",
      "type": "experience-timeline",
      "data": {
        "label": "Seasonal Adventures",
        "title": "Year-Round Alpine Experiences",
        "description": "From world-class skiing in winter to high-altitude hiking in summer, discover the Dolomites through immersive adventures tailored to every season.",
        "experiences": [
          {
            "id": "exp-skiing",
            "title": "Elite Ski Experience",
            "season": "Winter",
            "difficulty": "Moderate",
            "duration": "Full Day",
            "description": "Enjoy exclusive access to pristine slopes with our private ski guide. Experience includes equipment rental, lift tickets, and lunch at a mountain hut with panoramic views. Perfect for intermediate to advanced skiers looking to explore hidden corners of the Dolomiti Superski area.",
            "image": {
              "url": "https://images.unsplash.com/photo-1551524164-6ca4ac833fb5?w=600&q=85",
              "alt": "Skiers carving through fresh powder snow with dramatic Dolomites peaks towering in background"
            },
            "cta": { "id": "ski-cta", "label": "Book Ski Guide", "href": "/book-experience?type=skiing", "variant": "secondary" }
          },
          {
            "id": "exp-helicopter",
            "title": "Helicopter Mountain Tour",
            "season": "All Year",
            "difficulty": "Easy",
            "duration": "2 Hours",
            "description": "Soar above the dramatic peaks and valleys of the Dolomites in our private helicopter. This exclusive aerial tour offers unparalleled photo opportunities and access to remote mountain landing sites for champagne service at 3,000 meters altitude.",
            "image": {
              "url": "https://images.unsplash.com/photo-1540979388789-6cee28a1cdc9?w=600&q=85",
              "alt": "Luxury helicopter flying past dramatic Dolomites peaks with passengers enjoying panoramic mountain views"
            },
            "cta": { "id": "heli-cta", "label": "Reserve Flight", "href": "/book-experience?type=helicopter", "variant": "secondary" }
          },
          {
            "id": "exp-hiking",
            "title": "Via Ferrata Adventure",
            "season": "Summer",
            "difficulty": "Challenging",
            "duration": "6 Hours",
            "description": "Tackle the famous iron routes of the Dolomites with professional mountain guides. This thrilling climbing experience combines hiking, rock climbing, and breathtaking exposure on historic WWI routes with modern safety equipment.",
            "image": {
              "url": "https://images.unsplash.com/photo-1551632811-561732d1e306?w=600&q=85",
              "alt": "Climbers on via ferrata route with safety cables against vertical Dolomites rock face"
            },
            "cta": { "id": "ferrata-cta", "label": "Join Adventure", "href": "/book-experience?type=ferrata", "variant": "secondary" }
          },
          {
            "id": "exp-wellness",
            "title": "Forest Bathing & Meditation",
            "season": "Spring/Summer",
            "difficulty": "Easy",
            "duration": "3 Hours",
            "description": "Reconnect with nature through the Japanese practice of Shinrin-yoku adapted for Alpine forests. Led by certified forest therapy guides, this mindful experience includes meditation, breathing exercises, and sensory awareness practices among ancient larch and pine groves.",
            "image": {
              "url": "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=600&q=85",
              "alt": "Peaceful forest meditation scene with dappled sunlight filtering through alpine trees"
            },
            "cta": { "id": "forest-cta", "label": "Book Session", "href": "/book-experience?type=forest", "variant": "secondary" }
          }
        ]
      },
      "settings": {}
    }
  ]
}

END_OF_FILE_CONTENT
echo "Creating src/data/pages/home.json..."
cat << 'END_OF_FILE_CONTENT' > "src/data/pages/home.json"
{
  "id": "home-page",
  "slug": "home",
  "meta": {
    "title": "Lumina Alpine Retreat - Luxury Eco-Resort in the Dolomites",
    "description": "Experience unparalleled luxury in the heart of the Italian Dolomites. Premium eco-resort featuring world-class spa, Michelin-starred dining, and exclusive alpine adventures."
  },
  "sections": [
    {
      "id": "home-hero",
      "type": "alpine-hero",
      "data": {
        "badge": "Luxury Alpine Retreat",
        "title": "Where Mountains",
        "titleHighlight": "Meet Serenity",
        "description": "Discover unparalleled luxury nestled in the heart of the Italian Dolomites. Experience world-class hospitality, pristine alpine beauty, and sustainable luxury that respects the natural environment.",
        "primaryCta": { "id": "hero-primary", "label": "Reserve Your Stay", "href": "/book", "variant": "primary" },
        "secondaryCta": { "id": "hero-secondary", "label": "Explore Resort", "href": "/accommodations", "variant": "secondary" }
      },
      "settings": {}
    },
    {
      "id": "home-highlights",
      "type": "resort-highlights",
      "data": {
        "label": "Resort Features",
        "title": "Alpine Excellence Redefined",
        "highlights": [
          {
            "id": "highlight-spa",
            "title": "World-Class Spa",
            "description": "Rejuvenate your body and soul with our award-winning wellness treatments inspired by Alpine traditions.",
            "category": "Wellness",
            "image": {
              "url": "https://images.unsplash.com/photo-1571019613454-1cb2f99b2d8b?w=800&q=90",
              "alt": "Serene spa treatment room with mountain views and natural stone elements"
            }
          },
          {
            "id": "highlight-skiing",
            "title": "Elite Skiing Access",
            "description": "Direct access to pristine Dolomiti Superski slopes with private ski concierge service.",
            "category": "Adventure",
            "image": {
              "url": "https://images.unsplash.com/photo-1551524164-6ca4ac833fb5?w=800&q=90",
              "alt": "Ski slopes with dramatic Dolomites mountain peaks in golden morning light"
            }
          },
          {
            "id": "highlight-dining",
            "title": "Michelin-Starred Cuisine",
            "description": "Savor exceptional culinary artistry featuring locally-sourced Alpine ingredients.",
            "category": "Culinary",
            "image": {
              "url": "https://images.unsplash.com/photo-1414235077428-338989a2e8c0?w=800&q=90",
              "alt": "Elegant fine dining setup with mountain view backdrop and artisanal presentation"
            }
          },
          {
            "id": "highlight-sustainability",
            "title": "Eco-Luxury Pioneer",
            "description": "Leading sustainable hospitality with carbon-neutral operations and local community partnerships.",
            "category": "Sustainability",
            "image": {
              "url": "https://images.unsplash.com/photo-1518684079-3c830dcef090?w=800&q=90",
              "alt": "Modern eco-friendly architecture integrated harmoniously with alpine forest surroundings"
            }
          }
        ]
      },
      "settings": {}
    },
    {
      "id": "home-stats",
      "type": "stats-band",
      "data": {
        "title": "Alpine Excellence by Numbers",
        "stats": [
          { "id": "stat-1", "number": "94", "suffix": "%", "label": "Guest Satisfaction" },
          { "id": "stat-2", "number": "15", "label": "Luxury Suites" },
          { "id": "stat-3", "number": "2", "label": "Michelin Stars" },
          { "id": "stat-4", "number": "1", "label": "Carbon Neutral" }
        ]
      },
      "settings": {}
    },
    {
      "id": "home-testimonials",
      "type": "testimonials",
      "data": {
        "label": "Guest Reviews",
        "title": "What Our Guests Say",
        "testimonials": [
          {
            "id": "testimonial-1",
            "quote": "Lumina Alpine Retreat exceeded every expectation. The perfect blend of luxury, sustainability, and genuine Alpine hospitality. Our suite overlooked pristine peaks, and every meal was a culinary masterpiece.",
            "author": "Charlotte Dubois",
            "role": "Travel Editor",
            "location": "Paris, France",
            "rating": 5
          },
          {
            "id": "testimonial-2",
            "quote": "The spa treatments here are transformative. The Alpine Stone Ritual combined with the mountain air created the most relaxing experience of my life. I left feeling completely rejuvenated.",
            "author": "Marcus Weber",
            "role": "Executive",
            "location": "Zurich, Switzerland",
            "rating": 5
          },
          {
            "id": "testimonial-3",
            "quote": "As someone passionate about sustainable travel, I was impressed by their genuine commitment to environmental responsibility without compromising on luxury. The perfect eco-conscious getaway.",
            "author": "Isabella Rodriguez",
            "role": "Environmental Consultant",
            "location": "Barcelona, Spain",
            "rating": 5
          }
        ]
      },
      "settings": {}
    },
    {
      "id": "home-newsletter",
      "type": "newsletter-cta",
      "data": {
        "title": "Alpine Insider",
        "description": "Subscribe to receive exclusive seasonal offers, insider updates, and first access to our curated Alpine experiences.",
        "placeholder": "Enter your email address",
        "cta": { "id": "newsletter-cta", "label": "Join the Community", "href": "#", "variant": "primary" }
      },
      "settings": {}
    }
  ]
}

END_OF_FILE_CONTENT
echo "Creating src/data/pages/wellness.json..."
cat << 'END_OF_FILE_CONTENT' > "src/data/pages/wellness.json"
{
  "id": "wellness-page",
  "slug": "wellness",
  "meta": {
    "title": "Wellness & Spa - Lumina Alpine Retreat",
    "description": "Rejuvenate your body and soul with our award-winning spa treatments, thermal pools, and wellness programs inspired by Alpine traditions."
  },
  "sections": [
    {
      "id": "wellness-hero",
      "type": "page-hero",
      "data": {
        "title": "Wellness & Spa Sanctuary",
        "description": "Discover holistic wellness in our world-class spa, where ancient Alpine healing traditions meet modern therapeutic techniques.",
        "breadcrumbs": [
          { "id": "breadcrumb-home", "label": "Home", "href": "/" },
          { "id": "breadcrumb-wellness", "label": "Wellness", "href": "/wellness" }
        ]
      },
      "settings": {}
    },
    {
      "id": "spa-treatments",
      "type": "spa-treatments",
      "data": {
        "label": "Signature Treatments",
        "title": "Alpine Wellness Rituals",
        "description": "Each treatment is designed to harmonize your energy with the natural rhythms of the mountains, using locally-sourced ingredients and time-honored techniques.",
        "treatments": [
          {
            "id": "treatment-alpine-stone",
            "title": "Alpine Stone Ritual",
            "duration": "90 minutes",
            "price": "€280",
            "description": "Our signature treatment combines heated Dolomite stones with aromatic pine and juniper oils. The ritual begins with gentle exfoliation using mineral-rich Alpine salts, followed by a full-body massage that releases deep tension and promotes circulation. Conclude with a restorative meditation overlooking mountain peaks."
          },
          {
            "id": "treatment-thermal-journey",
            "title": "Thermal Circuit Journey",
            "duration": "120 minutes",
            "price": "€180",
            "description": "Experience the therapeutic benefits of our natural thermal pools. This journey includes alternating hot and cold treatments: Finnish sauna with mountain herbs, ice fountain, thermal soaking pools, and concludes in our infinity relaxation pool with mountain views."
          },
          {
            "id": "treatment-mountain-detox",
            "title": "Mountain Detox Wrap",
            "duration": "75 minutes",
            "price": "€220",
            "description": "Purify and energize with this full-body treatment using locally-harvested Alpine botanicals. Clay and mineral wrap removes toxins while organic mountain honey and Swiss herb oils nourish the skin. Includes lymphatic drainage massage and herbal tea ritual."
          },
          {
            "id": "treatment-couples-retreat",
            "title": "Couples Mountain Retreat",
            "duration": "180 minutes",
            "price": "€650",
            "description": "Share a transformative wellness experience in our couples' treatment suite. Includes side-by-side Alpine Stone Rituals, private thermal pool access, champagne and Alpine cheese tasting, and meditation session with mountain view backdrop."
          }
        ]
      },
      "settings": {}
    },
    {
      "id": "wellness-highlights",
      "type": "resort-highlights",
      "data": {
        "label": "Facilities",
        "title": "Complete Wellness Experience",
        "highlights": [
          {
            "id": "facility-thermal",
            "title": "Natural Thermal Pools",
            "description": "Soak in our naturally heated mineral pools with stunning Dolomites backdrop.",
            "category": "Thermal",
            "image": {
              "url": "https://images.unsplash.com/photo-1571019613454-1cb2f99b2d8b?w=600&q=85",
              "alt": "Natural thermal pool surrounded by rocks with steam rising and mountain views in background"
            }
          },
          {
            "id": "facility-yoga",
            "title": "Mountain Yoga Pavilion",
            "description": "Practice yoga and meditation in our glass pavilion suspended over the valley.",
            "category": "Mindfulness",
            "image": {
              "url": "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=600&q=85",
              "alt": "Glass yoga studio with mountain panorama and meditation cushions arranged in peaceful setting"
            }
          },
          {
            "id": "facility-sauna",
            "title": "Finnish Panorama Sauna",
            "description": "Sweat away stress in our glass-walled sauna with 180-degree mountain views.",
            "category": "Thermal",
            "image": {
              "url": "https://images.unsplash.com/photo-1571902943202-507ec2618e8f?w=600&q=85",
              "alt": "Modern glass sauna with panoramic mountain views and wooden benches"
            }
          }
        ]
      },
      "settings": {}
    }
  ]
}

END_OF_FILE_CONTENT
mkdir -p "src/emails"
echo "Creating src/emails/LeadNotificationEmail.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/emails/LeadNotificationEmail.tsx"
import React from "react";
import {
  Body,
  Button,
  Container,
  Head,
  Heading,
  Hr,
  Html,
  Img,
  Preview,
  Section,
  Text,
} from "@react-email/components";

type LeadData = Record<string, unknown>;

type EmailTheme = {
  colors?: {
    primary?: string;
    secondary?: string;
    accent?: string;
    background?: string;
    surface?: string;
    surfaceAlt?: string;
    text?: string;
    textMuted?: string;
    border?: string;
  };
  typography?: {
    fontFamily?: {
      primary?: string;
      display?: string;
      mono?: string;
    };
  };
  borderRadius?: {
    sm?: string;
    md?: string;
    lg?: string;
    xl?: string;
  };
};

export type LeadNotificationEmailProps = {
  tenantName: string;
  correlationId: string;
  replyTo?: string | null;
  leadData: LeadData;
  brandName?: string;
  logoUrl?: string;
  logoAlt?: string;
  tagline?: string;
  theme?: EmailTheme;
};

function safeString(value: unknown): string {
  if (value == null) return "-";
  if (typeof value === "string") {
    const trimmed = value.trim();
    return trimmed || "-";
  }
  return JSON.stringify(value);
}

function flattenLeadData(data: LeadData) {
  return Object.entries(data)
    .filter(([key]) => !key.startsWith("_"))
    .slice(0, 20)
    .map(([key, value]) => ({ label: key, value: safeString(value) }));
}

export function LeadNotificationEmail({
  tenantName,
  correlationId,
  replyTo,
  leadData,
  brandName,
  logoUrl,
  logoAlt,
  tagline,
  theme,
}: LeadNotificationEmailProps) {
  const fields = flattenLeadData(leadData);
  const brandLabel = brandName || tenantName;

  const colors = {
    primary: theme?.colors?.primary || "#2D5016",
    background: theme?.colors?.background || "#FAFAF5",
    surface: theme?.colors?.surface || "#FFFFFF",
    text: theme?.colors?.text || "#1C1C14",
    textMuted: theme?.colors?.textMuted || "#5A5A4A",
    border: theme?.colors?.border || "#D8D5C5",
  };

  const fonts = {
    primary: theme?.typography?.fontFamily?.primary || "Inter, Arial, sans-serif",
    display: theme?.typography?.fontFamily?.display || "Georgia, serif",
  };

  const radius = {
    md: theme?.borderRadius?.md || "10px",
    lg: theme?.borderRadius?.lg || "16px",
  };

  return (
    <Html>
      <Head />
      <Preview>Nuovo lead ricevuto da {brandLabel}</Preview>
      <Body style={{ backgroundColor: colors.background, color: colors.text, fontFamily: fonts.primary, padding: "24px" }}>
        <Container style={{ backgroundColor: colors.surface, border: `1px solid ${colors.border}`, borderRadius: radius.lg, padding: "24px" }}>
          <Section>
            {logoUrl ? <Img src={logoUrl} alt={logoAlt || brandLabel} height="44" style={{ marginBottom: "8px" }} /> : null}
            <Text style={{ color: colors.text, fontSize: "18px", fontWeight: 700, margin: "0 0 6px 0" }}>{brandLabel}</Text>
            <Text style={{ color: colors.textMuted, marginTop: "0", marginBottom: "0" }}>{tagline || "Notifica automatica lead"}</Text>
          </Section>

          <Hr style={{ borderColor: colors.border, margin: "20px 0" }} />

          <Heading as="h2" style={{ color: colors.text, margin: "0 0 12px 0", fontSize: "22px", fontFamily: fonts.display }}>
            Nuovo lead da {tenantName}
          </Heading>
          <Text style={{ color: colors.textMuted, marginTop: "0", marginBottom: "16px" }}>Correlation ID: {correlationId}</Text>

          <Section style={{ border: `1px solid ${colors.border}`, borderRadius: radius.md, padding: "12px" }}>
            {fields.length === 0 ? (
              <Text style={{ color: colors.textMuted, margin: 0 }}>Nessun campo lead disponibile.</Text>
            ) : (
              fields.map((field) => (
                <Text key={field.label} style={{ margin: "0 0 8px 0", color: colors.text, fontSize: "14px", wordBreak: "break-word" }}>
                  <strong>{field.label}:</strong> {field.value}
                </Text>
              ))
            )}
          </Section>

          <Section style={{ marginTop: "18px" }}>
            <Button
              href={replyTo ? `mailto:${replyTo}` : "mailto:"}
              style={{
                backgroundColor: colors.primary,
                color: "#ffffff",
                borderRadius: radius.md,
                textDecoration: "none",
                padding: "12px 18px",
                fontWeight: 600,
              }}
            >
              Rispondi ora
            </Button>
          </Section>
        </Container>
      </Body>
    </Html>
  );
}

export default LeadNotificationEmail;

END_OF_FILE_CONTENT
echo "Creating src/emails/LeadSenderConfirmationEmail.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/emails/LeadSenderConfirmationEmail.tsx"
import React from "react";
import {
  Body,
  Container,
  Head,
  Heading,
  Hr,
  Html,
  Img,
  Preview,
  Section,
  Text,
} from "@react-email/components";

type LeadData = Record<string, unknown>;

type EmailTheme = {
  colors?: {
    primary?: string;
    secondary?: string;
    accent?: string;
    background?: string;
    surface?: string;
    surfaceAlt?: string;
    text?: string;
    textMuted?: string;
    border?: string;
  };
  typography?: {
    fontFamily?: {
      primary?: string;
      display?: string;
      mono?: string;
    };
  };
  borderRadius?: {
    sm?: string;
    md?: string;
    lg?: string;
    xl?: string;
  };
};

export type LeadSenderConfirmationEmailProps = {
  tenantName: string;
  correlationId: string;
  leadData: LeadData;
  brandName?: string;
  logoUrl?: string;
  logoAlt?: string;
  tagline?: string;
  theme?: EmailTheme;
};

function safeString(value: unknown): string {
  if (value == null) return "-";
  if (typeof value === "string") {
    const trimmed = value.trim();
    return trimmed || "-";
  }
  return JSON.stringify(value);
}

function flattenLeadData(data: LeadData) {
  const skipKeys = new Set(["recipientEmail", "tenant", "source", "submittedAt", "email_confirm"]);
  return Object.entries(data)
    .filter(([key]) => !key.startsWith("_") && !skipKeys.has(key))
    .slice(0, 12)
    .map(([key, value]) => ({ label: key, value: safeString(value) }));
}

export function LeadSenderConfirmationEmail({
  tenantName,
  correlationId,
  leadData,
  brandName,
  logoUrl,
  logoAlt,
  tagline,
  theme,
}: LeadSenderConfirmationEmailProps) {
  const fields = flattenLeadData(leadData);
  const brandLabel = brandName || tenantName;

  const colors = {
    primary: theme?.colors?.primary || "#2D5016",
    background: theme?.colors?.background || "#FAFAF5",
    surface: theme?.colors?.surface || "#FFFFFF",
    text: theme?.colors?.text || "#1C1C14",
    textMuted: theme?.colors?.textMuted || "#5A5A4A",
    border: theme?.colors?.border || "#D8D5C5",
  };

  const fonts = {
    primary: theme?.typography?.fontFamily?.primary || "Inter, Arial, sans-serif",
    display: theme?.typography?.fontFamily?.display || "Georgia, serif",
  };

  const radius = {
    md: theme?.borderRadius?.md || "10px",
    lg: theme?.borderRadius?.lg || "16px",
  };

  return (
    <Html>
      <Head />
      <Preview>Conferma invio richiesta - {brandLabel}</Preview>
      <Body style={{ backgroundColor: colors.background, color: colors.background, fontFamily: fonts.primary, padding: "24px" }}>
        <Container style={{ backgroundColor: colors.primary, color: colors.background, border: `1px solid ${colors.border}`, borderRadius: radius.lg, padding: "24px" }}>
          <Section>
            {logoUrl ? <Img src={logoUrl} alt={logoAlt || brandLabel} height="44" style={{ marginBottom: "8px" }} /> : null}
            <Text style={{ color: colors.background, fontSize: "18px", fontWeight: 700, margin: "0 0 6px 0" }}>{brandLabel}</Text>
            <Text style={{ color: colors.background, marginTop: "0", marginBottom: "0" }}>{tagline || "Conferma automatica di ricezione"}</Text>
          </Section>

          <Hr style={{ borderColor: colors.border, margin: "20px 0" }} />

          <Heading as="h2" style={{ color: colors.background, margin: "0 0 12px 0", fontSize: "22px", fontFamily: fonts.display }}>
            Richiesta ricevuta
          </Heading>
          <Text style={{ color: colors.background, marginTop: "0", marginBottom: "16px" }}>
            Grazie, abbiamo ricevuto la tua richiesta per {tenantName}. Ti risponderemo il prima possibile.
          </Text>

          <Section style={{ border: `1px solid ${colors.border}`, borderRadius: radius.md, padding: "12px" }}>
            <Text style={{ margin: "0 0 8px 0", color: colors.background, fontWeight: 600 }}>Riepilogo inviato</Text>
            {fields.length === 0 ? (
              <Text style={{ color: colors.background, margin: 0 }}>Nessun dettaglio disponibile.</Text>
            ) : (
              fields.map((field) => (
                <Text key={field.label} style={{ margin: "0 0 8px 0", color: colors.background, fontSize: "14px", wordBreak: "break-word" }}>
                  <strong>{field.label}:</strong> {field.value}
                </Text>
              ))
            )}
          </Section>

          <Hr style={{ borderColor: colors.border, margin: "20px 0 12px 0" }} />
          <Text style={{ color: colors.background, fontSize: "12px", margin: 0 }}>Riferimento richiesta: {correlationId}</Text>
        </Container>
      </Body>
    </Html>
  );
}

export default LeadSenderConfirmationEmail;

END_OF_FILE_CONTENT
echo "Creating src/entry-ssg.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/entry-ssg.tsx"
import { renderToString } from 'react-dom/server';
import { StaticRouter } from 'react-router-dom/server';
import { ConfigProvider, PageRenderer, StudioProvider, resolveRuntimeConfig } from '@olonjs/core';
import type { JsonPagesConfig, PageConfig, SiteConfig, ThemeConfig } from '@/types';
import { ThemeProvider } from '@/components/ThemeProvider';
import { ComponentRegistry } from '@/lib/ComponentRegistry';
import { SECTION_SCHEMAS } from '@/lib/schemas';
import { menuConfig, pages, refDocuments, siteConfig, themeConfig } from '@/runtime';
import tenantCss from '@/index.css?inline';

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

function isRemoteStylesheetHref(value: string): boolean {
  return /^https?:\/\//i.test(value.trim());
}

function extractLeadingRemoteCssImports(cssText: string): { hrefs: string[]; rest: string } {
  const hrefs = new Set<string>();
  const leadingTriviaPattern = /^(?:\s+|\/\*[\s\S]*?\*\/)*/;
  const importPattern =
    /^@import(?:\s+url\(\s*(?:'([^']+)'|"([^"]+)"|([^'")\s][^)]*))\s*\)|\s*(['"])([^'"]+)\4)\s*([^;]*);/i;
  let rest = cssText;

  for (;;) {
    const trivia = rest.match(leadingTriviaPattern);
    if (trivia && trivia[0]) {
      rest = rest.slice(trivia[0].length);
    }

    const match = rest.match(importPattern);
    if (!match) break;

    const href = (match[1] ?? match[2] ?? match[3] ?? match[5] ?? '').trim();
    const trailingDirectives = (match[6] ?? '').trim();
    if (!isRemoteStylesheetHref(href) || trailingDirectives.length > 0) {
      break;
    }

    hrefs.add(href);
    rest = rest.slice(match[0].length);
  }

  return { hrefs: Array.from(hrefs), rest };
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

export function getCss(): string {
  const themeCss = buildThemeCssFromSot(themeConfig);
  const { rest } = extractLeadingRemoteCssImports(tenantCss);
  if (!themeCss) return rest;
  return `${themeCss}\n${rest}`;
}

export function getRemoteStylesheets(): string[] {
  return extractLeadingRemoteCssImports(tenantCss).hrefs;
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

END_OF_FILE_CONTENT
echo "Creating src/fonts.css..."
cat << 'END_OF_FILE_CONTENT' > "src/fonts.css"
@import url('https://fonts.googleapis.com/css2?family=Instrument+Sans:ital,wght@0,400;0,500;0,600;0,700;1,400&family=JetBrains+Mono:wght@400;500&display=swap');

END_OF_FILE_CONTENT
mkdir -p "src/hooks"
echo "Creating src/hooks/useDocumentMeta.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/hooks/useDocumentMeta.ts"
import { useEffect } from 'react';
import type { PageMeta } from '@/types';

export const useDocumentMeta = (meta: PageMeta): void => {
  useEffect(() => {
    // Set document title
    document.title = meta.title;

    // Set or update meta description
    let metaDescription = document.querySelector('meta[name="description"]');
    if (!metaDescription) {
      metaDescription = document.createElement('meta');
      metaDescription.setAttribute('name', 'description');
      document.head.appendChild(metaDescription);
    }
    metaDescription.setAttribute('content', meta.description);
  }, [meta.title, meta.description]);
};





END_OF_FILE_CONTENT
echo "Creating src/index.css..."
cat << 'END_OF_FILE_CONTENT' > "src/index.css"
@import url('https://fonts.googleapis.com/css2?family=Source+Serif+4:wght@400;500;600;700;800&family=Cormorant+Garamond:wght@400;500;600;700;800&family=IBM+Plex+Mono:wght@400;500;600;700;800&display=swap');

/* Typography contract: import this before any other CSS rules. */

@import "tailwindcss";
@source "./**/*.tsx";

@theme {
  --color-background:           var(--background);
  --color-foreground:           var(--foreground);
  --color-card:                 var(--card);
  --color-card-foreground:      var(--card-foreground);
  --color-primary:              var(--primary);
  --color-primary-foreground:   var(--primary-foreground);
  --color-secondary:            var(--secondary);
  --color-secondary-foreground: var(--secondary-foreground);
  --color-muted:                var(--muted);
  --color-muted-foreground:     var(--muted-foreground);
  --color-accent:               var(--accent);
  --color-border:               var(--border);
  --radius-lg:                  var(--theme-radius-lg);
  --radius-md:                  var(--theme-radius-md);
  --radius-sm:                  var(--theme-radius-sm);
  --font-primary: var(--theme-font-primary);
  --font-mono:    var(--theme-font-mono);
  --font-display: var(--theme-font-display);
}

:root {
  /* -- Layer 1: semantic bridge -----------------------------
     Engine injects: --theme-colors-{name}, --theme-font-*,
     --theme-border-radius-*, --theme-spacing-*, --theme-z-index-*
     The naming below is the tenant's sovereign choice.
  ---------------------------------------------------------- */
  --background:           var(--theme-colors-background);
  --foreground:           var(--theme-colors-foreground);
  --card:                 var(--theme-colors-card);
  --card-foreground:      var(--theme-colors-card-foreground);
  --elevated:             var(--theme-colors-elevated);
  --overlay:              var(--theme-colors-overlay);
  --primary:              var(--theme-colors-primary);
  --primary-foreground:   var(--theme-colors-primary-foreground);
  --primary-light:        var(--theme-colors-primary-light);
  --primary-dark:         var(--theme-colors-primary-dark);
  --secondary:            var(--theme-colors-secondary);
  --secondary-foreground: var(--theme-colors-secondary-foreground);
  --muted:                var(--theme-colors-muted);
  --muted-foreground:     var(--theme-colors-muted-foreground);
  --accent:               var(--theme-colors-accent);
  --accent-foreground:    var(--theme-colors-accent-foreground);
  --border:               var(--theme-colors-border);
  --border-strong:        var(--theme-colors-border-strong);
  --input:                var(--theme-colors-input);
  --ring:                 var(--theme-colors-ring);
  --destructive:          var(--theme-colors-destructive);
  --destructive-foreground: var(--theme-colors-destructive-foreground);
  --success:              var(--theme-colors-success);
  --success-foreground:   var(--theme-colors-success-foreground);
  --warning:              var(--theme-colors-warning);
  --warning-foreground:   var(--theme-colors-warning-foreground);
  --info:                 var(--theme-colors-info);
  --info-foreground:      var(--theme-colors-info-foreground);
  --radius:               var(--theme-radius-lg);

  /* Theme-derived helpers for section-owned demo/mockup surfaces. */
  --demo-surface:         color-mix(in oklch, var(--card) 86%, var(--background));
  --demo-surface-soft:    color-mix(in oklch, var(--card) 72%, var(--background));
  --demo-surface-strong:  color-mix(in oklch, var(--background) 82%, black);
  --demo-surface-deep:    color-mix(in oklch, var(--background) 70%, black);
  --demo-border-soft:     color-mix(in oklch, var(--foreground) 8%, transparent);
  --demo-border-strong:   color-mix(in oklch, var(--primary) 24%, transparent);
  --demo-accent-soft:     color-mix(in oklch, var(--primary) 10%, transparent);
  --demo-accent-strong:   color-mix(in oklch, var(--primary) 18%, transparent);
  --demo-text-soft:       color-mix(in oklch, var(--foreground) 88%, var(--muted-foreground));
  --demo-text-faint:      color-mix(in oklch, var(--muted-foreground) 72%, transparent);
}

/* LIGHT MODE OVERRIDES */
[data-theme="light"] {
  --background:           var(--theme-modes-light-colors-background);
  --foreground:           var(--theme-modes-light-colors-foreground);
  --card:                 var(--theme-modes-light-colors-card);
  --card-foreground:      var(--theme-modes-light-colors-card-foreground);
  --elevated:             var(--theme-modes-light-colors-elevated);
  --overlay:              var(--theme-modes-light-colors-overlay);
  --primary:              var(--theme-modes-light-colors-primary);
  --primary-foreground:   var(--theme-modes-light-colors-primary-foreground);
  --primary-light:        var(--theme-modes-light-colors-primary-light);
  --primary-dark:         var(--theme-modes-light-colors-primary-dark);
  --secondary:            var(--theme-modes-light-colors-secondary);
  --secondary-foreground: var(--theme-modes-light-colors-secondary-foreground);
  --muted:                var(--theme-modes-light-colors-muted);
  --muted-foreground:     var(--theme-modes-light-colors-muted-foreground);
  --accent:               var(--theme-modes-light-colors-accent);
  --accent-foreground:    var(--theme-modes-light-colors-accent-foreground);
  --border:               var(--theme-modes-light-colors-border);
  --border-strong:        var(--theme-modes-light-colors-border-strong);
  --input:                var(--theme-modes-light-colors-input);
  --ring:                 var(--theme-modes-light-colors-ring);
  --destructive:          var(--theme-modes-light-colors-destructive);
  --destructive-foreground: var(--theme-modes-light-colors-destructive-foreground);
  --success:              var(--theme-modes-light-colors-success);
  --success-foreground:   var(--theme-modes-light-colors-success-foreground);
  --warning:              var(--theme-modes-light-colors-warning);
  --warning-foreground:   var(--theme-modes-light-colors-warning-foreground);
  --info:                 var(--theme-modes-light-colors-info);
  --info-foreground:      var(--theme-modes-light-colors-info-foreground);
}

@layer base {
  * { border-color: var(--border); }
  body {
    background-color: var(--background);
    color: var(--foreground);
    font-family: var(--font-primary);
    line-height: 1.7;
    overflow-x: hidden;
    @apply antialiased;
  }
}

.font-display {
  font-family: var(--font-display, var(--font-primary));
}

html { scroll-behavior: smooth; }

/* Animation classes */
@keyframes jp-fadeUp {
  from { opacity: 0; transform: translateY(20px); }
  to   { opacity: 1; transform: translateY(0); }
}
.jp-animate-in { opacity: 0; animation: jp-fadeUp 0.7s ease forwards; }
.jp-d1 { animation-delay: 0.1s; }
.jp-d2 { animation-delay: 0.2s; }
.jp-d3 { animation-delay: 0.3s; }
.jp-d4 { animation-delay: 0.4s; }

@keyframes jp-pulseDot {
  0%, 100% { opacity: 1; transform: scale(1); }
  50%       { opacity: 0.5; transform: scale(0.85); }
}
.jp-pulse-dot { animation: jp-pulseDot 2s ease infinite; }

/* TOCC — required by §7 spec */
[data-jp-section-overlay] {
  position: absolute; inset: 0; z-index: 9999;
  pointer-events: none; border: 2px solid transparent;
  transition: border-color 0.15s, background-color 0.15s;
}
[data-section-id]:hover [data-jp-section-overlay] {
  border: 2px dashed color-mix(in oklch, var(--primary) 50%, transparent);
  background-color: color-mix(in oklch, var(--primary) 6%, transparent);
}
[data-section-id][data-jp-selected] [data-jp-section-overlay] {
  border: 2px solid var(--primary);
  background-color: color-mix(in oklch, var(--primary) 10%, transparent);
}
[data-jp-section-overlay] > div {
  position: absolute; top: 0; right: 0;
  padding: 0.2rem 0.55rem;
  font-size: 9px; font-weight: 800;
  text-transform: uppercase; letter-spacing: 0.1em;
  background: var(--primary); color: #fff;
  opacity: 0; transition: opacity 0.15s;
}
[data-section-id]:hover [data-jp-section-overlay] > div,
[data-section-id][data-jp-selected] [data-jp-section-overlay] > div { opacity: 1; }

END_OF_FILE_CONTENT
mkdir -p "src/lib"
echo "Creating src/lib/ComponentRegistry.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/lib/ComponentRegistry.tsx"
import React from 'react';
import { AlpineHero } from '@/components/alpine-hero';
import { PageHero } from '@/components/page-hero';
import { ResortHighlights } from '@/components/resort-highlights';
import { AccommodationShowcase } from '@/components/accommodation-showcase';
import { StatsBand } from '@/components/stats-band';
import { Testimonials } from '@/components/testimonials';
import { NewsletterCta } from '@/components/newsletter-cta';
import { SpaTreatments } from '@/components/spa-treatments';
import { CulinaryShowcase } from '@/components/culinary-showcase';
import { WineCellar } from '@/components/wine-cellar';
import { ExperienceTimeline } from '@/components/experience-timeline';
import { Header } from '@/components/header';
import { Footer } from '@/components/footer';

import type { SectionType } from '@olonjs/core';
import type { SectionComponentPropsMap } from '@/types';

export const ComponentRegistry: {
  [K in SectionType]: React.FC<SectionComponentPropsMap[K]>;
} = {
  'alpine-hero': AlpineHero,
  'page-hero': PageHero,
  'resort-highlights': ResortHighlights,
  'accommodation-showcase': AccommodationShowcase,
  'stats-band': StatsBand,
  'testimonials': Testimonials,
  'newsletter-cta': NewsletterCta,
  'spa-treatments': SpaTreatments,
  'culinary-showcase': CulinaryShowcase,
  'wine-cellar': WineCellar,
  'experience-timeline': ExperienceTimeline,
  'header': Header,
  'footer': Footer,
};

END_OF_FILE_CONTENT
echo "Creating src/lib/IconResolver.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/lib/IconResolver.tsx"
import React from 'react';
import {
  Layers,
  Github,
  ArrowRight,
  Box,
  Terminal,
  ChevronRight,
  Menu,
  X,
  Sparkles,
  Zap,
  Mail,
  type LucideIcon
} from 'lucide-react';

export const iconMap = {
  'layers': Layers,
  'github': Github,
  'arrow-right': ArrowRight,
  'box': Box,
  'terminal': Terminal,
  'chevron-right': ChevronRight,
  'menu': Menu,
  'x': X,
  'sparkles': Sparkles,
  'zap': Zap,
  'mail': Mail,
} as const satisfies Record<string, LucideIcon>;

export type IconName = keyof typeof iconMap;

export function isIconName(s: string): s is IconName {
  return s in iconMap;
}

interface IconProps {
  name: string;
  size?: number;
  className?: string;
}

export const Icon: React.FC<IconProps> = ({ name, size = 20, className }) => {
  const IconComponent = isIconName(name) ? iconMap[name] : undefined;

  if (!IconComponent) {
    if (import.meta.env.DEV) {
      console.warn(`[IconResolver] Unknown icon: "${name}". Add it to iconMap.`);
    }
    return null;
  }

  return <IconComponent size={size} className={className} />;
};



END_OF_FILE_CONTENT
echo "Creating src/lib/addSectionConfig.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/lib/addSectionConfig.ts"
import type { AddSectionConfig } from '@olonjs/core';

const addableSectionTypes = [
  'alpine-hero',
  'page-hero',
  'resort-highlights',
  'accommodation-showcase',
  'stats-band',
  'testimonials',
  'newsletter-cta',
  'spa-treatments',
  'culinary-showcase',
  'wine-cellar',
  'experience-timeline'
] as const;

const sectionTypeLabels: Record<string, string> = {
  'alpine-hero': 'Alpine Hero',
  'page-hero': 'Page Hero',
  'resort-highlights': 'Resort Highlights',
  'accommodation-showcase': 'Accommodation Showcase',
  'stats-band': 'Statistics Band',
  'testimonials': 'Testimonials',
  'newsletter-cta': 'Newsletter CTA',
  'spa-treatments': 'Spa Treatments',
  'culinary-showcase': 'Culinary Showcase',
  'wine-cellar': 'Wine Cellar',
  'experience-timeline': 'Experience Timeline',
};

function getDefaultSectionData(type: string): Record<string, unknown> {
  switch (type) {
    case 'alpine-hero':
      return {
        badge: 'Luxury Alpine Retreat',
        title: 'Experience Alpine Luxury',
        description: 'Discover unparalleled comfort in the heart of the Dolomites.',
        primaryCta: { id: 'cta-1', label: 'Book Now', href: '/book', variant: 'primary' },
        secondaryCta: { id: 'cta-2', label: 'Explore', href: '/accommodations', variant: 'secondary' }
      };
    case 'page-hero':
      return {
        title: 'Page Title',
        description: 'Page description goes here.',
        breadcrumbs: []
      };
    case 'resort-highlights':
      return {
        label: 'Highlights',
        title: 'Resort Features',
        highlights: []
      };
    case 'accommodation-showcase':
      return {
        label: 'Accommodations',
        title: 'Luxury Suites',
        accommodations: []
      };
    case 'stats-band':
      return {
        title: 'By the Numbers',
        stats: []
      };
    case 'testimonials':
      return {
        label: 'Testimonials',
        title: 'Guest Reviews',
        testimonials: []
      };
    case 'newsletter-cta':
      return {
        title: 'Stay Updated',
        description: 'Subscribe to our newsletter for exclusive offers.',
        placeholder: 'Enter your email',
        cta: { id: 'newsletter-cta', label: 'Subscribe', href: '#', variant: 'primary' }
      };
    case 'spa-treatments':
      return {
        label: 'Wellness',
        title: 'Spa Treatments',
        description: 'Rejuvenate with our world-class spa services.',
        treatments: []
      };
    case 'culinary-showcase':
      return {
        label: 'Culinary',
        title: 'Fine Dining Experience',
        description: 'Award-winning cuisine in the heart of the Alps.',
        items: []
      };
    case 'wine-cellar':
      return {
        label: 'Wine',
        title: 'Alpine Wine Cellar',
        description: 'Curated selection of regional and international wines.',
        wines: []
      };
    case 'experience-timeline':
      return {
        label: 'Activities',
        title: 'Alpine Experiences',
        description: 'From skiing to hiking, discover the best of the Dolomites.',
        experiences: []
      };
    default:
      return {};
  }
}

export const addSectionConfig: AddSectionConfig = {
  addableSectionTypes: [...addableSectionTypes],
  sectionTypeLabels,
  getDefaultSectionData,
};

END_OF_FILE_CONTENT
echo "Creating src/lib/draftStorage.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/lib/draftStorage.ts"
/**
 * Tenant initial data — file-backed only (no localStorage).
 */

import type { PageConfig, SiteConfig } from '@/types';

export interface HydratedData {
  pages: Record<string, PageConfig>;
  siteConfig: SiteConfig;
}

/**
 * Return pages and siteConfig from file-backed data only.
 */
export function getHydratedData(
  _tenantId: string,
  filePages: Record<string, PageConfig>,
  fileSiteConfig: SiteConfig
): HydratedData {
  return {
    pages: { ...filePages },
    siteConfig: fileSiteConfig,
  };
}

END_OF_FILE_CONTENT
echo "Creating src/lib/getFilePages.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/lib/getFilePages.ts"
/**
 * Page registry loaded from nested JSON files under src/data/pages.
 * Add a JSON file in that directory tree to register a page; no manual list in App.tsx.
 */
import type { PageConfig } from '@/types';

function slugFromPath(filePath: string): string {
  const normalizedPath = filePath.replace(/\\/g, '/');
  const match = normalizedPath.match(/\/data\/pages\/(.+)\.json$/i);
  const rawSlug = match?.[1] ?? normalizedPath.split('/').pop()?.replace(/\.json$/i, '') ?? '';
  const canonical = rawSlug
    .split('/')
    .map((segment) => segment.trim())
    .filter(Boolean)
    .join('/');
  return canonical || 'home';
}

export function getFilePages(): Record<string, PageConfig> {
  const glob = import.meta.glob<{ default: unknown }>('@/data/pages/**/*.json', { eager: true });
  const bySlug = new Map<string, PageConfig>();
  const entries = Object.entries(glob).sort(([a], [b]) => a.localeCompare(b));
  for (const [path, mod] of entries) {
    const slug = slugFromPath(path);
    const raw = mod?.default;
    if (raw == null || typeof raw !== 'object') {
      console.warn(`[tenant-alpha:getFilePages] Ignoring invalid page module at "${path}".`);
      continue;
    }
    if (bySlug.has(slug)) {
      console.warn(`[tenant-alpha:getFilePages] Duplicate slug "${slug}" at "${path}". Keeping latest match.`);
    }
    bySlug.set(slug, raw as PageConfig);
  }
  const slugs = Array.from(bySlug.keys()).sort((a, b) =>
    a === 'home' ? -1 : b === 'home' ? 1 : a.localeCompare(b)
  );
  const record: Record<string, PageConfig> = {};
  for (const slug of slugs) {
    const config = bySlug.get(slug);
    if (config) record[slug] = config;
  }
  return record;
}

END_OF_FILE_CONTENT
echo "Creating src/lib/schemas.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/lib/schemas.ts"
import { AlpineHeroSchema } from '@/components/alpine-hero';
import { PageHeroSchema } from '@/components/page-hero';
import { ResortHighlightsSchema } from '@/components/resort-highlights';
import { AccommodationShowcaseSchema } from '@/components/accommodation-showcase';
import { StatsBandSchema } from '@/components/stats-band';
import { TestimonialsSchema } from '@/components/testimonials';
import { NewsletterCtaSchema } from '@/components/newsletter-cta';
import { SpaTreatmentsSchema } from '@/components/spa-treatments';
import { CulinaryShowcaseSchema } from '@/components/culinary-showcase';
import { WineCellarSchema } from '@/components/wine-cellar';
import { ExperienceTimelineSchema } from '@/components/experience-timeline';
import { HeaderSchema } from '@/components/header';
import { FooterSchema } from '@/components/footer';

export const SECTION_SCHEMAS = {
  'alpine-hero': AlpineHeroSchema,
  'page-hero': PageHeroSchema,
  'resort-highlights': ResortHighlightsSchema,
  'accommodation-showcase': AccommodationShowcaseSchema,
  'stats-band': StatsBandSchema,
  'testimonials': TestimonialsSchema,
  'newsletter-cta': NewsletterCtaSchema,
  'spa-treatments': SpaTreatmentsSchema,
  'culinary-showcase': CulinaryShowcaseSchema,
  'wine-cellar': WineCellarSchema,
  'experience-timeline': ExperienceTimelineSchema,
  'header': HeaderSchema,
  'footer': FooterSchema,
} as const;

export const SECTION_SUBMISSION_SCHEMAS = {
} as const;

export type SectionType = keyof typeof SECTION_SCHEMAS;

export {
  BaseSectionData,
  BaseArrayItem,
  BaseSectionSettingsSchema,
  CtaSchema,
  ImageSelectionSchema,
} from '@olonjs/core';

END_OF_FILE_CONTENT
echo "Creating src/lib/useFormSubmit.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/lib/useFormSubmit.ts"
import { useState, useCallback } from 'react';

export type SubmitStatus = 'idle' | 'submitting' | 'success' | 'error';

interface UseFormSubmitOptions {
  source: string;
  tenantId: string;
}

export function useFormSubmit({ source, tenantId }: UseFormSubmitOptions) {
  const [status, setStatus] = useState<SubmitStatus>('idle');
  const [message, setMessage] = useState<string>('');

  const submit = useCallback(async (
    formData: FormData, 
    recipientEmail: string, 
    pageSlug: string, 
    sectionId: string
  ) => {
    const cloudApiUrl = import.meta.env.VITE_JSONPAGES_CLOUD_URL as string | undefined;
    const cloudApiKey = import.meta.env.VITE_JSONPAGES_API_KEY as string | undefined;

    if (!cloudApiUrl || !cloudApiKey) {
      setStatus('error');
      setMessage('Configurazione API non disponibile. Riprova tra poco.');
      return false;
    }

    // Trasformiamo FormData in un oggetto piatto per il payload JSON
    const data: Record<string, any> = {};
    formData.forEach((value, key) => {
      data[key] = String(value).trim();
    });

    const payload = {
      ...data,
      recipientEmail,
      page: pageSlug,
      section: sectionId,
      tenant: tenantId,
      source: source,
      submittedAt: new Date().toISOString(),
    };

    // Idempotency Key per evitare doppi invii accidentali
    const idempotencyKey = `form-${sectionId}-${Date.now()}`;

    setStatus('submitting');
    setMessage('Invio in corso...');

    try {
      const apiBase = cloudApiUrl.replace(/\/$/, '');
      const response = await fetch(`${apiBase}/forms/submit`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${cloudApiKey}`,
          'Content-Type': 'application/json',
          'Idempotency-Key': idempotencyKey,
        },
        body: JSON.stringify(payload),
      });

      const body = (await response.json().catch(() => ({}))) as { error?: string; code?: string };

      if (!response.ok) {
        throw new Error(body.error || body.code || `Submit failed (${response.status})`);
      }

      setStatus('success');
      setMessage('Richiesta inviata con successo. Ti risponderemo al più presto.');
      return true;
    } catch (error: unknown) {
      const errorMsg = error instanceof Error ? error.message : 'Invio non riuscito. Riprova tra poco.';
      setStatus('error');
      setMessage(errorMsg);
      return false;
    }
  }, [source, tenantId]);

  const reset = useCallback(() => {
    setStatus('idle');
    setMessage('');
  }, []);

  return { submit, status, message, reset };
}
END_OF_FILE_CONTENT
echo "Creating src/lib/useOlonForms.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/lib/useOlonForms.ts"
import { useCallback, useEffect, useState } from 'react';
import type { FormState } from '@olonjs/core';

const API_BASE =
  (import.meta.env.VITE_OLONJS_CLOUD_URL as string | undefined) ??
  (import.meta.env.VITE_JSONPAGES_CLOUD_URL as string | undefined);

const API_KEY =
  (import.meta.env.VITE_OLONJS_API_KEY as string | undefined) ??
  (import.meta.env.VITE_JSONPAGES_API_KEY as string | undefined);

interface UseOlonFormsOptions {
  /** Override the submit endpoint. Defaults to VITE_OLONJS_CLOUD_URL/forms/submit */
  endpoint?: string;
}

/**
 * Mount once in App.tsx. Scans the DOM for all <form data-olon-recipient="...">
 * elements and attaches submit handlers. Returns per-form states to be provided
 * via OlonFormsContext.Provider.
 *
 * Views consume state via useFormState(formId) — no direct coupling to this hook.
 */
export function useOlonForms(options?: UseOlonFormsOptions): { states: Record<string, FormState> } {
  const [states, setStates] = useState<Record<string, FormState>>({});

  const setFormState = useCallback((formId: string, state: FormState) => {
    setStates((prev) => ({ ...prev, [formId]: state }));
  }, []);

  useEffect(() => {
    const resolvedBase = options?.endpoint
      ? options.endpoint.replace(/\/$/, '')
      : API_BASE
        ? API_BASE.replace(/\/$/, '')
        : null;

    if (!resolvedBase || !API_KEY) {
      console.warn('[useOlonForms] Missing API endpoint or key — forms will not submit.');
      return;
    }

    const endpoint = resolvedBase.endsWith('/forms/submit')
      ? resolvedBase
      : `${resolvedBase}/forms/submit`;

    const forms = Array.from(
      document.querySelectorAll<HTMLFormElement>('form[data-olon-recipient]')
    );

    const controllers: AbortController[] = [];

    async function handleSubmit(form: HTMLFormElement, event: SubmitEvent) {
      event.preventDefault();

      const formId = form.id || form.dataset.olonRecipient || 'olon-form';
      const recipientEmail = form.dataset.olonRecipient ?? '';

      setFormState(formId, { status: 'submitting', message: 'Invio in corso...' });

      const raw: Record<string, string> = {};
      new FormData(form).forEach((value, key) => {
        raw[key] = String(value).trim();
      });

      const payload = {
        ...raw,
        recipientEmail,
        page: window.location.pathname,
        source: 'olon-form',
        submittedAt: new Date().toISOString(),
      };

      const controller = new AbortController();
      controllers.push(controller);

      try {
        const response = await fetch(endpoint, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${API_KEY}`,
            'Content-Type': 'application/json',
            'Idempotency-Key': `form-${formId}-${Date.now()}`,
          },
          body: JSON.stringify(payload),
          signal: controller.signal,
        });

        const body = (await response.json().catch(() => ({}))) as {
          error?: string;
          code?: string;
        };

        if (!response.ok) {
          throw new Error(body.error ?? body.code ?? `Submit failed (${response.status})`);
        }

        setFormState(formId, {
          status: 'success',
          message: 'Richiesta inviata con successo.',
        });
        form.reset();
      } catch (error: unknown) {
        if (error instanceof Error && error.name === 'AbortError') return;
        const message =
          error instanceof Error ? error.message : 'Invio non riuscito. Riprova.';
        setFormState(formId, { status: 'error', message });
      }
    }

    type Listener = { form: HTMLFormElement; handler: (e: Event) => void };
    const listeners: Listener[] = [];

    forms.forEach((form) => {
      const handler = (e: Event) => void handleSubmit(form, e as SubmitEvent);
      form.addEventListener('submit', handler);
      listeners.push({ form, handler });
    });

    return () => {
      controllers.forEach((c) => c.abort());
      listeners.forEach(({ form, handler }) => form.removeEventListener('submit', handler));
    };
  }, [options?.endpoint, setFormState]);

  return { states };
}

END_OF_FILE_CONTENT
echo "Creating src/lib/utils.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/lib/utils.ts"
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

END_OF_FILE_CONTENT
echo "Creating src/main.tsx..."
cat << 'END_OF_FILE_CONTENT' > "src/main.tsx"
import '@/types'; // TBP: load type augmentation from capsule-driven types
import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
// ... resto del file

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);




END_OF_FILE_CONTENT
echo "Creating src/runtime.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/runtime.ts"
import type { JsonPagesConfig, MenuConfig, PageConfig, SiteConfig, ThemeConfig } from '@/types';
import { SECTION_SCHEMAS, SECTION_SUBMISSION_SCHEMAS } from '@/lib/schemas';
import { getFilePages } from '@/lib/getFilePages';
import siteData from '@/data/config/site.json';
import menuData from '@/data/config/menu.json';
import themeData from '@/data/config/theme.json';

export const siteConfig = siteData as unknown as SiteConfig;
export const themeConfig = themeData as unknown as ThemeConfig;
export const menuConfig = menuData as unknown as MenuConfig;
export const pages = getFilePages();
export const refDocuments = {
  'menu.json': menuConfig,
  'config/menu.json': menuConfig,
  'src/data/config/menu.json': menuConfig,
} satisfies NonNullable<JsonPagesConfig['refDocuments']>;

export function getWebMcpBuildState(): {
  pages: Record<string, PageConfig>;
  schemas: JsonPagesConfig['schemas'];
  submissionSchemas: JsonPagesConfig['submissionSchemas'];
  siteConfig: SiteConfig;
} {
  return {
    pages,
    schemas: SECTION_SCHEMAS as unknown as JsonPagesConfig['schemas'],
    submissionSchemas: SECTION_SUBMISSION_SCHEMAS as unknown as JsonPagesConfig['submissionSchemas'],
    siteConfig,
  };
}

END_OF_FILE_CONTENT
echo "Creating src/types.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/types.ts"
import type { AlpineHeroData, AlpineHeroSettings } from '@/components/alpine-hero';
import type { PageHeroData, PageHeroSettings } from '@/components/page-hero';
import type { ResortHighlightsData, ResortHighlightsSettings } from '@/components/resort-highlights';
import type { AccommodationShowcaseData, AccommodationShowcaseSettings } from '@/components/accommodation-showcase';
import type { StatsBandData, StatsBandSettings } from '@/components/stats-band';
import type { TestimonialsData, TestimonialsSettings } from '@/components/testimonials';
import type { NewsletterCtaData, NewsletterCtaSettings } from '@/components/newsletter-cta';
import type { SpaTreatmentsData, SpaTreatmentsSettings } from '@/components/spa-treatments';
import type { CulinaryShowcaseData, CulinaryShowcaseSettings } from '@/components/culinary-showcase';
import type { WineCellarData, WineCellarSettings } from '@/components/wine-cellar';
import type { ExperienceTimelineData, ExperienceTimelineSettings } from '@/components/experience-timeline';
import type { HeaderData, HeaderSettings } from '@/components/header';
import type { FooterData, FooterSettings } from '@/components/footer';

export type SectionComponentPropsMap = {
  'alpine-hero': { data: AlpineHeroData; settings: AlpineHeroSettings };
  'page-hero': { data: PageHeroData; settings: PageHeroSettings };
  'resort-highlights': { data: ResortHighlightsData; settings: ResortHighlightsSettings };
  'accommodation-showcase': { data: AccommodationShowcaseData; settings: AccommodationShowcaseSettings };
  'stats-band': { data: StatsBandData; settings: StatsBandSettings };
  'testimonials': { data: TestimonialsData; settings: TestimonialsSettings };
  'newsletter-cta': { data: NewsletterCtaData; settings: NewsletterCtaSettings };
  'spa-treatments': { data: SpaTreatmentsData; settings: SpaTreatmentsSettings };
  'culinary-showcase': { data: CulinaryShowcaseData; settings: CulinaryShowcaseSettings };
  'wine-cellar': { data: WineCellarData; settings: WineCellarSettings };
  'experience-timeline': { data: ExperienceTimelineData; settings: ExperienceTimelineSettings };
  'header': { data: HeaderData; settings: HeaderSettings };
  'footer': { data: FooterData; settings: FooterSettings };
};

declare module '@olonjs/core' {
  export interface SectionDataRegistry {
    'alpine-hero': AlpineHeroData;
    'page-hero': PageHeroData;
    'resort-highlights': ResortHighlightsData;
    'accommodation-showcase': AccommodationShowcaseData;
    'stats-band': StatsBandData;
    'testimonials': TestimonialsData;
    'newsletter-cta': NewsletterCtaData;
    'spa-treatments': SpaTreatmentsData;
    'culinary-showcase': CulinaryShowcaseData;
    'wine-cellar': WineCellarData;
    'experience-timeline': ExperienceTimelineData;
    'header': HeaderData;
    'footer': FooterData;
  }
  export interface SectionSettingsRegistry {
    'alpine-hero': AlpineHeroSettings;
    'page-hero': PageHeroSettings;
    'resort-highlights': ResortHighlightsSettings;
    'accommodation-showcase': AccommodationShowcaseSettings;
    'stats-band': StatsBandSettings;
    'testimonials': TestimonialsSettings;
    'newsletter-cta': NewsletterCtaSettings;
    'spa-treatments': SpaTreatmentsSettings;
    'culinary-showcase': CulinaryShowcaseSettings;
    'wine-cellar': WineCellarSettings;
    'experience-timeline': ExperienceTimelineSettings;
    'header': HeaderSettings;
    'footer': FooterSettings;
  }
}

export * from '@olonjs/core';

END_OF_FILE_CONTENT
echo "Creating src/vite-env.d.ts..."
cat << 'END_OF_FILE_CONTENT' > "src/vite-env.d.ts"
/// <reference types="vite/client" />

declare module '*?inline' {
  const content: string;
  export default content;
}



END_OF_FILE_CONTENT
