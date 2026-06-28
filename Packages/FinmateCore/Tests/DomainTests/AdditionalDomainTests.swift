import Testing
import Foundation
@testable import Domain

// Additional coverage for M1 depth — docs/13 §1–§3, §5, §10.

// docs/13 §2 — USD↔EUR conversion rounding (HALF-UP to minor units, display-only)
@Suite struct ConversionRoundingTests {
    // eurUsd = 1.2345 USD per EUR; picked so scaling lands on a rounding boundary.
    let conv = CurrencyConverter(rates: ExchangeRates(
        eurUsd: Decimal(string: "1.2345")!, btcEur: 50_000, btcUsd: 55_000,
        fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)))

    @Test func usdToEurRoundsHalfUp() throws {
        // $1.00 -> €(1 / 1.2345) = €0.810044... -> 81 cents
        let eur = try conv.convert(Money(minorUnits: 100, currency: .usd), to: .eur)
        #expect(eur.currency == .eur)
        #expect(eur.minorUnits == 81)
    }

    @Test func eurToUsdRoundsHalfUp() throws {
        // €10.00 -> $12.345 -> 1234.5 cents -> HALF-UP -> 1235 cents
        let usd = try conv.convert(Money(minorUnits: 1_000, currency: .eur), to: .usd)
        #expect(usd.currency == .usd)
        #expect(usd.minorUnits == 1_235)
    }

    @Test func sameCurrencyIsIdentity() throws {
        let m = Money(minorUnits: 4_242, currency: .usd)
        #expect(try conv.convert(m, to: .usd) == m)
    }

    @Test func unavailableRateThrows() {
        let zeroEurUsd = CurrencyConverter(rates: ExchangeRates(
            eurUsd: 0, btcEur: 0, btcUsd: 0, fetchedAt: Date(timeIntervalSince1970: 0)))
        // eurUsd = 0 ⇒ usd→eur inverse is unavailable.
        #expect(throws: ConversionError.self) {
            try zeroEurUsd.convert(Money(minorUnits: 100, currency: .usd), to: .eur)
        }
    }
}

// docs/13 §3 — quarterly/annual normalization vectors
@Suite struct NormalizationVectorTests {
    @Test func quarterlyMonthlyRounding() {
        // €10.00 quarterly -> 1000/3 = 333.33 -> 333 cents/mo
        #expect(BillingPeriodMath.monthlyMinorUnits(amountMinor: 1_000, period: .quarterly) == 333)
        // €100.00 quarterly -> 10000/3 = 3333.33 -> 3333 cents/mo
        #expect(BillingPeriodMath.monthlyMinorUnits(amountMinor: 10_000, period: .quarterly) == 3_333)
    }

    @Test func annualUsesDirectMultiplierNotMonthlyTimesTwelve() {
        // Quarterly €100 -> annual is ×4 = 40000, NOT monthly(3333)×12 = 39996.
        #expect(BillingPeriodMath.annualMinorUnits(amountMinor: 10_000, period: .quarterly) == 40_000)
        #expect(BillingPeriodMath.monthlyMinorUnits(amountMinor: 10_000, period: .quarterly) * 12 == 39_996)
    }

    @Test func weeklyAnnualAndMonthly() {
        #expect(BillingPeriodMath.annualMinorUnits(amountMinor: 1_000, period: .weekly) == 52_000)
        // 1000 ×52/12 = 4333.33 -> 4333
        #expect(BillingPeriodMath.monthlyMinorUnits(amountMinor: 1_000, period: .weekly) == 4_333)
    }

    @Test func subscriptionMonthlyAmountUsesMath() {
        let sub = Subscription(name: "Yearly Plan", amountMinor: 12_000, currency: .eur,
                               billingPeriod: .yearly, startDate: Date(timeIntervalSince1970: 0))
        #expect(sub.monthlyAmount.minorUnits == 1_000)
        #expect(sub.monthlyAmount.currency == .eur)
    }
}

// docs/13 §1 — Money negative / overflow / subtraction edges
@Suite struct MoneyEdgeTests {
    @Test func subtractGuardsMismatchAndOverflow() throws {
        let r = try Money(minorUnits: 200, currency: .eur).subtracting(Money(minorUnits: 50, currency: .eur))
        #expect(r.minorUnits == 150)
        #expect(throws: MoneyError.self) {
            try Money(minorUnits: 100, currency: .eur).subtracting(Money(minorUnits: 1, currency: .usd))
        }
        #expect(throws: MoneyError.self) {
            try Money(minorUnits: .min, currency: .eur).subtracting(Money(minorUnits: 1, currency: .eur))
        }
    }

    @Test func parseRejectsNegativeZeroPrefixedAndOverflow() {
        #expect(throws: MoneyError.self) { try Money.parse("-0.01", currency: .eur) }
        // 1e17 EUR scaled by 100 overflows Int64 (max ~9.22e18).
        #expect(throws: MoneyError.self) { try Money.parse("100000000000000000", currency: .eur) }
    }

    @Test func decimalValueRoundTrips() throws {
        let m = try Money.parse("1234.56", currency: .eur)
        #expect(m.minorUnits == 123_456)
        #expect(m.decimalValue == Decimal(string: "1234.56")!)
    }

    @Test func zeroHelper() {
        #expect(Money.zero(.btc).minorUnits == 0)
        #expect(Money.zero(.btc).currency == .btc)
    }
}

// docs/13 §10 — predictor substring inference
@Suite struct PredictorSubstringTests {
    @Test func myChatGPTSubInfersAIChat() {
        // "my chatgpt sub" — substring of a seed key ⇒ AI Chat + openai vendor.
        let p = SubscriptionPredictor.predict(name: "my chatgpt sub")
        #expect(p?.category == "AI Chat")
        #expect(p?.vendorURL == "openai.com")
    }

    @Test func inferCategoryOnlySubstring() {
        #expect(SubscriptionPredictor.inferCategory(name: "Disney+ Annual") == "Streaming")
        #expect(SubscriptionPredictor.inferCategory(name: "Apple Music Family") == "Music")
        #expect(SubscriptionPredictor.inferCategory(name: "Cursor Pro") == "Coding")
        #expect(SubscriptionPredictor.inferCategory(name: "Totally Unknown") == "Other")
    }

    @Test func twoCharGuardBoundary() {
        // <2 chars never predicts; exactly 2 may.
        #expect(SubscriptionPredictor.predict(name: "n") == nil)
        #expect(SubscriptionPredictor.predict(name: "no")?.category == "Other")
    }
}

// docs/13 §5.1 — category distribution edge cases
@Suite struct CategoryDistributionEdgeTests {
    @Test func emptyReturnsEmpty() {
        #expect(Analytics.categoryDistribution([]).isEmpty)
    }

    @Test func sharesSumToOneAndAveragesComputed() {
        let slices = Analytics.categoryDistribution([
            (category: "AI Chat", amountMinor: 2_000),
            (category: "AI Chat", amountMinor: 2_000),
            (category: "Streaming", amountMinor: 1_299),
        ])
        let totalShare = slices.reduce(0.0) { $0 + $1.share }
        #expect(abs(totalShare - 1.0) < 0.0001)
        let ai = slices.first { $0.category == "AI Chat" }
        #expect(ai?.totalMinor == 4_000)
        #expect(ai?.averagePerItemMinor == 2_000)
        #expect(ai?.count == 2)
    }
}
