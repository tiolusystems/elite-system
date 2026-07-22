\set ON_ERROR_STOP on
begin;

do $$
declare
  v_actor uuid := '00000000-0000-4000-8000-000000000088';
  v_denied uuid := '00000000-0000-4000-8000-000000000188';
  v_client bigint; v_person bigint; v_order bigint; v_assignment bigint;
begin
  if has_function_privilege('anon','public.definir_com_pedido_comissao(bigint,bigint,text,numeric,text)','EXECUTE') then
    raise exception 'anon can assign order commission';
  end if;
  if has_table_privilege('authenticated','public.com_pedido_comissionados','INSERT')
     or has_table_privilege('authenticated','public.com_pedido_comissionados','UPDATE') then
    raise exception 'authenticated can write order commissions directly';
  end if;
  insert into auth.users(id) values (v_actor),(v_denied) on conflict (id) do nothing;
  insert into public.user_profiles(id,display_name,role,status) values
    (v_actor,'Commission Assignment Actor','admin','active'),
    (v_denied,'Commission Assignment Denied','financeiro','active')
  on conflict (id) do update set status='active';
  insert into public.user_permission_overrides(user_id,action_key,allowed,updated_by) values
    (v_actor,'pedidos.commissions.assign',true,v_actor),
    (v_denied,'pedidos.commissions.assign',false,v_actor)
  on conflict (user_id,action_key) do update set allowed=excluded.allowed,updated_by=excluded.updated_by;
  perform set_config('request.jwt.claim.sub',v_actor::text,true);
  if public.current_system_environment()='unconfigured' then
    perform public.set_system_runtime_environment('test','test_reset','0088 commission assignment smoke');
  end if;
  insert into public.cad_clientes(nome,nome_norm,cidade,uf,status,created_by,updated_by)
  values ('Cliente 0088','cliente 0088','Barretos','SP','active',v_actor,v_actor) returning id into v_client;
  insert into public.cad_pessoas_comerciais(nome,nome_norm,papeis_json,status,created_by,updated_by)
  values ('Agente 0088','agente 0088','["agente"]','active',v_actor,v_actor) returning id into v_person;
  insert into public.com_pedidos(codigo_pedido,cliente_id,tipo_pedido,status,data_pedido,valor_total,created_by,updated_by)
  values ('PED-0088',v_client,'venda','open',current_date,1000,v_actor,v_actor) returning id into v_order;

  perform set_config('request.jwt.claim.sub',v_denied::text,true);
  begin
    perform public.definir_com_pedido_comissao(v_order,v_person,'agente',2,'Tentativa sem alcada');
    raise exception 'denied actor assigned commission';
  exception when others then if sqlerrm <> 'not allowed: pedidos.commissions.assign' then raise; end if; end;

  perform set_config('request.jwt.claim.sub',v_actor::text,true);
  v_assignment := public.definir_com_pedido_comissao(v_order,v_person,'agente',2.5,'Atribuicao comercial aprovada');
  if not exists (select 1 from public.com_pedido_comissionados where id=v_assignment
    and papel_comissao='agente' and percentual_comissao=2.5 and valor_base=1000
    and valor_previsto=25 and status='prevista') then
    raise exception 'commission assignment was not calculated correctly';
  end if;
  if not exists (select 1 from public.action_logs where entity_type='com_pedido_comissionados'
    and entity_id=v_assignment::text and action_key='pedidos.commissions.assign'
    and metadata_json->>'justificativa'='Atribuicao comercial aprovada') then
    raise exception 'commission assignment audit is missing';
  end if;
  perform public.definir_com_pedido_comissao(v_order,v_person,'agente',3,'Revisao antes do recebimento');
  if (select count(*) from public.com_pedido_comissionados where pedido_id=v_order and pessoa_id=v_person and papel_comissao='agente')<>1
     or (select percentual_comissao from public.com_pedido_comissionados where id=v_assignment)<>3 then
    raise exception 'commission assignment revision duplicated the row';
  end if;
  insert into public.com_recebimentos(pedido_id,cliente_id,valor_recebido,data_recebimento,status,created_by)
  values (v_order,v_client,100,current_date,'active',v_actor);
  begin
    perform public.definir_com_pedido_comissao(v_order,v_person,'agente',4,'Tentativa apos recebimento');
    raise exception 'assignment changed after receipt';
  exception when others then if sqlerrm <> 'commission assignment must precede the first receipt' then raise; end if; end;
end;
$$;

rollback;
select 'PG_ORDER_COMMISSION_ASSIGNMENT_OK' as result;
