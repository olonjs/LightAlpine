import { z } from 'zod';
import { BaseSectionSettingsSchema } from '@olonjs/core';
import { NewsletterCtaSchema } from './schema';

export type NewsletterCtaData = z.infer<typeof NewsletterCtaSchema>;
export type NewsletterCtaSettings = z.infer<typeof BaseSectionSettingsSchema>;

