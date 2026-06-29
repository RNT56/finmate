// Auth layer over supabase-js (docs/07 §3). Exposes session state + the auth
// actions the UI needs: Sign in with Apple (OAuth), email/password sign-in &
// sign-up, sign-out, and live session changes via onAuthStateChange.
//
// CRITICAL OFFLINE PATH: when getSupabase() is null (no VITE_ env — the default
// here), we run a DEMO mode: an in-memory signed-in user so the app still builds,
// previews, and is usable on the sample repos exactly as before. Live Sign in with
// Apple / email-password run against Supabase only when configured.

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';
import type { Session, User } from '@supabase/auth-js';
import { getSupabase, isSupabaseConfigured } from '../../lib/supabase';
import type { AuthStatus } from '../../lib/authRoute';

/** The minimal session shape the UI reads (real or demo). */
export interface AuthUser {
  id: string;
  email: string | null;
  /** True when this is the offline demo user (no live backend). */
  isDemo: boolean;
}

export interface AuthContextValue {
  status: AuthStatus;
  user: AuthUser | null;
  /** True when a live Supabase backend is configured. */
  isConfigured: boolean;
  signInWithApple: () => Promise<void>;
  signIn: (email: string, password: string) => Promise<void>;
  signUp: (email: string, password: string) => Promise<void>;
  /** Send a password-reset email. Resolves without a network call in demo mode;
   *  callers show a neutral confirmation (never revealing whether the account exists). */
  resetPassword: (email: string) => Promise<void>;
  /** Enter the offline demo (in-memory signed-in user). */
  signInDemo: () => void;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

const DEMO_USER: AuthUser = { id: 'demo-user', email: 'demo@finmate.app', isDemo: true };

function toAuthUser(user: User | null | undefined): AuthUser | null {
  if (!user) return null;
  return { id: user.id, email: user.email ?? null, isDemo: false };
}

function fromSession(session: Session | null): AuthUser | null {
  return toAuthUser(session?.user);
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const supabase = useMemo(() => getSupabase(), []);
  // Demo mode (no backend): start signed-out so the user still sees Login with a
  // working "Try the demo" path. Live mode: start in 'loading' until we hydrate.
  const [status, setStatus] = useState<AuthStatus>(
    supabase ? 'loading' : 'unauthenticated',
  );
  const [user, setUser] = useState<AuthUser | null>(null);

  // Hydrate + subscribe to live session changes (no-op in demo mode).
  useEffect(() => {
    if (!supabase) return;
    let active = true;

    supabase.auth.getSession().then(({ data }) => {
      if (!active) return;
      const u = fromSession(data.session);
      setUser(u);
      setStatus(u ? 'authenticated' : 'unauthenticated');
    });

    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) => {
      const u = fromSession(session);
      setUser(u);
      setStatus(u ? 'authenticated' : 'unauthenticated');
    });

    return () => {
      active = false;
      sub.subscription.unsubscribe();
    };
  }, [supabase]);

  const signInWithApple = useCallback(async () => {
    if (!supabase) {
      // No backend: fall through to the demo so the button still works offline.
      setUser(DEMO_USER);
      setStatus('authenticated');
      return;
    }
    const { error } = await supabase.auth.signInWithOAuth({
      provider: 'apple',
      options: { redirectTo: window.location.origin },
    });
    if (error) throw error;
    // On success the browser redirects; onAuthStateChange picks up the session.
  }, [supabase]);

  const signIn = useCallback(
    async (email: string, password: string) => {
      if (!supabase) {
        setUser(DEMO_USER);
        setStatus('authenticated');
        return;
      }
      const { error } = await supabase.auth.signInWithPassword({ email, password });
      if (error) throw error;
    },
    [supabase],
  );

  const signUp = useCallback(
    async (email: string, password: string) => {
      if (!supabase) {
        setUser(DEMO_USER);
        setStatus('authenticated');
        return;
      }
      const { error } = await supabase.auth.signUp({ email, password });
      if (error) throw error;
    },
    [supabase],
  );

  const resetPassword = useCallback(
    async (email: string) => {
      // Demo / no backend: acknowledge without any network call.
      if (!supabase) return;
      const { error } = await supabase.auth.resetPasswordForEmail(email, {
        redirectTo: window.location.origin,
      });
      if (error) throw error;
    },
    [supabase],
  );

  const signInDemo = useCallback(() => {
    setUser(DEMO_USER);
    setStatus('authenticated');
  }, []);

  const signOut = useCallback(async () => {
    // Logout clears the live session (docs/07 §3); local caches are sample data.
    if (supabase) {
      await supabase.auth.signOut();
    }
    setUser(null);
    setStatus('unauthenticated');
  }, [supabase]);

  const value = useMemo<AuthContextValue>(
    () => ({
      status,
      user,
      isConfigured: isSupabaseConfigured,
      signInWithApple,
      signIn,
      signUp,
      resetPassword,
      signInDemo,
      signOut,
    }),
    [status, user, signInWithApple, signIn, signUp, resetPassword, signInDemo, signOut],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within an AuthProvider');
  return ctx;
}
