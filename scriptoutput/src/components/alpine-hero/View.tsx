// Layout: Hero=C (FULLSCREEN CINEMATIC), Features=A (BENTO GRID)
import React from 'react';
import { Button } from '@/components/ui/button';
import { ChevronDown } from 'lucide-react';
import type { AlpineHeroData, AlpineHeroSettings } from './types';

export const AlpineHero: React.FC<{ data: AlpineHeroData; settings: AlpineHeroSettings }> = ({ data }) => (
  <section
    style={{
      '--local-bg': 'var(--background)',
      '--local-text': 'var(--foreground)',
      '--local-text-muted': 'var(--muted-foreground)',
      '--local-primary': 'var(--primary)',
      '--local-primary-foreground': 'var(--primary-foreground)',
      '--local-accent': 'var(--accent)',
      '--local-accent-soft': 'color-mix(in oklch, var(--accent) 10%, transparent)',
      '--local-border': 'var(--border)',
      '--local-radius-md': 'var(--theme-radius-md)',
      '--local-radius-lg': 'var(--theme-radius-lg)',
    } as React.CSSProperties}
    className="relative z-0 min-h-screen flex items-center justify-center bg-[var(--local-bg)] overflow-hidden"
  >
    {/* Cinematic Background */}
    <div className="absolute inset-0">
      <img 
        src="https://images.unsplash.com/photo-1551524164-687a55dd1126?w=2000&q=90"
        alt="Dramatic view of snow-capped Dolomites peaks at golden hour with luxury alpine resort nestled in the valley"
        className="w-full h-full object-cover"
      />
      <div className="absolute inset-0 bg-gradient-to-t from-[var(--local-bg)]/95 via-[var(--local-bg)]/40 to-[var(--local-bg)]/20" />
    </div>

    {/* Decorative Elements */}
    <div className="absolute top-0 left-1/2 -translate-x-1/2 w-[1100px] h-[650px] bg-[radial-gradient(ellipse_at_50%_0%,var(--local-accent-soft),transparent_65%)] pointer-events-none" />
    
    {/* Content */}
    <div className="relative z-10 max-w-[900px] mx-auto px-8 text-center">
      {data.badge && (
        <div className="inline-flex items-center gap-2 bg-[var(--local-accent-soft)] border border-[var(--local-border)] px-4 py-1.5 rounded-full text-[0.70rem] font-mono font-semibold text-[var(--local-accent)] tracking-widest uppercase mb-8 jp-animate-in" data-jp-field="badge">
          <span className="w-1.5 h-1.5 rounded-full bg-[var(--local-primary)] jp-pulse-dot" />
          {data.badge}
        </div>
      )}
      
      <h1 className="font-display font-black text-[clamp(3rem,6vw,5.5rem)] leading-[1.0] tracking-tight text-[var(--local-text)] mb-6 jp-animate-in jp-d1" data-jp-field="title">
        {data.title}
        {data.titleHighlight && (
          <> <em className="not-italic bg-gradient-to-br from-[var(--local-accent)] to-[var(--local-primary)] bg-clip-text text-transparent" data-jp-field="titleHighlight">
            {data.titleHighlight}
          </em></>
        )}
      </h1>
      
      <p className="text-[var(--local-text-muted)] text-lg leading-relaxed max-w-[600px] mx-auto mb-10 jp-animate-in jp-d2" data-jp-field="description">
        {data.description}
      </p>
      
      <div className="flex flex-col sm:flex-row gap-4 justify-center items-center jp-animate-in jp-d3">
        <Button
          asChild
          className="inline-flex items-center gap-2 px-8 py-4 rounded-[var(--local-radius-md)] bg-[var(--local-primary)] text-[var(--local-primary-foreground)] font-semibold hover:opacity-90 transition-opacity"
        >
          <a href={data.primaryCta.href}>{data.primaryCta.label}</a>
        </Button>
        
        {data.secondaryCta && (
          <Button
            asChild
            variant="outline"
            className="inline-flex items-center gap-2 px-8 py-4 rounded-[var(--local-radius-md)] border border-[var(--local-border)] text-[var(--local-text)] font-semibold hover:border-[var(--local-accent)] transition"
          >
            <a href={data.secondaryCta.href}>{data.secondaryCta.label}</a>
          </Button>
        )}
      </div>
    </div>
    
    {/* Scroll Indicator */}
    <div className="absolute bottom-8 left-1/2 -translate-x-1/2 flex flex-col items-center gap-2 text-[var(--local-text-muted)] jp-animate-in jp-d4">
      <span className="text-xs uppercase tracking-wide font-mono">Scroll</span>
      <ChevronDown className="w-4 h-4 animate-bounce" />
    </div>
  </section>
);
