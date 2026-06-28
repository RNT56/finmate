// Home dashboard — the monthly-burn card computes the live monthly EUR total via
// the core normalization + conversion (docs/13 §6.2). Sample data renders €26.48,
// matching the iOS slice.

import { GlassCard } from './GlassCard';
import { Page } from './AppShell';
import { useSubscriptions } from '../features/subscriptions/useSubscriptions';
import { formatMoney } from '../core/money';

export function Home() {
  const { subscriptions, monthlyTotalMinor, loading } = useSubscriptions();
  const totalMinor = monthlyTotalMinor('EUR');

  return (
    <Page title="Home">
      <div className="fm-stack">
        <GlassCard>
          <div className="fm-secondary" style={{ fontWeight: 600, fontSize: 14 }}>
            Monthly subscriptions
          </div>
          <div className="fm-hero-amount" aria-live="polite">
            {loading ? '—' : formatMoney(totalMinor, 'EUR', 'de-DE')}
          </div>
          <div className="fm-secondary" style={{ marginTop: 4 }}>
            {subscriptions.length} active service{subscriptions.length === 1 ? '' : 's'}, normalized
            to a monthly equivalent
          </div>
        </GlassCard>

        <div
          style={{
            display: 'grid',
            gap: 'var(--fm-spacing)',
            gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))',
          }}
        >
          <GlassCard>
            <div className="fm-secondary" style={{ fontWeight: 600, fontSize: 14 }}>
              Annual equivalent
            </div>
            <div className="fm-amount" style={{ fontSize: 24, marginTop: 6 }}>
              {formatMoney(totalMinor * 12, 'EUR', 'de-DE')}
            </div>
          </GlassCard>
          <GlassCard>
            <div className="fm-secondary" style={{ fontWeight: 600, fontSize: 14 }}>
              Tracked services
            </div>
            <div className="fm-amount" style={{ fontSize: 24, marginTop: 6 }}>
              {subscriptions.length}
            </div>
          </GlassCard>
        </div>
      </div>
    </Page>
  );
}
