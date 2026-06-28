// SupabaseAssetsRepository — live implementation of the `AssetsRepository` protocol
// over the RLS-protected `financial_assets` table (docs/03 §3; docs/05 §3.7). RLS
// scopes every row to auth.uid() (docs/07 §3); money stays integer minor units.
//
// NOTE: the Postgres `asset_type` CHECK vocabulary (stock/crypto/savings/
// real_estate/other) differs from the Domain `AssetType` (crypto/stock/etf/cash/
// other). The mappers below translate both directions, mapping the unmatched
// classes onto the nearest Domain bucket (`savings`->`cash`, `real_estate`->`other`)
// and Domain `etf`/`cash` back onto `stock`/`savings` for persistence.

import type { SupabaseClient } from '@supabase/supabase-js';
import type { AssetTypeRow, Database, FinancialAssetRow } from '../../types/database';
import type { AssetType, FinancialAsset } from '../../core/assets';
import type { AssetsRepository } from './repository';

/** Postgres `asset_type` -> Domain `AssetType`. */
export function assetTypeFromRow(type: AssetTypeRow): AssetType {
  switch (type) {
    case 'crypto':
      return 'crypto';
    case 'stock':
      return 'stock';
    case 'savings':
      return 'cash';
    case 'real_estate':
      return 'other';
    case 'other':
      return 'other';
  }
}

/** Domain `AssetType` -> Postgres `asset_type` (round-trips the common classes;
 *  `etf` has no DB class so it persists as `stock`). */
export function assetTypeToRow(type: AssetType): AssetTypeRow {
  switch (type) {
    case 'crypto':
      return 'crypto';
    case 'stock':
      return 'stock';
    case 'etf':
      return 'stock';
    case 'cash':
      return 'savings';
    case 'other':
      return 'other';
  }
}

/** Row -> Domain. Nullable cost/qty/price columns default to 0 (docs/05 §3.7). */
export function assetFromRow(row: FinancialAssetRow): FinancialAsset {
  return {
    id: row.id,
    name: row.name,
    type: assetTypeFromRow(row.asset_type),
    currency: row.currency,
    quantity: row.quantity ?? 0,
    purchasePriceMinor: row.purchase_price_minor ?? 0,
    currentPriceMinor: row.current_price_minor ?? 0,
    valueMinor: row.value_minor,
    notes: row.notes,
  };
}

/** Domain -> Insert/Update payload. Omits `user_id` (RLS owner default) and the
 *  server-managed timestamps; `purchase_date` is not modeled in the Domain. */
export function assetToRow(asset: FinancialAsset): Partial<FinancialAssetRow> {
  return {
    id: asset.id,
    name: asset.name,
    asset_type: assetTypeToRow(asset.type),
    currency: asset.currency,
    value_minor: asset.valueMinor,
    quantity: asset.quantity,
    purchase_price_minor: asset.purchasePriceMinor,
    current_price_minor: asset.currentPriceMinor,
    notes: asset.notes,
  };
}

export class SupabaseAssetsRepository implements AssetsRepository {
  constructor(private readonly client: SupabaseClient<Database>) {}

  async all(): Promise<FinancialAsset[]> {
    const { data, error } = await this.client
      .from('financial_assets')
      .select('*')
      .order('name', { ascending: true });
    if (error) throw error;
    return (data ?? []).map(assetFromRow);
  }

  async upsert(asset: FinancialAsset): Promise<void> {
    const { error } = await this.client
      .from('financial_assets')
      .upsert(assetToRow(asset), { onConflict: 'id' });
    if (error) throw error;
  }

  async remove(id: string): Promise<void> {
    const { error } = await this.client.from('financial_assets').delete().eq('id', id);
    if (error) throw error;
  }
}
