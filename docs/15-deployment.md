# Backend Deployment Runbook

> Zero-to-working Finmate Supabase backend in a handful of commands — local dev stack, hosted-project linking, schema + Edge Function deploys, secrets, Auth providers, environments, backups, smoke tests, and rollback. This is the operational companion to the normative schema in [`./05-data-model.md`](./05-data-model.md), the security posture in [`./07-security-and-privacy.md`](./07-security-and-privacy.md), and the cost/scaling posture in [`./04-tech-stack.md`](./04-tech-stack.md).

Finmate's backend is **the entire product spine**: a managed PostgreSQL database with Row Level Security, two Edge Functions (`market-data`, `delete-account`), and Supabase Auth. The iOS app is just one consumer of this contract (a future web client will be another — see [`../CLAUDE.md`](../CLAUDE.md)). This document is binding on anyone — human or AI agent — who provisions, deploys, or operates that backend.

Two helper scripts make the common paths one command each:

- [`scripts/setup-backend.sh`](../scripts/setup-backend.sh) — bring up the **local** stack, apply all migrations, and serve the Edge Functions.
- [`scripts/deploy-backend.sh`](../scripts/deploy-backend.sh) — link-check, push the schema, deploy **both** functions, and set their production secrets from the environment.

---

## Table of contents

