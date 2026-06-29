# Obsidian Design System

> The single, cohesive visual language for Finmate — **Obsidian**: a near-monochrome ink/graphite palette with a single warm **bronze** signature accent, laid over a **near-flat** neutral background, with Apple-grade **Liquid Glass** on iOS 26+ and an automatic Materials fallback on iOS 18–25. This is the authoritative reference for the implemented tokens, glass strategy, component library, and accessibility.

This document describes the system **as built**. The Obsidian identity is implemented today in the app target's design files (`App/Sources/DesignSystemTokens.swift`, `DesignSystem.swift`, `DesignSystemComponents.swift`, `DesignSystemGallery.swift`) and mirrored on the web client (`web/src/styles/glass.css` + `web/src/features/styleguide/Styleguide.tsx`). The same token **values** are shared across both clients so iOS and web read with identical depth. Extraction into a standalone `DesignSystem` SPM package (per the module graph in [Architecture](./03-architecture.md)) is a later refactor; the values and rules below are canonical regardless of where the code physically lives.

> **Obsidian replaces the prior identity.** Earlier drafts of this document specified a **system-blue** brand accent (`#0A84FF`) and a multi-hue categorical chart palette (blue / orange / violet / emerald / pink / red). Obsidian **explicitly replaces all of it**: the accent is now a warm **bronze**, the primary action fill is a high-contrast **ink**, charts and the money-flow ramp are a **bronze→tan monochrome** scale, and the canvas is **near-flat** (no multi-color ambient gradient). The financial semantics (green = gain, red = loss, Bitcoin orange) survive — but only as *semantics*, never as brand color. This single language also still replaces Substimate's nine competing styles ([§12](#12-what-this-replaces)).

---

## Table of contents

