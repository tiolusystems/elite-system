"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { normalizeKey, normalizeUf } from "@/lib/normalization";
import { getRuntimeStatus } from "@/lib/runtime";
import { auditedRpc } from "@/lib/supabase/rpc";
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
const ALLOWED_PESSOA_ROLE_REASONS = new Set([
  "promocao",
  "correcao_cadastro",
  "transferencia_carteira",
  "desligamento_funcao",
  "mudanca_comissao",
  "outro"
]);
const DECIMAL_SEPARATOR = /,/g;
const ALLOWED_CADASTRO_RETURN_PATHS = new Set([
  "/cadastros/materias-primas",
  "/cadastros/unidades",
  "/cadastros/embalagens",
  "/cadastros/produtos"
]);

export async function createClienteAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/cadastros?grupo=clientes&modo=novo&result=not_configured#cadastro-cliente");
  }

  const nome = field(formData, "nome");
  const cidade = field(formData, "cidade");
  const uf = normalizeUf(field(formData, "uf"));
  const status = field(formData, "status") || "active";
  const codigoLegado = optionalField(formData, "codigo_legado");
  const apelidos = splitLines(optionalField(formData, "apelidos"));

  if (!nome || !cidade || !uf) {
    redirect("/cadastros?grupo=clientes&modo=novo&result=missing_required#cadastro-cliente");
  }
  if (uf.length !== 2) {
    redirect("/cadastros?grupo=clientes&modo=novo&result=invalid_uf#cadastro-cliente");
  }
  if (!ALLOWED_STATUS.has(status)) {
    redirect("/cadastros?grupo=clientes&modo=novo&result=invalid_status#cadastro-cliente");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "create_cad_cliente", {
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
    redirect(`/cadastros?grupo=clientes&modo=novo&result=${encodeURIComponent(mapSupabaseError(error.message))}#cadastro-cliente`);
  }

  revalidatePath("/cadastros");
  redirect("/cadastros?grupo=clientes&result=cliente_created");
}

export async function updateClienteAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/cadastros?grupo=clientes&result=not_configured");
  }

  const clienteId = optionalInteger(formData, "cliente_id");
  const nome = field(formData, "nome");
  const cidade = field(formData, "cidade");
  const uf = normalizeUf(field(formData, "uf"));
  const codigoLegado = optionalField(formData, "codigo_legado");
  const motivo = field(formData, "motivo");
  const apelidos = splitLines(optionalField(formData, "apelidos"));

  if (!clienteId || !nome || !cidade || !uf || !motivo) {
    redirect("/cadastros?grupo=clientes&result=missing_required");
  }
  if (!Number.isInteger(clienteId) || clienteId <= 0) {
    redirect("/cadastros?grupo=clientes&result=invalid_positive_number");
  }
  if (uf.length !== 2) {
    redirect(`/cadastros?grupo=clientes&cliente=${clienteId}&result=invalid_uf#cadastro-cliente`);
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "update_cad_cliente", {
    p_apelidos_json: apelidos,
    p_cidade: cidade,
    p_cliente_id: clienteId,
    p_codigo_legado: codigoLegado,
    p_motivo: motivo,
    p_nome: nome,
    p_nome_norm: normalizeKey(nome),
    p_uf: uf
  });

  if (error) {
    redirect(`/cadastros?grupo=clientes&cliente=${clienteId}&result=${encodeURIComponent(mapSupabaseError(error.message))}#cadastro-cliente`);
  }

  revalidatePath("/cadastros");
  redirect(`/cadastros?grupo=clientes&cliente=${clienteId}&result=cliente_updated#cadastro-cliente`);
}

