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

