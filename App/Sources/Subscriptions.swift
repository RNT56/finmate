import SwiftUI
import Observation
import Domain
import DataLayer

// MARK: - DataLayer (in-memory) — docs/03 §3. Implements the Domain repository
// protocol; the real Supabase-backed implementation swaps in behind the same seam.

actor InMemorySubscriptionRepository: SubscriptionRepository {
    private var store: [UUID: Subscription]
    init(seed: [Subscription]) {
        store = Dictionary(uniqueKeysWithValues: seed.map { ($0.id, $0) })
    }
    func all() async throws -> [Subscription] {
        store.values.sorted { $0.sortOrder < $1.sortOrder }
    }
    func upsert(_ subscription: Subscription) async throws {
        store[subscription.id] = subscription
    }
    func delete(id: UUID) async throws {
        store[id] = nil
    }
    func reorder(_ orderedIDs: [UUID]) async throws {
        for (index, id) in orderedIDs.enumerated() { store[id]?.sortOrder = index }
    }
}

enum SampleData {
    static let subscriptions: [Subscription] = [
        Subscription(name: "Netflix", vendorURL: "netflix.com", icon: "play.tv.fill",
                     amountMinor: 1299, currency: .eur, billingPeriod: .monthly,
                     paymentMethod: .creditCard, usageState: .active, startDate: .now, sortOrder: 0),
        Subscription(name: "Spotify", vendorURL: "spotify.com", icon: "music.note",
                     amountMinor: 1099, currency: .eur, billingPeriod: .monthly,
                     paymentMethod: .paypal, usageState: .active, startDate: .now, sortOrder: 1),
        Subscription(name: "iCloud+", vendorURL: "icloud.com", icon: "icloud.fill",
                     amountMinor: 2999, currency: .eur, billingPeriod: .yearly,
                     paymentMethod: .applePay, usageState: .rarely, startDate: .now, sortOrder: 2),
    ]
    static let repository = InMemorySubscriptionRepository(seed: subscriptions)

    /// Stable expense categories (ADR-0022) — the normalized `categories` rows the
    /// sample fixed/variable expenses reference by id. The in-memory
    /// `CategoryRepository` returns these same rows so `categoryID → name`
    /// resolution works offline exactly as it will against Supabase.
    static let expenseCategories: [Domain.Category] = [
        Domain.Category(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!,
                        name: "Housing", slug: "housing", kind: .expense),
        Domain.Category(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C2")!,
                        name: "Groceries", slug: "groceries", kind: .expense),
        Domain.Category(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!,
                        name: "Transport", slug: "transport", kind: .expense),
        Domain.Category(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C4")!,
                        name: "Utilities", slug: "utilities", kind: .expense),
        Domain.Category(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C5")!,
                        name: "Entertainment", slug: "entertainment", kind: .expense),
    ]
}

// MARK: - Store (@Observable, MainActor) — docs/03 unidirectional MVVM

@MainActor
@Observable
final class SubscriptionsStore {
    private(set) var subscriptions: [Subscription] = []
    private(set) var isLoading = false
    private(set) var loadError: String?
    private let repository: SubscriptionRepository

    init(repository: SubscriptionRepository) { self.repository = repository }

    func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            subscriptions = try await repository.all()
        } catch {
            loadError = error.localizedDescription
        }
    }

    func add(_ subscription: Subscription) async {
        try? await repository.upsert(subscription)
        await load()
    }

    func delete(id: UUID) async {
        try? await repository.delete(id: id)
        await load()
    }

    /// Move within the current ordering (drag-to-reorder / .onMove) and persist
    /// the new `sortOrder` through the repository.
    func move(from offsets: IndexSet, to destination: Int) async {
        var ordered = subscriptions
        ordered.move(fromOffsets: offsets, toOffset: destination)
        await reorder(ordered.map(\.id))
    }

    func reorder(_ orderedIDs: [UUID]) async {
        try? await repository.reorder(orderedIDs)
        await load()
    }
}

// MARK: - Views

