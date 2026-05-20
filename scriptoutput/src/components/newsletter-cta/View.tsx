// Layout: Hero=F (MINIMAL HERO), Features=F (MINIMAL HERO)
import React from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import type { NewsletterCtaData, NewsletterCtaSettings } from './types';

export const NewsletterCta: React.FC<{ data: NewsletterCtaData; settings: NewsletterCtaSettings }> = ({ data }) => (
  <section
    style={{
      '--local-bg': 'color-mix(in oklch, var(--accent) 8%, var(--background))',
      '--local-text': 'var(--foreground)',
      '--local-text-muted': 'var(--muted-foreground)',
      '--local-accent': 'var(--accent)',
      '--local-primary': 'var(--primary)',
      '--local-primary-foreground': 'var(--primary-foreground)',
      '--local-border': 'var(--border)',
      '--local-surface': 'var(--card)',
      '--local-radius-md': 'var(--theme-radius-md)',
    } as React.CSSProperties}
    className="relative z-0 py-28 bg-[var(--local-bg)]"
  >
    <div className="max-w-[800px] mx-auto px-8 text-center">
      <h2 className="font-display font-black text-[clamp(3rem,7vw,6.5rem)] leading-[1.0] tracking-tight text-[var(--local-text)] mb-6" data-jp-field="title">
        {data.title}
      </h2>
      
      {data.description && (
        <p className="text-[var(--local-text-muted)] text-lg leading-relaxed mb-12 max-w-[600px] mx-auto" data-jp-field="description">
          {data.description}
        </p>
      )}
      
      <form className="flex flex-col sm:flex-row gap-4 max-w-[500px] mx-auto" onSubmit={(e) => e.preventDefault()}>
        <Input
          type="email"
          placeholder={data.placeholder || "Enter your email"}
          className="flex-1 bg-[var(--local-surface)] border-[var(--local-border)] text-[var(--local-text)] rounded-[var(--local-radius-md)]"
        />
        <Button
          type="submit"
          className="px-8 py-2 rounded-[var(--local-radius-md)] bg-[var(--local-primary)] text-[var(--local-primary-foreground)] font-semibold hover:opacity-90 transition-opacity"
        >
          {data.cta.label}
        </Button>
      </form>
    </div>
  </section>
);

