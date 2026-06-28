import Testing
import Foundation
@testable import Domain

// docs/13 §2 + ADR-0015 — Asset valuation (per-asset & portfolio gains, distribution,
// cross-currency totals, and the BTC calculator). The SHARED vectors mirror the M5
// sample data so iOS and web agree on the numbers.
@Suite struct AssetValuationTests {

    // MARK: Sample portfolio (identical on both clients) — all EUR
    // Bitcoin: qty 0.5, cost 2_000_000, value 2_500_000 → +500_000
    // World ETF: qty 10, cost 150_000, value 180_000 → +30_000
    // ACME stock: cost 50_000, value 45_000 → −5_000
    private let bitcoin = FinancialAsset(
        name: "Bitcoin", type: .crypto, currency: .eur, quantity: Decimal(string: "0.5")!,
        purchasePriceMinor: 2_000_000, currentPriceMinor: 5_000_000, valueMinor: 2_500_000)
    private let etf = FinancialAsset(
        name: "World ETF", type: .etf, currency: .eur, quantity: 10,
        purchasePriceMinor: 150_000, currentPriceMinor: 18_000, valueMinor: 180_000)
    private let stock = FinancialAsset(
        name: "ACME", type: .stock, currency: .eur, quantity: 5,
        purchasePriceMinor: 50_000, currentPriceMinor: 9_000, valueMinor: 45_000)

    private var assets: [FinancialAsset] { [bitcoin, etf, stock] }

    // Sample display rates (shared with the calculator vector).
    private var converter: CurrencyConverter {
        CurrencyConverter(rates: ExchangeRates(
            eurUsd: Decimal(string: "1.10")!,
            btcEur: 50_000,
            btcUsd: 55_000,
            fetchedAt: Date(timeIntervalSince1970: 0)))
    }

    // MARK: Per-asset unrealized gain (ADR-0015)

    @Test func perAssetGains() {
        #expect(AssetValuation.unrealizedGainMinor(bitcoin) == 500_000)
        #expect(AssetValuation.unrealizedGainMinor(etf) == 30_000)
        #expect(AssetValuation.unrealizedGainMinor(stock) == -5_000)
    }

    @Test func perAssetGainPct() {
        // 500000 / 2000000 = 0.25
        #expect(abs(AssetValuation.gainPct(bitcoin) - 0.25) < 1e-9)
        // 30000 / 150000 = 0.20
        #expect(abs(AssetValuation.gainPct(etf) - 0.20) < 1e-9)
        // -5000 / 50000 = -0.10
        #expect(abs(AssetValuation.gainPct(stock) - (-0.10)) < 1e-9)
    }

    @Test func zeroCostBasisGainPctGuarded() {
        let free = FinancialAsset(name: "Airdrop", type: .crypto, currency: .eur, quantity: 1,
                                  purchasePriceMinor: 0, currentPriceMinor: 1_000, valueMinor: 1_000)
        #expect(AssetValuation.unrealizedGainMinor(free) == 1_000)
        #expect(AssetValuation.gainPct(free) == 0)
    }

    // MARK: Portfolio totals (same-currency EUR) — the headline M5 vector

