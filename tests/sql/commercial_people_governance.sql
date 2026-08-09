\set ON_ERROR_STOP on

begin;

do $people_governance$
declare
  v_actor uuid := '00000000-0000-4000-8000-000000000065';
  v_person_one bigint;
  v_person_two bigint;
  v_area_id bigint;
  v_link_one bigint;
  v_link_two bigint;
  v_candidates bigint[];
begin
  insert into auth.users(id) values (v_actor) on conflict (id) do nothing;
  insert into public.user_profiles(id, display_name, role, status)
  values (v_actor, 'People Governance Smoke Actor', 'admin', 'active')
  on conflict (id) do update set display_name = excluded.display_name, role = excluded.role, status = excluded.status;
  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  select v_actor, action.action_key, true, v_actor from public.permission_actions action
  on conflict (user_id, action_key) do update set allowed = true, updated_by = excluded.updated_by;
  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  perform public.set_system_runtime_environment('test', 'test_reset', 'Smoke transacional da migration 0065');

  insert into public.cad_areas_comerciais(nome, nome_norm, status, created_by, updated_by)
  values ('Area sintetica 0065', 'AREA SINTETICA 0065', 'active', v_actor, v_actor)
  returning id into v_area_id;

  v_person_one := public.create_cad_pessoa_comercial(
    p_nome => 'Joao Homonimo 0065',
    p_nome_norm => 'JOAO HOMONIMO 0065',
    p_papeis_json => '["vendedor"]'::jsonb,
    p_codigo_legado => 'P-0065-A',
    p_tipo_comercial => 'vendedor_direto_elite',
    p_apelidos_json => '["Tico 0065"]'::jsonb,
    p_grafias_incorretas_json => '["Joao Homnimo 0065"]'::jsonb
  );

  begin
    perform public.create_cad_pessoa_comercial(
      p_nome => 'Joao Homonimo 0065', p_nome_norm => 'JOAO HOMONIMO 0065',
      p_papeis_json => '["vendedor"]'::jsonb, p_codigo_legado => 'P-0065-B',
      p_tipo_comercial => 'vendedor_direto_elite'
    );
    raise exception 'same name without confirmation was accepted';
  exception when others then
    if sqlerrm <> 'possible commercial person duplicate requires confirmation' then raise; end if;
  end;

  select array_agg(candidate.pessoa_id order by candidate.pessoa_id)
    into v_candidates
    from public.find_cad_pessoa_possible_duplicates(
      'Joao Homonimo 0065', 'P-0065-B', '["Tico 0065"]'::jsonb,
      '[]'::jsonb, null, '["vendedor"]'::jsonb
    ) candidate;

  begin
    perform public.create_cad_pessoa_comercial(
      p_nome => 'Joao Homonimo 0065', p_nome_norm => 'JOAO HOMONIMO 0065',
      p_papeis_json => '["vendedor"]'::jsonb, p_codigo_legado => 'P-0065-B',
      p_tipo_comercial => 'vendedor_direto_elite', p_apelidos_json => '["Tico 0065"]'::jsonb,
      p_confirmar_possivel_duplicidade => true, p_motivo_duplicidade => 'curto',
      p_candidatos_apresentados => v_candidates
    );
    raise exception 'duplicate confirmation without sufficient reason was accepted';
  exception when others then
    if sqlerrm <> 'duplicate confirmation reason must have at least 10 characters' then raise; end if;
  end;

  v_person_two := public.create_cad_pessoa_comercial(
    p_nome => 'Joao Homonimo 0065', p_nome_norm => 'JOAO HOMONIMO 0065',
    p_papeis_json => '["vendedor"]'::jsonb, p_codigo_legado => 'P-0065-B',
    p_tipo_comercial => 'vendedor_direto_elite', p_apelidos_json => '["Tico 0065"]'::jsonb,
    p_confirmar_possivel_duplicidade => true,
    p_motivo_duplicidade => 'Pessoa distinta confirmada pelo operador do teste',
    p_candidatos_apresentados => v_candidates
  );

  if not exists (
    select 1 from public.cad_pessoa_aliases
     where pessoa_id = v_person_one and alias_norm = public.normalize_catalog_term('Tico 0065')
  ) or not exists (
    select 1 from public.cad_pessoa_aliases
     where pessoa_id = v_person_two and alias_norm = public.normalize_catalog_term('Tico 0065')
  ) then raise exception 'same alias across distinct people was not preserved'; end if;

  begin
    perform public.create_cad_pessoa_comercial(
      p_nome => 'Alias repetido 0065', p_nome_norm => 'ALIAS REPETIDO 0065',
      p_papeis_json => '["agente"]'::jsonb, p_codigo_legado => 'P-0065-C',
      p_tipo_comercial => 'agente_direto_elite', p_apelidos_json => '["Mesmo alias","mesmo alias"]'::jsonb
    );
    raise exception 'same alias repeated within one person was accepted';
  exception when others then
    if sqlerrm <> 'alias repeated within the same person' then raise; end if;
  end;

  begin
    perform public.create_cad_pessoa_comercial(
      p_nome => 'Codigo repetido 0065', p_nome_norm => 'CODIGO REPETIDO 0065',
      p_papeis_json => '["vendedor"]'::jsonb, p_codigo_legado => 'p 0065 a',
      p_tipo_comercial => 'vendedor_direto_elite',
      p_confirmar_possivel_duplicidade => true,
      p_motivo_duplicidade => 'Tentativa que deve ser bloqueada pelo codigo',
      p_candidatos_apresentados => array[v_person_one]
    );
    raise exception 'normalized duplicate legacy code was accepted';
  exception when others then
    if sqlerrm <> 'normalized legacy code already exists' then raise; end if;
  end;

  if not exists (
    select 1 from public.action_logs
     where action_key = 'cadastros.pessoas.create'
       and metadata_json->>'possible_duplicate_confirmed' = 'true'
       and metadata_json->>'duplicate_reason' = 'Pessoa distinta confirmada pelo operador do teste'
  ) then raise exception 'confirmed homonym was not audited'; end if;

  v_link_one := public.link_cad_pessoa_area_comercial(
    v_person_one, v_area_id, 'vendedor', date '2026-01-01', 'Vinculo inicial para o teste 0065'
  );
  begin
    perform public.link_cad_pessoa_area_comercial(
      v_person_one, v_area_id, 'vendedor', date '2026-02-01', 'Sobreposicao proposital do teste'
    );
    raise exception 'overlapping active area membership was accepted';
  exception when others then
    if sqlerrm <> 'active commercial area membership overlaps an existing period' then raise; end if;
  end;

  perform public.close_cad_pessoa_area_comercial(
    v_link_one, date '2026-03-31', 'Encerramento controlado do vinculo'
  );
  v_link_two := public.link_cad_pessoa_area_comercial(
    v_person_one, v_area_id, 'vendedor', date '2026-04-01', 'Nova vigencia depois do encerramento'
  );
  if v_link_two = v_link_one then raise exception 'new area period reused historical membership'; end if;

  perform public.close_cad_pessoa_area_comercial(
    v_link_two, date '2026-04-30', 'Encerramento antes da reativacao'
  );
  perform public.deactivate_cad_pessoa_comercial(v_person_one, 'Desativacao controlada para teste');
  perform public.reactivate_cad_pessoa_comercial(v_person_one, 'Reativacao controlada para teste');
  if not exists (select 1 from public.cad_pessoas_comerciais where id = v_person_one and status = 'active') then
    raise exception 'commercial person was not reactivated';
  end if;
  if exists (select 1 from public.cad_pessoa_areas_comerciais where id in (v_link_one, v_link_two) and status = 'active') then
    raise exception 'reactivation reopened historical area memberships';
  end if;
