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

