-- Envase operational contract: one order generates one PA lot for one sale item.

create or replace function public.finalizar_pcp_ordem_envase(
  p_ordem_envase_id bigint,
  p_lotes_pa_jsonb jsonb,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result bigint;
begin
  perform public.require_current_user_permission('pcp.envase.finish');
  if p_lotes_pa_jsonb is null
     or jsonb_typeof(p_lotes_pa_jsonb) <> 'array'
     or jsonb_array_length(p_lotes_pa_jsonb) <> 1 then
    raise exception 'packaging order must generate exactly one PA lot';
  end if;

  v_result := public.finalizar_pcp_ordem_envase_impl_0077(
    p_ordem_envase_id,
    p_lotes_pa_jsonb,
    p_observacao
  );
  perform public.materialize_pcp_envase_pa_cost(p_ordem_envase_id);
  return v_result;
end;
$$;

revoke all on function public.finalizar_pcp_ordem_envase(bigint, jsonb, text) from public, anon;
grant execute on function public.finalizar_pcp_ordem_envase(bigint, jsonb, text) to authenticated;

comment on function public.finalizar_pcp_ordem_envase(bigint, jsonb, text) is
  'Finaliza uma Ordem de Envase gerando exatamente um lote PA do item de venda da ordem; preserva custo direto PI mais embalagens.';
