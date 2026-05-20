// Layout: Hero=F (MINIMAL HERO), Features=A (BENTO GRID)
import React from 'react';
import { Card, CardContent } from '@/components/ui/card';
import { Star } from 'lucide-react';
import type { TestimonialsData, TestimonialsSettings } from './types';

export const Testimonials: React.FC<{ data: TestimonialsData; settings: TestimonialsSettings }> = ({ data }) => (
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
      
      <h2 className="font-display font-black text-[clamp(2rem,4.5vw,3.8rem)] leading-[1.05] tracking-tight text-[var(--local-text)] mb-16" data-jp-field="title">
        {data.title}
      </h2>
      
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
        {data.testimonials.map((testimonial, idx) => (
          <Card
            key={testimonial.id || `testimonial-${idx}`}
            className="bg-[var(--local-surface)] border border-[var(--local-border)] rounded-[var(--local-radius-lg)] hover:shadow-lg transition-shadow duration-300"
            data-jp-item-id={testimonial.id || `testimonial-${idx}`}
            data-jp-item-field="testimonials"
          >
            <CardContent className="p-8">
              {testimonial.rating && (
                <div className="flex items-center gap-1 mb-6">
                  {Array.from({ length: testimonial.rating }).map((_, starIdx) => (
                    <Star key={starIdx} className="w-4 h-4 fill-[var(--local-accent)] text-[var(--local-accent)]" />
                  ))}
                </div>
              )}
              
              <blockquote className="text-[var(--local-text)] text-lg leading-relaxed mb-6">
                "{testimonial.quote}"
              </blockquote>
              
              <footer>
                <div className="font-display font-bold text-[var(--local-text)] mb-1">
                  {testimonial.author}
                </div>
                {testimonial.role && (
                  <div className="text-[var(--local-text-muted)] text-sm">
                    {testimonial.role}
                  </div>
                )}
                {testimonial.location && (
                  <div className="text-[var(--local-accent)] text-xs font-mono uppercase tracking-wide mt-1">
                    {testimonial.location}
                  </div>
                )}
              </footer>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  </section>
);

