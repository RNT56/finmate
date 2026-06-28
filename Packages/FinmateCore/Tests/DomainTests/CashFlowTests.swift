import Testing
import Foundation
@testable import Domain

// docs/13 §6 — Cash-flow metrics (income/expense roll-ups, net, savings rate).
// Worked vectors mirror the M2 sample data so iOS and web agree on the numbers.
@Suite struct CashFlowTests {

    private func eurMonthly(_ name: String, _ minor: Int64) -> IncomeSource {
        IncomeSource(name: name, amountMinor: minor, currency: .eur, frequency: .monthly)
    }

    // MARK: Monthly income roll-up (docs/13 §6.1)

    @Test func monthlyIncomeSumsRecurringSources() {
        let income = [eurMonthly("Salary", 320_000), eurMonthly("Freelance", 60_000)]
        #expect(CashFlow.monthlyIncomeMinor(income) == 380_000)
    }

    @Test func oneTimeIncomeExcludedFromRecurringRollup() {
        let income = [
            eurMonthly("Salary", 320_000),
            eurMonthly("Freelance", 60_000),
            IncomeSource(name: "Tax refund", amountMinor: 500_000, currency: .eur, frequency: .oneTime),
        ]
        // The one_time 500000 must NOT inflate the recurring monthly income.
        #expect(CashFlow.monthlyIncomeMinor(income) == 380_000)
    }

    @Test func weeklyIncomeNormalizedHalfUp() {
        // docs/13 T6.d: weekly €100/wk → HALF_UP(10000 × 52/12) = 43333.
        let weekly = IncomeSource(name: "Tips", amountMinor: 10_000, currency: .eur, frequency: .weekly)
        #expect(weekly.monthlyMinor == 43_333)
        #expect(CashFlow.monthlyIncomeMinor([weekly]) == 43_333)
    }

    @Test func yearlyIncomeNormalizedHalfUp() {
        let yearly = IncomeSource(name: "Bonus", amountMinor: 120_000, currency: .eur, frequency: .yearly)
        #expect(yearly.monthlyMinor == 10_000)
    }

    // MARK: Expense roll-up (docs/13 §6.2)

    @Test func fixedExpensesNormalizedToMonthly() {
        let rent = FixedExpense(name: "Rent", amountMinor: 110_000, currency: .eur, frequency: .monthly)
        let insurance = FixedExpense(name: "Insurance", amountMinor: 9_000, currency: .eur, frequency: .monthly)
        let quarterly = FixedExpense(name: "Gym", amountMinor: 9_000, currency: .eur, frequency: .quarterly)
        #expect(rent.monthlyMinor == 110_000)
        #expect(insurance.monthlyMinor == 9_000)
        #expect(quarterly.monthlyMinor == 3_000) // 9000 / 3
    }

    @Test func variableThisMonthFiltersByMonth() {
        let cal = Calendar(identifier: .gregorian)
        let ref = DateComponents(calendar: cal, year: 2026, month: 6, day: 15).date!
        let inMonth = VariableExpense(name: "Groceries", amountMinor: 40_000, currency: .eur,
                                      date: DateComponents(calendar: cal, year: 2026, month: 6, day: 3).date!)
        let lastMonth = VariableExpense(name: "Old", amountMinor: 99_000, currency: .eur,
                                        date: DateComponents(calendar: cal, year: 2026, month: 5, day: 28).date!)
        #expect(CashFlow.variableThisMonthMinor([inMonth, lastMonth], reference: ref, calendar: cal) == 40_000)
    }

    @Test func monthlyExpensesAggregate() {
        let fixed = [
            FixedExpense(name: "Rent", amountMinor: 110_000, currency: .eur, frequency: .monthly),
            FixedExpense(name: "Insurance", amountMinor: 9_000, currency: .eur, frequency: .monthly),
        ]
        // fixed 119000 + subs 2648 + variable 40000 = 161648
        let total = CashFlow.monthlyExpensesMinor(
            fixed: fixed, variableThisMonthMinor: 40_000, subscriptionsMonthlyMinor: 2_648)
        #expect(total == 161_648)
    }

    // MARK: Net & savings rate (docs/13 §6.3) — the M2 sample-data vector

