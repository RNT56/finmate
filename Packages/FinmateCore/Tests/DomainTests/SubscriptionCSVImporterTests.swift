import Testing
import Foundation
@testable import Domain

// docs/13 §9 — CSV import: tokenizer, header aliases, per-row validation, preview.
@Suite struct SubscriptionCSVImporterTests {

    // 3-row CSV: row 1 valid, row 2 invalid amount, row 3 invalid currency.
    @Test func threeRowValidInvalidAmountInvalidCurrency() {
        let csv = """
        name,amount,currency,billing_period,payment_method
        Netflix,12.99,EUR,monthly,credit_card
        Spotify,abc,EUR,monthly,paypal
        GitHub,5.00,GBP,monthly,credit_card
        """
        let preview = SubscriptionCSVImporter.parseSubscriptionsCSV(csv)

        #expect(preview.totalRows == 3)
        #expect(preview.valid.count == 1)
        #expect(preview.valid.first?.name == "Netflix")
        #expect(preview.valid.first?.amountMinor == 1299)
        #expect(preview.valid.first?.currency == .eur)

        // Row 2 (data row index → file row 3) errors on amount.
        #expect(preview.errors.contains { $0.row == 3 && $0.field == "amount" })
        // Row 3 (file row 4) errors on currency.
        #expect(preview.errors.contains { $0.row == 4 && $0.field == "currency" })
    }

    // A quoted field containing a comma parses as one field.
    @Test func quotedFieldWithComma() {
        let csv = """
        name,amount,currency
        "Acme, Inc",10.00,USD
        """
        let preview = SubscriptionCSVImporter.parseSubscriptionsCSV(csv)
        #expect(preview.valid.count == 1)
        #expect(preview.valid.first?.name == "Acme, Inc")
        #expect(preview.valid.first?.amountMinor == 1000)
        #expect(preview.valid.first?.currency == .usd)
    }

    // A European amount "1.234,56" parses to 123456 minor units.
    @Test func europeanAmountParses() {
        let csv = """
        name,amount,currency
        Adobe,"1.234,56",EUR
        """
        let preview = SubscriptionCSVImporter.parseSubscriptionsCSV(csv)
        #expect(preview.valid.count == 1)
        #expect(preview.valid.first?.amountMinor == 123_456)
    }

    // A row missing the name errors.
    @Test func missingNameErrors() {
        let csv = """
        name,amount,currency
        ,9.99,EUR
        """
        let preview = SubscriptionCSVImporter.parseSubscriptionsCSV(csv)
        #expect(preview.valid.isEmpty)
        #expect(preview.errors.contains { $0.row == 2 && $0.field == "name" && $0.message == "Missing name" })
    }

    // Header aliases (monthly_cost ↔ amount) map correctly.
    @Test func headerAliasesMap() {
        let csv = """
        service,monthly_cost,ccy,cycle,method
        Disney+,7.99,USD,monthly,paypal
        """
        let preview = SubscriptionCSVImporter.parseSubscriptionsCSV(csv)
        #expect(preview.valid.count == 1)
        let sub = preview.valid.first
        #expect(sub?.name == "Disney+")
        #expect(sub?.amountMinor == 799)
        #expect(sub?.currency == .usd)
        #expect(sub?.billingPeriod == .monthly)
        #expect(sub?.paymentMethod == .paypal)
    }

    // Defaults: blank optional columns fall back (currency→EUR, period→monthly,
    // method→other, usage→active).
    @Test func defaultsApplyForBlankColumns() {
        let csv = """
        name,amount
        Basic,3.50
        """
        let preview = SubscriptionCSVImporter.parseSubscriptionsCSV(csv)
        #expect(preview.valid.count == 1)
        let sub = preview.valid.first
        #expect(sub?.currency == .eur)
        #expect(sub?.billingPeriod == .monthly)
        #expect(sub?.paymentMethod == .other)
        #expect(sub?.usageState == .active)
    }

    // CRLF line endings tokenize correctly.
    @Test func handlesCRLF() {
        let csv = "name,amount,currency\r\nNetflix,12.99,EUR\r\n"
        let preview = SubscriptionCSVImporter.parseSubscriptionsCSV(csv)
        #expect(preview.totalRows == 1)
        #expect(preview.valid.count == 1)
        #expect(preview.valid.first?.amountMinor == 1299)
    }

    // Escaped "" quotes inside a quoted field become a literal quote.
    @Test func escapedQuotes() {
        let csv = "name,amount,currency\n\"He said \"\"hi\"\"\",5.00,EUR\n"
        let preview = SubscriptionCSVImporter.parseSubscriptionsCSV(csv)
        #expect(preview.valid.first?.name == "He said \"hi\"")
    }

    // MARK: - Header analysis + explicit-mapping parse (M6-IMPORT-05/06)

