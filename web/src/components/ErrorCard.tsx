// ErrorCard — the inline "something went wrong" surface with a Retry action,
// shown when a repository load fails (hooks now capture the error instead of
// swallowing it). Mirrors the iOS error-state GlassCard. role="alert" so screen
// readers announce it; the happy path renders nothing here. One glass language.

import { GlassCard } from './GlassCard';

interface ErrorCardProps {
  /** Short, human-readable failure summary. */
  title?: string;
  /** Optional detail (e.g. the captured error message). */
  message?: string;
  /** Retry handler — re-runs the failed load. */
  onRetry: () => void;
}

export function ErrorCard({
  title = "Couldn't load this",
  message = 'Something went wrong while fetching your data.',
  onRetry,
}: ErrorCardProps) {
  return (
    <GlassCard>
      <div className="fm-errorcard" role="alert">
        <span className="fm-icon-tile fm-errorcard-icon" aria-hidden="true">
          !
        </span>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div className="fm-errorcard-title">{title}</div>
          <p className="fm-errorcard-message fm-secondary">{message}</p>
        </div>
        <button type="button" className="fm-btn fm-btn-ghost" onClick={onRetry}>
          Retry
        </button>
      </div>
    </GlassCard>
  );
}
