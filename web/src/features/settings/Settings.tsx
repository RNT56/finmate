// Settings page (M7) — replaces the More Settings stub with the real surface:
// Appearance (System/Light/Dark, applied app-wide), Default display currency,
// Reminders (toggles + lead-time), Privacy (biometric lock is iOS-only),
// Data (export + delete account stubs), and About. One Liquid Glass language,
// reusing GlassCard + glass tokens. Accessibility: aria-labels on icon-only /
// segmented controls, rem-based type so it scales, and native form semantics.

import type { ReactNode } from 'react';
import { GlassCard } from '../../components/GlassCard';
import { Page } from '../../components/AppShell';
import type { Appearance } from '../../core/preferences';
import {
  MIN_REMINDER_LEAD_TIME_DAYS,
  MAX_REMINDER_LEAD_TIME_DAYS,
} from '../../core/preferences';
import type { CurrencyCode } from '../../core/currency';
import { usePreferences } from './usePreferences';
import {
  buildExportBundle,
  downloadExportBundle,
  type ExportSources,
} from '../../core/dataExport';
import { getRepositories } from '../../lib/repositories';
import { useAuth } from '../auth/useAuth';

const APPEARANCES: { value: Appearance; label: string }[] = [
  { value: 'system', label: 'System' },
  { value: 'light', label: 'Light' },
  { value: 'dark', label: 'Dark' },
];

const CURRENCIES: CurrencyCode[] = ['EUR', 'USD', 'BTC'];

export function Settings() {
  const { preferences, update } = usePreferences();
  const { user, signOut } = useAuth();

  // Wire Export Data (docs/07 §9.3): read every owned entity from the SELECTED
  // repositories (Supabase when configured, in-memory sample otherwise — the same
  // selection the rest of the app uses) and download a round-trippable JSON bundle
  // with money kept as raw minor units + currency.
  const handleExport = async () => {
    try {
      const repos = getRepositories();
      const sources: ExportSources = {
        subscriptions: () => repos.subscriptions.all(),
        incomeSources: () => repos.cashFlow.incomes(),
        fixedExpenses: () => repos.cashFlow.fixedExpenses(),
        variableExpenses: () => repos.cashFlow.variableExpenses(),
        financialAssets: () => repos.assets.all(),
        preferences: () => preferences,
      };
      const bundle = await buildExportBundle(sources);
      downloadExportBundle(bundle);
    } catch {
      window.alert('Export failed. Please try again.');
    }
  };

  return (
    <Page title="Settings">
      <div className="fm-stack">
        {/* ---- Appearance ---- */}
        <Section title="Appearance">
          <SettingRow label="Theme" hint="System follows your device's light or dark setting.">
            <SegmentedControl
              groupLabel="Appearance"
              options={APPEARANCES}
              value={preferences.appearance}
              onChange={(appearance) => update({ appearance })}
            />
          </SettingRow>
        </Section>

        {/* ---- Default display currency ---- */}
        <Section title="Currency">
          <SettingRow
            label="Default display currency"
            hint="Used as the starting currency across analytics and conversions."
          >
            <SegmentedControl
              groupLabel="Default display currency"
              options={CURRENCIES.map((c) => ({ value: c, label: c }))}
              value={preferences.defaultCurrency}
              onChange={(defaultCurrency) => update({ defaultCurrency })}
            />
          </SettingRow>
        </Section>

        {/* ---- Reminders ---- */}
        <Section title="Reminders">
          <SettingRow label="Payment reminders" hint="Notify before a subscription or expense is charged.">
            <Toggle
              label="Payment reminders"
              checked={preferences.paymentRemindersEnabled}
              onChange={(paymentRemindersEnabled) => update({ paymentRemindersEnabled })}
            />
          </SettingRow>
          <SettingRow label="Payday reminders" hint="Notify when income is expected.">
            <Toggle
              label="Payday reminders"
              checked={preferences.paydayRemindersEnabled}
              onChange={(paydayRemindersEnabled) => update({ paydayRemindersEnabled })}
            />
          </SettingRow>
          <SettingRow
            label="Lead time"
            hint={`How many days ahead to remind you (${MIN_REMINDER_LEAD_TIME_DAYS}–${MAX_REMINDER_LEAD_TIME_DAYS}).`}
          >
            <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
              <input
                type="number"
                className="fm-input"
                style={{ width: '5rem' }}
                min={MIN_REMINDER_LEAD_TIME_DAYS}
                max={MAX_REMINDER_LEAD_TIME_DAYS}
                step={1}
                value={preferences.reminderLeadTimeDays}
                aria-label="Reminder lead time in days"
                onChange={(e) => update({ reminderLeadTimeDays: Number(e.target.value) })}
              />
              <span className="fm-secondary" style={{ fontSize: '0.875rem' }}>
                days
              </span>
            </div>
          </SettingRow>
        </Section>

        {/* ---- Privacy ---- */}
        <Section title="Privacy">
          <SettingRow
            label="Biometric app lock"
            hint="Face ID / Touch ID is available on iOS only; the web client cannot lock with biometrics."
          >
            <span className="fm-badge" aria-label="Biometric lock is iOS only">
              iOS only
            </span>
          </SettingRow>
        </Section>

        {/* ---- Data ---- */}
        <Section title="Data">
          <SettingRow
            label="Export data"
            hint="Download all your data as finmate-export.json — money kept as raw minor units + currency, with zero precision loss."
          >
            <button
              type="button"
              className="fm-btn fm-btn-ghost"
              style={{ padding: '0.5rem 0.875rem', fontSize: '0.8125rem' }}
              aria-label="Export your data as JSON"
              onClick={handleExport}
            >
              Export
            </button>
          </SettingRow>
          <SettingRow
            label="Delete account"
            hint="Permanently deletes your account and all data via the delete-account Edge Function. This cannot be undone."
          >
            <button
              type="button"
              className="fm-btn"
              style={{
                padding: '0.5rem 0.875rem',
                fontSize: '0.8125rem',
                background: 'var(--fm-down)',
              }}
              aria-label="Delete your account permanently"
              onClick={() =>
                window.alert(
                  'Account deletion calls the delete-account Edge Function (not wired in this demo).',
                )
              }
            >
              Delete account
            </button>
          </SettingRow>
        </Section>

        {/* ---- Account ---- */}
        <Section title="Account">
          <SettingRow
            label="Signed in"
            hint={
              user?.isDemo
                ? 'You are exploring the offline demo (sample data).'
                : (user?.email ?? 'Not signed in')
            }
          >
            <button
              type="button"
              className="fm-btn fm-btn-ghost"
              style={{ padding: '0.5rem 0.875rem', fontSize: '0.8125rem' }}
              aria-label="Log out"
              onClick={() => {
                void signOut();
              }}
            >
              Log out
            </button>
          </SettingRow>
        </Section>

        {/* ---- About ---- */}
        <Section title="About">
          <SettingRow label="Finmate" hint="Private-first personal finance, one Liquid Glass language.">
            <span className="fm-secondary fm-mono" style={{ fontSize: '0.875rem' }}>
              v1 (web)
            </span>
          </SettingRow>
          <div className="fm-secondary" style={{ fontSize: '0.8125rem', marginTop: '0.5rem' }}>
            iOS is the lead client; the web client shares the same Supabase backend
            contract and the docs/13 algorithms.
          </div>
        </Section>
      </div>
    </Page>
  );
}

