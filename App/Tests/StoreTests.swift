import Testing
import Foundation
import Domain
@testable import Finmate

// Store-layer unit tests (docs/09). The @Observable stores wire repository
// PROTOCOLS → UI; they are untested by the pure-Domain suite. These exercise the
// wiring: load (happy + empty), optimistic mutate + reload, ERROR capture (a
// throwing mock → `loadError`, happy path unaffected), reorder (subscriptions),
// and currency-recompute (changing `displayCurrency` recomputes the aggregates).
//
// Stores are @MainActor, so the suites are annotated @MainActor.

// MARK: - Throwing mock repos (prove error capture without breaking happy paths)

struct StoreTestError: Error, Equatable { let message: String }

/// Subscription repo whose reads throw — drives `SubscriptionsStore.load` into
/// the `loadError` branch.
struct ThrowingSubscriptionRepository: SubscriptionRepository {
    func all() async throws -> [Subscription] { throw StoreTestError(message: "subs boom") }
    func upsert(_ subscription: Subscription) async throws {}
    func delete(id: UUID) async throws {}
    func reorder(_ orderedIDs: [UUID]) async throws {}
}

struct ThrowingIncomeRepository: IncomeRepository {
    func all() async throws -> [IncomeSource] { throw StoreTestError(message: "income boom") }
    func upsert(_ income: IncomeSource) async throws {}
    func delete(id: UUID) async throws {}
}

struct ThrowingExpenseRepository: ExpenseRepository {
    func fixed() async throws -> [FixedExpense] { throw StoreTestError(message: "fixed boom") }
    func variable() async throws -> [VariableExpense] { throw StoreTestError(message: "var boom") }
    func upsertFixed(_ expense: FixedExpense) async throws {}
    func upsertVariable(_ expense: VariableExpense) async throws {}
    func deleteFixed(id: UUID) async throws {}
    func deleteVariable(id: UUID) async throws {}
}

struct ThrowingAssetRepository: AssetRepository {
    func all() async throws -> [FinancialAsset] { throw StoreTestError(message: "assets boom") }
    func transactions(assetID: UUID) async throws -> [AssetTransaction] { [] }
    func upsert(_ asset: FinancialAsset) async throws {}
    func delete(id: UUID) async throws {}
    func recordTransaction(_ transaction: AssetTransaction) async throws {}
}

/// A non-throwing category repo so CashFlowStore happy-path loads cleanly.
struct StubCategoryRepository: CategoryRepository {
    var rows: [Domain.Category] = []
    func categories(kind: CategoryKind) async throws -> [Domain.Category] { rows }
}

// Sample rates shared by the converter assertions (eurUsd 1.10).
private let testRates = ExchangeRates(
    eurUsd: Decimal(string: "1.10")!, btcEur: 50_000, btcUsd: 55_000, fetchedAt: .now)

// MARK: - SubscriptionsStore

@MainActor
@Suite struct SubscriptionsStoreTests {
    private func seeded() -> InMemorySubscriptionRepository {
        InMemorySubscriptionRepository(seed: [
            Subscription(name: "A", amountMinor: 1000, currency: .eur, billingPeriod: .monthly,
                         usageState: .active, startDate: .now, sortOrder: 0),
            Subscription(name: "B", amountMinor: 2000, currency: .eur, billingPeriod: .monthly,
                         usageState: .active, startDate: .now, sortOrder: 1),
        ])
    }

    @Test func loadPopulatesAndClearsError() async {
        let store = SubscriptionsStore(repository: seeded())
        await store.load()
        #expect(store.subscriptions.count == 2)
        #expect(store.loadError == nil)
        #expect(store.isLoading == false)
    }

    @Test func loadEmptyRepoYieldsEmpty() async {
        let store = SubscriptionsStore(repository: InMemorySubscriptionRepository(seed: []))
        await store.load()
        #expect(store.subscriptions.isEmpty)
        #expect(store.loadError == nil)
    }

    @Test func addThenReloadAppendsRow() async {
        let store = SubscriptionsStore(repository: seeded())
        await store.load()
        await store.add(Subscription(name: "C", amountMinor: 500, currency: .eur,
                                     billingPeriod: .monthly, usageState: .active,
                                     startDate: .now, sortOrder: 2))
        #expect(store.subscriptions.count == 3)
        #expect(store.subscriptions.contains { $0.name == "C" })
    }

