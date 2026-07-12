import { getRuntimeStatus } from "@/lib/runtime";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { SYSTEM_MODULE_CATALOG } from "@/lib/system-map";

export type SystemEnvironment = "unconfigured" | "development" | "test" | "staging" | "production";
export type ModuleLifecycle =
  | "construction"
  | "technical_validation"
  | "business_validation"
  | "pilot"
  | "operational"
  | "suspended";
export type ModuleAccessMode = "disabled" | "read_only" | "read_write";

export type ModuleBlocker = {
  moduleKey: string;
  requiredAccess: ModuleAccessMode;
  configuredAccess: ModuleAccessMode | null;
  lifecycle: ModuleLifecycle | null;
  reason: string;
};

export type ModuleRuntime = {
  environment: SystemEnvironment;
  activeEnvironment: SystemEnvironment;
  moduleKey: string;
  displayName: string;
  description: string;
  ownerDomain: string;
  isCore: boolean;
  lifecycle: ModuleLifecycle | null;
  configuredAccess: ModuleAccessMode;
  effectiveAccess: ModuleAccessMode;
  available: boolean;
  reason: string;
  blockers: ModuleBlocker[];
  sortOrder: number;
};

export type ModuleRuntimeDashboard = {
  environment: SystemEnvironment;
  activeEnvironment: SystemEnvironment;
  modules: ModuleRuntime[];
  canManage: boolean;
  metrics: {
    total: number;
    available: number;
    readWrite: number;
    blocked: number;
  };
  source: "supabase" | "not_configured" | "error";
  error: string | null;
};

const FALLBACK_MODULES: Array<
  Pick<ModuleRuntime, "moduleKey" | "displayName" | "description" | "ownerDomain" | "isCore" | "sortOrder">
> = SYSTEM_MODULE_CATALOG.map((module) => ({
  moduleKey: module.moduleKey,
  displayName: module.displayName,
  description: module.description,
  ownerDomain: module.ownerDomain,
  isCore: module.isCore,
  sortOrder: module.sortOrder
}));

export async function getModuleRuntimeDashboard(viewEnvironment?: SystemEnvironment | null): Promise<ModuleRuntimeDashboard> {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    return fallbackDashboard("not_configured", null);
  }

  try {
    const supabase = await createSupabaseServerClient();
    const [modulesResult, permissionResult] = await Promise.all([
      supabase.rpc("list_system_module_runtime", { p_environment: viewEnvironment ?? null }),
      supabase.rpc("can_current_user", { p_action_key: "system.admin" })
    ]);

    if (modulesResult.error) {
      return fallbackDashboard("error", modulesResult.error.message);
    }

    const modules = ((modulesResult.data ?? []) as Array<Record<string, unknown>>).map(mapModuleRuntime);
    return buildDashboard(
      modules[0]?.environment ?? "unconfigured",
      modules[0]?.activeEnvironment ?? "unconfigured",
      modules,
      permissionResult.error ? false : Boolean(permissionResult.data),
      "supabase",
      permissionResult.error?.message ?? null
    );
  } catch (error) {
    return fallbackDashboard("error", error instanceof Error ? error.message : "Erro desconhecido");
  }
}

export function moduleRuntimeFor(dashboard: ModuleRuntimeDashboard, moduleKey: string): ModuleRuntime | null {
  return dashboard.modules.find((module) => module.moduleKey === moduleKey) ?? null;
}

function fallbackDashboard(source: "not_configured" | "error", error: string | null): ModuleRuntimeDashboard {
  const modules = FALLBACK_MODULES.map<ModuleRuntime>((module) => ({
    ...module,
    environment: "unconfigured",
    activeEnvironment: "unconfigured",
    lifecycle: null,
    configuredAccess: "disabled",
    effectiveAccess: "disabled",
    available: false,
    reason: source === "not_configured" ? "database_not_configured" : "runtime_contract_unavailable",
    blockers: []
  }));
  return buildDashboard("unconfigured", "unconfigured", modules, false, source, error);
}

function buildDashboard(
  environment: SystemEnvironment,
  activeEnvironment: SystemEnvironment,
  modules: ModuleRuntime[],
  canManage: boolean,
  source: ModuleRuntimeDashboard["source"],
  error: string | null
): ModuleRuntimeDashboard {
  return {
    environment,
    activeEnvironment,
    modules,
    canManage,
    metrics: {
      total: modules.length,
      available: modules.filter((module) => module.available).length,
      readWrite: modules.filter((module) => module.effectiveAccess === "read_write").length,
      blocked: modules.filter((module) => !module.available).length
    },
    source,
    error
  };
}

function mapModuleRuntime(row: Record<string, unknown>): ModuleRuntime {
  return {
    environment: asEnvironment(row.environment),
    activeEnvironment: asEnvironment(row.active_environment),
    moduleKey: String(row.module_key),
    displayName: String(row.display_name),
    description: String(row.description),
    ownerDomain: String(row.owner_domain),
    isCore: Boolean(row.is_core),
    lifecycle: row.lifecycle === null ? null : asLifecycle(row.lifecycle),
    configuredAccess: asAccessMode(row.configured_access),
    effectiveAccess: asAccessMode(row.effective_access),
    available: Boolean(row.available),
    reason: String(row.reason),
    blockers: Array.isArray(row.blockers)
      ? (row.blockers as Array<Record<string, unknown>>).map((blocker) => ({
          moduleKey: String(blocker.module_key),
          requiredAccess: asAccessMode(blocker.required_access),
          configuredAccess: blocker.configured_access === null ? null : asAccessMode(blocker.configured_access),
          lifecycle: blocker.lifecycle === null ? null : asLifecycle(blocker.lifecycle),
          reason: String(blocker.reason)
        }))
      : [],
    sortOrder: Number(row.sort_order ?? 0)
  };
}

function asEnvironment(value: unknown): SystemEnvironment {
  const text = String(value);
  return text === "development" || text === "test" || text === "staging" || text === "production"
    ? text
    : "unconfigured";
}

function asLifecycle(value: unknown): ModuleLifecycle {
  const text = String(value);
  if (
    text === "construction" ||
    text === "technical_validation" ||
    text === "business_validation" ||
    text === "pilot" ||
    text === "operational" ||
    text === "suspended"
  ) {
    return text;
  }
  return "construction";
}

function asAccessMode(value: unknown): ModuleAccessMode {
  const text = String(value);
  if (text === "read_only" || text === "read_write") {
    return text;
  }
  return "disabled";
}
