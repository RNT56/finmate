// AppShell — responsive sidebar (desktop) / bottom tab bar (mobile) with the five
// sections, mirroring the iOS root TabView (Home / Subscriptions / Cash Flow /
// Calendar / More). One glass language.

import type { ReactNode } from 'react';
import { NavLink, Outlet } from 'react-router-dom';

interface Section {
  to: string;
  label: string;
  icon: string;
}

const SECTIONS: Section[] = [
  { to: '/', label: 'Home', icon: '◎' },
  { to: '/subscriptions', label: 'Subscriptions', icon: '⟳' },
  { to: '/cash-flow', label: 'Cash Flow', icon: '⇅' },
  { to: '/calendar', label: 'Calendar', icon: '▦' },
  { to: '/more', label: 'More', icon: '⋯' },
];

export function AppShell() {
  return (
    <div className="fm-shell">
      <nav className="fm-sidebar fm-glass" aria-label="Primary">
        <div className="fm-brand">
          <span className="fm-brand-dot" aria-hidden="true" />
          Finmate
        </div>
        {SECTIONS.map((s) => (
          <NavLink
            key={s.to}
            to={s.to}
            end={s.to === '/'}
            className={({ isActive }) => `fm-nav-link${isActive ? ' active' : ''}`}
          >
            <span className="fm-nav-icon" aria-hidden="true">
              {s.icon}
            </span>
            {s.label}
          </NavLink>
        ))}
      </nav>
      <main className="fm-main">
        <Outlet />
      </main>
    </div>
  );
}

/** Simple page scaffold used by feature screens. */
export function Page({ title, children }: { title: string; children: ReactNode }) {
  return (
    <>
      <h1 className="fm-page-title">{title}</h1>
      {children}
    </>
  );
}
