# Algorithms & Calculations — End-to-End Specification

> The **normative, end-to-end** specification of **every** algorithm, calculation, conversion, parsing routine, and statistic in Finmate. For each one this document states its **purpose**, **inputs/outputs with types** (money always as `Int64` minor units), the **exact formula / pseudocode and/or Swift signature**, **rounding & precision rules**, **edge cases & error handling**, **complexity**, and **2–3 worked numeric test vectors** suitable as unit tests.
>
> This is a *computation* contract. It does **not** redefine the database schema (see [`./05-data-model.md`](./05-data-model.md)), the currency-conversion *storage* contract (see [`./04-tech-stack.md`](./04-tech-stack.md) §6.2 "Currency & conversion"), the sync engine *prose* ([`./03-architecture.md`](./03-architecture.md) §5), or the chart visuals ([`./14-visualizations-and-charts.md`](./14-visualizations-and-charts.md)). Where a behavior is normative elsewhere, this doc restates the **math** and cross-links. If a formula here disagrees with [`./05-data-model.md`](./05-data-model.md), the data model wins; if it disagrees with [`./04-tech-stack.md`](./04-tech-stack.md) on conversion, tech-stack wins.

**Conventions used throughout**

- **Money is `Int64` minor units** + an ISO `CurrencyCode` (`EUR`/`USD`/`BTC`). Cents for EUR/USD (`exponent = 2`), satoshis for BTC (`exponent = 8`). `satsPerBTC = 100_000_000`. The `Money` value type and `CurrencyCode` are defined in [`./05-data-model.md`](./05-data-model.md) §2.2; this document uses them verbatim.
- **`Decimal` is the only intermediate numeric type** for division, percentages, conversion, and normalization. **No `Double`/`Float` ever touches money.** `Decimal` is base-10, 38-significant-digit, exact for the fractional values that appear in money math.
- **HALF-UP rounding** = `NSDecimalRound(&result, &value, scale, .plain)`. `.plain` is round-half-away-from-zero; because all monetary amounts are non-negative this is exactly "round half up". The single rounding rule across parse, format, conversion, and normalization, so boundary cases never disagree.
- **Base date** for every worked timestamp example is **2026-06-28** (today). "Now" in examples means `2026-06-28T00:00:00Z` unless a time is given.
- **Pure & total.** Every algorithm here is *pure* (output depends only on inputs + injected rate snapshot) and *total* (never traps/crashes on a production path — failures are typed thrown errors or clamped per the rules below). This is the golden rule from [`../CLAUDE.md`](../CLAUDE.md) §6 and [`./09-engineering-practices.md`](./09-engineering-practices.md) §3.
- **Complexity** is stated in terms of `n` = number of rows of the relevant entity; `m` = number of months in a window; `h` = number of price-history segments.

---

## 0. Index

