import { getRuntimeStatus } from "@/lib/runtime";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type SecurityProfile = {
  id: string;
  displayName: string;
  role: string;
  status: string;
  isSystemActor: boolean;
  systemActorKey: string | null;
  overridesCount: number;
  createdAt: string;
  updatedAt: string;
};

export type EffectivePermission = {
  actionKey: string;
  module: string;
  description: string;
  defaultAllowed: boolean;
  overrideAllowed: boolean | null;
  effectiveAllowed: boolean;
  sortOrder: number;
};

export type SecurityDashboard = {
  metrics: {
    totalProfiles: number | null;
    activeProfiles: number | null;
    systemActors: number | null;
    overrides: number | null;
  };
  profiles: SecurityProfile[];
  selectedProfile: SecurityProfile | null;
  permissions: EffectivePermission[];
  source: "supabase" | "not_configured" | "error";
  error: string | null;
};

export async function getSecurityDashboard(selectedUserId?: string | null): Promise<SecurityDashboard> {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    return emptyDashboard("not_configured", null);
  }

  try {
    const supabase = await createSupabaseServerClient();
    const profilesResult = await supabase.rpc("list_security_user_profiles");
    const profiles = profilesResult.error
      ? []
      : ((profilesResult.data ?? []) as Array<Record<string, unknown>>).map(mapProfile);
    const selectedProfile =
      profiles.find((profile) => profile.id === selectedUserId) ??
      profiles.find((profile) => !profile.isSystemActor && profile.status === "active") ??
      profiles[0] ??
      null;

    const permissionsResult = selectedProfile
      ? await supabase.rpc("list_security_effective_permissions", { p_user_id: selectedProfile.id })
      : { data: [], error: null };

    const permissions = permissionsResult.error
      ? []
      : ((permissionsResult.data ?? []) as Array<Record<string, unknown>>).map(mapPermission);

    return {
      metrics: {
        totalProfiles: profiles.length,
        activeProfiles: profiles.filter((profile) => profile.status === "active").length,
        systemActors: profiles.filter((profile) => profile.isSystemActor).length,
        overrides: profiles.reduce((sum, profile) => sum + profile.overridesCount, 0)
      },
      profiles,
      selectedProfile,
      permissions,
      source: "supabase",
      error: profilesResult.error?.message ?? permissionsResult.error?.message ?? null
    };
  } catch (error) {
    return emptyDashboard("error", error instanceof Error ? error.message : "Erro desconhecido");
  }
}

function emptyDashboard(source: "not_configured" | "error", error: string | null): SecurityDashboard {
  return {
    metrics: {
      totalProfiles: null,
      activeProfiles: null,
      systemActors: null,
      overrides: null
    },
    profiles: [],
    selectedProfile: null,
    permissions: [],
    source,
    error
  };
}

function mapProfile(row: Record<string, unknown>): SecurityProfile {
  return {
    id: String(row.id),
    displayName: String(row.display_name),
    role: String(row.role),
    status: String(row.status),
    isSystemActor: Boolean(row.is_system_actor),
    systemActorKey: row.system_actor_key === null ? null : String(row.system_actor_key),
    overridesCount: Number(row.overrides_count ?? 0),
    createdAt: String(row.created_at),
    updatedAt: String(row.updated_at)
  };
}

function mapPermission(row: Record<string, unknown>): EffectivePermission {
  return {
    actionKey: String(row.action_key),
    module: String(row.module),
    description: String(row.description),
    defaultAllowed: Boolean(row.default_allowed),
    overrideAllowed: row.override_allowed === null ? null : Boolean(row.override_allowed),
    effectiveAllowed: Boolean(row.effective_allowed),
    sortOrder: Number(row.sort_order ?? 0)
  };
}