end;
$people_governance$;

do $denied_user$
declare
  v_actor uuid := '00000000-0000-4000-8000-000000000165';
begin
  insert into auth.users(id) values (v_actor) on conflict (id) do nothing;
  insert into public.user_profiles(id, display_name, role, status)
  values (v_actor, 'People Governance Denied Actor', 'auditoria', 'active')
  on conflict (id) do update set status = 'active';
  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  values (v_actor, 'cadastros.pessoas.candidates.read', false, v_actor)
  on conflict (user_id, action_key) do update set allowed = false;
  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  begin
    perform public.find_cad_pessoa_possible_duplicates('Negado 0065', null, '[]'::jsonb, '[]'::jsonb, null, '[]'::jsonb);
    raise exception 'user without candidate permission was accepted';
  exception when others then
    if sqlerrm not like '%not allowed: cadastros.pessoas.candidates.read%' then raise; end if;
  end;
end;
$denied_user$;

do $privileges$
begin
  if has_function_privilege('anon', 'public.find_cad_pessoa_possible_duplicates(text,text,jsonb,jsonb,bigint,jsonb)', 'EXECUTE') then
    raise exception 'anon retained person duplicate finder execution';
  end if;
  if has_function_privilege('anon', 'public.link_cad_pessoa_area_comercial(bigint,bigint,text,date,text)', 'EXECUTE') then
    raise exception 'anon retained area link execution';
  end if;
  if has_function_privilege('anon', 'public.reactivate_cad_pessoa_comercial(bigint,text)', 'EXECUTE') then
    raise exception 'anon retained reactivation execution';
  end if;
  if has_table_privilege('authenticated', 'public.cad_pessoa_areas_comerciais', 'INSERT,UPDATE,DELETE') then
    raise exception 'authenticated retained direct area membership writes';
  end if;
end;
$privileges$;

set local role anon;
select set_config('request.jwt.claim.sub', '', true);
do $$
begin
  perform public.reactivate_cad_pessoa_comercial(1, 'Tentativa anonima proibida');
  raise exception 'anonymous reactivation was accepted';
exception
  when insufficient_privilege then null;
  when others then
    if sqlerrm not like '%permission denied%' and sqlerrm not like '%active user profile required%' then raise; end if;
end;
$$;

rollback;

select 'PG_VALIDATE_0065_WITH_SMOKE_OK' as result;
