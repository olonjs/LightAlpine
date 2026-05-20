import { z } from 'zod';
import { BaseSectionSettingsSchema } from '@olonjs/core';
import { AlpineHeroSchema } from './schema';

export type AlpineHeroData = z.infer<typeof AlpineHeroSchema>;
export type AlpineHeroSettings = z.infer<typeof BaseSectionSettingsSchema>;