    // analyzeHeader returns the raw tokens (as written) and the alias auto-mapping.
    @Test func analyzeHeaderReportsTokensAndAutoMapping() {
        let csv = """
        Service, Monthly Cost ,CCY
        Netflix,12.99,EUR
        """
        let analysis = SubscriptionCSVImporter.analyzeHeader(csv)
        #expect(analysis.headers == ["Service", "Monthly Cost", "CCY"])
        #expect(analysis.autoMapping[.name] == 0)
        #expect(analysis.autoMapping[.amount] == 1)
        #expect(analysis.autoMapping[.currency] == 2)
        // Unmapped fields are simply absent.
        #expect(analysis.autoMapping[.usageState] == nil)
    }

    // The explicit-mapping path matches the auto path on a clean, alias-detectable CSV.
    @Test func explicitMappingMatchesAutoOnCleanCSV() {
        let csv = """
        name,amount,currency,billing_period,payment_method
        Netflix,12.99,EUR,monthly,credit_card
        Spotify,abc,EUR,monthly,paypal
        GitHub,5.00,GBP,monthly,credit_card
        """
        let auto = SubscriptionCSVImporter.parseSubscriptionsCSV(csv)
        let mapping = SubscriptionCSVImporter.analyzeHeader(csv).autoMapping
        let explicit = SubscriptionCSVImporter.parse(csv, mapping: mapping)
        // Subscriptions carry a per-parse id/startDate, so compare the meaningful
        // shape rather than identity: same valid names/amounts and the same errors.
        #expect(explicit.errors == auto.errors)
        #expect(explicit.totalRows == auto.totalRows)
        #expect(explicit.valid.map(\.name) == auto.valid.map(\.name))
        #expect(explicit.valid.map(\.amountMinor) == auto.valid.map(\.amountMinor))
        #expect(explicit.valid.count == 1)
        #expect(explicit.valid.first?.name == "Netflix")
        #expect(explicit.valid.first?.amountMinor == 1299)
    }

    // A header whose tokens do NOT auto-detect: mapping is REQUIRED. Without it the
    // auto path produces no valid rows; with an explicit mapping the rows import.
    @Test func unmappableHeaderRequiresExplicitMapping() {
        let csv = """
        col_a,col_b,col_c
        Netflix,12.99,EUR
        Spotify,7.99,USD
        """
        // Auto-detect finds nothing → name/amount blank → every row errors.
        let auto = SubscriptionCSVImporter.parseSubscriptionsCSV(csv)
        #expect(auto.valid.isEmpty)
        #expect(SubscriptionCSVImporter.analyzeHeader(csv).autoMapping.isEmpty)

        // Explicit mapping recovers all rows.
        let mapping: [SubscriptionCSVImporter.CSVField: Int] = [
            .name: 0, .amount: 1, .currency: 2,
        ]
        let explicit = SubscriptionCSVImporter.parse(csv, mapping: mapping)
        #expect(explicit.totalRows == 2)
        #expect(explicit.valid.count == 2)
        #expect(explicit.valid.first?.name == "Netflix")
        #expect(explicit.valid.first?.amountMinor == 1299)
        #expect(explicit.valid.first?.currency == .eur)
        #expect(explicit.valid.last?.amountMinor == 799)
        #expect(explicit.valid.last?.currency == .usd)
    }

    // Explicit mapping over a multi-currency file (EUR cents, USD cents, BTC sats).
    @Test func explicitMappingMultiCurrency() {
        let csv = """
        X,Y,Z
        Netflix,12.99,EUR
        GitHub,100,USD
        Wallet,0.00012345,BTC
        """
        let mapping: [SubscriptionCSVImporter.CSVField: Int] = [.name: 0, .amount: 1, .currency: 2]
        let preview = SubscriptionCSVImporter.parse(csv, mapping: mapping)
        #expect(preview.valid.count == 3)
        #expect(preview.valid[0].amountMinor == 1299)          // EUR → cents
        #expect(preview.valid[1].amountMinor == 10_000)        // USD 100.00 → cents
        #expect(preview.valid[1].currency == .usd)
        #expect(preview.valid[2].amountMinor == 12_345)        // BTC → sats
        #expect(preview.valid[2].currency == .btc)
    }

    // Explicit mapping collects the same per-row errors as the auto path (dirty rows).
    @Test func explicitMappingCollectsDirtyRowErrors() {
        let csv = """
        a,b,c
        Netflix,12.99,EUR
        ,9.99,EUR
        Spotify,abc,EUR
        GitHub,5.00,GBP
        """
        let mapping: [SubscriptionCSVImporter.CSVField: Int] = [.name: 0, .amount: 1, .currency: 2]
        let preview = SubscriptionCSVImporter.parse(csv, mapping: mapping)
        #expect(preview.totalRows == 4)
        #expect(preview.valid.count == 1)               // only Netflix is clean
        #expect(preview.errors.contains { $0.row == 3 && $0.field == "name" })      // missing name
        #expect(preview.errors.contains { $0.row == 4 && $0.field == "amount" })    // bad amount
        #expect(preview.errors.contains { $0.row == 5 && $0.field == "currency" })  // GBP unsupported
    }

