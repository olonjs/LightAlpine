import type { AlpineHeroData, AlpineHeroSettings } from '@/components/alpine-hero';
import type { PageHeroData, PageHeroSettings } from '@/components/page-hero';
import type { ResortHighlightsData, ResortHighlightsSettings } from '@/components/resort-highlights';
import type { AccommodationShowcaseData, AccommodationShowcaseSettings } from '@/components/accommodation-showcase';
import type { StatsBandData, StatsBandSettings } from '@/components/stats-band';
import type { TestimonialsData, TestimonialsSettings } from '@/components/testimonials';
import type { NewsletterCtaData, NewsletterCtaSettings } from '@/components/newsletter-cta';
import type { SpaTreatmentsData, SpaTreatmentsSettings } from '@/components/spa-treatments';
import type { CulinaryShowcaseData, CulinaryShowcaseSettings } from '@/components/culinary-showcase';
import type { WineCellarData, WineCellarSettings } from '@/components/wine-cellar';
import type { ExperienceTimelineData, ExperienceTimelineSettings } from '@/components/experience-timeline';
import type { HeaderData, HeaderSettings } from '@/components/header';
import type { FooterData, FooterSettings } from '@/components/footer';

export type SectionComponentPropsMap = {
  'alpine-hero': { data: AlpineHeroData; settings: AlpineHeroSettings };
  'page-hero': { data: PageHeroData; settings: PageHeroSettings };
  'resort-highlights': { data: ResortHighlightsData; settings: ResortHighlightsSettings };
  'accommodation-showcase': { data: AccommodationShowcaseData; settings: AccommodationShowcaseSettings };
  'stats-band': { data: StatsBandData; settings: StatsBandSettings };
  'testimonials': { data: TestimonialsData; settings: TestimonialsSettings };
  'newsletter-cta': { data: NewsletterCtaData; settings: NewsletterCtaSettings };
  'spa-treatments': { data: SpaTreatmentsData; settings: SpaTreatmentsSettings };
  'culinary-showcase': { data: CulinaryShowcaseData; settings: CulinaryShowcaseSettings };
  'wine-cellar': { data: WineCellarData; settings: WineCellarSettings };
  'experience-timeline': { data: ExperienceTimelineData; settings: ExperienceTimelineSettings };
  'header': { data: HeaderData; settings: HeaderSettings };
  'footer': { data: FooterData; settings: FooterSettings };
};

declare module '@olonjs/core' {
  export interface SectionDataRegistry {
    'alpine-hero': AlpineHeroData;
    'page-hero': PageHeroData;
    'resort-highlights': ResortHighlightsData;
    'accommodation-showcase': AccommodationShowcaseData;
    'stats-band': StatsBandData;
    'testimonials': TestimonialsData;
    'newsletter-cta': NewsletterCtaData;
    'spa-treatments': SpaTreatmentsData;
    'culinary-showcase': CulinaryShowcaseData;
    'wine-cellar': WineCellarData;
    'experience-timeline': ExperienceTimelineData;
    'header': HeaderData;
    'footer': FooterData;
  }
  export interface SectionSettingsRegistry {
    'alpine-hero': AlpineHeroSettings;
    'page-hero': PageHeroSettings;
    'resort-highlights': ResortHighlightsSettings;
    'accommodation-showcase': AccommodationShowcaseSettings;
    'stats-band': StatsBandSettings;
    'testimonials': TestimonialsSettings;
    'newsletter-cta': NewsletterCtaSettings;
    'spa-treatments': SpaTreatmentsSettings;
    'culinary-showcase': CulinaryShowcaseSettings;
    'wine-cellar': WineCellarSettings;
    'experience-timeline': ExperienceTimelineSettings;
    'header': HeaderSettings;
    'footer': FooterSettings;
  }
}

export * from '@olonjs/core';

