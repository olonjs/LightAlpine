import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';
import { createRequire } from 'module';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, '..');
const baseUrl = process.env.WEBMCP_BASE_URL ?? 'http://127.0.0.1:4173';

function pageFilePathFromSlug(slug) {
  return path.resolve(rootDir, 'src', 'data', 'pages', `${slug}.json`);
}

function adminUrlFromSlug(slug) {
  return `${baseUrl}/admin${slug === 'home' ? '' : `/${slug}`}`;
}

function isStringSchema(schema) {
  if (!schema || typeof schema !== 'object') return false;
  if (schema.type === 'string') return true;
  if (Array.isArray(schema.anyOf)) {
    return schema.anyOf.some((entry) => entry && typeof entry === 'object' && entry.type === 'string');
  }
  return false;
}

function findTopLevelStringField(sectionSchema) {
  const properties = sectionSchema?.properties;
  if (!properties || typeof properties !== 'object') return null;
  const preferred = ['title', 'sectionTitle', 'label', 'headline', 'name'];
  for (const key of preferred) {
    if (isStringSchema(properties[key])) return key;
  }
  for (const [key, value] of Object.entries(properties)) {
    if (isStringSchema(value)) return key;
  }
  return null;
}

async function loadPlaywright() {
  const require = createRequire(import.meta.url);
  try {
    return require('playwright');
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(
      `Playwright is required for WebMCP verification. Install it before running this script. Original error: ${message}`
    );
  }
}

async function readPageJson(slug) {
  const pageFilePath = pageFilePathFromSlug(slug);
  const raw = await fs.readFile(pageFilePath, 'utf8');
  return { raw, json: JSON.parse(raw), pageFilePath };
}

async function waitFor(predicate, timeoutMs, label) {
  const startedAt = Date.now();
  for (;;) {
    const result = await predicate();
    if (result) return result;
    if (Date.now() - startedAt > timeoutMs) {
      throw new Error(`Timed out while waiting for ${label}.`);
    }
    await new Promise((resolve) => setTimeout(resolve, 150));
  }
}

async function waitForFileFieldValue(slug, sectionId, fieldKey, expectedValue) {
  await waitFor(async () => {
    const { json } = await readPageJson(slug);
    const section = Array.isArray(json.sections)
      ? json.sections.find((item) => item?.id === sectionId)
      : null;
    return section?.data?.[fieldKey] === expectedValue;
  }, 8_000, `file field "${fieldKey}" = "${expectedValue}"`);
}

async function ensureResponseOk(response, label) {
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`${label} failed with ${response.status}: ${text}`);
  }
  return response;
}

async function fetchJson(relativePath, label) {
  const response = await ensureResponseOk(await fetch(`${baseUrl}${relativePath}`), label);
  return response.json();
}

async function selectTarget() {
  const siteIndex = await fetchJson('/mcp-manifest.json', 'Manifest index request');
  const requestedSlug = typeof process.env.WEBMCP_TARGET_SLUG === 'string' && process.env.WEBMCP_TARGET_SLUG.trim()
    ? process.env.WEBMCP_TARGET_SLUG.trim()
    : null;

  const candidatePages = requestedSlug
    ? (siteIndex.pages ?? []).filter((page) => page?.slug === requestedSlug)
    : (siteIndex.pages ?? []);

  for (const pageEntry of candidatePages) {
    if (!pageEntry?.slug || !pageEntry?.manifestHref || !pageEntry?.contractHref) continue;
    const pageManifest = await fetchJson(pageEntry.manifestHref, `Page manifest request for ${pageEntry.slug}`);
    const pageContract = await fetchJson(pageEntry.contractHref, `Page contract request for ${pageEntry.slug}`);
    const localInstances = Array.isArray(pageContract.sectionInstances)
      ? pageContract.sectionInstances.filter((section) => section?.scope === 'local')
      : [];
    const tools = Array.isArray(pageManifest.tools) ? pageManifest.tools : [];

    for (const tool of tools) {
      const sectionType = tool?.sectionType;
      if (typeof tool?.name !== 'string' || typeof sectionType !== 'string') continue;
      const targetInstance = localInstances.find((section) => section?.type === sectionType);
      if (!targetInstance?.id) continue;
      const targetFieldKey = findTopLevelStringField(pageContract.sectionSchemas?.[sectionType]);
      if (!targetFieldKey) continue;
      const pageState = await readPageJson(pageEntry.slug);
      const section = Array.isArray(pageState.json.sections)
        ? pageState.json.sections.find((item) => item?.id === targetInstance.id)
        : null;
      const originalValue = section?.data?.[targetFieldKey];
      if (typeof originalValue !== 'string') continue;

      return {
        slug: pageEntry.slug,
        manifestHref: pageEntry.manifestHref,
        contractHref: pageEntry.contractHref,
        toolName: tool.name,
        sectionId: targetInstance.id,
        fieldKey: targetFieldKey,
        originalValue,
        originalState: pageState,
      };
    }
  }

  throw new Error(
    requestedSlug
      ? `No valid WebMCP verification target found for page "${requestedSlug}".`
      : 'No valid WebMCP verification target found in manifest index.'
  );
}

