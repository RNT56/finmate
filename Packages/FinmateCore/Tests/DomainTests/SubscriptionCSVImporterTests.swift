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
}
