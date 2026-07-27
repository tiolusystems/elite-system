\set ON_ERROR_STOP on

begin;

do $production_chain$
declare
  v_actor uuid := '00000000-0000-4000-8000-000000000087';
  v_unit_kg bigint;
  v_unit_un bigint;
  v_formula_mp_id bigint;
  v_packaging_mp_id bigint;
  v_product_id bigint;
  v_package_id bigint;
  v_sale_item_id bigint;
  v_package_version_id bigint;
  v_formula_id bigint;
  v_mapa_formula_id bigint;
  v_formula_lot_id bigint;
  v_packaging_lot_id bigint;
  v_formula_lot_code text;
  v_packaging_lot_code text;
  v_formula_entry_id bigint;
  v_packaging_entry_id bigint;
  v_separador_id bigint;
  v_conferente_id bigint;
  v_formulador_id bigint;
  v_responsavel_cq_id bigint;
  v_responsavel_liberacao_id bigint;
  v_op_id bigint;
  v_component_id bigint;
  v_pi_lot_id bigint;
  v_packaging_order_id bigint;
  v_packaging_plan_id bigint;
  v_pa_lot_id bigint;
  v_client_id bigint;
  v_order_id bigint;
  v_order_item_id bigint;
  v_romaneio_id bigint;
  v_romaneio_item_id bigint;
  v_fiscal_reference_id bigint;
  v_load record;
  v_cost numeric;
