-- Manual, audited commission assignment after managerial order approval.

alter table public.com_pedido_comissionados drop constraint if exists com_pedido_comissionados_papel_check;
alter table public.com_pedido_comissionados add constraint com_pedido_comissionados_papel_check check (
  papel_comissao in ('vendedor', 'agente', 'gerente', 'tecnico_campo', 'campanha', 'outro')
);

insert into public.permission_actions(
  action_key, module, description, default_allowed, sort_order,
  runtime_module_key, runtime_access_kind
)
values (
  'pedidos.commissions.assign', 'pedidos',
  'Definir comissionados de venda antes do recebimento', false, 108,
  'pedidos', 'write'
)
on conflict (action_key) do update set module=excluded.module, description=excluded.description,
  default_allowed=excluded.default_allowed, sort_order=excluded.sort_order,
  runtime_module_key=excluded.runtime_module_key,
  runtime_access_kind=excluded.runtime_access_kind;

create or replace function public.definir_com_pedido_comissao(
  p_pedido_id bigint, p_pessoa_id bigint, p_papel_comissao text,
  p_percentual_comissao numeric, p_justificativa text
) returns bigint language plpgsql security definer set search_path=public as $$
declare
  v_actor uuid; v_context jsonb; v_order public.com_pedidos%rowtype;
  v_assignment public.com_pedido_comissionados%rowtype; v_before jsonb; v_after jsonb;
  v_role text := lower(nullif(trim(p_papel_comissao), ''));
begin
  v_context := public.begin_audited_rpc(
    'pedidos.commissions.assign','pedidos','com_pedido_comissionados','change_type',
    jsonb_build_object('event','commission_assignment')
  );
  if p_pedido_id is null or p_pedido_id <= 0 then raise exception 'pedido_id is required'; end if;
  if p_pessoa_id is null or p_pessoa_id <= 0 then raise exception 'pessoa_id is required'; end if;
  if v_role is null or v_role not in ('vendedor','agente','gerente','outro') then raise exception 'invalid commission role'; end if;
  if p_percentual_comissao is null or p_percentual_comissao <= 0 or p_percentual_comissao > 100 then
    raise exception 'commission percentage must be greater than zero and at most 100';
  end if;
  if length(trim(coalesce(p_justificativa,''))) < 10 then
    raise exception 'commission justification must have at least 10 characters';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('order_commission:'||p_pedido_id::text,0));
  select * into v_order from public.com_pedidos where id=p_pedido_id for update;
  if not found then raise exception 'pedido not found'; end if;
  if v_order.tipo_pedido <> 'venda' then raise exception 'only sale orders allow commission'; end if;
  if v_order.status not in ('open','fulfilled') then raise exception 'order must be approved before commission assignment'; end if;
  if exists (select 1 from public.com_recebimentos where pedido_id=p_pedido_id and status='active')
     or exists (select 1 from public.fin_recebimento_alocacoes where pedido_id=p_pedido_id) then
    raise exception 'commission assignment must precede the first receipt';
  end if;
  if not exists (select 1 from public.cad_pessoas_comerciais where id=p_pessoa_id and status='active') then
    raise exception 'commission person must be active';
  end if;

  select * into v_assignment from public.com_pedido_comissionados
   where pedido_id=p_pedido_id and pessoa_id=p_pessoa_id and papel_comissao=v_role
     and status not in ('cancelada','estornada') order by id desc limit 1 for update;
  v_before := case when found then to_jsonb(v_assignment) else null end;
  v_actor := public.current_actor_id();
  if v_assignment.id is null then
    insert into public.com_pedido_comissionados(
      pedido_id,pessoa_id,papel_comissao,percentual_comissao,valor_base,valor_previsto,status,created_by,updated_by
    ) values (
      p_pedido_id,p_pessoa_id,v_role,p_percentual_comissao,v_order.valor_total,
      v_order.valor_total*p_percentual_comissao/100,'prevista',v_actor,v_actor
    ) returning * into v_assignment;
  else
    update public.com_pedido_comissionados set percentual_comissao=p_percentual_comissao,
      valor_base=v_order.valor_total, valor_previsto=v_order.valor_total*p_percentual_comissao/100,
      status='prevista', updated_by=v_actor where id=v_assignment.id returning * into v_assignment;
  end if;
  v_after := to_jsonb(v_assignment);
  perform public.log_audited_rpc_change(
    'pedidos','com_pedido_comissionados',v_assignment.id::text,'pedidos.comissao_definida',
    'pedidos.commissions.assign',v_context,v_before,v_after,
    jsonb_build_object('source','definir_com_pedido_comissao','pedido_id',p_pedido_id,
      'pessoa_id',p_pessoa_id,'papel_comissao',v_role,'justificativa',trim(p_justificativa))
  );
  return v_assignment.id;
end;
$$;

revoke all on function public.definir_com_pedido_comissao(bigint,bigint,text,numeric,text) from public, anon;
grant execute on function public.definir_com_pedido_comissao(bigint,bigint,text,numeric,text) to authenticated;
comment on function public.definir_com_pedido_comissao(bigint,bigint,text,numeric,text) is
  'Define ou revisa previsao de comissao para venda aprovada, antes do primeiro recebimento, com lock e auditoria.';
