import { z } from 'zod';
import { BaseSectionSettingsSchema } from '@olonjs/core';
import { FooterSchema } from './schema';

export type FooterData = z.infer<typeof FooterSchema>;
export type FooterSettings = z.infer<typeof BaseSectionSettingsSchema>;

