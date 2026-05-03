import fs from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { render } from "@react-email/render";
import React from "react";

type Args = {
  entry?: string;
  out?: string;
  outDir?: string;
  exportName?: string;
  propsFile?: string;
  siteConfig?: string;
  themeConfig?: string;
};

type BakeTarget = {
  entryAbs: string;
  outAbs: string;
};

type SiteConfig = {
  identity?: {
    title?: string;
    logoUrl?: string;
  };
  header?: {
    data?: {
      logoImageUrl?: {
        url?: string;
        alt?: string;
      };
    };
  };
  footer?: {
    data?: {
      brandText?: string;
      brandHighlight?: string;
      tagline?: string;
      logoImageUrl?: {
        url?: string;
        alt?: string;
      };
    };
  };
};

type ThemeConfig = {
  tokens?: {
    colors?: Record<string, string>;
    typography?: {
      fontFamily?: Record<string, string>;
    };
    borderRadius?: Record<string, string>;
  };
};

const DEFAULT_EMAIL_DIR = "src/emails";
const DEFAULT_OUT_DIR = "email-templates";
const DEFAULT_SITE_CONFIG = "src/data/config/site.json";
const DEFAULT_THEME_CONFIG = "src/data/config/theme.json";

function parseArgs(argv: string[]): Args {
  const args: Args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const key = argv[i];
    const next = argv[i + 1];
    if (!next) continue;
    if (key === "--entry") {
      args.entry = next;
      i += 1;
      continue;
    }
    if (key === "--out") {
      args.out = next;
      i += 1;
      continue;
    }
    if (key === "--out-dir") {
      args.outDir = next;
      i += 1;
      continue;
    }
    if (key === "--export") {
      args.exportName = next;
      i += 1;
      continue;
    }
    if (key === "--props") {
      args.propsFile = next;
      i += 1;
      continue;
    }
    if (key === "--site-config") {
      args.siteConfig = next;
      i += 1;
      continue;
    }
    if (key === "--theme-config") {
      args.themeConfig = next;
      i += 1;
    }
  }
  return args;
}

function isComponentExport(value: unknown): value is React.ComponentType<any> {
  return typeof value === "function";
}

function toKebabCase(value: string): string {
  return value
    .replace(/Email$/i, "")
    .replace(/([a-z0-9])([A-Z])/g, "$1-$2")
    .replace(/[_\s]+/g, "-")
    .toLowerCase();
}

function deriveOutAbs(entryAbs: string, outDirAbs: string): string {
  const base = path.basename(entryAbs).replace(/\.[^.]+$/, "");
  const fileName = `${toKebabCase(base)}.html`;
  return path.join(outDirAbs, fileName);
}

async function discoverEmailEntries(rootDir: string): Promise<string[]> {
  const abs = path.resolve(process.cwd(), rootDir);
  const dirEntries = await fs.readdir(abs, { withFileTypes: true }).catch(() => []);
  return dirEntries
    .filter((entry) => entry.isFile())
    .map((entry) => entry.name)
    .filter((name) => /\.(tsx|jsx)$/i.test(name))
    .map((name) => path.join(abs, name));
}

function normalizeUrl(value: string | undefined): string | undefined {
  if (!value) return undefined;
  const trimmed = value.trim();
  return trimmed || undefined;
}

async function readJsonObject<T>(filePath: string): Promise<T | null> {
  const abs = path.resolve(process.cwd(), filePath);
  const raw = await fs.readFile(abs, "utf8").catch(() => null);
  if (!raw) return null;
  const parsed = JSON.parse(raw);
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null;
  return parsed as T;
}

