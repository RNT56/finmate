// supabase/functions/delete-account/index.ts
//
// Finmate `delete-account` Edge Function — security-critical account deletion.
//
// This is the ONLY path to account deletion and satisfies App Store Review
// Guideline 5.1.1(v) (in-app account deletion). It is hardened exactly per
// ../../../docs/07-security-and-privacy.md §9.3 so the deleted identity can
// NEVER be attacker-chosen:
//
//   (1) Reject any request lacking a valid bearer JWT → 401, before any
//       service-role work happens.
//   (2) Verify the caller with a PER-REQUEST Supabase client built from the
//       caller's Authorization header; `auth.getUser()` validates the JWT
//       against Supabase Auth and yields the authenticated uid.
//   (3) IGNORE any body-supplied id — the body is never consulted for identity.
//       The only id used is the verified uid from step (2).
//   (4) Delete with a SERVICE-ROLE client, calling auth.admin.deleteUser(uid).
//       Every user-owned table FKs `user_id ... ON DELETE CASCADE`, so all
//       financial rows are removed transactionally with the auth.users row.
//
// SECRET HANDLING: SUPABASE_SERVICE_ROLE_KEY is read ONLY from the Edge
// Function environment (Deno.env). It bypasses RLS and must NEVER ship in the
// client bundle (../../../docs/07-security-and-privacy.md §5.2). It is used
// solely for the admin delete call below and is never echoed in any response.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { errorResponse, handlePreflight, jsonResponse } from "../_shared/cors.ts";

Deno.serve(async (req: Request): Promise<Response> => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;

  if (req.method !== "POST") {
    return errorResponse("Method not allowed", 405);
  }

  // Required env. Absence is a deployment/config error, not a client error.
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    console.error("delete-account misconfigured: missing required env vars");
    return errorResponse("Server misconfiguration", 500);
  }

  // (1) Require a bearer JWT — reject anything without one BEFORE any
  //     service-role work happens.
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return errorResponse("Missing bearer token", 401);
  }

  // (2) Per-request client bound to the CALLER's token; verify against
  //     Supabase Auth. This client carries no elevated privilege.
  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: { user }, error: authError } = await callerClient.auth.getUser();
  if (authError || !user) {
    return errorResponse("Invalid token", 401);
  }

  // (3) The ONLY id we trust. Any body-supplied id/user_id is intentionally
  //     never read — identity comes exclusively from the verified JWT.
  const verifiedUid = user.id;

  // (4) Service-role client used ONLY to delete the verified user. The
  //     ON DELETE CASCADE FKs remove all owned rows transactionally.
  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { error: deleteError } = await adminClient.auth.admin.deleteUser(
    verifiedUid,
  );
  if (deleteError) {
    console.error("delete-account deletion failed:", deleteError.message);
    return errorResponse("Deletion failed", 500);
  }

  return jsonResponse({ deleted: true }, 200);
});
