# Visualizations & Charts — End-to-End Rendering Specification

> The authoritative, per-visual contract for **every** graphic, chart, gauge, stat-surface, and the custom money-flow (Sankey) renderer in Finmate. For each visual this document fixes: where it appears, the data series/stat it shows (referencing the calc in [`./13-algorithms-and-calculations.md`](./13-algorithms-and-calculations.md)), the chart type + Swift Charts mark configuration (or the `Canvas`/`Path` approach), axes/scales/legend, color mapping to the [`./06-design-system.md`](./06-design-system.md) tokens, interaction, animation, empty/loading/error states, and **accessibility** (VoiceOver chart descriptions / `AXChartDescriptor` / audio graph, Reduce Motion, Reduce Transparency, color-independent encoding, Dynamic Type).
>
> **Normative inputs (do not contradict):** charts use **Swift Charts** where a mark exists; the money-flow uses the **custom `Canvas`/`Path` renderer** (`MoneyFlowDiagram`) because Swift Charts has no Sankey mark ([`./06-design-system.md §8.2`](./06-design-system.md)). All colors come from the [`./06-design-system.md §3`](./06-design-system.md) tokens — **no new colors are invented here.** All money is `Int64` **minor units**; conversion is **display-only** and never mutates stored amounts ([`./04-tech-stack.md` "Currency & conversion"](./04-tech-stack.md), [`./05-data-model.md §2.2`](./05-data-model.md)). Calculations are owned by [`./13-algorithms-and-calculations.md`](./13-algorithms-and-calculations.md); this document references those algorithm sections (written as a link to [`./13-algorithms-and-calculations.md`](./13-algorithms-and-calculations.md) + the section number) rather than re-deriving the math.
>
> **Base date for all worked examples:** `2026-06-28`.

---

## Table of contents

