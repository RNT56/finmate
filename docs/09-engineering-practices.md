# Engineering Practices & Quality Gates

> The how-we-build reference for Finmate: Swift & SwiftUI conventions, the testing pyramid, Git workflow, CI/CD pipeline, code-review standards, the Definition of Done, observability, performance budgets, and dependency policy. If it isn't enforced by a gate here, it isn't a standard — it's a suggestion.

This document is **operative**: it turns the [Canonical Decisions Brief](../CLAUDE.md#3-locked-decisions-non-negotiable) and the normative docs ([`./05-data-model.md`](./05-data-model.md), [`./07-security-and-privacy.md`](./07-security-and-privacy.md), [`./12-decisions-adr.md`](./12-decisions-adr.md)) into the day-to-day mechanics of writing, testing, reviewing, and shipping code. When this doc conflicts with a normative doc, the normative doc wins — open an issue and fix this one.

Audience: senior iOS engineers **and** AI coding agents. Every rule below is meant to be machine-checkable wherever possible; the ones that aren't are spelled out so a reviewer (human or agent) can apply them consistently.

---

## 0. Ground rules in one screen

For an agent picking up a task, this is the contract. The rest of the doc explains and enforces it.

- [ ] **Language:** Swift 6 language mode, strict concurrency `complete`. No warnings on the production paths; warnings-as-errors in CI for first-party targets.
- [ ] **No force-unwraps, no force-try, no `as!`** in non-test code. `swiftlint` fails the build on violation.
- [ ] **Money is `Int64` minor units + ISO code.** Never `Double`/`Float` for money. Use the `Money` value type from `Domain`. See [`./05-data-model.md`](./05-data-model.md).
- [ ] **Views are dumb.** No networking, no SwiftData queries, no money math, no date math in a `View`. That logic lives in an `@Observable` Store/ViewModel or in `Domain`.
- [ ] **Stores call repository *protocols*, never concrete Supabase/SwiftData types.** See [`./03-architecture.md`](./03-architecture.md).
- [ ] **All pure logic is unit-tested:** money math, currency conversion, analytics aggregation, CSV import parsing, date/billing-period rollover. No PR merges that reduces coverage of these modules.
- [ ] **DesignSystem components have snapshot tests** (light + dark, Dynamic Type XXL, RTL where relevant).
- [ ] **Conventional Commits**, trunk-based, PR into protected `main`, all required checks green.
- [ ] **Update the docs and the task backlog** in the same PR as the behavior change. Documentation-as-code is a merge gate, not an afterthought.
- [ ] **No secrets in the bundle or the repo.** Only the Supabase public anon key ships. Gitleaks blocks the rest.

---

## 1. Swift style & conventions

We follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) as the baseline and tighten them with the rules below. Formatting is mechanical (`swift-format`); style judgments are enforced by `swiftlint` plus code review.

### 1.1 Naming

| Kind | Convention | Example |
|------|-----------|---------|
| Types (struct/class/enum/actor/protocol) | `UpperCamelCase` | `SubscriptionStore`, `MoneyFormatter`, `SubscriptionRepository` |
| Protocols describing a capability | `…ing`/`…able` or noun-of-role | `SubscriptionRepository`, `CurrencyConverting`, `Cacheable` |
| Functions, methods, properties, cases | `lowerCamelCase` | `monthlyEquivalent(in:)`, `amountMinor`, `case yearly` |
| Constants (incl. static) | `lowerCamelCase` (no SCREAMING_SNAKE) | `static let satsPerBTC: Int64 = 100_000_000` |
| Generic params | single capital or descriptive | `Element`, `Repo` |
| Files | match the primary type | `SubscriptionStore.swift`, `Money.swift` |
| Test files | `<TypeUnderTest>Tests.swift` | `MoneyTests.swift`, `CSVImporterTests.swift` |
| SwiftData models | the domain noun | `SubscriptionEntity` (persistence) distinct from `Subscription` (domain) |

Rules:

