import SwiftUI
import Observation
import Domain
import DataLayer
import UniformTypeIdentifiers

// MARK: - M7 Settings (docs/02 §12, docs/05 §3.10, docs/07)
// The Settings surface: appearance, default display currency, reminders,
// biometric lock, data export, account deletion, About. App-wide appearance is
// driven by `PreferencesStore.appearance` via `.preferredColorScheme` at the App
// root (see FinmateApp). Account deletion calls the `delete-account` Edge Function
// (stubbed here); export shares a stub payload (docs/07).

extension Appearance {
    /// SwiftUI color-scheme override; `nil` == follow the system (docs/02 §12).
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
}

extension CurrencyCode {
    /// Human label for pickers, e.g. "EUR (€)".
    var displayLabel: String { "\(rawValue) (\(symbol))" }
}

// MARK: - Store (@Observable, MainActor) — docs/03 unidirectional MVVM

@MainActor
@Observable
final class PreferencesStore {
    private(set) var preferences: UserPreferences = .defaults
    private let repository: PreferencesRepository

    init(repository: PreferencesRepository = InMemoryPreferencesRepository()) {
        self.repository = repository
    }

    var appearance: Appearance { preferences.appearance }

    func load() async {
        if let loaded = try? await repository.load() { preferences = loaded }
    }

    /// Mutate-then-persist. Optimistic: the UI binds to `preferences` and the
    /// repository write follows (docs/03 offline-first writes).
    private func update(_ mutate: (inout UserPreferences) -> Void) {
        var next = preferences
        mutate(&next)
        preferences = next
        Task { try? await repository.save(next) }
    }

