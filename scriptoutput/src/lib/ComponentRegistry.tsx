import React from 'react';
import { AlpineHero } from '@/components/alpine-hero';
import { PageHero } from '@/components/page-hero';
import { ResortHighlights } from '@/components/resort-highlights';
import { AccommodationShowcase } from '@/components/accommodation-showcase';
import { StatsBand } from '@/components/stats-band';
import { Testimonials } from '@/components/testimonials';
import { NewsletterCta } from '@/components/newsletter-cta';
import { SpaTreatments } from '@/components/spa-treatments';
import { CulinaryShowcase } from '@/components/culinary-showcase';
import { WineCellar } from '@/components/wine-cellar';
import { ExperienceTimeline } from '@/components/experience-timeline';
import { Header } from '@/components/header';
import { Footer } from '@/components/footer';

import type { SectionType } from '@olonjs/core';
import type { SectionComponentPropsMap } from '@/types';

export const ComponentRegistry: {
  [K in SectionType]: React.FC<SectionComponentPropsMap[K]>;
} = {
  'alpine-hero': AlpineHero,
  'page-hero': PageHero,
  'resort-highlights': ResortHighlights,
  'accommodation-showcase': AccommodationShowcase,
  'stats-band': StatsBand,
  'testimonials': Testimonials,
  'newsletter-cta': NewsletterCta,
  'spa-treatments': SpaTreatments,
  'culinary-showcase': CulinaryShowcase,
  'wine-cellar': WineCellar,
  'experience-timeline': ExperienceTimeline,
  'header': Header,
  'footer': Footer,
};

