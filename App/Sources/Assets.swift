import SwiftUI
import Charts
import Observation
import Domain
import DataLayer
import Shared

// MARK: - DataLayer (in-memory) — docs/03 §3. Implements the Domain AssetRepository;
// the real Supabase-backed implementation swaps in behind the same seam.

actor InMemoryAssetRepository: AssetRepository {
    private var store: [UUID: FinancialAsset]
    private var txns: [UUID: [AssetTransaction]]
    init(seed: [FinancialAsset], transactions: [UUID: [AssetTransaction]]) {
        store = Dictionary(uniqueKeysWithValues: seed.map { ($0.id, $0) })
        txns = transactions
    }
    func all() async throws -> [FinancialAsset] {
        store.values.sorted { $0.valueMinor > $1.valueMinor }
    }
    func transactions(assetID: UUID) async throws -> [AssetTransaction] {
        (txns[assetID] ?? []).sorted { $0.date > $1.date }
    }
    func upsert(_ asset: FinancialAsset) async throws { store[asset.id] = asset }
    func delete(id: UUID) async throws { store[id] = nil; txns[id] = nil }
    func recordTransaction(_ transaction: AssetTransaction) async throws {
        var list = txns[transaction.assetID] ?? []
        if let idx = list.firstIndex(where: { $0.id == transaction.id }) {
            list[idx] = transaction
        } else {
            list.append(transaction)
        }
        txns[transaction.assetID] = list
    }
}

// MARK: - Sample data (matches the web client so the displayed figures agree, M5)
// Bitcoin +500_000, World ETF +30_000, ACME −5_000; portfolio value 2_725_000,
// cost 2_200_000, gain +525_000 (all EUR).

enum AssetsSampleData {
    static let bitcoin = FinancialAsset(
        name: "Bitcoin", type: .crypto, currency: .eur, quantity: Decimal(string: "0.5")!,
        purchasePriceMinor: 2_000_000, currentPriceMinor: 5_000_000, valueMinor: 2_500_000,
        notes: "Cold storage")
    static let etf = FinancialAsset(
        name: "World ETF", type: .etf, currency: .eur, quantity: 10,
        purchasePriceMinor: 150_000, currentPriceMinor: 18_000, valueMinor: 180_000)
    static let stock = FinancialAsset(
        name: "ACME", type: .stock, currency: .eur, quantity: 5,
        purchasePriceMinor: 50_000, currentPriceMinor: 9_000, valueMinor: 45_000)

    static let assets: [FinancialAsset] = [bitcoin, etf, stock]

    private static func monthsAgo(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: -n, to: .now) ?? .now
    }

    static let transactions: [UUID: [AssetTransaction]] = [
        bitcoin.id: [
            AssetTransaction(assetID: bitcoin.id, kind: .buy, quantity: Decimal(string: "0.3")!,
                             priceMinor: 3_500_000, feesMinor: 1_500, date: monthsAgo(8)),
            AssetTransaction(assetID: bitcoin.id, kind: .buy, quantity: Decimal(string: "0.2")!,
                             priceMinor: 4_700_000, feesMinor: 1_000, date: monthsAgo(3)),
        ],
        etf.id: [
            AssetTransaction(assetID: etf.id, kind: .buy, quantity: 10,
                             priceMinor: 15_000, feesMinor: 200, date: monthsAgo(12)),
            AssetTransaction(assetID: etf.id, kind: .dividend, quantity: 0,
                             priceMinor: 0, feesMinor: 0, date: monthsAgo(2), notes: "Q1 distribution"),
        ],
        stock.id: [
            AssetTransaction(assetID: stock.id, kind: .buy, quantity: 5,
                             priceMinor: 10_000, feesMinor: 100, date: monthsAgo(6)),
        ],
    ]

    static let repository = InMemoryAssetRepository(seed: assets, transactions: transactions)

    /// Sample display rates (shared with the calculator) — eurUsd 1.10, btcEur 50000, btcUsd 55000.
    static let sampleRates = ExchangeRates(
        eurUsd: Decimal(string: "1.10")!, btcEur: 50_000, btcUsd: 55_000,
        fetchedAt: .now)
}

