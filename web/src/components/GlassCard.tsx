// GlassCard — the single glass container primitive, mirroring the iOS GlassCard
// (App/Sources/DesignSystem.swift). One design language; no ad-hoc blurs in feature code.

import type { CSSProperties, ReactNode } from 'react';

interface GlassCardProps {
  children: ReactNode;
  padded?: boolean;
  className?: string;
  style?: CSSProperties;
}

export function GlassCard({ children, padded = true, className = '', style }: GlassCardProps) {
  return (
    <div className={`fm-glass ${padded ? 'fm-card' : ''} ${className}`.trim()} style={style}>
      {children}
    </div>
  );
}
