\set ON_ERROR_STOP on

begin;

do $dec011$
declare
  v_migration_actor uuid := public.historical_migration_actor_id();
  v_human_actor uuid := '00000000-0000-4000-8000-000000000752';
  v_workbook_id bigint;
  v_batch_id bigint;
  v_table_id bigint;
  v_source_row_id bigint;
  v_client_id bigint;
  v_property_id bigint;
  v_other_property_id bigint;
  v_seller_id bigint;
  v_area_seller_id bigint;
  v_attends_role_id bigint;
  v_registered_role_id bigint;
  v_direct_link_id bigint;
  v_area_id bigint;
begin
  if v_migration_actor is null then
    raise exception 'DEC-011 smoke requires Migracao Historica actor';
  end if;

  select id into v_attends_role_id
    from public.cad_cliente_vinculo_papeis where codigo_norm = 'atende';
  select id into v_registered_role_id
    from public.cad_cliente_vinculo_papeis where codigo_norm = 'cadastrou';
  if v_attends_role_id is null or v_registered_role_id is null then
    raise exception 'DEC-011 client link roles were not seeded';
  end if;

  if exists (
    select 1 from public.cad_cliente_vinculo_papeis
    where codigo_norm = 'cadastrou' and concede_visibilidade
  ) then
    raise exception 'registration fact must not grant current visibility';
  end if;

  insert into auth.users(id) values (v_human_actor)
  on conflict (id) do nothing;
  insert into public.user_profiles(id, display_name, role, status)
  values (v_human_actor, 'DEC-011 Human Reviewer', 'admin', 'active')
  on conflict (id) do update set
    display_name = excluded.display_name,
    role = excluded.role,
    status = excluded.status,
    is_system_actor = false,
    system_actor_key = null;

  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  values (v_human_actor, 'system.admin', true, v_human_actor)
  on conflict (user_id, action_key) do update set
    allowed = excluded.allowed,
    updated_by = excluded.updated_by;

  perform set_config('request.jwt.claim.sub', v_human_actor::text, true);
  perform public.set_system_runtime_environment(
    'test', 'test_reset', 'Validacao transacional da DEC-011 em PostgreSQL local'
  );

  insert into public.source_workbooks(
    file_name, sha256, size_bytes, metadata_json, created_by
  ) values (
    'dec011-fixture.xlsx', repeat('1', 64), 1100,
    '{"fixture":true}'::jsonb, v_migration_actor
  ) returning id into v_workbook_id;

  insert into public.migration_batches(workbook_id, status, notes, created_by, updated_by)
  values (v_workbook_id, 'running', 'DEC-011 fixture', v_migration_actor, v_migration_actor)
  returning id into v_batch_id;

  insert into public.source_tables(
    workbook_id, sheet_name, table_name, ref, header_row, data_first_row,
    data_last_row, column_count, row_count, metadata_json
  ) values (
    v_workbook_id, 'Clientes', 'DEC011Fixture', 'A1:F2', 1, 2, 2, 6, 1, '{}'::jsonb
  ) returning id into v_table_id;

  insert into public.source_rows(
    table_id, excel_row_number, row_index, row_hash, payload_json, formulas_json
  ) values (
    v_table_id, 2, 0, repeat('2', 64), '{"fixture":true}'::jsonb, '{}'::jsonb
  ) returning id into v_source_row_id;

  insert into public.cad_clientes(
    nome, nome_norm, cidade, uf, status, apelidos_json, payload_origem_json,
    created_by, updated_by, origem_dados
  ) values (
    'Cliente DEC-011', 'cliente dec-011', 'Campinas', 'SP', 'active',
    '[]'::jsonb, '{}'::jsonb, v_human_actor, v_human_actor, 'sistema'
  ) returning id into v_client_id;

  insert into public.cad_cliente_propriedades(
    cliente_id, nome, cidade, uf, status, created_by, updated_by
  ) values (
    v_client_id, 'Fazenda A', 'Campinas', 'SP', 'active', v_human_actor, v_human_actor
  ) returning id into v_property_id;

  insert into public.cad_cliente_propriedades(
    cliente_id, nome, cidade, uf, status, created_by, updated_by
  ) values (
    v_client_id, 'Fazenda B', 'Campinas', 'SP', 'active', v_human_actor, v_human_actor
  ) returning id into v_other_property_id;

  insert into public.cad_pessoas_comerciais(
    nome, nome_norm, papeis_json, status, payload_origem_json,
    created_by, updated_by, origem_dados
  ) values (
    'Vendedor DEC-011', 'vendedor dec-011', '["vendedor"]'::jsonb,
    'active', '{}'::jsonb, v_human_actor, v_human_actor, 'sistema'
  ) returning id into v_seller_id;

  insert into public.cad_pessoas_comerciais(
    nome, nome_norm, papeis_json, status, payload_origem_json,
    created_by, updated_by, origem_dados
  ) values (
    'Vendedor area DEC-011', 'vendedor area dec-011', '["vendedor"]'::jsonb,
    'active', '{}'::jsonb, v_human_actor, v_human_actor, 'sistema'
  ) returning id into v_area_seller_id;

  insert into public.cad_cliente_vendedores(
    cliente_id, propriedade_id, pessoa_id, papel_vinculo_id, status,
    vigencia_inicio, created_by, updated_by, origem_dados
  ) values (
    v_client_id, v_property_id, v_seller_id, v_attends_role_id, 'active',
    current_date, v_human_actor, v_human_actor, 'sistema'
  ) returning id into v_direct_link_id;

  if not exists (
    select 1 from public.cad_cliente_visibilidade_comercial_atual visibility
    where visibility.cliente_id = v_client_id
      and visibility.propriedade_id = v_property_id
      and visibility.pessoa_id = v_seller_id
      and visibility.origem_visibilidade = 'vinculo_direto'
  ) then
    raise exception 'active direct client/seller link did not grant relational visibility';
  end if;

  begin
    insert into public.cad_cliente_vendedores(
      cliente_id, propriedade_id, pessoa_id, papel_vinculo_id, status,
      vigencia_inicio, created_by, updated_by, origem_dados
    ) values (
      v_client_id, v_property_id, v_seller_id, v_attends_role_id, 'active',
      current_date, v_human_actor, v_human_actor, 'sistema'
    );
    raise exception 'overlapping active client/seller link was accepted';
  exception when others then
    if sqlerrm <> 'active client/seller link overlaps an existing period' then
      raise;
    end if;
  end;

  insert into public.cad_cliente_vendedores(
    cliente_id, pessoa_id, papel_vinculo_id, status, vigencia_inicio,
    created_by, updated_by, origem_dados, source_batch_id, source_row_id
  ) values (
    v_client_id, v_seller_id, v_registered_role_id, 'pending_review', null,
    v_migration_actor, v_migration_actor, 'excel_legado', v_batch_id, v_source_row_id
  );

  if exists (
    select 1 from public.cad_cliente_vinculos_atuais current_link
    where current_link.cliente_id = v_client_id
      and current_link.pessoa_id = v_seller_id
      and current_link.papel_codigo = 'cadastrou'
  ) then
    raise exception 'historical pending registration link reached current view';
  end if;

  begin
    insert into public.cad_cliente_vendedores(
      cliente_id, pessoa_id, papel_vinculo_id, status,
      created_by, updated_by, origem_dados, source_batch_id, source_row_id
    ) values (
      v_client_id, v_seller_id, v_registered_role_id, 'active',
      v_migration_actor, v_migration_actor, 'excel_legado', v_batch_id, v_source_row_id
    );
    raise exception 'historical link was promoted during insert';
  exception when others then
    if sqlerrm not like 'excel_legado requires status = pending_review%' then
      raise;
    end if;
  end;

  insert into public.cad_areas_comerciais(
    nome, nome_norm, status, created_by, updated_by, origem_dados
  ) values (
    'Regiao DEC-011', 'regiao dec-011', 'active',
    v_human_actor, v_human_actor, 'sistema'
  ) returning id into v_area_id;

  insert into public.cad_pessoa_areas_comerciais(
    pessoa_id, area_id, papel_area, status, vigencia_inicio,
    created_by, updated_by, origem_dados
  ) values (
    v_area_seller_id, v_area_id, 'vendedor', 'active', current_date,
    v_human_actor, v_human_actor, 'sistema'
  );

  insert into public.cad_cliente_areas_comerciais(
    cliente_id, area_id, status, vigencia_inicio,
    created_by, updated_by, origem_dados
  ) values (
    v_client_id, v_area_id, 'active', current_date,
    v_human_actor, v_human_actor, 'sistema'
  );

  if not exists (
    select 1 from public.cad_cliente_visibilidade_comercial_atual visibility
    where visibility.cliente_id = v_client_id
      and visibility.pessoa_id = v_area_seller_id
      and visibility.origem_visibilidade = 'area_comercial'
  ) then
    raise exception 'area link did not produce relational visibility';
  end if;

  insert into public.com_pedidos(
    codigo_pedido, cliente_id, propriedade_id, vendedor_gerador_id,
    cliente_vendedor_vinculo_id, tipo_pedido, status, data_pedido,
    origem_canal, valor_total, created_by, updated_by, origem_dados
  ) values (
    'DEC011-PED', v_client_id, v_property_id, v_seller_id,
    v_direct_link_id, 'venda', 'draft', current_date,
    'interno', 0, v_human_actor, v_human_actor, 'sistema'
  );

  begin
    insert into public.com_pedidos(
      codigo_pedido, cliente_id, propriedade_id, vendedor_gerador_id,
      cliente_vendedor_vinculo_id, tipo_pedido, status, data_pedido,
      origem_canal, valor_total, created_by, updated_by, origem_dados
    ) values (
      'DEC011-PED-BAD', v_client_id, v_other_property_id, v_seller_id,
      v_direct_link_id, 'venda', 'draft', current_date,
      'interno', 0, v_human_actor, v_human_actor, 'sistema'
    );
    raise exception 'order used a client/seller link from another property';
  exception when others then
    if sqlerrm <> 'order property is outside the selected client/seller link' then
      raise;
    end if;
  end;

  begin
    delete from public.cad_cliente_vendedores where id = v_direct_link_id;
    raise exception 'temporal client/seller link was physically deleted';
  exception when others then
    if sqlerrm not like 'cad_cliente_vendedores is historical%' then
      raise;
    end if;
  end;
end;
$dec011$;

rollback;

select 'DEC_011_CLIENT_SELLER_TEMPORAL_LINKS_SMOKE_OK' as result;
