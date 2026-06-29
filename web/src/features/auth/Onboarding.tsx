// First-run onboarding (docs/02 §2): pick a default display currency + appearance,
// reusing the existing preferences store. Completing marks the browser onboarded so
// the guard sends the user into the app. One Liquid Glass language.

import { GlassCard } from '../../components/GlassCard';
import { usePreferences } from '../settings/usePreferences';
import type { Appearance } from '../../core/preferences';
import type { CurrencyCode } from '../../core/currency';

const APPEARANCES: { value: Appearance; label: string }[] = [
  { value: 'system', label: 'System' },
  { value: 'light', label: 'Light' },
  { value: 'dark', label: 'Dark' },
];

const CURRENCIES: CurrencyCode[] = ['EUR', 'USD', 'BTC'];

export function Onboarding({ onComplete }: { onComplete: () => void }) {
  const { preferences, update } = usePreferences();

  return (
    <div className="fm-auth-screen">
      <div style={{ width: '100%', maxWidth: '28rem' }}>
        <div className="fm-brand" style={{ justifyContent: 'center', marginBottom: '1.5rem' }}>
          <span className="fm-brand-dot" aria-hidden="true" />
          Finmate
        </div>

        <GlassCard>
          <h1 style={{ fontSize: '1.25rem', fontWeight: 700, margin: '0 0 0.25rem' }}>
            Let&apos;s set you up
          </h1>
          <p className="fm-secondary" style={{ fontSize: '0.875rem', margin: '0 0 1.5rem' }}>
            A couple of quick choices — you can change these anytime in Settings.
          </p>

          <div className="fm-stack" style={{ gap: '1.25rem' }}>
            <Field label="Default display currency">
              <Segmented
                groupLabel="Default display currency"
                options={CURRENCIES.map((c) => ({ value: c, label: c }))}
                value={preferences.defaultCurrency}
                onChange={(defaultCurrency) => update({ defaultCurrency })}
              />
            </Field>

            <Field label="Appearance">
              <Segmented
                groupLabel="Appearance"
                options={APPEARANCES}
                value={preferences.appearance}
                onChange={(appearance) => update({ appearance })}
              />
            </Field>
          </div>

          <button
            type="button"
            className="fm-btn"
            style={{ width: '100%', justifyContent: 'center', marginTop: '1.75rem' }}
            data-testid="onboarding-continue"
            onClick={onComplete}
          >
            Get started →
          </button>
        </GlassCard>
      </div>
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <div style={{ fontWeight: 600, marginBottom: '0.5rem' }}>{label}</div>
      {children}
    </div>
  );
}

function Segmented<T extends string>({
  groupLabel,
  options,
  value,
  onChange,
}: {
  groupLabel: string;
  options: { value: T; label: string }[];
  value: T;
  onChange: (value: T) => void;
}) {
  return (
    <div className="fm-segment" role="group" aria-label={groupLabel} style={{ display: 'flex' }}>
      {options.map((opt) => (
        <button
          key={opt.value}
          type="button"
          className="fm-segment-item"
          style={{ flex: 1 }}
          aria-pressed={opt.value === value}
          onClick={() => onChange(opt.value)}
        >
          {opt.label}
        </button>
      ))}
    </div>
  );
}
