import SwiftUI

// MARK: - OBSIDIAN design tokens — docs/06 / docs/14
//
// The Obsidian identity: a near-monochrome ink/graphite palette with a single warm
// BRONZE signature accent, laid over a near-flat neutral background. Glass + content
// carry the depth (authentic iOS 26 Liquid Glass) — there is no multi-color ambient
// gradient. Semantic green=gain / red=loss / BTC-orange are kept (semantic, not brand).
//
// In production these live in a `DesignSystem` SPM package (docs/03); for the current
// executable slice they ship in the app target. One cohesive glass language.
//
// The light/dark hex values are the SAME TOKEN VALUES shared with the web client
// (web/src/styles/tokens). Colors resolve per `UITraitCollection` so every token is
// correct in light + dark + system.

// MARK: - Hex helpers

extension Color {
    /// Build a `Color` from a 6-digit RGB hex (e.g. 0x0B0C0E).
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }

    /// A light/dark dynamic color, resolved per trait collection.
    static func dynamic(light: Color, dark: Color) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }

    /// A light/dark dynamic color from hex + opacity pairs.
    static func dynamicHex(light: UInt32, lightOpacity: Double = 1,
                           dark: UInt32, darkOpacity: Double = 1) -> Color {
        dynamic(light: Color(hex: light).opacity(lightOpacity),
                dark: Color(hex: dark).opacity(darkOpacity))
    }
}

// MARK: - FinmateColor (the Obsidian palette)

/// The Obsidian palette. Backgrounds, surfaces and hairlines use the shared light/dark
/// token values; text uses the platform semantic colors where possible so Smart Invert
/// and increased-contrast behave correctly.
enum FinmateColor {

    // Backgrounds & surfaces (near-flat neutrals).
    static let background = Color.dynamicHex(light: 0xF3F3F5, dark: 0x0B0C0E)
    static let elevated   = Color.dynamicHex(light: 0xFFFFFF, dark: 0x15171B)
    static let surface    = Color.dynamicHex(light: 0xFFFFFF, dark: 0x1B1E23)
    static let surface2   = Color.dynamicHex(light: 0xFAFAFB, dark: 0x23262D)

    /// Hairline / divider.
    static let hairline = Color.dynamicHex(light: 0x000000, lightOpacity: 0.08,
                                           dark: 0xFFFFFF, darkOpacity: 0.10)

    // Text — prefer the platform semantic colors (they already track light/dark,
    // increased contrast, and Smart Invert).
    static let label          = Color.primary
    static let labelSecondary = Color.secondary
    static let labelTertiary  = Color(uiColor: .tertiaryLabel)

    // Signature accent.
    static let bronze     = Color.dynamicHex(light: 0x9A7544, dark: 0xC29A6A)
    static let bronzeDeep = Color.dynamicHex(light: 0x7E5F33, dark: 0xA07E50)

    /// Mono primary-action fill (high contrast) + its foreground.
    static let ink   = Color.dynamicHex(light: 0x1A1C20, dark: 0xF2F3F5)
    static let inkOn = Color.dynamicHex(light: 0xFFFFFF, dark: 0x15161A)

    // Semantic (kept — not brand).
    static let up      = Color.dynamicHex(light: 0x248A3D, dark: 0x34C759)
    static let down    = Color.dynamicHex(light: 0xD70015, dark: 0xFF453A)
    static let neutral = Color.dynamicHex(light: 0x8A8A8E, dark: 0x98989D)
    static let warning = Color.dynamicHex(light: 0xC8730A, dark: 0xFFB340)
    static let btc     = Color.dynamicHex(light: 0xE5860F, dark: 0xF7931A)

    // Glass fill / border (Materials-fallback tints; iOS 26 glassEffect carries its own).
    static let glassFill   = Color.dynamicHex(light: 0xFFFFFF, lightOpacity: 0.62,
                                              dark: 0xFFFFFF, darkOpacity: 0.06)
    static let glassBorder = Color.dynamicHex(light: 0xFFFFFF, lightOpacity: 0.70,
                                              dark: 0xFFFFFF, darkOpacity: 0.12)

    /// Sign-aware color for a signed minor amount.
    static func sign(_ minor: Int64) -> Color {
        if minor > 0 { return up }
        if minor < 0 { return down }
        return labelSecondary
    }

    // MARK: Money-flow (Sankey) ramp — mono + bronze (replaces the old violet).
    enum Flow {
        static let income        = FinmateColor.ink        // neutral ink
        static let fixed         = Color.dynamicHex(light: 0xB08A5A, dark: 0xB08A5A)
        static let variable      = Color.dynamicHex(light: 0xCDB089, dark: 0xCDB089)
        static let subscriptions = Color.dynamicHex(light: 0x8A6A42, dark: 0x8A6A42)
        static let savings       = FinmateColor.up
    }

    /// A bronze→tan monochrome ramp for category charts and allocation donuts. Cycles
    /// for indices beyond its length. Signed series should overlay `up`/`down`.
    static let chartRamp: [Color] = [
        FinmateColor.bronze,
        Color(hex: 0xB08A5A),
        Color(hex: 0xCDB089),
        FinmateColor.bronzeDeep,
        Color(hex: 0x8A6A42),
        Color(hex: 0xDCC8A6),
        FinmateColor.neutral,
        Color(hex: 0x6E5536),
    ]

    static func ramp(_ index: Int) -> Color { chartRamp[index % chartRamp.count] }
}

// MARK: - FinmateType (type ramp)

/// The Obsidian type ramp — mapped to the platform text styles so Dynamic Type scales
/// everything, with a dedicated rounded, tabular numeric face for money/figures.
enum FinmateType {
    static let largeTitle = Font.largeTitle
    static let title      = Font.title
    static let title2     = Font.title2
    static let title3     = Font.title3
    static let headline   = Font.headline
    static let body       = Font.body
    static let callout    = Font.callout
    static let subheadline = Font.subheadline
    static let footnote   = Font.footnote
    static let caption    = Font.caption
    static let caption2   = Font.caption2

    /// Rounded, tabular numeric money face at a given text style + weight. Tabular
    /// digits keep columns of figures aligned; rounded matches the Obsidian numerals.
    static func money(_ style: Font.TextStyle = .body, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .rounded).weight(weight).monospacedDigit()
    }
}

// MARK: - Scales

enum FinmateSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
}

enum FinmateRadius {
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 22
    static let xl: CGFloat = 28
    static let pill: CGFloat = 999
}

enum FinmateMotion {
    static let fast: TimeInterval = 0.15
    static let base: TimeInterval = 0.25
    static let slow: TimeInterval = 0.40

    /// Spring used for glass morphs (gate on reduce-motion at the call site).
    static let glassSpring: Animation = .spring(response: 0.40, dampingFraction: 0.82)
    static let baseEase: Animation = .easeInOut(duration: base)
    static let fastEase: Animation = .easeInOut(duration: fast)
}

// MARK: - Legacy token shim
//
// The codebase references `FinmateTokens.{cornerRadius,cardPadding,spacing}` widely.
// Keep the names mapped onto the new scales so feature views compile unchanged while
// the new `FinmateRadius`/`FinmateSpacing` scales become the canonical source.
enum FinmateTokens {
    static let cornerRadius: CGFloat = FinmateRadius.lg
    static let cardPadding: CGFloat = FinmateSpacing.lg
    static let spacing: CGFloat = FinmateSpacing.md
}
