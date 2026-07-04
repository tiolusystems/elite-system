"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { getRuntimeStatus } from "@/lib/runtime";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const DECIMAL_SEPARATOR = /,/g;
const ALLOWED_LOT_STATUS = new Set(["disponivel", "bloqueado"]);

type ParsedNfeItem = {
  numeroItem: number;
  codigoFornecedor: string | null;
  descricaoFornecedor: string;
  ncm: string | null;
  cfop: string | null;
  unidadeXml: string;
  quantidadeXml: number;
  valorTotal: number;
  loteFornecedor: string | null;
};

type ParsedNfeXml = {
  chaveAcesso: string;
  numero: string | null;
  serie: string | null;
  emitenteCnpj: string | null;
  emitenteNome: string | null;
  dataEmissao: string | null;
  items: ParsedNfeItem[];
};

export async function importNfeXmlTextAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/importacao-xml?result=not_configured#importar-xml");
  }

  const xmlText = field(formData, "xml_text");
  if (!xmlText) {
    redirect("/importacao-xml?result=missing_xml_text#importar-xml");
  }

  const parsed = parseNfeXml(xmlText);
  if (!parsed.chaveAcesso) {
    redirect("/importacao-xml?result=invalid_xml#importar-xml");
  }
  if (parsed.items.length === 0) {
    redirect("/importacao-xml?result=no_xml_items#importar-xml");
  }

  const supabase = await createSupabaseServerClient();
  const { data: nfeId, error } = await supabase.rpc("stage_imp_nfe_xml", {
    p_chave_acesso: parsed.chaveAcesso,
    p_data_emissao: parsed.dataEmissao,
    p_emitente_cnpj: parsed.emitenteCnpj,
    p_emitente_nome: parsed.emitenteNome,
    p_numero: parsed.numero,
    p_payload_resumo_json: { source: "apps/web/importacao-xml", mode: "xml_text" },
    p_serie: parsed.serie
  });

  if (error || !nfeId) {
    redirect(`/importacao-xml?result=${encodeURIComponent(mapImportError(error?.message ?? "save_failed"))}#importar-xml`);
  }

  for (const item of parsed.items) {
    const itemResult = await supabase.rpc("stage_imp_nfe_xml_item", {
      p_cfop: item.cfop,
      p_codigo_fornecedor: item.codigoFornecedor,
      p_data_fabricacao: null,
      p_data_validade: null,
      p_descricao_fornecedor: item.descricaoFornecedor,
      p_lote_fornecedor: item.loteFornecedor,
      p_ncm: item.ncm,
      p_nfe_id: Number(nfeId),
      p_numero_item: item.numeroItem,
      p_payload_item_json: { source: "apps/web/importacao-xml", mode: "xml_text" },
      p_quantidade_xml: item.quantidadeXml,
      p_unidade_xml: item.unidadeXml,
      p_valor_total: item.valorTotal
    });
    if (itemResult.error) {
      redirect(`/importacao-xml?result=${encodeURIComponent(mapImportError(itemResult.error.message))}#importar-xml`);
    }
  }

  revalidatePath("/importacao-xml");
  redirect("/importacao-xml?result=xml_imported#fila-xml");
}

export async function stageNfeHeaderAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/importacao-xml?result=not_configured#cabecalho-nfe");
  }

  const chaveAcesso = onlyDigits(field(formData, "chave_acesso"));
  if (chaveAcesso.length !== 44) {
    redirect("/importacao-xml?result=invalid_chave_acesso#cabecalho-nfe");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("stage_imp_nfe_xml", {
    p_chave_acesso: chaveAcesso,
    p_data_emissao: optionalField(formData, "data_emissao"),
    p_emitente_cnpj: optionalField(formData, "emitente_cnpj"),
    p_emitente_nome: optionalField(formData, "emitente_nome"),
    p_numero: optionalField(formData, "numero"),
    p_payload_resumo_json: { source: "apps/web/importacao-xml", mode: "manual_header" },
    p_serie: optionalField(formData, "serie")
  });

  if (error) {
    redirect(`/importacao-xml?result=${encodeURIComponent(mapImportError(error.message))}#cabecalho-nfe`);
  }

  revalidatePath("/importacao-xml");
  redirect("/importacao-xml?result=header_staged#cabecalho-nfe");
}