1. [Principles & the rendering contract](#1-principles--the-rendering-contract)
2. [Shared chart chrome & infrastructure](#2-shared-chart-chrome--infrastructure)
3. [Visual catalog index](#3-visual-catalog-index)
4. [Line & area charts (trends)](#4-line--area-charts-trends)
5. [Bar & stacked-bar charts](#5-bar--stacked-bar-charts)
6. [Donut / pie charts (distributions)](#6-donut--pie-charts-distributions)
7. [Sparklines](#7-sparklines)
8. [KPI / stat cards](#8-kpi--stat-cards)
9. [Usage gauges](#9-usage-gauges)
10. [Price-history timeline](#10-price-history-timeline)
11. [The custom money-flow (Sankey) renderer](#11-the-custom-money-flow-sankey-renderer)
12. [Dashboard card system & skeleton loaders](#12-dashboard-card-system--skeleton-loaders)
13. [Calendar dot visualization](#13-calendar-dot-visualization)
14. [Accessibility playbook (all visuals)](#14-accessibility-playbook-all-visuals)
15. [System & architecture diagrams inventory](#15-system--architecture-diagrams-inventory)
16. [Definition of Done for a visual](#16-definition-of-done-for-a-visual)
17. [Related documents](#17-related-documents)

---

## 1. Principles & the rendering contract

Every visual in Finmate obeys the same five hard rules. They are restated once here and assumed for every entry in the catalog.

| # | Rule | Why / where |
| --- | --- | --- |
| **V1** | **Money never reaches a chart as a `Double`.** Chart marks plot a `Double` *projection* of an `Int64` minor-unit value, produced **once** at the data-prep boundary by `Money.chartValue` (minor units → `Decimal` → `Double`, divided by the currency's minor-unit factor). Axis labels, tooltips, legends, and the VoiceOver readout are formatted from the **original `Money`**, never from the plotted `Double`. The plotted `Double` is for pixel geometry only. | [`./05-data-model.md §2.2`](./05-data-model.md); V1 prevents Substimate's float-money class of bug. |
| **V2** | **One palette, from tokens only.** Categorical hues come from `ChartPalette.categorical` (7 + BTC); financial direction uses `fmFinancialUp`/`fmFinancialDown`/`fmFinancialNeutral`/`fmFinancialWarning`; BTC uses `fmBTC`. No literal hex in feature or chart code. | [`./06-design-system.md §3.3`](./06-design-system.md) |
| **V3** | **Color is never the only encoding.** Every series/slice/segment is also distinguished by a label, a legend with a shape/swatch, a dash pattern (BTC), an icon, or a direct value annotation, so the visual survives color-blindness, Reduce Transparency, and grayscale snapshots. | [`./06-design-system.md §10.5`](./06-design-system.md) |
| **V4** | **Every visual has a text equivalent.** Each chart exposes an `AXChartDescriptor` (Swift Charts `.accessibilityChartDescriptor`) **and** a one-line summary; the money-flow and any bespoke `Canvas` expose an `.accessibilityRepresentation` that is a navigable list. No visual is VoiceOver-silent. | [`./06-design-system.md §10.2`](./06-design-system.md), §8.2 |
| **V5** | **Three render tiers + three a11y switches.** Glass tooltips/cards follow the Tier A/B/C ladder (`glassBackground`); **Reduce Motion** disables every entrance/scrub/flow animation (routes through `fmAnimation`); **Reduce Transparency** makes tooltip/flow surfaces opaque; **Dynamic Type** scales every axis/legend/label (named text styles only). | [`./06-design-system.md §2, §6.2, §10`](./06-design-system.md) |

**Math ownership.** No visual recomputes a statistic. Each entry names the producing calc in [`./13-algorithms-and-calculations.md`](./13-algorithms-and-calculations.md) (e.g. [`§3 Subscription cost normalization`](./13-algorithms-and-calculations.md#3-subscription-cost-normalization), [`§5.2 Monthly trends`](./13-algorithms-and-calculations.md#52-monthly-trends-multi-series-last-6-months), [`§5.1 Category distribution`](./13-algorithms-and-calculations.md#51-category-distribution), [`§4 Lifetime cost`](./13-algorithms-and-calculations.md#4-lifetime-cost-price-history-walk), [`§5.3 Usage statistics`](./13-algorithms-and-calculations.md#53-usage-statistics), [`§5.4 Payment-method breakdown`](./13-algorithms-and-calculations.md#54-payment-method-breakdown), [`§7 Asset valuation`](./13-algorithms-and-calculations.md#7-asset-valuation), [`§2 Currency conversion`](./13-algorithms-and-calculations.md#2-currency-conversion), [`§6.5 Money-flow bucket values`](./13-algorithms-and-calculations.md#65-money-flow-bucket-values)). The Store hands the visual a **ready-to-plot view model** of `Money` values; the visual only geometry-projects and styles. If doc 13's numbering shifts, the section *titles* quoted here are the stable anchor.

**Package home.** All reusable chart code lives in `DesignSystem/Sources/DesignSystem/Charts/` (`ChartPalette.swift`, `FMChartStyle.swift`, `MoneyFlowDiagram.swift`) plus new files this spec implies: `FMLineChart.swift`, `FMBarChart.swift`, `FMDonutChart.swift`, `Sparkline.swift`, `KPIStatCard.swift`, `UsageGauge.swift`, `PriceHistoryChart.swift`, `ChartAccessibility.swift` (the `AXChartDescriptor` builders). Feature modules pass data + a config; they never style a chart inline. This honors the module-boundary rule (Features → `DesignSystem` + `Domain`, never `DataLayer`) from [`../CLAUDE.md §6`](../CLAUDE.md).

---

## 2. Shared chart chrome & infrastructure

### 2.1 `FMChartStyle` (the base modifier)

Every Swift Charts view is wrapped in `.modifier(FMChartStyle())` from [`./06-design-system.md §8.1`](./06-design-system.md). It sets the categorical foreground scale, grid lines (`fmHairline`), axis ticks/labels (`fmLabelSecondary`, `.caption` text style for Dynamic Type), and a clear plot background. This document does **not** re-style axes per chart unless an entry overrides a default.

### 2.2 The plotting bridge — `Money.chartValue`

```swift
// DesignSystem consumes this Domain helper; it is the ONLY place money becomes Double for plotting.
public extension Money {
    /// Pixel-geometry projection of this amount in its own currency's major unit.
    /// EUR/USD: minorUnits / 100; BTC: minorUnits (sats) plotted directly (integer domain).
    /// NEVER used for display — display uses `formatted(...)` from the original Money.
    var chartValue: Double {
        Double(truncating: decimalValue as NSDecimalNumber)  // decimalValue already = minor/factor
    }
}
```

Charts that aggregate across currencies always receive amounts **already converted to the display currency** by the Store ([`§2 Currency conversion`](./13-algorithms-and-calculations.md#2-currency-conversion)), so a single axis is unambiguous. The view model therefore carries `Money` in the display currency only.

### 2.3 Selection & the glass tooltip

A single reusable selection treatment is shared by the line, area, bar, and donut charts.

```swift
// FMChartSelection.swift — attaches a rule mark + glass callout on tap/scrub.
public struct FMChartCallout: View {
    let title: String          // e.g. "March 2026" or "Streaming"
    let primary: AttributedString  // Money.formatted(...) — never a raw Double
    let secondary: String?     // e.g. "32% of income"
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(primary).font(.fmAmount().weight(.semibold)).monospacedDigit()
            if let secondary { Text(secondary).font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(Spacing.sm)
        .glassBackground(.card, shape: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}
```

- **Tap-to-select** on bar/donut; **scrub** (drag) on line/area via `chartOverlay` + a `DragGesture`. Selection snaps to the nearest domain value.
- The callout shows the value formatted by `Money` (V1) and a context line (e.g. share %).
- Reduce Transparency → `glassBackground(.card)` collapses to opaque `fmSurface` (Tier C). Reduce Motion → the callout cross-fades in (`fmAnimation`) instead of springing.
- A selection emits `Haptics.selection()` once per snap ([`./06-design-system.md §6.3`](./06-design-system.md)).

### 2.4 Timeframe / window controls

Charts windowed by time use the shared `Picker(.segmented)` timeframe control ([`./06-design-system.md §7.8`](./06-design-system.md)):

| Control | Cases | Default | Drives |
| --- | --- | --- | --- |
| **Trends window** | last-6-months (fixed) | — | Monthly-trends line/bar ([`§5.2`](./13-algorithms-and-calculations.md#52-monthly-trends-multi-series-last-6-months)) |
| **Expense distribution window** | Week · Month · Year | **Month** (current) | Expense category donut ([`§5.1`](./13-algorithms-and-calculations.md#51-category-distribution), [`./02-product-spec.md §6.4a`](./02-product-spec.md)) |
| **Flow timeframe** | Monthly · Quarterly · Yearly | **Monthly** | Money-flow + supporting breakdowns ([`§6.5`](./13-algorithms-and-calculations.md#65-money-flow-bucket-values), [`./02-product-spec.md §6.3`](./02-product-spec.md)) |

Changing the window re-runs the relevant calc in [`./13-algorithms-and-calculations.md`](./13-algorithms-and-calculations.md); **no network call** is made if exchange rates are cached ([`§2 Currency conversion`](./13-algorithms-and-calculations.md#2-currency-conversion)).

### 2.5 Universal state machine

Every visual implements the same four states with shared components:

| State | Renderer | Spec |
| --- | --- | --- |
| **Loading** | `SkeletonView` ([`./06-design-system.md §7.11`](./06-design-system.md)) | Token-shaped placeholders; shimmer via `Motion.fade`, **static** `fmLabelTertiary` 12% fill under Reduce Motion. Offline-first means this is rare (cache serves reads). |
| **Empty** | `FMEmptyState` ([`./06-design-system.md §7.10`](./06-design-system.md)) | Glyph + headline + body + optional `.fmPrimary` CTA. **Never** a blank rectangle; never NaN/∞ (every ratio guards divide-by-zero per [`./13-algorithms-and-calculations.md`](./13-algorithms-and-calculations.md)). |
| **Error** | inline retry banner | Last successful figures remain visible; non-blocking. |
| **Ready** | the chart | Below. |

---

## 3. Visual catalog index

| # | Visual | Type | Where | Series / stat (calc) | §  |
| --- | --- | --- | --- | --- | --- |
| C1 | Monthly Trends (cash flow) | Line + area, multi-series | Cash Flow overview; Money-flow screen | `income, expenses, fixed, variable, subscriptions, investments, savings, savingsRatio, investmentRatio` ([`§5.2`](./13-algorithms-and-calculations.md#52-monthly-trends-multi-series-last-6-months)) | [§4.1](#41-monthly-trends--cash-flow-multi-series-line--area) |
| C2 | Subscription Monthly Trends | Area | Subscription Analytics | monthly subscription cost, 6 mo ([`§5.2`](./13-algorithms-and-calculations.md#52-monthly-trends-multi-series-last-6-months)) | [§4.2](#42-subscription-monthly-trends) |
| C3 | Monthly Trends stacked bars | Stacked bar + overlays | Money-flow screen | fixed/variable/subscriptions stacked, income/savings/investment overlays ([`§5.2`](./13-algorithms-and-calculations.md#52-monthly-trends-multi-series-last-6-months)) | [§5.1](#51-monthly-trends-stacked-bar-with-overlays) |
| C4 | Payment-Method Breakdown | Horizontal bar | Subscription Analytics | monthly cost & count per payment method ([`§5.4`](./13-algorithms-and-calculations.md#54-payment-method-breakdown)) | [§5.2](#52-payment-method-breakdown-horizontal-bar) |
| C5 | Top Categories (mini bar) | Horizontal bar (compact) | Home `category-spotlight` card | top-3 category monthly spend ([`§5.1`](./13-algorithms-and-calculations.md#51-category-distribution)) | [§5.3](#53-top-categories-mini-bar-home-card) |
| C6 | Usage / billing-period distribution | Bar | Subscription Analytics (Usage) | counts per usage state & billing period ([`§5.3`](./13-algorithms-and-calculations.md#53-usage-statistics)) | [§5.4](#54-usage--billing-period-distribution-bars) |
| C7 | Subscription Category Distribution | Donut + legend | Subscription Analytics | monthly cost per subscription category ([`§5.1`](./13-algorithms-and-calculations.md#51-category-distribution)) | [§6.1](#61-subscription-category-distribution-donut) |
| C8 | Expense Category Distribution | Donut + legend (windowed) | Money-flow screen | windowed expense spend per category ([`§5.1`](./13-algorithms-and-calculations.md#51-category-distribution)) | [§6.2](#62-expense-category-distribution-windowed-donut) |
| C9 | Asset Distribution | Donut + legend | Assets list | portfolio value by asset type ([`§7`](./13-algorithms-and-calculations.md#7-asset-valuation)) | [§6.3](#63-asset-distribution-donut) |
| C10 | Card sparklines | Sparkline (line) | Home cards | mini 6-pt trend ([`§5.2`](./13-algorithms-and-calculations.md#52-monthly-trends-multi-series-last-6-months) slice) | [§7](#7-sparklines) |
| C11 | KPI / stat cards | Stat surface | Home, Cash Flow, Assets, Analytics | totals, deltas, ratios ([`§3`](./13-algorithms-and-calculations.md#3-subscription-cost-normalization), [`§5.2`](./13-algorithms-and-calculations.md#52-monthly-trends-multi-series-last-6-months), [`§5.3`](./13-algorithms-and-calculations.md#53-usage-statistics), [`§7`](./13-algorithms-and-calculations.md#7-asset-valuation)) | [§8](#8-kpi--stat-cards) |
| C12 | Usage gauges | Radial / linear gauge | Subscription Analytics; Cash Flow | usage-state share, savings-rate ([`§5.3`](./13-algorithms-and-calculations.md#53-usage-statistics), [`§5.2`](./13-algorithms-and-calculations.md#52-monthly-trends-multi-series-last-6-months)) | [§9](#9-usage-gauges) |
| C13 | Price-history timeline | Step line + points | Subscription Detail → Price History | price over time, corrections ([`§4`](./13-algorithms-and-calculations.md#4-lifetime-cost-price-history-walk) inputs) | [§10](#10-price-history-timeline) |
| C14 | **Money-flow (Sankey)** | Custom `Canvas`/`Path` | Money-flow screen (Cash Flow) | bucketed flow + drill-down ([`§6.5`](./13-algorithms-and-calculations.md#65-money-flow-bucket-values)) | [§11](#11-the-custom-money-flow-sankey-renderer) |
| C15 | Calendar charge dots | Dot glyph grid | Calendar | projected charge/payday markers ([`§11.1`](./13-algorithms-and-calculations.md#111-subscription-charge-projection) charge projection) | [§13](#13-calendar-dot-visualization) |
| C16 | Dashboard cards & skeletons | Card system | Home | composition + loaders | [§12](#12-dashboard-card-system--skeleton-loaders) |
| C17 | Lifetime Cost (ranked) | Horizontal bar (ranked) | Subscription Analytics | total spent per subscription since start ([`§4`](./13-algorithms-and-calculations.md#4-lifetime-cost-price-history-walk)) | [§5.5](#55-lifetime-cost-ranked-horizontal-bar) |

---

## 4. Line & area charts (trends)

### 4.1 Monthly Trends — cash flow (multi-series line + area)

**Where.** Cash Flow Overview ([`./02-product-spec.md §5.3`](./02-product-spec.md)) and the Money-flow screen header ([`./02-product-spec.md §6.4`](./02-product-spec.md)) — same dataset, two presentations (here as lines/area; the stacked-bar presentation is [§5.1](#51-monthly-trends-stacked-bar-with-overlays)).

**Data / stat.** The full monthly-trends series for the **last 6 months**, computed in [`§5.2 Monthly trends`](./13-algorithms-and-calculations.md#52-monthly-trends-multi-series-last-6-months): per month `income`, `expenses`, `fixedExpenses`, `variableExpenses`, `subscriptionCosts`, `investments` (the per-month sum of `buy` asset-transactions, defined as the `investments` series in [`§5.2`](./13-algorithms-and-calculations.md#52-monthly-trends-multi-series-last-6-months)), `savings = income − expenses`, `savingsRatio` (% of income saved, **0 when income = 0**), `investmentRatio` (% of income invested, **0 when income = 0**). Each money series is in display currency ([`§2 Currency conversion`](./13-algorithms-and-calculations.md#2-currency-conversion)). Domain is 6 ordered `Month` buckets.

**Chart type & marks.** Swift Charts. **Income** and **Expenses** are the two prominent series; the rest back tooltips and an optional "Breakdown" toggle.

```swift
Chart {
    // Income — emerald area + line
    ForEach(points) { p in
        AreaMark(x: .value("Month", p.month), y: .value("Amount", p.income.chartValue))
            .foregroundStyle(.linearGradient(
                colors: [Color.fmFinancialUp.opacity(0.22), Color.fmFinancialUp.opacity(0.0)],
                startPoint: .top, endPoint: .bottom))
            .interpolationMethod(.monotone)
            .accessibilityLabel(p.month.title)
            .accessibilityValue(p.income.formatted())
    }
    ForEach(points) { p in
        LineMark(x: .value("Month", p.month), y: .value("Amount", p.income.chartValue))
            .foregroundStyle(Color.fmFinancialUp)
            .lineStyle(.init(lineWidth: 2))
            .symbol { Circle().frame(width: 5, height: 5) }   // shape marker = color-independence (V3)
            .foregroundStyle(by: .value("Series", "Income"))
    }
    // Expenses — red line, dashed-free but distinct symbol (square)
    ForEach(points) { p in
        LineMark(x: .value("Month", p.month), y: .value("Amount", p.expenses.chartValue))
            .foregroundStyle(Color.fmFinancialDown)
            .lineStyle(.init(lineWidth: 2))
            .symbol(.square)
            .foregroundStyle(by: .value("Series", "Expenses"))
    }
    if let sel = selectedMonth {
        RuleMark(x: .value("Month", sel.month)).foregroundStyle(Color.fmHairline)
    }
}
.chartForegroundStyleScale([
    "Income":   Color.fmFinancialUp,
    "Expenses": Color.fmFinancialDown
])
.modifier(FMChartStyle())
```

- **Breakdown toggle** (segmented "Net / Breakdown"): in Breakdown mode add thin secondary `LineMark`s for `fixedExpenses` (palette Red 6), `variableExpenses` (Orange 7), `subscriptionCosts` (Violet 4), `investments` (BTC-independent: palette Blue 3); `savings` shown as a subtle `AreaMark` between income and expenses tinted `fmFinancialUp` 10%.

**Axes / scales / legend.** X = categorical month abbreviations ("Jan"…"Jun"), `.caption`. Y = `Money`-formatted currency, **0-baselined**, auto domain to `max(income, expenses) × 1.1`; ticks formatted via a compact currency style (e.g. "€2k") with full values in the callout. Legend below the plot: a swatch + shape marker + series name (color-independent). BTC display currency → y axis label shows "sats" and uses grouping, no decimals.

**Color mapping.** Income → `fmFinancialUp`; Expenses → `fmFinancialDown` (these intentionally share hue family with palette slots 1/6, [`./06-design-system.md §3.3`](./06-design-system.md)). Breakdown series map to the palette slots above. Investments series uses Blue 3, **not** `fmBTC` (investments ≠ BTC denomination).

**Interaction.** Horizontal **scrub**: a `DragGesture` over `chartOverlay` resolves the nearest month; a `RuleMark` + `FMChartCallout` shows that month's income, expenses, savings, and savings-rate. Tapping the legend toggles a series' visibility (with the toggle persisted per session, not stored). Each snap → `Haptics.selection()`.

**Animation.** On first appearance, lines draw left-to-right via a `.trim`-style mask over 0.35s (`Motion.springStandard` budget); area fades up. **Reduce Motion** → no draw-on; the chart appears at full extent with a 0.2s cross-fade.

**Empty / loading / error.**
- Empty (no income & no expenses): `FMEmptyState` "Add income and expenses to see your trends" + Add CTA.
- Some months zero: still plotted at 0 (a flat segment), never omitted — the 6-month axis is always complete.
- Loading: redacted plot + legend skeleton.
- `savingsRatio`/`investmentRatio` are guaranteed 0 (not NaN) when income = 0 by [`§5.2`](./13-algorithms-and-calculations.md#52-monthly-trends-multi-series-last-6-months).

**Accessibility.**
- `AXChartDescriptor`: X = categorical month axis; Y = numeric currency axis (label "Amount", formatted by `Money`); two series ("Income", "Expenses") with each month's data point carrying `.accessibilityValue(Money.formatted)`. VoiceOver can play the **audio graph** (rising/falling tone per series).
- One-line summary read first: *"Cash flow, last 6 months. Income trending up, June 4,200 euros. Expenses June 3,150 euros. Savings rate 25 percent."*
- Color-independence: distinct line symbols (circle vs square) + legend swatches; up/down also implied by the financial tokens.
- Dynamic Type: axis labels use `.caption`; at AX5 the legend wraps to two rows and tick density halves (`chartXAxis` `values:` thinned).

#### Worked example (C1)

Inputs (display currency EUR, all already converted, [`§5.2`](./13-algorithms-and-calculations.md#52-monthly-trends-multi-series-last-6-months)):

| Month | income | expenses | fixed | variable | subs | investments | savings | savingsRatio |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Jan | €4,000.00 | €3,400.00 | €1,800.00 | €900.00 | €700.00 | €200.00 | €600.00 | 15% |
| Feb | €4,000.00 | €3,250.00 | €1,800.00 | €750.00 | €700.00 | €0.00 | €750.00 | 18.75% |
| Mar | €4,200.00 | €3,150.00 | €1,800.00 | €640.00 | €710.00 | €500.00 | €1,050.00 | 25% |
| Apr | €4,200.00 | €3,500.00 | €1,850.00 | €930.00 | €720.00 | €0.00 | €700.00 | 16.67% |
| May | €4,200.00 | €3,300.00 | €1,850.00 | €730.00 | €720.00 | €300.00 | €900.00 | 21.43% |
| Jun | €4,500.00 | €3,150.00 | €1,850.00 | €580.00 | €720.00 | €0.00 | €1,350.00 | 30% |

Plotting (`Money.chartValue`, EUR factor 100): income Jun `450000 → 4500.0`. Y domain `0 … max(4500) × 1.1 = 4950.0`. Scrub to Mar → callout "March 2026 / Income €4,200.00 / Expenses €3,150.00 / Savings 25%". The stored minor units (e.g. `450000`) are untouched; only the projected `Double` feeds geometry (V1).

### 4.2 Subscription Monthly Trends

**Where.** Subscription Analytics, "Monthly Trends" ([`./02-product-spec.md §4.7`](./02-product-spec.md)).

**Data / stat.** Total **subscription** cost per month over 6 months, where yearly subscriptions contribute only in **anniversary months** and weekly/monthly/quarterly contribute their monthly-equivalent ([`§3 Subscription cost normalization`](./13-algorithms-and-calculations.md#3-subscription-cost-normalization) + [`§5.2`](./13-algorithms-and-calculations.md#52-monthly-trends-multi-series-last-6-months)), walking price history ([`§4 Lifetime cost`](./13-algorithms-and-calculations.md#4-lifetime-cost-price-history-walk)) so the price effective in each month is used. Display currency.

**Chart type & marks.** Single-series `AreaMark` + `LineMark`, 2pt stroke, area gradient `Violet 4 → Violet 4 @ 8%` (subscriptions = palette slot 4 per the money-flow convention). `.interpolationMethod(.monotone)`. Anniversary spikes are real data points, not annotations.

**Axes / interaction / animation / states / a11y.** Identical chrome to C1 (single series). Scrub callout shows the month total + count of charging subscriptions that month. Empty: "Add subscriptions to see trends". `AXChartDescriptor`: one numeric series over the month axis; summary *"Subscription cost, 6 months, June 84 euros, peak in March due to a yearly renewal."*

---

## 5. Bar & stacked-bar charts

### 5.1 Monthly Trends stacked bar (with overlays)

**Where.** Money-flow screen "Monthly Trends" presentation ([`./02-product-spec.md §6.4`](./02-product-spec.md)). Same [`§5.2`](./13-algorithms-and-calculations.md#52-monthly-trends-multi-series-last-6-months) dataset as C1.

**Data / stat.** Per month, a **stacked bar** of the three expense components (`fixedExpenses`, `variableExpenses`, `subscriptionCosts`) whose sum equals `expenses`; **overlays**: an `income` line, a `savings` line, and an `investments` point/marker.

**Chart type & marks.**

```swift
Chart(points) { p in
    // Stacked expense bar — position stacking sums to total expenses
    BarMark(x: .value("Month", p.month), y: .value("Fixed", p.fixed.chartValue))
        .foregroundStyle(by: .value("Component", "Fixed"))
    BarMark(x: .value("Month", p.month), y: .value("Variable", p.variable.chartValue))
        .foregroundStyle(by: .value("Component", "Variable"))
    BarMark(x: .value("Month", p.month), y: .value("Subscriptions", p.subscriptions.chartValue))
        .foregroundStyle(by: .value("Component", "Subscriptions"))
    // Income overlay line
    LineMark(x: .value("Month", p.month), y: .value("Income", p.income.chartValue))
        .foregroundStyle(Color.fmFinancialUp).lineStyle(.init(lineWidth: 2)).symbol(.circle)
    // Savings overlay line
    LineMark(x: .value("Month", p.month), y: .value("Savings", p.savings.chartValue))
        .foregroundStyle(Color.fmFinancialUp.opacity(0.5)).lineStyle(.init(lineWidth: 1.5, dash: [4,3]))
    // Investments marker
    PointMark(x: .value("Month", p.month), y: .value("Investments", p.investments.chartValue))
        .foregroundStyle(Color(ChartPalette.categorical[2]))   // Blue 3
        .symbol(.diamond)
}
.chartForegroundStyleScale([
    "Fixed":         Color(ChartPalette.categorical[5]),  // Red 6
    "Variable":      Color(ChartPalette.categorical[6]),  // Orange 7
    "Subscriptions": Color(ChartPalette.categorical[3])   // Violet 4
])
.modifier(FMChartStyle())
```

- Bars: 4pt top corner radius ([`./06-design-system.md §8.1`](./06-design-system.md)).
- **Color-independence:** the stack is also explained by an ordered legend (Fixed/Variable/Subscriptions) with swatches; overlays use distinct line dash + point shapes (circle/diamond/dashed).

**Axes / scale.** X categorical months; Y 0-baselined currency, domain `max(income, totalExpenses) × 1.1`. Legend shows 3 stack components + income/savings/investment overlays with their shape markers.

**Interaction.** Tap a month's bar → callout with the full stack breakdown (Fixed €X, Variable €Y, Subscriptions €Z) plus income, savings, investments for that month. `Haptics.selection()`.

**Animation.** Bars grow up from baseline (0.35s, staggered 20ms per month); overlays draw after. Reduce Motion → instant with cross-fade.

**States.** Empty/loading/error as §2.5. A month with zero expenses shows no bar segment but the income line still plots.

**Accessibility.** `AXChartDescriptor` exposes a categorical month axis with **three stacked series** + overlay series; summary *"Monthly expenses by type. June: fixed 1,850, variable 580, subscriptions 720, total 3,150 euros; income 4,500."* Each bar segment carries an `.accessibilityLabel` ("June fixed") + `.accessibilityValue` (`Money.formatted`).

### 5.2 Payment-Method Breakdown (horizontal bar)

**Where.** Subscription Analytics ([`./02-product-spec.md §4.7`](./02-product-spec.md), analytic 5).

**Data / stat.** Per `paymentMethod` (8 enum values: `credit_card, debit_card, paypal, bank_transfer, apple_pay, google_pay, crypto, other`): total monthly-equivalent cost and subscription count + average cost/service ([`§5.4 Payment-method breakdown`](./13-algorithms-and-calculations.md#54-payment-method-breakdown)). Sorted descending by total cost. Display currency.

**Chart type & marks.** Horizontal `BarMark` (`x` = amount, `y` = payment method, `.value` ordered by total desc). Each bar labeled at its end with the formatted total; subscript count shown as a `.caption2` annotation. Bar color = palette by index (categorical), but because these are categories not directions, also annotate each bar with its payment-method **SF Symbol** (e.g. `creditcard`, `applelogo`/`apple.logo`, `bitcoinsign`) for color-independence.

**Axes / scale.** Y = method names (Dynamic-Type wrapping; at AX5 names truncate with VoiceOver carrying the full name). X = currency, 0-based. No gridline clutter — one subtle vertical guide at the max.

**Interaction.** Tap a bar → callout: method name, total monthly cost, count, average per service. `Haptics.selection()`.

**Animation.** Bars wipe in left-to-right, staggered top-to-bottom. Reduce Motion → instant.

**States.** Empty: "No subscriptions to break down". Methods with zero subscriptions are **omitted** (no zero-length bar). Average per service guards divide-by-zero ([`§5.4`](./13-algorithms-and-calculations.md#54-payment-method-breakdown)).

**Accessibility.** `AXChartDescriptor` with categorical method axis + numeric cost axis; each bar `.accessibilityValue("12 euros 99 cents, 3 subscriptions")`. Summary *"Spending by payment method. Credit card highest at 45 euros across 4 subscriptions."*

### 5.3 Top Categories (mini bar, Home card)

**Where.** Home dashboard `category-spotlight` card ([`./02-product-spec.md §3.2`](./02-product-spec.md)); taps through to Subscription Analytics.

**Data / stat.** Top **3** spend categories this month by monthly-equivalent cost ([`§5.1 Category distribution`](./13-algorithms-and-calculations.md#51-category-distribution), truncated to 3). Display currency.

**Chart type & marks.** Compact horizontal `BarMark` (3 rows), each row = category icon badge (`CategoryIconBadge`, [`./06-design-system.md §9.3`](./06-design-system.md)) + name + bar + amount. Bar color = the category's own design-token tint (its palette slot from the category→tint mapping in [`./06-design-system.md §9.3`](./06-design-system.md)). No axis (it is a card mini-viz); the longest bar = card width.

**Interaction.** Whole card is the tap target (deep-link), not per-bar. No scrub.

**Animation.** Bars grow on card appear; Reduce Motion → instant.

**States.** Empty: card shows "Add subscriptions to see top categories". Fewer than 3 categories → show what exists (1 or 2 rows).

**Accessibility.** Card is one combined element with a label listing the three categories + amounts: *"Top categories: Streaming 32 euros, AI Chat 24 euros, Music 12 euros. Double-tap to open analytics."* Color-independent (icon + name + amount per row).

### 5.4 Usage / billing-period distribution (bars)

**Where.** Subscription Analytics → Usage Statistics ([`./02-product-spec.md §4.7`](./02-product-spec.md), analytic 4).

**Data / stat.** Two small bar charts: (a) **usage-state distribution** — counts & % of `active`/`rarely`/`unused`; (b) **billing-period distribution** — counts of `weekly`/`monthly`/`quarterly`/`yearly` ([`§5.3`](./13-algorithms-and-calculations.md#53-usage-statistics)).

**Chart type & marks.** Vertical `BarMark`, count on Y. Usage-state bars colored by **financial-state semantics**: `active` → `fmFinancialNeutral`, `rarely` → `fmFinancialWarning`, `unused` → `fmFinancialDown` ([`./06-design-system.md §3.2`](./06-design-system.md), matching the list-row usage accents in [`./02-product-spec.md §4.2`](./02-product-spec.md)). Billing-period bars use categorical palette slots 1–4. Each bar annotated with count + % above it (color-independence).

**Interaction.** Tap → callout (count, %). **Animation/States/Loading** as §2.5; empty → "No subscriptions yet".

**Accessibility.** `AXChartDescriptor` per chart; summary *"Usage: 7 active, 2 rarely used, 1 unused."* The warning/down colors are paired with their canonical glyphs in the adjacent legend (`exclamationmark.triangle.fill`, etc.).

### 5.5 Lifetime Cost (ranked horizontal bar)

**Where.** Subscription Analytics → Lifetime Cost ([`./02-product-spec.md §4.7`](./02-product-spec.md), analytic 3; [`./02-product-spec.md §4.7.3`](./02-product-spec.md)).

**Data / stat.** Per subscription, the **total amount spent since `startDate`** — `lifetimeCostMinor` from [`§4 Lifetime cost (price-history walk)`](./13-algorithms-and-calculations.md#4-lifetime-cost-price-history-walk), which walks the price-history segments (correction-aware, never double-counting a corrected step) and returns `(totalMinor, monthsActive)`. Each bar carries the lifetime total, the **months-active** count, and the **current monthly cost** (the subscription's monthly-equivalent, [`§3`](./13-algorithms-and-calculations.md#3-subscription-cost-normalization)). Per-segment display conversion is applied by the analytics layer before summing across currencies ([`§2 Currency conversion`](./13-algorithms-and-calculations.md#2-currency-conversion)), so the axis is a single display currency.

**Chart type & marks.** The same `FMBarChart` as C4 — a horizontal `BarMark` (`x` = lifetime total, `y` = subscription name), one row per subscription, **sorted descending by lifetime cost** (largest spend at top), ties broken by name ascending for deterministic order. Each bar is labeled at its end with the formatted lifetime total; a `.caption2` annotation under the name carries "`N` mo · `€X.XX`/mo" (months-active + current monthly cost). Bar color = categorical palette by rank index; because these are subscriptions (not financial directions), each bar is also prefixed with the subscription's category icon badge (`CategoryIconBadge`, [`./06-design-system.md §9.3`](./06-design-system.md)) for color-independence (V3).

**Axes / scale.** Y = subscription names (Dynamic-Type wrapping; at AX5 names truncate with VoiceOver carrying the full name). X = currency, 0-based, one subtle vertical guide at the max (no gridline clutter). A "Top N" cap (e.g. 10) keeps the list legible; a trailing "Show all" row deep-links to the full list. BTC display currency → x axis in sats with grouping, no decimals.

**Interaction.** Tap a bar → `FMChartCallout`: subscription name, lifetime total (`Money.formatted`), months active, and current monthly cost. `Haptics.selection()`. The row deep-links to that subscription's Detail → Price History (C13).

**Animation.** Bars wipe in left-to-right, staggered top-to-bottom (`Motion.springStandard`). Reduce Motion → instant.

**States.** Empty (no subscriptions): `FMEmptyState` "Add subscriptions to see lifetime cost". A brand-new subscription started today shows `monthsActive = 1` and one charge ([`§4.3`](./13-algorithms-and-calculations.md#43-partial-months--partial-periods)) — a real, non-zero bar, never blank. Loading → redacted bar list. No divide is performed (lifetime cost is a sum), so no NaN is possible.

**Accessibility.** `AXChartDescriptor` with a categorical subscription axis + numeric currency axis; each bar `.accessibilityValue("249 euros 88 cents, 25 months, 9 euros 99 cents per month")`. Summary read first: *"Lifetime cost by subscription. Highest: Spotify, 249 euros over 25 months."* Color-independence via category icons + the end-of-bar value labels + the months/monthly caption. Dynamic Type scales names and annotations; at AX5 the monthly-cost caption drops to the callout/VoiceOver only.

#### Worked example (C17)

Lifetime totals (display EUR, [`§4`](./13-algorithms-and-calculations.md#4-lifetime-cost-price-history-walk)): Spotify €249.88 (25 mo, €9.99/mo), Netflix €77.94 (6 mo, €12.99/mo — includes a corrected price step, not double-counted, [`§4.4`](./13-algorithms-and-calculations.md#44-corrections)), iCloud €23.94 (6 mo, €3.99/mo). Sorted desc → Spotify, Netflix, iCloud. Bars plotted via `Money.chartValue` (EUR factor 100: `24988 → 249.88`); X domain `0 … 249.88 × 1.1`. Labels and the months/monthly captions are formatted from `Money` (V1); the projected `Double` feeds geometry only.

---

## 6. Donut / pie charts (distributions)

All donuts use Swift Charts `SectorMark` (iOS 17+), `.innerRadius(.ratio(0.62))`, `angularInset: 2`, a 2pt `fmBackgroundElevated` stroke between slices ([`./06-design-system.md §8.1`](./06-design-system.md)), and a **center label** showing the total. They share `FMDonutChart`.

### 6.1 Subscription Category Distribution (donut)

**Where.** Subscription Analytics → Category Distribution ([`./02-product-spec.md §4.7`](./02-product-spec.md), analytic 2).

**Data / stat.** Monthly-equivalent cost per **subscription** category, with per-category subscription count and average cost/service ([`§5.1`](./13-algorithms-and-calculations.md#51-category-distribution)). Display currency. Slices ordered descending by amount; categories beyond a threshold (e.g. > 7) collapse into a trailing **"Other categories"** slice using `fmFinancialNeutral` so the ring stays legible.

**Chart type & marks.**

```swift
Chart(slices) { s in
    SectorMark(angle: .value("Cost", s.monthly.chartValue),
               innerRadius: .ratio(0.62), angularInset: 2)
        .cornerRadius(2)
        .foregroundStyle(s.category.tintColor)        // category's design-token tint
        .annotation(position: .overlay) {
            if s.fraction >= 0.08 { Text(s.percentLabel).font(.caption2) }  // inline % on big slices
        }
}
.chartBackground { _ in
    VStack { Text("Total").font(.caption).foregroundStyle(.secondary)
             Text(total.formatted()).font(.titleS).monospacedDigit() }
}
```

**Axes / legend.** No axes. A **two-column legend** below: swatch + category icon + name + amount + count + average. Legend is the primary color-independent encoding (donuts are not color-readable for color-blind users without it). Slices ≥ 8% carry an inline % label.

**Color mapping.** Each slice uses its **category tint** (the per-category palette slot from [`./06-design-system.md §9.3`](./06-design-system.md)), not a sequential palette walk, so a category keeps the same color across the donut, the mini bar (C5), and its list rows. Collapsed "Other categories" → `fmFinancialNeutral`.

**Interaction.** Tap a slice → it lifts (outer radius +4pt) and the center label switches to that slice's name + amount + % of total + count; legend row highlights. Tap center or background → reset to total. `Haptics.selection()`.

**Animation.** Slices sweep in clockwise from 12 o'clock over 0.4s. Reduce Motion → instant draw + cross-fade.

**States.** Empty: `FMEmptyState` "Add subscriptions to see category split". Single category → a full ring (100%). Divide-by-zero in averages guarded ([`§5.1`](./13-algorithms-and-calculations.md#51-category-distribution)); never a NaN slice.

**Accessibility.** `AXChartDescriptor` models each slice as a categorical data point (category name) with numeric value (cost) and the additional `.accessibilityValue` carrying "X percent, N subscriptions". Summary *"Category split: Streaming 38 percent (32 euros), AI Chat 28 percent, Music 14 percent, plus 3 more."* Selection announces the focused slice. Color-independent via the legend.

#### Worked example (C7)

Monthly-equivalent per category (EUR, [`§5.1`](./13-algorithms-and-calculations.md#51-category-distribution)): Streaming €32.00, AI Chat €24.00, Music €12.00, Coding €9.00, Gaming €8.00. Total €85.00. Fractions: Streaming `3200/8500 = 37.6%`, AI Chat `28.2%`, Music `14.1%`, Coding `10.6%`, Gaming `9.4%`. Angles: `fraction × 360°` → Streaming `135.5°`, etc. (geometry from `chartValue`; labels from `Money` — V1). Center shows "Total €85.00".

### 6.2 Expense Category Distribution (windowed donut)

**Where.** Money-flow screen ([`./02-product-spec.md §6.4a`](./02-product-spec.md)).

**Data / stat.** Expense spend per **expense-kind** category, **windowed** by a Week/Month/Year control (default current month, [§2.4](#24-timeframe--window-controls)). Within the window: variable expenses filtered by `spent_on` inside the window; fixed expenses scaled into the window (`week ≈ /4, month ×1, year ×12`, precise factors per [`§3`](./13-algorithms-and-calculations.md#3-subscription-cost-normalization)). Slices group by category, sorted desc ([`§5.1`](./13-algorithms-and-calculations.md#51-category-distribution)). Display currency.

**Everything else** mirrors C7 (same `FMDonutChart`, same legend, same a11y), **plus** the timeframe segmented control above the ring. Changing the window re-runs [`§5.1`](./13-algorithms-and-calculations.md#51-category-distribution) for the new window with no network call.

**States.** Empty (no expenses in window): "No expenses this month" + the window control still visible so the user can widen to Year. **No NaN slice** when the window is empty ([`./02-product-spec.md §6.4a`](./02-product-spec.md) acceptance).

**Accessibility.** Summary includes the active window: *"Expenses this month: Housing 46 percent, Food 21 percent…"*. The window control is a labeled segmented `Picker` (VoiceOver: "Window, Month, selected").

### 6.3 Asset Distribution (donut)

**Where.** Assets list header ([`./02-product-spec.md §9.3`](./02-product-spec.md)).

**Data / stat.** Total portfolio current value grouped by asset `type` (`stock · crypto · savings · real_estate · other`), each slice = summed `valueMinor` of that type converted to display currency, shares sum to 100% ([`§7 Asset valuation`](./13-algorithms-and-calculations.md#7-asset-valuation)). Sorted desc.

**Chart type & marks.** `FMDonutChart`. Type → fixed token mapping for stable recognition: `stock` → Blue 3, `crypto` → **`fmBTC`** (crypto context is the one place `fmBTC` applies to a category), `savings` → Emerald 1, `real_estate` → Violet 4, `other` → `fmFinancialNeutral`. Center label shows total portfolio value.

**Interaction / animation / states.** As C7. Empty: "No assets yet — add a stock, crypto holding, or savings account" ([`./02-product-spec.md §9.5`](./02-product-spec.md)). Single type → full ring. Shares verified to sum to 100% (acceptance [`./02-product-spec.md §9.6`](./02-product-spec.md)).

**Accessibility.** Summary *"Portfolio by type: crypto 52 percent (10,400 euros), stocks 33 percent, savings 15 percent."* Each type's slice carries an `.accessibilityValue` with its value + share. Color-independent via legend + type icons.

---

## 7. Sparklines

**Where.** Home dashboard cards that benefit from a micro-trend: `monthly-burn`, `net-cash-flow`, `subscriptions-summary`, `assets-snapshot` ([`./02-product-spec.md §3.2`](./02-product-spec.md)). Always a *supporting* glyph beside a KPI, never the card's only content.

**Data / stat.** A 6-point slice of the relevant [`§5.2`](./13-algorithms-and-calculations.md#52-monthly-trends-multi-series-last-6-months) series (e.g. `monthly-burn` → 6-month monthly-burn; `net-cash-flow` → 6-month savings). Display currency. The Store passes a `[Money]` of length 6 (oldest→newest).

**Chart type & marks.** Compact Swift Charts `LineMark` with **no axes, no grid, no labels** (a true sparkline). 1.5pt stroke; a single end-point `PointMark` marks "now". Optional faint `AreaMark` gradient at 6% for fill.

```swift
public struct Sparkline: View {
    let points: [Money]          // length 6, display currency
    let direction: MoneyDirection  // up/down/flat from first→last (drives stroke color)
    public var body: some View {
        Chart(Array(points.enumerated()), id: \.offset) { i, m in
            LineMark(x: .value("i", i), y: .value("v", m.chartValue))
                .interpolationMethod(.monotone)
                .foregroundStyle(direction.color)
            if i == points.count - 1 {
                PointMark(x: .value("i", i), y: .value("v", m.chartValue))
                    .foregroundStyle(direction.color).symbolSize(28)
            }
        }
        .chartXAxis(.hidden).chartYAxis(.hidden)
        .chartPlotStyle { $0.background(.clear) }
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityLabel(Self.summary(points, direction))
    }
}
```

**Color mapping.** Stroke = `MoneyDirection.color` derived from first→last delta: rising savings → `fmFinancialUp`, rising burn → `fmFinancialDown` (the card decides which direction is "good" and passes the right `direction`). Flat → `fmFinancialNeutral`. **Color-independence:** the sparkline is always paired with the card's delta chip (sign + glyph), so trend direction is never color-only.

**Interaction.** None (the card is the tap target). No scrub on a sparkline.

**Animation.** Draw-on with the card's appearance (line trim, 0.3s). Reduce Motion → instant.

**States.** Fewer than 2 points → render nothing (no degenerate single dot); the card shows just the KPI. Loading → a flat `fmLabelTertiary` placeholder line. No empty-state glyph (the parent card owns empty messaging).

**Accessibility.** Single combined element. Label: *"Trend over 6 months, up 12 percent, latest 1,350 euros."* It is supplementary; the KPI value (C11) is the primary accessible content. Not a separately navigable chart (too small to be useful as `AXChartDescriptor`) — the **card** carries the audio-graph-grade detail when expanded.

---

## 8. KPI / stat cards

**Where.** Home (`monthly-burn`, `subscriptions-summary`, `net-cash-flow`, `assets-snapshot`), Cash Flow Overview Key Metrics (Monthly Income / Expenses / Net / Savings-rate), Subscription Analytics headers, Asset Detail ([`./02-product-spec.md §3.2, §5.3, §4.7, §9.2`](./02-product-spec.md)).

**Data / stat.** A single headline `Money` or ratio plus an optional **delta** vs the prior period: monthly burn ([`§3`](./13-algorithms-and-calculations.md#3-subscription-cost-normalization)), net cash flow & savings rate ([`§5.2`](./13-algorithms-and-calculations.md#52-monthly-trends-multi-series-last-6-months)), subscription count + monthly total + review count ([`§5.3`](./13-algorithms-and-calculations.md#53-usage-statistics)), portfolio value + gain/loss ([`§7`](./13-algorithms-and-calculations.md#7-asset-valuation)), 3-month vs prior-3-month deltas ([`§5.3`](./13-algorithms-and-calculations.md#53-usage-statistics)).

**Surface anatomy.** `KPIStatCard` (a `GlassCard`, [`./06-design-system.md §7.2`](./06-design-system.md)):

```
┌───────────────────────────────┐
│ TITLE (caption, secondary)     │   ← e.g. "Monthly Burn"
│ €3,150.00      [↑ 4.8%]        │   ← value: fmBalanceHero / fmAmount, mono-digit
│                ╰ delta chip     │      delta: MoneyDirection color + glyph + sign
│ ┄┄┄ sparkline (optional) ┄┄┄   │   ← C10, supporting
│ subtitle (footnote, secondary) │   ← e.g. "vs €3,005 last month"
└───────────────────────────────┘
```

- **Value typography:** hero figures use `Font.fmBalanceHero()` (rounded, mono-digit); inline values use `Font.fmAmount()` ([`./06-design-system.md §4.2`](./06-design-system.md)). Always formatted by `Money.formatted(locale:)` — locale-correct, never hand-assembled (V1, [`./06-design-system.md §11.2`](./06-design-system.md)).
- **Delta chip:** a capsule with `MoneyDirection`'s color **and** glyph (`arrow.up.right`/`arrow.down.right`/`minus`) **and** a leading sign on the percentage. For "burn" and "expenses", an increase is `fmFinancialDown` (bad) and a decrease is `fmFinancialUp` (good); for "income/savings/portfolio", increase is `fmFinancialUp`. The card declares its `goodDirection` so the semantics are correct (color-independence + correct valence).
- **Savings-rate** stat may render as a small linear gauge (C12) instead of a bare %.

**Color mapping.** Title/subtitle `fmLabelSecondary`; value `fmLabel`; delta per `MoneyDirection`; BTC values tint the currency symbol `fmBTC` ([`./06-design-system.md §3.2`](./06-design-system.md)).

**Interaction.** The whole card is a deep-link tap target ([`./02-product-spec.md §3.2`](./02-product-spec.md) "Tap →"). No internal selection. Reorderable on Home (C16).

**Animation.** Value uses a `.contentTransition(.numericText())` so a refreshed figure rolls digit-by-digit (0.25s). Reduce Motion → value swaps without the rolling transition.

**States.** Loading → `redacted(reason: .placeholder)` over the value + delta ([`./02-product-spec.md §3.5`](./02-product-spec.md)). Empty (no data) → the card still renders with teaching copy, e.g. "Net Cash Flow — add income to see this" ([`./02-product-spec.md §3.6`](./02-product-spec.md) edge case), not hidden. Error → cached value stays; a subtle "couldn't refresh" affordance.

**Accessibility.** One combined element: *"Monthly Burn, 3,150 euros, up 4.8 percent versus last month, 3,005 euros."* The delta direction is spoken ("up"/"down") so it is not color-only. Value is `.monospacedDigit()` and scales to AX5; at AX5 the delta chip wraps below the value (`ViewThatFits`).

#### Worked example (C11 — Net Cash Flow card)

[`§5.2`](./13-algorithms-and-calculations.md#52-monthly-trends-multi-series-last-6-months) June: income €4,500.00, expenses €3,150.00 → net `savings = €1,350.00`; `savingsRatio = 135000/450000 = 30%`. Prior month net €900.00 → delta `(1350−900)/900 = +50%`. Card: value "€1,350.00", delta chip `arrow.up.right` "+50%" in `fmFinancialUp` (goodDirection = up). Subtitle "vs €900.00 last month". Sparkline (C10) over the 6 monthly nets, rising, `fmFinancialUp`.

---

## 9. Usage gauges

**Where.** Subscription Analytics → Usage Statistics (usage-state composition as a radial gauge); Cash Flow Overview & Home (savings-rate as a linear gauge).

**Data / stat.** (a) **Usage composition** — fractions of `active`/`rarely`/`unused` ([`§5.3`](./13-algorithms-and-calculations.md#53-usage-statistics)). (b) **Savings-rate** — `savingsRatio` 0–100%, **0 when income = 0** ([`§5.2`](./13-algorithms-and-calculations.md#52-monthly-trends-multi-series-last-6-months)). Optionally **investment-rate** (`investmentRatio`) as a second linear gauge.

### 9.1 Usage composition (radial segmented gauge)

A ring (not a donut — it is a *gauge* reading composition at a glance) built with the same `SectorMark` machinery but full-ring with three fixed-semantics segments:

- Segments: `active` → `fmFinancialNeutral`, `rarely` → `fmFinancialWarning`, `unused` → `fmFinancialDown` (matches C6 and the list-row accents).
- Center label: the count needing review (`rarely + unused`) — e.g. "3 to review" — deep-linking to the Review queue.
- **Color-independence:** a compact legend with the three states' canonical glyphs (`checkmark`/`exclamationmark.triangle.fill`/`xmark`) and counts sits beside the ring.

### 9.2 Savings-rate (linear progress gauge)

A horizontal capsule track (`Radius.capsule`) with a filled portion = `savingsRatio`:

```swift
public struct UsageGauge: View {    // also used for savings-rate
    let fraction: Double            // 0...1, clamped; 0 when income == 0 (never NaN)
    let tint: Color                 // fmFinancialUp for savings-rate
    let label: String               // "Savings rate"
    let valueText: String           // "30%" — formatted, not raw
    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack { Text(label).font(.caption).foregroundStyle(.secondary)
                     Spacer(); Text(valueText).font(.fmAmount().weight(.semibold)) }
            Capsule().fill(Color.fmHairline)
                .frame(height: 8)
                .overlay(alignment: .leading) {
                    Capsule().fill(tint)
                        .frame(width: max(0, min(1, fraction)) * trackWidth, height: 8)
                }
        }
        .accessibilityElement()
        .accessibilityLabel("\(label), \(valueText)")
    }
}
```

- Fill color = `fmFinancialUp` (savings) / Blue 3 (investment). Track = `fmHairline`. A small notch marks a benchmark (e.g. 20%) for context, with a caption — color-independent.

**Interaction.** None (read-only). Tap deep-links to Cash Flow.

**Animation.** Fill animates from 0 to `fraction` on appear (0.4s). Reduce Motion → static fill.

**States.** Income = 0 → fraction 0, value "0%", caption "Add income to see your savings rate" (never NaN, [`§5.2`](./13-algorithms-and-calculations.md#52-monthly-trends-multi-series-last-6-months)). Loading → track skeleton.

**Accessibility.** `.accessibilityValue` reads the percent; the radial gauge exposes the three counts. Spoken: *"Savings rate, 30 percent."* / *"Usage: 7 active, 2 rarely, 1 unused, 3 to review."* Glyph-paired legend covers color-blindness. Dynamic Type scales the labels; the ring's center count uses `.title3`.

---

## 10. Price-history timeline

**Where.** Subscription Detail → Price History ([`./02-product-spec.md §4.5, §4.3`](./02-product-spec.md) screen 5). An inline preview on Detail; full chart + list on the Price History screen.

**Data / stat.** `subscription_price_history` rows (effective date, `amount_minor`, currency, `is_correction`) in the subscription's **native currency** (price history is a per-subscription audit, shown in that subscription's currency, not display currency — a price change *is* the data point). The series is the **step function** of price over time used as the input to Lifetime Cost ([`§4`](./13-algorithms-and-calculations.md#4-lifetime-cost-price-history-walk)); this chart visualizes the raw steps, it does not compute lifetime cost.

**Chart type & marks.** A **step line** (`LineMark` with `.interpolationMethod(.stepEnd)`) so a price holds until the next change, plus a `PointMark` at each effective date.

```swift
Chart(history) { h in
    LineMark(x: .value("Effective", h.effectiveFrom),
             y: .value("Price", h.amount.chartValue))
        .interpolationMethod(.stepEnd)
        .foregroundStyle(Color.fmAccent)
        .lineStyle(.init(lineWidth: 2))
    PointMark(x: .value("Effective", h.effectiveFrom),
              y: .value("Price", h.amount.chartValue))
        .foregroundStyle(h.isCorrection ? Color.fmFinancialWarning : Color.fmAccent)
        .symbol(h.isCorrection ? .triangle : .circle)   // correction = distinct shape (V3)
}
.modifier(FMChartStyle())
```

- **Corrections** (`is_correction = true`) render with `fmFinancialWarning` + a **triangle** symbol and a "Correction" tag in the synchronized list; normal price changes use `fmAccent` + circle. Shape + tag = color-independent.
- BTC-priced subscriptions: line tinted `fmBTC`, y axis in sats.

**Axes / scale.** X = time (date axis, `.caption`, month/year ticks). Y = native-currency price, 0-based, domain padded 10%. A single step series; no legend needed beyond the correction marker explained in a footnote caption.

**Interaction.** Tap a point → callout: effective date, price (`Money.formatted`), and "Price change" vs "Correction". Tapping a list row scrolls/selects the matching point. `Haptics.selection()`.

**Animation.** Step line draws left-to-right on appear (0.35s). Reduce Motion → instant.

**States.** A brand-new subscription has exactly one history row (the initial insert, written by the trigger) → the chart shows a single point with a caption "No price changes yet". Empty (impossible in practice since the trigger always seeds one) → the inline preview hides and the section shows "Price history will appear after the first change". Loading → redacted.

**Accessibility.** `AXChartDescriptor`: time axis + numeric price axis; each point `.accessibilityValue("12 euros 99 cents, price change, March 2026")` (corrections say "correction"). Summary *"Price history: started at 9.99 euros in Jan 2025, increased to 12.99 in Mar 2026; one correction."* The synchronized text list ([`./02-product-spec.md §4.3`](./02-product-spec.md) screen 5) is itself a fully navigable VoiceOver fallback.

---

## 11. The custom money-flow (Sankey) renderer

`MoneyFlowDiagram` (in `DesignSystem/Sources/DesignSystem/Charts/MoneyFlowDiagram.swift`) is a **custom `Canvas`/`Path` renderer** — Swift Charts has no Sankey mark ([`./06-design-system.md §8.2`](./06-design-system.md), [`./03-architecture.md`](./03-architecture.md), ADR-0011/ADR-0016 in [`./12-decisions-adr.md`](./12-decisions-adr.md)). It is the centerpiece of the Cost-Tracker Money-Flow screen ([`./02-product-spec.md §6`](./02-product-spec.md)).

### 11.1 Where it appears & what it shows

- **Where.** Money-Flow (Sankey) view, reachable from the Cash Flow tab ([`./02-product-spec.md §1.1` route `C5`, `§6`](./02-product-spec.md)).
- **Stat.** The **bucketed money-flow** from [`§6.5 Money-flow bucket values`](./13-algorithms-and-calculations.md#65-money-flow-bucket-values): a single `Income` node flowing into the four buckets `Fixed Expenses`, `Variable Expenses`, `Subscriptions`, `Savings`, all normalized into the selected timeframe (Monthly/Quarterly/Yearly, [§2.4](#24-timeframe--window-controls)) and converted to display currency ([`§2 Currency conversion`](./13-algorithms-and-calculations.md#2-currency-conversion)). `Savings = max(0, totalIncome − totalExpenses)`, `totalExpenses = fixed + variable + subscriptions`. Tap-to-expand drills a bucket into its per-category sub-flows.

### 11.2 The data model handed to the renderer

The Store builds an immutable `FlowGraph` (pure, from [`§6.5`](./13-algorithms-and-calculations.md#65-money-flow-bucket-values)); the renderer never computes money.

```swift
public struct FlowNode: Identifiable, Sendable {
    public let id: FlowNodeID            // .income | .bucket(Bucket) | .category(Bucket, categoryId)
    public let title: String             // "Income", "Fixed Expenses", "Housing", …
    public let amount: Money             // display currency, already normalized to timeframe
    public let layer: Int                // 0 = Income, 1 = bucket, 2 = category
    public let tint: Color               // token (see §11.6)
    public let isExpandable: Bool        // true for non-empty expense buckets; false for Savings & leaves
}
public struct FlowLink: Identifiable, Sendable {
    public let id: String
    public let source: FlowNodeID
    public let target: FlowNodeID
    public let amount: Money             // == target node amount (link width source)
}
public struct FlowGraph: Sendable {
    public let nodes: [FlowNode]
    public let links: [FlowLink]
    public let totalIncome: Money
    public var expandedBucket: Bucket?   // at most one expanded at a time on iPhone
}
```

**Invariants (from [`§6.5`](./13-algorithms-and-calculations.md#65-money-flow-bucket-values)):**
- Exactly one `.income` node. Its `amount == totalIncome`.
- A bucket node exists **iff its amount > 0** — **empty buckets are omitted** (no zero-width link, no orphan node). `Savings` node exists iff `Savings > 0`.
- `sum(bucket link widths) == totalIncome` within rounding (links are non-negative; over-budget is handled by `Savings = 0`, never a negative width).
- When `expandedBucket == b`, layer-2 category nodes for `b` exist and `sum(category link widths) == b.amount`; the other buckets stay collapsed (single-expand on iPhone, a presentation choice per [`./02-product-spec.md §6.2`](./02-product-spec.md)).

### 11.3 Deterministic layout transform

The layout is a **pure function** `layout(graph, size) -> [NodeRect] + [LinkRibbon]` so it is unit-testable and snapshot-stable. No physics, no randomness, no D3 iterative relaxation (unlike Substimate's `d3-sankey`); a fixed three-column packing keeps it deterministic and cheap.

**Constants** (all from `Spacing`/`Radius` tokens where applicable):

```
nodeWidth      = 12pt            // column rect width
columnGapMin   = 64pt            // min horizontal gap between columns (for link curvature + labels)
nodePadding    = Spacing.sm (8)  // vertical gap between stacked nodes in a column
topInset       = Spacing.lg (16)
bottomInset    = Spacing.lg (16)
sideInset      = Spacing.lg (16)
minNodeHeight  = 6pt             // floor so a tiny bucket is still tappable (hit area padded to 44pt)
```

#### Pseudocode — `layoutFlow`

```
function layoutFlow(graph, size):
    plot.x0 = sideInset
    plot.x1 = size.width  - sideInset
    plot.y0 = topInset
    plot.y1 = size.height - bottomInset
    plotH   = plot.y1 - plot.y0

    # 1) Determine active columns.
    columns = [0, 1]                       # always Income + buckets
    if graph.expandedBucket != nil: columns.append(2)   # category column appears on expand
    colCount = columns.count

    # 2) Assign X per layer: evenly spaced column centers, left→right.
    #    Income pinned left, last column pinned right, middle distributed.
    for k in 0..<colCount:
        if colCount == 1: xCenter[k] = plot.x0 + nodeWidth/2
        else: xCenter[k] = plot.x0 + nodeWidth/2
                         + (plot.x1 - plot.x0 - nodeWidth) * Double(k)/Double(colCount-1)
        # enforce columnGapMin; if violated, widen size or clip labels (labels reflow, never overlap)

    # 3) Vertical value->pixel scale, PER COLUMN, value-proportional with packing.
    #    Each column's nodes share the plot height minus inter-node padding.
    for each column c with nodes N_c (ordered: see §11.4 ordering):
        sumValue   = Σ node.amount.chartValue for node in N_c   # Double projection (V1)
        gaps       = (N_c.count - 1) * nodePadding
        usableH    = plotH - gaps
        scale_c    = (sumValue > 0) ? usableH / sumValue : 0
        cursorY    = plot.y0
        for node in N_c (in order):
            h = max(minNodeHeight, node.amount.chartValue * scale_c)
            node.rect = Rect(x: xCenter[col] - nodeWidth/2, y: cursorY,
                             width: nodeWidth, height: h)
            cursorY += h + nodePadding
        # If minNodeHeight inflation overflowed plot, re-distribute overflow proportionally
        # from the largest nodes (deterministic shrink pass), so the column always fits.

    # 4) Income node spans (visually) the full stack of its targets:
    #    place the single Income node centered on the weighted centroid of bucket targets,
    #    height = Σ outgoing link widths (== totalIncome scaled by column-1 scale) so the
    #    left node's height visually equals the sum of ribbons leaving it.
    income.rect.height = Σ link.width for links from income
    income.rect.y      = centroidY(targets) - income.rect.height/2  (clamped into plot)

    # 5) Link ribbons. A link from S to T has width = T.amount * scale(of T's column),
    #    anchored on a running offset within S's right edge and T's left edge so sibling
    #    ribbons stack without overlap (the classic Sankey "thickness pinning").
    for each source node S (left→right):
        offsetOut = S.rect.y
        for link in outgoing(S) ordered like targets:
            w  = link.target.rect.height                      # ribbon thickness == target height
            y0 = offsetOut;        offsetOut += w               # source band
            y1 = link.target.rect.y                             # target band top (targets unstacked: 1 in per node)
            link.ribbon = makeRibbon(x0: S.rect.maxX, y0Top: y0, y0Bot: y0+w,
                                     x1: T.rect.minX, y1Top: y1, y1Bot: y1 + w)
    return (nodeRects, linkRibbons)
```

**`makeRibbon`** builds a filled `Path` between two vertical bands using two cubic Béziers (top edge and bottom edge) with horizontal control points at the **midpoint X** (`cx = (x0+x1)/2`), the standard Sankey S-curve:

```
Path:
  move to (x0, y0Top)
  curve to (x1, y1Top)  control1 (cx, y0Top)  control2 (cx, y1Top)
  line  to (x1, y1Bot)
  curve to (x0, y0Bot)  control1 (cx, y1Bot)  control2 (cx, y0Bot)
  close
```

This yields smooth, non-overlapping ribbons whose **thickness is exactly proportional to value** at both ends. Because each target node receives exactly one inbound link (Income→bucket, or bucket→category), target-side stacking is trivial (one band per node); source-side bands stack in target order.

### 11.4 Node ordering (deterministic)

- **Column 1 (buckets):** fixed canonical order top→bottom: `Fixed Expenses`, `Variable Expenses`, `Subscriptions`, `Savings` (omitting any with amount 0). Fixed order makes snapshots stable and the diagram learnable.
- **Column 2 (categories of the expanded bucket):** sorted **descending by amount** (largest at top), ties broken by category name ascending — deterministic.
- **Income (column 0):** the lone node; its vertical center is the value-weighted centroid of the bucket band so ribbons fan symmetrically.

### 11.5 Canvas drawing

Rendered in a single SwiftUI `Canvas` (vector, retina-crisp, cheap to redraw on expand/collapse), layered back-to-front:

1. **Link ribbons** (drawn first, under nodes). Each ribbon filled with a **linear gradient from source tint → target tint** along X (income green → bucket color → category color), at **~55% opacity** so overlaps read as depth. Under Reduce Transparency, ribbons render at full opacity with a 0.5pt `fmHairline` edge stroke for separation.
2. **Node rects** (`RoundedRectangle` `Radius.xs` continuous) filled with the node tint at full opacity, 0.5pt `fmHairline` stroke.
3. **Labels** drawn via `Canvas`'s `context.resolve(Text(...))`: node title (`.caption`, `fmLabel`) + amount (`Money.formatted`, `.caption2`, `fmLabelSecondary`, mono-digit) + for buckets the `% of income`. Income label on the left of its node; bucket/category labels to the **right** of their node, vertically centered, clipped/truncated with `…` if the column gap is tight (labels reflow, never overlap a ribbon). **All amounts formatted from `Money`** (V1), never the plotted `Double`.
4. **Selection highlight** (if a node/link is selected): a 2pt `fmAccent` stroke on the node and the connected ribbons brought to full opacity; everything else dims to 35% (`fmLabelTertiary` overlay).

Dynamic Type: label font scales with the named text styles; at AX5 the renderer drops the inline `% of income` from labels (kept in the tooltip and VoiceOver) to preserve room, and increases `columnGapMin` so larger text fits.

### 11.6 Color mapping (tokens only)

| Node | Tint token |
| --- | --- |
| `Income` | `fmFinancialUp` (income/positive family) |
| `Fixed Expenses` | palette **Red 6** (`ChartPalette.categorical[5]`) — matches C3 stack |
| `Variable Expenses` | palette **Orange 7** (`[6]`) |
| `Subscriptions` | palette **Violet 4** (`[3]`) |
| `Savings` | palette **Emerald 1** (`[0]`) — distinct from expense reds; savings reads "kept" |
| Category sub-nodes | the category's own design-token tint ([`./06-design-system.md §9.3`](./06-design-system.md)); expense categories that lack a custom tint fall back to their bucket's tint at varying lightness via opacity steps (deterministic by sort index) |

Ribbon gradient blends source→target tints. Over-budget caption (when `Savings = 0`) uses `fmFinancialWarning` text + `exclamationmark.triangle.fill` glyph. **No new colors** — every value is a §6 token.

### 11.7 Hit-testing (expand / collapse / select)

```
function hitTest(point):
    # Nodes first (on top), then ribbons.
    for node in nodes (front to back):
        if node.hitRect.contains(point):   # hitRect = node.rect expanded to ≥ 44×44pt
            if node.isExpandable:
                toggleExpand(node.bucket)  # collapse any other expanded bucket first
            else:
                select(node)               # Savings/leaf/Income → show tooltip only
            return
    for link in links (front to back):
        if link.ribbon.contains(point):    # SwiftUI Path.contains for fill hit-testing
            select(link)                    # tooltip: amount, % of income
            return
    clearSelection()
```

- **Tap an expense bucket** → `toggleExpand`: collapse the currently expanded bucket (if any), expand the tapped one, recompute `FlowGraph` (layer-2 nodes) and re-layout. `Haptics.impact(.light)`.
- **Tap `Savings`/`Income`/a leaf category** → select-only: a glass `FlowTooltip` (the `FlowTooltip` equivalent, `GlassRole.card`) shows amount, **% of income**, and for a collapsed bucket its **top categories** ([`./02-product-spec.md §6.2`](./02-product-spec.md)).
- **Tap empty canvas** → clear selection/tooltip.
- Hit areas are padded so even a `minNodeHeight` 6pt node and thin ribbons reach the ≥ 44×44pt target ([`./06-design-system.md §10.4`](./06-design-system.md)).

### 11.8 Animation between states

- **Entrance (flow-in):** ribbons grow from 0 → full thickness and nodes fade/scale in over `Motion.glassMorph` (0.4s, [`./06-design-system.md §6.2`](./06-design-system.md)).
- **Expand/collapse:** the tapped bucket's single ribbon **splits** into N category ribbons; nodes animate to their new rects via an interpolated layout (lerp each `NodeRect`/ribbon control point between old and new layouts) over 0.4s, `Motion.glassMorph`. The category column slides in from the bucket's X.
- **Selection dim/highlight:** 0.2s cross-fade.
- **Reduce Motion (mandatory, [`./02-product-spec.md §6.2, §6.6`](./02-product-spec.md)):** **no flow-in, no split animation — expand/collapse is instant** (layout swaps in one frame). Selection highlight is an instant opacity change. This is an explicit acceptance criterion.

### 11.9 Empty / loading / error states

| State | Behavior |
| --- | --- |
| **Loading** | Canvas shows a shimmer placeholder (Reduce-Motion → static `fmLabelTertiary` shapes); supporting breakdowns redacted ([`./02-product-spec.md §6.5`](./02-product-spec.md)). |
| **Empty — no income & no expenses** | `FMEmptyState` "Add income and expenses to see your money flow" + Add CTA. |
| **Income but no expenses** | A single ribbon `Income → Savings` (all income is saved). |
| **Empty buckets** | Any bucket with total 0 is omitted entirely — no node, no zero-width link ([`§6.5`](./13-algorithms-and-calculations.md#65-money-flow-bucket-values), [`./02-product-spec.md §6.5`](./02-product-spec.md)). |
| **Over budget** (`totalExpenses > totalIncome`) | `Savings = 0` → no `Savings` node/link; an "Over budget by €X" caption renders in `fmFinancialWarning` + glyph. **No negative widths, no NaN** (acceptance [`./02-product-spec.md §6.6`](./02-product-spec.md)). |
| **Error** | Retry banner; last cached flow stays drawn. |

### 11.10 Accessibility — tabular VoiceOver fallback

A freeform flow drawing is not VoiceOver-navigable, so `MoneyFlowDiagram` provides an **`.accessibilityRepresentation`** that replaces the canvas with a structured, navigable list (per [`./06-design-system.md §8.2`](./06-design-system.md), [`./02-product-spec.md §6.2`](./02-product-spec.md)):

```swift
.accessibilityRepresentation {
    List {
        Section("Money flow — \(timeframe.label), \(displayCurrency.code)") {
            Text("Income \(graph.totalIncome.formatted())")
            ForEach(graph.bucketRows) { row in   // Fixed, Variable, Subscriptions, Savings (non-empty)
                Button {
                    if row.isExpandable { toggleExpand(row.bucket) }
                } label: {
                    Text("\(row.title) \(row.amount.formatted()), \(row.percentOfIncome) of income")
                }
                .accessibilityHint(row.isExpandable
                    ? (row.bucket == graph.expandedBucket ? "Collapses category breakdown"
                                                          : "Expands category breakdown")
                    : "")
                if row.bucket == graph.expandedBucket {
                    ForEach(row.categories) { c in
                        Text("\(c.title) \(c.amount.formatted()), \(c.percentOfBucket) of \(row.title)")
                    }
                }
            }
            if graph.isOverBudget {
                Text("Over budget by \(graph.overBudgetAmount.formatted())")
            }
        }
    }
}
```

- The list **mirrors the diagram state**: expanding a bucket (by tapping in the canvas *or* activating its accessibility button) reveals its category rows. This satisfies "VoiceOver conveys each bucket flow, its share of income, and (when expanded) its category breakdown" ([`./02-product-spec.md §6.6`](./02-product-spec.md)).
- Amounts are formatted by `Money` (locale-correct, V1). Percentages guard divide-by-zero ([`§6.5`](./13-algorithms-and-calculations.md#65-money-flow-bucket-values)).
- **Color-independence:** the list is text-only; in the canvas, every node also carries a **title + amount label**, so meaning never depends on the ribbon/node color alone.
- **Reduce Transparency:** ribbons and nodes opaque (see §11.5).

### 11.11 Worked example (C14)

**Inputs** (timeframe Monthly, display EUR, normalized + converted per [`§3`](./13-algorithms-and-calculations.md#3-subscription-cost-normalization)/[`§2`](./13-algorithms-and-calculations.md#2-currency-conversion)):

- Income: Salary €4,500.00 → `totalIncome = €4,500.00`.
- Fixed Expenses: Housing €1,500.00 + Utilities €350.00 = **€1,850.00**.
- Variable Expenses: Food €420.00 + Transport €160.00 = **€580.00**.
- Subscriptions: Streaming €32.00 + AI Chat €24.00 + Music €12.00 = **€68.00**.
- `totalExpenses = 1850 + 580 + 68 = €2,498.00`.
- `Savings = max(0, 4500 − 2498) = €2,002.00`.

**Collapsed graph.** Nodes: Income (4500), Fixed (1850), Variable (580), Subscriptions (68), Savings (2002) — all > 0, so all present. Links: Income→Fixed (1850), Income→Variable (580), Income→Subscriptions (68), Income→Savings (2002). Sum of link widths `1850+580+68+2002 = 4500 = totalIncome` ✓ (acceptance [`./02-product-spec.md §6.6`](./02-product-spec.md)).

**Layout (size 360×260, insets 16).** plotH `= 260 − 32 = 228`. Column 1 sum `= 4500` (chartValue 4500.0), gaps `= 3 × 8 = 24`, usableH `= 204`, scale `= 204 / 4500 = 0.04533 pt per €`. Heights: Fixed `1850 × 0.04533 = 83.9pt`, Variable `26.3pt`, Subscriptions `3.1pt → floored to minNodeHeight 6pt`, Savings `90.8pt`. (The 2.9pt inflation of Subscriptions is reclaimed proportionally from the two largest nodes in the deterministic shrink pass, so the column still fits 204pt.) Income node height = Σ ribbon widths = 204pt (the scaled total), centered on the bucket centroid.

**% of income labels:** Fixed `1850/4500 = 41.1%`, Variable `12.9%`, Subscriptions `1.5%`, Savings `44.5%`.

**Expand Subscriptions** (tap). New layer-2 nodes (sorted desc): Streaming €32.00, AI Chat €24.00, Music €12.00; ribbons Subscriptions→Streaming (32), →AI Chat (24), →Music (12), summing to 68 = bucket width ✓. Other buckets stay collapsed (single-expand). `% of Subscriptions`: Streaming `47.1%`, AI Chat `35.3%`, Music `17.6%`.

**VoiceOver (collapsed):** *"Money flow — Monthly, EUR. Income 4,500 euros. Fixed Expenses 1,850 euros, 41 percent of income. Variable Expenses 580 euros, 13 percent. Subscriptions 68 euros, 2 percent, double-tap to expand. Savings 2,002 euros, 45 percent."*

---

## 12. Dashboard card system & skeleton loaders

### 12.1 Card system

The Home dashboard is a reorderable vertical grid of `DashboardCard`s whose order/visibility is the single `dashboard_layouts.card_order` array ([`./05-data-model.md`](./05-data-model.md), [`./02-product-spec.md §3`](./02-product-spec.md)). Each card is a `GlassCard` ([`./06-design-system.md §7.2, §7.12`](./06-design-system.md)) carrying a typed `DashboardCardKind`. The card → visual mapping:

| `cardId` | Card kind | Primary visual | Secondary visual | Calc |
| --- | --- | --- | --- | --- |
| `monthly-burn` | `.monthlyOverview` | KPI stat (C11) | sparkline (C10) | [`§3`](./13-algorithms-and-calculations.md#3-subscription-cost-normalization) |
| `subscriptions-summary` | — | KPI stat (count + total + review count) | sparkline (C10) | [`§5.3`](./13-algorithms-and-calculations.md#53-usage-statistics) |
| `upcoming-charges` | `.upcomingCharges` | list of next 5 charges (rows, no chart) | — | [`§11.1`](./13-algorithms-and-calculations.md#111-subscription-charge-projection) |
| `net-cash-flow` | `.cashFlowMini` | KPI stat + savings-rate gauge (C12) | sparkline (C10) | [`§5.2`](./13-algorithms-and-calculations.md#52-monthly-trends-multi-series-last-6-months) |
| `category-spotlight` | `.categoryDistribution` | top-3 mini bar (C5) | — | [`§5.1`](./13-algorithms-and-calculations.md#51-category-distribution) |
| `assets-snapshot` | `.assetsSummary` | KPI stat (value + gain/loss) | sparkline (C10) | [`§7`](./13-algorithms-and-calculations.md#7-asset-valuation) |
| `review-queue` | — | list of up to 5 `rarely`/`unused` subs by cost | usage chip per row | [`§5.3`](./13-algorithms-and-calculations.md#53-usage-statistics) |

- **Layout.** Single-column vertical scroll on iPhone (cards full content-width, `Spacing.lg` insets, `Spacing.md` between cards). Each card has a stable min height so the scaffold renders instantly from cached layout ([`./02-product-spec.md §3.5`](./02-product-spec.md)).
- **Reorder (Customize mode).** Long-press lifts a card (`Haptics.impact(.light)`), `Motion.springGentle` reflow, drop persists the new `card_order` ([`./06-design-system.md §7.12`](./06-design-system.md)). A VoiceOver custom action "Move up"/"Move down" provides drag-free reordering (accessibility requirement). Hidden cards are simply absent from `card_order`.
- **Forward-compat.** A `cardId` in `card_order` unknown to the build is ignored silently ([`./02-product-spec.md §3.6`](./02-product-spec.md)).
- **Empty (new user).** A "Let's set up your finances" hero card with three quick actions (Add subscription · Add income · Import CSV); data-less cards show their own empty copy, never auto-hide ([`./02-product-spec.md §3.5, §3.6`](./02-product-spec.md)).

### 12.2 Skeleton loaders

`SkeletonView` ([`./06-design-system.md §7.11`](./06-design-system.md)) renders token-shaped placeholders for each card's geometry while the cache warms / first sync runs:

- **Per-card skeleton** matches the card's real layout: title bar (small rounded rect), a large value rect for the KPI, three short rows for list cards, an arc/donut placeholder for distribution cards, a flat line for sparklines.
- Built with `.redacted(reason: .placeholder)` over the real card view where possible (so geometry is exact), `SkeletonView` for bespoke shapes (charts/donuts).
- **Shimmer** animates with `Motion.fade`; **under Reduce Motion it is disabled** and falls back to a static `fmLabelTertiary` 12% fill ([`./06-design-system.md §7.11`](./06-design-system.md)).
- Because Finmate is offline-first, skeletons are **rare** — the local cache usually serves reads instantly; skeletons appear mainly on first launch / cold cache.
- **Reduce Transparency:** skeleton fills are opaque tokens (no translucency).
- **Accessibility:** while loading, the card exposes `.accessibilityLabel("Loading <card title>")` and is not focusable as data; once loaded it swaps to the real combined label.

---

## 13. Calendar dot visualization

**Where.** Calendar tab month grid ([`./02-product-spec.md §7`](./02-product-spec.md)); the `MonthGridCalendar` component ([`./06-design-system.md §7.8`](./06-design-system.md)).

**Data / stat.** Per day, projected subscription **charge events** (from [`§11.1 Subscription charge projection`](./13-algorithms-and-calculations.md#111-subscription-charge-projection): monthly/yearly/quarterly/weekly, day-of-month clamping for 29–31) and income `nextPayment` markers. Each day shows up to **5 event dots** + a `+N` overflow ([`./02-product-spec.md §7.2`](./02-product-spec.md)).

**Type & rendering.** Not a Swift Chart — a `LazyVGrid` of 7 columns of day cells; each cell renders an `HStack`/wrapped row of small `Circle` dots (4–5pt) beneath the day number. This is a bespoke dot glyph grid, drawn with SwiftUI shapes (no `Canvas` needed at this scale).

**Color mapping (color-independent via dot count + legend + day-detail):**

| Marker | Token | Distinguisher |
| --- | --- | --- |
| Monthly/quarterly/weekly charge (upcoming) | `fmAccent` | dot |
| Yearly charge (upcoming) | palette **Violet 4** | dot (distinct hue; explained in legend) |
| Past charge | `fmFinancialNeutral` (muted) | dot |
| Income payday (`nextPayment`) | `fmFinancialUp` | a small `arrow.up` glyph-dot, not a plain circle, so income is shape-distinct from charges |
| Today | — | `fmAccent` ring around the day number |

A **legend** below the grid maps each dot color/shape to its meaning (color-independence). The `+N` overflow chip uses `fmLabelSecondary`.

**Interaction.** Tap a day with events → `Day detail sheet` listing each event (name, billing-period tag, amount in display currency, upcoming/past styling, [`./02-product-spec.md §7.2`](./02-product-spec.md)). Prev/next month chevrons. Selecting today scrolls into view. `Haptics.selection()` on month change.

**Animation.** Month transitions slide horizontally (`Motion.springStandard`); Reduce Motion → cross-fade. Dots fade in with the grid.

**States.** Loading → skeleton dots. Empty month → grid with no dots + caption "No charges this month" ([`./02-product-spec.md §7.4`](./02-product-spec.md)). Day-of-month 29–31 clamps to the last valid day (e.g. Jan-31 monthly → Feb-28/29).

**Accessibility.** Each day cell is a combined element: *"June 15, 3 charges: Netflix, Spotify, iCloud; payday: Salary."* Days with no events read just the date. The grid is navigable cell-by-cell; the day-detail sheet is the full breakdown. Dot meaning is conveyed by the spoken event list, never color alone. Dynamic Type scales day numbers; at AX5 the dot row caps at 3 dots + `+N` to keep cells legible.

---

## 14. Accessibility playbook (all visuals)

This consolidates the per-visual a11y rules into the testable checklist used in CI snapshot/UI tests ([`./09-engineering-practices.md`](./09-engineering-practices.md)).

### 14.1 VoiceOver chart descriptions (`AXChartDescriptor` / audio graph)

- Every Swift Charts view attaches `.accessibilityChartDescriptor(self)` returning an `AXChartDescriptor` built by `ChartAccessibility.descriptor(...)` in `DesignSystem`. It declares the X axis (categorical or date), Y axis (numeric, with `valueDescriptionProvider` formatting via `Money`), and one `AXDataSeriesDescriptor` per series.
- This enables VoiceOver's **Audio Graph** ("Describe Chart" → "Play Audio Graph"): tones rise/fall with values, letting a non-sighted user *hear* the trend.
- Every chart also exposes a **one-line text summary** (read before the data) so the gist is instant without playing the audio graph.
- The money-flow and the calendar (not Swift Charts) instead expose a navigable `.accessibilityRepresentation` list ([§11.10](#1110-accessibility--tabular-voiceover-fallback), [§13](#13-calendar-dot-visualization)).

### 14.2 Reduce Motion

- All entrance, scrub, sweep, draw-on, digit-roll, flow-in, and split animations route through `fmAnimation` / `Motion` so they **cross-fade or appear instantly** under Reduce Motion ([`./06-design-system.md §6.2`](./06-design-system.md)).
- The money-flow expand/collapse is **instant** under Reduce Motion (hard acceptance, [`./02-product-spec.md §6.6`](./02-product-spec.md)). Skeleton shimmer is disabled. Symbol bounces on save are disabled.

### 14.3 Reduce Transparency

- Glass tooltips/callouts (`FMChartCallout`, `FlowTooltip`) collapse to opaque `fmSurface` (Tier C, `glassBackground`).
- Money-flow ribbons render full-opacity with hairline edges; nodes opaque.
- Skeleton fills are opaque tokens.

### 14.4 Color-independence (per visual)

| Visual | Non-color encoding |
| --- | --- |
| Line/area (C1, C2) | distinct line **symbols** (circle/square/diamond) + legend swatches; BTC dashed |
| Stacked bar (C3) | ordered legend + overlay dash/point shapes + value annotations |
| Bars (C4–C6) | end-of-bar value/percent labels + method/category **icons** + legend |
| Donuts (C7–C9) | mandatory **legend** (icon + name + amount + %) + inline % on big slices |
| Sparkline (C10) | always paired with the card's signed/glyph delta chip |
| KPI/delta (C11) | sign (`+`/`−`) + `MoneyDirection` glyph + spoken "up/down" |
| Gauge (C12) | percent text + glyph-paired legend + benchmark notch caption |
| Price history (C13) | correction = **triangle** shape + "Correction" tag |
| Money-flow (C14) | node title + amount labels; tabular VoiceOver list |
| Calendar dots (C15) | income = arrow-glyph dot; legend; dot count; day-detail list |
| Lifetime cost (C17) | rank order + end-of-bar value labels + category **icons** + months/monthly caption |

### 14.5 Dynamic Type

- All axis labels, legends, tooltips, KPI values, and node labels use **named text styles** (`.caption`, `.caption2`, `Font.fmAmount`, `Font.fmBalanceHero`) — no fixed unscaled sizes ([`./06-design-system.md §4`](./06-design-system.md)).
- At **AX5**: tick density halves on line/bar charts; donut inline % drops to legend-only; KPI delta chips wrap below the value; money-flow drops inline `% of income` (kept in tooltip/VoiceOver) and widens `columnGapMin`; calendar caps dots at 3 + `+N`.
- Verified XS→AX5 with no clipping (Definition of Done, [§16](#16-definition-of-done-for-a-visual)).

---

## 15. System & architecture diagrams inventory

Beyond data visualizations, the Finmate docs contain **structural diagrams** (Mermaid + ASCII). This inventory is the canonical map of which diagram lives where, so they stay consistent and discoverable. (These are documentation diagrams, not in-app graphics; they are rendered by GitHub's Mermaid support / as fenced ASCII.)

| Diagram | Kind | Lives in | Subject |
| --- | --- | --- | --- |
| Module / package graph | ASCII | [`../CLAUDE.md §5`](../CLAUDE.md) | App → Features → Core packages dependency arrows (acyclic) |
| Navigation IA tree | Mermaid `graph TD` | [`./02-product-spec.md §1.1`](./02-product-spec.md) | TabView → per-tab NavigationStack → screens/sheets |
| Money-flow topology (buckets) | ASCII (this doc) | [§11.2–§11.4](#112-the-data-model-handed-to-the-renderer) | Income → 4 buckets → categories; layout columns |
| Sankey layout transform | Pseudocode (this doc) | [§11.3](#113-deterministic-layout-transform) | `layoutFlow` deterministic packing |
| KPI stat-card anatomy | ASCII (this doc) | [§8](#8-kpi--stat-cards) | Card slot layout |
| Glass tier ladder | table/diagram | [`./06-design-system.md §2.1`](./06-design-system.md) | Tier A/B/C capability tiers |
| Sync engine (LWW / delta-poll / tombstones) | Mermaid sequence/flow | [`./03-architecture.md` (sync §)](./03-architecture.md) | optimistic write → enqueue → delta-poll cursor → per-field LWW |
| Repository / data-flow | Mermaid/ASCII | [`./03-architecture.md`](./03-architecture.md) | Store → repository protocol → DataLayer (local SwiftData + Supabase) |
| Currency conversion matrix | table | [`./04-tech-stack.md` "Currency & conversion"](./04-tech-stack.md) | EUR/USD/BTC triangulation 3×3 |
| ER / schema relationships | (DDL + prose) | [`./05-data-model.md`](./05-data-model.md) | tables, FKs to `auth.users`, RLS |
| Roadmap milestone timeline | table/Gantt-ish | [`./08-roadmap-and-milestones.md`](./08-roadmap-and-milestones.md) | M0..Mn build order |
| Edge Function request flow | Mermaid sequence | [`./07-security-and-privacy.md`](./07-security-and-privacy.md) | client → market-data / delete-account Edge Function (keys server-side) |

**Rule.** A new structural diagram is added to **one** home doc and registered in this table; data-visualization specs always live **here** (docs/14). Keep diagrams in sync with code/schema — a stale diagram is a bug ([`../CLAUDE.md §9`](../CLAUDE.md)).

---

## 16. Definition of Done for a visual

A chart/gauge/stat-surface/diagram-component is "done" only when every box is checked (mirrors and extends the component DoD in [`./06-design-system.md §14`](./06-design-system.md)):

- [ ] Plots a **`Double` projection of `Money`** for geometry only; **all** displayed numbers/labels/tooltips/legends/VoiceOver come from `Money.formatted(...)` (V1).
- [ ] Uses **only** `ChartPalette` / financial / BTC **tokens** — no literal hex (V2).
- [ ] **Color is not the only encoding** — also a label/legend-swatch/shape/dash/icon/sign (V3, [§14.4](#144-color-independence-per-visual)).
- [ ] Exposes an `AXChartDescriptor` (Swift Charts) **or** a navigable `.accessibilityRepresentation` (Canvas/grid), **plus** a one-line text summary (V4).
- [ ] **Reduce Motion** disables all animation (instant/cross-fade); **Reduce Transparency** makes glass surfaces opaque (V5).
- [ ] Verified at Dynamic Type **XS → AX5** without clipping; reflows per [§14.5](#145-dynamic-type).
- [ ] Interactive targets (selectable nodes/bars/slices) reach **≥ 44×44pt** hit areas.
- [ ] Implements the **four states** — loading (skeleton), empty (`FMEmptyState`, never blank/NaN), error (cached + retry), ready (§2.5).
- [ ] Guards **divide-by-zero / NaN / ∞** at the data boundary (ratios are 0 when the denominator is 0, per [`./13-algorithms-and-calculations.md`](./13-algorithms-and-calculations.md)).
- [ ] Ships `#Preview`s (light / dark / Reduce Transparency / AX5 / empty / loading) and a **snapshot test** (`swift-snapshot-testing`); the money-flow adds a **deterministic-layout unit test** asserting `layoutFlow` rects/ribbons for the [§11.11](#1111-worked-example-c14) vectors.

---

## 17. Related documents

- [`../CLAUDE.md`](../CLAUDE.md) — Single source of truth; module boundaries; golden rules (money as `Int64` minor units).
- [`./00-index.md`](./00-index.md) — Documentation index & reading order.
- [`./02-product-spec.md`](./02-product-spec.md) — Screens & flows these visuals live on (dashboard, analytics, cost-tracker money-flow, calendar, price history).
- [`./03-architecture.md`](./03-architecture.md) — Where `DesignSystem`/charts sit; the custom Sankey renderer as an engineering item; sync engine diagram.
- [`./04-tech-stack.md`](./04-tech-stack.md) — Swift Charts; currency conversion (triangulation, HALF-UP rounding, `satsPerBTC`, 24h staleness).
- [`./05-data-model.md`](./05-data-model.md) — `Money`, `Category` tint mapping, `dashboard_layouts.card_order`, price-history schema, asset average-cost semantics.
- [`./06-design-system.md`](./06-design-system.md) — Tokens, chart palette, `FMChartStyle`, `MoneyFlowDiagram`, materials/glass tiers, accessibility primitives.
- [`./07-security-and-privacy.md`](./07-security-and-privacy.md) — Market-data Edge Function (price feeding the BTC/asset visuals server-side).
- [`./09-engineering-practices.md`](./09-engineering-practices.md) — Snapshot/accessibility gates; unit tests for the deterministic Sankey layout.
- [`./12-decisions-adr.md`](./12-decisions-adr.md) — ADR-0011 (in-house Sankey renderer), ADR-0016 (bucketed money-flow redesign vs Substimate).
- [`./13-algorithms-and-calculations.md`](./13-algorithms-and-calculations.md) — The calc source for every series/stat referenced here ([`§3`](./13-algorithms-and-calculations.md#3-subscription-cost-normalization) normalization, [`§5.2`](./13-algorithms-and-calculations.md#52-monthly-trends-multi-series-last-6-months) trends, [`§5.1`](./13-algorithms-and-calculations.md#51-category-distribution) category distribution, [`§4`](./13-algorithms-and-calculations.md#4-lifetime-cost-price-history-walk) lifetime cost, [`§5.3`](./13-algorithms-and-calculations.md#53-usage-statistics) usage stats, [`§5.4`](./13-algorithms-and-calculations.md#54-payment-method-breakdown) payment-method breakdown, [`§7`](./13-algorithms-and-calculations.md#7-asset-valuation) asset valuation / gain-loss, [`§2`](./13-algorithms-and-calculations.md#2-currency-conversion) conversion, [`§6.5`](./13-algorithms-and-calculations.md#65-money-flow-bucket-values) money-flow bucket values, [`§11`](./13-algorithms-and-calculations.md#11-payday-calendar--recurrence) payday/charge projection).
