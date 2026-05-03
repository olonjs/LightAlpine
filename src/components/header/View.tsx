import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
  type Dispatch,
  type SetStateAction,
} from 'react';
import { Link, useLocation } from 'react-router-dom';
import { Menu, Moon, Sun, X } from 'lucide-react';
import {
  AnimatePresence,
  motion,
  useMotionValue,
  useMotionValueEvent,
  useReducedMotion,
  useScroll,
  useSpring,
  type Variants,
} from 'motion/react';
import useMeasure from 'react-use-measure';
import { cn } from '@/lib/utils';
import { Button } from '@/components/ui/button';
import { useTheme } from '@/components/ThemeProvider';
import type { HeaderData, HeaderSettings } from './types';

const HEADER_HEIGHT_CSS_VAR = '--jp-fixed-shell-header-height';

function normalizePath(path: string): string {
  const t = path.replace(/\/+$/, '') || '/';
  return t;
}

function hrefIsActive(pathname: string, href: string): boolean {
  return normalizePath(pathname) === normalizePath(href);
}

/** Same-origin app paths → React Router `Link` (no full document reload). External / special → `<a>`. */
function isInAppPathHref(href: string): boolean {
  const t = href.trim();
  if (!t) return false;
  const lower = t.toLowerCase();
  if (
    lower.startsWith('http://')
    || lower.startsWith('https://')
    || lower.startsWith('mailto:')
    || lower.startsWith('tel:')
    || lower.startsWith('//')
    || lower.startsWith('javascript:')
    || lower.startsWith('data:')
  ) {
    return false;
  }
  return t.startsWith('/');
}

const MotionLink = motion(Link);

/* ─── Animation ───────────────────────────────────── */

const VERCEL_SPRING = {
  type: 'spring' as const,
  bounce: 0.1,
  duration: 0.25,
};

const logoVariants: Variants = {
  hidden: { opacity: 0, x: -6 },
  visible: {
    opacity: 1,
    x: 0,
    transition: { ...VERCEL_SPRING, duration: 0.4 },
  },
};

const navRailVariants: Variants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: { delay: 0.1, duration: 0.25 },
  },
};

const actionsVariants: Variants = {
  hidden: { opacity: 0, x: 6 },
  visible: {
    opacity: 1,
    x: 0,
    transition: { ...VERCEL_SPRING, delay: 0.3 },
  },
};

const mobileMenuVariants: Variants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: { staggerChildren: 0.04, delayChildren: 0.03 },
  },
  exit: { opacity: 0, transition: { duration: 0.12 } },
};

const mobileLinkVariants: Variants = {
  hidden: { opacity: 0, y: 8 },
  visible: {
    opacity: 1,
    y: 0,
    transition: VERCEL_SPRING,
  },
  exit: { opacity: 0, y: -4, transition: { duration: 0.1 } },
};

/* ─── Context ───────────────────────────────────────── */

interface HeaderNavContextValue {
  pathname: string;
  isMobileOpen: boolean;
  setIsMobileOpen: Dispatch<SetStateAction<boolean>>;
  closeMobile: () => void;
  navItems: NonNullable<HeaderData['menu']>;
  actions: NonNullable<HeaderData['actions']>;
}

const HeaderNavContext = createContext<HeaderNavContextValue | null>(null);

function useHeaderNavContext() {
  const ctx = useContext(HeaderNavContext);
  if (!ctx) throw new Error('Header subcomponents must render inside Header');
  return ctx;
}

/* ─── Sub-components ────────────────────────────────── */

function NavDivider() {
  return (
    <motion.div
      className="mx-4 hidden h-5 w-px bg-[var(--local-border)] lg:block"
      variants={logoVariants}
    />
  );
}

const UNDERLINE_SPRING = { stiffness: 500, damping: 30 };

