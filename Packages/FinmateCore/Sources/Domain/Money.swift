import Foundation
import Shared

// MARK: - CurrencyCode (docs/05 §2.1, docs/13 §2)

/// ISO-ish currency code. BTC's "minor unit" is the satoshi (10^8 per BTC);
/// EUR/USD use cents (10^2). `satsPerBTC == 100_000_000`.
public enum CurrencyCode: String, Codable, Sendable, CaseIterable, Hashable {
    case eur = "EUR"
    case usd = "USD"
    case btc = "BTC"

    /// Number of fractional digits in one major unit.
    public var minorUnitDigits: Int {
        switch self {
        case .eur, .usd: return 2
        case .btc: return 8
        }
    }

    /// Minor units in one major unit: 100 (cents) or 100_000_000 (satoshis).
    public var minorUnitsPerMajor: Int64 {
        var v: Int64 = 1
        for _ in 0..<minorUnitDigits { v *= 10 }
        return v
    }

    public var symbol: String {
        switch self {
        case .eur: return "€"
        case .usd: return "$"
        case .btc: return "₿"
        }
    }
}

public let satsPerBTC: Int64 = 100_000_000

// MARK: - Money (docs/05 §2.2, docs/13 §1) — Int64 minor units, never Double

public enum MoneyError: Error, Equatable, Sendable {
    case currencyMismatch(CurrencyCode, CurrencyCode)
    case negativeAmount
    case tooManyFractionalDigits(allowed: Int)
    case invalidNumber(String)
    case overflow
}

/// A value type pairing `Int64` minor units with a currency. All money in Finmate
/// flows through this type — `Decimal` is used only for computation/formatting.
public struct Money: Equatable, Hashable, Sendable, Codable {
    public let minorUnits: Int64
    public let currency: CurrencyCode

    public init(minorUnits: Int64, currency: CurrencyCode) {
        self.minorUnits = minorUnits
        self.currency = currency
    }

    public static func zero(_ currency: CurrencyCode) -> Money {
        Money(minorUnits: 0, currency: currency)
    }

    /// Major-unit value as `Decimal` (for conversion/formatting only).
    public var decimalValue: Decimal {
        Decimal(minorUnits) / Decimal(currency.minorUnitsPerMajor)
    }

    public func adding(_ other: Money) throws -> Money {
        guard currency == other.currency else {
            throw MoneyError.currencyMismatch(currency, other.currency)
        }
        let (r, overflow) = minorUnits.addingReportingOverflow(other.minorUnits)
        if overflow { throw MoneyError.overflow }
        return Money(minorUnits: r, currency: currency)
    }

    public func subtracting(_ other: Money) throws -> Money {
        guard currency == other.currency else {
            throw MoneyError.currencyMismatch(currency, other.currency)
        }
        let (r, overflow) = minorUnits.subtractingReportingOverflow(other.minorUnits)
        if overflow { throw MoneyError.overflow }
        return Money(minorUnits: r, currency: currency)
    }

    /// Parse a canonical decimal string (POSIX `.` separator) into minor units.
    /// HALF-UP rounding; rejects negatives, over-precision, non-numbers, and overflow.
    public static func parse(_ string: String, currency: CurrencyCode) throws -> Money {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MoneyError.invalidNumber(string) }
        if trimmed.hasPrefix("-") { throw MoneyError.negativeAmount }

        let posix = Locale(identifier: "en_US_POSIX")
        let nsdn = NSDecimalNumber(string: trimmed, locale: posix)
        if nsdn == NSDecimalNumber.notANumber { throw MoneyError.invalidNumber(string) }
        let dec = nsdn.decimalValue
        if dec.isSignMinus { throw MoneyError.negativeAmount }

        if let dotIdx = trimmed.firstIndex(of: ".") {
            let frac = trimmed.distance(from: trimmed.index(after: dotIdx), to: trimmed.endIndex)
            if frac > currency.minorUnitDigits {
                throw MoneyError.tooManyFractionalDigits(allowed: currency.minorUnitDigits)
            }
        }

        let scaled = dec * Decimal(currency.minorUnitsPerMajor)
        if scaled > Decimal(Int64.max) { throw MoneyError.overflow }
        return Money(minorUnits: roundHalfUpToInt64(scaled), currency: currency)
    }

    /// Locale-aware display string. Conversion to a display currency is a separate,
    /// non-mutating step (see `CurrencyConverter`); this never changes stored values.
    public func formatted(locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.rawValue
        formatter.locale = locale
        formatter.minimumFractionDigits = currency.minorUnitDigits
        formatter.maximumFractionDigits = currency.minorUnitDigits
        return formatter.string(from: decimalValue as NSDecimalNumber)
            ?? "\(decimalValue) \(currency.rawValue)"
    }
}

// MARK: - Exchange rates & conversion (docs/04 §6.2, docs/13 §2)

/// Canonical rate snapshot returned by the `market-data` Edge Function.
/// `eurUsd` = USD per 1 EUR; `btcEur` = EUR per 1 BTC; `btcUsd` = USD per 1 BTC.
public struct ExchangeRates: Equatable, Sendable, Codable {
    public let eurUsd: Decimal
    public let btcEur: Decimal
    public let btcUsd: Decimal
    public let fetchedAt: Date

    public init(eurUsd: Decimal, btcEur: Decimal, btcUsd: Decimal, fetchedAt: Date) {
        self.eurUsd = eurUsd
        self.btcEur = btcEur
        self.btcUsd = btcUsd
        self.fetchedAt = fetchedAt
    }

    /// Rates are shown with a staleness indicator past 24h but still used.
    public func isStale(now: Date, maxAge: TimeInterval = 86_400) -> Bool {
        now.timeIntervalSince(fetchedAt) > maxAge
    }
}

public enum ConversionError: Error, Equatable, Sendable {
    case rateUnavailable(from: CurrencyCode, to: CurrencyCode)
}

/// Display-only currency conversion. **Never** mutates a stored `Money` — it
/// returns a new `Money` in the target currency for display (fixes Substimate's
/// pre-store-conversion bug). All three EUR/USD/BTC pairs are carried directly.
public struct CurrencyConverter: Sendable {
    public let rates: ExchangeRates
    public init(rates: ExchangeRates) { self.rates = rates }

    /// Target major units per 1 source major unit, or nil if unavailable.
    public func rate(from: CurrencyCode, to: CurrencyCode) -> Decimal? {
        if from == to { return 1 }
        func inv(_ d: Decimal) -> Decimal? { d == 0 ? nil : 1 / d }
        switch (from, to) {
        case (.eur, .usd): return rates.eurUsd
        case (.usd, .eur): return inv(rates.eurUsd)
        case (.btc, .eur): return rates.btcEur
        case (.eur, .btc): return inv(rates.btcEur)
        case (.btc, .usd): return rates.btcUsd
        case (.usd, .btc): return inv(rates.btcUsd)
        default: return nil
        }
    }

    public func convert(_ money: Money, to target: CurrencyCode) throws -> Money {
        if money.currency == target { return money }
        guard let r = rate(from: money.currency, to: target) else {
            throw ConversionError.rateUnavailable(from: money.currency, to: target)
        }
        let targetMajor = money.decimalValue * r
        let scaled = targetMajor * Decimal(target.minorUnitsPerMajor)
        return Money(minorUnits: roundHalfUpToInt64(scaled), currency: target)
    }
}
