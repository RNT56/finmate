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

/// The result of parsing a CSV into entities of type `Entity`: the valid rows ready
/// to import, all collected errors, and the total number of data rows seen.
public struct EntityImportPreview<Entity: Equatable & Sendable>: Equatable, Sendable {
    public let valid: [Entity]
    public let errors: [ImportRowError]
    public let totalRows: Int

    public init(valid: [Entity], errors: [ImportRowError], totalRows: Int) {
        self.valid = valid
        self.errors = errors
        self.totalRows = totalRows
    }
}

/// The subscription-specific preview (kept as a name-stable alias for the existing
/// `SubscriptionCSVImporter` API).
public typealias ImportPreview = EntityImportPreview<Subscription>

public enum SubscriptionCSVImporter {

    // MARK: Canonical fields (docs/13 §9.2)

    /// The canonical, mappable target fields a CSV column can feed. `rawValue` is the
    /// canonical snake_case key used throughout the importer (and in error `field`s).
    public enum CSVField: String, CaseIterable, Hashable, Sendable {
        case name
        case amount
        case currency
        case billingPeriod = "billing_period"
        case paymentMethod = "payment_method"
        case category
        case usageState = "usage_state"
        case startDate = "start_date"
        case vendorURL = "vendor_url"

        /// A short, human-facing label for the column-mapping UI.
        public var displayName: String {
            switch self {
            case .name:          return "Name"
            case .amount:        return "Amount"
            case .currency:      return "Currency"
            case .billingPeriod: return "Billing period"
            case .paymentMethod: return "Payment method"
            case .category:      return "Category"
            case .usageState:    return "Usage state"
            case .startDate:     return "Start date"
            case .vendorURL:     return "URL"
            }
        }

        /// Required fields must resolve to a column (directly or by default semantics).
        /// Only `name` + `amount` are required; everything else has a sane default.
        public var isRequired: Bool { self == .name || self == .amount }
    }

    /// The result of inspecting a CSV header: the raw header tokens (as written) and
    /// the auto-detected field → column-index mapping (alias match; missing fields
    /// are simply absent). The UI seeds its per-field Pickers from `autoMapping` and
    /// lets the user override before calling ``parse(_:mapping:)``.
    public struct HeaderAnalysis: Equatable, Sendable {
        /// Header tokens exactly as they appear in the file (trimmed of surrounding
        /// whitespace), in column order.
        public let headers: [String]
        /// Auto-detected canonical-field → column-index mapping (alias-based).
        public let autoMapping: [CSVField: Int]

        public init(headers: [String], autoMapping: [CSVField: Int]) {
            self.headers = headers
            self.autoMapping = autoMapping
        }
    }

    // MARK: Header aliases (docs/13 §9.2). Canonical key ← {aliases}, case-insensitive.

    private static let aliases: [CSVField: Set<String>] = [
        .name:          ["name", "service", "title", "subscription"],
        .amount:        ["amount", "monthly_cost", "cost", "price", "monthly_amount"],
        .currency:      ["currency", "ccy"],
        .billingPeriod: ["billing_period", "period", "cycle", "billing"],
        .paymentMethod: ["payment_method", "method", "payment"],
        .category:      ["category"],
        .usageState:    ["usage_state", "usage", "status"],
        .startDate:     ["start_date", "start", "since", "date"],
        .vendorURL:     ["url", "vendor_url", "website"],
    ]

    // MARK: Header analysis

    /// Inspect a CSV's header row: return the raw tokens plus the auto-detected
    /// field → column-index mapping (alias match). Empty if the text has no rows.
    /// This is the read the column-mapping UI uses to seed its Pickers.
    public static func analyzeHeader(_ text: String) -> HeaderAnalysis {
        let rows = CSVImportKit.parseRecords(text)
        guard let header = rows.first else {
            return HeaderAnalysis(headers: [], autoMapping: [:])
        }
        let tokens = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return HeaderAnalysis(headers: tokens, autoMapping: autoDetectMapping(header))
    }

    /// Build the auto-detected field → column-index mapping for a header row. First
    /// alias match wins per field; first column wins on duplicate aliases.
    private static func autoDetectMapping(_ header: [String]) -> [CSVField: Int] {
        CSVImportKit.autoDetectMapping(header, aliases: aliases)
    }

