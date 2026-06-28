// Skeleton — CSS shimmer placeholders shown while a store/hook is loading, so the
// UI never flashes blank or "—". Mirrors the iOS `.redacted(reason: .placeholder)`
// pass. The shimmer is gated behind prefers-reduced-motion in glass.css (it falls
// back to a static block). Decorative by default: aria-hidden so screen readers
// hear the page-level "Loading…" status instead of a wall of empty boxes.

import type { CSSProperties } from 'react';
import { GlassCard } from './GlassCard';

interface SkeletonProps {
  /** CSS width (default 100%). */
  width?: string | number;
  /** CSS height in px (default 16). */
  height?: number;
  /** Corner radius in px (default 8). */
  radius?: number;
  style?: CSSProperties;
}

/** A single shimmering bar. */
export function Skeleton({
  width = '100%',
  height = 16,
  radius = 8,
  style,
}: SkeletonProps) {
  return (
    <span
      className="fm-skeleton"
      aria-hidden="true"
      style={{ width, height, borderRadius: radius, ...style }}
    />
  );
}

/** A glass card filled with a few skeleton lines — the default list/card placeholder. */
export function SkeletonCard({ lines = 2 }: { lines?: number }) {
  return (
    <GlassCard>
      <div className="fm-row" style={{ gap: 14 }}>
        <Skeleton width={40} height={40} radius={12} />
        <div
          style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 8 }}
        >
          <Skeleton width="55%" height={15} />
          {Array.from({ length: Math.max(0, lines - 1) }).map((_, i) => (
            <Skeleton key={i} width="35%" height={12} />
          ))}
        </div>
        <Skeleton width={64} height={18} />
      </div>
    </GlassCard>
  );
}

/** A vertical stack of skeleton cards, used as a list-loading placeholder. */
export function SkeletonList({
  count = 3,
  lines = 2,
}: {
  count?: number;
  lines?: number;
}) {
  return (
    <div className="fm-stack" role="status" aria-label="Loading">
      {Array.from({ length: count }).map((_, i) => (
        <SkeletonCard key={i} lines={lines} />
      ))}
    </div>
  );
}
