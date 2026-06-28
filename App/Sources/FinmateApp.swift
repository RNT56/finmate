import SwiftUI
import Domain

@main
struct FinmateApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
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
                                .contentTransition(.numericText())
                        }
                    }
                    GlassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Active services")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text("\(SampleData.subscriptions.count)")
                                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Finmate")
            .background(FinmateGradient())
        }
    }
}
