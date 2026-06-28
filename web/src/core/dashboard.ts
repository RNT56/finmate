// Dashboard layout model (M7-HOME) — mirrors the Swift Domain Dashboard.
// The Home screen is a customizable, reorderable set of cards (docs/02 §3). The
// user's chosen order persists to `dashboard_layouts.card_order text[]`
// (docs/05 §3.11); for the web demo we persist to localStorage behind a repo.
//
// Pure layout logic only — no React, no data fetching. iOS and web share these
// vectors: default order, drop-unknown-on-load, append-new-defaults, reorder.

/** Stable identifiers for every available Home card. snake-ish camelCase ids. */
export type DashboardCardId =
  | 'subscriptionsTotal'
  | 'netCashFlow'
  | 'savingsRate'
  | 'portfolioValue'
  | 'upcomingCharges'
  | 'activeServices';

/** Canonical order a fresh account starts with (also the union of all known ids). */
export const defaultOrder: readonly DashboardCardId[] = [
  'subscriptionsTotal',
  'netCashFlow',
  'savingsRate',
  'portfolioValue',
  'upcomingCharges',
  'activeServices',
];

/** Every known card id, as a Set for membership checks. */
const KNOWN_IDS: ReadonlySet<DashboardCardId> = new Set(defaultOrder);

/** True when `id` is a card this build knows how to render. */
export function isKnownCardId(id: string): id is DashboardCardId {
  return KNOWN_IDS.has(id as DashboardCardId);
}

/**
 * Resolve a persisted order into a valid render order:
 *   1. keep saved ids, in saved order, dropping any unknown ids (forward-compat:
 *      a card removed in a later build won't crash an older saved layout);
 *   2. append any known default ids the saved order is missing, in default
 *      order (so a card added in a newer build shows up for existing users).
 * De-duplicates. A null/empty saved order yields the full default order.
 */
export function resolveOrder(
  saved: readonly string[] | null | undefined,
): DashboardCardId[] {
  const result: DashboardCardId[] = [];
  const seen = new Set<DashboardCardId>();
  for (const id of saved ?? []) {
    if (isKnownCardId(id) && !seen.has(id)) {
      result.push(id);
      seen.add(id);
    }
  }
  for (const id of defaultOrder) {
    if (!seen.has(id)) {
      result.push(id);
      seen.add(id);
    }
  }
  return result;
}

/**
 * Move the card at `from` to `to`, returning a new array. Out-of-range indices
 * are clamped; a no-op move returns an equivalent array.
 */
export function reorder(
  order: readonly DashboardCardId[],
  from: number,
  to: number,
): DashboardCardId[] {
  const next = [...order];
  if (next.length === 0) return next;
  const clampedFrom = Math.max(0, Math.min(from, next.length - 1));
  const clampedTo = Math.max(0, Math.min(to, next.length - 1));
  const [moved] = next.splice(clampedFrom, 1);
  next.splice(clampedTo, 0, moved);
  return next;
}

/** Move the card at `index` one slot earlier (clamped). New array. */
export function moveUp(order: readonly DashboardCardId[], index: number): DashboardCardId[] {
  return reorder(order, index, index - 1);
}

/** Move the card at `index` one slot later (clamped). New array. */
export function moveDown(order: readonly DashboardCardId[], index: number): DashboardCardId[] {
  return reorder(order, index, index + 1);
}

/**
 * Toggle a card's visibility within a hidden-set. Returns a new Set: visible →
 * hidden adds the id; hidden → visible removes it. Unknown ids are ignored.
 */
export function toggleHidden(
  hidden: ReadonlySet<DashboardCardId>,
  id: DashboardCardId,
): Set<DashboardCardId> {
  const next = new Set(hidden);
  if (next.has(id)) next.delete(id);
  else next.add(id);
  return next;
}

/** The default human-facing title for each card (feature layer may override). */
export const cardTitles: Record<DashboardCardId, string> = {
  subscriptionsTotal: 'Monthly subscriptions',
  netCashFlow: 'Net cash flow',
  savingsRate: 'Savings rate',
  portfolioValue: 'Portfolio value',
  upcomingCharges: 'Upcoming charges',
  activeServices: 'Active services',
};