async function main() {
  const { chromium } = await loadPlaywright();
  const target = await selectTarget();
  const nextValue = `${target.originalValue} WebMCP ${Date.now()}`;
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();
  const consoleEvents = [];
  let mutationApplied = false;

  page.on('console', (message) => {
    if (message.type() === 'error' || message.type() === 'warning') {
      consoleEvents.push(`[console:${message.type()}] ${message.text()}`);
    }
  });
  page.on('pageerror', (error) => {
    consoleEvents.push(`[pageerror] ${error.message}`);
  });

  const restoreOriginal = async () => {
    try {
      await page.evaluate(
        async ({ toolName, slug, sectionId, fieldKey, value }) => {
          const runtime = navigator.modelContextTesting;
          if (!runtime?.executeTool) return;
          await runtime.executeTool(
            toolName,
            JSON.stringify({
              slug,
              sectionId,
              fieldKey,
              value,
            })
          );
        },
        {
          toolName: target.toolName,
          slug: target.slug,
          sectionId: target.sectionId,
          fieldKey: target.fieldKey,
          value: target.originalValue,
        }
      );
      await waitForFileFieldValue(target.slug, target.sectionId, target.fieldKey, target.originalValue);
    } catch {
      await fs.writeFile(target.originalState.pageFilePath, target.originalState.raw, 'utf8');
    }
  };

  try {
    const pageManifest = await fetchJson(target.manifestHref, `Manifest request for ${target.slug}`);
    if (!Array.isArray(pageManifest.tools) || !pageManifest.tools.some((tool) => tool?.name === target.toolName)) {
      throw new Error(`Manifest does not expose ${target.toolName}.`);
    }

    const pageContract = await fetchJson(target.contractHref, `Contract request for ${target.slug}`);
    if (!Array.isArray(pageContract.tools) || !pageContract.tools.some((tool) => tool?.name === target.toolName)) {
      throw new Error(`Page contract does not expose ${target.toolName}.`);
    }

    await page.goto(adminUrlFromSlug(target.slug), { waitUntil: 'networkidle' });

    try {
      await page.waitForFunction(
        ({ manifestHref, contractHref }) => {
          const manifestLink = document.head.querySelector('link[rel="mcp-manifest"]');
          const contractLink = document.head.querySelector('link[rel="olon-contract"]');
          return manifestLink?.getAttribute('href') === manifestHref
            && contractLink?.getAttribute('href') === contractHref;
        },
        { manifestHref: target.manifestHref, contractHref: target.contractHref },
        { timeout: 10_000 }
      );
    } catch (error) {
      const diagnostics = await page.evaluate(() => ({
        head: document.head.innerHTML,
        bodyText: document.body.innerText,
      }));
      throw new Error(
        [
          error instanceof Error ? error.message : String(error),
          `head=${diagnostics.head}`,
          `body=${diagnostics.bodyText}`,
          ...consoleEvents,
        ].join('\n')
      );
    }

    const toolNames = await page.evaluate(() => {
      const runtime = navigator.modelContextTesting;
      return runtime?.listTools?.().map((tool) => tool.name) ?? [];
    });
    if (!toolNames.includes(target.toolName)) {
      throw new Error(`Runtime did not register ${target.toolName}. Found: ${toolNames.join(', ')}`);
    }

    const rawResult = await page.evaluate(
      async ({ toolName, slug, sectionId, fieldKey, value }) => {
        const runtime = navigator.modelContextTesting;
        if (!runtime?.executeTool) {
          throw new Error('navigator.modelContextTesting.executeTool is unavailable.');
        }
        return runtime.executeTool(
          toolName,
          JSON.stringify({
            slug,
            sectionId,
            fieldKey,
            value,
          })
        );
      },
      {
        toolName: target.toolName,
        slug: target.slug,
        sectionId: target.sectionId,
        fieldKey: target.fieldKey,
        value: nextValue,
      }
    );

    const parsedResult = JSON.parse(rawResult);
    if (parsedResult?.isError) {
      throw new Error(`WebMCP tool returned an error: ${rawResult}`);
    }

    mutationApplied = true;
    await waitForFileFieldValue(target.slug, target.sectionId, target.fieldKey, nextValue);
    await page.frameLocator('iframe').getByText(nextValue, { exact: true }).waitFor({ state: 'attached' });

    console.log(
      JSON.stringify({
        ok: true,
        slug: target.slug,
        manifestHref: target.manifestHref,
        contractHref: target.contractHref,
        toolName: target.toolName,
        sectionId: target.sectionId,
        fieldKey: target.fieldKey,
        toolNames,
      })
    );
  } finally {
    if (mutationApplied) {
      await restoreOriginal();
    }
    await browser.close();
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.stack ?? error.message : String(error));
  process.exit(1);
});
