// Login screen (docs/02 §1): Sign in with Apple + an email/password form with a
// sign-in / sign-up toggle, and a prominent "Try the demo" action so the app is
// usable offline (no Supabase configured). One Liquid Glass language (GlassCard +
// glass tokens). Accessibility: labelled inputs, a single live error region.

import { useState, type FormEvent } from 'react';
import { GlassCard } from '../../components/GlassCard';
import { useAuth } from './useAuth';

type Mode = 'signIn' | 'signUp';

export function Login() {
  const { signInWithApple, signIn, signUp, signInDemo, isConfigured } = useAuth();
  const [mode, setMode] = useState<Mode>('signIn');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    setBusy(true);
    try {
      if (mode === 'signIn') await signIn(email, password);
      else await signUp(email, password);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Something went wrong. Please try again.');
    } finally {
      setBusy(false);
    }
  };

  const handleApple = async () => {
    setError(null);
    setBusy(true);
    try {
      await signInWithApple();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Sign in with Apple failed.');
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="fm-auth-screen">
      <div style={{ width: '100%', maxWidth: '24rem' }}>
        <div className="fm-brand" style={{ justifyContent: 'center', marginBottom: '1.5rem' }}>
          <span className="fm-brand-dot" aria-hidden="true" />
          Finmate
        </div>

        <GlassCard>
          <h1 style={{ fontSize: '1.25rem', fontWeight: 700, margin: '0 0 0.25rem' }}>
            {mode === 'signIn' ? 'Welcome back' : 'Create your account'}
          </h1>
          <p className="fm-secondary" style={{ fontSize: '0.875rem', margin: '0 0 1.25rem' }}>
            Private-first personal finance.
          </p>

          {/* Sign in with Apple */}
          <button
            type="button"
            className="fm-btn"
            style={{ width: '100%', justifyContent: 'center' }}
            aria-label="Sign in with Apple"
            disabled={busy}
            onClick={handleApple}
          >
            <span aria-hidden="true" style={{ marginRight: '0.5rem' }}></span>
            Sign in with Apple
          </button>

          <div className="fm-auth-divider" aria-hidden="true">
            <span>or</span>
          </div>

          {/* Email / password */}
          <form className="fm-stack" style={{ gap: '0.75rem' }} onSubmit={submit}>
            <label className="fm-stack" style={{ gap: '0.25rem' }}>
              <span className="fm-secondary" style={{ fontSize: '0.8125rem' }}>
                Email
              </span>
              <input
                type="email"
                className="fm-input"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                autoComplete="email"
                required
                aria-label="Email"
              />
            </label>
            <label className="fm-stack" style={{ gap: '0.25rem' }}>
              <span className="fm-secondary" style={{ fontSize: '0.8125rem' }}>
                Password
              </span>
              <input
                type="password"
                className="fm-input"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                autoComplete={mode === 'signIn' ? 'current-password' : 'new-password'}
                required
                minLength={6}
                aria-label="Password"
              />
            </label>

            {error && (
              <div role="alert" className="fm-auth-error">
                {error}
              </div>
            )}

            <button
              type="submit"
              className="fm-btn"
              style={{ width: '100%', justifyContent: 'center' }}
              disabled={busy}
            >
              {mode === 'signIn' ? 'Sign in' : 'Create account'}
            </button>
          </form>

          <button
            type="button"
            className="fm-btn fm-btn-ghost"
            style={{ width: '100%', justifyContent: 'center', marginTop: '0.75rem' }}
            onClick={() => {
              setMode((m) => (m === 'signIn' ? 'signUp' : 'signIn'));
              setError(null);
            }}
          >
            {mode === 'signIn' ? 'New here? Create an account' : 'Have an account? Sign in'}
          </button>
        </GlassCard>

        {/* Prominent demo entry — always works, no backend needed. */}
        <button
          type="button"
          className="fm-btn"
          style={{
            width: '100%',
            justifyContent: 'center',
            marginTop: '1rem',
            background: 'var(--fm-accent)',
            fontWeight: 700,
          }}
          aria-label="Try the demo without an account"
          data-testid="try-demo"
          onClick={signInDemo}
        >
          Try the demo →
        </button>
        <p
          className="fm-secondary"
          style={{ fontSize: '0.75rem', textAlign: 'center', marginTop: '0.5rem' }}
        >
          {isConfigured
            ? 'Explore Finmate with sample data — no sign-up required.'
            : 'No backend configured — the demo runs on in-memory sample data.'}
        </p>
      </div>
    </div>
  );
}
