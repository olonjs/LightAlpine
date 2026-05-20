import { z } from 'zod';
import { EmptyTenantSchema, EmptyTenantSettingsSchema } from './schema';

export type EmptyTenantData = z.infer<typeof EmptyTenantSchema>;
export type EmptyTenantSettings = z.infer<typeof EmptyTenantSettingsSchema>;

