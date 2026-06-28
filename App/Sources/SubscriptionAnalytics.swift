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
    /// units, then run the Domain distribution aggregator. Filters to a single
    /// currency (the displayed one) so totals are meaningful without conversion.
    static func slices(for subscriptions: [Subscription], currency: CurrencyCode) -> [AnalyticsSlice] {
        let rows = subscriptions
            .filter { $0.currency == currency }
            .map { (category: SubscriptionPredictor.inferCategory(name: $0.name),
                    amountMinor: $0.monthlyAmount.minorUnits) }
        return Analytics.categoryDistribution(rows).map {
            AnalyticsSlice(category: $0.category, monthlyMinor: $0.totalMinor,
                           share: $0.share, count: $0.count)
        }
    }
}

struct SubscriptionAnalyticsView: View {
    let subscriptions: [Subscription]
    private let displayCurrency: CurrencyCode = .eur

    private var slices: [AnalyticsSlice] {
        SubscriptionAnalytics.slices(for: subscriptions, currency: displayCurrency)
    }

    private var totalMonthly: Money {
        Money(minorUnits: slices.reduce(Int64(0)) { $0 + $1.monthlyMinor }, currency: displayCurrency)
    }

    // docs/14 chart palette — kept inline here; in production this lives in DesignSystem.
    private let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .green, .indigo, .mint]

    private func color(for index: Int) -> Color { palette[index % palette.count] }

    var body: some View {
        ScrollView {
            VStack(spacing: FinmateTokens.spacing) {
                if slices.isEmpty {
                    ContentUnavailableView(
                        "No subscriptions yet",
                        systemImage: "chart.pie",
                        description: Text("Add a subscription to see your spending by category."))
                        .padding(.top, 40)
                } else {
                    GlassCard {
                        VStack(spacing: 16) {
                            Text("Monthly spend by category")
                                .font(.headline)
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
        .background(FinmateGradient())
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
        }
        .chartLegend(.hidden)
        .frame(height: 220)
        .overlay {
            VStack(spacing: 2) {
                Text(totalMonthly.formatted())
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .contentTransition(.numericText())
                Text("per month").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Donut chart of monthly subscription spend by category, total \(totalMonthly.formatted())")
    }

    private var legend: some View {
        VStack(spacing: 8) {
            ForEach(Array(slices.enumerated()), id: \.element.id) { index, slice in
                HStack(spacing: 10) {
                    Circle().fill(color(for: index)).frame(width: 10, height: 10)
                    Text(slice.category).font(.subheadline)
                    Spacer()
                    Text(Money(minorUnits: slice.monthlyMinor, currency: displayCurrency).formatted())
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
