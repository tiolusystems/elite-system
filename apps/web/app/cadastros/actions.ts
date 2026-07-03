"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { normalizeKey, normalizeUf } from "@/lib/normalization";
import { getRuntimeStatus } from "@/lib/runtime";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const ALLOWED_STATUS = new Set(["active", "inactive", "pending_review"]);
const ALLOWED_TIPO_COMERCIAL = new Set([
  "funcionario_elite",
  "agente_vinculado",
  "agente_direto_elite",
  "vendedor_direto_elite",
  "tecnico_campo",
  "entregador",
  "gerente",
  "vendedor_gerente"
]);
const ALLOWED_PAPEIS = new Set(["funcionario", "vendedor", "agente", "tecnico_campo", "entregador", "gerente", "comissionado"]);
const DECIMAL_SEPARATOR = /,/g;

export async function createClienteAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/cadastros?result=not_configured#novo-cadastro");
  }

  const nome = field(formData, "nome");
  const cidade = field(formData, "cidade");
  const uf = normalizeUf(field(formData, "uf"));
  const status = field(formData, "status") || "active";
  const codigoLegado = optionalField(formData, "codigo_legado");
  const apelidos = splitLines(optionalField(formData, "apelidos"));

  if (!nome || !cidade || !uf) {
    redirect("/cadastros?result=missing_required#novo-cadastro");
  }
  if (uf.length !== 2) {
    redirect("/cadastros?result=invalid_uf#novo-cadastro");
  }
  if (!ALLOWED_STATUS.has(status)) {
    redirect("/cadastros?result=invalid_status#novo-cadastro");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("create_cad_cliente", {
    p_apelidos_json: apelidos,
    p_cidade: cidade,
    p_codigo_legado: codigoLegado,
    p_nome: nome,
    p_nome_norm: normalizeKey(nome),
    p_payload_origem_json: {
      source: "apps/web/app/cadastros",
      form: "cliente"
    },
    p_status: status,
    p_uf: uf
  });

  if (error) {
    redirect(`/cadastros?result=${encodeURIComponent(mapSupabaseError(error.message))}#novo-cadastro`);
  }

  revalidatePath("/cadastros");
  redirect("/cadastros?result=cliente_created#novo-cadastro");
}

export async function createPessoaComercialAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/cadastros?result=not_configured#nova-pessoa");
  }

  const nome = field(formData, "nome");
  const status = field(formData, "status") || "active";
  const tipoComercial = optionalField(formData, "tipo_comercial");
  const codigoLegado = optionalField(formData, "codigo_legado");
  const vendedorResponsavelId = optionalField(formData, "vendedor_responsavel_id");
  const vendedorResponsavelIdNumber = vendedorResponsavelId ? Number(vendedorResponsavelId) : null;
  const apelidos = splitLines(optionalField(formData, "apelidos"));
  const grafiasIncorretas = splitLines(optionalField(formData, "grafias_incorretas"));
  const papeis = formData
    .getAll("papeis")
    .map((item) => String(item).trim())
    .filter((item) => ALLOWED_PAPEIS.has(item));

  if (!nome || papeis.length === 0) {
    redirect("/cadastros?result=missing_person_required#nova-pessoa");
  }
  if (!ALLOWED_STATUS.has(status)) {
    redirect("/cadastros?result=invalid_status#nova-pessoa");
  }
  if (tipoComercial && !ALLOWED_TIPO_COMERCIAL.has(tipoComercial)) {
    redirect("/cadastros?result=invalid_commercial_type#nova-pessoa");
  }
  if (tipoComercial === "agente_vinculado" && !vendedorResponsavelId) {
    redirect("/cadastros?result=missing_responsible_seller#nova-pessoa");
  }
  if (vendedorResponsavelIdNumber !== null && !Number.isInteger(vendedorResponsavelIdNumber)) {
    redirect("/cadastros?result=invalid_responsible_seller#nova-pessoa");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("create_cad_pessoa_comercial", {
    p_apelidos_json: apelidos,
    p_codigo_legado: codigoLegado,
    p_grafias_incorretas_json: grafiasIncorretas,
    p_nome: nome,
    p_nome_norm: normalizeKey(nome),
    p_papeis_json: papeis,
    p_payload_origem_json: {
      source: "apps/web/app/cadastros",
      form: "pessoa_comercial"
    },
    p_status: status,
    p_tipo_comercial: tipoComercial,
    p_vendedor_responsavel_id: vendedorResponsavelIdNumber
  });

  if (error) {
    redirect(`/cadastros?result=${encodeURIComponent(mapSupabaseError(error.message))}#nova-pessoa`);
  }

  revalidatePath("/cadastros");
  redirect("/cadastros?result=pessoa_created#nova-pessoa");
}

