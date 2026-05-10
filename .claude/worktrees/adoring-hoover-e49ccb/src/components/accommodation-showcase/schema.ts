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

