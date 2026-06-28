#!/usr/bin/env sh
#
# deploy-backend.sh — deploy the Finmate Supabase backend to a HOSTED project.
#
# Order: link-check -> (optional) type-check functions -> push schema (forward-only)
#        -> set production secrets from the environment -> deploy BOTH functions.
#
# Prerequisites (see docs/15-deployment.md §5 and §8):
#   supabase login                              # once per machine
#   supabase link --project-ref <PROJECT_REF>   # selects the target environment
#   export COINGECKO_API_KEY=<key>              # the one secret you must provide
#
# This script REFUSES to run if no project is linked, so you can never push to
# the wrong environment. It does NOT enable Auth providers or PITR — those are
# one-time dashboard steps (docs/15 §9, §11) the CLI cannot perform.
#
# Reference: docs/15 §6 (db push), §7 (deploy functions), §8 (secrets).
# Security:  docs/07 §5 (secrets), §9.3 (delete-account), §13 (forward-only).

set -eu
( set -o pipefail 2>/dev/null ) && set -o pipefail || true

# ---------------------------------------------------------------------------
# Resolve the repo root from this script's location, so it runs from anywhere.
# ---------------------------------------------------------------------------
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

step()  { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
info()  { printf '    %s\n' "$1"; }
warn()  { printf '\033[1;33m    WARN:\033[0m %s\n' "$1"; }
fail()  { printf '\n\033[1;31mERROR:\033[0m %s\n' "$1" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. Preflight — tools, repo layout, project linkage, required secret.
# ---------------------------------------------------------------------------
step "Preflight: tools, link status, and required env"

command -v supabase >/dev/null 2>&1 || fail \
  "Supabase CLI not found. Install it: 'brew install supabase/tap/supabase' (see docs/15 §2)."
info "supabase: $(supabase --version 2>/dev/null | head -n1)"

[ -f "$REPO_ROOT/supabase/config.toml" ] || fail \
  "Missing supabase/config.toml. Run 'supabase init' at the repo root (see docs/15 §3)."
[ -d "$REPO_ROOT/supabase/migrations" ] || fail "Missing supabase/migrations/ (see docs/05 §7.1)."
[ -d "$REPO_ROOT/supabase/functions/market-data" ]   || fail "Missing supabase/functions/market-data."
[ -d "$REPO_ROOT/supabase/functions/delete-account" ] || fail "Missing supabase/functions/delete-account."

cd "$REPO_ROOT"

# Linkage guard: a hosted project MUST be linked. `supabase migration list`
# only succeeds against a linked remote, so it doubles as the link check.
step "Verifying a hosted project is linked (guard against wrong-environment deploys)"
if ! supabase migration list >/dev/null 2>&1; then
  fail "No linked project (or not logged in). Run:
        supabase login
        supabase link --project-ref <PROJECT_REF>
      then re-run this script. (docs/15 §5)"
fi
info "linked project confirmed (see 'supabase projects list' for which one)."

# Required secret guard. ${VAR:-} keeps 'set -u' from aborting before we report.
if [ -z "${COINGECKO_API_KEY:-}" ]; then
  fail "COINGECKO_API_KEY is not set in the environment.
      Export it before deploying:  export COINGECKO_API_KEY=<your-coingecko-key>
      It is read server-side by the market-data function and never ships in the app
      (docs/07 §5.2). SUPABASE_SERVICE_ROLE_KEY is provided to functions automatically
      and must NOT be set here (docs/15 §8)."
fi
info "COINGECKO_API_KEY: set (value hidden)."

# ---------------------------------------------------------------------------
# 2. Optional: type-check the function entrypoints before deploying.
# ---------------------------------------------------------------------------
step "Type-checking Edge Functions (optional; requires Deno)"
if command -v deno >/dev/null 2>&1; then
  info "deno: $(deno --version 2>/dev/null | head -n1)"
  deno check \
    "$REPO_ROOT/supabase/functions/market-data/index.ts" \
    "$REPO_ROOT/supabase/functions/delete-account/index.ts" \
    || fail "deno check failed — fix type errors before deploying."
  info "type-check passed."
else
  warn "Deno not installed; skipping type-check. Install it to catch errors early (docs/15 §2)."
fi

# ---------------------------------------------------------------------------
# 3. Push the schema — forward-only, non-destructive (applies pending migrations).
# ---------------------------------------------------------------------------
step "Pushing schema (supabase db push) — forward-only; applies only pending migrations"
info "Preview anytime with: supabase db push --dry-run  (docs/15 §6)"
supabase db push

# ---------------------------------------------------------------------------
# 4. Set production secrets from the environment.
# ---------------------------------------------------------------------------
step "Setting production secrets (supabase secrets set)"
info "Only COINGECKO_API_KEY is set here; SUPABASE_SERVICE_ROLE_KEY is injected automatically (docs/15 §8)."
supabase secrets set "COINGECKO_API_KEY=${COINGECKO_API_KEY}"

# ---------------------------------------------------------------------------
# 5. Deploy BOTH Edge Functions (JWT verification left ON for both).
# ---------------------------------------------------------------------------
step "Deploying Edge Function: market-data"
info "JWT verification stays ON so anonymous callers cannot burn provider quota."
supabase functions deploy market-data

step "Deploying Edge Function: delete-account"
info "JWT verification stays ON — the function re-verifies the caller and ignores any body id (docs/07 §9.3)."
supabase functions deploy delete-account

# ---------------------------------------------------------------------------
# 6. Done — point at the post-deploy smoke tests.
# ---------------------------------------------------------------------------
step "Deploy complete"
info "Run the smoke-test checklist before declaring success (docs/15 §12):"
info "  1) Anonymous read of every user-table returns []  (RLS isolation, T6)."
info "  2) A second user reads ZERO of the first user's rows."
info "  3) market-data returns the canonical JSON { eur_usd, btc_eur, btc_usd, fetched_at }."
info "  4) delete-account: no bearer -> 401; a foreign body id never deletes that user (T1)."
info ""
info "Still TODO in the dashboard (CLI cannot do these):"
info "  - Enable Auth providers: Email + Sign in with Apple (docs/15 §9)."
info "  - Production only: ensure Pro plan + enable PITR (docs/15 §11)."
