import { GlassCard } from './GlassCard';
import { Page } from './AppShell';

/** Placeholder for feature pillars that arrive in a later milestone (docs/08). */
export function Placeholder({ title }: { title: string }) {
  return (
    <Page title={title}>
      <GlassCard>
        <div style={{ fontWeight: 650, marginBottom: 4 }}>Coming soon</div>
        <div className="fm-secondary">
          This pillar arrives in a later milestone (see docs/08). The shared Supabase
          backend contract and the docs/13 algorithms are already in place.
        </div>
      </GlassCard>
    </Page>
  );
}
