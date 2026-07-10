"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { getRuntimeStatus } from "@/lib/runtime";
import { auditedRpcCall } from "@/lib/supabase/rpc";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const ENVIRONMENTS = new Set(["unconfigured", "development", "test", "staging", "production"]);
const ROLLOUT_ENVIRONMENTS = new Set(["development", "test", "staging", "production"]);
const LIFECYCLES = new Set([
  "construction",
  "technical_validation",
  "business_validation",
  "pilot",
  "operational",
  "suspended"
]);
const ACCESS_MODES = new Set(["disabled", "read_only", "read_write"]);
const ENVIRONMENT_REASONS = new Set([
  "initial_configuration",
  "deployment_promotion",
  "rollback",
  "incident",
  "test_reset",
  "other"
]);
const ROLLOUT_REASONS = new Set([
  "technical_validation",
  "business_validation",
  "pilot_start",
  "production_release",
  "rollback",
  "incident",
  "dependency_change",
  "other"
]);

export async function setSystemRuntimeEnvironmentAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/modulos?result=not_configured#ambiente");
  }

  const environment = field(formData, "environment");
  const reasonCode = field(formData, "reason_code");
  const reasonDetail = field(formData, "reason_detail");

  if (!ENVIRONMENTS.has(environment) || !ENVIRONMENT_REASONS.has(reasonCode)) {
    redirect("/modulos?result=invalid_environment_change#ambiente");
  }
  if (reasonCode === "other" && !reasonDetail) {
    redirect("/modulos?result=reason_detail_required#ambiente");
  }

  const supabase = await createSupabaseServerClient();
  const call = auditedRpcCall<number>(supabase, {
    actionKey: "system.admin",
    axis: "change_type",
    domain: "sistema",
    entity: "sys_runtime_environment_events",
    functionName: "set_system_runtime_environment"
  });
  const { error } = await call.execute({
    p_environment: environment,
    p_reason_code: reasonCode,
    p_reason_detail: reasonDetail || null
  }, {
    metadata: {
      failure_action: "sistema.runtime_environment_change_failed",
      target_environment: environment
    }
  });

  if (error) {
    redirect(`/modulos?result=${encodeURIComponent(mapModuleRuntimeError(error.message))}#ambiente`);
  }

  revalidatePath("/");
  revalidatePath("/modulos");
  redirect(`/modulos?environment=${encodeURIComponent(environment)}&result=environment_changed#ambiente`);
}

export async function setSystemModuleRolloutAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/modulos?result=not_configured#catalogo");
  }

  const environment = field(formData, "environment");
  const moduleKey = field(formData, "module_key");
  const lifecycle = field(formData, "lifecycle");
  const accessMode = field(formData, "access_mode");
  const reasonCode = field(formData, "reason_code");
  const reasonDetail = field(formData, "reason_detail");

  if (
    !ROLLOUT_ENVIRONMENTS.has(environment) ||
    !moduleKey ||
    !LIFECYCLES.has(lifecycle) ||
    !ACCESS_MODES.has(accessMode) ||
    !ROLLOUT_REASONS.has(reasonCode)
  ) {
    redirect("/modulos?result=invalid_rollout_change#catalogo");
  }
  if (reasonCode === "other" && !reasonDetail) {
    redirect("/modulos?result=reason_detail_required#catalogo");
  }

  const supabase = await createSupabaseServerClient();
  const call = auditedRpcCall<number>(supabase, {
    actionKey: "system.admin",
    axis: "change_type",
    domain: "sistema",
    entity: "sys_module_rollout_events",
    functionName: "set_system_module_rollout"
  });
  const { error } = await call.execute({
    p_access_mode: accessMode,
    p_environment: environment,
    p_lifecycle: lifecycle,
    p_module_key: moduleKey,
    p_reason_code: reasonCode,
    p_reason_detail: reasonDetail || null
  }, {
    metadata: {
      entity_id: `${environment}:${moduleKey}`,
      failure_action: "sistema.module_rollout_change_failed",
      target_environment: environment,
      target_module: moduleKey
    }
  });

  if (error) {
    redirect(`/modulos?result=${encodeURIComponent(mapModuleRuntimeError(error.message))}#catalogo`);
  }

  revalidatePath("/");
  revalidatePath("/modulos");
  redirect(`/modulos?environment=${encodeURIComponent(environment)}&result=rollout_changed&module=${encodeURIComponent(moduleKey)}#catalogo`);
}

function field(formData: FormData, name: string): string {
  return String(formData.get(name) ?? "").trim();
}

function mapModuleRuntimeError(message: string): string {
  if (message.includes("not allowed:")) return "permission_denied";
  if (message.includes("module dependencies unavailable")) return "dependency_unavailable";
  if (message.includes("lifecycle does not allow")) return "lifecycle_not_allowed";
  if (message.includes("core module must remain")) return "core_protected";
  if (message.includes("target environment")) return "target_environment_unavailable";
  if (message.includes("module unavailable:")) return "module_unavailable";
  return "runtime_change_failed";
}