struct SubscriptionsListView: View {
    @Environment(\.repositories) private var repositories
    @Environment(PreferencesStore.self) private var preferences
    @State private var store = SubscriptionsStore(repository: SampleData.repository)
    @State private var didBind = false
    @State private var showingAdd = false
    @State private var showingAnalytics = false
    @State private var converter = CurrencyConverter(rates: AssetsSampleData.sampleRates)

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.subscriptions.isEmpty {
                    ScrollView { SkeletonList().padding() }
                } else if let error = store.loadError {
                    ScrollView {
                        ErrorStateCard(message: error) { Task { await store.load() } }
                            .padding()
                    }
                } else if store.subscriptions.isEmpty {
                    ContentUnavailableView {
                        Label("No subscriptions yet", systemImage: "creditcard")
                    } description: {
                        Text("Track your recurring charges to see spending by category.")
                    } actions: {
                        GlassButton("Add subscription", systemImage: "plus") { showingAdd = true }
                    }
                } else {
                    subscriptionsList
                }
            }
            .navigationTitle("Subscriptions")
            .navigationDestination(for: UUID.self) { id in
                if let sub = store.subscriptions.first(where: { $0.id == id }) {
                    SubscriptionDetailView(subscription: sub, store: store)
                } else {
                    // Deleted while pushed — show a graceful empty state.
                    ContentUnavailableView("Subscription removed", systemImage: "trash")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAnalytics = true } label: { Image(systemName: "chart.pie.fill") }
                        .accessibilityLabel("Spending analytics")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add subscription")
                        .accessibilityIdentifier("subscriptions.add")
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddSubscriptionView { newSub in Task { await store.add(newSub) } }
            }
            .sheet(isPresented: $showingAnalytics) {
                NavigationStack {
                    SubscriptionAnalyticsView(
                        subscriptions: store.subscriptions,
                        displayCurrency: preferences.preferences.defaultCurrency,
                        converter: converter)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showingAnalytics = false }
                            }
                        }
                }
            }
            .task {
                if !didBind {
                    store = SubscriptionsStore(repository: repositories.subscriptions)
                    if let rates = try? await repositories.exchangeRates.latestRates() {
                        converter = CurrencyConverter(rates: rates)
                    }
                    didBind = true
                }
                await store.load()
            }
            .background(FinmateBackground())
        }
    }

    private var subscriptionsList: some View {
        List {
            ForEach(store.subscriptions) { sub in
                NavigationLink(value: sub.id) {
                    SubscriptionRow(subscription: sub)
                }
                .accessibilityHint("Opens subscription details")
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await store.delete(id: sub.id) }
                    } label: { Label("Delete", systemImage: "trash") }
                    .accessibilityLabel("Delete \(sub.name)")
                    .accessibilityHint("Removes this subscription")
                }
            }
            .onMove { offsets, destination in
                Task { await store.move(from: offsets, to: destination) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

/// One subscription row — extracted so the list and (future) widgets share it.
struct SubscriptionRow: View {
    let subscription: Subscription
    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                Image(systemName: subscription.icon ?? "creditcard.fill")
                    .font(.title2).frame(minWidth: 34)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(subscription.name).font(.headline)
                    Text("\(subscription.billingPeriod.rawValue.capitalized) · \(subscription.usageState.rawValue.capitalized)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(subscription.monthlyAmount.formatted())
                        .font(.headline.monospacedDigit())
                    Text("/mo").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(subscription.name), \(subscription.monthlyAmount.formatted()) per month, \(subscription.billingPeriod.rawValue), \(subscription.usageState.rawValue)")
    }
}

/// Add sheet — demonstrates the ported prediction/category-inference engine:
/// typing a known name auto-fills the category (docs/13 §10).
struct AddSubscriptionView: View {
    var onSave: (Subscription) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amount = ""
    @State private var inferredCategory = "Other"
    @State private var amountError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Service") {
                    TextField("Name (e.g. Netflix, ChatGPT)", text: $name)
                        .accessibilityIdentifier("addSubscription.name")
                        .onChange(of: name) { _, newValue in
                            inferredCategory = SubscriptionPredictor.predict(name: newValue)?.category ?? "Other"
                        }
                    LabeledContent("Category (auto)", value: inferredCategory)
                }
                Section("Cost") {
                    TextField("Monthly amount in EUR", text: $amount)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("addSubscription.amount")
                    if let amountError {
                        Text(amountError).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.isEmpty)
                        .accessibilityIdentifier("addSubscription.save")
                }
            }
        }
    }

    private func save() {
        let raw = amount.trimmingCharacters(in: .whitespaces)
        let minor: Int64
        do {
            minor = raw.isEmpty ? 0 : try Money.parse(raw, currency: .eur).minorUnits
        } catch {
            amountError = "Enter a valid amount (max 2 decimals)."
            return
        }
        onSave(Subscription(
            name: name, amountMinor: minor, currency: .eur,
            billingPeriod: .monthly, usageState: .active, startDate: .now,
            sortOrder: Int.max
        ))
        dismiss()
    }
}
