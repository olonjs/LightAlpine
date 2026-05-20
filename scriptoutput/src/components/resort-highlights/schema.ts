import { z } from 'zod';
import { BaseSectionData, BaseArrayItem, ImageSelectionSchema } from '@olonjs/core';

const HighlightItemSchema = BaseArrayItem.extend({
  title: z.string().describe('ui:text'),
  description: z.string().describe('ui:textarea'),
  image: ImageSelectionSchema.optional(),
  category: z.string().optional().describe('ui:text'),
});

export const ResortHighlightsSchema = BaseSectionData.extend({
  label: z.string().optional().describe('ui:text'),
  title: z.string().describe('ui:text'),
  highlights: z.array(HighlightItemSchema).describe('ui:list'),
});