- **No abbreviations** except the universally understood (`url`, `id`, `min`, `max`, `btc`, `eur`, `usd`, `rls`, `rpc`). Spell out `subscription`, not `sub`; `expense`, not `exp`.
- **Booleans read as assertions:** `isFavorite`, `autoRenew`, `biometricLockEnabled`, `hasPendingWrites`. This is the canonical fix for Substimate's `favorite` vs `isFavorite` duality — pick `isFavorite` in Swift, `favorite` in Postgres (see column mapping in [`./05-data-model.md`](./05-data-model.md)).
- **Domain field names are canonical and singular.** No `amount` vs `monthlyCost` duality (Substimate's bug). The money field is always `amountMinor: Int64`.
- **Mapping convention:** Postgres `snake_case` ↔ Swift `camelCase`. Use `CodingKeys` or a `JSONDecoder` with `.convertFromSnakeCase`; pick one per target and document it. Repository implementations own the mapping; domain types never carry `CodingKeys` for the wire format if it leaks DB concerns.

### 1.2 File & module organization

The repository is modular via local Swift Packages (SPM). The module graph and dependency rules are defined in [`./03-architecture.md`](./03-architecture.md); this section governs what goes *inside* a file/module.

```
finmate/
├── App/                       # thin app target — composition root only
│   └── FinmateApp.swift       # @main, DI wiring, root TabView
├── Packages/
│   ├── DesignSystem/          # tokens, Liquid Glass primitives, components, charts
│   ├── DataLayer/             # Supabase wrapper, repo protocols + impls, sync, cache
│   ├── Domain/                # entities, value types, Money, pure logic
│   ├── Shared/                # formatting, currency, logging, feature flags
│   └── Features/
│       ├── Auth/  Home/  Subscriptions/  CashFlow/  CostTracker/
│       ├── Calendar/  Import/  Assets/  Calculator/  Settings/
└── ...
```

Per-file rules:

- **One primary type per file.** Small supporting types (a private `enum`, a `CodingKeys`) may share the file. If a second type grows past ~30 lines, extract it.
- **Target file length budget:** soft cap **400 lines**, hard cap **600** (enforced by `swiftlint file_length`). A 600-line View file is a refactor, not a feature.
- **`// MARK:` section ordering** inside a type: stored properties → init → public API → private helpers → nested types. `swiftlint` `type_contents_order` warns on egregious violations.
- **`internal` is the default access level.** Only mark `public` what a module genuinely exports. `Domain` and `DesignSystem` have the largest public surface; `Features/*` export almost nothing to each other (they don't depend on each other — see [`./03-architecture.md`](./03-architecture.md)).
- **No `import Supabase` outside `DataLayer`.** No `import SwiftData` outside `DataLayer`. No `import SwiftUI` inside `Domain`. These are enforced by a custom `swiftlint` `forbidden_import` rule (see §10) and by the package manifests not declaring the dependency.

### 1.3 No force-unwraps, ever (on production paths)

`!` force-unwrap, `try!`, `as!`, and `fatalError()` in shipping code are build failures. Replacements:

```swift
// ❌ Forbidden
let user = session.user!
let amount = Int64(rawString)!
let sub = response.first as! Subscription

// ✅ Required
guard let user = session.user else { throw AuthError.notAuthenticated }
guard let amount = Int64(rawString) else { throw ImportError.invalidAmount(rawString) }
guard let sub = response.first else { return nil }
```

Allowed exceptions, each requiring a `// swiftlint:disable:next force_unwrapping` with a one-line justification:

- Statically-known resource literals that are a programmer error if missing, e.g. `Bundle.module.url(forResource:withExtension:)` in tests, or a compile-time-validated regex. Prefer the `Regex` literal (`/…/`) which is checked at compile time over `try! NSRegularExpression(...)`.
- `IndexPath`/`UUID()` constructions that cannot fail.

In **tests**, `#require` (Swift Testing) and `XCTUnwrap` are the sanctioned unwrap; bare `!` is still discouraged but not gated.

### 1.4 Error handling

- **Typed throws** (Swift 6) for module-boundary errors. Each layer defines its own error enum: `AuthError`, `RepositoryError`, `ImportError`, `SyncError`, `MoneyError`.

  ```swift
  enum ImportError: Error, Equatable {
      case unreadableFile(URL)
      case malformedHeader(expected: [String], found: [String])
      case invalidAmount(row: Int, raw: String)
      case unknownCurrency(row: Int, code: String)
      case emptyFile
  }

  func parse(_ data: Data) throws(ImportError) -> ImportPreview { ... }
  ```

- **No silent `try?` that discards errors** on a path the user cares about. `try?` is allowed only where `nil` is a meaningful, handled outcome and a comment says so.
- **Never swallow with empty `catch {}`.** At minimum log via `OSLog` at `.error` and surface a typed error or a user-facing toast.
- **Errors crossing into the UI** are mapped to a `UserFacingError` with a localized title/message and an optional retry action. Raw `RepositoryError`/`SyncError` are never shown to users.
- **`Result` is for stored/passed-around outcomes; `throws` is for call sites.** Don't mix gratuitously.

### 1.5 Concurrency rules (Swift 6 strict)

The whole app builds with `SWIFT_STRICT_CONCURRENCY=complete` and Swift 6 language mode. No `@preconcurrency` shims on first-party code; they are tolerated only on third-party imports and must carry a tracking task in [`./10-task-backlog.md`](./10-task-backlog.md).

- **UI state is `@MainActor`.** Every `@Observable` Store/ViewModel and every SwiftUI `View` is `@MainActor` (Views are implicitly main-actor-isolated in Swift 6). Annotate Stores explicitly:

  ```swift
  @MainActor
  @Observable
  final class SubscriptionsStore {
      private(set) var subscriptions: [Subscription] = []
      private(set) var phase: LoadPhase = .idle
      private let repository: any SubscriptionRepository

      init(repository: any SubscriptionRepository) { self.repository = repository }

      func load() async {
          phase = .loading
          do {
              subscriptions = try await repository.all()
              phase = .loaded
          } catch {
              phase = .failed(UserFacingError(error))
              Log.subscriptions.error("load failed: \(error)")
          }
      }
  }
  ```

- **Off-main work lives behind `async` repository calls** that hop to background executors internally. The Store `await`s; it never blocks the main thread. Heavy CPU (CSV parsing, analytics aggregation over thousands of rows) runs in a `nonisolated`/detached context or a dedicated actor, returning `Sendable` results.
- **Shared mutable state is an `actor`** (e.g. an in-memory cache, the rate-limit bookkeeper for the market-data Edge Function client). No locks, no `DispatchQueue` for mutual exclusion in new code.
- **Everything crossing an actor boundary is `Sendable`.** Domain value types are `struct` + `Sendable` by construction (immutable, value semantics). Reference types that must cross boundaries are `final` + `Sendable` with documented immutability, or are actors.
- **No `Task { }` fire-and-forget that mutates shared state without await/structured handling.** Prefer `.task {}` view modifiers (auto-cancelled on disappear) and structured `async let` / `TaskGroup`. Detached tasks (`Task.detached`) require a justification comment.
- **Cancellation is respected:** long operations check `Task.isCancelled` / use cancellation-aware APIs. The `.task(id:)` modifier is used so navigation changes cancel stale loads.
- **No `DispatchQueue.main.async` in new code** — use `await MainActor.run` only where a non-isolated callback (e.g. an old delegate) forces it, and prefer redesigning to `@MainActor`.

### 1.6 Observation usage

We use the **Observation framework** (`@Observable`), never `ObservableObject`/`@Published`/`Combine` for view state (ADR-documented in [`./12-decisions-adr.md`](./12-decisions-adr.md)).

- `@Observable final class XStore` for view-model state. Expose mutable-from-outside state as `private(set)` and mutate through methods (unidirectional flow).
- `@State private var store = XStore(...)` when the View **owns** the store's lifetime; `@Environment(XStore.self)` when it's injected; `@Bindable var store` when a child needs two-way bindings into an observable.
- Don't sprinkle `@State` for data that belongs in a store. View-local ephemeral UI state (e.g. `@State private var isSheetPresented`) stays in the View; domain/data state does not.
- No `objectWillChange`, no manual `Combine` pipelines for app state. Combine may appear only if a third-party API forces it, isolated inside `DataLayer`.

---

## 2. SwiftUI conventions

The visual language and component catalog are owned by [`./06-design-system.md`](./06-design-system.md). This section is about *structure*, not *style*.

- **Small views.** A `View`'s `body` over ~60 lines, or nesting deeper than ~4 levels, is decomposed into child views or `@ViewBuilder` computed properties. Prefer many small `View` structs over one giant `body`.
- **No business logic in views.** A View may format already-computed values for display and read store state. It must not: call the network, run a SwiftData fetch, compute a monthly-equivalent from a billing period, sum a category total, or parse a date. That belongs in the store or `Domain`.
- **Use the design system.** Colors, spacing, typography, glass surfaces, and buttons come from `DesignSystem` tokens and components (`GlassCard`, `.glassButtonStyle()`, `Theme.spacing.md`, `Theme.color.surface`). Do **not** hard-code `Color(red:…)`, magic paddings, or `.font(.system(size: 17))`. A `swiftlint` custom rule flags raw `Color(` and numeric font sizes in `Features/*`.
- **Liquid Glass with graceful fallback.** Use the design-system wrappers (which branch on `if #available(iOS 26, *)` to `glassEffect`/`GlassEffectContainer` else `.regularMaterial`/`.ultraThinMaterial`). Feature code never writes `glassEffect` directly — it consumes the wrapper. See [`./06-design-system.md`](./06-design-system.md).
- **Previews are mandatory for every View** and use mock repositories / sample data from a `PreviewData` fixture. Each non-trivial component gets previews for: light, dark, Dynamic Type `.accessibility3` (XXL), and (where text-direction-sensitive) RTL.

  ```swift
  #Preview("Light") {
      SubscriptionRow(subscription: .preview)
          .padding()
  }
  #Preview("Dark – XXL") {
      SubscriptionRow(subscription: .preview)
          .padding()
          .environment(\.colorScheme, .dark)
          .environment(\.dynamicTypeSize, .accessibility3)
  }
  ```

- **Navigation** uses `NavigationStack` + typed `NavigationPath` + the lightweight router/coordinator (see [`./03-architecture.md`](./03-architecture.md)). Views declare destinations via `navigationDestination(for:)`; they don't construct sibling-feature views directly.
- **Accessibility is not optional** (first-class per the brief): every interactive element has a label/hint where the visual isn't self-describing; respect `\.dynamicTypeSize`, `\.accessibilityReduceMotion` (gate animations), and contrast. Charts expose `.accessibilityChartDescriptor`. This is reviewed and partially snapshot-tested.
- **Localization-ready:** all user-facing strings via `String(localized:)` / `LocalizedStringKey` and a `Localizable.xcstrings` catalog, even though v1 ships English first. No string concatenation for sentences; use interpolation with format args.

---

## 3. Testing strategy & the pyramid

Substimate shipped **zero automated tests** (no test runner in `package.json`, no `*.test.*` files — verified against the reference repo). Finmate treats that as a defect to never repeat. Tests are a merge gate.

We use **Swift Testing** (the `@Test`/`#expect`/`#require` macro framework) for new unit and integration tests, with **XCTest** retained where the tooling requires it (XCUITest UI tests, and any API not yet covered by Swift Testing). **swift-snapshot-testing** (pointfreeco) covers the design system.

```
            ╱╲          XCUITest — critical user journeys (few, slow, high-value)
           ╱  ╲         ~5–10 flows
          ╱────╲
         ╱      ╲       Snapshot tests — DesignSystem components
        ╱        ╲      (light/dark, Dynamic Type, RTL)
       ╱──────────╲
      ╱            ╲    Integration tests — repositories against fakes,
     ╱              ╲   sync engine, mappers, Edge Function client (mocked transport)
    ╱────────────────╲
   ╱                  ╲ Unit tests — ALL pure logic (the wide base):
  ╱____________________╲ money, currency, analytics, CSV import, dates, billing rollover
```

### 3.1 What MUST be unit-tested (non-negotiable)

These modules have the highest correctness stakes and were exactly where Substimate had bugs. **A PR that touches them without tests does not pass review.**

- [ ] **Money math** (`Domain.Money`): construction via `init(minorUnits:currency:)`, arithmetic (`adding(_:)` throwing `MoneyError.currencyMismatch`, subtraction, scaling), `parse(_:currency:)` (HALF-UP rounding, negative-rejection, over-precision rejection, `Int64` overflow guard), rounding policy, equality, formatting per locale/currency, satoshi handling (`satsPerBTC = 100_000_000`). The named cases — mixed-currency throws (no crash), HALF-UP parse, negative rejected, excess-fraction rejected, overflow guarded — are in `MoneyTests` (§3.2). Property-based where feasible: `(a + b) - b == a`, no precision loss.
- [ ] **Currency conversion** (`Domain.CurrencyConverter`): fiat↔fiat via rate table, fiat↔BTC↔sats, rounding direction, unknown-currency error, identity conversion is a no-op. **Regression guard for the Substimate bug**: a value created in USD is *stored and read back in USD* — conversion is a *display* operation, never a *storage* mutation. Add an explicit test named `test_amount_is_never_silently_converted_before_storage`.
- [ ] **Analytics aggregation** (`Domain`/feature analytics): monthly trend bucketing, category distribution sums to total, lifetime cost from start date + billing period, payment-method breakdown, usage-state stats. Edge cases: empty data, single item, items spanning month/quarter/year boundaries, leap years, DST-crossing dates.
- [ ] **CSV import parsing** (`Features/Import` + `Domain`): header detection, delimiter handling, quoted fields with embedded commas/newlines, currency/amount parsing into `Int64` minor units, malformed-row reporting (row index + reason), empty file, BOM handling, preview generation, dedupe. Each `ImportError` case has a triggering test.
- [ ] **Billing-period / payday date logic** (`Domain`): next-payment computation for weekly/monthly/quarterly/yearly, month-end clamping (Jan 31 + 1 month → Feb 28/29), `one_time` handling, calendar generation for the payday view.

### 3.2 What to mock — and what not to

- **Mock repository protocols, not Supabase.** Stores and feature logic are tested against `InMemorySubscriptionRepository`, `FakeCurrencyRepository`, etc., conforming to the same protocols (`any SubscriptionRepository`) the real implementations do. This is the entire point of the protocol layer in [`./03-architecture.md`](./03-architecture.md).
- **Mock the network transport, not the SDK semantics**, when testing `DataLayer` implementations: inject a `URLProtocol` stub or a fake `PostgrestClient`-shaped seam so mapping/error handling is covered without hitting Supabase.
- **Do not mock pure logic.** `Money`, `CurrencyConverter`, analytics, and the CSV parser are tested directly with real inputs — no mocks, no fakes.
- **SwiftData cache** is tested with an in-memory `ModelContainer` (`isStoredInMemoryOnly: true`), not mocked.
- **Edge Function market-data client** is tested with a stubbed transport returning canned JSON; we assert the client never embeds secrets and handles non-200/timeout/garbage responses.

```swift
import Testing
@testable import Domain

@Suite("Money")
struct MoneyTests {
    @Test("addition stays exact in minor units")
    func additionExact() throws {
        let a = Money(minorUnits: 1_999, currency: .usd)   // $19.99
        let b = Money(minorUnits: 1,     currency: .usd)   // $0.01
        #expect(try a.adding(b) == Money(minorUnits: 2_000, currency: .usd))
    }

    @Test("mixing currencies throws (no crash)")
    func mixedCurrencyThrows() {
        let usd = Money(minorUnits: 100, currency: .usd)
        let eur = Money(minorUnits: 100, currency: .eur)
        // adding(_:) throws MoneyError.currencyMismatch — it never preconditions/crashes.
        #expect(throws: MoneyError.currencyMismatch(.usd, .eur)) {
            try usd.adding(eur)
        }
    }

    @Test("sats round-trip", arguments: [0, 1, 100_000_000, 250_000_000])
    func satsRoundTrip(sats: Int64) {
        let btc = Money(minorUnits: sats, currency: .btc)
        #expect(btc.minorUnits == sats)
    }

    @Test("parse rounds HALF-UP to currency precision")
    func parseRoundsHalfUp() throws {
        // 2 fractional digits for USD; 1.005 → 1.01 (half-up), not 1.00.
        #expect(try Money.parse("1.005", currency: .usd) == Money(minorUnits: 101, currency: .usd))
    }

    @Test("parse rejects negative input for amount fields")
    func parseRejectsNegative() {
        #expect(throws: MoneyError.self) {
            _ = try Money.parse("-5.00", currency: .usd)
        }
    }

    @Test("parse rejects more fractional digits than the currency allows")
    func parseRejectsExcessFraction() {
        // USD allows 2 fractional digits; 1.234 is over-precise and is rejected.
        #expect(throws: MoneyError.self) {
            _ = try Money.parse("1.234", currency: .usd)
        }
    }

    @Test("parse guards Int64 overflow")
    func parseGuardsOverflow() {
        #expect(throws: MoneyError.self) {
            _ = try Money.parse("99999999999999999999.00", currency: .usd)
        }
    }
}
```

> **Canonical `Money` API (reconciled with [`./05-data-model.md`](./05-data-model.md) §2.2; recorded in ADR-0005 in [`./12-decisions-adr.md`](./12-decisions-adr.md)).** There is exactly one contract:
>
> - `init(minorUnits: Int64, currency: CurrencyCode)`; the stored property is `minorUnits` (not `minor`/`amountMinor` on the value type).
> - `func adding(_ other: Money) throws -> Money` **throws** `MoneyError.currencyMismatch(_, _)` on a currency mismatch — it never `precondition`s or crashes (honors the no-force-unwrap / no-crash rule, §1.3).
> - `static func parse(_ string: String, currency: CurrencyCode) throws -> Money` rounds **HALF-UP** to the currency precision, **rejects** negative input for amount fields, **rejects** input with more fractional digits than the currency allows, and **guards `Int64` overflow** — each failure is a typed `MoneyError`.
>
> The bullet/method names above are the named unit-test cases gated by §3.1.

### 3.3 Snapshot tests (DesignSystem)

- Every reusable component in `DesignSystem` (`GlassCard`, buttons, list rows, chart wrappers, the Sankey/money-flow renderer) has snapshot coverage.
- Matrix per component: **light + dark**, **default + `.accessibility3` Dynamic Type**, and RTL for text-bearing components.
- Snapshots are recorded on a **pinned simulator** (see §5.4) to avoid rendering drift; mismatches fail CI. Re-recording requires reviewer sign-off and shows the image diff in the PR.

### 3.4 UI tests (XCUITest)

Few, high-value, stable. The critical journeys we keep green:

- [ ] Sign in with Apple / email-password → onboarding (currency + appearance + optional biometric) → land on Home.
- [ ] Add a subscription → it appears in the list and on the Calendar → analytics update.
- [ ] CSV import: pick file → preview shows parsed rows + flagged errors → confirm → rows persisted.
- [ ] Offline write then reconnect: create item offline, observe optimistic insert, confirm it syncs (against a local Supabase or a stubbed backend in a UI-test scheme).
- [ ] Biometric app-lock gate appears on cold launch when enabled.

UI tests run on the pinned simulator, are tagged `@MainActor`, and use accessibility identifiers (never label-text matching that breaks on localization). They run on CI for PRs to `main` and nightly; they are not on the per-commit fast path if they exceed the time budget (§5.3).

### 3.5 Coverage expectations

- **`Domain`, `Shared` (money/currency/format), `Features/Import` parser, analytics: ≥ 90% line coverage**, and 100% of `ImportError`/`MoneyError`/`CurrencyError` cases exercised.
- **`DataLayer` (mappers, repositories, sync): ≥ 75%.**
- **`Features/*` stores/view-models: ≥ 70%** (logic paths; Views excluded from the line-coverage bar but covered by snapshots/UI tests).
- **Overall project floor: 70%**, measured by `xccov`. CI publishes coverage; a PR that drops a gated module below its floor fails. Views, generated code, and previews are excluded from the denominator via an `xccov`/`slather` ignore list.

> Coverage is a floor and a smoke detector, not a goal. 90% coverage of money math with no overflow/rounding tests is worthless; reviewers check that the *meaningful* cases are there, not just the line count.

---

## 4. Git workflow

**Trunk-based development.** `main` is always releasable and is protected. No long-lived feature branches.

### 4.1 Branching

- Branch off `main`; keep branches short-lived (target < 2 days, < ~400 changed lines).
- **Branch naming:** `<type>/<short-kebab-summary>` and, when tracked, prefix the issue: `feat/subscription-price-history`, `fix/csv-import-quoted-commas`, `chore/swiftlint-config`, `docs/09-engineering-practices`. Types mirror Conventional Commits (§4.2).
- Rebase onto `main` before opening/merging a PR; we keep a linear history (`--ff-only` merges, or squash-merge — see §4.4). No merge commits from `main` into the branch.

### 4.2 Commits — Conventional Commits

Format: `type(scope): subject`, imperative mood, ≤ 72-char subject, body explains *why*.

```
feat(subscriptions): add price-history trigger sync
fix(import): handle quoted fields containing commas and newlines
refactor(datalayer): extract MoneyMapper from SubscriptionRepository
test(domain): cover satoshi round-trip and overflow guards
docs(roadmap): mark M2 CSV import acceptance criteria
chore(ci): pin gitleaks-action to v3
perf(charts): memoize Sankey layout computation
```

Allowed `type`s: `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `chore`, `build`, `ci`, `style`, `revert`. Scopes are the module/feature names (`subscriptions`, `import`, `datalayer`, `designsystem`, `domain`, `ci`, `security`, …). A `commitlint`-style check (or a lightweight CI script) validates commit/PR-title format. `feat:`/`fix:` map to minor/patch in any future automated changelog; `BREAKING CHANGE:` footer for contract breaks (rare; usually paired with an ADR).

### 4.3 Pull requests

Every change lands via PR. PR title follows Conventional Commits (it becomes the squash-commit subject). The PR template (`.github/pull_request_template.md`):

```markdown
## What & why
<!-- One paragraph. Link the task in docs/10-task-backlog.md and any ADR. -->
Closes #___  ·  Backlog: docs/10-task-backlog.md#___  ·  ADR: docs/12-decisions-adr.md#___

## Changes
- 

## Screenshots / recordings
<!-- Required for any UI change: light + dark. Drop snapshot diffs if applicable. -->

## Testing
- [ ] Unit tests added/updated for changed pure logic
- [ ] Snapshot tests added/updated for DesignSystem changes
- [ ] Ran the affected critical UI flow locally
- [ ] Manual test notes:

## Definition of Done (see docs/09-engineering-practices.md §6)
- [ ] No force-unwrap / force-try / `as!` on production paths
- [ ] Money is Int64 minor units; no Double/Float money
- [ ] Strict-concurrency clean; no new `@preconcurrency`/`@unchecked Sendable`
- [ ] Accessibility: Dynamic Type, VoiceOver labels, reduce-motion respected
- [ ] Security: no secrets added; RLS/ownership honored for any data access
- [ ] Docs updated (relevant /docs file) and task backlog updated
- [ ] No new dependency, or new dependency justified below per §11

## New dependencies (if any)
<!-- name, version, license, why, alternatives considered -->
```

PR rules:

- **Keep PRs small and single-purpose.** Mixing a refactor with a feature is grounds for a split request.
- Draft PRs early for visibility; mark ready when CI is green and the DoD is satisfied.
- The author resolves all CI failures before requesting review.

### 4.4 Protected `main` & required checks

`main` branch protection (GitHub):

- [ ] Require a pull request before merging; **≥ 1 approving review**; dismiss stale approvals on new commits.
- [ ] Require **all status checks** to pass and branches to be up to date before merge.
- [ ] Require **linear history** (squash-merge as the default merge method; squash subject = PR title in Conventional-Commit form).
- [ ] Require **conversation resolution** before merge.
- [ ] No force-push, no deletion of `main`. Admins included (no bypass without a logged reason).
- [ ] **Required checks (must be green):** `lint` (SwiftLint), `format-check` (swift-format `--lint`), `build`, `test` (unit + snapshot + coverage gate), `db-rls-regression` (migrations + pgTAP RLS/definer suite, §5.6), `secret-scan` (Gitleaks), `dependency-review`, `commit-lint`. UI tests run as a required nightly + pre-release check; on PRs they're required only on the `release/*` path if they exceed the per-PR time budget.

---

## 5. CI/CD pipeline

GitHub Actions for build/test/lint on macOS runners; **Fastlane** for build/sign/distribute; **TestFlight** for beta. **Xcode Cloud is the documented alternative** (ADR in [`./12-decisions-adr.md`](./12-decisions-adr.md)) if Actions macOS minutes become the bottleneck. Substimate's `ci.yml` (lint → typecheck → build → `npm audit` → Gitleaks) is the spiritual ancestor; Finmate's is the Swift/Xcode analogue.

### 5.1 Pipeline stages

```mermaid
flowchart LR
    A[Checkout] --> B[Resolve SPM\n+ cache]
    B --> C[swift-format --lint]
    B --> D[SwiftLint --strict]
    C --> E[Build\n(strict concurrency, warnings = errors)]
    D --> E
    E --> F[Unit + Snapshot tests\n+ coverage gate]
    A --> G[Gitleaks secret scan]
    A --> H[Dependency review]
    A --> I[Commit/PR-title lint]
    A --> N[DB & RLS regression\nsupabase db reset + pgTAP]
    F --> J{All green?}
    G --> J
    H --> J
    I --> J
    N --> J
    J -->|PR to main| K[Mergeable]
    J -->|push to main| L[Fastlane beta → TestFlight]
    J -->|nightly / release/*| M[XCUITest matrix]
```

Stage detail:

1. **Checkout** (`actions/checkout@v4`).
2. **Toolchain + cache:** select Xcode 26 (`xcodes`/`xcode-select`), cache `~/Library/Caches/org.swift.swiftpm` and the SPM build by `Package.resolved` hash.
3. **format-check:** `swift-format lint --recursive --strict .` — non-zero exit fails.
4. **lint:** `swiftlint lint --strict` — warnings are failures in CI.
5. **build:** `xcodebuild build-for-testing` with `SWIFT_STRICT_CONCURRENCY=complete`, `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` for first-party targets, on the pinned destination.
6. **test:** `xcodebuild test-without-building` → unit + snapshot. Generate `xcresult`, convert with `xccov`, enforce per-module coverage floors (§3.5); upload coverage + the `xcresult` as artifacts (e.g. via `xcresulttool`/`xcparse`).
7. **secret-scan:** `gitleaks/gitleaks-action@v3` with a tuned `.gitleaks.toml` (the only permitted "secret" pattern is the public anon key, which is not a secret; everything else fails).
8. **dependency-review:** GitHub `actions/dependency-review-action@v4` on PRs (license + known-vuln gate); plus an SPM advisory check.
9. **commit-lint:** validate Conventional-Commit format of commits/PR title.
10. **db-rls-regression:** apply all migrations to an ephemeral Postgres (`supabase db reset`) and run the pgTAP/`pg_prove` RLS + `SECURITY DEFINER` regression suite (§5.6).

These are independent jobs where possible (lint/format/secret-scan/dependency-review/db-rls-regression run in parallel with build) to keep wall-clock low.

### 5.2 Example workflow skeleton

```yaml
name: CI
on:
  pull_request:
  push:
    branches: [main]
permissions:
  contents: read
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  static-checks:
    runs-on: macos-15        # Apple-silicon runner with Xcode 26
    steps:
      - uses: actions/checkout@v4
      - run: sudo xcode-select -s /Applications/Xcode_26.app
      - name: swift-format lint
        run: swift-format lint --recursive --strict .
      - name: SwiftLint
        run: swiftlint lint --strict

  build-test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - run: sudo xcode-select -s /Applications/Xcode_26.app
      - name: Cache SPM
        uses: actions/cache@v4
        with:
          path: ~/Library/Caches/org.swift.swiftpm
          key: spm-${{ hashFiles('**/Package.resolved') }}
      - name: Build & test
        run: |
          xcodebuild test \
            -scheme Finmate \
            -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.4' \
            -enableCodeCoverage YES \
            SWIFT_STRICT_CONCURRENCY=complete \
            SWIFT_TREAT_WARNINGS_AS_ERRORS=YES | xcbeautify
      - name: Coverage gate
        run: ./scripts/coverage-gate.sh   # parses xccov, enforces §3.5 floors

  secret-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: gitleaks/gitleaks-action@v3
        env: { GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }} }

  dependency-review:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/dependency-review-action@v4
        with: { fail-on-severity: moderate }