function NavLinks() {
  const { navItems, pathname, closeMobile } = useHeaderNavContext();
  const railRef = useRef<HTMLDivElement>(null);
  const leftTarget = useMotionValue(0);
  const widthTarget = useMotionValue(0);
  const leftSpring = useSpring(leftTarget, UNDERLINE_SPRING);
  const widthSpring = useSpring(widthTarget, UNDERLINE_SPRING);

  const applyUnderline = useCallback(() => {
    const rail = railRef.current;
    if (!rail) return;
    const active = rail.querySelector<HTMLElement>('[data-main-nav-active="true"]');
    if (!active) return;
    const railRect = rail.getBoundingClientRect();
    const linkRect = active.getBoundingClientRect();
    leftTarget.set(linkRect.left - railRect.left);
    widthTarget.set(linkRect.width);
  }, [leftTarget, widthTarget]);

  useLayoutEffect(() => {
    applyUnderline();
    const id = window.requestAnimationFrame(() => applyUnderline());
    return () => window.cancelAnimationFrame(id);
  }, [pathname, navItems, applyUnderline]);

  useEffect(() => {
    const rail = railRef.current;
    if (!rail) return;
    const ro = new ResizeObserver(() => applyUnderline());
    ro.observe(rail);
    window.addEventListener('resize', applyUnderline);
    return () => {
      ro.disconnect();
      window.removeEventListener('resize', applyUnderline);
    };
  }, [applyUnderline]);

  return (
    <motion.div
      ref={railRef}
      className="relative hidden h-full items-center gap-0.5 lg:flex"
      variants={navRailVariants}
    >
      {navItems.map((item) => {
        const isActive = hrefIsActive(pathname, item.href);
        const inApp = isInAppPathHref(item.href);
        const className = cn(
          'relative px-3 py-1.5 text-sm transition-colors duration-150',
          isActive
            ? 'text-[var(--local-text)]'
            : 'text-[var(--local-muted)] hover:text-[var(--local-text)]',
        );
        const shared = {
          className,
          'data-jp-item-id': item.id,
          'data-jp-item-field': 'menu' as const,
          'data-main-nav-active': isActive ? ('true' as const) : undefined,
          onClick: () => closeMobile(),
          children: (
            <span className="flex items-center gap-1.5">
              <span data-jp-field="label">{item.label}</span>
              {item.badge ? (
                <span
                  className="inline-flex items-center rounded-full border border-[var(--local-border)] bg-[var(--local-secondary)] px-2 py-0.5 text-[10px] font-medium text-[var(--local-muted)]"
                  data-jp-field="badge"
                >
                  {item.badge}
                </span>
              ) : null}
            </span>
          ),
        };
        return inApp ? (
          <Link key={item.id} to={item.href} {...shared} />
        ) : (
          <a key={item.id} href={item.href} {...shared} />
        );
      })}
      <motion.div
        aria-hidden
        className="pointer-events-none absolute bottom-0 h-px bg-[var(--local-text)]"
        style={{ left: leftSpring, width: widthSpring }}
      />
    </motion.div>
  );
}

function NavActions() {
  const { actions, closeMobile } = useHeaderNavContext();
  return (
    <motion.div
      className="hidden items-center gap-2 lg:flex"
      variants={actionsVariants}
    >
      {actions.map((action) => {
        const inApp = isInAppPathHref(action.href);
        return action.variant === 'primary' ? (
          inApp ? (
            <MotionLink
              key={action.id}
              to={action.href}
              className="inline-flex items-center rounded-full bg-[var(--local-text)] px-4 py-1.5 text-sm font-medium text-[var(--local-text-on-solid)] transition-opacity duration-200 hover:opacity-90"
              whileHover={{ scale: 1.02 }}
              whileTap={{ scale: 0.98 }}
              data-jp-item-id={action.id}
              data-jp-item-field="actions"
            >
              <span data-jp-field="label">{action.label}</span>
            </MotionLink>
          ) : (
            <motion.a
              key={action.id}
              className="inline-flex items-center rounded-full bg-[var(--local-text)] px-4 py-1.5 text-sm font-medium text-[var(--local-text-on-solid)] transition-opacity duration-200 hover:opacity-90"
              href={action.href}
              whileHover={{ scale: 1.02 }}
              whileTap={{ scale: 0.98 }}
              data-jp-item-id={action.id}
              data-jp-item-field="actions"
            >
              <span data-jp-field="label">{action.label}</span>
            </motion.a>
          )
        ) : inApp ? (
          <Link
            key={action.id}
            to={action.href}
            className="px-3 py-1.5 text-sm text-[var(--local-muted)] transition-colors duration-150 hover:text-[var(--local-text)]"
            data-jp-item-id={action.id}
            data-jp-item-field="actions"
          >
            <span data-jp-field="label">{action.label}</span>
          </Link>
        ) : (
          <a
            key={action.id}
            className="px-3 py-1.5 text-sm text-[var(--local-muted)] transition-colors duration-150 hover:text-[var(--local-text)]"
            href={action.href}
            data-jp-item-id={action.id}
            data-jp-item-field="actions"
          >
            <span data-jp-field="label">{action.label}</span>
          </a>
        );
      })}
    </motion.div>
  );
}

