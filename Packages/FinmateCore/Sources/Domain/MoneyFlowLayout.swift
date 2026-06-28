import Foundation

// MARK: - Money-flow deterministic layout (docs/14 §11, ADR-0016 bucketed Sankey)
//
// A PURE, CoreGraphics-free flow-layout: the renderer never computes money or
// geometry — it only draws the `FlowNode`/`FlowLink` rects + ribbons returned
// here. Kept on plain `Double` structs so it unit-tests without UIKit/SwiftUI.
// The TypeScript web client mirrors this transform against the same vectors.

/// A bucket's stable palette token (resolved to a concrete color per design
/// system in the renderer — docs/06 chart palette: Fixed≈red, Variable≈orange,
/// Subscriptions≈violet, Savings≈emerald, Income≈accent).
public enum FlowColorToken: String, Sendable, Equatable, CaseIterable {
    case income, fixed, variable, subscriptions, savings
}

/// A laid-out node rect (income on the left, one bucket per right-column row).
public struct FlowNode: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let valueMinor: Int64
    public let x: Double
    public let y: Double
    public let w: Double
    public let h: Double
    public let color: FlowColorToken

    public init(id: String, label: String, valueMinor: Int64,
                x: Double, y: Double, w: Double, h: Double, color: FlowColorToken) {
        self.id = id
        self.label = label
        self.valueMinor = valueMinor
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.color = color
    }
}

/// A ribbon Income→bucket. Vertical segment on the income edge (`incomeY0…incomeY1`)
/// and on the bucket edge (`bucketY0…bucketY1`); the renderer joins them with a
/// cubic Bézier. Ribbon thickness equals the bucket height at both ends.
public struct FlowLink: Identifiable, Equatable, Sendable {
    public let id: String
    public let incomeY0: Double
    public let incomeY1: Double
    public let bucketY0: Double
    public let bucketY1: Double
    public let color: FlowColorToken

    public init(id: String, incomeY0: Double, incomeY1: Double,
                bucketY0: Double, bucketY1: Double, color: FlowColorToken) {
        self.id = id
        self.incomeY0 = incomeY0
        self.incomeY1 = incomeY1
        self.bucketY0 = bucketY0
        self.bucketY1 = bucketY1
        self.color = color
    }
}

/// Result of the layout transform: pure data the renderer geometry-projects.
public struct MoneyFlowLayout: Equatable, Sendable {
    public let nodes: [FlowNode]
    public let links: [FlowLink]
    /// X-coordinates of the income node's right edge and the bucket column's
    /// left edge — the horizontal span the renderer spans with each ribbon.
    public let incomeRightX: Double
    public let bucketLeftX: Double

    public init(nodes: [FlowNode], links: [FlowLink], incomeRightX: Double, bucketLeftX: Double) {
        self.nodes = nodes
        self.links = links
        self.incomeRightX = incomeRightX
        self.bucketLeftX = bucketLeftX
    }

    public var incomeNode: FlowNode? { nodes.first { $0.color == .income } }
    public var bucketNodes: [FlowNode] { nodes.filter { $0.color != .income } }
}

/// Pure layout transform for the bucketed money-flow (docs/14 §11.3).
///
/// - `total = max(income, Σ buckets)` guards the over-budget case so nothing
///   exceeds the canvas. With clamped Savings the two are usually equal.
/// - Left column: ONE Income node, height `income/total × usableH`, vertically
///   centered in `usableH`.
/// - Right column: the NON-ZERO buckets stacked top→bottom in the fixed order
///   [Fixed, Variable, Subscriptions, Savings], each height `value/total × usableH`,
///   separated by `gap`. Zero-value buckets are omitted.
/// - Links: one Income→bucket ribbon per bucket; the income end-segments stack in
///   the same order, partitioning the income node's right edge.
public enum MoneyFlowLayoutEngine {

    public struct Size: Equatable, Sendable {
        public let width: Double
        public let height: Double
        public init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }
    }

    public struct Padding: Equatable, Sendable {
        public let horizontal: Double
        public let vertical: Double
        public init(horizontal: Double, vertical: Double) {
            self.horizontal = horizontal
            self.vertical = vertical
        }
        public static let `default` = Padding(horizontal: 16, vertical: 16)
    }

    /// Fixed canonical bucket order (top→bottom on the right column).
    private struct BucketSpec {
        let id: String
        let label: String
        let value: Int64
        let color: FlowColorToken
    }

    public static func layout(
        flow: MoneyFlow,
        size: Size,
        padding: Padding = .default,
        nodeWidth: Double = 14
    ) -> MoneyFlowLayout {
        let buckets: [BucketSpec] = [
            BucketSpec(id: "fixed", label: "Fixed", value: flow.fixedMinor, color: .fixed),
            BucketSpec(id: "variable", label: "Variable", value: flow.variableMinor, color: .variable),
            BucketSpec(id: "subscriptions", label: "Subscriptions", value: flow.subscriptionsMinor, color: .subscriptions),
            BucketSpec(id: "savings", label: "Savings", value: flow.savingsMinor, color: .savings),
        ].filter { $0.value > 0 }

        let usableH = max(0, size.height - 2 * padding.vertical)
        let bucketSum = buckets.reduce(Int64(0)) { $0 + $1.value }
        let total = max(flow.incomeMinor, bucketSum)

        // Layout columns.
        let leftX = padding.horizontal
        let rightX = size.width - padding.horizontal - nodeWidth
        let incomeRightX = leftX + nodeWidth
        let bucketLeftX = rightX

        guard total > 0, usableH > 0 else {
            return MoneyFlowLayout(nodes: [], links: [], incomeRightX: incomeRightX, bucketLeftX: bucketLeftX)
        }

        // Gaps consume part of usableH so the stacked buckets + gaps fit exactly.
        let gapCount = max(0, buckets.count - 1)
        let gap: Double = gapCount > 0 ? 6 : 0
        let gapsTotal = gap * Double(gapCount)
        // Scale maps minor units → points. The scaled bucket-sum + gaps ≤ usableH:
        // bucketSum ≤ total, so bucketSum*scale ≤ usableH - gapsTotal ≤ usableH.
        let scale = (usableH - gapsTotal) / Double(total)

        // Income node — height proportional to income, vertically centered.
        let incomeH = Double(flow.incomeMinor) * scale
        let incomeY = padding.vertical + (usableH - incomeH) / 2
        let incomeNode = FlowNode(
            id: "income", label: "Income", valueMinor: flow.incomeMinor,
            x: leftX, y: incomeY, w: nodeWidth, h: incomeH, color: .income
        )

        // Right column — stack buckets top→bottom; income end-segments stack in
        // the same order so they partition the income node's right edge.
        var nodes: [FlowNode] = [incomeNode]
        var links: [FlowLink] = []
        var bucketCursorY = padding.vertical
        var incomeCursorY = incomeY

        for spec in buckets {
            let h = Double(spec.value) * scale
            let node = FlowNode(
                id: spec.id, label: spec.label, valueMinor: spec.value,
                x: rightX, y: bucketCursorY, w: nodeWidth, h: h, color: spec.color
            )
            nodes.append(node)

            links.append(FlowLink(
                id: spec.id,
                incomeY0: incomeCursorY, incomeY1: incomeCursorY + h,
                bucketY0: bucketCursorY, bucketY1: bucketCursorY + h,
                color: spec.color
            ))

            bucketCursorY += h + gap
            incomeCursorY += h
        }

        return MoneyFlowLayout(
            nodes: nodes, links: links,
            incomeRightX: incomeRightX, bucketLeftX: bucketLeftX
        )
    }
}
