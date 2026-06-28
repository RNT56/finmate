import Foundation

// MARK: - Money-flow accessibility descriptions (M7-A11Y, docs/06 §a11y)
//
// PURE description-string builders for the money-flow Sankey's VoiceOver fallback.
// The renderer is geometry; these turn the value model into human-readable rows
// ("Income → Savings: €2,183.52") plus a one-line summary. No UIKit/SwiftUI here
// so it unit-tests in plain Domain. The web client mirrors these strings.

public enum MoneyFlowAccessibility {

    /// One Income→bucket flow row, e.g. "Income to Savings, €2,183.52, 57 percent".
    public struct FlowDescription: Equatable, Sendable {
        public let bucket: String
        public let amount: String
        public let sharePercent: Int
        /// The composed VoiceOver line.
        public let label: String

        public init(bucket: String, amount: String, sharePercent: Int, label: String) {
            self.bucket = bucket
            self.amount = amount
            self.sharePercent = sharePercent
            self.label = label
        }
    }

    /// Canonical bucket order (matches the layout engine's top→bottom stacking).
    private static func buckets(for flow: MoneyFlow) -> [(name: String, value: Int64)] {
        [
            ("Fixed", flow.fixedMinor),
            ("Variable", flow.variableMinor),
            ("Subscriptions", flow.subscriptionsMinor),
            ("Savings", flow.savingsMinor),
        ].filter { $0.value > 0 }
    }

    /// Per-flow VoiceOver rows (tabular fallback). Non-zero buckets only, in the
    /// canonical layout order. Share is each bucket as a fraction of income
    /// (rounded to a whole percent); income == 0 yields 0 percent rows.
    public static func descriptions(
        for flow: MoneyFlow,
        currency: CurrencyCode = .eur,
        locale: Locale = .current
    ) -> [FlowDescription] {
        let incomeMinor = flow.incomeMinor
        return buckets(for: flow).map { bucket in
            let amount = Money(minorUnits: bucket.value, currency: currency).formatted(locale: locale)
            let share = incomeMinor > 0
                ? Int((Double(bucket.value) / Double(incomeMinor) * 100).rounded())
                : 0
            let label = "Income to \(bucket.name), \(amount), \(share) percent"
            return FlowDescription(
                bucket: bucket.name, amount: amount, sharePercent: share, label: label
            )
        }
    }

    /// A single chart-level summary line, e.g.
    /// "Money flow. Income €3,800.00 flows to Savings €2,183.52, Fixed €1,190.00, …".
    /// Buckets are listed largest first (reads most naturally for VoiceOver).
    public static func summary(
        for flow: MoneyFlow,
        currency: CurrencyCode = .eur,
        locale: Locale = .current
    ) -> String {
        let income = Money(minorUnits: flow.incomeMinor, currency: currency).formatted(locale: locale)
        let ordered = buckets(for: flow).sorted { $0.value > $1.value }
        guard !ordered.isEmpty else { return "Money flow. Income \(income), no outflows." }
        let parts = ordered.map {
            "\($0.name) \(Money(minorUnits: $0.value, currency: currency).formatted(locale: locale))"
        }
        return "Money flow. Income \(income) flows to " + parts.joined(separator: ", ") + "."
    }
}
