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

function field(formData: FormData, name: string): string {
  return String(formData.get(name) ?? "").trim();
}

function optionalField(formData: FormData, name: string): string | null {
  const value = field(formData, name);
  return value || null;
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
