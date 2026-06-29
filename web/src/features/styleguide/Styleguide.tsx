// Styleguide — the web mirror of the iOS DesignSystemGallery. Showcases the
// OBSIDIAN tokens (color roles, bronze accent, money-flow + chart ramps, radii,
// spacing, type ramp) and the component set (buttons, badges, segmented control,
// glass levels, toggle) so both clients can be eyeballed for parity. One glass
// language; no ad-hoc colors — every swatch reads a CSS variable.

import { useState } from 'react';
import { GlassCard } from '../../components/GlassCard';
import { Page } from '../../components/AppShell';

interface Swatch {
  name: string;
  varName: string;
  /** When set, use light text so the label reads on a dark fill. */
  light?: boolean;
}

const COLOR_ROLES: Swatch[] = [
  { name: 'background', varName: '--fm-background' },
  { name: 'elevated', varName: '--fm-background-elevated' },
  { name: 'surface', varName: '--fm-surface' },
  { name: 'surface-2', varName: '--fm-surface-2' },
  { name: 'label', varName: '--fm-label', light: true },
  { name: 'label-secondary', varName: '--fm-label-secondary' },
  { name: 'ink', varName: '--fm-ink', light: true },
  { name: 'bronze', varName: '--fm-bronze', light: true },
  { name: 'bronze-deep', varName: '--fm-bronze-deep', light: true },
  { name: 'accent', varName: '--fm-accent', light: true },
];

const SEMANTICS: Swatch[] = [
  { name: 'up (gain)', varName: '--fm-up', light: true },
  { name: 'down (loss)', varName: '--fm-down', light: true },
  { name: 'neutral', varName: '--fm-neutral', light: true },
  { name: 'warning', varName: '--fm-warning', light: true },
  { name: 'btc', varName: '--fm-btc', light: true },
];

const FLOW_RAMP: string[] = [
  '--fm-flow-income',
  '--fm-flow-fixed',
  '--fm-flow-variable',
  '--fm-flow-subscriptions',
  '--fm-flow-savings',
];

const CHART_RAMP: string[] = [
  '--fm-ramp-1',
  '--fm-ramp-2',
  '--fm-ramp-3',
  '--fm-ramp-4',
  '--fm-ramp-5',
  '--fm-ramp-6',
];

const RADII: { name: string; varName: string }[] = [
  { name: 'sm 12', varName: '--fm-radius-sm' },
  { name: 'md 16', varName: '--fm-radius-md' },
  { name: 'lg 22', varName: '--fm-radius-lg' },
  { name: 'xl 28', varName: '--fm-radius-xl' },
  { name: 'pill', varName: '--fm-radius-pill' },
];

const SPACING: { name: string; varName: string }[] = [
  { name: '1 · 4', varName: '--fm-space-1' },
  { name: '2 · 8', varName: '--fm-space-2' },
  { name: '3 · 12', varName: '--fm-space-3' },
  { name: '4 · 16', varName: '--fm-space-4' },
  { name: '5 · 20', varName: '--fm-space-5' },
  { name: '6 · 24', varName: '--fm-space-6' },
  { name: '7 · 32', varName: '--fm-space-7' },
];

const TYPE_RAMP: { name: string; varName: string }[] = [
  { name: 'largeTitle', varName: '--fm-font-largetitle' },
  { name: 'title1', varName: '--fm-font-title1' },
  { name: 'title2', varName: '--fm-font-title2' },
  { name: 'title3', varName: '--fm-font-title3' },
  { name: 'headline', varName: '--fm-font-headline' },
  { name: 'body', varName: '--fm-font-body' },
  { name: 'callout', varName: '--fm-font-callout' },
  { name: 'footnote', varName: '--fm-font-footnote' },
  { name: 'caption', varName: '--fm-font-caption' },
  { name: 'caption2', varName: '--fm-font-caption2' },
];

function SwatchGrid({ swatches }: { swatches: Swatch[] }) {
  return (
    <div className="fm-sg-grid">
      {swatches.map((s) => (
        <div
          key={s.varName}
          className="fm-sg-swatch"
          style={{
            background: `var(${s.varName})`,
            color: s.light ? '#fff' : 'var(--fm-label)',
          }}
        >
          <span className="fm-sg-swatch-name">{s.name}</span>
          <span className="fm-sg-swatch-val">{s.varName}</span>
        </div>
      ))}
    </div>
  );
}

function RampBar({ vars }: { vars: string[] }) {
  return (
    <div className="fm-sg-rampbar">
      {vars.map((v) => (
        <span key={v} style={{ background: `var(${v})` }} title={v} />
      ))}
    </div>
  );
}

