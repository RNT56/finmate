import SwiftUI

// MARK: - Component Gallery (the Obsidian design-system showcase) — docs/06
//
// A single scrollable showcase of the tokens + every component, so the design system
// can be eyeballed in light + dark at a glance (mirroring Substimate's depth). Not
// shipped in the tab bar — it exists for `#Preview` and design review only.

struct ComponentGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FinmateSpacing.xl) {
                header
                colorSection
                typeSection
                buttonSection
                badgeSection
                statTileSection
                listRowSection
                amountSection
                segmentedSection
                stateSection
            }
            .padding()
        }
        .background(FinmateBackground())
        .tint(FinmateColor.bronze)
        .finmateScrollEdge()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: FinmateSpacing.xs) {
            Text("Obsidian")
                .font(FinmateType.largeTitle.weight(.bold))
            Text("Near-monochrome ink + a warm bronze signature, on flat glass.")
                .font(FinmateType.subheadline)
                .foregroundStyle(FinmateColor.labelSecondary)
        }
    }

    // MARK: Colors

    private var colorSection: some View {
        gallerySection("Palette") {
            FlowingSwatches(swatches: [
                ("bg", FinmateColor.background), ("elevated", FinmateColor.elevated),
                ("surface", FinmateColor.surface), ("surface2", FinmateColor.surface2),
                ("ink", FinmateColor.ink), ("bronze", FinmateColor.bronze),
                ("bronzeDeep", FinmateColor.bronzeDeep), ("up", FinmateColor.up),
                ("down", FinmateColor.down), ("neutral", FinmateColor.neutral),
                ("warning", FinmateColor.warning), ("btc", FinmateColor.btc),
            ])
            Text("Money-flow ramp").font(FinmateType.caption).foregroundStyle(FinmateColor.labelSecondary)
            FlowingSwatches(swatches: [
                ("income", FinmateColor.Flow.income), ("fixed", FinmateColor.Flow.fixed),
                ("variable", FinmateColor.Flow.variable), ("subs", FinmateColor.Flow.subscriptions),
                ("savings", FinmateColor.Flow.savings),
            ])
            Text("Chart ramp").font(FinmateType.caption).foregroundStyle(FinmateColor.labelSecondary)
            FlowingSwatches(swatches: FinmateColor.chartRamp.enumerated().map { ("\($0.offset)", $0.element) })
        }
    }

    // MARK: Type

    private var typeSection: some View {
        gallerySection("Type ramp") {
            Text("Large Title").font(FinmateType.largeTitle)
            Text("Title").font(FinmateType.title)
            Text("Headline").font(FinmateType.headline)
            Text("Body — the quick brown fox.").font(FinmateType.body)
            Text("Subheadline").font(FinmateType.subheadline).foregroundStyle(FinmateColor.labelSecondary)
            Text("Caption").font(FinmateType.caption).foregroundStyle(FinmateColor.labelTertiary)
            Text("€12,345.67").font(FinmateType.money(.title2, weight: .bold))
        }
    }

    // MARK: Buttons

    private var buttonSection: some View {
        gallerySection("Buttons") {
            HStack {
                GlassButton("Primary", systemImage: "checkmark") {}
                GlassButton("Secondary", kind: .secondary) {}
            }
            HStack {
                GlassButton("Ghost", kind: .ghost) {}
                GlassButton("Delete", systemImage: "trash", kind: .destructive) {}
            }
            GlassButton("Full width", kind: .primary, fullWidth: true) {}
            HStack {
                GlassButton("Small", kind: .secondary, size: .sm) {}
                GlassButton("Medium", kind: .secondary, size: .md) {}
            }
        }
    }

    // MARK: Badges

    private var badgeSection: some View {
        gallerySection("Badges & pills") {
            FlowingBadges(badges: [
                Badge(text: "Neutral", tone: .neutral),
                Badge(text: "Accent", tone: .accent),
                Badge(text: "+12.4%", tone: .up, systemImage: "arrow.up.right"),
                Badge(text: "-3.1%", tone: .down, systemImage: "arrow.down.right"),
                Badge(text: "BTC", tone: .btc, systemImage: "bitcoinsign"),
                Badge(text: "Due soon", tone: .warning),
            ])
        }
    }

    // MARK: Stat tiles

    private var statTileSection: some View {
        gallerySection("Stat tiles") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: FinmateSpacing.md) {
                StatTile(title: "Monthly Income", value: "€3,800.00",
                         symbol: "arrow.down.circle.fill", tint: FinmateColor.up)
                StatTile(title: "Net", value: "+€1,250.00", symbol: "equal.circle.fill",
                         signMinor: 125000, detail: "Surplus this month")
                StatTile(title: "Portfolio", value: "€27,250.00", symbol: "chart.pie.fill")
                StatTile(title: "Loss", value: "-€420.00", symbol: "arrow.down.right",
                         signMinor: -42000)
            }
        }
    }

    // MARK: List rows

    private var listRowSection: some View {
        gallerySection("List rows") {
            GlassListRow(systemImage: "play.tv.fill", title: "Netflix",
                         subtitle: "Monthly · Active") {
                VStack(alignment: .trailing, spacing: 2) {
                    AmountText("€12.99", style: .headline)
                    Text("/mo").font(FinmateType.caption2).foregroundStyle(FinmateColor.labelSecondary)
                }
            }
            GlassListRow(systemImage: "bitcoinsign.circle.fill", iconTint: FinmateColor.btc,
                         title: "Bitcoin", subtitle: "Crypto") {
                AmountText("+€500.00", style: .headline, signMinor: 50000)
            }
        }
    }

    // MARK: Amounts

    private var amountSection: some View {
        gallerySection("Amount text") {
            HStack(spacing: FinmateSpacing.lg) {
                AmountText("+€1,250.00", style: .title3, signMinor: 125000)
                AmountText("-€420.00", style: .title3, signMinor: -42000)
                AmountText("€0.00", style: .title3, signMinor: 0)
            }
        }
    }

    // MARK: Segmented

    private var segmentedSection: some View {
        gallerySection("Segmented control") {
            SegmentedDemo()
        }
    }

    // MARK: States

    private var stateSection: some View {
        gallerySection("States") {
            SkeletonRow()
            ErrorStateCard(message: "The request timed out. Check your connection.") {}
            EmptyStateCard(title: "No holdings yet", systemImage: "chart.pie",
                           message: "Add an asset to track your portfolio.",
                           actionTitle: "Add asset") {}
            HStack {
                Toast(text: "Saved", tone: .success)
                Toast(text: "Heads up", tone: .warning)
            }
        }
    }

    // MARK: Section scaffolding

    @ViewBuilder
    private func gallerySection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: FinmateSpacing.md) {
            SectionHeader(title)
            content()
        }
    }
}

