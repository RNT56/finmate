import SwiftUI
import Domain
import DataLayer

@main
struct FinmateApp: App {
    /// Config-driven repository environment (Supabase when SUPABASE_URL +
    /// SUPABASE_ANON_KEY resolve, else the in-memory sample repos — docs/03 §3).
    private let repositories: RepositoryEnvironment

    /// App-root preferences store (M7). Owns appearance + display-currency +
    /// reminder/biometric prefs and drives `.preferredColorScheme` app-wide.
    /// Built from the chosen environment's `PreferencesRepository`.
    @State private var preferencesStore: PreferencesStore

    /// Biometric app-lock runtime (docs/07). No-op when the toggle is off (default).
    @State private var appLock: AppLockController

    @Environment(\.scenePhase) private var scenePhase

    init() {
        let repositories = RepositoryEnvironment.resolve()
        self.repositories = repositories
        let store = PreferencesStore(repository: repositories.preferences)
        _preferencesStore = State(initialValue: store)
        _appLock = State(initialValue: AppLockController(preferencesStore: store))
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environment(\.repositories, repositories)
                    .environment(preferencesStore)
                if appLock.isLocked {
                    AppLockOverlay(controller: appLock)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: appLock.isLocked)
            .preferredColorScheme(preferencesStore.appearance.preferredColorScheme)
            .task {
                await preferencesStore.load()
                // Lock on launch if the preference is enabled (after prefs load).
                appLock.start()
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:     appLock.didBecomeActive()
                case .inactive, .background: appLock.lockForBackground()
                @unknown default: break
                }
            }
        }
    }
}

/// Root tab navigation (docs/02 IA): Home · Subscriptions · Cash Flow · Calendar · More.
struct RootView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            SubscriptionsListView()
                .tabItem { Label("Subscriptions", systemImage: "creditcard.fill") }
            CashFlowView()
                .tabItem { Label("Cash Flow", systemImage: "chart.line.uptrend.xyaxis") }
            CalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
        }
    }
}

// MARK: - Home dashboard (M7-HOME, docs/02 §3) — customizable, reorderable cards
//
// The Home tab renders a user-ordered set of glass KPI cards. The order/visibility
// lives in a `DashboardLayout` persisted through a `DashboardLayoutRepository`
// (in-memory today; the `dashboard_layouts.card_order text[]` table, docs/05 §3.11,
// is the eventual store). Each card's value is computed from the existing sample
// data through the Domain money math (no Double).

/// One card's computed display values, derived from the sample/live data.
struct DashboardCardValue {
    let title: String
    let value: String
    /// Optional secondary line (e.g. a gain or a count detail).
    let detail: String?
    /// Optional tint for the value (gains green, losses red); nil = primary.
    let valueTint: Color?
}

/// Owns the Home dashboard's layout + the computed KPI values. Unidirectional
/// MVVM (`@Observable`, `@MainActor`); persists layout edits via the repository.
@MainActor
@Observable
final class HomeStore {
    private(set) var layout: DashboardLayout = .defaults
    /// While true the dashboard is in reorder/hide edit mode.
    var isEditing: Bool = false

    private let repository: DashboardLayoutRepository

    init(repository: DashboardLayoutRepository) {
        self.repository = repository
    }

    func load() async {
        layout = (try? await repository.load()) ?? .defaults
    }

