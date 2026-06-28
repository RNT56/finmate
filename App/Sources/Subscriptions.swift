import SwiftUI
import Observation
import Domain

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
}

// MARK: - Store (@Observable, MainActor) — docs/03 unidirectional MVVM

@MainActor
@Observable
final class SubscriptionsStore {
    private(set) var subscriptions: [Subscription] = []
    private let repository: SubscriptionRepository

    init(repository: SubscriptionRepository) { self.repository = repository }

    func load() async { subscriptions = (try? await repository.all()) ?? [] }

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
    @State private var store = SubscriptionsStore(repository: SampleData.repository)
    @State private var showingAdd = false
    @State private var showingAnalytics = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.subscriptions) { sub in
                    NavigationLink(value: sub.id) {
                        SubscriptionRow(subscription: sub)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await store.delete(id: sub.id) }
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
                .onMove { offsets, destination in
                    Task { await store.move(from: offsets, to: destination) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
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
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddSubscriptionView { newSub in Task { await store.add(newSub) } }
            }
            .sheet(isPresented: $showingAnalytics) {
                NavigationStack {
                    SubscriptionAnalyticsView(subscriptions: store.subscriptions)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showingAnalytics = false }
                            }
                        }
                }
            }
            .task { await store.load() }
            .background(FinmateGradient())
        }
    }
}

/// One subscription row — extracted so the list and (future) widgets share it.
struct SubscriptionRow: View {
    let subscription: Subscription
    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                Image(systemName: subscription.icon ?? "creditcard.fill")
                    .font(.title2).frame(width: 34)
                    .foregroundStyle(.tint)
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
                        .onChange(of: name) { _, newValue in
                            inferredCategory = SubscriptionPredictor.predict(name: newValue)?.category ?? "Other"
                        }
                    LabeledContent("Category (auto)", value: inferredCategory)
                }
                Section("Cost") {
                    TextField("Monthly amount in EUR", text: $amount)
                        .keyboardType(.decimalPad)
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
                    Button("Save", action: save).disabled(name.isEmpty)
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
