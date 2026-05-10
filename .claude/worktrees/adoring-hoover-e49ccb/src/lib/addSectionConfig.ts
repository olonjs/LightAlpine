import type { AddSectionConfig } from '@olonjs/core';

const addableSectionTypes = [
  'alpine-hero',
  'page-hero',
  'resort-highlights',
  'accommodation-showcase',
  'stats-band',
  'testimonials',
  'newsletter-cta',
  'spa-treatments',
  'culinary-showcase',
  'wine-cellar',
  'experience-timeline'
] as const;

const sectionTypeLabels: Record<string, string> = {
  'alpine-hero': 'Alpine Hero',
  'page-hero': 'Page Hero',
  'resort-highlights': 'Resort Highlights',
  'accommodation-showcase': 'Accommodation Showcase',
  'stats-band': 'Statistics Band',
  'testimonials': 'Testimonials',
  'newsletter-cta': 'Newsletter CTA',
  'spa-treatments': 'Spa Treatments',
  'culinary-showcase': 'Culinary Showcase',
  'wine-cellar': 'Wine Cellar',
  'experience-timeline': 'Experience Timeline',
};

function getDefaultSectionData(type: string): Record<string, unknown> {
  switch (type) {
    case 'alpine-hero':
      return {
        backgroundImage: {
          url: 'https://images.unsplash.com/photo-1551524164-687a55dd1126?w=2000&q=90',
          alt: 'Dramatic view of snow-capped Dolomites peaks at golden hour with luxury alpine resort nestled in the valley',
        },
        badge: 'Luxury Alpine Retreat',
        title: 'Experience Alpine Luxury',
        description: 'Discover unparalleled comfort in the heart of the Dolomites.',
        primaryCta: { id: 'cta-1', label: 'Book Now', href: '/book', variant: 'primary' },
        secondaryCta: { id: 'cta-2', label: 'Explore', href: '/accommodations', variant: 'secondary' },
      };
    case 'page-hero':
      return {
        title: 'Page Title',
        description: 'Page description goes here.',
        breadcrumbs: []
      };
    case 'resort-highlights':
      return {
        label: 'Highlights',
        title: 'Resort Features',
        highlights: []
      };
    case 'accommodation-showcase':
      return {
        label: 'Accommodations',
        title: 'Luxury Suites',
        accommodations: []
      };
    case 'stats-band':
      return {
        title: 'By the Numbers',
        stats: []
      };
    case 'testimonials':
      return {
        label: 'Testimonials',
        title: 'Guest Reviews',
        testimonials: []
      };
    case 'newsletter-cta':
      return {
        title: 'Stay Updated',
        description: 'Subscribe to our newsletter for exclusive offers.',
        placeholder: 'Enter your email',
        cta: { id: 'newsletter-cta', label: 'Subscribe', href: '#', variant: 'primary' }
      };
    case 'spa-treatments':
      return {
        label: 'Wellness',
        title: 'Spa Treatments',
        description: 'Rejuvenate with our world-class spa services.',
        treatments: []
      };
    case 'culinary-showcase':
      return {
        label: 'Culinary',
        title: 'Fine Dining Experience',
        description: 'Award-winning cuisine in the heart of the Alps.',
        items: []
      };
    case 'wine-cellar':
      return {
        label: 'Wine',
        title: 'Alpine Wine Cellar',
        description: 'Curated selection of regional and international wines.',
        wines: []
      };
    case 'experience-timeline':
      return {
        label: 'Activities',
        title: 'Alpine Experiences',
        description: 'From skiing to hiking, discover the best of the Dolomites.',
        experiences: []
      };
    default:
      return {};
  }
}

export const addSectionConfig: AddSectionConfig = {
  addableSectionTypes: [...addableSectionTypes],
  sectionTypeLabels,
  getDefaultSectionData,
};

