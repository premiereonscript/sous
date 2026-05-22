// Service-role Supabase client. This is the only DB caller (SPEC §9.1 / §10.2);
// it bypasses RLS. SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY are auto-injected.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

export function dbClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );
}
