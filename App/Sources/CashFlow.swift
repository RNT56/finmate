import SwiftUI
import Charts
import Observation
import Domain
import DataLayer

// MARK: - DataLayer (in-memory) — docs/03 §3. Income + expense repositories behind
// the Domain protocols; the Supabase-backed implementations swap in behind the seam.

actor InMemoryIncomeRepository: IncomeRepository {
    private var store: [UUID: IncomeSource]
    init(seed: [IncomeSource]) {
        store = Dictionary(uniqueKeysWithValues: seed.map { ($0.id, $0) })
    }
    func all() async throws -> [IncomeSource] {
        store.values.sorted { $0.monthlyMinor > $1.monthlyMinor }
    }
    func upsert(_ income: IncomeSource) async throws { store[income.id] = income }
    func delete(id: UUID) async throws { store[id] = nil }
}

actor InMemoryExpenseRepository: ExpenseRepository {
    private var fixedStore: [UUID: FixedExpense]
    private var variableStore: [UUID: VariableExpense]
    init(fixedSeed: [FixedExpense], variableSeed: [VariableExpense]) {
        fixedStore = Dictionary(uniqueKeysWithValues: fixedSeed.map { ($0.id, $0) })
        variableStore = Dictionary(uniqueKeysWithValues: variableSeed.map { ($0.id, $0) })
    }
    func fixed() async throws -> [FixedExpense] {
        fixedStore.values.sorted { $0.monthlyMinor > $1.monthlyMinor }
    }
    func variable() async throws -> [VariableExpense] {
        variableStore.values.sorted { $0.date > $1.date }
    }
    func upsertFixed(_ expense: FixedExpense) async throws { fixedStore[expense.id] = expense }
    func upsertVariable(_ expense: VariableExpense) async throws { variableStore[expense.id] = expense }
    func deleteFixed(id: UUID) async throws { fixedStore[id] = nil }
    func deleteVariable(id: UUID) async throws { variableStore[id] = nil }
}

// MARK: - Sample data (matches the web client so the displayed figures agree)

enum CashFlowSampleData {
    // Anchor dates (nextPayment / dueDate) drive the M4 payday-calendar markers;
    // they don't affect the M2 cash-flow metrics (those use frequency + amount only).
    private static func dayOfThisMonth(_ day: Int) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month], from: .now)
        comps.day = day
        return cal.date(from: comps) ?? .now
    }

    static let income: [IncomeSource] = [
        IncomeSource(name: "Salary", amountMinor: 320_000, currency: .eur, frequency: .monthly, nextPayment: dayOfThisMonth(15)),
        IncomeSource(name: "Freelance", amountMinor: 60_000, currency: .eur, frequency: .monthly, nextPayment: dayOfThisMonth(25)),
    ]
    static let fixedExpenses: [FixedExpense] = [
        FixedExpense(name: "Rent", amountMinor: 110_000, currency: .eur, category: "Housing", frequency: .monthly, dueDate: dayOfThisMonth(1), autopay: true),
        FixedExpense(name: "Insurance", amountMinor: 9_000, currency: .eur, category: "Insurance", frequency: .monthly, dueDate: dayOfThisMonth(5), autopay: true),
    ]
    static let variableExpenses: [VariableExpense] = [
        VariableExpense(name: "Groceries", amountMinor: 40_000, currency: .eur, category: "Food", date: .now),
    ]
    static let incomeRepository = InMemoryIncomeRepository(seed: income)
    static let expenseRepository = InMemoryExpenseRepository(fixedSeed: fixedExpenses, variableSeed: variableExpenses)
}

// MARK: - Store (@Observable, MainActor) — docs/03 unidirectional MVVM

@MainActor
@Observable
final class CashFlowStore {
    private(set) var income: [IncomeSource] = []
    private(set) var fixedExpenses: [FixedExpense] = []
    private(set) var variableExpenses: [VariableExpense] = []

