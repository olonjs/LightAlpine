import { z } from 'zod';
import { BaseSectionData, BaseArrayItem } from '@olonjs/core';

const TreatmentItemSchema = BaseArrayItem.extend({
  title: z.string().describe('ui:text'),
  duration: z.string().optional().describe('ui:text'),
  price: z.string().optional().describe('ui:text'),
  description: z.string().describe('ui:textarea'),
});

export const SpaTreatmentsSchema = BaseSectionData.extend({
  label: z.string().optional().describe('ui:text'),
  title: z.string().describe('ui:text'),
  description: z.string().optional().describe('ui:textarea'),
  treatments: z.array(TreatmentItemSchema).describe('ui:list'),
});

