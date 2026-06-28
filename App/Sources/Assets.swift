import SwiftUI
import Charts
import Observation
import Domain
import DataLayer

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
    /// Display currency switcher (EUR/USD/BTC) — reconverts totals non-mutatingly.
    var displayCurrency: CurrencyCode = .eur

    private let repository: AssetRepository
    let converter: CurrencyConverter

    init(repository: AssetRepository, rates: ExchangeRates) {
        self.repository = repository
        self.converter = CurrencyConverter(rates: rates)
    }

    func load() async { assets = (try? await repository.all()) ?? [] }

    func transactions(for assetID: UUID) async -> [AssetTransaction] {
        (try? await repository.transactions(assetID: assetID)) ?? []
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
    static func color(for type: AssetType) -> Color {
        switch type {
        case .crypto: return .orange
        case .stock:  return .blue
        case .etf:    return .purple
        case .cash:   return .green
        case .other:  return .gray
        }
    }
    static func gainColor(_ minor: Int64) -> Color { minor >= 0 ? .green : .red }
}

// MARK: - Views

struct AssetsView: View {
    @Environment(\.repositories) private var repositories
    @State private var store = AssetsStore(
        repository: AssetsSampleData.repository, rates: AssetsSampleData.sampleRates)
    @State private var didBind = false

    var body: some View {
        ScrollView {
            VStack(spacing: FinmateTokens.spacing) {
                currencySwitcher
                portfolioHeader
                if !store.distribution.isEmpty { distributionCard }
                holdingsList
            }
            .padding()
        }
        .navigationTitle("Assets")
        .navigationBarTitleDisplayMode(.large)
        .background(FinmateGradient())
        .navigationDestination(for: FinancialAsset.self) { asset in
            AssetDetailView(asset: asset, store: store)
        }
        .task {
            if !didBind {
                // Display rates come from the injected ExchangeRateProvider (live
                // market-data Edge Function or sample), falling back to the sample set.
                let rates = (try? await repositories.exchangeRates.latestRates()) ?? AssetsSampleData.sampleRates
                store = AssetsStore(repository: repositories.assets, rates: rates)
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
        .pickerStyle(.segmented)
        .accessibilityLabel("Display currency")
    }

    // MARK: Portfolio header KPI (total value + total gain/loss colored)

    private var portfolioHeader: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Portfolio value")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(store.portfolioValue.formatted())
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Image(systemName: store.portfolioGainMinor >= 0 ? "arrow.up.right" : "arrow.down.right")
                    Text(store.portfolioGain.formatted())
                        .monospacedDigit()
                    Text("(\(gainPctText(store.portfolioGainPct)))")
                        .monospacedDigit()
                }
                .font(.headline)
                .foregroundStyle(AssetPalette.gainColor(store.portfolioGainMinor))
                .accessibilityLabel("Total gain or loss \(store.portfolioGain.formatted()), \(gainPctText(store.portfolioGainPct))")
            }
        }
    }

    // MARK: Distribution donut by type (Swift Charts)

    private var distributionCard: some View {
        GlassCard {
            VStack(spacing: 16) {
                Text("Allocation by type")
                    .font(.headline)
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
        }
        .chartLegend(.hidden)
        .frame(height: 220)
        .overlay {
            VStack(spacing: 2) {
                Text(store.portfolioValue.formatted())
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("total").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
        }
        .accessibilityLabel("Donut chart of portfolio allocation by asset type, total \(store.portfolioValue.formatted())")
    }

    private var legend: some View {
        VStack(spacing: 8) {
            ForEach(store.distribution, id: \.type) { slice in
                HStack(spacing: 10) {
                    Circle().fill(AssetPalette.color(for: slice.type)).frame(width: 10, height: 10)
                    Text(slice.type.displayName).font(.subheadline)
                    Spacer()
                    Text(Money(minorUnits: slice.totalMinor, currency: store.displayCurrency).formatted())
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

    // MARK: Holdings list (glass rows with value + gain/loss)

    private var holdingsList: some View {
        VStack(spacing: FinmateTokens.spacing) {
            HStack {
                Text("Holdings").font(.headline)
                Spacer()
            }
            ForEach(store.assets) { asset in
                NavigationLink(value: asset) {
                    AssetRow(asset: asset,
                             displayValue: store.displayValue(asset),
                             displayGain: store.displayGain(asset),
                             gainPct: AssetValuation.gainPct(asset))
                }
                .buttonStyle(.plain)
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
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2).frame(width: 34)
                    .foregroundStyle(AssetPalette.color(for: asset.type))
                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.name).font(.headline)
                    Text(asset.type.displayName).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(displayValue.formatted())
                        .font(.headline.monospacedDigit())
                    Text("\(displayGain.formatted())  \(String(format: "%+.1f%%", gainPct * 100))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(AssetPalette.gainColor(displayGain.minorUnits))
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var symbol: String {
        switch asset.type {
        case .crypto: return "bitcoinsign.circle.fill"
        case .stock:  return "chart.line.uptrend.xyaxis"
        case .etf:    return "square.grid.2x2.fill"
        case .cash:   return "banknote.fill"
        case .other:  return "circle.grid.cross.fill"
        }
    }
}

// MARK: - Asset detail (value/cost/gain + transactions)

struct AssetDetailView: View {
    let asset: FinancialAsset
    let store: AssetsStore
    @State private var transactions: [AssetTransaction] = []

    private var gainMinor: Int64 { AssetValuation.unrealizedGainMinor(asset) }

    var body: some View {
        ScrollView {
            VStack(spacing: FinmateTokens.spacing) {
                header

                GlassCard {
                    VStack(spacing: 0) {
                        DetailRow(label: "Current value", value: asset.value.formatted())
                        Divider().padding(.vertical, 8)
                        DetailRow(label: "Cost basis", value: asset.costBasis.formatted())
                        Divider().padding(.vertical, 8)
                        DetailRow(label: "Per-unit price", value: asset.currentPrice.formatted())
                        Divider().padding(.vertical, 8)
                        DetailRow(label: "Quantity", value: quantityText)
                    }
                }

                GlassCard {
                    HStack {
                        Text("Unrealized gain/loss").foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Money(minorUnits: gainMinor, currency: asset.currency).formatted())  \(String(format: "%+.1f%%", AssetValuation.gainPct(asset) * 100))")
                            .font(.body.monospacedDigit().weight(.semibold))
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
        .background(FinmateGradient())
        .task { transactions = await store.transactions(for: asset.id) }
    }

    private var header: some View {
        GlassCard {
            HStack(spacing: 16) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(AssetPalette.color(for: asset.type))
                    .frame(width: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(asset.name)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                    Text(asset.type.displayName)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var transactionsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Transactions").font(.headline)
                if transactions.isEmpty {
                    Text("No transactions recorded.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(transactions) { txn in
                        TransactionRow(transaction: txn, currency: asset.currency)
                        if txn.id != transactions.last?.id { Divider().padding(.vertical, 4) }
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
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.kind.displayName).font(.subheadline.weight(.medium))
                Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if transaction.priceMinor > 0 {
                    Text(Money(minorUnits: transaction.priceMinor, currency: currency).formatted())
                        .font(.subheadline.monospacedDigit())
                }
                Text(detail).font(.caption2).foregroundStyle(.secondary)
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
