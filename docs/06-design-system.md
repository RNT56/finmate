# Liquid Glass Design System

> The single, cohesive visual language for Finmate — Apple-grade Liquid Glass on iOS 26+, with automatic Materials fallback on iOS 18–25. This is the authoritative reference for tokens, components, motion, haptics, iconography, and accessibility.

This document defines **one** design language. It explicitly replaces Substimate's nine competing styles (aurora, brutalist, claymorphism, glassmorphism, minimal, modern, neobrutalist, neumorphism, retro) with a single, opinionated, native iOS system. Every value here is a concrete starting point: real hex/HSL, real point sizes, real Swift. It is implemented in the `DesignSystem` Swift Package (see [System & Client Architecture](./03-architecture.md)) and consumed by every `Features/*` module.

---

## Table of contents

1. [Design principles](#1-design-principles)
2. [The Liquid Glass material strategy](#2-the-liquid-glass-material-strategy)
3. [Design tokens — color](#3-design-tokens--color)
4. [Design tokens — typography](#4-design-tokens--typography)
5. [Design tokens — spacing, radii, elevation](#5-design-tokens--spacing-radii-elevation)
6. [Design tokens — materials, motion, haptics](#6-design-tokens--materials-motion-haptics)
7. [Component library](#7-component-library)
8. [Charts & data-visualization styling](#8-charts--data-visualization-styling)
9. [Iconography](#9-iconography)
10. [Accessibility](#10-accessibility)
11. [Internationalization & formatting](#11-internationalization--formatting)
12. [Package layout & token codegen](#12-package-layout--token-codegen)
13. [What this replaces from Substimate](#13-what-this-replaces-from-substimate)
14. [Definition of Done for a component](#14-definition-of-done-for-a-component)
15. [Related documents](#15-related-documents)

---

## 1. Design principles

Finmate's design is grounded in the three pillars of the Apple Human Interface Guidelines — **Clarity, Deference, Depth** — extended with finance-specific rules.

| Principle | What it means in Finmate | Concrete rule |
| --- | --- | --- |
| **Clarity** | Money is legible at a glance. Numbers never lie or blur. | Currency amounts use the monospaced-digit font feature so columns align; financial sign is conveyed by color **and** glyph (`arrow.up.right` / `arrow.down.right`), never color alone. |
| **Deference** | The UI gets out of the way of the user's data. Glass defers to content behind it. | Glass surfaces are translucent over content, never over a flat brand wash. Chrome (tab bar, toolbars) is the *only* persistent glass; content cards earn glass only when floating above a scroll. |
| **Depth** | Layering communicates hierarchy and navigational position. | Exactly three z-layers: **Background** (scene), **Content** (scroll), **Chrome/Floating** (glass). No nested glass-on-glass (it muddies and kills legibility — see [§2.4](#24-rules-glass-hygiene)). |
| **One language** | A single Liquid Glass identity, light/dark/system. | No user-selectable "visual styles." The only appearance choice is `system \| light \| dark` (stored in `UserPreferences.appearance`). |
| **Calm & trustworthy** | A finance app must feel safe and unhurried. | Motion is purposeful and short (≤ 0.4s), haptics are restrained, accent color is used sparingly to mark the single most important action per screen. |
| **Accessible by default** | First-class Dynamic Type, VoiceOver, Reduce Motion/Transparency. | Every component ships with VoiceOver labels and respects `accessibilityReduceTransparency` / `accessibilityReduceMotion`. This is a hard gate in the Definition of Done. |

### 1.1 Design north star

Liquid Glass is the **signature material**. It is the lensing, light-refracting, content-aware translucent surface introduced across the Apple platforms with iOS 26. Where the OS provides it (`glassEffect`, `GlassEffectContainer`, `.glass` / `.glassProminent` button styles, scroll-edge effects), Finmate uses it directly. Where it does not (iOS 18–25), Finmate falls back to system **Materials** (`.ultraThinMaterial`, `.thinMaterial`, `.regularMaterial`, `.thickMaterial`, available since iOS 15) so that the app looks correct and premium on the entire supported range. The fallback is automatic and centralized in a single modifier (see [§2.2](#22-the-reusable-modifier-glassbackground)).

---

## 2. The Liquid Glass material strategy

### 2.1 Capability tiers

| Tier | iOS range | Surface technology | Notes |
| --- | --- | --- | --- |
| **A — Liquid Glass** | iOS 26.0+ | `glassEffect(_:in:)`, `GlassEffectContainer`, `glassEffectID(_:in:)`, `.buttonStyle(.glass)` / `.glassProminent`, automatic scroll-edge effects on `NavigationStack`/`TabView`/toolbars | Design-complete experience. Light refraction, specular highlights, blending between adjacent glass shapes. |
| **B — Materials fallback** | iOS 18.0–25.x | `.background(.ultraThinMaterial)` / `.regularMaterial` / `.thickMaterial` behind a rounded shape, `.bordered` / `.borderedProminent` button styles | Visually premium, no refraction. The minimum deployment target is **iOS 18.0** (see [Tech Stack](./04-tech-stack.md) and [ADR-0004](./12-decisions-adr.md)). |
| **C — Reduce Transparency** | any iOS, when `accessibilityReduceTransparency == true` | Opaque solid fill from semantic color tokens, hairline border | Both tiers above collapse to this when the user has enabled Reduce Transparency. Mandatory for legibility and a system requirement. |

We **never** branch on OS version inline in feature code. All branching lives in the `DesignSystem` package behind the `GlassBackground` modifier and the `GlassButtonStyle`.

### 2.2 The reusable modifier: `glassBackground`

A single `ViewModifier` encapsulates all three tiers. Feature code only ever writes `.glassBackground(.card)`.

```swift
// DesignSystem/Sources/DesignSystem/Glass/GlassBackground.swift
import SwiftUI

/// The role a glass surface plays. Drives intensity, tint, and fallback material.
public enum GlassRole: Sendable {
    case card           // floating content card
    case chrome         // tab bar / toolbar / nav surface
    case prominent      // a highlighted, attention-drawing surface (e.g. primary CTA tray)
    case sheetHeader    // grab-handle area / sticky sheet header

    /// Fallback Material for Tier B (iOS 18–25).
    var fallbackMaterial: Material {
        switch self {
        case .card:         return .regularMaterial
        case .chrome:       return .ultraThinMaterial
        case .prominent:    return .thickMaterial
        case .sheetHeader:  return .ultraThinMaterial
        }
    }
}

public struct GlassBackground: ViewModifier {
    let role: GlassRole
    let shape: AnyShape
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    public func body(content: Content) -> some View {
        if reduceTransparency {
            // Tier C — opaque, always legible.
            content
                .background(Color.fmSurfaceOpaque, in: shape)
                .overlay(shape.strokeBorder(Color.fmHairline, lineWidth: 0.5))
        } else if #available(iOS 26.0, *) {
            // Tier A — Liquid Glass.
            content
                .glassEffect(role == .prominent ? .regular.tint(Color.fmAccent.opacity(0.18)) : .regular,
                             in: shape)
        } else {
            // Tier B — Materials.
            content
                .background(role.fallbackMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.fmHairline, lineWidth: 0.5))
        }
    }
}

public extension View {
    /// Apply Finmate glass for a given role, defaulting to a continuous rounded rect.
    func glassBackground(_ role: GlassRole,
                         shape: some Shape = RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)) -> some View {
        modifier(GlassBackground(role: role, shape: AnyShape(shape)))
    }
}
```

### 2.3 Grouping glass: `GlassEffectContainer`

When multiple glass shapes sit near each other (e.g. a floating toolbar with several pill buttons, or a morphing Add menu), wrap them in a `GlassEffectContainer` on Tier A so the system blends their edges and renders one cohesive lensing pass instead of N independent blurs. `glassEffectID` enables matched-geometry morphing between states (e.g. the `+` button expanding into a quick-add menu).

```swift
// Same source on every tier: GlassEffectContainerCompat is the real GlassEffectContainer on
// Tier A and a no-op HStack/ZStack on Tier B (iOS 18–25); glassEffectID is itself a no-op on the
// fallback path, so the buttons simply render with material backgrounds.
struct QuickAddCluster: View {
    @Namespace private var glassNS
    @State private var expanded = false

    var body: some View {
        GlassEffectContainerCompat(spacing: Spacing.sm) {
            if expanded {
                ForEach(QuickAddItem.allCases) { item in
                    QuickAddPill(item: item)
                        .glassEffectID(item.id, in: glassNS)
                }
            }
            AddButton(isExpanded: $expanded)
                .glassEffectID("add", in: glassNS)
        }
        .animation(Motion.springStandard, value: expanded)
    }
}
```

A `GlassEffectContainerCompat` wrapper in `DesignSystem` provides a no-op container (just an `HStack`/`ZStack`) on iOS 18–25 so the same call site compiles and renders.

### 2.4 Rules (glass hygiene)

- [ ] **No glass-on-glass.** A glass card never sits inside another glass surface. Content layer is solid; only chrome and one floating layer are glass.
- [ ] **Glass needs content behind it.** Never place glass directly over `Color.fmBackground`. If there is nothing to refract, use a solid `fmSurface` card instead.
- [ ] **Text on glass is always on a legible substrate.** Body text over busy glass must have either a solid inner fill or a `.shadow`/vibrancy treatment. Prefer `foregroundStyle(.primary)` which the system tunes for vibrancy on Tier A.
- [ ] **One prominent glass per screen.** `GlassRole.prominent` (and `.glassProminent` buttons) marks the single primary action. Multiple prominent surfaces dilute hierarchy.
- [ ] **Respect scroll-edge effects.** On Tier A, do not hand-roll gradient scrims at the top of scroll views; the system scroll-edge effect handles the chrome blur. On Tier B, the `ScrollEdgeScrim` view from `DesignSystem` provides an equivalent gradient.

---

## 3. Design tokens — color

All colors are defined once in `DesignSystem` as an Asset Catalog (`Colors.xcassets`) with **Any Appearance / Dark Appearance** variants, plus a typed Swift accessor (`Color.fm…`). Feature code never writes a literal hex or a system color directly. The `fm` prefix prevents collisions with SwiftUI's `Color` statics.

### 3.1 Semantic roles

| Token | Role | Light (hex) | Dark (hex) | Backed by |
| --- | --- | --- | --- | --- |
| `fmBackground` | App scene background (base layer) | `#F2F3F7` | `#0B0C0F` | custom |
| `fmBackgroundElevated` | Grouped background behind cards | `#FFFFFF` | `#15171C` | custom |
| `fmSurface` | Solid card / row surface | `#FFFFFF` | `#1B1E25` | custom |
| `fmSurfaceOpaque` | Reduce-Transparency glass replacement | `#FFFFFF` | `#20232B` | custom |
| `fmHairline` | 0.5pt separators & glass borders | `#00000014` (8% black) | `#FFFFFF1F` (12% white) | custom |
| `fmLabel` | Primary text | `#0A0A0A` | `#FFFFFF` | maps to `Color.primary` |
| `fmLabelSecondary` | Secondary text | `#3C3C4399` (60%) | `#EBEBF599` (60%) | maps to `Color.secondary` |
| `fmLabelTertiary` | Tertiary / placeholder | `#3C3C434D` (30%) | `#EBEBF54D` (30%) | custom |
| `fmAccent` | Brand accent / primary tint | `#0A84FF` | `#0A84FF` | custom |
| `fmAccentPressed` | Accent, pressed state | `#0066D6` | `#3B9BFF` | custom |
| `fmSeparatorOpaque` | Opaque list separator | `#C6C6C8` | `#38383A` | maps to `.separator` |

The **accent** is a single, calm blue (`#0A84FF`, HSL `211°, 100%, 52%`) — the iOS system blue tuned slightly toward vibrancy. Finmate uses exactly one brand accent; we deliberately do not ship a user-pickable accent in v1 (revisit post-v1; see [ADR-0009](./12-decisions-adr.md)). Accent appears on at most one primary action per screen, on selection states, and on focus rings.

### 3.2 Financial semantic colors

Money direction is a first-class semantic concern. These are **separate** from the chart palette and from the brand accent so that "up/down" reads consistently everywhere (KPI tiles, transaction rows, deltas, the cash-flow Sankey).

| Token | Meaning | Light (hex) | Dark (hex) | Paired glyph (color-independence) |
| --- | --- | --- | --- | --- |
| `fmFinancialUp` | Income, gains, positive delta | `#1F9D55` (HSL `147°,67%,37%`) | `#30D158` | `arrow.up.right` |
| `fmFinancialDown` | Expense, loss, negative delta | `#D7263D` (HSL `352°,70%,50%`) | `#FF6961` | `arrow.down.right` |
| `fmFinancialNeutral` | No change / flat | `#8A8A8E` | `#98989D` | `minus` |
| `fmFinancialWarning` | Over-budget, unused subscription | `#E8830C` (HSL `33°,89%,48%`) | `#FFB340` | `exclamationmark.triangle.fill` |
| `fmBTC` | Bitcoin / sats context | `#F7931A` (HSL `33°,93%,54%`) | `#FFA62B` | `bitcoinsign.circle.fill` |

`fmBTC` is the canonical Bitcoin orange carried over from Substimate (`#f7931a`). In Substimate it was wired through an ad-hoc `data-currency="BTC"` override of `--highlight-color`; in Finmate it is a fixed semantic token applied **only** in BTC/sats contexts (the crypto calculator, sats-denominated values, the BTC series in charts) and **never** repurposed as a global highlight.

> Red/green color-blindness rule: financial up/down must **always** be accompanied by the paired glyph and, in lists, a leading sign (`+` / `−`). See [§10.5](#105-color-independence).

### 3.3 Chart palette

A categorical palette of 7 + BTC, lifted and de-duplicated from Substimate's chart variables (it shipped the same seven hues across all nine themes) and re-tuned for WCAG contrast on both `fmBackgroundElevated` surfaces. Defined as an ordered array `ChartPalette.categorical` and exposed to Swift Charts via `.chartForegroundStyleScale`.

| Slot | Name | Light (hex) | Dark (hex) | Typical use |
| --- | --- | --- | --- | --- |
| 1 | Emerald | `#10B981` | `#34D399` | Income / primary positive series |
| 2 | Amber | `#F59E0B` | `#FBBF24` | Warning / secondary |
| 3 | Blue | `#3B82F6` | `#60A5FA` | Neutral category |
| 4 | Violet | `#8B5CF6` | `#A78BFA` | Category |
| 5 | Pink | `#EC4899` | `#F472B6` | Category |
| 6 | Red | `#EF4444` | `#F87171` | Expense / negative series |
| 7 | Orange | `#F97316` | `#FB923C` | Category |
| BTC | Bitcoin | `#F7931A` | `#FFA62B` | BTC/sats series (fixed, never reassigned) |

Chart support tokens: grid lines `fmHairline`; axis & tick labels `fmLabelSecondary`; area-fill gradient is `series color → series color @ 8% opacity` top-to-bottom. Slot 6 (Red) and slot 1 (Emerald) intentionally match `fmFinancialDown`/`fmFinancialUp` in hue family so income/expense series read consistently with KPI tiles.

### 3.4 SwiftUI accessor pattern

```swift
// DesignSystem/Sources/DesignSystem/Color+Tokens.swift
import SwiftUI

public extension Color {
    static let fmBackground         = Color("fmBackground", bundle: .module)
    static let fmBackgroundElevated = Color("fmBackgroundElevated", bundle: .module)
    static let fmSurface            = Color("fmSurface", bundle: .module)
    static let fmSurfaceOpaque      = Color("fmSurfaceOpaque", bundle: .module)
    static let fmHairline           = Color("fmHairline", bundle: .module)
    static let fmAccent             = Color("fmAccent", bundle: .module)
    static let fmAccentPressed      = Color("fmAccentPressed", bundle: .module)
    static let fmFinancialUp        = Color("fmFinancialUp", bundle: .module)
    static let fmFinancialDown      = Color("fmFinancialDown", bundle: .module)
    static let fmFinancialNeutral   = Color("fmFinancialNeutral", bundle: .module)
    static let fmFinancialWarning   = Color("fmFinancialWarning", bundle: .module)
    static let fmBTC                = Color("fmBTC", bundle: .module)
}

/// Direction of a monetary value — drives both color and glyph.
public enum MoneyDirection { case up, down, flat
    public var color: Color {
        switch self { case .up: .fmFinancialUp; case .down: .fmFinancialDown; case .flat: .fmFinancialNeutral }
    }
    public var symbolName: String {
        switch self { case .up: "arrow.up.right"; case .down: "arrow.down.right"; case .flat: "minus" }
    }
}
```

---

## 4. Design tokens — typography

Finmate uses the system fonts only: **SF Pro** (text/display), **SF Pro Rounded** (numeric emphasis on KPI tiles, optional), and **SF Mono** is *not* used — instead we apply the monospaced-digit feature to SF Pro for tabular number alignment. All text scales with **Dynamic Type** via SwiftUI text styles; we never hard-code an unscaled `.font(.system(size:))` for body content.

### 4.1 Type ramp

The ramp maps Finmate roles onto the standard iOS text styles (base sizes at the Large content size category). Using the named styles is what guarantees Dynamic Type for free.

| Finmate role | Text style | Base size / leading (pt) | Weight | Notes |
| --- | --- | --- | --- | --- |
| `displayXL` | `.largeTitle` | 34 / 41 | Bold | Onboarding hero, big balance numbers |
| `display` | `.title` | 28 / 34 | Bold | Screen-level totals (e.g. monthly spend) |
| `titleM` | `.title2` | 22 / 28 | Semibold | Section headers, sheet titles |
| `titleS` | `.title3` | 20 / 25 | Semibold | Card titles |
| `headline` | `.headline` | 17 / 22 | Semibold | List row primary label |
| `body` | `.body` | 17 / 22 | Regular | Default reading text |
| `callout` | `.callout` | 16 / 21 | Regular | Secondary descriptions |
| `subheadline` | `.subheadline` | 15 / 20 | Regular | Row subtitles, metadata |
| `footnote` | `.footnote` | 13 / 18 | Regular | Captions, helper text |
| `caption` | `.caption` | 12 / 16 | Regular | Chart axis labels, timestamps |
| `caption2` | `.caption2` | 11 / 13 | Regular | Legal / fine print |

### 4.2 Numeric & currency type

Monetary values use `.monospacedDigit()` so that digits occupy fixed advance widths and amounts align in columns (transaction lists, the asset table, KPI grids). Large hero balances may opt into SF Pro Rounded for warmth.

```swift
public extension Font {
    /// Hero balance figure — rounded, mono-digit, scales with Dynamic Type from .largeTitle.
    static func fmBalanceHero() -> Font {
        .system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit()
    }
    /// Inline amount in a row — mono-digit body.
    static func fmAmount() -> Font {
        .system(.body, design: .default).monospacedDigit()
    }
}
```

> The `Money` value type ([Data Model](./05-data-model.md)) formats from `Int64` minor units via `Decimal` + `Decimal.FormatStyle.Currency`; the design system only governs *how* the resulting string is typeset, never the arithmetic.

### 4.3 Typography rules

- [ ] Always use a named text style (or a `Font.fm…` built from one) so Dynamic Type works.
- [ ] Cap line length on iPhone with `.frame(maxWidth:)` only for long-form legal copy; normal content is full-width with system margins.
- [ ] Never disable Dynamic Type; if a layout breaks at AX5 (largest accessibility size), the layout is wrong — reflow it (see [§10.1](#101-dynamic-type)).
- [ ] Use `.fontWeight(.semibold)` for emphasis, never all-caps tracking hacks.

---

## 5. Design tokens — spacing, radii, elevation

### 5.1 Spacing scale

A 4pt base grid. Defined as an enum of `CGFloat` constants; layouts compose from these only.

```swift
public enum Spacing {
    public static let xxs: CGFloat = 2
    public static let xs:  CGFloat = 4
    public static let sm:  CGFloat = 8
    public static let md:  CGFloat = 12
    public static let lg:  CGFloat = 16   // default content inset
    public static let xl:  CGFloat = 24
    public static let xxl: CGFloat = 32
    public static let xxxl: CGFloat = 48
}
```

Default screen content inset is `Spacing.lg` (16pt) horizontal. Card internal padding is `Spacing.lg`. Vertical rhythm between sections is `Spacing.xl` (24pt).

### 5.2 Corner radii

iOS 26 Liquid Glass and the wider system favor **continuous** (squircle) corners and capsule shapes. All rounded rects use `style: .continuous`.

```swift
public enum Radius {
    public static let xs: CGFloat = 6     // chips, small controls
    public static let sm: CGFloat = 10    // inputs, list-row inner art
    public static let md: CGFloat = 14    // buttons, small cards
    public static let lg: CGFloat = 20    // standard glass card
    public static let xl: CGFloat = 28    // sheets, large hero cards
    public static let capsule: CGFloat = .infinity  // pills, primary CTAs, tab indicators
}
```

### 5.3 Elevation & shadow

Finmate uses **light, diffuse** shadows — depth comes primarily from glass and layering, not heavy drop shadows. Two shadow tokens only.

| Token | Use | Spec (light) | Spec (dark) |
| --- | --- | --- | --- |
| `Elevation.resting` | Cards on a scroll | `color: black 6%`, `radius: 12`, `y: 4` | `color: black 30%`, `radius: 14`, `y: 6` |
| `Elevation.floating` | Sheets, popovers, the floating tab bar | `color: black 12%`, `radius: 24`, `y: 10` | `color: black 45%`, `radius: 28`, `y: 12` |

```swift
public enum Elevation {
    case resting, floating
    var color: Color { /* uses fmShadow asset (auto light/dark) */ Color("fmShadow", bundle: .module) }
    var radius: CGFloat { self == .resting ? 12 : 24 }
    var yOffset: CGFloat { self == .resting ? 4 : 10 }
}

public extension View {
    func elevation(_ e: Elevation) -> some View {
        shadow(color: e.color, radius: e.radius, x: 0, y: e.yOffset)
    }
}
```

> On Tier A, glass already produces its own subtle separation; apply `Elevation.resting` to glass cards only when they float over scrolling content, and never to chrome (the system handles chrome separation).

---

## 6. Design tokens — materials, motion, haptics

### 6.1 Materials reference (Tier B mapping)

| Semantic surface | Tier A (iOS 26+) | Tier B (iOS 18–25) | Tier C (Reduce Transparency) |
| --- | --- | --- | --- |
| Tab bar / toolbar chrome | `glassEffect(.regular)` + system chrome | `.ultraThinMaterial` | `fmSurfaceOpaque` |
| Floating card | `glassEffect(.regular)` | `.regularMaterial` | `fmSurface` |
| Primary CTA tray | `glassEffect(.regular.tint(accent 18%))` | `.thickMaterial` | `fmSurface` + accent border |
| Sheet header / grabber | `glassEffect(.regular)` | `.ultraThinMaterial` | `fmSurfaceOpaque` |
| Scrim behind modal | system dimming | `Color.black.opacity(0.32)` | `Color.black.opacity(0.48)` |

### 6.2 Motion — curves & durations

Motion is short, spring-led, and purposeful. All animations route through the `Motion` namespace so timing is consistent and reduce-motion is enforced centrally.

```swift
public enum Motion {
    /// Standard UI spring — buttons, card appearance, selection. ~0.35s settle.
    public static let springStandard = Animation.spring(response: 0.35, dampingFraction: 0.85)
    /// Snappy spring for taps & toggles. ~0.25s.
    public static let springSnappy   = Animation.spring(response: 0.25, dampingFraction: 0.9)
    /// Gentle spring for sheets & large surfaces. ~0.45s.
    public static let springGentle   = Animation.spring(response: 0.45, dampingFraction: 0.82)
    /// Linear-ish fade for cross-dissolves. 0.2s.
    public static let fade           = Animation.easeInOut(duration: 0.2)
    /// Glass morph (GlassEffectContainer transitions). 0.4s.
    public static let glassMorph     = Animation.spring(response: 0.4, dampingFraction: 0.8)
}
```

Duration ceilings: interaction feedback ≤ 0.25s, content transitions ≤ 0.35s, large surface (sheet) ≤ 0.45s. Nothing in normal use exceeds 0.45s.

**Reduce Motion handling** — a single helper swaps springs for a cross-fade and disables parallax/large translations:

```swift
public extension View {
    /// Use this instead of `.animation(_:value:)` for non-essential motion.
    func fmAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(ReduceMotionAware(animation: animation, value: value))
    }
}

private struct ReduceMotionAware<V: Equatable>: ViewModifier {
    let animation: Animation; let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.animation(reduceMotion ? Motion.fade : animation, value: value)
    }
}
```

### 6.3 Haptics

Haptics use `UIFeedbackGenerator` wrapped in a `Sendable`, `@MainActor` `Haptics` service injected via `@Environment`. They are **restrained** — finance users should not be buzzed for routine reads. Haptics respect a user setting (`UserPreferences`) and the system "Haptics" toggle.

| Event | Generator | When |
| --- | --- | --- |
| Selection change (segmented control, picker tick) | `UISelectionFeedbackGenerator.selectionChanged()` | Stepping through pickers, currency selector |
| Primary action committed (save subscription, confirm) | `UINotificationFeedbackGenerator(.success)` | Successful optimistic write |
| Destructive confirmed (delete) | `UIImpactFeedbackGenerator(.rigid)` | After confirm in destructive flow |
| Error / validation fail | `UINotificationFeedbackGenerator(.error)` | Form validation failure, sync conflict surfaced |
| Light press feedback (drag handle pickup on dashboard) | `UIImpactFeedbackGenerator(.light)` | Begin reorder drag |

```swift
@MainActor public final class Haptics: Sendable {
    public init() {}
    public func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    public func success()   { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    public func error()     { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    public func impact(_ s: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: s).impactOccurred()
    }
}
```

---

## 7. Component library

All components live in `DesignSystem/Sources/DesignSystem/Components/`. They are appearance-agnostic (use only tokens), accessibility-complete, and have SwiftUI previews + snapshot tests (`swift-snapshot-testing`). Each subsection lists the public API and the key visual spec.

### 7.1 Buttons

Three button styles, mapped across tiers.

| Finmate style | Tier A | Tier B | Use |
| --- | --- | --- | --- |
| `.fmPrimary` | `.buttonStyle(.glassProminent)` tinted `fmAccent` | `.borderedProminent` tint `fmAccent` | The single primary action per screen |
| `.fmSecondary` | `.buttonStyle(.glass)` | `.bordered` | Secondary actions |
| `.fmPlain` | `.buttonStyle(.plain)` + `fmAccent` label | same | Inline text actions, toolbar items |

```swift
public struct FMPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        return configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)        // ≥ 44pt tap target (see §10.4)
            .foregroundStyle(.white)
            .background {
                if reduceTransparency {
                    shape.fill(configuration.isPressed ? Color.fmAccentPressed : .fmAccent)
                } else if #available(iOS 26.0, *) {
                    shape.fill(.clear).glassEffect(.regular.tint(.fmAccent.opacity(configuration.isPressed ? 0.5 : 0.35)), in: shape)
                } else {
                    shape.fill(configuration.isPressed ? Color.fmAccentPressed : .fmAccent)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .fmAnimation(Motion.springSnappy, value: configuration.isPressed)
    }
}
```

- Minimum height **50pt** (comfortably exceeds the 44pt HIG tap target).
- Pressed state: 0.98 scale + tint deepen, never a hard color flip.
- Destructive buttons use `role: .destructive` and `fmFinancialDown` tint.

### 7.2 Cards (glass cards)

The workhorse container. `GlassCard` wraps arbitrary content with role-based glass, padding, radius, and optional resting elevation.

```swift
public struct GlassCard<Content: View>: View {
    var padding: CGFloat = Spacing.lg
    var elevated: Bool = true
    @ViewBuilder var content: () -> Content
    public var body: some View {
        content()
            .padding(padding)
            .glassBackground(.card)
            .modifier(ConditionalElevation(on: elevated))   // applies Elevation.resting when floating
    }
}
```

Spec: radius `Radius.lg` (20pt), padding `Spacing.lg`, hairline border on Tier B/C, resting elevation when floating over scroll. Cards never nest in cards.

### 7.3 List rows

A standard `FMListRow` with leading category icon (in a tinted rounded container), title/subtitle, and trailing amount with `MoneyDirection` color + sign. Used for subscriptions, transactions, income sources, fixed expenses.

```swift
public struct FMListRow: View {
    let icon: CategoryIcon
    let title: String
    let subtitle: String?
    let amount: AttributedString      // formatted by Money; carries +/− sign
    let direction: MoneyDirection
    public var body: some View {
        HStack(spacing: Spacing.md) {
            CategoryIconBadge(icon: icon)            // 40×40, Radius.sm tinted container
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
            }
            Spacer(minLength: Spacing.md)
            Text(amount)
                .font(.fmAmount())
                .foregroundStyle(direction.color)
        }
        .padding(.vertical, Spacing.sm)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.a11yLabel(title, subtitle, amount, direction))
    }
}
```

Rows live inside a `List` with `.listStyle(.insetGrouped)` and `.scrollContentBackground(.hidden)` so the `fmBackground` shows through; section backgrounds use `fmSurface`.

### 7.4 Tab bar & navigation

- **Root** is a `TabView` with the 5 canonical tabs (Home, Subscriptions, Cash Flow, Calendar, More) — see [Product Spec](./02-product-spec.md). On Tier A the tab bar is automatically Liquid Glass and adopts scroll-edge effects; on Tier B it uses `.ultraThinMaterial`. We rely on the system tab bar (no custom bar) so it inherits the correct OS behavior per version.
- **Stacks** use `NavigationStack` with typed paths driven by the router/coordinator from [Architecture](./03-architecture.md). Large titles by default (`.navigationBarTitleDisplayMode(.large)`), collapsing to inline on scroll.
- **The contextual Add (+)** is a prominent toolbar/overlay action. On Tier A it can morph via `GlassEffectContainer`/`glassEffectID` into a quick-add cluster ([§2.3](#23-grouping-glass-glasseffectcontainer)); on Tier B it presents a standard `confirmationDialog` or sheet menu.

### 7.5 Sheets & modals

- Use SwiftUI `.sheet` with `.presentationDetents([.medium, .large])` and `.presentationDragIndicator(.visible)` for add/edit flows (Add Subscription, Add Expense, Transaction).
- Sheet container: corner radius `Radius.xl` (system-provided), `fmBackgroundElevated` content, sticky header via `.sheetHeader` glass role.
- `.presentationBackground(.regularMaterial)` on Tier B; the system supplies glass on Tier A.
- Confirmation of destructive actions uses `confirmationDialog` (action sheet), not a custom modal.

### 7.6 Inputs & forms

`FMTextField`, `FMSecureField`, and `FMFormSection` standardize form chrome.

- Field surface: `fmSurface` fill, `Radius.sm`, hairline border, `fmAccent` 1.5pt focus ring on `@FocusState`.
- Inline validation message below the field in `footnote` weight, `fmFinancialDown` color + `exclamationmark.circle` glyph.
- Forms group into `FMFormSection` with a `headline` header and `footnote` footer help text.
- Keyboard: appropriate `.keyboardType` (`.decimalPad` for amounts, `.URL` for vendor URL, `.emailAddress` for auth), `.textContentType` for autofill (`.password`, `.oneTimeCode`), and `.submitLabel`.

### 7.7 Currency / amount input

A bespoke `AmountField` is the most important input in the app. It edits an `Int64` minor-unit value, never a `Double`.

- Displays a leading currency symbol/picker chip (EUR `€`, USD `$`, BTC shows `₿`/sats toggle).
- Uses `.decimalPad`; the formatter respects the locale's decimal separator and the currency's minor-unit exponent (2 for EUR/USD, 0 for sats — `satsPerBTC = 100_000_000`).
- Parses input through the `Money` type so the stored value is exact minor units; the field never round-trips through binary floating point.
- BTC mode tints the symbol with `fmBTC` and offers a BTC⇄sats unit toggle.
- VoiceOver reads the full formatted amount + currency name (e.g. "12 euros 99 cents").

```swift
public struct AmountField: View {
    @Binding var minorUnits: Int64
    let currency: CurrencyCode
    @FocusState private var focused: Bool
    // body: currency chip + TextField bound through a Money parse/format value binding…
}
```

### 7.8 Pickers, date picker, segmented controls

- **Currency selector**: a menu/picker of allowed currencies (EUR, USD, BTC initially; extensible) with code + symbol; selection triggers `Haptics.selection()`.
- **Category picker**: a grid/list of user categories with their icon + tint. `All` and `Favorites` appear here as **presentation-layer pseudo-filters**, not as category rows; only the seeded, non-deletable `Other` category is a real row ([§9.3](#93-category-icons)).
- **Date picker**: prefer the native `DatePicker` (graphical for due-date selection, compact for inline). The payday calendar uses a bespoke `MonthGridCalendar` in `DesignSystem` that highlights payday and upcoming-charge days with `fmFinancialUp`/`fmFinancialWarning` dots — this replaces Substimate's hand-rolled `DatePicker.tsx`.
- **Segmented control / timeframe selector**: `Picker(.segmented)` styled with tokens; used for chart timeframe (Week/Month/Quarter/Year), wired to selection haptics.

### 7.9 Toasts & notifications

A lightweight, non-blocking `Toast` overlay for optimistic-update feedback ("Subscription added", "Synced", "Offline — will sync"). Carried over conceptually from Substimate's toast pattern, rebuilt natively.

- Appears as a floating glass capsule (`GlassRole.prominent`, `Radius.capsule`) anchored near the top safe area, auto-dismiss after 2.5s, swipe-up to dismiss.
- Variants: `.success` (`fmFinancialUp` + `checkmark.circle.fill`), `.error` (`fmFinancialDown` + `xmark.octagon.fill`), `.info` (`fmAccent` + `info.circle.fill`), `.offline` (`fmFinancialNeutral` + `wifi.slash`).
- Presented via an environment `ToastCenter` (`@Observable`) so any view can `toast(.success("Saved"))`.
- VoiceOver: posts an `.announcement` notification so it is read aloud; never the only channel for critical info.

### 7.10 Empty states

`FMEmptyState` — a centered glyph (bespoke or SF Symbol, ~48pt, `fmLabelTertiary`), a `titleS` headline, a `subheadline` body, and an optional `.fmPrimary` CTA. Examples: "No subscriptions yet — add your first" with a `plus.circle` glyph; "No upcoming charges this month" on the calendar. Empty states are never blank; they always teach the next action.

### 7.11 Skeletons & loaders

- **Skeleton**: `SkeletonView` renders token-shaped placeholders (rounded rects at `Radius.sm`) with a shimmer that uses `Motion.fade` and is **disabled** under Reduce Motion (falls back to a static `fmLabelTertiary` 12% fill). Used while the local cache warms or first sync runs.
- **Inline spinner**: `ProgressView()` tinted `fmAccent` for in-row loads.
- **Pull-to-refresh**: native `.refreshable` triggering a repository resync.
- Because the app is **offline-first** ([Architecture](./03-architecture.md)), skeletons are rare — the local cache usually serves reads instantly; skeletons appear mainly on first launch / cold cache.

### 7.12 Customizable dashboard card

The Home dashboard is a reorderable grid of cards whose order is persisted in `DashboardLayout` ([Data Model](./05-data-model.md)). This replaces Substimate's `DraggableDashboardCard`/`DashboardGrid`.

- `DashboardCard` is a `GlassCard` carrying a typed `DashboardCardKind` (e.g. `.monthlyOverview`, `.upcomingCharges`, `.categoryDistribution`, `.cashFlowMini`, `.assetsSummary`).
- Reorder via drag in an "Edit" mode: long-press lifts the card (`Haptics.impact(.light)`), `Motion.springGentle` reflow, drop persists the new `DashboardLayout.cardOrder`.
- Each card exposes a VoiceOver custom action "Move up"/"Move down" so reordering is possible without drag (accessibility requirement).
- Cards render their own mini Swift Chart where relevant, styled per [§8](#8-charts--data-visualization-styling).

---

## 8. Charts & data-visualization styling

Charts use **Swift Charts** (native). Styling is centralized so every chart in the app shares axes, grid, legend, and palette treatment.

### 8.1 Shared chart chrome

```swift
public struct FMChartStyle: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .chartForegroundStyleScale(range: ChartPalette.categorical)   // §3.3
            .chartXAxis { AxisMarks { _ in
                AxisGridLine().foregroundStyle(Color.fmHairline)
                AxisTick().foregroundStyle(Color.fmLabelSecondary)
                AxisValueLabel().font(.caption).foregroundStyle(Color.fmLabelSecondary)
            }}
            .chartYAxis { AxisMarks { _ in
                AxisGridLine().foregroundStyle(Color.fmHairline)
                AxisValueLabel().font(.caption).foregroundStyle(Color.fmLabelSecondary)
            }}
            .chartPlotStyle { $0.background(Color.clear) }
    }
}
```

- **Bars**: corner radius 4pt top, series color from palette, expense bars use `fmFinancialDown`, income bars `fmFinancialUp`.
- **Lines/areas**: 2pt stroke, area fill is a top-down gradient `seriesColor → seriesColor@8%`; BTC series uses `fmBTC` with a dashed stroke to distinguish denomination.
- **Pie/donut (category distribution)**: palette in order, 2pt `fmBackgroundElevated` stroke between slices, center label shows total.
- **Tooltips / selection**: tap-to-select via `chartOverlay` + `.chartGesture`; selected value shown in a glass capsule (`GlassRole.card`) with the value formatted by `Money`.

### 8.2 Money-flow (Sankey) renderer — known engineering item

Swift Charts has **no** Sankey/flow mark. The Cash Flow cost-tracker money-flow diagram (Substimate's `SpendingFlowChart`/`IncomeFlowChart`) is built as a **custom `Canvas`/`Path` renderer** in `DesignSystem` (`MoneyFlowDiagram`), not a chart mark. This is explicitly called out as engineering work in the [Roadmap](./08-roadmap-and-milestones.md) and [Task Backlog](./10-task-backlog.md).

- Nodes (income sources → buckets → expense categories) are rounded-rect glyphs; link ribbons are quadratic `Path`s whose width is proportional to flow magnitude.
- Link color blends from source node color (income → `fmFinancialUp` family) to destination (expense → category palette / `fmFinancialDown`).
- Fully accessible: the diagram exposes an `accessibilityRepresentation` that is an itemized list ("Salary 3,200 € → Housing 1,100 €, Subscriptions 84 € …") because a freeform flow drawing is not navigable by VoiceOver otherwise.
- Reduce Motion disables the flow-in animation; Reduce Transparency renders nodes opaque.
- A vetted SPM dependency may be substituted if it meets the accessibility and styling bar; default plan is the in-house renderer (see [ADR-0011](./12-decisions-adr.md)).

---

## 9. Iconography

### 9.1 SF Symbols first

Finmate uses **SF Symbols** as the primary icon set — they are vector, weight-matched to SF Pro, Dynamic-Type aware, and support hierarchical/multicolor rendering. Substimate used `lucide-react`; on native we map those concepts to the closest SF Symbol.

- Rendering modes: `.hierarchical` for most UI glyphs (gives depth without custom color), `.palette` where a financial tint is needed, `.multicolor` only where the symbol's native colors aid recognition.
- Always set `.symbolRenderingMode(...)` and an `accessibilityLabel` when a symbol is the only content of a control.
- Symbol effects (e.g. `.symbolEffect(.bounce)`) are reserved for purposeful feedback (a successful save) and are disabled under Reduce Motion.

### 9.2 Bespoke symbols

For brand-distinct marks not in the SF Symbols catalog, Finmate ships **bespoke SF Symbol files** (custom `.svg` symbols exported from the SF Symbols app template) in `DesignSystem`'s asset catalog, so they inherit weight/scale/Dynamic Type exactly like system symbols. Candidates:

- The Finmate app glyph / wordmark mark.
- A "money flow" mark for the Cash Flow tab.
- A "subscription cycle" mark (recurring ring) for billing periods.
- A combined "sats" mark beside `bitcoinsign.circle`.

### 9.3 Category icons

Categories carry an icon + a palette tint, rendered in a `CategoryIconBadge` (40×40, `Radius.sm`, tinted container at 16% opacity with the symbol in full tint). This replaces Substimate's `IconSelector` lucide grid with an SF Symbol mapping. Canonical mapping for the seeded default categories ([Data Model](./05-data-model.md) seeds `AI Chat`, `Coding`, `Diffusion`, `Streaming`, `Music`, `Gaming`, `Productivity`, `Audio Generation`, `Video Generation`, `Cloud Services`, `Fitness`, `Health`, `Food`, `Transport`, `Financial`, `Creative`, `Social`, `Other`):

> **`All` and `Favorites` are presentation-layer pseudo-filters, not category rows.** They exist only in the picker/filter UI (show everything; show the favorited subset) and are never seeded into the `categories` table. The **only** seeded, protected (non-deletable) category is **`Other`** — one per `kind` (`subscription` and `expense`); see [Data Model §7.2](./05-data-model.md). Their icon/tint rows below are listed purely so the filter chips have a canonical glyph, not because they are stored categories.

| Category | SF Symbol | Default tint (palette slot) |
| --- | --- | --- |
| AI Chat | `bubble.left.and.text.bubble.right` | Violet (4) |
| Coding | `chevron.left.forwardslash.chevron.right` | Blue (3) |
| Diffusion | `sparkles` | Pink (5) |
| Streaming | `play.tv` | Red (6) |
| Music | `music.note` | Pink (5) |
| Gaming | `gamecontroller` | Violet (4) |
| Productivity | `checklist` | Blue (3) |
| Audio Generation | `waveform` | Amber (2) |
| Video Generation | `film` | Orange (7) |
| Cloud Services | `cloud` | Blue (3) |
| Fitness | `figure.run` | Emerald (1) |
| Health | `heart` | Red (6) |
| Food | `fork.knife` | Amber (2) |
| Transport | `car` | Blue (3) |
| Financial | `banknote` | Emerald (1) |
| Creative | `paintpalette` | Pink (5) |
| Social | `person.2` | Violet (4) |
| Other (seeded, protected — non-deletable) | `square.grid.2x2` | Neutral (`fmFinancialNeutral`) |
| All (pseudo-filter, not a row) | `tray.full` | `fmLabelSecondary` |
| Favorites (pseudo-filter, not a row) | `star.fill` | Amber (2) |

A picker lets the user choose any SF Symbol + tint for custom categories; selection is stored as a symbol name string on `Category` and validated against an allow-list at the DB layer.

---

## 10. Accessibility

Accessibility is a **hard gate**, not a nice-to-have. Substimate had effectively none of this; Finmate treats it as a Definition-of-Done requirement ([Engineering Practices](./09-engineering-practices.md)).

### 10.1 Dynamic Type

- Every text role uses a named text style ([§4.1](#41-type-ramp)); the app is verified at content sizes from XS up to **AX5** (the largest accessibility size).
- Layouts that break at AX5 reflow: `HStack` rows that would clip switch to `ViewThatFits` / vertical stacks; KPI grids reduce columns; the tab bar relies on the system's automatic accessibility presentation.
- No fixed-height text containers; heights are intrinsic.

### 10.2 VoiceOver

- Every interactive element has a clear `accessibilityLabel`, a `accessibilityValue` where stateful (e.g. a toggle), and an `accessibilityHint` where the action is non-obvious.
- Composite rows use `.accessibilityElement(children: .combine)` and produce a single, sensible spoken string, e.g. *"Netflix, Streaming, 12 euros 99 cents per month, due July 3."*
- Charts and the money-flow diagram expose `accessibilityChartDescriptor` / `accessibilityRepresentation` so the data is navigable as audio/structured content ([§8.2](#82-money-flow-sankey-renderer--known-engineering-item)).
- Toasts post `.announcement` notifications; reorder actions expose VoiceOver custom actions ([§7.12](#712-customizable-dashboard-card)).

### 10.3 Contrast targets

- Body and label text meet **WCAG AA**: ≥ 4.5:1 against its background; large text (≥ 22pt or ≥ 18pt bold) ≥ 3:1.
- The semantic tokens in [§3](#3-design-tokens--color) are chosen to pass AA on their intended surfaces in both appearances; this is verified with a contrast snapshot check in CI.
- When `accessibilityDarkerSystemColors` / increased-contrast is on, hairlines step up to `fmSeparatorOpaque` and glass tints deepen.

### 10.4 Tap targets & motion

- All controls have a **≥ 44×44pt** hit area (buttons spec 50pt min height — [§7.1](#71-buttons)); small glyph buttons use `.contentShape(Rectangle())` + padding to reach 44pt.
- **Reduce Motion**: all non-essential animation routes through `fmAnimation` ([§6.2](#62-motion--curves--durations)), which cross-fades instead of springing and disables parallax, symbol bounces, shimmer, and glass morphs.

### 10.5 Reduce Transparency & color-independence

- **Reduce Transparency** is critical for a glass-heavy UI. When on, `glassBackground` collapses to Tier C opaque surfaces ([§2.2](#22-the-reusable-modifier-glassbackground)); scrims darken; vibrancy text becomes solid `fmLabel`.
- **Color-independence**: financial direction is never color-only — it is paired with a glyph and a leading sign ([§3.2](#32-financial-semantic-colors)). Chart series are distinguished by both color and either a label, a dash pattern (BTC), or a legend with shape markers.
- Selection/focus states use shape/border changes in addition to color so they survive color-blindness and high-contrast modes.

---

## 11. Internationalization & formatting

Finmate **ships English first** in v1 but is built **localization-ready** from day one, and it handles money/number formatting in a locale-correct way so that international users — and their European-formatted CSVs — are never silently corrupted (a known Substimate-class bug). Two concerns live here: (a) UI string localization, and (b) numeric/money formatting and parsing.

### 11.1 Localization readiness

- **`.xcstrings` is the source of truth.** Each module (`DesignSystem`, every `Features/*`) owns a String Catalog (`Localizable.xcstrings`); all user-facing copy is referenced via `LocalizedStringKey` / `String(localized:)`, never hard-coded display strings. SwiftUI `Text("…")` literals are localizable by default — feature code must rely on that and avoid string interpolation that defeats translation (use catalog format args and `AttributedString` runs instead).
- **No string concatenation for sentences.** Compose with format strings (`String(localized: "due_in_days", defaultValue: "Due in \(days) days")`) so word order and pluralization stay translator-controllable; pluralization uses the catalog's variations (`.stringsdict`-style plural rules), not `if count == 1` branching.
- **Layout is i18n-safe.** Because every label uses Dynamic Type and intrinsic sizing ([§4](#4-design-tokens--typography), [§10.1](#101-dynamic-type)), longer translated strings reflow rather than clip. We do **not** assume English string lengths. Right-to-left is inherited from SwiftUI's automatic mirroring; directional glyphs (the `arrow.up.right`/`arrow.down.right` financial pair) use SF Symbols' automatic RTL variants where they exist.
- **Post-v1 language roadmap.** v1 = English (`en`). The first localization wave after v1 targets the highest-signal European markets implied by EUR support — German (`de`), French (`fr`), Spanish (`es`) — followed by demand-driven additions. Adding a language is purely a catalog + review task; no code change should be required if these rules are followed.

### 11.2 Money & number display formatting

Money **display** formatting is locale-driven, keyed off the value's ISO currency code — it is **not** tied to the localized UI language. A user with a German device locale sees `1.234,56 €`; a US-locale user sees `$1,234.56`; both from the same stored `Int64` minor units.

- Formatting uses SwiftUI/Foundation **`FormatStyle`** — specifically `Decimal.FormatStyle.Currency` (`.currency(code:)`) resolved against `Locale.current` (or `Locale.autoupdatingCurrent`) — so the **grouping separator, decimal separator, currency symbol position, and minor-unit digit count come from the device locale and the currency**, not from hard-coded glyphs.
- The arithmetic is owned by the `Money` value type ([Data Model §2.2](./05-data-model.md)): `Money` converts `Int64` minor units → `Decimal` and hands it to the format style. The design system governs only **typesetting** of the resulting string (mono-digit alignment, weight — [§4.2](#42-numeric--currency-type)), never the math and never the locale resolution.
- BTC/sats follow the same path with a zero-fraction currency-like style (`satsPerBTC = 100_000_000`) plus the `₿`/sats unit affordance ([§7.7](#77-currency--amount-input)); sats render with locale grouping but no decimal places.
- VoiceOver currency readout ([§10.2](#102-voiceover)) is likewise produced from the format style so it is spoken correctly per locale.

```swift
// Display formatting is locale-driven; never hand-assemble "€" + amount.
public extension Money {
    /// Localized display string, e.g. "1.234,56 €" (de) / "$1,234.56" (en-US).
    func formatted(locale: Locale = .autoupdatingCurrent) -> String {
        decimalValue.formatted(
            .currency(code: currency.isoCode)
            .locale(locale)
        )
    }
}
```

### 11.3 Locale-aware CSV number parsing (Substimate bug class)

CSV **import** number parsing is the dangerous direction: the same digits mean different values under different conventions — US `1,234.56` vs EU `1.234,56`. Parsing must be **locale-aware and unambiguous**, never a blind `Double(string)` (which would read `1.234,56` as `1.234` and silently destroy the value — exactly the Substimate-class corruption Finmate must not repeat).

Rules (the parsing logic lives in the `Import` feature / `Shared` and is **pure, unit-tested** — see [Engineering Practices](./09-engineering-practices.md) and [Product Spec §7 (CSV import)](./02-product-spec.md)):

- **Detect, then let the user confirm.** On import, the parser inspects the amount column and infers the decimal/grouping convention (heuristic: the **last** of `.`/`,` that is followed by 1–2 trailing digits and appears once is the decimal separator; the other, if repeated at thousands positions, is grouping). The detected convention (`US 1,234.56` vs `EU 1.234,56`) is shown in the import preview as a **user-selectable** control so an ambiguous file is never parsed blindly — the user can override the guess before committing.
- **Parse to exact minor units.** Once the convention is fixed, the cleaned numeric string is parsed via `Decimal` (not binary floating point) and converted to `Int64` minor units by the `Money` type, rounding HALF-UP to the currency's precision — matching the money/conversion contract in [Tech Stack — Currency & conversion](./04-tech-stack.md).
- **Reject the ambiguous/invalid.** Rows whose amount cannot be parsed unambiguously under the chosen convention are flagged in the preview and excluded (not silently zeroed), so a bad parse can never enter the ledger.
- **Named unit-test cases** (mandatory): `"1.234,56" + EU convention => 123456 minor units`; `"1,234.56" + US convention => 123456 minor units`; `"1.234,56"` parsed under US convention is **rejected** (would be ambiguous/invalid), never silently read as `1.234`; `"1234,5"` (EU) => `123450` minor units (HALF-UP to 2 places); a value with more fractional digits than the currency allows is rejected.

This is the same money-safety discipline as storage and conversion: **display adapts to locale; stored amounts are exact `Int64` minor units and never derived from a locale-misread float.**

---

## 12. Package layout & token codegen

```
DesignSystem/
├── Package.swift
└── Sources/DesignSystem/
    ├── Color+Tokens.swift          // semantic + financial + BTC accessors
    ├── Typography.swift            // Font.fm…, text-style ramp helpers
    ├── Spacing.swift               // Spacing, Radius
    ├── Elevation.swift             // shadow tokens
    ├── Motion.swift                // Motion namespace + fmAnimation + ReduceMotionAware
    ├── Haptics.swift               // Haptics service
    ├── Glass/
    │   ├── GlassBackground.swift   // tiered modifier (A/B/C)
    │   ├── GlassButtonStyle.swift  // FMPrimary/Secondary/Plain
    │   └── GlassEffectContainerCompat.swift
    ├── Components/
    │   ├── GlassCard.swift
    │   ├── FMListRow.swift
    │   ├── AmountField.swift
    │   ├── FMTextField.swift
    │   ├── Toast.swift  /  ToastCenter.swift
    │   ├── FMEmptyState.swift
    │   ├── SkeletonView.swift
    │   ├── MonthGridCalendar.swift
    │   ├── DashboardCard.swift
    │   └── CategoryIconBadge.swift
    ├── Charts/
    │   ├── ChartPalette.swift
    │   ├── FMChartStyle.swift
    │   └── MoneyFlowDiagram.swift  // custom Canvas/Path Sankey
    ├── Icons/
    │   └── SFSymbol+Category.swift // category → symbol + tint mapping
    └── Resources/
        ├── Colors.xcassets         // all fm… colors, light + dark variants
        └── Symbols/                // bespoke .svg SF Symbols
```

- Colors live in `Colors.xcassets` with light/dark variants so the OS handles appearance switching; the typed `Color.fm…` accessors are the only sanctioned reference.
- A small SwiftPM build plugin (or a checked-in `swift run tokens` script) can regenerate `Color+Tokens.swift` and a `tokens.json` from the asset catalog so a **future web client** can consume the identical palette — preserving the portable design contract called for in the canonical brief.
- Every component file ships `#Preview`s covering light, dark, Reduce Transparency, Reduce Motion, and AX5 size; snapshot tests assert these.

---

## 13. What this replaces from Substimate

| Substimate (before) | Finmate (after) |
| --- | --- |
| **9 visual styles** (`aurora`, `brutalist`, `claymorphism`, `glassmorphism`, `minimal`, `modern`, `neobrutalist`, `neumorphism`, `retro`) selectable at runtime, each a separate large CSS file with duplicated chart variables. | **One** Liquid Glass language. Appearance choice is only `system / light / dark`. |
| Visual style conflated with screen size (neumorphic on desktop, glass on mobile via media queries on the same class names). | Tier is chosen by **OS capability + accessibility**, never by viewport. Single `glassBackground` modifier. |
| `data-currency="BTC"` ad-hoc override of a global `--highlight-color` to `#f7931a`. | `fmBTC` is a fixed **semantic** token used only in BTC/sats contexts; the brand accent is independent. |
| Chart palette redeclared in every theme file (`--chart-color-1..7`, `--chart-color-btc`). | Single `ChartPalette.categorical` (7 + BTC), re-tuned for AA contrast, fed to Swift Charts. |
| `IconSelector` over `lucide-react`. | SF Symbols (+ bespoke symbols), weight-matched and Dynamic-Type aware; `CategoryIconBadge`. |
| Hand-rolled `DatePicker.tsx`, `DraggableDashboardCard`, toast pattern, `SpendingFlowChart`. | Native `MonthGridCalendar`, `DashboardCard` (reorder + VoiceOver actions), `Toast`/`ToastCenter`, custom-`Canvas` `MoneyFlowDiagram`. |
| No documented accessibility, no contrast guarantees, custom scrollbars, CSS cruft. | Dynamic Type to AX5, VoiceOver everywhere, AA contrast verified in CI, Reduce Motion/Transparency first-class. |

See the full migration map in [Substimate Analysis & Migration Map](./11-substimate-analysis.md).

---

## 14. Definition of Done for a component

A `DesignSystem` component is "done" only when every box is checked:

- [ ] Uses **only** tokens (no literal hex, pt sizes outside `Spacing`/`Radius`, or raw `Animation`).
- [ ] Renders correctly on **Tier A / B / C** (iOS 26 glass, iOS 18–25 materials, Reduce Transparency opaque).
- [ ] Respects **Reduce Motion** via `fmAnimation` (no orphaned `.animation`).
- [ ] Full **VoiceOver** label/value/hint; composite views combine sensibly.
- [ ] Verified at Dynamic Type **XS → AX5** without clipping; reflows where needed.
- [ ] All interactive targets **≥ 44×44pt**.
- [ ] Text meets **WCAG AA** contrast on its intended surface (CI contrast check passes).
- [ ] Financial values pair **color + glyph + sign** (no color-only meaning).
- [ ] Ships `#Preview`s (light/dark/reduce-transparency/AX5) and a **snapshot test** (`swift-snapshot-testing`).
- [ ] No glass-on-glass; obeys the glass-hygiene rules ([§2.4](#24-rules-glass-hygiene)).

---

## 15. Related documents

- [../CLAUDE.md](../CLAUDE.md) — Single source of truth & entry point.
- [./00-index.md](./00-index.md) — Documentation index & reading order.
- [./02-product-spec.md](./02-product-spec.md) — Screens & flows this system styles (tabs, dashboard, calendar, cost tracker).
- [./03-architecture.md](./03-architecture.md) — Where `DesignSystem` sits in the module graph; navigation/router.
- [./04-tech-stack.md](./04-tech-stack.md) — iOS 18 minimum, Xcode 26 / Swift 6, Swift Charts, snapshot-testing.
- [./05-data-model.md](./05-data-model.md) — `Money`, `Category`, `DashboardLayout`, `UserPreferences.appearance`, currencies.
- [./07-security-and-privacy.md](./07-security-and-privacy.md) — Biometric lock UI, privacy-sensitive screen treatment.
- [./09-engineering-practices.md](./09-engineering-practices.md) — Accessibility & snapshot gates, SwiftLint/swift-format.
- [./11-substimate-analysis.md](./11-substimate-analysis.md) — Full Substimate → Finmate migration map.
- [./12-decisions-adr.md](./12-decisions-adr.md) — ADR-0004 (deployment target), ADR-0009 (single design language / no user themes), ADR-0011 (Sankey renderer).
