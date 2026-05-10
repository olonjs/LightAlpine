import { z } from 'zod';
import { BaseSectionData, WithFormRecipient } from '@olonjs/core';

export const FormDemoSchema = BaseSectionData.merge(WithFormRecipient).extend({
  icon: z.string().optional().describe('ui:icon-picker'),
  title: z.string().optional().describe('ui:text'),
  description: z.string().optional().describe('ui:textarea'),
  submitLabel: z.string().default('Invia').describe('ui:text'),
  successMessage: z.string().default('Richiesta inviata con successo.').describe('ui:text'),
});

export const FormDemoSettingsSchema = z.object({});

/**
 * Submission payload schema for the `form-demo` section.
 *
 * Describes the fields actually submitted by the rendered `<form>` in View.tsx
 * (name, email, message). Exposed via `JsonPagesConfig.submissionSchemas` so that
 * MCP agents can discover the submission contract for this section type without
 * scraping the DOM. See ADR-0002 (docs/decisions/ADR-0002-form-submission-schemas.md).
 */
export const FormDemoSubmissionSchema = z.object({
  name: z.string().min(1).describe('Full name of the person submitting the form'),
  email: z.string().email().describe('Contact email address where we will reply'),
  message: z.string().min(1).describe('Free-form message body'),
});

