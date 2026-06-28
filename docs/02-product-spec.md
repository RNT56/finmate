# Product Specification — Features, Flows, Screens, Acceptance Criteria

> The complete, end-to-end behavioral contract for Finmate v1: information architecture, every feature pillar's screens/flows/validation/states, and testable acceptance criteria. This is the document an engineer or AI agent builds the UI from.

---

## 0. How to read this document

- **Scope:** All nine feature pillars target **v1** (per the [Canonical Decisions Brief](../CLAUDE.md)). The nine pillars are: subscriptions + analytics, income & expenses, cost-tracker money-flow, payday calendar, CSV import, assets/investments, crypto/BTC calculator, multi-currency, and settings/theming. Auth/Onboarding and Home/Dashboard are **foundational surfaces**, not counted as pillars. Build order is defined in [`./08-roadmap-and-milestones.md`](./08-roadmap-and-milestones.md); this spec defines *what* each pillar does, not *when*.
- **Platform:** iPhone, portrait-first, **iOS 18.0 minimum**. Liquid Glass design on iOS 26+, Materials fallback on iOS 18–25. See [`./06-design-system.md`](./06-design-system.md).
- **Money:** All amounts are **integer minor units** (`Int64`) plus an ISO currency code — cents for EUR/USD, satoshis for BTC. `Money` is a value type. The UI never sees a `Double`. See [`./05-data-model.md`](./05-data-model.md).
- **Acceptance criteria** are written as Given/When/Then scenarios or checklists. They are the source for XCUITest critical-flow tests and `Swift Testing` unit tests (see [`./09-engineering-practices.md`](./09-engineering-practices.md)).
- **"vs Substimate"** notes call out where the native reimagining intentionally differs from the React/Vite predecessor analyzed in [`./11-substimate-analysis.md`](./11-substimate-analysis.md).

**Term glossary used throughout:** *Store* = an `@Observable` view model. *Repository* = a protocol-backed data source coordinating local SwiftData cache + Supabase remote. *Sheet* = a modally presented partial-height or full-height SwiftUI sheet. *Optimistic write* = the local cache and UI update immediately; the remote sync happens in the background and rolls back on failure with a toast.

---

## 1. Information Architecture

### 1.1 Root structure

Finmate replaces Substimate's split navigation (desktop right-sidebar drawer in `Sidebar.tsx` + `MobileHeader.tsx`/`MobileMenu.tsx`) with a **single native `TabView`** as the root. There is no hamburger menu and no slide-over drawer.

```
RootView (TabView, 5 tabs)
├── Home            (tag: .home)        — overview / customizable dashboard
├── Subscriptions   (tag: .subscriptions)
├── Cash Flow       (tag: .cashFlow)    — income + expenses + cost-tracker flows
├── Calendar        (tag: .calendar)    — payday + upcoming charges
└── More            (tag: .more)        — Assets, Calculator, Import, Settings
```

Each tab owns its own `NavigationStack` with a typed `path: [Route]`. Tab state and navigation paths live in an `@Observable AppRouter` injected via `@Environment`. The architecture (router, coordinator, repository protocols) is specified in [`./03-architecture.md`](./03-architecture.md); this document specifies the *screens reachable* from each route.

```mermaid
graph TD
    Root[TabView] --> H[Home Tab\nNavigationStack]
    Root --> S[Subscriptions Tab\nNavigationStack]
    Root --> C[Cash Flow Tab\nNavigationStack]
    Root --> CAL[Calendar Tab\nNavigationStack]
    Root --> M[More Tab\nNavigationStack]

    H --> H1[Dashboard]
    H1 --> H2[Customize Dashboard sheet]
    H1 -.deep link.-> S2

    S --> S1[Subscriptions List]
    S1 --> S2[Subscription Detail]
    S1 --> S3[Add Subscription sheet]
    S2 --> S4[Edit Subscription sheet]
    S2 --> S5[Price History]
    S1 --> S6[Subscription Analytics]

    C --> C1[Cash Flow Overview]
    C1 --> C2[Income list / Income sheet]
    C1 --> C3[Fixed Expenses list / sheet]
    C1 --> C4[Variable Expenses list / sheet]
    C1 --> C5[Money-Flow (Sankey)]

    CAL --> CAL1[Month grid]
    CAL1 --> CAL2[Day detail sheet]

    M --> M1[More menu]
    M1 --> M2[Assets list]
    M2 --> M3[Asset Detail]
    M3 --> M4[Asset Transactions]
    M1 --> M5[BTC / Sats Calculator]
    M1 --> M6[CSV Import]
    M1 --> M7[Settings]
    M7 --> M8[Appearance / Currency / Security / Account / About]
```

### 1.2 Tab bar specification

| Tab | SF Symbol | Label | Default content |
|-----|-----------|-------|-----------------|
| Home | `house.fill` | Home | Customizable dashboard |
| Subscriptions | `creditcard.fill` | Subscriptions | Subscription list (the Substimate "root" view) |
| Cash Flow | `arrow.left.arrow.right` | Cash Flow | Overview cards + lists + money-flow entry |
| Calendar | `calendar` | Calendar | Current-month payment grid |
| More | `ellipsis.circle.fill` | More | Grouped list of Assets, Calculator, Import, Settings |

The tab bar uses the iOS 26 floating glass tab bar on iOS 26+ and the standard opaque `UITabBar` material on iOS 18–25. Selecting the already-selected tab pops its `NavigationStack` to root (standard iOS behavior).

### 1.3 The contextual Add (`+`) action

Substimate had a single hard-coded "Add Subscription" button in the header regardless of context. Finmate makes **Add contextual**:

- Each top-level screen that can create an entity shows a **primary Add affordance** in the navigation bar's trailing position using `.glassProminent` button style (Materials-tinted capsule on fallback OS).
- The action presented depends on the active tab/route:

| Active route | `+` presents |
|--------------|--------------|
| Home | Action menu: Add Subscription · Add Income · Add Expense · Add Asset |
| Subscriptions list | Add Subscription sheet |
| Cash Flow overview | Action menu: Add Income · Add Fixed Expense · Add Variable Expense |
| Calendar | Add Subscription sheet (calendar is read-only over subscriptions) |
| Assets list | Add Asset sheet |
| Asset detail | Add Transaction sheet (pre-filled with that asset) |

- On the Home tab, `+` is a `Menu` (long-press-free tap menu) because Home spans multiple entity types.
- A tap triggers `UIImpactFeedbackGenerator(.light)`; a successful create triggers `.success` notification haptics. Haptics respect the system "Reduce Motion"/haptics settings.

**Acceptance criteria — IA & Add:**

- [ ] Given the app is launched and a user is signed in, the root shows exactly 5 tabs in the order Home, Subscriptions, Cash Flow, Calendar, More.
- [ ] Given any tab, When the user taps that tab's already-selected icon, Then its navigation stack pops to root.
- [ ] Given the Subscriptions tab, When the user taps `+`, Then the Add Subscription sheet appears within 1 frame and no other entity type is offered.
- [ ] Given the Cash Flow tab, When the user taps `+`, Then a menu offers exactly Income, Fixed Expense, and Variable Expense.
- [ ] Given VoiceOver is on, Then the `+` control is labeled with its contextual action (e.g. "Add subscription") not a generic "Add".

---

## 2. Authentication & Onboarding

### 2.1 Purpose

Authenticate the user against Supabase Auth, store tokens in the iOS Keychain, and run a one-time first-run setup that establishes currency, appearance, and optional biometric lock. Substimate used an email/password-only `AuthModal.tsx` over the web app; Finmate adds **Sign in with Apple** and native first-run onboarding.

### 2.2 Screens

1. **Welcome / Sign-In screen** (unauthenticated root). Logo, one-line value prop, two buttons: `Sign in with Apple` (primary, `ASAuthorizationAppleIDButton` styled to match), `Continue with Email` (secondary). Footer links: Privacy Policy, Terms.
2. **Email sheet** — segmented control `Sign In` / `Create Account`; fields email + password (+ confirm password on Create); `Forgot password?` link.
3. **Onboarding flow** (paged, shown only after first successful auth where `UserPreferences` is unset):
   - Page 1 — **Default currency** picker (EUR · USD · BTC; default EUR). Explains all amounts are stored in their native currency.
   - Page 2 — **Appearance** (System · Light · Dark; default System) with a live preview card.
   - Page 3 — **App Lock** (optional): toggle "Require Face ID to open Finmate" + lock timeout picker (Immediately · After 1 min · After 5 min · After 15 min). Defaults off.
   - Page 4 — **Done**: "You're set up" + `Start using Finmate`.
4. **Forgot Password sheet** — email entry → Supabase `resetPasswordForEmail`.

### 2.3 Key flows

**Sign in with Apple (happy path):**
1. User taps `Sign in with Apple`.
2. `ASAuthorizationController` presents the system sheet; user authenticates with Face ID / passcode.
3. App receives the identity token, calls `supabase.auth.signInWithIdToken(provider: .apple, idToken:)` via supabase-swift.
4. Session tokens (access + refresh) are written to the Keychain by the SDK's configured storage adapter (never `UserDefaults` — see [`./07-security-and-privacy.md`](./07-security-and-privacy.md)).
5. If `UserPreferences` row absent → onboarding; else → Home tab.