function ThemeToggleButton({ className }: { className?: string }) {
  const { theme, toggleTheme } = useTheme();
  return (
    <Button
      type="button"
      variant="outline"
      onClick={toggleTheme}
      className={cn(
        'flex size-8 shrink-0 items-center justify-center rounded-md border-[var(--local-border)] bg-[var(--local-secondary)] p-0 text-[var(--local-text)]',
        className,
      )}
      aria-label="Toggle theme"
    >
      {theme === 'dark' ? <Sun className="size-4" /> : <Moon className="size-4" />}
    </Button>
  );
}

function MobileToggle() {
  const { isMobileOpen, setIsMobileOpen } = useHeaderNavContext();

  return (
    <motion.div variants={actionsVariants}>
      <motion.button
        aria-label={isMobileOpen ? 'Close menu' : 'Open menu'}
        className="flex size-8 cursor-pointer items-center justify-center rounded-md border border-[var(--local-border)] text-[var(--local-muted)] transition-colors hover:bg-[var(--local-secondary)] hover:text-[var(--local-text)] lg:hidden"
        onClick={() => setIsMobileOpen((prev) => !prev)}
        whileTap={{ scale: 0.95 }}
        type="button"
      >
        <AnimatePresence initial={false} mode="popLayout">
          <motion.span
            animate={{ opacity: 1, rotate: 0 }}
            className="flex items-center justify-center"
            exit={{ opacity: 0, rotate: 90 }}
            initial={{ opacity: 0, rotate: -90 }}
            key={isMobileOpen ? 'close' : 'open'}
            transition={{ type: 'spring', duration: 0.3, bounce: 0 }}
          >
            {isMobileOpen ? <X className="size-4" /> : <Menu className="size-4" />}
          </motion.span>
        </AnimatePresence>
      </motion.button>
    </motion.div>
  );
}

