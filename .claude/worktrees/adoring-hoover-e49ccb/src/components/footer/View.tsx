// Layout: Footer with brand column, contact info, and links
import React from 'react';
import { Separator } from '@/components/ui/separator';
import { Mail, MapPin, Phone } from 'lucide-react';
import type { FooterData, FooterSettings } from './types';

export const Footer: React.FC<{ data: FooterData; settings: FooterSettings }> = ({ data }) => {
  const navItems = Array.isArray(data.menu) ? data.menu : [];

  return (
    <footer
      style={{
        '--local-bg': 'var(--card)',
        '--local-text': 'var(--foreground)',
        '--local-text-muted': 'var(--muted-foreground)',
        '--local-border': 'var(--border)',
        '--local-primary': 'var(--primary)',
        '--local-accent': 'var(--accent)',
      } as React.CSSProperties}
      className="relative z-0 border-t border-[var(--local-border)] bg-[var(--local-bg)] py-20"
    >
      <div className="max-w-[1200px] mx-auto px-8">
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-12 mb-12">
          {/* Brand Column */}
          <div className="lg:col-span-2">
            <div className="flex items-baseline gap-2 mb-4">
              <h3
                className="font-wordmark text-2xl text-[var(--local-text)]"
                data-jp-field="brandText"
              >
                {data.brandText}
              </h3>
              {data.brandHighlight && (
                <span className="font-mono text-[0.72rem] uppercase tracking-[0.24em] text-[var(--local-primary)]" data-jp-field="brandHighlight">
                  {data.brandHighlight}
                </span>
              )}
            </div>
            
            {data.tagline && (
              <p className="text-[var(--local-text-muted)] text-lg leading-relaxed mb-6" data-jp-field="tagline">
                {data.tagline}
              </p>
            )}
          </div>
          
          {/* Contact Info */}
          <div>
            <h3 className="font-display font-bold text-[var(--local-text)] text-lg mb-6">Contact</h3>
            <div className="space-y-4">
              {data.address && (
                <div className="flex items-start gap-3">
                  <MapPin className="w-4 h-4 text-[var(--local-accent)] mt-1 flex-shrink-0" />
                  <address className="text-[var(--local-text-muted)] text-sm leading-relaxed not-italic" data-jp-field="address">
                    {data.address}
                  </address>
                </div>
              )}
              
              {data.phone && (
                <div className="flex items-center gap-3">
                  <Phone className="w-4 h-4 text-[var(--local-accent)]" />
                  <a href={`tel:${data.phone}`} className="text-[var(--local-text-muted)] text-sm hover:text-[var(--local-accent)] transition" data-jp-field="phone">
                    {data.phone}
                  </a>
                </div>
              )}
              
              {data.email && (
                <div className="flex items-center gap-3">
                  <Mail className="w-4 h-4 text-[var(--local-accent)]" />
                  <a href={`mailto:${data.email}`} className="text-[var(--local-text-muted)] text-sm hover:text-[var(--local-accent)] transition" data-jp-field="email">
                    {data.email}
                  </a>
                </div>
              )}
            </div>
          </div>
          
          {/* Links */}
          <div>
            <h3 className="font-display font-bold text-[var(--local-text)] text-lg mb-6">Links</h3>
            <nav className="space-y-3">
              {navItems.map((item, idx) => (
                <a
                  key={item.href + '-footer-' + idx}
                  href={item.href}
                  className="block text-[var(--local-text-muted)] text-sm hover:text-[var(--local-accent)] transition"
                  data-jp-item-id={`footer-link-${idx}`}
                  data-jp-item-field="menu"
                >
                  {item.label}
                </a>
              ))}
            </nav>
          </div>
        </div>
        
        <Separator className="bg-[var(--local-border)] mb-8" />
        
        <div className="text-center">
          <p className="text-[var(--local-text-muted)] text-sm" data-jp-field="copyright">
            {data.copyright}
          </p>
        </div>
      </div>
    </footer>
  );
};

