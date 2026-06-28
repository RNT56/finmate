# Substimate Analysis & Migration Map

> The bridge document: what Substimate (the React 19 + Vite + Supabase web app) actually is, where its bones are good, where it is broken, and exactly how each concept maps to Finmate's native iOS rebuild — **KEEP**, **IMPROVE**, or **CUT**.

Substimate is Finmate's direct predecessor and the source of its product vision. It validated the domain (subscriptions + spending + income + assets + currency-aware planning) and pioneered the security model Finmate inherits (Supabase + RLS + hardened `SECURITY DEFINER` RPCs). It also accumulated real cruft — float money, duplicated field names, a currency-conversion data bug, nine competing visual styles, no automated tests, and web-only navigation. Finmate keeps the proven backend contract and the feature set, and surgically fixes the rest.

This analysis is grounded in a read-only inspection of the Substimate source: `package.json`, `src/types.ts`, `src/contexts/*`, `src/hooks/*`, `src/lib/*`, `src/pages/*`, `src/styles/*`, and `supabase/migrations/*`. Source repo: <https://github.com/RNT56/Substimate>.

---

## 1. Substimate at a glance

| Dimension | Substimate (predecessor) | Finmate (this project) |
| --- | --- | --- |
| Platform | Web SPA (desktop + responsive mobile) | Native iOS, iPhone-first (see [`../CLAUDE.md`](../CLAUDE.md)) |
| UI framework | React 19.2 + React DOM | SwiftUI + Observation |
| Build tool | Vite 8 | Xcode 26 / SwiftPM |
| Language | TypeScript 6 (strict) | Swift 6 (strict concurrency) |
| Routing | `react-router-dom` 7 (`BrowserRouter`) | SwiftUI `NavigationStack` + `TabView` |
| State | React Context (5 providers) | `@Observable` Stores + repositories |
| Backend | **Supabase** (Postgres + Auth + RLS + Realtime) | **Supabase** (same contract) |
| SDK | `@supabase/supabase-js` 2.108 | `supabase-swift` |
| Charts | `recharts` 3.9 (8 files) + `d3-sankey` 0.12 | Swift Charts + custom Canvas/Path Sankey |
| Drag/drop | `@dnd-kit/*` (sortable dashboard + cards) | SwiftUI `.draggable`/`.dropDestination` |
| Dates | `date-fns` 4 | Foundation `Calendar`/`DateComponents` |
| Icons | `lucide-react` | SF Symbols + bespoke symbols |
| Styling | Tailwind 4 + **9 hand-written CSS theme files** | One Liquid Glass design system |
| Money storage | `decimal(10,2)` in DB, `number` (float) in TS | `Int64` minor units + ISO currency code |
| Tests | **None** (zero `.test`/`.spec`/`__tests__`) | Swift Testing + snapshots + XCUITest |
| CI | GitHub Actions: lint, typecheck, build, `npm audit`, Gitleaks | GitHub Actions: build, test, SwiftLint, swift-format, Gitleaks |

Roughly 12,600 lines of TypeScript/TSX across `src/`, plus ~40 SQL migrations under `supabase/migrations/`.

---

## 2. Application structure inventory

### 2.1 Pages / routes (`src/App.tsx`, `react-router-dom`)

Substimate composes seven provider layers (`AuthProvider` → `ThemeProvider` → `CurrencyProvider` → `SubscriptionProvider` → `ToastProvider`, wrapped in an `ErrorBoundary` and `BrowserRouter`) around a single `Layout` route with these children:

| Route | Component | Purpose |
| --- | --- | --- |
| `/` (index) | `HomePage` → `SubscriptionList` + `SubscriptionAnalytics` + `UsageStatistics` | Subscriptions list, analytics, usage stats; renders `LandingPage` when signed out |
| `/finance` | `FinancePage` | Income, fixed/variable expenses, assets, transactions |
| `/cost-tracker` | `CostTrackerPage` | Sankey money-flow visualizations, category distribution, monthly trends |
| `/payday-calendar` | `PaydayCalendarPage` | Calendar of paydays and upcoming charges |
| `/calculator` | `CalculatorPage` | Fiat → satoshis ("Sats Calculator") |
| `/settings` | `SettingsPage` | Theme, visual style, currency, account |
| `/import` | `ImportDataPage` | CSV subscription import with preview/validation |

All non-root routes are guarded with `user ? <Page/> : <Navigate to="/" replace/>` — a client-side auth gate (RLS is the real boundary).

### 2.2 Components (`src/components/`)

