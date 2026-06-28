import Foundation
import Shared

// MARK: - Data export (docs/07 §9.3, docs/02 §12) — GDPR / App Store data export
//
// A pure, deterministic serializer that bundles a snapshot of the user's data
// (subscriptions, income, fixed + variable expenses, assets, preferences) into a
// Codable `ExportBundle` and stable JSON `Data`. Money is carried as RAW
// `minorUnits` + ISO `currency` — NEVER preformatted and NEVER converted to a
// display currency (docs/05 §2.2; fixes Substimate's pre-conversion bug). The
// bundle records a `schemaVersion` + `exportedAt` so an import path (and humans)
// can interpret it. No UI, no Supabase — the App layer assembles the inputs from
// the live repositories and writes/shares the resulting `Data`.

/// A self-describing snapshot of the user's Finmate data. Round-trippable JSON:
/// every field is `Codable` and money stays in minor units + currency.
public struct ExportBundle: Equatable, Sendable, Codable {
    /// Bundle schema version (bump when the shape changes). Independent of the
    /// app/build version so importers can branch on the data contract.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var exportedAt: Date
    public var subscriptions: [Subscription]
    public var income: [IncomeSource]
    public var fixedExpenses: [FixedExpense]
    public var variableExpenses: [VariableExpense]
    public var assets: [FinancialAsset]
    public var preferences: UserPreferences

    public init(schemaVersion: Int = ExportBundle.currentSchemaVersion,
                exportedAt: Date,
                subscriptions: [Subscription],
                income: [IncomeSource],
                fixedExpenses: [FixedExpense],
                variableExpenses: [VariableExpense],
                assets: [FinancialAsset],
                preferences: UserPreferences) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.subscriptions = subscriptions
        self.income = income
        self.fixedExpenses = fixedExpenses
        self.variableExpenses = variableExpenses
        self.assets = assets
        self.preferences = preferences
    }
}

/// Pure JSON (de)serialization for `ExportBundle`. Deterministic key ordering and
/// ISO-8601 dates so the same snapshot always produces the same bytes (testable,
/// diff-friendly). Suggested filename is `finmate-export.json`.
public enum DataExport {
    /// Canonical export filename for the share sheet / file write.
    public static let fileName = "finmate-export.json"

    /// Encoder configured for a stable, human-readable, round-trippable bundle.
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Decoder matching `makeEncoder()` (ISO-8601 dates).
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Serialize a bundle to JSON `Data`. Money stays as `minorUnits` + `currency`.
    public static func encode(_ bundle: ExportBundle) throws -> Data {
        try makeEncoder().encode(bundle)
    }

    /// Decode a bundle from JSON `Data` (the inverse of `encode`).
    public static func decode(_ data: Data) throws -> ExportBundle {
        try makeDecoder().decode(ExportBundle.self, from: data)
    }
}
