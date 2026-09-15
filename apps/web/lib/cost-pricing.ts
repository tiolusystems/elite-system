import "server-only";

import { getRuntimeStatus } from "@/lib/runtime";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type PricingAccess = { view: boolean; policy: boolean; policyReview: boolean; scenario: boolean; calculate: boolean; calculationReview: boolean };
export type PricingWorkspace = {
  publication_enabled: boolean;
  apresentacoes: Array<{ id: number; codigo: string; produto: string; apresentacao: string }>;
  politicas: Array<{ id: number; codigo: string; nome: string; versoes: Array<{ id: number; versao: number; metodo: string; juros_mensais: number; documento_sha256: string; status: string; created_at: string }> }>;
  cenarios: Array<{ id: number; nome: string; produto_embalagem_id: number; politica_versao_id: number; motivo: string; created_at: string; componentes: Array<{ campo: string; valor: number; unidade: string; source_kind: string; source_reference: string; source_effective_date: string; reason: string }>; calculos: Array<{ id: number; metodo: string; preco_vista: number; cmv_percentual: number; contribuicao_liquida: number; result_sha256: string; status: string; calculated_at: string; prazos: Array<{ prazo_dias: number; preco: number }> }> }>;
};

const ACTIONS = {
  view: "precificacao.view", policy: "precificacao.policy.manage", policyReview: "precificacao.policy.review",
  scenario: "precificacao.scenario.manage", calculate: "precificacao.calculate", calculationReview: "precificacao.calculation.review",
} as const;

export async function getPricingAccess(): Promise<PricingAccess> {
  const denied = { view: false, policy: false, policyReview: false, scenario: false, calculate: false, calculationReview: false };
  if (!getRuntimeStatus().supabaseConfigured) return denied;
  try {
    const supabase = await createSupabaseServerClient();
    const entries = await Promise.all(Object.entries(ACTIONS).map(async ([key, action]) => {
      const { data, error } = await supabase.rpc("can_current_user", { p_action_key: action });
      return [key, !error && data === true] as const;
    }));
    return Object.fromEntries(entries) as PricingAccess;
  } catch { return denied; }
}

export async function getPricingWorkspace(): Promise<{ data: PricingWorkspace | null; error: string | null }> {
  try {
    const supabase = await createSupabaseServerClient();
    const { data, error } = await supabase.rpc("consultar_prc_workspace");
    if (error) return { data: null, error: friendly(error.message) };
    return { data: data as PricingWorkspace, error: null };
  } catch { return { data: null, error: "Nao foi possivel consultar a formacao de custos e precos." }; }
}

function friendly(message: string) {
  const value = message.toLocaleLowerCase("pt-BR");
  if (value.includes("not allowed") || value.includes("permission")) return "Sua conta nao possui alcada para esta consulta.";
  return "A memoria de custos e precos esta temporariamente indisponivel.";
}
