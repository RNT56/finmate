import SwiftUI
import Domain

// MARK: - Money-flow Sankey renderer (M3, docs/14 §11, ADR-0016 bucketed Sankey)
//
// A `Canvas`-based renderer that DRAWS the pure `MoneyFlowLayout` from the Domain
// engine — it never computes money. Rounded-rect nodes + cubic-Bézier ribbons
// filled with the design-system palette at ~0.5 opacity. Honors reduce-transparency
// (solid fallback) and ships a VoiceOver representation summarizing the flow.

/// Resolve a Domain `FlowColorToken` to the design-system chart palette (docs/06).
extension FlowColorToken {
    var color: Color {
        switch self {
        case .income:        return .accentColor
        case .fixed:         return .red
        case .variable:      return .orange
        case .subscriptions: return .purple
        case .savings:       return .green
        }
    }
}

struct MoneyFlowView: View {
    let flow: MoneyFlow
    var displayCurrency: CurrencyCode = .eur

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let canvasHeight: Double = 260
    private let padding = MoneyFlowLayoutEngine.Padding(horizontal: 16, vertical: 16)
    private let nodeWidth: Double = 14

    var body: some View {
        GeometryReader { geo in
            let size = MoneyFlowLayoutEngine.Size(width: Double(geo.size.width), height: canvasHeight)
            let layout = MoneyFlowLayoutEngine.layout(
                flow: flow, size: size, padding: padding, nodeWidth: nodeWidth
            )
            Canvas { context, _ in
                drawRibbons(context: context, layout: layout)
                drawNodes(context: context, layout: layout)
                drawLabels(context: context, layout: layout, width: Double(geo.size.width))
            }
        }
        .frame(height: canvasHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: Drawing

    private func drawRibbons(context: GraphicsContext, layout: MoneyFlowLayout) {
        let x0 = layout.incomeRightX
        let x1 = layout.bucketLeftX
        let midX = (x0 + x1) / 2
        for link in layout.links {
            var path = Path()
            // Top edge: income → bucket (cubic Bézier, control points at midX).
            path.move(to: CGPoint(x: x0, y: link.incomeY0))
            path.addCurve(
                to: CGPoint(x: x1, y: link.bucketY0),
                control1: CGPoint(x: midX, y: link.incomeY0),
                control2: CGPoint(x: midX, y: link.bucketY0)
            )
            // Down the bucket edge.
            path.addLine(to: CGPoint(x: x1, y: link.bucketY1))
            // Bottom edge: bucket → income.
            path.addCurve(
                to: CGPoint(x: x0, y: link.incomeY1),
                control1: CGPoint(x: midX, y: link.bucketY1),
                control2: CGPoint(x: midX, y: link.incomeY1)
            )
            path.closeSubpath()

            let tint = link.color.color
            if reduceTransparency {
                // Solid fallback + hairline edge for separation (docs/14 §11.4).
                context.fill(path, with: .color(tint))
                context.stroke(path, with: .color(Color(.systemBackground).opacity(0.6)), lineWidth: 0.5)
            } else {
                context.fill(path, with: .color(tint.opacity(0.5)))
            }
        }
    }

    private func drawNodes(context: GraphicsContext, layout: MoneyFlowLayout) {
        for node in layout.nodes {
            let rect = CGRect(x: node.x, y: node.y, width: node.w, height: node.h)
            let shape = Path(roundedRect: rect, cornerRadius: min(4, node.w / 2))
            context.fill(shape, with: .color(node.color.color))
        }
    }

    private func drawLabels(context: GraphicsContext, layout: MoneyFlowLayout, width: Double) {
        for node in layout.nodes {
            let amount = Money(minorUnits: node.valueMinor, currency: displayCurrency).formatted()
            let title = Text(node.label).font(.caption.weight(.semibold)).foregroundStyle(.primary)
            let value = Text(amount).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)

            let centerY = node.y + node.h / 2
            if node.color == .income {
                // Income label to the LEFT of its node, right-aligned at the node's left.
                context.draw(title, at: CGPoint(x: node.x - 4, y: centerY - 7), anchor: .trailing)
                context.draw(value, at: CGPoint(x: node.x - 4, y: centerY + 7), anchor: .trailing)
            } else {
                // Bucket labels to the RIGHT of their node, left-aligned.
                context.draw(title, at: CGPoint(x: node.x + node.w + 6, y: centerY - 7), anchor: .leading)
                context.draw(value, at: CGPoint(x: node.x + node.w + 6, y: centerY + 7), anchor: .leading)
            }
        }
    }

    // MARK: Accessibility

    /// VoiceOver summary, e.g. "Income €3,800.00 flows to Savings €2,183.52, Fixed €1,190.00, …".
    private var accessibilitySummary: String {
        let income = Money(minorUnits: flow.incomeMinor, currency: displayCurrency).formatted()
        // Largest buckets first reads most naturally.
        let buckets: [(String, Int64)] = [
            ("Savings", flow.savingsMinor),
            ("Fixed", flow.fixedMinor),
            ("Variable", flow.variableMinor),
            ("Subscriptions", flow.subscriptionsMinor),
        ]
        .filter { $0.1 > 0 }
        .sorted { $0.1 > $1.1 }

        guard !buckets.isEmpty else { return "Income \(income), no outflows." }
        let parts = buckets.map { "\($0.0) \(Money(minorUnits: $0.1, currency: displayCurrency).formatted())" }
        return "Money flow. Income \(income) flows to " + parts.joined(separator: ", ") + "."
    }
}

/// A wrapping legend of colored money chips shown beneath the money-flow diagram.
/// `items` are (label, amountMinor, color); amounts are formatted via the `Money` type.
struct FlowWrap: View {
    let items: [(String, Int64, Color)]
    var currency: CurrencyCode = .eur

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    Circle().fill(item.2).frame(width: 9, height: 9)
                    Text(item.0).font(.caption)
                    Spacer(minLength: 4)
                    Text(Money(minorUnits: item.1, currency: currency).formatted())
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
