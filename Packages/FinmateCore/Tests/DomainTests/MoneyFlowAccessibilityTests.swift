import Testing
import Foundation
@testable import Domain

// M7-A11Y — the PURE money-flow VoiceOver description builder. The Sankey renderer
// is geometry; these strings are its tabular fallback + chart summary.
@Suite struct MoneyFlowAccessibilityTests {

    // German locale → "1.190,00 €" style; fixed so amount substrings are stable.
    private let locale = Locale(identifier: "de_DE")

    // The M2 sample-data vector (matches MoneyFlowLayoutTests):
    // income 380000, fixed 119000, variable 40000, subs 2648, savings 218352.
    private var sampleFlow: MoneyFlow {
        MoneyFlow(incomeMinor: 380_000, fixedMinor: 119_000, variableMinor: 40_000, subscriptionsMinor: 2_648)
    }

    @Test func descriptionsAreInCanonicalOrderAndSkipZeroBuckets() {
        let rows = MoneyFlowAccessibility.descriptions(for: sampleFlow, currency: .eur, locale: locale)
        #expect(rows.map(\.bucket) == ["Fixed", "Variable", "Subscriptions", "Savings"])
        // Shares are fractions of income (rounded): 119000/380000 ≈ 31%, savings ≈ 57%.
        #expect(rows.first { $0.bucket == "Fixed" }?.sharePercent == 31)
        #expect(rows.first { $0.bucket == "Savings" }?.sharePercent == 57)
    }

    @Test func descriptionLabelComposesBucketAmountAndShare() {
        let rows = MoneyFlowAccessibility.descriptions(for: sampleFlow, currency: .eur, locale: locale)
        let savings = rows.first { $0.bucket == "Savings" }!
        #expect(savings.label.hasPrefix("Income to Savings, "))
        #expect(savings.label.hasSuffix(", 57 percent"))
        #expect(savings.label.contains(savings.amount))
    }

    @Test func zeroValueBucketsAreOmitted() {
        // No subscriptions, no savings (over budget).
        let flow = MoneyFlow(incomeMinor: 100_000, fixedMinor: 80_000, variableMinor: 40_000, subscriptionsMinor: 0)
        #expect(flow.savingsMinor == 0)
        let rows = MoneyFlowAccessibility.descriptions(for: flow, currency: .eur, locale: locale)
        #expect(rows.map(\.bucket) == ["Fixed", "Variable"])
    }

    @Test func summaryListsBucketsLargestFirst() {
        let summary = MoneyFlowAccessibility.summary(for: sampleFlow, currency: .eur, locale: locale)
        #expect(summary.hasPrefix("Money flow. Income "))
        #expect(summary.hasSuffix("."))
        // Savings (218352) is the largest bucket → appears before Fixed (119000).
        let savingsIdx = summary.range(of: "Savings")!.lowerBound
        let fixedIdx = summary.range(of: "Fixed")!.lowerBound
        #expect(savingsIdx < fixedIdx)
    }

    @Test func summaryHandlesNoOutflows() {
        let flow = MoneyFlow(incomeMinor: 300_000, fixedMinor: 0, variableMinor: 0, subscriptionsMinor: 0)
        // income with zero expenses → savings is the whole income (a bucket), so
        // exercise the truly-empty case with zero income too.
        #expect(flow.savingsMinor == 300_000)
        let empty = MoneyFlow(incomeMinor: 0, fixedMinor: 0, variableMinor: 0, subscriptionsMinor: 0)
        let summary = MoneyFlowAccessibility.summary(for: empty, currency: .eur, locale: locale)
        #expect(summary.contains("no outflows"))
    }

    @Test func zeroIncomeYieldsZeroPercentShares() {
        // Degenerate guard: expenses but no income → share denominator is 0.
        let flow = MoneyFlow(incomeMinor: 0, fixedMinor: 5_000, variableMinor: 0, subscriptionsMinor: 0)
        let rows = MoneyFlowAccessibility.descriptions(for: flow, currency: .eur, locale: locale)
        #expect(rows.allSatisfy { $0.sharePercent == 0 })
    }
}