function MobileMenu() {
  const { isMobileOpen, navItems, actions, pathname, closeMobile } = useHeaderNavContext();
  const [contentRef, { height: measuredHeight }] = useMeasure();

  return (
    <AnimatePresence>
      {isMobileOpen ? (
        <motion.div
          animate={{ height: measuredHeight || 'auto', opacity: 1 }}
          className="absolute inset-x-0 top-full overflow-hidden lg:hidden"
          exit={{ height: 0, opacity: 0 }}
          initial={{ height: 0, opacity: 0 }}
          transition={VERCEL_SPRING}
        >
          <div ref={contentRef}>
            <motion.div
              animate="visible"
              className="border-b border-[var(--local-border)] bg-[var(--local-bg)] px-6 pb-4 pt-2"
              exit="exit"
              initial="hidden"
              variants={mobileMenuVariants}
            >
              <div className="flex flex-col">
                {navItems.map((item) => {
                  const isActive = hrefIsActive(pathname, item.href);
                  const inApp = isInAppPathHref(item.href);
                  const className = cn(
                    'flex items-center gap-2 border-b border-[var(--local-border)] py-3 text-sm transition-colors last:border-b-0',
                    isActive
                      ? 'text-[var(--local-text)]'
                      : 'text-[var(--local-muted)] hover:text-[var(--local-text)]',
                  );
                  const motionProps = {
                    className,
                    variants: mobileLinkVariants,
                    onClick: () => closeMobile(),
                    'data-jp-item-id': item.id,
                    'data-jp-item-field': 'menu' as const,
                    children: (
                      <>
                        <span data-jp-field="label">{item.label}</span>
                        {item.badge ? (
                          <span
                            className="rounded-full border border-[var(--local-border)] bg-[var(--local-secondary)] px-2 py-0.5 text-[10px] font-medium text-[var(--local-muted)]"
                            data-jp-field="badge"
                          >
                            {item.badge}
                          </span>
                        ) : null}
                      </>
                    ),
                  };
                  return inApp ? (
                    <MotionLink key={item.id} to={item.href} {...motionProps} />
                  ) : (
                    <motion.a key={item.id} href={item.href} {...motionProps} />
                  );
                })}
              </div>
              <motion.div className="mt-4 flex flex-col gap-2" variants={mobileLinkVariants}>
                {actions.map((action) => {
                  const inApp = isInAppPathHref(action.href);
                  const onNav = () => closeMobile();
                  return action.variant === 'primary' ? inApp ? (
                    <Link
                      key={action.id}
                      to={action.href}
                      className="rounded-full bg-[var(--local-text)] px-4 py-2.5 text-center text-sm font-medium text-[var(--local-text-on-solid)]"
                      onClick={onNav}
                      data-jp-item-id={action.id}
                      data-jp-item-field="actions"
                    >
                      <span data-jp-field="label">{action.label}</span>
                    </Link>
                  ) : (
                    <a
                      key={action.id}
                      className="rounded-full bg-[var(--local-text)] px-4 py-2.5 text-center text-sm font-medium text-[var(--local-text-on-solid)]"
                      href={action.href}
                      onClick={onNav}
                      data-jp-item-id={action.id}
                      data-jp-item-field="actions"
                    >
                      <span data-jp-field="label">{action.label}</span>
                    </a>
                  ) : inApp ? (
                    <Link
                      key={action.id}
                      to={action.href}
                      className="px-4 py-2.5 text-sm text-[var(--local-muted)] transition-colors hover:text-[var(--local-text)]"
                      onClick={onNav}
                      data-jp-item-id={action.id}
                      data-jp-item-field="actions"
                    >
                      <span data-jp-field="label">{action.label}</span>
                    </Link>
                  ) : (
                    <a
                      key={action.id}
                      className="px-4 py-2.5 text-sm text-[var(--local-muted)] transition-colors hover:text-[var(--local-text)]"
                      href={action.href}
                      onClick={onNav}
                      data-jp-item-id={action.id}
                      data-jp-item-field="actions"
                    >
                      <span data-jp-field="label">{action.label}</span>
                    </a>
                  );
                })}
              </motion.div>
            </motion.div>
          </div>
        </motion.div>
      ) : null}
    </AnimatePresence>
  );
}

/* ─── Root ──────────────────────────────────────────── */

