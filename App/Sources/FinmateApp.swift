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

    /// Authentication session machine (docs/02 §1). Drives the signed-out / onboarding
    /// / root routing below; wraps the chosen `AuthRepository`.
    @State private var authStore: AuthStore

    /// First-run flag (docs/02 §2): true until onboarding completes for this install.
    @AppStorage("finmate.hasOnboarded") private var hasOnboarded = false

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {
        let repositories = RepositoryEnvironment.resolve()
        self.repositories = repositories
        let store = PreferencesStore(repository: repositories.preferences)
        _preferencesStore = State(initialValue: store)
        _appLock = State(initialValue: AppLockController(preferencesStore: store))
        _authStore = State(initialValue: AuthStore(repository: repositories.auth))

        // Test-only: UI smoke tests pass `-uiTestResetOnboarding` so each launch
        // starts from a clean first-run state regardless of persisted `@AppStorage`,
        // keeping the Auth → onboarding → Root flow deterministic. No effect on
        // normal launches (the arg is never set outside XCUITest).
        if ProcessInfo.processInfo.arguments.contains("-uiTestResetOnboarding") {
            UserDefaults.standard.set(false, forKey: "finmate.hasOnboarded")
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                rootContent
                    .environment(\.repositories, repositories)
                    .environment(preferencesStore)
                    .environment(\.authStore, authStore)
                if appLock.isLocked && authStore.state.isSignedIn {
                    AppLockOverlay(controller: appLock)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: appLock.isLocked)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: authStore.state)
            // App-wide BRONZE accent (Obsidian): drives Color.accentColor / `.tint`
            // everywhere — active nav/tab, selection, links, toggles, sliders.
            .tint(FinmateColor.bronze)
            .preferredColorScheme(preferencesStore.appearance.preferredColorScheme)
            .task {
                await preferencesStore.load()
                await authStore.start()
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

    /// Top-level routing (docs/02 §1–2):
    ///   • `.unknown`  → a neutral splash while the stored session resolves.
    ///   • `.signedOut` → `AuthView` (Apple / email-password / "Try the demo").
    ///   • signed in + first run → `OnboardingView`.
    ///   • signed in, onboarded → `RootView`.
    @ViewBuilder
    private var rootContent: some View {
        switch authStore.state {
        case .unknown:
            SplashView()
        case .signedOut:
            AuthView(store: authStore, isDemo: repositories.isDemo)
        case .signedIn:
            if hasOnboarded {
                RootView()
            } else {
                OnboardingView { hasOnboarded = true }
            }
        }
    }
}

/// Neutral launch placeholder shown while the stored session resolves (`.unknown`).
struct SplashView: View {
    var body: some View {
        ZStack {
            FinmateBackground()
            ProgressView().controlSize(.large)
        }
        .ignoresSafeArea()
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
    /// Semantic discipline: plain totals/balances stay neutral — only signed
    /// net/delta values colour (docs/06). Most cards leave this nil.
    let valueTint: Color?
    /// Optional tint for the `detail` line — used to colour a signed gain/loss
    /// delta (green/red) while the headline total stays neutral.
    var detailTint: Color? = nil
}

/// Owns the Home dashboard's layout + the computed KPI values. Unidirectional
/// MVVM (`@Observable`, `@MainActor`); persists layout edits via the repository.
@MainActor
@Observable
final class HomeStore {
    private(set) var layout: DashboardLayout = .defaults
    /// While true the dashboard is in reorder/hide edit mode.
    var isEditing: Bool = false

    /// App-wide display currency (Settings default) + the rate-backed converter.
    /// Every card amount is converted to this at read time (docs/13 §6/§7).
    var displayCurrency: CurrencyCode
    private let converter: CurrencyConverter

    private let repository: DashboardLayoutRepository

    init(repository: DashboardLayoutRepository,
         displayCurrency: CurrencyCode = .eur,
         converter: CurrencyConverter = CurrencyConverter(rates: AssetsSampleData.sampleRates)) {
        self.repository = repository
        self.displayCurrency = displayCurrency
        self.converter = converter
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
        CashFlow.subscriptionsMonthlyMinor(SampleData.subscriptions,
                                           displayCurrency: displayCurrency, converter: converter)
    }

    private var metrics: CashFlowMetrics {
        CashFlow.metrics(income: CashFlowSampleData.income,
                         fixed: CashFlowSampleData.fixedExpenses,
                         variable: CashFlowSampleData.variableExpenses,
                         subscriptionsMonthlyMinor: subscriptionsMonthlyMinor,
                         displayCurrency: displayCurrency, converter: converter)
    }

    private var portfolioValueMinor: Int64 {
        AssetValuation.portfolioValueMinor(AssetsSampleData.assets,
                                           displayCurrency: displayCurrency, converter: converter)
    }

    private var portfolioGainMinor: Int64 {
        AssetValuation.portfolioGainMinor(AssetsSampleData.assets,
                                          displayCurrency: displayCurrency, converter: converter)
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
                value: Money(minorUnits: subscriptionsMonthlyMinor, currency: displayCurrency).formatted(),
                detail: nil, valueTint: nil)
        case .netCashFlow:
            let net = metrics.netMinor
            return DashboardCardValue(
                title: id.title,
                value: Money(minorUnits: net, currency: displayCurrency).formatted(),
                detail: net >= 0 ? "Surplus this month" : "Shortfall this month",
                valueTint: net >= 0 ? FinmateColor.up : FinmateColor.down)
        case .savingsRate:
            let pct = Int((metrics.savingsRate * 100).rounded())
            return DashboardCardValue(
                title: id.title,
                value: "\(pct)%",
                detail: "of monthly income",
                valueTint: pct >= 0 ? nil : FinmateColor.down)
        case .portfolioValue:
            let gain = portfolioGainMinor
            let gainStr = Money(minorUnits: gain, currency: displayCurrency).formatted()
            return DashboardCardValue(
                title: id.title,
                value: Money(minorUnits: portfolioValueMinor, currency: displayCurrency).formatted(),
                detail: (gain >= 0 ? "+\(gainStr)" : gainStr) + " gain",
                // Total stays neutral; only the signed gain delta colours.
                valueTint: nil,
                detailTint: FinmateColor.sign(gain))
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
    @State private var didBind = false
    @Environment(\.repositories) private var repositories
    @Environment(PreferencesStore.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Namespace for the dashboard cards' Liquid Glass morph (read ⇄ edit mode).
    @Namespace private var glassNamespace

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
            .background(FinmateBackground())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(store.isEditing ? "Done" : "Edit") {
                        withAnimation(reduceMotion ? nil : FinmateMotion.glassSpring) {
                            store.isEditing.toggle()
                        }
                    }
                    .accessibilityHint(store.isEditing
                                       ? "Finish customizing the dashboard"
                                       : "Reorder or hide dashboard cards")
                }
            }
            .animation(reduceMotion ? nil : FinmateMotion.glassSpring, value: store.isEditing)
            .animation(reduceMotion ? nil : FinmateMotion.glassSpring, value: store.layout)
            .task {
                if !didBind {
                    let rates = (try? await repositories.exchangeRates.latestRates()) ?? AssetsSampleData.sampleRates
                    store = HomeStore(
                        repository: DashboardSampleData.repository,
                        displayCurrency: preferences.preferences.defaultCurrency,
                        converter: CurrencyConverter(rates: rates))
                    didBind = true
                }
                await store.load()
            }
            // App-wide display currency: recompute card values on Settings change.
            .onChange(of: preferences.preferences.defaultCurrency) { _, newValue in
                store.displayCurrency = newValue
            }
        }
    }

    // MARK: Read-only dashboard

    private var dashboard: some View {
        ScrollView {
            // Group the dashboard cards in one GlassEffectContainer so iOS 26 blends
            // the glass surfaces and the cards can MORPH (glassEffectID) when entering
            // / leaving edit-mode. No-op container ≤25. Spacing matches the VStack.
            FinmateGlassGroup(spacing: FinmateSpacing.md) {
                VStack(spacing: FinmateSpacing.md) {
                    ForEach(store.layout.cardOrder) { id in
                        DashboardCardView(value: store.value(for: id))
                            .finmateGlassMorph(id: id, in: glassNamespace,
                                               reduceMotion: reduceMotion)
                            .transition(.finmateRow)
                    }
                }
            }
            .padding()
        }
        .finmateScrollEdge()
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
            VStack(alignment: .leading, spacing: FinmateSpacing.sm) {
                Text(value.title)
                    .font(FinmateType.subheadline)
                    .foregroundStyle(FinmateColor.labelSecondary)
                Text(value.value)
                    .font(FinmateType.money(.largeTitle, weight: .bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(value.valueTint ?? Color.primary)
                    .contentTransition(.numericText())
                if let detail = value.detail {
                    Text(detail)
                        .font(FinmateType.footnote)
                        .foregroundStyle(value.detailTint ?? FinmateColor.labelSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = ["\(value.title), \(value.value)"]
        if let detail = value.detail { parts.append(detail) }
        return parts.joined(separator: ", ")
    }
}
