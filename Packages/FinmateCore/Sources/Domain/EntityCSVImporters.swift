import Foundation
import Shared

// MARK: - Income & expense CSV importers (docs/02 §6, docs/13 §9)
//
// Sibling importers to `SubscriptionCSVImporter`, all built on the shared
// `CSVImportKit` (one tokenizer, alias auto-mapping, the generic row loop, the shared
// currency/amount/date/bool parsers + category-name resolution). Each declares only
// its own `CSVField` enum, alias map, and row→entity builder. They mirror the
// subscription importer's public surface: `analyzeHeader` + an explicit-mapping
// `parse` returning the entity's typed `EntityImportPreview`.

public typealias IncomeImportPreview = EntityImportPreview<IncomeSource>
public typealias FixedExpenseImportPreview = EntityImportPreview<FixedExpense>
public typealias VariableExpenseImportPreview = EntityImportPreview<VariableExpense>

// MARK: - Income (IncomeSource)

public enum IncomeCSVImporter {

    public enum CSVField: String, CaseIterable, Hashable, Sendable {
        case name
        case amount
        case currency
        case frequency
        case nextPayment = "next_payment"
        case notes

        public var displayName: String {
            switch self {
            case .name:        return "Name"
            case .amount:      return "Amount"
            case .currency:    return "Currency"
            case .frequency:   return "Frequency"
            case .nextPayment: return "Next payment"
            case .notes:       return "Notes"
            }
        }

        public var isRequired: Bool { self == .name || self == .amount }
    }

    public struct HeaderAnalysis: Equatable, Sendable {
        public let headers: [String]
        public let autoMapping: [CSVField: Int]
        public init(headers: [String], autoMapping: [CSVField: Int]) {
            self.headers = headers; self.autoMapping = autoMapping
        }
    }

    private static let aliases: [CSVField: Set<String>] = [
        .name:        ["name", "source", "title", "income"],
        .amount:      ["amount", "pay", "salary", "income_amount", "monthly_amount"],
        .currency:    ["currency", "ccy"],
        .frequency:   ["frequency", "freq", "period", "cycle"],
        .nextPayment: ["next_payment", "next", "payday", "next_pay", "date"],
        .notes:       ["notes", "note", "memo", "description"],
    ]

    public static func analyzeHeader(_ text: String) -> HeaderAnalysis {
        let a = CSVImportKit.analyzeHeader(text, aliases: aliases)
        return HeaderAnalysis(headers: a.headers, autoMapping: a.autoMapping)
    }

    public static func parse(_ text: String, mapping: [CSVField: Int]) -> IncomeImportPreview {
        CSVImportKit.parse(text, mapping: mapping, build: buildRow)
    }

    private static func buildRow(fields: [String], columnIndex: [CSVField: Int], rowNumber: Int) -> CSVImportKit.RowResult<IncomeSource> {
        func value(_ key: CSVField) -> String { CSVImportKit.value(fields: fields, columnIndex: columnIndex, key: key) }
        var errors: [ImportRowError] = []

        let name = value(.name)
        if name.isEmpty {
            errors.append(ImportRowError(row: rowNumber, field: "name", message: "Missing name"))
        } else if name.count > 120 {
            errors.append(ImportRowError(row: rowNumber, field: "name", message: "Name too long (max 120 characters)"))
        }

        let currency = CSVImportKit.parseCurrency(value(.currency), row: rowNumber, errors: &errors)
        let amountMinor = CSVImportKit.parseAmount(value(.amount), currency: currency, row: rowNumber, errors: &errors)

        // frequency — default monthly
        var frequency: IncomeFrequency = .monthly
        let freqRaw = value(.frequency)
        if !freqRaw.isEmpty {
            if let f = IncomeFrequency(rawValue: freqRaw.lowercased()) {
                frequency = f
            } else {
                errors.append(ImportRowError(row: rowNumber, field: "frequency", message: "Invalid frequency (weekly/monthly/yearly/one_time)"))
            }
        }

        // next_payment — optional ISO date
        var nextPayment: Date?
        let nextRaw = value(.nextPayment)
        if !nextRaw.isEmpty {
            if let d = CSVImportKit.parseISODate(nextRaw) {
                nextPayment = d
            } else {
                errors.append(ImportRowError(row: rowNumber, field: "next_payment", message: "Invalid date (expected yyyy-MM-dd)"))
            }
        }

        let notesRaw = value(.notes)
        let notes = notesRaw.isEmpty ? nil : notesRaw

        guard errors.isEmpty else { return .failure(errors) }
        return .success(IncomeSource(
            name: name, amountMinor: amountMinor, currency: currency,
            frequency: frequency, nextPayment: nextPayment, notes: notes
        ))
    }
}

