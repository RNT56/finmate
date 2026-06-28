import Testing
import Foundation
@testable import Domain

// docs/13 §9, docs/02 §6 — CSV import generalized to income + fixed/variable expenses.
// Each suite reuses the shared CSVImportKit tokenizer/number-parser/mapping machinery
// via its sibling importer. Fixtures: clean, dirty, multi-currency, category name→id,
// missing-required.

// MARK: - Income

@Suite struct IncomeCSVImporterTests {

    // analyzeHeader returns raw tokens + the alias auto-mapping.
    @Test func analyzeHeaderAutoMaps() {
        let csv = """
        Source, Pay ,CCY,Freq
        Salary,3000,EUR,monthly
        """
        let a = IncomeCSVImporter.analyzeHeader(csv)
        #expect(a.headers == ["Source", "Pay", "CCY", "Freq"])
        #expect(a.autoMapping[.name] == 0)
        #expect(a.autoMapping[.amount] == 1)
        #expect(a.autoMapping[.currency] == 2)
        #expect(a.autoMapping[.frequency] == 3)
        #expect(a.autoMapping[.notes] == nil)
    }

    // Clean rows import with frequency + next_payment parsed.
    @Test func cleanRows() {
        let csv = """
        name,amount,currency,frequency,next_payment,notes
        Salary,3000.00,EUR,monthly,2026-07-01,Main job
        Dividend,150,USD,yearly,,
        Gift,50,EUR,one_time,,Birthday
        """
        let mapping = IncomeCSVImporter.analyzeHeader(csv).autoMapping
        let preview = IncomeCSVImporter.parse(csv, mapping: mapping)
        #expect(preview.totalRows == 3)
        #expect(preview.valid.count == 3)
        #expect(preview.valid[0].name == "Salary")
        #expect(preview.valid[0].amountMinor == 300_000)
        #expect(preview.valid[0].frequency == .monthly)
        #expect(preview.valid[0].nextPayment != nil)
        #expect(preview.valid[0].notes == "Main job")
        #expect(preview.valid[2].frequency == .oneTime)
        #expect(preview.valid[1].currency == .usd)
    }

    // Multi-currency: EUR cents, USD cents, BTC sats.
    @Test func multiCurrency() {
        let csv = """
        name,amount,currency
        Salary,3000,EUR
        Bonus,1000,USD
        Mining,0.00012345,BTC
        """
        let mapping = IncomeCSVImporter.analyzeHeader(csv).autoMapping
        let preview = IncomeCSVImporter.parse(csv, mapping: mapping)
        #expect(preview.valid.count == 3)
        #expect(preview.valid[0].amountMinor == 300_000)
        #expect(preview.valid[1].amountMinor == 100_000)
        #expect(preview.valid[2].amountMinor == 12_345)
        #expect(preview.valid[2].currency == .btc)
    }

    // Dirty: bad amount, bad currency, bad frequency, bad date, missing name.
    @Test func dirtyRowsCollectAllErrors() {
        let csv = """
        name,amount,currency,frequency,next_payment
        Salary,abc,EUR,monthly,2026-07-01
        Side,500,GBP,monthly,2026-07-01
        Odd,500,EUR,fortnightly,2026-07-01
        Bad,500,EUR,monthly,not-a-date
        ,500,EUR,monthly,2026-07-01
        """
        let mapping = IncomeCSVImporter.analyzeHeader(csv).autoMapping
        let preview = IncomeCSVImporter.parse(csv, mapping: mapping)
        #expect(preview.totalRows == 5)
        #expect(preview.valid.isEmpty)
        #expect(preview.errors.contains { $0.row == 2 && $0.field == "amount" })
        #expect(preview.errors.contains { $0.row == 3 && $0.field == "currency" })
        #expect(preview.errors.contains { $0.row == 4 && $0.field == "frequency" })
        #expect(preview.errors.contains { $0.row == 5 && $0.field == "next_payment" })
        #expect(preview.errors.contains { $0.row == 6 && $0.field == "name" })
    }

    // Missing-required: amount blank errors.
    @Test func missingRequiredAmount() {
        let csv = """
        name,amount
        Salary,
        """
        let mapping = IncomeCSVImporter.analyzeHeader(csv).autoMapping
        let preview = IncomeCSVImporter.parse(csv, mapping: mapping)
        #expect(preview.valid.isEmpty)
        #expect(preview.errors.contains { $0.row == 2 && $0.field == "amount" })
    }
}

// MARK: - Fixed expense

@Suite struct FixedExpenseCSVImporterTests {

