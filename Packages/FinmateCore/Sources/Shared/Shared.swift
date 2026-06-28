import Foundation

// MARK: - Rounding (docs/13 §1, §2 — HALF-UP to minor units)

/// Round a `Decimal` to the nearest integer, ties away from zero (HALF-UP for
/// non-negative money values), then narrow to `Int64`. `.plain` is Foundation's
/// round-half-away-from-zero mode.
public func roundHalfUpToInt64(_ value: Decimal) -> Int64 {
    var input = value
    var rounded = Decimal()
    NSDecimalRound(&rounded, &input, 0, .plain)
    return (rounded as NSDecimalNumber).int64Value
}

// MARK: - Locale-aware CSV number parsing (docs/13 §9 / §10 — CSV import)

public enum CSVParseError: Error, Equatable, Sendable {
    case empty
    case notANumber(String)
    case negative
    /// The value is ambiguous or carries more fractional digits than the currency
    /// allows (e.g. "1,234" for EUR) — we refuse to guess rather than silently corrupt.
    case ambiguousOrTooPrecise(String)
    case overflow
}

/// Parses a human-entered amount string into `Int64` minor units **without**
/// silently corrupting locale-formatted numbers (the Substimate-class bug).
///
/// Heuristic: of the two grouping/decimal candidates (`.` and `,`), the **right-most**
/// occurring one is treated as the decimal separator and the other as grouping
/// (which is stripped). A lone separator is treated as the decimal separator; if that
/// produces more fractional digits than the currency allows, we raise
/// `ambiguousOrTooPrecise` instead of guessing.
public enum CSVNumberParser {
    public static func parseAmountMinor(_ raw: String, currencyMinorDigits: Int) throws -> Int64 {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { throw CSVParseError.empty }
        if s.hasPrefix("-") { throw CSVParseError.negative }

        let lastDot = s.lastIndex(of: ".")
        let lastComma = s.lastIndex(of: ",")
        let decimalSep: Character?
        switch (lastDot, lastComma) {
        case let (d?, c?): decimalSep = d > c ? "." : ","
        case (_?, nil): decimalSep = "."
        case (nil, _?): decimalSep = ","
        case (nil, nil): decimalSep = nil
        }

        var canonical = ""
        for ch in s {
            if ch == "." || ch == "," {
                if ch == decimalSep { canonical.append(".") }   // keep as decimal point
                // else: grouping separator — drop it
            } else {
                canonical.append(ch)
            }
        }

        // fractional-digit guard
        if let dotIdx = canonical.firstIndex(of: ".") {
            let frac = canonical.distance(from: canonical.index(after: dotIdx), to: canonical.endIndex)
            if frac > currencyMinorDigits { throw CSVParseError.ambiguousOrTooPrecise(raw) }
        }

        let posix = Locale(identifier: "en_US_POSIX")
        let nsdn = NSDecimalNumber(string: canonical, locale: posix)
        if nsdn == NSDecimalNumber.notANumber { throw CSVParseError.notANumber(raw) }
        let dec = nsdn.decimalValue
        if dec.isSignMinus { throw CSVParseError.negative }

        var factor: Int64 = 1
        for _ in 0..<currencyMinorDigits { factor *= 10 }
        let scaled = dec * Decimal(factor)
        if scaled > Decimal(Int64.max) { throw CSVParseError.overflow }
        return roundHalfUpToInt64(scaled)
    }
}

// MARK: - Structured logging façade (docs/09 §9 — OSLog, no PII)

/// A tiny, dependency-free logging façade. The iOS app backs this with `OSLog`;
/// the pure-logic packages stay UI/OS-agnostic and never log PII.
public protocol FinmateLogging: Sendable {
    func debug(_ message: @autoclosure () -> String)
    func error(_ message: @autoclosure () -> String)
}

public struct NoopLogger: FinmateLogging {
    public init() {}
    public func debug(_ message: @autoclosure () -> String) {}
    public func error(_ message: @autoclosure () -> String) {}
}