```

### 5.3 Performance of the pipeline

- **PR fast path target: < 12 min wall-clock.** If exceeded, move XCUITest to nightly/`release/*`, parallelize test bundles, and tighten SPM caching.
- `concurrency.cancel-in-progress` cancels superseded runs on a branch.

### 5.4 Pinned environment

Reproducibility matters for snapshots and concurrency behavior. Pin and document:

- **Xcode 26.x** (exact version in `.xcode-version` and the workflow).
- **Simulator: iPhone 16 Pro, iOS 18.4** for snapshot + UI tests (snapshots are device/OS-sensitive). Record this in the snapshot test config.
- macOS runner image pinned (`macos-15`), not `macos-latest`.

### 5.5 Fastlane lanes & TestFlight

`fastlane/Fastfile` (signing via the App Store Connect API key + `fastlane match` — see §5.7 for the credential/code-signing decision):

```ruby
default_platform(:ios)

platform :ios do
  desc "Lint, build, and run unit + snapshot tests"
  lane :test do
    swiftlint(strict: true)
    run_tests(scheme: "Finmate", devices: ["iPhone 16 Pro (18.4)"], code_coverage: true)
  end

  desc "Build a signed beta and upload to TestFlight"
  lane :beta do
    setup_ci
    increment_build_number(build_number: latest_testflight_build_number + 1)
    build_app(scheme: "Finmate", export_method: "app-store")
    upload_to_testflight(
      distribute_external: false,
      changelog: File.read("../CHANGELOG_TESTFLIGHT.md"),
      skip_waiting_for_build_processing: true
    )
  end

  desc "Promote a TestFlight build to App Store review"
  lane :release do
    deliver(
      submit_for_review: true,
      automatic_release: false,
      force: true,
      precheck_include_in_app_purchases: false
    )
  end
end
```

- **`beta` runs on every successful push to `main`** (continuous delivery to internal testers). Version = marketing version; build number auto-incremented.
- **`release` is manual**, triggered from a `release/*` branch tag, after the full UI-test matrix is green.
- App Store Connect API key, signing certs, and provisioning profiles are CI secrets / managed by `match` in a **separate private** repo — **never in the app repo**. The full credential set, secret names, and CI bootstrap are specified in **§5.7**. This is part of the security posture in [`./07-security-and-privacy.md`](./07-security-and-privacy.md).

### 5.6 Database & RLS regression gate {#database-rls-regression-gate}

The security controls in [`./05-data-model.md`](./05-data-model.md) and [`./07-security-and-privacy.md`](./07-security-and-privacy.md) — Row-Level Security enabled **and forced** on every table, per-user data isolation, and hardened `SECURITY DEFINER` functions — are only real if a gate enforces them. A dedicated CI job, `db-rls-regression`, runs the migrations against an **ephemeral Postgres** and executes pgTAP/`pg_prove` assertions. This job is the canonical migration-test gate that [`./07-security-and-privacy.md`](./07-security-and-privacy.md) references for RLS/definer enforcement.

What the job does, in order:

1. Spin up a throwaway local Supabase stack and apply all migrations from a clean slate: `supabase db reset` (drops, recreates, re-runs every migration + seed against the ephemeral Postgres).
2. Run the pgTAP suite under `pg_prove`, asserting at minimum:
   - **RLS enabled *and* forced on every table** — for each `public` table, `relrowsecurity` AND `relforcerowsecurity` are both true (catches a table that is `ENABLE`d but not `FORCE`d, or a new table added with neither).
   - **Cross-user isolation** — seed two users (A and B); as user B, every owner-scoped table returns **zero rows** of user A's data (`SELECT`, `UPDATE`, `DELETE` affect nothing), proving the `user_id = auth.uid()` policies hold.
   - **Hardened definer functions** — every `SECURITY DEFINER` function (`seed_default_categories`, `handle_new_user`, `set_updated_at`, `prevent_user_id_change`, …) has `search_path` pinned to `public`, has `REVOKE ALL ... FROM PUBLIC` (not granted to `authenticated`), and exposes **no caller-supplied `uid`/`user_id` argument** (identity comes from the trigger context, never a client argument).
3. Fail the build on any assertion failure; publish the `pg_prove` TAP output as a CI artifact.

```yaml
  db-rls-regression:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: supabase/setup-cli@v1
        with: { version: latest }
      - name: Start ephemeral Postgres + apply all migrations
        run: supabase db reset            # clean slate: every migration + seed
      - name: Install pgTAP harness
        run: |
          sudo apt-get update && sudo apt-get install -y libtap-parser-sourcehandler-pgtap-perl postgresql-client
          # pgTAP extension is created by a migration / `CREATE EXTENSION pgtap;`
      - name: Run RLS + SECURITY DEFINER regression tests
        run: pg_prove --ext .sql -d "$SUPABASE_DB_URL" supabase/tests/rls/
        # asserts: RLS enabled AND forced on every table; user B reads 0 rows of user A;
        # every SECURITY DEFINER fn has search_path pinned + REVOKE PUBLIC + no caller-supplied uid arg
```

This job runs on every PR and on pushes to `main`, in parallel with the other static checks, and is a **required check** on protected `main` (§4.4). Any migration that adds a table without `ENABLE`+`FORCE` RLS, weakens a user-isolation policy, or introduces an unhardened definer function fails here before it can merge.

### 5.7 Code signing & CI credentials {#code-signing-ci-credentials}

> **Decision (binding):** Finmate signs and ships with an **App Store Connect API key** (`.p8`, key-based auth — no 2FA-bound Apple ID in CI) plus **`fastlane match`**, which stores the signing certificates and provisioning profiles **encrypted in a separate, private Git repository**. This supersedes the earlier "match/manual per the team" indecision; recorded in [`./12-decisions-adr.md`](./12-decisions-adr.md) and reflected in [`./04-tech-stack.md`](./04-tech-stack.md) (which previously punted code signing). It satisfies the "signing material never lives in the app repo" requirement of [`./07-security-and-privacy.md`](./07-security-and-privacy.md).

Why this combination:

- **API key over an Apple ID:** an `.p8` key is non-interactive, scoped, and revocable; it avoids storing an Apple ID password or a fragile 2FA session token in CI.
- **`match` over manual profiles:** one source of truth for certs/profiles across every machine and CI runner, encrypted at rest, regenerated reproducibly. No "works on my Mac" signing drift.

**Exact CI secrets** (set in GitHub Actions repository/organization secrets; mirrored to Fastlane env). None of these are ever committed:

| Secret | What it is | Used by |
|--------|-----------|---------|
| `ASC_KEY_ID` | App Store Connect API **Key ID** | `app_store_connect_api_key` |
| `ASC_ISSUER_ID` | App Store Connect API **Issuer ID** | `app_store_connect_api_key` |
| `ASC_KEY_P8` | The `.p8` private key, **base64-encoded** (decoded at runtime; never written to a tracked path) | `app_store_connect_api_key` |
| `MATCH_PASSWORD` | Passphrase that decrypts the `match` certificate/profile repo | `match` |
| `MATCH_GIT_URL` | URL of the **private** `match` storage repo | `match` |
| `MATCH_GIT_BASIC_AUTHORIZATION` | Base64 `user:token` for read access to the `match` repo from CI | `match` |

**Fastlane wiring** (`Appfile`/`Fastfile`) reads the API key once and uses `match(readonly: true)` on CI so runners **consume** signing material but never **regenerate/rotate** it (rotation is a deliberate local action by a maintainer):

```ruby
# Fastfile — shared signing setup
def asc_api_key
  app_store_connect_api_key(
    key_id: ENV.fetch("ASC_KEY_ID"),
    issuer_id: ENV.fetch("ASC_ISSUER_ID"),
    key_content: ENV.fetch("ASC_KEY_P8"),   # base64; Fastlane decodes with is_key_content_base64
    is_key_content_base64: true,
    in_house: false
  )
end

platform :ios do
  before_all do
    setup_ci if ENV["CI"]                    # ephemeral temp keychain on the runner
  end

  lane :beta do
    api_key = asc_api_key
    match(type: "appstore", readonly: ENV["CI"] == "true")   # readonly on CI: never mints new certs
    increment_build_number(build_number: latest_testflight_build_number(api_key: api_key) + 1)
    build_app(scheme: "Finmate", export_method: "app-store")
    upload_to_testflight(api_key: api_key, distribute_external: false,
                         changelog: File.read("../CHANGELOG_TESTFLIGHT.md"),
                         skip_waiting_for_build_processing: true)
  end
end
```

**CI bootstrap** — the two lines that make the runner sign correctly:

```ruby
setup_ci                       # creates a temporary, throwaway keychain (no human login)
match(type: "appstore", readonly: true)   # CI only ever READS certs/profiles from the private repo
```

Operational rules:

- **`match nuke` / cert rotation is a maintainer-only local operation**, never run from CI (CI is `readonly: true`). Rotating a revoked cert is a logged, deliberate action.
- **Secret rotation:** if any secret leaks, revoke the ASC API key in App Store Connect, rotate `MATCH_PASSWORD` + the repo token, and re-encrypt the `match` repo. Treat as a security incident per [`./07-security-and-privacy.md`](./07-security-and-privacy.md).
- The `match` storage repo is **private and access-scoped**; only CI (read) and signing maintainers (read/write) can reach it.

### 5.8 Release management {#release-management}

How a build becomes a shipped App Store version, and how we pull it back if something is wrong.

**Versioning — `MAJOR.MINOR.PATCH` (SemVer-flavored marketing version) + monotonic build number.**

- **Marketing version** (`CFBundleShortVersionString`, e.g. `1.0.0`) is set per release from the `release/*` branch; `MINOR` bumps for feature releases, `PATCH` for fixes, `MAJOR` reserved for a user-visible product-level shift. It is the human-facing App Store version.
- **Build number** (`CFBundleVersion`) is **monotonically increasing and unique**, auto-incremented from `latest_testflight_build_number + 1` in the `beta` lane (§5.5). Build numbers never reset across marketing versions.
- The marketing version is the single source bumped in one place (the project/`xcconfig`); CI does not invent marketing versions.

**Channels & TestFlight groups:**

| Channel | Audience | Trigger | Fastlane |
|---------|----------|---------|----------|
| **Internal** TestFlight | The team (App Store Connect internal testers) | every green push to `main` | `beta` (`distribute_external: false`) |
| **External** TestFlight | Invited beta testers (one named "Beta" group) | a `release/*` candidate, after UI-test matrix green | `beta` with the external group, requires Beta App Review |
| **App Store** | Public | manual promotion of a vetted build | `release` (`deliver`, `submit_for_review: true`, `automatic_release: false`) |

**Phased release is ON by default.** App Store **Phased Release for automatic updates** is enabled for every public release (the 7-day staged rollout to existing users), giving a real-world soak window. `release` sets `automatic_release: false` so the human owner controls the go-live moment; once live, phased rollout ramps automatically and **can be paused** from App Store Connect.

**Rollback / kill path** (in increasing severity):

1. **Pause the phased rollout** in App Store Connect — instantly stops further users from getting the bad version while you assess.
2. **Expedited release of a fix** — cut a `PATCH` `release/*`, ship a new higher build number; iOS has no true "un-publish to a prior binary," so *rolling forward with a fix* is the supported recovery, not downgrading users.
3. **Remove the version from sale** for a severe defect (last resort; blocks new downloads).
4. **Server-side kill switches** for anything that does **not** need a binary: feature flags and the certificate-pinning kill switch are remote-config booleans (§9.4) honored at launch — a misbehaving feature or a pinning failure is disabled **without** an App Store release. This is the fast path; the binary rollback paths above are for defects the server cannot mask.

**Release notes — single source:**

- **TestFlight ("What to Test")** is read from `CHANGELOG_TESTFLIGHT.md` by the `beta` lane (§5.5) — the canonical, in-repo source for beta notes.
- **App Store release notes** are derived from the merged Conventional-Commit history for the release range (`feat:`/`fix:` entries), curated into user-facing language, and committed alongside the release tag. Conventional Commits (§4.2) are therefore load-bearing: they feed both the changelog and the store notes.
- Release notes live in the repo (versioned with the tag), never hand-typed only into App Store Connect.

**Release checklist** (gates a `release/*` promotion): full XCUITest matrix green (§3.4); coverage floors met; `db-rls-regression` green; App Store submission mechanics satisfied (encryption declaration, age rating, reviewer demo account, review notes — see [`./07-security-and-privacy.md`](./07-security-and-privacy.md) §9.2 and milestone M8 in [`./08-roadmap-and-milestones.md`](./08-roadmap-and-milestones.md)); Privacy Policy + Terms live at their stable URLs.

---

## 6. Code review standards & Definition of Done

### 6.1 Reviewer responsibilities

A reviewer (human or AI agent) checks, in priority order:

1. **Correctness & contract conformance** — does it do what the task/acceptance criteria say, and does it honor the normative docs (data model field names/money type, RLS/ownership, security)?
2. **Concurrency safety** — no data races the compiler can't see; `@MainActor` boundaries correct; nothing blocking the main thread.
3. **Tests** — the *right* tests exist (see §3.1), not just any tests. Edge cases for money/dates/import present.
4. **Architecture** — code is in the right module; no forbidden imports; Views stay dumb; Stores talk to protocols.
5. **Design-system conformance** — uses tokens/components; Liquid Glass via the wrapper; accessibility handled.
6. **Readability & size** — small functions/views, clear names, no dead code, no commented-out code.

Reviews are **kind and specific**: prefer suggestions with code; distinguish blocking (`must`) from optional (`nit:`). Approvals require the DoD to be visibly satisfied (template checkboxes + the diff).

### 6.2 Definition of Done

A change is **Done** only when **all** of the following hold:

- [ ] Acceptance criteria from the linked task ([`./10-task-backlog.md`](./10-task-backlog.md)) / product spec ([`./02-product-spec.md`](./02-product-spec.md)) are met.
- [ ] Builds clean under Swift 6 strict concurrency; **zero warnings** on first-party targets.
- [ ] **No force-unwrap / `try!` / `as!` / `fatalError`** on production paths (or a justified, `swiftlint`-acknowledged exception).
- [ ] **Money is `Int64` minor units + currency code**; no `Double`/`Float` money anywhere; uses `Money` value type.
- [ ] Unit tests added/updated and green; gated modules meet coverage floors (§3.5); snapshot tests updated for DesignSystem changes.
- [ ] Lint (`swiftlint --strict`) and format-check (`swift-format lint --strict`) pass.
- [ ] **Accessibility:** Dynamic Type to XXL, VoiceOver labels/hints, `reduceMotion` respected, sufficient contrast.
- [ ] **Security:** no secrets added; only the anon key ships; data access honors RLS/ownership; tokens via Keychain (never `UserDefaults`); see [`./07-security-and-privacy.md`](./07-security-and-privacy.md).
- [ ] **Localization-ready:** user-facing strings in the catalog, no concatenated sentences.
- [ ] **Docs-as-code:** the relevant `/docs` file and [`./10-task-backlog.md`](./10-task-backlog.md) updated in the same PR; a new/changed binding decision recorded as an ADR in [`./12-decisions-adr.md`](./12-decisions-adr.md).
- [ ] PR is small, single-purpose, Conventional-Commit titled, CI green, ≥ 1 approval, conversations resolved.

---

## 7. Documentation-as-code

Docs are part of the change, not a follow-up.

- **Behavior or contract changes update `/docs` in the same PR.** The "which docs to touch" table in [`./00-index.md`](./00-index.md#at-a-glance-which-docs-to-touch-for-common-changes) is the routing guide: schema/RLS → [`./05-data-model.md`](./05-data-model.md) first; auth/RPC → [`./07-security-and-privacy.md`](./07-security-and-privacy.md) first; then propagate; then ADR.
- **Update the task backlog** ([`./10-task-backlog.md`](./10-task-backlog.md)): check off completed items, add discovered work, link the PR.
- **New binding decisions become ADRs** in [`./12-decisions-adr.md`](./12-decisions-adr.md) (numbered, dated, with rationale + revisit conditions). Reversing a locked decision requires an ADR, not a quiet code change.
- **Keep cross-links valid:** relative links only (`./05-data-model.md`, `../CLAUDE.md`). A docs link-checker (e.g. `lychee` or `markdown-link-check`) runs in CI to catch broken relative links.
- **Public-facing changes** (features, setup) update [`../README.md`](../README.md); agent-facing structure/decisions update [`../CLAUDE.md`](../CLAUDE.md).
- Code documents itself with `///` doc comments on public API (especially `Domain` and `DesignSystem`). Generated docs (DocC) are a post-v1 nicety, not a v1 gate.

---

## 8. Linting & formatting setup

Two complementary tools, both enforced in CI: **swift-format** (Apple's formatter — mechanical layout) and **SwiftLint** (style + correctness rules, incl. our custom rules). They are configured to not fight each other (formatting owned by swift-format; SwiftLint disables purely-formatting rules it would duplicate).

### 8.1 `.swift-format` (repo root)

```json
{
  "version": 1,
  "lineLength": 100,
  "indentation": { "spaces": 4 },
  "respectsExistingLineBreaks": true,
  "lineBreakBeforeEachArgument": true,
  "indentConditionalCompilationBlocks": false,
  "maximumBlankLines": 1,
  "rules": {
    "AlwaysUseLowerCamelCase": true,
    "NoForceUnwrapping": true,
    "OrderedImports": true,
    "UseLetInEveryBoundCaseVariable": true,
    "ReturnVoidInsteadOfEmptyTuple": true
  }
}
```

Run: `swift-format format --in-place --recursive .` locally (and via the pre-commit hook); CI runs `swift-format lint --strict`.

### 8.2 `.swiftlint.yml` (repo root)

```yaml
strict: true                       # warnings fail in CI (--strict on the CLI)
included: [App, Packages]
excluded:
  - "**/.build"
  - "**/Generated"
  - "**/*.snapshot"