    @Test func sampleDataNetAndSavingsRate() {
        let cal = Calendar(identifier: .gregorian)
        let ref = DateComponents(calendar: cal, year: 2026, month: 6, day: 15).date!
        let income = [eurMonthly("Salary", 320_000), eurMonthly("Freelance", 60_000)]
        let fixed = [
            FixedExpense(name: "Rent", amountMinor: 110_000, currency: .eur, frequency: .monthly),
            FixedExpense(name: "Insurance", amountMinor: 9_000, currency: .eur, frequency: .monthly),
        ]
        let variable = [
            VariableExpense(name: "Groceries", amountMinor: 40_000, currency: .eur,
                            date: DateComponents(calendar: cal, year: 2026, month: 6, day: 5).date!),
        ]
        let m = CashFlow.metrics(income: income, fixed: fixed, variable: variable,
                                 subscriptionsMonthlyMinor: 2_648, reference: ref, calendar: cal)
        #expect(m.incomeMinor == 380_000)
        #expect(m.expenseMinor == 161_648)
        #expect(m.netMinor == 218_352)
        // savingsRate = 218352 / 380000 ≈ 0.574610…
        #expect(abs(m.savingsRate - (218_352.0 / 380_000.0)) < 1e-9)
    }

    @Test func zeroIncomeSavingsRateGuarded() {
        // docs/13 T6.c — zero-income guard, not NaN.
        let m = CashFlow.metrics(income: [], fixed: [
            FixedExpense(name: "Rent", amountMinor: 100_000, currency: .eur, frequency: .monthly),
        ], variable: [], subscriptionsMonthlyMinor: 0)
        #expect(m.incomeMinor == 0)
        #expect(m.netMinor == -100_000)
        #expect(m.savingsRate == 0)
    }

    @Test func negativeNetIsSigned() {
        // docs/13 T6.b — spending exceeds income; savingsRate may be negative.
        let m = CashFlowMetrics(incomeMinor: 200_000, expenseMinor: 250_000)
        #expect(m.netMinor == -50_000)
        #expect(abs(m.savingsRate - (-0.25)) < 1e-9)
    }

    // MARK: Mixed-currency, converted to a display currency (docs/13 §6/§7)
    // Sample rates: eurUsd 1.10 (USD per EUR), btcEur 50_000, btcUsd 55_000.

    private var sampleConverter: CurrencyConverter {
        CurrencyConverter(rates: ExchangeRates(
            eurUsd: Decimal(string: "1.10")!, btcEur: 50_000, btcUsd: 55_000, fetchedAt: .init()))
    }

    @Test func mixedCurrencyIncomeConvertsPerItemBeforeSumming() {
        // €3000 + $1100→€ at 1/1.10 = €1000 ⇒ €4000 (= 400_000 cents).
        let income = [
            IncomeSource(name: "Salary", amountMinor: 300_000, currency: .eur, frequency: .monthly),
            IncomeSource(name: "US gig", amountMinor: 110_000, currency: .usd, frequency: .monthly),
        ]
        let eur = CashFlow.monthlyIncomeMinor(income, displayCurrency: .eur, converter: sampleConverter)
        #expect(eur == 400_000)
        // Same inputs displayed in USD: €3000→$3300 + $1100 = $4400.
        let usd = CashFlow.monthlyIncomeMinor(income, displayCurrency: .usd, converter: sampleConverter)
        #expect(usd == 440_000)
        // Stored amounts are untouched (display-only conversion).
        #expect(income[0].amountMinor == 300_000 && income[0].currency == .eur)
        #expect(income[1].amountMinor == 110_000 && income[1].currency == .usd)
    }

