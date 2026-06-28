import Testing
import Foundation
@testable import Domain

// docs/07 §9.3 / docs/02 §12 — the data-export bundle: round-trippable JSON,
// money stays in RAW minor units + ISO currency (no preformatting, no display
// conversion), and the bundle records schemaVersion + exportedAt.
@Suite struct DataExportTests {

    // A representative multi-currency snapshot.
    private func sampleBundle(exportedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> ExportBundle {
        let sub = Subscription(
            name: "Netflix", amountMinor: 1599, currency: .eur,
            billingPeriod: .monthly, startDate: Date(timeIntervalSince1970: 1_600_000_000)
        )
        let income = IncomeSource(
            name: "Salary", amountMinor: 350_000, currency: .eur, frequency: .monthly
        )
        let fixed = FixedExpense(
            name: "Rent", amountMinor: 120_000, currency: .eur, frequency: .monthly
        )
        let variable = VariableExpense(
            name: "Groceries", amountMinor: 4_250, currency: .usd,
            date: Date(timeIntervalSince1970: 1_690_000_000)
        )
        let asset = FinancialAsset(
            name: "Bitcoin", type: .crypto, currency: .btc,
            quantity: Decimal(string: "0.5")!, purchasePriceMinor: 2_000_000_000,
            currentPriceMinor: 5_000_000_000, valueMinor: 2_500_000_000
        )
        var prefs = UserPreferences.defaults
        prefs.defaultCurrency = .usd
        prefs.biometricLockEnabled = true
        return ExportBundle(
            exportedAt: exportedAt,
            subscriptions: [sub], income: [income],
            fixedExpenses: [fixed], variableExpenses: [variable],
            assets: [asset], preferences: prefs
        )
    }

    @Test func encodesAndDecodesRoundTrip() throws {
        let bundle = sampleBundle()
        let data = try DataExport.encode(bundle)
        let decoded = try DataExport.decode(data)
        #expect(decoded == bundle)
    }

    @Test func defaultSchemaVersionIsCurrent() {
        let bundle = sampleBundle()
        #expect(bundle.schemaVersion == ExportBundle.currentSchemaVersion)
        #expect(ExportBundle.currentSchemaVersion == 1)
    }

    @Test func jsonCarriesRawMinorUnitsNotFormatted() throws {
        let bundle = sampleBundle()
        let data = try DataExport.encode(bundle)
        let json = String(decoding: data, as: UTF8.self)

        // RAW minor units present as integers; no currency symbols / formatting.
        #expect(json.contains("\"amountMinor\" : 1599"))      // Netflix cents
        #expect(json.contains("\"valueMinor\" : 2500000000")) // BTC sats, raw
        #expect(json.contains("\"currency\" : \"EUR\""))
        #expect(json.contains("\"currency\" : \"BTC\""))
        // No preformatted money leaked into the bundle.
        #expect(!json.contains("€"))
        #expect(!json.contains("$"))
        #expect(!json.contains("15.99"))
    }

    @Test func moneyStaysInOwnCurrencyNoDisplayConversion() throws {
        // The USD variable expense and BTC asset must keep their own currency —
        // export never converts to the preferences' display currency.
        let bundle = sampleBundle()
        let decoded = try DataExport.decode(try DataExport.encode(bundle))
        #expect(decoded.preferences.defaultCurrency == .usd)
        #expect(decoded.variableExpenses.first?.currency == .usd)
        #expect(decoded.variableExpenses.first?.amountMinor == 4_250)
        #expect(decoded.assets.first?.currency == .btc)
        #expect(decoded.assets.first?.valueMinor == 2_500_000_000)
    }

    @Test func exportedAtAndSchemaSurviveRoundTrip() throws {
        let when = Date(timeIntervalSince1970: 1_711_111_111)
        let bundle = sampleBundle(exportedAt: when)
        let decoded = try DataExport.decode(try DataExport.encode(bundle))
        // ISO-8601 strategy is whole-second precision.
        #expect(Int(decoded.exportedAt.timeIntervalSince1970) == Int(when.timeIntervalSince1970))
        #expect(decoded.schemaVersion == bundle.schemaVersion)
    }

    @Test func emptyBundleRoundTrips() throws {
        let empty = ExportBundle(
            exportedAt: Date(timeIntervalSince1970: 0),
            subscriptions: [], income: [], fixedExpenses: [],
            variableExpenses: [], assets: [], preferences: .defaults
        )
        let decoded = try DataExport.decode(try DataExport.encode(empty))
        #expect(decoded == empty)
        #expect(decoded.subscriptions.isEmpty)
        #expect(decoded.assets.isEmpty)
    }

    @Test func filenameIsCanonical() {
        #expect(DataExport.fileName == "finmate-export.json")
    }
}
