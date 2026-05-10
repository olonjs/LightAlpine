import { z } from 'zod';
import { BaseSectionSettingsSchema } from '@olonjs/core';
import { SpaTreatmentsSchema } from './schema';

export type SpaTreatmentsData = z.infer<typeof SpaTreatmentsSchema>;
export type SpaTreatmentsSettings = z.infer<typeof BaseSectionSettingsSchema>;

