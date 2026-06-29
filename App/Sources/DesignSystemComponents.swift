import SwiftUI

// MARK: - Obsidian component library — docs/06
//
// The depth layer: buttons, badges, amount text, list rows, segmented control,
// stat tiles, section headers, empty/toast states — all built on the tokens in
// `DesignSystemTokens.swift` and the glass surfaces in `DesignSystem.swift`. Every
// component keeps Dynamic Type (@ScaledMetric), VoiceOver labels/traits, and
// reduce-motion intact.

// MARK: - GlassButton

/// The Obsidian button. Primary = high-contrast INK fill, secondary = glass, ghost =
/// plain accent, destructive = down-red. On iOS 26 the primary maps to `.glassProminent`
/// and the secondary to `.glass`; on 18–25 they fall back to `.borderedProminent`/
/// `.bordered`. INK fill is applied via tint so the system styles stay native.
struct GlassButton: View {
    enum Kind { case primary, secondary, ghost, destructive }
    enum Size { case sm, md
        /// Backwards-friendly aliases.
        static let small = Size.sm
        static let medium = Size.md
    }

    let title: String
    var systemImage: String?
    var kind: Kind = .primary
    var size: Size = .md
    var fullWidth: Bool = false
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, kind: Kind = .primary,
         size: Size = .md, fullWidth: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.kind = kind
        self.size = size
        self.fullWidth = fullWidth
        self.action = action
    }

    @ScaledMetric(relativeTo: .body) private var vPadSm: CGFloat = 6
    @ScaledMetric(relativeTo: .body) private var vPadMd: CGFloat = 10
    @ScaledMetric(relativeTo: .body) private var hPad: CGFloat = 16

    var body: some View {
        let button = Button(action: action) {
            label
                .padding(.vertical, size == .sm ? vPadSm : vPadMd)
                .padding(.horizontal, hPad)
                .frame(maxWidth: fullWidth ? .infinity : nil)
        }
        styled(button)
            .tint(tint)
    }

    @ViewBuilder private var label: some View {
        let font = size == .sm ? FinmateType.subheadline.weight(.semibold)
                               : FinmateType.body.weight(.semibold)
        if let systemImage {
            Label(title, systemImage: systemImage).font(font)
        } else {
            Text(title).font(font)
        }
    }

    private var tint: Color {
        switch kind {
        case .primary:     return FinmateColor.ink
        case .secondary:   return FinmateColor.bronze
        case .ghost:       return FinmateColor.bronze
        case .destructive: return FinmateColor.down
        }
    }

    @ViewBuilder private func styled(_ button: some View) -> some View {
        if #available(iOS 26.0, *) {
            switch kind {
            case .primary:     button.buttonStyle(.glassProminent)
            case .destructive: button.buttonStyle(.glassProminent)
            case .secondary:   button.buttonStyle(.glass)
            case .ghost:       button.buttonStyle(.plain).foregroundStyle(FinmateColor.bronze)
            }
        } else {
            switch kind {
            case .primary:     button.buttonStyle(.borderedProminent)
            case .destructive: button.buttonStyle(.borderedProminent)
            case .secondary:   button.buttonStyle(.bordered)
            case .ghost:       button.buttonStyle(.plain).foregroundStyle(FinmateColor.bronze)
            }
        }
    }
}

// MARK: - Badge / Pill

/// A compact pill label. Neutral / accent / up / down / btc tones.
struct Badge: View {
    enum Tone { case neutral, accent, up, down, btc, warning }
    let text: String
    var tone: Tone = .neutral
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.caption2) }
            Text(text).font(FinmateType.caption.weight(.semibold))
        }
        .padding(.horizontal, FinmateSpacing.sm)
        .padding(.vertical, FinmateSpacing.xs)
        .foregroundStyle(fg)
        .background(bg, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var fg: Color {
        switch tone {
        case .neutral: return FinmateColor.labelSecondary
        case .accent:  return FinmateColor.bronze
        case .up:      return FinmateColor.up
        case .down:    return FinmateColor.down
        case .btc:     return FinmateColor.btc
        case .warning: return FinmateColor.warning
        }
    }
    private var bg: Color { fg.opacity(0.16) }
}

// MARK: - AmountText

/// Money/figure text in the rounded, tabular numeric face, optionally colored by sign.
struct AmountText: View {
    let text: String
    var style: Font.TextStyle = .body
    var weight: Font.Weight = .semibold
    /// When set, colors by the sign of this minor amount (gain green / loss red).
    var signMinor: Int64?

    init(_ text: String, style: Font.TextStyle = .body, weight: Font.Weight = .semibold,
         signMinor: Int64? = nil) {
        self.text = text
        self.style = style
        self.weight = weight
        self.signMinor = signMinor
    }

    var body: some View {
        Text(text)
            .font(FinmateType.money(style, weight: weight))
            .foregroundStyle(signMinor.map { FinmateColor.sign($0) } ?? Color.primary)
            .contentTransition(.numericText())
    }
}

// MARK: - SectionHeader

