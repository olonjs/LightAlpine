// Layout: Hero=C (FULLSCREEN CINEMATIC), Features=A (BENTO GRID)
import React from 'react';
import { Card, CardContent } from '@/components/ui/card';
import type { ResortHighlightsData, ResortHighlightsSettings } from './types';

export const ResortHighlights: React.FC<{ data: ResortHighlightsData; settings: ResortHighlightsSettings }> = ({ data }) => (
  <section
    style={{
      '--local-bg': 'var(--background)',
      '--local-text': 'var(--foreground)',
      '--local-text-muted': 'var(--muted-foreground)',
      '--local-accent': 'var(--accent)',
      '--local-surface': 'var(--card)',
      '--local-border': 'var(--border)',
      '--local-radius-lg': 'var(--theme-radius-lg)',
      '--local-primary': 'var(--primary)',
      '--local-text-on-image': 'var(--semantic-overlay-text-on-image)',
      '--local-text-on-image-muted': 'var(--semantic-overlay-text-on-image-muted)',
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
      
      {/* Bento Grid Layout */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 auto-rows-[300px]">
        {data.highlights.map((highlight, idx) => (
          <Card
            key={highlight.id || `highlight-${idx}`}
            className={`group relative overflow-hidden bg-[var(--local-surface)] border border-[var(--local-border)] rounded-[var(--local-radius-lg)] hover:shadow-2xl transition-all duration-500 ${
              idx === 0 ? 'lg:col-span-2 lg:row-span-1' : 
              idx === 1 ? 'lg:row-span-2' : 
              idx === 3 ? 'md:col-span-2 lg:col-span-1' : ''
            }`}
            data-jp-item-id={highlight.id || `highlight-${idx}`}
            data-jp-item-field="highlights"
          >
            {highlight.image?.url && (
              <div className="absolute inset-0">
                <img 
                  src={highlight.image.url}
                  alt={highlight.image.alt}
                  className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-700"
                />
                <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-black/20 to-transparent" />
              </div>
            )}
            
            <CardContent className="relative z-10 h-full flex flex-col justify-end p-8">
              {highlight.category && (
                <div className="inline-flex items-center px-3 py-1 bg-[var(--local-accent)]/20 border border-[var(--local-accent)]/30 rounded-full text-xs font-mono uppercase tracking-wide text-[var(--local-accent)] mb-4 self-start">
                  {highlight.category}
                </div>
              )}
              
              <h3 className="font-display font-bold text-xl leading-tight tracking-tight text-[var(--local-text-on-image)] mb-3">
                {highlight.title}
              </h3>

              <p className="text-[var(--local-text-on-image-muted)] text-sm leading-relaxed">
                {highlight.description}
              </p>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  </section>
);