// MARK: - Fixed expense (FixedExpense)
//
// Category is a NAME in the CSV; `parse(_:mapping:categories:)` resolves it
// case-insensitively to an existing expense `Category` id (nil fallback).

public enum FixedExpenseCSVImporter {

    public enum CSVField: String, CaseIterable, Hashable, Sendable {
        case name
        case amount
        case currency
        case category
        case frequency
        case dueDate = "due_date"
        case autopay
        case notes

        public var displayName: String {
            switch self {
            case .name:      return "Name"
            case .amount:    return "Amount"
            case .currency:  return "Currency"
            case .category:  return "Category"
            case .frequency: return "Frequency"
            case .dueDate:   return "Due date"
            case .autopay:   return "Autopay"
            case .notes:     return "Notes"
            }
        }

        public var isRequired: Bool { self == .name || self == .amount }
    }

    public struct HeaderAnalysis: Equatable, Sendable {
        public let headers: [String]
        public let autoMapping: [CSVField: Int]
        public init(headers: [String], autoMapping: [CSVField: Int]) {
            self.headers = headers; self.autoMapping = autoMapping
        }
    }

    private static let aliases: [CSVField: Set<String>] = [
        .name:      ["name", "bill", "title", "expense"],
        .amount:    ["amount", "cost", "price", "monthly_cost", "monthly_amount"],
        .currency:  ["currency", "ccy"],
        .category:  ["category", "cat"],
        .frequency: ["frequency", "freq", "period", "cycle", "billing_period"],
        .dueDate:   ["due_date", "due", "date"],
        .autopay:   ["autopay", "auto_pay", "auto"],
        .notes:     ["notes", "note", "memo", "description"],
    ]

    public static func analyzeHeader(_ text: String) -> HeaderAnalysis {
        let a = CSVImportKit.analyzeHeader(text, aliases: aliases)
        return HeaderAnalysis(headers: a.headers, autoMapping: a.autoMapping)
    }

    /// Parse fixed expenses, resolving the category NAME column against `categories`
    /// (case-insensitive name → id; nil fallback / Uncategorized).
    public static func parse(_ text: String, mapping: [CSVField: Int], categories: [Category]) -> FixedExpenseImportPreview {
        CSVImportKit.parse(text, mapping: mapping) { fields, columnIndex, rowNumber in
            buildRow(fields: fields, columnIndex: columnIndex, rowNumber: rowNumber, categories: categories)
        }
    }

    private static func buildRow(fields: [String], columnIndex: [CSVField: Int], rowNumber: Int, categories: [Category]) -> CSVImportKit.RowResult<FixedExpense> {
        func value(_ key: CSVField) -> String { CSVImportKit.value(fields: fields, columnIndex: columnIndex, key: key) }
        var errors: [ImportRowError] = []

        let name = value(.name)
        if name.isEmpty {
            errors.append(ImportRowError(row: rowNumber, field: "name", message: "Missing name"))
        } else if name.count > 120 {
            errors.append(ImportRowError(row: rowNumber, field: "name", message: "Name too long (max 120 characters)"))
        }

        let currency = CSVImportKit.parseCurrency(value(.currency), row: rowNumber, errors: &errors)
        let amountMinor = CSVImportKit.parseAmount(value(.amount), currency: currency, row: rowNumber, errors: &errors)

        // category NAME → id (case-insensitive, nil fallback — never an error)
        let categoryID = CSVImportKit.resolveCategoryID(value(.category), in: categories)

        // frequency — BillingPeriod (weekly/monthly/quarterly/yearly), default monthly
        var frequency: BillingPeriod = .monthly
        let freqRaw = value(.frequency)
        if !freqRaw.isEmpty {
            if let f = BillingPeriod(rawValue: freqRaw.lowercased()) {
                frequency = f
            } else {
                errors.append(ImportRowError(row: rowNumber, field: "frequency", message: "Invalid frequency (weekly/monthly/quarterly/yearly)"))
            }
        }

        // due_date — optional ISO date
        var dueDate: Date?
        let dueRaw = value(.dueDate)
        if !dueRaw.isEmpty {
            if let d = CSVImportKit.parseISODate(dueRaw) {
                dueDate = d
            } else {
                errors.append(ImportRowError(row: rowNumber, field: "due_date", message: "Invalid date (expected yyyy-MM-dd)"))
            }
        }

        // autopay — optional bool, default false
        let autopay = CSVImportKit.parseBool(value(.autopay), field: "autopay", row: rowNumber, errors: &errors) ?? false

        let notesRaw = value(.notes)
        let notes = notesRaw.isEmpty ? nil : notesRaw

        guard errors.isEmpty else { return .failure(errors) }
        return .success(FixedExpense(
            name: name, amountMinor: amountMinor, currency: currency,
            categoryID: categoryID, frequency: frequency, dueDate: dueDate,
            autopay: autopay, notes: notes
        ))
    }
}

