// Pure auth-state → route resolution (docs/02 §1–2, docs/07 §3). Kept separate
// from React so it is trivially unit-testable and shared by the App router guard.

/** Coarse authentication status the UI cares about. */
export type AuthStatus = 'loading' | 'unauthenticated' | 'authenticated';

/** Where the router should send the user given auth + first-run state. */
export type AuthRoute = 'loading' | 'login' | 'onboarding' | 'app';

/**
 * Resolve the destination from the current auth status and whether the signed-in
 * user has completed onboarding.
 *
 * - loading            → 'loading' (splash; never flash Login before we know)
 * - unauthenticated    → 'login'
 * - authenticated, not onboarded → 'onboarding' (first run)
 * - authenticated, onboarded     → 'app'
 */
export function resolveAuthRoute(status: AuthStatus, onboarded: boolean): AuthRoute {
  switch (status) {
    case 'loading':
      return 'loading';
    case 'unauthenticated':
      return 'login';
    case 'authenticated':
      return onboarded ? 'app' : 'onboarding';
  }
}
