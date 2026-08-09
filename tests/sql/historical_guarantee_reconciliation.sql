begin;

do $$
declare
  v_actor uuid := '00000000-0000-4000-8000-000000000774';
  v_migration_actor uuid := public.historical_migration_actor_id();
  v_workbook_id bigint;
  v_batch_id bigint;
  v_table_id bigint;
  v_row_id bigint;
  v_product_id bigint;
  v_source_id bigint;
  v_nutrient_id bigint;
  v_unit_percent bigint;
  v_unit_kg_l bigint;
  v_operational_before bigint;
  v_event_id bigint;
begin
  if v_migration_actor is null then raise exception 'historical migration actor is required'; end if;

  insert into auth.users(id) values (v_actor) on conflict (id) do nothing;
  insert into public.user_profiles(id, display_name, role, status)
  values (v_actor, 'Guarantee reconciliation reviewer', 'admin', 'active')
  on conflict (id) do update set display_name = excluded.display_name, role = excluded.role, status = excluded.status;
  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  values
    (v_actor, 'system.admin', true, v_actor),
    (v_actor, 'pcp.guarantee.historical.review', true, v_actor)
  on conflict (user_id, action_key) do update set allowed = true, updated_by = excluded.updated_by;
  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  if public.current_system_environment() = 'unconfigured' then
    perform public.set_system_runtime_environment(
      'test', 'test_reset', '0074 disposable historical guarantee smoke'
    );
  elsif public.current_system_environment() <> 'test' then
    raise exception '0074 smoke requires disposable test environment';
  end if;

  insert into public.source_workbooks(file_name, sha256, size_bytes, metadata_json, created_by)
  values ('guarantee-reconciliation-fixture.xlsx', repeat('7', 64), 774, '{"fixture":true}', v_migration_actor)
  returning id into v_workbook_id;
  insert into public.migration_batches(workbook_id, status, notes, created_by, updated_by)
  values (v_workbook_id, 'running', '0074 disposable smoke', v_migration_actor, v_migration_actor)
  returning id into v_batch_id;
  insert into public.source_tables(workbook_id, sheet_name, table_name, ref, column_count, row_count)
  values (v_workbook_id, 'Fixture', 'Guarantees', 'A1:C2', 3, 1)
  returning id into v_table_id;
  insert into public.source_rows(table_id, excel_row_number, row_index, row_hash, payload_json)
  values (v_table_id, 2, 0, repeat('8', 64), '{"fixture":true}')
  returning id into v_row_id;

  insert into public.cad_produtos_base(
    codigo_produto, nome, nome_norm, status, payload_origem_json,
    created_by, updated_by, origem_dados
  ) values (
    '9774', 'Historical guarantee fixture', 'historical guarantee fixture',
    'active', '{}', v_actor, v_actor, 'sistema'
  ) returning id into v_product_id;

  select id into v_nutrient_id from public.cad_nutrientes where status = 'active' order by id limit 1;
  select id into v_unit_percent from public.cad_unidades_medida where codigo_norm = 'percent';
  select id into v_unit_kg_l from public.cad_unidades_medida where codigo_norm in ('kg_l', 'kg/l') order by id limit 1;
  if v_nutrient_id is null or v_unit_percent is null then raise exception 'governed catalogs are required'; end if;
  v_unit_kg_l := coalesce(v_unit_kg_l, v_unit_percent);

  insert into public.pcp_garantia_fontes_historicas(
    produto_id, descricao_origem, valor_pp_percentual_l, valor_pv_kg_l,
    source_batch_id, source_row_id, created_by
  ) values (
    v_product_id, 'Fixture nutrient expression', 2.5, 0.025,
    v_batch_id, v_row_id, v_migration_actor
  ) returning id into v_source_id;

  select count(*) into v_operational_before from public.cad_garantias_produto_mapa;
  v_event_id := public.revisar_pcp_garantia_historica(
    v_source_id, 'classificada', v_nutrient_id, v_unit_percent, v_unit_kg_l,
    'Classificacao confirmada apenas para conciliacao historica'
  );
  if not exists (
    select 1 from public.pcp_garantias_historicas_conciliacao_atual
    where id = v_source_id and decisao = 'classificada' and nutriente_id = v_nutrient_id
  ) then raise exception 'review did not reach current reconciliation view'; end if;
  if (select count(*) from public.cad_garantias_produto_mapa) <> v_operational_before then
    raise exception 'historical review promoted an operational product guarantee';
  end if;
  if not exists (
    select 1 from public.action_logs
    where entity_type = 'pcp_garantia_reconciliacao_eventos' and entity_id = v_event_id::text
  ) then raise exception 'historical review audit log not found'; end if;

  begin
    perform public.revisar_pcp_garantia_historica(
      v_source_id, 'classificada', null, null, null, 'Invalid catalog-free classification'
    );
    raise exception 'classification without catalogs should have failed';
  exception when others then
    if sqlerrm not like 'nutrient and both units are required%' then raise; end if;
  end;

  begin
    update public.pcp_garantia_fontes_historicas set descricao_origem = 'changed' where id = v_source_id;
    raise exception 'append-only source update should have failed';
  exception when others then
    if sqlerrm not like '%append-only%' then raise; end if;
  end;

  if has_table_privilege('authenticated', 'public.pcp_garantia_fontes_historicas', 'INSERT,UPDATE,DELETE')
     or has_table_privilege('authenticated', 'public.pcp_garantia_reconciliacao_eventos', 'INSERT,UPDATE,DELETE') then
    raise exception 'authenticated retains direct historical guarantee write';
  end if;
  if has_function_privilege('anon', 'public.revisar_pcp_garantia_historica(bigint,text,bigint,bigint,bigint,text)', 'EXECUTE')
     or exists (
       select 1
       from pg_proc procedure
       cross join lateral aclexplode(coalesce(procedure.proacl, acldefault('f', procedure.proowner))) privilege
       where procedure.oid = 'public.revisar_pcp_garantia_historica(bigint,text,bigint,bigint,bigint,text)'::regprocedure
         and privilege.grantee = 0
         and privilege.privilege_type = 'EXECUTE'
     ) then
    raise exception 'anonymous or PUBLIC can execute historical review';
  end if;
end;
$$;

rollback;

select 'PG_VALIDATE_0074_HISTORICAL_GUARANTEE_RECONCILIATION_OK' as result;
