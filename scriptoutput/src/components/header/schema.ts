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