    // MARK: Public entry points

    /// Parse a CSV string into an `ImportPreview`. The header row is required and is
    /// counted as row 1; data rows start at row 2. Columns are mapped automatically
    /// from the header aliases.
    public static func parseSubscriptionsCSV(_ text: String) -> ImportPreview {
        let rows = CSVImportKit.parseRecords(text)
        guard let header = rows.first else {
            return ImportPreview(valid: [], errors: [], totalRows: 0)
        }
        return parse(rows, mapping: autoDetectMapping(header))
    }

    /// Parse a CSV string with an **explicit** field → column-index mapping (the UI's
    /// user-overridable mapping). The header row is still consumed as row 1 — the
    /// mapping refers to its column positions — and data rows start at row 2. Fields
    /// absent from `mapping` fall back to their defaults exactly as with auto-detect.
    public static func parse(_ text: String, mapping: [CSVField: Int]) -> ImportPreview {
        parse(CSVImportKit.parseRecords(text), mapping: mapping)
    }

    /// Shared core: parse already-tokenized records (header at index 0) with an
    /// explicit field → column-index mapping.
    private static func parse(_ rows: [[String]], mapping: [CSVField: Int]) -> ImportPreview {
        CSVImportKit.parseRows(rows, mapping: mapping) { fields, columnIndex, rowNumber in
            buildRow(fields: fields, columnIndex: columnIndex, rowNumber: rowNumber)
        }
    }

    // MARK: Per-row validation (docs/13 §9.3) — collect ALL errors per row.

    private static func buildRow(fields: [String], columnIndex: [CSVField: Int], rowNumber: Int) -> CSVImportKit.RowResult<Subscription> {
        func value(_ key: CSVField) -> String {
            CSVImportKit.value(fields: fields, columnIndex: columnIndex, key: key)
        }

        var errors: [ImportRowError] = []

        // name — required, 1...120 chars
        let name = value(.name)
        if name.isEmpty {
            errors.append(ImportRowError(row: rowNumber, field: "name", message: "Missing name"))
        } else if name.count > 120 {
            errors.append(ImportRowError(row: rowNumber, field: "name", message: "Name too long (max 120 characters)"))
        }

        // currency — default EUR if blank, else must be one of the supported codes
        let currency = CSVImportKit.parseCurrency(value(.currency), row: rowNumber, errors: &errors)

        // amount — required, locale-aware, non-negative, within currency precision
        let amountMinor = CSVImportKit.parseAmount(value(.amount), currency: currency, row: rowNumber, errors: &errors)

        // billing_period — default monthly
        var billingPeriod: BillingPeriod = .monthly
        let periodRaw = value(.billingPeriod)
        if !periodRaw.isEmpty {
            if let p = BillingPeriod(rawValue: periodRaw.lowercased()) {
                billingPeriod = p
            } else {
                errors.append(ImportRowError(row: rowNumber, field: "billing_period", message: "Invalid billing period"))
            }
        }

        // payment_method — default other
        var paymentMethod: PaymentMethod = .other
        let methodRaw = value(.paymentMethod)
        if !methodRaw.isEmpty {
            if let m = PaymentMethod(rawValue: methodRaw.lowercased()) {
                paymentMethod = m
            } else {
                errors.append(ImportRowError(row: rowNumber, field: "payment_method", message: "Unsupported payment method"))
            }
        }

        // usage_state — default active
        var usageState: UsageState = .active
        let usageRaw = value(.usageState)
        if !usageRaw.isEmpty {
            if let u = UsageState(rawValue: usageRaw.lowercased()) {
                usageState = u
            } else {
                errors.append(ImportRowError(row: rowNumber, field: "usage_state", message: "Unsupported usage state"))
            }
        }

        // start_date — default today, parsed yyyy-MM-dd
        var startDate = Date()
        let dateRaw = value(.startDate)
        if !dateRaw.isEmpty {
            if let d = CSVImportKit.parseISODate(dateRaw) {
                startDate = d
            } else {
                errors.append(ImportRowError(row: rowNumber, field: "start_date", message: "Invalid start date (expected yyyy-MM-dd)"))
            }
        }

        // vendor_url — optional, no validation beyond emptiness
        let vendorRaw = value(.vendorURL)
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
}
