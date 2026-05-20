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

