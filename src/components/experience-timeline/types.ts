import { z } from 'zod';
import { BaseSectionSettingsSchema } from '@olonjs/core';
import { ExperienceTimelineSchema } from './schema';

export type ExperienceTimelineData = z.infer<typeof ExperienceTimelineSchema>;
export type ExperienceTimelineSettings = z.infer<typeof BaseSectionSettingsSchema>;

