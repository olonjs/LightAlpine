import { z } from 'zod';
import { BaseSectionSettingsSchema } from '@olonjs/core';
import { ResortHighlightsSchema } from './schema';

export type ResortHighlightsData = z.infer<typeof ResortHighlightsSchema>;
export type ResortHighlightsSettings = z.infer<typeof BaseSectionSettingsSchema>;