export async function stageNfeItemAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/importacao-xml?result=not_configured#item-nfe");
  }

  const nfeId = optionalInteger(formData, "nfe_id");
  const numeroItem = optionalInteger(formData, "numero_item");
  const descricao = field(formData, "descricao_fornecedor");
  const unidadeXml = field(formData, "unidade_xml").toUpperCase();
  const quantidadeXml = optionalNumber(formData, "quantidade_xml");
  const valorTotal = optionalNumber(formData, "valor_total") ?? 0;

  if (!nfeId || !numeroItem || !descricao || !unidadeXml || quantidadeXml === null) {
    redirect("/importacao-xml?result=missing_item_required#item-nfe");
  }
  if (!Number.isInteger(nfeId) || nfeId <= 0 || !Number.isInteger(numeroItem) || numeroItem <= 0) {
    redirect("/importacao-xml?result=invalid_positive_number#item-nfe");
  }
  if (!Number.isFinite(quantidadeXml) || quantidadeXml <= 0 || !Number.isFinite(valorTotal) || valorTotal < 0) {
    redirect("/importacao-xml?result=invalid_number#item-nfe");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("stage_imp_nfe_xml_item", {
    p_cfop: optionalField(formData, "cfop"),
    p_codigo_fornecedor: optionalField(formData, "codigo_fornecedor"),
    p_data_fabricacao: optionalField(formData, "data_fabricacao"),
    p_data_validade: optionalField(formData, "data_validade"),
    p_descricao_fornecedor: descricao,
    p_lote_fornecedor: optionalField(formData, "lote_fornecedor"),
    p_ncm: optionalField(formData, "ncm"),
    p_nfe_id: nfeId,
    p_numero_item: numeroItem,
    p_payload_item_json: { source: "apps/web/importacao-xml", mode: "manual_item" },
    p_quantidade_xml: quantidadeXml,
    p_unidade_xml: unidadeXml,
    p_valor_total: valorTotal
  });

  if (error) {
    redirect(`/importacao-xml?result=${encodeURIComponent(mapImportError(error.message))}#item-nfe`);
  }

  revalidatePath("/importacao-xml");
  redirect("/importacao-xml?result=item_staged#fila-xml");
}

export async function confirmNfeItemMatchAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/importacao-xml?result=not_configured#fila-xml");
  }

  const itemId = optionalInteger(formData, "item_id");
  const materiaPrimaId = optionalInteger(formData, "materia_prima_id");
  const fatorConversao = optionalNumber(formData, "fator_conversao");
  const motivo = field(formData, "motivo");

  if (!itemId || !materiaPrimaId || !motivo) {
    redirect("/importacao-xml?result=missing_match_required#fila-xml");
  }
  if (!Number.isInteger(itemId) || itemId <= 0 || !Number.isInteger(materiaPrimaId) || materiaPrimaId <= 0) {
    redirect("/importacao-xml?result=invalid_positive_number#fila-xml");
  }
  if (fatorConversao !== null && (!Number.isFinite(fatorConversao) || fatorConversao <= 0)) {
    redirect("/importacao-xml?result=invalid_positive_number#fila-xml");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("confirm_imp_nfe_item_match", {
    p_data_fabricacao: optionalField(formData, "data_fabricacao"),
    p_data_validade: optionalField(formData, "data_validade"),
    p_fator_conversao: fatorConversao,
    p_item_id: itemId,
    p_lote_fornecedor: optionalField(formData, "lote_fornecedor"),
    p_materia_prima_id: materiaPrimaId,
    p_motivo: motivo,
    p_unidade_destino: optionalField(formData, "unidade_destino")?.toUpperCase() ?? null
  });

  if (error) {
    redirect(`/importacao-xml?result=${encodeURIComponent(mapImportError(error.message))}#fila-xml`);
  }

  revalidatePath("/importacao-xml");
  redirect("/importacao-xml?result=item_matched#fila-xml");
}

export async function generateMpLotFromNfeItemAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/importacao-xml?result=not_configured#fila-xml");
  }

  const itemId = optionalInteger(formData, "item_id");
  const status = field(formData, "status") || "disponivel";
  if (!itemId || !Number.isInteger(itemId) || itemId <= 0) {
    redirect("/importacao-xml?result=invalid_positive_number#fila-xml");
  }
  if (!ALLOWED_LOT_STATUS.has(status)) {
    redirect("/importacao-xml?result=invalid_lot_status#fila-xml");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("gerar_lote_mp_from_imp_nfe_item", {
    p_item_id: itemId,
    p_observacao: optionalField(formData, "observacao"),
    p_status: status
  });

  if (error) {
    redirect(`/importacao-xml?result=${encodeURIComponent(mapImportError(error.message))}#fila-xml`);
  }

  revalidatePath("/importacao-xml");
  redirect("/importacao-xml?result=mp_lot_generated#fila-xml");
}

export async function ignoreNfeItemAction(formData: FormData) {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    redirect("/importacao-xml?result=not_configured#fila-xml");
  }

  const itemId = optionalInteger(formData, "item_id");
  const motivo = field(formData, "motivo");
  if (!itemId || !motivo) {
    redirect("/importacao-xml?result=missing_ignore_required#fila-xml");
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.rpc("ignore_imp_nfe_xml_item", {
    p_item_id: itemId,
    p_motivo: motivo
  });

  if (error) {
    redirect(`/importacao-xml?result=${encodeURIComponent(mapImportError(error.message))}#fila-xml`);
  }

  revalidatePath("/importacao-xml");
  redirect("/importacao-xml?result=item_ignored#fila-xml");
}

