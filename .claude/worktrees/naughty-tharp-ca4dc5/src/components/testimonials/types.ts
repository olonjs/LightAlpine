import { z } from 'zod';
import { BaseSectionSettingsSchema } from '@olonjs/core';
import { TestimonialsSchema } from './schema';

export type TestimonialsData = z.infer<typeof TestimonialsSchema>;
export type TestimonialsSettings = z.infer<typeof BaseSectionSettingsSchema>;

