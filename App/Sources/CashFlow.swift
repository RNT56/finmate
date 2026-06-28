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
    // Reference the stable `SampleData.expenseCategories` rows by id (ADR-0022).
    private static func categoryID(_ slug: String) -> UUID? {
        SampleData.expenseCategories.first { $0.slug == slug }?.id
    }
    static let fixedExpenses: [FixedExpense] = [
        FixedExpense(name: "Rent", amountMinor: 110_000, currency: .eur, categoryID: categoryID("housing"), frequency: .monthly, dueDate: dayOfThisMonth(1), autopay: true),
        FixedExpense(name: "Insurance", amountMinor: 9_000, currency: .eur, categoryID: categoryID("utilities"), frequency: .monthly, dueDate: dayOfThisMonth(5), autopay: true),
    ]
    static let variableExpenses: [VariableExpense] = [
        VariableExpense(name: "Groceries", amountMinor: 40_000, currency: .eur, categoryID: categoryID("groceries"), date: .now),
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
    /// The expense categories (ADR-0022) used to resolve `categoryID → name` for
    /// the breakdown rows, the expense-row secondary labels, and the form Picker.
    private(set) var expenseCategories: [Domain.Category] = []

    private let incomeRepository: IncomeRepository
    private let expenseRepository: ExpenseRepository
    private let categoryRepository: CategoryRepository
    /// Subscriptions feed the expense roll-up; their monthly-equivalent total in EUR
    /// is computed once via the Domain math (matches the Home card).
    private let subscriptionsMonthlyMinor: Int64
    private let displayCurrency: CurrencyCode = .eur

    init(incomeRepository: IncomeRepository,
         expenseRepository: ExpenseRepository,
         categoryRepository: CategoryRepository,
         subscriptions: [Subscription]) {
        self.incomeRepository = incomeRepository
        self.expenseRepository = expenseRepository
        self.categoryRepository = categoryRepository
        self.subscriptionsMonthlyMinor = subscriptions
            .filter { $0.currency == .eur }
            .reduce(Int64(0)) { $0 + $1.monthlyAmount.minorUnits }
    }

    func load() async {
        income = (try? await incomeRepository.all()) ?? []
        fixedExpenses = (try? await expenseRepository.fixed()) ?? []
        variableExpenses = (try? await expenseRepository.variable()) ?? []
        expenseCategories = (try? await categoryRepository.categories(kind: .expense)) ?? []
    }

    /// Resolve a category id to its display name, falling back to "Uncategorized"
    /// (ADR-0022). The pure breakdown math stays label-agnostic.
    func categoryName(_ id: UUID?) -> String {
        guard let id, let match = expenseCategories.first(where: { $0.id == id }) else {
            return "Uncategorized"
        }
        return match.name
    }

    // MARK: Income mutations — call the repo, then reload (KPIs + flow recompute).

    func addIncome(_ income: IncomeSource) async {
        try? await incomeRepository.upsert(income)
        await load()
    }
    func updateIncome(_ income: IncomeSource) async {
        try? await incomeRepository.upsert(income)
        await load()
    }
    func deleteIncome(id: UUID) async {
        try? await incomeRepository.delete(id: id)
        await load()
    }

    // MARK: Fixed-expense mutations

    func addFixed(_ expense: FixedExpense) async {
        try? await expenseRepository.upsertFixed(expense)
        await load()
    }
    func updateFixed(_ expense: FixedExpense) async {
        try? await expenseRepository.upsertFixed(expense)
        await load()
    }
    func deleteFixed(id: UUID) async {
        try? await expenseRepository.deleteFixed(id: id)
        await load()
    }

    // MARK: Variable-expense mutations

    func addVariable(_ expense: VariableExpense) async {
        try? await expenseRepository.upsertVariable(expense)
        await load()
    }
    func updateVariable(_ expense: VariableExpense) async {
        try? await expenseRepository.upsertVariable(expense)
        await load()
    }
    func deleteVariable(id: UUID) async {
        try? await expenseRepository.deleteVariable(id: id)
        await load()
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
            (categoryName($0.categoryID), $0.monthlyMinor)
        }
        for ve in variableExpenses where Calendar.current.isDate(ve.date, equalTo: .now, toGranularity: .month) {
            rows.append((categoryName(ve.categoryID), ve.amountMinor))
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
        categoryRepository: InMemoryCategoryRepository(),
        subscriptions: SampleData.subscriptions
    )
    @State private var didBind = false

    @State private var editingIncome: IncomeSource?
    @State private var addingIncome = false
    @State private var editingFixed: FixedExpense?
    @State private var addingFixed = false
    @State private var editingVariable: VariableExpense?
    @State private var addingVariable = false

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
                    incomeSection
                    fixedSection
                    variableSection
                }
                .padding()
            }
            .navigationTitle("Cash Flow")
            .background(FinmateGradient())
            .sheet(isPresented: $addingIncome) {
                IncomeFormView(income: nil) { saved in Task { await store.addIncome(saved) } }
            }
            .sheet(item: $editingIncome) { item in
                IncomeFormView(income: item) { saved in Task { await store.updateIncome(saved) } }
            }
            .sheet(isPresented: $addingFixed) {
                FixedExpenseFormView(expense: nil, categories: store.expenseCategories) { saved in Task { await store.addFixed(saved) } }
            }
            .sheet(item: $editingFixed) { item in
                FixedExpenseFormView(expense: item, categories: store.expenseCategories) { saved in Task { await store.updateFixed(saved) } }
            }
            .sheet(isPresented: $addingVariable) {
                VariableExpenseFormView(expense: nil, categories: store.expenseCategories) { saved in Task { await store.addVariable(saved) } }
            }
            .sheet(item: $editingVariable) { item in
                VariableExpenseFormView(expense: item, categories: store.expenseCategories) { saved in Task { await store.updateVariable(saved) } }
            }
            .task {
                if !didBind {
                    // Subscriptions feed the expense roll-up; fetch them from the
                    // injected repo so the bucket matches the Subscriptions tab.
                    let subs = (try? await repositories.subscriptions.all()) ?? SampleData.subscriptions
                    store = CashFlowStore(
                        incomeRepository: repositories.income,
                        expenseRepository: repositories.expenses,
                        categoryRepository: repositories.categories,
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

    // MARK: Editable Income section

    private var incomeSection: some View {
        editableSection(
            title: "Income",
            symbol: "arrow.down.circle.fill",
            tint: .green,
            add: { addingIncome = true },
            addLabel: "Add income"
        ) {
            if store.income.isEmpty {
                emptyRow("No income sources yet.")
            } else {
                ForEach(store.income) { item in
                    flowEntryRow(
                        name: item.name,
                        detail: item.frequency.rawValue.capitalized,
                        amount: Money(minorUnits: item.amountMinor, currency: item.currency).formatted(),
                        edit: { editingIncome = item },
                        delete: { Task { await store.deleteIncome(id: item.id) } }
                    )
                }
            }
        }
    }

    // MARK: Editable Fixed-expense section

    private var fixedSection: some View {
        editableSection(
            title: "Fixed expenses",
            symbol: "calendar.badge.clock",
            tint: .red,
            add: { addingFixed = true },
            addLabel: "Add fixed expense"
        ) {
            if store.fixedExpenses.isEmpty {
                emptyRow("No fixed expenses yet.")
            } else {
                ForEach(store.fixedExpenses) { item in
                    flowEntryRow(
                        name: item.name,
                        detail: "\(store.categoryName(item.categoryID)) · \(item.frequency.rawValue.capitalized)",
                        amount: Money(minorUnits: item.amountMinor, currency: item.currency).formatted(),
                        edit: { editingFixed = item },
                        delete: { Task { await store.deleteFixed(id: item.id) } }
                    )
                }
            }
        }
    }

    // MARK: Editable Variable-expense section

    private var variableSection: some View {
        editableSection(
            title: "Variable expenses",
            symbol: "cart.fill",
            tint: .orange,
            add: { addingVariable = true },
            addLabel: "Add variable expense"
        ) {
            if store.variableExpenses.isEmpty {
                emptyRow("No variable expenses yet.")
            } else {
                ForEach(store.variableExpenses) { item in
                    flowEntryRow(
                        name: item.name,
                        detail: "\(store.categoryName(item.categoryID)) · \(item.date.formatted(date: .abbreviated, time: .omitted))",
                        amount: Money(minorUnits: item.amountMinor, currency: item.currency).formatted(),
                        edit: { editingVariable = item },
                        delete: { Task { await store.deleteVariable(id: item.id) } }
                    )
                }
            }
        }
    }

    // MARK: Section building blocks (shared layout for the three editable lists)

    private func editableSection<Content: View>(
        title: String, symbol: String, tint: Color,
        add: @escaping () -> Void, addLabel: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: symbol).foregroundStyle(tint)
                    Text(title).font(.headline)
                    Spacer()
                    Button(action: add) { Image(systemName: "plus.circle.fill") }
                        .accessibilityLabel(addLabel)
                }
                content()
            }
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary)
    }

    private func flowEntryRow(
        name: String, detail: String, amount: String,
        edit: @escaping () -> Void, delete: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(amount).font(.subheadline.monospacedDigit())
            Button(action: delete) {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete \(name)")
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: edit)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(detail), \(amount)")
        .accessibilityHint("Tap to edit")
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

// MARK: - Forms (add/edit) — docs/02 §5. Each is a Form with name + amount
// (parsed via Money.parse with validation), currency, and frequency/date pickers.

/// A reusable currency picker (EUR/USD/BTC) for the cash-flow forms.
private struct CurrencyPickerRow: View {
    @Binding var currency: CurrencyCode
    var body: some View {
        Picker("Currency", selection: $currency) {
            ForEach(CurrencyCode.allCases, id: \.self) { code in
                Text("\(code.symbol) \(code.rawValue)").tag(code)
            }
        }
    }
}

/// A category Picker keyed by `Category.id` (ADR-0022). A `nil` tag means
/// "Uncategorized"; the row resolves names from the supplied categories list.
private struct CategoryPickerRow: View {
    let categories: [Domain.Category]
    @Binding var categoryID: UUID?
    var body: some View {
        Picker("Category", selection: $categoryID) {
            Text("Uncategorized").tag(UUID?.none)
            ForEach(categories) { category in
                Text(category.name).tag(UUID?.some(category.id))
            }
        }
    }
}

/// Parse a major-unit decimal string into minor units for `currency`, or set an error.
private func parsedMinor(_ raw: String, currency: CurrencyCode, error: inout String?) -> Int64? {
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    do {
        let minor = try Money.parse(trimmed, currency: currency).minorUnits
        error = nil
        return minor
    } catch {
        return nil
    }
}

struct IncomeFormView: View {
    let income: IncomeSource?
    var onSave: (IncomeSource) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var amount: String
    @State private var currency: CurrencyCode
    @State private var frequency: IncomeFrequency
    @State private var nextPayment: Date
    @State private var amountError: String?

    init(income: IncomeSource?, onSave: @escaping (IncomeSource) -> Void) {
        self.income = income
        self.onSave = onSave
        _name = State(initialValue: income?.name ?? "")
        let cur = income?.currency ?? .eur
        _currency = State(initialValue: cur)
        _amount = State(initialValue: income.map {
            Money(minorUnits: $0.amountMinor, currency: $0.currency).decimalValue.description
        } ?? "")
        _frequency = State(initialValue: income?.frequency ?? .monthly)
        _nextPayment = State(initialValue: income?.nextPayment ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Source") {
                    TextField("Name (e.g. Salary)", text: $name)
                }
                Section("Amount") {
                    TextField("Amount", text: $amount).keyboardType(.decimalPad)
                    CurrencyPickerRow(currency: $currency)
                    if let amountError {
                        Text(amountError).font(.caption).foregroundStyle(.red)
                    }
                }
                Section("Schedule") {
                    Picker("Frequency", selection: $frequency) {
                        ForEach(IncomeFrequency.allCases, id: \.self) { f in
                            Text(f.rawValue.capitalized).tag(f)
                        }
                    }
                    DatePicker("Next payment", selection: $nextPayment, displayedComponents: .date)
                }
            }
            .navigationTitle(income == nil ? "Add Income" : "Edit Income")
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
        guard let minor = parsedMinor(amount, currency: currency, error: &amountError) else {
            amountError = "Enter a valid amount (max \(currency.minorUnitDigits) decimals)."
            return
        }
        onSave(IncomeSource(
            id: income?.id ?? UUID(), name: name, amountMinor: minor, currency: currency,
            frequency: frequency, nextPayment: nextPayment, notes: income?.notes))
        dismiss()
    }
}

