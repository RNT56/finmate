import Foundation
import Shared

// MARK: - Assets / investments (docs/05 §3.7–3.8, M5)
// Average-cost basis per ADR-0015:
//   purchasePriceMinor = TOTAL cost basis (what was paid, incl. fees, summed)
//   currentPriceMinor  = latest PER-UNIT price
//   valueMinor         = current TOTAL value (quantity × per-unit price)
//   unrealized gain    = valueMinor − purchasePriceMinor
// Money is Int64 minor units; Decimal is used only for conversion/share math.

public enum AssetType: String, Codable, Sendable, CaseIterable, Hashable {
    case crypto, stock, etf, cash, other

    /// Human label for UI/legends.
    public var displayName: String {
        switch self {
        case .crypto: return "Crypto"
        case .stock:  return "Stock"
        case .etf:    return "ETF"
        case .cash:   return "Cash"
        case .other:  return "Other"
        }
    }
}

/// A holding in the portfolio — docs/05 `financial_assets`.
public struct FinancialAsset: Identifiable, Equatable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var type: AssetType
    public var currency: CurrencyCode
    /// Units held (shares, coins, …). Decimal — never Double — for precision.
    public var quantity: Decimal
    /// TOTAL cost basis in minor units (ADR-0015: average-cost, the sum of buys + fees).
    public var purchasePriceMinor: Int64
    /// Latest PER-UNIT price in minor units (from the market-data Edge Function, ADR-0010).
    public var currentPriceMinor: Int64
    /// Current TOTAL value in minor units (quantity × per-unit price, precomputed/cached).
    public var valueMinor: Int64
    public var notes: String?

    public init(id: UUID = UUID(), name: String, type: AssetType, currency: CurrencyCode,
                quantity: Decimal, purchasePriceMinor: Int64, currentPriceMinor: Int64,
                valueMinor: Int64, notes: String? = nil) {
        self.id = id; self.name = name; self.type = type; self.currency = currency
        self.quantity = quantity; self.purchasePriceMinor = purchasePriceMinor
        self.currentPriceMinor = currentPriceMinor; self.valueMinor = valueMinor; self.notes = notes
    }

    /// Current total value as `Money` in the asset's own currency.
    public var value: Money { Money(minorUnits: valueMinor, currency: currency) }
    /// Cost basis as `Money` in the asset's own currency.
    public var costBasis: Money { Money(minorUnits: purchasePriceMinor, currency: currency) }
    /// Latest per-unit price as `Money` in the asset's own currency.
    public var currentPrice: Money { Money(minorUnits: currentPriceMinor, currency: currency) }
}

public enum AssetTransactionKind: String, Codable, Sendable, CaseIterable, Hashable {
    case buy, sell, dividend, other

    public var displayName: String {
        switch self {
        case .buy:      return "Buy"
        case .sell:     return "Sell"
        case .dividend: return "Dividend"
        case .other:    return "Other"
        }
    }
}

/// A lot/transaction against an asset — docs/05 `asset_transactions`.
public struct AssetTransaction: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public var assetID: UUID
    public var kind: AssetTransactionKind
    public var quantity: Decimal
    /// PER-UNIT price in minor units.
    public var priceMinor: Int64
    public var feesMinor: Int64
    public var date: Date
    public var notes: String?

    public init(id: UUID = UUID(), assetID: UUID, kind: AssetTransactionKind, quantity: Decimal,
                priceMinor: Int64, feesMinor: Int64 = 0, date: Date, notes: String? = nil) {
        self.id = id; self.assetID = assetID; self.kind = kind; self.quantity = quantity
        self.priceMinor = priceMinor; self.feesMinor = feesMinor; self.date = date; self.notes = notes
    }
}

// MARK: - Repository protocol (docs/03 §3 — declared in Domain, implemented in DataLayer)

public protocol AssetRepository: Sendable {
    func all() async throws -> [FinancialAsset]
    func transactions(assetID: UUID) async throws -> [AssetTransaction]
    func upsert(_ asset: FinancialAsset) async throws
    func delete(id: UUID) async throws
    /// Append (or update) a transaction against an asset. The caller is responsible
    /// for recomputing + persisting the holding's average-cost fields (docs/13 §2).
    func recordTransaction(_ transaction: AssetTransaction) async throws
}

