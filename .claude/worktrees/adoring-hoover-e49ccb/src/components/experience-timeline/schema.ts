import { z } from 'zod';
import { BaseSectionData, BaseArrayItem, ImageSelectionSchema, CtaSchema } from '@olonjs/core';

const ExperienceItemSchema = BaseArrayItem.extend({
  title: z.string().describe('ui:text'),
  season: z.string().optional().describe('ui:text'),
  difficulty: z.enum(['Easy', 'Moderate', 'Challenging', 'Expert']).optional().describe('ui:select'),
  duration: z.string().optional().describe('ui:text'),
  description: z.string().describe('ui:textarea'),
  image: ImageSelectionSchema.optional(),
  cta: CtaSchema.optional(),
});

export const ExperienceTimelineSchema = BaseSectionData.extend({
  label: z.string().optional().describe('ui:text'),
  title: z.string().describe('ui:text'),
  description: z.string().optional().describe('ui:textarea'),
  experiences: z.array(ExperienceItemSchema).describe('ui:list'),
});

