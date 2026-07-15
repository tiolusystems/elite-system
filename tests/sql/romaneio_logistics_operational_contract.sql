\set ON_ERROR_STOP on

begin;

do $romaneio_logistics_operational$
declare
  v_actor uuid := '00000000-0000-4000-8000-000000000059';
  v_denied_actor uuid := '00000000-0000-4000-8000-000000000159';
  v_client_id bigint;
  v_order_id bigint;
  v_romaneio_id bigint;
  v_delivery_person_id bigint;
  v_vehicle_id bigint;
  v_event_id bigint;
  v_event_count integer;
begin
  if not has_function_privilege(
    'authenticated',
    'public.registrar_exp_romaneio_logistica_atribuicao(bigint,bigint,bigint,text)',
    'EXECUTE'
  ) then
    raise exception 'authenticated cannot execute logistics assignment RPC';
  end if;
  if has_function_privilege(
    'anon',
    'public.registrar_exp_romaneio_logistica_atribuicao(bigint,bigint,bigint,text)',
    'EXECUTE'
  ) then
    raise exception 'anon can execute logistics assignment RPC';
  end if;
  if has_table_privilege('authenticated', 'public.exp_romaneio_logistica_eventos', 'INSERT') then
    raise exception 'authenticated can insert logistics events directly';
  end if;

  insert into auth.users(id) values (v_actor), (v_denied_actor)
  on conflict (id) do nothing;

  insert into public.user_profiles(id, display_name, role, status)
  values
    (v_actor, 'Romaneio Logistics Smoke Actor', 'admin', 'active'),
    (v_denied_actor, 'Romaneio Logistics Denied Actor', 'expedicao', 'active')
  on conflict (id) do update set
    display_name = excluded.display_name,
    role = excluded.role,
    status = excluded.status;

  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  select v_actor, action.action_key, true, v_actor
    from public.permission_actions action
  on conflict (user_id, action_key) do update set
    allowed = excluded.allowed,
    updated_by = excluded.updated_by;

  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  values
    (v_denied_actor, 'romaneios.logistics.assign', false, v_actor),
    (v_denied_actor, 'romaneios.logistics.remove', false, v_actor)
  on conflict (user_id, action_key) do update set
    allowed = excluded.allowed,
    updated_by = excluded.updated_by;

  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  if public.current_system_environment() = 'unconfigured' then
    perform public.set_system_runtime_environment(
      'test', 'test_reset', 'Smoke 0059 de logistica operacional do romaneio'
    );
  elsif public.current_system_environment() <> 'test' then
    raise exception 'romaneio logistics smoke requires unconfigured or test environment';
  end if;

  insert into public.cad_clientes(
    nome, nome_norm, cidade, uf, status, apelidos_json, payload_origem_json,
    created_by, updated_by, origem_dados
  ) values (
    'Cliente Smoke 0059', 'cliente smoke 0059', 'Campinas', 'SP', 'active',
    '[]'::jsonb, '{}'::jsonb, v_actor, v_actor, 'sistema'
  ) returning id into v_client_id;

  insert into public.com_pedidos(
    codigo_pedido, cliente_id, tipo_pedido, status, data_pedido,
    origem_canal, valor_total, created_by, updated_by, origem_dados
  ) values (
    'SMOKE-0059-PED', v_client_id, 'venda', 'open', current_date,
    'interno', 0, v_actor, v_actor, 'sistema'
  ) returning id into v_order_id;

  insert into public.exp_romaneios(
    codigo_romaneio, pedido_id, tipo_separacao, status, data_romaneio,
    created_by, updated_by, review_status, origem_dados
  ) values (
    'SMOKE-0059-ROM', v_order_id, 'parcial', 'draft', current_date,
    v_actor, v_actor, 'approved', 'sistema'
  ) returning id into v_romaneio_id;

  insert into public.cad_pessoas_comerciais(
    nome, nome_norm, papeis_json, status, payload_origem_json,
    created_by, updated_by, origem_dados
  ) values (
    'Entregador Smoke 0059', 'entregador smoke 0059', '["entregador"]'::jsonb,
    'active', '{}'::jsonb, v_actor, v_actor, 'sistema'
  ) returning id into v_delivery_person_id;

  insert into public.cad_veiculos(
    descricao, descricao_norm, placa, placa_norm, status,
    created_by, updated_by, origem_dados
  ) values (
    'Veiculo Smoke 0059', 'veiculo smoke 0059', 'SMK0A59', 'SMK0A59', 'active',
    v_actor, v_actor, 'sistema'
  ) returning id into v_vehicle_id;

  if not exists (
    select 1
      from public.cad_pessoa_papeis papel
     where papel.pessoa_id = v_delivery_person_id
       and papel.papel = 'entregador'
       and papel.status = 'active'
  ) then
    raise exception 'delivery role was not normalized relationally';
  end if;

  perform set_config('request.jwt.claim.sub', v_denied_actor::text, true);
  begin
    perform public.registrar_exp_romaneio_logistica_atribuicao(null, null, null, null);
    raise exception 'zero-grant actor reached input validation';
  exception when others then
    if sqlerrm <> 'not allowed: romaneios.logistics.assign' then
      raise;
    end if;
  end;

  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  v_event_id := public.registrar_exp_romaneio_logistica_atribuicao(
    v_romaneio_id,
    v_delivery_person_id,
    v_vehicle_id,
    'Separacao programada'
  );

  if not exists (
    select 1
      from public.exp_romaneio_logistica_atual atual
     where atual.romaneio_id = v_romaneio_id
       and atual.entregador_id = v_delivery_person_id
       and atual.veiculo_id = v_vehicle_id
       and atual.evento_id = v_event_id
  ) then
    raise exception 'assignment did not reach current logistics view';
  end if;

  if not exists (
    select 1
      from public.action_logs log
     where log.entity_type = 'exp_romaneios'
       and log.entity_id = v_romaneio_id::text
       and log.action_key = 'romaneios.logistics.assign'
       and log.after_json->>'evento_id' = v_event_id::text
       and log.metadata_json->>'correlation_id' = format('romaneio:%s:logistics', v_romaneio_id)
  ) then
    raise exception 'assignment audit log was not recorded';
  end if;

  begin
    perform public.registrar_exp_romaneio_logistica_atribuicao(
      v_romaneio_id, v_delivery_person_id, v_vehicle_id, null
    );
    raise exception 'duplicate active assignment was accepted';
  exception when others then
    if sqlerrm <> 'logistics assignment already active' then
      raise;
    end if;
  end;

  v_event_id := public.registrar_exp_romaneio_logistica_remocao(
    v_romaneio_id,
    'Programacao de entrega alterada'
  );

  if exists (
    select 1 from public.exp_romaneio_logistica_atual atual
    where atual.romaneio_id = v_romaneio_id
  ) then
    raise exception 'removal did not clear current logistics view';
  end if;

  if not exists (
    select 1
      from public.action_logs log
     where log.entity_type = 'exp_romaneios'
       and log.entity_id = v_romaneio_id::text
       and log.action_key = 'romaneios.logistics.remove'
       and log.after_json->>'evento_id' = v_event_id::text
  ) then
    raise exception 'removal audit log was not recorded';
  end if;

  select count(*)
    into v_event_count
    from public.exp_romaneio_logistica_eventos event
   where event.romaneio_id = v_romaneio_id;
  if v_event_count <> 2 then
    raise exception 'expected two append-only logistics events, got %', v_event_count;
  end if;

  begin
    update public.exp_romaneio_logistica_eventos
       set motivo = 'Tentativa de sobrescrita'
     where id = v_event_id;
    raise exception 'append-only logistics event was updated';
  exception when others then
    if sqlerrm not like 'exp_romaneio_logistica_eventos is append-only%' then
      raise;
    end if;
  end;
end;
$romaneio_logistics_operational$;

rollback;

select 'PG_VALIDATE_0059_WITH_SMOKE_OK' as result;
