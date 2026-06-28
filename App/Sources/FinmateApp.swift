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

    init() {
        let repositories = RepositoryEnvironment.resolve()
        self.repositories = repositories
        _preferencesStore = State(initialValue: PreferencesStore(repository: repositories.preferences))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.repositories, repositories)
                .environment(preferencesStore)
                .preferredColorScheme(preferencesStore.appearance.preferredColorScheme)
                .task { await preferencesStore.load() }
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

/// Overview dashboard card — computes the real monthly EUR subscription total
/// through the Domain money/normalization math (no Double).
struct HomeView: View {
    private var monthlyEUR: Money {
        let minor = SampleData.subscriptions
            .filter { $0.currency == .eur }
            .reduce(Int64(0)) { $0 + $1.monthlyAmount.minorUnits }
        return Money(minorUnits: minor, currency: .eur)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FinmateTokens.spacing) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Monthly subscriptions")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text(monthlyEUR.formatted())
                                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                                .minimumScaleFactor(0.6)
                                .contentTransition(.numericText())
                        }
                    }
                    .accessibilityElement(children: .combine)
                    GlassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Active services")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text("\(SampleData.subscriptions.count)")
                                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                .padding()
            }
            .navigationTitle("Finmate")
            .background(FinmateGradient())
        }
    }
}
