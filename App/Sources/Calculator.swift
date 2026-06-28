import SwiftUI
import Domain

// MARK: - Crypto / BTC calculator (docs/02 §10, M5)
// Fiat amount + currency picker → BTC + sats via the Domain CryptoCalculator over
// the shared sample rates (eurUsd 1.10, btcEur 50000, btcUsd 55000). Conversion is
// display-only; market data comes from the Edge Function in production (ADR-0010).

struct CalculatorView: View {
    private let converter = CurrencyConverter(rates: AssetsSampleData.sampleRates)

    @State private var amount: String = "500"
    @State private var fiatCurrency: CurrencyCode = .eur
    @State private var parseError: String?

    /// Fiat currencies only (BTC is the target, not a source for this calculator).
    private let fiatOptions: [CurrencyCode] = [.eur, .usd]

    private var conversion: CryptoConversion? {
        let raw = amount.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return nil }
        guard let fiat = try? Money.parse(raw, currency: fiatCurrency) else { return nil }
        return try? CryptoCalculator.fiatToBTC(fiat, converter: converter)
    }

    private var rateText: String {
        let rate = fiatCurrency == .eur ? AssetsSampleData.sampleRates.btcEur : AssetsSampleData.sampleRates.btcUsd
        let money = Money(minorUnits: NSDecimalNumber(decimal: rate * Decimal(fiatCurrency.minorUnitsPerMajor)).int64Value,
                          currency: fiatCurrency)
        return "1 ₿ = \(money.formatted())"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: FinmateTokens.spacing) {
                inputCard
                resultCard
                GlassCard {
                    HStack {
                        Label("Rate", systemImage: "arrow.left.arrow.right")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Text(rateText).font(.subheadline.monospacedDigit())
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding()
        }
        .navigationTitle("BTC Calculator")
        .navigationBarTitleDisplayMode(.inline)
        .background(FinmateGradient())
    }

    private var inputCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Amount").font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    TextField("0", text: $amount)
                        .keyboardType(.decimalPad)
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .onChange(of: amount) { _, newValue in
                            validate(newValue)
                        }
                    Picker("Currency", selection: $fiatCurrency) {
                        ForEach(fiatOptions, id: \.self) { code in
                            Text("\(code.symbol) \(code.rawValue)").tag(code)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: fiatCurrency) { _, _ in validate(amount) }
                }
                if let parseError {
                    Text(parseError).font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    private var resultCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Equivalent").font(.subheadline).foregroundStyle(.secondary)
                if let conversion {
                    HStack {
                        Image(systemName: "bitcoinsign.circle.fill").foregroundStyle(.orange)
                        Text(conversion.btc.formatted())
                            .font(.system(.title, design: .rounded).weight(.bold))
                            .contentTransition(.numericText())
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                    Divider()
                    HStack {
                        Text("Satoshis").foregroundStyle(.secondary)
                        Spacer()
                        Text(satsText(conversion.sats)).font(.body.monospacedDigit().weight(.medium))
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    Text("Enter a fiat amount to convert.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func validate(_ newValue: String) {
        let raw = newValue.trimmingCharacters(in: .whitespaces)
        if raw.isEmpty { parseError = nil; return }
        do { _ = try Money.parse(raw, currency: fiatCurrency); parseError = nil }
        catch { parseError = "Enter a valid amount (max \(fiatCurrency.minorUnitDigits) decimals)." }
    }

    private func satsText(_ sats: Int64) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return (f.string(from: NSNumber(value: sats)) ?? "\(sats)") + " sats"
    }
}

// MARK: - More hub (docs/02 IA) — Assets · Calculator · Settings

struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink(value: MoreDestination.assets) {
                        Label("Assets", systemImage: "chart.pie.fill")
                    }
                    NavigationLink(value: MoreDestination.calculator) {
                        Label("BTC Calculator", systemImage: "bitcoinsign.circle.fill")
                    }
                    NavigationLink(value: MoreDestination.importCSV) {
                        Label("Import CSV", systemImage: "square.and.arrow.down")
                    }
                }
                Section {
                    NavigationLink(value: MoreDestination.settings) {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("More")
            .navigationDestination(for: MoreDestination.self) { destination in
                switch destination {
                case .assets:     AssetsView()
                case .calculator: CalculatorView()
                case .importCSV:  ImportView()
                case .settings:   SettingsStubView()
                }
            }
            .background(FinmateGradient())
        }
    }
}

enum MoreDestination: Hashable {
    case assets, calculator, importCSV, settings
}

/// Settings placeholder (full settings/theming arrives in a later milestone, docs/08).
struct SettingsStubView: View {
    var body: some View {
        ContentUnavailableView(
            "Settings",
            systemImage: "gearshape.fill",
            description: Text("Theming, currency preferences, and account controls arrive in a later milestone (see docs/08).")
        )
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .background(FinmateGradient())
    }
}
