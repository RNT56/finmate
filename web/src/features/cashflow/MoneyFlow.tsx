// M3 money-flow visualization (the headline cost-tracker chart, ADR-0016 bucketed Sankey).
// Renders the SHARED deterministic core/moneyflow layout() as inline SVG: rounded <rect>
// nodes + cubic-Bézier ribbons in the palette colors, with labels + amounts. The figures
// come straight from useCashFlow so the flow agrees with the KPIs. One design language.
//
// Accessibility: role="img" + an aria-label that narrates the whole flow for screen
// readers; under prefers-reduced-transparency the ribbons render with solid fills (no
// translucency) so the chart never depends on opacity to read.

import { useId } from 'react';
import {
  layout,
  ribbonPath,
  savingsMinor,
  totalExpensesMinor,
  type MoneyFlow as MoneyFlowModel,
} from '../../core/moneyflow';
import { formatMoney } from '../../core/money';
import type { CurrencyCode } from '../../core/currency';

const WIDTH = 640;
const HEIGHT = 280;
const PADDING = 20;
const NODE_WIDTH = 14;
const NODE_GAP = 10;

interface MoneyFlowProps {
  flow: MoneyFlowModel;
  currency: CurrencyCode;
  locale?: string;
}

export function MoneyFlow({ flow, currency, locale = 'de-DE' }: MoneyFlowProps) {
  const titleId = useId();
  const fmt = (minor: number) => formatMoney(minor, currency, locale);

  const result = layout(flow, {
    width: WIDTH,
    height: HEIGHT,
    padding: PADDING,
    nodeWidth: NODE_WIDTH,
    nodeGap: NODE_GAP,
  });

  const income = result.nodes.find((n) => n.id === 'income')!;
  const buckets = result.nodes.filter((n) => n.id !== 'income');

  // Full spoken description of the flow (income split across each non-zero bucket).
  const pctOfIncome = (v: number) =>
    flow.incomeMinor === 0 ? 0 : Math.round((v / flow.incomeMinor) * 100);
  const ariaLabel = [
    `Money flow. Income ${fmt(flow.incomeMinor)} splits into`,
    buckets
      .map((b) => `${b.label} ${fmt(b.valueMinor)} (${pctOfIncome(b.valueMinor)}% of income)`)
      .join(', '),
    `Total expenses ${fmt(totalExpensesMinor(flow))}, savings ${fmt(savingsMinor(flow))}.`,
  ].join(' ');

  const empty = flow.incomeMinor === 0 && totalExpensesMinor(flow) === 0;

  return (
    <div
      role="img"
      aria-labelledby={titleId}
      style={{ width: '100%' }}
      className="fm-mono"
    >
      <span id={titleId} style={{ position: 'absolute', width: 1, height: 1, overflow: 'hidden', clip: 'rect(0 0 0 0)', whiteSpace: 'nowrap' }}>
        {empty ? 'Money flow. No income or expenses tracked yet.' : ariaLabel}
      </span>

      {empty ? (
        <div className="fm-secondary" style={{ padding: '24px 0', textAlign: 'center' }}>
          No income or expenses tracked yet.
        </div>
      ) : (
        <svg
          viewBox={`0 0 ${WIDTH} ${HEIGHT}`}
          width="100%"
          preserveAspectRatio="xMidYMid meet"
          aria-hidden="true"
        >
          {/* Ribbons first (under the nodes). Translucent for depth; the
              prefers-reduced-transparency block below restores full opacity. */}
          <g className="fm-flow-ribbons">
            {result.links.map((link) => (
              <path
                key={link.id}
                d={ribbonPath(link)}
                fill={link.color}
                className="fm-flow-ribbon"
              />
            ))}
          </g>

          {/* Income node + label/amount on its left. */}
          <rect
            x={income.x}
            y={income.y}
            width={income.w}
            height={income.h}
            rx={5}
            fill={income.color}
          />
          <text
            x={income.x + income.w + 10}
            y={income.y + income.h / 2 - 4}
            fontSize={14}
            fontWeight={600}
            fill="var(--fm-label)"
          >
            Income
          </text>
          <text
            x={income.x + income.w + 10}
            y={income.y + income.h / 2 + 14}
            fontSize={13}
            fill="var(--fm-label-secondary)"
          >
            {fmt(income.valueMinor)}
          </text>

          {/* Bucket nodes + label/amount/percent to the right of each. */}
          {buckets.map((node) => {
            const labelY = node.y + node.h / 2;
            return (
              <g key={node.id}>
                <rect
                  x={node.x}
                  y={node.y}
                  width={node.w}
                  height={Math.max(node.h, 2)}
                  rx={5}
                  fill={node.color}
                />
                <text
                  x={node.x - 8}
                  y={labelY - 3}
                  textAnchor="end"
                  fontSize={13}
                  fontWeight={600}
                  fill="var(--fm-label)"
                >
                  {node.label}
                </text>
                <text
                  x={node.x - 8}
                  y={labelY + 13}
                  textAnchor="end"
                  fontSize={12}
                  fill="var(--fm-label-secondary)"
                >
                  {fmt(node.valueMinor)} · {pctOfIncome(node.valueMinor)}%
                </text>
              </g>
            );
          })}
        </svg>
      )}
    </div>
  );
}