| # | Algorithm / calculation | Section | Primary inputs | Output | Money? |
|---|---|---|---|---|---|
| 1 | Money arithmetic (add/subtract/negate/compare, overflow guards) | [§1](#1-money-arithmetic) | `Money`, `Money` | `Money`/`Bool` | yes |
| 1.6 | Money parse (HALF-UP, reject negative/over-precision) | [§1.6](#16-parsing--moneyparse_currency) | `String`, `CurrencyCode` | `Money` | yes |
| 1.7 | Money format (locale, sats grouping) | [§1.7](#17-formatting--moneyformatted) | `Money`, locale | `String` | yes |
| 2 | Currency conversion (EUR/USD/BTC triangulation) | [§2](#2-currency-conversion) | `Money`, `ExchangeRates`, target | `Money` | yes |
| 2.4 | BTC ↔ sats | [§2.4](#24-btc--satoshis) | `Decimal`/`Int64` | `Int64`/`Decimal` | yes |
| 2.5 | Staleness & missing-rate policy | [§2.5](#25-staleness--missing-rate-policy) | `ExchangeRates`, now | flag / `Money` | yes |
| 3 | Subscription cost normalization (period → monthly/annual) | [§3](#3-subscription-cost-normalization) | `Subscription` | `Int64` minor | yes |
| 3.4 | Effective spend by usage state | [§3.4](#34-effective-spend-by-usage-state) | `[Subscription]` | `Int64` minor | yes |
| 4 | Lifetime cost (price-history walk) | [§4](#4-lifetime-cost-price-history-walk) | `Subscription`, `[PriceSegment]` | `Int64` minor | yes |
| 5 | Analytics aggregations (category, trends, usage, payment method) | [§5](#5-analytics-aggregations) | entity collections | structs | yes |
| 6 | Cash-flow metrics (income/expense roll-ups, net, savings rate) | [§6](#6-cash-flow-metrics) | income + expenses + subs | `Int64` + `Decimal` | yes |
| 7 | Asset valuation (cost basis, gain/loss, portfolio, distribution) | [§7](#7-asset-valuation) | `[FinancialAsset]`, `[AssetTransaction]` | `Int64` + `Decimal` | yes |
| 8 | BTC calculator (fiat ↔ sats) | [§8](#8-btc-calculator) | `Decimal`, price | `Int64`/`Decimal` | yes |
| 9 | CSV import (locale number parse, mapping, validation, dedup, preview) | [§9](#9-csv-import) | CSV text | `[ParsedRow]` | yes |
| 10 | Prediction & category inference | [§10](#10-prediction--category-inference) | name `String` | prefill / category | yes |
| 11 | Payday calendar & recurrence (next occurrence, windowing, reminders) | [§11](#11-payday-calendar--recurrence) | entity + date window | `[ChargeEvent]` | no |
| 12 | Sync reconciliation math (per-field LWW, delta cursor, tombstones) | [§12](#12-sync-reconciliation-math) | local + remote rows | merged row | no |
| 13 | Search / filter / sort ordering | [§13](#13-searchfiltersort-ordering) | collection + query | ordered subset | no |
| — | Test-vector index (→ [`./09`](./09-engineering-practices.md) §3.1) | [§14](#14-test-vector-index) | — | — | — |

---

## 1. Money arithmetic

> **Purpose.** Provide exact, overflow-safe integer arithmetic and comparison over `Money`, plus exact parse/format, so no money operation can silently drift, overflow, or mix currencies. This is the foundation every other section stands on. Definitions are canonical in [`./05-data-model.md`](./05-data-model.md) §2.2; this section is the *behavioral / test-vector* statement.

All arithmetic operates on the single stored `minorUnits: Int64` field. Cross-currency operations **throw** (`MoneyError.currencyMismatch`) — they never auto-convert (conversion is [§2](#2-currency-conversion), and is display-only). All overflow is **guarded** with `Int64.addingReportingOverflow` / `subtractingReportingOverflow` / `multipliedReportingOverflow` and throws `MoneyError.overflow`.

```
MoneyError = currencyMismatch(CurrencyCode, CurrencyCode)
           | negativeAmount
           | tooManyFractionalDigits(allowed: Int)
           | invalidNumber
           | overflow
```

### 1.1 Add

```swift
func adding(_ other: Money) throws(MoneyError) -> Money
```

| Aspect | Rule |
|---|---|
| Purpose | Same-currency sum. |
| Inputs | `self: Money`, `other: Money` |
| Output | `Money` (same currency) |
| Formula | guard `self.currency == other.currency` else throw `.currencyMismatch`; `(sum, ovf) = a.addingReportingOverflow(b)`; guard `!ovf` else throw `.overflow`; return `Money(sum, currency)`. |
| Precision | exact integer; no rounding. |
| Edge cases | mismatch → throw; overflow → throw; `0 + x = x`. |
| Complexity | O(1). |

**Test vectors**

| # | a | b | result |
|---|---|---|---|
| T1.1a | `1299 EUR` | `100 EUR` | `1399 EUR` (`adding_sameCurrency_sums`) |
| T1.1b | `1000 EUR` | `1 USD` | throws `.currencyMismatch(.eur, .usd)` (`adding_mismatch_throws`) |
| T1.1c | `Int64.max EUR` | `1 EUR` | throws `.overflow` (`adding_guardsOverflow`) |

### 1.2 Subtract

```swift
func subtracting(_ other: Money) throws(MoneyError) -> Money
```

Same-currency difference using `subtractingReportingOverflow`. **Subtraction MAY yield a negative `minorUnits`** (a signed delta is a legitimate computed value — e.g. net cash flow, unrealized loss). The non-negativity invariant applies to **stored amount fields** ([`./05-data-model.md`](./05-data-model.md) §0), not to in-memory computed deltas. Callers that must persist a result re-validate before write.

| # | a | b | result |
|---|---|---|---|
| T1.2a | `1399 EUR` | `1299 EUR` | `100 EUR` |
| T1.2b | `1000 EUR` | `1500 EUR` | `-500 EUR` (signed delta; allowed) |
| T1.2c | `Int64.min EUR` | `1 EUR` | throws `.overflow` |

### 1.3 Negate

```swift
func negated() throws(MoneyError) -> Money   // throws on Int64.min
```

`-minorUnits`, guarding the single overflow case `Int64.min` (whose negation overflows). Used by cash-flow and gain/loss display.

| # | a | result |
|---|---|---|
| T1.3a | `250 EUR` | `-250 EUR` |
| T1.3b | `Int64.min EUR` | throws `.overflow` |

### 1.4 Scale by an integer count (for "× N periods")

```swift
func scaled(by factor: Int64) throws(MoneyError) -> Money
```

`(p, ovf) = minorUnits.multipliedReportingOverflow(by: factor)`; guard `!ovf`. Used for annualizing an exact monthly amount by 12, summing N identical charges, etc. **Fractional** scaling (e.g. weekly → monthly by 52/12) is **not** this method — it goes through the `Decimal` normalization path in [§3](#3-subscription-cost-normalization) because the factor is non-integer and needs HALF-UP rounding.

| # | a | factor | result |
|---|---|---|---|
| T1.4a | `1000 EUR` | `12` | `12000 EUR` |
| T1.4b | `4_611_686_018_427_388 EUR` | `3` | throws `.overflow` |

### 1.5 Compare & equality

```swift
func compare(_ other: Money) throws(MoneyError) -> ComparisonResult   // throws on mismatch
static func == (Money, Money) -> Bool   // Hashable: equal iff SAME currency AND minorUnits
```

`compare` requires same currency (else `.currencyMismatch`) and compares `minorUnits`. `==`/`Hashable` consider currency part of identity: `100 EUR != 100 USD` and they hash differently (so a `Set<Money>` keeps them distinct). Ordering across currencies is meaningless and is **never** done without converting first (§2).

| # | a | b | result |
|---|---|---|---|
| T1.5a | `1299 EUR` | `1300 EUR` | `.orderedAscending` |
| T1.5b | `100 EUR` | `100 USD` | `==` is `false`; `compare` throws `.currencyMismatch` |
| T1.5c | `0 BTC` | `0 BTC` | `.orderedSame`, `==` true |

### 1.6 Parsing — `Money.parse(_:currency:)`

> **Purpose.** Turn already-locale-normalized user input (a `.`-decimal string, e.g. `"12.99"`, `"0.00050000"`) into exact minor units. This is an **amount parser** (subscription cost, expense, income, asset price): it **rejects** negatives, **rejects** over-precision, **rejects** non-numbers, and **guards** overflow. Locale grouping/decimal handling (commas, `1.234,56`) is the caller's job (CSV in [§9.1](#91-locale-aware-number-parsing); free-form fields use the field's locale) — this parser receives a canonical string. Canonical signature in [`./05-data-model.md`](./05-data-model.md) §2.2.

```
parse(text, currency):
  t      = trim(text)
  value  = Decimal(string: t)               ; require finite        else .invalidNumber
  require value >= 0                                                 else .negativeAmount
  fracDigits = max(0, -value.exponent)        ; digits after the point
  require fracDigits <= currency.exponent                            else .tooManyFractionalDigits(currency.exponent)
  scaled = value * 10^currency.exponent
  rounded = HALF_UP(scaled, scale = 0)
  require rounded <= Decimal(Int64.max)                              else .overflow
  return Money(minorUnits: Int64(rounded), currency)
```

| Aspect | Rule |
|---|---|
| Rounding | HALF-UP at integer precision. Because over-precise input is **rejected**, rounding only fires where the scale multiply is exact; the HALF-UP path is exercised on the conversion route (§2), which mechanically introduces extra precision. |
| Over-precision | EUR/USD allow ≤ 2 fractional digits; BTC ≤ 8. `"12.999"` (EUR) and `"0.000000001"` (BTC) are **rejected**, so a typo can never be silently truncated. |
| Negatives | rejected — amount fields are `>= 0`. (Signed deltas come from arithmetic, never from parsing user amounts.) |
| Invalid | `"abc"`, `""`, `"1.2.3"`, `NaN`, `∞` → `.invalidNumber`. |
| Overflow | a value scaling beyond `Int64.max` → `.overflow` (NSDecimalNumber would otherwise clamp silently). |
| Complexity | O(len(text)). |

**Test vectors**

| # | input | currency | result | test name |
|---|---|---|---|---|
| T1.6a | `"12.99"` | EUR | `1299 EUR` | `parse_basicEUR` |
| T1.6b | `"4.00"` | USD | `400 USD` | `parse_basicUSD` |
| T1.6c | `"0.00050000"` | BTC | `50000 BTC` (50 000 sats) | `parse_btcSats` |
| T1.6d | `"12.999"` | EUR | throws `.tooManyFractionalDigits(allowed: 2)` | `parse_rejectsTooManyFractionalDigits` |
| T1.6e | `"0.000000001"` | BTC | throws `.tooManyFractionalDigits(allowed: 8)` | `parse_rejectsTooManyFractionalDigits` |
| T1.6f | `"-1.00"` | EUR | throws `.negativeAmount` | `parse_rejectsNegative` |
| T1.6g | `"abc"`, `""` | EUR | throws `.invalidNumber` | `parse_rejectsInvalid` |
| T1.6h | `"99999999999999999999"` | EUR | throws `.overflow` | `parse_guardsOverflow` |
| T1.6i | `"12.5"` | EUR | `1250 EUR` (trailing-zero-implied) | `parse_singleDecimal` |

### 1.7 Formatting — `Money.formatted(...)`

> **Purpose.** Render a `Money` for display in the user's locale, never losing or fabricating precision. Centralized in `Shared/Utilities`; consumed by every screen. See [`./02-product-spec.md`](./02-product-spec.md) §11.2 and [`./06-design-system.md`](./06-design-system.md) "Internationalization & formatting".

```
formatted(money, locale):
  major = Decimal(minorUnits) / 10^exponent          ; exact
  switch currency:
    EUR: NumberFormatter(.currency, "EUR", locale ?? de_DE), 2 fraction digits
    USD: NumberFormatter(.currency, "USD", locale ?? en_US), 2 fraction digits
    BTC: integer sats with grouping separators + " sats"   (e.g. 12,345,678 sats)
```

| Aspect | Rule |
|---|---|
| Output | `String`. |
| Precision | exactly `exponent` fraction digits for fiat; BTC renders whole sats (integer) with grouping. |
| Rounding | none needed — the value already *is* the exact minor-unit count; formatting only inserts separators. (A BTC "show as ₿" mode divides by `satsPerBTC` and shows 8 dp — still exact.) |
| Edge cases | negative computed deltas render with a leading minus (or accounting parens per design); `0` renders `€0.00` / `0 sats`; very large values keep grouping. Never NaN/∞ (input is integer). |
| Complexity | O(1). |

**Test vectors**

| # | money | locale | output | test name |
|---|---|---|---|---|
| T1.7a | `1299 EUR` | `de_DE` | `12,99 €` | `format_eurDE` |
| T1.7b | `400 USD` | `en_US` | `$4.00` | `format_usdUS` |
| T1.7c | `12_345_678 BTC` | any | `12,345,678 sats` | `format_btcSatsGrouping` |
| T1.7d | `-500 EUR` | `de_DE` | `-5,00 €` | `format_negativeDelta` |

---

## 2. Currency conversion

> **Purpose.** Convert a stored `Money` into a target display currency, **display-only, never mutating stored amounts** (the cardinal Substimate-bug fix, [`./05-data-model.md`](./05-data-model.md) §9 item 2). The conversion *contract* (rate schema, triangulation table, rounding, staleness/missing-rate policy, the `CurrencyConverter` protocol) is canonical in [`./04-tech-stack.md`](./04-tech-stack.md) §6.2. This section is the **algorithm + numeric test vectors**; if it disagrees with §6.2, §6.2 wins.

### 2.1 The rate snapshot

The only rate shape stored or transported is the canonical `exchange_rates` jsonb / `ExchangeRates` value:

```
ExchangeRates { eurUsd: Decimal,   // USD per 1 EUR
                btcEur: Decimal,   // EUR per 1 BTC
                btcUsd: Decimal,   // USD per 1 BTC
                fetchedAt: Date }  // ISO8601
```

All three pairs are required to build the full matrix; a missing/nil pair makes the conversions that need it *unavailable* (§2.5).

### 2.2 The triangulation matrix (factor `f(from→to)`)

Multiply the *major-unit* source value by `f`:

| from \ to | EUR | USD | BTC |
|---|---|---|---|
| **EUR** | `1` | `eurUsd` | `1 / btcEur` |
| **USD** | `1 / eurUsd` | `1` | `1 / btcUsd` |
| **BTC** | `btcEur` | `btcUsd` | `1` |

A hypothetical fourth fiat would route through USD; v1 needs only these nine. Identity (`from == to`) returns the input **unchanged** (no rounding, no rate lookup).

### 2.3 The conversion algorithm

```
convert(money, target, rates):
  if money.currency == target: return money            ; identity, byte-for-byte
  f = factor(money.currency -> target, rates)          ; from §2.2; throw .rateUnavailable if any needed rate is nil/<=0
  sourceMajor = Decimal(money.minorUnits) / 10^money.currency.exponent
  targetMajor = sourceMajor * f                        ; exact Decimal multiply/divide
  scaled      = targetMajor * 10^target.exponent
  minor       = HALF_UP(scaled, scale = 0)             ; round to target minor units
  guard 0 <= minor <= Int64.max  else clamp/throw      ; (input >= 0, so minor >= 0)
  return Money(minorUnits: Int64(minor), currency: target)
```

```swift
func convert(_ money: Money, to target: CurrencyCode) throws(ConversionError) -> Money
// ConversionError.rateUnavailable(from:to:)
```

| Aspect | Rule |
|---|---|
| Rounding | HALF-UP to the **target** currency's minor units (2 dp fiat → cents, 8 dp BTC → sats). Same rule as `Money.parse`, so a display conversion and a re-parse never disagree on a boundary. |
| Precision | all intermediates are `Decimal`; only the final scale-and-round produces the `Int64`. |
| Missing rate | any rate needed for the pair being nil/zero/negative → `.rateUnavailable(from:to:)`; the caller then shows the **stored source amount unconverted** (§2.5). |
| Staleness | conversion still proceeds when stale; the UI flags it (§2.5). Staleness does **not** change the number. |
| Identity | same-currency returns the exact input (no rounding artifact). |
| Complexity | O(1). |

**Worked test vectors** (rates: `eurUsd = 1.0825`, `btcEur = 58234.50`, `btcUsd = 63038.85`, `fetchedAt = 2026-06-28T09:14:32Z`)

| # | input | target | computation | result | test name |
|---|---|---|---|---|---|
| T2.3a | `1000 EUR` (€10.00) | USD | `10.00 × 1.0825 = 10.825 → $10.83` (HALF-UP) | `1083 USD` | `convert_eurToUsd_halfUp` |
| T2.3b | `1083 USD` ($10.83) | EUR | `10.83 / 1.0825 = 10.00461… → €10.00` | `1000 EUR` | `convert_usdToEur` |
| T2.3c | `1000 EUR` (€10.00) | BTC | `10.00 / 58234.50 = 0.0001717216… BTC → ×1e8 = 17172.16… → 17172 sats` | `17172 BTC` | `convert_eurToBtcSats` |
| T2.3d | `50000 BTC` (0.0005 BTC) | USD | `0.0005 × 63038.85 = 31.519425 → $31.52` | `3152 USD` | `convert_btcToUsd` |
| T2.3e | `2500 USD` | USD | identity | `2500 USD` (unchanged) | `convert_identity` |
| T2.3f | `1000 EUR`, `btcEur = nil` | BTC | needed rate missing | throws `.rateUnavailable(.eur, .btc)` | `convert_rateUnavailable` |

> **Rounding boundary vector** (`convert_halfUpBoundary`): convert `1 USD` (1 cent) to EUR at `eurUsd = 2.0` → `0.01 / 2.0 = 0.005 → HALF-UP → €0.01 = 1 EUR-cent` (half rounds **up**, not to even). This pins the half-up rule against banker's rounding.

### 2.4 BTC ↔ satoshis

> **Purpose.** Exact conversion between BTC major units and the satoshi minor unit, used by the calculator (§8), asset valuation (§7), and any BTC display.

```
satsFromBTC(btc: Decimal) -> Int64 :  HALF_UP(btc * 100_000_000, scale = 0)
btcFromSats(sats: Int64)  -> Decimal:  Decimal(sats) / 100_000_000      ; exact, 8 dp
```

`satsPerBTC = 100_000_000`. Sub-sat input rounds HALF-UP to the nearest whole sat (a sat is indivisible). `btcFromSats` is exact (a sat count divides cleanly into an 8-dp Decimal).

| # | input | output | test name |
|---|---|---|---|
| T2.4a | `0.00050000 BTC` | `50000` sats | `sats_fromBtc` |
| T2.4b | `1 BTC` | `100_000_000` sats | `sats_oneBtc` |
| T2.4c | `0.000000005 BTC` (half a sat) | `1` sat (HALF-UP) | `sats_subSatRoundsUp` |
| T2.4d | `123_456_789` sats | `1.23456789 BTC` | `btc_fromSats` |

### 2.5 Staleness & missing-rate policy

```
ratesAreStale(rates, now) :  now - rates.fetchedAt > 24h
```

| Condition | Behavior |
|---|---|
| `fetchedAt` older than **24h** | still convert; UI shows a non-blocking "rates may be stale" indicator on converted figures. The number is unchanged. |
| a needed rate nil / ≤ 0 (pair unavailable) | conversion **unavailable**: caller displays the **stored source amount, unconverted**, in its original currency. Never 0, never NaN, never a guess. |
| offline | use the last cached `exchange_rates` row; conversion never blocks on a network call. |

| # | `fetchedAt` | now | `ratesAreStale` | test name |
|---|---|---|---|---|
| T2.5a | `2026-06-28T00:00:00Z` | `2026-06-28T12:00:00Z` | `false` (12h < 24h) | `stale_within24h` |
| T2.5b | `2026-06-26T00:00:00Z` | `2026-06-28T00:00:01Z` | `true` (48h > 24h) | `stale_beyond24h` |
| T2.5c | `2026-06-27T00:00:00Z` | `2026-06-28T00:00:00Z` | `false` (exactly 24h, not `>`) | `stale_exactlyAtBoundary` |

---

## 3. Subscription cost normalization

> **Purpose.** Convert a subscription's stored **billing-period amount** (`amountMinor` in `currency`, for `billingPeriod ∈ {weekly, monthly, quarterly, yearly}`) into a **canonical monthly-equivalent** and a **canonical annual-equivalent** minor-unit amount, so heterogeneous billing periods can be summed and trended. This is computed on the fly — Finmate stores the native period amount and never does Substimate's lossy yearly→monthly round-trip ([`./02-product-spec.md`](./02-product-spec.md) §4.2). Pure logic in `Domain`/`Shared`, unit-tested.

### 3.1 Period factors

`monthlyEquivalentMinor = HALF_UP( Decimal(amountMinor) × periodToMonthlyFactor )`, where:

| billingPeriod | → monthly factor | → annual factor | Rationale |
|---|---|---|---|
| `weekly` | `52 / 12` (≈ 4.3333…) | `52` | 52 weeks per year; **precise**, not Substimate's `×4` approximation. |
| `monthly` | `1` | `12` | identity. |
| `quarterly` | `1 / 3` | `4` | a quarter is 3 months / 4 per year. |
| `yearly` | `1 / 12` | `1` | spread one annual charge over 12 months. |

Annual-equivalent may be computed directly via the annual factor, or as `monthlyEquivalentMinor × 12` — the two **can differ by ≤ 1 minor unit** due to independent rounding, so the canonical rule is: **compute monthly from the table (HALF-UP), and compute annual from the table (HALF-UP) independently.** Trends that need both use each directly; never derive one from the other to avoid compounding rounding.

```swift
func monthlyEquivalentMinor(_ s: Subscription) -> Int64       // HALF-UP of amountMinor × factor
func annualEquivalentMinor (_ s: Subscription) -> Int64       // HALF-UP of amountMinor × annualFactor
```

| Aspect | Rule |
|---|---|
| Rounding | HALF-UP to the subscription's own currency minor units (computation is currency-agnostic — it scales the integer minor count, currency unchanged). |
| Edge cases | `amountMinor = 0` → `0`. Overflow guarded (annualizing a huge weekly amount): `Decimal` intermediate then range-checked before `Int64`. |
| Ended subs | normalization is purely about the period factor; whether an ended sub *contributes* to a window is the caller's filter ([§5](#5-analytics-aggregations), [§11](#11-payday-calendar--recurrence)). |
| Complexity | O(1) per subscription. |

**Test vectors**

| # | amountMinor / currency | period | monthly-equiv | annual-equiv | test name |
|---|---|---|---|---|---|
| T3.1a | `12000 EUR` (€120 / yr) | yearly | `1000` (€10.00) | `12000` (€120.00) | `normalize_yearlyToMonthly` |
| T3.1b | `10000 USD` ($100 / wk) | weekly | `HALF_UP(10000 × 52/12) = HALF_UP(43333.33…) = 43333` ($433.33) | `520000` ($5,200) | `normalize_weekly_52over12` |
| T3.1c | `3000 EUR` (€30 / qtr) | quarterly | `HALF_UP(3000 / 3) = 1000` (€10.00) | `12000` (€120.00) | `normalize_quarterly` |
| T3.1d | `1549 EUR` (€15.49 / mo) | monthly | `1549` | `18588` (€185.88) | `normalize_monthlyIdentity` |
| T3.1e | `100 EUR` (€1 / wk) | weekly | `HALF_UP(100 × 52/12)=HALF_UP(433.33…)=433` (€4.33) | `5200` (€52.00) | `normalize_weeklyRounding` |

> T3.1e is the canonical "weekly is `52/12`, not `×4`" guard: `×4` would give €4.00; the correct monthly-equivalent is €4.33. This matches [`./02-product-spec.md`](./02-product-spec.md) §5.7 (weekly €100 income → €433.33/mo).

### 3.2 Quarterly: monthly-vs-annual consistency

Quarterly has two stated derivations (`/3` monthly, `×4` annual). Both are exact for the canonical examples but the rule above keeps them independent. Worked check: `3000 / 3 = 1000` monthly; `1000 × 12 = 12000` annual; `3000 × 4 = 12000` annual — consistent here. A non-divisible amount (`amountMinor = 1000`, quarterly) gives `HALF_UP(1000/3) = 333` monthly (vs `333×12 = 3996`) and `1000×4 = 4000` annual — a 4-minor-unit divergence that confirms why annual is taken directly, not via monthly.

### 3.3 Timeframe scaling (cost-tracker)

The cost-tracker timeframe selector (Monthly · Quarterly · Yearly, [`./02-product-spec.md`](./02-product-spec.md) §6.3) scales the **monthly-equivalent** by the window:

```
windowAmount(monthlyEquivMinor, timeframe) :
  Monthly   -> monthlyEquivMinor × 1
  Quarterly -> monthlyEquivMinor × 3
  Yearly    -> monthlyEquivMinor × 12
```

Integer scale (`scaled(by:)` from §1.4) — exact, no rounding. Expense-distribution windowing (§6.4a of the spec) uses Week ≈ `/4`, Month `×1`, Year `×12` for fixed expenses (HALF-UP for the `/4`).

| # | monthly-equiv | timeframe | window amount | test name |
|---|---|---|---|---|
| T3.3a | `1000 EUR` | Yearly | `12000 EUR` | `window_yearlyTimesTwelve` |
| T3.3b | `1549 EUR` | Quarterly | `4647 EUR` | `window_quarterly` |

### 3.4 Effective spend by usage state

> **Purpose.** Surface "wasted" recurring spend by partitioning monthly-equivalent totals by `usageState`. Feeds the Review queue and usage statistics ([`./02-product-spec.md`](./02-product-spec.md) §4.7).

```
effectiveSpend(subs, displayCurrency, rates):
  for each non-ended sub: m = convert(monthlyEquivalent(sub), displayCurrency, rates)   ; or unconverted if rate unavailable
  bucket m into sub.usageState
  return { active: Σ, rarely: Σ, unused: Σ, total: active+rarely+unused }
```

| Aspect | Rule |
|---|---|
| "Effective"/wasted | `rarely + unused` is the at-risk spend. `active` is the kept spend. |
| Conversion | per-sub convert to display currency (§2) then sum; if a rate is unavailable the sub is summed in its native currency into a per-currency residual the UI shows separately (never silently dropped). |
| Edge cases | empty list → all zeros (no divide). Ended subs (`endDate < today`) excluded from forward-looking effective spend. |
| Complexity | O(n). |

**Test vector** (`effectiveSpend_buckets`): subs (all EUR, display EUR) — `Netflix 1000 active`, `Audible 999 rarely`, `OldGym 2999 unused`, `Spotify 999 active` → `active = 1999`, `rarely = 999`, `unused = 2999`, `total = 5997`. At-risk = `3998` (66.7% of total).

---

## 4. Lifetime cost (price-history walk)

> **Purpose.** Compute the **total amount spent** on a subscription since its `startDate`, honoring every historical price by walking the `subscription_price_history` segments. Powers Lifetime Cost analytics ([`./02-product-spec.md`](./02-product-spec.md) §4.7.3). This is the Int64-minor-unit, correction-aware reimagining of Substimate's `useSubscriptionAnalytics.ts` lifetime walk.

### 4.1 Inputs / outputs

```
lifetimeCostMinor(sub, history, now) -> (totalMinor: Int64, monthsActive: Int)
```

- `sub`: `Subscription` (`startDate`, `endDate?`, `billingPeriod`, current `amountMinor`/`currency`).
- `history`: `[PriceSegment]` from `subscription_price_history`, each `{ amountMinor, currency, effectiveFrom, isCorrection }`, ascending by `effectiveFrom`. Always contains at least the insert row (the trigger writes one on insert, [`./05-data-model.md`](./05-data-model.md) §4.2).
- `now`: current instant (clamped to `endDate` if the sub has ended).
- Output is in the subscription's **native currency** (display conversion applied afterward, per-segment, by the analytics layer).

### 4.2 The walk (monthly & weekly/quarterly)

For non-yearly billing, iterate each **charge period** from `startDate` to `min(now, endDate)`, applying the price effective at that period and summing the **period charge** (the amount actually billed that period — for monthly that's the monthly amount; for quarterly the quarterly amount once per quarter; for weekly the weekly amount once per week):

```
priceAt(history, t):
  candidates = history.filter { isCorrection == false  AND effectiveFrom <= t }   ; corrections handled in §4.4
  return candidates.maxBy(effectiveFrom)?.amount  ?? sub.currentAmount             ; latest effective
  // a correction at effectiveFrom RETROACTIVELY replaces the price of the segment it corrects (§4.4)

total = 0
for periodStart in chargeDates(sub.startDate, min(now, endDate), sub.billingPeriod):
   total += priceAt(effectivePrices, periodStart)      ; period charge in native currency
return (total, monthsActive = differenceInMonths(start, end) + 1)
```

For **yearly** billing, iterate **anniversaries** (not months): one charge per completed year from `startDate`, applying the price effective at each anniversary. This matches Substimate's "count completed yearly payments" logic but in minor units and correction-aware.

### 4.3 Partial months / partial periods

v1 charges on **whole period boundaries** — a subscription started mid-month still incurs its first full charge at `startDate` (subscriptions bill the whole period, not pro-rated). Therefore `chargeDates` yields a charge at `startDate` and then at each period anniversary; no fractional/partial-month proration is applied to the *charge* amount. `monthsActive` (for the "X months active" label) is the **inclusive** count `differenceInMonths(start, end) + 1` so a sub started today shows "1 month active". This whole-period rule is the documented v1 semantics; pro-ration is an explicit non-goal.

### 4.4 Corrections

A history row with `isCorrection = true` **fixes the prior price step rather than introducing a new one**. Algorithm: build the *effective* price timeline by, for each correction, **replacing** the amount of the most recent non-correction segment whose `effectiveFrom <= correction.effectiveFrom` (it overrides what that segment *should have been*), instead of appending a new step. The walk then runs over the corrected timeline. This guarantees Lifetime Cost does **not** double-count a corrected step (acceptance criterion in [`./02-product-spec.md`](./02-product-spec.md) §4.9).

| Aspect | Rule |
|---|---|
| Rounding | summation is exact integer addition of native-currency minor amounts; display conversion (HALF-UP) is applied **per segment** afterward, never to the running total, to avoid compounding. |
| Edge cases | started today → 1 charge, `monthsActive = 1`. Ended sub → walk stops at `endDate`. Empty history (shouldn't happen) → fall back to `sub.currentAmount` for every period. Currency change mid-life → each segment carries its own currency; the analytics layer converts each segment to display currency before summing across currencies. |
| Overflow | running total guarded (`addingReportingOverflow`); a multi-decade daily-priced sub still fits `Int64`. |
| Complexity | O(p + h) where p = number of charge periods, h = history segments (sorting is O(h log h) once). |

**Test vectors** (`now = 2026-06-28`)

| # | scenario | computation | result | test name |
|---|---|---|---|---|
| T4.a | Monthly €9.99, start `2026-01-15`, no price change | 6 charges (Jan,Feb,Mar,Apr,May,Jun) × `999` | `5994` (€59.94), monthsActive `6` | `lifetime_monthly_flat` |
| T4.b | Monthly, start `2026-01-15`, `999` then **price change** to `1299` effective `2026-04-01` | Jan,Feb,Mar `999` (×3=2997) + Apr,May,Jun `1299` (×3=3897) | `6894` (€68.94) | `lifetime_monthly_priceChange` |
| T4.c | Same as T4.b but the `1299` row is a **correction** (`isCorrection=true`) of the original | every month uses corrected `1299`: `1299 × 6` | `7794` (€77.94) — *not* double-counted | `lifetime_monthly_correction` |
| T4.d | Yearly €120, start `2024-06-01` | anniversaries 2024-06, 2025-06, 2026-06 all passed → 3 charges × `12000` | `36000` (€360.00), monthsActive `25` | `lifetime_yearly_anniversaries` |

---

## 5. Analytics aggregations

> **Purpose.** Produce the dashboards/charts of [`./02-product-spec.md`](./02-product-spec.md) §4.7 (subscription analytics) and §5.3/§6.4 (cash-flow analytics). All aggregations: (a) convert each row to display currency at read time (§2), summing in display currency; (b) **guard every division** against zero (no NaN/∞ — the Substimate weakness); (c) are pure and unit-tested. Visual mapping is in [`./14-visualizations-and-charts.md`](./14-visualizations-and-charts.md).

### 5.1 Category distribution

```
categoryDistribution(items, kind, displayCurrency, rates):
  for each item: cat = item.categoryId ?? OTHER(kind)        ; nil → protected "Other"
                 m   = convert(monthlyEquivalent(item), displayCurrency, rates)
                 acc[cat].total += m;  acc[cat].count += 1
  grand = Σ acc[*].total
  for each cat: cat.share = grand == 0 ? 0 : Decimal(cat.total)/Decimal(grand)        ; 0 guard
                cat.avgPerService = cat.count == 0 ? 0 : HALF_UP(Decimal(cat.total)/cat.count)
  sort descending by total
```

| Output per category | type | formula |
|---|---|---|
| `total` | `Int64` minor (display ccy) | Σ monthly-equiv of members |
| `count` | `Int` | number of members |
| `share` | `Decimal` (0…1, ×100 for %) | `total / grandTotal`, **0 when grandTotal = 0** |
| `avgPerService` | `Int64` minor | `HALF_UP(total / count)`, **0 when count = 0** |

Complexity O(n). Slices with `total = 0` are omitted from charts (no zero slice).

**Test vector** (`categoryDistribution_sharesAndAvg`, display EUR): Streaming `{Netflix 1549, Disney 899}`, AI Chat `{Claude 2000}` → Streaming `total=2448, count=2, avg=1224, share=0.5503`; AI Chat `total=2000, count=1, avg=2000, share=0.4497`; grand `4448`. Empty input → `[]`, no NaN (`categoryDistribution_emptyNoNaN`).

### 5.2 Monthly trends (multi-series, last 6 months)

> The full Substimate `useFinanceAnalytics.ts` dataset, in minor units, for each of the last `m = 6` months (`startOfMonth(subMonths(now,5)) … now`).

For each month with `[monthStart, monthEnd]`, compute (all converted to display currency, all `Int64` minor unless noted):

```
income           = Σ incomeContribution(src, month)         ; weekly ×52/12, monthly ×1, yearly only in its month, one_time only if nextPayment ∈ month
fixedExpenses    = Σ fixedContribution(fe, month)           ; monthly ×1, quarterly only when month%3 aligns to its cadence, yearly only in its month
variableExpenses = Σ ve.amount where ve.spentOn ∈ [monthStart, monthEnd]
subscriptions    = Σ subContribution(sub, month)            ; non-yearly → monthlyEquivalent; yearly → full amount only in anniversary month; sub counts only if startDate <= monthEnd and (endDate == nil or endDate >= monthStart)
investments      = Σ (tx.price × tx.quantity) where tx.type == buy and tx.date ∈ month      ; HALF-UP to minor units
expenses         = fixedExpenses + variableExpenses + subscriptions
savings          = income − expenses                         ; signed (may be negative)
savingsRatio     = income == 0 ? 0 : Decimal(savings)/Decimal(income)        ; 0-guard
investmentRatio  = income == 0 ? 0 : Decimal(investments)/Decimal(income)    ; 0-guard
```

| Series | type | zero-guard |
|---|---|---|
| `income`, `expenses`, `fixedExpenses`, `variableExpenses`, `subscriptions`, `investments`, `savings` | `Int64` minor (display ccy) | — (`savings` may be negative) |
| `savingsRatio`, `investmentRatio` | `Decimal` (×100 = %) | **0 when `income == 0`** |

> **`investments` definition (pinned):** the sum of `buy` asset-transactions whose `date` falls in the month, valued `price × quantity` (fees excluded — fees are cost basis, not "invested capital" for the ratio). `quantity` is `Decimal`; `price × quantity` is computed in `Decimal` then HALF-UP to display-currency minor units.

Complexity O(m × (i + f + v + s + t)) ≈ linear in total rows × 6.

**Test vectors** (single month June 2026, display EUR)

| # | data | expected | test name |
|---|---|---|---|
| T5.2a | income `monthly 400000`; fixed `monthly 120000`; variable two rows `30000 + 15000` dated in June; subs `monthly 1549 + yearly 12000 started 2025-06-10` (anniversary June) ; buys `tx 50000@2 = 100000` in June | `income=400000, fixed=120000, variable=45000, subscriptions=1549+12000=13549, expenses=178549, savings=221451, savingsRatio=0.5536, investments=100000, investmentRatio=0.2500` | `trends_fullSeries_june` |
| T5.2b | income `0`; any expenses | `savingsRatio=0, investmentRatio=0` (no NaN) | `trends_zeroIncomeRatiosZero` |
| T5.2c | yearly sub started `2025-03-10`, month = June 2026 | contributes `0` (not anniversary month) | `trends_yearlyOnlyInAnniversaryMonth` |

### 5.3 Usage statistics

```
usageStats(subs, displayCurrency, rates):
  byState   = countAndCost partitioned over {active, rarely, unused}        ; cost = Σ monthlyEquivalent converted
  byPeriod  = count partitioned over {weekly, monthly, quarterly, yearly}
  recent    = subs created in last 3 months;  prior = subs created in the 3 months before that
  countDelta = recent.count − prior.count
  costDelta  = recent.costSum − prior.costSum         ; signed
  for each state: state.pct = total == 0 ? 0 : Decimal(state.count)/Decimal(total)
```

| Output | type | zero-guard |
|---|---|---|
| per-state `{count, cost, pct}` | `Int`, `Int64`, `Decimal` | pct = 0 when total = 0 |
| per-period `count` | `Int` | — |
| `countDelta` | `Int` (signed) | — |
| `costDelta` | `Int64` minor (signed) | — |

Complexity O(n). **Test vector** (`usageStats_distribution`): 10 subs → 6 active, 3 rarely, 1 unused → pct `0.6 / 0.3 / 0.1`; empty → all pct 0.

### 5.4 Payment-method breakdown

```
paymentMethodBreakdown(subs, displayCurrency, rates):
  for each sub: pm = sub.paymentMethod ?? .other
                m  = convert(monthlyEquivalent(sub), displayCurrency, rates)
                acc[pm].total += m; acc[pm].count += 1
  for each pm: pm.avgPerService = pm.count == 0 ? 0 : HALF_UP(total/count)
  sort descending by total
```

Same shape and zero-guards as §5.1 but keyed on the 8-value `PaymentMethod` enum. Complexity O(n).

**Test vector** (`paymentMethod_breakdown`): `credit_card {1549, 2000}`, `paypal {999}` → credit_card `total=3549, count=2, avg=1775` (HALF-UP of 1774.5 → 1775), paypal `total=999, count=1, avg=999`.

---

## 6. Cash-flow metrics

> **Purpose.** Roll up income and outgoings across mixed frequencies into the monthly **Key Metrics** cards of the Cash Flow overview ([`./02-product-spec.md`](./02-product-spec.md) §5.3) and the Home `monthly-burn`/`net-cash-flow` cards (§3.2).

### 6.1 Monthly income roll-up

```
monthlyIncomeMinor(incomeSources, displayCurrency, rates):
  Σ over recurring sources of convert(monthlyContribution(src), displayCurrency, rates)
  monthlyContribution(src):
     weekly  -> HALF_UP(amount × 52/12)
     monthly -> amount
     yearly  -> HALF_UP(amount / 12)
     one_time-> 0          ; excluded from RECURRING monthly income (still listed/charted by date)
```

### 6.2 Monthly expense roll-up & monthly burn

```
monthlyExpensesMinor = fixedMonthly + variableThisMonth + subscriptionsMonthly
  fixedMonthly        = Σ convert(feMonthly(fe))           ; monthly ×1, quarterly /3 (HALF-UP), yearly /12 (HALF-UP)
  variableThisMonth   = Σ convert(ve.amount) for ve.spentOn ∈ current month
  subscriptionsMonthly= Σ convert(monthlyEquivalent(sub)) for non-ended subs
monthlyBurnMinor      = monthlyExpensesMinor               ; the "Monthly Burn" card = total committed monthly spend
```

> **Monthly Burn** (Home card) = subscriptions (normalized monthly) + fixed expenses (normalized monthly) + this-month variable expenses, in display currency — exactly [`./02-product-spec.md`](./02-product-spec.md) §3.2.

### 6.3 Net & savings rate

```
netCashFlowMinor = monthlyIncomeMinor − monthlyExpensesMinor      ; signed (negative = over budget)
savingsRate      = monthlyIncomeMinor == 0 ? 0
                                           : Decimal(netCashFlowMinor) / Decimal(monthlyIncomeMinor)   ; may be negative
```

| Aspect | Rule |
|---|---|
| Sign | `net` and `savingsRate` are signed; negative net is a valid "spending exceeds income" state, never an error (rendered with warning treatment, [`./02-product-spec.md`](./02-product-spec.md) §5.6). |
| Zero income | `savingsRate = 0` (no NaN). |
| Rounding | HALF-UP per-source on the frequency normalization; sums are exact integer adds in display currency. |
| Savings (flow / Sankey) | `Savings = max(0, income − expenses)` is the **bucket** value used by the money-flow ([§ flow](#65-money-flow-bucket-values)); the *metric* `net` above is signed. These are deliberately different (a clamped bucket vs a signed metric). |
| Complexity | O(i + f + v + s). |

**Test vectors** (display EUR)

| # | data | net | savingsRate | test name |
|---|---|---|---|---|
| T6.a | income `monthly 400000`; expenses (fixed `120000` + variable `45000` + subs `40000`) = `205000` | `195000` (€1,950) | `0.4875` (48.75%) | `cashflow_positiveNet` |
| T6.b | income `monthly 200000`; expenses `250000` | `-50000` (−€500) | `-0.25` (−25%) | `cashflow_negativeNetClamped` |
| T6.c | income `0`; expenses `100000` | `-100000` | `0` (zero-income guard, not NaN) | `cashflow_zeroIncome` |
| T6.d | income weekly `10000` (€100/wk) | monthly contribution `HALF_UP(10000×52/12)=43333` (€433.33) | — | `cashflow_weeklyIncome_433` |

### 6.5 Money-flow bucket values

The Sankey buckets ([`./02-product-spec.md`](./02-product-spec.md) §6.2, redesign ADR-0016):

```
totalIncome   = Σ income normalized to timeframe (display ccy)
fixed         = Σ fixed expenses normalized to timeframe
variable      = Σ variable expenses within the timeframe window
subscriptions = Σ subscription monthly-equivalents normalized to timeframe
totalExpenses = fixed + variable + subscriptions
savingsBucket = max(0, totalIncome − totalExpenses)        ; clamped, never negative
```

Link width ∝ bucket value; buckets with value `0` are **omitted** (no zero-width link). Sum of outgoing links from Income = `totalIncome` within rounding (savings absorbs the remainder; over-budget clamps savings to 0 and shows an "Over budget" caption). Bucket→category drill-down: bucket value = Σ its category sub-values.

**Test vector** (`flow_bucketsAndSavingsClamp`, Monthly, display EUR): income `400000`; fixed `120000`, variable `45000`, subs `40000` → `totalExpenses=205000`, `savings=195000`; links Income→{Fixed 120000, Variable 45000, Subscriptions 40000, Savings 195000} sum `400000 = totalIncome`. Over-budget vector (`flow_overBudgetNoSavingsLink`): income `200000`, expenses `250000` → `savings=max(0,−50000)=0`, no Savings link, "Over budget by €500" caption.

---

## 7. Asset valuation

> **Purpose.** Compute cost basis, unrealized gain/loss, portfolio total, and asset-type distribution from `financial_assets` + `asset_transactions`, using the **average-cost** method (v1; FIFO deferred per ADR-0015). Field semantics are pinned in [`./05-data-model.md`](./05-data-model.md) §3.7: `purchasePriceMinor` = **total** cost basis, `currentPriceMinor` = **per-unit** market price, `valueMinor` = **total** current value.

### 7.1 Average-cost basis from transactions

```
averageCost(transactions for asset):
  heldQty   : Decimal = 0
  costBasis : Int64   = 0          ; total invested currently held (minor units, native ccy)
  realized  : Int64   = 0          ; realized P/L + dividends
  for tx in transactions ordered by date asc:
    switch tx.type:
      buy:  buyCost   = HALF_UP(tx.price × tx.quantity) + (tx.fees ?? 0)
            costBasis += buyCost ;  heldQty += tx.quantity
      sell: if tx.quantity > heldQty: ERROR .sellsMoreThanHeld
            avgUnit   = heldQty == 0 ? 0 : Decimal(costBasis)/heldQty            ; 0-guard
            soldCost  = HALF_UP(avgUnit × tx.quantity)
            proceeds  = HALF_UP(tx.price × tx.quantity) − (tx.fees ?? 0)
            realized += proceeds − soldCost
            costBasis -= soldCost ; heldQty -= tx.quantity
      dividend: realized += HALF_UP(tx.price × tx.quantity) − (tx.fees ?? 0)
      other:    ignored for basis (notes only)
  return (heldQty, costBasis, realized)
```

| Aspect | Rule |
|---|---|
| Cost basis | average-cost: a sell reduces basis by `avgUnit × soldQty`, not FIFO lots. `purchasePriceMinor` stored on the asset is this running `costBasis` (total invested currently held). |
| Rounding | each `price × quantity` and `avgUnit × quantity` is HALF-UP to native minor units; basis is exact integer thereafter. |
| Edge cases | sell > held → `.sellsMoreThanHeld` (validation error, no save — [`./02-product-spec.md`](./02-product-spec.md) §9.5). `heldQty == 0` → avgUnit 0 (no divide). Fractional `quantity` via `Decimal`. Mixed-currency txns: each tx carries its own currency; cross-currency basis converts per-tx (§2). |
| Complexity | O(t log t) to order, O(t) to fold. |

### 7.2 Unrealized gain/loss

```
unrealizedGainLossMinor(asset) = asset.valueMinor − (asset.purchasePriceMinor ?? 0)      ; signed
gainLossPct(asset) = purchasePriceMinor in {nil, 0} ? nil
                                                     : Decimal(unrealized) / Decimal(purchasePriceMinor)
```

`valueMinor` is the authoritative total market value (≈ `quantity × currentPriceMinor`, but the stored total is authoritative). The percentage is `nil` (shown as "—") when there is no cost basis, never NaN/∞.

| # | valueMinor | purchasePriceMinor | gain/loss | pct | test name |
|---|---|---|---|---|---|
| T7.2a | `125000 EUR` | `100000 EUR` | `+25000` (+€250) | `+0.25` (+25%) | `gainLoss_positive` |
| T7.2b | `80000 EUR` | `100000 EUR` | `-20000` (−€200) | `-0.20` (−20%) | `gainLoss_negative` |
| T7.2c | `5000 EUR` | `0`/`nil` | `+5000` | `nil` ("—", no divide) | `gainLoss_noBasisNoNaN` |

### 7.3 Portfolio total & asset-type distribution

```
portfolioTotalMinor(assets, displayCurrency, rates) = Σ convert(asset.value, displayCurrency, rates)
assetDistribution(assets, displayCurrency, rates):
  for each asset: acc[asset.type].value += convert(asset.value, displayCurrency, rates)
  total = Σ acc[*].value
  for each type: type.share = total == 0 ? 0 : Decimal(type.value)/Decimal(total)
  sort descending by value
```

One slice per `AssetType` (`stock`/`crypto`/`savings`/`real_estate`/`other`); shares sum to 1.0 (100%) when total > 0, else all 0 (no NaN). Complexity O(n).

**Test vector** (`assetDistribution_shares`, display EUR): stock `300000`, crypto `150000`, savings `50000` → total `500000`; shares `0.60 / 0.30 / 0.10` summing to 1.0. Empty → `[]`, total `0`, no slice.

---

## 8. BTC calculator

> **Purpose.** Bidirectional fiat (EUR/USD) ↔ sats/BTC at the live market price, sourced server-side from the `market-data` Edge Function ([`./02-product-spec.md`](./02-product-spec.md) §10). The price is read from the canonical rate snapshot's `btcEur`/`btcUsd`.

```
fiatToSats(fiatMajor: Decimal, btcPriceFiat: Decimal) -> Int64:
   require btcPriceFiat > 0  else return nil/"—"
   btc  = fiatMajor / btcPriceFiat
   sats = HALF_UP(btc × 100_000_000, scale = 0)
   return sats

satsToFiatMinor(sats: Int64, btcPriceFiat: Decimal, fiatCcy) -> Int64:
   btc      = Decimal(sats) / 100_000_000
   fiatMajor= btc × btcPriceFiat
   return HALF_UP(fiatMajor × 100, scale = 0)         ; cents
```

| Aspect | Rule |
|---|---|
| Rounding | HALF-UP to whole sats (sats indivisible) / to cents. |
| Edge cases | non-numeric / negative / `btcPrice ≤ 0` input → result `"—"`, **never NaN, never crash**. Very large inputs format with grouping (§1.7). |
| Stale/offline | uses cached price with an "as of <time>" caption; never blocks (§2.5). |
| Complexity | O(1). |

**Test vectors**

| # | input | price | result | test name |
|---|---|---|---|---|
| T8.a | €500 | btcEur `50000` | `500 / 50000 = 0.01 BTC → 1,000,000 sats (0.01000000 BTC)` | `calc_eurToSats` |
| T8.b | 2,000,000 sats | btcUsd `60000` | `0.02 × 60000 = $1,200.00 → 120000 cents` | `calc_satsToUsd` |
| T8.c | invalid / `"-5"` | any | `"—"` (no crash, no NaN) | `calc_invalidInputDash` |
| T8.d | €1 | btcEur `63038.85` | `1/63038.85 = 0.00001586… BTC → 1586.31… → 1586 sats` (HALF-UP) | `calc_subSatRounding` |

---

## 9. CSV import

> **Purpose.** Parse a user-supplied CSV of subscriptions into validated, previewable rows; import only valid rows (partial import). Maps Substimate's `ImportDataPage.tsx`, hardened for minor units, native currency, all four billing periods, and locale-aware number parsing. Column set, aliases, defaults, and validation copy are normative in [`./02-product-spec.md`](./02-product-spec.md) §8.

### 9.1 Locale-aware number parsing

CSV amounts arrive in US (`1,234.56`) **or** EU (`1.234,56`) convention. The parser **detects** the convention, normalizes to a `.`-decimal string, then feeds `Money.parse` (§1.6).

```
detectAndNormalizeNumber(raw: String) -> String? :
  s = trim(strip currency symbols and spaces)
  lastDot   = lastIndex(s, '.')
  lastComma = lastIndex(s, ',')
  if both present:
     decimalSep = (lastComma > lastDot) ? ',' : '.'         ; the rightmost separator is the decimal
  elif only comma:
     # ambiguous: "1,234" could be 1234 (grouping) or 1.234 (decimal)
     decimalSep = (count(',') == 1 AND digitsAfterComma ∈ {1,2}) ? ',' : 'none'   ; heuristic → CONFIRM if ambiguous
  elif only dot:
     decimalSep = (count('.') == 1 AND digitsAfterDot ∈ {1,2}) ? '.' : 'none'
  else: decimalSep = 'none'                                  ; pure integer
  remove all separators except decimalSep; replace decimalSep with '.'
  return canonical or nil if non-numeric
```

| Aspect | Rule |
|---|---|
| Detect rule | when both `.` and `,` appear, the **rightmost** is the decimal separator and the other is grouping. This unambiguously distinguishes `1,234.56` (US) from `1.234,56` (EU). |
| Ambiguity | a lone separator with 1–2 trailing digits is treated as decimal; a lone separator with 3 trailing digits (e.g. `1,234`) is **grouping** → integer. Genuinely ambiguous cases surface a one-time **"confirm number format" prompt** in the preview (US vs EU), defaulting to the device locale; the chosen convention then applies to the whole file. |
| Output | a `.`-decimal string handed to `Money.parse` (which still rejects over-precision per the row currency). |
| Complexity | O(len). |

**Test vectors**

| # | raw | detected | normalized | minor (EUR) | test name |
|---|---|---|---|---|---|
| T9.1a | `"1,234.56"` | US | `"1234.56"` | `123456` | `csvNum_usGrouping` |
| T9.1b | `"1.234,56"` | EU | `"1234.56"` | `123456` | `csvNum_euGrouping` |
| T9.1c | `"15,49"` | EU decimal | `"15.49"` | `1549` | `csvNum_euDecimalOnly` |
| T9.1d | `"15.49"` | US decimal | `"15.49"` | `1549` | `csvNum_usDecimalOnly` |
| T9.1e | `"1,234"` | grouping → integer | `"1234"` | `123400` | `csvNum_loneCommaThousands` |
| T9.1f | `"abc"` | — | nil → row error "Invalid amount" | — | `csvNum_invalid` |

### 9.2 Column mapping & aliases

```
header row -> lowercased, trimmed, snake_cased tokens
map each token to a canonical column via the alias table:
  name           <- name | service | subscription            (required)
  amount         <- amount | cost | price                    (billing-period amount; required OR monthly_cost)
  monthly_cost   <- monthly_cost | monthly_amount            (always monthly; alt to amount)
  billing_period <- billing_period | billing | period        (default monthly)
  currency       <- currency                                 (default EUR)
  payment_method <- payment_method | payment | method        (default credit_card)
  category       <- category                                 (default Other; created if new)
  start_date     <- start_date | start | date                (default today)
  usage_state    <- usage_state | usage                      (default active)
  url            <- url | website                            (normalized to https)
  auto_renew     <- auto_renew | autorenew                   (default true)
  icon           <- icon
unknown columns are ignored; a missing required column fails the whole file (not per-row)
```

If both `amount` and `monthly_cost` are present, `monthly_cost` (always a monthly figure) wins and `billing_period` is forced `monthly` for that row.

### 9.3 Row validation rules

Each row yields `status = Ready` or a **comma-joined list of errors** (all errors collected, not first-fail), per [`./02-product-spec.md`](./02-product-spec.md) §8.4:

| Check | Error copy |
|---|---|
| `name` empty | "Missing name" |
| amount not finite ≥ 0 (after §9.1) | "Invalid amount" |
| `billing_period` ∉ {weekly,monthly,quarterly,yearly} | "Invalid billing period" |
| `currency` ∉ {EUR,USD,BTC} | "Unsupported currency" |
| `payment_method` ∉ the 8 enum values | "Unsupported payment method" |
| `usage_state` ∉ {active,rarely,unused} | "Unsupported usage state" |
| amount over-precision for currency (via `Money.parse`) | "Invalid amount" |

Amount → minor units of the row's currency (2-dp fiat / integer sats BTC). The field tokenizer handles **quoted fields and escaped quotes** (`"a,b"` is one field; `""` is a literal quote).

### 9.4 CSV field tokenizer (RFC-4180-lite)

```
parseLine(line):
  fields=[]; cur=""; inQuotes=false; i=0
  while i < len:
    c = line[i]
    if inQuotes:
      if c == '"' and line[i+1] == '"': cur += '"'; i += 2; continue   ; escaped quote
      if c == '"': inQuotes=false; i+=1; continue
      cur += c; i+=1
    else:
      if c == '"': inQuotes=true; i+=1; continue
      if c == ',': fields.append(cur); cur=""; i+=1; continue
      cur += c; i+=1
  fields.append(cur)
  return fields
```

Complexity O(len(line)). Handles embedded commas, embedded newlines inside quotes (the reader joins physical lines while `inQuotes`), and `""` escapes.

### 9.5 Dedup & partial-import semantics

| Aspect | Rule |
|---|---|
| Dedup | **No dedup in v1.** Duplicate names are *allowed* but flagged in preview as a non-blocking "Possible duplicate" hint (name match, case-insensitive, against existing subs and within the file). The hint never blocks import. |
| Partial import | "Import N valid rows" imports only `Ready` rows; invalid rows are **skipped** and never block a valid sibling. |
| Path | each imported row goes through the **same repository create path** as manual add, so the price-history trigger fires (one `subscription_price_history` row per import). |
| Idempotency | re-importing the same file creates duplicates (no dedup) — by design; the preview retains so the user can fix-and-reimport. |
| Complexity | O(rows × fields). |

**Test vectors**

| # | input | result | test name |
|---|---|---|---|
| T9.5a | sample CSV (Netflix 15.49 monthly EUR; GitHub 100 yearly USD) | 2 rows `Ready`; GitHub stores `10000 USD`, `billing_period=yearly`, monthly-equiv `HALF_UP(10000/12)=833` (~$8.33) | `csvImport_sampleTwoRows` |
| T9.5b | 3 valid + 1 row missing name | imports 3; 4th status "Missing name"; skipped | `csvImport_partial3of4` |
| T9.5c | row with quoted `"Acme, Inc"` name + comma | name kept as one field `Acme, Inc` | `csvImport_quotedComma` |
| T9.5d | row with category `Streaming Plus` (new) | category created (user-owned, kind=subscription) on import | `csvImport_newCategoryCreated` |
| T9.5e | non-CSV file | refused: "Only CSV files are supported." | `csvImport_rejectsNonCsv` |

---

## 10. Prediction & category inference

> **Purpose.** As the user types a service name in Add Subscription, prefill `vendorURL`, `icon`, a suggested amount, and infer a category — a **pure, offline dictionary lookup** ported from Substimate (`subscriptionData.ts` + `subscriptionPredictions.ts`), unit-tested. No network. Normative behavior in [`./02-product-spec.md`](./02-product-spec.md) §4.10.

### 10.1 Seed prediction dictionary (shape)

```
PredictedSubscription { vendorURL: URL,           // canonical vendor URL, normalized to https
                        icon: String,             // SF Symbol / brand-asset id (Substimate lucide names mapped)
                        typicalAmountMinor: Int64? } // optional suggested amount, minor units of default ccy
seedDictionary: [normalizedKey: String -> PredictedSubscription]
```

Keys are lowercased, trimmed service identifiers (`"netflix"`, `"chatgpt"`, `"github"`, `"midjourney"`, `"mj"`, …). Substimate's `monthlyCost` numbers port to `typicalAmountMinor` (e.g. ChatGPT $20 → `2000`; Netflix `1549`; GitHub `1000`). Substimate lucide icon names (`Bot`, `Code`, `Tv`, `Music`, `Image`, `Video`, `Mic`, …) map to SF Symbols / brand assets at port time.

### 10.2 Name match rule (exact → substring, <2-char guard)

```
predict(name):
  term = lowercase(trim(name))
  if term.length < 2: return nil                       ; guard
  if seedDictionary[term] != nil: return that          ; EXACT match first
  for (key, pred) in seedDictionary:                   ; SUBSTRING fallback (declaration order)
     if key.contains(term) OR term.contains(key): return pred
  return nil
```

The substring rule is **bidirectional** (typed term contains a key, or a key contains the typed term) — matching Substimate's `predictSubscription`. Exact match always wins over substring.

### 10.3 Keyword → category inference

A map independent of the name dictionary, evaluated in **declaration order**, returning the **first** group whose any keyword is a case-insensitive substring of the name; default `Other`:

```
inferCategory(name):
  s = lowercase(name)
  for group in keywordMap (in order):     ; AI Chat, Coding, Diffusion, Productivity, Creative, Social,
                                          ; Streaming, Music, Gaming, Audio Generation, Video Generation,
                                          ; Cloud Services, Fitness, Health, Food, Transport, Financial
    if any keyword in group.keywords where s.contains(keyword): return group.category
  return "Other"
```

The keyword lists are exactly the table in [`./02-product-spec.md`](./02-product-spec.md) §4.10(b) (e.g. AI Chat: chatgpt, claude, gemini, perplexity, anthropic, bard; Coding: bolt.new, cursor, v0, copilot, codeium, replit, github, gitlab; …). **Order matters** for overlaps — e.g. "github" is under Coding and is checked before any later group.

### 10.4 Prefill composition

```
prefill(name) :
  pred = predict(name)
  cat  = inferCategory(name)
  return { vendorURL: pred?.vendorURL, icon: pred?.icon ?? "creditcard",
           suggestedAmountMinor: pred?.typicalAmountMinor, category: cat }
  // all fields user-editable; explicit user edits WIN over predictions
```

| Aspect | Rule |
|---|---|
| Edge cases | term < 2 chars → no prediction *and* category not auto-applied. Unknown name, no keyword → `predict = nil`, category `Other`, no prefill applied. |
| Determinism | pure; declaration order fixed; no locale/network dependence. |
| Complexity | O(dictionary size × len) worst case for substring scan (dictionary is small, ~100 entries). |

**Test vectors**

| # | input | category | prediction | test name |
|---|---|---|---|---|
| T10.a | `"github"` | `Coding` | `github.com` | `infer_github_coding` |
| T10.b | `"ChatGPT"` | `AI Chat` | `chat.openai.com`, amount `2000` | `infer_chatgpt_aichat` |
| T10.c | `"midjourney"` | `Diffusion` | `midjourney.com`, amount `1000` | `infer_midjourney_diffusion` |
| T10.d | `"Netflix"` (any case) | `Streaming` | `netflix.com`, icon streaming, amount `1549` | `predict_netflixExact` |
| T10.e | `"n"` (1 char) | not applied | `nil` | `predict_underTwoCharsNil` |
| T10.f | `"Acme Widgets"` | `Other` | `nil` | `infer_unknownIsOther` |
| T10.g | `"mj"` (alias) | `Diffusion` | `midjourney.com` (exact alias) | `predict_aliasMj` |

---

## 11. Payday calendar & recurrence

> **Purpose.** Project recurring charge/payday events into a date window for the calendar grid and for local-notification scheduling ([`./02-product-spec.md`](./02-product-spec.md) §7). Pure date math; no money rounding (amounts are already computed elsewhere).

### 11.1 Subscription charge projection

```
chargeDates(sub, windowStart, windowEnd):
  if sub.startDate > windowEnd: return []
  cap = min(windowEnd, sub.endDate ?? windowEnd)
  step =  weekly    -> +7 days
          monthly   -> +1 month   (clamp day-of-month, §11.3)
          quarterly -> +3 months  (clamp)
          yearly    -> +1 year    (clamp Feb-29)
  d = sub.startDate
  while d <= cap:
     if d >= windowStart: emit ChargeEvent(date=d, amount=periodCharge, status = d > today ? upcoming : past)
     d = advance(d, step)
  return events
```

| billingPeriod | recurrence from `startDate` |
|---|---|
| weekly | every 7 days |
| monthly | same day-of-month each month (clamped) |
| quarterly | every 3 months (clamped) |
| yearly | the (month, day) anniversary each year (Feb 29 → Feb 28 in non-leap years) |

A charge is `upcoming` if its date is in the future relative to today, else `past`. A sub not yet started, or whose `endDate` precedes the projected date, produces **no** event.

### 11.2 Income next-occurrence

```
nextIncomeOccurrence(src, from = today):
  if src.nextPayment == nil: return nil
  base = src.nextPayment
  switch src.frequency:
     one_time: return base >= from ? base : nil       ; fires once, only if still in the future
     weekly:   return advanceToFutureBy(base, +7 days, from)
     monthly:  return advanceToFutureBy(base, +1 month (clamp), from)
     yearly:   return advanceToFutureBy(base, +1 year (clamp), from)
advanceToFutureBy(base, step, from): roll base forward by step until >= from
```

Income markers are placed on `nextPayment` (and its forward recurrences within the viewed window). `one_time` income has no recurrence — a single marker, only if it falls in the window.

### 11.3 Day-of-month clamping

Months lacking the start day clamp to the **last day of that month**: a subscription started on the **31st** charges on **Feb 28** (or **Feb 29** in a leap year), Apr 30, etc. Clamping does **not** drift the anchor — March still uses the 31st; only the rendered occurrence in a short month is clamped. Leap-year rule: a Feb-29 yearly anchor renders Feb 28 in non-leap years and Feb 29 in leap years.

```
clampDay(year, month, anchorDay) = min(anchorDay, daysInMonth(year, month))
```

### 11.4 Windowing

The calendar renders one month `[firstOfMonth, lastOfMonth]`; projection is generated for that window only (plus a small look-ahead for the Home "Upcoming" card: next 30 days, at most 5 events, sorted ascending by date). Past months are navigable and read-only.

### 11.5 Lead-time reminder scheduling

```
reminderFireDate(eventDate, leadDays) = startOfDay(eventDate) − leadDays days     ; leadDays ∈ 0…30
schedule only if: master toggle on (payment_reminders_enabled / payday_reminders_enabled)
             AND per-entity opt-in (subscriptions.reminders_enabled)
             AND reminderFireDate >= now    (don't schedule past reminders)
```

Lead time is `user_preferences.reminder_lead_time_days` (CHECK 0…30, default 2). Reminders are **recomputed** when the underlying entity changes and **cancelled** when it is deleted or notifications turned off. Authorization is deferred to first opt-in (never on cold launch). All local via `UNUserNotificationCenter` — no server push in v1.

| Aspect | Rule |
|---|---|
| Edge cases | `leadDays = 0` → fire on the event day (start of day). A fire date already in the past is **not** scheduled. day-29/30/31 anchors clamp per §11.3. |
| Complexity | O(events in window) per entity; O(n × events) overall. |

**Test vectors** (`today = 2026-06-28`)

| # | scenario | events / result | test name |
|---|---|---|---|
| T11.a | monthly sub, `startDate 2026-01-15`, window June 2026 | one charge `2026-06-15`, status `past` | `calendar_monthlyDayOfMonth` |
| T11.b | yearly sub, `startDate 2025-03-10`, year 2026 | one charge `2026-03-10` (anniversary month only) | `calendar_yearlyAnniversaryOnce` |
| T11.c | sub `startDate 2026-01-31`, window February 2026 | charge clamps to `2026-02-28` | `calendar_clampJan31ToFeb28` |
| T11.d | sub `startDate 2024-01-31`, window February 2024 (leap) | charge clamps to `2024-02-29` | `calendar_clampLeapFeb29` |
| T11.e | monthly charge `2026-07-01`, leadDays `2`, reminders on | reminder fires `2026-06-29T00:00` (future → scheduled) | `reminder_leadTimeTwoDays` |
| T11.f | charge `2026-06-20` (past), leadDays `2` | fire date past → **not** scheduled | `reminder_pastNotScheduled` |
| T11.g | weekly sub `startDate 2026-06-01`, window June | charges 06-01,06-08,06-15,06-22,06-29 | `calendar_weeklySteps` |
| T11.h | one_time income `nextPayment 2026-06-30` | single marker `2026-06-30`; no recurrence | `income_oneTimeSingleMarker` |

---

## 12. Sync reconciliation math

> **Purpose.** The *algorithmic* statement of the offline-first reconciliation: per-field last-write-wins, the delta-poll cursor, and tombstone rules. The full engine **prose** (pending-write queue, Realtime layering, coalescing) is canonical in [`./03-architecture.md`](./03-architecture.md) §5 and the column contract in [`./05-data-model.md`](./05-data-model.md) §6 — this section states the comparisons as testable functions; if it diverges, those docs win.

### 12.1 Per-field last-write-wins

The conflict clock is `updated_at` on the server side and `clientMutatedAt` on the local side, compared **per field** (not per row). For a `(entity, id)` with a downstream remote row and a local pending mutation carrying `changedKeys`:

```
reconcile(localPending, remoteRow):
  merged = remoteRow                                  ; step 1: server row is the base (already applied to cache)
  for key in localPending.changedKeys:                ; step 2: re-apply still-winning local fields
     if localPending.clientMutatedAt[key] STRICTLY-GREATER-THAN remoteRow.updatedAt:
        merged[key] = localPending.value[key]         ; local wins, stays queued for push
     else:
        drop key from pending                          ; server wins, local edit superseded
  return merged
```

| Aspect | Rule |
|---|---|
| Tie rule | equal timestamps resolve in favor of the **remote** (server authoritative) — `clientMutatedAt` must be **strictly** greater to win. |
| Granularity | per field: a remote change to `name` and a local change to `amountMinor` **both** survive (no clobber) when each is the newer writer of its own field. |
| Precision | `updated_at` decoded at full microsecond precision ([`./05-data-model.md`](./05-data-model.md) §8.4) so server ordering never inverts locally. |
| Post-push | after a successful push, the server `updated_at` (re-stamped by the `set_updated_at` trigger) becomes the new field baseline and satisfied keys leave the queue. |
| Append-only | `subscription_price_history`, `asset_transactions` are insert-only and **never** reconcile (no conflict path). |
| `clientMutatedAt` | a monotonic, persisted clock advanced ≥1 tick per write — never goes backwards across NTP/restart ([`./03-architecture.md`](./03-architecture.md) §5.4). |
| Complexity | O(k) per row, k = changedKeys. |

**Test vectors**

| # | local | remote | merged | test name |
|---|---|---|---|---|
| T12.1a | `name` changed, `clientMutatedAt = T+5` | row `updatedAt = T+2` | local `name` wins, stays queued | `lww_localFieldNewerWins` |
| T12.1b | `name` changed, `clientMutatedAt = T+2` | row `updatedAt = T+5` | remote `name` wins, key dropped | `lww_remoteNewerSupersedes` |
| T12.1c | `name` changed `clientMutatedAt = T+3`; remote changed only `amountMinor` at `T+4` | both survive: local `name`, remote `amountMinor` | `lww_perFieldNoClobber` |
| T12.1d | `name` changed `clientMutatedAt = T+5`; remote `updatedAt = T+5` (tie) | remote wins (strict `>` required) | `lww_tieFavorsRemote` |

### 12.2 Delta-poll cursor

```
deltaQuery(entity): SELECT * WHERE updated_at > lastSyncedAt[entity] ORDER BY (updated_at, id)
onSuccess(rows): lastSyncedAt[entity] = max(rows.updated_at, lastSyncedAt[entity])     ; never regress
firstSync (lastSyncedAt unset): full paginated fetch, pages of 1000 by (updated_at, id), until short page; then set cursor
```

Realtime events do **not** advance the cursor (the delta poll is the authority, so a missed Realtime event is recovered next poll). The cursor is persisted per entity type.

| # | scenario | result | test name |
|---|---|---|---|
| T12.2a | cursor `T+10`; poll returns rows max `updated_at = T+25` | cursor advances to `T+25` | `cursor_advancesToMax` |
| T12.2b | cursor `T+25`; poll returns rows max `T+20` (clock skew) | cursor stays `T+25` (never regresses) | `cursor_neverRegresses` |
| T12.2c | cursor unset | full paginated bootstrap then cursor = max seen | `cursor_firstSyncBootstrap` |

### 12.3 Tombstones

```
delete(id): write PendingMutation(.delete) + cache tombstone(id)
while tombstone(id) live:  ignore any incoming insert/refresh row carrying id    ; stale remote echo
onServerConfirm(delete RPC): GC tombstone(id)
SET-NULL reconcile: a queued upsert whose category_id was SET NULL server-side keeps NULL (never resurrect stale FK)
```

| Aspect | Rule |
|---|---|
| Live window | tombstone retained until the server confirms the delete (via `delete_subscription` RPC or DELETE), then garbage-collected. |
| Echo suppression | a Realtime insert or refresh row for a tombstoned id is **ignored** so a stale echo can't undo the local delete. |
| SET NULL | a `category_id` that lost its referent (category deleted) is treated as superseded by the server (NULL kept), dropped from the pending changed-field set. |
| Complexity | O(1) per event (tombstone set lookup). |

| # | scenario | result | test name |
|---|---|---|---|
| T12.3a | delete `id=A`; Realtime insert `id=A` arrives before confirm | insert ignored (tombstone live) | `tombstone_suppressesEcho` |
| T12.3b | delete `id=A`; server confirms | tombstone GC'd; future `A` rows accepted | `tombstone_gcAfterConfirm` |
| T12.3c | queued upsert sets `category_id=X`; server SET NULL (cat deleted) | merged keeps NULL | `tombstone_setNullKept` |

---

## 13. Search/filter/sort ordering

> **Purpose.** Deterministic client-side search, filtering, and sorting over cached collections (subscriptions, expenses, assets), per [`./02-product-spec.md`](./02-product-spec.md) §4.3–§4.4. All client-side over the cached set; no server round-trip.

### 13.1 Search

```
matches(sub, query):
  q = foldedLowercase(trim(query))            ; Unicode case+diacritic fold, locale-independent
  if q.isEmpty: return true
  return foldedLowercase(sub.name).contains(q)
      OR foldedLowercase(categoryName(sub)).contains(q)
      OR foldedLowercase(sub.paymentMethod.label).contains(q)
      OR foldedLowercase(sub.billingPeriod.label).contains(q)
```

Searches name, category name, payment method, billing period (the same fields Substimate searched). Case- and diacritic-insensitive via `String.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)` — pinned locale-independent so results are deterministic. Empty query matches all.

### 13.2 Filter chips

```
filter(subs, chip):
  All        -> subs                              ; pseudo-filter, not a row
  Favorites  -> subs.filter { $0.favorite }       ; pseudo-filter (favorite == true)
  category   -> subs.filter { $0.categoryId == chip.id }
```

`All`/`Favorites` are presentation pseudo-filters (never category rows). A nil `categoryId` matches the protected `Other` bucket when the `Other` chip is selected.

### 13.3 Sort

```
sort(subs, option):
  Manual       -> by sortOrder asc, then createdAt asc (stable)          ; default; enables drag-reorder
  Name         -> by foldedLowercase(name) asc, then id asc              ; deterministic tie-break
  Monthly cost -> by monthlyEquivalent(display ccy) DESC, then name asc  ; high→low
  Usage        -> by usageRank {unused:0, rarely:1, active:2} asc, then monthlyEquivalent DESC
```

| Aspect | Rule |
|---|---|
| Stability & determinism | every sort has an explicit final tie-break (`id` or `name`) so ordering is total and stable across runs. |
| Cost sort | uses monthly-equivalent in **display currency** (§3); rows with unavailable conversion sort by native amount last (deterministic, flagged). |
| Manual sort | the only mode where drag-reorder is enabled; persisted via `batch_reorder_subscriptions` ([`./05-data-model.md`](./05-data-model.md) §5.2). |
| Complexity | O(n) filter/search, O(n log n) sort. |

**Test vectors**

| # | data | op | result | test name |
|---|---|---|---|---|
| T13.a | names `["Spotify","Netflix","spotify"]` | search `"spot"` | matches `Spotify`, `spotify` (case-fold) | `search_caseFold` |
| T13.b | search `"café"` vs name `"Cafe Plus"` | search | matches (diacritic-fold) | `search_diacriticFold` |
| T13.c | subs monthly-equiv `{A:1000, B:3000, C:2000}` | sort Monthly cost | `[B,C,A]` (desc) | `sort_monthlyCostDesc` |
| T13.d | usage `{X:active, Y:unused, Z:rarely}` | sort Usage | `[Y,Z,X]` (unused→rarely→active) | `sort_usageRank` |
| T13.e | favorites `{A:true, B:false}` | filter Favorites | `[A]` | `filter_favoritesOnly` |

---

## 14. Test-vector index

Every algorithm above ships with its named unit tests **in the same change** (golden rule, [`../CLAUDE.md`](../CLAUDE.md) §6; quality gate [`./09-engineering-practices.md`](./09-engineering-practices.md) §3.1). Tests are `Swift Testing` `@Test` cases (parameterized `@Test(arguments:)` for the table-driven ones), in the package that owns the logic (`Domain/Models`, `Shared/Utilities`, or `DataLayer` for sync/CSV). This index maps each algorithm to its tests and home target.

| Algorithm | §  | Test target | Named tests |
|---|---|---|---|
| Money add/sub/negate/scale/compare | 1.1–1.5 | `Domain/Models` | `adding_sameCurrency_sums`, `adding_mismatch_throws`, `adding_guardsOverflow`, `subtracting_allowsNegativeDelta`, `subtracting_guardsOverflow`, `negated_guardsIntMin`, `scaled_byInt`, `scaled_guardsOverflow`, `compare_sameCurrency`, `compare_mismatch_throws`, `equality_currencyIsIdentity` |
| Money parse | 1.6 | `Domain/Models` | `parse_basicEUR`, `parse_basicUSD`, `parse_btcSats`, `parse_singleDecimal`, `parse_rejectsTooManyFractionalDigits`, `parse_rejectsNegative`, `parse_rejectsInvalid`, `parse_guardsOverflow`, `parse_roundsHalfUp` |
| Money format | 1.7 | `Shared/Utilities` | `format_eurDE`, `format_usdUS`, `format_btcSatsGrouping`, `format_negativeDelta` |
| Currency conversion | 2.1–2.3 | `Domain/Models` | `convert_eurToUsd_halfUp`, `convert_usdToEur`, `convert_eurToBtcSats`, `convert_btcToUsd`, `convert_identity`, `convert_rateUnavailable`, `convert_halfUpBoundary` |
| BTC ↔ sats | 2.4 | `Domain/Models` | `sats_fromBtc`, `sats_oneBtc`, `sats_subSatRoundsUp`, `btc_fromSats` |
| Staleness / missing rate | 2.5 | `Domain/Models` | `stale_within24h`, `stale_beyond24h`, `stale_exactlyAtBoundary`, `missingRate_displaysUnconverted` |
| Subscription normalization | 3.1–3.3 | `Domain/Shared` | `normalize_yearlyToMonthly`, `normalize_weekly_52over12`, `normalize_quarterly`, `normalize_monthlyIdentity`, `normalize_weeklyRounding`, `normalize_annualIndependentOfMonthly`, `window_yearlyTimesTwelve`, `window_quarterly` |
| Effective spend by usage | 3.4 | `Shared/Utilities` | `effectiveSpend_buckets` |
| Lifetime cost (price-history walk) | 4 | `Shared/Utilities` | `lifetime_monthly_flat`, `lifetime_monthly_priceChange`, `lifetime_monthly_correction`, `lifetime_yearly_anniversaries`, `lifetime_startedTodayOneMonth` |
| Category distribution | 5.1 | `Shared/Utilities` | `categoryDistribution_sharesAndAvg`, `categoryDistribution_emptyNoNaN` |
| Monthly trends multi-series | 5.2 | `Shared/Utilities` | `trends_fullSeries_june`, `trends_zeroIncomeRatiosZero`, `trends_yearlyOnlyInAnniversaryMonth`, `trends_investmentsAreBuysOnly` |
| Usage statistics | 5.3 | `Shared/Utilities` | `usageStats_distribution`, `usageStats_deltaTrend`, `usageStats_emptyNoNaN` |
| Payment-method breakdown | 5.4 | `Shared/Utilities` | `paymentMethod_breakdown`, `paymentMethod_nilDefaultsOther` |
| Cash-flow metrics | 6 | `Shared/Utilities` | `cashflow_positiveNet`, `cashflow_negativeNetClamped`, `cashflow_zeroIncome`, `cashflow_weeklyIncome_433`, `flow_bucketsAndSavingsClamp`, `flow_overBudgetNoSavingsLink` |
| Asset valuation | 7 | `Shared/Utilities` | `avgCost_buySellFold`, `avgCost_sellMoreThanHeldThrows`, `gainLoss_positive`, `gainLoss_negative`, `gainLoss_noBasisNoNaN`, `assetDistribution_shares` |
| BTC calculator | 8 | `Shared/Utilities` | `calc_eurToSats`, `calc_satsToUsd`, `calc_invalidInputDash`, `calc_subSatRounding` |
| CSV locale number parse | 9.1 | `DataLayer` | `csvNum_usGrouping`, `csvNum_euGrouping`, `csvNum_euDecimalOnly`, `csvNum_usDecimalOnly`, `csvNum_loneCommaThousands`, `csvNum_invalid` |
| CSV mapping/validation/tokenize/import | 9.2–9.5 | `DataLayer` | `csvImport_sampleTwoRows`, `csvImport_partial3of4`, `csvImport_quotedComma`, `csvImport_newCategoryCreated`, `csvImport_rejectsNonCsv`, `csvMap_aliases`, `csvMap_missingRequiredColumnFailsFile`, `csvValidate_collectsAllErrors` |
| Prediction & inference | 10 | `Shared/Utilities` | `infer_github_coding`, `infer_chatgpt_aichat`, `infer_midjourney_diffusion`, `predict_netflixExact`, `predict_underTwoCharsNil`, `infer_unknownIsOther`, `predict_aliasMj` |
| Payday calendar & recurrence | 11 | `Shared/Utilities` | `calendar_monthlyDayOfMonth`, `calendar_yearlyAnniversaryOnce`, `calendar_clampJan31ToFeb28`, `calendar_clampLeapFeb29`, `calendar_weeklySteps`, `income_oneTimeSingleMarker`, `reminder_leadTimeTwoDays`, `reminder_pastNotScheduled` |
| Sync reconciliation | 12 | `DataLayer` | `lww_localFieldNewerWins`, `lww_remoteNewerSupersedes`, `lww_perFieldNoClobber`, `lww_tieFavorsRemote`, `cursor_advancesToMax`, `cursor_neverRegresses`, `cursor_firstSyncBootstrap`, `tombstone_suppressesEcho`, `tombstone_gcAfterConfirm`, `tombstone_setNullKept` |
| Search/filter/sort | 13 | `Shared/Utilities` | `search_caseFold`, `search_diacriticFold`, `sort_monthlyCostDesc`, `sort_usageRank`, `filter_favoritesOnly` |

> **Coverage rule.** No algorithm in this document ships without at least the test vectors listed above. The money/currency/analytics/CSV cases are precisely the logic Substimate left **untested**; covering them is a Definition-of-Done gate ([`./09-engineering-practices.md`](./09-engineering-practices.md) §3.1).

---

## Related documents

- [`../CLAUDE.md`](../CLAUDE.md) — Canonical Decisions Brief; money-as-minor-units, no-`Double`, tests-with-logic golden rules.
- [`./02-product-spec.md`](./02-product-spec.md) — Behavioral contract: analytics, money-flow redesign, CSV import, prediction, calendar, calculator.
- [`./03-architecture.md`](./03-architecture.md) — Sync engine prose (per-field LWW, delta-poll cursor, tombstones, Realtime layering).
- [`./04-tech-stack.md`](./04-tech-stack.md) §6.2 — Canonical currency-conversion contract (rate schema, triangulation, HALF-UP, staleness).
- [`./05-data-model.md`](./05-data-model.md) — Normative schema, `Money`/`CurrencyConverter`, price-history trigger, RPCs, sync columns, date decoding.
- [`./06-design-system.md`](./06-design-system.md) — Formatting/i18n, chart palette, accessibility.
- [`./09-engineering-practices.md`](./09-engineering-practices.md) §3.1 — Testing strategy and the Definition of Done the test-vector index ties to.
- [`./14-visualizations-and-charts.md`](./14-visualizations-and-charts.md) — How these aggregations render as charts (the visual half of analytics).
