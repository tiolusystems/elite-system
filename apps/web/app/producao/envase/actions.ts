"use server";

import { headers } from "next/headers";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getRuntimeStatus } from "@/lib/runtime";
import { auditedRpc } from "@/lib/supabase/rpc";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export async function issuePackagingOrderAction(formData: FormData) {
  if (!getRuntimeStatus().supabaseConfigured) redirect("/producao/envase?result=not_configured#emitir");
  const idempotencyKey = uuid(formData, "idempotency_key");
  const formulaId = integer(formData, "formula_mapa_versao_id");
  const piLotId = integer(formData, "lote_pi_origem_id");
  const presentationId = integer(formData, "produto_embalagem_id");
  const volume = decimal(formData, "volume_planejado_l");
  if (!idempotencyKey || !formulaId || !piLotId || !presentationId || !volume || volume <= 0) redirect("/producao/envase?result=missing_packaging_issue#emitir");
  const requestHeaders = await headers();
  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "emitir_pcp_op_mapa_com_envase_idempotente", {
    p_idempotency_key: idempotencyKey,
    p_formula_mapa_versao_id: formulaId,
    p_lote_pi_origem_id: piLotId,
    p_observacao: optionalText(formData, "observacao"),
    p_produto_embalagem_id: presentationId,
    p_terminal_emissor: terminalSnapshot(requestHeaders),
    p_volume_planejado_l: volume
  }, audit("pcp.envase.issue", "pcp_ordens_envase", "apps/web/pcp.envase.issue"));
  if (error) redirect(`/producao/envase?result=${encodeURIComponent(mapError(error.message))}#emitir`);
  refreshPackaging();
  redirect("/producao/envase?result=packaging_order_issued#ordens-envase");
}

export async function reservePackagingAction(formData: FormData) {
  const planId = integer(formData, "embalagem_planejada_id");
  const lotId = integer(formData, "lote_mp_id");
  const quantity = decimal(formData, "quantidade");
  if (!planId || !lotId || !quantity || quantity <= 0) redirect("/producao/envase?result=missing_packaging_reservation#ordens-envase");
  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "reservar_pcp_ordem_envase_embalagem", {
    p_embalagem_planejada_id: planId, p_lote_mp_id: lotId, p_quantidade: quantity
  }, audit("pcp.envase.reserve", "pcp_ordem_envase_reservas", "apps/web/pcp.envase.reserve"));
  if (error) redirect(`/producao/envase?result=${encodeURIComponent(mapError(error.message))}#ordens-envase`);
  refreshPackaging();
  redirect("/producao/envase?result=packaging_reserved#ordens-envase");
}

export async function startPackagingAction(formData: FormData) {
  const orderId = integer(formData, "ordem_envase_id");
  if (!orderId) redirect("/producao/envase?result=missing_op_required#ordens-envase");
  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "iniciar_pcp_ordem_envase", { p_ordem_envase_id: orderId },
    audit("pcp.envase.start", "pcp_ordens_envase", "apps/web/pcp.envase.start"));
  if (error) redirect(`/producao/envase?result=${encodeURIComponent(mapError(error.message))}#ordens-envase`);
  refreshPackaging();
  redirect("/producao/envase?result=packaging_started#ordens-envase");
}

export async function finishPackagingAction(formData: FormData) {
  const orderId = integer(formData, "ordem_envase_id");
  const quantity = decimal(formData, "lote_pa_quantidade");
  if (!orderId || !quantity || quantity <= 0) redirect("/producao/envase?result=missing_packaging_outputs#ordens-envase");
  const outputs = [{
    quantidade: quantity,
    observacao: optionalText(formData, "lote_pa_observacao")
  }];
  const supabase = await createSupabaseServerClient();
  const { error } = await auditedRpc(supabase, "finalizar_pcp_ordem_envase", {
    p_lotes_pa_jsonb: outputs, p_observacao: optionalText(formData, "observacao"), p_ordem_envase_id: orderId
  }, audit("pcp.envase.finish", "pcp_ordens_envase", "apps/web/pcp.envase.finish"));
  if (error) redirect(`/producao/envase?result=${encodeURIComponent(mapError(error.message))}#ordens-envase`);
  refreshPackaging();
  redirect("/producao/envase?result=packaging_finished#ordens-envase");
}

function audit(actionKey: string, entity: string, origin: string) {
  return { origin, metadata: { action_key: actionKey, axis: "movement_event", domain: "pcp", entity } } as const;
}
function terminalSnapshot(values: Headers): string {
  const governed = values.get("x-elite-terminal-id")?.trim();
  if (governed) return governed.slice(0, 120);
  const platform = values.get("sec-ch-ua-platform")?.replaceAll('"', "").trim();
  return `Web${platform ? ` / ${platform}` : " / dispositivo nao identificado"}`.slice(0, 120);
}
function text(formData: FormData, name: string): string { return String(formData.get(name) ?? "").trim(); }
function optionalText(formData: FormData, name: string): string | null { return text(formData, name) || null; }
function integer(formData: FormData, name: string): number | null { const value = Number.parseInt(text(formData, name), 10); return Number.isInteger(value) && value > 0 ? value : null; }
function decimal(formData: FormData, name: string): number | null { const raw = text(formData, name).replace(",", "."); if (!raw) return null; const value = Number(raw); return Number.isFinite(value) ? value : null; }
function uuid(formData: FormData, name: string): string | null { const value = text(formData, name); return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value) ? value : null; }
function refreshPackaging() { for (const path of ["/producao", "/producao/envase", "/producao/estoque", "/relatorios", "/romaneios"]) revalidatePath(path); }
function mapError(message: string): string {
  const normalized = message.toLowerCase();
  if (normalized.includes("not allowed")) return "not_allowed";
  if (normalized.includes("available") || normalized.includes("reservation") || normalized.includes("planned")) return "missing_packaging_reservation";
  if (normalized.includes("whole number") || normalized.includes("sum") || normalized.includes("output")) return "missing_packaging_outputs";
  return "operation_failed";
}