    @Test func sameCurrencyOverloadMatchesConvertedWhenAllEUR() {
        let income = [eurMonthly("Salary", 320_000), eurMonthly("Freelance", 60_000)]
        #expect(CashFlow.monthlyIncomeMinor(income)
                == CashFlow.monthlyIncomeMinor(income, displayCurrency: .eur, converter: sampleConverter))
    }

    @Test func mixedCurrencyMetricsConvertEachIncomeAndExpense() {
        let cal = Calendar(identifier: .gregorian)
        let ref = DateComponents(calendar: cal, year: 2026, month: 6, day: 15).date!
        // Income: €3000 + $1100→€1000 = €4000.
        let income = [
            IncomeSource(name: "Salary", amountMinor: 300_000, currency: .eur, frequency: .monthly),
            IncomeSource(name: "US gig", amountMinor: 110_000, currency: .usd, frequency: .monthly),
        ]
        // Fixed: €1100 + $220→€200 = €1300 monthly.
        let fixed = [
            FixedExpense(name: "Rent", amountMinor: 110_000, currency: .eur, frequency: .monthly),
            FixedExpense(name: "US sub bill", amountMinor: 22_000, currency: .usd, frequency: .monthly),
        ]
        // Variable: $110→€100 in-month.
        let variable = [
            VariableExpense(name: "Travel", amountMinor: 11_000, currency: .usd,
                            date: DateComponents(calendar: cal, year: 2026, month: 6, day: 5).date!),
        ]
        // Subscriptions already in display currency (e.g. €50).
        let m = CashFlow.metrics(
            income: income, fixed: fixed, variable: variable, subscriptionsMonthlyMinor: 5_000,
            displayCurrency: .eur, converter: sampleConverter, reference: ref, calendar: cal)
        #expect(m.incomeMinor == 400_000)        // €4000
        // expenses = €1300 fixed + €100 variable + €50 subs = €1450.
        #expect(m.expenseMinor == 145_000)
        #expect(m.netMinor == 255_000)
    }

    @Test func mixedCurrencySubscriptionsTotalConvertsPerItem() {
        let subs = [
            Subscription(name: "Netflix", amountMinor: 1_299, currency: .eur,
                         billingPeriod: .monthly, startDate: .init()),
            // $11/mo → €10 at 1/1.10.
            Subscription(name: "US SaaS", amountMinor: 1_100, currency: .usd,
                         billingPeriod: .monthly, startDate: .init()),
        ]
        let total = CashFlow.subscriptionsMonthlyMinor(subs, displayCurrency: .eur, converter: sampleConverter)
        // €12.99 + €10.00 = €22.99 = 2299 cents.
        #expect(total == 2_299)
    }

    @Test func mixedCurrencyMoneyFlowBucketsConvert() {
        let cal = Calendar(identifier: .gregorian)
        let ref = DateComponents(calendar: cal, year: 2026, month: 6, day: 15).date!
        let income = [
            IncomeSource(name: "Salary", amountMinor: 300_000, currency: .eur, frequency: .monthly),
            IncomeSource(name: "US gig", amountMinor: 110_000, currency: .usd, frequency: .monthly),
        ]
        let fixed = [FixedExpense(name: "Rent", amountMinor: 110_000, currency: .eur, frequency: .monthly)]
        let variable = [
            VariableExpense(name: "Travel", amountMinor: 11_000, currency: .usd,
                            date: DateComponents(calendar: cal, year: 2026, month: 6, day: 5).date!),
        ]
        let flow = MoneyFlow.make(
            income: income, fixed: fixed, variable: variable, subscriptionsMonthlyMinor: 5_000,
            displayCurrency: .eur, converter: sampleConverter, reference: ref, calendar: cal)
        #expect(flow.incomeMinor == 400_000)     // €4000
        #expect(flow.fixedMinor == 110_000)      // €1100
        #expect(flow.variableMinor == 10_000)    // $110 → €100
        #expect(flow.subscriptionsMinor == 5_000)
        // savings = 400000 - (110000 + 10000 + 5000) = 275000.
        #expect(flow.savingsMinor == 275_000)
    }

    @Test func mixedCurrencyCategoryDistributionConverts() {
        let rows: [(category: String, amount: Money)] = [
            ("Housing", Money(minorUnits: 110_000, currency: .eur)),    // €1100
            ("Travel", Money(minorUnits: 11_000, currency: .usd)),      // $110 → €100
            ("Housing", Money(minorUnits: 22_000, currency: .usd)),     // $220 → €200
        ]
        let slices = Analytics.categoryDistribution(rows, displayCurrency: .eur, converter: sampleConverter)
        // Housing €1100 + €200 = €1300 (top), Travel €100. Grand €1400.
        #expect(slices.first?.category == "Housing")
        #expect(slices.first?.totalMinor == 130_000)
        #expect(slices.first?.count == 2)
        #expect(slices.last?.category == "Travel")
        #expect(slices.last?.totalMinor == 10_000)
    }
}
