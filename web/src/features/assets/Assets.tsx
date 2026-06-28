// Assets page (M5) — portfolio total + total gain/loss KPIs, a distribution donut
// by asset type, and an asset list with per-asset value + gain/loss. A display-
// currency switcher (EUR/USD/BTC) re-converts the totals (non-mutating; product
// spec §9 + §11). All figures come from core/assets; one glass language.

import { useState } from 'react';
import { GlassCard } from '../../components/GlassCard';
import { EmptyState } from '../../components/EmptyState';
import { ErrorCard } from '../../components/ErrorCard';
import { SkeletonList } from '../../components/Skeleton';
import { ChartDataTable } from '../../components/ChartDataTable';
import { Page } from '../../components/AppShell';
import { formatMoney } from '../../core/money';
import { describeAllocation } from '../../core/chartDescription';
import type { CurrencyCode } from '../../core/currency';
import {
  type AssetSlice,
  type AssetType,
  type FinancialAsset,
  assetTypeLabel,
  gainPct,
  unrealizedGainMinor,
} from '../../core/assets';
import { useAssets } from './useAssets';
import { AssetModal } from './AssetModal';
import { TransactionModal } from './TransactionModal';

const DISPLAY_CURRENCIES: CurrencyCode[] = ['EUR', 'USD', 'BTC'];

// Stable per-type palette drawn from the glass tokens (docs/06 §3.2).
const TYPE_COLOR: Record<AssetType, string> = {
  crypto: 'var(--fm-btc)',
  stock: 'var(--fm-accent)',
  etf: 'var(--fm-flow-violet)',
  cash: 'var(--fm-up)',
  other: 'var(--fm-neutral)',
};