- **Top-level shell**: `Layout`, `Sidebar` (desktop nav), `MobileHeader` + `MobileMenu` (the parallel mobile nav), `ThemeToggle`, `CurrencySelector`, `SearchBar`, `CategoryFilter`, `ActionButtons`, `ErrorBoundary`.
- **Auth/marketing**: `AuthModal` (email/password), `LandingPage`.
- **Subscriptions**: `SubscriptionList`, `SubscriptionCard`, `SortableSubscriptionCard`, `AddSubscriptionModal`, `EditSubscriptionModal`, `ConfirmDeleteModal`, `IconSelector`, `SubscriptionAnalytics`, `UsageStatistics`.
- **Dashboard**: `DashboardGrid`, `DraggableDashboardCard` (dnd-kit sortable cards).
- **Modals**: `TransactionModal`, `ExpenseModal`, `IncomeModal`, `AssetManagementModal`, `DatePicker`.
- **`components/finance/`**: `KeyMetrics`, `MonthlyTrendsChart`, `CategoryDistributionChart`, `IncomeFlowChart`, `QuickActions`, `IncomeList`, `ExpenseList`, `TransactionList`, `AssetList`, `PaydayDetailModal`.
- **`components/cost-tracker/`**: `SpendingFlowChart` + `IncomeFlowChart` (both `d3-sankey`), `FlowTooltip`, `TooltipBreakdown`, `CategoryDistribution`, `ExpenseBreakdown`, `MonthlyTrendsChart`, `TimeframeSelector`, plus a local `types.ts`.
- **`components/analytics/`**: `LifetimeCosts`, `MonthlyTrends`, `CategoryDistribution`.

### 2.3 Contexts (`src/contexts/`)

| Context | Responsibility | Notes carried into Finmate |
| --- | --- | --- |
| `AuthContext` | Wraps `supabase.auth.signInWithPassword` / `signUp` / `signOut`; exposes `user`, `loading` | **Email/password only — no Sign in with Apple.** Finmate adds Sign in with Apple. |
| `ThemeContext` | `theme` (`light`/`dark`) + `visualStyle` (one of **9**); persists both to `localStorage`; sets `data-theme` / `data-visual-style` on `<html>` | The 9-style switcher is the design debt Finmate eliminates. |
| `CurrencyContext` | `displayCurrency`, `convertAmount`, `formatAmount`; hourly client-side rate refresh; persists to `currency_preferences` | Contains the conversion logic implicated in the pre-store bug; rates fetched **client-side**. |
| `SubscriptionContext` | CRUD + optimistic updates + Realtime subscription; delete via `delete_subscription_directly` RPC; reorder via `batch_update_subscription_order` RPC | Strong optimistic-update + Realtime pattern worth keeping; carries the `monthlyCost`/`amount` and `favorite`/`isFavorite` duality. |
| `ToastContext` | Transient success/error feedback | Pattern kept as native toast/snackbar in DesignSystem. |

### 2.4 Hooks (`src/hooks/`)

- `useSubscriptions.ts` — single-line re-export of the context hook.
- `useSubscriptionAnalytics.ts` (264 lines) — lifetime cost computation walking `subscription_price_history`, plus category distribution and 6-month monthly trends. **Pure-ish analytics math with zero tests.**
- `useFinancialData.ts` (688 lines) — CRUD + Realtime for `financial_assets`, `asset_transactions`, `fixed_expenses`, `variable_expenses`, `income_sources`.
- `useFinanceAnalytics.ts` (111 lines) — income/expense aggregation for the finance dashboard.
- `useDashboardLayout.ts` (98 lines) — reads/writes `dashboard_layouts.layout` (a `text[]` of card ids).
- `useDevice.ts` (32 lines) — viewport/device detection that drives the **desktop-vs-mobile navigation split** (replaced by a single adaptive native UI).

### 2.5 Library / utilities (`src/lib/`, `src/utils/`)

- `supabase.ts` — singleton client from `VITE_SUPABASE_URL` + `VITE_SUPABASE_ANON_KEY`; exposes `supabaseConfigError`.
- `marketData.ts` — **`fetchBitcoinPrices` (CoinGecko `api.coingecko.com`) and `fetchEurUsdRate` (Frankfurter `api.frankfurter.app`) called directly from the browser.**
- `subscriptionCosts.ts` — `getSubscriptionMonthlyAmount`/`...PaymentAmount`/`convert...` helpers that read **`monthlyCost ?? amount`**, i.e. encode the dual-field workaround.
- `constants.ts` — `satsPerBTC = 100000000`, `PROTECTED_CATEGORIES = ['All','Favorites','Other']`, and 18 `DEFAULT_CATEGORIES` (AI Chat, Coding, Diffusion, Streaming, Music, Gaming, Productivity, Audio Generation, Video Generation, Cloud Services, Fitness, Health, Food, Transport, Financial, Creative, Social, Other).
- `subscriptionData.ts` — a **seed dictionary** mapping known service names → `{ vendorURL, icon, typicalAmount? }` (e.g. Netflix, Spotify, ChatGPT, GitHub, Figma), used to prefill the Add sheet.
- `subscriptionPredictions.ts` — a **keyword → category inference map** (e.g. `chatgpt`/`claude`/`gemini` → AI Chat; `cursor`/`copilot`/`github` → Coding; `midjourney`/`runway`/`leonardo` → Diffusion; `netflix`/`disney` → Streaming; `spotify` → Music; `notion`/`linear`/`trello` → Productivity; `adobe`/`figma` → Creative) plus the match logic. **Pure prediction logic with zero tests** — Finmate ports it and unit-tests it (Section 4.11).
- `database.types.ts` — generated Supabase types (the portable contract Finmate also regenerates).

---

## 3. Data model inventory

