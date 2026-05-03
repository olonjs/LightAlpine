import { z } from 'zod';
import { BaseSectionData, BaseArrayItem, ImageSelectionSchema } from '@olonjs/core';

const WineItemSchema = BaseArrayItem.extend({
  name: z.string().describe('ui:text'),
  vintage: z.string().optional().describe('ui:text'),
  region: z.string().optional().describe('ui:text'),
  description: z.string().describe('ui:textarea'),
  type: z.enum(['red', 'white', 'sparkling', 'dessert']).optional().describe('ui:select'),
});

export const WineCellarSchema = BaseSectionData.extend({
  label: z.string().optional().describe('ui:text'),
  title: z.string().describe('ui:text'),
  description: z.string().optional().describe('ui:textarea'),
  image: ImageSelectionSchema.optional(),
  wines: z.array(WineItemSchema).describe('ui:list'),
});

