import Foundation
import Supabase
import Domain
import Shared

// MARK: - User preferences DTO ↔ Domain (docs/05 §3.10)
// One row per user (RLS-scoped). `load` returns the single owned row, falling
// back to `.defaults` when none exists yet; `save` upserts it.

struct UserPreferencesDTO: Codable, Sendable {
    let appearance: String
    let defaultCurrency: String
    let biometricLockEnabled: Bool
    let paymentRemindersEnabled: Bool
    let paydayRemindersEnabled: Bool
    let reminderLeadTimeDays: Int

    enum CodingKeys: String, CodingKey {
        case appearance
        case defaultCurrency = "default_currency"
        case biometricLockEnabled = "biometric_lock_enabled"
        case paymentRemindersEnabled = "payment_reminders_enabled"
        case paydayRemindersEnabled = "payday_reminders_enabled"
        case reminderLeadTimeDays = "reminder_lead_time_days"
    }

    init(_ p: UserPreferences) {
        appearance = p.appearance.rawValue
        defaultCurrency = p.defaultCurrency.rawValue
        biometricLockEnabled = p.biometricLockEnabled
        paymentRemindersEnabled = p.paymentRemindersEnabled
        paydayRemindersEnabled = p.paydayRemindersEnabled
        reminderLeadTimeDays = p.reminderLeadTimeDays
    }

    func toDomain() -> UserPreferences {
        UserPreferences(
            appearance: Appearance(rawValue: appearance) ?? .system,
            defaultCurrency: CurrencyCode(rawValue: defaultCurrency) ?? .eur,
            biometricLockEnabled: biometricLockEnabled,
            paymentRemindersEnabled: paymentRemindersEnabled,
            paydayRemindersEnabled: paydayRemindersEnabled,
            reminderLeadTimeDays: reminderLeadTimeDays
        )
    }
}

// MARK: - SupabasePreferencesRepository

public struct SupabasePreferencesRepository: PreferencesRepository {
    private let provider: SupabaseClientProvider
    public init(provider: SupabaseClientProvider) { self.provider = provider }

    public func load() async throws -> UserPreferences {
        let client = await provider.client()
        let rows: [UserPreferencesDTO] = try await client
            .from("user_preferences").select().limit(1).execute().value
        return rows.first?.toDomain() ?? .defaults
    }

    public func save(_ preferences: UserPreferences) async throws {
        let client = await provider.client()
        try await client.from("user_preferences").upsert(UserPreferencesDTO(preferences)).execute()
    }
}