export async function createMateriaPrimaAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/cadastros?result=not_configured#nova-mp");
  }

  const nome = field(formData, "nome");
  const skuCorrigido = field(formData, "sku_corrigido");
  const unidadeBaseEstoque = field(formData, "unidade_base_estoque");
  const status = field(formData, "status") || "active";
  const densidade = optionalNumber(formData, "densidade");
  const estoqueMinimo = optionalNumber(formData, "estoque_minimo");

  if (!nome || !skuCorrigido || !unidadeBaseEstoque) {
    redirect("/cadastros?result=missing_mp_required#nova-mp");
  }
  if (!ALLOWED_STATUS.has(status)) {
    redirect("/cadastros?result=invalid_status#nova-mp");
  }
  if (densidade !== null && (!Number.isFinite(densidade) || densidade <= 0)) {
    redirect("/cadastros?result=invalid_positive_number#nova-mp");
  }
  if (estoqueMinimo !== null && (!Number.isFinite(estoqueMinimo) || estoqueMinimo < 0)) {
    redirect("/cadastros?result=invalid_non_negative_number#nova-mp");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("create_cad_materia_prima", {
    p_codigo_ads: optionalField(formData, "codigo_ads"),
    p_codigo_legado: optionalField(formData, "codigo_legado"),
    p_densidade: densidade,
    p_estoque_minimo: estoqueMinimo,
    p_ibama: optionalField(formData, "ibama"),
    p_ncm: optionalField(formData, "ncm"),
    p_nome: nome,
    p_nome_norm: normalizeKey(nome),
    p_payload_origem_json: {
      source: "apps/web/app/cadastros",
      form: "materia_prima"
    },
    p_sku_corrigido: skuCorrigido.toUpperCase(),
    p_status: status,
    p_tipo: optionalField(formData, "tipo"),
    p_unidade_base_estoque: unidadeBaseEstoque.toUpperCase()
  });

  if (error) {
    redirect(`/cadastros?result=${encodeURIComponent(mapSupabaseError(error.message))}#nova-mp`);
  }

  revalidatePath("/cadastros");
  redirect("/cadastros?result=mp_created#nova-mp");
}

export async function createProdutoBaseAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/cadastros?result=not_configured#novo-produto");
  }

  const codigoProduto = field(formData, "codigo_produto");
  const nome = field(formData, "nome");
  const status = field(formData, "status") || "active";
  const densidadeKgL = optionalNumber(formData, "densidade_kg_l");

  if (!codigoProduto || !nome) {
    redirect("/cadastros?result=missing_product_required#novo-produto");
  }
  if (!ALLOWED_STATUS.has(status)) {
    redirect("/cadastros?result=invalid_status#novo-produto");
  }
  if (densidadeKgL !== null && (!Number.isFinite(densidadeKgL) || densidadeKgL <= 0)) {
    redirect("/cadastros?result=invalid_positive_number#novo-produto");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("create_cad_produto_base", {
    p_ads: optionalField(formData, "ads"),
    p_codigo_produto: codigoProduto.toUpperCase(),
    p_densidade_kg_l: densidadeKgL,
    p_grupo: optionalField(formData, "grupo"),
    p_ibama: optionalField(formData, "ibama"),
    p_ncm: optionalField(formData, "ncm"),
    p_nome: nome,
    p_nome_norm: normalizeKey(nome),
    p_payload_origem_json: {
      source: "apps/web/app/cadastros",
      form: "produto_base"
    },
    p_reg_mapa: optionalField(formData, "reg_mapa"),
    p_status: status
  });

  if (error) {
    redirect(`/cadastros?result=${encodeURIComponent(mapSupabaseError(error.message))}#novo-produto`);
  }

  revalidatePath("/cadastros");
  redirect("/cadastros?result=produto_created#novo-produto");
}

export async function createEmbalagemAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/cadastros?result=not_configured#nova-embalagem");
  }

  const descricao = field(formData, "descricao");
  const unidade = field(formData, "unidade");
  const status = field(formData, "status") || "active";
  const volumeLitros = optionalNumber(formData, "volume_litros");
  const controlaEstoque = formData.get("controla_estoque") === "1";
  const materiaPrimaId = optionalInteger(formData, "materia_prima_id");

  if (!descricao || !unidade) {
    redirect("/cadastros?result=missing_package_required#nova-embalagem");
  }
  if (!ALLOWED_STATUS.has(status)) {
    redirect("/cadastros?result=invalid_status#nova-embalagem");
  }
  if (volumeLitros !== null && (!Number.isFinite(volumeLitros) || volumeLitros <= 0)) {
    redirect("/cadastros?result=invalid_positive_number#nova-embalagem");
  }
  if (materiaPrimaId !== null && (!Number.isInteger(materiaPrimaId) || materiaPrimaId <= 0)) {
    redirect("/cadastros?result=invalid_positive_number#nova-embalagem");
  }
  if (controlaEstoque && materiaPrimaId === null) {
    redirect("/cadastros?result=missing_package_stock_item#nova-embalagem");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("create_cad_embalagem", {
    p_codigo_legado: optionalField(formData, "codigo_legado"),
    p_controla_estoque: controlaEstoque,
    p_descricao: descricao,
    p_descricao_norm: normalizeKey(descricao),
    p_materia_prima_id: materiaPrimaId,
    p_payload_origem_json: {
      source: "apps/web/app/cadastros",
      form: "embalagem"
    },
    p_status: status,
    p_unidade: unidade.toUpperCase(),
    p_volume_litros: volumeLitros
  });

  if (error) {
    redirect(`/cadastros?result=${encodeURIComponent(mapSupabaseError(error.message))}#nova-embalagem`);
  }

  revalidatePath("/cadastros");
  redirect("/cadastros?result=embalagem_created#nova-embalagem");
}

