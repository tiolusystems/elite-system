import "server-only";

import { getRuntimeStatus } from "@/lib/runtime";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type PriceListAccess = {
  view: boolean;
  analyze: boolean;
  publish: boolean;
  any: boolean;
};

export type PriceListCatalogs = {
  produtos: Array<{ codigo: string; nome: string }>;
  apresentacoes: Array<{ codigo: string; produto_codigo: string; nome: string; volume_litros: number | null }>;
  unidades: Array<{ codigo: string; nome: string; simbolo: string }>;
  canais: Array<{ codigo: string; nome: string }>;
};

export type PriceListWorkspace = {
  listas: Array<{
    codigo: string;
    nome: string;
    descricao: string | null;
    versoes: Array<{
      numero: number;
      vigencia_inicio: string;
      vigencia_fim: string | null;
      situacao: "RASCUNHO" | "PUBLICADA" | "SUBSTITUIDA" | "RETIRADA";
      published_at: string | null;
      published_by: string | null;
    }>;
  }>;
  analises: Array<{
    id: number;
    codigo_lista: string;
    nome_lista: string;
    status: "ready" | "blocked";
    total_linhas: number;
    linhas_aviso: number;
    linhas_erro: number;
    created_at: string;
    publicacao_id: number | null;
    versao_id: number | null;
  }>;
  catalogos: PriceListCatalogs;
};

export type PriceListAnalysis = {
  id: number;
  lista_id: number | null;
  codigo_lista: string;
  nome_lista: string;
  nome_lista_canonico: string | null;
  avisos: string[];
  vigencia_inicio: string;
  vigencia_fim: string | null;
  uf: string | null;
  canal: string | null;
  observacao: string | null;
  status: "ready" | "blocked";
  total_linhas: number;
  linhas_aprovadas: number;
  linhas_aviso: number;
  linhas_erro: number;
  produtos_count: number;
  apresentacoes_count: number;
  faixas_count: number;
  canonical_payload_sha256: string;
  linhas: Array<{
    excel_row: number;
    codigo_produto: string | null;
    nome_produto_importado: string | null;
    nome_produto_canonico: string | null;
    codigo_apresentacao: string | null;
    nome_apresentacao_importado: string | null;
    nome_apresentacao_canonico: string | null;
    unidade_precificacao: string | null;
    fator_por_apresentacao: number | null;
    pmp_min_dias: number | null;
    pmp_max_dias: number | null;
    preco_unitario: number | null;
    preco_centavos_por_unidade: number | null;
    celulas: Record<string, string>;
    status: "APROVADA" | "AVISO" | "ERRO";
    avisos: string[];
    erros: string[];
    observacao: string | null;
  }>;
  publicacao: { versao_id: number; publicacao_id: number; published_at: string } | null;
};

const ACTIONS = {
  view: "pedidos.price_lists.view",
  analyze: "pedidos.price_lists.import.stage",
  publish: "pedidos.price_lists.publish",
} as const;

export async function getPriceListAccess(): Promise<PriceListAccess> {
  if (!getRuntimeStatus().supabaseConfigured) return { view: false, analyze: false, publish: false, any: false };
  try {
    const supabase = await createSupabaseServerClient();
    const entries = await Promise.all(Object.entries(ACTIONS).map(async ([key, action]) => {
      const { data, error } = await supabase.rpc("can_current_user", { p_action_key: action });
      return [key, !error && data === true] as const;
    }));
    const values = Object.fromEntries(entries) as Omit<PriceListAccess, "any">;
    return { ...values, any: values.view || values.analyze || values.publish };
  } catch {
    return { view: false, analyze: false, publish: false, any: false };
  }
}

export async function getPriceListWorkspace(): Promise<{ data: PriceListWorkspace | null; error: string | null }> {
  try {
    const supabase = await createSupabaseServerClient();
    const { data, error } = await supabase.rpc("consultar_com_listas_preco_workspace");
    return error ? { data: null, error: friendlyError(error.message) } : { data: data as PriceListWorkspace, error: null };
  } catch {
    return { data: null, error: "Nao foi possivel consultar as listas de precos." };
  }
}

export async function getPriceListAnalysis(id: number): Promise<{ data: PriceListAnalysis | null; error: string | null }> {
  if (!Number.isInteger(id) || id <= 0) return { data: null, error: "Analise invalida." };
  try {
    const supabase = await createSupabaseServerClient();
    const { data, error } = await supabase.rpc("consultar_com_lista_preco_xlsx_analise", { p_analise_id: id });
    return error ? { data: null, error: friendlyError(error.message) } : { data: data as PriceListAnalysis, error: null };
  } catch {
    return { data: null, error: "Nao foi possivel consultar a analise da planilha." };
  }
}

function friendlyError(message: string): string {
  const normalized = message.toLocaleLowerCase("pt-BR");
  if (normalized.includes("not allowed") || normalized.includes("permission")) return "Sua conta nao possui alcada para consultar listas de precos.";
  return "Nao foi possivel concluir a consulta de listas de precos.";
}
