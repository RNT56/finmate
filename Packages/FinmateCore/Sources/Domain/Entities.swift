import Foundation
import Shared

// MARK: - Domain entities (docs/05) — camelCase mirrors of the snake_case schema.
// Money is carried as (amountMinor, currency); never Double.

public enum UsageState: String, Codable, Sendable, CaseIterable {
    case active, rarely, unused
}

public enum PaymentMethod: String, Codable, Sendable, CaseIterable {
    case creditCard = "credit_card"
    case debitCard = "debit_card"
    case paypal
    case bankTransfer = "bank_transfer"
    case applePay = "apple_pay"
    case googlePay = "google_pay"
    case crypto
    case other
}

public struct Subscription: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var vendorURL: String?
    public var icon: String?
    public var amountMinor: Int64
    public var currency: CurrencyCode
    public var billingPeriod: BillingPeriod
    public var paymentMethod: PaymentMethod
    public var categoryID: UUID?
    public var usageState: UsageState
    public var startDate: Date
    public var endDate: Date?
    public var autoRenew: Bool
    public var favorite: Bool
    public var remindersEnabled: Bool
    public var sortOrder: Int
    public var notes: String?

    public init(id: UUID = UUID(), name: String, vendorURL: String? = nil, icon: String? = nil,
                amountMinor: Int64, currency: CurrencyCode, billingPeriod: BillingPeriod,
                paymentMethod: PaymentMethod = .other, categoryID: UUID? = nil,
                usageState: UsageState = .active, startDate: Date, endDate: Date? = nil,
                autoRenew: Bool = true, favorite: Bool = false, remindersEnabled: Bool = false,
                sortOrder: Int = 0, notes: String? = nil) {
        self.id = id; self.name = name; self.vendorURL = vendorURL; self.icon = icon
        self.amountMinor = amountMinor; self.currency = currency; self.billingPeriod = billingPeriod
        self.paymentMethod = paymentMethod; self.categoryID = categoryID; self.usageState = usageState
        self.startDate = startDate; self.endDate = endDate; self.autoRenew = autoRenew
        self.favorite = favorite; self.remindersEnabled = remindersEnabled
        self.sortOrder = sortOrder; self.notes = notes
    }

    /// Canonical monthly cost in this subscription's own currency.
    public var monthlyAmount: Money {
        Money(minorUnits: BillingPeriodMath.monthlyMinorUnits(amountMinor: amountMinor, period: billingPeriod),
              currency: currency)
    }
}

public enum CategoryKind: String, Codable, Sendable, CaseIterable {
    case subscription, expense
}

public struct Category: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var slug: String
    public var kind: CategoryKind
    public var isProtected: Bool

    public init(id: UUID = UUID(), name: String, slug: String, kind: CategoryKind, isProtected: Bool = false) {
        self.id = id; self.name = name; self.slug = slug; self.kind = kind; self.isProtected = isProtected
    }
}

// MARK: - Income & expenses (docs/05 §3.4–3.6, M2)

/// A recurring (or one-time) income source — docs/05 `income_sources`.
/// `oneTime` income is excluded from the recurring monthly roll-up (docs/13 §6.1).
public struct IncomeSource: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var amountMinor: Int64
    public var currency: CurrencyCode
    public var frequency: IncomeFrequency
    public var nextPayment: Date?
    public var notes: String?

    public init(id: UUID = UUID(), name: String, amountMinor: Int64, currency: CurrencyCode,
                frequency: IncomeFrequency, nextPayment: Date? = nil, notes: String? = nil) {
        self.id = id; self.name = name; self.amountMinor = amountMinor; self.currency = currency
        self.frequency = frequency; self.nextPayment = nextPayment; self.notes = notes
    }

    /// Monthly-equivalent minor units in this source's own currency (docs/13 §6.1,
    /// HALF-UP). `oneTime` contributes 0 to the recurring roll-up.
    public var monthlyMinor: Int64 {
        roundHalfUpToInt64(Decimal(amountMinor) * frequency.monthlyFactor)
    }
}

/// A fixed/recurring bill — docs/05 `fixed_expenses`. Reuses `BillingPeriod`
/// (monthly/quarterly/yearly; weekly also supported) for frequency normalization.
public struct FixedExpense: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var amountMinor: Int64
    public var currency: CurrencyCode
    public var category: String?
    public var frequency: BillingPeriod
    public var dueDate: Date?
    public var autopay: Bool
    public var notes: String?

    public init(id: UUID = UUID(), name: String, amountMinor: Int64, currency: CurrencyCode,
                category: String? = nil, frequency: BillingPeriod, dueDate: Date? = nil,
                autopay: Bool = false, notes: String? = nil) {
        self.id = id; self.name = name; self.amountMinor = amountMinor; self.currency = currency
        self.category = category; self.frequency = frequency; self.dueDate = dueDate
        self.autopay = autopay; self.notes = notes
    }

    /// Canonical monthly minor units in this expense's own currency (docs/13 §3/§6.2).
    public var monthlyMinor: Int64 {
        BillingPeriodMath.monthlyMinorUnits(amountMinor: amountMinor, period: frequency)
    }
}

/// A one-off spend within a month — docs/05 `variable_expenses`.
public struct VariableExpense: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var amountMinor: Int64
    public var currency: CurrencyCode
    public var category: String?
    public var date: Date
    public var notes: String?

    public init(id: UUID = UUID(), name: String, amountMinor: Int64, currency: CurrencyCode,
                category: String? = nil, date: Date, notes: String? = nil) {
        self.id = id; self.name = name; self.amountMinor = amountMinor; self.currency = currency
        self.category = category; self.date = date; self.notes = notes
    }
}

// MARK: - Repository protocols (docs/03 §3 — declared in Domain, implemented in DataLayer)

public protocol SubscriptionRepository: Sendable {
    func all() async throws -> [Subscription]
    func upsert(_ subscription: Subscription) async throws
    func delete(id: UUID) async throws
    func reorder(_ orderedIDs: [UUID]) async throws
}

public protocol IncomeRepository: Sendable {
    func all() async throws -> [IncomeSource]
    func upsert(_ income: IncomeSource) async throws
    func delete(id: UUID) async throws
}

public protocol ExpenseRepository: Sendable {
    func fixed() async throws -> [FixedExpense]
    func variable() async throws -> [VariableExpense]
    func upsertFixed(_ expense: FixedExpense) async throws
    func upsertVariable(_ expense: VariableExpense) async throws
    func deleteFixed(id: UUID) async throws
    func deleteVariable(id: UUID) async throws
}

public protocol CategoryRepository: Sendable {
    func categories(kind: CategoryKind) async throws -> [Category]
}

public protocol ExchangeRateProvider: Sendable {
    /// Fetches the latest rates from the `market-data` Edge Function (display-only use).
    func latestRates() async throws -> ExchangeRates
}
