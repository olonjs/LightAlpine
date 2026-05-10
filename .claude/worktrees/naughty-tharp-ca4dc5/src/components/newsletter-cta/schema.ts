import { z } from 'zod';
import { BaseSectionData, CtaSchema } from '@olonjs/core';

export const NewsletterCtaSchema = BaseSectionData.extend({
  title: z.string().describe('ui:text'),
  description: z.string().optional().describe('ui:textarea'),
  placeholder: z.string().optional().describe('ui:text'),
  cta: CtaSchema,
});

