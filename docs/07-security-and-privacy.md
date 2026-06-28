# Security, Privacy & Hardening

> The threat model, controls, and hardening checklist that make Finmate a private-first, Apple-grade finance app — covering device, network, and Supabase trust boundaries, with each control mapped to where it is enforced (client / DB / CI).

Finmate stores some of the most sensitive data a person owns: a complete map of their subscriptions, income, expenses, assets, and net worth. The security posture here is a **hard requirement**, not a nice-to-have. This document is the authoritative reference for how Finmate protects that data and is binding on both human engineers and AI coding agents building from these docs.

The guiding principle: **the device is hostile, the network is hostile, and the only thing that authorizes access to a row is `auth.uid()` evaluated server-side inside PostgreSQL Row Level Security.** The client is a convenient, beautiful renderer of data it is *allowed* to see — never the arbiter of what it is allowed to see.

This document grounds its database section in the **actual hardened migrations from Substimate** (the React/Supabase predecessor), specifically `20260627090000_harden_security_definer_functions.sql` and `20260627103000_fix_price_history_currency_and_rpc_hardening.sql`. Finmate reuses those exact patterns because they are correct.

---

## Table of contents

1. [Security objectives & non-goals](#1-security-objectives--non-goals)
2. [Threat model (STRIDE)](#2-threat-model-stride)
3. [Authentication & session security](#3-authentication--session-security)
4. [Authorization — RLS & hardened SECURITY DEFINER functions](#4-authorization--rls--hardened-security-definer-functions)
5. [Secrets management](#5-secrets-management)
6. [Network security](#6-network-security)
7. [Device security & data-at-rest](#7-device-security--data-at-rest)
8. [Input validation & output encoding](#8-input-validation--output-encoding)
9. [Privacy & compliance](#9-privacy--compliance)
10. [Supply-chain security](#10-supply-chain-security)
11. [Logging, telemetry & observability](#11-logging-telemetry--observability)
12. [Hardening checklist](#12-hardening-checklist)
13. [Backups & disaster recovery](#13-backups--disaster-recovery)
14. [Incident response](#14-incident-response)
15. [Related documents](#15-related-documents)

---

## 1. Security objectives & non-goals

### Objectives (in priority order)

1. **Confidentiality of financial data.** A user's rows are never readable by any other principal — not other users, not an unauthenticated attacker, not a leaked client build, not a curious engineer running ad-hoc queries with the wrong role.
2. **Integrity of money math and ownership.** No client can write a row it does not own, mislabel currency, or corrupt the `user_id` linkage. Money is `Int64` minor units (cents / satoshis) — never `Double` — so rounding cannot silently destroy value (see [`./05-data-model.md`](./05-data-model.md)).
3. **Credential safety on device.** Auth tokens live in the iOS Keychain with the most restrictive access class that still permits background refresh, never in `UserDefaults` or plaintext files.
4. **No secrets in the client.** Only the public anon key ships in the app bundle. Service-role keys and any market-data provider keys live exclusively in Supabase Edge Function environment variables.
5. **Privacy by design.** Data minimization, an accurate App Privacy nutrition label, no third-party trackers, no PII in logs, and in-app account deletion + data export.

### Non-goals (explicitly out of scope for v1)

- **Defending against a fully jailbroken, attacker-controlled device with the legitimate user's biometrics/passcode.** If the OS sandbox and Secure Enclave are defeated, the local cache is exposed. We mitigate (file protection, Keychain access classes, optional biometric lock) but do not claim immunity. iOS jailbreak detection is a **post-v1** consideration, deliberately not relied upon.
- **End-to-end encryption of data at rest in Postgres.** Finmate is private-first, not zero-knowledge. Supabase (the database operator) can technically read rows. This is an accepted, documented trust assumption; revisiting it (client-side field encryption) is logged as a future ADR candidate in [`./12-decisions-adr.md`](./12-decisions-adr.md).
- **Protecting against a compromised Apple ID / iCloud Keychain.** Out of our control.
- **Web client hardening.** The web client is now in scope as a second client after the iOS foundation ([`./16-web-client.md`](./16-web-client.md), [ADR-0021](./12-decisions-adr.md#adr-0021--web-client-brought-into-scope-amends-adr-0002)); it reuses the same backend contract and inherits RLS, but its browser-specific concerns (XSS, CSP, CSRF, session storage) are out of scope for *this* iOS-focused posture and are documented in the web client's own hardening pass.

---

## 2. Threat model (STRIDE)

### 2.1 Assets

| Asset | Sensitivity | Where it lives |
|---|---|---|
| User financial data (subscriptions, income, expenses, assets, transactions) | **High** | Postgres (source of truth) + SwiftData local cache (device) |
| Auth tokens (access JWT + refresh token) | **Critical** | iOS Keychain (device); minted by Supabase Auth (server) |
| `user_id` / `auth.uid()` identity binding | **Critical** | Postgres `auth.users`; embedded as `sub` claim in JWT |
| Supabase anon key | Low (public by design) | App bundle, source |
| Supabase service-role key | **Critical** | Edge Function env only — never in client |
| Market-data provider keys (BTC/FX) | Medium | Edge Function env only |
| Derived analytics & net worth | High | Computed on device from the above |

### 2.2 Actors

- **Legitimate user** — owns the device and one Supabase account. Trusted within their own data partition.
- **Co-located attacker** — has brief physical access to an unlocked or lockscreen device (lost phone, shoulder-surfer, malicious roommate).
- **Network attacker** — controls the network path (rogue Wi-Fi, captive portal, on-path MITM).
- **Malicious authenticated user** — a real Finmate account holder who crafts API requests (bypassing the app UI) to try to read or mutate *other* users' rows.
- **Anonymous internet attacker** — hits the Supabase REST/Realtime endpoints with the public anon key and no valid session.
- **Supply-chain attacker** — compromises an SPM dependency or a GitHub Action.
- **Curious insider** — an engineer with database console access using the wrong (over-privileged) role.

### 2.3 Trust boundaries

```
            +---------------------------------------------------+
            |                  DEVICE (untrusted host)          |
            |                                                   |
            |   SwiftUI app  ──>  Keychain (tokens)             |
            |       │             SwiftData cache (file-prot.)  |
            |       │                                           |
            +───────┼───────────────────────────────────────────+
                    │  ── TRUST BOUNDARY 1: device ↔ network
                    │     (TLS 1.2+, ATS, optional cert pinning)
                    ▼
            +---------------------------------------------------+
            |          NETWORK (untrusted transport)            |
            +---------------------------------------------------+
                    │  ── TRUST BOUNDARY 2: network ↔ Supabase
                    ▼
   +-------------------------------------------------------------------+
   |                       SUPABASE (semi-trusted)                     |
   |                                                                   |
   |   API Gateway (anon key gates entry, not authorization)           |
   |        │                                                          |
   |        ▼                                                          |
   |   PostgREST / Realtime ──> Postgres + RLS  ◄── THE REAL PERIMETER |
   |        │                      (auth.uid() owner checks)           |
   |        ▼                                                          |
   |   Edge Functions (service-role + provider keys live ONLY here)    |
   |        │                                                          |
   |        └──> external market-data APIs (BTC price, FX rates)       |
   +-------------------------------------------------------------------+
```

**Key insight:** the anon key gates *entry to the API*, not *access to data*. Anyone can obtain the anon key by inspecting the app bundle — that is expected and fine. The actual authorization perimeter is **RLS inside Postgres**, evaluated on every row using the `auth.uid()` derived from the verified JWT.

### 2.4 STRIDE threats and mitigations

Legend for **Enforced at**: **C** = Client (Swift), **DB** = Supabase/Postgres, **EF** = Edge Function, **CI** = pipeline, **AS** = App Store / process.

| # | STRIDE | Threat scenario | Mitigation | Enforced at |
|---|---|---|---|---|
| T1 | **Spoofing** | Attacker forges a request claiming to be another user by passing a chosen `user_id`. | Server **ignores any client-supplied `user_id`**; ownership is derived from `auth.uid()` in RLS and inside every `SECURITY DEFINER` function. INSERT policies use `WITH CHECK (auth.uid() = user_id)`. | DB |
| T2 | **Spoofing** | Stolen/forged JWT used to impersonate a user. | Supabase signs JWTs with the project secret; PostgREST verifies the signature. Short-lived access tokens (1 h) + rotating refresh tokens. Sign in with Apple uses Apple-issued identity tokens. | DB, C |
| T3 | **Tampering** | Malicious authenticated user edits/deletes another user's subscription via raw REST call. | RLS `UPDATE`/`DELETE` policies `USING (auth.uid() = user_id)`; Finmate's hardened RPCs re-check `user_id = auth.uid()` per row (`delete_subscription`, `batch_reorder_subscriptions`). | DB |
| T4 | **Tampering** | Client mislabels currency or stores a converted amount under the wrong code (the Substimate "EUR pre-store" bug). | Money stored as native-currency `Int64` minor units; `CHECK (currency IN ('EUR','USD','BTC'))`; no client-side currency conversion before store. | C, DB |
| T5 | **Repudiation** | Price/currency change happens with no audit trail. | DB trigger `handle_subscription_price_change()` (SECURITY DEFINER) writes an immutable `subscription_price_history` row on every price/currency change. | DB |
| T6 | **Information disclosure** | Anonymous attacker queries REST endpoints with the anon key and reads all rows. | **RLS enabled on every table.** With no valid session, `auth.uid()` is `NULL`, so `auth.uid() = user_id` is never true → zero rows. Anon key alone returns nothing. | DB |
| T7 | **Information disclosure** | Tokens read from device storage (lost phone, backup extraction). | Tokens in **Keychain** with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (non-syncable, non-exportable to other devices, unavailable before first unlock). Never `UserDefaults`/plist. | C |
| T8 | **Information disclosure** | Cached financial data read from device filesystem. | SwiftData store uses **`NSFileProtectionComplete`**-class protection; sensitive caches **wiped on logout**; app supports optional biometric lock. | C |
| T9 | **Information disclosure** | Secrets (service-role key, provider keys) leak from the app bundle or git history. | Only the **anon key** ships. Service-role + provider keys live in Edge Function env. **Gitleaks** secret scan in CI; `.env` git-ignored. | C, EF, CI |
| T10 | **Information disclosure** | On-path attacker reads traffic. | **ATS** (HTTPS-only, TLS 1.2+, forward secrecy); optional **certificate pinning** for the Supabase host. | C |
| T11 | **Information disclosure** | Sensitive values captured via screenshots, app-switcher snapshot, or clipboard. | Privacy overlay on backgrounding (app-switcher snapshot blur); no auto-copy of balances; clipboard items that *are* copied use expiring/`isSensitive` pasteboard items. | C |
| T12 | **Elevation of privilege** | A `SECURITY DEFINER` function is hijacked via `search_path` injection (a shadowed `subscriptions` table/operator in a malicious schema). | Every definer function sets **`SET search_path = public`**, `REVOKE ALL ... FROM PUBLIC`, `GRANT EXECUTE ... TO authenticated`. | DB |
| T13 | **Elevation of privilege** | Function accepts caller-supplied `user_id` and acts on someone else's rows. | Legacy `(uuid, uuid)` signatures **dropped**; recreated to derive ownership from `auth.uid()` only. | DB |
| T14 | **Denial of service** | Abuse of auth or market-data endpoints. | Supabase Auth built-in rate limits; Edge Function caches market data (short TTL) so external APIs are not hammered; client backoff on 429. | EF, DB, C |
| T15 | **Spoofing / tampering (supply chain)** | Compromised SPM dependency or GitHub Action injects code. | Pinned dependency versions + `Package.resolved` committed; pinned action SHAs; dependency review in CI. | CI |

---

## 3. Authentication & session security

### 3.1 Identity providers

Finmate uses **Supabase Auth** with two sign-in methods (per the canonical brief):

1. **Sign in with Apple** (primary, privacy-preserving — supports Apple's private relay email). Required by App Store guidelines when offering third-party sign-in.
2. **Email + password** (fallback / power users), with Supabase email confirmation enabled.

Substimate shipped email/password only (`signInWithPassword`, `signUp`) — Finmate **adds Sign in with Apple** and is the canonical improvement.

```swift
// Features/Auth — sign in with Apple via supabase-swift.
// The ASAuthorizationAppleIDCredential identity token is handed to Supabase Auth,
// which verifies it with Apple and mints a Supabase session.
func signInWithApple(idToken: String, nonce: String) async throws {
    try await supabase.auth.signInWithIdToken(
        credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
    )
}
```

The `nonce` is generated client-side as a cryptographically random value, **SHA-256 hashed** before being placed in the `ASAuthorizationAppleIDRequest`, and sent raw to Supabase — this binds the Apple credential to this specific request and defeats replay (T2).

### 3.2 Token storage — the Keychain rule

> **Hard rule:** access and refresh tokens are stored in the **iOS Keychain**, never in `UserDefaults`, never in a file, never in `@AppStorage`.

`supabase-swift` exposes a pluggable session storage. Finmate injects a Keychain-backed implementation:

```swift
// DataLayer/Auth — KeychainTokenStorage
import Security

struct KeychainTokenStorage: AuthLocalStorage {
    private let service = "com.finmate.app.supabase.session"
    // After first unlock, this-device-only: survives reboots for background
    // token refresh, but is NOT synced to iCloud Keychain and NOT restored
    // onto a different device from an encrypted backup.
    private let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    func store(key: String, value: Data) throws {
        // Every write explicitly pins kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        // so no item is ever created with the weaker default access class.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessible as String: accessibility,
            kSecValueData as String: value
        ]
        SecItemDelete(query as CFDictionary) // upsert
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    func retrieve(key: String) throws -> Data? { /* SecItemCopyMatching */ }
    func remove(key: String) throws { /* SecItemDelete */ }

    /// Deletes every session item this storage owns (all keys under `service`).
    /// Used by SensitiveCacheCleaner on logout (§3.4).
    func removeAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }
}
```

**Why `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`:**

- `...AfterFirstUnlock` (not `...WhenUnlocked`) — the SDK must refresh tokens during background work (e.g. a sync triggered by a notification), which can happen while the screen is locked but after the first post-boot unlock.
- `...ThisDeviceOnly` — the item is **never** written to iCloud Keychain and **never** migrates to a restored/cloned device (T7). A stolen iCloud backup yields no Finmate tokens.

### 3.3 Token lifecycle & refresh

- Access tokens are short-lived JWTs (default 3600 s). `supabase-swift` **auto-refreshes** using the rotating refresh token; Finmate does not hand-roll refresh.
- Refresh-token rotation is enabled in the Supabase project so a captured refresh token is single-use.
- The app observes auth state changes via the SDK's `authStateChanges` async stream and routes the UI between authenticated and unauthenticated states. This mirrors Substimate's `onAuthStateChange` listener but in Swift Concurrency:

```swift
// Features/Auth — AuthStore (@Observable @MainActor)
func observeAuth() async {
    for await (event, session) in supabase.auth.authStateChanges {
        switch event {
        case .signedIn, .tokenRefreshed:
            self.session = session
        case .signedOut:
            self.session = nil
            await SensitiveCacheCleaner.purge() // see §3.4
        default:
            break
        }
    }
}
```

### 3.4 Logout & sensitive-cache clearing

On sign-out, Finmate must leave **no readable financial data** behind. Substimate already clears `localStorage` keys (`subscriptions`, `categories`, `dashboard_layout`) on `SIGNED_OUT`; Finmate hardens this into a deterministic, exhaustive purge:

```swift
// DataLayer — SensitiveCacheCleaner
enum SensitiveCacheCleaner {
    static func purge() async {
        try? await supabase.auth.signOut()        // revoke refresh token server-side
        try? KeychainTokenStorage().removeAll()    // wipe tokens from Keychain
        await ModelStore.shared.deleteAllUserData()// drop the SwiftData store contents
        InMemoryCaches.shared.clear()              // FX rates, computed analytics, images
        URLCache.shared.removeAllCachedResponses()
    }
}
```

Logout invokes `supabase.auth.signOut()` so the refresh token is invalidated **server-side** as well as locally — a stolen-then-logged-out token cannot be reused.

| Auth control | Enforced at |
|---|---|
| Sign in with Apple + email/password | C + DB (Supabase Auth) |
| Tokens in Keychain (`AfterFirstUnlockThisDeviceOnly`) | C |
| Auto refresh + rotation + short-lived access tokens | C (SDK) + DB |
| Server-side sign-out (refresh revocation) | C → DB |
| Exhaustive cache purge on logout | C |

---

## 4. Authorization — RLS & hardened SECURITY DEFINER functions

> Full schema, every table's policies, and migration ordering live in [`./05-data-model.md`](./05-data-model.md). This section covers the **security rationale and the hardening patterns**, grounded in Substimate's real migrations.

### 4.1 RLS on every table, ownership from `auth.uid()`

Every table carries a `user_id uuid REFERENCES auth.users` column, has `ENABLE ROW LEVEL SECURITY`, and exposes owner-only policies. Substimate's `subscriptions` table (`20250208144136_light_forest.sql`) is the canonical, correct pattern Finmate adopts verbatim:

```sql
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own subscriptions"
  ON subscriptions FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Users can create subscriptions"
  ON subscriptions FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);   -- can only insert rows you own

CREATE POLICY "Users can update own subscriptions"
  ON subscriptions FOR UPDATE TO authenticated
  USING (auth.uid() = user_id)         -- can only target your rows
  WITH CHECK (auth.uid() = user_id);   -- and can't re-assign ownership

CREATE POLICY "Users can delete own subscriptions"
  ON subscriptions FOR DELETE TO authenticated
  USING (auth.uid() = user_id);
```

For the financial tables, Substimate's `20250309195225_long_breeze.sql` uses the compact `FOR ALL` form, which Finmate keeps for `financial_assets`, `asset_transactions`, `fixed_expenses`, `variable_expenses`, and `income_sources`:

```sql
ALTER TABLE financial_assets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own assets"
  ON financial_assets FOR ALL TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
```

**Three rules every Finmate table must satisfy (gated by the Database & RLS regression CI job — §5 / the quality-gates table of [`./09-engineering-practices.md`](./09-engineering-practices.md) — which runs migrations against an ephemeral Postgres and executes pgTAP/pg_prove RLS/definer assertions):**

1. RLS is **enabled** (and `FORCE`d so even the table owner role is subject to it).
2. Policies are scoped `TO authenticated` (never `TO public`/`anon`).
3. Both `USING` (read/target filter) **and** `WITH CHECK` (write guard) reference `auth.uid() = user_id` for any write path. A missing `WITH CHECK` would let a user re-home a row onto another user.

**Why this is the real perimeter (T6):** an anonymous caller using only the anon key has `auth.uid() = NULL`. `NULL = user_id` evaluates to `NULL` (not true), so the policy filters out every row. The anon key buys you the right to *ask*; RLS decides you receive *nothing*.

> ⚠️ **Substimate gap Finmate closes:** the `subscription_price_history` table is written by a trigger and must *also* carry its own owner-only RLS policies (it stores `user_id`). Finmate's data model requires explicit RLS on price-history so a direct read of that table is owner-scoped too — see [`./05-data-model.md`](./05-data-model.md).

### 4.2 The four hardening rules for `SECURITY DEFINER` functions

`SECURITY DEFINER` functions run with the **definer's** privileges (effectively bypassing RLS), so they are a privilege-escalation surface (T12, T13). Substimate's `20260627090000_harden_security_definer_functions.sql` and `20260627103000_fix_price_history_currency_and_rpc_hardening.sql` apply four rules that Finmate mandates for **every** definer function:

1. **`SET search_path = public`** — pins the schema search path so an attacker cannot shadow `subscriptions`, an operator, or a function with a malicious object in a schema earlier on the path. Without this, a definer function is a textbook search-path injection target.
2. **`REVOKE ALL ON FUNCTION ... FROM PUBLIC`** — removes the default `EXECUTE` grant that Postgres hands to `PUBLIC`.
3. **`GRANT EXECUTE ON FUNCTION ... TO authenticated`** — re-grants execute to logged-in users only (omitted for trigger functions, which are invoked by the trigger, not called directly — see `handle_subscription_price_change`).
4. **Per-row owner check via `auth.uid()` inside the body** — the function never trusts a caller-supplied id and never operates outside the caller's partition.

#### Canonical example: delete RPC

The quoted migration below is **Substimate's** (its RPC is named `delete_subscription_directly`); the equivalent Finmate RPC is named **`delete_subscription`** and applies the identical hardening. Note the **dropped** two-arg legacy signature that accepted a caller-supplied `user_id`:

```sql
-- 20260627090000_harden_security_definer_functions.sql
DROP FUNCTION IF EXISTS delete_subscription_directly(uuid, uuid);  -- legacy: trusted caller uid (T13)

CREATE OR REPLACE FUNCTION delete_subscription_directly(sub_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public          -- rule 1
AS $$
BEGIN
  DELETE FROM subscriptions
  WHERE id = sub_id
    AND user_id = auth.uid();     -- rule 4: ownership from session, not args
END;
$$;

REVOKE ALL ON FUNCTION delete_subscription_directly(uuid) FROM PUBLIC;     -- rule 2
GRANT EXECUTE ON FUNCTION delete_subscription_directly(uuid) TO authenticated; -- rule 3
```

#### Canonical example: aggregation RPC (`get_user_categories`)

```sql
DROP FUNCTION IF EXISTS get_user_categories(uuid);  -- drop caller-uid variant

CREATE OR REPLACE FUNCTION get_user_categories()
RETURNS TABLE (category text, subscription_count bigint)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT subscriptions.category, COUNT(*) AS subscription_count
  FROM subscriptions
  WHERE subscriptions.user_id = auth.uid()   -- partition to the caller
    AND subscriptions.category IS NOT NULL
  GROUP BY subscriptions.category
  ORDER BY subscriptions.category;
$$;

REVOKE ALL ON FUNCTION get_user_categories() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_user_categories() TO authenticated;
```

Finmate exposes the equivalent **`get_user_categories`-style RPC** for its user-owned `Category` model (the canonical brief calls for a `get_user_categories` equivalent).

#### Canonical example: trigger function (audit trail) + batch RPC with explicit owner check

From **Substimate's** `20260627103000_fix_price_history_currency_and_rpc_hardening.sql`, the price-history trigger (T5) and the reorder RPC (T3) — note the batch RPC validates **each** element's ownership before mutating. Substimate names its reorder RPC `batch_update_subscription_order`; the equivalent Finmate RPC is named **`batch_reorder_subscriptions`** with the same per-row owner check:

```sql
CREATE OR REPLACE FUNCTION handle_subscription_price_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF (TG_OP = 'INSERT')
     OR (OLD.monthly_cost IS DISTINCT FROM NEW.monthly_cost)
     OR (OLD.currency IS DISTINCT FROM NEW.currency) THEN
    INSERT INTO subscription_price_history (
      subscription_id, user_id, monthly_cost, currency, effective_from, is_correction
    ) VALUES (
      NEW.id, NEW.user_id, NEW.monthly_cost, NEW.currency,
      CASE WHEN TG_OP = 'INSERT' THEN COALESCE(NEW.start_date, now()) ELSE now() END,
      false
    );
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION handle_subscription_price_change() FROM PUBLIC;  -- no direct EXECUTE grant

-- Batch reorder: per-row ownership assertion, raises on any foreign row
CREATE OR REPLACE FUNCTION batch_update_subscription_order(updates jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE subscription_record record;
BEGIN
  IF jsonb_typeof(updates) != 'array' THEN
    RAISE EXCEPTION 'Input must be a JSONB array';   -- input validation in the DB
  END IF;
  FOR subscription_record IN
    SELECT (value->>'id')::uuid AS id, (value->>'created_at')::timestamptz AS new_created_at
    FROM jsonb_array_elements(updates)
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM subscriptions
      WHERE id = subscription_record.id AND user_id = auth.uid()
    ) THEN
      RAISE EXCEPTION 'Access denied for subscription %', subscription_record.id;  -- T3
    END IF;
    UPDATE subscriptions SET created_at = subscription_record.new_created_at
    WHERE id = subscription_record.id AND user_id = auth.uid();
  END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION batch_update_subscription_order(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION batch_update_subscription_order(jsonb) TO authenticated;
```

### 4.3 Authorization checklist for new tables/functions

When an engineer or agent adds a table or RPC, the migration **must**:

- [ ] Add `user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL`.
- [ ] `ALTER TABLE x ENABLE ROW LEVEL SECURITY;` (and `FORCE ROW LEVEL SECURITY`).
- [ ] Add SELECT/INSERT/UPDATE/DELETE (or `FOR ALL`) policies `TO authenticated` with `auth.uid() = user_id` in both `USING` and `WITH CHECK`.
- [ ] Add `CHECK` constraints (currency in allowed set, `amount_minor >= 0` where appropriate).
- [ ] For any `SECURITY DEFINER` function: apply all four hardening rules (§4.2) and drop any legacy signature that accepts a caller-supplied id.

| Authorization control | Enforced at |
|---|---|
| RLS owner policies on every table | DB |
| `SECURITY DEFINER` four-rule hardening | DB |
| Drop caller-uid legacy signatures | DB |
| Per-row owner checks in RPCs | DB |
| Immutable price-history audit trail | DB (trigger) |
| Database & RLS regression job enforcing the above | CI (docs/09 §5 / quality-gates) |

---

## 5. Secrets management

### 5.1 What may ship in the client

**Only the Supabase project URL and the public anon key.** That is the complete set of secrets allowed in the app bundle. The anon key is designed to be public; RLS is what protects data (§4). Substimate models this correctly — its `.env.example` contains exactly two non-secret values:

```env
VITE_SUPABASE_URL=https://your-project-ref.supabase.co
VITE_SUPABASE_ANON_KEY=your-supabase-anon-key
```

Finmate's iOS equivalent injects these at build time (xcconfig + Info.plist keys, or a generated `Secrets.swift` from CI) — values are **not** hardcoded in tracked source. Per-environment (`Debug`/`Release`/TestFlight) configs point at separate Supabase projects.

### 5.2 What must NEVER ship in the client

- **Supabase service-role key** — bypasses RLS entirely. If it leaked, every user's data is exposed. Lives **only** in Edge Function environment variables.
- **Market-data provider API keys** (BTC price, FX rates). This is a deliberate, canonical improvement over Substimate, whose `src/lib/marketData.ts` calls CoinGecko and Frankfurter **directly from the client**:

  ```ts
  // Substimate (anti-pattern Finmate removes): client calls market APIs directly.
  await fetch(`https://api.coingecko.com/api/v3/simple/price?${params}`);
  await fetch('https://api.frankfurter.app/latest?from=EUR&to=USD');
  ```

  Today these endpoints happen to be keyless, but the architecture leaks the *provider relationship*, can't add a paid/keyed provider without shipping the key, can't cache centrally, and exposes the client to provider-side response tampering. **Finmate routes all market data through a Supabase Edge Function** so any provider key stays server-side, responses are validated and cached, and the BTC/crypto calculator converts fiat ↔ satoshis using server-fetched data:

  ```
  iOS app ──(authenticated)──> Edge Function `market-data`
                                  │  reads PROVIDER_API_KEY from env
                                  │  fetches + validates + caches (TTL ~60s)
                                  ▼
                          { btc_eur, btc_usd, eur_usd, fetched_at }
  ```

### 5.3 `.env` hygiene and git

- `.env` and `.env.*` are **git-ignored**; only `.env.example` (placeholders, no real values) is committed. Substimate's `.gitignore` already does this:

  ```gitignore
  .env
  .env.*
  !.env.example
  ```

- xcconfig files holding real keys are git-ignored; an `.xcconfig.example` is committed.
- **Gitleaks** runs in CI on every PR and push (Substimate's `.github/workflows/ci.yml` already includes `gitleaks/gitleaks-action`). Finmate keeps this step and adds a custom rule set covering Supabase keys (`sb_...`, JWT-shaped anon/service keys) and Apple `AuthKey_*.p8` patterns.
- Fastlane signing material (App Store Connect API key `.p8`, match certificates) lives in CI secrets, never in the repo.

### 5.4 Secret rotation

- Anon key rotation: re-provision via Supabase, ship a new build. Low blast radius (public key).
- Service-role / provider key rotation: update Edge Function env, redeploy. No client release needed.
- If a service-role key is ever exposed → treat as a Sev-1 incident (§14): rotate immediately, audit logs for anomalous reads, force-rotate JWT signing secret if there is any chance it was paired.

| Secret control | Enforced at |
|---|---|
| Anon key only in client | C |
| Service-role + provider keys in Edge Function env | EF |
| Market data proxied via Edge Function | EF (+ C calls it) |
| `.env`/xcconfig git-ignored, `.example` committed | CI / repo |
| Gitleaks secret scan | CI |
| Signing secrets in CI vault | CI |

---

## 6. Network security

### 6.1 App Transport Security (ATS)

- **HTTPS-only, no exceptions.** The `Info.plist` contains **no** `NSAllowsArbitraryLoads` and no per-domain ATS exceptions. All Supabase and Edge Function traffic is TLS 1.2+ with forward-secret cipher suites — the iOS defaults enforce this.
- Local/dev pointing at a non-TLS Supabase emulator is handled with a **Debug-only** build config and a scoped exception, never in `Release`/TestFlight builds.

### 6.2 Certificate pinning (optional, recommended)

Pinning the Supabase host's certificate (or its SPKI public-key hash) defeats on-path TLS interception with a rogue-but-trusted CA (T10). Finmate implements this via a `URLSessionDelegate` that the `supabase-swift` client's `URLSession` uses:

```swift
// DataLayer/Networking — PinnedSessionDelegate
func urlSession(_ session: URLSession,
                didReceive challenge: URLAuthenticationChallenge,
                completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
          let trust = challenge.protectionSpace.serverTrust,
          let key = SecTrustCopyKey(trust),
          PinnedKeys.spkiHashes.contains(sha256SPKI(key)) else {
        completionHandler(.cancelAuthenticationChallenge, nil); return  // fail closed
    }
    completionHandler(.useCredential, URLCredential(trust: trust))
}
```

**Operational guardrails (pinning is a foot-gun if misconfigured):**

- Pin **two** SPKI hashes (current + a pre-provisioned backup/intermediate) so certificate renewal does not brick the app.
- Pinning config is **feature-flagged** and remote-killable, so a surprise cert change cannot strand users on an old build.
- Decision: pinning is **recommended but not blocking for v1** (Supabase rotates certs on a managed cadence). Tracked as an ADR candidate in [`./12-decisions-adr.md`](./12-decisions-adr.md).

| Network control | Enforced at |
|---|---|
| ATS HTTPS-only, TLS 1.2+ | C (Info.plist) |
| No arbitrary-load exceptions in Release | C + CI (plist lint) |
| Optional SPKI cert pinning, fail-closed, dual-pin | C |

---

## 7. Device security & data-at-rest

### 7.1 Biometric app lock (LocalAuthentication)

An optional **Face ID / Touch ID** app lock gates entry to Finmate (canonical brief; toggled in onboarding and Settings). It is an app-entry gate layered *on top of* — not a replacement for — the device passcode.

```swift
// Features/Auth — AppLockService
import LocalAuthentication

func authenticate() async throws {
    let context = LAContext()
    context.localizedFallbackTitle = "Use Passcode"
    var error: NSError?
    // Prefer biometrics; fall back to device passcode so a user without enrolled
    // biometrics is not locked out (deviceOwnerAuthentication includes passcode).
    let policy: LAPolicy = .deviceOwnerAuthentication
    guard context.canEvaluatePolicy(policy, error: &error) else { throw AppLockError.unavailable }
    let ok = try await context.evaluatePolicy(policy, localizedReason: "Unlock Finmate")
    guard ok else { throw AppLockError.failed }
}
```

- **Configurable timeout** (immediately / after 1 min / 5 min / 15 min) determines how long after backgrounding a re-auth is required.
- The lock is purely a UI gate — it does **not** decrypt data; data protection (§7.2) is what actually protects bytes at rest.
- Respects `reduce motion`/accessibility; never traps the user in a loop if biometrics fail (passcode fallback).

### 7.2 Data-at-rest

| Storage | Protection |
|---|---|
| Auth tokens | Keychain, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (§3.2). |
| SwiftData offline cache | File-protection class **Complete** (`NSFileProtectionComplete`): the store file is encrypted and inaccessible while the device is locked. Set via the app's data-protection entitlement and the SwiftData/Core Data store options. |
| In-memory analytics, FX rates, decoded icons | Process memory only; cleared on logout and on memory pressure. |
| Image cache (vendor icons) | `URLCache` with file protection; non-sensitive but still purged on logout. |

> **Note on SwiftData + full file protection:** `NSFileProtectionComplete` means the store is unreadable when locked, which can interrupt background writes while the screen is off. Finmate uses **Complete** for the primary store and falls back to **CompleteUnlessOpen** only for components that genuinely need locked-screen background access. This trade-off is recorded in [`./03-architecture.md`](./03-architecture.md) and [`./12-decisions-adr.md`](./12-decisions-adr.md). If SwiftData's protection controls prove too coarse, GRDB/SQLite (the documented fallback) gives finer-grained control.

### 7.3 Screenshot, app-switcher snapshot & clipboard (T11)

- **App-switcher snapshot blur:** on `scenePhase` transition to `.inactive`/`.background`, Finmate overlays an opaque privacy view (logo over a `.regularMaterial` blur) so the multitasking thumbnail never shows balances.
- **Screenshots:** iOS cannot fully block screenshots of arbitrary SwiftUI content, so Finmate (a) does not display full account numbers anywhere, (b) optionally posts a privacy reminder when a screenshot is detected on a sensitive screen via `UIScreen.userDidTakeScreenshotNotification`.
- **Clipboard:** balances are never auto-copied. When the user explicitly copies a value (e.g. a BTC amount from the calculator), Finmate writes an **expiring, local-only** pasteboard item (`UIPasteboard` with `expirationDate` and `localOnly: true`) so it neither syncs via Universal Clipboard nor lingers indefinitely.

| Device control | Enforced at |
|---|---|
| Optional biometric/passcode app lock + timeout | C |
| Keychain access class for tokens | C |
| SwiftData store file protection (Complete) | C |
| App-switcher privacy overlay | C |
| Screenshot reminder on sensitive screens | C |
| Expiring, local-only clipboard items | C |

---

## 8. Input validation & output encoding

Validation is **defense in depth**: client validation for UX and early rejection, **DB constraints as the authoritative gate** (a malicious client bypassing the UI still cannot persist invalid data).

### 8.1 Client-side (Swift)

- A dedicated `Money` value type wraps `Int64` minor units + ISO currency code; parsing user input (e.g. "12.99") goes through `Decimal` then to minor units with explicit rounding — never `Double`. Negative amounts rejected where `amount_minor >= 0` applies.
- All free-text fields are length-bounded and trimmed; URLs validated against an allowlist scheme (`https`).
- **CSV import** is parsed and validated with a typed parser before any write, then shown in a **preview** for user confirmation (a canonical pillar; Substimate had import but lacked tests — Finmate ships unit tests for the parser per [`./09-engineering-practices.md`](./09-engineering-practices.md)). Imports are streamed with row count caps and per-cell type/format validation to avoid pathological inputs.
- Typed, throwing errors (no force-unwraps on production paths) surface validation failures as user-facing toasts.

### 8.2 Database-side

- `CHECK` constraints encode the rules authoritatively, e.g. from Substimate's hardened currency migration:

  ```sql
  ALTER TABLE subscriptions
    ADD CONSTRAINT valid_subscription_currency CHECK (currency IN ('EUR','USD','BTC'));
  ALTER TABLE subscription_price_history
    ADD CONSTRAINT valid_price_history_currency CHECK (currency IN ('EUR','USD','BTC'));
  ```

  Finmate extends this pattern to `amount_minor >= 0`, enum-like `billing_period`/`frequency`/`usage_state`/`type` checks, and `NOT NULL` ownership columns. The reorder RPC additionally validates its JSONB input shape (`jsonb_typeof(updates) != 'array' → RAISE EXCEPTION`).

### 8.3 Output encoding / injection

- The `supabase-swift` SDK issues **parameterized** PostgREST and RPC requests; Finmate never string-interpolates user input into queries.
- No raw HTML/web views render user data in the iOS client (native SwiftUI text), so classic XSS is not in scope there. The **web client** (see [`./16-web-client.md`](./16-web-client.md)) must apply a strict Content-Security-Policy and output-encoding; XSS hardening is owned there.

| Validation control | Enforced at |
|---|---|
| `Money`/`Decimal` parsing, no `Double` | C |
| Field length/URL/scheme validation | C |
| CSV import typed parse + preview + caps | C |
| `CHECK` constraints (currency, amounts, enums) | DB |
| RPC input-shape validation | DB |
| Parameterized requests (no injection) | C (SDK) |

---

## 9. Privacy & compliance

Finmate is **private-first** — this is the brand promise, and the privacy controls are first-class.

### 9.1 Data minimization

- Collect only what a finance app needs: the user's own financial records plus an email (or Apple private-relay address) for auth. No contacts, no location, no device advertising identifier (IDFA), no behavioral profiling.
- Sign in with Apple is offered specifically so users can withhold their real email.

### 9.2 App Privacy nutrition label (App Store Connect)

The label is filled out **accurately** (a compliance obligation, T-process). Expected declarations:

| Data type | Collected? | Linked to identity? | Used for tracking? | Purpose |
|---|---|---|---|---|
| Email address | Yes | Yes | **No** | App functionality (account/auth) |
| Financial info (the user's own records) | Yes | Yes | **No** | App functionality |
| User ID (`auth.uid()`) | Yes | Yes | **No** | App functionality |
| Diagnostics (crash, non-PII) | Optional | No | **No** | App functionality / debugging |
| Usage data, advertising, location, contacts | **No** | — | — | Not collected |

**No third-party trackers**, **no analytics SDKs that profile users**, **no IDFA**. Any future analytics is privacy-preserving and aggregate; no PII or financial values ever enter analytics or logs.

#### Encryption export-compliance declaration

Finmate uses **only** standard, exempt cryptography: HTTPS/TLS for transport (system `URLSession`), the iOS Keychain, and OS-level file-protection at rest. It implements **no proprietary or non-standard encryption** and does not bundle a custom crypto library. Therefore the `Info.plist` declares:

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

Rationale (kept with the key in source control): the only cryptography is (a) standard HTTPS/TLS terminated by the OS networking stack, and (b) Apple-provided Keychain and Data Protection. Both fall under the App Store Connect export-compliance exemption for apps that "only use standard encryption within Apple's operating system," so no annual self-classification report (CCATS/ERN) is filed. If Finmate ever adds client-side field encryption (the post-v1 zero-knowledge ADR candidate in [`./12-decisions-adr.md`](./12-decisions-adr.md)), this declaration is re-evaluated and the key flipped to `true` with a French encryption declaration as required.

#### Age rating

Finmate's App Store **age rating is 4+**: it contains no objectionable content, no user-generated social feed, no gambling, no unrestricted web browsing (the only outbound web is opening a user-entered subscription vendor URL in `SFSafariViewController`, see [`./02-product-spec.md`](./02-product-spec.md) §4.3). The questionnaire answers are recorded with the metadata plan below.

#### Reviewer demo account & review notes

App Review must be able to exercise the full app without creating their own account or hitting an empty state:

- A **seeded reviewer demo account** (email/password) is provisioned in the production Supabase project, pre-populated with representative subscriptions, income, expenses, assets, and transactions so every screen renders real data. Credentials are supplied in App Store Connect's **App Review Information** fields (never committed to the repo).
- A **review-notes template** accompanies every submission:

  ```
  Sign in: use the demo account in the App Review Information fields
           (email + password), OR tap "Sign in with Apple".
  To test: 1) Subscriptions tab — add a subscription (the Add sheet
              prefills vendor/icon/category from the prediction engine).
           2) Cash Flow tab — view the money-flow buckets; tap a bucket
              to drill into its categories.
           3) Calculator tab — convert fiat <-> BTC (rates fetched via
              the market-data Edge Function).
           4) Settings — Export Data (produces a .zip) and Delete Account
              (irreversible; demo account is reset between submissions).
  Notes:   All financial data is the signed-in user's own and is
           gated by Postgres RLS; there is no shared/social content.
  ```

#### Sign in with Apple — review rules

Because Finmate offers Sign in with Apple, App Review Guideline **4.8 / 4.0** rules are honored:

- An **equivalent email/password path** is offered alongside Sign in with Apple, so a reviewer (or user) is never forced through Apple.
- Sign in with Apple is presented **at least as prominently** as the email/password option on the auth screen (it is the primary CTA, per §3.1).
- Finmate **does not require a real email**: Apple's private-relay address is accepted and never resolved or cross-referenced; the email/password path likewise does not demand identity verification beyond confirmation.

#### Screenshots & metadata plan

- **Screenshots** are captured deterministically via a Fastlane `snapshot` (UI-test) lane against the seeded demo data on the required device sizes (6.7" / 6.9" and 6.1" iPhone classes), in light and dark, so the store listing always matches the shipped build. No mocked/photoshopped financials.
- **Metadata** (name, subtitle, keywords, description, support URL, marketing URL, privacy policy URL) lives in `fastlane/metadata/` (Fastlane `deliver`) and is versioned in the repo. The privacy-policy and terms URLs are the stable URLs from the [Legal & policy documents](#94-legal--policy-documents) subsection.

### 9.3 Account deletion & data export (App Store 5.1.1(v))

App Store Review Guideline **5.1.1(v)** requires that apps offering account creation also offer **in-app account deletion**. Finmate ships both, inside Settings:

- **Account deletion:** a confirmed, in-app flow that calls a hardened Edge Function (`delete-account`, service-role, re-verifies `auth.uid()` from the caller's JWT) to delete the `auth.users` row. Because every table FKs `user_id ... ON DELETE CASCADE` (see `20250309195225_long_breeze.sql`), all financial rows are removed transactionally. The local cache and Keychain are then purged via `SensitiveCacheCleaner` (§3.4). Deletion is irreversible and clearly communicated.

#### `delete-account` Edge Function (security-critical)

`delete-account` is one of exactly two named Edge Functions in v1 (the other is `market-data`). It is the **only** path to account deletion and is hardened so the deleted identity can never be attacker-chosen. The identity is derived **exclusively from the verified JWT**, never from the request body:

1. **Reject any request lacking a valid bearer JWT.** A missing/blank/malformed `Authorization` header returns `401` immediately — no service-role work happens.
2. **Verify the caller with a per-request client.** A Supabase client is constructed *per request* using the caller's `Authorization` bearer token; `auth.getUser()` validates the JWT against Supabase Auth and returns the authenticated `uid`. If verification fails, return `401`.
3. **Ignore any body-supplied id.** Whatever `user_id`/`id` the body contains is discarded. The only id used for deletion is the `verifiedUid` from step 2.
4. **Delete with the service-role client.** The service-role client is used **only** to call `auth.admin.deleteUser(verifiedUid)`; the `ON DELETE CASCADE` FKs remove all owned rows transactionally.

```ts
// supabase/functions/delete-account/index.ts
import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  // (1) Require a bearer JWT — reject anything without one.
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return new Response(JSON.stringify({ error: "Missing bearer token" }), { status: 401 });
  }

  // (2) Per-request client bound to the CALLER's token; verify against Supabase Auth.
  const callerClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: { user }, error: authError } = await callerClient.auth.getUser();
  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Invalid token" }), { status: 401 });
  }
  const verifiedUid = user.id; // (3) the ONLY id we trust — any body-supplied id is ignored.

  // (4) Service-role client used ONLY to delete the verified user.
  const adminClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, // never shipped to the client
  );
  const { error: deleteError } = await adminClient.auth.admin.deleteUser(verifiedUid);
  if (deleteError) {
    return new Response(JSON.stringify({ error: "Deletion failed" }), { status: 500 });
  }
  return new Response(JSON.stringify({ deleted: true }), { status: 200 });
});
```

The service-role key is read from Edge Function env (§5.2) and never leaves the server. Because `verifiedUid` comes from `auth.getUser()` and the body is never consulted for identity, a malicious authenticated user cannot delete another user's account by supplying a foreign id (a Spoofing/T1-class defense). This function is listed in the Edge Function inventory in [`./05-data-model.md`](./05-data-model.md).
- **Data export:** the user can export all their data on device from authenticated reads — supporting GDPR data-portability and giving users control even though Finmate is not formally a GDPR data controller for an individual's personal-use records. The export format is specified below.

#### Data export format (`.zip`)

Settings → **Export Data** produces a **single `.zip` archive** containing both a round-trippable JSON document and per-entity CSV files:

```
finmate-export-2026-06-28.zip
├─ finmate-export.json        ← complete, round-trippable dump of ALL user entities
├─ subscriptions.csv
├─ income_sources.csv
├─ fixed_expenses.csv
├─ variable_expenses.csv
├─ financial_assets.csv
├─ asset_transactions.csv
├─ categories.csv
├─ subscription_price_history.csv
└─ README.txt                 ← format/version notes + the money-encoding contract
```

**Exported entities** (everything the user owns): `subscriptions`, `income_sources`, `fixed_expenses`, `variable_expenses`, `financial_assets`, `asset_transactions`, `categories` (both `subscription` and `expense` kinds), and `subscription_price_history`. The `user_preferences` / `dashboard_layouts` rows are device/account settings, not financial records, and are intentionally **not** part of the portable export.

**Money is exported losslessly.** Every monetary value is written as its **raw `Int64` minor units plus the ISO currency code** — e.g. `amount_minor: 1299, currency: "EUR"` — **never** pre-formatted (`"€12.99"`) and **never** converted to a display currency. This mirrors the storage contract (§ [`./05-data-model.md`](./05-data-model.md)) and guarantees a re-import suffers **zero precision loss** (the same discipline that fixes Substimate's float/pre-convert bug). Dates are exported as ISO 8601 (`yyyy-MM-dd` for date-only fields; full timestamp for `created_at`/`updated_at`).

**Round-trip guarantee.** The CSV files for the entities the **CSV importer** supports (subscriptions, income, fixed/variable expenses — see the Import pillar in [`./02-product-spec.md`](./02-product-spec.md)) are emitted in exactly the column shape that import accepts, so an exported CSV re-imports cleanly. CSV number columns use the lossless `amount_minor` + `currency` representation; on import, the locale-aware parser still applies only to free-typed user input, not to these machine columns (see the internationalization/formatting rules in [`./05-data-model.md`](./05-data-model.md) / [`./06-design-system.md`](./06-design-system.md)). A DataLayer round-trip test asserts that export → import reproduces every entity field-for-field.

### 9.4 Legal & policy documents

A Privacy Policy and Terms of Service are **mandatory and must be live before submission** — App Store Review requires a reachable privacy-policy URL, and Finmate's "private-first" promise is hollow without a published policy.

- **Hosting:** both documents are hosted at **stable, public URLs**:
  - Privacy Policy — `https://finmate.app/privacy` *(owner to confirm domain)*
  - Terms of Service — `https://finmate.app/terms` *(owner to confirm domain)*

  These exact URLs are what the App Store listing's "Privacy Policy URL" and the in-app Settings links point to, and they appear in the Fastlane `deliver` metadata (§9.2).
- **Ownership & authoring:** the **product owner** authors and owns the legal text (engineering does not invent legal language). Engineering owns wiring the URLs into the build and listing.
- **Versioning:** the Markdown/HTML sources are versioned in a repo **`legal/`** directory (`legal/privacy-policy.md`, `legal/terms-of-service.md`) with a visible `Last updated` date and a changelog, so the published documents trace to a commit.

**Privacy Policy — minimum content checklist:**
- [ ] What data is collected (email/Apple-relay address, the user's own financial records, `auth.uid()`, non-PII diagnostics) — mirroring the §9.2 nutrition label exactly.
- [ ] Why it is collected (account/auth and app functionality only) and that there is **no tracking, no IDFA, no ad/behavioral profiling, no data selling**.
- [ ] Who processes it: Supabase as data sub-processor, the chosen data-residency region (§9.4 GDPR posture), and the market-data provider relationship (server-side only).
- [ ] User rights: erasure (in-app account deletion, §9.3), access/portability (in-app export, §9.3), and how to exercise them.
- [ ] Data retention and what deletion removes (cascade), plus the security posture summary (RLS, encryption in transit/at rest, Keychain).
- [ ] Contact path for privacy requests (the support address from [`./02-product-spec.md`](./02-product-spec.md) Settings / docs/09) and `Last updated` date.

**Terms of Service — minimum content checklist:**
- [ ] Service description, eligibility/age (4+), and acceptable-use.
- [ ] Account responsibilities and the irreversible nature of account deletion.
- [ ] Disclaimer that Finmate is a personal-finance **tracking** tool, **not** financial, tax, or investment advice.
- [ ] Limitation of liability, warranty disclaimer, governing law *(owner to confirm jurisdiction)*.
- [ ] Changes-to-terms process and effective/`Last updated` date.

> **Milestone dependency:** a privacy-policy + terms **stub live at the stable URLs** is an explicit **M0** deliverable, and the **final, owner-approved** documents are a hard **M8** (submission) gate — tracked in [`./08-roadmap-and-milestones.md`](./08-roadmap-and-milestones.md) and [`./10-task-backlog.md`](./10-task-backlog.md).

### 9.5 GDPR-friendly posture

- **Right to erasure** → account deletion (§9.3).
- **Right to access / portability** → data export (§9.3).
- **Data minimization & purpose limitation** → §9.1.
- **Transparency** → a plain-language privacy policy linked in-app and on the App Store listing (§9.4).
- **Data residency** → choose a Supabase region appropriate to the launch market (EU region for an EU-centric launch); recorded in [`./12-decisions-adr.md`](./12-decisions-adr.md).

| Privacy control | Enforced at |
|---|---|
| Data minimization (no trackers/IDFA/location) | C + AS |
| Accurate App Privacy label | AS |
| `ITSAppUsesNonExemptEncryption = NO` (exempt crypto) | C + AS |
| Reviewer demo account + review notes; SIWA 4.8 parity | AS |
| In-app account deletion (cascade) via hardened Edge Function | C + EF + DB |
| In-app data export (`.zip`: JSON + per-entity CSV, raw minor units) | C |
| Privacy Policy + Terms live at stable URLs (M0 stub / M8 final) | AS + repo |
| Privacy policy + GDPR posture | AS |
| No PII/financial values in logs | C |

---

## 10. Supply-chain security

- **Pinned SPM dependencies.** Exact versions are pinned and `Package.resolved` is **committed** so every build (and every CI run) resolves byte-identical dependency graphs. No floating `branch:`/`from:`-only ranges for security-relevant packages. Primary dependencies and their pins are catalogued in [`./04-tech-stack.md`](./04-tech-stack.md) — at minimum `supabase-swift`, `swift-snapshot-testing`, and any vetted flow/Sankey renderer.
- **Dependency review in CI.** New or bumped dependencies require an explicit PR with a justification; CI runs a dependency-review step that flags known-vulnerable versions and license changes. (Substimate's web CI runs `npm audit --audit-level=moderate`; the Swift equivalent is pinned `Package.resolved` diffs + dependency-review.)
- **Pinned GitHub Actions by SHA.** Workflow steps reference actions by commit SHA (not floating tags) to prevent tag-repoint supply-chain attacks (T15). Substimate's workflow uses `@v7`/`@v6`/`@v3` tags; Finmate hardens these to SHAs.
- **Minimal CI permissions.** Workflows declare least-privilege `permissions:` (Substimate already sets `contents: read`); Finmate keeps `contents: read` as the default and elevates per-job only when strictly required (e.g. TestFlight upload).
- **Vendor before unvetted.** A new third-party SPM package for a security-sensitive function (crypto, networking, the Sankey renderer) requires review of its maintenance, license, and transitive deps before adoption.

| Supply-chain control | Enforced at |
|---|---|
| Pinned SPM versions + committed `Package.resolved` | CI / repo |
| Dependency review on PRs | CI |
| GitHub Actions pinned by SHA | CI |
| Least-privilege workflow permissions | CI |

---

## 11. Logging, telemetry & observability

- **Structured logging via `OSLog`** with explicit privacy qualifiers. Anything that could be PII or a financial value is logged as `.private` (redacted in release) or simply not logged. The default is to log *events*, not *data*:

  ```swift
  import OSLog
  let log = Logger(subsystem: "com.finmate.app", category: "sync")
  // user_id and amounts are sensitive → .private (redacted on device by default)
  log.info("sync.upsert ok table=\(table, privacy: .public) rows=\(count, privacy: .public) uid=\(uid, privacy: .private)")
  ```

- **No financial values, account identifiers, or tokens in logs**, crash reports, or analytics — ever (T8/privacy). This is checked in code review and by a SwiftLint custom rule flagging string-interpolated logging of known-sensitive types.
- **Crash reporting** (if enabled) uses a privacy-respecting tool configured to strip user data; symbolication only, no breadcrumbs containing financial content.
- Server-side, Supabase logs API/auth events; access to those logs is restricted to the on-call owner and used for incident investigation (§14), not analytics.

---

## 12. Hardening checklist

A consolidated, auditable checklist. Each item names where it is enforced. This list is the **Definition of Done gate** for any security-relevant change and is cross-referenced from [`./09-engineering-practices.md`](./09-engineering-practices.md) and [`./10-task-backlog.md`](./10-task-backlog.md).

### Authentication & session
- [ ] Sign in with Apple implemented with hashed nonce (replay-safe). **[C/DB]**
- [ ] Email/password with email confirmation enabled. **[DB]**
- [ ] Tokens stored in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; never `UserDefaults`. **[C]**
- [ ] Refresh-token rotation enabled; access token TTL ≤ 1 h. **[DB]**
- [ ] Logout calls server-side `signOut()` and purges Keychain + SwiftData + in-memory caches. **[C]**

### Authorization (database)
- [ ] RLS `ENABLE`d **and** `FORCE`d on every table. **[DB]**
- [ ] Owner policies `TO authenticated` with `auth.uid() = user_id` in `USING` and `WITH CHECK`. **[DB]**
- [ ] `subscription_price_history` has its own owner-only RLS policies. **[DB]**
- [ ] Every `SECURITY DEFINER` fn: `SET search_path = public`, `REVOKE ALL FROM PUBLIC`, `GRANT EXECUTE TO authenticated`, per-row `auth.uid()` check. **[DB]**
- [ ] No function signature accepts a caller-supplied `user_id`; legacy ones dropped. **[DB]**
- [ ] Database & RLS regression CI job (docs/09 §5 / quality-gates: `supabase db reset` on ephemeral Postgres + pgTAP/pg_prove) asserts RLS enabled-and-forced on every table, a second user reads zero rows, and every definer fn has pinned `search_path` + `REVOKE PUBLIC` + no caller-supplied uid. **[CI]**

### Secrets
- [ ] Only Supabase URL + anon key in the client. **[C]**
- [ ] Service-role + market-data provider keys only in Edge Function env. **[EF]**
- [ ] Market data fetched server-side via Edge Function, not the client. **[EF/C]**
- [ ] `.env`/xcconfig with real values git-ignored; `.example` committed. **[repo]**
- [ ] Gitleaks secret scan passes on every PR/push. **[CI]**

### Network
- [ ] ATS HTTPS-only; no `NSAllowsArbitraryLoads` in Release. **[C]**
- [ ] (Recommended) SPKI cert pinning, fail-closed, dual-pinned, kill-switchable. **[C]**

### Device & data-at-rest
- [ ] Optional biometric/passcode app lock with configurable timeout. **[C]**
- [ ] SwiftData store uses file protection (Complete / CompleteUnlessOpen). **[C]**
- [ ] App-switcher privacy overlay on background. **[C]**
- [ ] No full account numbers shown; expiring local-only clipboard for copied values. **[C]**

### Input validation
- [ ] `Money`/`Decimal` parsing (no `Double`); negative/oversize inputs rejected. **[C]**
- [ ] DB `CHECK` constraints for currency, amounts, and enums. **[DB]**
- [ ] CSV import typed-parsed, capped, previewed before write; covered by tests. **[C/CI]**
- [ ] Parameterized SDK requests only (no string-built queries). **[C]**

### Privacy & compliance
- [ ] Accurate App Privacy nutrition label; no trackers/IDFA. **[AS]**
- [ ] In-app account deletion (cascade) via hardened Edge Function. **[C/EF/DB]**
- [ ] In-app data export (CSV/JSON). **[C]**
- [ ] No PII/financial values in logs, crash reports, analytics. **[C]**

### Supply chain & CI
- [ ] SPM versions pinned; `Package.resolved` committed. **[repo]**
- [ ] Dependency review on dependency changes. **[CI]**
- [ ] GitHub Actions pinned by SHA; least-privilege `permissions:`. **[CI]**
- [ ] SwiftLint + swift-format + build + test all required to merge. **[CI]**

---

## 13. Backups & disaster recovery

A confidentiality-first posture is incomplete without **availability and durability**: a bad migration, an accidental mass-delete, or a regional incident must not destroy users' financial history. Backups and recovery are a Supabase-plan and process concern; the plan posture itself is recorded in **ADR-0018** ([`./12-decisions-adr.md`](./12-decisions-adr.md)) and the "Supabase plan & scaling" subsection of [`./04-tech-stack.md`](./04-tech-stack.md).

### 13.1 Production runs on Supabase Pro

- **Production uses Supabase Pro**, which unlocks **daily automated backups** and **Point-in-Time Recovery (PITR)** with at least a **7-day retention** window. Dev/preview environments may stay on Free (Free has no PITR and auto-pauses after 7 days of inactivity), but the production project is Pro precisely so backups + PITR exist.
- PITR lets us restore to any moment within the retention window (not just the nightly snapshot), which is what makes recovery from a mid-day destructive event possible with minimal data loss.

### 13.2 Forward-only migrations with a tested rollback/forward-fix policy

- Migrations are **forward-only**: we do not run speculative `down` migrations against production. A regression is corrected by a **new forward migration** (forward-fix), which is itself reviewed and tested in CI against an ephemeral Postgres (the Database & RLS regression job, §4 / [`./09-engineering-practices.md`](./09-engineering-practices.md)).
- **Before applying any destructive migration in production** (a `DROP`, a column type change, a data backfill that rewrites rows, a `DELETE`), the on-call owner takes a **fresh manual backup/snapshot immediately beforehand** so PITR is anchored at a known-good point right before the change. Destructive migrations are tagged as such in review.
- A rollback that cannot be expressed as a forward-fix (e.g. data already destroyed) escalates to the **restore runbook** below.

### 13.3 Restore runbook

When data loss or a bad migration is confirmed (a Sev-1/Sev-2 per §14), restore via PITR to a **fork**, verify, then cut over — never restore destructively over the live project blind:

1. **Identify the target timestamp** — the last moment before the bad event (from migration logs, the deploy timestamp, or the first error report). Note it in UTC.
2. **PITR-restore to a fork / new project**, not in place — Supabase restores to a separate instance at the chosen timestamp, leaving the (possibly corrupted) live project untouched for forensics.
3. **Verify the fork** — run smoke checks: row counts per table vs. expectations, RLS still enabled-and-forced, the seeded default categories present, a sample user's data intact, money fields still raw `Int64` minor units (no precision/conversion damage).
4. **Cut over** — repoint the app's Supabase URL/keys (per-environment xcconfig, §5.1) to the verified fork, or promote the fork, during a brief maintenance window. Communicate via the support channel.
5. **Post-restore** — re-anchor a fresh backup, file the incident post-mortem (§14), and add a regression test/check for the failure class (e.g. a CI assertion that the offending migration shape is rejected).

### 13.4 What backups do and do not cover

- **Covered:** all Postgres data (every user's financial rows, categories, price history, preferences) and schema. Account deletion remains atomic via `ON DELETE CASCADE` (§9.3) — backups are about *accidental* loss, not undoing a user's intentional deletion.
- **Not covered by Postgres backups:** Edge Function code and secrets (versioned in the repo + CI vault, §5), and the device-local SwiftData cache (reconstructed from the server on next sync — it is a cache, not a source of truth).

> **Risk register cross-reference:** a **"data-loss / bad-migration"** risk is recorded in the [`./08-roadmap-and-milestones.md`](./08-roadmap-and-milestones.md) risk register, mitigated by Pro + PITR, forward-only migrations, the pre-destructive-migration snapshot rule, and this runbook.

| Backup/DR control | Enforced at |
|---|---|
| Production on Supabase Pro (daily backups + PITR ≥ 7 days) | DB / process |
| Forward-only migrations; forward-fix policy | CI / process |
| Fresh snapshot before any destructive prod migration | process |
| PITR-restore-to-fork → verify → cut-over runbook | process |

---

## 14. Incident response

A lightweight but real process suitable for a small team / solo owner.

### Severity levels

| Sev | Definition | Example | Target response |
|---|---|---|---|
| **Sev-1** | Confidentiality/integrity breach of user data, or service-role key exposure. | Service-role key committed to git; an RLS gap lets a user read others' rows. | Immediate (acknowledge < 1 h) |
| **Sev-2** | Security control degraded but no confirmed data exposure. | Cert pinning misconfigured; Gitleaks false-negative found post-merge. | < 24 h |
| **Sev-3** | Hardening gap / hygiene issue with low immediate risk. | A new table merged without `FORCE RLS`. | Next working day |

### Response runbook

1. **Detect** — sources: Gitleaks/CI failures, Supabase auth/API anomaly logs, App Store/user reports, dependency-review alerts.
2. **Contain** — rotate any exposed secret *immediately* (service-role key, JWT signing secret if implicated, provider keys). Disable a compromised Edge Function. If an RLS gap is found, ship the corrective migration first (`ENABLE`/`FORCE RLS`, fix the policy) before anything else.
3. **Eradicate** — fix root cause: corrected migration, patched dependency, rotated key. Add a regression test (RLS test that a second user gets zero rows; a Gitleaks rule for the leaked pattern).
4. **Recover** — force re-authentication if refresh tokens may be compromised (rotate JWT secret invalidates all sessions); ship the patched build to TestFlight → App Store expedited review if user-facing.
5. **Notify** — if personal data was exposed, notify affected users and (where GDPR applies) the relevant supervisory authority within the legally required window. Maintain a contact path in the privacy policy.
6. **Post-mortem** — blameless write-up; capture the gap as a new checklist item (§12) and, if architectural, a new ADR in [`./12-decisions-adr.md`](./12-decisions-adr.md).

### Standing safeguards that shorten incidents

- Secrets are rotatable without a client release (service-role/provider keys in Edge env).
- `ON DELETE CASCADE` means account deletion is atomic and complete.
- Sessions are centrally revocable (JWT secret rotation) for a worst-case mass logout.
- CI fails closed on secret-scan and lint, so most classes never reach `main`.

---

## 15. Related documents

- [`../CLAUDE.md`](../CLAUDE.md) — Canonical decisions brief & entry point (the security posture summarized here is binding).
- [`./05-data-model.md`](./05-data-model.md) — Full schema, every table's RLS policies, migrations, and constraints.
- [`./03-architecture.md`](./03-architecture.md) — Where the DataLayer, Keychain storage, sync engine, and Edge Functions live in the module graph.
- [`./04-tech-stack.md`](./04-tech-stack.md) — `supabase-swift`, pinned dependency versions, and tooling.
- [`./09-engineering-practices.md`](./09-engineering-practices.md) — CI gates, SwiftLint/swift-format, testing, Definition of Done.
- [`./07-security-and-privacy.md`](./07-security-and-privacy.md) — (this document).
- [`./11-substimate-analysis.md`](./11-substimate-analysis.md) — Detailed Substimate → Finmate migration map (currency bug, RPC hardening, client-side market data).
- [`./12-decisions-adr.md`](./12-decisions-adr.md) — ADRs: minimum iOS 18, cert pinning, file-protection class, data residency, field-level encryption.
