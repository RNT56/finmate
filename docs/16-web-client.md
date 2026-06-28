# Web Client — Architecture & Plan

> The architecture, structure, and build plan for Finmate's **web client** — a separate Vite + React 19 + TypeScript + `supabase-js` application that reuses the **identical Supabase backend contract** and the [`./13-algorithms-and-calculations.md`](./13-algorithms-and-calculations.md) algorithms (reimplemented in TypeScript), expressed in the **same one Liquid Glass design language** as iOS via CSS `backdrop-filter` glass.

This document is the authoritative reference for **how the web client is built and how it stays coherent with iOS**. It exists because the owner brought a full web interface into scope ([ADR-0021](./12-decisions-adr.md#adr-0021--web-client-brought-into-scope-amends-adr-0002)), amending the original "web deferred" sequencing of [ADR-0002](./12-decisions-adr.md#adr-0002--ios-first-web-second-client-after-the-ios-foundation). **iOS remains the lead client**; the web mirrors it.

The portable layer shared across clients is the **Supabase backend** (schema + RLS + Edge Functions + generated types) and the **algorithms in [`./13`](./13-algorithms-and-calculations.md)** — *not* UI code ([ADR-0001](./12-decisions-adr.md#adr-0001--native-ios-swift--swiftui-over-cross-platform) keeps iOS UI native SwiftUI; this client builds its own React UI over the same contract). Where this doc restates a rule that is normative elsewhere (schema, money math, design tokens, security), the normative doc wins and is cross-linked.

---

## Table of contents

1. [Scope & relationship to iOS](#1-scope--relationship-to-ios)
2. [Stack & versions](#2-stack--versions)
3. [The shared backend contract](#3-the-shared-backend-contract)
4. [Project structure](#4-project-structure)
5. [The TypeScript algorithm core (mirrors `Packages/FinmateCore`)](#5-the-typescript-algorithm-core-mirrors-packagesfinmatecore)
6. [Design parity — Liquid Glass in CSS](#6-design-parity--liquid-glass-in-css)
7. [Auth via `supabase-js`](#7-auth-via-supabase-js)
8. [Environment & secrets (anon key only)](#8-environment--secrets-anon-key-only)
9. [Build, test & deploy](#9-build-test--deploy)
10. [Milestones — the web tracks the iOS pillars](#10-milestones--the-web-tracks-the-ios-pillars)
11. [Related documents](#11-related-documents)

---

## 1. Scope & relationship to iOS

- **A separate client, not a shared UI codebase.** The web app is its own React project under `web/`. It does **not** share UI with iOS (no React Native Web, no cross-platform UI layer — rejected in [ADR-0021](./12-decisions-adr.md#adr-0021--web-client-brought-into-scope-amends-adr-0002)). It shares the **backend** and the **math**, nothing else.
- **iOS is the lead client.** iOS sets the product bar (the [`./02-product-spec.md`](./02-product-spec.md) pillars, the design language, the algorithm semantics). The web mirrors iOS pillar-for-pillar and tracks the same milestones (see [§10](#10-milestones--the-web-tracks-the-ios-pillars)).
- **One design language, two expressions.** [ADR-0009](./12-decisions-adr.md#adr-0009--a-single-liquid-glass-design-language-retire-the-9-themes) is upheld: the web mirrors the **same Liquid Glass tokens and language** with CSS, and does **not** invent a second visual identity or revive Substimate's nine styles.
- **No backend change.** The web is purely additive. It introduces no web-specific tables, **no RLS relaxation**, and no new service-role surface. It points at the **same Supabase project** as iOS.

```text
                         ┌──────────────────────────────────────────┐
                         │   Supabase project (single, shared)        │
                         │   Postgres + RLS + Auth + Edge Functions   │
                         │   + Realtime + Storage                     │
                         └──────────────────────────────────────────┘
                              ▲ identical contract (schema + RLS      ▲
                              │  + Edge Functions + generated types)  │
              anon key only ──┤                                       ├── anon key only
                              │                                       │
                ┌─────────────┴─────────────┐         ┌───────────────┴───────────────┐
                │   iOS app (lead client)    │         │   Web client (this doc)        │
                │   Swift 6 / SwiftUI        │         │   Vite + React 19 + TS         │
                │   FinmateCore (Domain math) │         │   web/core (same math in TS)   │
                │   Liquid Glass (glassEffect)│         │   Liquid Glass (backdrop-filter)│
                └────────────────────────────┘         └────────────────────────────────┘
```

---

## 2. Stack & versions

Treat versions as the **floor**; bump within the same major line freely. A major bump of `supabase-js`, React, or Vite is a decision worthy of an ADR (mirrors the policy in [`./04-tech-stack.md`](./04-tech-stack.md)).

| Concern | Choice | Version / target | Rationale (1-liner) |
|---|---|---|---|
| Language | **TypeScript** (strict) | 5.4+ | Type safety; `strict: true`, `noUncheckedIndexedAccess`. |
| UI framework | **React** | 19.x | Matches Substimate's lineage; modern hooks/`use`/Actions. |
| Build tool / dev server | **Vite** | 5.x | Fast HMR, static SPA build, first-class TS. |
| Backend SDK | **`@supabase/supabase-js`** | 2.x | Same backend contract as `supabase-swift`; Auth + PostgREST + Realtime + Functions + Storage. |
| Routing | **React Router** | 6.x | Client-side routing for the SPA. |
| State | React state + small stores (e.g. **Zustand**) | 4.x | Lightweight, unidirectional — parallels the iOS `@Observable` Store pattern. |
| Charts | **Recharts** (standard charts) + custom **SVG** flow renderer | latest minor | Native charts for standard cases; the Sankey/money-flow is bespoke (mirrors [ADR-0011](./12-decisions-adr.md#adr-0011--swift-charts--a-custom-canvas-flow-renderer-for-sankey)) — SVG/`<path>` in the web, `Canvas`/`Path` on iOS. |
| Styling | **CSS** (CSS variables + `backdrop-filter` glass) | — | One token set in `styles/glass.css`; no CSS-in-JS framework that forks the visual language. |
| Unit / logic testing | **Vitest** | 1.x | Runs the [`./13`](./13-algorithms-and-calculations.md) test vectors against the TS core. |
| Lint / format | **ESLint** + **Prettier** | latest | CI-enforced, mirrors SwiftLint/swift-format's role on iOS. |
| Secret scanning | **Gitleaks** (shared CI) | 8.x | Same gate as iOS; never commit keys. |

**Not Next.js, not React Native Web.** Both were considered and rejected in [ADR-0021](./12-decisions-adr.md#adr-0021--web-client-brought-into-scope-amends-adr-0002): the data is per-user and RLS-gated behind `supabase-js`, so a client-rendered SPA on a static host is the simplest, cheapest fit; and a shared-UI framework would contradict [ADR-0001](./12-decisions-adr.md#adr-0001--native-ios-swift--swiftui-over-cross-platform).

---

## 3. The shared backend contract

The web client binds to the **same** backend artifacts the iOS app uses — the entire portable contract preserved deliberately by [ADR-0002](./12-decisions-adr.md#adr-0002--ios-first-web-second-client-after-the-ios-foundation)/[ADR-0003](./12-decisions-adr.md#adr-0003--supabase-as-the-backend):

| Contract artifact | Source of truth | How the web consumes it |
|---|---|---|
| **Schema** (tables, columns, CHECK constraints) | [`./05-data-model.md`](./05-data-model.md) + `supabase/migrations/` | Generated TS types (`supabase gen types typescript`) → `web/src/lib/supabase/types.ts`. Money columns are `*_minor: number` (integer minor units). |
| **RLS policies** (owner-only via `auth.uid()`) | [`./05-data-model.md`](./05-data-model.md), [`./07-security-and-privacy.md`](./07-security-and-privacy.md) | Enforced server-side; the web simply queries — a client bug cannot leak another user's rows. No web-side authorization logic. |
| **Edge Functions** (`market-data`, `delete-account`) | `supabase/functions/` | Called via `supabase.functions.invoke('market-data')`. Provider keys stay server-side; the web never calls a market-data provider directly ([ADR-0010](./12-decisions-adr.md#adr-0010--server-side-market-data-via-supabase-edge-functions)). |
| **Generated types** | `supabase gen types` | Single typed surface for queries; canonical `snake_case` columns mapped to `camelCase` at the web boundary, mirroring iOS ([ADR-0020](./12-decisions-adr.md#adr-0020--single-canonical-domain-field-names-kill-substimate-duality)). |
| **Realtime / sync** | Postgres change streams | Optional latency layer over delta-poll, same posture as iOS ([ADR-0014](./12-decisions-adr.md#adr-0014--supabase-realtime-in-v1-as-a-latency-optimization-over-delta-polling)); conflict policy is last-write-wins per field ([ADR-0012](./12-decisions-adr.md#adr-0012--last-write-wins-per-field-conflict-resolution-using-updated_at)). |

> **Single canonical names.** As on iOS, the web maps Postgres `snake_case` ↔ TS `camelCase` at exactly one boundary (`lib/supabase`), with no `amount`/`monthlyCost` or `favorite`/`isFavorite` duality ([ADR-0020](./12-decisions-adr.md#adr-0020--single-canonical-domain-field-names-kill-substimate-duality)).

---

## 4. Project structure

The web client lives under `web/` and mirrors what is being built there. It separates the **portable algorithm core** (`core/`) from the **backend binding** (`lib/supabase`), the **feature UIs** (`features/*`), the **shared components**, and the **design tokens** (`styles/glass.css`). Features depend on `core` and components — never directly on raw SDK types scattered through the tree (the SDK is wrapped in `lib/supabase`), paralleling the iOS module-boundary discipline ([`./03-architecture.md`](./03-architecture.md)).

```text
web/
├─ index.html
├─ package.json
├─ vite.config.ts
├─ tsconfig.json
├─ .env.example                 # VITE_SUPABASE_URL + VITE_SUPABASE_ANON_KEY (anon only)
└─ src/
   ├─ core/                     # ── portable algorithm core (mirrors Packages/FinmateCore/Domain) ──
   │  ├─ money.ts               #   Money as Int64-equivalent minor units (number), HALF-UP scaling
   │  ├─ currency.ts            #   CurrencyCode (EUR/USD/BTC), satsPerBTC, CurrencyConverter (eurUsd/btcEur/btcUsd)
   │  ├─ normalization.ts       #   BillingPeriod normalization (weekly ×52/12, quarterly /3, yearly /12); income frequency
   │  ├─ predictor.ts           #   SubscriptionPredictor (exact-then-substring, <2-char guard, keyword→category)
   │  ├─ analytics.ts           #   category distribution, monthly trends, lifetime cost, money-flow buckets
   │  └─ __tests__/             #   the docs/13 test vectors (shared with the Swift suite)
   ├─ lib/
   │  └─ supabase/
   │     ├─ client.ts           #   createClient(url, anonKey) — the only place the SDK is constructed
   │     ├─ types.ts            #   `supabase gen types typescript` output (the schema contract)
   │     └─ repositories.ts     #   typed query helpers; snake_case ↔ camelCase mapping at this boundary
   ├─ features/
   │  └─ subscriptions/         #   first vertical slice (list + add), driven by core math, renders with sample data
   │     ├─ SubscriptionsList.tsx
   │     ├─ AddSubscription.tsx
   │     ├─ useSubscriptions.ts  #   store/hook calling the repository (or sample data when no backend)
   │     └─ sampleData.ts        #   mirrors App/Sources SampleData so the slice previews with no live backend
   ├─ components/               #   shared Liquid Glass primitives: GlassCard, GlassButton, KPI tile, chart wrappers
   ├─ styles/
   │  └─ glass.css              #   CSS variables (tokens) + backdrop-filter glass utilities + reduced-transparency fallback
   ├─ App.tsx                   #   router + tab shell (mirrors the iOS TabView IA)
   └─ main.tsx                  #   composition root
```

This mirrors the iOS layout: `core/` ↔ `Packages/FinmateCore` (`Domain` math), `lib/supabase` ↔ `DataLayer`, `features/subscriptions` ↔ the iOS Subscriptions slice (`App/Sources/Subscriptions.swift`), `components` + `styles/glass.css` ↔ `DesignSystem` (`App/Sources/DesignSystem.swift`), and `sampleData.ts` ↔ the iOS `SampleData` / `InMemorySubscriptionRepository`.

---

## 5. The TypeScript algorithm core (mirrors `Packages/FinmateCore`)

The `core/` modules are a **faithful TypeScript port** of the Swift reference in `Packages/FinmateCore/Sources/Domain/*` (`Money`, `CurrencyConverter`, `BillingPeriodMath`, `Analytics`, `SubscriptionPredictor`). They carry the **same [`./13`](./13-algorithms-and-calculations.md) test vectors** so the two implementations stay provably equivalent.

**Money rule (identical to iOS — [ADR-0005](./12-decisions-adr.md#adr-0005--money-as-int64-minor-units)).** Money is **integer minor units** — cents for fiat, satoshis for BTC (`satsPerBTC = 100_000_000`). In TypeScript these are integer `number` values, which is **safe**: the largest representable amount (21 000 000 BTC × 10⁸ sats ≈ 2.1 × 10¹⁵) is well under `Number.MAX_SAFE_INTEGER` (2⁵³ ≈ 9.0 × 10¹⁵). **Never** use floating-point for stored money; compute via integer/Decimal-style helpers and round **HALF-UP** when scaling a major-unit value down to minor units. Display conversion is **non-mutating** — it returns a new amount in the target currency and never rewrites a stored value (this is the fix for Substimate's pre-store-conversion bug).

| Swift reference (`Domain/*`) | TS module | What it ports |
|---|---|---|
| `Money`, `MoneyError`, `CurrencyCode`, `satsPerBTC` | `core/money.ts`, `core/currency.ts` | Minor-units value type; `parse` (HALF-UP, reject negatives / over-precision / overflow); `formatted` (locale-aware via `Intl.NumberFormat`); `adding`/`subtracting` (currency-mismatch guard). |
| `CurrencyConverter`, `ExchangeRates` | `core/currency.ts` | `eurUsd` (USD per 1 EUR), `btcEur` (EUR per 1 BTC), `btcUsd` (USD per 1 BTC) + inverses; `convert` rounds HALF-UP to the target's minor units; rates fetched from the `market-data` Edge Function. |
| `BillingPeriodMath`, `IncomeFrequency` | `core/normalization.ts` | Monthly normalization (weekly ×52/12, monthly ×1, quarterly /3, yearly /12) and annual (quarterly ×4 directly to avoid compounding rounding error); income monthly factors. |
| `Analytics`, `LifetimeCost`, `MoneyFlow`, `MonthlyTrendPoint` | `core/analytics.ts` | Category distribution (descending, share, per-item average); lifetime cost (Σ monthly × months over price segments); money-flow buckets with `savings = max(0, income − expenses)` ([ADR-0016](./12-decisions-adr.md#adr-0016--cost-tracker-money-flow-redesign-bucketed-sankey-with-drill-down)). |
| `SubscriptionPredictor` | `core/predictor.ts` | **Exact name match first, then case-insensitive substring**; names **shorter than 2 chars never predict**; keyword→category table (exact-then-substring), default `"Other"`. Ported from Substimate's `subscriptionPredictions.ts`, same seed and keyword tables as the Swift port. |

> **Test parity is a hard gate.** The `core/__tests__/` Vitest suite uses the worked numeric vectors from [`./13`](./13-algorithms-and-calculations.md). A vector that passes in Swift must pass in TypeScript; divergence is a bug in one of the two ports, not a "platform difference."

---

## 6. Design parity — Liquid Glass in CSS

The web mirrors the **single Liquid Glass language** from [`./06-design-system.md`](./06-design-system.md) ([ADR-0009](./12-decisions-adr.md#adr-0009--a-single-liquid-glass-design-language-retire-the-9-themes)). It does **not** invent a new look. The mapping from the iOS glass strategy to CSS:

| iOS (SwiftUI) | Web (CSS) | Notes |
|---|---|---|
| `glassEffect(.regular, in: shape)` (Tier A) | `backdrop-filter: blur(20px) saturate(180%)` + translucent fill + hairline border | Glass surfaces are translucent over content, never over a flat brand wash (Deference — same glass hygiene as iOS). |
| Materials fallback `.regularMaterial` (Tier B, iOS 18–25) | the same `backdrop-filter` recipe; degrade `blur` where `backdrop-filter` is unsupported | One recipe; browsers without `backdrop-filter` fall back to a near-opaque fill. |
| Reduce-Transparency tier (Tier C) | `@media (prefers-reduced-transparency: reduce)` → opaque `--fm-surface-opaque` fill + hairline | Mandatory legibility fallback, paralleling iOS's `accessibilityReduceTransparency`. |
| `Color.fm…` tokens (Asset Catalog) | CSS variables in `styles/glass.css` | Same hex values, light/dark via `@media (prefers-color-scheme)` or a `data-theme` attribute. |
| `Radius.lg = 20`, `Radius.md = 14` | `--fm-radius-lg: 20px`, `--fm-radius-md: 14px` | Standard glass card = `lg`; buttons/small cards = `md`. |
| `ChartPalette.categorical` (7 + BTC) | `--fm-chart-1..7`, `--fm-chart-btc` | Same ordered palette; BTC orange `#F7931A` is fixed and never reassigned. |

```css
/* web/src/styles/glass.css — tokens mirror docs/06; values are identical to the iOS Color.fm… set */
:root {
  /* surfaces */
  --fm-background: #F2F3F7;
  --fm-surface: #FFFFFF;
  --fm-surface-opaque: #FFFFFF;         /* reduced-transparency replacement */
  --fm-hairline: rgba(0,0,0,0.08);
  /* text */
  --fm-label: #0A0A0A;
  --fm-label-secondary: rgba(60,60,67,0.60);
  /* accent + financial semantics */
  --fm-accent: #0A84FF;                 /* single brand accent (HSL 211°,100%,52%) */
  --fm-financial-up: #1F9D55;           /* income / gain — always paired with an ↑ glyph */
  --fm-financial-down: #D7263D;         /* expense / loss — always paired with a ↓ glyph */
  --fm-btc: #F7931A;                    /* fixed Bitcoin orange, BTC contexts only */
  /* shape */
  --fm-radius-md: 14px;
  --fm-radius-lg: 20px;
}
@media (prefers-color-scheme: dark) {
  :root {
    --fm-background: #0B0C0F;
    --fm-surface: #1B1E25;
    --fm-surface-opaque: #20232B;
    --fm-hairline: rgba(255,255,255,0.12);
    --fm-label: #FFFFFF;
    --fm-label-secondary: rgba(235,235,245,0.60);
    --fm-financial-up: #30D158;
    --fm-financial-down: #FF6961;
    --fm-btc: #FFA62B;
  }
}

/* the one glass recipe, used by GlassCard / chrome (parallels iOS .glassBackground) */
.fm-glass {
  background: color-mix(in srgb, var(--fm-surface) 60%, transparent);
  backdrop-filter: blur(20px) saturate(180%);
  -webkit-backdrop-filter: blur(20px) saturate(180%);
  border: 0.5px solid var(--fm-hairline);
  border-radius: var(--fm-radius-lg);
}
@media (prefers-reduced-transparency: reduce) {
  .fm-glass {                            /* Tier C — opaque, always legible */
    background: var(--fm-surface-opaque);
    backdrop-filter: none;
    -webkit-backdrop-filter: none;
  }
}
```

The same glass hygiene rules apply as on iOS ([`./06-design-system.md`](./06-design-system.md) §2.4): **no glass-on-glass**, glass needs content behind it, text on glass sits on a legible substrate, one prominent glass per screen, and financial up/down is conveyed by **color *and* glyph** (`↑`/`↓`), never color alone.

---

## 7. Auth via `supabase-js`

- **Same auth providers as iOS** ([ADR-0003](./12-decisions-adr.md#adr-0003--supabase-as-the-backend)): Supabase Auth with **Sign in with Apple** and **email/password**, against the same project.
- The SDK is constructed in exactly one place (`lib/supabase/client.ts`) with the project URL + anon key. The web uses `supabase.auth.signInWithPassword`, `supabase.auth.signInWithOAuth({ provider: 'apple' })`, `getSession`, and `onAuthStateChange`.
- **Session storage.** On the web there is no Keychain; the SDK persists the session in the browser's storage layer with auto-refresh. This is the standard `supabase-js` posture — it does **not** weaken the iOS Keychain rule ([`./07-security-and-privacy.md`](./07-security-and-privacy.md)), which governs the native app. Sensitive data is owner-scoped by RLS regardless of where the session token lives, and the web clears the session on sign-out.
- All data access flows through RLS exactly as on iOS; the web performs **no** client-side authorization — ownership derives from `auth.uid()` server-side.

---

## 8. Environment & secrets (anon key only)

Mirrors the iOS posture in [`./07-security-and-privacy.md`](./07-security-and-privacy.md): **only the public anon key ships**.

- The web reads `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` from the environment at build time (Vite inlines `VITE_`-prefixed vars). A committed **`web/.env.example`** documents these two keys and nothing else.
- **Never** ship the service-role key or any provider secret in the web bundle — they live only in the Edge Function environment. Market data is fetched **server-side** via `market-data` ([ADR-0010](./12-decisions-adr.md#adr-0010--server-side-market-data-via-supabase-edge-functions)).
- Real `.env` files are git-ignored; **Gitleaks** runs in CI as it does for iOS.
- The first vertical slice **builds and renders with sample data** (`features/subscriptions/sampleData.ts`), so the app compiles and previews with **no live backend** — the anon key is only required to talk to a real project.

```bash
# web/.env.example  (committed — placeholders only, anon key is public/safe-to-ship)
VITE_SUPABASE_URL=https://YOUR-PROJECT-ref.supabase.co
VITE_SUPABASE_ANON_KEY=YOUR-PUBLIC-ANON-KEY
```

---

## 9. Build, test & deploy

```bash
# from web/
npm install
npm run dev        # Vite dev server with HMR (renders the slice on sample data)
npm run test       # Vitest — runs the docs/13 algorithm vectors against core/
npm run lint       # ESLint + Prettier (CI gate)
npm run build      # Vite production build → web/dist/ (static SPA)
npm run preview    # serve the production build locally
```

- **Build output is a static SPA** (`web/dist/`). Deploy it to any static host (Vercel, Netlify, Cloudflare Pages, or an S3/CDN bucket). No server tier is required — the data path is `supabase-js` → the **same Supabase project** the iOS app uses, gated by RLS.
- **Backend deploy is unchanged.** The web introduces **no** new migrations or Edge Functions; it consumes the existing `supabase/` backend exactly as iOS does (see [`./15-deployment.md`](./15-deployment.md)). Regenerate `lib/supabase/types.ts` with `supabase gen types typescript` whenever the schema changes.
- **CI parity.** Lint, type-check, and the Vitest algorithm suite run on every change, alongside the shared Gitleaks secret scan — the web's equivalent of the iOS quality gates in [`./09-engineering-practices.md`](./09-engineering-practices.md).

---

## 10. Milestones — the web tracks the iOS pillars

The web client **follows the iOS pillars** (M1…M8 in [`./08-roadmap-and-milestones.md`](./08-roadmap-and-milestones.md)) rather than defining a parallel roadmap. iOS leads each pillar; the web mirrors it on the same backend contract once the pillar's data model and algorithms are settled.

- **First slice (now):** Subscriptions list + add, driven by `core/` math and rendered with **sample data** — the web counterpart of the built iOS Subscriptions slice. No live backend required to preview.
- **Then, pillar-for-pillar:** Subscriptions + analytics → Income & Expenses + cash-flow → Cost-tracker money-flow (SVG flow renderer) → Calendar → Assets + crypto + multi-currency (via `market-data`) → CSV import → polish / accessibility → hardening.
- **Lock-step rule:** when an iOS pillar changes a [`./13`](./13-algorithms-and-calculations.md) algorithm or a [`./05-data-model.md`](./05-data-model.md) field, the web's `core/` port and `lib/supabase/types.ts` update in the same wave, and the shared test vectors keep both honest.

---

## 11. Related documents

- [`../CLAUDE.md`](../CLAUDE.md) — single source of truth; the web client is in scope per the locked decisions.
- [`./12-decisions-adr.md`](./12-decisions-adr.md) — [ADR-0021](./12-decisions-adr.md#adr-0021--web-client-brought-into-scope-amends-adr-0002) (web in scope), [ADR-0002](./12-decisions-adr.md#adr-0002--ios-first-web-second-client-after-the-ios-foundation) (iOS-first sequencing it amends), [ADR-0001](./12-decisions-adr.md#adr-0001--native-ios-swift--swiftui-over-cross-platform)/[0003](./12-decisions-adr.md#adr-0003--supabase-as-the-backend)/[0005](./12-decisions-adr.md#adr-0005--money-as-int64-minor-units)/[0009](./12-decisions-adr.md#adr-0009--a-single-liquid-glass-design-language-retire-the-9-themes)/[0010](./12-decisions-adr.md#adr-0010--server-side-market-data-via-supabase-edge-functions) (the invariants the web upholds).
- [`./05-data-model.md`](./05-data-model.md) — the schema the web's generated types mirror (normative).
- [`./07-security-and-privacy.md`](./07-security-and-privacy.md) — the anon-key-only, RLS-everywhere, secrets-server-side posture the web shares (normative).
- [`./06-design-system.md`](./06-design-system.md) — the Liquid Glass tokens and hygiene rules the web mirrors in CSS.
- [`./13-algorithms-and-calculations.md`](./13-algorithms-and-calculations.md) — the algorithms (and test vectors) reimplemented in `web/src/core`.
- [`./15-deployment.md`](./15-deployment.md) — the (unchanged) backend the web consumes.
- [`./08-roadmap-and-milestones.md`](./08-roadmap-and-milestones.md) — the iOS pillars the web tracks.