// MARK: - Store (@Observable, MainActor) — docs/03 unidirectional MVVM

@MainActor
@Observable
final class AssetsStore {
    private(set) var assets: [FinancialAsset] = []
    private(set) var isLoading = false
    private(set) var loadError: String?
    private(set) var hasLoaded = false
    /// Display currency switcher (EUR/USD/BTC) — reconverts totals non-mutatingly.
    /// Seeded from the app-wide Settings default; the inline segmented switcher is a
    /// local per-screen override.
    var displayCurrency: CurrencyCode

    private let repository: AssetRepository
    let converter: CurrencyConverter

    init(repository: AssetRepository, rates: ExchangeRates, displayCurrency: CurrencyCode = .eur) {
        self.repository = repository
        self.converter = CurrencyConverter(rates: rates)
        self.displayCurrency = displayCurrency
    }

    func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false; hasLoaded = true }
        do {
            assets = try await repository.all()
        } catch {
            loadError = error.localizedDescription
        }
    }

    func transactions(for assetID: UUID) async -> [AssetTransaction] {
        (try? await repository.transactions(assetID: assetID)) ?? []
    }

    // MARK: Mutations — write through the repo, then reload (portfolio recomputes).

    func addAsset(_ asset: FinancialAsset) async {
        try? await repository.upsert(asset)
        await load()
    }
    func updateAsset(_ asset: FinancialAsset) async {
        try? await repository.upsert(asset)
        await load()
    }
    func deleteAsset(id: UUID) async {
        try? await repository.delete(id: id)
        await load()
    }

    /// Record a transaction against an asset, then recompute the holding's quantity,
    /// average-cost basis, and current value from the full history (ADR-0015,
    /// docs/13 §2) before persisting and reloading. Returns the refreshed asset (or
    /// nil if it no longer exists) so a pushed detail view can update in place.
    @discardableResult
    func recordTransaction(_ txn: AssetTransaction, for asset: FinancialAsset) async -> FinancialAsset? {
        try? await repository.recordTransaction(txn)
        let history = await transactions(for: asset.id)
        let recomputed = AssetValuation.recompute(
            transactions: history, currentPriceMinor: asset.currentPriceMinor)
        var updated = asset
        updated.quantity = recomputed.quantity
        updated.purchasePriceMinor = recomputed.costBasisMinor
        updated.valueMinor = recomputed.valueMinor
        try? await repository.upsert(updated)
        await load()
        return assets.first { $0.id == updated.id }
    }

    // MARK: Derived (all via Domain.AssetValuation — never Double for money)

    var portfolioValue: Money {
        Money(minorUnits: AssetValuation.portfolioValueMinor(assets, displayCurrency: displayCurrency, converter: converter),
              currency: displayCurrency)
    }
    var portfolioCostBasis: Money {
        Money(minorUnits: AssetValuation.portfolioCostBasisMinor(assets, displayCurrency: displayCurrency, converter: converter),
              currency: displayCurrency)
    }
    var portfolioGainMinor: Int64 {
        AssetValuation.portfolioGainMinor(assets, displayCurrency: displayCurrency, converter: converter)
    }
    var portfolioGain: Money { Money(minorUnits: portfolioGainMinor, currency: displayCurrency) }
    var portfolioGainPct: Double {
        AssetValuation.portfolioGainPct(assets, displayCurrency: displayCurrency, converter: converter)
    }
    var distribution: [AssetDistributionSlice] {
        AssetValuation.assetDistribution(assets, displayCurrency: displayCurrency, converter: converter)
    }

    /// A holding's current value converted to the display currency.
    func displayValue(_ asset: FinancialAsset) -> Money {
        (try? converter.convert(asset.value, to: displayCurrency)) ?? asset.value
    }
    /// A holding's unrealized gain converted to the display currency (own-currency
    /// gain then converted — preserves sign).
    func displayGain(_ asset: FinancialAsset) -> Money {
        let gain = Money(minorUnits: AssetValuation.unrealizedGainMinor(asset), currency: asset.currency)
        return (try? converter.convert(gain, to: displayCurrency)) ?? gain
    }
}

// MARK: - Color helper for asset types