/// A section header — title (+ optional symbol) with an optional trailing action.
struct SectionHeader<Trailing: View>: View {
    let title: String
    var systemImage: String?
    var tint: Color = FinmateColor.bronze
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, systemImage: String? = nil, tint: Color = FinmateColor.bronze,
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            if let systemImage {
                Image(systemName: systemImage).foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
            Text(title).font(FinmateType.headline)
            Spacer()
            trailing()
        }
    }
}

// MARK: - StatTile / KPICard

/// A compact KPI tile — title + symbol over a big rounded-tabular value, on glass.
/// `StatTile` is the canonical name; `KPICard` is a thin alias kept for existing call
/// sites (Cash Flow). Both render identically.
struct StatTile: View {
    let title: String
    let value: String
    var symbol: String?
    var tint: Color = FinmateColor.bronze
    /// Optional sign-coloring of the value.
    var signMinor: Int64?
    var detail: String?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: FinmateSpacing.sm) {
                HStack(spacing: FinmateSpacing.xs + 2) {
                    if let symbol {
                        Image(systemName: symbol).foregroundStyle(tint)
                            .accessibilityHidden(true)
                    }
                    Text(title).font(FinmateType.caption).foregroundStyle(FinmateColor.labelSecondary)
                }
                Text(value)
                    .font(FinmateType.money(.title2, weight: .bold))
                    .foregroundStyle(signMinor.map { FinmateColor.sign($0) } ?? Color.primary)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if let detail {
                    Text(detail).font(FinmateType.footnote).foregroundStyle(FinmateColor.labelSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(detail.map { "\(title), \(value), \($0)" } ?? "\(title), \(value)")
    }
}

/// Alias kept for existing Cash Flow call sites (`KPICard(title:value:symbol:tint:)`).
struct KPICard: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color
    var body: some View {
        StatTile(title: title, value: value, symbol: symbol, tint: tint)
    }
}

// MARK: - GlassListRow

/// A leading icon + title/subtitle + trailing content row, on glass. Generic over the
/// trailing view so callers supply amount text, a chevron, controls, etc.
struct GlassListRow<Trailing: View>: View {
    var systemImage: String?
    var iconTint: Color = FinmateColor.bronze
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    init(systemImage: String? = nil, iconTint: Color = FinmateColor.bronze,
         title: String, subtitle: String? = nil,
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.systemImage = systemImage
        self.iconTint = iconTint
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        GlassCard {
            HStack(spacing: FinmateSpacing.lg) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.title2).frame(minWidth: 34)
                        .foregroundStyle(iconTint)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(FinmateType.headline)
                    if let subtitle {
                        Text(subtitle).font(FinmateType.caption).foregroundStyle(FinmateColor.labelSecondary)
                    }
                }
                Spacer()
                trailing()
            }
        }
    }
}

// MARK: - Prominent / secondary button-style helpers
//
// For controls that aren't plain `Button` (ShareLink, Link, Menu) — apply the Obsidian
// prominent glass style on iOS 26 with a `.borderedProminent` fallback. The bronze tint
// comes from the app-wide `.tint`.

extension View {
    /// Primary glass CTA style (`.glassProminent` on iOS 26, `.borderedProminent` below).
    @ViewBuilder func finmateProminent() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// Secondary glass style (`.glass` on iOS 26, `.bordered` below).
    @ViewBuilder func finmateGlassButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

// MARK: - Segmented control style (bronze selection)

extension View {
    /// Apply the Obsidian bronze accent to a segmented `Picker`. Uses `.tint` so the
    /// system segmented control carries the bronze selection without a custom redraw.
    func finmateSegmented() -> some View {
        self.pickerStyle(.segmented).tint(FinmateColor.bronze)
    }
}

// MARK: - EmptyState

/// A glass empty-state with an icon, message, and an optional primary CTA.
struct EmptyStateCard: View {
    let title: String
    let systemImage: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: FinmateSpacing.lg) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(FinmateColor.bronze)
                .accessibilityHidden(true)
            Text(title).font(FinmateType.headline)
            Text(message)
                .font(FinmateType.subheadline)
                .foregroundStyle(FinmateColor.labelSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                GlassButton(actionTitle, systemImage: "plus", kind: .primary, action: action)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(FinmateSpacing.xxl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(message)")
    }
}

// MARK: - Toast

/// A transient glass toast. Tones reuse the semantic palette.
struct Toast: View {
    enum Tone { case info, success, warning, error }
    let text: String
    var tone: Tone = .info

    var body: some View {
        HStack(spacing: FinmateSpacing.sm) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).font(FinmateType.subheadline.weight(.medium))
        }
        .padding(.horizontal, FinmateSpacing.lg)
        .padding(.vertical, FinmateSpacing.md)
        .glassSurface(cornerRadius: FinmateRadius.pill)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }

    private var symbol: String {
        switch tone {
        case .info:    return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.octagon.fill"
        }
    }
    private var tint: Color {
        switch tone {
        case .info:    return FinmateColor.bronze
        case .success: return FinmateColor.up
        case .warning: return FinmateColor.warning
        case .error:   return FinmateColor.down
        }
    }
}
