import { describe, it, expect } from 'vitest';
import { assetTypeFromRow, assetTypeToRow } from './supabaseRepository';
import { allAssetTypes, type AssetType } from '../../core/assets';
import type { AssetTypeRow } from '../../types/database';

// ADR-0023: the Postgres asset_type CHECK now matches the Domain AssetType union
// exactly, so the mappers round-trip 1:1 across all 7 classes with no lossy bucketing.

const ALL_ROWS: AssetTypeRow[] = [
  'crypto',
  'stock',
  'etf',
  'cash',
  'savings',
  'real_estate',
  'other',
];

describe('asset_type mapper (1:1 round-trip, all 7 classes)', () => {
  it('Domain -> row preserves every type', () => {
    for (const t of allAssetTypes) {
      expect(assetTypeToRow(t)).toBe(t as unknown as AssetTypeRow);
    }
  });

  it('row -> Domain preserves every type', () => {
    for (const r of ALL_ROWS) {
      expect(assetTypeFromRow(r)).toBe(r as unknown as AssetType);
    }
  });

  it('round-trips Domain -> row -> Domain for all 7 types', () => {
    for (const t of allAssetTypes) {
      expect(assetTypeFromRow(assetTypeToRow(t))).toBe(t);
    }
  });

  it('covers exactly the 7 canonical classes', () => {
    expect(ALL_ROWS).toHaveLength(7);
    expect(allAssetTypes).toHaveLength(7);
  });
});