enum AssetPalette {
    /// Asset-type colors drawn from the Obsidian bronze→tan ramp, with BTC keeping its
    /// semantic orange. Cash/savings read as up-green (liquid), other as neutral.
    static func color(for type: AssetType) -> Color {
        switch type {
        case .crypto:     return FinmateColor.btc
        case .stock:      return FinmateColor.bronze
        case .etf:        return FinmateColor.bronzeDeep
        case .cash:       return FinmateColor.up
        case .savings:    return Color(hex: 0xCDB089)
        case .realEstate: return Color(hex: 0x8A6A42)
        case .other:      return FinmateColor.neutral
        }
    }
    static func gainColor(_ minor: Int64) -> Color { minor >= 0 ? FinmateColor.up : FinmateColor.down }
}

// MARK: - Views

struct AssetsView: View {
    @Environment(\.repositories) private var repositories
    @Environment(PreferencesStore.self) private var preferences
    @State private var store = AssetsStore(
        repository: AssetsSampleData.repository, rates: AssetsSampleData.sampleRates)
    @State private var didBind = false
    @State private var addingAsset = false
    @State private var editingAsset: FinancialAsset?

    var body: some View {
        ScrollView {
            VStack(spacing: FinmateSpacing.md) {
                if store.isLoading && !store.hasLoaded {
                    SkeletonList(count: 4)
                } else if let error = store.loadError {
                    ErrorStateCard(message: error) { Task { await store.load() } }
                } else if store.assets.isEmpty {
                    ContentUnavailableView {
                        Label("No holdings yet", systemImage: "chart.pie")
                    } description: {
                        Text("Add an asset to track your portfolio value and allocation.")
                    } actions: {
                        GlassButton("Add asset", systemImage: "plus") { addingAsset = true }
                    }
                    .padding(.top, FinmateSpacing.xxl)
                } else {
                    currencySwitcher
                    portfolioHeader
                    if !store.distribution.isEmpty { distributionCard }
                    holdingsList
                }
            }
            .padding()
        }
        .navigationTitle("Assets")
        .navigationBarTitleDisplayMode(.large)
        .background(FinmateBackground())
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { addingAsset = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add asset")
            }
        }
        .sheet(isPresented: $addingAsset) {
            AssetFormView(asset: nil) { saved in Task { await store.addAsset(saved) } }
        }
        .sheet(item: $editingAsset) { item in
            AssetFormView(asset: item) { saved in Task { await store.updateAsset(saved) } }
        }
        .navigationDestination(for: FinancialAsset.self) { asset in
            AssetDetailView(asset: asset, store: store)
        }
        .task {
            if !didBind {
                // Display rates come from the injected ExchangeRateProvider (live
                // market-data Edge Function or sample), falling back to the sample set.
                let rates = (try? await repositories.exchangeRates.latestRates()) ?? AssetsSampleData.sampleRates
                store = AssetsStore(repository: repositories.assets, rates: rates,
                                    displayCurrency: preferences.preferences.defaultCurrency)
                didBind = true
            }
            await store.load()
        }
    }

    // MARK: Display-currency switcher (EUR / USD / BTC)

    private var currencySwitcher: some View {
        Picker("Display currency", selection: $store.displayCurrency) {
            ForEach(CurrencyCode.allCases, id: \.self) { code in
                Text("\(code.symbol) \(code.rawValue)").tag(code)
            }
        }
        .finmateSegmented()
        .accessibilityLabel("Display currency")
    }

    // MARK: Portfolio header KPI (total value + total gain/loss colored)

    private var portfolioHeader: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: FinmateSpacing.sm) {
                Text("Portfolio value")
                    .font(FinmateType.subheadline).foregroundStyle(FinmateColor.labelSecondary)
                // Total stays neutral (semantic discipline — docs/06); only the gain
                // delta below colours.
                Text(store.portfolioValue.formatted())
                    .font(FinmateType.money(.largeTitle, weight: .bold))
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                HStack(spacing: FinmateSpacing.xs + 2) {
                    Image(systemName: store.portfolioGainMinor >= 0 ? "arrow.up.right" : "arrow.down.right")
                    Text(store.portfolioGain.formatted())
                        .monospacedDigit()
                    Text("(\(gainPctText(store.portfolioGainPct)))")
                        .monospacedDigit()
                }
                .font(FinmateType.headline)
                .foregroundStyle(AssetPalette.gainColor(store.portfolioGainMinor))
                .accessibilityLabel("Total gain or loss \(store.portfolioGain.formatted()), \(gainPctText(store.portfolioGainPct))")
            }
        }
    }

    // MARK: Distribution donut by type (Swift Charts)

    private var distributionCard: some View {
        GlassCard {
            VStack(spacing: FinmateSpacing.lg) {
                Text("Allocation by type")
                    .font(FinmateType.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                donut
                legend
            }
        }
    }

    private var donut: some View {
        Chart(store.distribution, id: \.type) { slice in
            SectorMark(
                angle: .value("Value", Double(slice.totalMinor)),
                innerRadius: .ratio(0.62),
                angularInset: 1.5
            )
            .cornerRadius(4)
            .foregroundStyle(AssetPalette.color(for: slice.type))
            .accessibilityLabel(slice.type.displayName)
            .accessibilityValue("\(Money(minorUnits: slice.totalMinor, currency: store.displayCurrency).formatted()), \(Int((slice.share * 100).rounded())) percent")
        }
        .chartLegend(.hidden)
        .frame(height: 220)
        .overlay {
            VStack(spacing: FinmateSpacing.xs / 2) {
                Text(store.portfolioValue.formatted())
                    .font(FinmateType.money(.title3, weight: .bold))
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("total").font(FinmateType.caption).foregroundStyle(FinmateColor.labelSecondary)
            }
            .padding(.horizontal, FinmateSpacing.xl)
            .accessibilityHidden(true)
        }
        // Summary; the per-type breakdown is the legend below (tabular fallback).
        .accessibilityLabel("Portfolio allocation by asset type, total \(store.portfolioValue.formatted())")
    }

    /// Visible legend that doubles as the VoiceOver tabular fallback — one element
    /// per asset type ("Crypto, €25,000.00, 92 percent").
    private var legend: some View {
        VStack(spacing: FinmateSpacing.sm) {
            ForEach(store.distribution, id: \.type) { slice in
                HStack(spacing: FinmateSpacing.md) {
                    Circle().fill(AssetPalette.color(for: slice.type)).frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    Text(slice.type.displayName).font(FinmateType.subheadline)
                    Spacer()
                    Text(Money(minorUnits: slice.totalMinor, currency: store.displayCurrency).formatted())
                        .font(FinmateType.money(.subheadline, weight: .regular))
                    Text("\(Int((slice.share * 100).rounded()))%")
                        .font(FinmateType.money(.caption, weight: .regular))
                        .foregroundStyle(FinmateColor.labelSecondary)
                        .frame(width: 40, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(slice.type.displayName), \(Money(minorUnits: slice.totalMinor, currency: store.displayCurrency).formatted()), \(Int((slice.share * 100).rounded())) percent")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Allocation by asset type")
    }

    // MARK: Holdings list (glass rows with value + gain/loss)

    private var holdingsList: some View {
        VStack(spacing: FinmateSpacing.md) {
            SectionHeader("Holdings")
            ForEach(store.assets) { asset in
                NavigationLink(value: asset) {
                    AssetRow(asset: asset,
                             displayValue: store.displayValue(asset),
                             displayGain: store.displayGain(asset),
                             gainPct: AssetValuation.gainPct(asset))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens holding details. Long press for edit and delete")
                .contextMenu {
                    Button { editingAsset = asset } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive) {
                        Task { await store.deleteAsset(id: asset.id) }
                    } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
    }

    private func gainPctText(_ pct: Double) -> String {
        let v = pct * 100
        return String(format: "%+.1f%%", v)
    }
}

/// One holding row — name + type, current value, and colored gain/loss.
struct AssetRow: View {
    let asset: FinancialAsset
    let displayValue: Money
    let displayGain: Money
    let gainPct: Double

    var body: some View {
        GlassCard {
            HStack(spacing: FinmateSpacing.lg) {
                Image(systemName: symbol)
                    .font(.title2).frame(width: 34)
                    .foregroundStyle(AssetPalette.color(for: asset.type))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: FinmateSpacing.xs / 2) {
                    Text(asset.name).font(FinmateType.headline)
                    Text(asset.type.displayName).font(FinmateType.caption).foregroundStyle(FinmateColor.labelSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: FinmateSpacing.xs / 2) {
                    // Holding value is a plain total → neutral; only the gain line colours.
                    AmountText(displayValue.formatted(), style: .headline)
                    Text("\(displayGain.formatted())  \(String(format: "%+.1f%%", gainPct * 100))")
                        .font(FinmateType.money(.caption2, weight: .regular))
                        .foregroundStyle(AssetPalette.gainColor(displayGain.minorUnits))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(asset.name), \(asset.type.displayName), value \(displayValue.formatted()), gain \(displayGain.formatted())")
        }
    }

    private var symbol: String {
        switch asset.type {
        case .crypto:     return "bitcoinsign.circle.fill"
        case .stock:      return "chart.line.uptrend.xyaxis"
        case .etf:        return "square.grid.2x2.fill"
        case .cash:       return "banknote.fill"
        case .savings:    return "building.columns.fill"
        case .realEstate: return "house.fill"
        case .other:      return "circle.grid.cross.fill"
        }
    }
}

// MARK: - Asset detail (value/cost/gain + transactions)

struct AssetDetailView: View {
    let store: AssetsStore
    @State private var asset: FinancialAsset
    @State private var transactions: [AssetTransaction] = []
    @State private var recordingTxn = false

    /// Header glyph size + slot — scale with Dynamic Type so the icon tracks the title.
    @ScaledMetric(relativeTo: .title2) private var headerIconSize: CGFloat = 36
    @ScaledMetric(relativeTo: .title2) private var headerIconSlot: CGFloat = 48

    init(asset: FinancialAsset, store: AssetsStore) {
        self.store = store
        _asset = State(initialValue: asset)
    }

    private var gainMinor: Int64 { AssetValuation.unrealizedGainMinor(asset) }

    var body: some View {
        ScrollView {
            VStack(spacing: FinmateSpacing.md) {
                header

                GlassCard {
                    VStack(spacing: 0) {
                        DetailRow(label: "Current value", value: asset.value.formatted())
                        Divider().padding(.vertical, FinmateSpacing.sm)
                        DetailRow(label: "Cost basis", value: asset.costBasis.formatted())
                        Divider().padding(.vertical, FinmateSpacing.sm)
                        DetailRow(label: "Per-unit price", value: asset.currentPrice.formatted())
                        Divider().padding(.vertical, FinmateSpacing.sm)
                        DetailRow(label: "Quantity", value: quantityText)
                    }
                }

                GlassCard {
                    HStack {
                        Text("Unrealized gain/loss")
                            .font(FinmateType.body).foregroundStyle(FinmateColor.labelSecondary)
                        Spacer()
                        Text("\(Money(minorUnits: gainMinor, currency: asset.currency).formatted())  \(String(format: "%+.1f%%", AssetValuation.gainPct(asset) * 100))")
                            .font(FinmateType.money(.body))
                            .foregroundStyle(AssetPalette.gainColor(gainMinor))
                    }
                    .accessibilityElement(children: .combine)
                }

                transactionsCard
            }
            .padding()
        }
        .navigationTitle(asset.name)
        .navigationBarTitleDisplayMode(.inline)
        .background(FinmateBackground())
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { recordingTxn = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Record transaction")
            }
        }
        .sheet(isPresented: $recordingTxn) {
            TransactionFormView(assetID: asset.id, currency: asset.currency) { txn in
                Task {
                    if let refreshed = await store.recordTransaction(txn, for: asset) {
                        asset = refreshed
                    }
                    transactions = await store.transactions(for: asset.id)
                }
            }
        }
        .task { transactions = await store.transactions(for: asset.id) }
    }

    private var header: some View {
        GlassCard {
            HStack(spacing: FinmateSpacing.lg) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: headerIconSize))
                    .foregroundStyle(AssetPalette.color(for: asset.type))
                    .frame(width: headerIconSlot)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: FinmateSpacing.xs) {
                    Text(asset.name)
                        .font(FinmateType.title2.weight(.bold))
                    Text(asset.type.displayName)
                        .font(FinmateType.subheadline).foregroundStyle(FinmateColor.labelSecondary)
                }
                Spacer()
            }
        }
    }

    private var transactionsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: FinmateSpacing.md) {
                Text("Transactions").font(FinmateType.headline)
                if transactions.isEmpty {
                    Text("No transactions recorded.")
                        .font(FinmateType.subheadline).foregroundStyle(FinmateColor.labelSecondary)
                } else {
                    ForEach(transactions) { txn in
                        TransactionRow(transaction: txn, currency: asset.currency)
                        if txn.id != transactions.last?.id { Divider().padding(.vertical, FinmateSpacing.xs) }
                    }
                }
            }
        }
    }

    private var quantityText: String {
        NSDecimalNumber(decimal: asset.quantity).stringValue
    }
}

