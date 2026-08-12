\set ON_ERROR_STOP on
begin;

do $$
declare
  v_actor uuid := '00000000-0000-4000-8000-000000000088';
  v_denied uuid := '00000000-0000-4000-8000-000000000188';
  v_client bigint;
  v_person bigint;
  v_person_after_receipt bigint;
  v_order bigint;
  v_assignment bigint;
  v_assignment_after_receipt bigint;
  v_receipt bigint;
  v_allocation bigint;
  v_request uuid;
  v_request_after_receipt uuid;
  v_prepare jsonb;
  v_prepare_retry jsonb;
  v_confirm jsonb;
  v_confirm_retry jsonb;
begin
  if has_function_privilege(
    'authenticated',
    'public.definir_com_pedido_comissao(bigint,bigint,text,numeric,text)',
    'EXECUTE'
  ) then
    raise exception 'authenticated retained unkeyed commission assignment';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.definir_com_pedido_comissao_idempotente(uuid,bigint,bigint,text,numeric,text)',
    'EXECUTE'
  ) then
    raise exception 'authenticated retained legacy one-step keyed commission assignment';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.propor_com_pedido_comissao(bigint,bigint,text,numeric,text)',
    'EXECUTE'
  ) then
    raise exception 'authenticated can bypass keyed commission proposal';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.confirmar_com_pedido_comissao(uuid)',
    'EXECUTE'
  ) then
    raise exception 'authenticated can bypass idempotent commission confirmation';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.propor_com_pedido_comissao_idempotente(uuid,bigint,bigint,text,numeric,text)',
    'EXECUTE'
  ) then
    raise exception 'authenticated cannot execute keyed commission proposal';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.confirmar_com_pedido_comissao_idempotente(uuid)',
    'EXECUTE'
  ) then
    raise exception 'authenticated cannot execute idempotent commission confirmation';
  end if;

  if has_function_privilege(
    'anon',
    'public.propor_com_pedido_comissao_idempotente(uuid,bigint,bigint,text,numeric,text)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'public.confirmar_com_pedido_comissao_idempotente(uuid)',
    'EXECUTE'
  ) then
    raise exception 'anon can mutate order commissions';
  end if;

  if has_table_privilege('authenticated','public.com_pedido_comissionados','INSERT')
     or has_table_privilege('authenticated','public.com_pedido_comissionados','UPDATE')
     or has_table_privilege('authenticated','public.com_comissao_alteracao_solicitacoes','INSERT')
     or has_table_privilege('authenticated','public.com_comissao_alteracao_solicitacoes','UPDATE') then
    raise exception 'authenticated can bypass governed commission writes';
  end if;

  insert into auth.users(id)
  values (v_actor),(v_denied)
  on conflict (id) do nothing;

  insert into public.user_profiles(id,display_name,role,status)
  values
    (v_actor,'Commission Assignment Actor','admin','active'),
    (v_denied,'Commission Assignment Denied','auditoria','active')
  on conflict (id) do update set status='active';

  insert into public.user_permission_overrides(user_id,action_key,allowed,updated_by)
  values
    (v_actor,'pedidos.commissions.assign',true,v_actor),
    (v_actor,'financeiro.commissions.revision.request',true,v_actor),
    (v_actor,'financeiro.commissions.revision.confirm',true,v_actor),
    (v_actor,'financeiro.commissions.release',true,v_actor),
    (v_actor,'system.admin',true,v_actor),
    (v_denied,'financeiro.commissions.revision.request',true,v_actor),
    (v_denied,'pedidos.commissions.assign',false,v_actor)
  on conflict (user_id,action_key)
  do update set allowed=excluded.allowed,updated_by=excluded.updated_by;

  perform set_config('request.jwt.claim.sub',v_actor::text,true);
  if public.current_system_environment()='unconfigured' then
    perform public.set_system_runtime_environment(
      'test',
      'test_reset',
      'order commission double confirmation smoke'
    );
  end if;

  insert into public.cad_clientes(
    nome,nome_norm,cidade,uf,status,created_by,updated_by
  )
  values (
    'Cliente 0088','cliente 0088','Barretos','SP','active',v_actor,v_actor
  )
  returning id into v_client;

  insert into public.cad_pessoas_comerciais(
    nome,nome_norm,papeis_json,status,created_by,updated_by
  )
  values (
    'Agente 0088','agente 0088','["agente"]','active',v_actor,v_actor
  )
  returning id into v_person;

  insert into public.com_pedidos(
    codigo_pedido,cliente_id,tipo_pedido,status,data_pedido,valor_total,created_by,updated_by
  )
  values (
    'PED-0088',v_client,'venda','open',current_date,1000,v_actor,v_actor
  )
  returning id into v_order;

  perform set_config('request.jwt.claim.sub',v_denied::text,true);
  begin
    perform public.propor_com_pedido_comissao_idempotente(
      '00000000-0000-4000-8000-000000000188',
      v_order,
      v_person,
      'agente',
      2,
      'Tentativa sem alcada'
    );
    raise exception 'denied actor prepared commission change';
  exception when others then
    if sqlerrm <> 'not allowed: pedidos.commissions.assign' then
      raise;
    end if;
  end;

  perform set_config('request.jwt.claim.sub',v_actor::text,true);

  v_prepare := public.propor_com_pedido_comissao_idempotente(
    '00000000-0000-4000-8000-000000000088',
    v_order,
    v_person,
    'agente',
    2.5,
    'Atribuicao comercial aprovada'
  );
  v_request := nullif(v_prepare->>'solicitacao_id','')::uuid;

  if v_request is null
     or v_prepare->>'status' <> 'pending'
     or (v_prepare#>>'{preview,percentual_comissao}')::numeric <> 2.5
     or (v_prepare#>>'{preview,valor_previsto}')::numeric <> 25
     or (v_prepare#>>'{preview,valor_recebido_ativo}')::numeric <> 0
     or (v_prepare#>>'{preview,valor_liberavel_imediato_estimado}')::numeric <> 0 then
    raise exception 'commission proposal preview is incorrect';
  end if;

  if exists (
    select 1
      from public.com_pedido_comissionados
     where pedido_id=v_order
       and pessoa_id=v_person
       and papel_comissao='agente'
       and status not in ('cancelada','estornada')
  ) then
    raise exception 'commission proposal created a right before confirmation';
  end if;

  v_prepare_retry := public.propor_com_pedido_comissao_idempotente(
    '00000000-0000-4000-8000-000000000088',
    v_order,
    v_person,
    'agente',
    2.5,
    'Atribuicao comercial aprovada'
  );
  if nullif(v_prepare_retry->>'solicitacao_id','')::uuid <> v_request then
    raise exception 'commission proposal retry did not return the original request';
  end if;

  begin
    perform public.propor_com_pedido_comissao_idempotente(
      '00000000-0000-4000-8000-000000000088',
      v_order,
      v_person,
      'agente',
      3,
      'Atribuicao comercial aprovada'
    );
    raise exception 'commission request key accepted a different payload';
  exception when others then
    if sqlerrm <> 'commission request key reused with different payload' then
      raise;
    end if;
  end;

  if not exists (
    select 1
      from public.action_logs
     where entity_type='com_comissao_alteracao_solicitacoes'
       and entity_id=v_request::text
       and action_key='financeiro.commissions.revision.request'
       and metadata_json->>'double_confirmation_step'='1'
  ) then
    raise exception 'commission proposal audit is missing';
  end if;

  v_confirm := public.confirmar_com_pedido_comissao_idempotente(v_request);
  v_assignment := nullif(v_confirm->>'comissionado_id','')::bigint;

  if v_assignment is null or v_confirm->>'status' <> 'confirmed' then
    raise exception 'commission confirmation did not create the assignment';
  end if;

  if not exists (
    select 1
      from public.com_pedido_comissionados
     where id=v_assignment
       and pedido_id=v_order
       and pessoa_id=v_person
       and papel_comissao='agente'
       and percentual_comissao=2.5
       and valor_base=1000
       and valor_previsto=25
       and status='prevista'
       and origem_comissao='manual_adicional'
       and justificativa_registro='Atribuicao comercial aprovada'
  ) then
    raise exception 'confirmed commission assignment was not calculated correctly';
  end if;

  if not exists (
    select 1
      from public.com_comissao_alteracao_solicitacoes
     where id=v_request
       and status='confirmed'
       and comissionado_id=v_assignment
       and confirmed_by=v_actor
  ) then
    raise exception 'commission request was not marked confirmed';
  end if;

  if not exists (
    select 1
      from public.action_logs
     where entity_type='com_comissao_alteracao_solicitacoes'
       and entity_id=v_request::text
       and action_key='financeiro.commissions.revision.confirm'
       and metadata_json->>'double_confirmation_step'='2'
  ) then
    raise exception 'commission confirmation audit is missing';
  end if;

  v_confirm_retry := public.confirmar_com_pedido_comissao_idempotente(v_request);
  if nullif(v_confirm_retry->>'comissionado_id','')::bigint <> v_assignment
     or coalesce((v_confirm_retry->>'idempotent_replay')::boolean,false) is not true then
    raise exception 'commission confirmation retry was not idempotent';
  end if;

  insert into public.com_recebimentos(
    pedido_id,cliente_id,valor_recebido,data_recebimento,status,correlation_id,created_by
  )
  values (
    v_order,v_client,100,current_date,'active','commission-smoke-0088',v_actor
  )
  returning id into v_receipt;

  insert into public.fin_recebimento_alocacoes(
    recebimento_id,pedido_id,valor_alocado,tipo_alocacao,origem,memoria_calculo_json,created_by
  )
  values (
    v_receipt,v_order,100,'recebimento','pedido',
    '{"source":"order_commission_assignment_smoke"}'::jsonb,
    v_actor
  )
  returning id into v_allocation;

  insert into public.cad_pessoas_comerciais(
    nome,nome_norm,papeis_json,status,created_by,updated_by
  )
  values (
    'Agente Pos Recebimento 0088',
    'agente pos recebimento 0088',
    '["agente"]',
    'active',
    v_actor,
    v_actor
  )
  returning id into v_person_after_receipt;

  v_prepare := public.propor_com_pedido_comissao_idempotente(
    '00000000-0000-4000-8000-000000000091',
    v_order,
    v_person_after_receipt,
    'agente',
    2.5,
    'Inclusao aprovada apos recebimento'
  );
  v_request_after_receipt := nullif(v_prepare->>'solicitacao_id','')::uuid;

  if v_request_after_receipt is null
     or (v_prepare#>>'{preview,valor_recebido_ativo}')::numeric <> 100
     or (v_prepare#>>'{preview,valor_previsto}')::numeric <> 25
     or (v_prepare#>>'{preview,valor_liberavel_imediato_estimado}')::numeric <> 2.5 then
    raise exception 'post-receipt commission preview is incorrect';
  end if;

  v_confirm := public.confirmar_com_pedido_comissao_idempotente(
    v_request_after_receipt
  );
  v_assignment_after_receipt := nullif(v_confirm->>'comissionado_id','')::bigint;

  if v_assignment_after_receipt is null
     or (v_confirm->>'liberacoes_recebimentos_existentes')::integer <> 1 then
    raise exception 'post-receipt commission confirmation did not release existing receipt';
  end if;

  if not exists (
    select 1
      from public.com_pedido_comissionados
     where id=v_assignment_after_receipt
       and pedido_id=v_order
       and pessoa_id=v_person_after_receipt
       and percentual_comissao=2.5
       and valor_previsto=25
       and status='liberada'
       and origem_comissao='manual_adicional'
  ) then
    raise exception 'post-receipt participant was not created correctly';
  end if;

  if not exists (
    select 1
      from public.com_comissao_liberacoes
     where alocacao_id=v_allocation
       and comissionado_id=v_assignment_after_receipt
       and valor_liberado=2.5
       and status='liberada'
       and memoria_calculo_json->>'modelo_calculo'='novo_participante_pos_recebimento'
  ) then
    raise exception 'existing receipt was not released proportionally for the new participant';
  end if;

  if not exists (
    select 1
      from public.fin_comissao_movimentos movement
      join public.com_comissao_liberacoes release
        on release.id=movement.liberacao_id
     where release.alocacao_id=v_allocation
       and release.comissionado_id=v_assignment_after_receipt
       and movement.tipo_movimento='credito_liberacao'
       and movement.valor=2.5
  ) then
    raise exception 'post-receipt commission current-account movement is missing';
  end if;
end;
$$;

rollback;
select 'PG_ORDER_COMMISSION_ASSIGNMENT_OK' as result;