export function Assets() {
  const [displayCurrency, setDisplayCurrency] = useState<CurrencyCode>('EUR');
  const {
    loading,
    error,
    reload,
    assets,
    totalValueMinor,
    totalGainMinor,
    totalGainPct,
    distribution,
    saveAsset,
    removeAsset,
    recordTransaction,
  } = useAssets(displayCurrency);

  // null = closed; { existing: null } = add; { existing: asset } = edit.
  const [assetModal, setAssetModal] = useState<{
    existing: FinancialAsset | null;
  } | null>(null);
  const [txnAsset, setTxnAsset] = useState<FinancialAsset | null>(null);

  const fmt = (minor: number) => formatMoney(minor, displayCurrency);
  const gainPositive = totalGainMinor >= 0;

  if (error) {
    return (
      <Page title="Assets">
        <ErrorCard
          title="Couldn't load assets"
          message={error}
          onRetry={() => void reload()}
        />
      </Page>
    );
  }

  if (loading) {
    return (
      <Page title="Assets">
        <SkeletonList count={4} />
      </Page>
    );
  }

  if (assets.length === 0) {
    return (
      <Page title="Assets">
        <EmptyState
          icon="◆"
          title="No assets yet"
          message="Add your crypto, stocks, ETFs, or cash to track portfolio value and gains."
          cta={{
            label: '+ Add asset',
            onClick: () => setAssetModal({ existing: null }),
          }}
        />
        {assetModal && (
          <AssetModal
            existing={assetModal.existing}
            onClose={() => setAssetModal(null)}
            onSave={async (asset) => {
              await saveAsset(asset);
              setAssetModal(null);
            }}
          />
        )}
      </Page>
    );
  }

  return (
    <Page title="Assets">
      <div className="fm-stack">
        <GlassCard>
          <div
            style={{
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'flex-start',
              gap: 12,
              flexWrap: 'wrap',
            }}
          >
            <div>
              <div
                className="fm-secondary"
                style={{ fontWeight: 600, fontSize: 14 }}
              >
                Portfolio value
              </div>
              <div
                className="fm-hero-amount"
                style={{ marginTop: 4 }}
                aria-live="polite"
              >
                {loading ? '—' : fmt(totalValueMinor)}
              </div>
              <div
                className="fm-amount"
                style={{
                  marginTop: 6,
                  fontSize: 16,
                  color: gainPositive ? 'var(--fm-up)' : 'var(--fm-down)',
                }}
              >
                {loading
                  ? ''
                  : `${gainPositive ? '▲' : '▼'} ${fmt(Math.abs(totalGainMinor))} (${(
                      totalGainPct * 100
                    ).toFixed(1)}%)`}
              </div>
            </div>
            <CurrencySwitcher
              value={displayCurrency}
              onChange={setDisplayCurrency}
            />
          </div>
        </GlassCard>

        <GlassCard>
          <div
            className="fm-secondary"
            style={{ fontWeight: 600, fontSize: 14, marginBottom: 12 }}
          >
            Allocation by type
          </div>
          {distribution.length === 0 ? (
            <div className="fm-secondary">No assets yet.</div>
          ) : (
            <div
              style={{
                display: 'flex',
                gap: 24,
                alignItems: 'center',
                flexWrap: 'wrap',
              }}
            >
              <DistributionDonut slices={distribution} format={fmt} />
              <ul
                style={{
                  listStyle: 'none',
                  margin: 0,
                  padding: 0,
                  flex: 1,
                  minWidth: 180,
                }}
              >
                {distribution.map((s) => (
                  <li
                    key={s.type}
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      gap: 10,
                      padding: '6px 0',
                    }}
                  >
                    <span
                      aria-hidden="true"
                      style={{
                        width: 12,
                        height: 12,
                        borderRadius: 3,
                        background: TYPE_COLOR[s.type],
                        flexShrink: 0,
                      }}
                    />
                    <span style={{ flex: 1 }}>{assetTypeLabel(s.type)}</span>
                    <span className="fm-secondary" style={{ fontSize: 13 }}>
                      {(s.share * 100).toFixed(0)}%
                    </span>
                    <span className="fm-amount">{fmt(s.totalMinor)}</span>
                  </li>
                ))}
              </ul>
            </div>
          )}
        </GlassCard>

        <GlassCard>
          <div
            className="fm-row"
            style={{
              justifyContent: 'space-between',
              alignItems: 'center',
              marginBottom: 8,
            }}
          >
            <span
              className="fm-secondary"
              style={{ fontWeight: 600, fontSize: 14 }}
            >
              Holdings
            </span>
            <button
              type="button"
              className="fm-btn"
              style={{ padding: '6px 12px', fontSize: 13 }}
              onClick={() => setAssetModal({ existing: null })}
            >
              + Add asset
            </button>
          </div>
          <ul style={{ listStyle: 'none', margin: 0, padding: 0 }}>
            {assets.map((a) => (
              <AssetRow
                key={a.id}
                asset={a}
                onEdit={() => setAssetModal({ existing: a })}
                onTransaction={() => setTxnAsset(a)}
                onDelete={() => void removeAsset(a.id)}
              />
            ))}
            {!loading && assets.length === 0 && (
              <li className="fm-secondary" style={{ padding: '8px 0' }}>
                No holdings tracked yet.
              </li>
            )}
          </ul>
        </GlassCard>
      </div>

      {assetModal && (
        <AssetModal
          existing={assetModal.existing}
          onClose={() => setAssetModal(null)}
          onSave={async (asset) => {
            await saveAsset(asset);
            setAssetModal(null);
          }}
        />
      )}

      {txnAsset && (
        <TransactionModal
          asset={txnAsset}
          onClose={() => setTxnAsset(null)}
          onSubmit={async (input) => {
            await recordTransaction(txnAsset.id, input);
            setTxnAsset(null);
          }}
        />
      )}
    </Page>
  );
}

function CurrencySwitcher({
  value,
  onChange,
}: {
  value: CurrencyCode;
  onChange: (c: CurrencyCode) => void;
}) {
  return (
    <div
      role="group"
      aria-label="Display currency"
      style={{ display: 'flex', gap: 6 }}
    >
      {DISPLAY_CURRENCIES.map((c) => (
        <button
          key={c}
          type="button"
          className={c === value ? 'fm-btn' : 'fm-btn fm-btn-ghost'}
          style={{ padding: '6px 12px', fontSize: 13 }}
          aria-pressed={c === value}
          onClick={() => onChange(c)}
        >
          {c}
        </button>
      ))}
    </div>
  );
}

