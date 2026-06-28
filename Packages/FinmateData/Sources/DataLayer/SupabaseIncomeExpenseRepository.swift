import Foundation
import Supabase
import Domain
import Shared

// MARK: - Income source DTO ↔ Domain (docs/05 §3.4)

struct IncomeSourceDTO: Codable, Sendable {
    let id: UUID
    let name: String
    let amountMinor: Int64
    let currency: String
    let frequency: String
    let nextPayment: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, name, currency, frequency, notes
        case amountMinor = "amount_minor"
        case nextPayment = "next_payment"
    }

    init(_ s: IncomeSource) {
        id = s.id
        name = s.name
        amountMinor = s.amountMinor
        currency = s.currency.rawValue
        frequency = s.frequency.rawValue
        nextPayment = s.nextPayment.map(SupabaseCoding.dayString)
        notes = s.notes
    }

    func toDomain() -> IncomeSource {
        IncomeSource(
            id: id,
            name: name,
            amountMinor: amountMinor,
            currency: CurrencyCode(rawValue: currency) ?? .eur,
            frequency: IncomeFrequency(rawValue: frequency) ?? .monthly,
            nextPayment: SupabaseCoding.date(fromDay: nextPayment),
            notes: notes
        )
    }
}

// MARK: - Fixed expense DTO ↔ Domain (docs/05 §3.5)

struct FixedExpenseDTO: Codable, Sendable {
    let id: UUID
    let name: String
    let amountMinor: Int64
    let currency: String
    let categoryID: UUID?
    let frequency: String
    let dueDate: String?
    let autopay: Bool
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, name, currency, frequency, autopay, notes
        case amountMinor = "amount_minor"
        case categoryID = "category_id"
        case dueDate = "due_date"
    }

    init(_ e: FixedExpense) {
        id = e.id
        name = e.name
        amountMinor = e.amountMinor
        currency = e.currency.rawValue
        categoryID = e.categoryID
        // Schema CHECK allows monthly/quarterly/yearly; weekly maps to monthly.
        frequency = (e.frequency == .weekly ? .monthly : e.frequency).rawValue
        dueDate = e.dueDate.map(SupabaseCoding.dayString)
        autopay = e.autopay
        notes = e.notes
    }

    func toDomain() -> FixedExpense {
        FixedExpense(
            id: id,
            name: name,
            amountMinor: amountMinor,
            currency: CurrencyCode(rawValue: currency) ?? .eur,
            categoryID: categoryID,
            frequency: BillingPeriod(rawValue: frequency) ?? .monthly,
            dueDate: SupabaseCoding.date(fromDay: dueDate),
            autopay: autopay,
            notes: notes
        )
    }
}

// MARK: - Variable expense DTO ↔ Domain (docs/05 §3.6) — `spent_on` date column

struct VariableExpenseDTO: Codable, Sendable {
    let id: UUID
    let name: String
    let amountMinor: Int64
    let currency: String
    let categoryID: UUID?
    let spentOn: String
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, name, currency, notes
        case amountMinor = "amount_minor"
        case categoryID = "category_id"
        case spentOn = "spent_on"
    }

    init(_ e: VariableExpense) {
        id = e.id
        name = e.name
        amountMinor = e.amountMinor
        currency = e.currency.rawValue
        categoryID = e.categoryID
        spentOn = SupabaseCoding.dayString(e.date)
        notes = e.notes
    }

    func toDomain() -> VariableExpense {
        VariableExpense(
            id: id,
            name: name,
            amountMinor: amountMinor,
            currency: CurrencyCode(rawValue: currency) ?? .eur,
            categoryID: categoryID,
            date: SupabaseCoding.date(fromDay: spentOn) ?? .now,
            notes: notes
        )
    }
}

// MARK: - SupabaseIncomeRepository

public struct SupabaseIncomeRepository: IncomeRepository {
    private let provider: SupabaseClientProvider
    public init(provider: SupabaseClientProvider) { self.provider = provider }

    public func all() async throws -> [IncomeSource] {
        let client = await provider.client()
        let rows: [IncomeSourceDTO] = try await client
            .from("income_sources").select().execute().value
        return rows.map { $0.toDomain() }
    }

    public func upsert(_ income: IncomeSource) async throws {
        let client = await provider.client()
        try await client.from("income_sources").upsert(IncomeSourceDTO(income)).execute()
    }

    public func delete(id: UUID) async throws {
        let client = await provider.client()
        try await client.from("income_sources").delete().eq("id", value: id.uuidString).execute()
    }
}

// MARK: - SupabaseExpenseRepository

public struct SupabaseExpenseRepository: ExpenseRepository {
    private let provider: SupabaseClientProvider
    public init(provider: SupabaseClientProvider) { self.provider = provider }

    public func fixed() async throws -> [FixedExpense] {
        let client = await provider.client()
        let rows: [FixedExpenseDTO] = try await client
            .from("fixed_expenses").select().execute().value
        return rows.map { $0.toDomain() }
    }

    public func variable() async throws -> [VariableExpense] {
        let client = await provider.client()
        let rows: [VariableExpenseDTO] = try await client
            .from("variable_expenses").select().order("spent_on", ascending: false).execute().value
        return rows.map { $0.toDomain() }
    }

    public func upsertFixed(_ expense: FixedExpense) async throws {
        let client = await provider.client()
        try await client.from("fixed_expenses").upsert(FixedExpenseDTO(expense)).execute()
    }

    public func upsertVariable(_ expense: VariableExpense) async throws {
        let client = await provider.client()
        try await client.from("variable_expenses").upsert(VariableExpenseDTO(expense)).execute()
    }

    public func deleteFixed(id: UUID) async throws {
        let client = await provider.client()
        try await client.from("fixed_expenses").delete().eq("id", value: id.uuidString).execute()
    }

    public func deleteVariable(id: UUID) async throws {
        let client = await provider.client()
        try await client.from("variable_expenses").delete().eq("id", value: id.uuidString).execute()
    }
}
