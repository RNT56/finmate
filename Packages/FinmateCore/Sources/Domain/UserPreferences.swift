import Foundation
import Shared

// MARK: - User preferences (docs/02 §12, docs/05 §3.10) — M7 Settings
// Mirrors the snake_case `user_preferences` row (camelCase in Swift). Pure data +
// a repository protocol; the in-memory implementation backs the Settings UI until
// the Supabase-backed repository swaps in behind the same seam (docs/03 §3).

/// App appearance preference. `system` follows the OS setting (docs/02 §12).
public enum Appearance: String, Codable, Sendable, CaseIterable {
    case system, light, dark
}

/// User-level preferences row (docs/05 §3.10). One per user.
/// Defaults (docs/02 §12 / docs/05 §3.10): system appearance, EUR display
/// currency, biometric lock off, both reminder kinds on, 2-day lead time.
public struct UserPreferences: Equatable, Sendable, Codable {
    public var appearance: Appearance
    public var defaultCurrency: CurrencyCode
    public var biometricLockEnabled: Bool
    public var paymentRemindersEnabled: Bool
    public var paydayRemindersEnabled: Bool
    /// Days before a due date to remind. Clamped to `0...30` (docs/05 §3.10 CHECK).
    public var reminderLeadTimeDays: Int

    /// Allowed inclusive range for the reminder lead time (docs/05 §3.10).
    public static let reminderLeadTimeRange = 0...30

    public init(appearance: Appearance = .system,
                defaultCurrency: CurrencyCode = .eur,
                biometricLockEnabled: Bool = false,
                paymentRemindersEnabled: Bool = true,
                paydayRemindersEnabled: Bool = true,
                reminderLeadTimeDays: Int = 2) {
        self.appearance = appearance
        self.defaultCurrency = defaultCurrency
        self.biometricLockEnabled = biometricLockEnabled
        self.paymentRemindersEnabled = paymentRemindersEnabled
        self.paydayRemindersEnabled = paydayRemindersEnabled
        self.reminderLeadTimeDays = UserPreferences.clampLeadTime(reminderLeadTimeDays)
    }

    /// Canonical defaults (docs/02 §12).
    public static let defaults = UserPreferences()

    /// Clamp a lead-time value into the allowed `0...30` range (HALF-open inputs
    /// from steppers/CSV are coerced, never rejected).
    public static func clampLeadTime(_ days: Int) -> Int {
        min(reminderLeadTimeRange.upperBound, max(reminderLeadTimeRange.lowerBound, days))
    }

    /// Set the lead time, clamping into range.
    public mutating func setReminderLeadTime(_ days: Int) {
        reminderLeadTimeDays = UserPreferences.clampLeadTime(days)
    }
}

// MARK: - Repository protocol (docs/03 §3 — declared in Domain, implemented in DataLayer)

public protocol PreferencesRepository: Sendable {
    func load() async throws -> UserPreferences
    func save(_ preferences: UserPreferences) async throws
}

/// In-memory `PreferencesRepository` for previews/tests and the first executable
/// slice; the Supabase-backed implementation swaps in behind the same protocol.
public actor InMemoryPreferencesRepository: PreferencesRepository {
    private var preferences: UserPreferences

    public init(seed: UserPreferences = .defaults) {
        self.preferences = seed
    }

    public func load() async throws -> UserPreferences { preferences }

    public func save(_ preferences: UserPreferences) async throws {
        self.preferences = UserPreferences(
            appearance: preferences.appearance,
            defaultCurrency: preferences.defaultCurrency,
            biometricLockEnabled: preferences.biometricLockEnabled,
            paymentRemindersEnabled: preferences.paymentRemindersEnabled,
            paydayRemindersEnabled: preferences.paydayRemindersEnabled,
            reminderLeadTimeDays: preferences.reminderLeadTimeDays
        )
    }
}
