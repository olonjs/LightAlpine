// Layout: Hero=F (MINIMAL HERO), Features=A (BENTO GRID)
import React from 'react';
import type { StatsBandData, StatsBandSettings } from './types';

export const StatsBand: React.FC<{ data: StatsBandData; settings: StatsBandSettings }> = ({ data }) => (
  <section
    style={{
      '--local-bg': 'color-mix(in oklch, var(--card) 50%, var(--background))',
      '--local-text': 'var(--foreground)',
      '--local-text-muted': 'var(--muted-foreground)',
      '--local-accent': 'var(--accent)',
      '--local-border': 'var(--border)',
      '--local-primary': 'var(--primary)',
    } as React.CSSProperties}
    className="relative z-0 py-20 bg-[var(--local-bg)] border-y border-[var(--local-border)]"
  >
    <div className="max-w-[1200px] mx-auto px-8">
      {data.title && (
        <h2 className="font-display font-bold text-center text-[var(--local-text)] text-2xl mb-12" data-jp-field="title">
          {data.title}
        </h2>
      )}
      
      <div className="grid grid-cols-2 md:grid-cols-4 gap-8">
        {data.stats.map((stat, idx) => (
          <div
            key={stat.id || `stat-${idx}`}
            className="text-center"
            data-jp-item-id={stat.id || `stat-${idx}`}
            data-jp-item-field="stats"
          >
            <div className="font-display font-black text-[clamp(2rem,4vw,3.5rem)] leading-none text-[var(--local-primary)] mb-2">
              {stat.number}
              {stat.suffix && <span className="text-[var(--local-accent)]">{stat.suffix}</span>}
            </div>
            <div className="text-[var(--local-text-muted)] text-sm uppercase tracking-wide font-mono">
              {stat.label}
            </div>
          </div>
        ))}
      </div>
    </div>
  </section>
);