    @Test func deleteRemovesRow() async {
        let store = SubscriptionsStore(repository: seeded())
        await store.load()
        let id = try! #require(store.subscriptions.first).id
        await store.delete(id: id)
        #expect(store.subscriptions.count == 1)
        #expect(!store.subscriptions.contains { $0.id == id })
    }

    @Test func reorderPersistsNewSortOrder() async {
        let store = SubscriptionsStore(repository: seeded())
        await store.load()
        let reversed = store.subscriptions.reversed().map(\.id)
        await store.reorder(Array(reversed))
        // The repo sorts by sortOrder; the previously-last row is now first.
        #expect(store.subscriptions.map(\.id) == Array(reversed))
    }

    @Test func loadErrorCaptured() async {
        let store = SubscriptionsStore(repository: ThrowingSubscriptionRepository())
        await store.load()
        #expect(store.loadError != nil)
        #expect(store.subscriptions.isEmpty)
        #expect(store.isLoading == false)
    }
}

// MARK: - CashFlowStore

@MainActor
@Suite struct CashFlowStoreTests {
    private func happyStore(displayCurrency: CurrencyCode = .eur) -> CashFlowStore {
        CashFlowStore(
            incomeRepository: InMemoryIncomeRepository(seed: [
                IncomeSource(name: "Salary", amountMinor: 300_000, currency: .eur,
                             frequency: .monthly, nextPayment: .now),
            ]),
            expenseRepository: InMemoryExpenseRepository(
                fixedSeed: [FixedExpense(name: "Rent", amountMinor: 100_000, currency: .eur,
                                         categoryID: nil, frequency: .monthly, dueDate: .now, autopay: true)],
                variableSeed: [VariableExpense(name: "Food", amountMinor: 20_000, currency: .eur,
                                               categoryID: nil, date: .now)]),
            categoryRepository: StubCategoryRepository(),
            subscriptions: [],
            displayCurrency: displayCurrency,
            converter: CurrencyConverter(rates: testRates))
    }

    @Test func loadPopulatesAllSections() async {
        let store = happyStore()
        await store.load()
        #expect(store.income.count == 1)
        #expect(store.fixedExpenses.count == 1)
        #expect(store.variableExpenses.count == 1)
        #expect(store.loadError == nil)
        #expect(store.hasLoaded)
    }

    @Test func emptyRepoIsEmptyAfterLoad() async {
        let store = CashFlowStore(
            incomeRepository: InMemoryIncomeRepository(seed: []),
            expenseRepository: InMemoryExpenseRepository(fixedSeed: [], variableSeed: []),
            categoryRepository: StubCategoryRepository(),
            subscriptions: [],
            converter: CurrencyConverter(rates: testRates))
        await store.load()
        #expect(store.isEmpty)
        #expect(store.loadError == nil)
    }

    @Test func metricsReflectIncomeAndExpenses() async {
        let store = happyStore()
        await store.load()
        // income 3000 EUR, expenses 1000 (fixed) + 200 (variable) = 1200 EUR.
        #expect(store.metrics.incomeMinor == 300_000)
        #expect(store.metrics.expenseMinor == 120_000)
        #expect(store.net.minorUnits == 180_000)
    }

    @Test func addIncomeFixedVariableRecompute() async {
        let store = happyStore()
        await store.load()
        await store.addIncome(IncomeSource(name: "Bonus", amountMinor: 50_000, currency: .eur,
                                           frequency: .monthly, nextPayment: .now))
        #expect(store.metrics.incomeMinor == 350_000)
        await store.addFixed(FixedExpense(name: "Gym", amountMinor: 5_000, currency: .eur,
                                          categoryID: nil, frequency: .monthly, dueDate: .now, autopay: false))
        await store.addVariable(VariableExpense(name: "Taxi", amountMinor: 3_000, currency: .eur,
                                                categoryID: nil, date: .now))
        #expect(store.metrics.expenseMinor == 128_000)
    }

