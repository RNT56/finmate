// supabase/functions/_shared/cors.ts
//
// Shared CORS headers + small helpers for Finmate's Edge Functions.
//
// Finmate's iOS client calls these functions; a future web client (deferred,
// see ../../../CLAUDE.md) will call them from a browser, where CORS preflight
// is mandatory. Keeping the headers in one place guarantees `market-data` and
// `delete-account` answer preflight identically.
//
// SECURITY NOTE: these functions never carry secrets in their *responses*.
// Provider API keys and the Supabase service-role key live ONLY in the Edge
// Function environment (Deno.env) and never reach any client. See
// ../../../docs/07-security-and-privacy.md §5.2.

/**
 * Permissive CORS headers. The data perimeter is Postgres RLS + per-request JWT
 * verification (delete-account) — not the browser origin — so a wildcard origin
 * is safe here and keeps the future web client simple. Tighten `Access-Control-
 * Allow-Origin` to an allow-list if/when a fixed web origin is provisioned.
 */
export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
};

/** Standard JSON response content type. */
const JSON_CONTENT_TYPE = "application/json; charset=utf-8";

/**
 * Returns a CORS preflight response when `req` is an OPTIONS request, otherwise
 * `null`. Every handler should call this first and short-circuit on a non-null
 * result.
 */
export function handlePreflight(req: Request): Response | null {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 204, headers: corsHeaders });
  }
  return null;
}

/** Build a JSON response with CORS headers merged in. */
export function jsonResponse(
  body: unknown,
  status = 200,
  extraHeaders: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": JSON_CONTENT_TYPE,
      ...extraHeaders,
    },
  });
}

/** Build a JSON `{ error }` response with CORS headers. */
export function errorResponse(message: string, status: number): Response {
  return jsonResponse({ error: message }, status);
}
