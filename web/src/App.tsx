import { useState } from 'react';
import { createBrowserRouter, RouterProvider } from 'react-router-dom';
import { AppShell } from './components/AppShell';
import { Home } from './components/Home';
import { Placeholder } from './components/Placeholder';
import { SubscriptionList } from './features/subscriptions/SubscriptionList';
import { CashFlow } from './features/cashflow/CashFlow';
import { Calendar } from './features/calendar/Calendar';
import { More } from './features/more/More';
import { Assets } from './features/assets/Assets';
import { Calculator } from './features/calculator/Calculator';
import { Import } from './features/import/Import';
import { Settings } from './features/settings/Settings';
import { Styleguide } from './features/styleguide/Styleguide';
import { AuthProvider, useAuth } from './features/auth/useAuth';
import { Login } from './features/auth/Login';
import { Onboarding } from './features/auth/Onboarding';
import { isOnboarded, setOnboarded } from './features/auth/onboardingState';
import { resolveAuthRoute } from './lib/authRoute';

const router = createBrowserRouter([
  {
    path: '/',
    element: <AppShell />,
    children: [
      { index: true, element: <Home /> },
      { path: 'subscriptions', element: <SubscriptionList /> },
      { path: 'cash-flow', element: <CashFlow /> },
      { path: 'calendar', element: <Calendar /> },
      { path: 'more', element: <More /> },
      { path: 'assets', element: <Assets /> },
      { path: 'calculator', element: <Calculator /> },
      { path: 'import', element: <Import /> },
      { path: 'settings', element: <Settings /> },
      { path: 'styleguide', element: <Styleguide /> },
      { path: '*', element: <Placeholder title="Not found" /> },
    ],
  },
]);

/**
 * Auth + first-run guard (docs/02 §1–2). Resolves the destination from the auth
 * status and onboarding flag: loading → splash; unauthenticated → Login;
 * authenticated && first-run → Onboarding; else the app. Default here (no VITE_
 * env) starts at Login with a working "Try the demo" path, so build/preview is
 * unaffected.
 */
function AuthGate() {
  const { status, user } = useAuth();
  // Re-render the gate when onboarding completes within the session.
  const [onboarded, setOnboardedState] = useState<boolean>(() => isOnboarded());

  const route = resolveAuthRoute(status, onboarded);

  switch (route) {
    case 'loading':
      return (
        <div className="fm-auth-screen" aria-busy="true">
          <div className="fm-brand">
            <span className="fm-brand-dot" aria-hidden="true" />
            Finmate
          </div>
        </div>
      );
    case 'login':
      return <Login />;
    case 'onboarding':
      return (
        <Onboarding
          onComplete={() => {
            setOnboarded(true);
            setOnboardedState(true);
          }}
        />
      );
    case 'app':
      return <RouterProvider router={router} key={user?.id ?? 'app'} />;
  }
}

export function App() {
  return (
    <AuthProvider>
      <AuthGate />
    </AuthProvider>
  );
}
