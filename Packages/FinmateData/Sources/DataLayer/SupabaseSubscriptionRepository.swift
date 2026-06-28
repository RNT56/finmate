import Foundation
import Supabase
import Domain
import Shared

// MARK: - Subscription DTO ↔ Domain (docs/05 §3.1)
// `user_id` is server-derived from `auth.uid()` via RLS, so it is never sent on
// insert/update from the client (the INSERT policy enforces `auth.uid() = user_id`,
// and the column defaults are owner-stamped by the new-user bootstrap / RLS).

struct SubscriptionDTO: Codable, Sendable {
    let id: UUID
    let name: String
    let vendorURL: String?
    let icon: String?
    let amountMinor: Int64
    let currency: String
    let billingPeriod: String
    let paymentMethod: String?
    let categoryID: UUID?
    let usageState: String
    let startDate: String
    let endDate: String?
    let autoRenew: Bool
    let favorite: Bool
    let remindersEnabled: Bool
    let sortOrder: Int
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, name, icon, currency, favorite, notes
        case vendorURL = "vendor_url"
        case amountMinor = "amount_minor"
        case billingPeriod = "billing_period"
        case paymentMethod = "payment_method"
        case categoryID = "category_id"
        case usageState = "usage_state"
        case startDate = "start_date"
        case endDate = "end_date"
        case autoRenew = "auto_renew"
        case remindersEnabled = "reminders_enabled"
        case sortOrder = "sort_order"
    }

    init(_ s: Subscription) {
        id = s.id
        name = s.name
        vendorURL = s.vendorURL
        icon = s.icon
        amountMinor = s.amountMinor
        currency = s.currency.rawValue
        billingPeriod = s.billingPeriod.rawValue
        paymentMethod = s.paymentMethod.rawValue
        categoryID = s.categoryID
        usageState = s.usageState.rawValue
        startDate = SupabaseCoding.dayString(s.startDate)
        endDate = s.endDate.map(SupabaseCoding.dayString)
        autoRenew = s.autoRenew
        favorite = s.favorite
        remindersEnabled = s.remindersEnabled
        sortOrder = s.sortOrder
        notes = s.notes
    }

    func toDomain() -> Subscription {
        Subscription(
            id: id,
            name: name,
            vendorURL: vendorURL,
            icon: icon,
            amountMinor: amountMinor,
            currency: CurrencyCode(rawValue: currency) ?? .eur,
            billingPeriod: BillingPeriod(rawValue: billingPeriod) ?? .monthly,
            paymentMethod: paymentMethod.flatMap(PaymentMethod.init(rawValue:)) ?? .other,
            categoryID: categoryID,
            usageState: UsageState(rawValue: usageState) ?? .active,
            startDate: SupabaseCoding.date(fromDay: startDate) ?? .now,
            endDate: SupabaseCoding.date(fromDay: endDate),
            autoRenew: autoRenew,
            favorite: favorite,
            remindersEnabled: remindersEnabled,
            sortOrder: sortOrder,
            notes: notes
        )
    }
}

// MARK: - SupabaseSubscriptionRepository (docs/03 §3 — implements Domain protocol)

public struct SupabaseSubscriptionRepository: SubscriptionRepository {
    private let provider: SupabaseClientProvider
    public init(provider: SupabaseClientProvider) { self.provider = provider }

    public func all() async throws -> [Subscription] {
        let client = await provider.client()
        let rows: [SubscriptionDTO] = try await client
            .from("subscriptions")
            .select()
            .order("sort_order", ascending: true)
            .execute()
            .value
        return rows.map { $0.toDomain() }
    }

    public func upsert(_ subscription: Subscription) async throws {
        let client = await provider.client()
        try await client
            .from("subscriptions")
            .upsert(SubscriptionDTO(subscription))
            .execute()
    }

    /// Owner-checked delete via the hardened `delete_subscription(uuid)` RPC
    /// (docs/05 §5.3) rather than a direct DELETE.
    public func delete(id: UUID) async throws {
        let client = await provider.client()
        try await client
            .rpc("delete_subscription", params: DeleteParams(subID: id))
            .execute()
    }

    /// Reorder via `batch_reorder_subscriptions(jsonb)` (docs/05 §5.2): only
    /// `sort_order` is touched, never `created_at`.
    public func reorder(_ orderedIDs: [UUID]) async throws {
        let client = await provider.client()
        let updates = orderedIDs.enumerated().map { index, id in
            ReorderItem(id: id, sortOrder: index)
        }
        try await client
            .rpc("batch_reorder_subscriptions", params: ReorderParams(updates: updates))
            .execute()
    }

    private struct DeleteParams: Encodable, Sendable {
        let subID: UUID
        enum CodingKeys: String, CodingKey { case subID = "sub_id" }
    }

    private struct ReorderParams: Encodable, Sendable {
        let updates: [ReorderItem]
    }

    private struct ReorderItem: Encodable, Sendable {
        let id: UUID
        let sortOrder: Int
        enum CodingKeys: String, CodingKey {
            case id
            case sortOrder = "sort_order"
        }
    }
}
