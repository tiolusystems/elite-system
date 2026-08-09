\set ON_ERROR_STOP on

begin;

do $vehicle_registration$
declare
  v_actor uuid := '00000000-0000-4000-8000-000000000109';
  v_denied_actor uuid := '00000000-0000-4000-8000-000000000110';
  v_vehicle_id bigint;
begin
  insert into auth.users(id) values (v_actor), (v_denied_actor) on conflict (id) do nothing;
  insert into public.user_profiles(id, display_name, role, status)
  values
    (v_actor, 'Vehicle Smoke Actor', 'admin', 'active'),
    (v_denied_actor, 'Vehicle Denied Actor', 'auditoria', 'active')
  on conflict (id) do update set status = excluded.status;

  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  values
    (v_actor, 'cadastros.veiculos.create', true, v_actor),
    (v_actor, 'cadastros.veiculos.status.manage', true, v_actor),
    (v_actor, 'system.admin', true, v_actor)
  on conflict (user_id, action_key) do update set allowed = excluded.allowed, updated_by = excluded.updated_by;

  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  if public.current_system_environment() = 'unconfigured' then
    perform public.set_system_runtime_environment('test', 'test_reset', 'Vehicle governance smoke');
  elsif public.current_system_environment() <> 'test' then
    raise exception 'vehicle smoke requires unconfigured or test environment';
  end if;

  v_vehicle_id := public.create_cad_veiculo_governado(
    'Veiculo HOM-E2E 0109',
    'SMK-0A09',
    'HOM-E2E-0109'
  );

  if not exists (
    select 1
      from public.cad_veiculos
     where id = v_vehicle_id
       and placa_norm = 'SMK0A09'
       and status = 'active'
       and origem_dados = 'sistema'
  ) then
    raise exception 'governed vehicle was not created correctly';
  end if;

  begin
    perform public.create_cad_veiculo_governado('Outro veiculo', ' smk0a09 ', null);
    raise exception 'normalized duplicate plate was accepted';
  exception
    when unique_violation then null;
  end;

  perform public.set_cad_veiculo_active_state(
    v_vehicle_id,
    false,
    'Inativacao controlada no smoke'
  );
  perform public.set_cad_veiculo_active_state(
    v_vehicle_id,
    true,
    'Reativacao controlada no smoke'
  );

  if (
    select count(*)
      from public.action_logs
     where entity_type = 'cad_veiculos'
       and entity_id = v_vehicle_id::text
  ) <> 3 then
    raise exception 'vehicle audit history is incomplete';
  end if;

  perform set_config('request.jwt.claim.sub', v_denied_actor::text, true);
  begin
    perform public.create_cad_veiculo_governado('Veiculo sem alcada', 'DEN-0A09', null);
    raise exception 'user without explicit permission created a vehicle';
  exception
    when others then
      if sqlerrm not like '%not allowed: cadastros.veiculos.create%' then
        raise;
      end if;
  end;

  if has_function_privilege('anon', 'public.create_cad_veiculo_governado(text,text,text)', 'EXECUTE') then
    raise exception 'anon can create vehicles';
  end if;
  if exists (
    select 1
      from pg_proc function_definition
      cross join lateral aclexplode(
        coalesce(
          function_definition.proacl,
          acldefault('f', function_definition.proowner)
        )
      ) privilege
     where function_definition.oid = 'public.set_cad_veiculo_active_state(bigint,boolean,text)'::regprocedure
       and privilege.grantee = 0
       and privilege.privilege_type = 'EXECUTE'
  ) then
    raise exception 'PUBLIC can change vehicle status';
  end if;
end;
$vehicle_registration$;

set local role authenticated;
do $direct_write$
begin
  begin
    insert into public.cad_veiculos(descricao, descricao_norm, placa, placa_norm, status, origem_dados)
    values ('Escrita direta', 'escrita direta', 'DIR-0A09', 'DIR0A09', 'active', 'sistema');
    raise exception 'direct authenticated vehicle write was accepted';
  exception
    when insufficient_privilege then null;
  end;
end;
$direct_write$;
reset role;

rollback;
select 'PG_VEHICLE_REGISTRATION_GOVERNANCE_OK' as result;