The schema lives across ~40 timestamped migrations. Tables (all `public`, all RLS-enabled, all keyed by `user_id uuid REFERENCES auth.users`):

| Table | Key columns (Substimate) | Money type today | Finmate change |
| --- | --- | --- | --- |
| `subscriptions` | `name, url, icon, monthly_cost, currency, billing_period, payment_method, category (text), usage_state, start_date, favorite, auto_renew, created_at, updated_at` | `monthly_cost decimal(10,2)` | `amount_minor int64` + `billing_period` enum incl. weekly/quarterly; `category_id` FK; `vendor_url`; `sort_order`, `end_date`, `notes` |
| `subscription_price_history` | `subscription_id, user_id, monthly_cost, currency, effective_from, is_correction` | `decimal` | `amount_minor int64`; trigger-written (kept) |
| `income_sources` | `source, amount, frequency, next_payment, notes` | `numeric` | `amount_minor int64`; frequency incl. `one_time` |
| `fixed_expenses` | `name, amount, category, due_date, frequency, autopay, notes` | `numeric` | `amount_minor int64`; `category_id` FK |
| `variable_expenses` | `name, amount, category, date, notes` | `numeric` | `amount_minor int64`; `category_id` FK |
| `financial_assets` | `name, type, value, quantity, purchase_price, purchase_date, current_price, notes` | `numeric` | `value_minor`, `purchase_price_minor`, `current_price_minor` |
| `asset_transactions` | `asset_id, type (buy/sell/dividend/other), quantity, price, date, fees, notes` | `numeric` | `price_minor`, `fees_minor` |
| `currency_preferences` | `display_currency, exchange_rates (jsonb), last_updated` | n/a | Kept; rates refreshed server-side via Edge Function |
| `dashboard_layouts` | `layout (text[])` | n/a | Kept as `DashboardLayout` (ordered card ids) |

> Categories are stored as a **free-text `category` column** on subscriptions/expenses, surfaced via the `get_user_categories()` RPC (a `GROUP BY` over distinct values) — not a normalized table. Finmate promotes categories to a first-class `Category` entity with `category_id` foreign keys. See [`./05-data-model.md`](./05-data-model.md).

### 3.1 RPCs / functions

- `delete_subscription_directly(sub_id uuid)` — `SECURITY DEFINER`, deletes where `id = sub_id AND user_id = auth.uid()`.
- `batch_update_subscription_order(updates jsonb)` — `SECURITY DEFINER`, validates the input is a non-empty JSONB array, then per-row checks `user_id = auth.uid()` before rewriting `created_at` (Substimate encodes sort order as `created_at` timestamps — a hack Finmate replaces with an explicit `sort_order int`).
- `get_user_categories()` — `SECURITY DEFINER` aggregate of a user's categories.
- `handle_subscription_price_change()` — trigger function (below).

### 3.2 Triggers

- `update_updated_at_column()` → `update_*_updated_at` triggers on each table (`BEFORE UPDATE`, sets `updated_at = now()`). **Kept as a Finmate pattern.**
- `subscription_price_change_trigger` (`AFTER INSERT OR UPDATE OF monthly_cost, currency`) → `handle_subscription_price_change()` writes a `subscription_price_history` row whenever price or currency changes. **This is the auto-price-history mechanism Finmate keeps verbatim in spirit** (re-expressed against `amount_minor`).

### 3.3 RLS

Every table follows the same four-policy pattern, e.g. from the first migration (`20250208144136_light_forest.sql`):

```sql
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own subscriptions"
  ON subscriptions FOR SELECT TO authenticated
  USING (auth.uid() = user_id);
-- + INSERT (WITH CHECK), UPDATE (USING + WITH CHECK), DELETE (USING)
```

This `auth.uid() = user_id` owner-only model is the security foundation Finmate inherits wholesale (see [`./07-security-and-privacy.md`](./07-security-and-privacy.md)).

### 3.4 The two June 2026 hardening migrations (must-read)

Substimate's two most recent migrations are the template for Finmate's hardened RPCs and the documented fix for the currency bug:

1. **`20260627090000_harden_security_definer_functions.sql`** — drops older RPC signatures that accepted a caller-supplied `user_id` and recreates them to derive ownership from `auth.uid()`, with the exact hardening Finmate mandates:
   ```sql
   CREATE OR REPLACE FUNCTION delete_subscription_directly(sub_id uuid)
   RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
   BEGIN
     DELETE FROM subscriptions WHERE id = sub_id AND user_id = auth.uid();
   END; $$;
   REVOKE ALL ON FUNCTION delete_subscription_directly(uuid) FROM PUBLIC;
   GRANT EXECUTE ON FUNCTION delete_subscription_directly(uuid) TO authenticated;
   ```
   Note `SET search_path = public`, `REVOKE ALL FROM PUBLIC`, `GRANT EXECUTE TO authenticated`, and the per-row `auth.uid()` check — exactly the posture in the canonical brief.

