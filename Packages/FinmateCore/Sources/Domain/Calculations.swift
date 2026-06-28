import Foundation
import Shared

// MARK: - Billing periods & cost normalization (docs/13 §3)

public enum BillingPeriod: String, Codable, Sendable, CaseIterable {
    case weekly, monthly, quarterly, yearly
}

public enum BillingPeriodMath {
    /// Canonical **monthly** minor units for a charge billed on `period`.
    /// weekly ×52/12, monthly ×1, quarterly /3, yearly /12 — Decimal, HALF-UP.
    public static func monthlyMinorUnits(amountMinor: Int64, period: BillingPeriod) -> Int64 {
        let a = Decimal(amountMinor)
        let monthly: Decimal
        switch period {
        case .weekly:    monthly = a * 52 / 12
        case .monthly:   monthly = a
        case .quarterly: monthly = a / 3
        case .yearly:    monthly = a / 12
        }
        return roundHalfUpToInt64(monthly)
    }

    /// Canonical **annual** minor units. Quarterly uses ×4 directly (not monthly×12)
    /// to avoid compounding the rounding error (docs/13 §3 assumption).
    public static func annualMinorUnits(amountMinor: Int64, period: BillingPeriod) -> Int64 {
        let a = Decimal(amountMinor)
        let annual: Decimal
        switch period {
        case .weekly:    annual = a * 52
        case .monthly:   annual = a * 12
        case .quarterly: annual = a * 4
        case .yearly:    annual = a
        }
        return roundHalfUpToInt64(annual)
    }
}

// MARK: - Income frequency normalization (docs/13 §6)

public enum IncomeFrequency: String, Codable, Sendable, CaseIterable {
    case weekly, monthly, yearly, oneTime = "one_time"

    /// Monthly-equivalent factor as a `Decimal`. `oneTime` contributes 0 to a
    /// recurring monthly roll-up (counted only in the month it occurs elsewhere).
    public var monthlyFactor: Decimal {
        switch self {
        case .weekly:  return Decimal(52) / Decimal(12)
        case .monthly: return 1
        case .yearly:  return Decimal(1) / Decimal(12)
        case .oneTime: return 0
        }
    }
}

// MARK: - Cash-flow metrics (docs/13 §6)

public struct CashFlowMetrics: Equatable, Sendable {
    public let incomeMinor: Int64
    public let expenseMinor: Int64

    public init(incomeMinor: Int64, expenseMinor: Int64) {
        self.incomeMinor = incomeMinor
        self.expenseMinor = expenseMinor
    }

    public var netMinor: Int64 { incomeMinor - expenseMinor }

    /// Savings rate = net / income, in [−∞, 1]. Zero income ⇒ 0 (zero-guarded).
    public var savingsRate: Double {
        incomeMinor == 0 ? 0 : Double(netMinor) / Double(incomeMinor)
    }
}

// MARK: - Cash-flow roll-ups (docs/13 §6.1–6.3, M2)

public enum CashFlow {
    /// Recurring monthly income in minor units (docs/13 §6.1). Same-currency inputs
    /// assumed (display conversion is a separate read-time step); `oneTime` excluded.
    public static func monthlyIncomeMinor(_ sources: [IncomeSource]) -> Int64 {
        sources.reduce(Int64(0)) { $0 + $1.monthlyMinor }
    }

    /// Recurring monthly income converted to `displayCurrency` (docs/13 §6.1/§7).
    /// Each source's monthly-equivalent `Money` is converted **before** summing
    /// (HALF-UP, display-only — stored amounts are never mutated); `oneTime`
    /// excluded. Unconvertible sources are skipped rather than corrupting the total.
    public static func monthlyIncomeMinor(
        _ sources: [IncomeSource], displayCurrency: CurrencyCode, converter: CurrencyConverter
    ) -> Int64 {
        sources.reduce(Int64(0)) { acc, src in
            let money = Money(minorUnits: src.monthlyMinor, currency: src.currency)
            guard let converted = try? converter.convert(money, to: displayCurrency) else { return acc }
            return acc + converted.minorUnits
        }
    }