function buildDefaultProps(site: SiteConfig | null, theme: ThemeConfig | null): Record<string, unknown> {
  const footerBrandText = site?.footer?.data?.brandText?.trim() ?? "";
  const footerBrandHighlight = site?.footer?.data?.brandHighlight?.trim() ?? "";
  const brandName = `${footerBrandText}${footerBrandHighlight}`.trim() || "{{tenantName}}";

  const tenantName = site?.identity?.title?.trim() || brandName;
  const logoUrl =
    normalizeUrl(site?.header?.data?.logoImageUrl?.url) ||
    normalizeUrl(site?.footer?.data?.logoImageUrl?.url) ||
    normalizeUrl(site?.identity?.logoUrl) ||
    "";
  const logoAlt =
    site?.header?.data?.logoImageUrl?.alt?.trim() ||
    site?.footer?.data?.logoImageUrl?.alt?.trim() ||
    brandName;
  const tagline = site?.footer?.data?.tagline?.trim() || "";

  return {
    tenantName,
    brandName,
    logoUrl,
    logoAlt,
    tagline,
    theme: theme?.tokens ?? {},
    correlationId: "{{correlationId}}",
    replyTo: "{{replyTo}}",
    leadData: {
      name: "{{lead.name}}",
      email: "{{lead.email}}",
      phone: "{{lead.phone}}",
      checkin: "{{lead.checkin}}",
      checkout: "{{lead.checkout}}",
      guests: "{{lead.guests}}",
      notes: "{{lead.notes}}",
    },
  };
}

async function readProps(
  propsFile: string | undefined,
  siteConfigPath: string,
  themeConfigPath: string
): Promise<Record<string, unknown>> {
  if (propsFile) {
    const raw = await fs.readFile(path.resolve(process.cwd(), propsFile), "utf8");
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error("--props must point to a JSON object file");
    }
    return parsed as Record<string, unknown>;
  }

  const site = await readJsonObject<SiteConfig>(siteConfigPath);
  const theme = await readJsonObject<ThemeConfig>(themeConfigPath);
  return buildDefaultProps(site, theme);
}

async function buildTargets(args: Args): Promise<BakeTarget[]> {
  const outDirAbs = path.resolve(process.cwd(), args.outDir ?? DEFAULT_OUT_DIR);

  if (args.entry) {
    const entryAbs = path.resolve(process.cwd(), args.entry);
    const outAbs = args.out ? path.resolve(process.cwd(), args.out) : deriveOutAbs(entryAbs, outDirAbs);
    return [{ entryAbs, outAbs }];
  }

  const discovered = await discoverEmailEntries(DEFAULT_EMAIL_DIR);
  if (discovered.length === 0) {
    throw new Error(`No templates found in ${DEFAULT_EMAIL_DIR}`);
  }

  return discovered.map((entryAbs) => ({
    entryAbs,
    outAbs: deriveOutAbs(entryAbs, outDirAbs),
  }));
}

async function bakeTemplate(target: BakeTarget, args: Args, props: Record<string, unknown>) {
  const moduleUrl = pathToFileURL(target.entryAbs).href;
  const mod = (await import(moduleUrl)) as Record<string, unknown>;
  const picked = args.exportName ? mod[args.exportName] : mod.default;

  if (!isComponentExport(picked)) {
    const available = Object.keys(mod).join(", ") || "(none)";
    throw new Error(
      `Template export not found or not a component. Requested: ${args.exportName ?? "default"}. Available exports: ${available}. Entry: ${target.entryAbs}`
    );
  }

  const element = React.createElement(picked, props);
  const html = await render(element, { pretty: true });

  await fs.mkdir(path.dirname(target.outAbs), { recursive: true });
  await fs.writeFile(target.outAbs, html, "utf8");

  console.log(`Baked email template: ${path.relative(process.cwd(), target.outAbs)}`);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const targets = await buildTargets(args);
  const props = await readProps(
    args.propsFile,
    args.siteConfig ?? DEFAULT_SITE_CONFIG,
    args.themeConfig ?? DEFAULT_THEME_CONFIG
  );

  for (const target of targets) {
    await bakeTemplate(target, args, props);
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