    // A field mapped to "ignore" (absent from the mapping) falls back to its default;
    // remapping a column to a different field is honored.
    @Test func mappingOverrideAndIgnore() {
        // Header would auto-map col 0→name, col 1→amount, col 2→currency, but the user
        // remaps: name←col2, amount←col1, and currency is left to default (EUR).
        let csv = """
        name,amount,currency
        ignore-me,8.50,Spotify
        """
        let mapping: [SubscriptionCSVImporter.CSVField: Int] = [.name: 2, .amount: 1]
        let preview = SubscriptionCSVImporter.parse(csv, mapping: mapping)
        #expect(preview.valid.count == 1)
        #expect(preview.valid.first?.name == "Spotify")       // came from col 2
        #expect(preview.valid.first?.amountMinor == 850)
        #expect(preview.valid.first?.currency == .eur)        // unmapped → default
    }

    // MARK: - Delimiter auto-detection + BOM strip (de-DE / Excel hardening, docs/13 §9)

    // A semicolon-delimited CSV (typical de-DE Excel export) parses into the right
    // columns. The European amount "12,99" is quoted so its comma is not a delimiter.
    @Test func semicolonDelimiterParses() {
        let csv = """
        name;amount;currency;billing_period;payment_method
        Netflix;12.99;EUR;monthly;credit_card
        Spotify;7.99;USD;monthly;paypal
        """
        let preview = SubscriptionCSVImporter.parseSubscriptionsCSV(csv)
        #expect(preview.totalRows == 2)
        #expect(preview.valid.count == 2)
        #expect(preview.valid.first?.name == "Netflix")
        #expect(preview.valid.first?.amountMinor == 1299)
        #expect(preview.valid.first?.currency == .eur)
        #expect(preview.valid.first?.paymentMethod == .creditCard)
        #expect(preview.valid.last?.name == "Spotify")
        #expect(preview.valid.last?.amountMinor == 799)
        #expect(preview.valid.last?.currency == .usd)
    }

    // A tab-delimited CSV parses into the right columns.
    @Test func tabDelimiterParses() {
        let csv = "name\tamount\tcurrency\nNetflix\t12.99\tEUR\nGitHub\t5.00\tUSD\n"
        let preview = SubscriptionCSVImporter.parseSubscriptionsCSV(csv)
        #expect(preview.totalRows == 2)
        #expect(preview.valid.count == 2)
        #expect(preview.valid.first?.name == "Netflix")
        #expect(preview.valid.first?.amountMinor == 1299)
        #expect(preview.valid.first?.currency == .eur)
        #expect(preview.valid.last?.amountMinor == 500)
        #expect(preview.valid.last?.currency == .usd)
    }

    // A leading UTF-8 BOM is stripped so the first header alias still matches.
    @Test func leadingBOMStripped() {
        let csv = "\u{FEFF}name,amount,currency\nNetflix,12.99,EUR\n"
        let analysis = SubscriptionCSVImporter.analyzeHeader(csv)
        // Without the strip the first token would be "\u{FEFF}name" and miss the alias.
        #expect(analysis.headers.first == "name")
        #expect(analysis.autoMapping[.name] == 0)

        let preview = SubscriptionCSVImporter.parseSubscriptionsCSV(csv)
        #expect(preview.valid.count == 1)
        #expect(preview.valid.first?.name == "Netflix")
        #expect(preview.valid.first?.amountMinor == 1299)
    }

    // A BOM + semicolon delimiter together (the most common de-DE Excel shape) parse.
    @Test func bomPlusSemicolonParses() {
        let csv = "\u{FEFF}name;amount;currency\nNetflix;12.99;EUR\n"
        let preview = SubscriptionCSVImporter.parseSubscriptionsCSV(csv)
        #expect(preview.valid.count == 1)
        #expect(preview.valid.first?.name == "Netflix")
        #expect(preview.valid.first?.amountMinor == 1299)
        #expect(preview.valid.first?.currency == .eur)
    }

    // Plain comma CSV is unchanged: a header value containing a semicolon does NOT flip
    // the detected delimiter away from comma.
    @Test func plainCommaUnchangedDespiteSemicolonInField() {
        let csv = """
        name,amount,currency
        "Acme; Inc",10.00,USD
        """
        let preview = SubscriptionCSVImporter.parseSubscriptionsCSV(csv)
        #expect(preview.valid.count == 1)
        #expect(preview.valid.first?.name == "Acme; Inc")
        #expect(preview.valid.first?.amountMinor == 1000)
        #expect(preview.valid.first?.currency == .usd)
    }
}
