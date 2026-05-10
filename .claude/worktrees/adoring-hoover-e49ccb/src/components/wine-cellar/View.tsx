// Layout: Hero=A (SPLIT 60/40), Features=B (HORIZONTAL SCROLL)
import React from 'react';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { ScrollArea } from '@/components/ui/scroll-area';
import type { WineCellarData, WineCellarSettings } from './types';

const WINE_TYPE_CLASS: Record<string, string> = {
  red: 'text-[var(--local-wine-red-text)] bg-[var(--local-wine-red-bg)] border-[var(--local-wine-red-border)]',
  white: 'text-[var(--local-wine-white-text)] bg-[var(--local-wine-white-bg)] border-[var(--local-wine-white-border)]',
  sparkling: 'text-[var(--local-wine-sparkling-text)] bg-[var(--local-wine-sparkling-bg)] border-[var(--local-wine-sparkling-border)]',
  dessert: 'text-[var(--local-wine-dessert-text)] bg-[var(--local-wine-dessert-bg)] border-[var(--local-wine-dessert-border)]',
};

export const WineCellar: React.FC<{ data: WineCellarData; settings: WineCellarSettings }> = ({ data }) => {
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
        '--local-radius-lg': 'var(--theme-radius-lg)',
        '--local-wine-red-bg':        'var(--semantic-wine-red-bg)',
        '--local-wine-red-border':    'var(--semantic-wine-red-border)',
        '--local-wine-red-text':      'var(--semantic-wine-red-text)',
        '--local-wine-white-bg':      'var(--semantic-wine-white-bg)',
        '--local-wine-white-border':  'var(--semantic-wine-white-border)',
        '--local-wine-white-text':    'var(--semantic-wine-white-text)',
        '--local-wine-sparkling-bg':     'var(--semantic-wine-sparkling-bg)',
        '--local-wine-sparkling-border': 'var(--semantic-wine-sparkling-border)',
        '--local-wine-sparkling-text':   'var(--semantic-wine-sparkling-text)',
        '--local-wine-dessert-bg':    'var(--semantic-wine-dessert-bg)',
        '--local-wine-dessert-border': 'var(--semantic-wine-dessert-border)',
        '--local-wine-dessert-text':  'var(--semantic-wine-dessert-text)',
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
          
          {data.image?.url && (
            <div className="relative">
              <img 
                src={data.image.url}
                alt={data.image.alt}
                className="w-full h-[400px] object-cover rounded-[var(--local-radius-lg)]"
              />
            </div>
          )}
        </div>
        
        {/* Horizontal Scroll Wine List */}
        <ScrollArea className="w-full whitespace-nowrap">
          <div className="flex gap-6 pb-4">
            {data.wines.map((wine, idx) => (
              <Card
                key={wine.id || `wine-${idx}`}
                className="flex-shrink-0 w-[300px] bg-[var(--local-surface)] border border-[var(--local-border)] rounded-[var(--local-radius-lg)] hover:shadow-lg transition-shadow duration-300"
                data-jp-item-id={wine.id || `wine-${idx}`}
                data-jp-item-field="wines"
              >
                <CardContent className="p-6 whitespace-normal">
                  <div className="flex items-start justify-between mb-3">
                    <h3 className="font-display font-bold text-lg text-[var(--local-text)]">
                      {wine.name}
                    </h3>
                    {wine.type && (
                      <Badge className={`text-xs ${WINE_TYPE_CLASS[wine.type] || 'text-[var(--local-accent)] bg-[var(--local-accent)]/10 border-[var(--local-accent)]/20'}`}>
                        {wine.type}
                      </Badge>
                    )}
                  </div>
                  
                  <div className="flex items-center gap-2 text-sm text-[var(--local-text-muted)] mb-3">
                    {wine.vintage && <span className="font-mono">{wine.vintage}</span>}
                    {wine.vintage && wine.region && <span>•</span>}
                    {wine.region && <span>{wine.region}</span>}
                  </div>
                  
                  <p className="text-[var(--local-text-muted)] text-sm leading-relaxed">
                    {wine.description}
                  </p>
                </CardContent>
              </Card>
            ))}
          </div>
        </ScrollArea>
      </div>
    </section>
  );
};

