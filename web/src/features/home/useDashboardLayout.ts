// Dashboard layout store/hook (M7-HOME) — owns the resolved card order + the
// hidden-card set, and persists them. The eventual store is the
// `dashboard_layouts.card_order text[]` table (docs/05 §3.11); for the web demo
// we persist to localStorage behind this small repo, matching the Settings /
// preferences pattern. All ordering logic is the pure core/dashboard module.

import { useCallback, useMemo, useState } from 'react';
import {
  type DashboardCardId,
  resolveOrder,
  moveUp as moveUpCore,
  moveDown as moveDownCore,
  reorder as reorderCore,
  toggleHidden as toggleHiddenCore,
  isKnownCardId,
} from '../../core/dashboard';

interface PersistedLayout {
  cardOrder: string[];
  hidden: string[];
}

const STORAGE_KEY = 'finmate.dashboard.v1';

/** Repository protocol — the Home store talks to this, never storage directly. */
export interface DashboardLayoutRepository {
  load(): PersistedLayout | null;
  save(layout: PersistedLayout): void;
}

/** localStorage-backed repo (parity with LocalStoragePreferencesRepository). */
export class LocalStorageDashboardLayoutRepository implements DashboardLayoutRepository {
  load(): PersistedLayout | null {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return null;
      const parsed = JSON.parse(raw) as Partial<PersistedLayout>;
      return {
        cardOrder: Array.isArray(parsed.cardOrder) ? parsed.cardOrder : [],
        hidden: Array.isArray(parsed.hidden) ? parsed.hidden : [],
      };
    } catch {
      return null;
    }
  }

  save(layout: PersistedLayout): void {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(layout));
    } catch {
      // localStorage unavailable (private mode / SSR) — best effort only.
    }
  }
}

/** In-memory repo for tests / non-persisting contexts. */
export class InMemoryDashboardLayoutRepository implements DashboardLayoutRepository {
  private layout: PersistedLayout | null;
  constructor(initial: PersistedLayout | null = null) {
    this.layout = initial;
  }
  load(): PersistedLayout | null {
    return this.layout;
  }
  save(layout: PersistedLayout): void {
    this.layout = layout;
  }
}

const sharedRepository: DashboardLayoutRepository = new LocalStorageDashboardLayoutRepository();

export interface UseDashboardLayout {
  /** The resolved, render-ready order (unknown dropped, new defaults appended). */
  order: DashboardCardId[];
  /** Card ids the user has hidden. */
  hidden: Set<DashboardCardId>;
  isHidden: (id: DashboardCardId) => boolean;
  /** Visible cards in order — what Home renders. */
  visibleOrder: DashboardCardId[];
  moveUp: (index: number) => void;
  moveDown: (index: number) => void;
  reorder: (from: number, to: number) => void;
  toggle: (id: DashboardCardId) => void;
  reset: () => void;
}

export function useDashboardLayout(
  repository: DashboardLayoutRepository = sharedRepository,
): UseDashboardLayout {
  const [order, setOrder] = useState<DashboardCardId[]>(() =>
    resolveOrder(repository.load()?.cardOrder ?? null),
  );
  const [hidden, setHidden] = useState<Set<DashboardCardId>>(() => {
    const saved = repository.load()?.hidden ?? [];
    return new Set(saved.filter(isKnownCardId));
  });

  const persist = useCallback(
    (nextOrder: DashboardCardId[], nextHidden: Set<DashboardCardId>) => {
      repository.save({ cardOrder: nextOrder, hidden: [...nextHidden] });
    },
    [repository],
  );

  const applyOrder = useCallback(
    (next: DashboardCardId[]) => {
      setOrder(next);
      persist(next, hidden);
    },
    [hidden, persist],
  );

  const moveUp = useCallback(
    (index: number) => applyOrder(moveUpCore(order, index)),
    [order, applyOrder],
  );
  const moveDown = useCallback(
    (index: number) => applyOrder(moveDownCore(order, index)),
    [order, applyOrder],
  );
  const reorder = useCallback(
    (from: number, to: number) => applyOrder(reorderCore(order, from, to)),
    [order, applyOrder],
  );

  const toggle = useCallback(
    (id: DashboardCardId) => {
      const next = toggleHiddenCore(hidden, id);
      setHidden(next);
      persist(order, next);
    },
    [hidden, order, persist],
  );

  const reset = useCallback(() => {
    const next = resolveOrder(null);
    const nextHidden = new Set<DashboardCardId>();
    setOrder(next);
    setHidden(nextHidden);
    persist(next, nextHidden);
  }, [persist]);

  const isHidden = useCallback((id: DashboardCardId) => hidden.has(id), [hidden]);

  const visibleOrder = useMemo(
    () => order.filter((id) => !hidden.has(id)),
    [order, hidden],
  );

  return { order, hidden, isHidden, visibleOrder, moveUp, moveDown, reorder, toggle, reset };
}