2. **`20260627103000_fix_price_history_currency_and_rpc_hardening.sql`** — documents and repairs the **currency-pre-store-conversion bug** (Section 4.3). It adds `currency NOT NULL DEFAULT 'EUR'` + `CHECK (currency IN ('EUR','USD','BTC'))` to `subscriptions` and `subscription_price_history`, normalizes corrupted non-EUR rows back to EUR (because their stored amounts were actually EUR-denominated), backfills `subscription_price_history.currency` from the parent, and rebuilds the price-history trigger to record currency alongside amount.

---

## 4. Strengths to preserve and weaknesses to fix

### 4.1 Genuine strengths (the reasons to evolve, not rewrite from scratch)

- **Coherent backend contract**: clean per-table RLS, hardened `SECURITY DEFINER` RPCs, an `updated_at` trigger convention, and generated types. This is portable and Finmate reuses it directly.
- **Auto subscription price history** via DB trigger — durable, server-enforced, immune to client bugs.
- **Optimistic updates + Realtime** in `SubscriptionContext` (an `optimisticUpdatesRef` set deduplicates the app's own writes echoed back over Realtime, with rollback on failure) — a solid pattern Finmate re-expresses as offline-first sync.
- **Multi-currency support** (EUR/USD/BTC with sats) and a **fiat→sats calculator**.
- **CSV import with a real preview + per-row validation** (`ImportDataPage` validates name, amount, billing period, currency, payment method, usage state and shows a preview table before commit).
- **Subscription prediction & category inference** (`subscriptionData.ts` + `subscriptionPredictions.ts`): a service-name seed dictionary plus keyword→category mapping that prefills vendor URL, icon, amount, and category in the Add sheet. **Genuinely useful, genuinely portable — kept and unit-tested** (Section 4.11).
- **Sankey money-flow cost tracker** and a rich analytics suite (lifetime cost, category distribution, monthly trends, usage stats, payment-method breakdown). The flow visualization itself is **intentionally redesigned** in Finmate (Section 4.10, ADR-0016) — kept as a concept, improved in structure.
- **Multi-series monthly trends** (`MonthlyTrendsChart` / `useFinanceAnalytics`): not just income-vs-expenses but the full series — income, expenses, fixed/variable expenses, subscription costs, investments (sum of `buy` asset-transactions in the month), savings, savings ratio, and investment ratio. **Kept in full** (Section 6.4).
- **Asset distribution donut** (`CategoryDistributionChart` with `type=assets`): portfolio value grouped by asset type/category. **Kept** as a native donut (Section 6.5).
- **Customizable, draggable dashboard** persisted per user.
- **Security-minded recent work**: only the public anon key ships; CI already runs Gitleaks + `npm audit`.

### 4.2 Float money (data-integrity defect)

`monthly_cost` is `decimal(10,2)` in Postgres and surfaces as `number` (IEEE-754 float) throughout TypeScript. `src/types.ts`:

```ts
export interface Subscription {
  amount?: number;       // float
  monthlyCost?: number;  // float
  // ...
}
```

Financial tables (`fixed_expenses.amount`, `variable_expenses.amount`, `financial_assets.value/purchase_price/current_price`, `asset_transactions.price/fees`) are likewise floating numerics coerced through `Number(...)` in `useFinancialData.ts`. Float money accumulates rounding error and is a recurring class of finance-app bug. **Finmate stores integer minor units (`Int64` cents / satoshis) + an ISO currency code, computes with `Decimal`, and wraps it in a `Money` value type.** See [`./05-data-model.md`](./05-data-model.md) and ADR-0005 in [`./12-decisions-adr.md`](./12-decisions-adr.md).

### 4.3 The currency-pre-store-conversion bug (data corruption)

The most damaging Substimate bug: the client **converted non-EUR subscription amounts to EUR before storing them, while keeping the originally selected currency label.** A row could read `monthly_cost = 14.34, currency = 'USD'` when the user actually entered `$15.49` — the stored number was EUR, the label said USD, and every downstream conversion re-applied a rate to an already-converted value. The remediation migration spells it out:

```sql
/* The previous client converted non-EUR subscription amounts to EUR before
   storing them while keeping the selected currency label. Existing non-EUR
   rows are normalized back to EUR because their stored amounts are
   EUR-denominated. New client code stores monthly_cost in the selected
   subscription currency. */
```

**Finmate's rule: store the amount in its native currency, untouched, as `amount_minor` + `currency`. Convert only at read/display time** using rates fetched server-side. This makes the storage layer the single source of truth and conversion a pure, testable function. See ADR-0005 and [`./05-data-model.md`](./05-data-model.md).

### 4.4 Dual field-name cruft (`amount`/`monthlyCost`, `favorite`/`isFavorite`)

`Subscription` carries **both** `amount` and `monthlyCost`, and **both** `favorite` and `isFavorite`, "for backwards compatibility." The transform layer mirrors both on every read:

```ts
const transformSubscription = (data: any): Subscription => ({
  monthlyCost: parseFloat(data.monthly_cost) || 0,
  amount: parseFloat(data.monthly_cost) || 0,   // duplicate of monthlyCost
  isFavorite: data.favorite || false,
  favorite: data.favorite || false,             // duplicate of favorite
  // ...
});
```

…and `subscriptionCosts.ts` reads `monthlyCost ?? amount`, `toggleFavorite` checks `isFavorite || favorite`. Every consumer must defensively check both, multiplying the surface for drift and bugs. The CSV importer perpetuates it (`monthlyCost` *and* `amount` both set per row). **Finmate uses single canonical names** (`amountMinor`, `favorite`) with no shims; the Substimate→Finmate field mapping in Section 6 is the cleanup contract.

### 4.5 Nine competing visual styles (design incoherence)

`ThemeContext` exposes a `VisualStyle` union of **nine** styles — `neumorphic`, `glassmorphic`, `minimal`, `brutalist`, `neobrutalist`, `modern`, `claymorphism`, `aurora`, `retro` — each backed by its own CSS file:

```
src/styles/  aurora.css (202)  brutalist.css (154)  claymorphism.css (198)
glassmorphism.css (339)  minimal.css (223)  modern.css (158)
neobrutalist.css (161)  neumorphism.css (205)  retro.css (252)
+ base.css (283) + index.css (291)
```

That is ~2,750 lines of mutually-redundant CSS implementing the same component set (`.themed-card`, `.themed-button`, `.themed-input`, `.title-gradient`, `--theme-primary`/`--theme-secondary`) nine different ways. No product needs nine identities; it inflated bundle size, fractured QA, and prevented a single polished look. **Finmate ships exactly one design language — Liquid Glass — with light/dark/system appearance only.** See [`./06-design-system.md`](./06-design-system.md) and ADR-0009 in [`./12-decisions-adr.md`](./12-decisions-adr.md).

### 4.6 CSS duplication & token sprawl

Beyond the nine themes, each style redeclares the full token set and component rules; `base.css` + `index.css` add another ~570 lines. Tailwind utility classes are also interleaved inline with `themed-*` classes, so a single visual change can require edits in multiple files. **Finmate centralizes all visual decisions in DesignSystem tokens + reusable SwiftUI components** so a token change propagates everywhere.

### 4.7 No automated tests

A full-tree search finds **zero** test files (`*.test.*`, `*.spec.*`, `__tests__/`). The money math (`subscriptionCosts.ts`), currency conversion (`CurrencyContext.convertAmount`), lifetime-cost analytics (264 lines in `useSubscriptionAnalytics.ts`), and CSV parser (`parseImportRows`) — precisely the logic where the float-money and currency bugs lived — are entirely unverified. **Finmate mandates Swift Testing/XCTest unit tests for all pure logic, snapshot tests for DesignSystem, and XCUITests for critical flows.** See [`./09-engineering-practices.md`](./09-engineering-practices.md).

### 4.8 Web-only, split navigation

Navigation is duplicated across `Sidebar` (desktop) and `MobileHeader` + `MobileMenu` (mobile), branched by `useDevice`. Two nav surfaces must be kept in sync by hand. Sidebar order today: Subscriptions (`/`), Finance, Cost Tracker, Payday Calendar, Sats Calculator, then Settings + Import Data. **Finmate replaces both with one native `TabView` (Home, Subscriptions, Cash Flow, Calendar, More) plus a contextual Add (+) action** — one adaptive navigation truth. See [`./03-architecture.md`](./03-architecture.md) and [`./02-product-spec.md`](./02-product-spec.md).

### 4.9 Client-side market-data fetches (key-exposure + reliability risk)

`marketData.ts` calls CoinGecko and Frankfurter **directly from the browser**, and both `CurrencyContext` (hourly rate refresh) and `CalculatorPage` invoke it client-side. Any future provider that needs an API key would force that key into the client bundle, and rate-limit/CORS failures hit users directly. **Finmate moves all market-data fetching behind a Supabase Edge Function** so provider keys stay server-side and responses can be cached/shared. See ADR-0010 in [`./12-decisions-adr.md`](./12-decisions-adr.md).

### 4.10 Sankey money-flow: intentional redesign (not a faithful port)

Substimate's cost-tracker Sankey flowed **a single `Total Income` node directly to one node per category** — every fixed expense, variable expense, and subscription category got its own leaf, producing a wide, flat fan that was hard to read at a glance.

Finmate **deliberately diverges** here (this is an IMPROVE, not a faithful port). The money-flow is `INCOME` (left) → four top-level **bucket** nodes — **Fixed Expenses, Variable Expenses, Subscriptions, Savings** — where `Savings = max(0, totalIncome − totalExpenses)`. Each bucket is **tap-to-expand**, drilling into its per-category sub-flows (fixed-expense categories, variable-expense categories, subscription categories). This gives a clear top-level overview first, with detail on demand.

Acceptance: the sum of outgoing link widths equals total income; expanding a bucket reveals its category breakdown; empty buckets are omitted. Recorded as **ADR-0016** in [`./12-decisions-adr.md`](./12-decisions-adr.md); see also [`./02-product-spec.md`](./02-product-spec.md). The renderer remains the custom Canvas/Path Sankey in DesignSystem.

### 4.11 Prediction engine & category inference (keep — port the data)

Substimate's `subscriptionData.ts` and `subscriptionPredictions.ts` are a small but high-value asset: a **seed dictionary** of known service names → `{ vendorURL, icon, typicalAmount? }`, plus a **keyword → category inference map**. When the user types a name in the Add sheet, the app prefills vendor URL, icon, a suggested amount, and the category. It is **pure logic and had zero tests** in Substimate.

Finmate **keeps and ports it**:

- **(a) Seed dictionary** — `serviceName → { vendorURL, icon (SF Symbol or asset), typicalAmountMinor? }`, curated from Substimate's data and extensible.
- **(b) Inference map** — keyword → category, e.g. `chatgpt`/`claude`/`gemini` → AI Chat; `cursor`/`copilot`/`github` → Coding; `midjourney`/`runway`/`leonardo` → Diffusion; `netflix`/`disney` → Streaming; `spotify` → Music; `notion`/`linear`/`trello` → Productivity; `adobe`/`figma` → Creative.
- **(c) Match rule** — exact name match first, then case-insensitive substring match.
- **(d) On match** — the Add sheet prefills vendor URL, icon, suggested amount, and category.

This is **pure logic and must be unit-tested** (e.g. *"name contains `github` ⇒ category Coding"*, *"exact match `Netflix` ⇒ Streaming + vendor URL prefilled"*). See [`./09-engineering-practices.md`](./09-engineering-practices.md) and the data model in [`./05-data-model.md`](./05-data-model.md).

### 4.12 Smaller cruft

- **Sort order encoded as `created_at` timestamps** (`batch_update_subscription_order` rewrites timestamps to reorder) → Finmate uses an explicit `sort_order int`.
- **`billing_period` limited to `monthly | yearly`** in Substimate → Finmate adds `weekly` and `quarterly`.
- **Email/password auth only** → Finmate adds Sign in with Apple and stores tokens in the Keychain (Substimate relies on the JS SDK's browser storage).
- **No biometric app lock, no in-app account deletion/export** → Finmate adds all three (App Store requirements + privacy posture).

---

## 5. KEEP / IMPROVE / CUT matrix

| Substimate concept | Verdict | Finmate treatment |
| --- | --- | --- |
| Supabase (Postgres + Auth + RLS + Realtime + Storage) backend | **KEEP** | Same managed backend via `supabase-swift`; portable contract for a future web client |
| Owner-only RLS via `auth.uid() = user_id` on every table | **KEEP** | Identical policy pattern on every Finmate table |
| Hardened `SECURITY DEFINER` RPCs (`SET search_path`, `REVOKE ALL`, `GRANT … authenticated`, per-row `auth.uid()`) | **KEEP** | Mandated for all RPCs (mirrors `20260627090000` migration) |
| Auto price-history trigger (`handle_subscription_price_change`) | **KEEP** | Re-expressed against `amount_minor`; behavior preserved |
| `updated_at` trigger convention | **KEEP** | Used for last-write-wins conflict resolution in sync |
| Optimistic updates + toast feedback + Realtime | **KEEP** | Offline-first repository: optimistic writes, then sync; native toasts |
| Multi-currency (EUR/USD/BTC, sats) | **KEEP** | `Money` type; extensible currency set; `satsPerBTC = 100_000_000` |
| Fiat→sats calculator | **KEEP** | Native Calculator feature; market data via Edge Function |
| CSV import with preview + per-row validation | **KEEP** | Native importer; same validation rules + DB CHECK constraints; **with unit tests** |
| Subscription prediction & category inference (`subscriptionData.ts` + `subscriptionPredictions.ts`) | **KEEP** | Port seed dictionary + keyword→category map; prefill Add sheet; pure logic, unit-tested (Section 4.11) |
| Sankey / money-flow cost tracker | **IMPROVE** | Concept kept; **redesigned** to Income → bucket nodes (Fixed / Variable / Subscriptions / Savings) with tap-to-expand drill-down. Intentional divergence from Substimate's flat per-category fan. Custom Canvas/Path renderer in DesignSystem (ADR-0016) |
| Analytics suite (lifetime, category, trends, usage, payment-method) | **KEEP** | Native Swift Charts; analytics math unit-tested. Trends keep the **full multi-series set** (income, expenses, fixed/variable, subscription costs, investments, savings, savings ratio, investment ratio) and the **asset-distribution donut** (portfolio value by type) |
| Customizable/draggable dashboard (`dashboard_layouts`) | **KEEP** | `DashboardLayout` of card ids; SwiftUI drag/drop |
| Default + protected categories (`All`/`Favorites`/`Other`) | **KEEP** | Seeded `Category` rows; protected set preserved |
| `get_user_categories()` RPC | **KEEP** | Equivalent RPC against normalized categories |
| Float money (`decimal`/`number`) | **IMPROVE** | `Int64` minor units + ISO currency; `Decimal` math; `Money` type |
| Pre-store EUR conversion of non-EUR amounts | **IMPROVE** | Store native currency untouched; convert only at display time |
| Dual field names (`amount`/`monthlyCost`, `favorite`/`isFavorite`) | **IMPROVE** | Single canonical names; no compat shims |
| Sort order via `created_at` timestamps | **IMPROVE** | Explicit `sort_order int` column |
| `billing_period` ∈ {monthly, yearly} | **IMPROVE** | Adds `weekly`, `quarterly` |
| Free-text `category` column | **IMPROVE** | First-class `Category` entity + `category_id` FK |
| Client-side market-data fetch (CoinGecko/Frankfurter) | **IMPROVE** | Supabase Edge Function; provider keys server-side |
| Email/password auth only, SDK browser token storage | **IMPROVE** | Adds Sign in with Apple; tokens in iOS Keychain |
| `recharts` + `d3-sankey` (web charting) | **IMPROVE** | Native Swift Charts + custom Canvas Sankey |
| No biometric lock / account deletion / export | **IMPROVE** | Face ID/Touch ID lock, in-app account deletion + data export |
| No automated tests | **IMPROVE** | Swift Testing/XCTest + snapshot + XCUITest with CI gates |
| Nine visual styles (`VisualStyle` union + 9 CSS files) | **CUT** | One Liquid Glass language (light/dark/system) |
| Duplicated theme CSS / token sprawl (`base.css` + `index.css` + 9) | **CUT** | DesignSystem tokens + reusable components |
| Sidebar + MobileHeader/MobileMenu split (`useDevice`) | **CUT** | Single native `TabView` + contextual Add |
| Web routing (`react-router-dom`, `BrowserRouter`) | **CUT** | SwiftUI `NavigationStack` + typed paths + router |
| Backwards-compat shims / dead fields (`description`, `color`, `reminderDate`, `order`) | **CUT** | Removed; clean domain model |
| Web layout cruft (Tailwind utility soup, responsive branches) | **CUT** | Adaptive SwiftUI layout |

---

## 6. Feature-by-feature old → new mapping

### 6.1 Navigation & shell

| Substimate | Finmate |
| --- | --- |
| `Layout` + `Sidebar` (desktop) + `MobileHeader`/`MobileMenu` (mobile), branched by `useDevice` | One adaptive `RootView` with a `TabView`: **Home · Subscriptions · Cash Flow · Calendar · More** |
| `react-router-dom` routes + `<Navigate>` auth guards | `NavigationStack` per tab + typed navigation paths + lightweight router; auth gate at app composition root |
| `ActionButtons` / per-page add buttons | One prominent contextual **Add (+)** action |

### 6.2 Subscriptions (`/` → Subscriptions tab)

| Substimate | Finmate |
| --- | --- |
| `SubscriptionList` / `SubscriptionCard` / `SortableSubscriptionCard` | `SubscriptionsListView` + Liquid Glass `SubscriptionCard`; SwiftUI drag to reorder |
| `AddSubscriptionModal` / `EditSubscriptionModal` / `ConfirmDeleteModal` | Native sheets driven by an `@Observable` `SubscriptionsStore` |
| `subscriptionData.ts` + `subscriptionPredictions.ts` prefill on name entry | Ported prediction engine: exact-then-substring match prefills vendor URL, icon, suggested amount, and category; pure logic, unit-tested (Section 4.11) |
| `monthly_cost` (float) + `monthlyCost`/`amount` | `amountMinor: Int64` + `currency`, single name |
| `favorite`/`isFavorite` | `favorite: Bool` |
| Reorder via `batch_update_subscription_order` (timestamps) | `sort_order` updates through the subscriptions repository |
| `subscription_price_history` + trigger | Same trigger, `amount_minor`; history surfaced in detail view |

### 6.3 Cash Flow (`/finance` + `/cost-tracker` → Cash Flow tab)

| Substimate | Finmate |
| --- | --- |
| `FinancePage` + `useFinancialData` (income, fixed/variable expenses, assets, transactions) | `CashFlowView` over `IncomeStore` / `ExpensesStore` via repositories |
| `IncomeList`/`ExpenseList`/`TransactionList`/`AssetList` + modals | Native list + sheet editors |
| `CostTrackerPage` + `SpendingFlowChart`/`IncomeFlowChart` (`d3-sankey`, Total Income → per-category fan) | **Redesigned** Sankey: Income → bucket nodes (Fixed / Variable / Subscriptions / Savings) with tap-to-expand drill-down; custom Canvas/Path renderer in DesignSystem (ADR-0016) |
| `KeyMetrics`, `MonthlyTrendsChart`, `CategoryDistributionChart` (`recharts`) | Swift Charts views; aggregation unit-tested. Trends keep the **full series** (income, expenses, fixed/variable, subscription costs, investments, savings, savings ratio, investment ratio); expense category-distribution is **windowed** by a timeframe selector |
| Float `amount`/`value`/`price` | `*_minor: Int64` everywhere |

### 6.4 Calendar (`/payday-calendar` → Calendar tab)

| Substimate | Finmate |
| --- | --- |
| `PaydayCalendarPage` + `PaydayDetailModal` (income `next_payment` + upcoming charges) | `CalendarView` (paydays + upcoming subscription/expense charges) + native detail sheet |
| `date-fns` scheduling math | Foundation `Calendar`/`DateComponents`, unit-tested |

### 6.5 More (Assets, Calculator, Import, Settings → More tab)

| Substimate | Finmate |
| --- | --- |
| `financial_assets` + `asset_transactions` via `AssetManagementModal`/`TransactionModal` | Assets feature; `value_minor`/`price_minor`/`fees_minor` |
| `CategoryDistributionChart` with `type=assets` (asset distribution) | Native **asset-distribution donut** grouping portfolio value by asset type/category |
| `CalculatorPage` (fiat→sats) calling `marketData.ts` client-side | Calculator feature; rates via Edge Function |
| `ImportDataPage` CSV parser + preview + validation | Native importer; same rules + DB CHECK constraints + unit-tested parser |
| `SettingsPage` (theme + 1 of 9 visual styles + currency + account) | Settings: appearance (system/light/dark), default currency, biometric lock, account deletion + export |

### 6.6 Cross-cutting

| Substimate | Finmate |
| --- | --- |
| `AuthContext` (email/password) | Auth feature: Sign in with Apple **and** email/password; tokens in Keychain |
| `ThemeContext` (light/dark + 9 styles) | Appearance only (system/light/dark) in DesignSystem |
| `CurrencyContext` (client rate refresh, conversion) | `CurrencyStore` + Edge-Function rates; pure `Money` conversion |
| `ToastContext` | Native toast/snackbar component |
| `ErrorBoundary` | Typed throwing errors + structured `OSLog` + graceful failure states |

---

## 7. Lessons learned (why the Finmate decisions are what they are)

1. **Money must be exact and self-describing.** Float money plus pre-store conversion produced silent corruption that needed a remediation migration. → Integer minor units + native-currency storage + convert-at-display, all unit-tested. (ADR-0005)
2. **Duplicated field names are a bug factory.** `amount`/`monthlyCost` and `favorite`/`isFavorite` forced every consumer to guard both. → Single canonical names, no shims.
3. **Untested finance logic is where bugs hide.** The exact modules with bugs (conversion, money math, analytics, CSV parse) had zero tests. → Tests are non-negotiable for all pure logic. (See [`./09-engineering-practices.md`](./09-engineering-practices.md))
4. **Design surface area is a tax.** Nine themes meant 9× the CSS, QA, and drift, and still no single polished identity. → One Liquid Glass language. (ADR-0009)
5. **Secrets and third-party calls belong on the server.** Client-side market data blocks any keyed provider and exposes users to upstream failures. → Edge Functions. (ADR-0010)
6. **The backend contract was the durable asset.** RLS, hardened RPCs, the price-history trigger, and generated types survive the platform change intact — proving the value of a clean, owner-scoped Supabase schema. (See [`./05-data-model.md`](./05-data-model.md), [`./07-security-and-privacy.md`](./07-security-and-privacy.md))
7. **Two navigation surfaces drift.** The sidebar/mobile-menu split duplicated intent. → One native `TabView`.
8. **Implicit sort keys leak.** Reordering by mutating `created_at` overloads a column with two meanings. → Explicit `sort_order`.

### Migration checklist (carried into the roadmap)

- [ ] Port the Supabase schema with `amount_minor: Int64` + `currency` on every money-bearing table.
- [ ] Re-implement the price-history trigger and hardened RPCs (`delete_subscription_directly`, `batch`/`sort_order` update, `get_user_categories`) against the new schema.
- [ ] Promote categories to a `Category` table with `category_id` FKs; seed defaults + protected set.
- [ ] Add `weekly`/`quarterly` billing periods and `sort_order`.
- [ ] Build the market-data Edge Function (BTC/EUR/USD); remove all client-side provider calls.
- [ ] Add Sign in with Apple; store tokens in the Keychain; add biometric lock, account deletion, and data export.
- [ ] Port the CSV importer with single canonical fields and a unit-tested parser.
- [ ] Port the prediction engine (seed dictionary + keyword→category map from `subscriptionData.ts`/`subscriptionPredictions.ts`) into Domain/Shared as pure, unit-tested logic; wire prefill into the Add Subscription sheet.
- [ ] Implement the custom Canvas/Path Sankey renderer in DesignSystem and the **redesigned bucketed flow** (Income → Fixed/Variable/Subscriptions/Savings, tap-to-expand) per ADR-0016.
- [ ] Implement the full monthly-trends series (income, expenses, fixed/variable, subscription costs, investments, savings, savings ratio, investment ratio) and the asset-distribution donut.
- [ ] Write unit tests for money math, currency conversion, analytics aggregation, prediction/inference, and CSV parsing before porting downstream UI.

---

## Related documents

- [`../CLAUDE.md`](../CLAUDE.md) — Single source of truth & entry point
- [`./05-data-model.md`](./05-data-model.md) — Finmate schema, RLS, and migrations (the cleaned-up model)
- [`./07-security-and-privacy.md`](./07-security-and-privacy.md) — RLS + hardened RPC posture inherited from Substimate
- [`./12-decisions-adr.md`](./12-decisions-adr.md) — ADRs for money type, single design language, and Edge-Function market data
- [`./03-architecture.md`](./03-architecture.md) — Native client architecture replacing the web SPA
- [`./02-product-spec.md`](./02-product-spec.md) — Feature specs that re-home Substimate's pages into native tabs
- [`./06-design-system.md`](./06-design-system.md) — The single Liquid Glass language replacing the 9 styles