export async function deactivateClienteAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/cadastros?grupo=clientes&result=not_configured");
  }

  const clienteId = optionalInteger(formData, "cliente_id");
  const motivo = field(formData, "motivo");

  if (!clienteId || !motivo) {
    redirect("/cadastros?grupo=clientes&result=missing_required");
  }
  if (!Number.isInteger(clienteId) || clienteId <= 0) {
    redirect("/cadastros?grupo=clientes&result=invalid_positive_number");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "deactivate_cad_cliente", {
    p_cliente_id: clienteId,
    p_motivo: motivo
  });

  if (error) {
    redirect(`/cadastros?grupo=clientes&cliente=${clienteId}&result=${encodeURIComponent(mapSupabaseError(error.message))}`);
  }

  revalidatePath("/cadastros");
  redirect(`/cadastros?grupo=clientes&cliente=${clienteId}&result=cliente_deactivated`);
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
  const { error } = await auditedRpc(supabase, "create_cad_pessoa_comercial", {
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

export async function updatePessoaComercialIdentityAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/cadastros?result=not_configured#nova-pessoa");
  }

  const pessoaId = optionalInteger(formData, "pessoa_id");
  const nome = field(formData, "nome");
  const codigoLegado = optionalField(formData, "codigo_legado");
  const apelidos = splitLines(optionalField(formData, "apelidos"));
  const grafiasIncorretas = splitLines(optionalField(formData, "grafias_incorretas"));
  const motivo = field(formData, "motivo");

  if (!pessoaId || !nome || !motivo) {
    redirect("/cadastros?result=missing_person_required#nova-pessoa");
  }
  if (!Number.isInteger(pessoaId) || pessoaId <= 0) {
    redirect("/cadastros?result=invalid_positive_number#nova-pessoa");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "update_cad_pessoa_comercial_identity", {
    p_apelidos_json: apelidos,
    p_codigo_legado: codigoLegado,
    p_grafias_incorretas_json: grafiasIncorretas,
    p_motivo: motivo,
    p_nome: nome,
    p_nome_norm: normalizeKey(nome),
    p_pessoa_id: pessoaId
  });

  if (error) {
    redirect(`/cadastros?result=${encodeURIComponent(mapSupabaseError(error.message))}#nova-pessoa`);
  }

  revalidatePath("/cadastros");
  redirect("/cadastros?result=pessoa_identity_updated#nova-pessoa");
}

export async function updatePessoaComercialRoleAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/cadastros?result=not_configured#nova-pessoa");
  }

  const pessoaId = optionalInteger(formData, "pessoa_id");
  const tipoComercial = optionalField(formData, "tipo_comercial");
  const vendedorResponsavelId = optionalField(formData, "vendedor_responsavel_id");
  const vendedorResponsavelIdNumber = vendedorResponsavelId ? Number(vendedorResponsavelId) : null;
  const motivoCodigo = field(formData, "motivo_codigo");
  const motivoDetalhe = optionalField(formData, "motivo_detalhe");
  const papeis = formData
    .getAll("papeis")
    .map((item) => String(item).trim())
    .filter((item) => ALLOWED_PAPEIS.has(item));

  if (!pessoaId || papeis.length === 0 || !motivoCodigo) {
    redirect("/cadastros?result=missing_person_required#nova-pessoa");
  }
  if (!Number.isInteger(pessoaId) || pessoaId <= 0) {
    redirect("/cadastros?result=invalid_positive_number#nova-pessoa");
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
  if (!ALLOWED_PESSOA_ROLE_REASONS.has(motivoCodigo)) {
    redirect("/cadastros?result=invalid_role_reason#nova-pessoa");
  }
  if (motivoCodigo === "outro" && !motivoDetalhe) {
    redirect("/cadastros?result=missing_role_reason_detail#nova-pessoa");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "update_cad_pessoa_comercial_role", {
    p_motivo_codigo: motivoCodigo,
    p_motivo_detalhe: motivoDetalhe,
    p_papeis_json: papeis,
    p_pessoa_id: pessoaId,
    p_tipo_comercial: tipoComercial,
    p_vendedor_responsavel_id: vendedorResponsavelIdNumber
  });

  if (error) {
    redirect(`/cadastros?result=${encodeURIComponent(mapSupabaseError(error.message))}#nova-pessoa`);
  }

  revalidatePath("/cadastros");
  redirect("/cadastros?result=pessoa_role_updated#nova-pessoa");
}

export async function deactivatePessoaComercialAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/cadastros?result=not_configured#nova-pessoa");
  }

  const pessoaId = optionalInteger(formData, "pessoa_id");
  const motivo = field(formData, "motivo");

  if (!pessoaId || !motivo) {
    redirect("/cadastros?result=missing_person_required#nova-pessoa");
  }
  if (!Number.isInteger(pessoaId) || pessoaId <= 0) {
    redirect("/cadastros?result=invalid_positive_number#nova-pessoa");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "deactivate_cad_pessoa_comercial", {
    p_motivo: motivo,
    p_pessoa_id: pessoaId
  });

  if (error) {
    redirect(`/cadastros?result=${encodeURIComponent(mapSupabaseError(error.message))}#nova-pessoa`);
  }

  revalidatePath("/cadastros");
  redirect("/cadastros?result=pessoa_deactivated#nova-pessoa");
}