function parseNfeXml(xmlText: string): ParsedNfeXml {
  const xml = xmlText.replace(/\r?\n/g, " ");
  return {
    chaveAcesso: onlyDigits(extractTag(xml, "chNFe") ?? extractInfNfeId(xml) ?? ""),
    numero: extractTag(xml, "nNF"),
    serie: extractTag(xml, "serie"),
    emitenteCnpj: extractFromBlock(xml, "emit", "CNPJ"),
    emitenteNome: extractFromBlock(xml, "emit", "xNome"),
    dataEmissao: parseXmlDate(extractTag(xml, "dhEmi") ?? extractTag(xml, "dEmi")),
    items: parseNfeItems(xml)
  };
}

function parseNfeItems(xml: string): ParsedNfeItem[] {
  const matches = Array.from(xml.matchAll(/<(?:[A-Za-z0-9_]+:)?det\b([^>]*)>([\s\S]*?)<\/(?:[A-Za-z0-9_]+:)?det>/gi));
  return matches
    .map((match, index) => {
      const attrs = match[1] ?? "";
      const detBlock = match[2] ?? "";
      const prodBlock = extractBlock(detBlock, "prod") ?? detBlock;
      const numeroItem = Number(attrs.match(/nItem=["']?(\d+)["']?/i)?.[1] ?? index + 1);
      const descricaoFornecedor = extractTag(prodBlock, "xProd");
      const unidadeXml = extractTag(prodBlock, "uCom") ?? extractTag(prodBlock, "uTrib");
      const quantidadeXml = parseXmlNumber(extractTag(prodBlock, "qCom") ?? extractTag(prodBlock, "qTrib"));

      if (!descricaoFornecedor || !unidadeXml || quantidadeXml === null || quantidadeXml <= 0) {
        return null;
      }

      return {
        numeroItem,
        codigoFornecedor: extractTag(prodBlock, "cProd"),
        descricaoFornecedor,
        ncm: extractTag(prodBlock, "NCM"),
        cfop: extractTag(prodBlock, "CFOP"),
        unidadeXml: unidadeXml.toUpperCase(),
        quantidadeXml,
        valorTotal: parseXmlNumber(extractTag(prodBlock, "vProd")) ?? 0,
        loteFornecedor: extractTag(prodBlock, "nLote")
      };
    })
    .filter((item): item is ParsedNfeItem => item !== null);
}

function extractInfNfeId(xml: string): string | null {
  return xml.match(/<(?:[A-Za-z0-9_]+:)?infNFe\b[^>]*\bId=["']NFe(\d{44})["']/i)?.[1] ?? null;
}

function extractFromBlock(xml: string, blockTag: string, tag: string): string | null {
  const block = extractBlock(xml, blockTag);
  return block ? extractTag(block, tag) : null;
}

function extractBlock(xml: string, tag: string): string | null {
  const match = xml.match(new RegExp(`<(?:[A-Za-z0-9_]+:)?${tag}\\b[^>]*>([\\s\\S]*?)<\\/(?:[A-Za-z0-9_]+:)?${tag}>`, "i"));
  return match?.[1] ? match[1] : null;
}

function extractTag(xml: string, tag: string): string | null {
  const value = extractBlock(xml, tag);
  return value ? decodeXml(value.trim()) : null;
}

function parseXmlDate(value: string | null): string | null {
  if (!value) {
    return null;
  }
  const datePart = value.slice(0, 10);
  return /^\d{4}-\d{2}-\d{2}$/.test(datePart) ? datePart : null;
}

function parseXmlNumber(value: string | null): number | null {
  if (!value) {
    return null;
  }
  const parsed = Number(value.replace(DECIMAL_SEPARATOR, "."));
  return Number.isFinite(parsed) ? parsed : null;
}

function decodeXml(value: string): string {
  return value
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'");
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
  const parsed = Number(value.replace(DECIMAL_SEPARATOR, "."));
  return Number.isFinite(parsed) ? parsed : null;
}

function optionalInteger(formData: FormData, name: string): number | null {
  const value = optionalField(formData, name);
  if (value === null) {
    return null;
  }
  const idPrefix = value.match(/^\s*(\d+)/);
  return Number(idPrefix ? idPrefix[1] : value);
}

function onlyDigits(value: string): string {
  return value.replace(/\D/g, "");
}

function mapImportError(message: string): string {
  const normalized = message.toLowerCase();
  if (normalized.includes("44 digits")) {
    return "invalid_chave_acesso";
  }
  if (normalized.includes("already generated") || normalized.includes("already has generated")) {
    return "already_generated";
  }
  if (normalized.includes("unit conversion factor is required")) {
    return "missing_conversion_factor";
  }
  if (normalized.includes("motivo is required")) {
    return "missing_motivo";
  }
  if (normalized.includes("not found") || normalized.includes("foreign key")) {
    return "missing_related_record";
  }
  if (normalized.includes("permission") || normalized.includes("row-level security")) {
    return "permission_denied";
  }
  if (normalized.includes("duplicate") || normalized.includes("unique")) {
    return "duplicated";
  }
  return "save_failed";
}