opt_in_rules:
  - force_unwrapping             # ❌ no `!`
  - empty_count
  - first_where
  - explicit_init
  - closure_spacing
  - redundant_nil_coalescing
  - unused_import
  - unused_declaration
  - private_outlet
  - prohibited_super_call
  - overridden_super_call
  - sorted_imports
  - vertical_whitespace_closing_braces

disabled_rules:
  - todo                          # tracked in docs/10-task-backlog.md, not as lint noise
  - line_length                   # owned by swift-format

force_cast: error                 # ❌ no `as!`
force_try: error                  # ❌ no `try!`
force_unwrapping: error

file_length:
  warning: 400
  error: 600
type_body_length:
  warning: 300
  error: 450
function_body_length:
  warning: 50
  error: 80
cyclomatic_complexity:
  warning: 10
  error: 15

identifier_name:
  excluded: [id, x, y, db, ui, to]

custom_rules:
  no_supabase_import_outside_datalayer:
    name: "Supabase import only in DataLayer"
    regex: '^import (Supabase|PostgREST|GoTrue|Realtime)$'
    match_kinds: [keyword, identifier]
    excluded: ".*/Packages/DataLayer/.*"
    message: "Import Supabase only inside DataLayer; features use repository protocols."
    severity: error
  no_swiftdata_outside_datalayer:
    name: "SwiftData import only in DataLayer"
    regex: '^import SwiftData$'
    excluded: ".*/Packages/DataLayer/.*"
    message: "SwiftData is the cache behind repositories; keep it in DataLayer."
    severity: error
  no_double_money:
    name: "No Double/Float money"
    regex: '(amount|price|cost|value|balance|total)[A-Za-z]*\s*:\s*(Double|Float|CGFloat)'
    message: "Money is Int64 minor units. Use the Money value type, never Double/Float."
    severity: error
  no_raw_color_in_features:
    name: "No raw Color() in feature code"
    regex: 'Color\(red:|UIColor\('
    included: ".*/Packages/Features/.*"
    message: "Use DesignSystem color tokens, not raw Color()."
    severity: warning
  no_userdefaults_for_tokens:
    name: "No tokens/secrets in UserDefaults"
    regex: 'UserDefaults.*\.(set|string).*(token|secret|password|apiKey)'
    message: "Auth tokens live in the Keychain. See docs/07-security-and-privacy.md."
    severity: error