    /// Monthly expenses = fixed (normalized) + this-month variable + subscriptions
    /// monthly-equivalent (docs/13 §6.2). Variable expenses are pre-summed by the
    /// caller for the current month; same-currency inputs assumed.
    public static func monthlyExpensesMinor(
        fixed: [FixedExpense],
        variableThisMonthMinor: Int64,
        subscriptionsMonthlyMinor: Int64
    ) -> Int64 {
        let fixedMonthly = fixed.reduce(Int64(0)) { $0 + $1.monthlyMinor }
        return fixedMonthly + variableThisMonthMinor + subscriptionsMonthlyMinor
    }

    /// Fixed expenses normalized to monthly, each converted to `displayCurrency`
    /// before summing (docs/13 §6.2/§7, HALF-UP; stored amounts untouched).
    public static func fixedMonthlyMinor(
        _ fixed: [FixedExpense], displayCurrency: CurrencyCode, converter: CurrencyConverter
    ) -> Int64 {
        fixed.reduce(Int64(0)) { acc, exp in
            let money = Money(minorUnits: exp.monthlyMinor, currency: exp.currency)
            guard let converted = try? converter.convert(money, to: displayCurrency) else { return acc }
            return acc + converted.minorUnits
        }
    }

    /// Sum of variable expenses whose `date` falls in the calendar month of `reference`.
    public static func variableThisMonthMinor(
        _ variable: [VariableExpense],
        reference: Date = .now,
        calendar: Calendar = .current
    ) -> Int64 {
        variable
            .filter { calendar.isDate($0.date, equalTo: reference, toGranularity: .month) }
            .reduce(Int64(0)) { $0 + $1.amountMinor }
    }

    /// This-month variable expenses converted to `displayCurrency` per item before
    /// summing (docs/13 §6.2/§7; stored amounts untouched).
    public static func variableThisMonthMinor(
        _ variable: [VariableExpense],
        displayCurrency: CurrencyCode,
        converter: CurrencyConverter,
        reference: Date = .now,
        calendar: Calendar = .current
    ) -> Int64 {
        variable
            .filter { calendar.isDate($0.date, equalTo: reference, toGranularity: .month) }
            .reduce(Int64(0)) { acc, exp in
                let money = Money(minorUnits: exp.amountMinor, currency: exp.currency)
                guard let converted = try? converter.convert(money, to: displayCurrency) else { return acc }
                return acc + converted.minorUnits
            }
    }

    /// Build the signed `CashFlowMetrics` (net + savings rate) from the roll-ups.
    public static func metrics(
        income: [IncomeSource],
        fixed: [FixedExpense],
        variable: [VariableExpense],
        subscriptionsMonthlyMinor: Int64,
        reference: Date = .now,
        calendar: Calendar = .current
    ) -> CashFlowMetrics {
        let incomeMinor = monthlyIncomeMinor(income)
        let variableMonth = variableThisMonthMinor(variable, reference: reference, calendar: calendar)
        let expenseMinor = monthlyExpensesMinor(
            fixed: fixed,
            variableThisMonthMinor: variableMonth,
            subscriptionsMonthlyMinor: subscriptionsMonthlyMinor
        )
        return CashFlowMetrics(incomeMinor: incomeMinor, expenseMinor: expenseMinor)
    }

