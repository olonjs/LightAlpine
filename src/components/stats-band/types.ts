import { z } from 'zod';
import { BaseSectionSettingsSchema } from '@olonjs/core';
import { StatsBandSchema } from './schema';

export type StatsBandData = z.infer<typeof StatsBandSchema>;
export type StatsBandSettings = z.infer<typeof BaseSectionSettingsSchema>;

