import SwiftUI
import Domain
import DataLayer

// MARK: - Composition root (docs/03 §3) — config-driven repo selection
//
// Resolves a `RepositoryEnvironment`:
//   • Supabase-backed when `FinmateConfig` resolves (SUPABASE_URL + SUPABASE_ANON_KEY
//     present in Info.plist/env), per ADR-0006.
//   • the existing in-memory sample repos otherwise (the default — keeps previews,
//     offline runs, and this build green with no credentials).
//
// The chosen environment is injected through SwiftUI `Environment` so feature
// Stores receive repository PROTOCOL values and never see SupabaseClient.

extension RepositoryEnvironment {
    /// The in-memory sample environment (Subscriptions/Income/Expense/Asset +
    /// in-memory Preferences + sample rates). Mirrors today's hard-coded defaults.
    static func inMemorySample() -> RepositoryEnvironment {
        RepositoryEnvironment(
            subscriptions: SampleData.repository,
            income: CashFlowSampleData.incomeRepository,
            expenses: CashFlowSampleData.expenseRepository,
            assets: AssetsSampleData.repository,
            preferences: InMemoryPreferencesRepository(),
            categories: InMemoryCategoryRepository(),
            exchangeRates: SampleRateProvider()
        )
    }

    /// Supabase when credentials resolve, else the in-memory sample environment.
    static func resolve() -> RepositoryEnvironment {
        resolveLive() ?? inMemorySample()
    }
}

// MARK: - In-memory CategoryRepository + ExchangeRateProvider (App-side samples)

/// In-memory categories so the app has a non-Supabase `CategoryRepository`
/// implementation behind the same protocol (the live one lives in DataLayer).
actor InMemoryCategoryRepository: CategoryRepository {
    func categories(kind: CategoryKind) async throws -> [Domain.Category] {
        switch kind {
        case .subscription:
            return [
                Domain.Category(name: "Entertainment", slug: "entertainment", kind: .subscription),
                Domain.Category(name: "Productivity", slug: "productivity", kind: .subscription),
                Domain.Category(name: "Other", slug: "other", kind: .subscription, isProtected: true),
            ]
        case .expense:
            return [
                Domain.Category(name: "Housing", slug: "housing", kind: .expense),
                Domain.Category(name: "Food", slug: "food", kind: .expense),
                Domain.Category(name: "Other", slug: "other", kind: .expense, isProtected: true),
            ]
        }
    }
}

/// Sample `ExchangeRateProvider` returning the same fixed rates the UI uses today
/// (the live `MarketDataRateProvider` lives in DataLayer).
struct SampleRateProvider: ExchangeRateProvider {
    func latestRates() async throws -> ExchangeRates { AssetsSampleData.sampleRates }
}

// MARK: - SwiftUI Environment plumbing

private struct RepositoryEnvironmentKey: EnvironmentKey {
    static let defaultValue: RepositoryEnvironment = .inMemorySample()
}

extension EnvironmentValues {
    /// The injected repository environment. Defaults to in-memory so previews and
    /// any unconfigured build keep working.
    var repositories: RepositoryEnvironment {
        get { self[RepositoryEnvironmentKey.self] }
        set { self[RepositoryEnvironmentKey.self] = newValue }
    }
}
