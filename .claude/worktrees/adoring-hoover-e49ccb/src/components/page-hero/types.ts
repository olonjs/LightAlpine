import { z } from 'zod';
import { BaseSectionSettingsSchema } from '@olonjs/core';
import { PageHeroSchema } from './schema';

export type PageHeroData = z.infer<typeof PageHeroSchema>;
export type PageHeroSettings = z.infer<typeof BaseSectionSettingsSchema>;

