import SwiftUI
import Charts
import Domain

// MARK: - Subscription analytics (docs/13 §5.1, docs/14 chart palette)
// Category-distribution donut built from Domain.Analytics.categoryDistribution over
// the current subscriptions, grouped by an inferred display category (the sample
// data has no category rows yet → SubscriptionPredictor.inferCategory). Amounts are
// normalized to monthly minor units so periods are comparable. Same-currency
// (EUR) assumption matches SampleData; mixed currency would convert first.

/// A chart-ready slice pairing a Domain `CategorySlice` with a stable color index.
struct AnalyticsSlice: Identifiable {
    let id = UUID()
    let category: String
    let monthlyMinor: Int64
    let share: Double
    let count: Int
}

enum SubscriptionAnalytics {
    /// Group subscriptions by inferred category, summing normalized **monthly** minor
    /// units converted to `currency` per item via the Domain aggregator (docs/13
    /// §5.1/§7). Display-only conversion — stored amounts are never mutated.
    static func slices(for subscriptions: [Subscription], currency: CurrencyCode,
                       converter: CurrencyConverter) -> [AnalyticsSlice] {
        let rows: [(category: String, amount: Money)] = subscriptions.map {
            (category: SubscriptionPredictor.inferCategory(name: $0.name), amount: $0.monthlyAmount)
        }
        return Analytics.categoryDistribution(rows, displayCurrency: currency, converter: converter).map {
            AnalyticsSlice(category: $0.category, monthlyMinor: $0.totalMinor,
                           share: $0.share, count: $0.count)
        }
    }
}

struct SubscriptionAnalyticsView: View {
    let subscriptions: [Subscription]
    var displayCurrency: CurrencyCode = .eur
    var converter: CurrencyConverter = CurrencyConverter(rates: AssetsSampleData.sampleRates)

    private var slices: [AnalyticsSlice] {
        SubscriptionAnalytics.slices(for: subscriptions, currency: displayCurrency, converter: converter)
    }

    private var totalMonthly: Money {
        Money(minorUnits: slices.reduce(Int64(0)) { $0 + $1.monthlyMinor }, currency: displayCurrency)
    }

    // docs/14 chart palette — the Obsidian bronze→tan monochrome ramp (DesignSystem).
    private func color(for index: Int) -> Color { FinmateColor.ramp(index) }

    var body: some View {
        ScrollView {
            VStack(spacing: FinmateSpacing.md) {
                if slices.isEmpty {
                    ContentUnavailableView(
                        "No subscriptions yet",
                        systemImage: "chart.pie",
                        description: Text("Add a subscription to see your spending by category."))
                        .padding(.top, 40)
                } else {
                    GlassCard {
                        VStack(spacing: FinmateSpacing.lg) {
                            Text("Monthly spend by category")
                                .font(FinmateType.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            donut
                            legend
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Analytics")
        .navigationBarTitleDisplayMode(.inline)
        .background(FinmateBackground())
    }

    private var donut: some View {
        Chart(Array(slices.enumerated()), id: \.element.id) { index, slice in
            SectorMark(
                angle: .value("Monthly", Double(slice.monthlyMinor)),
                innerRadius: .ratio(0.62),
                angularInset: 1.5
            )
            .cornerRadius(4)
            .foregroundStyle(color(for: index))
            .accessibilityLabel(slice.category)
            .accessibilityValue("\(Money(minorUnits: slice.monthlyMinor, currency: displayCurrency).formatted()) per month, \(Int((slice.share * 100).rounded())) percent")
        }
        .chartLegend(.hidden)
        .frame(height: 220)
        .overlay {
            VStack(spacing: FinmateSpacing.xs / 2) {
                Text(totalMonthly.formatted())
                    .font(FinmateType.money(.title3, weight: .bold))
                    .contentTransition(.numericText())
                Text("per month").font(FinmateType.caption).foregroundStyle(FinmateColor.labelSecondary)
            }
            .accessibilityHidden(true)
        }
        // Chart-level summary; the per-category breakdown is the legend below
        // (each row is its own VoiceOver element — the tabular fallback).
        .accessibilityLabel("Monthly subscription spend by category, total \(totalMonthly.formatted())")
    }

    /// Visible legend that doubles as the VoiceOver tabular fallback — one element
    /// per category, read as "Entertainment, €23.98 per month, 65 percent".
    private var legend: some View {
        VStack(spacing: FinmateSpacing.sm) {
            ForEach(Array(slices.enumerated()), id: \.element.id) { index, slice in
                HStack(spacing: FinmateSpacing.md) {
                    Circle().fill(color(for: index)).frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    Text(slice.category).font(FinmateType.subheadline)
                    Spacer()
                    Text(Money(minorUnits: slice.monthlyMinor, currency: displayCurrency).formatted())
                        .font(FinmateType.money(.subheadline, weight: .regular))
                    Text("\(Int((slice.share * 100).rounded()))%")
                        .font(FinmateType.money(.caption, weight: .regular))
                        .foregroundStyle(FinmateColor.labelSecondary)
                        .frame(width: 40, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(slice.category), \(Money(minorUnits: slice.monthlyMinor, currency: displayCurrency).formatted()) per month, \(Int((slice.share * 100).rounded())) percent")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Spending by category")
    }
}
