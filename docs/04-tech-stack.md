# Technology Stack & Rationale

> The complete, versioned technology stack for Finmate's native iOS app and Supabase backend — every choice named with concrete versions, the reasoning behind it, the alternatives we rejected, and whether the decision is foundational (hard to reverse) or reversible.

This document is the authoritative reference for **what we build with and why**. It is downstream of the [Canonical Decisions Brief](../CLAUDE.md) and the [Architecture](./03-architecture.md) document: those define _shape_; this defines _materials_. Where a choice has deeper treatment elsewhere (data model, security, design system), this document gives the rationale and links out rather than duplicating detail.

Audience: senior iOS engineers and AI coding agents who will scaffold the project, add SPM dependencies, and configure CI from these specs. Treat the versions below as the **floor**; bump within the same major line freely, and treat a major-version bump (e.g. a new supabase-swift major) as a decision worthy of an ADR entry in [docs/12-decisions-adr.md](./12-decisions-adr.md).

---

## 1. Summary table

| Concern | Choice | Version / target | Reversibility | Rationale (1-liner) |
|---|---|---|---|---|
| Language | **Swift** (strict concurrency, language mode 6) | Swift 6.0+ (Xcode 26+) | **Foundational** | Native, memory-safe, first-class concurrency; compile-time data-race safety. |
| UI framework | **SwiftUI** + **Observation** | iOS 18 SDK baseline; built on iOS 26 SDK | **Foundational** | Declarative, the only path to Liquid Glass; `@Observable` is the modern state model. |
| Min deployment target | **iOS 18.0** | iOS 18.0 → latest | Reversible (raise/lower) | Mature SwiftData/Charts/Observation; broad device coverage. |
| Design language ceiling | **Liquid Glass** on iOS 26+, **Materials** fallback on 18–25 | iOS 26 APIs, graceful degrade | Reversible | One cohesive design language; no feature gating below 26. |
| Local persistence | **SwiftData**, behind repository protocols | iOS 17+ API (we require 18) | Reversible (swap to GRDB) | Offline cache; native, `@Model`-driven; isolated by protocols. |
| Persistence escape hatch | **GRDB.swift** (documented alternative) | 7.x | Reversible | Battle-tested SQLite if SwiftData's query model proves limiting. |
| Backend SDK | **supabase-swift** | 2.x (≥ 2.20) | **Foundational** (the contract), reversible (the client) | Official SDK: Auth, PostgREST, Realtime, Storage, Functions. |
| Backend platform | **Supabase** (Postgres + Auth + RLS + Edge Functions + Realtime + Storage) | Postgres 15+, platform managed | **Foundational** | Portable backend contract; RLS-centered security; cheap to start. |
| Charts | **Swift Charts** + custom Canvas/Path flow renderer | iOS 18 API | Reversible | Native charts; Sankey not built in → bespoke renderer in DesignSystem. |
| Auth | **Supabase Auth** + **Sign in with Apple** + email/password | platform + AuthenticationServices | **Foundational** | App Store requirement (SiwA) + email; tokens in Keychain. |
| Secure token storage | **Keychain Services** (via supabase-swift storage hook) | OS framework | **Foundational** | Tokens never in UserDefaults; hardware-backed where available. |
| App privacy lock | **LocalAuthentication** (Face ID / Touch ID) | OS framework | Reversible (opt-in feature) | Optional biometric gate on app entry. |
| Dependency injection | **Environment-based composition** + protocol injection (no DI framework v1) | language-native | Reversible | Constructor + `@Environment` injection; swap in a container later if needed. |
| Unit / logic testing | **Swift Testing** (primary) + **XCTest** (where required) | Swift Testing (Xcode 26), XCTest | Reversible | Modern `@Test`/`#expect`; XCTest for async/UIKit-bridged corners. |
| Snapshot testing | **swift-snapshot-testing** (Point-Free) | 1.18.x | Reversible | DesignSystem regression coverage for Liquid Glass components. |
| UI / E2E testing | **XCUITest** | OS framework | Reversible | Critical-flow coverage (auth, add subscription, import). |
| Linting | **SwiftLint** | 0.57.x+ | Reversible | Style + correctness lint, enforced in CI and pre-commit. |
| Formatting | **swift-format** (Apple) | bundled with Swift 6 toolchain | Reversible | Deterministic formatting; one config, no debates. |
| Package management | **Swift Package Manager** (SPM) + local packages | Swift 6 SPM | **Foundational** | Modular graph as local packages; no CocoaPods/Carthage. |
| CI/CD | **GitHub Actions** + **Fastlane** + **TestFlight** | macOS runner w/ Xcode 26 | Reversible | Build/test/lint + signed TestFlight delivery; Xcode Cloud as alt. |
| Secret scanning | **Gitleaks** | 8.x | Reversible | Block committed secrets in CI. |
| Logging | **OSLog** (`os.Logger`) | OS framework | Reversible | Structured, privacy-redacting, low-overhead logging. |
| Runtime metrics | **MetricKit** | OS framework | Reversible | On-device performance/crash diagnostics, privacy-preserving. |
| Product analytics | **None third-party in v1** (privacy-first) | — | Reversible | No trackers; optional first-party Supabase event table only if needed. |
| Edge runtime | **Supabase Edge Functions** (Deno) | Deno-based, platform managed | **Foundational** | Server-side market data + secrets (BTC calculator). |

**Reading the "Reversibility" column.** _Foundational_ means a change ripples through the codebase, the backend contract, or the App Store listing and should be treated as a major re-platform (write an ADR, scope a migration). _Reversible_ means the choice is hidden behind a boundary (a protocol, a CI workflow, a config file) and can be swapped with localized effort. The boundaries that make things reversible are the point of the [architecture](./03-architecture.md): repository protocols hide SwiftData; the DataLayer wrapper hides supabase-swift; the DesignSystem hides Liquid Glass vs Materials.

---

## 2. Language — Swift 6 with strict concurrency

**Choice:** Swift 6.0+, compiled with **Xcode 26+**, project set to **Swift language mode 6** with **complete strict concurrency checking** (`SWIFT_STRICT_CONCURRENCY = complete`).

