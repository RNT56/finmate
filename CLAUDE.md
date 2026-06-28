# CLAUDE.md — Finmate Single Source of Truth & Agent/Engineer Entry Point

> **The first file you read.** It orients any engineer or AI agent in minutes, states the locked decisions and non-negotiables, and points precisely into [`/docs`](./docs/00-index.md) for depth. If something here conflicts with code, the docs win over code, and the [Canonical Decisions Brief](#3-locked-decisions-non-negotiable) wins over everything.

---

## 1. What Finmate is

Finmate is a **private-first, Apple-grade personal finance companion for iPhone** — a native Swift/SwiftUI app for tracking subscriptions, income, expenses, money-flow, assets/investments, and multi-currency planning, with a flawless, polished **Liquid Glass** experience.

It is the **modern, leaner, hardened successor to Substimate** — an existing React 19 + Vite + Supabase **web** app ([RNT56/Substimate](https://github.com/RNT56/Substimate)). Finmate keeps Substimate's product domain and vision but reimagines it as a **native iOS app** on the same Supabase backend contract. It deliberately **fixes Substimate's mistakes**: float-based money becomes `Int64` minor units, nine competing visual styles collapse into one Liquid Glass design language, client-side market-data calls move server-side, and there is real automated test coverage. See [docs/11-substimate-analysis.md](./docs/11-substimate-analysis.md) for the full migration map.

A **web client is now in scope** as a committed **second client after the iOS foundation** ([ADR-0021](./docs/12-decisions-adr.md), amending ADR-0002): a separate Vite + React 19 + TypeScript + `supabase-js` app under `web/`, reusing the **identical** Supabase backend contract (schema + RLS + Edge Functions + generated types) and the [docs/13](./docs/13-algorithms-and-calculations.md) algorithms (reimplemented in TypeScript), in the **same one Liquid Glass design language** (CSS `backdrop-filter`). **iOS remains the lead client.** Full plan: [docs/16-web-client.md](./docs/16-web-client.md).

---

## 2. Current status

**Greenfield → in build. Docs complete; backend deployment-ready; M0 foundation + M1–M6 (Subscriptions, Income & Expenses, money-flow, payday calendar, assets/crypto/multi-currency, CSV import) built, compiled, and tested on both clients.**

- [x] Remote repo exists but is **empty**: <https://github.com/RNT56/finmate.git>
- [x] Canonical Decisions Brief locked by product owner (2026-06-27)
- [x] Documentation set authored — `CLAUDE.md`, `README.md`, `/docs/00`–`16`.
- [x] **Backend deployment-ready** — Supabase schema (`supabase/migrations/`, 9 ordered migrations), Edge Functions (`market-data`, `delete-account` — both pass `deno check`), `config.toml`, seed, `scripts/` deploy helpers.
- [x] **M0–M6 (iOS) executed & verified** — `Packages/FinmateCore` (`Domain` + `Shared`) implements the [docs/13](./docs/13-algorithms-and-calculations.md) algorithms (incl. §6 cash-flow metrics) with passing unit tests (`swift test`); the iOS app (`App/`, generated from `project.yml` via XcodeGen) **builds for the iPhone 17 / iOS 26 simulator** and boots — Liquid Glass UI, root `TabView`, a Subscriptions slice (list + add, a **detail** screen, a **Swift Charts** category-distribution analytic, delete/reorder), and a live **Cash Flow** tab — **Income & Expenses + cash-flow metrics (M2)** with the **Monthly Income / Monthly Expenses / Net / Savings-rate %** KPIs computed by the Domain `CashFlowMetrics` math. **M3 (cost-tracker money-flow) shipped** — the bucketed money-flow **value model** per [ADR-0016](./docs/12-decisions-adr.md) (`MoneyFlow`: income + Fixed/Variable/Subscriptions buckets, `totalExpensesMinor`, the derived `savingsMinor = max(0, income − expenses)` clamp, [docs/13](./docs/13-algorithms-and-calculations.md) §6.5) is in the shared core (Swift `Domain` + web `core/`, unit-tested with matching vectors), rendered as a `Canvas`/`Path` Sankey on iOS and inline SVG on web, and wired into the Cash Flow screen on **both** clients (Income → Fixed/Variable/Subscriptions/Savings with proportional ribbons). **M4 (payday calendar) shipped** — a pure recurrence engine (`PaydayCalendar` / `recurrence.ts`: subscription charges, income paydays, fixed-expense due dates with anchor-based day-of-month clamping, [docs/13](./docs/13-algorithms-and-calculations.md) §11) in the shared core with matching Swift+TS vectors, surfaced as a month-calendar with event dots + day detail on **both** clients, plus an iOS `UNUserNotificationCenter` reminder scheduler (ADR-0013, gated). **M5 (assets, crypto calculator, multi-currency) shipped** — `FinancialAsset`/`AssetTransaction` + average-cost valuation (ADR-0015: unrealized gain/loss, portfolio total, allocation distribution), a `CurrencyConverter`-backed BTC/sats calculator, and an EUR/USD/BTC display-currency switcher, surfaced as an Assets screen (allocation donut) + a Calculator under a **More** hub on **both** clients — using sample exchange rates pending the live `market-data` Edge Function wiring. **M6 (CSV import) shipped** — a pure RFC-4180-lite importer (tokenizer + header aliases + per-row validation + valid/errors **preview before write**, [docs/13](./docs/13-algorithms-and-calculations.md) §9) in the shared core (`SubscriptionCSVImporter` / `csvImport.ts`, unit-tested), with an Import screen (paste/file → preview → import valid rows) under the **More** hub on **both** clients.
- [x] **Web client scaffolded & verified** ([ADR-0021](./docs/12-decisions-adr.md)) — a separate Vite + React 19 + TypeScript + `supabase-js` app under `web/`; **builds** (`npm --prefix web run build`) and previews the Home + Subscriptions + **Cash Flow** slices in the Liquid Glass language (CSS `backdrop-filter`), with passing Vitest tests whose TS `core/` mirrors the Swift `Domain` and shares [docs/13](./docs/13-algorithms-and-calculations.md)'s test vectors. The web **Cash Flow** section ships the same **M2** KPIs (Monthly Income / Monthly Expenses / Net / Savings-rate %) **plus the M3 money-flow Sankey** (SVG) and the **M4 payday calendar** (month grid + the shared recurrence engine), and the **M5 Assets / Calculator / More** screens (portfolio €27,250 / +€5,250, allocation donut, BTC calculator, EUR/USD/BTC switcher), plus **M6 CSV import** (validate + preview), so iOS and web agree on the figures. Architecture & plan: [docs/16-web-client.md](./docs/16-web-client.md). iOS remains the lead client.
- [ ] **Remaining build:** feature pillars M7–M8 (full UIs on **both** iOS and web), the live `market-data` Edge Function wiring (clients use sample exchange rates today), the real Supabase-backed data layer (swap the in-memory repos for `supabase-swift` / `supabase-js` against RLS), local DB apply (`supabase db reset`, needs Docker running), and hosted deploy (needs the owner's Supabase account).

> **For agents:** `supabase/` (deployable backend) and `Packages/FinmateCore` + `App/` (the iOS app — regenerate the project with `xcodegen generate`) now **exist**; the **web client** lives under `web/` (Vite + React 19 + TS). Keep all of them in lock-step with the normative docs ([docs/05](./docs/05-data-model.md), [docs/13](./docs/13-algorithms-and-calculations.md)) — the iOS Swift core and the web TypeScript core share the [docs/13](./docs/13-algorithms-and-calculations.md) algorithms and test vectors. Build the app: `xcodebuild -project Finmate.xcodeproj -scheme Finmate -destination 'platform=iOS Simulator,name=iPhone 17' build`. Run core tests: `swift test --package-path Packages/FinmateCore`. Web: `npm --prefix web run dev` / `npm --prefix web run test`.

---

## 3. Locked decisions (non-negotiable)

These come from the product owner and are dated **2026-06-27**. Do not contradict them. Rationale and revisit conditions live in [docs/12-decisions-adr.md](./docs/12-decisions-adr.md).

| # | Decision | Detail |
|---|----------|--------|
| 1 | **Platform** | iOS-first, **native Swift / SwiftUI** as the **lead client**. iPhone, mobile-only for the iOS v1. No React Native, no Flutter, no cross-platform UI (iOS UI stays native). iPad / Mac Catalyst are post-v1. **A web client is now in scope** as a *separate* second client after the iOS foundation — Vite + React 19 + TypeScript over the **same Supabase backend contract**, **not** a shared UI codebase ([ADR-0021](./docs/12-decisions-adr.md), amending ADR-0002; see [docs/16-web-client.md](./docs/16-web-client.md)). |
| 2 | **Backend** | **Supabase** — managed PostgreSQL + Auth + RLS + Edge Functions + Realtime + Storage, accessed via the official `supabase-swift` SDK. Security centered on RLS deriving ownership from `auth.uid()`. |
| 3 | **v1 scope** | **All feature pillars** ship in v1: subscriptions + analytics, income & expenses, cost-tracker money-flow, payday calendar, CSV import, assets/investments, crypto/BTC calculator, multi-currency, settings/theming. An internal build order (milestones **M0..Mn**) still applies — see [docs/08-roadmap-and-milestones.md](./docs/08-roadmap-and-milestones.md). |
| 4 | **Design** | One cohesive **Liquid Glass** language. iOS 26+ Liquid Glass APIs (`glassEffect`, `GlassEffectContainer`, `glassEffectID`, `.glass`/`.glassProminent` button styles, scroll-edge effects) with **graceful fallback** to system Materials (`.ultraThinMaterial`, `.regularMaterial`, …) on iOS 18–25. Light + dark + system. Explicitly **not** Substimate's 9 styles. |
| 5 | **Deployment target** | **Minimum iOS 18.0.** Design-complete Liquid Glass on iOS 26+, automatic Materials fallback on 18–25. Built with **Xcode 26+ / Swift 6** (strict concurrency). |
| 6 | **Execution underway** | The initial docs-only pass is complete; implementation has begun. **M0 foundation + M1 Subscriptions + M2 Income & Expenses** are built, compiled, and tested on **both** clients (iOS + web). See [§2](#2-current-status) for the live status. |

---

## 4. Tech stack at a glance

Full rationale and version pins in [docs/04-tech-stack.md](./docs/04-tech-stack.md).

| Layer | Choice | Notes |
|-------|--------|-------|
| Language | Swift 6 (strict concurrency) | `SWIFT_STRICT_CONCURRENCY=complete` |
| UI | SwiftUI | iOS 26 Liquid Glass APIs + Materials fallback |
| State | Observation framework | `@Observable`, `@Bindable`, `@Environment` — not `ObservableObject` |
| Concurrency | Swift Concurrency | `async`/`await`, actors, `@MainActor` |
| Min OS / Tooling | iOS 18.0 / Xcode 26+ | |
| Local persistence | **SwiftData** (iOS 17+) | Offline cache behind repository protocols; GRDB/SQLite noted as fallback if SwiftData limits complex queries |
| Charts | **Swift Charts** | Native. Sankey/money-flow is **not** built in → custom `Canvas`/`Path` flow renderer in DesignSystem |
| Navigation | `NavigationStack` + typed paths + lightweight coordinator/router | Root is a `TabView` |
| Backend | Supabase (Postgres + Auth + RLS + Edge Functions + Realtime + Storage) | via `supabase-swift` |
| Money | `Int64` **minor units** + ISO currency code | `Decimal` for compute/format; dedicated `Money` value type. **Never** `Double`/`Float` |
| Auth | Supabase Auth: Sign in with Apple + email/password | Tokens in **Keychain**, never `UserDefaults` |
| Modularization | Local Swift Packages (SPM) | Thin app target |
| Testing | Swift Testing / XCTest, swift-snapshot-testing, XCUITest | Unit tests for **all** pure logic |
| Lint/format | SwiftLint + swift-format | Enforced in CI |
| CI/CD | GitHub Actions + Fastlane + TestFlight | Xcode Cloud as alternative; Gitleaks secret scan |
| Logging | OSLog (structured) | No PII in logs |

---

## 5. Repository / module layout (target)

> **Target structure — does not exist yet.** Build to this. Details and dependency rules in [docs/03-architecture.md](./docs/03-architecture.md).

**Module graph (acyclic). Arrows = "depends on". Features never depend on each other.**

```
                    ┌─────────────────────────────┐
                    │  App (target / composition   │
                    │  root: @main, DI, routing)   │
                    └──────────────┬──────────────┘
                                   │
           ┌───────────────────────┴───────────────────────┐
           ▼                                                 ▼
   ┌───────────────┐                                ┌──────────────────┐
   │  Features/*   │                                │  Core packages    │
   │  Auth         │                                │                   │
   │  Home         │   each Feature depends on ───▶ │  DesignSystem     │
   │  Subscriptions│   Domain (repo protocols) +    │  DataLayer        │
   │  CashFlow     │   DesignSystem — NOT DataLayer  │  Domain (Models)  │
   │  CostTracker  │                                │  Shared (Utils)   │
   │  Calendar     │                                └─────────┬────────┘
   │  Import       │                                          │
   │  Assets       │   Core dependency direction:             ▼
   │  Calculator   │   DesignSystem ─▶ Domain, Shared
   │  Settings     │   DataLayer    ─▶ Domain, Shared
   └───────────────┘   Domain       ─▶ Shared (leaf-ish)
                        Shared       ─▶ (no internal deps)
```

| Package | Responsibility |
|---------|----------------|
| **App** (target) | Composition root: `@main`, dependency injection, root `TabView`, router wiring. Thin. |
| **Features/\*** | One package (or product) per pillar: `Auth`, `Home`, `Subscriptions`, `CashFlow`, `CostTracker`, `Calendar`, `Import`, `Assets`, `Calculator`, `Settings`. Views + `@Observable` Stores/ViewModels. Depend only on `Domain` (which holds the repository **protocols**) and `DesignSystem`. **Must not import `DataLayer`** — the module-boundary lint forbids it. |
| **DesignSystem** | Tokens, Liquid Glass primitives + Materials fallback, components, iconography, Swift Charts wrappers, custom Sankey/flow renderer. |
| **DataLayer** | Supabase client wrapper, repository **implementations** (the protocols themselves live in `Domain`), sync engine, local SwiftData cache. |
| **Domain** (Models) | Entities, value types, the `Money` type, currency, **repository protocols (interfaces)**. No UI, no Supabase. |
| **Shared** (Utilities) | Formatting, currency math, logging, feature flags. Leaf package. |

Proposed top-level repo layout:

```
finmate/
├─ CLAUDE.md                 ← you are here
├─ README.md
├─ docs/                     ← 00–16 (see §8)
├─ App/                      ← Xcode app target (lead client)
├─ Packages/
│  ├─ Domain/
│  ├─ Shared/
│  ├─ DesignSystem/
│  ├─ DataLayer/
│  └─ Features/              ← Auth, Home, Subscriptions, …
├─ web/                      ← web client: Vite + React 19 + TS + supabase-js
│  └─ src/                   ← core/ (TS algorithm port), lib/supabase, features/*, components, styles/glass.css (see docs/16)
├─ supabase/                 ← migrations, RLS policies, Edge Functions (shared by both clients)
├─ fastlane/
└─ .github/workflows/        ← build, test, lint, gitleaks
```

---

## 6. Golden rules / non-negotiables

Anyone (human or agent) writing code in this repo **must** follow these. Each maps to a doc with the full rules.

- [ ] **Money is `Int64` minor units only** — cents for fiat, satoshis for BTC (`satsPerBTC = 100_000_000`). Store `amount_minor: Int64` + ISO `currency`. Compute/format via `Decimal` and the `Money` value type. **Never** `Double`/`Float`. **Never** pre-convert to a display currency before storing (Substimate's bug). → [docs/05-data-model.md](./docs/05-data-model.md)
- [ ] **RLS on every table.** Ownership derives from `auth.uid()`. Owner-only policies, `created_at`/`updated_at` triggers, sensible `CHECK` constraints. SECURITY DEFINER RPCs are hardened: `SET search_path = public`, `REVOKE ALL FROM PUBLIC`, `GRANT EXECUTE TO authenticated`, per-row owner checks. → [docs/07-security-and-privacy.md](./docs/07-security-and-privacy.md)
- [ ] **No secrets in the client.** Only the public **anon** key ships. **No** service-role key, **no** provider secrets in the bundle. Secrets live in Edge Function environment. Auth tokens in **Keychain**, never `UserDefaults`. → [docs/07-security-and-privacy.md](./docs/07-security-and-privacy.md)
- [ ] **Offline-first via repository protocols.** Local cache (SwiftData) is the read source; remote (Supabase) is the source of truth. Writes are **optimistic then synced**. Conflicts: **last-write-wins per field** using `updated_at`. Stores call protocols, never SDK types directly. → [docs/03-architecture.md](./docs/03-architecture.md)
- [ ] **One design language.** Liquid Glass via DesignSystem primitives only. No ad-hoc colors/blurs/materials in feature code. Honor light/dark/system. → [docs/06-design-system.md](./docs/06-design-system.md)
- [ ] **Swift 6 strict concurrency.** `@MainActor` UI, actors for shared mutable state, typed throwing errors, structured `OSLog`. **No force-unwraps on production paths.** → [docs/09-engineering-practices.md](./docs/09-engineering-practices.md)
- [ ] **Tests for all pure logic.** Money math, currency conversion, analytics aggregation, CSV import parsing — all unit-tested (Substimate had none). Snapshot tests for DesignSystem; XCUITest for critical flows. → [docs/09-engineering-practices.md](./docs/09-engineering-practices.md)
- [ ] **Accessibility is first-class.** Dynamic Type, VoiceOver labels, reduce-motion, sufficient contrast on every component. → [docs/06-design-system.md](./docs/06-design-system.md)
- [ ] **Single canonical field names.** No `amount` vs `monthlyCost`, no `favorite` vs `isFavorite` duality. snake_case in Postgres, camelCase in Swift. → [docs/05-data-model.md](./docs/05-data-model.md)

---

## 7. How to build / run / test (target commands)

> **Targets, not yet runnable** — no project exists. These are the commands the structure in [§5](#5-repository--module-layout-target) will support, mirrored by [docs/09-engineering-practices.md](./docs/09-engineering-practices.md) and `.github/workflows/`.

```bash
# Build the app for an iPhone 16 simulator (iOS 18+).
xcodebuild \
  -scheme Finmate \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build

# Run the full app test suite (unit + UI) on the simulator.
xcodebuild \
  -scheme Finmate \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test

# Fast, package-only unit tests (pure logic: Money, currency, analytics, CSV).
swift test --package-path Packages/Domain
swift test --package-path Packages/DataLayer

# Lint & format (must pass in CI).
swiftlint --strict
swift-format lint --recursive --strict .

# Local CI parity, build/test/lint/TestFlight via Fastlane.
fastlane test          # build + test
fastlane beta          # build + upload to TestFlight

# Supabase backend (local dev stack + apply migrations).
supabase start
supabase db reset      # re-applies supabase/migrations against local Postgres
supabase functions serve   # run Edge Functions locally (e.g. market-data)
```

Secret scanning runs in CI via **Gitleaks**; never commit keys. Local pre-commit can run `gitleaks detect --no-banner`. A root `.gitignore` already excludes `.env`, `supabase/.env`, `*.xcconfig`, and signing material.

**Backend deploy (ready now):** `scripts/setup-backend.sh` brings up the local stack and applies all migrations; `scripts/deploy-backend.sh` pushes the schema and deploys both Edge Functions to a linked project. Full runbook: [docs/15-deployment.md](./docs/15-deployment.md).

---

## 8. Documentation map

All docs are GitHub-flavored Markdown. From a `docs/` file, link to another as `./05-data-model.md`; to root files as `../CLAUDE.md`. Start at [docs/00-index.md](./docs/00-index.md) for the canonical reading order.

| Doc | Purpose | Read this when… |
|-----|---------|-----------------|
| [README.md](./README.md) | Public project overview | You want the outside-in pitch / repo landing page |
| [docs/00-index.md](./docs/00-index.md) | Documentation index & reading order | You're starting and want the guided path |
| [docs/01-vision-and-principles.md](./docs/01-vision-and-principles.md) | Vision, mission, product principles | You need the "why" and the product north star |
| [docs/02-product-spec.md](./docs/02-product-spec.md) | Features, flows, screens, acceptance criteria | You're building a feature and need exact behavior |
| [docs/03-architecture.md](./docs/03-architecture.md) | System & client architecture | You're wiring modules, repositories, sync, navigation |
| [docs/04-tech-stack.md](./docs/04-tech-stack.md) | Technology stack & rationale | You need version pins or a tool decision's "why" |
| [docs/05-data-model.md](./docs/05-data-model.md) | Domain & data model — schema, RLS, migrations | You're touching entities, SQL, RLS, or money fields |
| [docs/06-design-system.md](./docs/06-design-system.md) | Liquid Glass design system | You're building UI, components, charts, accessibility |
| [docs/07-security-and-privacy.md](./docs/07-security-and-privacy.md) | Security, privacy & hardening | You touch auth, secrets, RLS, Keychain, privacy |
| [docs/08-roadmap-and-milestones.md](./docs/08-roadmap-and-milestones.md) | Roadmap & milestones (M0..Mn) | You need build order and what ships when |
| [docs/09-engineering-practices.md](./docs/09-engineering-practices.md) | Engineering practices & quality gates | You need CI rules, testing, Definition of Done |
| [docs/10-task-backlog.md](./docs/10-task-backlog.md) | Task backlog & TODOs | You're picking up work or recording new tasks |
| [docs/11-substimate-analysis.md](./docs/11-substimate-analysis.md) | Substimate analysis & migration map | You need the KEEP/IMPROVE/CUT mapping |
| [docs/12-decisions-adr.md](./docs/12-decisions-adr.md) | Architecture Decision Records | You want the rationale + revisit conditions for a decision |
| [docs/13-algorithms-and-calculations.md](./docs/13-algorithms-and-calculations.md) | Algorithms, calculations, conversions & stats | You're implementing money math, currency conversion, analytics, CSV parsing, prediction, recurrence, or sync — with test vectors |
| [docs/14-visualizations-and-charts.md](./docs/14-visualizations-and-charts.md) | Visualizations, charts, diagrams & the Sankey renderer | You're building a chart, the money-flow renderer, a dashboard card, or a diagram |
| [docs/15-deployment.md](./docs/15-deployment.md) | Deployment runbook (backend) | You're standing up / deploying the Supabase backend (migrations, Edge Functions, secrets, environments) |
| [docs/16-web-client.md](./docs/16-web-client.md) | Web client — architecture & plan | You're building the web client under `web/` (Vite + React 19 + TS), the TypeScript algorithm port, or its Liquid Glass CSS |

---

## 9. Working agreements for AI agents

When you act on this repository:

- [ ] **Keep docs in sync with code.** If you change behavior, schema, or architecture, update the relevant `/docs` file in the **same** change. Docs are the source of truth; stale docs are a bug.
- [ ] **Never contradict the Canonical Decisions Brief** ([§3](#3-locked-decisions-non-negotiable)). If a task seems to require it, stop and surface the conflict; propose an ADR in [docs/12-decisions-adr.md](./docs/12-decisions-adr.md) rather than silently diverging.
- [ ] **Follow the design system.** Use DesignSystem primitives; do not introduce new visual styles, colors, or material hacks in feature code. → [docs/06-design-system.md](./docs/06-design-system.md)
- [ ] **Never weaken security.** Do not move secrets into the client, disable RLS, loosen RPC grants, store tokens outside Keychain, or call market-data providers from the client. Market data goes through the Edge Function. → [docs/07-security-and-privacy.md](./docs/07-security-and-privacy.md)
- [ ] **Update the task backlog.** Check items off, add discovered work, and reference doc sections in [docs/10-task-backlog.md](./docs/10-task-backlog.md).
- [ ] **Respect module boundaries.** Features depend on `Domain` (which holds the repository **protocols**) + `DesignSystem` only — never on another Feature and **never import `DataLayer`** (the module-boundary lint forbids it). Stores talk to repository **protocols**, not Supabase types. Repository **implementations** live in `DataLayer`.
- [ ] **Write tests with the logic.** Any pure logic (money, currency, analytics, CSV) ships with unit tests in the same change.
- [ ] **Conventional commits, PRs, protected `main`.** Trunk-based with required checks; satisfy the Definition of Done in [docs/09-engineering-practices.md](./docs/09-engineering-practices.md).

---

## 10. Glossary

| Term | Meaning |
|------|---------|
| **Liquid Glass** | iOS 26 glass material system (`glassEffect`, `GlassEffectContainer`, `glassEffectID`, `.glass`/`.glassProminent`). Finmate's single design language, with Materials fallback on iOS 18–25. |
| **Minor units** | Smallest indivisible unit of a currency: cents for EUR/USD, satoshis for BTC. Stored as `Int64` `amount_minor`. |
| **`Money`** | Domain value type pairing `amount_minor: Int64` with an ISO `currency` code; uses `Decimal` for computation and formatting. |
| **satsPerBTC** | `100_000_000` — satoshis in one bitcoin. |
| **RLS** | Row Level Security — Postgres feature gating every row by `auth.uid()`; enabled on all Finmate tables. |
| **SECURITY DEFINER RPC** | A Postgres function running with its owner's privileges; hardened with `SET search_path = public`, `REVOKE ALL FROM PUBLIC`, `GRANT EXECUTE TO authenticated`, and per-row owner checks. |
| **anon key** | Public Supabase API key safe to ship in the client; carries no elevated privileges (gated by RLS). |
| **service-role key** | Privileged Supabase key that bypasses RLS. **Never** ships in the app; server-side only. |
| **Repository protocol** | Swift protocol abstracting data access; lets Stores stay backend-agnostic and enables mocking and a future backend swap. |
| **Offline-first** | Local cache serves reads instantly; writes are optimistic then synced; conflicts resolved last-write-wins per field via `updated_at`. |
| **Sankey / money-flow** | Flow diagram of income → expenses/savings for the cost tracker. Not in Swift Charts → custom `Canvas`/`Path` renderer in DesignSystem. |
| **Store / ViewModel** | `@Observable` object a View observes (unidirectional MVVM); calls repository protocols. |
| **Substimate** | The predecessor React 19 + Vite + Supabase web app this product is reimagined from. |
| **Edge Function** | Supabase server-side function (e.g. crypto/BTC market data) where provider keys stay server-side. |
| **Usage state** | A subscription's `active \| rarely \| unused` flag, feeding usage analytics. |
| **Payday calendar** | Calendar surfacing income paydays and upcoming subscription/expense charges. |
| **Web client** | The second client (after iOS): a Vite + React 19 + TypeScript + `supabase-js` app under `web/`, reusing the same Supabase backend contract and the [docs/13](./docs/13-algorithms-and-calculations.md) algorithms (TypeScript port), in the same Liquid Glass language via CSS `backdrop-filter`. See [docs/16-web-client.md](./docs/16-web-client.md) ([ADR-0021](./docs/12-decisions-adr.md)). |
| **Backend contract** | The portable layer shared across clients: schema + RLS + Edge Functions + generated types, plus the [docs/13](./docs/13-algorithms-and-calculations.md) algorithms. Shared by iOS and web; not shared UI. |

---

## Related documents

- [docs/00-index.md](./docs/00-index.md) — start here for the guided reading order
- [docs/03-architecture.md](./docs/03-architecture.md) — module graph, repositories, sync, navigation
- [docs/05-data-model.md](./docs/05-data-model.md) — schema, RLS, money, migrations
- [docs/07-security-and-privacy.md](./docs/07-security-and-privacy.md) — the hardened security posture
- [docs/12-decisions-adr.md](./docs/12-decisions-adr.md) — rationale and revisit conditions for the locked decisions
- [docs/16-web-client.md](./docs/16-web-client.md) — the web client architecture & plan (second client on the same backend)
