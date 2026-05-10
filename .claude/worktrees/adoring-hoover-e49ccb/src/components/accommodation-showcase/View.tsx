// Layout: Hero=A (SPLIT 60/40), Features=A (BENTO GRID)
import React from 'react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Check } from 'lucide-react';
import type { AccommodationShowcaseData, AccommodationShowcaseSettings } from './types';

export const AccommodationShowcase: React.FC<{ data: AccommodationShowcaseData; settings: AccommodationShowcaseSettings }> = ({ data }) => (
  <section
    style={{
      '--local-bg': 'var(--background)',
      '--local-text': 'var(--foreground)',
      '--local-text-muted': 'var(--muted-foreground)',
      '--local-accent': 'var(--accent)',
      '--local-surface': 'var(--card)',
      '--local-border': 'var(--border)',
      '--local-primary': 'var(--primary)',
      '--local-primary-foreground': 'var(--primary-foreground)',
      '--local-radius-lg': 'var(--theme-radius-lg)',
      '--local-radius-md': 'var(--theme-radius-md)',
    } as React.CSSProperties}
    className="relative z-0 py-28 bg-[var(--local-bg)]"
  >
    <div className="max-w-[1200px] mx-auto px-8">
      {data.label && (
        <div className="jp-section-label inline-flex items-center gap-2 text-[0.72rem] font-bold uppercase tracking-[0.12em] text-[var(--local-accent)] mb-4" data-jp-field="label">
          <span className="w-5 h-px bg-[var(--local-primary)]" />
          {data.label}
        </div>
      )}
      
      <h2 className="font-display font-black text-[clamp(2rem,4.5vw,3.8rem)] leading-[1.05] tracking-tight text-[var(--local-text)] mb-16" data-jp-field="title">
        {data.title}
      </h2>
      
      <div className="space-y-24">
        {data.accommodations.map((accommodation, idx) => (
          <div
            key={accommodation.id || `accommodation-${idx}`}
            className={`grid grid-cols-1 lg:grid-cols-2 gap-16 items-center ${idx % 2 === 1 ? 'lg:grid-flow-col-dense' : ''}`}
            data-jp-item-id={accommodation.id || `accommodation-${idx}`}
            data-jp-item-field="accommodations"
          >
            {/* Content */}
            <div className={idx % 2 === 1 ? 'lg:col-start-2' : ''}>
              {accommodation.subtitle && (
                <Badge variant="secondary" className="mb-4 bg-[var(--local-surface)] text-[var(--local-text)] border-[var(--local-border)]">
                  {accommodation.subtitle}
                </Badge>
              )}
              
              <h3 className="font-display font-bold text-[clamp(1.5rem,3vw,2.5rem)] leading-tight tracking-tight text-[var(--local-text)] mb-6">
                {accommodation.title}
              </h3>
              
              <p className="text-[var(--local-text-muted)] text-lg leading-relaxed mb-8">
                {accommodation.description}
              </p>
              
              {accommodation.features && accommodation.features.length > 0 && (
                <ul className="space-y-3 mb-8">
                  {accommodation.features.map((feature, featureIdx) => (
                    <li key={featureIdx} className="flex items-center gap-3 text-[var(--local-text)]">
                      <Check className="w-5 h-5 text-[var(--local-primary)] flex-shrink-0" />
                      <span>{feature}</span>
                    </li>
                  ))}
                </ul>
              )}
              
              {accommodation.cta && (
                <Button
                  asChild
                  className="inline-flex items-center gap-2 px-6 py-3 rounded-[var(--local-radius-md)] bg-[var(--local-primary)] text-[var(--local-primary-foreground)] font-semibold hover:opacity-90 transition-opacity"
                >
                  <a href={accommodation.cta.href}>{accommodation.cta.label}</a>
                </Button>
              )}
            </div>
            
            {/* Image */}
            <div className={`relative ${idx % 2 === 1 ? 'lg:col-start-1' : ''}`}>
              {accommodation.image?.url && (
                <div className="relative overflow-hidden rounded-[var(--local-radius-lg)]">
                  <img 
                    src={accommodation.image.url}
                    alt={accommodation.image.alt}
                    className="w-full h-[500px] object-cover hover:scale-105 transition-transform duration-700"
                  />
                  <div className="absolute inset-0 bg-gradient-to-t from-black/20 to-transparent" />
                </div>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  </section>
);

