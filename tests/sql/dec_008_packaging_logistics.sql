\set ON_ERROR_STOP on

begin;

do $dec008$
declare
  v_migration_actor uuid := public.historical_migration_actor_id();
  v_human_actor uuid := '00000000-0000-4000-8000-000000000751';
  v_workbook_id bigint;
  v_batch_id bigint;
  v_table_id bigint;
  v_source_row_id bigint;
  v_kg_id bigint := public.resolve_cad_unidade_id('kg');
  v_l_id bigint := public.resolve_cad_unidade_id('l');
  v_t_id bigint := public.resolve_cad_unidade_id('t');
  v_un_id bigint := public.resolve_cad_unidade_id('un');
  v_component_mp_id bigint;
  v_historical_package_id bigint;
  v_system_package_id bigint;
  v_small_package_id bigint;
  v_package_version_id bigint;
  v_product_id bigint;
  v_product_package_20_id bigint;
  v_product_package_5_id bigint;
  v_client_id bigint;
  v_order_id bigint;
  v_order_item_id bigint;
  v_romaneio_id bigint;
  v_delivery_person_id bigint;
  v_vehicle_id bigint;
  v_lot_20_id bigint;
  v_lot_5_id bigint;
  v_transformation_id bigint;
begin
  if v_migration_actor is null then
    raise exception 'DEC-008 smoke requires Migracao Historica actor';
  end if;
  if v_kg_id is null or v_l_id is null or v_t_id is null or v_un_id is null then
    raise exception 'DEC-008 smoke requires canonical kg/l/t/un units';
  end if;

  insert into auth.users(id) values (v_human_actor)
  on conflict (id) do nothing;

  insert into public.user_profiles(id, display_name, role, status)
  values (v_human_actor, 'DEC-008 Human Reviewer', 'admin', 'active')
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
    'test', 'test_reset', 'Validacao transacional da DEC-008 em PostgreSQL local'
  );

  insert into public.source_workbooks(
    file_name, sha256, size_bytes, metadata_json, created_by
  ) values (
    'dec008-fixture.xlsx', repeat('8', 64), 800, '{"fixture":true}'::jsonb,
    v_migration_actor
  ) returning id into v_workbook_id;

  insert into public.migration_batches(workbook_id, status, notes, created_by, updated_by)
  values (v_workbook_id, 'running', 'DEC-008 fixture', v_migration_actor, v_migration_actor)
  returning id into v_batch_id;

  insert into public.source_tables(
    workbook_id, sheet_name, table_name, ref, header_row, data_first_row,
    data_last_row, column_count, row_count, metadata_json
  ) values (
    v_workbook_id, 'DEC008', 'DEC008Fixture', 'A1:H2', 1, 2, 2, 8, 1, '{}'::jsonb
  ) returning id into v_table_id;

  insert into public.source_rows(
    table_id, excel_row_number, row_index, row_hash, payload_json, formulas_json
  ) values (
    v_table_id, 2, 0, repeat('9', 64), '{"fixture":true}'::jsonb, '{}'::jsonb
  ) returning id into v_source_row_id;

  insert into public.cad_materias_primas(
    sku_corrigido, nome, nome_norm, unidade_base_estoque, status,
    payload_origem_json, created_by, updated_by, origem_dados
  ) values (
    'DEC008-COMP', 'Componente de embalagem DEC-008',
    'componente de embalagem dec-008', 'un', 'active', '{}'::jsonb,
    v_human_actor, v_human_actor, 'sistema'
  ) returning id into v_component_mp_id;

  insert into public.cad_embalagens(
    descricao, descricao_norm, unidade, volume_litros, controla_estoque,
    status, origem_dados, source_batch_id, source_row_id, created_by, updated_by
  ) values (
    'Bombona historica 20L', 'bombona historica 20l', 'litros', 20, false,
    'pending_review', 'excel_legado', v_batch_id, v_source_row_id,
    v_migration_actor, v_migration_actor
  ) returning id into v_historical_package_id;

  if not exists (
    select 1 from public.cad_embalagens package
    where package.id = v_historical_package_id and package.unidade_id = v_l_id
  ) then
    raise exception 'historical package unit alias was not canonicalized';
  end if;

  insert into public.cad_embalagem_versoes(
    embalagem_id, versao, peso_tara_kg, cubagem_m3, review_status,
    origem_dados, source_batch_id, source_row_id, created_by
  ) values (
    v_historical_package_id, 1, 0.8, 0.03, 'pending_review',
    'excel_legado', v_batch_id, v_source_row_id, v_migration_actor
  );

  begin
    insert into public.cad_embalagem_versoes(
      embalagem_id, versao, review_status, origem_dados,
      source_batch_id, source_row_id, created_by
    ) values (
      v_historical_package_id, 2, 'approved', 'excel_legado',
      v_batch_id, v_source_row_id, v_migration_actor
    );
    raise exception 'historical package version was promoted automatically';
  exception when others then
    if sqlerrm not like 'excel_legado requires review_status = pending_review%' then
      raise;
    end if;
  end;

  insert into public.cad_embalagens(
    descricao, descricao_norm, unidade, volume_litros, controla_estoque,
    status, origem_dados, created_by, updated_by
  ) values (
    'Bombona operacional 20L', 'bombona operacional 20l', 'l', 20, false,
    'active', 'sistema', v_human_actor, v_human_actor
  ) returning id into v_system_package_id;

  insert into public.cad_embalagens(
    descricao, descricao_norm, unidade, volume_litros, controla_estoque,
    status, origem_dados, created_by, updated_by
  ) values (
    'Frasco operacional 5L', 'frasco operacional 5l', 'l', 5, false,
    'active', 'sistema', v_human_actor, v_human_actor
  ) returning id into v_small_package_id;

  insert into public.cad_embalagem_versoes(
    embalagem_id, versao, peso_tara_kg, cubagem_m3, justificativa,
    review_status, origem_dados, created_by
  ) values (
    v_system_package_id, 1, 0.8, 0.03, 'Fixture aprovada',
    'approved', 'sistema', v_human_actor
  ) returning id into v_package_version_id;

  insert into public.cad_embalagem_componentes(
    embalagem_versao_id, materia_prima_id, quantidade, unidade_id,
    review_status, origem_dados, created_by
  ) values (
    v_package_version_id, v_component_mp_id, 1, v_un_id,
    'approved', 'sistema', v_human_actor
  );

  insert into public.cad_embalagem_versao_ativacoes(
    embalagem_versao_id, tipo_evento, motivo, created_by
  ) values (v_package_version_id, 'ativacao', 'Fixture DEC-008', v_human_actor);

  if not exists (
    select 1 from public.cad_embalagem_configuracoes_atuais current_package
    where current_package.embalagem_versao_id = v_package_version_id
      and current_package.peso_tara_kg = 0.8
      and current_package.cubagem_m3 = 0.03
  ) then
    raise exception 'approved package version did not reach current view';
  end if;

  begin
    insert into public.cad_embalagem_versao_ativacoes(
      embalagem_versao_id, tipo_evento, motivo, created_by
    ) values (v_package_version_id, 'ativacao', 'System actor attempt', v_migration_actor);
    raise exception 'system actor activated packaging version';
  exception when others then
    if sqlerrm <> 'only active human profiles can activate packaging versions' then
      raise;
    end if;
  end;

  insert into public.cad_conversoes_unidade_mp(
    materia_prima_id, unidade_origem, unidade_destino, fator,
    review_status, origem_dados, source_batch_id, source_row_id, created_by
  ) values (
    v_component_mp_id, 'quilogramas', 'toneladas', 0.001,
    'pending_review', 'excel_legado', v_batch_id, v_source_row_id, v_migration_actor
  );

  if not exists (
    select 1 from public.cad_conversoes_unidade_mp conversion
    where conversion.materia_prima_id = v_component_mp_id
      and conversion.unidade_origem_id = v_kg_id
      and conversion.unidade_destino_id = v_t_id
      and conversion.review_status = 'pending_review'
  ) then
    raise exception 'historical conversion did not use canonical FKs';
  end if;

  insert into public.cad_produtos_base(
    codigo_produto, nome, nome_norm, status, payload_origem_json,
    created_by, updated_by, origem_dados
  ) values (
    '8008', 'Produto DEC-008', 'produto dec-008', 'active', '{}'::jsonb,
    v_human_actor, v_human_actor, 'sistema'
  ) returning id into v_product_id;

  insert into public.cad_produto_embalagens(
    produto_id, embalagem_id, codigo_item, status, created_by, updated_by, origem_dados
  ) values (
    v_product_id, v_system_package_id, '8008-20L', 'active',
    v_human_actor, v_human_actor, 'sistema'
  ) returning id into v_product_package_20_id;

  insert into public.cad_produto_embalagens(
    produto_id, embalagem_id, codigo_item, status, created_by, updated_by, origem_dados
  ) values (
    v_product_id, v_small_package_id, '8008-5L', 'active',
    v_human_actor, v_human_actor, 'sistema'
  ) returning id into v_product_package_5_id;

  insert into public.cad_clientes(
    nome, nome_norm, cidade, uf, status, apelidos_json, payload_origem_json,
    created_by, updated_by, origem_dados
  ) values (
    'Cliente DEC-008', 'cliente dec-008', 'Campinas', 'SP', 'active',
    '[]'::jsonb, '{}'::jsonb, v_human_actor, v_human_actor, 'sistema'
  ) returning id into v_client_id;

  insert into public.com_pedidos(
    codigo_pedido, cliente_id, tipo_pedido, status, data_pedido,
    origem_canal, valor_total, created_by, updated_by, origem_dados
  ) values (
    'DEC008-PED', v_client_id, 'venda', 'open', current_date,
    'interno', 0, v_human_actor, v_human_actor, 'sistema'
  ) returning id into v_order_id;

  insert into public.com_pedido_itens(
    pedido_id, produto_embalagem_id, tipo_item, quantidade, valor_unitario,
    percentual_desconto, valor_total, status, created_by, updated_by, origem_dados
  ) values (
    v_order_id, v_product_package_20_id, 'venda', 1, 0, 0, 0, 'active',
    v_human_actor, v_human_actor, 'sistema'
  ) returning id into v_order_item_id;

  insert into public.exp_romaneios(
    codigo_romaneio, pedido_id, tipo_separacao, status, data_romaneio,
    created_by, updated_by, review_status, origem_dados
  ) values (
    'DEC008-ROM', v_order_id, 'total', 'draft', current_date,
    v_human_actor, v_human_actor, 'approved', 'sistema'
  ) returning id into v_romaneio_id;

  insert into public.exp_romaneio_itens(
    romaneio_id, pedido_id, pedido_item_id, produto_embalagem_id,
    quantidade_romaneada, quantidade_reservada, status, created_by, updated_by,
    review_status, origem_dados
  ) values (
    v_romaneio_id, v_order_id, v_order_item_id, v_product_package_20_id,
    1, 0, 'draft', v_human_actor, v_human_actor, 'approved', 'sistema'
  );

  insert into public.cad_pessoas_comerciais(
    nome, nome_norm, papeis_json, status, payload_origem_json,
    created_by, updated_by, origem_dados
  ) values (
    'Entregador DEC-008', 'entregador dec-008', '["entregador"]'::jsonb,
    'active', '{}'::jsonb, v_human_actor, v_human_actor, 'sistema'
  ) returning id into v_delivery_person_id;

  insert into public.cad_veiculos(
    descricao, descricao_norm, placa, placa_norm, status,
    created_by, updated_by, origem_dados
  ) values (
    'Veiculo DEC-008', 'veiculo dec-008', 'DEC8A51', 'DEC8A51', 'active',
    v_human_actor, v_human_actor, 'sistema'
  ) returning id into v_vehicle_id;

  insert into public.exp_romaneio_logistica_eventos(
    romaneio_id, tipo_evento, entregador_id, veiculo_id, ocorrido_em,
    review_status, origem_dados, created_by
  ) values (
    v_romaneio_id, 'atribuicao', v_delivery_person_id, v_vehicle_id, now(),
    'approved', 'sistema', v_human_actor
  );

  if not exists (
    select 1 from public.exp_romaneio_logistica_atual logistics
    where logistics.romaneio_id = v_romaneio_id
      and logistics.entregador_id = v_delivery_person_id
      and logistics.veiculo_id = v_vehicle_id
  ) then
    raise exception 'approved logistics event did not reach current view';
  end if;

  insert into public.exp_romaneio_logistica_eventos(
    romaneio_id, tipo_evento, entregador_id, ocorrido_em,
    review_status, origem_dados, source_batch_id, source_row_id, created_by
  ) values (
    v_romaneio_id, 'atribuicao', v_delivery_person_id, null,
    'pending_review', 'excel_legado', v_batch_id, v_source_row_id,
    v_migration_actor
  );

  if (select count(*) from public.exp_romaneio_logistica_atual where romaneio_id = v_romaneio_id) <> 1 then
    raise exception 'pending historical logistics changed current assignment';
  end if;

  insert into public.est_lotes_pa(
    produto_embalagem_id, codigo_lote, status, created_by, updated_by
  ) values (
    v_product_package_20_id, 'DEC008-20', 'disponivel', v_human_actor, v_human_actor
  ) returning id into v_lot_20_id;

  insert into public.est_lotes_pa(
    produto_embalagem_id, codigo_lote, status, created_by, updated_by
  ) values (
    v_product_package_5_id, 'DEC008-5', 'disponivel', v_human_actor, v_human_actor
  ) returning id into v_lot_5_id;

  insert into public.est_transformacoes(
    tipo_transformacao, evidencia_tipo, evidencia_detalhe, review_status,
    origem_dados, source_batch_id, source_row_id, created_by
  ) values (
    'fracionamento_embalagem', 'inferida', 'Fixture de inferencia explicita',
    'pending_review', 'excel_legado', v_batch_id, v_source_row_id, v_migration_actor
  ) returning id into v_transformation_id;

  insert into public.est_transformacao_origens(
    transformacao_id, familia, lote_pa_id, quantidade, unidade_id,
    origem_dados, source_batch_id, source_row_id, created_by
  ) values (
    v_transformation_id, 'PA', v_lot_20_id, 1, v_un_id,
    'excel_legado', v_batch_id, v_source_row_id, v_migration_actor
  );

  insert into public.est_transformacao_destinos(
    transformacao_id, familia, lote_pa_id, quantidade, unidade_id,
    origem_dados, source_batch_id, source_row_id, created_by
  ) values (
    v_transformation_id, 'PA', v_lot_5_id, 4, v_un_id,
    'excel_legado', v_batch_id, v_source_row_id, v_migration_actor
  );

  if exists (
    select 1 from public.est_transformacoes_aprovadas approved
    where approved.id = v_transformation_id
  ) then
    raise exception 'inferred historical transformation reached approved view';
  end if;

  begin
    update public.est_transformacoes
       set evidencia_detalhe = 'Tentativa de sobrescrita'
     where id = v_transformation_id;
    raise exception 'append-only transformation was updated';
  exception when others then
    if sqlerrm not like 'est_transformacoes is append-only%' then
      raise;
    end if;
  end;

  if exists (
    select 1 from public.est_movimentos_pa movement
    where movement.origem_tabela = 'est_transformacoes'
      and movement.origem_id = v_transformation_id::text
  ) then
    raise exception 'DEC-008 created stock movement automatically';
  end if;
end;
$dec008$;

rollback;

select 'DEC_008_PACKAGING_LOGISTICS_SMOKE_OK' as result;
