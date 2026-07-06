"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { getRuntimeStatus } from "@/lib/runtime";
import { auditedRpc } from "@/lib/supabase/rpc";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const ALLOWED_ROLES = new Set(["admin", "comercial", "producao", "estoque", "expedicao", "auditoria"]);
const ALLOWED_STATUS = new Set(["active", "inactive"]);
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function upsertSecurityUserProfileAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/seguranca?result=not_configured#perfil");
  }

  const userId = field(formData, "user_id");
  const displayName = field(formData, "display_name");
  const role = field(formData, "role") || "comercial";
  const status = field(formData, "status") || "active";

  if (!userId || !displayName) {
    redirect("/seguranca?result=missing_profile_required#perfil");
  }
  if (!UUID_PATTERN.test(userId)) {
    redirect("/seguranca?result=invalid_uuid#perfil");
  }
  if (!ALLOWED_ROLES.has(role)) {
    redirect("/seguranca?result=invalid_role#perfil");
  }
  if (!ALLOWED_STATUS.has(status)) {
    redirect("/seguranca?result=invalid_status#perfil");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "upsert_security_user_profile", {
    p_display_name: displayName,
    p_role: role,
    p_status: status,
    p_user_id: userId
  }, {
    metadata: {
      action_key: "security.manage_users",
      axis: "change_type",
      domain: "seguranca",
      entity: "user_profiles",
      entity_id: userId,
      failure_action: "seguranca.user_profile_upsert_failed"
    }
  });

  if (error) {
    redirect(`/seguranca?result=${encodeURIComponent(mapSecurityError(error.message))}#perfil`);
  }

  revalidatePath("/seguranca");
  redirect(`/seguranca?user_id=${encodeURIComponent(userId)}&result=profile_saved#perfil`);
}

export async function setSecurityPermissionOverrideAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/seguranca?result=not_configured#alcadas");
  }

  const userId = field(formData, "user_id");
  const actionKey = field(formData, "action_key");
  const allowedText = field(formData, "allowed");

  if (!userId || !actionKey || !allowedText) {
    redirect("/seguranca?result=missing_permission_required#alcadas");
  }
  if (!UUID_PATTERN.test(userId)) {
    redirect("/seguranca?result=invalid_uuid#alcadas");
  }
  if (allowedText !== "true" && allowedText !== "false") {
    redirect("/seguranca?result=invalid_permission_value#alcadas");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "set_security_permission_override", {
    p_action_key: actionKey,
    p_allowed: allowedText === "true",
    p_user_id: userId
  }, {
    metadata: {
      action_key: "security.manage_permissions",
      axis: "change_type",
      domain: "seguranca",
      entity: "user_permission_overrides",
      entity_id: `${userId}:${actionKey}`,
      failure_action: "seguranca.permission_override_set_failed"
    }
  });

  if (error) {
    redirect(`/seguranca?user_id=${encodeURIComponent(userId)}&result=${encodeURIComponent(mapSecurityError(error.message))}#alcadas`);
  }

  revalidatePath("/seguranca");
  redirect(`/seguranca?user_id=${encodeURIComponent(userId)}&result=permission_saved#alcadas`);
}

export async function clearSecurityPermissionOverrideAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/seguranca?result=not_configured#alcadas");
  }

  const userId = field(formData, "user_id");
  const actionKey = field(formData, "action_key");

  if (!userId || !actionKey) {
    redirect("/seguranca?result=missing_permission_required#alcadas");
  }
  if (!UUID_PATTERN.test(userId)) {
    redirect("/seguranca?result=invalid_uuid#alcadas");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "clear_security_permission_override", {
    p_action_key: actionKey,
    p_user_id: userId
  }, {
    metadata: {
      action_key: "security.manage_permissions",
      axis: "change_type",
      domain: "seguranca",
      entity: "user_permission_overrides",
      entity_id: `${userId}:${actionKey}`,
      failure_action: "seguranca.permission_override_clear_failed"
    }
  });

  if (error) {
    redirect(`/seguranca?user_id=${encodeURIComponent(userId)}&result=${encodeURIComponent(mapSecurityError(error.message))}#alcadas`);
  }

  revalidatePath("/seguranca");
  redirect(`/seguranca?user_id=${encodeURIComponent(userId)}&result=permission_cleared#alcadas`);
}

function field(formData: FormData, name: string): string {
  const value = formData.get(name);
  return typeof value === "string" ? value.trim() : "";
}

function mapSecurityError(message: string): string {
  const normalized = message.toLowerCase();
  if (normalized.includes("not allowed")) return "permission_denied";
  if (normalized.includes("auth user must exist")) return "auth_user_missing";
  if (normalized.includes("system actor")) return "system_actor_blocked";
  if (normalized.includes("permission action not found")) return "permission_action_not_found";
  if (normalized.includes("target user profile not found")) return "target_profile_not_found";
  if (normalized.includes("invalid user role")) return "invalid_role";
  if (normalized.includes("invalid user status")) return "invalid_status";
  return "security_error";
}