    /// Build `CashFlowMetrics` with **every** income & expense converted to
    /// `displayCurrency` at read time before summing (docs/13 §6/§7). This both
    /// expresses the KPIs in the display currency and *correctly* sums mixed-currency
    /// inputs (the same-currency overload latently mis-sums those). `subscriptionsMonthlyMinor`
    /// is expected already in the display currency (compute it via
    /// `subscriptionsMonthlyMinor(_:displayCurrency:converter:)`). Stored amounts are
    /// never mutated.
    public static func metrics(
        income: [IncomeSource],
        fixed: [FixedExpense],
        variable: [VariableExpense],
        subscriptionsMonthlyMinor: Int64,
        displayCurrency: CurrencyCode,
        converter: CurrencyConverter,
        reference: Date = .now,
        calendar: Calendar = .current
    ) -> CashFlowMetrics {
        let incomeMinor = monthlyIncomeMinor(income, displayCurrency: displayCurrency, converter: converter)
        let fixedMonthly = fixedMonthlyMinor(fixed, displayCurrency: displayCurrency, converter: converter)
        let variableMonth = variableThisMonthMinor(
            variable, displayCurrency: displayCurrency, converter: converter,
            reference: reference, calendar: calendar)
        let expenseMinor = fixedMonthly + variableMonth + subscriptionsMonthlyMinor
        return CashFlowMetrics(incomeMinor: incomeMinor, expenseMinor: expenseMinor)
    }

    /// Σ convert(subscription.monthlyAmount → displayCurrency) over all subscriptions
    /// (docs/13 §3/§7). Each subscription's monthly-equivalent `Money` is converted
    /// per item before summing (HALF-UP; stored amounts untouched). Replaces the old
    /// "filter to one currency" shortcut so mixed-currency portfolios sum correctly.
    public static func subscriptionsMonthlyMinor(
        _ subscriptions: [Subscription], displayCurrency: CurrencyCode, converter: CurrencyConverter
    ) -> Int64 {
        subscriptions.reduce(Int64(0)) { acc, sub in
            guard let converted = try? converter.convert(sub.monthlyAmount, to: displayCurrency) else { return acc }
            return acc + converted.minorUnits
        }
    }
}

/// Per-month trend point (docs/13 §5.2 — the full multi-series, not income-vs-expense).
public struct MonthlyTrendPoint: Equatable, Sendable {
    public let incomeMinor: Int64
    public let expenseMinor: Int64
    public let fixedMinor: Int64
    public let variableMinor: Int64
    public let subscriptionsMinor: Int64
    public let investmentsMinor: Int64

    public init(incomeMinor: Int64, expenseMinor: Int64, fixedMinor: Int64,
                variableMinor: Int64, subscriptionsMinor: Int64, investmentsMinor: Int64) {
        self.incomeMinor = incomeMinor
        self.expenseMinor = expenseMinor
        self.fixedMinor = fixedMinor
        self.variableMinor = variableMinor
        self.subscriptionsMinor = subscriptionsMinor
        self.investmentsMinor = investmentsMinor
    }

    public var savingsMinor: Int64 { incomeMinor - expenseMinor }
    /// % of income saved; 0 when income is 0.
    public var savingsRatio: Double { incomeMinor == 0 ? 0 : Double(savingsMinor) / Double(incomeMinor) }
    /// % of income invested; 0 when income is 0.
    public var investmentRatio: Double { incomeMinor == 0 ? 0 : Double(investmentsMinor) / Double(incomeMinor) }
}

// MARK: - Category distribution (docs/13 §5.1)

public struct CategorySlice: Equatable, Sendable {
    public let category: String
    public let totalMinor: Int64
    public let count: Int
    public let share: Double          // fraction of grand total (0...1)
    public let averagePerItemMinor: Int64
}

public enum Analytics {
    /// Aggregate `(category, amountMinor)` rows into descending-by-total slices
    /// with share and per-item average. Same-currency inputs assumed.
    public static func categoryDistribution(_ rows: [(category: String, amountMinor: Int64)]) -> [CategorySlice] {
        guard !rows.isEmpty else { return [] }
        var totals: [String: (sum: Int64, count: Int)] = [:]
        for r in rows {
            let cur = totals[r.category] ?? (0, 0)
            totals[r.category] = (cur.sum + r.amountMinor, cur.count + 1)
        }
        let grand = totals.values.reduce(Int64(0)) { $0 + $1.sum }
        return totals
            .map { (cat, v) in
                CategorySlice(
                    category: cat,
                    totalMinor: v.sum,
                    count: v.count,
                    share: grand == 0 ? 0 : Double(v.sum) / Double(grand),
                    averagePerItemMinor: v.count == 0 ? 0 : Int64((Double(v.sum) / Double(v.count)).rounded())
                )
            }
            .sorted { $0.totalMinor != $1.totalMinor ? $0.totalMinor > $1.totalMinor : $0.category < $1.category }
    }

