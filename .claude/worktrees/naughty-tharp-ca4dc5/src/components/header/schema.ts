import { z } from 'zod';
import { BaseArrayItem, BaseSectionData } from '@olonjs/core';

const HeaderMenuLinkSchema = BaseArrayItem.extend({
  id: z.string().describe('ui:text'),
  label: z.string().describe('ui:text'),
  href: z.string().describe('ui:text'),
  badge: z.string().optional().describe('ui:text'),
});

const HeaderCtaFromMenuSchema = BaseArrayItem.extend({
  id: z.string().describe('ui:text'),
  label: z.string().describe('ui:text'),
  href: z.string().describe('ui:text'),
  variant: z.enum(['primary', 'ghost']).default('ghost').describe('ui:select'),
});

export const HeaderSchema = BaseSectionData.extend({
  logoText: z.string().describe('ui:text'),
  logoHighlight: z.string().optional().describe('ui:text'),
  logoHref: z.string().optional().describe('ui:text'),
  announcement: z.string().optional().describe('ui:text'),
  scrollThreshold: z.number().optional().describe('ui:number'),
  menu: z.array(HeaderMenuLinkSchema).optional().describe('ui:list'),
  actions: z.array(HeaderCtaFromMenuSchema).optional().describe('ui:list'),
});
