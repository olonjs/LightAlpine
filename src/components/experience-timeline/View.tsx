// Layout: Hero=F (MINIMAL HERO), Features=C (TIMELINE)
import React from 'react';
import { Link } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Clock } from 'lucide-react';
import { isInAppPathHref } from '@/lib/isInAppPathHref';
import type { ExperienceTimelineData, ExperienceTimelineSettings } from './types';

const DIFFICULTY_CLASS: Record<string, string> = {
  Easy: 'text-[var(--local-difficulty-easy-text)] bg-[var(--local-difficulty-easy-bg)] border-[var(--local-difficulty-easy-border)]',
  Moderate: 'text-[var(--local-difficulty-moderate-text)] bg-[var(--local-difficulty-moderate-bg)] border-[var(--local-difficulty-moderate-border)]',
  Challenging: 'text-[var(--local-difficulty-challenging-text)] bg-[var(--local-difficulty-challenging-bg)] border-[var(--local-difficulty-challenging-border)]',
  Expert: 'text-[var(--local-difficulty-expert-text)] bg-[var(--local-difficulty-expert-bg)] border-[var(--local-difficulty-expert-border)]',
};

export const ExperienceTimeline: React.FC<{ data: ExperienceTimelineData; settings: ExperienceTimelineSettings }> = ({ data }) => {
  return (
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
        '--local-difficulty-easy-bg':        'var(--semantic-difficulty-easy-bg)',
        '--local-difficulty-easy-border':    'var(--semantic-difficulty-easy-border)',
        '--local-difficulty-easy-text':      'var(--semantic-difficulty-easy-text)',
        '--local-difficulty-moderate-bg':    'var(--semantic-difficulty-moderate-bg)',
        '--local-difficulty-moderate-border': 'var(--semantic-difficulty-moderate-border)',
        '--local-difficulty-moderate-text':  'var(--semantic-difficulty-moderate-text)',
        '--local-difficulty-challenging-bg':    'var(--semantic-difficulty-challenging-bg)',
        '--local-difficulty-challenging-border': 'var(--semantic-difficulty-challenging-border)',
        '--local-difficulty-challenging-text':  'var(--semantic-difficulty-challenging-text)',
        '--local-difficulty-expert-bg':    'var(--semantic-difficulty-expert-bg)',
        '--local-difficulty-expert-border': 'var(--semantic-difficulty-expert-border)',
        '--local-difficulty-expert-text':  'var(--semantic-difficulty-expert-text)',
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
        
        {/* Timeline */}
        <div className="relative">
          {/* Timeline Line */}
          <div className="absolute left-8 top-0 bottom-0 w-px bg-gradient-to-b from-[var(--local-primary)] via-[var(--local-accent)] to-[var(--local-primary)]" />
          
          <div className="space-y-16">
            {data.experiences.map((experience, idx) => (
              <div
                key={experience.id || `experience-${idx}`}
                className={`relative flex ${idx % 2 === 0 ? 'lg:flex-row' : 'lg:flex-row-reverse'} flex-col gap-12 items-center`}
                data-jp-item-id={experience.id || `experience-${idx}`}
                data-jp-item-field="experiences"
              >
                {/* Timeline Dot */}
                <div className="absolute left-8 lg:left-8 w-4 h-4 bg-[var(--local-primary)] rounded-full border-4 border-[var(--local-bg)] z-10" />
                
                {/* Content */}
                <div className={`flex-1 ${idx % 2 === 0 ? 'lg:pr-16 lg:pl-24' : 'lg:pl-16 lg:pr-24'} pl-24`}>
                  <div className="bg-[var(--local-surface)] border border-[var(--local-border)] rounded-[var(--local-radius-lg)] p-8">
                    <div className="flex items-center gap-3 mb-4">
                      {experience.season && (
                        <Badge variant="secondary" className="bg-[var(--local-accent)]/10 text-[var(--local-accent)] border-[var(--local-accent)]/20">
                          {experience.season}
                        </Badge>
                      )}
                      {experience.difficulty && (
                        <Badge className={`text-xs ${DIFFICULTY_CLASS[experience.difficulty] ?? ''}`}>
                          {experience.difficulty}
                        </Badge>
                      )}
                    </div>
                    
                    <h3 className="font-display font-bold text-[1.5rem] leading-tight tracking-tight text-[var(--local-text)] mb-3">
                      {experience.title}
                    </h3>
                    
                    {experience.duration && (
                      <div className="flex items-center gap-2 text-[var(--local-text-muted)] mb-4">
                        <Clock className="w-4 h-4" />
                        <span className="text-sm">{experience.duration}</span>
                      </div>
                    )}
                    
                    <p className="text-[var(--local-text-muted)] leading-relaxed mb-6">
                      {experience.description}
                    </p>
                    
                    {experience.cta && (
                      <Button
                        asChild
                        variant="outline"
                        className="rounded-[var(--local-radius-md)] border-[var(--local-border)] text-[var(--local-text)] hover:border-[var(--local-accent)] transition"
                      >
                        {isInAppPathHref(experience.cta.href) ? (
                          <Link to={experience.cta.href} viewTransition>{experience.cta.label}</Link>
                        ) : (
                          <a href={experience.cta.href}>{experience.cta.label}</a>
                        )}
                      </Button>
                    )}
                  </div>
                </div>
                
                {/* Image */}
                <div className={`flex-1 ${idx % 2 === 0 ? 'lg:pl-16' : 'lg:pr-16'}`}>
                  {experience.image?.url && (
                    <div className="relative overflow-hidden rounded-[var(--local-radius-lg)]">
                      <img 
                        src={experience.image.url}
                        alt={experience.image.alt}
                        className="w-full h-[300px] object-cover hover:scale-105 transition-transform duration-700"
                      />
                    </div>
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
};