```

### 8.3 Local hooks

A `.git/hooks/pre-commit` (installed via a `scripts/install-hooks.sh`) runs `swift-format format --in-place` on staged files and `swiftlint --strict` on changed files, so violations are caught before CI. CI is the source of truth; the hook is a convenience.

---

## 9. Logging & observability

### 9.1 OSLog / `Logger`

Structured logging via `os.Logger` (unified logging), never `print()` in shipping code (`print` is flagged in review; a debug-only `Log.debug` wrapper is allowed in DEBUG builds). One `Logger` per subsystem area, defined centrally in `Shared`:

```swift
import OSLog

enum Log {
    private static let subsystem = "com.finmate.app"
    static let auth          = Logger(subsystem: subsystem, category: "auth")
    static let sync          = Logger(subsystem: subsystem, category: "sync")
    static let datalayer     = Logger(subsystem: subsystem, category: "datalayer")
    static let subscriptions = Logger(subsystem: subsystem, category: "subscriptions")
    static let importer      = Logger(subsystem: subsystem, category: "import")
    static let ui            = Logger(subsystem: subsystem, category: "ui")
}
```

- **Log levels:** `.debug` (dev only, compiled-friendly), `.info` (lifecycle), `.notice` (default-visible significant events), `.error` (recoverable failures), `.fault` (programmer errors / invariant breaks).
- **Privacy is the hard rule (no PII in logs).** OSLog redacts interpolations by default; we keep it that way. Dynamic values are `\(value, privacy: .private)` unless they are provably non-PII (e.g. an enum case, a count, a duration), in which case `\(value, privacy: .public)`. **Never log:** access/refresh tokens, email, amounts/balances, account ids, raw CSV contents. Log *shapes and counts*, not *contents* ("imported 42 rows, 3 flagged", not the rows).

### 9.2 MetricKit & crash/performance signals

- Subscribe to **MetricKit** (`MXMetricManager`) to collect daily aggregated metrics: launch time, hang rate, memory, CPU, disk writes, and crash/diagnostic payloads — all on-device, aggregated, privacy-preserving by design. Payloads are summarized to the unified log (no PII) and, post-v1, optionally forwarded to a privacy-respecting backend.
- **No third-party analytics/crash SDK that phones home with PII or trackers** (App Privacy "no tracking" is a commitment in [`./07-security-and-privacy.md`](./07-security-and-privacy.md)). If a crash service is added later it must be vetted (§11), data-minimizing, and reflected in the privacy nutrition label.
- **Signposts** (`OSSignposter`) instrument the hot paths we have budgets for (§10): app launch, first dashboard render, CSV import of N rows, Sankey layout, chart render.

**Analytics stance (explicit):** v1 ships **no product analytics** — no event tracking, no funnels, no third-party telemetry of any kind. The only signals collected are on-device, aggregated MetricKit payloads (performance/stability) and the unified log; nothing about *what the user does in the app* leaves the device. The deliberate trade-off: **activation, retention, and feature-usage metrics are unmeasured in v1.** We accept flying blind on product metrics rather than ship tracking that contradicts the privacy posture. A privacy-preserving analytics solution (e.g. aggregated, opt-in, no per-user identifiers) is a **post-v1** item; if/when it lands it goes through dependency vetting (§11), data-minimization review, and the privacy nutrition label, and is recorded as an ADR in [`./12-decisions-adr.md`](./12-decisions-adr.md).

**Support channel:** user-reported problems come through `support@finmate.app` *(placeholder — owner to confirm the support address/domain)* and an in-app **Settings → Report a problem** flow that attaches the **redacted** log archive (§9.3) on explicit user action. v1 triage is **best-effort** (no SLA); see [`./02-product-spec.md`](./02-product-spec.md) Settings for the surface.

### 9.3 In-app diagnostics

A Settings → Diagnostics screen can export a redacted log archive (sysdiagnose-style, PII-stripped) for support, gated behind explicit user action. Sensitive caches are cleared on logout (security requirement).

### 9.4 Feature flags & remote config {#feature-flags-remote-config}

Some behavior must be changeable **without** shipping a new binary — most importantly the certificate-pinning kill switch that [`./07-security-and-privacy.md`](./07-security-and-privacy.md) calls "remote-killable." This subsection makes that real.

**Source of truth: a Supabase-served `app_config`** — a single **public-readable** row (RLS allows `SELECT` to everyone, including unauthenticated, since it carries no user data and no secrets) read at app launch. For richer logic it may instead be a tiny Edge Function returning the same JSON shape; the client treats either as the same `AppConfig` value. The config is **fetched once at launch (and on foreground after a debounce), then cached locally** (e.g. in the app container, not Keychain — it is non-secret).

**Safe compile-time defaults always exist.** The fetch is best-effort: on first launch, offline, or any fetch failure, the app uses **baked-in default values** so it is never bricked by a missing/unreachable config. The remote value only ever *overrides* a known default — an unknown remote key is ignored.

**The flag registry lives in the `Shared` package** (one canonical place; `Domain`/`Features` consume it, never redefine flags):

```swift
// Shared/FeatureFlags.swift
public struct AppConfig: Sendable, Codable {
    /// Master switch for TLS certificate pinning. Default ON; flip to false (remotely)
    /// to disable pinning at launch WITHOUT a client release — the "remote-killable"
    /// control referenced by docs/07-security-and-privacy.md.
    public var certificatePinningEnabled: Bool = true