    @Test func currencyRecomputeChangesConvertedKPIs() async {
        let store = happyStore(displayCurrency: .eur)
        await store.load()
        let eurIncome = store.monthlyIncome.minorUnits
        store.displayCurrency = .usd
        let usdIncome = store.monthlyIncome.minorUnits
        // EUR→USD at 1.10 ⇒ converted income is strictly larger and in USD.
        #expect(store.monthlyIncome.currency == .usd)
        #expect(usdIncome > eurIncome)
        #expect(usdIncome == 330_000) // 300_000 * 1.10
    }

    @Test func loadErrorCaptured() async {
        let store = CashFlowStore(
            incomeRepository: ThrowingIncomeRepository(),
            expenseRepository: ThrowingExpenseRepository(),
            categoryRepository: StubCategoryRepository(),
            subscriptions: [],
            converter: CurrencyConverter(rates: testRates))
        await store.load()
        #expect(store.loadError != nil)
        #expect(store.income.isEmpty)
        #expect(store.hasLoaded)
    }
}

// MARK: - AssetsStore

@MainActor
@Suite struct AssetsStoreTests {
    private func seededRepo() -> InMemoryAssetRepository {
        let btc = FinancialAsset(name: "BTC", type: .crypto, currency: .eur,
                                 quantity: Decimal(string: "0.5")!,
                                 purchasePriceMinor: 2_000_000, currentPriceMinor: 5_000_000,
                                 valueMinor: 2_500_000)
        return InMemoryAssetRepository(seed: [btc], transactions: [:])
    }

    @Test func loadPopulates() async {
        let store = AssetsStore(repository: seededRepo(), rates: testRates)
        await store.load()
        #expect(store.assets.count == 1)
        #expect(store.loadError == nil)
        #expect(store.hasLoaded)
    }

    @Test func emptyRepoLoadsEmpty() async {
        let store = AssetsStore(repository: InMemoryAssetRepository(seed: [], transactions: [:]),
                                rates: testRates)
        await store.load()
        #expect(store.assets.isEmpty)
        #expect(store.loadError == nil)
    }

    @Test func addAndEditAsset() async {
        let store = AssetsStore(repository: InMemoryAssetRepository(seed: [], transactions: [:]),
                                rates: testRates)
        await store.load()
        var asset = FinancialAsset(name: "Cash", type: .cash, currency: .eur, quantity: 1,
                                   purchasePriceMinor: 100_000, currentPriceMinor: 100_000,
                                   valueMinor: 100_000)
        await store.addAsset(asset)
        #expect(store.assets.count == 1)
        asset.name = "Savings"
        await store.updateAsset(asset)
        #expect(store.assets.first?.name == "Savings")
    }

    @Test func recordTransactionRecomputesValuation() async {
        let asset = FinancialAsset(name: "ETF", type: .etf, currency: .eur, quantity: 0,
                                   purchasePriceMinor: 0, currentPriceMinor: 20_000, valueMinor: 0)
        let store = AssetsStore(repository: InMemoryAssetRepository(seed: [asset], transactions: [:]),
                                rates: testRates)
        await store.load()
        let txn = AssetTransaction(assetID: asset.id, kind: .buy, quantity: 10,
                                   priceMinor: 15_000, feesMinor: 0, date: .now)
        let updated = await store.recordTransaction(txn, for: asset)
        // 10 units bought; quantity + value recompute off the history.
        #expect(updated != nil)
        #expect(store.assets.first?.quantity == 10)
        #expect((store.assets.first?.valueMinor ?? 0) > 0)
    }

    @Test func currencyRecomputeChangesPortfolioValue() async {
        let store = AssetsStore(repository: seededRepo(), rates: testRates, displayCurrency: .eur)
        await store.load()
        let eurValue = store.portfolioValue.minorUnits
        store.displayCurrency = .usd
        #expect(store.portfolioValue.currency == .usd)
        #expect(store.portfolioValue.minorUnits != eurValue)
    }

    @Test func loadErrorCaptured() async {
        let store = AssetsStore(repository: ThrowingAssetRepository(), rates: testRates)
        await store.load()
        #expect(store.loadError != nil)
        #expect(store.assets.isEmpty)
        #expect(store.hasLoaded)
    }
}
