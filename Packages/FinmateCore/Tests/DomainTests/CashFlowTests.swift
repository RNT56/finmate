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
}
