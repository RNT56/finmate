// Preferences store/hook (M7) — a small React context over a PreferencesRepository.
// Persists to localStorage for the web demo and applies the appearance app-wide by
// toggling a `data-theme` attribute on <html> (respecting prefers-color-scheme for
// `system`). Stores call the repository protocol, never storage directly (docs/03).

import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';
import {
  type Appearance,
  type UserPreferences,
  type PreferencesRepository,
  LocalStoragePreferencesRepository,
} from '../../core/preferences';

interface PreferencesContextValue {
  preferences: UserPreferences;
  /** Patch one or more fields; persists + reapplies appearance. */
  update: (patch: Partial<UserPreferences>) => void;
}

const PreferencesContext = createContext<PreferencesContextValue | null>(null);

/**
 * Resolve the effective theme. `system` reads prefers-color-scheme; everything
 * else is explicit. Returns 'light' | 'dark'.
 */
function resolveTheme(appearance: Appearance): 'light' | 'dark' {
  if (appearance === 'light' || appearance === 'dark') return appearance;
  const prefersDark =
    typeof window !== 'undefined' &&
    typeof window.matchMedia === 'function' &&
    window.matchMedia('(prefers-color-scheme: dark)').matches;
  return prefersDark ? 'dark' : 'light';
}

/** Toggle the document root `data-theme` so glass.css can switch the look. */
function applyAppearance(appearance: Appearance): void {
  if (typeof document === 'undefined') return;
  const root = document.documentElement;
  if (appearance === 'system') {
    // Let prefers-color-scheme drive the :root defaults; no explicit override.
    root.removeAttribute('data-theme');
  } else {
    root.setAttribute('data-theme', resolveTheme(appearance));
  }
}

export function PreferencesProvider({
  children,
  repository,
}: {
  children: ReactNode;
  repository?: PreferencesRepository;
}) {
  const repo = useMemo(
    () => repository ?? new LocalStoragePreferencesRepository(),
    [repository],
  );
  const [preferences, setPreferences] = useState<UserPreferences>(() => repo.load());

  // Apply on mount and whenever the appearance changes.
  useEffect(() => {
    applyAppearance(preferences.appearance);
  }, [preferences.appearance]);

  // When following the system, react to OS light/dark changes live.
  useEffect(() => {
    if (preferences.appearance !== 'system') return;
    if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') return;
    const mql = window.matchMedia('(prefers-color-scheme: dark)');
    const handler = () => applyAppearance('system');
    mql.addEventListener?.('change', handler);
    return () => mql.removeEventListener?.('change', handler);
  }, [preferences.appearance]);

  const value = useMemo<PreferencesContextValue>(
    () => ({
      preferences,
      update: (patch) => {
        setPreferences((prev) => {
          const next = { ...prev, ...patch };
          repo.save(next);
          return repo.load();
        });
      },
    }),
    [preferences, repo],
  );

  return <PreferencesContext.Provider value={value}>{children}</PreferencesContext.Provider>;
}

export function usePreferences(): PreferencesContextValue {
  const ctx = useContext(PreferencesContext);
  if (!ctx) {
    throw new Error('usePreferences must be used within a PreferencesProvider');
  }
  return ctx;
}
