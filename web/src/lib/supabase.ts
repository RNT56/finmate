// Supabase client. Only the PUBLIC anon key ships in the client (RLS gates every
// row by auth.uid()). The service-role key and provider secrets never ship — they
// live server-side in Edge Function environments (docs/07).
//
// The app builds and previews with sample data without a live backend: the client
// is created lazily and only when both env vars are present.

import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '../types/database';

const url = import.meta.env.VITE_SUPABASE_URL;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

/** True when a live Supabase backend is configured. Otherwise sample data is used. */
export const isSupabaseConfigured: boolean = Boolean(url && anonKey);

let client: SupabaseClient<Database> | null = null;

/**
 * Returns the configured Supabase client, or null when no backend is configured
 * (so the app still renders with sample data — no live backend needed to preview).
 */
export function getSupabase(): SupabaseClient<Database> | null {
  if (!isSupabaseConfigured) return null;
  if (!client) {
    client = createClient<Database>(url as string, anonKey as string, {
      auth: { persistSession: true, autoRefreshToken: true },
    });
  }
  return client;
}