    private static let categories: [Domain.Category] = [
        Domain.Category(name: "Housing", slug: "housing", kind: .expense),
        Domain.Category(name: "Utilities", slug: "utilities", kind: .expense),
    ]

    @Test func analyzeHeaderAutoMaps() {
        let csv = """
        name,amount,currency,category,frequency,due_date,autopay
        Rent,1200,EUR,Housing,monthly,2026-07-01,true
        """
        let a = FixedExpenseCSVImporter.analyzeHeader(csv)
        #expect(a.autoMapping[.name] == 0)
        #expect(a.autoMapping[.amount] == 1)
        #expect(a.autoMapping[.category] == 3)
        #expect(a.autoMapping[.frequency] == 4)
        #expect(a.autoMapping[.dueDate] == 5)
        #expect(a.autoMapping[.autopay] == 6)
    }

    // Clean + category NAME → id (case-insensitive) + autopay bool.
    @Test func cleanRowsResolveCategoryNameToID() {
        let csv = """
        name,amount,currency,category,frequency,due_date,autopay
        Rent,1200.00,EUR,Housing,monthly,2026-07-01,true
        Power,90,EUR,utilities,monthly,2026-07-15,no
        Unknown,30,EUR,Mystery,monthly,,
        """
        let mapping = FixedExpenseCSVImporter.analyzeHeader(csv).autoMapping
        let preview = FixedExpenseCSVImporter.parse(csv, mapping: mapping, categories: Self.categories)
        #expect(preview.valid.count == 3)
        #expect(preview.valid[0].amountMinor == 120_000)
        #expect(preview.valid[0].categoryID == Self.categories[0].id)   // "Housing"
        #expect(preview.valid[0].autopay == true)
        #expect(preview.valid[1].categoryID == Self.categories[1].id)   // "utilities" case-insensitive
        #expect(preview.valid[1].autopay == false)
        #expect(preview.valid[2].categoryID == nil)                     // "Mystery" → Uncategorized
    }

    @Test func multiCurrency() {
        let csv = """
        name,amount,currency
        Rent,1200,EUR
        Server,20,USD
        Cold,0.001,BTC
        """
        let mapping = FixedExpenseCSVImporter.analyzeHeader(csv).autoMapping
        let preview = FixedExpenseCSVImporter.parse(csv, mapping: mapping, categories: Self.categories)
        #expect(preview.valid.count == 3)
        #expect(preview.valid[0].amountMinor == 120_000)
        #expect(preview.valid[1].amountMinor == 2_000)
        #expect(preview.valid[2].amountMinor == 100_000)
        #expect(preview.valid[2].currency == .btc)
    }

    @Test func dirtyRowsCollectAllErrors() {
        let csv = """
        name,amount,currency,frequency,due_date,autopay
        Rent,1200,EUR,monthly,2026-07-01,true
        Bad,xx,EUR,monthly,2026-07-01,true
        Cur,10,GBP,monthly,2026-07-01,true
        Freq,10,EUR,fortnightly,2026-07-01,true
        Date,10,EUR,monthly,nope,true
        Auto,10,EUR,monthly,2026-07-01,maybe
        """
        let mapping = FixedExpenseCSVImporter.analyzeHeader(csv).autoMapping
        let preview = FixedExpenseCSVImporter.parse(csv, mapping: mapping, categories: Self.categories)
        #expect(preview.valid.count == 1)
        #expect(preview.errors.contains { $0.row == 3 && $0.field == "amount" })
        #expect(preview.errors.contains { $0.row == 4 && $0.field == "currency" })
        #expect(preview.errors.contains { $0.row == 5 && $0.field == "frequency" })
        #expect(preview.errors.contains { $0.row == 6 && $0.field == "due_date" })
        #expect(preview.errors.contains { $0.row == 7 && $0.field == "autopay" })
    }

    @Test func missingRequiredName() {
        let csv = """
        name,amount
        ,1200
        """
        let mapping = FixedExpenseCSVImporter.analyzeHeader(csv).autoMapping
        let preview = FixedExpenseCSVImporter.parse(csv, mapping: mapping, categories: Self.categories)
        #expect(preview.valid.isEmpty)
        #expect(preview.errors.contains { $0.row == 2 && $0.field == "name" })
    }

    // Weekly frequency is supported (BillingPeriod.weekly).
    @Test func weeklyFrequencySupported() {
        let csv = """
        name,amount,frequency
        Cleaner,50,weekly
        """
        let mapping = FixedExpenseCSVImporter.analyzeHeader(csv).autoMapping
        let preview = FixedExpenseCSVImporter.parse(csv, mapping: mapping, categories: Self.categories)
        #expect(preview.valid.count == 1)
        #expect(preview.valid[0].frequency == .weekly)
    }
}

