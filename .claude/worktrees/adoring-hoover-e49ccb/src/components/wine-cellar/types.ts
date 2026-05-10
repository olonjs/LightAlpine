import { z } from 'zod';
import { BaseSectionSettingsSchema } from '@olonjs/core';
import { WineCellarSchema } from './schema';

export type WineCellarData = z.infer<typeof WineCellarSchema>;
export type WineCellarSettings = z.infer<typeof BaseSectionSettingsSchema>;