export async function createMateriaPrimaAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirectCadastroAction(formData, "not_configured", "#nova-mp");
  }

  const nome = field(formData, "nome");
  const skuCorrigido = field(formData, "sku_corrigido");
  const unidadeBaseEstoque = field(formData, "unidade_base_estoque");
  const status = field(formData, "status") || "active";
  const densidade = optionalNumber(formData, "densidade");
  const estoqueMinimo = optionalNumber(formData, "estoque_minimo");

  if (!nome || !skuCorrigido || !unidadeBaseEstoque) {
    redirectCadastroAction(formData, "missing_mp_required", "#nova-mp");
  }
  if (!ALLOWED_STATUS.has(status)) {
    redirectCadastroAction(formData, "invalid_status", "#nova-mp");
  }
  if (densidade !== null && (!Number.isFinite(densidade) || densidade <= 0)) {
    redirectCadastroAction(formData, "invalid_positive_number", "#nova-mp");
  }
  if (estoqueMinimo !== null && (!Number.isFinite(estoqueMinimo) || estoqueMinimo < 0)) {
    redirectCadastroAction(formData, "invalid_non_negative_number", "#nova-mp");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "create_cad_materia_prima", {
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
    redirectCadastroAction(formData, mapSupabaseError(error.message), "#nova-mp");
  }

  revalidateTechnicalCatalogs();
  redirectCadastroAction(formData, "mp_created", "#nova-mp");
}

export async function updateMateriaPrimaIdentityAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirectCadastroAction(formData, "not_configured", "#editar");
  }

  const materiaPrimaId = optionalInteger(formData, "materia_prima_id");
  const nome = field(formData, "nome");

  const motivo = field(formData, "motivo");

  if (!materiaPrimaId || !nome || !motivo) {
    redirectCadastroAction(formData, "missing_mp_required", "#editar", materiaPrimaId);
  }
  if (!Number.isInteger(materiaPrimaId) || materiaPrimaId <= 0) {
    redirectCadastroAction(formData, "invalid_positive_number", "#editar", materiaPrimaId);
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "update_cad_materia_prima_identity", {
    p_materia_prima_id: materiaPrimaId,
    p_motivo: motivo,
    p_nome: nome,
    p_nome_norm: normalizeKey(nome),
    p_tipo: null
  });

  if (error) {
    redirectCadastroAction(formData, mapSupabaseError(error.message), "#editar", materiaPrimaId);
  }

  revalidateTechnicalCatalogs();
  redirectCadastroAction(formData, "mp_identity_updated", "#editar", materiaPrimaId);
}

export async function updateMateriaPrimaSkuAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirectCadastroAction(formData, "not_configured", "#editar");
  }

  const materiaPrimaId = optionalInteger(formData, "materia_prima_id");
  const skuCorrigido = field(formData, "sku_corrigido").toUpperCase();
  const codigoLegado = optionalField(formData, "codigo_legado");
  const motivo = field(formData, "motivo");

  if (!materiaPrimaId || !skuCorrigido || !motivo) {
    redirectCadastroAction(formData, "missing_mp_required", "#editar", materiaPrimaId);
  }
  if (!Number.isInteger(materiaPrimaId) || materiaPrimaId <= 0) {
    redirectCadastroAction(formData, "invalid_positive_number", "#editar", materiaPrimaId);
  }
  if (/\s/.test(skuCorrigido)) {
    redirectCadastroAction(formData, "invalid_sku", "#editar", materiaPrimaId);
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "update_cad_materia_prima_sku", {
    p_codigo_legado: codigoLegado,
    p_materia_prima_id: materiaPrimaId,
    p_motivo: motivo,
    p_sku_corrigido: skuCorrigido
  });

  if (error) {
    redirectCadastroAction(formData, mapSupabaseError(error.message), "#editar", materiaPrimaId);
  }

  revalidateTechnicalCatalogs();
  redirectCadastroAction(formData, "mp_sku_updated", "#editar", materiaPrimaId);
}

export async function updateMateriaPrimaTechnicalAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirectCadastroAction(formData, "not_configured", "#editar");
  }

  const materiaPrimaId = optionalInteger(formData, "materia_prima_id");
  const unidadeBaseEstoqueId = optionalInteger(formData, "unidade_base_estoque_id");
  const densidade = optionalNumber(formData, "densidade");
  const motivo = field(formData, "motivo");

  if (!materiaPrimaId || !unidadeBaseEstoqueId || !motivo) {
    redirectCadastroAction(formData, "missing_mp_required", "#editar", materiaPrimaId);
  }
  if (!Number.isInteger(materiaPrimaId) || materiaPrimaId <= 0) {
    redirectCadastroAction(formData, "invalid_positive_number", "#editar", materiaPrimaId);
  }
  if (densidade !== null && (!Number.isFinite(densidade) || densidade <= 0)) {
    redirectCadastroAction(formData, "invalid_positive_number", "#editar", materiaPrimaId);
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "update_cad_materia_prima_technical_governada", {
    p_densidade: densidade,
    p_materia_prima_id: materiaPrimaId,
    p_motivo: motivo,
    p_unidade_base_estoque_id: unidadeBaseEstoqueId
  });

  if (error) {
    redirectCadastroAction(formData, mapSupabaseError(error.message), "#editar", materiaPrimaId);
  }

  revalidateTechnicalCatalogs();
  redirectCadastroAction(formData, "mp_technical_updated", "#editar", materiaPrimaId);
}

export async function updateMateriaPrimaStockPolicyAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirectCadastroAction(formData, "not_configured", "#editar");
  }

  const materiaPrimaId = optionalInteger(formData, "materia_prima_id");
  const estoqueMinimo = optionalNumber(formData, "estoque_minimo");
  const motivo = field(formData, "motivo");

  if (!materiaPrimaId || estoqueMinimo === null || !motivo) {
    redirectCadastroAction(formData, "missing_mp_required", "#editar", materiaPrimaId);
  }
  if (!Number.isInteger(materiaPrimaId) || materiaPrimaId <= 0) {
    redirectCadastroAction(formData, "invalid_positive_number", "#editar", materiaPrimaId);
  }
  if (!Number.isFinite(estoqueMinimo) || estoqueMinimo < 0) {
    redirectCadastroAction(formData, "invalid_non_negative_number", "#editar", materiaPrimaId);
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "update_cad_materia_prima_stock_policy", {
    p_estoque_minimo: estoqueMinimo,
    p_materia_prima_id: materiaPrimaId,
    p_motivo: motivo
  });

  if (error) {
    redirectCadastroAction(formData, mapSupabaseError(error.message), "#editar", materiaPrimaId);
  }

  revalidateTechnicalCatalogs();
  redirectCadastroAction(formData, "mp_stock_policy_updated", "#editar", materiaPrimaId);
}

export async function updateMateriaPrimaRegulatoryAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirectCadastroAction(formData, "not_configured", "#editar");
  }

  const materiaPrimaId = optionalInteger(formData, "materia_prima_id");
  const ncm = optionalField(formData, "ncm");
  const ibama = optionalField(formData, "ibama");
  const codigoAds = optionalField(formData, "codigo_ads");
  const motivo = field(formData, "motivo");

  if (!materiaPrimaId || !motivo) {
    redirectCadastroAction(formData, "missing_mp_required", "#editar", materiaPrimaId);
  }
  if (!Number.isInteger(materiaPrimaId) || materiaPrimaId <= 0) {
    redirectCadastroAction(formData, "invalid_positive_number", "#editar", materiaPrimaId);
  }
  if (ncm && !/^\d{8}$/.test(onlyDigits(ncm))) {
    redirectCadastroAction(formData, "invalid_ncm", "#editar", materiaPrimaId);
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "update_cad_materia_prima_regulatory", {
    p_codigo_ads: codigoAds,
    p_ibama: ibama,
    p_materia_prima_id: materiaPrimaId,
    p_motivo: motivo,
    p_ncm: ncm
  });

  if (error) {
    redirectCadastroAction(formData, mapSupabaseError(error.message), "#editar", materiaPrimaId);
  }

  revalidateTechnicalCatalogs();
  redirectCadastroAction(formData, "mp_regulatory_updated", "#editar", materiaPrimaId);
}

export async function deactivateMateriaPrimaAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirectCadastroAction(formData, "not_configured", "#editar");
  }

  const materiaPrimaId = optionalInteger(formData, "materia_prima_id");
  const motivo = field(formData, "motivo");

  if (!materiaPrimaId || !motivo) {
    redirectCadastroAction(formData, "missing_mp_required", "#editar", materiaPrimaId);
  }
  if (!Number.isInteger(materiaPrimaId) || materiaPrimaId <= 0) {
    redirectCadastroAction(formData, "invalid_positive_number", "#editar", materiaPrimaId);
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "deactivate_cad_materia_prima", {
    p_materia_prima_id: materiaPrimaId,
    p_motivo: motivo
  });

  if (error) {
    redirectCadastroAction(formData, mapSupabaseError(error.message), "#editar", materiaPrimaId);
  }

  revalidateTechnicalCatalogs();
  redirectCadastroAction(formData, "mp_deactivated", "#editar", materiaPrimaId);
}

export async function createProdutoBaseAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirectCadastroAction(formData, "not_configured", "#novo-produto");
  }

  const codigoProduto = field(formData, "codigo_produto");
  const nome = field(formData, "nome");
  const status = field(formData, "status") || "active";
  const densidadeKgL = optionalNumber(formData, "densidade_kg_l");
  const prazoValidadeMesesText = optionalField(formData, "prazo_validade_meses");
  const prazoValidadeMeses = prazoValidadeMesesText === null ? null : Number(prazoValidadeMesesText);

  if (!codigoProduto || !nome) {
    redirectCadastroAction(formData, "missing_product_required", "#novo-produto");
  }
  if (!ALLOWED_STATUS.has(status)) {
    redirectCadastroAction(formData, "invalid_status", "#novo-produto");
  }
  if (densidadeKgL !== null && (!Number.isFinite(densidadeKgL) || densidadeKgL <= 0)) {
    redirectCadastroAction(formData, "invalid_positive_number", "#novo-produto");
  }
  if (
    prazoValidadeMeses !== null &&
    (!Number.isInteger(prazoValidadeMeses) || prazoValidadeMeses < 1 || prazoValidadeMeses > 240)
  ) {
    redirectCadastroAction(formData, "invalid_validity_months", "#novo-produto");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc<number>(supabase, "create_cad_produto_base", {
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
    p_prazo_validade_meses: prazoValidadeMeses,
    p_reg_mapa: optionalField(formData, "reg_mapa"),
    p_status: status
  });

  if (error) {
    redirectCadastroAction(formData, mapSupabaseError(error.message), "#novo-produto");
  }
  revalidateTechnicalCatalogs();
  redirectCadastroAction(formData, "produto_created", "#novo-produto");
}

export async function createEmbalagemAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirectCadastroAction(formData, "not_configured", "#nova-embalagem");
  }

  const descricao = field(formData, "descricao");
  const unidade = field(formData, "unidade");
  const status = field(formData, "status") || "active";
  const volumeLitros = optionalNumber(formData, "volume_litros");
  const controlaEstoque = formData.get("controla_estoque") === "1";
  const materiaPrimaId = optionalInteger(formData, "materia_prima_id");

  if (!descricao || !unidade) {
    redirectCadastroAction(formData, "missing_package_required", "#nova-embalagem");
  }
  if (!ALLOWED_STATUS.has(status)) {
    redirectCadastroAction(formData, "invalid_status", "#nova-embalagem");
  }
  if (volumeLitros !== null && (!Number.isFinite(volumeLitros) || volumeLitros <= 0)) {
    redirectCadastroAction(formData, "invalid_positive_number", "#nova-embalagem");
  }
  if (materiaPrimaId !== null && (!Number.isInteger(materiaPrimaId) || materiaPrimaId <= 0)) {
    redirectCadastroAction(formData, "invalid_positive_number", "#nova-embalagem");
  }
  if (controlaEstoque && materiaPrimaId === null) {
    redirectCadastroAction(formData, "missing_package_stock_item", "#nova-embalagem");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "create_cad_embalagem", {
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
    redirectCadastroAction(formData, mapSupabaseError(error.message), "#nova-embalagem");
  }

  revalidateTechnicalCatalogs();
  redirectCadastroAction(formData, "embalagem_created", "#nova-embalagem");
}