    @Test func portfolioTotalsEUR() {
        #expect(AssetValuation.portfolioValueMinor(assets, displayCurrency: .eur, converter: converter) == 2_725_000)
        #expect(AssetValuation.portfolioCostBasisMinor(assets, displayCurrency: .eur, converter: converter) == 2_200_000)
        #expect(AssetValuation.portfolioGainMinor(assets, displayCurrency: .eur, converter: converter) == 525_000)
        // gainPct = 525000 / 2200000
        #expect(abs(AssetValuation.portfolioGainPct(assets, displayCurrency: .eur, converter: converter)
                    - (525_000.0 / 2_200_000.0)) < 1e-9)
    }

    // MARK: Cross-currency portfolio total via the sample rates

    @Test func portfolioTotalConvertedToUSD() {
        // EUR portfolio value 2_725_000 cents (€27,250) × 1.10 = $29,975.00 = 2_997_500 USD cents.
        #expect(AssetValuation.portfolioValueMinor(assets, displayCurrency: .usd, converter: converter) == 2_997_500)
        // cost 2_200_000 cents (€22,000) × 1.10 = $24,200.00 = 2_420_000 USD cents.
        #expect(AssetValuation.portfolioCostBasisMinor(assets, displayCurrency: .usd, converter: converter) == 2_420_000)
        // gain = 2_997_500 − 2_420_000 = 577_500 USD cents.
        #expect(AssetValuation.portfolioGainMinor(assets, displayCurrency: .usd, converter: converter) == 577_500)
    }

    // MARK: Distribution by type (converted total + share)

    @Test func distributionByType() {
        let slices = AssetValuation.assetDistribution(assets, displayCurrency: .eur, converter: converter)
        #expect(slices.count == 3)
        // Descending by total: crypto 2_500_000 > etf 180_000 > stock 45_000.
        #expect(slices[0].type == .crypto)
        #expect(slices[0].totalMinor == 2_500_000)
        #expect(slices[1].type == .etf)
        #expect(slices[1].totalMinor == 180_000)
        #expect(slices[2].type == .stock)
        #expect(slices[2].totalMinor == 45_000)
        // Shares sum to ~1.
        let shareSum = slices.reduce(0.0) { $0 + $1.share }
        #expect(abs(shareSum - 1.0) < 1e-9)
        // crypto share = 2_500_000 / 2_725_000.
        #expect(abs(slices[0].share - (2_500_000.0 / 2_725_000.0)) < 1e-9)
    }

    // MARK: BTC calculator (docs/02 §10) — €500 → 1_000_000 sats

    @Test func btcCalculatorEUR() throws {
        let result = try CryptoCalculator.fiatToBTC(
            Money(minorUnits: 50_000, currency: .eur), converter: converter)  // €500.00
        #expect(result.btc.currency == .btc)
        #expect(result.sats == 1_000_000)          // 0.01 BTC
        #expect(result.btcDecimal == Decimal(string: "0.01")!)
    }

    @Test func btcCalculatorUSD() throws {
        // $5,500 @ $55,000/BTC = 0.1 BTC = 10_000_000 sats.
        let result = try CryptoCalculator.fiatToBTC(
            Money(minorUnits: 550_000, currency: .usd), converter: converter)
        #expect(result.sats == 10_000_000)
    }

    // MARK: Average-cost recompute from transactions (ADR-0015, docs/13 §2)

    @Test func recomputeAverageCostFromBuys() {
        let id = UUID()
        // Two buys: 0.3 @ 3_500_000 + fee 1_500, then 0.2 @ 4_700_000 + fee 1_000.
        // qty = 0.5; cost = 0.3*3_500_000 + 1_500 + 0.2*4_700_000 + 1_000
        //              = 1_050_000 + 1_500 + 940_000 + 1_000 = 1_992_500.
        // value @ current 5_000_000/unit = 0.5 * 5_000_000 = 2_500_000.
        let txns = [
            AssetTransaction(assetID: id, kind: .buy, quantity: Decimal(string: "0.3")!,
                             priceMinor: 3_500_000, feesMinor: 1_500, date: Date(timeIntervalSince1970: 100)),
            AssetTransaction(assetID: id, kind: .buy, quantity: Decimal(string: "0.2")!,
                             priceMinor: 4_700_000, feesMinor: 1_000, date: Date(timeIntervalSince1970: 200)),
        ]
        let h = AssetValuation.recompute(transactions: txns, currentPriceMinor: 5_000_000)
        #expect(h.quantity == Decimal(string: "0.5")!)
        #expect(h.costBasisMinor == 1_992_500)
        #expect(h.valueMinor == 2_500_000)
    }

    @Test func recomputeSellReducesBasisAtAverageCost() {
        let id = UUID()
        // Buy 10 @ 100 (cost 1_000), sell 4. Average cost = 100/unit.
        // Remaining qty 6, basis 600; value @ 150/unit = 900. Dividend leaves it unchanged.
        let txns = [
            AssetTransaction(assetID: id, kind: .buy, quantity: 10,
                             priceMinor: 100, feesMinor: 0, date: Date(timeIntervalSince1970: 100)),
            AssetTransaction(assetID: id, kind: .sell, quantity: 4,
                             priceMinor: 200, feesMinor: 0, date: Date(timeIntervalSince1970: 200)),
            AssetTransaction(assetID: id, kind: .dividend, quantity: 0,
                             priceMinor: 0, feesMinor: 0, date: Date(timeIntervalSince1970: 300)),
        ]
        let h = AssetValuation.recompute(transactions: txns, currentPriceMinor: 150)
        #expect(h.quantity == 6)
        #expect(h.costBasisMinor == 600)
        #expect(h.valueMinor == 900)
    }

    @Test func recomputeFullSellZeroesPosition() {
        let id = UUID()
        let txns = [
            AssetTransaction(assetID: id, kind: .buy, quantity: 5,
                             priceMinor: 1_000, feesMinor: 50, date: Date(timeIntervalSince1970: 100)),
            AssetTransaction(assetID: id, kind: .sell, quantity: 5,
                             priceMinor: 1_200, feesMinor: 0, date: Date(timeIntervalSince1970: 200)),
        ]
        let h = AssetValuation.recompute(transactions: txns, currentPriceMinor: 1_200)
        #expect(h.quantity == 0)
        #expect(h.costBasisMinor == 0)
        #expect(h.valueMinor == 0)
    }
}
