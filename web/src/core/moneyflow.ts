// TS mirror of Domain MoneyFlow (docs/13 §6.5, ADR-0016 bucketed Sankey) + the SHARED
// deterministic layout() that turns buckets + a canvas size into draw-ready nodes + links.
//
// The layout is a PURE function (no randomness, no physics) so both clients lay the flow
// out identically and it is unit-testable against the same vectors as the Swift
// MoneyFlowLayoutTests. Money stays integer minor units; only the geometry is fractional.
//
// Buckets are stacked top→bottom in this FIXED order: Fixed, Variable, Subscriptions,
// Savings. Income is the single left node; one ribbon Income→bucket per non-zero bucket.
// total = max(income, Σbuckets) guards the over-budget case so nothing exceeds the canvas.

/** A bucketed money flow (docs/13 §6.5). Savings is clamped ≥ 0 by the caller/getter. */
export interface MoneyFlow {
  incomeMinor: number;
  fixedMinor: number;
  variableMinor: number;
  subscriptionsMinor: number;
}

/** Σ of the three expense buckets. */
export function totalExpensesMinor(flow: MoneyFlow): number {
  return flow.fixedMinor + flow.variableMinor + flow.subscriptionsMinor;
}

/** Savings = max(0, income − expenses) — over-budget months show no negative ribbon. */
export function savingsMinor(flow: MoneyFlow): number {
  return Math.max(0, flow.incomeMinor - totalExpensesMinor(flow));
}

/** Stable bucket identity, used for ordering and palette lookup. */
export type BucketKind = 'fixed' | 'variable' | 'subscriptions' | 'savings';

/** The fixed top→bottom stacking order of the right column. */
export const BUCKET_ORDER: readonly BucketKind[] = [
  'fixed',
  'variable',
  'subscriptions',
  'savings',
] as const;

/** Display labels per bucket. */
export const BUCKET_LABELS: Record<BucketKind, string> = {
  fixed: 'Fixed',
  variable: 'Variable',
  subscriptions: 'Subscriptions',
  savings: 'Savings',
};

/**
 * Palette CSS variables per node (docs/06): Fixed≈red, Variable≈orange,
 * Subscriptions≈violet, Savings≈emerald/green, Income≈accent. var() with a literal
 * fallback so the renderer is correct even without the stylesheet (and in jsdom).
 */
export const FLOW_COLORS: Record<BucketKind | 'income', string> = {
  income: 'var(--fm-accent, #0a84ff)',
  fixed: 'var(--fm-down, #d7263d)',
  variable: 'var(--fm-warning, #e8830c)',
  subscriptions: 'var(--fm-flow-violet, #8e5cff)',
  savings: 'var(--fm-up, #1f9d55)',
};

export interface FlowNode {
  id: BucketKind | 'income';
  label: string;
  valueMinor: number;
  x: number;
  y: number;
  w: number;
  h: number;
  color: string;
}

export interface FlowLink {
  id: BucketKind;
  color: string;
  /** Source (income) edge band, top/bottom y. */
  incomeY0: number;
  incomeY1: number;
  /** Target (bucket) edge band, top/bottom y. */
  bucketY0: number;
  bucketY1: number;
  /** Convenience X anchors for the renderer. */
  x0: number;
  x1: number;
}

export interface FlowLayout {
  width: number;
  height: number;
  nodes: FlowNode[];
  links: FlowLink[];
  total: number;
}

export interface LayoutOptions {
  width: number;
  height: number;
  /** Horizontal/vertical inset of the plot area. Default 16. */
  padding?: number;
  /** Column rect width. Default 14. */
  nodeWidth?: number;
  /** Vertical gap between stacked bucket nodes. Default 8. */
  nodeGap?: number;
}

