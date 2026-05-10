import { z } from 'zod';
import { BaseSectionData, BaseArrayItem } from '@olonjs/core';

const StatItemSchema = BaseArrayItem.extend({
  number: z.string().describe('ui:text'),
  label: z.string().describe('ui:text'),
  suffix: z.string().optional().describe('ui:text'),
});

export const StatsBandSchema = BaseSectionData.extend({
  title: z.string().optional().describe('ui:text'),
  stats: z.array(StatItemSchema).describe('ui:list'),
});

