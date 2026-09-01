"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { auditedRpc } from "@/lib/supabase/rpc";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{12}$/i;
const COMPONENTS = [
  ["materia_prima", "BRL_L"], ["embalagem", "BRL_L"], ["custo_pontuacao_vendedor", "BRL_L"],
  ["custo_pontuacao_revenda", "BRL_L"], ["premiacao_revenda", "BRL_L"], ["premio_producao", "BRL_L"],
  ["frete", "BRL_L"], ["comissao", "FRACAO"], ["risco", "FRACAO"], ["marketing", "FRACAO"], ["tributacao", "FRACAO"],
] as const;

export async function createPricingPolicyAction(formData: FormData) {
  await call("salvar_prc_politica_versao_idempotente", "precificacao.policy.manage", "prc_politica_versoes", {
    p_key: key(formData), p_codigo: text(formData,"codigo"), p_nome: text(formData,"nome"), p_metodo: text(formData,"metodo"),
    p_lucro_minimo: nullableNumber(formData,"lucro_minimo"), p_markup: nullableNumber(formData,"markup"),
    p_juros_mensais: number(formData,"juros_mensais"), p_motivo: text(formData,"motivo"),
  }, "policy");
}

export async function reviewPricingPolicyAction(formData: FormData) {
  await call("decidir_prc_politica_versao_idempotente", "precificacao.policy.review", "prc_politica_revisoes", {
    p_key:key(formData),p_versao_id:integer(formData,"versao_id"),p_decisao:text(formData,"decisao"),p_justificativa:text(formData,"justificativa"),
  }, "policy-review");
}

export async function createPricingScenarioAction(formData: FormData) {
  const sourceKind=text(formData,"source_kind"); const sourceReference=text(formData,"source_reference");
  const sourceDate=text(formData,"source_effective_date"); const sourceReason=text(formData,"source_reason");
  const componentes=COMPONENTS.map(([campo,unidade])=>({ campo, unidade, valor:number(formData,campo), source_kind:sourceKind,
    source_reference:sourceReference, source_effective_date:sourceDate, reason:sourceReason }));
  await call("criar_prc_cenario_idempotente", "precificacao.scenario.manage", "prc_cenarios", {
    p_key:key(formData),p_politica_versao_id:integer(formData,"politica_versao_id"),p_produto_embalagem_id:integer(formData,"produto_embalagem_id"),
    p_nome:text(formData,"nome"),p_motivo:text(formData,"motivo"),p_componentes:componentes,
  }, "scenario");
}

export async function calculatePricingScenarioAction(formData: FormData) {
  await call("calcular_prc_cenario_idempotente", "precificacao.calculate", "prc_calculos", {
    p_key:key(formData),p_cenario_id:integer(formData,"cenario_id"),p_motivo:text(formData,"motivo"),
  }, "calculation");
}

export async function reviewPricingCalculationAction(formData: FormData) {
  await call("decidir_prc_calculo_idempotente", "precificacao.calculation.review", "prc_calculo_decisoes", {
    p_key:key(formData),p_calculo_id:integer(formData,"calculo_id"),p_decisao:text(formData,"decisao"),p_justificativa:text(formData,"justificativa"),
  }, "calculation-review");
}

async function call(functionName:string,actionKey:string,entity:string,args:Record<string,unknown>,result:string) {
  if (!UUID.test(String(args.p_key ?? ""))) redirect("/custos-precos?result=invalid-request");
  const supabase=await createSupabaseServerClient();
  const { error }=await auditedRpc(supabase,functionName,args,{origin:"apps/web/app/custos-precos",metadata:{action_key:actionKey,axis:"field_risk",domain:"precificacao",entity,failure_action:`precificacao.${result}.failed`,correlation_id:String(args.p_key)}});
  if(error) redirect(`/custos-precos?result=${encodeURIComponent(mapError(error.message))}`);
  revalidatePath("/custos-precos"); redirect(`/custos-precos?result=${result}-saved`);
}
function text(formData:FormData,name:string){return String(formData.get(name)??"").trim();}
function number(formData:FormData,name:string){const value=Number(text(formData,name).replace(",","."));return Number.isFinite(value)?value:NaN;}
function nullableNumber(formData:FormData,name:string){return text(formData,name)?number(formData,name):null;}
function integer(formData:FormData,name:string){const value=Number(text(formData,name));return Number.isInteger(value)&&value>0?value:null;}
function key(formData:FormData){return text(formData,"idempotency_key");}
function mapError(message:string){const value=message.toLocaleLowerCase("pt-BR");if(value.includes("not allowed")||value.includes("permission"))return "permission";if(value.includes("denominador"))return "denominator";if(value.includes("componente")||value.includes("fonte"))return "components";if(value.includes("criador"))return "segregation";if(value.includes("idempotencia"))return "idempotency";return "failed";}
