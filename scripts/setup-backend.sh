#!/usr/bin/env sh
#
# setup-backend.sh — bring up the LOCAL Finmate Supabase backend.
#
# Starts the local stack (Postgres + Auth + Realtime + Storage + Functions in
# Docker), re-applies EVERY migration in supabase/migrations/, prints the local
# API URL + anon key (for the Debug xcconfig), then serves the Edge Functions
# with hot reload in the foreground (Ctrl-C to stop).
#
# Idempotent: safe to re-run. `supabase start` is a no-op if already running;
# `supabase db reset` recreates the local DB from scratch each time.
#
# Reference: docs/15-deployment.md §4 (Local development).
# Schema/migrations: docs/05-data-model.md §7.1.   Secrets: docs/07 §5.

set -eu
# Enable pipefail when the shell supports it (bash/zsh/ksh); POSIX sh may not.
( set -o pipefail 2>/dev/null ) && set -o pipefail || true

# ---------------------------------------------------------------------------
# Resolve the repo root from this script's location, so it runs from anywhere.
# ---------------------------------------------------------------------------
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

step()  { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
info()  { printf '    %s\n' "$1"; }
fail()  { printf '\n\033[1;31mERROR:\033[0m %s\n' "$1" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. Preflight — required tools and expected repo layout.
# ---------------------------------------------------------------------------
step "Preflight: checking tools and repo layout"

command -v supabase >/dev/null 2>&1 || fail \
  "Supabase CLI not found. Install it: 'brew install supabase/tap/supabase' (see docs/15 §2)."
info "supabase: $(supabase --version 2>/dev/null | head -n1)"

command -v docker >/dev/null 2>&1 || fail \
  "Docker not found. The local stack needs Docker Desktop / a Docker runtime (see docs/15 §2)."
docker info >/dev/null 2>&1 || fail \
  "Docker is installed but not running. Start Docker Desktop and retry."
info "docker: running"

[ -f "$REPO_ROOT/supabase/config.toml" ] || fail \
  "Missing supabase/config.toml. Run 'supabase init' once at the repo root (see docs/15 §3)."
[ -d "$REPO_ROOT/supabase/migrations" ] || fail \
  "Missing supabase/migrations/. Nothing to apply (see docs/05 §7.1)."
info "repo root: $REPO_ROOT"

# All supabase commands run from the repo root.
cd "$REPO_ROOT"

if [ -f "$REPO_ROOT/supabase/.env" ]; then
  info "local function secrets: supabase/.env present (loaded automatically)"
else
  info "local function secrets: no supabase/.env (COINGECKO_API_KEY optional locally; docs/15 §4.5)"
fi

# ---------------------------------------------------------------------------
# 2. Start the local stack (no-op if already up).
# ---------------------------------------------------------------------------
step "Starting local Supabase stack (supabase start)"
info "First run pulls container images; subsequent runs are fast."
supabase start

# ---------------------------------------------------------------------------
# 3. Apply ALL migrations against a fresh local database.
# ---------------------------------------------------------------------------
step "Applying all migrations (supabase db reset)"
info "Drops + recreates the local DB and replays every migration + seed.sql (if any)."
supabase db reset

# ---------------------------------------------------------------------------
# 4. Show the local endpoints + keys (for the Debug xcconfig).
# ---------------------------------------------------------------------------
step "Local endpoints + keys (copy API URL + anon key into the Debug xcconfig — docs/15 §10)"
supabase status

# ---------------------------------------------------------------------------
# 5. Serve the Edge Functions (foreground, hot reload).
# ---------------------------------------------------------------------------
step "Serving Edge Functions (supabase functions serve) — Ctrl-C to stop"
info "Endpoints: http://127.0.0.1:54321/functions/v1/{market-data,delete-account}"
info "Smoke test (another terminal):"
info "  curl -s http://127.0.0.1:54321/functions/v1/market-data -H 'Authorization: Bearer <LOCAL_ANON_KEY>'"
info "See the full smoke-test checklist in docs/15 §12."

if [ -f "$REPO_ROOT/supabase/.env" ]; then
  exec supabase functions serve --env-file "$REPO_ROOT/supabase/.env"
else
  exec supabase functions serve
fi
