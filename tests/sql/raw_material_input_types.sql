\set ON_ERROR_STOP on

begin;

do $input_types$
declare
  v_actor uuid := '00000000-0000-4000-8000-000000000063';
  v_type_id bigint;
  v_material_id bigint;
  v_summary record;
begin
  insert into auth.users(id) values (v_actor) on conflict (id) do nothing;
  insert into public.user_profiles(id, display_name, role, status)
  values (v_actor, 'Input Type Smoke Actor', 'admin', 'active')
  on conflict (id) do update set display_name = excluded.display_name, role = excluded.role, status = excluded.status;

  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  select v_actor, action.action_key, true, v_actor from public.permission_actions action
  on conflict (user_id, action_key) do update set allowed = true, updated_by = excluded.updated_by;

  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  perform public.set_system_runtime_environment(
    'test', 'test_reset', 'Smoke transacional da migration 0063'
  );
  if public.current_system_environment() <> 'test' then
    raise exception 'input type smoke requires test environment';
  end if;

  v_type_id := public.create_cad_tipo_insumo(
    'SMOKE-LIQ', 'Líquido de teste', 'Somente validação transacional', 'pending_review', 10, 'Smoke 0063'
  );
  perform public.activate_cad_tipo_insumo(v_type_id, 'Aprovação no smoke');

  begin
    perform public.create_cad_tipo_insumo('SMOKE-LIQ-2', 'Líquido de teste', null, 'active', 20, 'Duplicidade');
    raise exception 'normalized duplicate name was accepted';
  exception when unique_violation then null;
  end;

  v_material_id := public.create_cad_materia_prima_governada(
    'Matéria-prima Smoke 0063', 'MATERIA PRIMA SMOKE 0063', 'MP-SMOKE-0063', 'KG',
    null, 'active', null, null, 0, null, null, null, '{}'::jsonb
  );

  if not exists (
    select 1 from public.cad_materias_primas
    where id = v_material_id and tipo_insumo_id is null
      and tipo_insumo_review_status = 'pending_review' and tipo is null
  ) then raise exception 'unclassified material was not preserved as pending review'; end if;

  perform public.set_cad_materia_prima_tipo(v_material_id, v_type_id, 'Classificação manual no smoke');
  if not exists (
    select 1 from public.cad_materias_primas
    where id = v_material_id and tipo_insumo_id = v_type_id
      and tipo_insumo_review_status = 'approved' and tipo_insumo_source = 'manual_governado'
  ) then raise exception 'governed material link was not persisted'; end if;

  begin
    perform public.set_cad_materia_prima_tipo(v_material_id, 999999999, 'ID inexistente');
    raise exception 'missing input type was accepted';
  exception when others then
    if sqlerrm <> 'active input type not found' then raise; end if;
  end;

  if not exists (
    select 1 from public.action_logs
    where entity_type = 'cad_materias_primas' and entity_id = v_material_id::text
      and action_key = 'cadastros.materias_primas.update.input_type'
      and before_json is not null and after_json is not null
  ) then raise exception 'material classification audit was not recorded'; end if;

  perform public.deactivate_cad_tipo_insumo(v_type_id, 'Inativação no smoke');
  begin
    delete from public.cad_tipos_insumo where id = v_type_id;
    raise exception 'physical deletion was accepted';
  exception when others then
    if sqlerrm not like '%append-preserved%' then raise; end if;
  end;

  select * into v_summary from public.cad_materias_primas_tipos_resumo;
  if v_summary.classificadas_por_inferencia <> 0 then raise exception 'inferred classification count must be zero'; end if;
end;
$input_types$;

set local role anon;
select set_config('request.jwt.claim.sub', '', true);

do $$
begin
  perform public.create_cad_tipo_insumo('ANON', 'Anônimo', null, 'active', 1, 'Negado');
  raise exception 'anonymous RPC execution was accepted';
exception
  when insufficient_privilege then null;
  when others then
    if sqlerrm not like '%active user profile required%' and sqlerrm not like '%permission denied%' then raise; end if;
end;
$$;

rollback;

select 'PG_VALIDATE_0063_WITH_SMOKE_OK' as result;
