import { AlpineHeroSchema } from '@/components/alpine-hero';
import { PageHeroSchema } from '@/components/page-hero';
import { ResortHighlightsSchema } from '@/components/resort-highlights';
import { AccommodationShowcaseSchema } from '@/components/accommodation-showcase';
import { StatsBandSchema } from '@/components/stats-band';
import { TestimonialsSchema } from '@/components/testimonials';
import { NewsletterCtaSchema } from '@/components/newsletter-cta';
import { SpaTreatmentsSchema } from '@/components/spa-treatments';
import { CulinaryShowcaseSchema } from '@/components/culinary-showcase';
import { WineCellarSchema } from '@/components/wine-cellar';
import { ExperienceTimelineSchema } from '@/components/experience-timeline';
import { HeaderSchema } from '@/components/header';
import { FooterSchema } from '@/components/footer';

export const SECTION_SCHEMAS = {
  'alpine-hero': AlpineHeroSchema,
  'page-hero': PageHeroSchema,
  'resort-highlights': ResortHighlightsSchema,
  'accommodation-showcase': AccommodationShowcaseSchema,
  'stats-band': StatsBandSchema,
  'testimonials': TestimonialsSchema,
  'newsletter-cta': NewsletterCtaSchema,
  'spa-treatments': SpaTreatmentsSchema,
  'culinary-showcase': CulinaryShowcaseSchema,
  'wine-cellar': WineCellarSchema,
  'experience-timeline': ExperienceTimelineSchema,
  'header': HeaderSchema,
  'footer': FooterSchema,
} as const;

export const SECTION_SUBMISSION_SCHEMAS = {
} as const;

export type SectionType = keyof typeof SECTION_SCHEMAS;

export {
  BaseSectionData,
  BaseArrayItem,
  BaseSectionSettingsSchema,
  CtaSchema,
  ImageSelectionSchema,
} from '@olonjs/core';