    private let incomeRepository: IncomeRepository
    private let expenseRepository: ExpenseRepository
    /// Subscriptions feed the expense roll-up; their monthly-equivalent total in EUR
    /// is computed once via the Domain math (matches the Home card).
    private let subscriptionsMonthlyMinor: Int64
    private let displayCurrency: CurrencyCode = .eur

    init(incomeRepository: IncomeRepository,
         expenseRepository: ExpenseRepository,
         subscriptions: [Subscription]) {
        self.incomeRepository = incomeRepository
        self.expenseRepository = expenseRepository
        self.subscriptionsMonthlyMinor = subscriptions
            .filter { $0.currency == .eur }
            .reduce(Int64(0)) { $0 + $1.monthlyAmount.minorUnits }
    }

    func load() async {
        income = (try? await incomeRepository.all()) ?? []
        fixedExpenses = (try? await expenseRepository.fixed()) ?? []
        variableExpenses = (try? await expenseRepository.variable()) ?? []
    }

    /// The signed cash-flow metrics for the current month (docs/13 §6).
    var metrics: CashFlowMetrics {
        CashFlow.metrics(income: income, fixed: fixedExpenses, variable: variableExpenses,
                         subscriptionsMonthlyMinor: subscriptionsMonthlyMinor)
    }

    var monthlyIncome: Money { Money(minorUnits: metrics.incomeMinor, currency: displayCurrency) }
    var monthlyExpenses: Money { Money(minorUnits: metrics.expenseMinor, currency: displayCurrency) }
    var net: Money { Money(minorUnits: metrics.netMinor, currency: displayCurrency) }

    var variableThisMonthMinor: Int64 {
        CashFlow.variableThisMonthMinor(variableExpenses)
    }

    /// The bucketed money-flow for the headline Sankey (docs/13 §6.5, ADR-0016):
    /// Income → Fixed / Variable / Subscriptions / Savings (savings clamped ≥ 0).
    var moneyFlow: MoneyFlow {
        let fixedMonthly = fixedExpenses.reduce(Int64(0)) { $0 + $1.monthlyMinor }
        return MoneyFlow(
            incomeMinor: metrics.incomeMinor,
            fixedMinor: fixedMonthly,
            variableMinor: variableThisMonthMinor,
            subscriptionsMinor: subscriptionsMonthlyMinor
        )
    }

    /// Expense category breakdown (fixed normalized monthly + this-month variable +
    /// subscriptions bucket) via the Domain distribution aggregator (docs/13 §5.1).
    var expenseSlices: [CategorySlice] {
        var rows: [(category: String, amountMinor: Int64)] = fixedExpenses.map {
            ($0.category ?? "Other", $0.monthlyMinor)
        }
        for ve in variableExpenses where Calendar.current.isDate(ve.date, equalTo: .now, toGranularity: .month) {
            rows.append((ve.category ?? "Other", ve.amountMinor))
        }
        if subscriptionsMonthlyMinor > 0 {
            rows.append(("Subscriptions", subscriptionsMonthlyMinor))
        }
        return Analytics.categoryDistribution(rows)
    }
}

// MARK: - View

struct CashFlowView: View {
    @Environment(\.repositories) private var repositories
    @State private var store = CashFlowStore(
        incomeRepository: CashFlowSampleData.incomeRepository,
        expenseRepository: CashFlowSampleData.expenseRepository,
        subscriptions: SampleData.subscriptions
    )
    @State private var didBind = false

