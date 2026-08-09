import { createClient } from "@supabase/supabase-js";

export function hasSupabaseAdminConfig(): boolean {
  return Boolean(adminUrl() && adminServiceRoleKey());
}

export function createSupabaseAdminClient() {
  const url = adminUrl();
  const serviceRoleKey = adminServiceRoleKey();

  if (!url || !serviceRoleKey) {
    throw new Error("Supabase admin credentials are not configured");
  }

  return createClient(url, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false
    }
  });
}

function adminUrl(): string {
  return process.env.NEXT_PUBLIC_SUPABASE_URL?.trim() ?? "";
}

function adminServiceRoleKey(): string {
  return process.env.SUPABASE_SERVICE_ROLE_KEY?.trim() ?? "";
}
