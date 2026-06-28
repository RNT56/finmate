// supabase/functions/market-data/index.ts
//
// Finmate `market-data` Edge Function — server-side BTC spot + EUR/USD FX proxy.
//
// WHY THIS EXISTS (the whole point):
// ----------------------------------
// Substimate called CoinGecko and Frankfurter DIRECTLY FROM THE CLIENT
// (src/lib/marketData.ts). Finmate routes ALL market data through this Edge
// Function so that:
//   * any provider API key stays SERVER-SIDE in Deno.env and NEVER ships in the
//     iOS bundle (today these providers are keyless, but the architecture must
//     not leak a key the moment a paid/keyed provider is swapped in);
//   * responses are validated and centrally cached, so external providers are
//     not hammered once-per-user (rate-limit friendliness, see
//     ../../../docs/04-tech-stack.md §17.1);
//   * the canonical exchange-rate JSON shape is produced in exactly one place.
//
// CANONICAL RESPONSE (the ONLY shape any client/cache stores; see
// ../../../docs/04-tech-stack.md §6.2 "Currency & conversion" and
// ../../../docs/07-security-and-privacy.md §5.2):
//
//   {
//     "eur_usd":    number,   // USD per 1 EUR
//     "btc_eur":    number,   // EUR per 1 BTC
//     "btc_usd":    number,   // USD per 1 BTC
//     "fetched_at": string    // ISO8601 with fractional seconds + offset
//   }
//
// The rate data itself is not user-specific, but this function is deployed with
// `verify_jwt = true` (see supabase/config.toml): the Supabase gateway requires a
// valid JWT, so only authenticated app users can call it — this protects the
// upstream provider quota from anonymous abuse. Do NOT deploy with --no-verify-jwt.
// It is also rate-limit friendly: a single short-TTL in-memory cache fans one
// upstream fetch out to all callers.

import { corsHeaders, errorResponse, handlePreflight } from "../_shared/cors.ts";

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/** Short server-side cache TTL. Rates are global, not per-user, so one fetch
 *  serves every client until it expires (~60s; tech-stack §17.1). */
const CACHE_TTL_MS = 60_000;

/** Upstream request timeout — fail fast rather than hang a client. */
const UPSTREAM_TIMEOUT_MS = 8_000;

/**
 * Provider API key, if any, is read EXCLUSIVELY from the environment — never
 * hardcoded. CoinGecko's public endpoint is keyless today; if a Demo/Pro key is
 * configured it is sent as the documented header. The key never leaves this
 * function (it is not echoed in any response).
 */
const COINGECKO_API_KEY = Deno.env.get("COINGECKO_API_KEY") ?? "";

const COINGECKO_URL =
  "https://api.coingecko.com/api/v3/simple/price" +
  "?ids=bitcoin&vs_currencies=eur,usd";

const FRANKFURTER_URL = "https://api.frankfurter.app/latest?from=EUR&to=USD";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/** The canonical exchange-rate payload returned to clients. */
interface ExchangeRates {
  eur_usd: number;
  btc_eur: number;
  btc_usd: number;
  fetched_at: string;
}

interface CacheEntry {
  rates: ExchangeRates;
  storedAtMs: number;
}

// ---------------------------------------------------------------------------
// In-memory cache (per warm isolate)
// ---------------------------------------------------------------------------
//
// `lastKnown` is retained even after the TTL expires so that a transient
// upstream failure can serve the last good value rather than a hard error
// (graceful degradation; the client still sees `fetched_at` and applies its own
// 24h staleness rule per tech-stack §6.2).

let cache: CacheEntry | null = null;
let lastKnown: ExchangeRates | null = null;

function isFresh(entry: CacheEntry | null, nowMs: number): entry is CacheEntry {
  return entry !== null && nowMs - entry.storedAtMs < CACHE_TTL_MS;
}

// ---------------------------------------------------------------------------
// Upstream fetching
// ---------------------------------------------------------------------------

async function fetchJson(url: string): Promise<unknown> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), UPSTREAM_TIMEOUT_MS);
  try {
    const headers: Record<string, string> = { accept: "application/json" };
    // Provider key (if configured) is attached here, server-side only.
    if (COINGECKO_API_KEY && url.startsWith("https://api.coingecko.com")) {
      headers["x-cg-demo-api-key"] = COINGECKO_API_KEY;
    }
    const res = await fetch(url, { headers, signal: controller.signal });
    if (!res.ok) {
      throw new Error(`upstream ${res.status} for ${new URL(url).host}`);
    }
    return await res.json();
  } finally {
    clearTimeout(timer);
  }
}

/** A finite, strictly-positive number guard. */
function posNum(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) && value > 0
    ? value
    : null;
}

/**
 * Fetch BTC (EUR + USD) from CoinGecko and EUR/USD FX from Frankfurter in
 * parallel, validate, and assemble the canonical payload. Throws on any missing
 * or non-positive rate so the caller can fall back to last-known.
 */
async function fetchRates(): Promise<ExchangeRates> {
  const [btcRaw, fxRaw] = await Promise.all([
    fetchJson(COINGECKO_URL),
    fetchJson(FRANKFURTER_URL),
  ]);

  // CoinGecko: { "bitcoin": { "eur": <num>, "usd": <num> } }
  const btc = (btcRaw as { bitcoin?: { eur?: unknown; usd?: unknown } })
    ?.bitcoin;
  const btcEur = posNum(btc?.eur);
  const btcUsd = posNum(btc?.usd);

  // Frankfurter: { "rates": { "USD": <num> }, ... }
  const eurUsd = posNum(
    (fxRaw as { rates?: { USD?: unknown } })?.rates?.USD,
  );

  if (btcEur === null || btcUsd === null || eurUsd === null) {
    throw new Error("incomplete or invalid upstream rate data");
  }

  return {
    eur_usd: eurUsd,
    btc_eur: btcEur,
    btc_usd: btcUsd,
    fetched_at: new Date().toISOString(),
  };
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request): Promise<Response> => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;

  if (req.method !== "GET" && req.method !== "POST") {
    return errorResponse("Method not allowed", 405);
  }

  const nowMs = Date.now();

  // 1) Serve a fresh cached value without touching upstream (rate-limit friendly).
  if (isFresh(cache, nowMs)) {
    return new Response(JSON.stringify(cache.rates), {
      status: 200,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json; charset=utf-8",
        "Cache-Control": "public, max-age=60",
        "X-Cache": "HIT",
      },
    });
  }

  // 2) Cache miss/stale: fetch upstream, validate, refresh cache.
  try {
    const rates = await fetchRates();
    cache = { rates, storedAtMs: nowMs };
    lastKnown = rates;
    return new Response(JSON.stringify(rates), {
      status: 200,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json; charset=utf-8",
        "Cache-Control": "public, max-age=60",
        "X-Cache": "MISS",
      },
    });
  } catch (err) {
    // 3a) Upstream failed but we have a last-known good value → serve it.
    //     The client applies its own 24h staleness rule against `fetched_at`.
    if (lastKnown) {
      return new Response(JSON.stringify(lastKnown), {
        status: 200,
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json; charset=utf-8",
          "Cache-Control": "public, max-age=30",
          "X-Cache": "STALE",
          "Warning": '110 - "stale market data; upstream unavailable"',
        },
      });
    }
    // 3b) No cache at all → clear 5xx so the client shows source amounts
    //     unconverted (never guess a rate).
    console.error("market-data upstream failure (no cache):", err);
    return errorResponse(
      "Market data temporarily unavailable; no cached rates to serve.",
      502,
    );
  }
});
