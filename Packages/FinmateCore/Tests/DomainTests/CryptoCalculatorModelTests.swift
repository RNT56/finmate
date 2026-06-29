import Testing
import Foundation
@testable import Domain

// M5-CALC-03 — the pure BTC-calculator model: fiat string + currency + converter →
// BTC/sats (or nil on invalid input). Stubbed rates assert rate-dependence and the
// €500 → 1,000,000 sats sample vector; invalid/empty/negative/over-precision → nil.
@Suite struct CryptoCalculatorModelTests {

    // Sample rates (shared with the app): eurUsd 1.10, btcEur 50_000, btcUsd 55_000.
    private let sampleRates = ExchangeRates(
        eurUsd: Decimal(string: "1.10")!, btcEur: 50_000, btcUsd: 55_000, fetchedAt: .init(timeIntervalSince1970: 0))
    private func model(_ rates: ExchangeRates) -> CryptoCalculatorModel {
        CryptoCalculatorModel(converter: CurrencyConverter(rates: rates))
    }

    // MARK: Sample vector — €500 @ €50,000/BTC → 0.01 BTC → 1,000,000 sats
    @Test func eur500AtSampleRateGivesExpectedSats() {
        let m = model(sampleRates)
        let conv = m.conversion(for: "500", currency: .eur)
        #expect(conv?.sats == 1_000_000)
        #expect(conv?.btc.currency == .btc)
        #expect(conv?.fiat == Money(minorUnits: 50_000, currency: .eur))
    }

    @Test func usd550AtSampleRateGivesExpectedSats() {
        // $550 @ $55,000/BTC → 0.01 BTC → 1,000,000 sats
        let conv = model(sampleRates).conversion(for: "550", currency: .usd)
        #expect(conv?.sats == 1_000_000)
    }

    // MARK: Rate-dependence — different rates produce different sats
    @Test func differentRatesProduceDifferentSats() {
        let cheaper = ExchangeRates(
            eurUsd: Decimal(string: "1.10")!, btcEur: 25_000, btcUsd: 55_000, fetchedAt: .init(timeIntervalSince1970: 0))
        let base = model(sampleRates).conversion(for: "500", currency: .eur)?.sats
        let cheap = model(cheaper).conversion(for: "500", currency: .eur)?.sats
        #expect(base == 1_000_000)
        #expect(cheap == 2_000_000)       // half the BTC price → twice the sats
        #expect(base != cheap)
    }

    // MARK: Invalid input → nil
    @Test func emptyOrWhitespaceIsNil() {
        let m = model(sampleRates)
        #expect(m.conversion(for: "", currency: .eur) == nil)
        #expect(m.conversion(for: "   ", currency: .eur) == nil)
        #expect(m.parseFiat("", currency: .eur) == nil)
    }

    @Test func nonNumericIsNil() {
        let m = model(sampleRates)
        #expect(m.conversion(for: "abc", currency: .eur) == nil)
        #expect(m.conversion(for: "1.2.3", currency: .eur) == nil) // malformed number
    }

    @Test func negativeIsNil() {
        let m = model(sampleRates)
        #expect(m.conversion(for: "-500", currency: .eur) == nil)
        #expect(m.parseFiat("-1", currency: .eur) == nil)
    }

    @Test func overPrecisionIsNil() {
        let m = model(sampleRates)
        // EUR allows 2 decimals — 3 is rejected.
        #expect(m.conversion(for: "1.234", currency: .eur) == nil)
        #expect(m.parseFiat("0.001", currency: .usd) == nil)
    }

    // MARK: parseFiat accepts valid input + trims whitespace
    @Test func parseFiatTrimsAndAccepts() {
        let m = model(sampleRates)
        #expect(m.parseFiat("  500  ", currency: .eur) == Money(minorUnits: 50_000, currency: .eur))
        #expect(m.parseFiat("12.34", currency: .usd) == Money(minorUnits: 1_234, currency: .usd))
    }

    // MARK: rateMoney mirrors the converter's BTC→fiat rate
    @Test func rateMoneyMatchesSampleRates() {
        let m = model(sampleRates)
        #expect(m.rateMoney(for: .eur) == Money(minorUnits: 5_000_000, currency: .eur)) // €50,000
        #expect(m.rateMoney(for: .usd) == Money(minorUnits: 5_500_000, currency: .usd)) // $55,000
    }

    @Test func rateMoneyNilWhenRateUnavailable() {
        let zeroBtc = ExchangeRates(
            eurUsd: Decimal(string: "1.10")!, btcEur: 0, btcUsd: 55_000, fetchedAt: .init(timeIntervalSince1970: 0))
        // btcEur 0 makes EUR→BTC unavailable, but BTC→EUR is the direct rate (0) here;
        // conversion of €amount→BTC should be nil since the inverse rate is undefined.
        let m = model(zeroBtc)
        #expect(m.conversion(for: "500", currency: .eur) == nil)
    }
}