1. [TL;DR — the happy path](#1-tldr--the-happy-path)
2. [Prerequisites](#2-prerequisites)
3. [Repository layout the scripts assume](#3-repository-layout-the-scripts-assume)
4. [Local development](#4-local-development)
5. [Linking a hosted project](#5-linking-a-hosted-project)
6. [Applying the schema (`db push`)](#6-applying-the-schema-db-push)
7. [Deploying the Edge Functions](#7-deploying-the-edge-functions)
8. [Setting production secrets](#8-setting-production-secrets)
9. [Enabling Auth providers (email + Sign in with Apple)](#9-enabling-auth-providers-email--sign-in-with-apple)
10. [Environments (dev / staging / prod)](#10-environments-dev--staging--prod)
11. [Backups & PITR on Pro](#11-backups--pitr-on-pro)
12. [Smoke-test checklist](#12-smoke-test-checklist)
13. [Rollback & forward-fix](#13-rollback--forward-fix)
14. [The four deferred owner placeholders](#14-the-four-deferred-owner-placeholders)
15. [Helper-script reference](#15-helper-script-reference)
16. [Related documents](#16-related-documents)

---

## 1. TL;DR — the happy path

**Local, from a clean checkout:**

```bash
# 1. Bring up Postgres + Auth + Functions locally, apply every migration, serve functions.
./scripts/setup-backend.sh
# → prints local API URL + anon key; functions served on http://127.0.0.1:54321/functions/v1
```

**Hosted (staging or prod), once you have a project ref:**

```bash
# 2. Authenticate the CLI once per machine.
supabase login

# 3. Link this repo to a hosted project (interactive db-password prompt).
supabase link --project-ref <PROJECT_REF>

# 4. Push schema + deploy both functions + set production secrets from env.
export COINGECKO_API_KEY=<your-coingecko-key>
./scripts/deploy-backend.sh
```

That is the whole backend. Everything below is the detail behind those four commands, plus the manual steps the CLI cannot do for you (enabling Auth providers, turning on PITR), and the verification you must run afterward.

---

## 2. Prerequisites

You need an account, three tools, and (for hosted deploys) one provider key.

| Requirement | What / why | Install / get it |
|---|---|---|
| **Supabase account** | Owns the hosted dev/staging/prod projects and the billing plan. | <https://supabase.com> — sign up, create an organization. |
| **Supabase CLI** ≥ 1.200 | Drives `start`, `db reset`, `db push`, `functions deploy`, `secrets set`, `link`. The single tool this whole runbook is built on. | `brew install supabase/tap/supabase` (macOS) · or download from <https://github.com/supabase/cli/releases>. Verify: `supabase --version`. |
| **Docker Desktop** (or a Docker-compatible runtime) | The **local** stack (`supabase start`) runs Postgres, Auth, Realtime, Storage, and the functions runtime in containers. Not needed for hosted-only operations, but `db reset` and `functions serve` require it. | <https://www.docker.com/products/docker-desktop> · or Colima/OrbStack. Verify: `docker info`. |
| **Deno** ≥ 1.45 | The Edge Function runtime. The CLI bundles a Deno for `functions serve`/`deploy`, but a local Deno lets you type-check and lint `supabase/functions/**` (`deno check`, `deno lint`) before deploying. | `brew install deno` · or <https://deno.land>. Verify: `deno --version`. |
| **`COINGECKO_API_KEY`** (hosted only) | The rate-provider key the `market-data` function reads **server-side** so it never ships in the app bundle (see [`./07-security-and-privacy.md`](./07-security-and-privacy.md#52-what-must-never-ship-in-the-client)). | A CoinGecko API key (Demo or Pro). Not required for the local stack — `market-data` falls back to keyless calls locally. |

> **You do not need** the service-role key as an input: `SUPABASE_SERVICE_ROLE_KEY` is **injected into every Edge Function automatically** by the platform (and by the local runtime). The `delete-account` function reads it from `Deno.env` — you never set it as a secret. See [§8](#8-setting-production-secrets).

A quick all-in-one preflight (the scripts run a stricter version of this):

```bash
supabase --version && docker info >/dev/null && deno --version
```

---

## 3. Repository layout the scripts assume

The backend lives entirely under `supabase/`, exactly as the migration plan in [`./05-data-model.md §7.1`](./05-data-model.md) lays out:

```text
finmate/
├─ supabase/
│  ├─ config.toml                      ← project id, local ports, auth config (created by `supabase init`)
│  ├─ migrations/                       ← forward-only, timestamped SQL (the schema, RLS, triggers, RPCs)
│  │  ├─ 20260628000100_extensions_and_helpers.sql
│  │  ├─ 20260628000200_categories.sql
│  │  ├─ 20260628000300_subscriptions.sql
│  │  ├─ 20260628000400_subscription_price_history.sql
│  │  ├─ 20260628000500_income_and_expenses.sql
│  │  ├─ 20260628000600_assets.sql
│  │  ├─ 20260628000700_preferences.sql
│  │  ├─ 20260628000800_rpcs.sql
│  │  └─ 20260628000900_new_user_bootstrap.sql
│  ├─ functions/
│  │  ├─ _shared/cors.ts                ← shared CORS + JSON helpers (no secrets in responses)
│  │  ├─ market-data/index.ts           ← FX + fiat↔sats; holds COINGECKO_API_KEY server-side
│  │  └─ delete-account/index.ts        ← JWT-verified account deletion (service-role, server-only)
│  ├─ seed.sql                          ← optional local-only seed (NOT run against prod)
│  └─ .env                              ← LOCAL function secrets (git-ignored; see §4.4)
└─ scripts/
   ├─ setup-backend.sh
   └─ deploy-backend.sh
```

> **`supabase init` is assumed already done** — `supabase/config.toml` exists in the repo. If you are bootstrapping a brand-new clone and it is missing, run `supabase init` once (it is idempotent and will not clobber existing migrations/functions).

---

## 4. Local development

The local stack is a full Supabase running in Docker on your machine. It is disposable: you can reset it to a pristine, fully-migrated state at any time. Use it for all day-to-day development — never develop against the hosted prod project.

### 4.1 One command

```bash
./scripts/setup-backend.sh
```

This script (see [§15](#15-helper-script-reference)) does, in order: preflight (CLI + Docker present), `supabase start`, `supabase db reset` (re-applies **all** migrations against the fresh local Postgres), prints the local API URL + anon key, then `supabase functions serve` (foreground). The manual equivalent is the next three subsections.

### 4.2 `supabase start` — bring the stack up

```bash
supabase start
```

First run pulls container images (slow once, cached after). On success the CLI prints the local endpoints and keys — capture these for the iOS Debug xcconfig ([§10](#10-environments-dev--staging--prod)):

```text
         API URL: http://127.0.0.1:54321
     GraphQL URL: http://127.0.0.1:54321/graphql/v1
          DB URL: postgresql://postgres:postgres@127.0.0.1:54322/postgres
      Studio URL: http://127.0.0.1:54323
        anon key: eyJhbGciOi... (local, non-secret, safe to commit to a Debug xcconfig)
service_role key: eyJhbGciOi... (local only — still never ships in the app)
```

Stop the stack with `supabase stop` (add `--no-backup` to also drop the local data volume).

### 4.3 `supabase db reset` — apply all migrations

```bash
supabase db reset
```

This **drops and recreates** the local database, then replays **every** file in `supabase/migrations/` in lexicographic (= chronological) order, and finally runs `supabase/seed.sql` if present. It is the local mirror of what CI does on every PR (the Database & RLS regression job in [`./09-engineering-practices.md`](./09-engineering-practices.md)). Run it whenever you add or edit a migration.

Because the schema's `handle_new_user()` trigger seeds the 18 subscription + 11 expense categories on each new `auth.users` row (see [`./05-data-model.md §7.2`](./05-data-model.md)), a freshly-reset DB already has correct per-user category seeding the moment you sign up a test user — no manual seed step is needed for that.

To author a new migration:

```bash
supabase migration new add_something          # creates a timestamped empty SQL file
# …edit supabase/migrations/<timestamp>_add_something.sql…
supabase db reset                              # re-apply the whole set, including the new file
```

### 4.4 `supabase functions serve` — run the Edge Functions locally

```bash
supabase functions serve            # serves ALL functions with hot reload
# or a single one:
supabase functions serve market-data
```

Functions are served at `http://127.0.0.1:54321/functions/v1/<name>`. Smoke them with the **local anon key** from `supabase start`:

```bash
# market-data: expect the canonical JSON (see §12).
curl -s http://127.0.0.1:54321/functions/v1/market-data \
  -H "Authorization: Bearer <LOCAL_ANON_KEY>"
```

### 4.5 Local function secrets — `supabase/.env`

Edge Functions read secrets from `Deno.env`. Locally those come from **`supabase/.env`** (git-ignored), which the functions runtime loads automatically:

```bash
# supabase/.env  — LOCAL ONLY, never committed (.gitignore covers .env / .env.*)
COINGECKO_API_KEY=cg-demo-xxxxxxxxxxxxxxxx
```

Notes:

- `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and **`SUPABASE_SERVICE_ROLE_KEY`** are provided to the local functions runtime **automatically** — do not put them in `supabase/.env`. (The same automatic injection happens in production; [§8](#8-setting-production-secrets).)
- `COINGECKO_API_KEY` is **optional locally**: with no key the `market-data` function falls back to keyless provider calls, which is fine for development. It is **required in production** so the proxy is keyed and centrally cacheable.
- To pass an explicit env file to a one-off serve: `supabase functions serve --env-file supabase/.env`.
- Never commit `supabase/.env`. Commit an `supabase/.env.example` with placeholders instead (matches the `.env` hygiene rule in [`./07-security-and-privacy.md §5.3`](./07-security-and-privacy.md#53-env-hygiene-and-git)).

---

## 5. Linking a hosted project

Everything from here on targets a **hosted** Supabase project (one per environment — [§10](#10-environments-dev--staging--prod)). You link the repo to one project at a time.

### 5.1 Authenticate the CLI (once per machine)

```bash
supabase login            # opens a browser; pastes back an access token
# non-interactive (CI): export SUPABASE_ACCESS_TOKEN=<token> instead of `login`
```

### 5.2 Create the project (if it does not exist)

In the Supabase dashboard (or `supabase projects create`), create a project per environment in your org and note its **project ref** (the `abcd...` slug in the dashboard URL / `*.supabase.co` hostname).

### 5.3 Link

```bash
supabase link --project-ref <PROJECT_REF>
```

This prompts for the database password (set at project creation; store it in your password manager / CI secret, never in the repo) and writes the linkage into `supabase/config.toml` / `supabase/.temp`. After linking, `db push`, `functions deploy`, and `secrets set` all act on **that** project. Confirm what you are pointed at before any deploy:

```bash
supabase projects list        # the linked project is marked
```

> **Re-link to switch environments.** There is one active link at a time. To deploy to a different environment, run `supabase link --project-ref <OTHER_REF>` again. The `deploy-backend.sh` script refuses to run if no project is linked ([§13](#13-rollback--forward-fix), [§15](#15-helper-script-reference)) so you never accidentally push to the wrong place.

---

## 6. Applying the schema (`db push`)

```bash
supabase db push
```

`db push` compares `supabase/migrations/` against the linked project's `schema_migrations` ledger and applies **only the migrations not yet applied**, in order. It is the hosted counterpart to local `db reset` — but **non-destructive**: it never drops the database, it only forward-applies new migrations. This is exactly the **forward-only** policy in [`./07-security-and-privacy.md §13.2`](./07-security-and-privacy.md#132-forward-only-migrations-with-a-tested-rollbackforward-fix-policy): a regression is fixed by a **new** migration, never a destructive in-place edit.

- Preview first: `supabase db push --dry-run` prints which migrations would run without applying them.
- On a brand-new project this applies the entire initial set (`20260628000100` … `20260628000900`), giving you all tables, RLS (enabled + forced), triggers, the price-history audit trigger, and the four RPCs in one shot.
- **Do not** run `supabase/seed.sql` against production. Seeding is per-user via the `handle_new_user()` trigger; `seed.sql` is a *local* convenience only. The single intentional exception is the App Review demo account ([§12](#12-smoke-test-checklist) / [`./07-security-and-privacy.md §9.2`](./07-security-and-privacy.md)), which is provisioned by signing the demo user up through the app, not by a SQL seed.

---

## 7. Deploying the Edge Functions

Finmate ships **exactly two** functions ([`./05-data-model.md §7.3`](./05-data-model.md)). Deploy each by name:

```bash
supabase functions deploy market-data
supabase functions deploy delete-account
```

Both share `supabase/functions/_shared/cors.ts`; the CLI bundles shared modules automatically. Notes:

- **`delete-account` must verify its own JWT.** It is deployed with default JWT verification semantics and additionally re-verifies the caller via a per-request client (`auth.getUser()`), discarding any body-supplied id — the full spec is in [`./07-security-and-privacy.md §9.3`](./07-security-and-privacy.md). Do **not** deploy it with `--no-verify-jwt`.
- **`market-data`** is called by authenticated clients; keep JWT verification on so anonymous callers cannot burn your provider quota.
- Type-check before deploying (the deploy script does this if Deno is installed): `deno check supabase/functions/market-data/index.ts supabase/functions/delete-account/index.ts`.
- Redeploys are zero-downtime and versioned by the platform; you can roll a function back from the dashboard if a deploy regresses ([§13](#13-rollback--forward-fix)).

---

## 8. Setting production secrets

Function secrets live **only** in the Edge Function environment, never in the app bundle (the canonical secrets rule, [`./07-security-and-privacy.md §5`](./07-security-and-privacy.md#5-secrets-management)).

```bash
# The one secret you must set for production:
supabase secrets set COINGECKO_API_KEY=cg-pro-xxxxxxxxxxxxxxxx

# Inspect what is set (values are masked):
supabase secrets list
```

### What is and is NOT a secret you set

| Variable | Who sets it | Where it lives |
|---|---|---|
| `COINGECKO_API_KEY` | **You**, via `supabase secrets set` (or `deploy-backend.sh` from the env). | Edge Function env (prod), `supabase/.env` (local). |
| `SUPABASE_SERVICE_ROLE_KEY` | **Nobody** — **provided to functions automatically** by the platform. | Injected into the function runtime; read by `delete-account` from `Deno.env`. **Never** put it in `secrets set`, the repo, or the app. |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | Provided automatically too. | Injected into the function runtime. |

> **Set secrets, then (re)deploy.** Secrets are read at function invocation, but deploy after setting them so the running version is the one you intend. The `deploy-backend.sh` script sets `COINGECKO_API_KEY` from the environment *before* deploying for exactly this reason.

If you ever need to rotate `COINGECKO_API_KEY`: `supabase secrets set COINGECKO_API_KEY=<new>` then redeploy `market-data`. **No iOS release is required** — the key never lived in the client (rotation posture, [`./07-security-and-privacy.md §5.4`](./07-security-and-privacy.md#54-secret-rotation)).

---

## 9. Enabling Auth providers (email + Sign in with Apple)

Finmate uses Supabase Auth with **two** sign-in methods ([`./07-security-and-privacy.md §3.1`](./07-security-and-privacy.md#31-identity-providers)): email/password and Sign in with Apple. These are configured in the **Auth → Providers** dashboard (not via migrations), per hosted project.

### 9.1 Email / password

- Dashboard → **Authentication → Providers → Email**: enable it; keep **Confirm email** on (Supabase email confirmation, per §3.1).
- Set the **Site URL** and any **Redirect URLs** the app uses for confirmation/magic-link callbacks.

### 9.2 Sign in with Apple

Sign in with Apple needs credentials from your **Apple Developer** account; they go into the Supabase **Apple provider** config (server-side), never into the app bundle.

1. **Apple Developer portal:**
   - An **App ID** with the *Sign in with Apple* capability (your app's bundle id).
   - A **Services ID** (the OAuth `client_id` Supabase uses), configured with the Supabase callback `https://<PROJECT_REF>.supabase.co/auth/v1/callback` as a Return URL.
   - A **Sign in with Apple key** (`AuthKey_XXXXXXXXXX.p8`) — download it once. Note the **Key ID** and your **Team ID**.
2. **Supabase dashboard → Authentication → Providers → Apple:** enable it and supply:
   - **Services ID** (client id),
   - **Team ID**,
   - **Key ID**,
   - the **`.p8` private key** contents (Supabase derives the client secret from these — you do not paste a long-lived secret).
3. **Where the Apple keys go:** the `.p8`, Key ID, and Team ID live **only** in the Supabase Apple-provider config (and your CI/secret vault for safekeeping) — they are server-side credentials and match the "never ship secrets in the client" rule. The `AuthKey_*.p8` pattern is covered by the Gitleaks custom rules ([`./07-security-and-privacy.md §5.3`](./07-security-and-privacy.md#53-env-hygiene-and-git)) so it can never be committed.
4. On the **client**, the iOS app performs the native `ASAuthorizationController` flow and hands Apple's identity token (+ raw nonce) to `supabase.auth.signInWithIdToken(...)` — no Apple secret is needed in the app for this.

> **App Review parity (Guideline 4.8):** keep the email/password path enabled alongside Apple so a reviewer is never *forced* through Apple ([`./07-security-and-privacy.md §9.2`](./07-security-and-privacy.md)).

---

## 10. Environments (dev / staging / prod)

Run **separate Supabase projects per environment** — never share one project across dev and prod. Each project has its own URL, anon key, data, secrets, and Auth-provider config.

| Environment | Plan | Purpose | iOS build config |
|---|---|---|---|
| **Local** | n/a (Docker) | Day-to-day dev; disposable; `db reset` freely. | Debug, pointing at `http://127.0.0.1:54321` + local anon key. |
| **Dev / Staging** | **Free** acceptable | Shared integration, TestFlight betas, App Review demo account. | Beta/TestFlight xcconfig → staging URL + anon key. |
| **Production** | **Pro** (non-negotiable) | Real users. Pro removes the 7-day auto-pause and unlocks backups + PITR ([`./04-tech-stack.md §17.1`](./04-tech-stack.md#171-operating-cost--scaling)). | Release xcconfig → prod URL + anon key. |

### Per-environment anon URLs feed the iOS xcconfig

The two non-secret values for each environment — **project URL** and **anon key** — are injected into the iOS app at build time via per-configuration **xcconfig** files (the mechanism in [`./07-security-and-privacy.md §5.1–5.2`](./07-security-and-privacy.md#51-what-may-ship-in-the-client), and the cut-over target in the restore runbook §13.3). These are the **only** secrets that ship in the client; the anon key is public-by-design and gated entirely by RLS.

```text
Config/Secrets.Debug.xcconfig      SUPABASE_URL = http://127.0.0.1:54321   SUPABASE_ANON_KEY = <local anon>
Config/Secrets.Beta.xcconfig       SUPABASE_URL = https://<staging-ref>.supabase.co   SUPABASE_ANON_KEY = <staging anon>
Config/Secrets.Release.xcconfig    SUPABASE_URL = https://<prod-ref>.supabase.co      SUPABASE_ANON_KEY = <prod anon>
```

The real-keyed xcconfig files are git-ignored; only an `*.xcconfig.example` is committed (same hygiene as `.env`). Service-role and provider keys never appear in any xcconfig — they live in Edge Function env ([§8](#8-setting-production-secrets)).

### Deploying to each environment

Re-link, then deploy:

```bash
supabase link --project-ref <staging-ref> && ./scripts/deploy-backend.sh
supabase link --project-ref <prod-ref>    && ./scripts/deploy-backend.sh
```

Set each environment's `COINGECKO_API_KEY` separately (a staging key and a prod key are fine, or the same key — but set it per project, since secrets are per-project).

---

## 11. Backups & PITR on Pro

Production durability is a **plan + process** concern, fully specified in [`./07-security-and-privacy.md §13`](./07-security-and-privacy.md#13-backups--disaster-recovery). The deploy-time actions:

1. **Put the production project on Supabase Pro before any real traffic** (it is the launch baseline). Pro gives **daily automated backups** and **Point-in-Time Recovery (PITR)** with ≥ 7-day retention.
2. **Enable PITR** in the dashboard: **Project → Settings → Database → Point-in-Time Recovery** (toggle on; pick the retention window). Confirm the "Backups" section shows PITR active.
3. **Before any destructive production migration** (a `DROP`, a type change, a row-rewriting backfill, a `DELETE`), take a **fresh manual snapshot immediately beforehand** so PITR is anchored at a known-good point (`§13.2`). Tag destructive migrations as such in review.
4. Backups cover **all Postgres data + schema**; they do **not** cover Edge Function code/secrets (those live in the repo + CI vault) or the device-local SwiftData cache (a rebuildable cache, not a source of truth) — see `§13.4`.

Dev/staging may stay on Free (no PITR, auto-pause after 7 days idle) — only production *requires* Pro.

---

## 12. Smoke-test checklist

After a deploy (local or hosted), prove the perimeter holds before declaring success. These checks map directly to the security guarantees in [`./07-security-and-privacy.md`](./07-security-and-privacy.md).

### 12.1 RLS isolation — a second user reads zero rows (T6)

The single most important check: **anonymous and cross-user reads must return nothing.**

```bash
# (a) Anonymous read with only the anon key → ZERO rows (auth.uid() is NULL).
curl -s "$SUPABASE_URL/rest/v1/subscriptions?select=id" \
  -H "apikey: $ANON_KEY"
# Expect: []   (empty array — RLS filters every row when there is no session)
```

- [ ] **Anonymous** (anon key, no JWT) read of every user-table (`subscriptions`, `income_sources`, `fixed_expenses`, `variable_expenses`, `financial_assets`, `asset_transactions`, `subscription_price_history`, `categories`, `*_preferences`, `dashboard_layouts`) returns `[]`.
- [ ] **User A** signs up, creates a subscription; **User B** signs up and reads `subscriptions` → sees **only B's** rows (zero of A's). The decisive isolation test.
- [ ] Each table reports RLS **enabled and forced** (in Studio, or `SELECT relname, relrowsecurity, relforcerowsecurity FROM pg_class WHERE relrowsecurity;`).
- [ ] A fresh sign-up has the **18 subscription + 11 expense** seeded categories (`handle_new_user()` fired) — [`./05-data-model.md §7.2`](./05-data-model.md).

### 12.2 `market-data` returns the canonical JSON

```bash
curl -s "$SUPABASE_URL/functions/v1/market-data" \
  -H "Authorization: Bearer $ANON_KEY"
```

- [ ] Returns the **exact canonical shape** — all four keys present, `Decimal`-valued, ISO8601 `fetched_at` ([`./04-tech-stack.md §6.2`](./04-tech-stack.md#currency-and-conversion)):

  ```jsonc
  { "eur_usd": 1.0825, "btc_eur": 58234.50, "btc_usd": 63038.85, "fetched_at": "2026-06-28T09:14:32.512Z" }
  ```

- [ ] No provider key appears in the response body (secrets stay server-side).
- [ ] A call **without** a bearer token is rejected (JWT verification on).

### 12.3 `delete-account` rejects a foreign / missing id (T1)

```bash
# (a) No bearer token → 401, no service-role work happens.
curl -s -o /dev/null -w "%{http_code}\n" -X POST "$SUPABASE_URL/functions/v1/delete-account"
# Expect: 401

# (b) Valid JWT for user A, body claims user B's id → B is NOT deleted; only A could be.
curl -s -X POST "$SUPABASE_URL/functions/v1/delete-account" \
  -H "Authorization: Bearer $USER_A_JWT" \
  -H "Content-Type: application/json" \
  -d '{"user_id":"<USER_B_UUID>"}'
# Expect: the function ignores the body id; it can only ever delete the verified caller (A).
```

- [ ] Missing/blank/malformed `Authorization` → **401**, nothing deleted.
- [ ] A valid caller supplying **another user's id in the body** never deletes that other user — identity comes only from `auth.getUser()` ([`./07-security-and-privacy.md §9.3`](./07-security-and-privacy.md)).
- [ ] Deleting a real test user cascades: all of that user's rows vanish (`ON DELETE CASCADE`), confirmed by re-querying as an admin.

### 12.4 General

- [ ] All migrations applied (`supabase migration list` shows the linked project up to `20260628000900`).
- [ ] Both functions show **deployed** in the dashboard with the expected version.
- [ ] `supabase secrets list` shows `COINGECKO_API_KEY` set (prod).
- [ ] Auth providers: email **and** Apple both enabled.
- [ ] (Prod) PITR active; project on Pro.

---

## 13. Rollback & forward-fix

Finmate migrations are **forward-only** ([`./07-security-and-privacy.md §13.2`](./07-security-and-privacy.md#132-forward-only-migrations-with-a-tested-rollbackforward-fix-policy)). There is no speculative `down` migration against production.

**Schema regression → forward-fix:**

1. Write a **new** migration that corrects the problem (e.g. re-adds a constraint, fixes a function). Test it locally with `supabase db reset`, then in CI, then on staging.
2. `supabase db push` it to production. The fix is itself an auditable, reviewed migration.

**Function regression → redeploy previous version:**

- Edge Function deploys are versioned. Roll back from the dashboard (**Functions → version history**) or redeploy the last-good commit's function (`git checkout <good-sha> -- supabase/functions/<name> && supabase functions deploy <name>`).

**Data loss / a destructive migration that already ran → restore runbook:**

- This escalates beyond a forward-fix. Follow the **PITR-restore-to-a-fork → verify → cut-over** runbook in [`./07-security-and-privacy.md §13.3`](./07-security-and-privacy.md#133-restore-runbook): never restore destructively over the live project; restore to a fork at the last-good UTC timestamp, run the §12 smoke checks on the fork (RLS forced, seeds present, money fields still raw `Int64` minor units), then repoint the app's per-env xcconfig URL/keys to the verified fork during a brief maintenance window.

**Always**, before applying a destructive migration in prod, take the fresh pre-migration snapshot (§11.3) so PITR is anchored right before the change.

---

## 14. The four deferred owner placeholders

Four owner-supplied values are **intentionally deferred to the end of production** and **do not block any backend deploy**. The backend stands up, RLS protects data, functions run, and Auth works without them. They are App-Store / legal metadata, not backend infrastructure:

| # | Placeholder | Where it eventually goes | Why it does not block deploy |
|---|---|---|---|
| 1 | **Production domain / marketing URL** | App Store Connect metadata; Auth Site URL/redirects can use the `*.supabase.co` URL until then. | The backend works on the Supabase-provided hostname; a custom domain is cosmetic. |
| 2 | **Support email** | App Store Connect support URL; in-app Settings. | No backend dependency. |
| 3 | **Terms-of-Service jurisdiction** | The ToS / privacy-policy documents linked from App Store metadata ([`./07-security-and-privacy.md §9.2`](./07-security-and-privacy.md)). | Legal copy, finalized at submission. |
| 4 | **Scale thresholds** (exact MAU / invocation / connection numbers) | The scaling triggers in [`./04-tech-stack.md §17.1`](./04-tech-stack.md#171-operating-cost--scaling). | Defaults (Free dev, Pro prod, aggressive `market-data` caching) are sufficient at launch; exact numbers are tuned with real traffic. |

Record their resolution in the relevant doc when the owner supplies them; until then, deploy proceeds with the defaults above.

---

## 15. Helper-script reference

Both scripts are POSIX `sh`, `set -euo pipefail`, with clear `echo` step banners and guards for missing tools / env / linkage. They live in [`scripts/`](../scripts/) and are safe to re-run (idempotent where the underlying CLI is).

### `scripts/setup-backend.sh` — local stack

Brings up the local stack, applies every migration, and serves the functions:

1. **Preflight** — fails fast if `supabase` or `docker` is missing, or if `supabase/config.toml` / `supabase/migrations` are absent (run from repo root or any subdir; the script resolves the repo root).
2. `supabase start` — boots Postgres/Auth/Realtime/Storage/Functions (skips if already running).
3. `supabase db reset` — replays all migrations (+ `seed.sql` if present) against the fresh local DB.
4. Prints the local **API URL** and **anon key** (for the Debug xcconfig).
5. `supabase functions serve` — serves both functions with hot reload (foreground; Ctrl-C to stop).

```bash
./scripts/setup-backend.sh
```

### `scripts/deploy-backend.sh` — hosted deploy

Link-check → push schema → deploy both functions → set secrets from env:

1. **Preflight** — `supabase` present; a project is **linked** (refuses to run otherwise, so you never push to the wrong project); `COINGECKO_API_KEY` is set in the environment (guarded — the script aborts with a clear message if missing).
2. (If Deno is installed) `deno check` both function entrypoints.
3. `supabase db push` — forward-applies pending migrations (non-destructive).
4. `supabase secrets set COINGECKO_API_KEY=…` from the environment (notes that `SUPABASE_SERVICE_ROLE_KEY` is injected automatically and is **not** set here).
5. `supabase functions deploy market-data` and `supabase functions deploy delete-account` (JWT verification left **on** for both).
6. Prints the post-deploy smoke-test reminders from [§12](#12-smoke-test-checklist).

```bash
export COINGECKO_API_KEY=cg-pro-xxxxxxxxxxxx
supabase login                                  # once per machine
supabase link --project-ref <PROJECT_REF>       # pick the environment
./scripts/deploy-backend.sh
```

> The script does **not** enable Auth providers or PITR — those are one-time dashboard steps ([§9](#9-enabling-auth-providers-email--sign-in-with-apple), [§11](#11-backups--pitr-on-pro)) the CLI cannot perform.

---

## 16. Related documents

- [`../CLAUDE.md`](../CLAUDE.md) — Canonical Decisions Brief; the build/run/test command surface in §7 that this runbook operationalizes.
- [`./05-data-model.md`](./05-data-model.md) — the normative schema, migration set (§7.1), seeding (§7.2), and the two-function Edge inventory (§7.3) this runbook deploys.
- [`./07-security-and-privacy.md`](./07-security-and-privacy.md) — secrets management (§5), the `delete-account` and `market-data` specs (§5.2, §9.3), and backups/PITR + restore runbook (§13).
- [`./04-tech-stack.md`](./04-tech-stack.md) — the currency/`market-data` canonical JSON (§6.2) and the operating-cost / Free-vs-Pro / scaling posture (§17.1).
- [`./09-engineering-practices.md`](./09-engineering-practices.md) — the CI Database & RLS regression job that mirrors local `db reset`, and the Fastlane/TestFlight lanes.
- [`./03-architecture.md`](./03-architecture.md) — the offline-first sync contract the backend serves.