**Email sign-up:**
1. User picks `Create Account`, enters email + password + confirm.
2. Client validation runs (below). On pass, `supabase.auth.signUp(email:password:)`.
3. If email confirmation is required by the project, show a "Check your inbox" state; otherwise proceed to onboarding.

**Sign out** (from Settings → Account):
1. Confirmation dialog "Sign out of Finmate?".
2. On confirm: `supabase.auth.signOut()`, **clear sensitive local caches** (SwiftData store wiped of user-owned rows; in-memory stores reset), return to Welcome screen.

### 2.4 Inputs & validation

| Field | Rule | Error copy |
|-------|------|-----------|
| Email | Non-empty, matches RFC-5322-lite regex, trimmed | "Enter a valid email address." |
| Password (sign in) | Non-empty | "Enter your password." |
| Password (create) | ≥ 8 chars, ≥ 1 letter + 1 digit | "Use at least 8 characters with a letter and a number." |
| Confirm password | Equals password | "Passwords don't match." |

Validation is performed on the client (immediate, inline under field) **and** enforced by Supabase Auth server-side. Submit button is disabled until the form is valid.

### 2.5 States

- **Loading:** Buttons show inline spinners and disable; full-screen launch state shows the Finmate glass logo while the SDK restores a cached session.
- **Empty:** N/A (auth is the entry point).
- **Error:** Map Supabase auth errors to friendly copy — invalid credentials → "Email or password is incorrect."; network → "Can't reach Finmate. Check your connection."; rate-limited → "Too many attempts. Try again in a moment." Errors appear as an inline banner above the form, not a toast.
- **Offline:** If launched offline with a valid cached session, the user enters the app against the local cache (offline-first). If launched offline with no session, show "You're offline. Sign in once you're connected."

### 2.6 Edge cases

- Apple relay/private email: store whatever Supabase returns; never require a "real" email.
- Apple returns name only on first authorization — capture it then if a display name is ever surfaced; do not depend on it later.
- Token refresh failure mid-session → SDK attempts silent refresh; on hard failure, surface a non-destructive "Session expired, sign in again" and return to Welcome without wiping the offline cache until re-auth resolves to a *different* user (then wipe).
- Switching accounts: if the newly signed-in `user.id` differs from the cached one, the local SwiftData store for the previous user is purged before sync.

### 2.7 Acceptance criteria

- [ ] Given the Welcome screen, When the user completes Sign in with Apple, Then tokens are present in the Keychain and absent from `UserDefaults`.
- [ ] Given a brand-new account with no `UserPreferences`, When auth succeeds, Then the 4-page onboarding appears before Home.
- [ ] Given onboarding completes, Then a `UserPreferences` row exists with the chosen currency and appearance, and onboarding never appears again for that account.
- [ ] Given Create Account with mismatched passwords, Then the submit button is disabled and "Passwords don't match." is shown inline.
- [ ] Given sign-out is confirmed, Then no user-owned rows remain in the local cache and the app returns to Welcome.
- [ ] Given the device is offline with a valid cached session, When the app launches, Then the user reaches Home backed by cached data.

---

## 3. Home / Dashboard

### 3.1 Purpose

A glanceable, **customizable** overview of the user's financial picture. Substimate had an implicit dashboard via `DashboardGrid.tsx` + `DraggableDashboardCard.tsx` + a `dashboard_layouts` table storing an ordered array of card ids (`useDashboardLayout.ts`). Finmate keeps the customizable ordered-cards concept and makes it the dedicated Home tab.

### 3.2 Dashboard cards (v1 set)

Each card has a stable `cardId`, a title, a tap target (deep link), and per-card loading/empty states. The ordered list of visible card ids is persisted in `dashboard_layouts.card_order` (Postgres `text[]`, Swift `cardOrder: [String]`) per the data model — created in the M0 preferences migration and persisted by M1-HOME (see [`./05-data-model.md`](./05-data-model.md) and [`./08-roadmap-and-milestones.md`](./08-roadmap-and-milestones.md)).

