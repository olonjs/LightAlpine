// Layout: Hero=A (SPLIT 60/40), Features=A (BENTO GRID)
import React from 'react';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import type { CulinaryShowcaseData, CulinaryShowcaseSettings } from './types';

export const CulinaryShowcase: React.FC<{ data: CulinaryShowcaseData; settings: CulinaryShowcaseSettings }> = ({ data }) => (
  <section
    style={{
      '--local-bg': 'var(--background)',
      '--local-text': 'var(--foreground)',
      '--local-text-muted': 'var(--muted-foreground)',
      '--local-accent': 'var(--accent)',
      '--local-surface': 'var(--card)',
      '--local-border': 'var(--border)',
      '--local-primary': 'var(--primary)',
      '--local-radius-lg': 'var(--theme-radius-lg)',
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
      
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-16 items-center mb-16">
        <div>
          <h2 className="font-display font-black text-[clamp(2rem,4.5vw,3.8rem)] leading-[1.05] tracking-tight text-[var(--local-text)] mb-6" data-jp-field="title">
            {data.title}
          </h2>
          
          {data.description && (
            <p className="text-[var(--local-text-muted)] text-lg leading-relaxed" data-jp-field="description">
              {data.description}
            </p>
          )}
        </div>
        
        {data.items[0]?.image?.url && (
          <div className="relative">
            <img 
              src={data.items[0].image.url}
              alt={data.items[0].image.alt}
              className="w-full h-[400px] object-cover rounded-[var(--local-radius-lg)]"
            />
          </div>
        )}
      </div>
      
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
        {data.items.map((item, idx) => (
          <Card
            key={item.id || `culinary-${idx}`}
            className="group relative overflow-hidden bg-[var(--local-surface)] border border-[var(--local-border)] rounded-[var(--local-radius-lg)] hover:shadow-lg transition-all duration-300"
            data-jp-item-id={item.id || `culinary-${idx}`}
            data-jp-item-field="items"
          >
            {item.image?.url && (
              <div className="aspect-[4/3] overflow-hidden">
                <img 
                  src={item.image.url}
                  alt={item.image.alt}
                  className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
                />
              </div>
            )}
            
            <CardContent className="p-6">
              {item.badge && (
                <Badge variant="secondary" className="mb-3 bg-[var(--local-accent)]/10 text-[var(--local-accent)] border-[var(--local-accent)]/20">
                  {item.badge}
                </Badge>
              )}
              
              <h3 className="font-display font-bold text-[1.2rem] leading-tight tracking-tight text-[var(--local-text)] mb-3">
                {item.title}
              </h3>
              
              <p className="text-[var(--local-text-muted)] leading-relaxed">
                {item.description}
              </p>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  </section>
);