begin
  if not exists (
    select 1
      from pg_class relation
     where relation.oid = 'public.exp_romaneio_carga_resumo'::regclass
       and coalesce(relation.reloptions @> array['security_invoker=true'], false)
  ) then
    raise exception 'romaneio load summary is not security_invoker';
  end if;
  if not has_table_privilege(
    'authenticated',
    'public.exp_romaneio_carga_resumo',
    'SELECT'
  ) or has_table_privilege(
    'anon',
    'public.exp_romaneio_carga_resumo',
    'SELECT'
  ) or exists (
    select 1
      from pg_class relation
      cross join lateral aclexplode(
        coalesce(relation.relacl, acldefault('r', relation.relowner))
      ) privilege
     where relation.oid = 'public.exp_romaneio_carga_resumo'::regclass
       and privilege.grantee = 0
       and privilege.privilege_type = 'SELECT'
  ) then
    raise exception 'romaneio load summary privileges are broader than authenticated read';
  end if;

  if has_function_privilege('authenticated', 'public.create_pcp_formula_versao(bigint,text,text,jsonb,text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.create_pcp_formula_versao_idempotente(uuid,bigint,text,text,jsonb,text)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.create_pcp_formula_versao_idempotente(uuid,bigint,text,text,jsonb,text)', 'EXECUTE') then
    raise exception 'formula creation grants are broader than the idempotent contract';
  end if;
  if has_function_privilege('authenticated', 'public.create_pcp_op(bigint,text,numeric,text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.create_pcp_op_idempotente(uuid,bigint,text,numeric,text)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.create_pcp_op_idempotente(uuid,bigint,text,numeric,text)', 'EXECUTE') then
    raise exception 'OP creation grants are broader than the idempotent contract';
  end if;

  insert into auth.users(id) values (v_actor) on conflict (id) do nothing;
  insert into public.user_profiles(id, display_name, role, status)
  values (v_actor, 'Cadeia industrial sintetica 0087', 'admin', 'active')
  on conflict (id) do update set display_name = excluded.display_name, role = excluded.role, status = excluded.status;
  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  select v_actor, action_key, true, v_actor from public.permission_actions
  on conflict (user_id, action_key) do update set allowed = true, updated_by = excluded.updated_by;
  perform set_config('request.jwt.claim.sub', v_actor::text, true);

  insert into public.cad_pessoas_comerciais(nome, nome_norm, papeis_json, status)
  values ('Separador cadeia 0087', 'SEPARADOR CADEIA 0087', '["funcionario"]'::jsonb, 'active')
  returning id into v_separador_id;
  insert into public.cad_pessoas_comerciais(nome, nome_norm, papeis_json, status)
  values ('Conferente cadeia 0087', 'CONFERENTE CADEIA 0087', '["funcionario"]'::jsonb, 'active')
  returning id into v_conferente_id;
  insert into public.cad_pessoas_comerciais(nome, nome_norm, papeis_json, status)
  values ('Formulador cadeia 0087', 'FORMULADOR CADEIA 0087', '["funcionario"]'::jsonb, 'active')
  returning id into v_formulador_id;
  insert into public.cad_pessoas_comerciais(nome, nome_norm, papeis_json, status)
  values ('Responsavel CQ cadeia 0087', 'RESPONSAVEL CQ CADEIA 0087', '["funcionario"]'::jsonb, 'active')
  returning id into v_responsavel_cq_id;
  insert into public.cad_pessoas_comerciais(nome, nome_norm, papeis_json, status)
  values ('Responsavel liberacao cadeia 0087', 'RESPONSAVEL LIBERACAO CADEIA 0087', '["funcionario"]'::jsonb, 'active')
  returning id into v_responsavel_liberacao_id;

  if public.current_system_environment() = 'unconfigured' then
    perform public.set_system_runtime_environment('test', 'test_reset', 'Cadeia industrial integrada descartavel');
  elsif public.current_system_environment() <> 'test' then
    raise exception 'integrated production smoke requires disposable test environment';
  end if;

  select id into v_unit_kg from public.cad_unidades_medida where codigo = 'kg_l_produzido' and status = 'active';
  select id into v_unit_un from public.cad_unidades_medida where upper(codigo) = 'UN' and status = 'active';
  if v_unit_kg is null or v_unit_un is null then raise exception 'canonical production units not found'; end if;

  v_formula_mp_id := public.create_cad_materia_prima_governada(
    p_nome => 'Materia-prima cadeia 0087', p_nome_norm => 'MATERIA PRIMA CADEIA 0087',
    p_sku_corrigido => 'MP-CHAIN-0087', p_unidade_base_estoque_id => v_unit_kg, p_status => 'active'
  );
  v_packaging_mp_id := public.create_cad_materia_prima_governada(
    p_nome => 'Embalagem cadeia 0087', p_nome_norm => 'EMBALAGEM CADEIA 0087',
    p_sku_corrigido => 'EMB-CHAIN-0087', p_unidade_base_estoque_id => v_unit_un, p_status => 'active'
  );
  v_product_id := public.create_cad_produto_base(
    p_codigo_produto => '9087', p_nome => 'Produto cadeia 0087',
    p_nome_norm => 'PRODUTO CADEIA 0087', p_status => 'active', p_prazo_validade_meses => 24
  );
  v_package_id := public.create_cad_embalagem(
    p_descricao => 'Galao sintetico 5 L 0087', p_descricao_norm => 'GALAO SINTETICO 5 L 0087',
    p_unidade => 'UN', p_status => 'active', p_volume_litros => 5,
    p_controla_estoque => true, p_materia_prima_id => v_packaging_mp_id
  );
  v_sale_item_id := public.create_cad_produto_embalagem(v_product_id, v_package_id, '9087-5L', 'active');
  perform public.update_cad_apresentacao_logistica(
    v_sale_item_id, 1, 'Uma unidade sintetica por volume logistico'
  );
  v_package_version_id := public.create_cad_embalagem_versao_un_l(
    v_package_id, current_date, null, 0.25, 0.02, 'Composicao sintetica integrada'
  );
  perform public.add_cad_embalagem_componente_un_l(
    v_package_version_id, v_packaging_mp_id, 0.2, 'Uma unidade para cada cinco litros'
  );
  perform public.review_cad_embalagem_versao(v_package_version_id, 'approved', 'Composicao conferida no smoke integrado');
  perform public.activate_cad_embalagem_versao(v_package_version_id, true, 'Composicao ativa para o smoke integrado');

  v_formula_lot_id := public.create_est_lote_mp(
    v_formula_mp_id, 12, null, 'entrada_compra', 'disponivel', current_date, current_date + 365,
    'MP-CHAIN-LOT-0087', 'Entrada sintetica para producao'
  );
  v_packaging_lot_id := public.create_est_lote_mp(
    v_packaging_mp_id, 3, null, 'entrada_compra', 'disponivel', current_date, current_date + 365,
    'EMB-CHAIN-LOT-0087', 'Entrada sintetica de embalagem'
  );
  select codigo_lote into v_formula_lot_code from public.est_lotes_mp where id = v_formula_lot_id;
  select codigo_lote into v_packaging_lot_code from public.est_lotes_mp where id = v_packaging_lot_id;
  select id into v_formula_entry_id from public.est_movimentos_mp where lote_mp_id = v_formula_lot_id order by id limit 1;
  select id into v_packaging_entry_id from public.est_movimentos_mp where lote_mp_id = v_packaging_lot_id order by id limit 1;
  insert into public.est_movimentos_mp_valores(
    movimento_mp_id, quantidade_origem, unidade_origem, quantidade_base, moeda,
    valor_materia_prima, difal_status, documento_ref, origem_dados, created_by
  ) values
    (v_formula_entry_id, 12, 'KG', 12, 'BRL', 120, 'not_applicable', 'NF-CHAIN-MP-0087', 'sistema', v_actor),
    (v_packaging_entry_id, 3, 'UN', 3, 'BRL', 6, 'not_applicable', 'NF-CHAIN-EMB-0087', 'sistema', v_actor);

  v_formula_id := public.create_pcp_formula_versao_idempotente(
    '87000000-0000-4000-8000-000000000001', v_product_id, 'producao', 'Formula operacional integrada 0087',
    jsonb_build_array(jsonb_build_object(
      'tipo_componente', 'MP', 'materia_prima_id', v_formula_mp_id,
      'quantidade', 1, 'unidade_id', v_unit_kg, 'unidade', 'kg_l_produzido'
    )), 'Base de um litro'
  );
  if public.create_pcp_formula_versao_idempotente(
    '87000000-0000-4000-8000-000000000001', v_product_id, 'producao', 'Formula operacional integrada 0087',
    jsonb_build_array(jsonb_build_object(
      'tipo_componente', 'MP', 'materia_prima_id', v_formula_mp_id,
      'quantidade', 1, 'unidade_id', v_unit_kg, 'unidade', 'kg_l_produzido'
    )), 'Base de um litro'
  ) <> v_formula_id then raise exception 'formula retry did not return the original version'; end if;
  perform public.activate_pcp_formula_versao(v_formula_id, 'Formula operacional aprovada no smoke integrado');
  v_mapa_formula_id := public.create_pcp_formula_versao_idempotente(
    '87000000-0000-4000-8000-000000000002', v_product_id, 'mapa', 'Formula MAPA documental integrada 0087', '[]'::jsonb,
    'Documento MAPA sem consumo de materia-prima'
  );
  perform public.activate_pcp_formula_versao(v_mapa_formula_id, 'Formula MAPA aprovada no smoke integrado');

  v_op_id := public.create_pcp_op_idempotente(
    '87000000-0000-4000-8000-000000000010', v_formula_id, 'estoque', 10, 'OP integrada 0087'
  );
  if public.create_pcp_op_idempotente(
    '87000000-0000-4000-8000-000000000010', v_formula_id, 'estoque', 10, 'OP integrada 0087'
  ) <> v_op_id then
    raise exception 'OP retry did not return the original production order';
  end if;
  begin
    perform public.create_pcp_op_idempotente(
      '87000000-0000-4000-8000-000000000010', v_formula_id, 'estoque', 11, 'OP integrada 0087'
    );
    raise exception 'changed OP payload reused the request key';
  exception when others then
    if sqlerrm not like 'idempotency key reused with different production order request%' then raise; end if;
  end;
  select id into v_component_id from public.pcp_op_componentes_planejados
   where op_id = v_op_id and tipo_componente = 'MP';
  perform public.reservar_pcp_op_componente(
    v_component_id, v_formula_lot_id, null, null, 10, 'Reserva completa da formula'
  );
  perform public.iniciar_pcp_op(v_op_id, 'Inicio da producao integrada');
  perform public.finalizar_pcp_op_relacional(
    v_op_id,
    jsonb_build_array(jsonb_build_object(
      'tipo_produto', 'PI', 'produto_id', v_product_id, 'quantidade', 9,
      'observacao', 'Lote PI unico da cadeia integrada'
    )),
    'aprovado', 6.5, 1, 9, 9, 25,
    v_separador_id,
    v_conferente_id,
    array[v_formulador_id],
    v_responsavel_cq_id,
    v_responsavel_liberacao_id,
    'Perda de processo de um litro'
  );

  if (
    select count(*)
      from public.pcp_op_cq_participantes
     where op_id = v_op_id
       and pessoa_comercial_id in (
         v_separador_id,
         v_conferente_id,
         v_formulador_id,
         v_responsavel_cq_id,
         v_responsavel_liberacao_id
       )
  ) <> 5 then
    raise exception 'relational CQ participants were not preserved';
  end if;

  select lote_pi_id into v_pi_lot_id from public.pcp_op_produtos_gerados where op_id = v_op_id;
  if v_pi_lot_id is null or (select count(*) from public.pcp_op_produtos_gerados where op_id = v_op_id) <> 1 then
    raise exception 'production did not generate exactly one PI lot';
  end if;
  if (select status from public.est_lotes_pi where id = v_pi_lot_id) <> 'disponivel' then
    raise exception 'approved CQ did not release generated PI lot';
  end if;
  if (select saldo_fisico from public.est_lotes_mp_saldos where lote_mp_id = v_formula_lot_id) <> 2 then
    raise exception 'production MP consumption is inconsistent';
  end if;

  v_packaging_order_id := public.emitir_pcp_op_mapa_com_envase_idempotente(
    '00000000-0000-4000-8000-000000000987', v_mapa_formula_id, v_pi_lot_id, v_sale_item_id, 5,
    'elite-validation-0087', 'Emissao integrada de OP MAPA e envase'
  );
  select id into v_packaging_plan_id from public.pcp_ordem_envase_embalagens
   where ordem_envase_id = v_packaging_order_id and materia_prima_id = v_packaging_mp_id;
  perform public.reservar_pcp_ordem_envase_embalagem(v_packaging_plan_id, v_packaging_lot_id, 1);
  perform public.iniciar_pcp_ordem_envase(v_packaging_order_id);
  perform public.finalizar_pcp_ordem_envase(
    v_packaging_order_id,
    '[{"quantidade": 1, "observacao": "Lote PA unico da cadeia integrada"}]'::jsonb,
    'Finalizacao integrada do envase'
  );

  select lote_pa_id into v_pa_lot_id from public.pcp_ordem_envase_lotes_pa
   where ordem_envase_id = v_packaging_order_id;
  if v_pa_lot_id is null or (select count(*) from public.pcp_ordem_envase_lotes_pa where ordem_envase_id = v_packaging_order_id) <> 1 then
    raise exception 'packaging did not generate exactly one PA lot';
  end if;
  if (select saldo_fisico from public.est_lotes_pi_saldos where lote_pi_id = v_pi_lot_id) <> 4 then
    raise exception 'packaging did not consume five liters of PI';
  end if;
  if (select saldo_fisico from public.est_lotes_mp_saldos where lote_mp_id = v_packaging_lot_id) <> 2 then
    raise exception 'packaging material consumption is inconsistent';
  end if;
  if (select saldo_fisico from public.est_lotes_pa_saldos where lote_pa_id = v_pa_lot_id) <> 1 then
    raise exception 'generated PA balance is inconsistent';
  end if;
  if exists (
    select 1 from public.pcp_ordem_envase_reservas
     where ordem_envase_id = v_packaging_order_id and status = 'ativa'
  ) then raise exception 'packaging reservations remained active after completion'; end if;

  insert into public.cad_clientes(
    nome, nome_norm, cidade, uf, status, apelidos_json, payload_origem_json,
    created_by, updated_by, origem_dados
  ) values (
    'Cliente carga integrada 0112', 'cliente carga integrada 0112', 'Campinas', 'SP',
    'active', '[]'::jsonb, '{}'::jsonb, v_actor, v_actor, 'sistema'
  ) returning id into v_client_id;

  insert into public.com_pedidos(
    codigo_pedido, cliente_id, tipo_pedido, status, data_pedido,
    origem_canal, valor_total, created_by, updated_by, origem_dados
  ) values (
    'SMOKE-0112-PED', v_client_id, 'venda', 'open', current_date,
    'interno', 0, v_actor, v_actor, 'sistema'
  ) returning id into v_order_id;

  insert into public.com_pedido_itens(
    pedido_id, produto_embalagem_id, tipo_item, quantidade, valor_unitario,
    percentual_desconto, valor_total, status, created_by, updated_by, origem_dados
  ) values (
    v_order_id, v_sale_item_id, 'venda', 1, 0, 0, 0, 'active',
    v_actor, v_actor, 'sistema'
  ) returning id into v_order_item_id;

  insert into public.exp_romaneios(
    codigo_romaneio, pedido_id, tipo_separacao, status, data_romaneio,
    created_by, updated_by, origem_dados
  ) values (
    'SMOKE-0112-ROM', v_order_id, 'total', 'separacao', current_date,
    v_actor, v_actor, 'sistema'
  ) returning id into v_romaneio_id;

  insert into public.exp_romaneio_itens(
    romaneio_id, pedido_id, pedido_item_id, produto_embalagem_id,
    quantidade_romaneada, quantidade_reservada, status,
    created_by, updated_by, origem_dados
  ) values (
    v_romaneio_id, v_order_id, v_order_item_id, v_sale_item_id,
    1, 1, 'reservado', v_actor, v_actor, 'sistema'
  ) returning id into v_romaneio_item_id;

  insert into public.est_reservas_pa(
    lote_pa_id, romaneio_id, romaneio_item_id, produto_embalagem_id,
    quantidade_reservada, status, created_by, updated_by
  ) values (
    v_pa_lot_id, v_romaneio_id, v_romaneio_item_id, v_sale_item_id,
    1, 'ativa', v_actor, v_actor
  );

  select *
    into v_load
    from public.exp_romaneio_carga_resumo
   where romaneio_id = v_romaneio_id;

  if v_load.volume_liquido_l <> 5
     or v_load.volumes_logisticos <> 1
     or v_load.peso_liquido_kg <> 5
     or v_load.peso_bruto_kg <> 5.25
     or v_load.itens_sem_volume_configurado <> 0
     or v_load.itens_sem_densidade <> 0
     or v_load.itens_sem_tara <> 0 then
    raise exception 'envase PA load did not use the operational PI CQ density: %', to_jsonb(v_load);
  end if;

  insert into public.exp_romaneio_movimentos_pa(
    romaneio_id, romaneio_item_id, pedido_id, pedido_item_id,
    produto_embalagem_id, lote_pa_ref, lote_pa_id,
    tipo_movimento, quantidade, observacao, created_by
  ) values (
    v_romaneio_id, v_romaneio_item_id, v_order_id, v_order_item_id,
    v_sale_item_id,
    (select codigo_lote from public.est_lotes_pa where id = v_pa_lot_id),
    v_pa_lot_id,
    'baixa', 1, 'Smoke transacional da rastreabilidade 0113', v_actor
  );

  update public.exp_romaneios
     set status = 'confirmado', updated_by = v_actor
   where id = v_romaneio_id;
  update public.exp_romaneio_itens
     set status = 'confirmado', updated_by = v_actor
   where id = v_romaneio_item_id;

  insert into public.fat_notas_fiscais(
    pedido_id, romaneio_id, chave_nfe, numero, serie, data_emissao,
    valor_nf, tipo, status_atual, observacao, origem_registro,
    created_by, updated_by
  ) values (
    v_order_id, v_romaneio_id, null, 'SMOKE-0113-REM', 'HOM', current_date,
    0, 'remessa_total', 'emitida', 'Referencia externa sintetica',
    'externa', v_actor, v_actor
  ) returning id into v_fiscal_reference_id;

  if not exists (
    select 1
      from public.consultar_rel_rastreabilidade(
        'MP', v_formula_lot_code, null, null, null, null, 'frente', 500
      ) trace
     where trace.destino_tipo = 'REFERENCIA_FISCAL'
       and trace.destino_id = v_fiscal_reference_id
  ) then
    raise exception 'traceability did not reach external fiscal reference';
  end if;

  if not exists (
    select 1
      from public.consultar_rel_rastreabilidade(
        null, null, null, null, null, 'SMOKE-0113-REM-HOM', 'tras', 500
      ) trace
     where trace.origem_tipo = 'PA'
       and trace.origem_id = v_pa_lot_id
  ) then
    raise exception 'external fiscal reference did not trace back to PA';
  end if;

  if not exists (
    select 1
      from public.simular_rel_recolhimento('PA', v_pa_lot_id) recall
     where recall.romaneio_id = v_romaneio_id
       and recall.referencia_fiscal_id = v_fiscal_reference_id
       and recall.quantidade = 1
  ) then
    raise exception 'recall simulation did not return the active shipment';
  end if;

  select sum(component.custo_total) into v_cost
    from public.est_lotes_pa_custo_camadas layer
    join public.est_lotes_pa_custo_componentes component on component.lote_custo_id = layer.id
   where layer.lote_pa_id = v_pa_lot_id and component.moeda = 'BRL';
  if v_cost is null or v_cost <= 0 then raise exception 'PA direct material cost was not materialized'; end if;

  if not exists (
    select 1
      from public.consultar_rel_rastreabilidade(
        'MP', v_formula_lot_code, null, null, null, null, 'frente', 500
      ) trace
     where trace.destino_tipo = 'OP' and trace.destino_id = v_op_id
  ) then
    raise exception 'derived traceability did not connect MP to OP';
  end if;
  if not exists (
    select 1
      from public.consultar_rel_rastreabilidade(
        'MP', v_formula_lot_code, null, null, null, null, 'frente', 500
      ) trace
     where trace.destino_tipo = 'PA' and trace.destino_id = v_pa_lot_id
  ) then
    raise exception 'derived traceability did not connect MP through OP, PI and packaging to PA';
  end if;
  if not exists (
    select 1
      from public.consultar_rel_rastreabilidade(
        'EMBALAGEM', v_packaging_lot_code, null, null, null, null, 'frente', 500
      ) trace
     where trace.destino_tipo = 'PA' and trace.destino_id = v_pa_lot_id
  ) then
    raise exception 'packaging material lot did not reach the finished PA lot';
  end if;
  if exists (
    select 1 from public.rel_rastreabilidade_conciliacao reconciliation
     where reconciliation.lote_id in (v_formula_lot_id, v_packaging_lot_id, v_pi_lot_id, v_pa_lot_id)
       and reconciliation.divergencia <> 0
  ) then
    raise exception 'traceability quantitative reconciliation found a divergence';
  end if;

  if not exists (
    select 1 from public.consultar_est_estoque_pa_posicao(current_date) position
     where position.lote_pa_id = v_pa_lot_id
       and position.saldo_fisico = 1
       and position.litros_fisicos = 5
       and position.volumes_fisicos = 1
  ) then raise exception 'PA stock report did not expose the generated lot'; end if;
  if not exists (
    select 1 from public.rel_estoque_lotes_vencimento report
     where report.tipo_lote = 'PI' and report.lote_id = v_pi_lot_id
  ) or not exists (
    select 1 from public.rel_estoque_lotes_vencimento report
     where report.tipo_lote = 'PA' and report.lote_id = v_pa_lot_id
  ) then raise exception 'PI/PA family reports did not expose the integrated chain'; end if;

  if not exists (
    select 1 from public.action_logs where action_key = 'pcp.op.finish' and entity_id = v_op_id::text and status = 'success'
  ) or not exists (
    select 1 from public.action_logs where action_key = 'pcp.envase.finish' and entity_id = v_packaging_order_id::text and status = 'success'
  ) then raise exception 'integrated production audit chain is incomplete'; end if;
end;
$production_chain$;

rollback;

select 'PG_PRODUCTION_END_TO_END_CHAIN_OK' as result;
