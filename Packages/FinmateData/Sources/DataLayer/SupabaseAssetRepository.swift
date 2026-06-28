import Foundation
import Supabase
import Domain
import Shared

// MARK: - Asset type mapping (docs/05 §3.7 schema vs. Domain AssetType)
// Canonical UNION set (ADR-0023, migration 20260628001000): schema CHECK and
// Domain AssetType now agree exactly:
//   crypto | stock | etf | cash | savings | real_estate | other
// The mapping is a lossless 1:1 round-trip across all 7 cases. The only
// camelCase↔snake_case rename is realEstate ↔ "real_estate"; every other case's
// rawValue already equals its column value.

private enum AssetTypeMapping {
    static func toColumn(_ type: AssetType) -> String { type.rawValue }

    static func toDomain(_ column: String) -> AssetType {
        AssetType(rawValue: column) ?? .other
    }
}

// MARK: - Financial asset DTO ↔ Domain (docs/05 §3.7)

struct FinancialAssetDTO: Codable, Sendable {
    let id: UUID
    let name: String
    let assetType: String
    let currency: String
    let valueMinor: Int64
    let quantity: DecimalString?
    let purchasePriceMinor: Int64?
    let currentPriceMinor: Int64?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, name, currency, quantity, notes
        case assetType = "asset_type"
        case valueMinor = "value_minor"
        case purchasePriceMinor = "purchase_price_minor"
        case currentPriceMinor = "current_price_minor"
    }

    init(_ a: FinancialAsset) {
        id = a.id
        name = a.name
        assetType = AssetTypeMapping.toColumn(a.type)
        currency = a.currency.rawValue
        valueMinor = a.valueMinor
        quantity = DecimalString(a.quantity)
        purchasePriceMinor = a.purchasePriceMinor
        currentPriceMinor = a.currentPriceMinor
        notes = a.notes
    }

    func toDomain() -> FinancialAsset {
        FinancialAsset(
            id: id,
            name: name,
            type: AssetTypeMapping.toDomain(assetType),
            currency: CurrencyCode(rawValue: currency) ?? .eur,
            quantity: quantity?.value ?? 0,
            purchasePriceMinor: purchasePriceMinor ?? 0,
            currentPriceMinor: currentPriceMinor ?? 0,
            valueMinor: valueMinor,
            notes: notes
        )
    }
}

// MARK: - Asset transaction DTO ↔ Domain (docs/05 §3.8) — `txn_type` + `date` column

struct AssetTransactionDTO: Codable, Sendable {
    let id: UUID
    let assetID: UUID
    let txnType: String
    let quantity: DecimalString
    let priceMinor: Int64
    let feesMinor: Int64?
    let date: String
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, quantity, date, notes
        case assetID = "asset_id"
        case txnType = "txn_type"
        case priceMinor = "price_minor"
        case feesMinor = "fees_minor"
    }

    init(_ t: AssetTransaction) {
        id = t.id
        assetID = t.assetID
        txnType = t.kind.rawValue
        quantity = DecimalString(t.quantity)
        priceMinor = t.priceMinor
        feesMinor = t.feesMinor
        date = SupabaseCoding.dayString(t.date)
        notes = t.notes
    }

    func toDomain() -> AssetTransaction {
        AssetTransaction(
            id: id,
            assetID: assetID,
            kind: AssetTransactionKind(rawValue: txnType) ?? .other,
            quantity: quantity.value,
            priceMinor: priceMinor,
            feesMinor: feesMinor ?? 0,
            date: SupabaseCoding.date(fromDay: date) ?? .now,
            notes: notes
        )
    }
}

// MARK: - SupabaseAssetRepository

public struct SupabaseAssetRepository: AssetRepository {
    private let provider: SupabaseClientProvider
    public init(provider: SupabaseClientProvider) { self.provider = provider }

    public func all() async throws -> [FinancialAsset] {
        let client = await provider.client()
        let rows: [FinancialAssetDTO] = try await client
            .from("financial_assets").select().order("value_minor", ascending: false).execute().value
        return rows.map { $0.toDomain() }
    }

    public func transactions(assetID: UUID) async throws -> [AssetTransaction] {
        let client = await provider.client()
        let rows: [AssetTransactionDTO] = try await client
            .from("asset_transactions")
            .select()
            .eq("asset_id", value: assetID.uuidString)
            .order("date", ascending: false)
            .execute().value
        return rows.map { $0.toDomain() }
    }

    public func upsert(_ asset: FinancialAsset) async throws {
        let client = await provider.client()
        try await client.from("financial_assets").upsert(FinancialAssetDTO(asset)).execute()
    }

    public func delete(id: UUID) async throws {
        let client = await provider.client()
        try await client.from("financial_assets").delete().eq("id", value: id.uuidString).execute()
    }

    public func recordTransaction(_ transaction: AssetTransaction) async throws {
        let client = await provider.client()
        try await client.from("asset_transactions").upsert(AssetTransactionDTO(transaction)).execute()
    }
}