export async function createProdutoEmbalagemAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirectCadastroAction(formData, "not_configured", "#novo-item-vendavel");
  }

  const produtoId = optionalInteger(formData, "produto_id");
  const embalagemId = optionalInteger(formData, "embalagem_id");
  const codigoItem = field(formData, "codigo_item");
  const status = field(formData, "status") || "active";

  if (!produtoId || !embalagemId || !codigoItem) {
    redirectCadastroAction(formData, "missing_sale_item_required", "#novo-item-vendavel");
  }
  if (!Number.isInteger(produtoId) || produtoId <= 0 || !Number.isInteger(embalagemId) || embalagemId <= 0) {
    redirectCadastroAction(formData, "invalid_positive_number", "#novo-item-vendavel");
  }
  if (!ALLOWED_STATUS.has(status)) {
    redirectCadastroAction(formData, "invalid_status", "#novo-item-vendavel");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "create_cad_produto_embalagem", {
    p_codigo_item: codigoItem.toUpperCase(),
    p_embalagem_id: embalagemId,
    p_produto_id: produtoId,
    p_status: status
  });

  if (error) {
    redirectCadastroAction(formData, mapSupabaseError(error.message), "#novo-item-vendavel");
  }

  revalidateTechnicalCatalogs();
  redirectCadastroAction(formData, "item_vendavel_created", "#novo-item-vendavel");
}

export async function createConversaoUnidadeMpAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirectCadastroAction(formData, "not_configured", "#nova-conversao-mp");
  }

  const materiaPrimaId = optionalInteger(formData, "materia_prima_id");
  const unidadeOrigem = field(formData, "unidade_origem").toUpperCase();
  const unidadeDestino = field(formData, "unidade_destino").toUpperCase();
  const fator = optionalNumber(formData, "fator");
  const vigenciaInicio = optionalField(formData, "vigencia_inicio");
  const vigenciaFim = optionalField(formData, "vigencia_fim");

  if (!materiaPrimaId || !unidadeOrigem || !unidadeDestino || fator === null) {
    redirectCadastroAction(formData, "missing_conversion_required", "#nova-conversao-mp");
  }
  if (!Number.isInteger(materiaPrimaId) || materiaPrimaId <= 0) {
    redirectCadastroAction(formData, "invalid_positive_number", "#nova-conversao-mp");
  }
  if (!Number.isFinite(fator) || fator <= 0) {
    redirectCadastroAction(formData, "invalid_positive_number", "#nova-conversao-mp");
  }
  if (unidadeOrigem === unidadeDestino) {
    redirectCadastroAction(formData, "invalid_unit_conversion", "#nova-conversao-mp");
  }
  if (vigenciaInicio && vigenciaFim && vigenciaFim < vigenciaInicio) {
    redirectCadastroAction(formData, "invalid_date_range", "#nova-conversao-mp");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "create_cad_conversao_unidade_mp", {
    p_fator: fator,
    p_materia_prima_id: materiaPrimaId,
    p_unidade_destino: unidadeDestino,
    p_unidade_origem: unidadeOrigem,
    p_vigencia_fim: vigenciaFim,
    p_vigencia_inicio: vigenciaInicio
  });

  if (error) {
    redirectCadastroAction(formData, mapSupabaseError(error.message), "#nova-conversao-mp");
  }

  revalidateTechnicalCatalogs();
  redirectCadastroAction(formData, "conversion_created", "#nova-conversao-mp");
}

function redirectCadastroAction(
  formData: FormData,
  result: string,
  hash: string,
  selectedId: number | null = null
): never {
  const requestedPath = optionalField(formData, "return_to");
  const targetPath = requestedPath && ALLOWED_CADASTRO_RETURN_PATHS.has(requestedPath)
    ? requestedPath
    : "/cadastros";
  const params = new URLSearchParams({ result });
  if (targetPath === "/cadastros/materias-primas" && selectedId && selectedId > 0) {
    params.set("selected", String(selectedId));
  }
  redirect(`${targetPath}?${params.toString()}${hash}`);
}

function revalidateTechnicalCatalogs() {
  revalidatePath("/cadastros");
  revalidatePath("/cadastros/tecnicos");
  revalidatePath("/cadastros/materias-primas");
  revalidatePath("/cadastros/unidades");
  revalidatePath("/cadastros/embalagens");
  revalidatePath("/cadastros/produtos");
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
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && String(parsed) === value ? parsed : null;
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

function onlyDigits(value: string): string {
  return value.replace(/\D/g, "");
}

function mapSupabaseError(message: string): string {
  const normalized = message.toLowerCase();
  if (normalized.includes("duplicate") || normalized.includes("unique")) {
    return "duplicated";
  }
  if (normalized.includes("permission") || normalized.includes("row-level security") || normalized.includes("not allowed")) {
    return "permission_denied";
  }
  return "save_failed";
}