// MARK: - Variable expense (VariableExpense)
//
// `date` (spent_on) is REQUIRED. Category is a NAME resolved like fixed expenses.

public enum VariableExpenseCSVImporter {

    public enum CSVField: String, CaseIterable, Hashable, Sendable {
        case name
        case amount
        case currency
        case category
        case date
        case notes

        public var displayName: String {
            switch self {
            case .name:     return "Name"
            case .amount:   return "Amount"
            case .currency: return "Currency"
            case .category: return "Category"
            case .date:     return "Date"
            case .notes:    return "Notes"
            }
        }

        public var isRequired: Bool { self == .name || self == .amount || self == .date }
    }

    public struct HeaderAnalysis: Equatable, Sendable {
        public let headers: [String]
        public let autoMapping: [CSVField: Int]
        public init(headers: [String], autoMapping: [CSVField: Int]) {
            self.headers = headers; self.autoMapping = autoMapping
        }
    }

    private static let aliases: [CSVField: Set<String>] = [
        .name:     ["name", "title", "expense", "merchant", "description"],
        .amount:   ["amount", "cost", "price", "spent"],
        .currency: ["currency", "ccy"],
        .category: ["category", "cat"],
        .date:     ["spent_on", "date", "spent", "on"],
        .notes:    ["notes", "note", "memo"],
    ]

    public static func analyzeHeader(_ text: String) -> HeaderAnalysis {
        let a = CSVImportKit.analyzeHeader(text, aliases: aliases)
        return HeaderAnalysis(headers: a.headers, autoMapping: a.autoMapping)
    }

    /// Parse variable expenses, resolving the category NAME column against `categories`.
    public static func parse(_ text: String, mapping: [CSVField: Int], categories: [Category]) -> VariableExpenseImportPreview {
        CSVImportKit.parse(text, mapping: mapping) { fields, columnIndex, rowNumber in
            buildRow(fields: fields, columnIndex: columnIndex, rowNumber: rowNumber, categories: categories)
        }
    }

    private static func buildRow(fields: [String], columnIndex: [CSVField: Int], rowNumber: Int, categories: [Category]) -> CSVImportKit.RowResult<VariableExpense> {
        func value(_ key: CSVField) -> String { CSVImportKit.value(fields: fields, columnIndex: columnIndex, key: key) }
        var errors: [ImportRowError] = []

        let name = value(.name)
        if name.isEmpty {
            errors.append(ImportRowError(row: rowNumber, field: "name", message: "Missing name"))
        } else if name.count > 120 {
            errors.append(ImportRowError(row: rowNumber, field: "name", message: "Name too long (max 120 characters)"))
        }

        let currency = CSVImportKit.parseCurrency(value(.currency), row: rowNumber, errors: &errors)
        let amountMinor = CSVImportKit.parseAmount(value(.amount), currency: currency, row: rowNumber, errors: &errors)

        let categoryID = CSVImportKit.resolveCategoryID(value(.category), in: categories)

        // date — REQUIRED ISO date
        var date = Date()
        let dateRaw = value(.date)
        if dateRaw.isEmpty {
            errors.append(ImportRowError(row: rowNumber, field: "date", message: "Missing date (expected yyyy-MM-dd)"))
        } else if let d = CSVImportKit.parseISODate(dateRaw) {
            date = d
        } else {
            errors.append(ImportRowError(row: rowNumber, field: "date", message: "Invalid date (expected yyyy-MM-dd)"))
        }

        let notesRaw = value(.notes)
        let notes = notesRaw.isEmpty ? nil : notesRaw

        guard errors.isEmpty else { return .failure(errors) }
        return .success(VariableExpense(
            name: name, amountMinor: amountMinor, currency: currency,
            categoryID: categoryID, date: date, notes: notes
        ))
    }
}