/// One transaction line: kind + date, quantity, and a per-unit price (with fees).
struct TransactionRow: View {
    let transaction: AssetTransaction
    let currency: CurrencyCode

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: FinmateSpacing.xs / 2) {
                Text(transaction.kind.displayName).font(FinmateType.subheadline.weight(.medium))
                Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
                    .font(FinmateType.caption).foregroundStyle(FinmateColor.labelSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: FinmateSpacing.xs / 2) {
                if transaction.priceMinor > 0 {
                    Text(Money(minorUnits: transaction.priceMinor, currency: currency).formatted())
                        .font(FinmateType.money(.subheadline, weight: .regular))
                }
                Text(detail).font(FinmateType.caption2).foregroundStyle(FinmateColor.labelSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let qty = NSDecimalNumber(decimal: transaction.quantity).stringValue
        if transaction.kind == .dividend { return transaction.notes ?? "Distribution" }
        var s = "× \(qty)"
        if transaction.feesMinor > 0 {
            s += " · fee \(Money(minorUnits: transaction.feesMinor, currency: currency).formatted())"
        }
        return s
    }
}

// MARK: - Forms (add/edit asset, record transaction) — docs/02 §9

/// Parse a major-unit decimal string into minor units for `currency`, returning nil
/// on an invalid/over-precision/negative value (via the Domain Money.parse, HALF-UP).
private func assetParsedMinor(_ raw: String, currency: CurrencyCode) -> Int64? {
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    return try? Money.parse(trimmed, currency: currency).minorUnits
}

/// Parse a non-negative quantity Decimal, rejecting blanks and negatives.
private func parsedQuantity(_ raw: String) -> Decimal? {
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, let dec = Decimal(string: trimmed), dec >= 0 else { return nil }
    return dec
}

private struct AssetCurrencyPickerRow: View {
    @Binding var currency: CurrencyCode
    var body: some View {
        Picker("Currency", selection: $currency) {
            ForEach(CurrencyCode.allCases, id: \.self) { code in
                Text("\(code.symbol) \(code.rawValue)").tag(code)
            }
        }
    }
}

/// Add or edit a holding — name, type, currency, quantity, total cost basis, and
/// current per-unit price (the value is quantity × price, all Int64 minor units).
struct AssetFormView: View {
    let asset: FinancialAsset?
    var onSave: (FinancialAsset) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var type: AssetType
    @State private var currency: CurrencyCode
    @State private var quantity: String
    @State private var costBasis: String
    @State private var currentPrice: String
    @State private var error: String?

    init(asset: FinancialAsset?, onSave: @escaping (FinancialAsset) -> Void) {
        self.asset = asset
        self.onSave = onSave
        _name = State(initialValue: asset?.name ?? "")
        _type = State(initialValue: asset?.type ?? .stock)
        let cur = asset?.currency ?? .eur
        _currency = State(initialValue: cur)
        _quantity = State(initialValue: asset.map { NSDecimalNumber(decimal: $0.quantity).stringValue } ?? "")
        _costBasis = State(initialValue: asset.map {
            Money(minorUnits: $0.purchasePriceMinor, currency: $0.currency).decimalValue.description
        } ?? "")
        _currentPrice = State(initialValue: asset.map {
            Money(minorUnits: $0.currentPriceMinor, currency: $0.currency).decimalValue.description
        } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Holding") {
                    TextField("Name (e.g. Bitcoin)", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(AssetType.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    AssetCurrencyPickerRow(currency: $currency)
                }
                Section("Position") {
                    TextField("Quantity", text: $quantity).keyboardType(.decimalPad)
                    TextField("Total cost basis", text: $costBasis).keyboardType(.decimalPad)
                    TextField("Current per-unit price", text: $currentPrice).keyboardType(.decimalPad)
                    if let error {
                        Text(error).font(FinmateType.caption).foregroundStyle(FinmateColor.down)
                    }
                }
            }
            .navigationTitle(asset == nil ? "Add Asset" : "Edit Asset")
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
        guard let qty = parsedQuantity(quantity) else {
            error = "Enter a valid (non-negative) quantity."
            return
        }
        guard let cost = assetParsedMinor(costBasis, currency: currency) else {
            error = "Enter a valid cost basis (max \(currency.minorUnitDigits) decimals)."
            return
        }
        guard let price = assetParsedMinor(currentPrice, currency: currency) else {
            error = "Enter a valid per-unit price (max \(currency.minorUnitDigits) decimals)."
            return
        }
        // value = quantity × per-unit price, rounded HALF-UP to Int64 minor units.
        let value = roundHalfUpToInt64(qty * Decimal(price))
        onSave(FinancialAsset(
            id: asset?.id ?? UUID(), name: name, type: type, currency: currency,
            quantity: qty, purchasePriceMinor: cost, currentPriceMinor: price,
            valueMinor: value, notes: asset?.notes))
        dismiss()
    }
}

/// Record a buy/sell/dividend/other transaction against an asset — quantity,
/// per-unit price, fees, and date. The store recomputes the holding after saving.
struct TransactionFormView: View {
    let assetID: UUID
    let currency: CurrencyCode
    var onSave: (AssetTransaction) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var kind: AssetTransactionKind = .buy
    @State private var quantity = ""
    @State private var price = ""
    @State private var fees = ""
    @State private var date = Date.now
    @State private var notes = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Transaction") {
                    Picker("Kind", selection: $kind) {
                        ForEach(AssetTransactionKind.allCases, id: \.self) { k in
                            Text(k.displayName).tag(k)
                        }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
                if kind == .buy || kind == .sell {
                    Section("Details") {
                        TextField("Quantity", text: $quantity).keyboardType(.decimalPad)
                        TextField("Per-unit price", text: $price).keyboardType(.decimalPad)
                        TextField("Fees", text: $fees).keyboardType(.decimalPad)
                    }
                }
                Section("Notes") {
                    TextField("Notes (optional)", text: $notes)
                }
                if let error {
                    Text(error).font(FinmateType.caption).foregroundStyle(FinmateColor.down)
                }
            }
            .navigationTitle("Record Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
        }
    }

    private func save() {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)
        let noteValue = trimmedNotes.isEmpty ? nil : trimmedNotes

        if kind == .buy || kind == .sell {
            guard let qty = parsedQuantity(quantity) else {
                error = "Enter a valid (non-negative) quantity."
                return
            }
            guard let priceMinor = assetParsedMinor(price, currency: currency) else {
                error = "Enter a valid per-unit price (max \(currency.minorUnitDigits) decimals)."
                return
            }
            // Fees are optional; blank → 0, but any entered value must be valid.
            let feesTrimmed = fees.trimmingCharacters(in: .whitespaces)
            let feesMinor: Int64
            if feesTrimmed.isEmpty {
                feesMinor = 0
            } else if let parsedFees = assetParsedMinor(feesTrimmed, currency: currency) {
                feesMinor = parsedFees
            } else {
                error = "Enter a valid fee amount."
                return
            }
            onSave(AssetTransaction(
                assetID: assetID, kind: kind, quantity: qty, priceMinor: priceMinor,
                feesMinor: feesMinor, date: date, notes: noteValue))
        } else {
            // dividend / other — quantity & price are not part of the average-cost math.
            onSave(AssetTransaction(
                assetID: assetID, kind: kind, quantity: 0, priceMinor: 0,
                feesMinor: 0, date: date, notes: noteValue))
        }
        dismiss()
    }
}