| `cardId` | Title | Content | Tap → |
|----------|-------|---------|-------|
| `monthly-burn` | Monthly Burn | Total monthly committed spend = subscriptions (normalized to monthly) + fixed expenses + this-month variable expenses, in display currency | Cash Flow overview |
| `subscriptions-summary` | Subscriptions | Count + total monthly cost + count flagged for review | Subscriptions list |
| `upcoming-charges` | Upcoming | Next 5 subscription charges in the next 30 days (date, name, amount) | Calendar |
| `net-cash-flow` | Net Cash Flow | Monthly income − monthly expenses, with savings-rate % | Cash Flow overview |
| `category-spotlight` | Top Categories | Top 3 spend categories this month (mini bar) | Subscription Analytics |
| `assets-snapshot` | Assets | Total asset value + simple gain/loss vs cost basis | Assets list |
| `review-queue` | Review | Up to 5 `rarely`/`unused` subscriptions by monthly cost (Substimate's "Review Queue") | Subscription detail of tapped item |

All monetary values render in the user's **display currency** (converted at read time; stored values are never mutated by display-currency changes — this fixes a Substimate class of bug).

### 3.3 Screens

1. **Dashboard** — vertical scroll of cards in saved order. Navigation bar: title "Home", trailing `+` (contextual menu), and an `Edit`/`Customize` button (`square.grid.2x2`).
2. **Customize Dashboard sheet** — full-height. A list of all cards with: drag handles to reorder (`onMove`), a per-card visibility toggle, and a "Reset to default" button. Live preview not required; reorder is the cache-truth.

### 3.4 Flows

**Reorder a card:**
1. User taps `Customize`.
2. Drags a row using the reorder handle; the local order updates optimistically.
3. On sheet dismiss (or immediately on each move), the new `card_order` array is written to the cache and synced to `dashboard_layouts` via the repository. Failure rolls back order with an error toast.

**Hide a card:** toggle off → removed from the dashboard's visible set immediately; a hidden card is represented by its absence from `card_order` (the visible, ordered set), so hide and reorder share the one `card_order` array.

### 3.5 States

- **Loading:** Each card shows a `redacted(reason: .placeholder)` skeleton; the dashboard scaffold (titles) renders instantly from the last cached layout.
- **Empty (new user, no data):** A friendly "Let's set up your finances" hero card with three quick actions: Add your first subscription · Add income · Import from CSV. Cards that have no data show per-card empty copy (e.g. Assets → "No assets yet").
- **Error:** A non-blocking inline banner "Some data couldn't refresh" with a retry; cached values remain visible.

### 3.6 Edge cases

- A `cardId` present in `card_order` but unknown to the current build (forward-compat) is ignored silently.
- A card with zero underlying data still renders (empty state), it is not auto-hidden, so the user can see "Net Cash Flow: add income to see this".
- Display-currency change recomputes all card values without a network round-trip if exchange rates are cached.

### 3.7 Acceptance criteria

- [ ] Given a new user with no `dashboard_layouts` row, When Home first loads, Then the default ordered card set is created and persisted.
- [ ] Given the user reorders cards and dismisses Customize, When they relaunch the app, Then the new order is preserved (from cache, even offline).
- [ ] Given the Upcoming card, Then it lists at most 5 charges, all within the next 30 days, sorted ascending by date.
- [ ] Given the Review card, Then it lists only subscriptions whose `usage_state` is `rarely` or `unused`, sorted by monthly cost descending, max 5.
- [ ] Given the display currency is changed to BTC, Then every card's amounts render as sats without a network call when rates are cached.

---

## 4. Subscriptions & Subscription Analytics

### 4.1 Purpose

The core pillar: track recurring subscriptions, categorize and triage them, see price history, and analyze cost over time. This maps Substimate's `SubscriptionContext.tsx`, `SubscriptionCard.tsx`, `SubscriptionList.tsx`, `AddSubscriptionModal.tsx`, `EditSubscriptionModal.tsx`, `CategoryFilter.tsx`, plus the `analytics/` components.

### 4.2 The Subscription model (v1, canonical)

Maps to the `subscriptions` table. Field names are the single canonical names from the brief — there is **no** `amount`/`monthlyCost` duality and **no** `favorite`/`isFavorite` duality (both were Substimate cruft).

| Field | Type (Swift) | Notes / validation |
|-------|--------------|--------------------|
| `id` | `UUID` | server-generated |
| `name` | `String` | required, 1–120 chars, trimmed |
| `vendorURL` | `URL?` | optional; bare host gets `https://` prefixed |
| `icon` | `String` | SF Symbol name or bundled brand symbol id; default `creditcard` |
| `amountMinor` | `Int64` | the **billing-period** amount in minor units of `currency`, ≥ 0 |
| `currency` | `CurrencyCode` | EUR · USD · BTC; CHECK-constrained in DB |
| `billingPeriod` | enum | **`weekly` · `monthly` · `quarterly` · `yearly`** |
| `paymentMethod` | enum | `credit_card` · `debit_card` · `paypal` · `bank_transfer` · `apple_pay` · `google_pay` · `crypto` · `other` |
| `categoryId` | `UUID?` | references user-owned `categories`; nil → "Other" |
| `usageState` | enum | **`active` · `rarely` · `unused`** |
| `startDate` | `Date` | required; defaults today; cannot be in the future |
| `endDate` | `Date?` | optional; if set, must be ≥ `startDate` |
| `autoRenew` | `Bool` | default true |
| `favorite` | `Bool` | default false |
| `sortOrder` | `Int` | manual ordering position |
| `notes` | `String?` | optional, ≤ 500 chars |

> **Improvement over Substimate.** Substimate stored `monthly_cost` as a float and only supported `monthly`/`yearly` billing in its modals; it normalized yearly→monthly on input and re-multiplied on edit (`EditSubscriptionModal.tsx` lines 72–77), a lossy round-trip. Finmate stores the **billing-period amount** in **minor units** and derives the monthly-equivalent on the fly:
> `monthlyEquivalentMinor = amountMinor × periodToMonthlyFactor(billingPeriod)` where factors are weekly ≈ 52/12, monthly = 1, quarterly = 1/3, yearly = 1/12, computed in `Decimal` then rounded to minor units. This computation lives in `Domain`/`Shared` and is unit-tested.

#### Usage states

| State | Meaning | UI treatment |
|-------|---------|--------------|
| `active` | Actively used | neutral |
| `rarely` | Used rarely (Substimate's "not much") | amber accent, eligible for Review |
| `unused` | Not used | red accent, eligible for Review |

#### Categories (the `categories` pillar)

User-owned categories surfaced via an RPC equivalent to Substimate's `get_user_categories`. Seeded defaults on first run:

`AI Chat · Coding · Diffusion · Streaming · Music · Gaming · Productivity · Audio Generation · Video Generation · Cloud Services · Fitness · Health · Food · Transport · Financial · Creative · Social · Other`

**`All`** and **`Favorites`** are **presentation-layer pseudo-filters**, not seeded category rows — they exist only as filter chips (see §4.3). The single **seeded, protected (non-deletable, non-renamable) category** per kind is **`Other`**, the catch-all fallback assignment. Users can create custom categories; deleting a category reassigns its subscriptions to `Other`.

### 4.3 Screens

1. **Subscriptions List** — primary screen.
   - **Header summary:** total monthly cost (display currency), subscription count.
   - **Search field** — filters by name, category name, payment method, billing period (Substimate searched the same fields in `Layout.tsx`).
   - **Category filter** — a horizontally scrolling chip row: `All`, `Favorites`, then user categories (Substimate `CategoryFilter.tsx`). Selecting filters the list.
   - **List** of subscription rows (cards): icon, name, category, monthly-equivalent amount, billing period, favorite star, usage-state accent. Rows support reordering when sorted manually.
   - **Empty state:** "No subscriptions yet" + Add button + "Import from CSV" secondary.
2. **Subscription Detail** — name + icon header; amount + billing period + monthly equivalent; category; payment method; usage-state segmented control; favorite toggle; auto-renew toggle; start/end dates; notes; **Price History** section (inline preview, tap → full history); destructive `Delete`. Trailing `Edit`. When `vendorURL` is present, the header shows a tappable "Open website" affordance that opens the URL **in-app** via `SFSafariViewController` (never an external Safari hand-off, never a raw `UIApplication.open`), so the user stays inside Finmate. Only `http`/`https` URLs are openable.
3. **Add Subscription sheet** — fields per model with **name-driven prediction prefill** (the engine in §4.10): as the user types a known service name (Netflix, Spotify, ChatGPT, Disney+, Apple Music, YouTube Premium, Amazon Prime, HBO Max, Apple TV+, GitHub, Midjourney, etc.) the sheet prefills `vendorURL`, `icon`, a suggested amount, and the inferred `category`. Money is entered in real currency and stored as minor units. The user can override any prefilled value before saving.
4. **Edit Subscription sheet** — same fields; editing the amount or currency prompts the price-change behavior (below).
5. **Price History** — reverse-chronological list of `SubscriptionPriceHistory` entries: effective date, amount, currency, and a `Correction` badge for `is_correction = true` rows. A small line chart of price over time (Swift Charts).
6. **Subscription Analytics** — see §4.7.

### 4.4 Reordering, favorites, filtering

- **Favorite toggle:** optimistic; tapping the star flips `favorite`, updates the cache and the `Favorites` filter instantly, syncs in the background (mirrors Substimate's optimistic `toggleFavorite`, but on the typed `favorite` field only).
- **Reorder:** drag rows; `sortOrder` is recomputed and persisted via the Finmate batch RPC `batch_reorder_subscriptions` (Substimate's legacy `batch_update_subscription_order` hardened the equivalent RPC with per-row `auth.uid()` ownership checks; Finmate reuses that ownership contract). Available only when the active sort is "Manual".
- **Sort options:** Manual (default) · Name · Monthly cost (high→low) · Usage.
- **Filtering** is client-side over the cached set; `All` shows everything, `Favorites` shows `favorite == true`, a category chip shows that `categoryId`.

### 4.5 Price history surfacing

A DB trigger (`handle_subscription_price_change`, `SECURITY DEFINER`, `SET search_path = public`) writes a `subscription_price_history` row on insert and on any change to `amount_minor`/`currency` (Finmate's canonical names; Substimate's migration `20260627103000_*` does exactly this on `monthly_cost`/`currency`). The client never writes price history directly.

- On **edit** where amount or currency changed, the Edit sheet asks: "Is this a price correction or a real price change?"
  - **Price change** → trigger writes a normal history row (`is_correction = false`), `effective_from = now`.
  - **Correction** → the client sets a correction flag so the new row is marked `is_correction = true`; lifetime-cost math treats corrections as fixing the prior value rather than as a new price step.
- Price history powers **Lifetime Cost** analytics (§4.7) which walk the timeline applying the price that was effective in each month/anniversary.

### 4.6 Inputs & validation (Add/Edit)

| Field | Validation | Error |
|-------|-----------|-------|
| Name | required, 1–120 chars | "Enter a name." |
| Amount | parse in display locale → `Decimal` ≥ 0; converted to minor units of the chosen currency | "Enter an amount of 0 or more." |
| Currency | one of EUR/USD/BTC | n/a (picker) |
| Billing period | one of the 4 enum cases | n/a (picker) |
| Payment method | one of the 8 enum cases | "Choose a payment method." |
| Category | optional; free-type creates a new category after confirm | n/a |
| Start date | ≤ today | "Start date can't be in the future." |
| End date | nil or ≥ start date | "End date must be after the start date." |
| URL | optional; normalized to `https://` if scheme missing; must be a valid URL if present | "Enter a valid web address." |
| Notes | ≤ 500 chars | "Notes are too long." |

Amount entry uses a currency-aware field: for EUR/USD it accepts 2 decimal places; for BTC it accepts a sats integer (or a BTC value that is converted to sats). The Save button disables until required fields validate.

### 4.7 Subscription Analytics

A dedicated analytics screen (reachable from the Subscriptions list toolbar and the Home `category-spotlight` card). All charts use **Swift Charts**. Five analytics, matching Substimate's `useSubscriptionAnalytics.ts` + `analytics/` + `UsageStatistics.tsx`:

1. **Monthly Trends** — total subscription cost per month over the last 6 months (line/area). Yearly subscriptions contribute only in anniversary months; monthly/weekly/quarterly contribute their monthly-equivalent. Uses display currency.
2. **Category Distribution** — donut + legend of monthly cost per category, with per-category subscription count and average cost/service.
3. **Lifetime Cost** — per subscription, total spent since `startDate`, walking the price-history timeline (corrections applied). Sorted high→low. Shows months-active and current monthly cost.
4. **Usage Statistics** — distribution of `active`/`rarely`/`unused` (% and counts), billing-period distribution (weekly/monthly/quarterly/yearly), 3-month vs prior-3-month subscription-count and cost trend deltas, and a sortable table (by name/cost/usage).
5. **Payment-Method Breakdown** — total monthly cost and count per payment method, with average cost/service.

**Analytics states:**
- **Loading:** chart areas redacted; legend skeletons.
- **Empty:** "Add subscriptions to see analytics" with an Add button (each chart guards against divide-by-zero — Substimate guarded `/ (older || 1)` style; Finmate computes safely and renders an empty chart, never NaN).
- **Error:** inline retry; last successful figures stay visible.

### 4.8 Edge cases

- Deleting a subscription is optimistic with an undo toast (5 s); the row dims during the pending delete (Substimate dimmed via `isDeleting`). On confirm-window expiry the remote delete commits (cascade-deletes its price history per FK).
- A subscription started today appears in this month's trends and the calendar from today forward.
- Quarterly billing: monthly-equivalent = amount/3; appears in the calendar on the quarter anniversaries from `startDate`.
- Changing currency on an existing subscription writes a price-history row (currency change) — the stored amount keeps its native currency (the Substimate "convert-to-EUR-but-keep-label" bug is explicitly prevented).
- `endDate` in the past → subscription is "ended": excluded from forward-looking burn/calendar but still counts in Lifetime Cost up to `endDate`.

### 4.9 Acceptance criteria

- [ ] Given a yearly subscription of €120, Then its monthly equivalent shown in the list is €10.00 and its Calendar charge appears once per year on the start-date anniversary.
- [ ] Given the user toggles favorite on a row, Then the star fills immediately and the `Favorites` filter includes it without waiting for the network.
- [ ] Given the user edits the amount and selects "Price change", Then a new `subscription_price_history` row exists with `is_correction = false` and `effective_from ≈ now`, written by the DB trigger (not the client).
- [ ] Given the user edits the amount and selects "Correction", Then the new history row has `is_correction = true` and Lifetime Cost does not double-count the corrected step.
- [ ] Given manual sort and a drag-reorder, Then `sort_order` persists via the `batch_reorder_subscriptions` RPC and the RPC rejects any row not owned by `auth.uid()`.
- [ ] Given a subscription priced in USD, When display currency is EUR, Then list and analytics show converted EUR values while the stored row remains USD minor units.
- [ ] Given no subscriptions, Then every analytics chart renders an empty state and never displays NaN/∞.
- [ ] Given a category is deleted, Then its subscriptions are reassigned to `Other` and the protected category `Other` cannot be deleted (the `All`/`Favorites` chips are presentation-layer filters, not deletable rows).
- [ ] Given the user types "github" into the Add sheet name field, Then `category` is prefilled `Coding`, `vendorURL` `https://github.com`, and a suggested amount appears, all overridable.
- [ ] Given a subscription with a `vendorURL`, When the user taps "Open website" on the detail screen, Then the URL opens in an `SFSafariViewController` presented within Finmate (not an external Safari switch).

### 4.10 Subscription prediction & category inference (KEEP, ported)

Finmate ships a **prediction engine ported from Substimate** (`src/utils/subscriptionData.ts` + `subscriptionPredictions.ts`), curated and kept extensible. It is **pure logic** in `Domain`/`Shared` and is **unit-tested** (see acceptance below and [`./09-engineering-practices.md`](./09-engineering-practices.md)). It powers the §4.3 Add-sheet prefill. It never performs a network call — it is a local dictionary lookup.

**(a) Seed prediction dictionary** — maps a known service name → `{ vendorURL, icon, typicalAmountMinor? }`:

| Field | Notes |
|-------|-------|
| `vendorURL` | canonical vendor URL (e.g. `claude.com`, `netflix.com`), normalized to `https://` |
| `icon` | SF Symbol name or bundled brand-asset id (Substimate's lucide icon names — `Bot`, `Code`, `Tv`, `Music`, `Image`, `Video`, … — are mapped to SF Symbols/brand assets during the port) |
| `typicalAmountMinor` | optional suggested amount in minor units (Substimate stored a `monthlyCost` number, e.g. ChatGPT 20, Netflix 15; ported to minor units of the default currency) |

Seed examples (curated from Substimate): `anthropic`/`claude` → `claude.com`; `chatgpt`/`openai`/`gpt` → `chat.openai.com`/`openai.com`; `cursor` → `cursor.sh`; `github`/`copilot` → `github.com`; `midjourney`/`mj` → `midjourney.com`; `runway` → `runway.ml`; `netflix` → `netflix.com`; `spotify` → `spotify.com`; `notion` → `notion.so`; `adobe` → `adobe.com`; etc.

**(b) Keyword → category inference map** — independent of the name dictionary, infers a category from substrings of the typed name:

| Inferred category | Trigger keywords (substring, case-insensitive) |
|-------------------|------------------------------------------------|
| AI Chat | chatgpt, claude, gemini, perplexity, anthropic, bard |
| Coding | bolt.new, cursor, v0, copilot, codeium, replit, github, gitlab |
| Diffusion | midjourney, runway, magnific, photoai, krea, stable diffusion, leonardo, dall-e |
| Productivity | notion, obsidian, linear, asana, trello, clickup |
| Creative | adobe, creative cloud, figma, sketch, affinity, procreate |
| Social | primal, discord, slack, telegram, twitter, mastodon |
| Streaming | netflix, disney, hbo, prime video, apple tv, hulu |
| Music | spotify, apple music, tidal, deezer, youtube music |
| Gaming | xbox, playstation, nintendo, steam, ea play, game pass |
| Audio Generation | elevenlabs, suno, udio, mubert |
| Video Generation | opus, heygen, synthesia, descript |
| Cloud Services | aws, azure, gcp, digitalocean, vercel, netlify |
| Fitness | fitbit, strava, peloton, zwift, gympass, classpass |
| Health | calm, headspace, noom, myfitnesspal, nike, withings |
| Food | hellofresh, bluechef, doordash, ubereats, grubhub, instacart |
| Transport | uber, lyft, bird, lime, citibike, trainline |
| Financial | robinhood, coinbase, binance, etoro, fidelity, schwab |
| Other | (no keyword matched) |

**(c) Match rule:** the name lookup tries an **exact** (case-insensitive, trimmed) name match first; if none, it falls back to a **case-insensitive substring** match (either the typed term contains a known key or a known key contains the typed term, per Substimate `predictSubscription`). Inputs shorter than 2 characters return no prediction. Category inference runs in declaration order and returns the first matching group, defaulting to `Other`.

**(d) On match in the Add sheet:** prefill `vendorURL`, `icon`, suggested amount (`typicalAmountMinor` if present), and the inferred `category`. All prefilled values remain user-editable; the user's explicit edits win over predictions.

**Acceptance criteria — prediction & inference (unit-tested):**

- [ ] Given a name containing "github", Then the inferred category is `Coding`.
- [ ] Given a name containing "chatgpt", Then the inferred category is `AI Chat`.
- [ ] Given a name containing "midjourney", Then the inferred category is `Diffusion`.
- [ ] Given the exact name "Netflix" (any case), Then the prediction returns `netflix.com`, a streaming icon, and the seeded suggested amount.
- [ ] Given a typed term shorter than 2 characters, Then the engine returns no prediction.
- [ ] Given an unknown name with no keyword match, Then category inference returns `Other` and no prefill is applied.

---

## 5. Income & Expenses

### 5.1 Purpose

Track money in (income sources) and money out (fixed + variable expenses) to compute net cash flow and feed the money-flow visualization and Home cards. Maps Substimate's `useFinancialData.ts`, `IncomeModal.tsx`, `ExpenseModal.tsx`, and `finance/` lists. In Finmate these live under the **Cash Flow** tab.

### 5.2 Models

**IncomeSource** (`income_sources`):

| Field | Type | Validation |
|-------|------|-----------|
| `name` (a.k.a. source) | `String` | required, 1–120 chars |
| `amountMinor` | `Int64` | ≥ 0 |
| `currency` | `CurrencyCode` | EUR/USD/BTC |
| `frequency` | enum | `weekly` · `monthly` · `yearly` · `one_time` |
| `nextPayment` | `Date?` | optional |
| `notes` | `String?` | ≤ 500 |

**FixedExpense** (`fixed_expenses`):

| Field | Type | Validation |
|-------|------|-----------|
| `name` | `String` | required, 1–120 chars |
| `amountMinor` | `Int64` | ≥ 0 |
| `currency` | `CurrencyCode` | EUR/USD/BTC |
| `categoryId` | `UUID?` | expense category; nil → Other |
| `dueDate` | `Date?` | optional |
| `frequency` | enum | `monthly` · `quarterly` · `yearly` |
| `autopay` | `Bool` | default false |
| `notes` | `String?` | ≤ 500 |

**VariableExpense** (`variable_expenses`):

| Field | Type | Validation |
|-------|------|-----------|
| `name` | `String` | required, 1–120 chars |
| `amountMinor` | `Int64` | ≥ 0 |
| `currency` | `CurrencyCode` | EUR/USD/BTC |
| `categoryId` | `UUID?` | nil → Other |
| `spentOn` (persisted as `spent_on`) | `Date` | required; defaults today. Named `spent_on` (Swift `spentOn`) to avoid shadowing the SQL `date` type — see [`./05-data-model.md`](./05-data-model.md) §3.6 |
| `notes` | `String?` | ≤ 500 |

Expense categories are **distinct from subscription categories** and are kept apart by a `categories.kind` discriminator (`'subscription'` vs `'expense'`, per [`./05-data-model.md`](./05-data-model.md) §7). Both `fixed_expenses` and `variable_expenses` resolve `category_id` against categories with `kind = 'expense'`; subscriptions resolve against `kind = 'subscription'`. The expense sheets fetch their options via `get_user_categories(p_kind => 'expense')`. The seeded expense set (11 categories, per Substimate `ExpenseModal.tsx`) is: `Housing · Transportation · Food · Utilities · Insurance · Healthcare · Entertainment · Shopping · Education · Savings · Other`, plus user-created customs (also created with `kind = 'expense'`). `Other` is the seeded protected fallback for the expense kind.

> **Monthly normalization (computed, tested):** income → monthly: weekly ×52/12, monthly ×1, yearly ×1/12, one_time excluded from recurring monthly income; fixed expense → monthly: monthly ×1, quarterly ×1/3, yearly ×1/12. Substimate used `×4` for weekly which is a rough approximation; Finmate uses the precise 52/12 factor and documents it.

### 5.3 Screens

1. **Cash Flow Overview** (Cash Flow tab root):
   - **Key Metrics** cards: Monthly Income · Monthly Expenses (fixed + variable + subscriptions) · Net (savings) · Savings rate %.
   - **Monthly Trends** chart (last 6 months). The trends dataset is **not** reduced to "income vs expenses"; per month it includes the full series ported from Substimate `useFinanceAnalytics.ts`: `income`, `expenses`, `fixedExpenses`, `variableExpenses`, `subscriptionCosts`, `investments` (sum of `buy` asset-transactions in the month), `savings` (income − expenses), `savingsRatio` (% of income saved), and `investmentRatio` (% of income invested). Each series is in display currency; ratios are 0 when income is 0 (no divide-by-NaN). The chart can surface income/expenses prominently while the remaining series back the breakdown and tooltips.
   - Section links: Income · Fixed Expenses · Variable Expenses · Money-Flow.
2. **Income list / Income sheet** — list rows (source, amount, frequency, next payment). Sheet = Add/Edit with a "Recurring" toggle (off → `one_time`, hides frequency) exactly mirroring Substimate's `IncomeModal`.
3. **Fixed Expenses list / sheet** — rows (name, amount, frequency, autopay badge, due date). The category picker shows **expense-kind categories only** (`get_user_categories(p_kind => 'expense')`); subscription categories never appear here. Sheet includes a custom-category path that creates the category with `kind = 'expense'`.
4. **Variable Expenses list / sheet** — rows (name, amount, category, date). The category picker shows **expense-kind categories only**, same as fixed expenses. The date persists as `spent_on` (Swift `spentOn`), per §5.2. Sheet defaults the date to today.

### 5.4 Flows

**Add income:** `+` → Income sheet → enter source + amount + (recurring? frequency : one_time) + optional next payment + notes → Save (optimistic insert, toast on success/failure).

**Edit/Delete** any item: tap row → edit sheet, or swipe-to-delete with undo toast. Delete is optimistic.

### 5.5 States

- **Loading:** list skeleton rows; metric cards redacted.
- **Empty:** each list has its own empty state with an inline Add ("No income sources yet — add your salary, freelance, or investment income").
- **Error:** optimistic write failure rolls back and shows an error toast; the sheet can be reopened with entered values preserved.

### 5.6 Edge cases

- `one_time` income is excluded from recurring monthly income but is shown in the income list and counted in the money-flow for the selected timeframe if its date falls inside it.
- Mixed currencies: each item keeps its native currency; aggregates convert to display currency at read time.
- Negative net cash flow renders with a clear "spending exceeds income" treatment (not an error).

### 5.7 Acceptance criteria

- [ ] Given weekly income of €100, Then monthly income contribution is €433.33 (100 × 52/12), not €400.
- [ ] Given a one_time income, Then it is excluded from "Monthly Income" but appears in the income list.
- [ ] Given a fixed expense set to quarterly, Then its monthly-equivalent in metrics is amount/3.
- [ ] Given an expense saved with a custom category name, Then that category is created (user-owned) and reusable.
- [ ] Given an optimistic add fails to sync, Then the item is rolled back, an error toast appears, and reopening the sheet preserves the entered values.

---

## 6. Cost-Tracker Money-Flow

### 6.1 Purpose

Visualize how income flows into expense categories — a Sankey/money-flow diagram plus supporting breakdowns. Maps Substimate's `CostTrackerPage.tsx` + `cost-tracker/SpendingFlowChart.tsx` (D3-Sankey on web) + `MonthlyTrendsChart`, `CategoryDistribution`, `ExpenseBreakdown`, `TimeframeSelector`, `FlowTooltip`. In Finmate this is reachable from the Cash Flow tab.

### 6.2 The money-flow (Sankey) renderer

Swift Charts has **no** built-in Sankey, so Finmate ships a **custom `Canvas`/`Path`-based flow renderer in `DesignSystem`** (called out as a known engineering item in [`./03-architecture.md`](./03-architecture.md) and [`./10-task-backlog.md`](./10-task-backlog.md)).

> **Intentional redesign vs Substimate (ADR-0016).** Substimate's `SpendingFlowChart.tsx` flowed a single `Total Income` node *directly* to one node per category — fixed-expense categories, variable-expense categories, and subscription categories were all peers fanning straight out of income (e.g. `Fixed: Housing`, `Variable: Food`, `Sub: Streaming`, plus a `Savings` node), producing a wide, hard-to-scan fan. Finmate **groups the flow into four top-level buckets first, then drills down on demand** for a cleaner overview. This is an explicit, recorded divergence from Substimate — **not** a faithful port. See [`./12-decisions-adr.md`](./12-decisions-adr.md) ADR-0016.

**Topology (collapsed, default state):**

- **Left node:** a single `Income` node whose value is `totalIncome` (sum of all income normalized into the selected timeframe and converted to display currency).
- **Right nodes — the four top-level buckets:** `Fixed Expenses`, `Variable Expenses`, `Subscriptions`, `Savings`.
  - Each expense bucket value = the sum of its constituent items normalized into the timeframe and converted to display currency.
  - `Savings = max(0, totalIncome − totalExpenses)` where `totalExpenses = fixed + variable + subscriptions`. This mirrors Substimate's `Math.max(0, totalIncome - totalExpenses)` for the savings node, but Substimate computed it *after* fanning to per-category nodes; Finmate uses it as a first-class bucket.
- **Links:** one link from `Income` to each non-empty bucket; width ∝ the bucket's normalized amount in display currency. **Empty buckets are omitted** (no zero-width link, no orphan node).

**Tap-to-expand (drill-down):**

- Tapping a bucket node **expands it in place** into its per-category sub-flows:
  - `Fixed Expenses` → one sub-node per fixed-expense category (e.g. `Housing`, `Utilities`, …).
  - `Variable Expenses` → one sub-node per variable-expense category (e.g. `Food`, `Transportation`, …).
  - `Subscriptions` → one sub-node per subscription category (e.g. `Streaming`, `AI Chat`, …).
  - `Savings` is a leaf and does not expand.
- The expanded bucket renders an intermediate column: `Income → <Bucket> → <category…>`, with the bucket→category link widths summing to the bucket width. Tapping the bucket again collapses it. Only one bucket need be expanded at a time on iPhone (others collapse) to keep the canvas legible; this is a presentation choice, not a data constraint.
- **Interaction:** tap a node/link → a glass tooltip card (`FlowTooltip` equivalent) showing the amount, % of income, and (for a collapsed bucket) its top categories.
- **Accessibility:** the diagram exposes an equivalent VoiceOver summary list ("Income €X. Fixed Expenses €A, P% of income. Variable Expenses €B… Subscriptions €C… Savings €D.") and, on a bucket's expansion, reads its category breakdown. Respects Reduce Motion (no link-flow animation; expand/collapse is instant rather than animated).

### 6.3 Timeframe selection

A `TimeframeSelector` offering **Monthly · Quarterly · Yearly** plus a "from" date, exactly as Substimate. The selected timeframe scales all normalized amounts (e.g. Yearly = monthly × 12) and filters dated variable expenses/one-time income into the window.

### 6.4 Supporting views (same screen)

- **Monthly Trends** — last-6-months series shared with the Cash Flow overview (§5.3): per month `income`, `expenses`, `fixedExpenses`, `variableExpenses`, `subscriptionCosts`, `investments` (sum of `buy` asset-transactions in the month), `savings`, `savingsRatio`, `investmentRatio`. Rendered here as stacked bars of fixed/variable/subscription costs with income, savings, and investment overlays. This is the full Substimate `useFinanceAnalytics.ts` dataset, not an income-vs-expenses reduction.
- **Category Distribution** — expense spend per category, **windowed** by the timeframe selector (default current month) — see §6.4a.
- **Expense Breakdown** — Fixed vs Variable vs Subscriptions totals.
- **Review Queue** — top 5 `rarely`/`unused` subscriptions by monthly cost (shared with Home's review card).

#### 6.4a Expense Category Distribution — windowing

The expense category-distribution (a donut, mirroring Substimate `finance/CategoryDistributionChart` with `type=expenses`) is **windowed by a timeframe selector**, not all-time. The control offers **Week · Month · Year** (Substimate's `'week' | 'month' | 'year'`) and **defaults to the current month**. Within the selected window:

- Variable expenses are filtered to those whose `spent_on` date falls inside the window.
- Fixed expenses are scaled into the window (week ≈ amount/4, month = amount, year = amount × 12; the precise normalization factors from §5.2 apply).
- Slices group by category; the legend shows each category's amount in display currency, sorted descending by amount.

This explicit window prevents an ever-growing all-time pie and matches the cost-tracker's other timeframe-scoped views.

**Acceptance criteria — expense distribution windowing:**

- [ ] Given the Expense Category Distribution, Then a Week/Month/Year timeframe control is present and defaults to the current month.
- [ ] Given timeframe = Month, Then only variable expenses dated within the current month contribute, and fixed expenses contribute their monthly amount.
- [ ] Given no expenses in the selected window, Then the chart shows its empty state and renders no NaN slice.

### 6.5 States & edge cases

- **Loading:** the flow canvas shows a shimmer; breakdowns redacted.
- **Empty:** if there is no income and no expenses → "Add income and expenses to see your money flow." If income exists but no expenses → all income flows to the `Savings` bucket. Buckets with a zero total are omitted entirely (no zero-width link).
- **Error:** retry banner; cached figures persist.
- **Edge:** expenses exceeding income → `Savings = max(0, …)` clamps to 0, so no `Savings` link is drawn; an "Over budget" caption (warning treatment) states by how much expenses exceed income. Link widths are always non-negative; the over-budget state is communicated in copy/color, never as a negative width.
- Currency conversion happens at read time in display currency.

### 6.6 Acceptance criteria

- [ ] Given income and expenses exist, Then the sum of the outgoing link widths from `Income` equals total income (within rounding), with `Savings = max(0, totalIncome − totalExpenses)`.
- [ ] Given a bucket with at least one item, When the user taps it, Then it expands into its per-category sub-flows and the bucket→category link widths sum to the bucket width; tapping again collapses it.
- [ ] Given a bucket whose total is zero (no items), Then that bucket node and its link are omitted from the diagram.
- [ ] Given timeframe = Yearly, Then every flow amount equals the monthly-normalized value × 12.
- [ ] Given Reduce Motion is on, Then the flow renders without animated transitions and expand/collapse is instant.
- [ ] Given VoiceOver, Then a textual summary conveys each bucket flow, its share of income, and (when expanded) its category breakdown.
- [ ] Given expenses exceed income, Then `Savings` is 0 (no `Savings` link), an "Over budget" caption states the shortfall, and no chart math produces NaN or a negative width.

---

## 7. Payday Calendar

### 7.1 Purpose

A month grid showing upcoming and past subscription charges so the user sees when money leaves. Maps Substimate's `PaydayCalendarPage.tsx` + `finance/PaydayDetailModal.tsx`. (Substimate's calendar plots *subscription* payments; despite the "payday" name it is charge-centric. Finmate keeps charge events and additionally overlays income `nextPayment` markers.)

### 7.2 Screens

1. **Month grid** — 7-column calendar for the current month; prev/next month chevrons; "Today" ring. Each day with events shows up to 5 event dots (yearly = purple accent, monthly = display-accent, past = muted) + a `+N` overflow. A legend explains the dot colors. Income `nextPayment` dates show a distinct income marker.
2. **Day detail sheet** — tapping a day with events opens a sheet listing each event: name, billing-period tag, amount (charge amount in display currency), upcoming vs past styling.

### 7.3 Charge projection logic

- **Monthly:** charge on the same day-of-month as `startDate`, every month from `startDate`.
- **Yearly:** charge on the `startDate` anniversary (month+day) in the viewed year.
- **Quarterly:** charge every 3 months from `startDate`.
- **Weekly:** charge weekly from `startDate` (new vs Substimate, which had only monthly/yearly).
- A charge is `upcoming` if its date is in the future relative to today, else `past`.
- Subscriptions with `endDate` before a projected date produce no event; subscriptions not yet started produce no event.

### 7.4 States & edge cases

- **Loading:** grid renders with skeleton dots.
- **Empty:** a month with no charges shows the grid with no dots and a caption "No charges this month."
- **Edge:** day-of-month 29–31 for months that lack that day → clamp to the last day of the month (e.g. a 31st start renders on Feb 28/29). Document this clamping behavior.
- Past months are fully navigable and read-only.

### 7.5 Acceptance criteria

- [ ] Given a monthly subscription started on the 15th, Then every month shows a charge dot on the 15th.
- [ ] Given a yearly subscription, Then exactly one charge appears in its anniversary month with the yearly amount.
- [ ] Given a subscription started on Jan 31, When viewing February, Then the charge clamps to Feb 28 (or 29 in a leap year).
- [ ] Given a day with more than 5 events, Then 5 dots plus a `+N` overflow indicator render, and the day-detail sheet lists all events.
- [ ] Given an income source with a `nextPayment` date in the viewed month, Then an income marker appears on that day.

### 7.6 Local notifications (upcoming charges + upcoming paydays)

Finmate v1 ships **local notifications** scheduled on-device via `UNUserNotificationCenter` (roadmap **M4**, [`./12-decisions-adr.md`](./12-decisions-adr.md) ADR-0013). These are entirely local — there is **no** remote/server-driven push or email reminder service in v1; a server-driven reminder service is an explicit post-v1 non-goal. Local notifications are **opt-in and permission-gated**.

**Flows:**

- **Upcoming charges:** for subscriptions with notifications enabled, a local notification fires ahead of each projected charge date (per the §7.3 charge-projection logic), e.g. "Netflix charges €15.49 tomorrow." Lead time follows the user's reminder preference.
- **Upcoming paydays:** for income sources with a `nextPayment` date, a local notification fires ahead of the payday, e.g. "Payday: Salary expected tomorrow."

**Permission UX:**

- The notification authorization prompt is **deferred until first opt-in** (toggling Payment/Payday reminders on in Settings → Notifications, §12.2), never on cold launch.
- If the user previously denied notifications, toggling on surfaces a non-blocking caption "Enable notifications for Finmate in iOS Settings" with a deep link to the system settings; the app never repeatedly re-prompts.
- Scheduled notifications are recomputed when the underlying subscription/income data changes and cleared when the entity is deleted or notifications are turned off.

**Acceptance criteria — local notifications:**

- [ ] Given the user has never enabled reminders, When the app cold-launches, Then no notification permission prompt appears.
- [ ] Given the user toggles Payment reminders on for the first time, Then the system authorization prompt appears, and on grant a local notification is scheduled ahead of the next projected charge.
- [ ] Given a payday reminder is enabled for an income source with a `nextPayment` date, Then a local notification is scheduled ahead of that date.
- [ ] Given notification permission was previously denied, When the user toggles a reminder on, Then an explanatory caption with a link to iOS Settings appears and the app does not crash or re-prompt repeatedly.
- [ ] Given a subscription with a scheduled charge reminder is deleted, Then its pending local notifications are cancelled.

---

## 8. CSV Import

### 8.1 Purpose

Bulk-import subscriptions from a CSV file with preview, per-row validation, and partial import of valid rows. Maps Substimate's `ImportDataPage.tsx`. Finmate keeps the format and validation philosophy and improves the parser robustness and the value-mapping (minor units, native currency).

### 8.2 Screen & flow

1. **Import screen** (More → Import): a file picker entry ("Choose CSV") via `UIDocumentPickerViewController`/`fileImporter`, plus a "CSV format" help card and a downloadable/visible sample.
2. **Parse & preview:** the selected `.csv` is parsed; a **preview table** lists every row with: row number, name, monthly amount, currency, category, status (`Ready` or comma-joined error list).
3. **Import valid rows:** an "Import N valid rows" button imports only error-free rows; invalid rows are skipped (partial import). Progress + a completion summary ("Imported N subscriptions") and a toast.

### 8.3 Format

Header row required. Recognized columns (with accepted aliases, normalized to snake_case lower):

| Canonical column | Aliases | Required | Notes |
|------------------|---------|----------|-------|
| `name` | `service`, `subscription` | yes | non-empty |
| `amount` | `cost`, `price` | yes (or `monthly_cost`) | interpreted as the **billing-period** amount |
| `monthly_cost` | `monthly_amount` | alt to `amount` | always a monthly amount |
| `billing_period` | `billing`, `period` | no (default `monthly`) | one of weekly/monthly/quarterly/yearly |
| `currency` | — | no (default `EUR`) | EUR/USD/BTC |
| `payment_method` | `payment`, `method` | no (default `credit_card`) | one of the 8 enum values (incl. `other`) |
| `category` | — | no (default `Other`) | created if new |
| `start_date` | `start`, `date` | no (default today) | parsed leniently → ISO date |
| `usage_state` | `usage` | no (default `active`) | active/rarely/unused |
| `url` | `website` | no | normalized to https |
| `auto_renew` | `autorenew` | no (default true) | `true`/`false` |
| `icon` | — | no | SF Symbol / brand id |

Sample CSV shown in-app:

```csv
name,amount,billing_period,currency,payment_method,category,start_date,url
Netflix,15.49,monthly,EUR,credit_card,Streaming,2026-01-01,https://netflix.com
GitHub,100,yearly,USD,paypal,Coding,2026-02-15,https://github.com
```

### 8.4 Validation rules (per row)

- Missing `name` → error "Missing name".
- `amount`/`monthly_cost` not a finite number ≥ 0 → "Invalid amount".
- `billing_period` not in the allowed set → "Invalid billing period". *(Finmate accepts all four periods; Substimate only allowed monthly/yearly.)*
- `currency` not in EUR/USD/BTC → "Unsupported currency".
- `payment_method` not in the 8 values → "Unsupported payment method".
- `usage_state` not in active/rarely/unused → "Unsupported usage state".
- Amount → minor units of the row's currency (2-dp for fiat, integer sats for BTC). The CSV parser handles quoted fields and escaped quotes (the Substimate parser already did; preserve that).

### 8.5 States & edge cases

- **Idle:** picker + format help.
- **Ready:** preview with valid/invalid counts ("3 valid, 1 invalid").
- **Importing:** button shows progress; UI disabled.
- **Complete:** summary + toast; preview retained so the user can re-import after fixing.
- **Error:** non-CSV file → "Only CSV files are supported."; unreadable/empty → "The file didn't contain importable rows."
- **Edge:** duplicate names are allowed (no dedupe in v1) but flagged in preview as a non-blocking "Possible duplicate" hint; partial import never blocks valid rows on a sibling's error.
- Each imported subscription is created through the same repository path as manual add (so its price-history trigger fires).

### 8.6 Acceptance criteria

- [ ] Given a CSV with 3 valid and 1 invalid row, When the user imports, Then exactly 3 subscriptions are created and the invalid row is skipped with its error shown.
- [ ] Given a non-`.csv` file, Then import is refused with "Only CSV files are supported."
- [ ] Given a row with `amount=100` and `billing_period=yearly`, Then the created subscription stores 10000 minor units (USD) with `billing_period = yearly` and a €/$-correct monthly equivalent of ~8.33.
- [ ] Given a quoted field containing a comma, Then the parser keeps it as one field.
- [ ] Given an unknown category, Then it is created as a user-owned category during import.
- [ ] Given import completes, Then each created subscription has an initial `subscription_price_history` row (trigger fired).

---

## 9. Assets / Investments

### 9.1 Purpose

Track assets (stocks, crypto, savings, real estate, other) and their transactions (buy/sell/dividend/other) to show portfolio value and gain/loss. Maps Substimate's `AssetManagementModal.tsx`, `TransactionModal.tsx`, `finance/AssetList.tsx`, `finance/TransactionList.tsx`.

### 9.2 Models

**FinancialAsset** (`financial_assets`):

| Field | Type | Validation |
|-------|------|-----------|
| `name` | `String` | required, 1–120 chars |
| `type` | enum | `stock` · `crypto` · `savings` · `real_estate` · `other` |
| `valueMinor` | `Int64` | current **total** market value (minor units), ≥ 0 |
| `quantity` | `Decimal` | ≥ 0 (supports fractional crypto/shares) |
| `purchasePriceMinor` | `Int64` | **total** cost basis — aggregate amount invested, average-cost method (minor units), ≥ 0 |
| `purchaseDate` | `Date` | ≤ today |
| `currentPriceMinor` | `Int64?` | latest **per-unit** market price |
| `currency` | `CurrencyCode` | EUR/USD/BTC |
| `notes` | `String?` | ≤ 500 |

**AssetTransaction** (`asset_transactions`):

| Field | Type | Validation |
|-------|------|-----------|
| `assetId` | `UUID` | required FK |
| `type` | enum | `buy` · `sell` · `dividend` · `other` |
| `quantity` | `Decimal` | ≥ 0 |
| `priceMinor` | `Int64` | ≥ 0 |
| `date` | `Date` | ≤ today |
| `feesMinor` | `Int64` | ≥ 0, default 0 |
| `notes` | `String?` | ≤ 500 |

### 9.3 Screens

1. **Assets list** (More → Assets): rows (name, type, current value, gain/loss vs cost basis). Header: total portfolio value (display currency). An **Asset Distribution** donut groups total portfolio value by asset `type` (stock · crypto · savings · real_estate · other), with a legend showing each type's value (display currency) and share %, sorted descending — mirroring Substimate `finance/CategoryDistributionChart` with `type=assets`. `+` → Add Asset.
2. **Asset detail:** value, quantity, cost basis, current price, gain/loss %, notes, and a **Transactions** list for that asset; `+` → Add Transaction (pre-filled asset).
3. **Add/Edit Asset sheet:** name, type, quantity, purchase price, purchase date, currency, notes. For `type = crypto` with a Bitcoin-named asset, offer to prefill `currentPrice` from the **server-side Edge Function** market data (see §11) — never a client-side provider call (Substimate fetched market data from the client; Finmate moves it server-side).
4. **Add/Edit Transaction sheet:** type, quantity, price, date, fees, notes.

### 9.4 Flows & computation

- **Unrealized gain/loss** = `valueMinor` − `purchasePriceMinor` (current total market value − total cost basis). `currentPriceMinor` is the latest per-unit market price (so `valueMinor ≈ quantity × currentPriceMinor`), while `purchasePriceMinor` is the aggregate invested. Cost basis is derived from `buy` transactions (qty × price + fees) under the **average-cost** method, reduced by realized `sell`s; `dividend` adds to realized income. v1 computation is documented and unit-tested; the accounting method is recorded in [`./12-decisions-adr.md`](./12-decisions-adr.md) (ADR-0015) — **v1 uses average cost; FIFO is deferred**.
- Adding a `buy`/`sell` transaction optionally updates the asset's `quantity` and `valueMinor`.

### 9.5 States & edge cases

- **Loading/Empty/Error:** standard list skeleton; empty "No assets yet — add a stock, crypto holding, or savings account"; optimistic write with rollback.
- **Edge:** selling more quantity than held → validation error "Can't sell more than you hold."; fractional crypto quantities supported via `Decimal`; mixed-currency assets convert to display currency in totals.

### 9.6 Acceptance criteria

- [ ] Given an asset with cost basis €1,000 and current value €1,250, Then gain/loss shows +€250 (+25%).
- [ ] Given a Bitcoin crypto asset, When prefilling current price, Then the price comes from the Edge Function and no provider key is in the app bundle.
- [ ] Given a `sell` transaction exceeding held quantity, Then the sheet shows a validation error and does not save.
- [ ] Given an asset priced in USD, When display currency is EUR, Then portfolio totals convert while the asset stays USD-native.
- [ ] Given assets of more than one type, Then the Asset Distribution donut shows one slice per asset type, each slice's value equals the summed current value of that type in display currency, and the slice shares sum to 100%.

---

## 10. Crypto / BTC Calculator

### 10.1 Purpose

Convert fiat (EUR/USD) ↔ satoshis/BTC at the live market price. Maps Substimate's `CalculatorPage.tsx` ("Sats Calculator"). Finmate sources the price from a **Supabase Edge Function** instead of a direct client call.

### 10.2 Screen

A two-pane (stacked on iPhone) calculator: an input pane (amount field, EUR/USD segmented control, "Refresh rates" button) and a results pane (current BTC price, computed sats, computed BTC to 8 dp). Bidirectional: entering sats/BTC computes the fiat equivalent too.

- `satsPerBTC = 100_000_000`.
- `sats = round( fiatAmount / btcPrice × satsPerBTC )` using `Decimal` math.
- The BTC price comes from the `market-data` Edge Function (server holds any provider key), which returns the canonical rate JSON `{ "eur_usd", "btc_eur", "btc_usd", "fetched_at" }` (see [`./04-tech-stack.md`](./04-tech-stack.md) "Currency & conversion"). The calculator reads the BTC fiat price directly from `btc_eur` / `btc_usd` — there is no separate response shape for this function.

### 10.3 States & edge cases

- **Loading:** Refresh button spins; last-known price shows a "as of <time>" caption.
- **Empty:** no amount entered → results show "—".
- **Error:** Edge Function failure → inline "Couldn't fetch the current Bitcoin price." with retry; if a cached price exists it stays usable with a staleness caption.
- **Edge:** non-numeric or negative input → results show "—" (no crash); very large inputs format with grouping separators.

### 10.4 Acceptance criteria

- [ ] Given a BTC price of €50,000 and an input of €500, Then the result shows 1,000,000 sats (0.01000000 BTC).
- [ ] Given the price fetch fails and a cached price exists, Then the calculator still computes using the cached price with an "as of" timestamp.
- [ ] Given no app-bundle secret, Then the price comes only from the Edge Function response.
- [ ] Given invalid input, Then results show "—" and the app does not crash or show NaN.

---

## 11. Multi-Currency

### 11.1 Purpose

Let the user view all figures in one display currency (EUR, USD, or BTC) while every entity stores its own native currency in minor units. Maps Substimate's `CurrencyContext.tsx`, but fixes the core defects: no float money and no pre-store conversion.

### 11.2 Behavior

- **Display currency** is a user preference (`currency_preferences.display_currency`), default EUR, changeable in Settings and via a quick switcher.
- **Exchange rates** are cached in `currency_preferences.exchange_rates` (jsonb) with `last_updated`, using the canonical three-pair schema `{ "eur_usd", "btc_eur", "btc_usd", "fetched_at" }` (see [`./04-tech-stack.md`](./04-tech-stack.md) "Currency & conversion"). Rates refresh from the `market-data` Edge Function (server-side fetch replaces Substimate's client fetch); if `fetched_at` is older than 24h the UI shows a "rates may be stale" indicator but still converts.
- **Conversion** happens only at **read/display time**. Stored `amount_minor` + `currency` are never rewritten when display currency changes (the explicit Substimate bug fix).
- **Formatting:** EUR → `de-DE`-style `€` with 2 dp; USD → `en-US` `$` 2 dp; BTC → integer **sats** with grouping ("12,345,678 sats"). Formatting is centralized in `Shared/Utilities` and unit-tested.

### 11.3 States & edge cases

- **Stale rates / offline:** use last cached rates and show a subtle "rates may be out of date" affordance where aggregates are shown; never block reads.
- **Missing rate for a pair:** fall back to a sane default and log; never produce 0 or NaN silently.
- **BTC display:** sub-sat rounding always rounds to the nearest whole sat.

### 11.4 Acceptance criteria

- [ ] Given a subscription stored as 1549 USD-cents, When display currency switches to EUR, Then the displayed value converts using cached rates and the stored row remains `1549` `USD`.
- [ ] Given display currency BTC, Then all amounts render as whole sats with grouping separators.
- [ ] Given the device is offline, Then changing display currency still works using cached rates.
- [ ] Given a brand-new account, Then `currency_preferences` is seeded with the onboarding-chosen currency and default rates.

---

## 12. Settings & Theming

### 12.1 Purpose

Central place for appearance, currency, security/privacy lock, account management, data export, account deletion, notifications, and about. Maps Substimate's `SettingsPage.tsx` (which only had appearance/visual-style, import link, a notifications toggle, and provider-managed 2FA) and expands it to meet App Store and the brief's hardened requirements.

### 12.2 Sections & screens

1. **Appearance**
   - **Theme:** System · Light · Dark (replaces Substimate's binary toggle; persisted to `user_preferences.appearance`).
   - **No "Visual Style" picker.** Substimate shipped 9 competing styles (aurora, brutalist, claymorphism, glassmorphism, minimal, modern, neobrutalist, neumorphism, retro); Finmate is **one Liquid Glass language** (see [`./06-design-system.md`](./06-design-system.md)). This control is intentionally removed.
2. **Currency**
   - **Display currency:** EUR · USD · BTC. Changing it updates every screen at read time.
3. **Security & Privacy**
   - **App Lock (Face ID / Touch ID):** toggle + lock timeout (Immediately · 1 min · 5 min · 15 min) via `LocalAuthentication`. Persisted in `user_preferences.biometric_lock_enabled`.
   - Note: "Authentication and password are managed by your Finmate account" (Supabase Auth).
4. **Notifications**
   - **Payment reminders:** toggle (persisted in `user_preferences`). v1 wires local notifications for upcoming charges where granted; copy reflects the actual capability shipped per [`./08-roadmap-and-milestones.md`](./08-roadmap-and-milestones.md).
5. **Data**
   - **Import from CSV** → §8.
   - **Export my data** → generates a single **`.zip`** archive and presents the share sheet (App Store requirement). The archive contains a round-trippable **JSON** of all user entities **plus per-entity CSVs**, with money exported as raw `minor_units` + ISO currency code (never preformatted, no precision loss). The CSV entities that the CSV importer (§8) supports must round-trip back through import. Exact format spec lives in [`./07-security-and-privacy.md`](./07-security-and-privacy.md) §9.3. Exported entities: subscriptions, subscription price history, income sources, fixed expenses, variable expenses, categories, financial assets, asset transactions, and preferences.
6. **Account**
   - **Email / signed-in identity** (read-only).
   - **Sign out** (§2.3).
   - **Delete account** (destructive): double confirmation (type "DELETE" or hold-to-confirm), calls the server-side `delete-account` Edge Function (see [`./07-security-and-privacy.md`](./07-security-and-privacy.md) §9.3) that removes all user-owned rows and the auth user; clears local caches; returns to Welcome (App Store requirement).
7. **About**
   - App version/build, links to Privacy Policy, Terms, open-source licenses.
   - **Report a problem** — opens an in-app "Report a problem" composer that attaches a **redacted** OSLog excerpt (no PII; redaction rules per [`./07-security-and-privacy.md`](./07-security-and-privacy.md)) and sends to **`support@finmate.app`** *(placeholder — owner to confirm)*. Support is **best-effort triage in v1**.
   - **Analytics stance (explicit):** Finmate **v1 ships NO product analytics** — no event/telemetry SDK, no third-party analytics. Consequently activation and retention are **unmeasured** in v1; a privacy-preserving analytics solution is deferred post-v1 (see [`./09-engineering-practices.md`](./09-engineering-practices.md) §9.2). The only diagnostics that ever leave the device are the redacted logs a user *explicitly* attaches to a "Report a problem" message.

### 12.3 Flows

**Enable App Lock:**
1. Toggle on → immediate `LAContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)` to confirm capability.
2. On success, persist enabled + chosen timeout. On entering the app (cold launch or after the timeout in background), present a biometric gate; on failure offer passcode fallback; repeated failure keeps the app gated.

**Export data:**
1. Tap Export → progress → share sheet with the generated `.zip` archive (round-trippable JSON + per-entity CSVs; money as raw minor units + currency, per §12.2 and [`./07-security-and-privacy.md`](./07-security-and-privacy.md) §9.3). No data leaves the device except via the user's chosen share target.

**Delete account:**
1. Tap Delete account → warning sheet listing what will be removed → strong confirm → server deletion → local wipe → Welcome.

### 12.4 States & edge cases

- **Loading:** preference reads from cache instantly; toggles reflect cached values.
- **Error:** preference write failure rolls back the toggle with a toast.
- **Edge:** biometric not enrolled/available → App Lock toggle is disabled with explanatory caption "Set up Face ID in iOS Settings to use App Lock." Export with no data still produces a valid (empty-collections) archive. Delete account requires online connectivity; offline shows "Connect to the internet to delete your account."

### 12.5 Acceptance criteria

- [ ] Given Theme = System, Then the app follows the device light/dark setting live.
- [ ] Given there is no visual-style picker anywhere in Settings (Substimate's 9-style control is removed).
- [ ] Given App Lock is enabled with timeout = Immediately, When the app returns from background, Then a biometric gate is presented before any data is visible.
- [ ] Given biometrics are not enrolled, Then the App Lock toggle is disabled with an explanatory caption.
- [ ] Given Export my data, Then a share sheet presents a `.zip` containing a round-trippable JSON plus per-entity CSVs of the user's subscriptions, price history, income, fixed/variable expenses, categories, assets, asset transactions, and preferences — with money as raw minor units + ISO currency (no precision loss) — and nothing is transmitted to a third party automatically.
- [ ] Given Delete account is confirmed, Then all user-owned rows and the auth user are removed and the app returns to Welcome with a cleared local cache.

---

## 13. Cross-cutting behaviors

These apply to every pillar and are testable in their own right.

- **Offline-first:** every read is served from the SwiftData cache; every create/update/delete is optimistic locally and synced in the background. Conflicts resolve **last-write-wins per field** using `updated_at` (policy detailed in [`./03-architecture.md`](./03-architecture.md)). A subtle sync indicator shows when the queue is draining.
- **Toasts & feedback:** success/error/info/warning toasts (Substimate's `ToastContext`) reimagined as a single glass toast component with haptics; destructive deletes offer a 5 s **Undo**.
- **Accessibility (first-class):** full Dynamic Type (no clipped layouts up to XXXL), VoiceOver labels/values on every control and chart (charts expose an `accessibilityChartDescriptor` or a text-summary fallback), Reduce Motion disables flow/transition animations, contrast meets WCAG AA in both appearances.
- **Errors never crash:** no force-unwraps on production paths; failed network reads degrade to cached data; math guards against divide-by-zero/NaN (a known Substimate analytics weakness).
- **Empty states everywhere:** every list and chart has a designed empty state with a primary next action.

**Acceptance criteria — cross-cutting:**

- [ ] Given any create action while offline, Then the entity appears immediately and syncs when connectivity returns.
- [ ] Given Dynamic Type at the largest accessibility size, Then no primary screen clips or truncates critical labels.
- [ ] Given a delete, Then an Undo toast appears for 5 s and undo fully restores the entity.

---

## 14. Screen inventory (build checklist)

- [ ] Welcome / Sign-In
- [ ] Email auth sheet · Forgot password sheet
- [ ] Onboarding (currency · appearance · app lock · done)
- [ ] Home dashboard · Customize dashboard sheet
- [ ] Subscriptions list · detail · add · edit · price history
- [ ] Subscription analytics (trends · category · lifetime · usage · payment method)
- [ ] Cash Flow overview · income list/sheet · fixed expenses list/sheet · variable expenses list/sheet
- [ ] Money-flow (Sankey) + supporting breakdowns + timeframe selector
- [ ] Calendar month grid · day detail sheet
- [ ] CSV import (idle · preview · importing · complete · error)
- [ ] Assets list · asset detail · add/edit asset · add/edit transaction
- [ ] BTC / Sats calculator
- [ ] Settings (appearance · currency · security · notifications · data · account · about)

---

## Related documents

- [`../CLAUDE.md`](../CLAUDE.md) — Single source of truth and canonical decisions.
- [`./05-data-model.md`](./05-data-model.md) — Schema, RLS, triggers, and the canonical field names referenced here.
- [`./03-architecture.md`](./03-architecture.md) — Router, stores, repositories, offline-first sync, and the custom Sankey renderer.
- [`./06-design-system.md`](./06-design-system.md) — Liquid Glass components, theming, accessibility primitives.
- [`./07-security-and-privacy.md`](./07-security-and-privacy.md) — Keychain, biometric lock, account deletion, data export, Edge Function secrets.
- [`./11-substimate-analysis.md`](./11-substimate-analysis.md) — Full Substimate feature audit and the KEEP/IMPROVE/CUT migration map.
- [`./08-roadmap-and-milestones.md`](./08-roadmap-and-milestones.md) — Internal build order (M0..Mn) for these pillars.
