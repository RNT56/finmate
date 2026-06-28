// BTC Calculator page (M5) — fiat -> BTC/sats via the existing CurrencyConverter
// and sample rates (product spec §10). Example: €500 @ €50,000/BTC = 0.01 BTC =
// 1,000,000 sats. Conversion is display-only and non-mutating (docs/13 §2); in
// production the rates come from the market-data Edge Function (ADR-0010).

import { useMemo, useState } from 'react';
import { GlassCard } from '../../components/GlassCard';
import { Page } from '../../components/AppShell';
import {
  CurrencyConverter,
  type CurrencyCode,
  btcFromSats,
} from '../../core/currency';
import { formatMoney, parseMoney } from '../../core/money';
import { SAMPLE_ASSET_RATES } from '../assets/useAssets';

const FIAT: CurrencyCode[] = ['EUR', 'USD'];

export function Calculator() {
  const [amount, setAmount] = useState('500');
  const [fiat, setFiat] = useState<CurrencyCode>('EUR');
  const converter = useMemo(() => new CurrencyConverter(SAMPLE_ASSET_RATES), []);

  const result = useMemo(() => {
    let minor: number;
    try {
      minor = parseMoney(amount, fiat);
    } catch {
      return null;
    }
    const sats = converter.convert(minor, fiat, 'BTC');
    if (!sats.ok) return null;
    return {
      fiatMinor: minor,
      sats: sats.minorUnits,
      btc: btcFromSats(sats.minorUnits),
    };
  }, [amount, fiat, converter]);

  const btcEur = SAMPLE_ASSET_RATES.btcEur;
  const btcUsd = SAMPLE_ASSET_RATES.btcUsd;

  return (
    <Page title="BTC Calculator">
      <div className="fm-stack">
        <GlassCard>
          <div style={{ display: 'flex', gap: 10, alignItems: 'flex-end', flexWrap: 'wrap' }}>
            <div style={{ flex: 1, minWidth: 160 }}>
              <label className="fm-field-label" htmlFor="calc-amount">
                Amount
              </label>
              <input
                id="calc-amount"
                className="fm-input"
                inputMode="decimal"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                placeholder="500"
              />
            </div>
            <div style={{ width: 120 }}>
              <label className="fm-field-label" htmlFor="calc-currency">
                Currency
              </label>
              <select
                id="calc-currency"
                className="fm-select"
                value={fiat}
                onChange={(e) => setFiat(e.target.value as CurrencyCode)}
              >
                {FIAT.map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
              </select>
            </div>
          </div>
        </GlassCard>

        <GlassCard>
          <div className="fm-secondary" style={{ fontWeight: 600, fontSize: 14 }}>
            Converts to
          </div>
          {result === null ? (
            <div className="fm-error" style={{ marginTop: 8 }}>
              Enter a valid amount.
            </div>
          ) : (
            <>
              <div className="fm-hero-amount" style={{ marginTop: 6 }} aria-live="polite">
                {result.btc.toLocaleString('en-US', { maximumFractionDigits: 8 })} BTC
              </div>
              <div className="fm-amount" style={{ marginTop: 4, fontSize: 18 }}>
                {formatMoney(result.sats, 'BTC')}
              </div>
              <div className="fm-secondary" style={{ marginTop: 8, fontSize: 13 }}>
                {formatMoney(result.fiatMinor, fiat)} at{' '}
                {fiat === 'EUR'
                  ? `€${btcEur.toLocaleString('en-US')}`
                  : `$${btcUsd.toLocaleString('en-US')}`}{' '}
                / BTC
              </div>
            </>
          )}
        </GlassCard>

        <GlassCard>
          <div className="fm-secondary" style={{ fontWeight: 600, fontSize: 14, marginBottom: 8 }}>
            Sample rates
          </div>
          <ul style={{ listStyle: 'none', margin: 0, padding: 0 }}>
            <RateRow label="BTC / EUR" value={`€${btcEur.toLocaleString('en-US')}`} />
            <RateRow label="BTC / USD" value={`$${btcUsd.toLocaleString('en-US')}`} />
            <RateRow
              label="EUR / USD"
              value={SAMPLE_ASSET_RATES.eurUsd.toFixed(2)}
            />
          </ul>
          <div className="fm-secondary" style={{ fontSize: 12, marginTop: 8 }}>
            Rates are illustrative. Live rates come from the server-side market-data
            function (ADR-0010), never the client.
          </div>
        </GlassCard>
      </div>
    </Page>
  );
}

function RateRow({ label, value }: { label: string; value: string }) {
  return (
    <li
      style={{
        display: 'flex',
        justifyContent: 'space-between',
        padding: '8px 0',
        borderTop: '1px solid var(--fm-glass-border)',
      }}
    >
      <span className="fm-secondary">{label}</span>
      <span className="fm-amount">{value}</span>
    </li>
  );
}