    func setAppearance(_ value: Appearance) { update { $0.appearance = value } }
    func setDefaultCurrency(_ value: CurrencyCode) { update { $0.defaultCurrency = value } }
    func setBiometricLock(_ value: Bool) { update { $0.biometricLockEnabled = value } }
    func setPaymentReminders(_ value: Bool) { update { $0.paymentRemindersEnabled = value } }
    func setPaydayReminders(_ value: Bool) { update { $0.paydayRemindersEnabled = value } }
    func setReminderLeadTime(_ days: Int) { update { $0.setReminderLeadTime(days) } }
}

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(PreferencesStore.self) private var store
    @Environment(\.repositories) private var repositories
    @Environment(\.authStore) private var authStore

    @State private var showingExport = false
    @State private var showingLogoutConfirm = false
    @State private var showingDeleteConfirm = false
    @State private var showingDeleteFinalConfirm = false
    @State private var exportData: Data?
    @State private var exporting = false
    @State private var exportError: String?

    private let leadTimeRange = UserPreferences.reminderLeadTimeRange

    var body: some View {
        // Local bindings into the @Observable store (controls write through setters).
        let appearance = Binding(
            get: { store.appearance },
            set: { store.setAppearance($0) }
        )
        let currency = Binding(
            get: { store.preferences.defaultCurrency },
            set: { store.setDefaultCurrency($0) }
        )
        let biometric = Binding(
            get: { store.preferences.biometricLockEnabled },
            set: { store.setBiometricLock($0) }
        )
        let paymentReminders = Binding(
            get: { store.preferences.paymentRemindersEnabled },
            set: { store.setPaymentReminders($0) }
        )
        let paydayReminders = Binding(
            get: { store.preferences.paydayRemindersEnabled },
            set: { store.setPaydayReminders($0) }
        )

        Form {
            // MARK: Appearance
            Section("Appearance") {
                Picker(selection: appearance) {
                    ForEach(Appearance.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                } label: {
                    Label("Theme", systemImage: "circle.lefthalf.filled")
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Appearance theme")
            }

            // MARK: Default currency
            Section {
                Picker(selection: currency) {
                    ForEach([CurrencyCode.eur, .usd, .btc], id: \.self) { code in
                        Text(code.displayLabel).tag(code)
                    }
                } label: {
                    Label("Display currency", systemImage: "coloncurrencysign.circle")
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Default display currency")
            } header: {
                Text("Currency")
            } footer: {
                Text("Used to display totals. Stored amounts keep their own currency and are never converted at rest.")
            }

            // MARK: Reminders
            Section {
                Toggle(isOn: paymentReminders) {
                    Label("Payment reminders", systemImage: "bell.badge")
                }
                Toggle(isOn: paydayReminders) {
                    Label("Payday reminders", systemImage: "calendar.badge.clock")
                }
                Stepper(value: Binding(
                    get: { store.preferences.reminderLeadTimeDays },
                    set: { store.setReminderLeadTime($0) }
                ), in: leadTimeRange) {
                    LabeledContent {
                        Text("\(store.preferences.reminderLeadTimeDays) day\(store.preferences.reminderLeadTimeDays == 1 ? "" : "s")")
                    } label: {
                        Label("Lead time", systemImage: "clock.arrow.circlepath")
                    }
                }
                .accessibilityLabel("Reminder lead time in days")
                .accessibilityValue("\(store.preferences.reminderLeadTimeDays)")
            } header: {
                Text("Reminders")
            } footer: {
                Text("How many days ahead to notify you about an upcoming charge or payday (0–30).")
            }

            // MARK: Privacy
            Section {
                Toggle(isOn: biometric) {
                    Label("Require Face ID / Touch ID", systemImage: "faceid")
                }
                .accessibilityLabel("Require Face ID or Touch ID to unlock")
            } header: {
                Text("Privacy")
            } footer: {
                Text("Locks the app behind device biometrics using LocalAuthentication. Tokens stay in the Keychain.")
            }

            // MARK: Account
            Section {
                Button(role: .destructive) {
                    showingLogoutConfirm = true
                } label: {
                    Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .accessibilityHint("Signs out and returns to the sign-in screen")
            } header: {
                Text("Account")
            } footer: {
                Text("Signing out clears your session from the Keychain and returns to the sign-in screen.")
            }

            // MARK: Data
            Section {
                Button {
                    Task { await runExport() }
                } label: {
                    HStack {
                        Label("Export data", systemImage: "square.and.arrow.up")
                        if exporting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(exporting)
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete account", systemImage: "trash")
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Export downloads a copy of your data. Deleting your account is permanent and runs the delete-account Edge Function.")
            }

            // MARK: About
            Section("About") {
                LabeledContent("Version", value: Self.appVersion)
                Link(destination: URL(string: "https://github.com/RNT56/finmate")!) {
                    Label("Source & docs", systemImage: "doc.text")
                }
                Link(destination: URL(string: "https://github.com/RNT56/finmate/blob/main/docs/07-security-and-privacy.md")!) {
                    Label("Privacy & security", systemImage: "lock.shield")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(FinmateGradient())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingExport) {
            if let data = exportData {
                ExportDataView(data: data)
            }
        }
        .alert("Export failed", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        // Double-confirm account deletion (docs/07) — first dialog, then a final one.
        .confirmationDialog(
            "Log out of Finmate?",
            isPresented: $showingLogoutConfirm,
            titleVisibility: .visible
        ) {
            Button("Log out", role: .destructive) {
                Task { await authStore?.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll return to the sign-in screen. Your session is cleared from the Keychain.")
        }
        .confirmationDialog(
            "Delete your account?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Continue", role: .destructive) { showingDeleteFinalConfirm = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes all your Finmate data via the delete-account Edge Function. This cannot be undone.")
        }
        .confirmationDialog(
            "Are you absolutely sure?",
            isPresented: $showingDeleteFinalConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete account permanently", role: .destructive) {
                Task { await Self.deleteAccountStub() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("There is no recovery. Confirm to call delete-account.")
        }
    }

    static var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    /// Build the real export `ExportBundle` from the live repositories and encode
    /// it to JSON `Data` (docs/07 §9.3). Money stays in RAW minor units + currency.
    @MainActor
    private func runExport() async {
        exporting = true
        defer { exporting = false }
        do {
            async let subs = repositories.subscriptions.all()
            async let income = repositories.income.all()
            async let fixed = repositories.expenses.fixed()
            async let variable = repositories.expenses.variable()
            async let assets = repositories.assets.all()

            let bundle = ExportBundle(
                exportedAt: Date(),
                subscriptions: try await subs,
                income: try await income,
                fixedExpenses: try await fixed,
                variableExpenses: try await variable,
                assets: try await assets,
                preferences: store.preferences
            )
            exportData = try DataExport.encode(bundle)
            showingExport = true
        } catch {
            exportError = error.localizedDescription
        }
    }

    /// Stub for the `delete-account` Edge Function call (docs/07). In production this
    /// invokes the hardened Edge Function via the authenticated client, then signs out.
    static func deleteAccountStub() async {
        // No-op placeholder; wiring to supabase-swift lands with the real DataLayer.
    }
}

/// A `finmate-export.json` file backed by in-memory `Data`, exposed as a
/// `Transferable` so `ShareLink` writes a real `.json` file to the share sheet.
struct ExportFile: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { file in
            file.data
        }
        .suggestedFileName(DataExport.fileName)
    }
}

/// Share-sheet wrapper presenting the real JSON export as a `finmate-export.json`
/// file (docs/07 §9.3).
struct ExportDataView: View {
    let data: Data
    @Environment(\.dismiss) private var dismiss

    private var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: FinmateTokens.spacing) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(DataExport.fileName, systemImage: "doc.text")
                            .font(.headline)
                        Text("A JSON copy of your subscriptions, income, expenses, assets, and preferences. Amounts are exported in raw minor units with their own currency.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(sizeLabel)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                ShareLink(
                    item: ExportFile(data: data),
                    preview: SharePreview(DataExport.fileName)
                ) {
                    Label("Share export", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(FinmateGradient())
            .navigationTitle("Export data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
