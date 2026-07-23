import type { User } from "@supabase/supabase-js";

import { isReservedEmailAddress } from "@/lib/email-address";
import { getRuntimeStatus } from "@/lib/runtime";
import { createSupabaseAdminClient, hasSupabaseAdminConfig } from "@/lib/supabase/admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const LEGACY_PERMISSION_KEYS = new Set(["pedidos.credit.limit.adjust"]);

export type AuthEmailStatus =
  | "confirmed"
  | "missing"
  | "not_applicable"
  | "pending_activation"
  | "pending_confirmation"
  | "placeholder";

export type SecurityProfile = {
  id: string;
  displayName: string;
  role: string;
  status: string;
  isSystemActor: boolean;
  systemActorKey: string | null;
  email: string | null;
  emailStatus: AuthEmailStatus;
  emailConfirmedAt: string | null;
  invitedAt: string | null;
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

export type SecurityEmailChangeRequest = {
  requestId: string;
  userId: string;
  displayName: string | null;
  status: "approved" | "completed" | "confirmation_pending" | "pending_admin" | "rejected";
  requestReasonCode: string;
  requestReasonDetail: string | null;
  newEmail: string | null;
  reviewReason: string | null;
  requestedAt: string;
  reviewedAt: string | null;
  confirmationRequestedAt: string | null;
  completedAt: string | null;
};

export type SecurityDashboard = {
  metrics: {
    totalProfiles: number | null;
    activeProfiles: number | null;
    confirmedEmails: number | null;
    pendingEmails: number | null;
    placeholderEmails: number | null;
    systemActors: number | null;
  };
  profiles: SecurityProfile[];
  selectedProfile: SecurityProfile | null;
  emailChangeRequests: SecurityEmailChangeRequest[];
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
    const authDirectory = profilesResult.error
      ? { users: [] as User[], error: null }
      : await listAllAuthUsers();
    const authUsersById = new Map(authDirectory.users.map((user) => [user.id, user]));
    const profiles = profilesResult.error
      ? []
      : ((profilesResult.data ?? []) as Array<Record<string, unknown>>).map((row) =>
          mapProfile(row, authUsersById.get(String(row.id)))
        );
    const selectedProfile =
      profiles.find((profile) => profile.id === selectedUserId) ??
      profiles.find((profile) => !profile.isSystemActor && profile.status === "active") ??
      profiles[0] ??
      null;

    const permissionsResult = selectedProfile
      ? await supabase.rpc("list_security_effective_permissions", { p_user_id: selectedProfile.id })
      : { data: [], error: null };
    const emailChangeResult = selectedProfile
      ? await supabase.rpc("list_security_email_change_requests", {
          p_include_closed: false,
          p_user_id: selectedProfile.id
        })
      : { data: [], error: null };

    const permissions = permissionsResult.error
      ? []
      : ((permissionsResult.data ?? []) as Array<Record<string, unknown>>)
          .map(mapPermission)
          .filter((permission) => !LEGACY_PERMISSION_KEYS.has(permission.actionKey));
    const emailChangeRequests = emailChangeResult.error
      ? []
      : ((emailChangeResult.data ?? []) as Array<Record<string, unknown>>).map(mapEmailChangeRequest);

    return {
      metrics: {
        totalProfiles: profiles.length,
        activeProfiles: profiles.filter((profile) => profile.status === "active").length,
        confirmedEmails: profiles.filter((profile) => profile.emailStatus === "confirmed").length,
        pendingEmails: profiles.filter((profile) =>
          profile.emailStatus === "pending_confirmation" || profile.emailStatus === "pending_activation"
        ).length,
        placeholderEmails: profiles.filter((profile) => profile.emailStatus === "placeholder").length,
        systemActors: profiles.filter((profile) => profile.isSystemActor).length
      },
      profiles,
      selectedProfile,
      emailChangeRequests,
      permissions,
      source: "supabase",
      error:
        profilesResult.error?.message ??
        authDirectory.error ??
        permissionsResult.error?.message ??
        emailChangeResult.error?.message ??
        null
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
      confirmedEmails: null,
      pendingEmails: null,
      placeholderEmails: null,
      systemActors: null,
    },
    profiles: [],
    selectedProfile: null,
    emailChangeRequests: [],
    permissions: [],
    source,
    error
  };
}

