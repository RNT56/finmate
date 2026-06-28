// Home — the customizable, reorderable dashboard (M7-HOME, docs/02 §3). Cards are
// rendered from the resolved order (core/dashboard) and can be reordered and
// shown/hidden in Edit mode; the layout persists to localStorage today, the
// `dashboard_layouts.card_order` table eventually (docs/05 §3.11). All money
// figures come from the existing feature hooks — one source of truth per pillar.

import { useMemo, useState, type DragEvent, type ReactNode } from 'react';
import { GlassCard } from './GlassCard';
import { Page } from './AppShell';
import { useSubscriptions } from '../features/subscriptions/useSubscriptions';
import { useCashFlow } from '../features/cashflow/useCashFlow';
import { useAssets } from '../features/assets/useAssets';
import { useCalendar } from '../features/calendar/useCalendar';
import { useDashboardLayout } from '../features/home/useDashboardLayout';
import { type DashboardCardId, cardTitles } from '../core/dashboard';
import { formatMoney } from '../core/money';

interface CardContent {
  label: string;
  value: string;
  detail?: string;
  /** 'up' | 'down' tints the value (gain/loss, net sign); undefined = neutral. */
  tone?: 'up' | 'down';
}

function formatSignedMoney(minor: number, currency: 'EUR' | 'USD' | 'BTC', locale: string): string {
  const sign = minor > 0 ? '+' : '';
  return `${sign}${formatMoney(minor, currency, locale)}`;
}

/** Build the live content for every card from the feature hooks. */
function useCardContent(): { content: Record<DashboardCardId, CardContent>; loading: boolean } {
  const { subscriptions, monthlyTotalMinor, loading: subsLoading } = useSubscriptions();
  const { metrics, loading: cfLoading } = useCashFlow();
  const { totalValueMinor, totalGainMinor, totalGainPct, loading: assetsLoading } =
    useAssets('EUR');
  const { events, loading: calLoading } = useCalendar();

  const subsTotal = monthlyTotalMinor('EUR');

  const upcomingCharges = useMemo(
    () => events.filter((e) => e.kind === 'subscription' || e.kind === 'fixedExpense'),
    [events],
  );
  const upcomingChargesMinor = useMemo(
    () => upcomingCharges.reduce((sum, e) => sum + e.amountMinor, 0),
    [upcomingCharges],
  );

  const content: Record<DashboardCardId, CardContent> = {
    subscriptionsTotal: {
      label: cardTitles.subscriptionsTotal,
      value: formatMoney(subsTotal, 'EUR', 'de-DE'),
      detail: `${formatMoney(subsTotal * 12, 'EUR', 'de-DE')} / year`,
    },
    netCashFlow: {
      label: cardTitles.netCashFlow,
      value: formatSignedMoney(metrics.netMinor, 'EUR', 'de-DE'),
      detail: `${formatMoney(metrics.incomeMinor, 'EUR', 'de-DE')} in · ${formatMoney(
        metrics.expenseMinor,
        'EUR',
        'de-DE',
      )} out`,
      tone: metrics.netMinor >= 0 ? 'up' : 'down',
    },
    savingsRate: {
      label: cardTitles.savingsRate,
      value: `${(metrics.savingsRate * 100).toFixed(1)}%`,
      detail: 'of monthly income kept',
      tone: metrics.savingsRate >= 0 ? 'up' : 'down',
    },
    portfolioValue: {
      label: cardTitles.portfolioValue,
      value: formatMoney(totalValueMinor, 'EUR', 'de-DE'),
      detail: `${formatSignedMoney(totalGainMinor, 'EUR', 'de-DE')} (${(totalGainPct * 100).toFixed(1)}%)`,
      tone: totalGainMinor >= 0 ? 'up' : 'down',
    },
    upcomingCharges: {
      label: cardTitles.upcomingCharges,
      value: formatMoney(upcomingChargesMinor, 'EUR', 'de-DE'),
      detail: `${upcomingCharges.length} charge${upcomingCharges.length === 1 ? '' : 's'} this month`,
    },
    activeServices: {
      label: cardTitles.activeServices,
      value: String(subscriptions.length),
      detail: `tracked subscription${subscriptions.length === 1 ? '' : 's'}`,
    },
  };

  return {
    content,
    loading: subsLoading || cfLoading || assetsLoading || calLoading,
  };
}

function ValueCard({ content }: { content: CardContent }) {
  const toneColor =
    content.tone === 'up'
      ? 'var(--fm-up)'
      : content.tone === 'down'
        ? 'var(--fm-down)'
        : 'var(--fm-label)';
  return (
    <>
      <div className="fm-secondary" style={{ fontWeight: 600, fontSize: 14 }}>
        {content.label}
      </div>
      <div
        className="fm-amount"
        style={{ fontSize: 28, marginTop: 6, color: toneColor }}
        aria-live="polite"
      >
        {content.value}
      </div>
      {content.detail && (
        <div className="fm-secondary" style={{ marginTop: 4, fontSize: 13 }}>
          {content.detail}
        </div>
      )}
    </>
  );
}