struct FixedExpenseFormView: View {
    let expense: FixedExpense?
    let categories: [Domain.Category]
    var onSave: (FixedExpense) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var amount: String
    @State private var currency: CurrencyCode
    @State private var categoryID: UUID?
    @State private var frequency: BillingPeriod
    @State private var dueDate: Date
    @State private var autopay: Bool
    @State private var amountError: String?

    init(expense: FixedExpense?, categories: [Domain.Category], onSave: @escaping (FixedExpense) -> Void) {
        self.expense = expense
        self.categories = categories
        self.onSave = onSave
        _name = State(initialValue: expense?.name ?? "")
        let cur = expense?.currency ?? .eur
        _currency = State(initialValue: cur)
        _amount = State(initialValue: expense.map {
            Money(minorUnits: $0.amountMinor, currency: $0.currency).decimalValue.description
        } ?? "")
        _categoryID = State(initialValue: expense?.categoryID)
        _frequency = State(initialValue: expense?.frequency ?? .monthly)
        _dueDate = State(initialValue: expense?.dueDate ?? .now)
        _autopay = State(initialValue: expense?.autopay ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Expense") {
                    TextField("Name (e.g. Rent)", text: $name)
                    CategoryPickerRow(categories: categories, categoryID: $categoryID)
                }
                Section("Amount") {
                    TextField("Amount", text: $amount).keyboardType(.decimalPad)
                    CurrencyPickerRow(currency: $currency)
                    if let amountError {
                        Text(amountError).font(.caption).foregroundStyle(.red)
                    }
                }
                Section("Schedule") {
                    Picker("Frequency", selection: $frequency) {
                        ForEach(BillingPeriod.allCases, id: \.self) { f in
                            Text(f.rawValue.capitalized).tag(f)
                        }
                    }
                    DatePicker("Due date", selection: $dueDate, displayedComponents: .date)
                    Toggle("Autopay", isOn: $autopay)
                }
            }
            .navigationTitle(expense == nil ? "Add Fixed Expense" : "Edit Fixed Expense")
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
        guard let minor = parsedMinor(amount, currency: currency, error: &amountError) else {
            amountError = "Enter a valid amount (max \(currency.minorUnitDigits) decimals)."
            return
        }
        onSave(FixedExpense(
            id: expense?.id ?? UUID(), name: name, amountMinor: minor, currency: currency,
            categoryID: categoryID, frequency: frequency,
            dueDate: dueDate, autopay: autopay, notes: expense?.notes))
        dismiss()
    }
}

