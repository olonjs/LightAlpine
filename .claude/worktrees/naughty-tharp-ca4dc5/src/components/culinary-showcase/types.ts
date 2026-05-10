import { z } from 'zod';
import { BaseSectionSettingsSchema } from '@olonjs/core';
import { CulinaryShowcaseSchema } from './schema';

export type CulinaryShowcaseData = z.infer<typeof CulinaryShowcaseSchema>;
export type CulinaryShowcaseSettings = z.infer<typeof BaseSectionSettingsSchema>;