/** A holding row shown in its own native currency (the per-asset figures are stored). */
function AssetRow({
  asset,
  onEdit,
  onTransaction,
  onDelete,
}: {
  asset: FinancialAsset;
  onEdit: () => void;
  onTransaction: () => void;
  onDelete: () => void;
}) {
  const gain = unrealizedGainMinor(asset);
  const pct = gainPct(asset) * 100;
  const positive = gain >= 0;
  return (
    <li
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: 14,
        padding: '10px 0',
        borderTop: '1px solid var(--fm-glass-border)',
        flexWrap: 'wrap',
      }}
    >
      <span
        className="fm-icon-tile"
        style={{ color: TYPE_COLOR[asset.type] }}
        aria-hidden="true"
      >
        {assetTypeLabel(asset.type).charAt(0)}
      </span>
      <span style={{ flex: 1, minWidth: 0 }}>
        <span style={{ fontWeight: 600, display: 'block' }}>{asset.name}</span>
        <span className="fm-secondary" style={{ fontSize: 13 }}>
          {assetTypeLabel(asset.type)} · {asset.quantity} units
        </span>
      </span>
      <span style={{ textAlign: 'right' }}>
        <span className="fm-amount" style={{ display: 'block' }}>
          {formatMoney(asset.valueMinor, asset.currency)}
        </span>
        <span
          style={{
            fontSize: 13,
            fontWeight: 600,
            color: positive ? 'var(--fm-up)' : 'var(--fm-down)',
          }}
        >
          {positive ? '+' : '−'}
          {formatMoney(Math.abs(gain), asset.currency)} ({pct.toFixed(1)}%)
        </span>
      </span>
      <span className="fm-row" style={{ gap: 6 }}>
        <button
          type="button"
          className="fm-btn fm-btn-ghost"
          style={{ padding: '6px 10px', fontSize: 13 }}
          aria-label={`Record transaction for ${asset.name}`}
          onClick={onTransaction}
        >
          Txn
        </button>
        <button
          type="button"
          className="fm-btn fm-btn-ghost"
          style={{ padding: '6px 10px', fontSize: 13 }}
          aria-label={`Edit ${asset.name}`}
          onClick={onEdit}
        >
          Edit
        </button>
        <button
          type="button"
          className="fm-btn fm-btn-ghost"
          style={{ padding: '6px 10px', fontSize: 13 }}
          aria-label={`Delete ${asset.name}`}
          onClick={onDelete}
        >
          Delete
        </button>
      </span>
    </li>
  );
}

/** Inline-SVG donut of the by-type distribution (mirrors the iOS Swift Charts donut). */
function DistributionDonut({
  slices,
  format,
}: {
  slices: AssetSlice[];
  format: (minor: number) => string;
}) {
  const size = 160;
  const cx = size / 2;
  const cy = size / 2;
  const r = 64;
  const stroke = 26;
  const circumference = 2 * Math.PI * r;
  let offset = 0;
  const { summary, rows } = describeAllocation(slices, format);

  return (
    <div>
      <span className="fm-sr-only" role="img" aria-label={summary} />
      <ChartDataTable
        caption="Portfolio allocation by asset type"
        labelHeader="Type"
        valueHeader="Share and value"
        rows={rows}
      />
      <svg
        viewBox={`0 0 ${size} ${size}`}
        width={size}
        height={size}
        aria-hidden="true"
      >
        <circle
          cx={cx}
          cy={cy}
          r={r}
          fill="none"
          stroke="var(--fm-glass-border)"
          strokeWidth={stroke}
        />
        {slices.map((s) => {
          const len = s.share * circumference;
          const seg = (
            <circle
              key={s.type}
              cx={cx}
              cy={cy}
              r={r}
              fill="none"
              stroke={TYPE_COLOR[s.type]}
              strokeWidth={stroke}
              strokeDasharray={`${len} ${circumference - len}`}
              strokeDashoffset={-offset}
              transform={`rotate(-90 ${cx} ${cy})`}
            />
          );
          offset += len;
          return seg;
        })}
        <text
          x={cx}
          y={cy + 5}
          textAnchor="middle"
          fontSize={15}
          fontWeight={650}
          fill="currentColor"
        >
          {slices.length} types
        </text>
      </svg>
    </div>
  );
}
