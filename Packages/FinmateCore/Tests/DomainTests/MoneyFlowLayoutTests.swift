import Testing
import Foundation
@testable import Domain

// docs/14 §11.3 — the deterministic money-flow layout transform. Pure data,
// shared vectors with the web TypeScript port. Money is integer minor units.
@Suite struct MoneyFlowLayoutTests {

    private typealias Engine = MoneyFlowLayoutEngine
    private let size = MoneyFlowLayoutEngine.Size(width: 360, height: 260)
    private let pad = MoneyFlowLayoutEngine.Padding(horizontal: 16, vertical: 16)
    private let nodeW = 14.0

    // The M2 sample-data vector: income 380000, fixed 119000, variable 40000,
    // subs 2648, savings = 380000 − 161648 = 218352. total == income (savings absorbs).
    private var sampleFlow: MoneyFlow {
        MoneyFlow(incomeMinor: 380_000, fixedMinor: 119_000, variableMinor: 40_000, subscriptionsMinor: 2_648)
    }

    private func node(_ layout: MoneyFlowLayout, _ id: String) -> FlowNode {
        layout.nodes.first { $0.id == id }!
    }

    // MARK: Bucket value fractions (value / total)

    @Test func sampleBucketFractions() {
        #expect(sampleFlow.savingsMinor == 218_352)
        let layout = Engine.layout(flow: sampleFlow, size: size, padding: pad, nodeWidth: nodeW)
        let usableH = size.height - 2 * pad.vertical          // 228
        let gap = 6.0
        let gapsTotal = gap * 3                                // 4 buckets → 3 gaps
        let total = 380_000.0
        let scale = (usableH - gapsTotal) / total

        func frac(_ id: String, _ value: Double) {
            let n = node(layout, id)
            #expect(abs(n.h - value * scale) < 1e-6)
        }
        frac("fixed", 119_000)        // ≈ 0.3132 of income
        frac("variable", 40_000)      // ≈ 0.1053
        frac("subscriptions", 2_648)  // ≈ 0.0070
        frac("savings", 218_352)      // ≈ 0.5746

        // Relative fractions sanity (height ratio == value ratio).
        let f = node(layout, "fixed").h
        let s = node(layout, "savings").h
        #expect(abs(s / f - (218_352.0 / 119_000.0)) < 1e-9)
    }

    // MARK: Sum ≤ usableH (stacked buckets + gaps fit the canvas)

    @Test func bucketHeightsPlusGapsFitUsableHeight() {
        let layout = Engine.layout(flow: sampleFlow, size: size, padding: pad, nodeWidth: nodeW)
        let usableH = size.height - 2 * pad.vertical
        let buckets = layout.bucketNodes
        let heightSum = buckets.reduce(0.0) { $0 + $1.h }
        let gaps = 6.0 * Double(buckets.count - 1)
        #expect(heightSum + gaps <= usableH + 1e-6)
        // Each node fits.
        for n in layout.nodes { #expect(n.h <= usableH + 1e-6) }
        // Bottom of the last bucket within the canvas.
        let last = buckets.max { $0.y < $1.y }!
        #expect(last.y + last.h <= size.height - pad.vertical + 1e-6)
    }

    // MARK: Income node — centered, full-height (since total == income)

    @Test func incomeNodeCenteredAndFullHeight() {
        let layout = Engine.layout(flow: sampleFlow, size: size, padding: pad, nodeWidth: nodeW)
        let income = node(layout, "income")
        let usableH = size.height - 2 * pad.vertical
        let scale = (usableH - 18.0) / 380_000.0
        #expect(abs(income.h - 380_000.0 * scale) < 1e-6)
        // Centered in usableH.
        let expectedY = pad.vertical + (usableH - income.h) / 2
        #expect(abs(income.y - expectedY) < 1e-6)
        #expect(income.color == .income)
        #expect(income.x == pad.horizontal)
    }

    // MARK: Ordering — fixed canonical order top→bottom

    @Test func bucketsStackedInCanonicalOrder() {
        let layout = Engine.layout(flow: sampleFlow, size: size, padding: pad, nodeWidth: nodeW)
        let order = layout.bucketNodes.sorted { $0.y < $1.y }.map(\.id)
        #expect(order == ["fixed", "variable", "subscriptions", "savings"])
        // Income end-segments partition the income node's right edge in the same
        // order (each link's incomeY1 == the next link's incomeY0).
        let income = node(layout, "income")
        let sortedLinks = layout.links // links are appended in canonical order
        #expect(sortedLinks.map(\.id) == ["fixed", "variable", "subscriptions", "savings"])
        #expect(abs(sortedLinks.first!.incomeY0 - income.y) < 1e-6)
        for i in 1..<sortedLinks.count {
            #expect(abs(sortedLinks[i].incomeY0 - sortedLinks[i - 1].incomeY1) < 1e-6)
        }
        #expect(abs(sortedLinks.last!.incomeY1 - (income.y + income.h)) < 1e-6)
        // Each ribbon's thickness equals its bucket height at both ends.
        for link in sortedLinks {
            let n = node(layout, link.id)
            #expect(abs((link.incomeY1 - link.incomeY0) - n.h) < 1e-6)
            #expect(abs((link.bucketY1 - link.bucketY0) - n.h) < 1e-6)
        }
    }

    // MARK: Over-budget — no Savings node, income scaled by total = expenses

    @Test func overBudgetOmitsSavingsAndScalesByTotal() {
        // income 100000, expenses 120000 → savings = 0, total = 120000.
        let flow = MoneyFlow(incomeMinor: 100_000, fixedMinor: 80_000, variableMinor: 40_000, subscriptionsMinor: 0)
        #expect(flow.savingsMinor == 0)
        let layout = Engine.layout(flow: flow, size: size, padding: pad, nodeWidth: nodeW)
        // No Savings node, no zero-value Subscriptions node.
        #expect(layout.nodes.first { $0.id == "savings" } == nil)
        #expect(layout.nodes.first { $0.id == "subscriptions" } == nil)
        #expect(layout.bucketNodes.map(\.id).sorted() == ["fixed", "variable"])

        let usableH = size.height - 2 * pad.vertical
        let gap = 6.0 * 1   // 2 buckets → 1 gap
        let total = 120_000.0
        let scale = (usableH - gap) / total
        let income = node(layout, "income")
        #expect(abs(income.h - 100_000.0 * scale) < 1e-6)   // 100000/120000 * (usableH-gap)
        // Income node is shorter than the bucket column (it underflows the canvas).
        let bucketSpan = layout.bucketNodes.reduce(0.0) { $0 + $1.h } + gap
        #expect(income.h < bucketSpan)
        #expect(abs(bucketSpan - (usableH)) < 1e-6) // expenses fill usableH (they == total)
    }

    // MARK: Zero / degenerate guards

    @Test func zeroFlowYieldsEmptyLayout() {
        let flow = MoneyFlow(incomeMinor: 0, fixedMinor: 0, variableMinor: 0, subscriptionsMinor: 0)
        let layout = Engine.layout(flow: flow, size: size, padding: pad, nodeWidth: nodeW)
        #expect(layout.nodes.isEmpty)
        #expect(layout.links.isEmpty)
    }
}
