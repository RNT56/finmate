// ChartDataTable — the screen-reader-only tabular fallback that accompanies every
// chart/flow (the money-flow Sankey, the assets allocation donut, the income-vs-
// expenses bar). The SVG itself is aria-hidden; a sibling role="img" + aria-label
// gives the one-line summary, and this visually-hidden <table> gives a screen-reader
// user the same row-by-row figures a sighted user sees. Rows come from the PURE,
// unit-tested core/chartDescription helpers (mirroring the iOS Domain helpers).

import type { ChartDataRow } from '../core/chartDescription';

interface ChartDataTableProps {
  /** Accessible caption, e.g. "Money flow breakdown". */
  caption: string;
  /** Header for the first (category) column. */
  labelHeader: string;
  /** Header for the second (value) column. */
  valueHeader: string;
  rows: ChartDataRow[];
}

export function ChartDataTable({
  caption,
  labelHeader,
  valueHeader,
  rows,
}: ChartDataTableProps) {
  if (rows.length === 0) return null;
  return (
    <table className="fm-sr-only">
      <caption>{caption}</caption>
      <thead>
        <tr>
          <th scope="col">{labelHeader}</th>
          <th scope="col">{valueHeader}</th>
        </tr>
      </thead>
      <tbody>
        {rows.map((row) => (
          <tr key={row.label}>
            <th scope="row">{row.label}</th>
            <td>{row.value}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}
