import Foundation
import Shared

// MARK: - CSV import (docs/13 §9, docs/02 §8) — validate + preview before write.
//
// A pure, UI-agnostic importer: an RFC-4180-lite tokenizer, case-insensitive header
// mapping with aliases, per-row validation collecting *all* errors, and a preview
// (valid `Subscription`s + row errors). Nothing is written until the caller confirms.
// Locale-aware amount parsing reuses `Shared.CSVNumberParser`.

/// A single row-level validation failure. `row` is 1-based and counts the header
/// row as row 1 (so the first data row is row 2).
public struct ImportRowError: Equatable, Sendable {
    public let row: Int
    public let field: String?
    public let message: String

    public init(row: Int, field: String? = nil, message: String) {
        self.row = row
        self.field = field
        self.message = message
    }
}

/// The result of parsing a CSV: the valid rows ready to import, all collected
/// errors, and the total number of data rows seen.
public struct ImportPreview: Equatable, Sendable {
    public let valid: [Subscription]
    public let errors: [ImportRowError]
    public let totalRows: Int

    public init(valid: [Subscription], errors: [ImportRowError], totalRows: Int) {
        self.valid = valid
        self.errors = errors
        self.totalRows = totalRows
    }
}

public enum SubscriptionCSVImporter {

    // MARK: Header aliases (docs/13 §9.2). Canonical key ← {aliases}, case-insensitive.

    private static let aliases: [String: Set<String>] = [
        "name":           ["name", "service", "title", "subscription"],
        "amount":         ["amount", "monthly_cost", "cost", "price", "monthly_amount"],
        "currency":       ["currency", "ccy"],
        "billing_period": ["billing_period", "period", "cycle", "billing"],
        "payment_method": ["payment_method", "method", "payment"],
        "category":       ["category"],
        "usage_state":    ["usage_state", "usage", "status"],
        "start_date":     ["start_date", "start", "since", "date"],
        "vendor_url":     ["url", "vendor_url", "website"],
    ]

    // MARK: Public entry point

    /// Parse a CSV string into an `ImportPreview`. The header row is required and is
    /// counted as row 1; data rows start at row 2.
    public static func parseSubscriptionsCSV(_ text: String) -> ImportPreview {
        let rows = parseRecords(text)
        guard let header = rows.first else {
            return ImportPreview(valid: [], errors: [], totalRows: 0)
        }

        // Build canonical-column → field-index map from the header.
        var columnIndex: [String: Int] = [:]
        for (i, raw) in header.enumerated() {
            let token = normalizeHeaderToken(raw)
            for (canonical, set) in aliases where set.contains(token) {
                if columnIndex[canonical] == nil { columnIndex[canonical] = i }
            }
        }

        let dataRows = Array(rows.dropFirst())
        var valid: [Subscription] = []
        var errors: [ImportRowError] = []

        for (offset, fields) in dataRows.enumerated() {
            let rowNumber = offset + 2 // header is row 1
            // Skip wholly-blank trailing rows (common when text ends with a newline).
            if fields.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }

            switch buildRow(fields: fields, columnIndex: columnIndex, rowNumber: rowNumber) {
            case .success(let sub):
                valid.append(sub)
            case .failure(let rowErrors):
                errors.append(contentsOf: rowErrors)
            }
        }

