import { getRuntimeStatus } from "@/lib/runtime";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type ControlledProcedureVersion = {
  popId: number;
  versionId: number;
  code: string;
  title: string;
  purpose: string;
  revision: string;
  effectiveFrom: string;
  versionStatus: string;
  popStatus: string;
  documentReference: string;
  content: string;
  reason: string;
  supersedesId: number | null;
  createdAt: string;
  publishedAt: string | null;
  applicabilityCount: number;
};

export type ControlledProcedureApplicability = {
  versionId: number;
  stage: string;
  formulaVersionId: number | null;
  status: string;
  displayOrder: number;
  reason: string;
  createdAt: string;
};

export type ControlledProcedureCapabilities = {
  canCreateVersion: boolean;
  canPublish: boolean;
  canManageState: boolean;
  canManageApplicability: boolean;
  canRecordCq: boolean;
};

export type ControlledProcedureWorkbench = {
  versions: ControlledProcedureVersion[];
  applicabilities: ControlledProcedureApplicability[];
  capabilities: ControlledProcedureCapabilities;
  source: "supabase" | "not_configured" | "error";
  error: string | null;
};

export type OpControlledProcedure = {
  id: number;
  opId: number;
  versionId: number;
  stage: string;
  code: string;
  title: string;
  revision: string;
  effectiveFrom: string;
  displayOrder: number;
  cqResult: string | null;
  cqStage: string | null;
  cqObservation: string | null;
  correctiveAction: string | null;
  cqCreatedAt: string | null;
};

const CAPABILITY_KEYS = {
  canCreateVersion: "pcp.pop.version.create",
  canPublish: "pcp.pop.publish",
  canManageState: "pcp.pop.state.manage",
  canManageApplicability: "pcp.pop.applicability.manage",
  canRecordCq: "pcp.pop.cq.record"
} as const;

const EMPTY_CAPABILITIES: ControlledProcedureCapabilities = {
  canCreateVersion: false,
  canPublish: false,
  canManageState: false,
  canManageApplicability: false,
  canRecordCq: false
};

export async function getControlledProcedureWorkbench(): Promise<ControlledProcedureWorkbench> {
  if (!getRuntimeStatus().supabaseConfigured) {
    return {
      versions: [],
      applicabilities: [],
      capabilities: EMPTY_CAPABILITIES,
      source: "not_configured",
      error: null
    };
  }

  try {
    const supabase = await createSupabaseServerClient();
    const [catalogResponse, applicabilityResponse, capabilityEntries] = await Promise.all([
      supabase.rpc("list_pcp_pop_catalog"),
      supabase.rpc("list_pcp_pop_applicabilities"),
      Promise.all(
        Object.entries(CAPABILITY_KEYS).map(async ([capability, actionKey]) => {
          const { data, error } = await supabase.rpc("can_current_user", {
            p_action_key: actionKey
          });
          return [capability, !error && data === true] as const;
        })
      )
    ]);

    const firstError = catalogResponse.error?.message ?? applicabilityResponse.error?.message ?? null;
    if (firstError) {
      return {
        versions: [],
        applicabilities: [],
        capabilities: Object.fromEntries(capabilityEntries) as ControlledProcedureCapabilities,
        source: "error",
        error: firstError
      };
    }

    return {
      versions: ((catalogResponse.data ?? []) as Array<Record<string, unknown>>).map(mapVersion),
      applicabilities: ((applicabilityResponse.data ?? []) as Array<Record<string, unknown>>).map(mapApplicability),
      capabilities: Object.fromEntries(capabilityEntries) as ControlledProcedureCapabilities,
      source: "supabase",
      error: null
    };
  } catch (error) {
    return {
      versions: [],
      applicabilities: [],
      capabilities: EMPTY_CAPABILITIES,
      source: "error",
      error: error instanceof Error ? error.message : "Nao foi possivel carregar os POPs."
    };
  }
}

export async function getOpControlledProcedures(opId: number | null = null): Promise<OpControlledProcedure[]> {
  if (!getRuntimeStatus().supabaseConfigured || (opId !== null && (!Number.isInteger(opId) || opId <= 0))) {
    return [];
  }

  try {
    const supabase = await createSupabaseServerClient();
    const { data, error } = await supabase.rpc("list_pcp_op_pop_references", {
      p_op_id: opId
    });
    if (error) return [];
    return ((data ?? []) as Array<Record<string, unknown>>).map((row) => ({
      id: Number(row.id),
      opId: Number(row.op_id),
      versionId: Number(row.pop_versao_id),
      stage: String(row.etapa),
      code: String(row.codigo),
      title: String(row.titulo),
      revision: String(row.revisao),
      effectiveFrom: String(row.vigencia_inicio),
      displayOrder: Number(row.ordem_exibicao ?? 0),
      cqResult: nullableString(row.cq_resultado),
      cqStage: nullableString(row.cq_etapa_controle),
      cqObservation: nullableString(row.cq_observacao),
      correctiveAction: nullableString(row.cq_acao_corretiva),
      cqCreatedAt: nullableString(row.cq_created_at)
    }));
  } catch {
    return [];
  }
}

function mapVersion(row: Record<string, unknown>): ControlledProcedureVersion {
  return {
    popId: Number(row.pop_id),
    versionId: Number(row.pop_versao_id),
    code: String(row.codigo),
    title: String(row.titulo),
    purpose: String(row.finalidade),
    revision: String(row.revisao),
    effectiveFrom: String(row.vigencia_inicio),
    versionStatus: String(row.version_status),
    popStatus: String(row.pop_status),
    documentReference: String(row.referencia_documental),
    content: String(row.conteudo),
    reason: String(row.justificativa),
    supersedesId: nullableNumber(row.supersedes_id),
    createdAt: String(row.created_at),
    publishedAt: nullableString(row.published_at),
    applicabilityCount: Number(row.applicability_count ?? 0)
  };
}

function mapApplicability(row: Record<string, unknown>): ControlledProcedureApplicability {
  return {
    versionId: Number(row.pop_versao_id),
    stage: String(row.etapa),
    formulaVersionId: nullableNumber(row.formula_versao_id),
    status: String(row.status),
    displayOrder: Number(row.ordem_exibicao ?? 0),
    reason: String(row.motivo),
    createdAt: String(row.created_at)
  };
}

function nullableString(value: unknown): string | null {
  return value === null || value === undefined ? null : String(value);
}

function nullableNumber(value: unknown): number | null {
  return value === null || value === undefined ? null : Number(value);
}
