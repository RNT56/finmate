import Foundation
import Shared

// MARK: - CSVImportKit (docs/13 §9, docs/02 §6) — shared CSV-import machinery.
//
// The reusable engine behind every entity importer (Subscriptions / Income / Fixed
// & Variable expenses): one RFC-4180-lite tokenizer, header-token normalization,
// alias-based auto-mapping, the generic explicit-mapping row loop that collects ALL
// per-row errors, plus the shared column-value lookup and ISO-date parser. Each
// importer supplies only its own `CSVField` enum, alias map, and row→entity builder;
// nothing about the tokenizer or validation skeleton is duplicated per type.
//
// `CSVField` is modeled as `RawRepresentable<String> & Hashable` so the kit can build
// generic mappings keyed by any importer's field enum.
enum CSVImportKit {

    /// The outcome of building a single entity row: the entity, or all its errors.
    enum RowResult<Entity> {
        case success(Entity)
        case failure([ImportRowError])
    }

    // MARK: Auto-mapping

    /// Build the auto-detected field → column-index mapping for a header row using a
    /// per-field alias set. First alias match wins per field; first column wins on
    /// duplicate aliases. Tokens are normalized (lowercased, snake-cased) first.
    static func autoDetectMapping<Field: Hashable>(
        _ header: [String],
        aliases: [Field: Set<String>]
    ) -> [Field: Int] {
        var mapping: [Field: Int] = [:]
        for (i, raw) in header.enumerated() {
            let token = normalizeHeaderToken(raw)
            for (field, set) in aliases where set.contains(token) {
                if mapping[field] == nil { mapping[field] = i }
            }
        }
        return mapping
    }

    // MARK: Header analysis (shared shape for every importer)

    /// Inspect a CSV header: the raw tokens (trimmed, as written) + the alias
    /// auto-mapping. Empty when the text has no rows.
    static func analyzeHeader<Field: Hashable>(
        _ text: String,
        aliases: [Field: Set<String>]
    ) -> (headers: [String], autoMapping: [Field: Int]) {
        let rows = parseRecords(text)
        guard let header = rows.first else { return ([], [:]) }
        let tokens = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return (tokens, autoDetectMapping(header, aliases: aliases))
    }

    // MARK: Generic explicit-mapping row loop

    /// Parse a CSV string with an explicit field → column-index mapping into a typed
    /// preview, delegating per-row construction to `build`. The header row is row 1;
    /// data rows start at row 2. Wholly-blank rows are skipped.
    static func parse<Field: Hashable, Entity: Equatable & Sendable>(
        _ text: String,
        mapping: [Field: Int],
        build: (_ fields: [String], _ columnIndex: [Field: Int], _ rowNumber: Int) -> RowResult<Entity>
    ) -> EntityImportPreview<Entity> {
        parseRows(parseRecords(text), mapping: mapping, build: build)
    }

    /// Same as `parse` but over already-tokenized records (header at index 0).
    static func parseRows<Field: Hashable, Entity: Equatable & Sendable>(
        _ rows: [[String]],
        mapping: [Field: Int],
        build: (_ fields: [String], _ columnIndex: [Field: Int], _ rowNumber: Int) -> RowResult<Entity>
    ) -> EntityImportPreview<Entity> {
        guard !rows.isEmpty else {
            return EntityImportPreview(valid: [], errors: [], totalRows: 0)
        }

        let dataRows = Array(rows.dropFirst())
        var valid: [Entity] = []
        var errors: [ImportRowError] = []

        for (offset, fields) in dataRows.enumerated() {
            let rowNumber = offset + 2 // header is row 1
            if isBlank(fields) { continue }
            switch build(fields, mapping, rowNumber) {
            case .success(let entity): valid.append(entity)
            case .failure(let rowErrors): errors.append(contentsOf: rowErrors)
            }
        }

        let totalRows = dataRows.filter { !isBlank($0) }.count
        return EntityImportPreview(valid: valid, errors: errors, totalRows: totalRows)
    }

    private static func isBlank(_ fields: [String]) -> Bool {
        fields.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    // MARK: Shared column-value lookup

    /// The trimmed value for a mapped field, or "" if unmapped / out of range.
    static func value<Field: Hashable>(fields: [String], columnIndex: [Field: Int], key: Field) -> String {
        guard let idx = columnIndex[key], idx >= 0, idx < fields.count else { return "" }
        return fields[idx].trimmingCharacters(in: .whitespaces)
    }

    // MARK: Header token normalization

    /// Lowercase, trim, and snake-case a header token (`Monthly Cost` → `monthly_cost`).
    static func normalizeHeaderToken(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var out = ""
        for ch in trimmed {
            if ch == " " || ch == "-" { out.append("_") }
            else { out.append(ch) }
        }
        return out
    }

    // MARK: Shared field parsers (currency / amount / date / bool)

    /// Parse a currency cell. Blank → `.eur` default, no error. An unknown code returns
    /// `.eur` with an "Unsupported currency" error appended to `errors`.
    static func parseCurrency(_ raw: String, row: Int, errors: inout [ImportRowError]) -> CurrencyCode {
        guard !raw.isEmpty else { return .eur }
        if let c = CurrencyCode(rawValue: raw.uppercased()) { return c }
        errors.append(ImportRowError(row: row, field: "currency", message: "Unsupported currency"))
        return .eur
    }

    /// Parse a required amount cell into minor units for `currency` (HALF-UP). Blank or
    /// unparseable → 0 with an "Invalid amount" error.
    static func parseAmount(_ raw: String, currency: CurrencyCode, row: Int, errors: inout [ImportRowError]) -> Int64 {
        if raw.isEmpty {
            errors.append(ImportRowError(row: row, field: "amount", message: "Invalid amount"))
            return 0
        }
        do {
            return try CSVNumberParser.parseAmountMinor(raw, currencyMinorDigits: currency.minorUnitDigits)
        } catch {
            errors.append(ImportRowError(row: row, field: "amount", message: "Invalid amount"))
            return 0
        }
    }

    /// Parse an ISO `yyyy-MM-dd` date (UTC, POSIX). Returns nil on failure.
    static func parseISODate(_ raw: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: raw)
    }

    /// Parse a loose boolean cell: true/yes/1/y/on → true; false/no/0/n/off → false;
    /// blank → `nil` (caller's default). Anything else returns `nil` and appends an error.
    static func parseBool(_ raw: String, field: String, row: Int, errors: inout [ImportRowError]) -> Bool? {
        let v = raw.lowercased()
        guard !v.isEmpty else { return nil }
        switch v {
        case "true", "yes", "1", "y", "on":  return true
        case "false", "no", "0", "n", "off": return false
        default:
            errors.append(ImportRowError(row: row, field: field, message: "Invalid boolean (expected true/false)"))
            return nil
        }
    }

    /// Resolve a category NAME to an existing expense category id (case-insensitive,
    /// trimmed). Blank or no match → `nil` (Uncategorized). Never an error.
    static func resolveCategoryID(_ name: String, in categories: [Category]) -> UUID? {
        let needle = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return nil }
        return categories.first { $0.name.lowercased() == needle }?.id
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
