// More page (M5) — a menu hub linking the secondary pillars: Assets, BTC
// Calculator, and a Settings stub. Replaces the old More placeholder route.
// One glass language; reuses GlassCard + glass tokens.

import { Link } from 'react-router-dom';
import { GlassCard } from '../../components/GlassCard';
import { Page } from '../../components/AppShell';

interface MoreItem {
  to: string;
  icon: string;
  title: string;
  subtitle: string;
}

const ITEMS: MoreItem[] = [
  {
    to: '/assets',
    icon: '◆',
    title: 'Assets',
    subtitle: 'Portfolio, allocation, and unrealized gain/loss',
  },
  {
    to: '/calculator',
    icon: '₿',
    title: 'BTC Calculator',
    subtitle: 'Convert fiat to BTC and satoshis',
  },
];

export function More() {
  return (
    <Page title="More">
      <div className="fm-stack">
        <GlassCard padded={false}>
          <ul style={{ listStyle: 'none', margin: 0, padding: 0 }}>
            {ITEMS.map((item, i) => (
              <li key={item.to}>
                <Link
                  to={item.to}
                  className="fm-row"
                  style={{
                    padding: '14px 16px',
                    textDecoration: 'none',
                    color: 'inherit',
                    borderTop: i === 0 ? 'none' : '1px solid var(--fm-glass-border)',
                  }}
                >
                  <span className="fm-icon-tile" aria-hidden="true">
                    {item.icon}
                  </span>
                  <span style={{ flex: 1 }}>
                    <span style={{ fontWeight: 600, display: 'block' }}>{item.title}</span>
                    <span className="fm-secondary" style={{ fontSize: 13 }}>
                      {item.subtitle}
                    </span>
                  </span>
                  <span className="fm-secondary" aria-hidden="true">
                    ›
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        </GlassCard>

        <GlassCard>
          <div style={{ fontWeight: 600, marginBottom: 4 }}>Settings</div>
          <div className="fm-secondary" style={{ fontSize: 14 }}>
            Appearance, currency, and account settings arrive in a later milestone
            (docs/08). Light/dark already follow the system via the Liquid Glass tokens.
          </div>
        </GlassCard>
      </div>
    </Page>
  );
}