// MARK: - Asset valuation math (ADR-0015, docs/13 §2 conversion)

/// One slice of the portfolio distribution-by-type, with a converted total + share.
public struct AssetDistributionSlice: Equatable, Sendable {
    public let type: AssetType
    public let totalMinor: Int64          // in the display currency
    public let count: Int
    public let share: Double              // fraction of converted grand total (0...1)

    public init(type: AssetType, totalMinor: Int64, count: Int, share: Double) {
        self.type = type; self.totalMinor = totalMinor; self.count = count; self.share = share
    }
}

/// Pure portfolio/asset valuation, ADR-0015 average-cost basis. Cross-currency
/// totals convert each holding's `Money` into the display currency (display-only;
/// stored values are never mutated — docs/13 §2, docs/04 §6.2).
public enum AssetValuation {
    /// Unrealized gain/loss in the asset's own currency = value − cost basis (signed).
    public static func unrealizedGainMinor(_ asset: FinancialAsset) -> Int64 {
        asset.valueMinor - asset.purchasePriceMinor
    }

    /// Gain as a fraction of cost basis; 0 when cost basis is 0 (zero-guarded).
    public static func gainPct(_ asset: FinancialAsset) -> Double {
        asset.purchasePriceMinor == 0
            ? 0
            : Double(unrealizedGainMinor(asset)) / Double(asset.purchasePriceMinor)
    }

    /// Σ convert(asset.value → displayCurrency) over all assets. Unconvertible
    /// holdings are skipped rather than corrupting the total.
    public static func portfolioValueMinor(
        _ assets: [FinancialAsset], displayCurrency: CurrencyCode, converter: CurrencyConverter
    ) -> Int64 {
        sumConverted(assets, displayCurrency: displayCurrency, converter: converter) { $0.valueMinor }
    }

    /// Σ convert(asset.costBasis → displayCurrency) over all assets.
    public static func portfolioCostBasisMinor(
        _ assets: [FinancialAsset], displayCurrency: CurrencyCode, converter: CurrencyConverter
    ) -> Int64 {
        sumConverted(assets, displayCurrency: displayCurrency, converter: converter) { $0.purchasePriceMinor }
    }

    /// Portfolio unrealized gain in the display currency = value − cost basis.
    public static func portfolioGainMinor(
        _ assets: [FinancialAsset], displayCurrency: CurrencyCode, converter: CurrencyConverter
    ) -> Int64 {
        portfolioValueMinor(assets, displayCurrency: displayCurrency, converter: converter)
            - portfolioCostBasisMinor(assets, displayCurrency: displayCurrency, converter: converter)
    }

    /// Portfolio gain as a fraction of converted cost basis; 0-guarded.
    public static func portfolioGainPct(
        _ assets: [FinancialAsset], displayCurrency: CurrencyCode, converter: CurrencyConverter
    ) -> Double {
        let cost = portfolioCostBasisMinor(assets, displayCurrency: displayCurrency, converter: converter)
        let gain = portfolioGainMinor(assets, displayCurrency: displayCurrency, converter: converter)
        return cost == 0 ? 0 : Double(gain) / Double(cost)
    }

    /// Distribution of converted current value by `AssetType`, descending by total
    /// (ties broken by type rawValue). Reuses the category-distribution aggregator
    /// (docs/13 §5.1) over (type, convertedValue) rows.
    public static func assetDistribution(
        _ assets: [FinancialAsset], displayCurrency: CurrencyCode, converter: CurrencyConverter
    ) -> [AssetDistributionSlice] {
        let rows: [(category: String, amountMinor: Int64)] = assets.compactMap { asset in
            guard let converted = try? converter.convert(asset.value, to: displayCurrency) else { return nil }
            return (category: asset.type.rawValue, amountMinor: converted.minorUnits)
        }
        return Analytics.categoryDistribution(rows).compactMap { slice in
            guard let type = AssetType(rawValue: slice.category) else { return nil }
            return AssetDistributionSlice(type: type, totalMinor: slice.totalMinor,
                                          count: slice.count, share: slice.share)
        }
    }