export function Styleguide() {
  const [toggleOn, setToggleOn] = useState(true);
  const [segment, setSegment] = useState('Month');

  return (
    <Page title="Styleguide">
      <p
        className="fm-secondary"
        style={{ marginTop: 'calc(-1 * var(--fm-space-3))', marginBottom: 'var(--fm-space-6)' }}
      >
        OBSIDIAN — near-monochrome ink/graphite + a single warm bronze accent on a
        near-flat neutral. The web mirror of the iOS DesignSystem gallery.
      </p>

      <section className="fm-sg-section">
        <h2 className="fm-sg-heading">Color roles</h2>
        <GlassCard>
          <SwatchGrid swatches={COLOR_ROLES} />
        </GlassCard>
      </section>

      <section className="fm-sg-section">
        <h2 className="fm-sg-heading">Financial semantics</h2>
        <GlassCard>
          <SwatchGrid swatches={SEMANTICS} />
        </GlassCard>
      </section>

      <section className="fm-sg-section">
        <h2 className="fm-sg-heading">Money-flow ramp (Sankey)</h2>
        <GlassCard>
          <RampBar vars={FLOW_RAMP} />
          <p className="fm-secondary" style={{ fontSize: 'var(--fm-font-footnote)', marginBottom: 0 }}>
            income · fixed · variable · subscriptions · savings
          </p>
        </GlassCard>
      </section>

      <section className="fm-sg-section">
        <h2 className="fm-sg-heading">Chart ramp (bronze → tan)</h2>
        <GlassCard>
          <RampBar vars={CHART_RAMP} />
        </GlassCard>
      </section>

      <section className="fm-sg-section">
        <h2 className="fm-sg-heading">Buttons</h2>
        <GlassCard>
          <div className="fm-sg-clusters">
            <button type="button" className="fm-btn">
              Primary (ink)
            </button>
            <button type="button" className="fm-btn fm-btn-secondary">
              Secondary
            </button>
            <button type="button" className="fm-btn fm-btn-accent">
              Accent (bronze)
            </button>
            <button type="button" className="fm-btn fm-btn-ghost">
              Ghost
            </button>
            <button type="button" className="fm-btn fm-btn-destructive">
              Destructive
            </button>
            <button type="button" className="fm-btn fm-btn-sm">
              Small
            </button>
          </div>
        </GlassCard>
      </section>

      <section className="fm-sg-section">
        <h2 className="fm-sg-heading">Badges</h2>
        <GlassCard>
          <div className="fm-sg-clusters">
            <span className="fm-badge">Neutral</span>
            <span className="fm-badge fm-badge-accent">Accent</span>
            <span className="fm-badge fm-badge-up">+4.2%</span>
            <span className="fm-badge fm-badge-down">−1.8%</span>
            <span className="fm-badge fm-badge-btc">BTC</span>
          </div>
        </GlassCard>
      </section>

      <section className="fm-sg-section">
        <h2 className="fm-sg-heading">Segmented control</h2>
        <GlassCard>
          <div className="fm-segment" role="group" aria-label="Range">
            {['Week', 'Month', 'Year'].map((label) => (
              <button
                key={label}
                type="button"
                className="fm-segment-item"
                aria-pressed={segment === label}
                onClick={() => setSegment(label)}
              >
                {label}
              </button>
            ))}
          </div>
        </GlassCard>
      </section>

      <section className="fm-sg-section">
        <h2 className="fm-sg-heading">Toggle</h2>
        <GlassCard>
          <button
            type="button"
            role="switch"
            aria-checked={toggleOn}
            aria-label="Demo toggle"
            className="fm-toggle"
            data-on={toggleOn}
            onClick={() => setToggleOn((v) => !v)}
          >
            <span className="fm-toggle-knob" aria-hidden="true" />
          </button>
        </GlassCard>
      </section>

      <section className="fm-sg-section">
        <h2 className="fm-sg-heading">Glass levels</h2>
        <div className="fm-sg-clusters">
          <GlassCard>standard</GlassCard>
          <GlassCard className="fm-glass-chrome">chrome</GlassCard>
          <GlassCard className="fm-glass-thin">thin</GlassCard>
        </div>
      </section>

      <section className="fm-sg-section">
        <h2 className="fm-sg-heading">Radii</h2>
        <GlassCard>
          <div className="fm-sg-clusters">
            {RADII.map((r) => (
              <div
                key={r.varName}
                className="fm-sg-radius-demo"
                style={{ borderRadius: `var(${r.varName})` }}
              >
                {r.name}
              </div>
            ))}
          </div>
        </GlassCard>
      </section>

      <section className="fm-sg-section">
        <h2 className="fm-sg-heading">Spacing</h2>
        <GlassCard>
          <div style={{ display: 'flex', alignItems: 'flex-end', gap: 'var(--fm-space-3)' }}>
            {SPACING.map((s) => (
              <div key={s.varName} style={{ textAlign: 'center' }}>
                <div
                  style={{
                    width: `var(${s.varName})`,
                    height: `var(${s.varName})`,
                    background: 'var(--fm-bronze)',
                    borderRadius: 'var(--fm-space-1)',
                    marginInline: 'auto',
                  }}
                />
                <span className="fm-sg-swatch-val" style={{ fontSize: 'var(--fm-font-caption2)' }}>
                  {s.name}
                </span>
              </div>
            ))}
          </div>
        </GlassCard>
      </section>

      <section className="fm-sg-section">
        <h2 className="fm-sg-heading">Type ramp</h2>
        <GlassCard>
          {TYPE_RAMP.map((t) => (
            <div key={t.varName} className="fm-sg-type-row">
              <span className="fm-sg-type-label">{t.name}</span>
              <span style={{ fontSize: `var(${t.varName})`, fontWeight: 600 }}>
                Finmate
              </span>
              <span className="fm-mono fm-secondary" style={{ marginLeft: 'auto' }}>
                €1,234.50
              </span>
            </div>
          ))}
        </GlassCard>
      </section>
    </Page>
  );
}
