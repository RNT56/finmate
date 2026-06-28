import { createBrowserRouter, RouterProvider } from 'react-router-dom';
import { AppShell } from './components/AppShell';
import { Home } from './components/Home';
import { Placeholder } from './components/Placeholder';
import { SubscriptionList } from './features/subscriptions/SubscriptionList';
import { CashFlow } from './features/cashflow/CashFlow';
import { Calendar } from './features/calendar/Calendar';

const router = createBrowserRouter([
  {
    path: '/',
    element: <AppShell />,
    children: [
      { index: true, element: <Home /> },
      { path: 'subscriptions', element: <SubscriptionList /> },
      { path: 'cash-flow', element: <CashFlow /> },
      { path: 'calendar', element: <Calendar /> },
      { path: 'more', element: <Placeholder title="More" /> },
      { path: '*', element: <Placeholder title="Not found" /> },
    ],
  },
]);

export function App() {
  return <RouterProvider router={router} />;
}
