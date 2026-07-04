import { getRuntimeStatus } from "@/lib/runtime";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type AuthProfile = {
  id: string;
  displayName: string;
  role: string;
  status: string;
};

export type AuthStatus = {
  isConfigured: boolean;
  isAuthenticated: boolean;
  email: string | null;
  profile: AuthProfile | null;
  source: "supabase" | "not_configured" | "anonymous" | "error";
  error: string | null;
};

export async function getAuthStatus(): Promise<AuthStatus> {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    return {
      isConfigured: false,
      isAuthenticated: false,
      email: null,
      profile: null,
      source: "not_configured",
      error: null
    };
  }

  try {
    const supabase = await createSupabaseServerClient();
    const userResult = await supabase.auth.getUser();
    const user = userResult.data.user;

    if (userResult.error || !user) {
      return {
        isConfigured: true,
        isAuthenticated: false,
        email: null,
        profile: null,
        source: "anonymous",
        error: null
      };
    }

    const profileResult = await supabase
      .from("user_profiles")
      .select("id,display_name,role,status")
      .eq("id", user.id)
      .maybeSingle();

    return {
      isConfigured: true,
      isAuthenticated: true,
      email: user.email ?? null,
      profile: profileResult.data
        ? {
            id: String(profileResult.data.id),
            displayName: String(profileResult.data.display_name),
            role: String(profileResult.data.role),
            status: String(profileResult.data.status)
          }
        : null,
      source: profileResult.error ? "error" : "supabase",
      error: profileResult.error?.message ?? null
    };
  } catch (error) {
    return {
      isConfigured: true,
      isAuthenticated: false,
      email: null,
      profile: null,
      source: "error",
      error: error instanceof Error ? error.message : "Erro desconhecido"
    };
  }
}