1. [Design principles](#1-design-principles)
2. [The Liquid Glass material strategy](#2-the-liquid-glass-material-strategy)
3. [Tokens — color (the Obsidian palette)](#3-tokens--color-the-obsidian-palette)
4. [Tokens — typography](#4-tokens--typography)
5. [Tokens — spacing, radii](#5-tokens--spacing-radii)
6. [Tokens — motion](#6-tokens--motion)
7. [The near-flat background](#7-the-near-flat-background)
8. [Component library](#8-component-library)
9. [Charts & the money-flow ramp](#9-charts--the-money-flow-ramp)
10. [Iconography](#10-iconography)
11. [Accessibility](#11-accessibility)
12. [What this replaces](#12-what-this-replaces)
13. [Cross-client parity & the component gallery](#13-cross-client-parity--the-component-gallery)
14. [Related documents](#14-related-documents)

---

## 1. Design principles

Obsidian keeps the Apple HIG pillars — **Clarity, Deference, Depth** — and adds the finance-specific stance that *color is information, not decoration*.

| Principle | What it means in Finmate | Concrete rule (as built) |
| --- | --- | --- |
| **Clarity** | Money is legible at a glance. | Amounts render in a rounded, **tabular monospaced-digit** face (`FinmateType.money` / `.fm-mono`, `font-variant-numeric: tabular-nums`) so columns align; sign is conveyed by **color and** glyph/leading sign, never color alone. |
| **Deference** | The chrome and accent get out of the way of the user's data. | The palette is near-monochrome ink/graphite; the bronze accent appears sparingly — on the active nav/tab, selection, links, and at most one primary action per screen. |
| **Depth comes from glass, not the canvas** | Layering communicates hierarchy. | The background is **near-flat** ([§7](#7-the-near-flat-background)); glass surfaces and content carry the depth. No multi-color ambient wash for the glass to refract off a busy gradient. |
| **One language** | A single Obsidian identity, light/dark/system. | There is no user-selectable "visual style." The only appearance choice is `system \| light \| dark` (stored in `UserPreferences.appearance`, applied app-wide — [§2.5](#25-app-wide-appearance--accent)). |
| **Calm & trustworthy** | A finance app feels safe and unhurried. | Motion is short (≤ 0.40s) and gated on Reduce Motion; the warm bronze is the only "color event" on an otherwise neutral surface. |
| **Accessible by default** | Dynamic Type, VoiceOver, Reduce Motion/Transparency, AA contrast. | Text uses platform semantic colors and named text styles; components carry VoiceOver labels and respect reduce-motion/-transparency ([§11](#11-accessibility)). |

---

## 2. The Liquid Glass material strategy

Glass is the signature surface. Obsidian adopts **authentic iOS 26 Liquid Glass** where the OS provides it and falls back to system **Materials** on iOS 18–25. All branching lives behind one modifier (`GlassBackground` / `.glassSurface`) and the `GlassCard` container — feature code never branches on OS version inline.

### 2.1 Capability tiers

| Tier | iOS range | Surface technology (as implemented) | Notes |
| --- | --- | --- | --- |
| **A — Liquid Glass** | iOS 26.0+ | `.glassEffect(.regular, in: shape)` on cards; `.glassEffect(.regular.tint(bronze 16%), …)` for a tinted prominent surface; `.buttonStyle(.glass)` / `.glassProminent`; `.scrollEdgeEffectStyle(.soft, for: .all)` on primary scroll surfaces. | Design-complete experience. Light refraction + specular highlights from the OS. |
| **B — Materials fallback** | iOS 18.0–25.x | `.background(FinmateColor.glassFill, in: shape)` over `.ultraThinMaterial` with a `FinmateColor.glassBorder` hairline stroke; `.borderedProminent` / `.bordered` button styles; scroll-edge is a no-op. | Premium, no refraction. Minimum deployment target **iOS 18.0** ([ADR-0004](./12-decisions-adr.md)). |
| **C — Reduce Transparency** | any iOS / web `prefers-reduced-transparency` | Opaque solid surface (web: `.fm-glass` → `--fm-surface-opaque`, blur removed). iOS leans on the system, which renders the glass/material opaque under Reduce Transparency. | Mandatory for legibility. |

### 2.2 The reusable surface: `GlassBackground` / `.glassSurface` / `GlassCard`

A single `ViewModifier` (`GlassBackground`) encapsulates Tier A vs. Tier B; `GlassCard` is the workhorse container that pads content and applies it. (Source: `App/Sources/DesignSystem.swift`.)

```swift
struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = FinmateRadius.lg
    var tinted: Bool = false  // prominent surfaces get a subtle bronze tint

    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            content.glassEffect(tinted ? .regular.tint(FinmateColor.bronze.opacity(0.16))
                                       : .regular, in: shape)
        } else {
            content
                .background(FinmateColor.glassFill, in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(FinmateColor.glassBorder, lineWidth: 0.75))
        }
    }
}

extension View {
    func glassSurface(cornerRadius: CGFloat = FinmateRadius.lg, tinted: Bool = false) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius, tinted: tinted))
    }
}

struct GlassCard<Content: View>: View {   // pads + frames + applies the glass surface
    var cornerRadius: CGFloat = FinmateRadius.lg
    var tinted: Bool = false
    var padding: CGFloat = FinmateSpacing.lg
    @ViewBuilder var content: () -> Content
}
```

On the web, the equivalent is the `.fm-glass` primitive in `glass.css` (translucent fill + `backdrop-filter: blur(20px) saturate(180%)` + a 1px border + soft shadow), wrapped by the `GlassCard` React component (`web/src/components/GlassCard.tsx`).

### 2.3 Glass levels

Three glass levels exist on the web; iOS uses the single `.regular` glass (plus the tinted prominent variant):

| Level | Web class | Use |
| --- | --- | --- |
| Standard | `.fm-glass` | Floating content cards (`--fm-glass-fill`). |
| Chrome | `.fm-glass-chrome` | Nav / sidebar / toolbars — slightly more opaque (`--fm-glass-chrome`). |
| Thin | `.fm-glass-thin` | Subtle overlays (`--fm-glass-thin`). |
| Tinted prominent | iOS `tinted: true` → `.regular.tint(bronze 16%)` | A prominent surface that carries a whisper of bronze. |

### 2.4 Scroll-edge effect

On iOS 26 a single helper applies the soft scroll-edge effect to primary scroll/list surfaces; it is a no-op below 26.

```swift
extension View {
    @ViewBuilder func finmateScrollEdge() -> some View {
        if #available(iOS 26.0, *) { self.scrollEdgeEffectStyle(.soft, for: .all) }
        else { self }
    }
}
```

It is applied to the Home dashboard scroll and the component gallery. Feature code does not hand-roll gradient scrims.

### 2.5 App-wide appearance & accent

- The bronze accent is set **once** at the app root via `.tint(FinmateColor.bronze)` (iOS, `FinmateApp.swift`) so the active tab/nav, selection, links, toggles, and sliders all recolor to bronze. On the web, `--fm-accent` is defined to equal `--fm-bronze`, so every existing `var(--fm-accent)` reference recolors blue → bronze without touching call sites.
- Appearance (`system \| light \| dark`) is applied app-wide: iOS uses `.preferredColorScheme(preferencesStore.appearance.preferredColorScheme)`; web sets `data-theme` on `<html>` (with `prefers-color-scheme` honored for `system`).

### 2.6 Glass-effect APIs — adopted vs. not

Recorded precisely against the final code:

- **Adopted (Tier A):** `glassEffect(_:in:)`, `Glass.regular` + `.regular.tint(...)`, `.buttonStyle(.glass)` / `.glassProminent`, `scrollEdgeEffectStyle(.soft, for:)`.
- **Not yet adopted:** `GlassEffectContainer` and `glassEffectID` (matched-geometry glass morphing). These are referenced only in a source comment, not in any rendered view; grouping/morph transitions remain open work (see [Task Backlog](./10-task-backlog.md) M7-PERF-02).

---

## 3. Tokens — color (the Obsidian palette)

Colors are defined once per client and resolve per appearance. iOS uses `Color.dynamicHex(light:dark:)` dynamic colors (resolved per `UITraitCollection`); web uses CSS custom properties under `:root`, `@media (prefers-color-scheme: dark)`, and explicit `[data-theme]` overrides. **The hex values are identical across the two clients.** Source: `App/Sources/DesignSystemTokens.swift` (`enum FinmateColor`) and `web/src/styles/glass.css`.

### 3.1 Backgrounds, surfaces, hairline, text

| Token (iOS `FinmateColor.*` / web `--fm-*`) | Role | Light | Dark |
| --- | --- | --- | --- |
| `background` / `--fm-background` | App scene background (near-flat) | `#F3F3F5` | `#0B0C0E` |
| `elevated` / `--fm-background-elevated` | Grouped/elevated background | `#FFFFFF` | `#15171B` |
| `surface` / `--fm-surface` | Solid card / row surface | `#FFFFFF` | `#1B1E23` |
| `surface2` / `--fm-surface-2` | Secondary surface | `#FAFAFB` | `#23262D` |
| (web) `--fm-surface-opaque` | Reduce-Transparency glass replacement | `#FFFFFF` | `#1B1E23` |
| `hairline` / `--fm-hairline` | 0.5–0.75pt separators & glass borders | black @ 8% | white @ 10% |
| `label` / `--fm-label` | Primary text | `Color.primary` (iOS) / `#0B0C0E` (web) | `Color.primary` / `#FFFFFF` |
| `labelSecondary` / `--fm-label-secondary` | Secondary text | `Color.secondary` / `rgba(60,60,67,.74)` | `Color.secondary` / `rgba(235,235,245,.62)` |
| `labelTertiary` / `--fm-label-tertiary` | Tertiary / placeholder | `.tertiaryLabel` / `rgba(60,60,67,.6)` | `.tertiaryLabel` / `rgba(235,235,245,.5)` |

iOS deliberately maps the text roles onto the **platform semantic colors** (`Color.primary`, `Color.secondary`, `.tertiaryLabel`) so increased-contrast, Smart Invert, and appearance switching behave correctly for free. The web tertiary/secondary opacities were tuned up to meet AA contrast ([§11.3](#113-contrast)).

### 3.2 Ink (primary action) & bronze (signature accent)

| Token | Role | Light | Dark |
| --- | --- | --- | --- |
| `ink` / `--fm-ink` | Mono primary-action fill (high contrast) | `#1A1C20` | `#F2F3F5` |
| `inkOn` / `--fm-ink-on` | Foreground on the ink fill | `#FFFFFF` | `#15161A` |
| `bronze` / `--fm-bronze` / `--fm-accent` | The single signature accent | `#9A7544` | `#C29A6A` |
| `bronzeDeep` / `--fm-bronze-deep` / `--fm-accent-pressed` | Deepened bronze (pressed/hover) | `#7E5F33` | `#A07E50` |

The **primary action** is a high-contrast monochrome **ink** fill (near-black in light, near-white in dark); the **bronze** is the one warm accent. On iOS the ink fill is applied via `.tint(FinmateColor.ink)` over the native `.glassProminent` style so the system glass stays authentic; on web the primary button is a solid `--fm-ink` fill with `--fm-ink-on` text. Bronze drives the accent button, ghost text, segmented selection, the brand mark, list-row icon tint, and focus rings.

### 3.3 Financial semantics (kept, not brand)

These are separate from the accent so "up/down" reads consistently everywhere.

| Token | Meaning | Light | Dark | Paired affordance |
| --- | --- | --- | --- | --- |
| `up` / `--fm-up` (`--fm-positive`) | Income, gain, positive delta | `#248A3D` | `#34C759` | `arrow.up.right`, leading `+` |
| `down` / `--fm-down` (`--fm-negative`) | Expense, loss, negative delta | `#D70015` | `#FF453A` | `arrow.down.right`, leading `−` |
| `neutral` / `--fm-neutral` | No change / flat | `#8A8A8E` | `#98989D` | `minus` |
| `warning` / `--fm-warning` | Over-budget, due soon, error state | `#C8730A` | `#FFB340` | `exclamationmark.triangle.fill` |
| `btc` / `--fm-btc` | Bitcoin / sats context | `#E5860F` | `#F7931A` | `bitcoinsign[.circle.fill]` |

`FinmateColor.sign(_:)` returns `up` for a positive `Int64` minor amount, `down` for negative, secondary label for zero — this is the single source for sign-coloring (`AmountText`, `StatTile`). Bitcoin orange is applied **only** in BTC/sats contexts (the crypto calculator, BTC asset rows, the BTC chart series), never as a global highlight.

### 3.4 Glass fill / border (Materials-fallback tints)

| Token | Light | Dark |
| --- | --- | --- |
| `glassFill` / `--fm-glass-fill` | white @ 62% | white @ 6% |
| `glassBorder` / `--fm-glass-border` | white @ 70% | white @ 12% |
| (web) `--fm-glass-chrome` | white @ 72% | white @ 8% |
| (web) `--fm-glass-thin` | white @ 42% | white @ 4% |

On Tier A the OS `glassEffect` carries its own material; these tints are the Tier B / web fallback.

### 3.5 Money-flow ramp (Sankey) — monochrome + bronze

The cost-tracker money-flow diagram uses a mono+bronze ramp (this **replaces** the prior violet flow color). Source: `FinmateColor.Flow` / `--fm-flow-*`.

| Token | Role | Light | Dark |
| --- | --- | --- | --- |
| `Flow.income` / `--fm-flow-income` | Income node | ink (neutral) | ink |
| `Flow.fixed` / `--fm-flow-fixed` | Fixed expenses | `#B08A5A` | `#C29A6A` |
| `Flow.variable` / `--fm-flow-variable` | Variable expenses | `#CDB089` | `#DDC49B` |
| `Flow.subscriptions` / `--fm-flow-subscriptions` | Subscriptions | `#8A6A42` | `#A07E50` |
| `Flow.savings` / `--fm-flow-savings` | Savings | `up` (green) | `up` |

The legacy web token `--fm-flow-violet` is retained as a back-compat alias that now resolves to a bronze tone.

### 3.6 Chart ramp — bronze → tan monochrome

A monochrome bronze→tan scale for category charts and allocation donuts (this **replaces** the prior 7-hue categorical palette). Signed series should still overlay `up`/`down`.

- **iOS** (`FinmateColor.chartRamp`, 8 entries, cycled via `FinmateColor.ramp(index)`): `bronze`, `#B08A5A`, `#CDB089`, `bronzeDeep`, `#8A6A42`, `#DCC8A6`, `neutral`, `#6E5536`.
- **Web** (`--fm-ramp-1`…`--fm-ramp-6`): light `#7E5F33 / #9A7544 / #B08A5A / #C6A479 / #D9C19C / #E7D6BA`; dark `#A07E50 / #C29A6A / #D4B083 / #E0C499 / #EAD7B6 / #F1E6CF`.

---

## 4. Tokens — typography

Obsidian uses the **system font** and maps every role onto the platform text styles, so Dynamic Type scales everything for free. Money/figures use a dedicated rounded, tabular monospaced-digit face.

### 4.1 Type ramp

iOS `FinmateType` maps directly to SwiftUI `Font` styles; web `--fm-font-*` are rem sizes pinned to the equivalent iOS base sizes:

| Role | iOS (`FinmateType.*`) | Web (`--fm-font-*`) |
| --- | --- | --- |
| largeTitle | `Font.largeTitle` | `2.125rem` |
| title / title1 | `Font.title` | `1.75rem` |
| title2 | `Font.title2` | `1.375rem` |
| title3 | `Font.title3` | `1.1875rem` |
| headline | `Font.headline` | `1.0625rem` |
| body | `Font.body` | `1rem` |
| callout | `Font.callout` | `0.9375rem` |
| subheadline | `Font.subheadline` | `0.9375rem` |
| footnote | `Font.footnote` | `0.8125rem` |
| caption | `Font.caption` | `0.75rem` |
| caption2 | `Font.caption2` | `0.6875rem` |

### 4.2 Numeric / money face

```swift
// FinmateType.money — rounded, tabular, monospaced-digit, scales with Dynamic Type.
static func money(_ style: Font.TextStyle = .body, weight: Font.Weight = .semibold) -> Font {
    .system(style, design: .rounded).weight(weight).monospacedDigit()
}
```

The web equivalent is `--fm-font-rounded` (`ui-rounded` / SF Pro Rounded stack) applied with `font-variant-numeric: tabular-nums` via the `.fm-mono` / `.fm-amount` / `.fm-hero-amount` classes. The `Money` value type ([Data Model](./05-data-model.md)) owns the arithmetic and formatting from `Int64` minor units; the design system governs only the typesetting.

---

## 5. Tokens — spacing, radii

### 5.1 Spacing (4pt base grid)

| iOS `FinmateSpacing.*` | Value | Web `--fm-space-*` |
| --- | --- | --- |
| `xs` | 4 | `--fm-space-1` |
| `sm` | 8 | `--fm-space-2` |
| `md` | 12 | `--fm-space-3` |
| `lg` | 16 (default card padding) | `--fm-space-4` |
| `xl` | 20 | `--fm-space-5` |
| `xxl` | 24 | `--fm-space-6` |
| `xxxl` | 32 | `--fm-space-7` |

Web also defines `--fm-card-padding: var(--fm-space-4)` and `--fm-spacing: var(--fm-space-3)`. iOS keeps a legacy `FinmateTokens` shim (`cornerRadius`/`cardPadding`/`spacing`) mapped onto the new scales so older call sites compile unchanged.

### 5.2 Radii (continuous corners)

| iOS `FinmateRadius.*` | Value | Web `--fm-radius-*` |
| --- | --- | --- |
| `sm` | 12 | `--fm-radius-sm` |
| `md` | 16 | `--fm-radius-md` |
| `lg` | 22 (standard glass card) | `--fm-radius-lg` (also `--fm-radius`) |
| `xl` | 28 | `--fm-radius-xl` |
| `pill` | 999 | `--fm-radius-pill` |

All rounded rects use `style: .continuous` on iOS.

---

## 6. Tokens — motion

Motion is short, spring-led, and gated on Reduce Motion at each call site.

```swift
enum FinmateMotion {
    static let fast: TimeInterval = 0.15
    static let base: TimeInterval = 0.25
    static let slow: TimeInterval = 0.40
    static let glassSpring = Animation.spring(response: 0.40, dampingFraction: 0.82)
    static let baseEase    = Animation.easeInOut(duration: base)
    static let fastEase    = Animation.easeInOut(duration: fast)
}
```

Web mirrors these as `--fm-motion-fast: .15s`, `--fm-motion-base: .25s`, `--fm-motion-slow: .4s`, and a `--fm-spring: cubic-bezier(0.34, 1.56, 0.64, 1)`. Nothing in normal use exceeds 0.40s. Reduce-motion handling is described in [§11.2](#112-reduce-motion--reduce-transparency).

---

## 7. The near-flat background

Obsidian's defining move: **depth comes from glass + content, not from a colorful canvas.** There is no multi-color ambient gradient.

- **iOS** (`FinmateBackground`, `App/Sources/DesignSystem.swift`): the flat `FinmateColor.background` neutral, plus a barely-there vertical `LinearGradient` — a few percent bronze at the top, clear in the middle, ~3% ink at the bottom — *only* enough lift to give flat glass something to refract. The deprecated `FinmateGradient` is an alias that routes to `FinmateBackground` so old call sites compile.
- **Web** (`glass.css` `body`): `var(--fm-background)` plus a single whisper-soft radial vignette (`color-mix(in srgb, var(--fm-label) 3%, transparent)` at the top), `background-attachment: fixed`. Near-monochrome, never dead-flat.

This is the surface every screen sits on (`.background(FinmateBackground())` across the feature views, the splash, the app-lock overlay, etc.).

---

## 8. Component library

The depth layer. iOS components live in `App/Sources/DesignSystemComponents.swift` (plus the surfaces/states in `DesignSystem.swift`); the web equivalents are CSS classes in `glass.css` and a few React components. Every component keeps Dynamic Type (`@ScaledMetric` where it sets fixed paddings), VoiceOver labels/traits, and reduce-motion intact.

### 8.1 Buttons — `GlassButton`

Four kinds × two sizes (`sm` / `md`, with `small`/`medium` aliases), optional `fullWidth`.

| Kind | Tier A | Tier B | Tint |
| --- | --- | --- | --- |
| `.primary` | `.buttonStyle(.glassProminent)` | `.borderedProminent` | `ink` (high-contrast mono) |
| `.destructive` | `.glassProminent` | `.borderedProminent` | `down` (red) |
| `.secondary` | `.buttonStyle(.glass)` | `.bordered` | `bronze` |
| `.ghost` | `.buttonStyle(.plain)` + bronze label | same | `bronze` |

The tint is applied through `.tint(...)` so the native system glass styles stay authentic. The web mirror is `.fm-btn` (primary = ink fill) with `.fm-btn-secondary` (glass/bordered), `.fm-btn-accent` (bronze fill), `.fm-btn-ghost` (bronze text + hairline), `.fm-btn-destructive` (red tinted), and `.fm-btn-sm`. Helper modifiers `finmateProminent()` / `finmateGlassButton()` apply the prominent/secondary glass style to non-`Button` controls (ShareLink, Link, Menu).

### 8.2 Badge / Pill

`Badge` — a compact capsule with tones `neutral / accent / up / down / btc / warning`; foreground is the tone color, background is the tone at 16%. Web: `.fm-badge` + `.fm-badge-accent / -up / -down / -btc` (a dark-mode override lifts accent text from bronze-deep to bronze for legibility on the tinted chip).

### 8.3 AmountText

Money/figure text in the rounded tabular face, optionally sign-colored via `signMinor` (drives `FinmateColor.sign`), with `.contentTransition(.numericText())` for animated value changes. Web: the `.fm-amount` / `.fm-hero-amount` classes (the hero amount uses `overflow-wrap: anywhere` so long BTC/large balances wrap rather than overflow).

### 8.4 SectionHeader

A title (+ optional SF Symbol tinted bronze) with an optional trailing action slot. `headline` weight.

### 8.5 StatTile / KPICard

A compact KPI tile on glass — title + symbol over a big rounded-tabular value, optional sign-coloring and a detail line, `minimumScaleFactor(0.6)` + `lineLimit(1)` to protect the figure, and a combined accessibility label. `KPICard` is a thin alias kept for the Cash Flow call sites; both render identically.

### 8.6 GlassListRow

Leading SF Symbol (default tint bronze) + title/subtitle + a generic trailing slot (amount text, chevron, controls), all on a `GlassCard`. The workhorse row for subscriptions, income, expenses, and assets. Web: `.fm-row` inside a glass card + `.fm-icon-tile` (bronze-tinted icon container).

### 8.7 Segmented control

`finmateSegmented()` applies `.pickerStyle(.segmented).tint(FinmateColor.bronze)` so the system segmented control carries the bronze selection. Web: `.fm-segment` / `.fm-segment-item` with `aria-pressed`/`.selected` → bronze fill.

### 8.8 EmptyStateCard

Centered SF Symbol (40pt, bronze), `headline` title, `subheadline` message, optional primary CTA. Combined accessibility label. Web: `.fm-emptystate` (icon / title / message) + the `EmptyState` React component.

### 8.9 Toast

A transient glass capsule (`pill` radius) with tones `info / success / warning / error` — info uses bronze; the rest reuse the semantic palette. Posts a combined accessibility label.

### 8.10 Loading / error states

- `ErrorStateCard` — an inline glass card with a warning label, message, and a `Retry` `GlassButton`; combined accessibility label + retry hint. Web: `.fm-errorcard` + the `ErrorCard` component.
- `SkeletonRow` / `SkeletonList` — redacted (`.redacted(reason: .placeholder)`) glass placeholders shown while a store loads instead of a blank flash; `accessibilityHidden`. Web: `.fm-skeleton` (a shimmer that is disabled under `prefers-reduced-motion`).
- `PlaceholderView` — a `ContentUnavailableView` for not-yet-built milestones.

### 8.11 Web-only shell & controls

The web client adds a responsive shell that mirrors the iOS root `TabView`: `.fm-shell` collapses a sticky glass sidebar (`.fm-sidebar.fm-glass-chrome` + bronze active state) into a bottom tab bar under `47.5em`; `.fm-brand-dot` is a mono→bronze gradient mark; `.fm-toggle` is a `role="switch"` pill that turns bronze when on; `.fm-input` / `.fm-select` carry a bronze focus ring; `.fm-dash-*` provides the Home reorder controls; `.fm-sr-only` is the screen-reader-only helper for chart/flow tabular fallbacks.

---

## 9. Charts & the money-flow ramp

Charts use **Swift Charts** on iOS and inline SVG on web, styled from the bronze→tan chart ramp ([§3.6](#36-chart-ramp--bronze--tan-monochrome)); signed/financial series overlay `up`/`down`; BTC series uses `btc`.

- **Category distribution / allocation** (subscriptions analytics, assets allocation donut) cycle `FinmateColor.ramp(index)` / `--fm-ramp-*`.
- **Money-flow (Sankey)** — Swift Charts has no Sankey mark, so the diagram is a custom `Canvas`/`Path` renderer on iOS (`MoneyFlowView`) and an inline SVG on web (`MoneyFlow`), colored by the [§3.5](#35-money-flow-ramp-sankey--monochrome--bronze) flow ramp. Income → Fixed/Variable/Subscriptions/Savings ribbons are proportional. The flow-in animation is gated on Reduce Motion (`.animation(reduceMotion ? nil : .default, value: flow)`); web ribbons are translucent (`.fm-flow-ribbon` at 0.55 opacity) and turn solid with a hairline edge under `prefers-reduced-transparency`.

Full chart/Sankey specs live in [Visualizations & Charts](./14-visualizations-and-charts.md).

---

## 10. Iconography

Finmate uses **SF Symbols** as the icon set throughout — `house.fill`, `creditcard.fill`, `chart.line.uptrend.xyaxis`, `calendar`, `ellipsis.circle.fill` for the five tabs; semantic glyphs (`arrow.up.right`, `arrow.down.right`, `exclamationmark.triangle.fill`, `bitcoinsign.circle.fill`, `checkmark.circle.fill`, `xmark.octagon.fill`, etc.) for financial direction and states. Symbols used as the sole content of a control carry an `accessibilityLabel`; decorative symbols are `accessibilityHidden(true)`. List-row and section icons default to the bronze tint; BTC icons use `btc`. Bespoke SF Symbol files and a full per-category icon/tint mapping are not yet in the codebase — the canonical category mapping remains a later task ([Task Backlog](./10-task-backlog.md) M7-DS-02).

---

## 11. Accessibility

Accessibility is a hard gate, built into the components rather than bolted on.

### 11.1 Dynamic Type & VoiceOver

- Every text role uses a named text style ([§4.1](#41-type-ramp)) so Dynamic Type scales the whole UI; components that set fixed paddings use `@ScaledMetric` (e.g. `GlassButton`'s vertical/horizontal padding) so the touch target grows with text. The web shell sizes its breakpoint and sidebar in `rem`/`em` so larger root text collapses the layout before it clips.
- Composite views combine into one sensible spoken string (`.accessibilityElement(children: .combine)`) — `StatTile`, `GlassListRow`, `Badge`, `EmptyStateCard`, `ErrorStateCard`, `Toast`. Decorative icons are hidden; the money-flow diagram and charts expose a tabular/structured representation (web `.fm-sr-only`) so freeform drawings remain navigable.

### 11.2 Reduce Motion & Reduce Transparency

- **Reduce Motion** is honored via `@Environment(\.accessibilityReduceMotion)` at every non-essential animation call site — the root app-lock/auth-state transitions, the forgot-password reveal, calendar day selection, the money-flow flow-in, and the Home dashboard edit/reorder reflow all pass `reduceMotion ? nil : …`. Web gates all transitions and the skeleton shimmer behind `@media (prefers-reduced-motion: reduce)`.
- **Reduce Transparency**: web `.fm-glass` collapses to `--fm-surface-opaque` (blur removed) under `prefers-reduced-transparency`, and falls back to a solid `--fm-surface` where `backdrop-filter` is unsupported. iOS relies on the system, which renders `glassEffect` / Materials opaque when Reduce Transparency is on.

### 11.3 Contrast

- iOS text uses the **platform semantic colors** (`Color.primary` / `.secondary` / `.tertiaryLabel`), which Apple guarantees at AA in light and dark.
- Web token opacities were raised where they failed AA: light secondary `.6 → .74` (≈5.1:1), light tertiary `.3 → .6`, dark tertiary `.3 → .5` (≈4.5:1); dark secondary was already ≈5.9:1.

### 11.4 Color-independence

Financial direction is never color-only — it pairs the `up`/`down`/`warning` color with a glyph and/or a leading `+`/`−` sign ([§3.3](#33-financial-semantics-kept-not-brand)). Selection/focus uses border/fill changes (bronze focus ring, segmented selection fill) in addition to color.

---

## 12. What this replaces

| Before | Obsidian (now) |
| --- | --- |
| **System-blue brand accent** (`#0A84FF`) on buttons, selection, focus. | A warm **bronze** accent (`#9A7544` / `#C29A6A`); the **primary action** is a high-contrast monochrome **ink** fill. `--fm-accent` is aliased to bronze so call sites recolor automatically. |
| **Multi-hue categorical chart palette** (blue / orange / violet / emerald / pink / red). | A **bronze→tan monochrome** chart ramp; signed series overlay green/red, BTC uses Bitcoin orange. |
| **Violet money-flow** color. | A **mono + bronze** flow ramp (income = ink, savings = green); legacy violet token aliased to bronze. |
| Multi-color ambient background gradient for glass to refract. | A **near-flat** neutral canvas with a barely-there single-hue lift; depth comes from glass + content. |
| Substimate's **9 selectable visual styles** (aurora, brutalist, claymorphism, glassmorphism, minimal, modern, neobrutalist, neumorphism, retro). | **One** Obsidian Liquid Glass language; the only appearance choice is `system / light / dark` ([ADR-0009](./12-decisions-adr.md)). |
| Substimate `data-currency="BTC"` ad-hoc global highlight override. | `btc` / `--fm-btc` is a fixed **semantic** token used only in BTC/sats contexts. |
| Substimate `lucide-react` `IconSelector`. | SF Symbols throughout. |

See the full migration map in [Substimate Analysis & Migration Map](./11-substimate-analysis.md).

---

## 13. Cross-client parity & the component gallery

- **iOS** ships a `ComponentGallery` (`App/Sources/DesignSystemGallery.swift`) — a single scrollable showcase of the palette (color roles, money-flow ramp, chart ramp), the type ramp, every button kind/size, badges, stat tiles, list rows, amount text, the segmented control, and the loading/empty/error/toast states, with light + dark `#Preview`s. It is not in the tab bar; it exists for design review and snapshot testing.
- **Web** mirrors it with `Styleguide` (`web/src/features/styleguide/Styleguide.tsx`) reading every swatch from a CSS variable — color roles, financial semantics, money-flow + chart ramps, buttons, badges, segmented control, toggle, the three glass levels, radii, spacing, and the type ramp — so the two clients can be eyeballed for parity.

Both showcases prove the rule that feature code uses **only** tokens and shared components — no ad-hoc colors, blurs, or spacing.

---

## 14. Related documents

- [../CLAUDE.md](../CLAUDE.md) — Single source of truth & entry point.
- [./00-index.md](./00-index.md) — Documentation index & reading order.
- [./02-product-spec.md](./02-product-spec.md) — Screens & flows this system styles (tabs, dashboard, calendar, cost tracker).
- [./03-architecture.md](./03-architecture.md) — Where the design layer sits in the module graph; navigation/router.
- [./04-tech-stack.md](./04-tech-stack.md) — iOS 18 minimum, Xcode 26 / Swift 6, Swift Charts.
- [./05-data-model.md](./05-data-model.md) — `Money`, `Category`, `DashboardLayout`, `UserPreferences.appearance`, currencies.
- [./10-task-backlog.md](./10-task-backlog.md) — design-system backlog (M0-DS-\*, M1-DS-\*, M7-DS-\*).
- [./11-substimate-analysis.md](./11-substimate-analysis.md) — Full Substimate → Finmate migration map.
- [./12-decisions-adr.md](./12-decisions-adr.md) — ADR-0004 (deployment target), ADR-0009 (single design language / no user themes), ADR-0011 (Sankey renderer).
- [./14-visualizations-and-charts.md](./14-visualizations-and-charts.md) — chart styling, the money-flow renderer, dashboard cards.
