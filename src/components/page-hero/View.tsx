import React from 'react';
import { Link } from 'react-router-dom';
import { isInAppPathHref } from '@/lib/isInAppPathHref';
import type { PageHeroData, PageHeroSettings } from './types';

export const PageHero: React.FC<{ data: PageHeroData; settings: PageHeroSettings }> = ({ data }) => (
  <section
    style={{
      '--local-bg': 'var(--background)',
      '--local-text': 'var(--foreground)',
      '--local-text-muted': 'var(--muted-foreground)',
      '--local-accent': 'var(--accent)',
      '--local-border': 'var(--border)',
    } as React.CSSProperties}
    className="relative z-0 py-24 bg-[var(--local-bg)]"
  >
    <div className="max-w-[1200px] mx-auto px-8">
      {data.breadcrumbs && data.breadcrumbs.length > 0 && (
        <nav className="flex items-center gap-2 text-sm text-[var(--local-text-muted)] mb-8">
          {data.breadcrumbs.map((crumb, idx) => (
            <React.Fragment key={crumb.id || `crumb-${idx}`}>
              {isInAppPathHref(crumb.href) ? (
                <Link to={crumb.href} viewTransition className="hover:text-[var(--local-accent)] transition">
                  {crumb.label}
                </Link>
              ) : (
                <a href={crumb.href} className="hover:text-[var(--local-accent)] transition">
                  {crumb.label}
                </a>
              )}
              {idx < (data.breadcrumbs?.length ?? 0) - 1 && <span>/</span>}
            </React.Fragment>
          ))}
        </nav>
      )}
      
      <h1 className="font-display font-black text-[clamp(2rem,4.5vw,3.8rem)] leading-[1.05] tracking-tight text-[var(--local-text)] mb-6" data-jp-field="title">
        {data.title}
      </h1>
      
      {data.description && (
        <p className="text-[var(--local-text-muted)] text-lg leading-relaxed max-w-[700px]" data-jp-field="description">
          {data.description}
        </p>
      )}
    </div>
  </section>
);