    /// Force an in-app "please update" gate when the running version is unsupported.
    public var minimumSupportedBuild: Int = 0

    /// Soft kill of the market-data path (e.g. provider outage) — show last-known rates.
    public var marketDataEnabled: Bool = true

    /// Allow CSV import (kill switch if a parsing regression ships).
    public var csvImportEnabled: Bool = true
}
```

| Flag | Default (compile-time) | Owner | Notes |
|------|------------------------|-------|-------|
| `certificatePinningEnabled` | `true` (pinning ON) | Security owner | Remote kill switch; honored at launch. Disabling needs a logged reason. |
| `minimumSupportedBuild` | `0` (no gate) | Release owner | Raises to force-update after a breaking server change. |
| `marketDataEnabled` | `true` | Backend owner | Soft-disable the Edge Function path during a provider outage. |
| `csvImportEnabled` | `true` | Feature owner | Disable import quickly if a parsing regression escapes. |

Rules:

- **Defaults are conservative and fail-safe:** security-relevant flags default to the *secure* state (`certificatePinningEnabled = true`), so a config the app never receives leaves the app in its hardened posture.
- **Flag reads go through `Shared`**, behind a small `@Observable AppConfigStore` injected at the composition root; features read the typed `AppConfig`, never raw JSON.
- **Changing a flag value is an operational action**, logged with a reason; flipping `certificatePinningEnabled` off is recorded as a security event per [`./07-security-and-privacy.md`](./07-security-and-privacy.md).
- The release rollback path (§5.8) leans on these flags as the no-binary recovery option.

---

## 10. Performance budgets

Budgets are tracked with signposts/MetricKit and spot-checked in review. Regressions beyond budget block release.

| Path | Budget | Measured by |
|------|--------|-------------|
| Cold launch → first interactive frame | **< 1.2 s** on iPhone 12-class hardware | MetricKit launch metric, signpost |
| Warm launch | < 400 ms | signpost |
| Home dashboard first render (cached data) | < 300 ms after launch | signpost |
| Tab switch / navigation push | 60 fps, no dropped frames; < 100 ms to content | Instruments, review |
| List scroll (Subscriptions, transactions) | sustained 60–120 fps, no hitches | Instruments Hitches |
| CSV import parse, 1,000 rows | < 500 ms off-main; UI never blocks | signpost, unit perf test |
| Sankey / money-flow layout, typical dataset | < 50 ms; cached/memoized between renders | signpost |
| Chart render (Swift Charts) | < 16 ms/frame during interaction | Instruments |
| Memory footprint, steady state | < 150 MB typical session | MetricKit memory metric |
| Optimistic write → visible in UI | < 16 ms (next frame); sync happens after | review, UI test |

Practices that keep us in budget: offline-first reads from the local cache (never block on the network for first paint — see [`./03-architecture.md`](./03-architecture.md)); heavy work off `@MainActor`; lazy lists (`LazyVStack`/`List`) with stable identities; memoized derived values in stores; `task(id:)` to cancel stale loads; avoid re-encoding/re-decoding on the hot path.

---

## 11. Dependency policy

**Vet, pin, minimize.** Every dependency is attack surface, build-time cost, and a future maintenance liability. The default answer to "should we add a dependency?" is *no* unless it clearly beats writing/owning the code.

### 11.1 Adding a dependency

A new SPM dependency requires, in the PR (per the template §4.3):

- **Name, exact version, license** (must be permissive: MIT/Apache-2.0/BSD; copyleft requires explicit owner approval).
- **Why** it beats the alternatives, including "write it ourselves."
- **Health check:** active maintenance, release cadence, issue responsiveness, Swift 6 / strict-concurrency readiness, transitive dependency count.
- **Blast radius:** which module depends on it (keep it as deep/narrow as possible — ideally behind an abstraction in `DataLayer`/`DesignSystem` so it can be swapped).

The `dependency-review` CI job (§5.1) blocks known-vulnerable or disallowed-license additions.

### 11.2 Pinning & updating

- **Commit `Package.resolved`.** Builds are reproducible; CI uses the resolved graph. Avoid `branch:`/`from: "0.0.0"` open ranges; pin to `.upToNextMinor(from:)` for libraries and exact versions for tooling.
- **Renovate/Dependabot** opens grouped update PRs weekly; each goes through the full pipeline. No auto-merge of dependency PRs without green CI + review.
- Periodic audit (each milestone) prunes anything unused (`unused_import` helps surface candidates).

### 11.3 The dependency allow-list (v1)

These are the only third-party packages anticipated for v1; anything else needs the §11.1 process. Versions are pins to confirm against current releases at provisioning time.

| Dependency | Purpose | Scope | Notes |
|-----------|---------|-------|-------|
| `supabase-swift` (`supabase/supabase-swift`) | Auth, PostgREST, Realtime, Storage, Edge Functions client | **DataLayer only** | Official SDK; the only place `import Supabase` is allowed. |
| `swift-snapshot-testing` (pointfreeco) | Snapshot tests for DesignSystem | test targets only | Pinned simulator (§5.4). |
| SwiftLint | Lint + custom rules | tooling/CI | Run via CLI; not linked into the app. |
| swift-format | Formatting | tooling/CI | Apple-maintained. |
| Fastlane | Build/sign/TestFlight | CI/tooling | Ruby tooling, not app code. |

> First-party by design (we do **not** take a dependency for these): the `Money` value type, currency conversion, analytics aggregation, the CSV importer, and the **Sankey/money-flow renderer** (custom `Canvas`/`Path` in DesignSystem — Swift Charts has no Sankey; a vetted SPM renderer is an option only if it passes §11.1). See [`./04-tech-stack.md`](./04-tech-stack.md) and [`./06-design-system.md`](./06-design-system.md).

---

## 12. Quality gates at a glance

The full set of gates a change passes before it ships, mapped to where it's enforced:

| Gate | Enforced by | Blocks |
|------|-------------|--------|
| Formatting | `swift-format lint --strict` | CI `format-check` |
| Style + no force-unwrap + custom rules | `swiftlint --strict` | CI `lint` |
| Strict-concurrency, zero warnings | `xcodebuild` (warnings-as-errors) | CI `build` |
| Tests + coverage floors | `xcodebuild test` + `xccov` gate | CI `test` |
| Database & RLS regression | `supabase db reset` + pgTAP/`pg_prove` (RLS enabled **and** forced on every table; user B reads 0 rows of user A; every `SECURITY DEFINER` fn has `search_path` pinned + `REVOKE PUBLIC` + no caller-supplied `uid` arg) — see [§5.6](#database-rls-regression-gate) | CI `db-rls-regression` |
| Snapshot fidelity | swift-snapshot-testing on pinned sim | CI `test` |
| Critical journeys | XCUITest (nightly/`release/*`) | release |
| Signed, reproducible build | ASC API key + `match (readonly)` — see [§5.7](#code-signing-ci-credentials) | release |
| Phased release + rollback/kill path | App Store phased release ON; remote-config kill switches ([§5.8](#release-management), [§9.4](#feature-flags-remote-config)) | release |
| No secrets | Gitleaks | CI `secret-scan` |
| Dependency safety | dependency-review + `Package.resolved` | CI `dependency-review` |
| Commit hygiene | Conventional-Commit lint | CI `commit-lint` |
| Docs in sync | reviewer + link-checker | review + CI |
| Definition of Done | reviewer + PR template | review + protected `main` |

---

## Related documents

- [`../CLAUDE.md`](../CLAUDE.md) — the single source of truth and the locked decisions every gate here serves.
- [`./03-architecture.md`](./03-architecture.md) — the module graph, MVVM + Observation, and repository protocols these conventions assume.
- [`./04-tech-stack.md`](./04-tech-stack.md) — the chosen tools/versions (Swift 6, SwiftData, Swift Charts, supabase-swift) referenced throughout.
- [`./05-data-model.md`](./05-data-model.md) — **normative**: money as `Int64` minor units, canonical field names, RLS the code must honor.
- [`./07-security-and-privacy.md`](./07-security-and-privacy.md) — **normative**: Keychain tokens, RLS, hardened RPCs, no-secrets-in-bundle — the security gates above enforce it.
- [`./10-task-backlog.md`](./10-task-backlog.md) — where work and DoD checkboxes live; update it with every change.
- [`./12-decisions-adr.md`](./12-decisions-adr.md) — **normative**: the binding decisions (Observation over Combine, Actions+Fastlane CI, etc.); record reversals here.
- [`./11-substimate-analysis.md`](./11-substimate-analysis.md) — why we test (Substimate had none) and the bugs (float money, pre-store conversion, field duality) these practices prevent.
