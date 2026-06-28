import Foundation
import Shared

// MARK: - Import duplicate detection (docs/13 §9, M6) — advisory, not hard errors.
//
// A pure, additive helper layered over the existing `EntityImportPreview` machinery.
// During the import preview the UI flags rows that are *likely* duplicates as
// skippable warnings (NOT validation errors): (a) within-CSV duplicates — another
// valid row with the same normalized dedupe key — and (b) rows matching an EXISTING
// entity, whose keys the caller passes in. The user can still import everything; the
// hint is advisory, with an "import non-duplicates only" affordance built on the
// flagged-index set.
//
// The dedupe key is `name|amountMinor|currency` with the name lowercased + trimmed
// and the currency upcased — matching the web `csvImport.ts` port's vectors.

/// Anything that can be deduplicated by its display name, minor-unit amount, and
/// currency. The four CSV-import entities (`Subscription`, `IncomeSource`,
/// `FixedExpense`, `VariableExpense`) all conform automatically.
public protocol DuplicateKeyed {
    var name: String { get }
    var amountMinor: Int64 { get }
    var currency: CurrencyCode { get }
}

extension Subscription: DuplicateKeyed {}
extension IncomeSource: DuplicateKeyed {}
extension FixedExpense: DuplicateKeyed {}
extension VariableExpense: DuplicateKeyed {}

/// The outcome of scanning a set of valid rows for likely duplicates.
public struct DuplicateScan: Equatable, Sendable {
    /// The indices (into the scanned `rows` array) flagged as likely duplicates —
    /// either a within-CSV repeat or a match against an existing key.
    public let flaggedIndices: Set<Int>
    /// The normalized dedupe key computed per row (parallel to `rows`).
    public let keys: [String]

    public init(flaggedIndices: Set<Int>, keys: [String]) {
        self.flaggedIndices = flaggedIndices
        self.keys = keys
    }

    /// Count of flagged rows.
    public var flaggedCount: Int { flaggedIndices.count }

    /// True if a given row index is flagged.
    public func isFlagged(_ index: Int) -> Bool { flaggedIndices.contains(index) }
}

public enum ImportDuplicateDetector {

    /// Build the normalized dedupe key for one keyed value:
    /// `lowercased+trimmed name | amountMinor | upcased currency`.
    public static func duplicateKey(name: String, amountMinor: Int64, currency: CurrencyCode) -> String {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(normalizedName)|\(amountMinor)|\(currency.rawValue.uppercased())"
    }

    /// Build the dedupe key for a keyed entity.
    public static func duplicateKey(_ entity: DuplicateKeyed) -> String {
        duplicateKey(name: entity.name, amountMinor: entity.amountMinor, currency: entity.currency)
    }

    /// Build the set of dedupe keys for a collection of existing entities — pass this
    /// as `existingKeys` to `findDuplicates` so newly imported rows that match a row
    /// already in the user's data are flagged.
    public static func keys(for entities: [DuplicateKeyed]) -> Set<String> {
        Set(entities.map { duplicateKey($0) })
    }

    /// Scan `rows` for likely duplicates. A row is flagged when its normalized dedupe
    /// key either (a) matches a key in `existingKeys`, or (b) has already appeared
    /// among the earlier rows of `rows` (a within-CSV duplicate — the FIRST occurrence
    /// is NOT flagged; every subsequent repeat is). Case- and whitespace-insensitive on
    /// the name. Pure & order-stable.
    public static func findDuplicates(
        _ rows: [DuplicateKeyed],
        existingKeys: Set<String> = []
    ) -> DuplicateScan {
        var keys: [String] = []
        keys.reserveCapacity(rows.count)
        var flagged: Set<Int> = []
        var seen: Set<String> = []

        for (index, row) in rows.enumerated() {
            let key = duplicateKey(row)
            keys.append(key)
            if existingKeys.contains(key) || seen.contains(key) {
                flagged.insert(index)
            }
            seen.insert(key)
        }
        return DuplicateScan(flaggedIndices: flagged, keys: keys)
    }
}