// MARK: - Building blocks

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <GlassCard>
      <h2
        style={{
          fontSize: '0.8125rem',
          fontWeight: 700,
          textTransform: 'uppercase',
          letterSpacing: '0.04em',
          color: 'var(--fm-label-secondary)',
          margin: '0 0 0.75rem',
        }}
      >
        {title}
      </h2>
      <div className="fm-stack" style={{ gap: '0.875rem' }}>
        {children}
      </div>
    </GlassCard>
  );
}

function SettingRow({
  label,
  hint,
  children,
}: {
  label: string;
  hint?: string;
  children: ReactNode;
}) {
  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: '1rem',
        flexWrap: 'wrap',
      }}
    >
      <div style={{ flex: 1, minWidth: '10rem' }}>
        <div style={{ fontWeight: 600 }}>{label}</div>
        {hint && (
          <div className="fm-secondary" style={{ fontSize: '0.8125rem', marginTop: '0.125rem' }}>
            {hint}
          </div>
        )}
      </div>
      <div style={{ flexShrink: 0 }}>{children}</div>
    </div>
  );
}

function SegmentedControl<T extends string>({
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
    <div className="fm-segment" role="group" aria-label={groupLabel}>
      {options.map((opt) => (
        <button
          key={opt.value}
          type="button"
          className="fm-segment-item"
          aria-pressed={opt.value === value}
          onClick={() => onChange(opt.value)}
        >
          {opt.label}
        </button>
      ))}
    </div>
  );
}

function Toggle({
  label,
  checked,
  onChange,
}: {
  label: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={label}
      onClick={() => onChange(!checked)}
      className="fm-toggle"
      data-on={checked ? 'true' : 'false'}
    >
      <span className="fm-toggle-knob" aria-hidden="true" />
    </button>
  );
}
