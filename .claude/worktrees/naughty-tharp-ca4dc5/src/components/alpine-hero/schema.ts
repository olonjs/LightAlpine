import { z } from 'zod';
import { BaseSectionData, CtaSchema, ImageSelectionSchema } from '@olonjs/core';

export const AlpineHeroSchema = BaseSectionData.extend({
  backgroundImage: ImageSelectionSchema.optional(),
  badge: z.string().optional().describe('ui:text'),
  title: z.string().describe('ui:text'),
  titleHighlight: z.string().optional().describe('ui:text'),
  description: z.string().describe('ui:textarea'),
  primaryCta: CtaSchema,
  secondaryCta: CtaSchema.optional(),
});
