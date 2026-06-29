// Hook-layer test for useAuth's password-reset action on the demo / no-backend
// path (getSupabase() is null in tests, so resetPassword must resolve without a
// network call). Mirrors the iOS AuthStore.sendPasswordReset test.
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import type { ReactNode } from 'react';
import { AuthProvider, useAuth } from './useAuth';

const wrapper = ({ children }: { children: ReactNode }) => <AuthProvider>{children}</AuthProvider>;

describe('useAuth resetPassword (demo / no backend)', () => {
  it('exposes resetPassword and resolves without a network call', async () => {
    const { result } = renderHook(() => useAuth(), { wrapper });
    expect(typeof result.current.resetPassword).toBe('function');
    await act(async () => {
      await expect(result.current.resetPassword('user@example.com')).resolves.toBeUndefined();
    });
  });
});