/**
 * Deterministic flow layout (the SHARED algorithm). Pure: same inputs → same output.
 *
 * - total      = max(income, Σbuckets)            (guards over-budget; nothing exceeds canvas)
 * - usableH    = height − 2·padding − gaps(between non-zero buckets)
 * - scale      = usableH / total                  (minor units → points)
 * - Income     : one left node, height = income·scale, vertically centered in the plot.
 * - Buckets    : non-zero buckets only, stacked top→bottom in BUCKET_ORDER on the right,
 *                each height = value·scale, separated by nodeGap.
 * - Links      : one Income→bucket ribbon per bucket; the income-side bands are stacked in
 *                the SAME order so they partition the income node's right edge exactly.
 */
export function layout(flow: MoneyFlow, options: LayoutOptions): FlowLayout {
  const padding = options.padding ?? 16;
  const nodeWidth = options.nodeWidth ?? 14;
  const nodeGap = options.nodeGap ?? 8;
  const { width, height } = options;

  const bucketValues: Record<BucketKind, number> = {
    fixed: flow.fixedMinor,
    variable: flow.variableMinor,
    subscriptions: flow.subscriptionsMinor,
    savings: savingsMinor(flow),
  };

  const activeBuckets = BUCKET_ORDER.filter((k) => bucketValues[k] > 0);
  const bucketSum = activeBuckets.reduce((s, k) => s + bucketValues[k], 0);
  const total = Math.max(flow.incomeMinor, bucketSum);

  const plotTop = padding;
  const plotH = Math.max(0, height - padding * 2);
  // Gaps only sit BETWEEN active buckets.
  const gaps = Math.max(0, activeBuckets.length - 1) * nodeGap;
  const usableH = Math.max(0, plotH - gaps);
  const scale = total > 0 ? usableH / total : 0;

  const leftX = padding;
  const rightX = width - padding - nodeWidth;

  // Income node: height = income·scale, vertically centered in the plot area.
  const incomeH = flow.incomeMinor * scale;
  const incomeY = plotTop + (plotH - incomeH) / 2;
  const incomeNode: FlowNode = {
    id: 'income',
    label: 'Income',
    valueMinor: flow.incomeMinor,
    x: leftX,
    y: incomeY,
    w: nodeWidth,
    h: incomeH,
    color: FLOW_COLORS.income,
  };

  const nodes: FlowNode[] = [incomeNode];
  const links: FlowLink[] = [];

  // Right column: stack active buckets top→bottom. Income-side bands stack in the same
  // order from the top of the income node so they partition its right edge exactly.
  let bucketCursor = plotTop;
  let incomeCursor = incomeY;
  for (const kind of activeBuckets) {
    const value = bucketValues[kind];
    const h = value * scale;

    nodes.push({
      id: kind,
      label: BUCKET_LABELS[kind],
      valueMinor: value,
      x: rightX,
      y: bucketCursor,
      w: nodeWidth,
      h,
      color: FLOW_COLORS[kind],
    });

    links.push({
      id: kind,
      color: FLOW_COLORS[kind],
      incomeY0: incomeCursor,
      incomeY1: incomeCursor + h,
      bucketY0: bucketCursor,
      bucketY1: bucketCursor + h,
      x0: leftX + nodeWidth,
      x1: rightX,
    });

    bucketCursor += h + nodeGap;
    incomeCursor += h;
  }

  return { width, height, nodes, links, total };
}

/**
 * Build the SVG path for a ribbon: two cubic Béziers (top edge then bottom edge back)
 * with horizontal control points at the midpoint X — the standard Sankey S-curve.
 */
export function ribbonPath(link: FlowLink): string {
  const cx = (link.x0 + link.x1) / 2;
  const { x0, x1, incomeY0, incomeY1, bucketY0, bucketY1 } = link;
  return [
    `M ${x0} ${incomeY0}`,
    `C ${cx} ${incomeY0}, ${cx} ${bucketY0}, ${x1} ${bucketY0}`,
    `L ${x1} ${bucketY1}`,
    `C ${cx} ${bucketY1}, ${cx} ${incomeY1}, ${x0} ${incomeY1}`,
    'Z',
  ].join(' ');
}