private struct SegmentedDemo: View {
    @State private var selection = 0
    var body: some View {
        Picker("Currency", selection: $selection) {
            Text("€ EUR").tag(0)
            Text("$ USD").tag(1)
            Text("₿ BTC").tag(2)
        }
        .finmateSegmented()
    }
}

private struct FlowingSwatches: View {
    let swatches: [(String, Color)]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: FinmateSpacing.sm)],
                  alignment: .leading, spacing: FinmateSpacing.sm) {
            ForEach(Array(swatches.enumerated()), id: \.offset) { _, swatch in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: FinmateRadius.sm, style: .continuous)
                        .fill(swatch.1)
                        .frame(height: 40)
                        .overlay(RoundedRectangle(cornerRadius: FinmateRadius.sm, style: .continuous)
                            .strokeBorder(FinmateColor.hairline))
                    Text(swatch.0).font(.caption2).foregroundStyle(FinmateColor.labelSecondary)
                }
            }
        }
    }
}

private struct FlowingBadges: View {
    let badges: [Badge]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: FinmateSpacing.sm)],
                  alignment: .leading, spacing: FinmateSpacing.sm) {
            ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in badge }
        }
    }
}

// MARK: - Preview (light + dark)

#Preview("Component Gallery — Light") {
    ComponentGallery()
        .preferredColorScheme(.light)
}

#Preview("Component Gallery — Dark") {
    ComponentGallery()
        .preferredColorScheme(.dark)
}