export async function getOwnEmailChangeRequest(): Promise<{
  request: SecurityEmailChangeRequest | null;
  error: string | null;
}> {
  if (!getRuntimeStatus().supabaseConfigured) {
    return { request: null, error: null };
  }

  try {
    const supabase = await createSupabaseServerClient();
    const result = await supabase.rpc("get_security_own_email_change_request");
    if (result.error) {
      return { request: null, error: result.error.message };
    }
    const row = ((result.data ?? []) as Array<Record<string, unknown>>)[0];
    return {
      request: row ? mapEmailChangeRequest(row) : null,
      error: null
    };
  } catch (error) {
    return { request: null, error: error instanceof Error ? error.message : "Erro desconhecido" };
  }
}

function mapProfile(row: Record<string, unknown>, authUser: User | undefined): SecurityProfile {
  const isSystemActor = Boolean(row.is_system_actor);
  return {
    id: String(row.id),
    displayName: String(row.display_name),
    role: String(row.role),
    status: String(row.status),
    isSystemActor,
    systemActorKey: row.system_actor_key === null ? null : String(row.system_actor_key),
    email: authUser?.email ?? null,
    emailStatus: authEmailStatus(authUser, isSystemActor),
    emailConfirmedAt: authUser?.email_confirmed_at ?? null,
    invitedAt: authUser?.invited_at ?? null,
    overridesCount: Number(row.overrides_count ?? 0),
    createdAt: String(row.created_at),
    updatedAt: String(row.updated_at)
  };
}

async function listAllAuthUsers(): Promise<{ users: User[]; error: string | null }> {
  if (!hasSupabaseAdminConfig()) {
    return { users: [], error: "Credenciais administrativas do Auth nao configuradas." };
  }

  const admin = createSupabaseAdminClient();
  const users: User[] = [];
  const perPage = 1000;

  for (let page = 1; page <= 100; page += 1) {
    const result = await admin.auth.admin.listUsers({ page, perPage });
    if (result.error) {
      return { users: [], error: result.error.message };
    }
    users.push(...result.data.users);
    if (result.data.users.length < perPage) {
      return { users, error: null };
    }
  }

  return { users: [], error: "Limite de leitura do diretorio Auth excedido." };
}

function authEmailStatus(authUser: User | undefined, isSystemActor: boolean): AuthEmailStatus {
  if (isSystemActor) {
    return "not_applicable";
  }
  if (!authUser) {
    return "missing";
  }
  const email = authUser.email?.toLowerCase() ?? "";
  if (!email) {
    return "missing";
  }
  if (isReservedEmailAddress(email)) {
    return "placeholder";
  }
  if (authUser.user_metadata?.invitation_pending === true) {
    return authUser.email_confirmed_at ? "pending_activation" : "pending_confirmation";
  }
  if (!authUser.email_confirmed_at) {
    return "pending_confirmation";
  }
  return "confirmed";
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

function mapEmailChangeRequest(row: Record<string, unknown>): SecurityEmailChangeRequest {
  return {
    requestId: String(row.request_id),
    userId: row.user_id === undefined ? "" : String(row.user_id),
    displayName: row.display_name === undefined || row.display_name === null ? null : String(row.display_name),
    status: String(row.status) as SecurityEmailChangeRequest["status"],
    requestReasonCode: String(row.request_reason_code),
    requestReasonDetail: nullableString(row.request_reason_detail),
    newEmail: nullableString(row.new_email),
    reviewReason: nullableString(row.review_reason),
    requestedAt: String(row.requested_at),
    reviewedAt: nullableString(row.reviewed_at),
    confirmationRequestedAt: nullableString(row.confirmation_requested_at),
    completedAt: nullableString(row.completed_at)
  };
}

function nullableString(value: unknown): string | null {
  return value === null || value === undefined ? null : String(value);
}
