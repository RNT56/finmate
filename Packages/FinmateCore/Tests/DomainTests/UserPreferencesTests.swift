import Testing
import Foundation
@testable import Domain

// docs/02 §12 / docs/05 §3.10 — UserPreferences defaults, lead-time clamping,
// and round-trip through the in-memory repository. iOS + web share these values.
@Suite struct UserPreferencesTests {

    // MARK: Defaults (docs/02 §12)

    @Test func defaultsMatchSpec() {
        let prefs = UserPreferences.defaults
        #expect(prefs.appearance == .system)
        #expect(prefs.defaultCurrency == .eur)
        #expect(prefs.biometricLockEnabled == false)
        #expect(prefs.paymentRemindersEnabled == true)
        #expect(prefs.paydayRemindersEnabled == true)
        #expect(prefs.reminderLeadTimeDays == 2)
    }

    @Test func memberwiseInitDefaultsMatch() {
        #expect(UserPreferences() == UserPreferences.defaults)
    }

    // MARK: Lead-time clamping (docs/05 §3.10 CHECK 0…30)

    @Test func leadTimeClampsBelowRange() {
        #expect(UserPreferences.clampLeadTime(-5) == 0)
    }

    @Test func leadTimeClampsAboveRange() {
        #expect(UserPreferences.clampLeadTime(45) == 30)
    }

    @Test func leadTimePassesThroughInRange() {
        #expect(UserPreferences.clampLeadTime(0) == 0)
        #expect(UserPreferences.clampLeadTime(2) == 2)
        #expect(UserPreferences.clampLeadTime(30) == 30)
    }

    @Test func initClampsLeadTime() {
        #expect(UserPreferences(reminderLeadTimeDays: 100).reminderLeadTimeDays == 30)
        #expect(UserPreferences(reminderLeadTimeDays: -1).reminderLeadTimeDays == 0)
    }

    @Test func mutatingSetterClamps() {
        var prefs = UserPreferences.defaults
        prefs.setReminderLeadTime(99)
        #expect(prefs.reminderLeadTimeDays == 30)
        prefs.setReminderLeadTime(7)
        #expect(prefs.reminderLeadTimeDays == 7)
    }

    // MARK: Repository round-trip

    @Test func repositoryLoadsSeededDefaults() async throws {
        let repo = InMemoryPreferencesRepository()
        let loaded = try await repo.load()
        #expect(loaded == UserPreferences.defaults)
    }

    @Test func repositoryRoundTripsSavedPreferences() async throws {
        let repo = InMemoryPreferencesRepository()
        var prefs = UserPreferences.defaults
        prefs.appearance = .dark
        prefs.defaultCurrency = .usd
        prefs.biometricLockEnabled = true
        prefs.paymentRemindersEnabled = false
        prefs.setReminderLeadTime(14)
        try await repo.save(prefs)

        let reloaded = try await repo.load()
        #expect(reloaded == prefs)
        #expect(reloaded.appearance == .dark)
        #expect(reloaded.defaultCurrency == .usd)
        #expect(reloaded.biometricLockEnabled == true)
        #expect(reloaded.paymentRemindersEnabled == false)
        #expect(reloaded.reminderLeadTimeDays == 14)
    }
}
