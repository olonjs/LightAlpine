import { z } from 'zod';
import { BaseSectionSettingsSchema } from '@olonjs/core';
import { AccommodationShowcaseSchema } from './schema';

export type AccommodationShowcaseData = z.infer<typeof AccommodationShowcaseSchema>;
export type AccommodationShowcaseSettings = z.infer<typeof BaseSectionSettingsSchema>;

