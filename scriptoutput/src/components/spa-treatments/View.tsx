// Layout: Hero=F (MINIMAL HERO), Features=D (ACCORDION)
import React from 'react';
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from '@/components/ui/accordion';
import type { SpaTreatmentsData, SpaTreatmentsSettings } from './types';

export const SpaTreatments: React.FC<{ data: SpaTreatmentsData; settings: SpaTreatmentsSettings }> = ({ data }) => (
  <section
    style={{
      '--local-bg': 'var(--background)',
      '--local-text': 'var(--foreground)',
      '--local-text-muted': 'var(--muted-foreground)',
      '--local-accent': 'var(--accent)',
      '--local-primary': 'var(--primary)',
      '--local-surface': 'var(--card)',
      '--local-border': 'var(--border)',
      '--local-radius-lg': 'var(--theme-radius-lg)',
    } as React.CSSProperties}
    className="relative z-0 py-28 bg-[var(--local-bg)]"
  >
    <div className="max-w-[1000px] mx-auto px-8">
      {data.label && (
        <div className="jp-section-label inline-flex items-center gap-2 text-[0.72rem] font-bold uppercase tracking-[0.12em] text-[var(--local-accent)] mb-4" data-jp-field="label">
          <span className="w-5 h-px bg-[var(--local-primary)]" />
          {data.label}
        </div>
      )}
      
      <h2 className="font-display font-black text-[clamp(2rem,4.5vw,3.8rem)] leading-[1.05] tracking-tight text-[var(--local-text)] mb-6" data-jp-field="title">
        {data.title}
      </h2>
      
      {data.description && (
        <p className="text-[var(--local-text-muted)] text-lg leading-relaxed mb-16 max-w-[700px]" data-jp-field="description">
          {data.description}
        </p>
      )}
      
      <Accordion type="single" collapsible className="space-y-4">
        {data.treatments.map((treatment, idx) => (
          <AccordionItem
            key={treatment.id || `treatment-${idx}`}
            value={treatment.id || `treatment-${idx}`}
            className="border border-[var(--local-border)] rounded-[var(--local-radius-lg)] bg-[var(--local-surface)] overflow-hidden"
            data-jp-item-id={treatment.id || `treatment-${idx}`}
            data-jp-item-field="treatments"
          >
            <AccordionTrigger className="px-8 py-6 text-left hover:no-underline group">
              <div className="flex items-center justify-between w-full">
                <div>
                  <h3 className="font-display font-bold text-lg text-[var(--local-text)] mb-1">
                    {treatment.title}
                  </h3>
                  <div className="flex items-center gap-4 text-sm text-[var(--local-text-muted)]">
                    {treatment.duration && <span>{treatment.duration}</span>}
                    {treatment.price && (
                      <>
                        {treatment.duration && <span>•</span>}
                        <span className="font-mono text-[var(--local-accent)]">{treatment.price}</span>
                      </>
                    )}
                  </div>
                </div>
              </div>
            </AccordionTrigger>
            <AccordionContent className="px-8 pb-6">
              <p className="text-[var(--local-text-muted)] leading-relaxed">
                {treatment.description}
              </p>
            </AccordionContent>
          </AccordionItem>
        ))}
      </Accordion>
    </div>
  </section>
);