        let totalRows = dataRows.filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }.count
        return ImportPreview(valid: valid, errors: errors, totalRows: totalRows)
    }

    // MARK: Per-row validation (docs/13 §9.3) — collect ALL errors per row.

    private enum RowResult {
        case success(Subscription)
        case failure([ImportRowError])
    }

    private static func buildRow(fields: [String], columnIndex: [String: Int], rowNumber: Int) -> RowResult {
        func value(_ key: String) -> String {
            guard let idx = columnIndex[key], idx < fields.count else { return "" }
            return fields[idx].trimmingCharacters(in: .whitespaces)
        }

        var errors: [ImportRowError] = []

        // name — required, 1...120 chars
        let name = value("name")
        if name.isEmpty {
            errors.append(ImportRowError(row: rowNumber, field: "name", message: "Missing name"))
        } else if name.count > 120 {
            errors.append(ImportRowError(row: rowNumber, field: "name", message: "Name too long (max 120 characters)"))
        }

        // currency — default EUR if blank, else must be one of the supported codes
        let currencyRaw = value("currency")
        var currency: CurrencyCode = .eur
        if !currencyRaw.isEmpty {
            if let c = CurrencyCode(rawValue: currencyRaw.uppercased()) {
                currency = c
            } else {
                errors.append(ImportRowError(row: rowNumber, field: "currency", message: "Unsupported currency"))
            }
        }

        // amount — required, locale-aware, non-negative, within currency precision
        let amountRaw = value("amount")
        var amountMinor: Int64 = 0
        if amountRaw.isEmpty {
            errors.append(ImportRowError(row: rowNumber, field: "amount", message: "Invalid amount"))
        } else {
            do {
                amountMinor = try CSVNumberParser.parseAmountMinor(amountRaw, currencyMinorDigits: currency.minorUnitDigits)
            } catch {
                errors.append(ImportRowError(row: rowNumber, field: "amount", message: "Invalid amount"))
            }
        }

        // billing_period — default monthly
        var billingPeriod: BillingPeriod = .monthly
        let periodRaw = value("billing_period")
        if !periodRaw.isEmpty {
            if let p = BillingPeriod(rawValue: periodRaw.lowercased()) {
                billingPeriod = p
            } else {
                errors.append(ImportRowError(row: rowNumber, field: "billing_period", message: "Invalid billing period"))
            }
        }

        // payment_method — default other
        var paymentMethod: PaymentMethod = .other
        let methodRaw = value("payment_method")
        if !methodRaw.isEmpty {
            if let m = PaymentMethod(rawValue: methodRaw.lowercased()) {
                paymentMethod = m
            } else {
                errors.append(ImportRowError(row: rowNumber, field: "payment_method", message: "Unsupported payment method"))
            }
        }

        // usage_state — default active
        var usageState: UsageState = .active
        let usageRaw = value("usage_state")
        if !usageRaw.isEmpty {
            if let u = UsageState(rawValue: usageRaw.lowercased()) {
                usageState = u
            } else {
                errors.append(ImportRowError(row: rowNumber, field: "usage_state", message: "Unsupported usage state"))
            }
        }

        // start_date — default today, parsed yyyy-MM-dd
        var startDate = Date()
        let dateRaw = value("start_date")
        if !dateRaw.isEmpty {
            if let d = parseISODate(dateRaw) {
                startDate = d
            } else {
                errors.append(ImportRowError(row: rowNumber, field: "start_date", message: "Invalid start date (expected yyyy-MM-dd)"))
            }
        }

        // vendor_url — optional, no validation beyond emptiness
        let vendorRaw = value("vendor_url")
        let vendorURL = vendorRaw.isEmpty ? nil : vendorRaw

        guard errors.isEmpty else { return .failure(errors) }

        return .success(Subscription(
            name: name,
            vendorURL: vendorURL,
            amountMinor: amountMinor,
            currency: currency,
            billingPeriod: billingPeriod,
            paymentMethod: paymentMethod,
            usageState: usageState,
            startDate: startDate,
            sortOrder: Int.max
        ))
    }

    // MARK: Header token normalization

    /// Lowercase, trim, and snake-case a header token (`Monthly Cost` → `monthly_cost`).
    private static func normalizeHeaderToken(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var out = ""
        for ch in trimmed {
            if ch == " " || ch == "-" { out.append("_") }
            else { out.append(ch) }
        }
        return out
    }

    private static func parseISODate(_ raw: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: raw)
    }

    // MARK: RFC-4180-lite tokenizer (docs/13 §4) — quoted fields, "" escapes, CRLF/LF.

    /// Parse the whole document into records of fields. Honors quoted fields that
    /// contain commas and newlines, and `""` as a literal quote. Splits records on
    /// LF / CRLF that occur outside of quotes.
    static func parseRecords(_ text: String) -> [[String]] {
        var records: [[String]] = []
        var fields: [String] = []
        var cur = ""
        var inQuotes = false

        // Iterate over Unicode scalars (not Characters): Swift folds "\r\n" into a
        // single grapheme cluster, which would otherwise hide the newline from the
        // switch below.
        let scalars = Array(text.unicodeScalars)
        var i = 0
        let n = scalars.count

        func endField() { fields.append(cur); cur = "" }
        func endRecord() { endField(); records.append(fields); fields = [] }

        let quote: Unicode.Scalar = "\""
        let comma: Unicode.Scalar = ","
        let cr: Unicode.Scalar = "\r"
        let lf: Unicode.Scalar = "\n"

        while i < n {
            let c = scalars[i]
            if inQuotes {
                if c == quote {
                    if i + 1 < n && scalars[i + 1] == quote {
                        cur.append("\""); i += 2; continue   // escaped quote
                    }
                    inQuotes = false; i += 1; continue
                }
                cur.unicodeScalars.append(c); i += 1
            } else {
                switch c {
                case quote:
                    inQuotes = true; i += 1
                case comma:
                    endField(); i += 1
                case cr:
                    // CRLF or lone CR → record end
                    if i + 1 < n && scalars[i + 1] == lf { i += 1 }
                    endRecord(); i += 1
                case lf:
                    endRecord(); i += 1
                default:
                    cur.unicodeScalars.append(c); i += 1
                }
            }
        }
        // Final field/record (no trailing newline).
        if !cur.isEmpty || !fields.isEmpty {
            endRecord()
        }
        return records
    }
}