    /// Aggregate `(category, Money)` rows into descending-by-total slices, converting
    /// each row's `Money` to `displayCurrency` before aggregating (docs/13 §5.1/§7,
    /// HALF-UP; stored amounts untouched). Unconvertible rows are skipped.
    public static func categoryDistribution(
        _ rows: [(category: String, amount: Money)],
        displayCurrency: CurrencyCode,
        converter: CurrencyConverter
    ) -> [CategorySlice] {
        let converted: [(category: String, amountMinor: Int64)] = rows.compactMap { row in
            guard let m = try? converter.convert(row.amount, to: displayCurrency) else { return nil }
            return (category: row.category, amountMinor: m.minorUnits)
        }
        return categoryDistribution(converted)
    }
}

// MARK: - Lifetime cost (docs/13 §4 — price-history walk)

/// One contiguous price segment of a subscription's history.
public struct PriceSegment: Equatable, Sendable {
    public let monthlyMinor: Int64
    public let months: Int
    public init(monthlyMinor: Int64, months: Int) {
        self.monthlyMinor = monthlyMinor
        self.months = months
    }
}

public enum LifetimeCost {
    /// Σ (monthly cost × months active) across price-history segments. Whole-period
    /// charging (no proration) is the v1 semantics (docs/13 §4 assumption).
    public static func totalMinor(segments: [PriceSegment]) -> Int64 {
        segments.reduce(Int64(0)) { $0 + $1.monthlyMinor * Int64(max(0, $1.months)) }
    }
}

// MARK: - Money-flow buckets (docs/13 §6.5, ADR-0016 bucketed Sankey)

public struct MoneyFlow: Equatable, Sendable {
    public let fixedMinor: Int64
    public let variableMinor: Int64
    public let subscriptionsMinor: Int64
    public let incomeMinor: Int64

    public init(incomeMinor: Int64, fixedMinor: Int64, variableMinor: Int64, subscriptionsMinor: Int64) {
        self.incomeMinor = incomeMinor
        self.fixedMinor = fixedMinor
        self.variableMinor = variableMinor
        self.subscriptionsMinor = subscriptionsMinor
    }

    public var totalExpensesMinor: Int64 { fixedMinor + variableMinor + subscriptionsMinor }
    /// Savings is clamped at 0 — an over-budget month shows no negative ribbon.
    public var savingsMinor: Int64 { max(0, incomeMinor - totalExpensesMinor) }

    /// Build the bucketed money-flow with every income/fixed/variable bucket converted
    /// to `displayCurrency` at read time before summing (docs/13 §6.5/§7; stored
    /// amounts untouched). `subscriptionsMonthlyMinor` is expected already in the
    /// display currency (use `CashFlow.subscriptionsMonthlyMinor(_:displayCurrency:converter:)`).
    public static func make(
        income: [IncomeSource],
        fixed: [FixedExpense],
        variable: [VariableExpense],
        subscriptionsMonthlyMinor: Int64,
        displayCurrency: CurrencyCode,
        converter: CurrencyConverter,
        reference: Date = .now,
        calendar: Calendar = .current
    ) -> MoneyFlow {
        MoneyFlow(
            incomeMinor: CashFlow.monthlyIncomeMinor(income, displayCurrency: displayCurrency, converter: converter),
            fixedMinor: CashFlow.fixedMonthlyMinor(fixed, displayCurrency: displayCurrency, converter: converter),
            variableMinor: CashFlow.variableThisMonthMinor(
                variable, displayCurrency: displayCurrency, converter: converter,
                reference: reference, calendar: calendar),
            subscriptionsMinor: subscriptionsMonthlyMinor
        )
    }
}