    private func persist() {
        let layout = self.layout
        Task { try? await repository.save(layout) }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        layout.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    func setVisible(_ id: DashboardCardID, _ visible: Bool) {
        layout.setVisible(id, visible)
        persist()
    }

    // MARK: Computed KPI values (from the sample data, via Domain math)

    private var subscriptionsMonthlyMinor: Int64 {
        SampleData.subscriptions
            .filter { $0.currency == .eur }
            .reduce(Int64(0)) { $0 + $1.monthlyAmount.minorUnits }
    }

    private var metrics: CashFlowMetrics {
        CashFlow.metrics(income: CashFlowSampleData.income,
                         fixed: CashFlowSampleData.fixedExpenses,
                         variable: CashFlowSampleData.variableExpenses,
                         subscriptionsMonthlyMinor: subscriptionsMonthlyMinor)
    }

    private var portfolioValueMinor: Int64 {
        AssetsSampleData.assets.reduce(Int64(0)) { $0 + $1.valueMinor }
    }

    private var portfolioGainMinor: Int64 {
        AssetsSampleData.assets.reduce(Int64(0)) { $0 + AssetValuation.unrealizedGainMinor($1) }
    }

    private var upcomingChargesCount: Int {
        let calendar = Calendar.current
        let window = DateWindow.month(containing: .now, calendar: calendar)
        let events = PaydayCalendar.events(
            in: window,
            incomes: [],
            subscriptions: SampleData.subscriptions,
            fixedExpenses: CashFlowSampleData.fixedExpenses,
            calendar: calendar)
        let today = calendar.startOfDay(for: .now)
        return events.filter { $0.date >= today }.count
    }

    /// The display values for a card id.
    func value(for id: DashboardCardID) -> DashboardCardValue {
        switch id {
        case .monthlySubscriptions:
            return DashboardCardValue(
                title: id.title,
                value: Money(minorUnits: subscriptionsMonthlyMinor, currency: .eur).formatted(),
                detail: nil, valueTint: nil)
        case .netCashFlow:
            let net = metrics.netMinor
            return DashboardCardValue(
                title: id.title,
                value: Money(minorUnits: net, currency: .eur).formatted(),
                detail: net >= 0 ? "Surplus this month" : "Shortfall this month",
                valueTint: net >= 0 ? .green : .red)
        case .savingsRate:
            let pct = Int((metrics.savingsRate * 100).rounded())
            return DashboardCardValue(
                title: id.title,
                value: "\(pct)%",
                detail: "of monthly income",
                valueTint: pct >= 0 ? nil : .red)
        case .portfolioValue:
            let gain = portfolioGainMinor
            let gainStr = Money(minorUnits: gain, currency: .eur).formatted()
            return DashboardCardValue(
                title: id.title,
                value: Money(minorUnits: portfolioValueMinor, currency: .eur).formatted(),
                detail: (gain >= 0 ? "+\(gainStr)" : gainStr) + " gain",
                valueTint: nil)
        case .upcomingCharges:
            let count = upcomingChargesCount
            return DashboardCardValue(
                title: id.title,
                value: "\(count)",
                detail: count == 1 ? "charge remaining this month" : "charges remaining this month",
                valueTint: nil)
        case .activeServices:
            let active = SampleData.subscriptions.filter { $0.usageState == .active }.count
            return DashboardCardValue(
                title: id.title,
                value: "\(SampleData.subscriptions.count)",
                detail: "\(active) active",
                valueTint: nil)
        }
    }
}

/// In-memory `DashboardLayoutRepository` instance shared by the Home tab (the
/// `dashboard_layouts` table is the eventual store — docs/05 §3.11).
enum DashboardSampleData {
    static let repository = InMemoryDashboardLayoutRepository()
}

/// The customizable Home dashboard. Renders cards in `card_order`; an Edit toolbar
/// toggle enables drag-to-reorder (`.onMove`) and show/hide. Reduce-motion friendly.
struct HomeView: View {
    @State private var store = HomeStore(repository: DashboardSampleData.repository)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            Group {
                if store.isEditing {
                    editList
                } else {
                    dashboard
                }
            }
            .navigationTitle("Finmate")
            .background(FinmateGradient())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(store.isEditing ? "Done" : "Edit") {
                        store.isEditing.toggle()
                    }
                    .accessibilityHint(store.isEditing
                                       ? "Finish customizing the dashboard"
                                       : "Reorder or hide dashboard cards")
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.isEditing)
            .animation(reduceMotion ? nil : .default, value: store.layout)
            .task { await store.load() }
        }
    }

    // MARK: Read-only dashboard

    private var dashboard: some View {
        ScrollView {
            VStack(spacing: FinmateTokens.spacing) {
                ForEach(store.layout.cardOrder) { id in
                    DashboardCardView(value: store.value(for: id))
                }
            }
            .padding()
        }
    }

    // MARK: Edit mode — reorder (.onMove) + show/hide

    private var editList: some View {
        List {
            Section("Shown") {
                ForEach(store.layout.cardOrder) { id in
                    HStack {
                        Text(id.title)
                        Spacer()
                        Button {
                            store.setVisible(id, false)
                        } label: {
                            Image(systemName: "eye.slash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Hide \(id.title)")
                    }
                }
                .onMove { source, destination in
                    store.move(fromOffsets: source, toOffset: destination)
                }
                if store.layout.cardOrder.isEmpty {
                    Text("No cards shown — add some below.")
                        .foregroundStyle(.secondary)
                }
            }
            if !store.layout.hidden.isEmpty {
                Section("Hidden") {
                    ForEach(store.layout.hidden) { id in
                        HStack {
                            Text(id.title).foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                store.setVisible(id, true)
                            } label: {
                                Image(systemName: "eye")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Show \(id.title)")
                        }
                    }
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
    }
}

/// Renders a single dashboard KPI as a glass card.
struct DashboardCardView: View {
    let value: DashboardCardValue

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(value.title)
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(value.value)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(value.valueTint ?? .primary)
                    .contentTransition(.numericText())
                if let detail = value.detail {
                    Text(detail)
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