    private let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .green, .indigo, .mint]
    private func color(for index: Int) -> Color { palette[index % palette.count] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FinmateTokens.spacing) {
                    moneyFlowCard
                    kpiGrid
                    incomeVsExpensesCard
                    if !store.expenseSlices.isEmpty { expenseBreakdownCard }
                }
                .padding()
            }
            .navigationTitle("Cash Flow")
            .background(FinmateGradient())
            .task {
                if !didBind {
                    // Subscriptions feed the expense roll-up; fetch them from the
                    // injected repo so the bucket matches the Subscriptions tab.
                    let subs = (try? await repositories.subscriptions.all()) ?? SampleData.subscriptions
                    store = CashFlowStore(
                        incomeRepository: repositories.income,
                        expenseRepository: repositories.expenses,
                        subscriptions: subs
                    )
                    didBind = true
                }
                await store.load()
            }
        }
    }

    // MARK: Money flow (headline Sankey — M3, docs/14 §11)

    private var moneyFlowCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Money flow").font(.headline)
                    Spacer()
                    Text("This month").font(.caption).foregroundStyle(.secondary)
                }
                MoneyFlowView(flow: store.moneyFlow)
                flowLegend
            }
        }
    }

    private var flowLegend: some View {
        let items: [(String, Int64, Color)] = [
            ("Fixed", store.moneyFlow.fixedMinor, .red),
            ("Variable", store.moneyFlow.variableMinor, .orange),
            ("Subscriptions", store.moneyFlow.subscriptionsMinor, .purple),
            ("Savings", store.moneyFlow.savingsMinor, .green),
        ].filter { $0.1 > 0 }
        return FlowWrap(items: items)
    }

    // MARK: KPI cards (docs/02 §5.3 metric set)

    private var kpiGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: FinmateTokens.spacing) {
            KPICard(title: "Monthly Income", value: store.monthlyIncome.formatted(),
                    symbol: "arrow.down.circle.fill", tint: .green)
            KPICard(title: "Monthly Expenses", value: store.monthlyExpenses.formatted(),
                    symbol: "arrow.up.circle.fill", tint: .orange)
            KPICard(title: "Net", value: store.net.formatted(),
                    symbol: "equal.circle.fill", tint: store.metrics.netMinor >= 0 ? .blue : .red)
            KPICard(title: "Savings rate", value: savingsRateText,
                    symbol: "percent", tint: store.metrics.savingsRate >= 0 ? .teal : .red)
        }
    }

    private var savingsRateText: String {
        let pct = store.metrics.savingsRate * 100
        return "\(Int(pct.rounded()))%"
    }

    // MARK: Income vs expenses chart

    private var incomeVsExpensesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Income vs expenses").font(.headline)
                Chart {
                    BarMark(x: .value("Kind", "Income"),
                            y: .value("Amount", (store.monthlyIncome.decimalValue as NSDecimalNumber).doubleValue))
                        .foregroundStyle(.green)
                        .annotation(position: .top) {
                            Text(store.monthlyIncome.formatted()).font(.caption2).foregroundStyle(.secondary)
                        }
                    BarMark(x: .value("Kind", "Expenses"),
                            y: .value("Amount", (store.monthlyExpenses.decimalValue as NSDecimalNumber).doubleValue))
                        .foregroundStyle(.orange)
                        .annotation(position: .top) {
                            Text(store.monthlyExpenses.formatted()).font(.caption2).foregroundStyle(.secondary)
                        }
                }
                .frame(height: 200)
                .accessibilityLabel("Bar chart comparing monthly income \(store.monthlyIncome.formatted()) and expenses \(store.monthlyExpenses.formatted())")
            }
        }
    }

    // MARK: Expense category breakdown

    private var expenseBreakdownCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Expenses by category").font(.headline)
                ForEach(Array(store.expenseSlices.enumerated()), id: \.element.category) { index, slice in
                    HStack(spacing: 10) {
                        Circle().fill(color(for: index)).frame(width: 10, height: 10)
                        Text(slice.category).font(.subheadline)
                        Spacer()
                        Text(Money(minorUnits: slice.totalMinor, currency: .eur).formatted())
                            .font(.subheadline.monospacedDigit())
                        Text("\(Int((slice.share * 100).rounded()))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// A Liquid Glass KPI tile.
struct KPICard: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: symbol).foregroundStyle(tint)
                    Text(title).font(.caption).foregroundStyle(.secondary)
                }
                Text(value)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
