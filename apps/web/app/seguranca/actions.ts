"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { applicationUrl } from "@/lib/application-url";
import { EMAIL_ADDRESS_PATTERN, isReservedEmailAddress } from "@/lib/email-address";
import { getRuntimeStatus } from "@/lib/runtime";
import { createSupabaseAdminClient, hasSupabaseAdminConfig } from "@/lib/supabase/admin";
import { auditedRpc } from "@/lib/supabase/rpc";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const ALLOWED_ROLES = new Set(["admin", "comercial", "producao", "estoque", "expedicao", "auditoria"]);
const ALLOWED_STATUS = new Set(["active", "inactive"]);
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type AuthProvisionAuthorization = {
  email_hash?: string;
  provision_mode?: string;
};

export async function inviteSecurityAuthUserAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/seguranca?result=not_configured#novo-acesso");
  }
  if (!hasSupabaseAdminConfig()) {
    redirect("/seguranca?result=service_role_missing#novo-acesso");
  }
  const email = field(formData, "email").toLowerCase();
  const displayName = field(formData, "display_name");
  const role = field(formData, "role") || "auditoria";
  const accessProfileId = field(formData, "access_profile_id");
  const pessoaId = field(formData, "pessoa_id");
  const status = "active";

  if (!email || !displayName) {
    redirect("/seguranca?result=missing_auth_user_required#novo-acesso");
  }
  if (!EMAIL_ADDRESS_PATTERN.test(email)) {
    redirect("/seguranca?result=invalid_email#novo-acesso");
  }
  if (!ALLOWED_ROLES.has(role)) {
    redirect("/seguranca?result=invalid_role#novo-acesso");
  }
  if (!/^[1-9]\d*$/.test(accessProfileId)) {
    redirect("/seguranca?result=access_profile_required#novo-acesso");
  }
  if (isReservedEmailAddress(email)) {
    redirect("/seguranca?result=fictitious_email#novo-acesso");
  }

  const supabase = await createSupabaseServerClient();
  const authorization = await auditedRpc<AuthProvisionAuthorization>(supabase, "authorize_security_auth_user_provision", {
    p_display_name: displayName,
    p_email: email,
    p_role: role,
    p_status: status
  }, {
    metadata: {
      action_key: "security.manage_users",
      axis: "change_type",
      domain: "seguranca",
      entity: "auth.users",
      failure_action: "seguranca.auth_user_invitation_authorization_failed"
    }
  });

  if (authorization.error) {
    redirect(`/seguranca?result=${encodeURIComponent(mapSecurityError(authorization.error.message))}#novo-acesso`);
  }

  const admin = createSupabaseAdminClient();
  const created = await admin.auth.admin.inviteUserByEmail(email, {
    data: {
      display_name: displayName,
      elite_role: role,
      invitation_pending: true
    },
    redirectTo: applicationUrl("/auth/confirm?flow=invite").toString()
  });

  if (created.error) {
    redirect(`/seguranca?result=${encodeURIComponent(mapSecurityError(created.error.message))}#novo-acesso`);
  }
  if (!created.data.user) {
    redirect("/seguranca?result=auth_user_create_failed#novo-acesso");
  }

  const userId = created.data.user.id;
  const profile = await auditedRpc(supabase, "upsert_security_user_profile", {
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

  if (profile.error) {
    await admin.auth.admin.deleteUser(userId);
    redirect(`/seguranca?result=${encodeURIComponent(mapSecurityError(profile.error.message))}#novo-acesso`);
  }

  const provisioned = await auditedRpc(supabase, "provision_security_human_identity", {
    p_user_id: userId,
    p_profile_id: Number(accessProfileId),
    p_pessoa_id: pessoaId ? Number(pessoaId) : null,
    p_display_name: displayName,
    p_reason: "Provisionamento de identidade e perfil no convite",
    p_correlation_id: `iam:invite:${userId}`
  }, {
    metadata: {
      action_key: "security.manage_permissions",
      axis: "change_type",
      domain: "seguranca",
      entity: "user_profiles",
      entity_id: userId,
      failure_action: "seguranca.human_identity_provisioning_failed"
    }
  });

  if (provisioned.error) {
    await admin.auth.admin.deleteUser(userId);
    redirect(`/seguranca?result=${encodeURIComponent(mapSecurityError(provisioned.error.message))}#novo-acesso`);
  }

  const sentLog = await auditedRpc(supabase, "record_security_auth_user_invitation_sent", {
    p_email: email,
    p_user_id: userId
  }, {
    metadata: {
      action_key: "security.manage_users",
      axis: "change_type",
      domain: "seguranca",
      entity: "auth.users",
      entity_id: userId,
      failure_action: "seguranca.auth_user_invitation_sent_log_failed"
    }
  });

  if (sentLog.error) {
    redirect(`/seguranca?user_id=${encodeURIComponent(userId)}&result=${encodeURIComponent(mapSecurityError(sentLog.error.message))}#perfil`);
  }

  revalidatePath("/seguranca");
  redirect(`/seguranca?user_id=${encodeURIComponent(userId)}&result=auth_invitation_sent#perfis`);
}

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

export async function linkSecurityUserCommercialPersonAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) {
    redirect("/seguranca?result=not_configured#vinculo-pessoa");
  }

  const userId = field(formData, "user_id");
  const pessoaId = field(formData, "pessoa_id");
  const motivo = field(formData, "motivo");

  if (!UUID_PATTERN.test(userId) || !/^[1-9]\d*$/.test(pessoaId) || motivo.length < 10) {
    redirect(`/seguranca?user_id=${encodeURIComponent(userId)}&result=missing_person_link_required#vinculo-pessoa`);
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "link_security_user_commercial_person", {
    p_motivo: motivo,
    p_pessoa_id: Number(pessoaId),
    p_user_id: userId
  }, {
    metadata: {
      action_key: "security.identity.person.link",
      axis: "change_type",
      domain: "seguranca",
      entity: "cad_pessoas_comerciais",
      entity_id: pessoaId,
      failure_action: "seguranca.conta_pessoa_vinculo_failed"
    }
  });

  if (error) {
    redirect(`/seguranca?user_id=${encodeURIComponent(userId)}&result=${encodeURIComponent(mapSecurityError(error.message))}#vinculo-pessoa`);
  }

  revalidatePath("/cadastros");
  revalidatePath("/pedidos");
  revalidatePath("/seguranca");
  redirect(`/seguranca?user_id=${encodeURIComponent(userId)}&result=person_linked#vinculo-pessoa`);
}

export async function assignSecurityAccessProfileAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) {
    redirect("/seguranca?result=not_configured#perfis");
  }
  const userId = field(formData, "user_id");
  const profileId = field(formData, "profile_id");
  const reason = field(formData, "reason");
  if (!UUID_PATTERN.test(userId) || !/^[1-9]\d*$/.test(profileId) || reason.length < 10) {
    redirect(`/seguranca?user_id=${encodeURIComponent(userId)}&result=access_profile_required#perfis`);
  }
  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "assign_security_access_profile", {
    p_user_id: userId,
    p_profile_id: Number(profileId),
    p_reason: reason,
    p_correlation_id: `iam:assign:${userId}:${profileId}`
  }, {
    metadata: {
      action_key: "security.manage_permissions",
      axis: "change_type",
      domain: "seguranca",
      entity: "security_user_access_profiles",
      entity_id: `${userId}:${profileId}`,
      failure_action: "seguranca.access_profile_assignment_failed"
    }
  });
  if (error) redirect(`/seguranca?user_id=${encodeURIComponent(userId)}&result=${encodeURIComponent(mapSecurityError(error.message))}#perfis`);
  revalidatePath("/seguranca");
  redirect(`/seguranca?user_id=${encodeURIComponent(userId)}&result=access_profile_assigned#perfis`);
}

export async function removeSecurityAccessProfileAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) {
    redirect("/seguranca?result=not_configured#perfis");
  }
  const userId = field(formData, "user_id");
  const profileId = field(formData, "profile_id");
  const reason = field(formData, "reason");
  if (!UUID_PATTERN.test(userId) || !/^[1-9]\d*$/.test(profileId) || reason.length < 10) {
    redirect(`/seguranca?user_id=${encodeURIComponent(userId)}&result=access_profile_required#perfis`);
  }
  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "remove_security_access_profile", {
    p_user_id: userId,
    p_profile_id: Number(profileId),
    p_reason: reason
  }, {
    metadata: {
      action_key: "security.manage_permissions",
      axis: "change_type",
      domain: "seguranca",
      entity: "security_user_access_profiles",
      entity_id: `${userId}:${profileId}`,
      failure_action: "seguranca.access_profile_removal_failed"
    }
  });
  if (error) redirect(`/seguranca?user_id=${encodeURIComponent(userId)}&result=${encodeURIComponent(mapSecurityError(error.message))}#perfis`);
  revalidatePath("/seguranca");
  redirect(`/seguranca?user_id=${encodeURIComponent(userId)}&result=access_profile_removed#perfis`);
}

export async function reviewSecurityEmailChangeAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/seguranca?result=not_configured#troca-email");
  }

  const requestId = field(formData, "request_id");
  const userId = field(formData, "user_id");
  const decision = field(formData, "decision");
  const newEmail = field(formData, "new_email").toLowerCase();
  const reviewReason = field(formData, "review_reason");

  if (!UUID_PATTERN.test(requestId) || !UUID_PATTERN.test(userId)) {
    redirect("/seguranca?result=invalid_uuid#troca-email");
  }
  if (decision !== "approve" && decision !== "reject") {
    redirect(`/seguranca?user_id=${encodeURIComponent(userId)}&result=invalid_email_review#troca-email`);
  }
  if (!reviewReason) {
    redirect(`/seguranca?user_id=${encodeURIComponent(userId)}&result=email_review_reason_required#troca-email`);
  }
  if (decision === "approve" && !EMAIL_ADDRESS_PATTERN.test(newEmail)) {
    redirect(`/seguranca?user_id=${encodeURIComponent(userId)}&result=invalid_email#troca-email`);
  }
  if (decision === "approve" && isReservedEmailAddress(newEmail)) {
    redirect(`/seguranca?user_id=${encodeURIComponent(userId)}&result=fictitious_email#troca-email`);
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "review_security_email_change_request", {
    p_decision: decision,
    p_new_email: decision === "approve" ? newEmail : null,
    p_request_id: requestId,
    p_review_reason: reviewReason
  }, {
    metadata: {
      action_key: "security.email_change.review",
      axis: "status_transition",
      domain: "seguranca",
      entity: "security_email_change_requests",
      entity_id: requestId,
      failure_action: "seguranca.email_change_review_failed"
    }
  });

  if (error) {
    redirect(
      `/seguranca?user_id=${encodeURIComponent(userId)}&result=${encodeURIComponent(mapSecurityError(error.message))}#troca-email`
    );
  }

  revalidatePath("/login");
  revalidatePath("/seguranca");
  const result = decision === "approve" ? "email_change_approved" : "email_change_rejected";
  redirect(`/seguranca?user_id=${encodeURIComponent(userId)}&result=${result}#troca-email`);
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
  if (normalized.includes("already been registered") || normalized.includes("already registered")) return "auth_user_exists";
  if (normalized.includes("invalid email")) return "invalid_email";
  if (normalized.includes("fictitious email")) return "fictitious_email";
  if (normalized.includes("auth user must exist")) return "auth_user_missing";
  if (normalized.includes("system actor")) return "system_actor_blocked";
  if (normalized.includes("permission action not found")) return "permission_action_not_found";
  if (normalized.includes("target user profile not found")) return "target_profile_not_found";
  if (normalized.includes("access profile")) return "access_profile_required";
  if (normalized.includes("invalid user role")) return "invalid_role";
  if (normalized.includes("invalid user status")) return "invalid_status";
  if (normalized.includes("system administrator role")) return "admin_role_required";
  if (normalized.includes("email change request not found")) return "email_change_request_not_found";
  if (normalized.includes("not pending administrator review")) return "email_change_request_not_pending";
  if (normalized.includes("email already belongs")) return "auth_user_exists";
  if (normalized.includes("matches current auth email")) return "email_unchanged";
  if (normalized.includes("reason must have")) return "missing_person_link_required";
  if (normalized.includes("already linked")) return "person_link_conflict";
  if (normalized.includes("commercial person is not active")) return "person_inactive";
  if (normalized.includes("commercial person not found")) return "person_not_found";
  return "security_error";
}