**Rationale.** Finmate is a native iOS app (locked decision #1), so Swift is the only serious option. We commit to **language mode 6** — not the 5-mode-with-warnings transitional posture — from the first commit, because retrofitting `Sendable` correctness and actor isolation onto an existing codebase is far more painful than building with it on. Strict concurrency turns data races into **compile errors**, which is exactly the guarantee we want for an offline-first app that interleaves a SwiftData cache (`@MainActor`-bound model context in practice), background sync tasks, and Supabase Realtime callbacks.

Concrete conventions that follow from this:
- UI state types (`@Observable` Stores) are `@MainActor`-isolated.
- Repository implementations are `actor`s or `@MainActor` types depending on whether they own background work; the DataLayer sync engine is an `actor`.
- All cross-boundary value types (Money, domain entities, DTOs) are `Sendable` value types (`struct`/`enum`).
- Errors are **typed throws** (`throws(SyncError)`) where the error domain is closed and known, per the engineering practices in [docs/09-engineering-practices.md](./09-engineering-practices.md).
- No force-unwraps (`!`) or `try!` / `as!` on production paths (SwiftLint-enforced).

**Alternatives considered.**
- **Objective-C** — rejected: no SwiftUI authoring, no Observation, no value-type concurrency safety, no path to Liquid Glass. A non-starter for a 2026 greenfield app.
- **Swift 5 language mode (defer strict concurrency)** — rejected: this is the migration posture for legacy code. We have no legacy Swift, so we pay the strictness cost once, up front, and never accumulate concurrency debt.
- **Kotlin Multiplatform / Swift-on-the-backend sharing** — rejected: the backend is Supabase (Postgres + Deno Edge Functions), not a Swift service, so there is nothing to share. Cross-platform code sharing is explicitly out of scope (decision #1).

**Reversibility: Foundational.** This is the bedrock.

---

## 3. UI — SwiftUI + Observation

**Choice:** **SwiftUI** as the sole UI framework, with the **Observation** framework (`@Observable`, `@Bindable`, `@Environment`) for state management. No Storyboards, no XIBs, no UIKit view controllers as primary screens. UIKit is permitted only as a thin bridge where SwiftUI lacks an API (e.g. wrapping a specific control via `UIViewRepresentable`), and such bridges live behind DesignSystem or Shared abstractions.

**Rationale.** SwiftUI is the **only** framework that exposes the iOS 26 Liquid Glass APIs (`glassEffect`, `GlassEffectContainer`, `glassEffectID`, the `.glass` / `.glassProminent` button styles, scroll-edge effects) — see [docs/06-design-system.md](./06-design-system.md). Committing to UIKit would forfeit the design north star. The **Observation** framework replaces the old `ObservableObject` / `@Published` / `@StateObject` model: `@Observable` gives precise, property-level change tracking (only views that read a changed property re-render), removes `Combine` boilerplate, and pairs cleanly with `@MainActor` isolation. This is the canonical state model in the brief and in [docs/03-architecture.md](./03-architecture.md): Views observe `@Observable` Stores; Stores call repository protocols.

**Alternatives considered.**
- **UIKit (programmatic or Storyboards)** — rejected: no Liquid Glass APIs, imperative view lifecycle, far more code for the same screens, and it fights the unidirectional MVVM pattern we want.
- **`ObservableObject` + Combine** — rejected: superseded by Observation on iOS 17+; coarser invalidation (whole-object), more boilerplate, and Combine's threading model is awkward under Swift 6 strict concurrency.
- **The Composable Architecture (TCA)** — considered, rejected for v1: TCA is powerful but imposes a heavy mental model, a large dependency, and significant boilerplate that is overkill for an app whose state is naturally per-feature. Our lighter unidirectional MVVM (Stores → repository protocols) captures the testability benefits without the framework lock-in. We can adopt TCA inside a single feature later if its complexity warrants — the architecture does not preclude it. (Reversible decision; would be an ADR.)
- **React Native / Flutter** — rejected by locked decision #1.

**Reversibility: Foundational** (SwiftUI) / **Reversible** (the specific state-management pattern within SwiftUI).

---

## 4. Deployment target — iOS 18.0, Liquid Glass on iOS 26+

**Choice:** **Minimum deployment target iOS 18.0.** Build against the latest SDK (iOS 26 at time of writing). Ship a **design-complete Liquid Glass** experience on iOS 26+, with **automatic graceful fallback to system Materials** (`.ultraThinMaterial`, `.regularMaterial`, `.thickMaterial`, available since iOS 15) on iOS 18–25.

**Rationale.** iOS 18 is the floor because it is where the platform features the architecture depends on are all _mature_, not merely _present_:
- **Observation** (`@Observable`) — iOS 17, mature by 18.
- **SwiftData** — iOS 17, with significant stability/query fixes landing in 17.x and 18.
- **Swift Charts** — iOS 16, with the chart types and interactivity we use stable by 18.
- **Swift Concurrency** runtime — fully mature on iOS 18.

Choosing 18 (rather than 17) buys a more dependable SwiftData and a cleaner concurrency runtime at a modest cost in device coverage, since iOS 18 adoption is high across the supported iPhone fleet by mid-2026. The Liquid-Glass-on-26 / Materials-on-18 split means **no feature is gated behind iOS version** — every user gets the full product; only the surface finish differs. This is implemented via a capability check in DesignSystem (`if #available(iOS 26, *)`), not scattered across feature code. The owner may revisit the floor; raising it to 26 later (once adoption justifies it) would let us delete the Materials fallback path, which is an explicit future simplification, not a v1 commitment.

**Alternatives considered.**
- **iOS 17 minimum** — viable, gains a sliver of older devices, but accepts the less-stable early SwiftData and forgoes nothing we need. Rejected for the stability margin.
- **iOS 26 minimum (Liquid-Glass-only)** — rejected for v1: cuts off a large installed base in mid-2026 and offers no functional benefit, only the convenience of deleting the fallback path. Revisit post-v1.

**Reversibility: Reversible.** Raising/lowering the floor is a build-setting change plus an availability-audit; the fallback architecture is designed for exactly this.

---

## 5. Local persistence — SwiftData (with GRDB as the documented escape hatch)

**Choice:** **SwiftData** as the on-device offline cache, **hidden entirely behind repository protocols** in the DataLayer package so no feature ever imports SwiftData directly. **GRDB.swift 7.x** is documented as the battle-tested alternative we will swap to if SwiftData proves limiting.

**Rationale.** The architecture (brief + [docs/03-architecture.md](./03-architecture.md)) is offline-first: the local cache is the instant read source; writes are optimistic, then synced to Supabase (the source of truth); conflicts resolve last-write-wins per field on `updated_at`. SwiftData is the lowest-friction way to get a typed, `@Model`-driven local store on iOS 18: it integrates with Observation, supports `@Query` (which we deliberately **do not** expose to features — features go through repositories so we keep the swap option), and requires no schema-DSL or SQL hand-rolling for the common case.

The **key risk** — and the reason GRDB is pre-vetted — is that SwiftData's query surface (`#Predicate`, `FetchDescriptor`) is still less expressive than raw SQL for the analytics-heavy queries Finmate needs: monthly trend aggregation, category distribution, lifetime cost, payment-method breakdown (see the analytics pillar in [docs/02-product-spec.md](./02-product-spec.md)). Three mitigations:
1. Heavy aggregation can run **server-side in Postgres** via RPC/views and be cached, rather than in the local store.
2. The repository protocols mean we can move _individual_ repositories to GRDB without rewriting the app.
3. If SwiftData's limitations (complex predicates, migration ergonomics, or concurrency edge cases) become systemic, we swap the whole local store to **GRDB.swift** — a mature, well-maintained SQLite wrapper with full SQL access, robust migrations, and a `ValueObservation` model that pairs with our reactive Stores.

The Substimate predecessor stored money as floats and had field-name duality (`amount` vs `monthlyCost`, `favorite` vs `isFavorite`); our `@Model` types use the **single canonical names** and **`Int64` minor units** mandated by the brief — see [docs/05-data-model.md](./05-data-model.md) and [docs/11-substimate-analysis.md](./11-substimate-analysis.md).

**Alternatives considered.**
- **GRDB.swift (as primary)** — strong contender; more powerful and predictable than SwiftData today. We chose SwiftData _first_ for its tighter Observation/SwiftUI integration and lower boilerplate, while keeping GRDB one protocol-swap away. If we hit a wall in M1–M2, this flips.
- **Core Data (direct)** — rejected: SwiftData _is_ the modern Core Data front end; using Core Data directly means more boilerplate (`NSManagedObject` subclasses, `NSFetchRequest`) for no benefit on a greenfield iOS 18 app.
- **Realm** — rejected: third-party, the Atlas Device SDK roadmap is uncertain post-MongoDB-acquisition changes, and we prefer first-party or thin-SQLite for a long-lived offline store.
- **Plain SQLite (SQLite3 C API)** — rejected: GRDB already wraps this well; hand-rolling is needless risk.

**Reversibility: Reversible** by construction — this is the single most deliberately-isolated dependency in the app. See ADR in [docs/12-decisions-adr.md](./12-decisions-adr.md).

---

## 6. Networking & data — supabase-swift SDK

**Choice:** the official **supabase-swift** SDK (`supabase/supabase-swift`), **2.x (pin ≥ 2.20.0)**, added via SPM. We use its sub-modules: **Auth (GoTrue)**, **PostgREST**, **Realtime**, **Storage**, and **Functions**. All access is funneled through a **single DataLayer wrapper** (`SupabaseClientProvider` + repository implementations); no feature talks to the SDK directly.

**Rationale.** supabase-swift is the canonical client for our backend (decision #2) and gives us, in one Swift-native package:
- **Auth**: session lifecycle, **automatic access/refresh token refresh**, Sign in with Apple via OIDC, email/password. We supply a **custom Keychain-backed storage** for tokens (see §10) instead of the default.
- **PostgREST**: typed query builder over the REST interface to Postgres; honors **RLS** automatically because every request carries the user's JWT. We generate Swift DTOs from the database (see §6.1) so column drift surfaces at compile time.
- **Realtime**: Postgres change subscriptions to drive cache invalidation/live updates (e.g. a subscription edited on a future web client appears on the phone). Realtime is `Sendable`-friendly and bridges to `AsyncStream` for our actor-based sync engine.
- **Storage**: for user-uploadable assets (e.g. custom subscription icons) under RLS-scoped buckets.
- **Functions**: typed invocation of Edge Functions — notably the **server-side market-data function** for the BTC/crypto calculator (decision: provider keys stay server-side, an explicit improvement over Substimate, which called market data from the client).

The wrapper boundary keeps the SDK swappable: if we ever needed to hand-roll PostgREST calls or move off supabase-swift, only the DataLayer changes. This is also what makes the **future web client** viable — the backend contract (schema + RLS + Edge Functions + generated types) is the durable artifact; the Swift SDK is just one consumer of it.

### 6.1 Type generation
We treat the database schema as the source of truth and **generate types** rather than hand-maintaining DTOs. The Supabase CLI emits TypeScript types (`supabase gen types typescript`), which we consume for the **future web client**; for Swift we maintain a thin, reviewed mapping layer (hand-written `Codable` DTOs that mirror generated TS, validated by integration tests against a seeded local Supabase). A community Swift type-gen tool may be adopted if it stabilizes; until then the hand-written-but-test-guarded DTO layer is intentional. See [docs/05-data-model.md](./05-data-model.md) for the schema and [docs/09-engineering-practices.md](./09-engineering-practices.md) for the verification gate.

<a id="currency-and-conversion"></a>

### 6.2 Currency & conversion

This is the **canonical home** for Finmate's currency-conversion contract. [docs/05-data-model.md](./05-data-model.md) references this section instead of re-specifying it. v1 supports three currencies — **EUR, USD, BTC** — and the rule that governs everything below is one line:

> **Conversion is display-only and never mutates a stored amount.** Stored amounts are always `Int64` minor units in their original `currency`. We convert at read/display time only. This is the single most important Substimate bug we are fixing — Substimate pre-converted amounts to a display currency *before storing*, corrupting the data permanently. Finmate never does this.

**Canonical rate source (single source of truth).** The market-data Edge Function (§17, [docs/07-security-and-privacy.md §5.2](./07-security-and-privacy.md#52-what-must-never-ship-in-the-client)) returns **exactly** this JSON, which is the only shape any client or cache stores in the `exchange_rates` jsonb:

```jsonc
{
  "eur_usd":    1.0825,        // Decimal: USD per 1 EUR
  "btc_eur":    58234.50,      // Decimal: EUR per 1 BTC
  "btc_usd":    63038.85,      // Decimal: USD per 1 BTC
  "fetched_at": "2026-06-28T09:14:32.512Z"  // ISO8601, fractional seconds + offset
}
```

The keys align verbatim with the Edge Function response diagram in [docs/07-security-and-privacy.md §5.2](./07-security-and-privacy.md#52-what-must-never-ship-in-the-client). All four keys are required; rates are transported and computed as `Decimal` (never `Double`/`Float`), and the BTC pairs are stored at full precision (the example values are illustrative).

**Building the conversion matrix.** From those three pairs we build the full **3×3 EUR/USD/BTC** rate matrix by triangulation, so any source→target pair is available even though the Edge Function only sends three quotes:

| from \ to | EUR | USD | BTC |
|---|---|---|---|
| **EUR** | `1` | `eur_usd` | `1 / btc_eur` |
| **USD** | `1 / eur_usd` | `1` | `1 / btc_usd` |
| **BTC** | `btc_eur` | `btc_usd` | `1` |

Cross rates that aren't directly quoted are derived by triangulation (e.g. a hypothetical fourth fiat would route through USD). **BTC ↔ satoshis** uses the domain constant `satsPerBTC = 100_000_000`: 1 BTC = `100_000_000` minor units (sats), 1 EUR/USD = `100` minor units (cents).

**Rounding.** Every conversion runs in `Decimal` and the final amount is rounded **HALF-UP** to the *target* currency's minor-unit precision (2 fractional digits for EUR/USD → cents; 8 for BTC → sats). Half-up rounding is the same rule the `Money` type and `parse(_:currency:)` use (see [docs/05-data-model.md §2.2](./05-data-model.md) and [docs/09-engineering-practices.md §3.2](./09-engineering-practices.md)), so display conversion and money parsing never disagree on a boundary case.

**Staleness & missing-rate policy.**
- If `fetched_at` is **older than 24h**, still convert, but surface a non-blocking **"rates may be stale"** indicator on any converted figure.
- If a **rate needed for a pair is missing** (e.g. the cache has never been populated, or the BTC quote is absent), conversion for that pair is **unavailable**: display the **stored source amount unconverted**, in its original currency, rather than guessing or showing a wrong number.
- The cache is refreshed opportunistically when the app fetches market data; conversion never blocks UI on a network call (offline-first — the last good `exchange_rates` row is used).

**The `CurrencyConverter` protocol.** Conversion lives behind a protocol in `Domain` (implementation in `DataLayer`, fed by the cached `exchange_rates` row), so Stores and views convert without knowing the rate source:

```swift
public enum ConversionError: Error, Sendable {
    case rateUnavailable(from: Currency, to: Currency)
}

public struct ExchangeRates: Sendable, Equatable {
    public let eurUsd: Decimal   // USD per 1 EUR
    public let btcEur: Decimal   // EUR per 1 BTC
    public let btcUsd: Decimal   // USD per 1 BTC
    public let fetchedAt: Date
}

public protocol CurrencyConverter: Sendable {
    /// Display-only conversion. Rounds HALF-UP to `target` minor units.
    /// Throws `.rateUnavailable` if no path exists for the pair — callers
    /// then show the stored source amount unconverted.
    func convert(_ money: Money, to target: Currency) throws(ConversionError) -> Money

    /// True when `fetchedAt` is older than the 24h staleness window.
    var ratesAreStale: Bool { get }
}
```

`convert` is **pure** with respect to its inputs (a `Money` plus the injected rate snapshot) and is unit-tested with table-driven cases: EUR→USD, USD→EUR, EUR→BTC→sats, BTC→USD, identity (same currency returns the input unchanged), half-up rounding at the cent/sat boundary, and the `rateUnavailable` path. It **never** writes back to the store.

**Reversibility: Reversible** — the protocol seam in `Domain` and the `exchange_rates` jsonb contract make the rate provider swappable; the *display-only, never-mutate-stored-amounts* rule is a non-negotiable invariant, not a reversible choice.

**Alternatives considered.**
- **Hand-rolled `URLSession` + PostgREST REST calls** — rejected: re-implements auth refresh, retry, Realtime websockets, and storage multipart — all solved by the SDK. We keep `URLSession` only for trivial, non-Supabase fetches if any arise.
- **Apollo / GraphQL** — rejected: Supabase's primary contract is PostgREST + RPC; pg_graphql exists but adds a layer we don't need and complicates RLS reasoning.
- **A different BaaS (Firebase, Appwrite)** — rejected by decision #2: Supabase's Postgres + RLS gives us a portable, SQL-standard, owner-derived security model and a backend contract a web client can reuse. Firebase's security-rules model and NoSQL data model do not match the relational domain (price history, asset transactions, categories).

**Reversibility:** the **backend platform and contract are Foundational**; the **specific Swift SDK is Reversible** (hidden behind DataLayer).

---

## 7. Charts — Swift Charts + a custom money-flow renderer

**Choice:** **Swift Charts** (Apple, native) for all standard visualizations — monthly spend trends (line/area), category distribution (bar/pie via `SectorMark`), payment-method breakdown, usage stats. For the **Sankey / money-flow** cost-tracker visualization, a **custom `Canvas`/`Path`-based flow renderer** lives in the DesignSystem package.

**Rationale.** Swift Charts is native, accessible (VoiceOver chart descriptions, audio graphs), animatable, and theming-aware — it lines up with our accessibility and design commitments. The one thing it **does not** provide is a Sankey/alluvial diagram (the money-flow view that shows income flowing into categories and out to expenses). Substimate built this with `d3-sankey` + `recharts` on the web; on iOS we have no equivalent native primitive, so we build a deterministic layout + `Canvas` renderer in DesignSystem (node placement, link curves as cubic Béziers, hit-testing for taps, reduce-motion-aware transitions). This is flagged as a **known engineering item** in [docs/06-design-system.md](./06-design-system.md), [docs/08-roadmap-and-milestones.md](./08-roadmap-and-milestones.md), and [docs/10-task-backlog.md](./10-task-backlog.md).

**Alternatives considered.**
- **DGCharts (formerly Charts/ios-charts)** — rejected: heavy third-party dependency, UIKit-rooted, redundant with Swift Charts for everything except Sankey, and still wouldn't give us Sankey.
- **A vetted SPM Sankey package** — kept as a fallback option for the flow renderer if a high-quality, maintained, SwiftUI-native, accessible one exists at build time; default is our own renderer for full control over Liquid Glass styling and accessibility. (Reversible.)
- **Web view + d3-sankey (reuse Substimate's renderer)** — rejected: a `WKWebView` chart breaks the native design language, accessibility, and performance goals; it's exactly the "web cruft" the brief says to cut.

**Reversibility: Reversible.** Standard charts are native and stable; the flow renderer is a self-contained DesignSystem component.

---

## 8. Authentication — Supabase Auth + Sign in with Apple

**Choice:** **Supabase Auth** as the identity provider, exposing **Sign in with Apple** (primary, via `AuthenticationServices` / `ASAuthorizationController`) and **email + password** (secondary). First-run onboarding sets currency, appearance, and optional biometric lock.

**Rationale.** Sign in with Apple is effectively **required by App Store Review Guideline 4.8** when offering third-party/social login, and it's the most private, lowest-friction option for an Apple-grade finance app. Supabase Auth brokers the Apple OIDC flow and issues the JWT that every PostgREST/Realtime request carries, which is what makes RLS (`auth.uid()`) work end-to-end. Email/password covers users who prefer it and the web client later. The SDK handles **automatic token refresh**; we override only **where tokens are stored** (Keychain, §10). Account deletion and data export — App Store requirements — are implemented as in-app flows backed by hardened RPCs (see [docs/07-security-and-privacy.md](./07-security-and-privacy.md)).

**Alternatives considered.**
- **Firebase Auth** — rejected: would split identity from the data layer (different vendor than the Postgres/RLS backend), breaking the single-`auth.uid()` ownership model.
- **Custom auth backend** — rejected: re-implements a solved, security-sensitive problem; Supabase Auth is audited and integrated with RLS.
- **Sign in with Apple only (no email/password)** — rejected: email/password broadens reach and is needed for the future web client; both ship in v1.

**Reversibility: Foundational** — identity is wired to the RLS security model and the App Store listing.

---

## 9. Secure token storage — Keychain Services

**Choice:** access and refresh tokens are stored in the **iOS Keychain** (Keychain Services), supplied to supabase-swift as a **custom `AuthLocalStorage` conformance** that reads/writes Keychain items. **Never** UserDefaults, never a plist, never the SwiftData cache.

**Rationale.** Tokens are bearer credentials to the user's entire financial dataset. The Keychain provides encrypted, OS-managed storage with item accessibility classes; we use **`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`** so tokens are unavailable before first unlock and never sync to iCloud or migrate to a new device via backup. On logout we **delete** the token items and clear sensitive caches (brief: "clear sensitive caches on logout"). This is a hard requirement in the security posture and is detailed in [docs/07-security-and-privacy.md](./07-security-and-privacy.md).

**Alternatives considered.**
- **UserDefaults / plist** — rejected outright: plaintext, backed up, trivially readable on a jailbroken or backed-up device. This is the canonical mistake the brief forbids.
- **A wrapper library (e.g. KeychainAccess)** — optional convenience; we prefer a small, audited in-house `KeychainStore` in the Shared/Utilities package to keep the dependency surface and the security-critical code under our review. (Reversible.)

**Reversibility: Foundational** (Keychain as the store) / **Reversible** (the helper used to talk to it).

---

## 10. App privacy lock — LocalAuthentication

**Choice:** an **optional** app-entry biometric lock using the **LocalAuthentication** framework (`LAContext`, `LAPolicy.deviceOwnerAuthenticationWithBiometrics`, falling back to device passcode), with a configurable timeout. Off by default; enabled in onboarding or Settings.

**Rationale.** A finance app benefits from a lock independent of device unlock; LocalAuthentication is the native Face ID / Touch ID API. It gates the UI only — it is **not** an encryption key and does not replace Keychain accessibility or RLS. Behavior on failure/cancel, backgrounding blur, and timeout policy are specified in [docs/07-security-and-privacy.md](./07-security-and-privacy.md) and the Settings feature in [docs/02-product-spec.md](./02-product-spec.md).

**Alternatives considered.**
- **Custom PIN screen** — rejected as the primary mechanism: biometrics are more secure and lower-friction; a PIN may be added later as a fallback for devices without biometrics if demand appears. (Reversible.)

**Reversibility: Reversible** — it's an opt-in feature behind a clear boundary.

---

## 11. Dependency injection

**Choice:** **No DI framework in v1.** We use **language-native composition**: protocol dependencies injected via initializers, with app-wide singletons/services provided through the SwiftUI **`@Environment`** using custom `EnvironmentKey`s (and the `@Entry` macro for brevity). The composition root is the App target, which constructs concrete repository implementations and injects them down.

**Rationale.** Our architecture already enforces protocol-based seams (Stores depend on repository _protocols_; DataLayer provides implementations). That is exactly what a DI container would give us, achievable here with zero dependencies and full Swift 6 concurrency clarity. For tests we inject mocks/in-memory fakes directly. Adding a container (e.g. swift-dependencies, Factory) would add a dependency and indirection without solving a problem we have at v1 scale.

**Alternatives considered.**
- **Point-Free swift-dependencies** — strong, ergonomic, test-friendly; reconsider if the manual wiring in the composition root becomes unwieldy as features multiply. (Reversible; would be an ADR.)
- **Factory / Resolver / Swinject** — rejected for v1: runtime registration and reflection-ish patterns fight Swift 6 concurrency checking and add weight we don't need.

**Reversibility: Reversible** — the protocol seams mean a container can be introduced later without touching feature code.

---

## 12. Testing stack

**Choice:**
- **Swift Testing** (`import Testing`, `@Test`, `#expect`, `#require`, parameterized tests) as the **primary** unit-test framework.
- **XCTest** where Swift Testing has gaps (some async expectation patterns, legacy-style performance tests, and as the host for XCUITest).
- **swift-snapshot-testing** (Point-Free, 1.18.x) for **DesignSystem** visual-regression snapshots (light/dark, Dynamic Type sizes, reduce-motion).
- **XCUITest** for critical end-to-end flows.

**Rationale.** The brief is explicit and pointed: Substimate **lacked** automated tests for the very logic most prone to silent money bugs. Finmate requires **unit tests for all pure logic** — money math (`Int64` minor-unit arithmetic, rounding), currency conversion (fiat↔sats with `satsPerBTC = 100_000_000`), analytics aggregation (monthly trend, category distribution, lifetime cost), and **CSV import parsing/validation** (the import preview flow). Swift Testing's `#expect` and parameterized `@Test(arguments:)` are ideal for table-driven money/currency cases. Snapshot tests lock in the Liquid Glass components so a styling change can't silently regress the design language across appearances and accessibility settings. XCUITest covers the flows where a regression is most user-visible:

- [ ] Sign in with Apple → land on Home
- [ ] Add a subscription → appears optimistically, persists after relaunch
- [ ] CSV import → preview → confirm → rows present
- [ ] Toggle biometric lock → app gated on next cold launch
- [ ] Account deletion → data gone, signed out

**Alternatives considered.**
- **XCTest only** — rejected as _primary_: Swift Testing is the modern, more expressive framework shipping in the Swift 6 toolchain; we use XCTest only where it's still the better tool.
- **Quick/Nimble** — rejected: third-party BDD layer that Swift Testing's native ergonomics make unnecessary.
- **Third-party snapshot libs other than swift-snapshot-testing** — rejected: Point-Free's is the de-facto standard, SwiftUI-aware, and actively maintained.

**Reversibility: Reversible** — test tooling is internal.

---

## 13. Linting & formatting

**Choice:** **SwiftLint** (0.57.x+) for lint rules and **swift-format** (Apple, bundled with the Swift 6 toolchain) for formatting. Both run in **pre-commit hooks** and as **required CI checks**.

**Rationale.** Two tools, two jobs: swift-format imposes deterministic, non-negotiable formatting (no style bikeshedding in review); SwiftLint enforces correctness/safety rules that formatting can't — notably **no force-unwraps / `try!` / `as!` on production paths**, file/type length, cyclomatic complexity, and custom rules (e.g. ban `Double`/`Float` for money types, ban `print`, require `os.Logger`). Configs (`.swiftlint.yml`, `.swift-format`) are committed and treated as code. Full rule set and rationale live in [docs/09-engineering-practices.md](./09-engineering-practices.md).

**Alternatives considered.**
- **swiftformat (Nick Lockwood)** — capable and popular, but we standardize on **Apple's swift-format** because it ships with the toolchain (no version-skew with Xcode), aligns with the official style direction, and reduces our dependency surface. SwiftLint remains for the lint rules swift-format doesn't cover.

**Reversibility: Reversible.**

---

## 14. Package management — Swift Package Manager

**Choice:** **Swift Package Manager** exclusively. The app is **modularized as local Swift packages** (the module graph from the brief: `App` → `Features/*` → `Core` packages `DesignSystem`, `DataLayer`, `Domain`/`Models`, `Shared`/`Utilities`). External dependencies are added as SPM products. **No CocoaPods, no Carthage.**

**Rationale.** SPM is first-party, integrated into Xcode 26, and is the right vehicle for our **modular** architecture: each `Features/*` and `Core` package is a real SPM module with explicit dependencies, which is what enforces "features never depend on each other; they depend on Domain + DesignSystem + DataLayer abstractions." Local packages also give fast, isolated builds and previewable modules. The (small) external dependency list:

| Package | Source | Purpose |
|---|---|---|
| supabase-swift | `supabase/supabase-swift` 2.x | Backend SDK (§6) |
| swift-snapshot-testing | `pointfreeco/swift-snapshot-testing` 1.18.x | DesignSystem snapshots (test-only) |
| (optional) GRDB.swift | `groue/GRDB.swift` 7.x | Persistence escape hatch (§5) |
| (optional) a vetted Sankey package | TBD | Only if we don't build our own flow renderer (§7) |

Everything else (SwiftLint, swift-format, Gitleaks, Fastlane) is tooling, not a linked dependency. We keep the linked-dependency count deliberately tiny — fewer supply-chain and concurrency-audit surfaces.

**Alternatives considered.**
- **CocoaPods** — rejected: not Swift 6 / SPM-native, requires a workspace and a Ruby toolchain, and is in long-term decline.
- **Carthage** — rejected: manual integration overhead; SPM covers the use case.
- **A monolithic single-target app** — rejected: defeats the modular architecture; local SPM packages are the mechanism that gives us enforced boundaries and parallel builds.

**Reversibility: Foundational** — SPM and the local-package graph _are_ the architecture's enforcement mechanism.

---

## 15. CI/CD — GitHub Actions + Fastlane + TestFlight

**Choice:** **GitHub Actions** on a macOS runner with **Xcode 26** as CI; **Fastlane** for build/sign/deliver lanes; **TestFlight** for beta distribution. **Xcode Cloud** is the documented alternative.

**Rationale.** The remote repo is on GitHub (`https://github.com/RNT56/finmate.git`), so GitHub Actions is the natural CI with no extra vendor. Required PR checks (trunk-based, protected `main`, conventional commits — see [docs/09-engineering-practices.md](./09-engineering-practices.md)):

- [ ] **Lint**: SwiftLint + swift-format `--lint`
- [ ] **Build**: `xcodebuild` / `swift build` for the app and all packages
- [ ] **Test**: Swift Testing + XCTest + snapshot tests on a simulator
- [ ] **Secret scan**: **Gitleaks** (block any committed secret; the app must ship only the public anon key)
- [ ] **Dependency review**: GitHub's dependency-review action on PRs

Fastlane handles code signing, incrementing build numbers, building the archive, and uploading to TestFlight. This separation — Actions orchestrates, Fastlane does the Apple-specific signing/delivery — keeps the delivery logic portable if we move CI. The **signing strategy is decided, not punted**: an **App Store Connect API key (`.p8`)** plus **fastlane `match`** storing certificates and provisioning profiles in a **private git repo**, with the exact CI secret names (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `MATCH_PASSWORD`, `MATCH_GIT_URL`, `MATCH_GIT_BASIC_AUTHORIZATION`) and the `setup_ci` + `match(readonly: true)` CI bootstrap specified in [docs/09-engineering-practices.md §5.5](./09-engineering-practices.md#55-fastlane-lanes--testflight). The earlier "match or manual per the team" wording is superseded by that decision.

**Alternatives considered.**
- **Xcode Cloud** — first-party, zero-config signing, tight TestFlight integration; the documented alternative and a reasonable switch if Actions runner minutes/macOS costs become painful. We default to Actions for flexibility (custom steps like Gitleaks, dependency review) and because the repo already lives on GitHub. (Reversible.)
- **Bitrise / CircleCI** — rejected: extra vendor with no advantage over Actions for an Apple-only pipeline.

**Reversibility: Reversible** — CI is configuration; Fastlane lanes are portable across CI vendors.

---

## 16. Observability & analytics — privacy-preserving by default

**Choice:**
- **Logging:** **OSLog** (`os.Logger`) with per-subsystem/category loggers and `privacy:` redaction; **no `print`** in production.
- **Runtime diagnostics:** **MetricKit** for on-device performance and crash/hang diagnostics.
- **Product analytics:** **none third-party in v1.** No Firebase Analytics, no Amplitude, no Mixpanel, no SDK that phones home. If we ever need product metrics, they go to a **first-party, RLS-protected Supabase table** with **no PII**, disclosed in the privacy label and toggleable by the user.

**Rationale.** This is a hard requirement from the security/privacy posture: **no third-party trackers, no PII in analytics/logs, accurate App Privacy nutrition label, data minimization.** OSLog is the native, low-overhead, privacy-aware logging API — sensitive interpolations are marked `.private` and redacted in logs by default; we log _events_, never financial values or identifiers. MetricKit gives us aggregate performance/crash data **on-device, delivered by the OS**, without embedding a third-party crash SDK that would expand the privacy label and the supply-chain surface. Details and the exact subsystem taxonomy are in [docs/07-security-and-privacy.md](./07-security-and-privacy.md) and [docs/09-engineering-practices.md](./09-engineering-practices.md).

**Alternatives considered.**
- **Firebase Crashlytics / Sentry** — rejected for v1: both add a third-party SDK, network egress, and privacy-label obligations that conflict with the "no third-party trackers" rule. MetricKit covers crash/hang diagnostics natively. Revisit only if MetricKit's fidelity is insufficient, and then only with an explicit privacy review. (Reversible.)
- **Amplitude / Mixpanel / Firebase Analytics** — rejected: product trackers are exactly what the brief forbids.

**Reversibility: Reversible** — but reintroducing any third-party telemetry is a privacy decision requiring an ADR and a privacy-label review.

---

## 17. Backend platform — Supabase (Postgres + Edge Functions + Storage)

**Choice:** **Supabase** managed platform: **PostgreSQL 15+**, **Auth**, **Row Level Security**, **Edge Functions** (Deno runtime), **Realtime**, and **Storage**. Security is centered on **RLS deriving ownership from `auth.uid()`** on **every** table.

**Rationale.** This is locked decision #2 and the durable backbone of the product: it "starts small and cheap, scales cleanly, is robust, and leaves a portable backend contract (schema + RLS + Edge Functions + generated types) that a future web client reuses." Specifics that matter to the stack:
- **Postgres + RLS** gives us a relational model that fits the domain (subscriptions, price history, asset transactions, categories) and a single, auditable ownership model. The full schema, RLS policies, triggers, and migrations are in [docs/05-data-model.md](./05-data-model.md).
- **Edge Functions (Deno)** host server-side logic where **secrets must not ship in the app** — chiefly the **market-data function** for the BTC/crypto calculator (fiat↔sats), so provider keys live in Edge Function environment variables, not the bundle. This directly fixes Substimate calling market data from the client.
- **SECURITY DEFINER RPCs** (e.g. the `get_user_categories` equivalent, account deletion, subscription deletion) are hardened with `SET search_path = public`, `REVOKE ALL FROM PUBLIC`, `GRANT EXECUTE TO authenticated`, and per-row owner checks. Substimate's latest migrations (dated **2026-06-27**: `20260627090000_harden_security_definer_functions.sql` and `20260627103000_fix_price_history_currency_and_rpc_hardening.sql`) contain exactly these patterns and are the reference; see [docs/11-substimate-analysis.md](./11-substimate-analysis.md) and [docs/07-security-and-privacy.md](./07-security-and-privacy.md).
- A **DB trigger** auto-writes `SubscriptionPriceHistory` on price/currency change (Substimate uses a SECURITY DEFINER trigger for this).

The backend is the **one stack element that is explicitly a shared contract** with a future client, so its stability is paramount.

### 17.1 Operating cost & scaling

Supabase "starts small and cheap" — but cheap is not free of constraints, and a finance app cannot afford a surprise auto-pause. The posture (recorded as **ADR-0018** in [docs/12-decisions-adr.md](./12-decisions-adr.md), with the matching data-loss / scaling risks in the [docs/08 risk register](./08-roadmap-and-milestones.md)):

- **Dev/CI on the Free tier.** Local-first development uses `supabase start`; the hosted Free project is for shared dev/staging.
- **Production on Pro.** Production runs on **Supabase Pro** from launch. Two reasons make this non-optional: Pro removes the Free tier's **7-day-inactivity auto-pause** (an idle Free project is paused, which for a finance app means a user's data appears to vanish), and Pro unlocks **daily backups + Point-in-Time Recovery** — the backbone of the disaster-recovery runbook in [docs/07-security-and-privacy.md §13](./07-security-and-privacy.md).

**First limits expected to bind**, roughly in the order they will be hit as the user base grows:

| Limit | Why it binds for Finmate | Mitigation |
|---|---|---|
| **Monthly Active Users (Auth)** | Every signed-in user is a MAU; the headline pricing dimension. | Track MAU vs plan allowance; budget for the per-MAU overage at scale. |
| **Edge Function invocations** | The `market-data` function is called per user for the BTC/crypto calculator and currency display. Naïvely, every user-session that shows a converted figure is an invocation. | **Cache aggressively**: a **single shared `exchange_rates` row** refreshed on a TTL (~60s server-side, then served from the local cache per §6.2) instead of one provider call per user. Rates are global, not per-user, so one fetch fans out to all clients. |
| **Realtime concurrent connections** | Offline-first sync uses Realtime as the latency layer over delta-poll; each foregrounded app holds a connection. | Connect Realtime only while the app is foreground/active; rely on delta-poll on cold start; tune channel subscriptions to the entities actually on screen. |
| **Database size (500MB Free ceiling)** | Price history and asset-transaction rows accumulate. | The Free ceiling is a dev concern; Pro raises it. Keep heavy aggregation server-side and prune/retain price history sensibly. |

**Database connection pooling.** Edge Functions access the database through **Supavisor in transaction-pooling mode** (not a direct per-invocation connection), so a burst of function invocations does not exhaust Postgres connection slots.

**Scale-up triggers (owner to confirm exact thresholds).** Move from Free→Pro **before** any production traffic (already the launch baseline). Watch dashboards and act when: MAU exceeds ~80% of the plan allowance; Edge Function invocations trend toward the monthly cap; Realtime concurrent connections approach the plan limit; or database size crosses ~80% of the tier ceiling. Each trigger is a plan bump or an architecture tightening (more caching, narrower Realtime subscriptions), evaluated against the risk register in [docs/08-roadmap-and-milestones.md](./08-roadmap-and-milestones.md).

**Alternatives considered.**
- **Firebase / Firestore** — rejected: NoSQL doesn't fit the relational domain; security rules are less expressive and auditable than SQL RLS; ties identity and data to one model that a future web client and our `Int64`-minor-unit money design would fight.
- **A hand-rolled backend (Vapor/Express + self-managed Postgres)** — rejected for v1: re-implements auth, RLS-equivalent authorization, Realtime, and storage; far more ops burden; no cheaper at our scale.
- **AWS Amplify / AppSync** — rejected: heavier, GraphQL-centric, more vendor lock-in, and no advantage over Supabase's Postgres+RLS for this domain.

**Reversibility: Foundational** — the backend contract is the product's spine and the future web client's dependency.

---

## 18. What's intentionally NOT in the stack

To make the minimalism explicit (and to prevent well-meaning re-additions):

- **No Combine** as a primary reactive layer — Observation + Swift Concurrency `AsyncStream` replace it.
- **No third-party networking** (Alamofire) — supabase-swift + `URLSession` suffice.
- **No third-party analytics/crash SDKs** — OSLog + MetricKit, privacy-first (§16).
- **No CocoaPods/Carthage** — SPM only (§14).
- **No 9 visual styles / no CSS** — one Liquid Glass language; web layout cruft is cut (brief; [docs/06-design-system.md](./06-design-system.md)).
- **No floating-point money anywhere** — `Int64` minor units, `Decimal` for computation, a `Money` value type ([docs/05-data-model.md](./05-data-model.md)).
- **No service-role key or provider secrets in the bundle** — public anon key only; secrets in Edge Functions (§17, [docs/07-security-and-privacy.md](./07-security-and-privacy.md)).

---

## 19. Foundational vs reversible — the one-glance summary

```
FOUNDATIONAL (re-platform to change; write an ADR + migration)
├─ Swift 6 / strict concurrency
├─ SwiftUI + Observation
├─ Supabase backend platform + contract (Postgres/RLS/Edge/Realtime/Storage)
├─ Supabase Auth + Sign in with Apple (wired to RLS auth.uid())
├─ Keychain for tokens
└─ SPM + local-package module graph

REVERSIBLE (hidden behind a boundary; localized change)
├─ iOS 18 deployment floor (build setting + availability audit)
├─ SwiftData ⇄ GRDB  (repository protocols)
├─ supabase-swift SDK  (DataLayer wrapper)
├─ Charts: Swift Charts + custom flow renderer  (DesignSystem)
├─ DI: env/protocol composition ⇄ swift-dependencies
├─ Testing tools, SwiftLint/swift-format, Gitleaks
├─ CI: GitHub Actions ⇄ Xcode Cloud  (Fastlane portable)
└─ Observability: OSLog/MetricKit (no 3rd-party telemetry)
```

The design rule behind this table: **every reversible choice is reversible because the architecture puts a protocol, a wrapper, a package boundary, or a config file in front of it.** Keep those boundaries intact and the stack stays cheap to evolve.

---

## Related documents

- [../CLAUDE.md](../CLAUDE.md) — Canonical Decisions Brief & agent/engineer entry point (the source of truth this doc obeys).
- [./03-architecture.md](./03-architecture.md) — System & client architecture; the module graph and boundaries that make choices reversible.
- [./05-data-model.md](./05-data-model.md) — Schema, RLS, migrations, `Money`/minor-units, price-history trigger.
- [./06-design-system.md](./06-design-system.md) — Liquid Glass design language, Materials fallback, custom flow renderer.
- [./07-security-and-privacy.md](./07-security-and-privacy.md) — Keychain, LocalAuthentication, RLS, hardened RPCs, privacy label.
- [./09-engineering-practices.md](./09-engineering-practices.md) — Testing strategy, SwiftLint/swift-format rules, CI gates, Definition of Done.
- [./11-substimate-analysis.md](./11-substimate-analysis.md) — Predecessor stack and the specific bugs/patterns we keep, improve, and cut.
- [./12-decisions-adr.md](./12-decisions-adr.md) — ADRs (SwiftData-vs-GRDB, no-DI-framework, iOS 18 floor, etc.).
