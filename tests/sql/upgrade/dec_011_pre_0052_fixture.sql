do $$
declare
  v_actor uuid := public.historical_migration_actor_id();
  v_client_id bigint;
  v_person_id bigint;
  v_area_id bigint;
begin
  insert into public.cad_clientes(
    nome, nome_norm, cidade, uf, status, apelidos_json, payload_origem_json,
    created_by, updated_by, origem_dados
  ) values (
    'DEC-011 upgrade client', 'dec-011 upgrade client', 'Campinas', 'SP',
    'active', '[]'::jsonb, '{}'::jsonb, v_actor, v_actor, 'sistema'
  ) returning id into v_client_id;

  insert into public.cad_pessoas_comerciais(
    nome, nome_norm, papeis_json, status, payload_origem_json,
    created_by, updated_by, origem_dados
  ) values (
    'DEC-011 upgrade seller', 'dec-011 upgrade seller', '["vendedor"]'::jsonb,
    'active', '{}'::jsonb, v_actor, v_actor, 'sistema'
  ) returning id into v_person_id;

  insert into public.cad_cliente_vendedores(
    cliente_id, pessoa_id, status, vigencia_inicio, created_by, updated_by
  ) values (
    v_client_id, v_person_id, 'active', date '2020-01-01', v_actor, v_actor
  );

  insert into public.cad_areas_comerciais(
    nome, nome_norm, status, created_by, updated_by
  ) values (
    'DEC-011 upgrade area', 'dec-011 upgrade area', 'active', v_actor, v_actor
  ) returning id into v_area_id;

  insert into public.cad_pessoa_areas_comerciais(
    pessoa_id, area_id, papel_area, status, vigencia_inicio,
    created_by, updated_by
  ) values (
    v_person_id, v_area_id, 'vendedor', 'active', date '2020-01-01',
    v_actor, v_actor
  );
end;
$$;