    /// Recomputed average-cost holding fields derived from a transaction history.
    public struct RecomputedHolding: Equatable, Sendable {
        public let quantity: Decimal
        /// TOTAL average-cost basis of the remaining position, in minor units.
        public let costBasisMinor: Int64
        /// Current TOTAL value = remaining quantity × current per-unit price.
        public let valueMinor: Int64

        public init(quantity: Decimal, costBasisMinor: Int64, valueMinor: Int64) {
            self.quantity = quantity
            self.costBasisMinor = costBasisMinor
            self.valueMinor = valueMinor
        }
    }

    /// Recompute a holding's quantity, cost basis, and value from its transaction
    /// history under the ADR-0015 average-cost method (docs/13 §2). Buys add
    /// quantity and `quantity × price + fees` to the cost basis; sells remove
    /// quantity and proportionally reduce the cost basis at the running average
    /// cost; dividend/other leave quantity and basis unchanged. The returned value
    /// is the remaining quantity × the supplied current per-unit price. All money is
    /// `Int64` minor units; `Decimal` is used only for the quantity/average math.
    public static func recompute(
        transactions: [AssetTransaction], currentPriceMinor: Int64
    ) -> RecomputedHolding {
        var quantity = Decimal(0)
        var costBasis = Decimal(0)          // total cost basis in minor units
        for txn in transactions.sorted(by: { $0.date < $1.date }) {
            switch txn.kind {
            case .buy:
                quantity += txn.quantity
                costBasis += txn.quantity * Decimal(txn.priceMinor) + Decimal(txn.feesMinor)
            case .sell:
                let avg = quantity > 0 ? costBasis / quantity : 0
                let sold = min(txn.quantity, quantity)
                quantity -= sold
                costBasis -= avg * sold
                if quantity <= 0 { quantity = 0; costBasis = 0 }
            case .dividend, .other:
                break
            }
        }
        let value = quantity * Decimal(currentPriceMinor)
        return RecomputedHolding(
            quantity: quantity,
            costBasisMinor: roundHalfUpToInt64(costBasis),
            valueMinor: roundHalfUpToInt64(value))
    }

    // MARK: Private

    private static func sumConverted(
        _ assets: [FinancialAsset], displayCurrency: CurrencyCode, converter: CurrencyConverter,
        _ minor: (FinancialAsset) -> Int64
    ) -> Int64 {
        assets.reduce(Int64(0)) { acc, asset in
            let money = Money(minorUnits: minor(asset), currency: asset.currency)
            guard let converted = try? converter.convert(money, to: displayCurrency) else { return acc }
            return acc + converted.minorUnits
        }
    }
}

// MARK: - BTC / crypto calculator (docs/02 §10) — fiat ↔ sats via CurrencyConverter

/// A fiat→crypto conversion result, carrying both the source fiat and the BTC/sats.
public struct CryptoConversion: Equatable, Sendable {
    public let fiat: Money
    public let btc: Money          // currency == .btc, minorUnits == sats
    public init(fiat: Money, btc: Money) { self.fiat = fiat; self.btc = btc }

    /// Whole satoshis (== btc.minorUnits, since BTC's minor unit is the satoshi).
    public var sats: Int64 { btc.minorUnits }
    /// BTC as a major-unit Decimal (display/format only).
    public var btcDecimal: Decimal { btc.decimalValue }
}

public enum CryptoCalculator {
    /// Convert a fiat `Money` to BTC/sats using the converter's rates.
    /// e.g. €500 @ €50,000/BTC → 0.01 BTC → 1,000,000 sats.
    public static func fiatToBTC(_ fiat: Money, converter: CurrencyConverter) throws -> CryptoConversion {
        let btc = try converter.convert(fiat, to: .btc)
        return CryptoConversion(fiat: fiat, btc: btc)
    }
}
