import Testing
import Foundation
@testable import Domain

// docs/13 §9, M6 — import duplicate detection (advisory, skippable warnings).
// Matching Swift+TS vectors live alongside the web `csvImport.ts` duplicate scan.
// Dedupe key = `lowercased+trimmed name | amountMinor | upcased currency`.

@Suite struct ImportDuplicateDetectorTests {

    private func sub(_ name: String, _ minor: Int64, _ ccy: CurrencyCode = .eur) -> Subscription {
        Subscription(name: name, amountMinor: minor, currency: ccy, billingPeriod: .monthly, startDate: Date())
    }

    // MARK: key construction

    @Test func keyNormalizesNameAndCurrency() {
        let key = ImportDuplicateDetector.duplicateKey(name: "  NetFlix  ", amountMinor: 1299, currency: .eur)
        #expect(key == "netflix|1299|EUR")
    }

    @Test func keyForEntityMatchesExplicitKey() {
        let s = sub("Spotify", 999, .usd)
        #expect(ImportDuplicateDetector.duplicateKey(s) ==
                ImportDuplicateDetector.duplicateKey(name: "spotify", amountMinor: 999, currency: .usd))
    }

    // MARK: within-CSV duplicates

    @Test func withinCSVDuplicatesFlagLaterOccurrences() {
        let rows: [DuplicateKeyed] = [
            sub("Netflix", 1299),   // 0 — first, not flagged
            sub("Spotify", 999),    // 1 — unique
            sub("netflix", 1299),   // 2 — dup of 0 (case-insensitive)
        ]
        let scan = ImportDuplicateDetector.findDuplicates(rows)
        #expect(scan.flaggedIndices == [2])
        #expect(scan.flaggedCount == 1)
        #expect(scan.isFlagged(2))
        #expect(!scan.isFlagged(0))
    }

    @Test func caseAndWhitespaceInsensitive() {
        let rows: [DuplicateKeyed] = [
            sub("Netflix", 1299),
            sub("  NETFLIX ", 1299),
        ]
        let scan = ImportDuplicateDetector.findDuplicates(rows)
        #expect(scan.flaggedIndices == [1])
    }

    // MARK: against existing keys

    @Test func matchesAgainstExistingKeys() {
        let existing = ImportDuplicateDetector.keys(for: [sub("Netflix", 1299)])
        let rows: [DuplicateKeyed] = [
            sub("Netflix", 1299),   // 0 — matches existing
            sub("Spotify", 999),    // 1 — new
        ]
        let scan = ImportDuplicateDetector.findDuplicates(rows, existingKeys: existing)
        #expect(scan.flaggedIndices == [0])
    }

    @Test func differentAmountOrCurrencyIsNotADuplicate() {
        let existing = ImportDuplicateDetector.keys(for: [sub("Netflix", 1299, .eur)])
        let rows: [DuplicateKeyed] = [
            sub("Netflix", 1300, .eur),   // different amount
            sub("Netflix", 1299, .usd),   // different currency
        ]
        let scan = ImportDuplicateDetector.findDuplicates(rows, existingKeys: existing)
        #expect(scan.flaggedIndices.isEmpty)
    }

    // MARK: no duplicates

    @Test func noDuplicatesFlagsNothing() {
        let rows: [DuplicateKeyed] = [
            sub("Netflix", 1299),
            sub("Spotify", 999),
            sub("GitHub", 10000, .usd),
        ]
        let scan = ImportDuplicateDetector.findDuplicates(rows)
        #expect(scan.flaggedIndices.isEmpty)
        #expect(scan.keys.count == 3)
    }

    @Test func emptyRowsIsEmptyScan() {
        let scan = ImportDuplicateDetector.findDuplicates([])
        #expect(scan.flaggedIndices.isEmpty)
        #expect(scan.keys.isEmpty)
    }

    // MARK: cross-entity (income / fixed / variable conform too)

    @Test func worksAcrossEntityTypes() {
        let rows: [DuplicateKeyed] = [
            IncomeSource(name: "Salary", amountMinor: 300000, currency: .eur, frequency: .monthly),
            IncomeSource(name: "salary", amountMinor: 300000, currency: .eur, frequency: .monthly),
        ]
        let scan = ImportDuplicateDetector.findDuplicates(rows)
        #expect(scan.flaggedIndices == [1])
    }
}