export function Home() {
  const layout = useDashboardLayout();
  const { content, loading } = useCardContent();
  const [editing, setEditing] = useState(false);
  const [dragIndex, setDragIndex] = useState<number | null>(null);
  const [dropIndex, setDropIndex] = useState<number | null>(null);

  const onDragStart = (index: number) => (e: DragEvent) => {
    setDragIndex(index);
    e.dataTransfer.effectAllowed = 'move';
  };
  const onDragOver = (index: number) => (e: DragEvent) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = 'move';
    if (index !== dropIndex) setDropIndex(index);
  };
  const onDrop = (index: number) => (e: DragEvent) => {
    e.preventDefault();
    if (dragIndex !== null && dragIndex !== index) {
      layout.reorder(dragIndex, index);
    }
    setDragIndex(null);
    setDropIndex(null);
  };
  const onDragEnd = () => {
    setDragIndex(null);
    setDropIndex(null);
  };

  const editToggle = (
    <button
      type="button"
      className={`fm-btn fm-btn-sm ${editing ? '' : 'fm-btn-ghost'}`}
      onClick={() => setEditing((v) => !v)}
      aria-pressed={editing}
    >
      {editing ? 'Done' : 'Edit'}
    </button>
  );

  // EDIT MODE: full order, with reorder + show/hide controls (accessible).
  if (editing) {
    return (
      <Page title="Home">
        <div className="fm-stack">
          <div className="fm-dash-toolbar">
            <div className="fm-secondary" style={{ fontSize: 14 }}>
              Drag, or use the arrows, to reorder. Toggle a card to show or hide it.
            </div>
            <div className="fm-row" style={{ gap: 8 }}>
              <button type="button" className="fm-btn fm-btn-ghost fm-btn-sm" onClick={layout.reset}>
                Reset
              </button>
              {editToggle}
            </div>
          </div>

          <ul className="fm-stack" style={{ listStyle: 'none', margin: 0, padding: 0 }} aria-label="Dashboard cards">
            {layout.order.map((id, index) => {
              const hidden = layout.isHidden(id);
              const cardClass = [
                'fm-dash-card',
                dragIndex === index ? 'fm-dash-card-dragging' : '',
                dropIndex === index && dragIndex !== null ? 'fm-dash-card-drop' : '',
              ]
                .filter(Boolean)
                .join(' ');
              return (
                <li key={id}>
                  <GlassCard
                    className={cardClass}
                    style={hidden ? { opacity: 0.5 } : undefined}
                  >
                    <div
                      className="fm-dash-editrow"
                      draggable
                      onDragStart={onDragStart(index)}
                      onDragOver={onDragOver(index)}
                      onDrop={onDrop(index)}
                      onDragEnd={onDragEnd}
                    >
                      <div className="fm-dash-handle">
                        <button
                          type="button"
                          className="fm-iconbtn"
                          onClick={() => layout.moveUp(index)}
                          disabled={index === 0}
                          aria-label={`Move ${cardTitles[id]} up`}
                        >
                          ↑
                        </button>
                        <button
                          type="button"
                          className="fm-iconbtn"
                          onClick={() => layout.moveDown(index)}
                          disabled={index === layout.order.length - 1}
                          aria-label={`Move ${cardTitles[id]} down`}
                        >
                          ↓
                        </button>
                      </div>
                      <div style={{ flex: 1, minWidth: 0 }}>
                        <div style={{ fontWeight: 600 }}>{cardTitles[id]}</div>
                        <div className="fm-secondary" style={{ fontSize: 13 }}>
                          {content[id].value}
                        </div>
                      </div>
                      <button
                        type="button"
                        role="switch"
                        aria-checked={!hidden}
                        aria-label={`Show ${cardTitles[id]}`}
                        className="fm-toggle"
                        data-on={(!hidden).toString()}
                        onClick={() => layout.toggle(id)}
                      >
                        <span className="fm-toggle-knob" />
                      </button>
                    </div>
                  </GlassCard>
                </li>
              );
            })}
          </ul>
        </div>
      </Page>
    );
  }

  // VIEW MODE: only visible cards, in resolved order. First card is the hero.
  const visible = layout.visibleOrder;
  const renderCard = (id: DashboardCardId): ReactNode => (
    <GlassCard key={id}>
      <ValueCard content={loading ? { ...content[id], value: '—', detail: undefined } : content[id]} />
    </GlassCard>
  );

  return (
    <Page title="Home">
      <div className="fm-stack">
        <div className="fm-dash-toolbar">
          <div className="fm-secondary" style={{ fontSize: 14 }}>
            Your overview at a glance
          </div>
          {editToggle}
        </div>

        {visible.length === 0 ? (
          <GlassCard>
            <div className="fm-empty">
              No cards shown. Tap <strong>Edit</strong> to add some back.
            </div>
          </GlassCard>
        ) : (
          <div
            style={{
              display: 'grid',
              gap: 'var(--fm-spacing)',
              gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))',
            }}
          >
            {visible.map(renderCard)}
          </div>
        )}
      </div>
    </Page>
  );
}
