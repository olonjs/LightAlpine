import { z } from 'zod';
import { FormDemoSchema, FormDemoSettingsSchema } from './schema';

export type FormDemoData = z.infer<typeof FormDemoSchema>;
export type FormDemoSettings = z.infer<typeof FormDemoSettingsSchema>;

