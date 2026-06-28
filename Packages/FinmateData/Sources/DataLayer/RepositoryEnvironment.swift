import Foundation
import Domain

// MARK: - RepositoryEnvironment (composition root — docs/03 §3)
//
// A bundle of the live repository protocol values the app injects through SwiftUI
// `Environment`. The app builds either:
//   • a Supabase-backed environment (`RepositoryEnvironment.live`) when a
//     `FinmateConfig` resolves (URL + anon key present), or
//   • an in-memory environment from the existing sample repos (built app-side,
//     using `RepositoryEnvironment(...)` directly), the default.
//
// Stores depend only on the Domain protocols here — they never see SupabaseClient.

public struct RepositoryEnvironment: Sendable {
    public let subscriptions: any SubscriptionRepository
    public let income: any IncomeRepository
    public let expenses: any ExpenseRepository
    public let assets: any AssetRepository
    public let preferences: any PreferencesRepository
    public let categories: any CategoryRepository
    public let exchangeRates: any ExchangeRateProvider
    /// The chosen authentication repository: Supabase-backed when configured,
    /// else the offline `DemoAuthRepository` ("Try the demo"). docs/07 §3.
    public let auth: any AuthRepository

    public init(
        subscriptions: any SubscriptionRepository,
        income: any IncomeRepository,
        expenses: any ExpenseRepository,
        assets: any AssetRepository,
        preferences: any PreferencesRepository,
        categories: any CategoryRepository,
        exchangeRates: any ExchangeRateProvider,
        auth: any AuthRepository = DemoAuthRepository()
    ) {
        self.subscriptions = subscriptions
        self.income = income
        self.expenses = expenses
        self.assets = assets
        self.preferences = preferences
        self.categories = categories
        self.exchangeRates = exchangeRates
        self.auth = auth
    }

    /// True when the offline demo auth path is active (no Supabase config) — the
    /// Auth screen surfaces the prominent "Try the demo" entry in this case.
    public var isDemo: Bool { auth is DemoAuthRepository }

    /// Build the Supabase-backed environment for a resolved config. The single
    /// `SupabaseClientProvider` (Keychain-backed auth storage) is shared by every
    /// repository so they reuse one authenticated client.
    public static func live(config: FinmateConfig) -> RepositoryEnvironment {
        let provider = SupabaseClientProvider(config: config)
        return RepositoryEnvironment(
            subscriptions: SupabaseSubscriptionRepository(provider: provider),
            income: SupabaseIncomeRepository(provider: provider),
            expenses: SupabaseExpenseRepository(provider: provider),
            assets: SupabaseAssetRepository(provider: provider),
            preferences: SupabasePreferencesRepository(provider: provider),
            categories: SupabaseCategoryRepository(provider: provider),
            exchangeRates: MarketDataRateProvider(provider: provider),
            auth: SupabaseAuthRepository(provider: provider)
        )
    }

    /// Resolve a live environment from the ambient config (Info.plist / env), or
    /// `nil` when no credentials are present (the caller then uses in-memory repos).
    public static func resolveLive() -> RepositoryEnvironment? {
        FinmateConfig.resolve().map(live(config:))
    }
}
