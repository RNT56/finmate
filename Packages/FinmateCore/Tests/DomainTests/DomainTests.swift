import Testing
import Foundation
@testable import Domain

// docs/13 §1 — Money
@Suite struct MoneyTests {
    @Test func parsesCents() throws {
        #expect(try Money.parse("12.34", currency: .eur).minorUnits == 1234)
        #expect(try Money.parse("100", currency: .eur).minorUnits == 10000)
        #expect(try Money.parse("1.1", currency: .usd).minorUnits == 110)
    }
    @Test func parsesSatoshis() throws {
        #expect(try Money.parse("0.00000001", currency: .btc).minorUnits == 1)
        #expect(try Money.parse("1", currency: .btc).minorUnits == satsPerBTC)
    }
    @Test func rejectsNegative() {
        #expect(throws: MoneyError.self) { try Money.parse("-5", currency: .eur) }
    }
    @Test func rejectsOverPrecision() {
        #expect(throws: MoneyError.self) { try Money.parse("12.999", currency: .eur) }
    }
    @Test func rejectsNonNumber() {
        #expect(throws: MoneyError.self) { try Money.parse("abc", currency: .eur) }
    }
    @Test func addsAndGuardsOverflow() throws {
        let sum = try Money(minorUnits: 100, currency: .eur).adding(Money(minorUnits: 50, currency: .eur))
        #expect(sum.minorUnits == 150)
        #expect(throws: MoneyError.self) {
            try Money(minorUnits: .max, currency: .eur).adding(Money(minorUnits: 1, currency: .eur))
        }
        #expect(throws: MoneyError.self) {
            try Money(minorUnits: 100, currency: .eur).adding(Money(minorUnits: 100, currency: .usd))
        }
    }
}

// docs/13 §2 — Currency conversion (display-only)
@Suite struct ConversionTests {
    let conv = CurrencyConverter(rates: ExchangeRates(
        eurUsd: Decimal(string: "1.10")!, btcEur: 50000, btcUsd: 55000,
        fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)))

    @Test func eurToBTCInSats() throws {
        // €500 at €50,000/BTC = 0.01 BTC = 1,000,000 sats
        let out = try conv.convert(Money(minorUnits: 50_000, currency: .eur), to: .btc)
        #expect(out.currency == .btc)
        #expect(out.minorUnits == 1_000_000)
    }
    @Test func eurUsdRoundTrip() throws {
        let usd = try conv.convert(Money(minorUnits: 10_000, currency: .eur), to: .usd) // €100 -> $110
        #expect(usd.minorUnits == 11_000)
        let eur = try conv.convert(usd, to: .eur)                                       // $110 -> €100
        #expect(eur.minorUnits == 10_000)
    }
    @Test func staleness() {
        let now = Date(timeIntervalSince1970: 1_700_000_000 + 2 * 86_400)
        #expect(conv.rates.isStale(now: now) == true)
    }
}

// docs/13 §3 — billing-period normalization
@Suite struct NormalizationTests {
    @Test func monthlyEquivalents() {
        #expect(BillingPeriodMath.monthlyMinorUnits(amountMinor: 10_000, period: .weekly) == 43_333) // ×52/12
        #expect(BillingPeriodMath.monthlyMinorUnits(amountMinor: 12_000, period: .yearly) == 1_000)
        #expect(BillingPeriodMath.monthlyMinorUnits(amountMinor: 3_000, period: .quarterly) == 1_000)
        #expect(BillingPeriodMath.monthlyMinorUnits(amountMinor: 999, period: .monthly) == 999)
    }
    @Test func annualEquivalents() {
        #expect(BillingPeriodMath.annualMinorUnits(amountMinor: 1_000, period: .monthly) == 12_000)
        #expect(BillingPeriodMath.annualMinorUnits(amountMinor: 3_000, period: .quarterly) == 12_000)
    }
}

// docs/13 §5–§6 — analytics
@Suite struct AnalyticsTests {
    @Test func savingsRate() {
        let m = CashFlowMetrics(incomeMinor: 224_000, expenseMinor: 100_000)
        #expect(m.netMinor == 124_000)
        #expect(abs(m.savingsRate - 0.5536) < 0.001)
        #expect(CashFlowMetrics(incomeMinor: 0, expenseMinor: 500).savingsRate == 0)
    }
    @Test func trendRatios() {
        let p = MonthlyTrendPoint(incomeMinor: 300_000, expenseMinor: 150_000, fixedMinor: 100_000,
                                  variableMinor: 50_000, subscriptionsMinor: 0, investmentsMinor: 60_000)
        #expect(p.savingsMinor == 150_000)
        #expect(abs(p.savingsRatio - 0.5) < 0.0001)
        #expect(abs(p.investmentRatio - 0.2) < 0.0001)
    }
    @Test func categoryDistribution() {
        let slices = Analytics.categoryDistribution([
            (category: "Streaming", amountMinor: 1299),
            (category: "Streaming", amountMinor: 1099),
            (category: "Music", amountMinor: 1099),
        ])
        #expect(slices.first?.category == "Streaming")
        #expect(slices.first?.totalMinor == 2398)
        #expect(slices.first?.count == 2)
        #expect(abs((slices.first?.share ?? 0) - (2398.0 / 3497.0)) < 0.0001)
    }
    @Test func lifetimeCost() {
        let total = LifetimeCost.totalMinor(segments: [
            PriceSegment(monthlyMinor: 1_000, months: 12),
            PriceSegment(monthlyMinor: 1_200, months: 6),
        ])
        #expect(total == 19_200)
    }
    @Test func moneyFlowClampsSavings() {
        let over = MoneyFlow(incomeMinor: 100_000, fixedMinor: 80_000, variableMinor: 30_000, subscriptionsMinor: 10_000)
        #expect(over.totalExpensesMinor == 120_000)
        #expect(over.savingsMinor == 0) // clamped, no negative ribbon
    }
}

// docs/13 §10 — prediction & inference
@Suite struct PredictorTests {
    @Test func exactAndSubstring() {
        #expect(SubscriptionPredictor.predict(name: "github")?.category == "Coding")
        #expect(SubscriptionPredictor.predict(name: "github")?.vendorURL == "github.com")
        #expect(SubscriptionPredictor.predict(name: "ChatGPT")?.category == "AI Chat")
        #expect(SubscriptionPredictor.inferCategory(name: "My Netflix Plan") == "Streaming")
    }
    @Test func tooShortNeverPredicts() {
        #expect(SubscriptionPredictor.predict(name: "x") == nil)
    }
    @Test func unknownFallsBackToOther() {
        let p = SubscriptionPredictor.predict(name: "Acme Random Service")
        #expect(p?.category == "Other")
        #expect(p?.vendorURL == nil)
    }
}
