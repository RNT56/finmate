import { describe, it, expect } from 'vitest';
import { resolveAuthRoute } from './authRoute';

// Mirrors the iOS RootView guard: loading splash → Login → Onboarding → app.

describe('resolveAuthRoute', () => {
  it('shows the loading splash while auth is resolving (onboarded irrelevant)', () => {
    expect(resolveAuthRoute('loading', false)).toBe('loading');
    expect(resolveAuthRoute('loading', true)).toBe('loading');
  });

  it('routes unauthenticated users to Login (onboarded irrelevant)', () => {
    expect(resolveAuthRoute('unauthenticated', false)).toBe('login');
    expect(resolveAuthRoute('unauthenticated', true)).toBe('login');
  });

  it('routes a signed-in first-run user to Onboarding', () => {
    expect(resolveAuthRoute('authenticated', false)).toBe('onboarding');
  });

  it('routes a signed-in onboarded user into the app', () => {
    expect(resolveAuthRoute('authenticated', true)).toBe('app');
  });
});
