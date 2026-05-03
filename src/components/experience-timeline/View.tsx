// Layout: Hero=F (MINIMAL HERO), Features=C (TIMELINE)
import React from 'react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Clock } from 'lucide-react';
import type { ExperienceTimelineData, ExperienceTimelineSettings } from './types';

export const ExperienceTimeline: React.FC<{ data: ExperienceTimelineData; settings: ExperienceTimelineSettings }> = ({ data }) => {
  const difficultyColors = {
    'Easy': 'text-green-400 bg-green-400/10 border-green-400/20',
    'Moderate': 'text-yellow-400 bg-yellow-400/10 border-yellow-400/20',
    'Challenging': 'text-orange-400 bg-orange-400/10 border-orange-400/20',
    'Expert': 'text-red-400 bg-red-400/10 border-red-400/20',
  };

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
                        <Badge className={`text-xs ${difficultyColors[experience.difficulty]}`}>
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
                        <a href={experience.cta.href}>{experience.cta.label}</a>
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
