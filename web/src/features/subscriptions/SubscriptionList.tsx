// SubscriptionList — mirrors the iOS SubscriptionsListView. Each row shows the
// monthly-equivalent amount computed via core normalization.

import { useState } from 'react';
import { GlassCard } from '../../components/GlassCard';
import { EmptyState } from '../../components/EmptyState';
import { ErrorCard } from '../../components/ErrorCard';
import { SkeletonList } from '../../components/Skeleton';
import { Page } from '../../components/AppShell';
import { useSubscriptions } from './useSubscriptions';
import { monthlyAmountMinor } from './types';
import { formatMoney } from '../../core/money';
import { AddSubscription } from './AddSubscription';

export function SubscriptionList() {
  const { subscriptions, loading, error, reload, add } = useSubscriptions();
  const [showAdd, setShowAdd] = useState(false);

  return (
    <Page title="Subscriptions">
      <div
        className="fm-row"
        style={{ justifyContent: 'space-between', marginBottom: 18 }}
      >
        <span className="fm-secondary">
          {loading
            ? 'Loading…'
            : `${subscriptions.length} service${subscriptions.length === 1 ? '' : 's'}`}
        </span>
        <button
          className="fm-btn"
          data-testid="add-subscription"
          onClick={() => setShowAdd(true)}
        >
          + Add subscription
        </button>
      </div>

      {error ? (
        <ErrorCard
          title="Couldn't load subscriptions"
          message={error}
          onRetry={() => void reload()}
        />
      ) : loading ? (
        <SkeletonList count={3} />
      ) : subscriptions.length === 0 ? (
        <EmptyState
          icon="⟳"
          title="No subscriptions yet"
          message="Track recurring services to see your monthly spend and upcoming charges."
          cta={{ label: '+ Add subscription', onClick: () => setShowAdd(true) }}
        />
      ) : (
        <div className="fm-stack">
          {subscriptions.map((sub) => (
            <GlassCard key={sub.id}>
              <div
                className="fm-row"
                style={{ justifyContent: 'space-between' }}
              >
                <div className="fm-row">
                  <span className="fm-icon-tile" aria-hidden="true">
                    {sub.name.charAt(0).toUpperCase()}
                  </span>
                  <div>
                    <div style={{ fontWeight: 650 }}>{sub.name}</div>
                    <div className="fm-secondary" style={{ fontSize: 13 }}>
                      <span className="fm-badge">{sub.categoryName}</span>{' '}
                      {sub.billingPeriod} · {sub.usageState}
                    </div>
                  </div>
                </div>
                <div style={{ textAlign: 'right' }}>
                  <div className="fm-amount">
                    {formatMoney(
                      monthlyAmountMinor(sub),
                      sub.currency,
                      'de-DE'
                    )}
                  </div>
                  <div className="fm-secondary" style={{ fontSize: 12 }}>
                    / mo
                  </div>
                </div>
              </div>
            </GlassCard>
          ))}
        </div>
      )}

      {showAdd && (
        <AddSubscription
          onClose={() => setShowAdd(false)}
          onSave={async (sub) => {
            await add(sub);
            setShowAdd(false);
          }}
        />
      )}
    </Page>
  );
}
