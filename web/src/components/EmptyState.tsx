// EmptyState — the shared "nothing here yet" surface, mirroring the iOS
// ContentUnavailableView / GlassCard empty state (docs/06 §a11y). One glass
// language: a glyph tile + title + message + an optional call-to-action button.
// Used by Subscriptions, Cash Flow, Assets, Calendar, and Import when a collection
// is empty after load (NOT during loading — that path shows skeletons instead).

import type { ReactNode } from 'react';
import { GlassCard } from './GlassCard';

interface EmptyStateProps {
  /** Decorative glyph rendered in the icon tile (aria-hidden). */
  icon: ReactNode;
  /** Short headline, e.g. "No subscriptions yet". */
  title: string;
  /** One- or two-sentence supporting copy. */
  message: string;
  /** Optional primary action (e.g. "Add subscription"). */
  cta?: { label: string; onClick: () => void };
}

export function EmptyState({ icon, title, message, cta }: EmptyStateProps) {
  return (
    <GlassCard>
      <div className="fm-emptystate">
        <span className="fm-icon-tile fm-emptystate-icon" aria-hidden="true">
          {icon}
        </span>
        <div className="fm-emptystate-title">{title}</div>
        <p className="fm-emptystate-message fm-secondary">{message}</p>
        {cta && (
          <button type="button" className="fm-btn" onClick={cta.onClick}>
            {cta.label}
          </button>
        )}
      </div>
    </GlassCard>
  );
}