struct VariableExpenseFormView: View {
    let expense: VariableExpense?
    let categories: [Domain.Category]
    var onSave: (VariableExpense) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var amount: String
    @State private var currency: CurrencyCode
    @State private var categoryID: UUID?
    @State private var date: Date
    @State private var amountError: String?

    init(expense: VariableExpense?, categories: [Domain.Category], onSave: @escaping (VariableExpense) -> Void) {
        self.expense = expense
        self.categories = categories
        self.onSave = onSave
        _name = State(initialValue: expense?.name ?? "")
        let cur = expense?.currency ?? .eur
        _currency = State(initialValue: cur)
        _amount = State(initialValue: expense.map {
            Money(minorUnits: $0.amountMinor, currency: $0.currency).decimalValue.description
        } ?? "")
        _categoryID = State(initialValue: expense?.categoryID)
        _date = State(initialValue: expense?.date ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Expense") {
                    TextField("Name (e.g. Groceries)", text: $name)
                    CategoryPickerRow(categories: categories, categoryID: $categoryID)
                }
                Section("Amount") {
                    TextField("Amount", text: $amount).keyboardType(.decimalPad)
                    CurrencyPickerRow(currency: $currency)
                    if let amountError {
                        Text(amountError).font(.caption).foregroundStyle(.red)
                    }
                }
                Section("Date") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
            }
            .navigationTitle(expense == nil ? "Add Variable Expense" : "Edit Variable Expense")
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
        guard let minor = parsedMinor(amount, currency: currency, error: &amountError) else {
            amountError = "Enter a valid amount (max \(currency.minorUnitDigits) decimals)."
            return
        }
        onSave(VariableExpense(
            id: expense?.id ?? UUID(), name: name, amountMinor: minor, currency: currency,
            categoryID: categoryID, date: date, notes: expense?.notes))
        dismiss()
    }
}
