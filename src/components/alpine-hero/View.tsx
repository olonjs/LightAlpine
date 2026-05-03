// Layout: Hero=C (FULLSCREEN CINEMATIC), Features=A (BENTO GRID)
// IDAC v1.2 + ECIP §5.5 / JAP: nested targets use ancestor data-jp-item-id + data-jp-item-field, leaf scalars use data-jp-field (see @olonjs/core ti() path build).
import React from 'react';
import { Button } from '@/components/ui/button';
import { ChevronDown } from 'lucide-react';
import type { AlpineHeroData, AlpineHeroSettings } from './types';

const BG_ITEM_ID = 'alpine-hero-backgroundImage';

export const AlpineHero: React.FC<{ data: AlpineHeroData; settings: AlpineHeroSettings }> = ({ data }) => {
  const bg = data.backgroundImage;
  const primaryId = data.primaryCta.id ?? 'alpine-primary-cta';
  const secondaryId = data.secondaryCta?.id ?? 'alpine-secondary-cta';

  return (
    <section
      style={
        {
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
        } as React.CSSProperties
      }
      className="relative z-0 flex min-h-screen items-center justify-center overflow-hidden bg-[var(--local-bg)]"
    >
      <div className="absolute inset-0">
        {bg?.url ? (
          <div
            className="absolute inset-0"
            data-jp-item-field="backgroundImage"
            data-jp-item-id={BG_ITEM_ID}
          >
            <img
              src={bg.url}
              alt={bg.alt ?? ''}
              className="h-full w-full object-cover"
              data-jp-field="url"
            />
            <span className="sr-only" data-jp-field="alt">
              {bg.alt ?? ''}
            </span>
          </div>
        ) : null}
        <div className="absolute inset-0 bg-gradient-to-t from-[var(--local-bg)]/95 via-[var(--local-bg)]/40 to-[var(--local-bg)]/20" />
      </div>

      <div className="pointer-events-none absolute left-1/2 top-0 h-[650px] w-[1100px] -translate-x-1/2 bg-[radial-gradient(ellipse_at_50%_0%,var(--local-accent-soft),transparent_65%)]" />

      <div className="relative z-10 mx-auto max-w-[900px] px-8 text-center">
        {data.badge ? (
          <div className="jp-animate-in mb-8 inline-flex items-center gap-2 rounded-full border border-[var(--local-border)] bg-[var(--local-accent-soft)] px-4 py-1.5 font-mono text-[0.70rem] font-semibold uppercase tracking-widest text-[var(--local-accent)]">
            <span className="jp-pulse-dot h-1.5 w-1.5 rounded-full bg-[var(--local-primary)]" aria-hidden />
            <span data-jp-field="badge">{data.badge}</span>
          </div>
        ) : null}

        <h1 className="jp-animate-in jp-d1 mb-6 font-display text-[clamp(3rem,6vw,5.5rem)] font-black leading-[1.0] tracking-tight text-[var(--local-text)]">
          <span data-jp-field="title">{data.title}</span>
          {data.titleHighlight ? (
            <>
              {' '}
              <em
                className="not-italic bg-gradient-to-br from-[var(--local-accent)] to-[var(--local-primary)] bg-clip-text text-transparent"
                data-jp-field="titleHighlight"
              >
                {data.titleHighlight}
              </em>
            </>
          ) : null}
        </h1>

        <p
          className="jp-animate-in jp-d2 mx-auto mb-10 max-w-[600px] text-lg leading-relaxed text-[var(--local-text-muted)]"
          data-jp-field="description"
        >
          {data.description}
        </p>

        <div className="jp-animate-in jp-d3 flex flex-col items-center justify-center gap-4 sm:flex-row">
          <div data-jp-item-field="primaryCta" data-jp-item-id={primaryId}>
            <Button
              asChild
              className="inline-flex items-center gap-2 rounded-[var(--local-radius-md)] bg-[var(--local-primary)] px-8 py-4 font-semibold text-[var(--local-primary-foreground)] transition-opacity hover:opacity-90"
            >
              <a href={data.primaryCta.href} data-jp-field="href">
                <span data-jp-field="label">{data.primaryCta.label}</span>
              </a>
            </Button>
            <span className="sr-only" data-jp-field="variant">
              {data.primaryCta.variant}
            </span>
          </div>

          {data.secondaryCta ? (
            <div data-jp-item-field="secondaryCta" data-jp-item-id={secondaryId}>
              <Button
                asChild
                variant="outline"
                className="inline-flex items-center gap-2 rounded-[var(--local-radius-md)] border border-[var(--local-border)] px-8 py-4 font-semibold text-[var(--local-text)] transition hover:border-[var(--local-accent)]"
              >
                <a href={data.secondaryCta.href} data-jp-field="href">
                  <span data-jp-field="label">{data.secondaryCta.label}</span>
                </a>
              </Button>
              <span className="sr-only" data-jp-field="variant">
                {data.secondaryCta.variant}
              </span>
            </div>
          ) : null}
        </div>
      </div>

      <div className="jp-animate-in jp-d4 absolute bottom-8 left-1/2 flex -translate-x-1/2 flex-col items-center gap-2 text-[var(--local-text-muted)]">
        <span className="font-mono text-xs uppercase tracking-wide">Scroll</span>
        <ChevronDown className="h-4 w-4 animate-bounce" aria-hidden />
      </div>
    </section>
  );
};