export async function createProdutoEmbalagemAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/cadastros?result=not_configured#novo-item-vendavel");
  }

  const produtoId = optionalInteger(formData, "produto_id");
  const embalagemId = optionalInteger(formData, "embalagem_id");
  const codigoItem = field(formData, "codigo_item");
  const status = field(formData, "status") || "active";

  if (!produtoId || !embalagemId || !codigoItem) {
    redirect("/cadastros?result=missing_sale_item_required#novo-item-vendavel");
  }
  if (!Number.isInteger(produtoId) || produtoId <= 0 || !Number.isInteger(embalagemId) || embalagemId <= 0) {
    redirect("/cadastros?result=invalid_positive_number#novo-item-vendavel");
  }
  if (!ALLOWED_STATUS.has(status)) {
    redirect("/cadastros?result=invalid_status#novo-item-vendavel");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("create_cad_produto_embalagem", {
    p_codigo_item: codigoItem.toUpperCase(),
    p_embalagem_id: embalagemId,
    p_produto_id: produtoId,
    p_status: status
  });

  if (error) {
    redirect(`/cadastros?result=${encodeURIComponent(mapSupabaseError(error.message))}#novo-item-vendavel`);
  }

  revalidatePath("/cadastros");
  redirect("/cadastros?result=item_vendavel_created#novo-item-vendavel");
}

export async function createConversaoUnidadeMpAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/cadastros?result=not_configured#nova-conversao-mp");
  }

  const materiaPrimaId = optionalInteger(formData, "materia_prima_id");
  const unidadeOrigem = field(formData, "unidade_origem").toUpperCase();
  const unidadeDestino = field(formData, "unidade_destino").toUpperCase();
  const fator = optionalNumber(formData, "fator");
  const vigenciaInicio = optionalField(formData, "vigencia_inicio");
  const vigenciaFim = optionalField(formData, "vigencia_fim");

  if (!materiaPrimaId || !unidadeOrigem || !unidadeDestino || fator === null) {
    redirect("/cadastros?result=missing_conversion_required#nova-conversao-mp");
  }
  if (!Number.isInteger(materiaPrimaId) || materiaPrimaId <= 0) {
    redirect("/cadastros?result=invalid_positive_number#nova-conversao-mp");
  }
  if (!Number.isFinite(fator) || fator <= 0) {
    redirect("/cadastros?result=invalid_positive_number#nova-conversao-mp");
  }
  if (unidadeOrigem === unidadeDestino) {
    redirect("/cadastros?result=invalid_unit_conversion#nova-conversao-mp");
  }
  if (vigenciaInicio && vigenciaFim && vigenciaFim < vigenciaInicio) {
    redirect("/cadastros?result=invalid_date_range#nova-conversao-mp");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("create_cad_conversao_unidade_mp", {
    p_fator: fator,
    p_materia_prima_id: materiaPrimaId,
    p_unidade_destino: unidadeDestino,
    p_unidade_origem: unidadeOrigem,
    p_vigencia_fim: vigenciaFim,
    p_vigencia_inicio: vigenciaInicio
  });

  if (error) {
    redirect(`/cadastros?result=${encodeURIComponent(mapSupabaseError(error.message))}#nova-conversao-mp`);
  }

  revalidatePath("/cadastros");
  redirect("/cadastros?result=conversion_created#nova-conversao-mp");
}

function field(formData: FormData, name: string): string {
  return String(formData.get(name) ?? "").trim();
}

function optionalField(formData: FormData, name: string): string | null {
  const value = field(formData, name);
  return value || null;
}

function optionalNumber(formData: FormData, name: string): number | null {
  const value = optionalField(formData, name);
  if (value === null) {
    return null;
  }
  return Number(value.replace(DECIMAL_SEPARATOR, "."));
}

function optionalInteger(formData: FormData, name: string): number | null {
  const value = optionalField(formData, name);
  if (value === null) {
    return null;
  }
  const idPrefix = value.match(/^\s*(\d+)/);
  if (idPrefix) {
    return Number(idPrefix[1]);
  }
  return Number(value);
}

function splitLines(value: string | null): string[] {
  if (!value) {
    return [];
  }
  return uniqueStrings(value.split(/[,;\n]/).map((item) => item.trim()));
}

function uniqueStrings(values: string[]): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const value of values) {
    if (!value) {
      continue;
    }
    const key = normalizeKey(value);
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    result.push(value);
  }
  return result;
}

function mapSupabaseError(message: string): string {
  const normalized = message.toLowerCase();
  if (normalized.includes("duplicate") || normalized.includes("unique")) {
    return "duplicated";
  }
  if (normalized.includes("permission") || normalized.includes("row-level security")) {
    return "permission_denied";
  }
  return "save_failed";
}
