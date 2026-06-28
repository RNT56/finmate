import Foundation

// MARK: - Coding support for Supabase row DTOs (docs/05 — snake_case ↔ camelCase)
//
// Postgres columns are snake_case; the Domain types are camelCase. Each DTO below
// declares explicit `CodingKeys` mapping to its table's columns. Dates are stored
// as Postgres `date` (yyyy-MM-dd) or `timestamptz` (ISO-8601); we decode/encode
// `date` columns as day strings to avoid timezone drift on calendar anchors.

enum SupabaseCoding {
    /// `yyyy-MM-dd` formatter in UTC for Postgres `date` columns.
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayString(_ date: Date) -> String { dayFormatter.string(from: date) }

    static func date(fromDay string: String?) -> Date? {
        guard let string else { return nil }
        return dayFormatter.date(from: string)
    }

    /// ISO-8601 parser tolerant of fractional seconds (for `timestamptz` columns).
    static func date(fromTimestamp string: String?) -> Date? {
        guard let string else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: string) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}

/// A `Decimal` carried over JSON as a string, preserving precision for `numeric`
/// columns (asset quantity). Decoding accepts a string or a JSON number.
struct DecimalString: Codable, Sendable {
    let value: Decimal

    init(_ value: Decimal) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self), let d = Decimal(string: s) {
            value = d
        } else if let dbl = try? container.decode(Double.self) {
            // Round-trip through string to avoid binary-float artifacts.
            value = Decimal(string: String(dbl)) ?? Decimal(dbl)
        } else {
            value = 0
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(NSDecimalNumber(decimal: value).stringValue)
    }
}

enum DataLayerError: Error, Sendable {
    case decodingFailed(String)
}
