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
      { path: '*', element: <Placeholder title="Not found" /> },
    ],
  },
]);

export function App() {
  return <RouterProvider router={router} />;
}
