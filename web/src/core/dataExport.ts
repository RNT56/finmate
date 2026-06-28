// TS mirror of the Swift Domain `DataExport` (docs/07 §9.3 — data export).
//
// Serializes everything the user owns into a single round-trippable JSON document,
// the `ExportBundle`. The hard contract from docs/07 §9.3:
//
//   * Money is exported LOSSLESSLY — every monetary value is written as its RAW
//     Int64 minor units PLUS the ISO currency code (e.g. `amountMinor: 1299,
//     currency: "EUR"`). NEVER pre-formatted ("€12.99") and NEVER converted to a
//     display currency. A re-import therefore suffers zero precision loss (the same
//     discipline that fixes Substimate's float / pre-convert bug).
//   * `schemaVersion` + `exportedAt` (ISO 8601) sit at the top of the bundle so a
//     future importer can branch on format.
//   * Dates stay ISO 8601 strings exactly as the entities already carry them.
//
// iOS and web emit the same logical shape so an export from either client is
// portable. The web client ships the JSON document (the iOS `.zip` additionally
// bundles per-entity CSVs — docs/07 §9.3).

import type { CurrencyCode } from './currency';
import type { UserPreferences } from './preferences';
import type { FinancialAsset } from './assets';
import type {
  IncomeSource,
  FixedExpense,
  VariableExpense,
} from '../features/cashflow/types';
import type { Subscription } from '../features/subscriptions/types';

/** Bump when the bundle's logical shape changes in a non-back-compatible way. */
export const EXPORT_SCHEMA_VERSION = 1;

/** The serialized JSON document Settings → Export Data produces. */
export interface ExportBundle {
  /** Format version so a future importer can branch (docs/07 §9.3). */
  schemaVersion: number;
  /** ISO 8601 timestamp the export was generated. */
  exportedAt: string;
  /** Every financial entity the user owns, money as raw minor units + currency. */
  data: ExportData;
  /**
   * Device/account settings. Per docs/07 §9.3 preferences are NOT part of the
   * *portable financial* export, so they live in a clearly separate field rather
   * than alongside the financial records.
   */
  preferences: UserPreferences;
}

/** The financial entity payload. Each row keeps its own `amountMinor` + `currency`. */
export interface ExportData {
  subscriptions: Subscription[];
  incomeSources: IncomeSource[];
  fixedExpenses: FixedExpense[];
  variableExpenses: VariableExpense[];
  financialAssets: FinancialAsset[];
}

/** The data sources an export reads from (the selected repositories). */
export interface ExportSources {
  subscriptions(): Promise<Subscription[]>;
  incomeSources(): Promise<IncomeSource[]>;
  fixedExpenses(): Promise<FixedExpense[]>;
  variableExpenses(): Promise<VariableExpense[]>;
  financialAssets(): Promise<FinancialAsset[]>;
  preferences(): UserPreferences;
}

/**
 * Build the in-memory `ExportBundle` from the live data sources. Pure aside from
 * the read calls and the timestamp — the timestamp is injectable for deterministic
 * tests. Entities are deep-copied so the bundle never aliases live repo state.
 */
export async function buildExportBundle(
  sources: ExportSources,
  now: Date = new Date(),
): Promise<ExportBundle> {
  const [subscriptions, incomeSources, fixedExpenses, variableExpenses, financialAssets] =
    await Promise.all([
      sources.subscriptions(),
      sources.incomeSources(),
      sources.fixedExpenses(),
      sources.variableExpenses(),
      sources.financialAssets(),
    ]);

  return {
    schemaVersion: EXPORT_SCHEMA_VERSION,
    exportedAt: now.toISOString(),
    data: {
      subscriptions: subscriptions.map((s) => ({ ...s })),
      incomeSources: incomeSources.map((i) => ({ ...i })),
      fixedExpenses: fixedExpenses.map((e) => ({ ...e })),
      variableExpenses: variableExpenses.map((e) => ({ ...e })),
      financialAssets: financialAssets.map((a) => ({ ...a })),
    },
    preferences: { ...sources.preferences() },
  };
}

/** Pretty-printed, stable JSON string for the downloaded file. */
export function serializeExportBundle(bundle: ExportBundle): string {
  return JSON.stringify(bundle, null, 2);
}

/** Default download filename (docs/07 §9.3 names the JSON document `finmate-export.json`). */
export const EXPORT_FILENAME = 'finmate-export.json';

/**
 * Every currency code that appears in a bundle — useful for round-trip assertions
 * that the export never collapsed entities into a single display currency.
 */
export function bundleCurrencies(bundle: ExportBundle): Set<CurrencyCode> {
  const codes = new Set<CurrencyCode>();
  const { data } = bundle;
  for (const s of data.subscriptions) codes.add(s.currency);
  for (const i of data.incomeSources) codes.add(i.currency);
  for (const e of data.fixedExpenses) codes.add(e.currency);
  for (const e of data.variableExpenses) codes.add(e.currency);
  for (const a of data.financialAssets) codes.add(a.currency);
  return codes;
}

/**
 * Trigger a browser download of the bundle as `finmate-export.json` via a Blob +
 * a transient anchor element. No-op outside a DOM (guards SSR / tests).
 */
export function downloadExportBundle(
  bundle: ExportBundle,
  filename: string = EXPORT_FILENAME,
): void {
  if (typeof document === 'undefined' || typeof URL.createObjectURL !== 'function') {
    return;
  }
  const json = serializeExportBundle(bundle);
  const blob = new Blob([json], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = filename;
  anchor.style.display = 'none';
  document.body.appendChild(anchor);
  anchor.click();
  document.body.removeChild(anchor);
  URL.revokeObjectURL(url);
}
