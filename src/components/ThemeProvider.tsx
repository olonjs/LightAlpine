import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';

type Theme = 'dark' | 'light';

interface ThemeContextValue {
  theme: Theme;
  toggleTheme: () => void;
  setTheme: (t: Theme) => void;
}

const ThemeContext = createContext<ThemeContextValue>({
  theme: 'dark',
  toggleTheme: () => {},
  setTheme: () => {},
});

/** Must match the inline script in `index.html` (first paint + this module). */
export const THEME_STORAGE_KEY = 'olon:theme';

function isTheme(value: unknown): value is Theme {
  return value === 'dark' || value === 'light';
}

function readStoredTheme(): Theme | null {
  if (typeof window === 'undefined') return null;
  try {
    const raw = window.localStorage.getItem(THEME_STORAGE_KEY);
    return isTheme(raw) ? raw : null;
  } catch {
    return null;
  }
}

function resolveInitialTheme(): Theme {
  if (typeof window === 'undefined') return 'dark';

  const stored = readStoredTheme();
  if (stored) return stored;

  const fromDom = document.documentElement.getAttribute('data-theme');
  if (isTheme(fromDom)) return fromDom;

  const prefersLight = window.matchMedia?.('(prefers-color-scheme: light)').matches;
  return prefersLight ? 'light' : 'dark';
}

function persistThemeToStorage(theme: Theme) {
  try {
    window.localStorage.setItem(THEME_STORAGE_KEY, theme);
  } catch {
    /* private mode / quota */
  }
}

export function ThemeProvider({ children }: { children: ReactNode }) {
  const [theme, setThemeState] = useState<Theme>(resolveInitialTheme);

  useEffect(() => {
    const html = document.documentElement;

    const apply = () => {
      html.setAttribute('data-theme', theme);
      persistThemeToStorage(theme);
    };

    apply();

    // @olonjs/core reapplies theme from theme.json on route changes; that resets
    // data-theme on <html> while React theme state is unchanged. Re-sync DOM + storage.
    const observer = new MutationObserver(() => {
      const current = html.getAttribute('data-theme');
      if (current !== theme) {
        apply();
      }
    });

    observer.observe(html, { attributes: true, attributeFilter: ['data-theme'] });
    return () => observer.disconnect();
  }, [theme]);

  function setTheme(t: Theme) {
    setThemeState(t);
  }

  function toggleTheme() {
    setThemeState((prev) => (prev === 'dark' ? 'light' : 'dark'));
  }

  const value = useMemo(() => ({ theme, toggleTheme, setTheme }), [theme]);

  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export function useTheme() {
  return useContext(ThemeContext);
}