// MARK: - Variable expense

@Suite struct VariableExpenseCSVImporterTests {

    private static let categories: [Domain.Category] = [
        Domain.Category(name: "Groceries", slug: "groceries", kind: .expense),
        Domain.Category(name: "Dining", slug: "dining", kind: .expense),
    ]

    @Test func analyzeHeaderAutoMapsSpentOn() {
        let csv = """
        name,amount,currency,category,spent_on
        Lunch,12.50,EUR,Dining,2026-06-15
        """
        let a = VariableExpenseCSVImporter.analyzeHeader(csv)
        #expect(a.autoMapping[.name] == 0)
        #expect(a.autoMapping[.amount] == 1)
        #expect(a.autoMapping[.category] == 3)
        #expect(a.autoMapping[.date] == 4)
    }

    @Test func cleanRowsResolveCategoryNameToID() {
        let csv = """
        name,amount,currency,category,spent_on
        Groceries,45.20,EUR,Groceries,2026-06-10
        Lunch,12.50,EUR,dining,2026-06-15
        Misc,5,EUR,Nope,2026-06-16
        """
        let mapping = VariableExpenseCSVImporter.analyzeHeader(csv).autoMapping
        let preview = VariableExpenseCSVImporter.parse(csv, mapping: mapping, categories: Self.categories)
        #expect(preview.valid.count == 3)
        #expect(preview.valid[0].amountMinor == 4_520)
        #expect(preview.valid[0].categoryID == Self.categories[0].id)
        #expect(preview.valid[1].categoryID == Self.categories[1].id)   // case-insensitive
        #expect(preview.valid[2].categoryID == nil)
    }

    @Test func multiCurrency() {
        let csv = """
        name,amount,currency,spent_on
        A,10,EUR,2026-06-10
        B,10,USD,2026-06-10
        C,0.0005,BTC,2026-06-10
        """
        let mapping = VariableExpenseCSVImporter.analyzeHeader(csv).autoMapping
        let preview = VariableExpenseCSVImporter.parse(csv, mapping: mapping, categories: Self.categories)
        #expect(preview.valid.count == 3)
        #expect(preview.valid[0].amountMinor == 1_000)
        #expect(preview.valid[1].amountMinor == 1_000)
        #expect(preview.valid[2].amountMinor == 50_000)
        #expect(preview.valid[2].currency == .btc)
    }

    // date is REQUIRED for variable expenses — missing/invalid errors.
    @Test func missingRequiredDateErrors() {
        let csv = """
        name,amount,spent_on
        NoDate,10,
        BadDate,10,not-a-date
        Good,10,2026-06-10
        """
        let mapping = VariableExpenseCSVImporter.analyzeHeader(csv).autoMapping
        let preview = VariableExpenseCSVImporter.parse(csv, mapping: mapping, categories: Self.categories)
        #expect(preview.totalRows == 3)
        #expect(preview.valid.count == 1)
        #expect(preview.valid[0].name == "Good")
        #expect(preview.errors.contains { $0.row == 2 && $0.field == "date" })
        #expect(preview.errors.contains { $0.row == 3 && $0.field == "date" })
    }

    @Test func dirtyRowsCollectAllErrors() {
        let csv = """
        name,amount,currency,spent_on
        Good,10,EUR,2026-06-10
        ,10,EUR,2026-06-10
        Bad,xx,EUR,2026-06-10
        Cur,10,GBP,2026-06-10
        """
        let mapping = VariableExpenseCSVImporter.analyzeHeader(csv).autoMapping
        let preview = VariableExpenseCSVImporter.parse(csv, mapping: mapping, categories: Self.categories)
        #expect(preview.valid.count == 1)
        #expect(preview.errors.contains { $0.row == 3 && $0.field == "name" })
        #expect(preview.errors.contains { $0.row == 4 && $0.field == "amount" })
        #expect(preview.errors.contains { $0.row == 5 && $0.field == "currency" })
    }

    // Explicit mapping over an unmappable header recovers rows (shared machinery).
    @Test func explicitMappingUnmappableHeader() {
        let csv = """
        c0,c1,c2
        Lunch,12.50,2026-06-15
        """
        let mapping: [VariableExpenseCSVImporter.CSVField: Int] = [.name: 0, .amount: 1, .date: 2]
        let preview = VariableExpenseCSVImporter.parse(csv, mapping: mapping, categories: Self.categories)
        #expect(preview.valid.count == 1)
        #expect(preview.valid[0].name == "Lunch")
        #expect(preview.valid[0].amountMinor == 1_250)
    }
}
