"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { normalizeKey, normalizeUf } from "@/lib/normalization";
import { getRuntimeStatus } from "@/lib/runtime";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const ALLOWED_STATUS = new Set(["active", "inactive", "pending_review"]);

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
  return value
    .split(/[,;\n]/)
    .map((item) => item.trim())
    .filter(Boolean);
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