export function Header({
  data,
  settings: _settings,
}: {
  data: HeaderData;
  settings: HeaderSettings;
}) {
  const navItems = useMemo(() => (Array.isArray(data.menu) ? data.menu : []), [data.menu]);
  const actions = useMemo(() => (Array.isArray(data.actions) ? data.actions : []), [data.actions]);
  const { pathname } = useLocation();
  const [isScrolled, setIsScrolled] = useState(false);
  const [isMobileOpen, setIsMobileOpen] = useState(false);
  /** Skip CSS transitions for one frame after route change (avoids header blur/bg flashing when scroll resets). */
  const [routePaintLock, setRoutePaintLock] = useState(false);
  const prefersReduced = useReducedMotion();
  const { scrollY } = useScroll();
  const navRef = useRef<HTMLElement>(null);
  const firstPathname = useRef(true);
  const scrollThreshold = data.scrollThreshold ?? 20;
  const logoHref = data.logoHref?.trim() || '/';

  useMotionValueEvent(scrollY, 'change', (latest) => {
    setIsScrolled(latest > scrollThreshold);
  });

  useLayoutEffect(() => {
    if (firstPathname.current) {
      firstPathname.current = false;
      return;
    }
    window.scrollTo({ top: 0, left: 0, behavior: 'instant' });
    setIsScrolled(false);
    setRoutePaintLock(true);
    const id = window.requestAnimationFrame(() => setRoutePaintLock(false));
    return () => window.cancelAnimationFrame(id);
  }, [pathname]);

  const closeMobile = useCallback(() => setIsMobileOpen(false), []);

  useEffect(() => {
    if (!isMobileOpen) return;
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') closeMobile();
    };
    document.addEventListener('keydown', handleKey);
    return () => document.removeEventListener('keydown', handleKey);
  }, [isMobileOpen, closeMobile]);

  useEffect(() => {
    if (!isMobileOpen) return;
    const handleClick = (e: MouseEvent) => {
      if (navRef.current && !navRef.current.contains(e.target as Node)) {
        closeMobile();
      }
    };
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, [isMobileOpen, closeMobile]);

  useLayoutEffect(() => {
    const el = navRef.current;
    if (!el) return;
    const apply = () => {
      document.documentElement.style.setProperty(HEADER_HEIGHT_CSS_VAR, `${el.offsetHeight}px`);
    };
    apply();
    const ro = new ResizeObserver(apply);
    ro.observe(el);
    return () => {
      ro.disconnect();
      document.documentElement.style.removeProperty(HEADER_HEIGHT_CSS_VAR);
    };
  }, [data.announcement]);

  const shellStyle = {
    '--local-bg': 'var(--background)',
    '--local-text': 'var(--foreground)',
    '--local-muted': 'var(--muted-foreground)',
    '--local-border': 'var(--border)',
    '--local-secondary': 'var(--secondary)',
    '--local-text-on-solid': 'var(--background)',
    '--local-radius-md': 'var(--theme-radius-md)',
  } as CSSProperties;

  const ctx: HeaderNavContextValue = {
    pathname,
    isMobileOpen,
    setIsMobileOpen,
    closeMobile,
    navItems,
    actions,
  };

  return (
    <HeaderNavContext.Provider value={ctx}>
      <motion.header
        ref={navRef}
        className={cn(
          'fixed inset-x-0 top-0 z-50 border-b border-[var(--local-border)]',
          !routePaintLock && 'transition-[backdrop-filter] duration-300',
          isScrolled && 'backdrop-blur-sm',
        )}
        initial={prefersReduced ? false : 'hidden'}
        animate="visible"
        style={{
          ...shellStyle,
          backgroundColor: isScrolled
            ? 'color-mix(in oklch, var(--background) 88%, transparent)'
            : 'var(--background)',
        }}
      >
        {data.announcement ? (
          <div
            className="border-b border-[var(--local-border)] py-2 text-center text-[0.72rem] font-mono uppercase tracking-[0.16em] text-[var(--local-muted)]"
            data-jp-field="announcement"
          >
            {data.announcement}
          </div>
        ) : null}

        <div className="mx-auto flex h-14 max-w-[1200px] items-center justify-between px-6">
          <div className="flex h-full min-w-0 items-center">
            {isInAppPathHref(logoHref) ? (
              <MotionLink
                className="flex shrink-0 items-baseline gap-2"
                to={logoHref}
                variants={logoVariants}
                data-jp-field="logoHref"
              >
                <span
                  className="font-display text-lg font-semibold tracking-tight text-[var(--local-text)] sm:text-xl"
                  style={{
                    fontFamily: '"Cormorant Garamond", Helvetica, Arial, sans-serif',
                    fontWeight: 600,
                    letterSpacing: '-0.04em',
                  }}
                  data-jp-field="logoText"
                >
                  {data.logoText}
                </span>
                {data.logoHighlight ? (
                  <span
                    className="hidden font-mono text-[0.65rem] uppercase tracking-[0.2em] text-[var(--local-muted)] sm:inline"
                    data-jp-field="logoHighlight"
                  >
                    {data.logoHighlight}
                  </span>
                ) : null}
              </MotionLink>
            ) : (
              <motion.a
                className="flex shrink-0 items-baseline gap-2"
                href={logoHref}
                variants={logoVariants}
                data-jp-field="logoHref"
              >
                <span
                  className="font-display text-lg font-semibold tracking-tight text-[var(--local-text)] sm:text-xl"
                  style={{
                    fontFamily: '"Cormorant Garamond", Helvetica, Arial, sans-serif',
                    fontWeight: 600,
                    letterSpacing: '-0.04em',
                  }}
                  data-jp-field="logoText"
                >
                  {data.logoText}
                </span>
                {data.logoHighlight ? (
                  <span
                    className="hidden font-mono text-[0.65rem] uppercase tracking-[0.2em] text-[var(--local-muted)] sm:inline"
                    data-jp-field="logoHighlight"
                  >
                    {data.logoHighlight}
                  </span>
                ) : null}
              </motion.a>
            )}
            <NavDivider />
            <NavLinks />
          </div>
          <div className="flex shrink-0 items-center gap-2">
            <NavActions />
            <ThemeToggleButton />
            <MobileToggle />
          </div>
        </div>
        <MobileMenu />
      </motion.header>
    </HeaderNavContext.Provider>
  );
}
