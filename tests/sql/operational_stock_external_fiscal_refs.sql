\set ON_ERROR_STOP on

begin;

do $test$
declare
  v_actor uuid := '00000000-0000-4000-8000-000000001050';
  v_denied uuid := '00000000-0000-4000-8000-000000001051';
  v_unit bigint;
  v_mp bigint;
  v_lot bigint;
  v_product bigint;
  v_package bigint;
  v_presentation bigint;
  v_client bigint;
  v_order bigint;
  v_order_item bigint;
  v_romaneio bigint;
  v_romaneio_item bigint;
  v_simple bigint;
  v_shipping bigint;
  v_correction bigint;
  v_before_movements bigint;
  v_before_commissions bigint;
begin
  insert into auth.users(id, email) values
    (v_actor, 'e2e-0105-authorized@test.invalid'),
    (v_denied, 'e2e-0105-denied@test.invalid')
  on conflict (id) do nothing;
  insert into public.user_profiles(id, display_name, role, status) values
    (v_actor, 'E2E 0105 autorizado', 'admin', 'active'),
    (v_denied, 'E2E 0105 sem alcada', 'admin', 'active')
  on conflict (id) do update set status = 'active';
  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  if public.current_system_environment() = 'unconfigured' then
    perform public.set_system_runtime_environment('test', 'test_reset', 'E2E 0105 descartavel');
  end if;
  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  values
    (v_actor, 'estoque.mp.lots.create', true, v_actor),
    (v_actor, 'estoque.mp.acquisition_value.register', true, v_actor),
    (v_actor, 'faturamento.external_references.register', true, v_actor),
    (v_actor, 'faturamento.external_references.correct', true, v_actor)
  on conflict (user_id, action_key) do update set allowed = excluded.allowed, updated_by = excluded.updated_by;

  select id into v_unit from public.cad_unidades_medida where status = 'active' order by id limit 1;
  v_mp := public.create_cad_materia_prima_governada(
    p_nome => 'MP E2E 0105', p_nome_norm => 'MP E2E 0105',
    p_sku_corrigido => 'MP-E2E-0105', p_unidade_base_estoque_id => v_unit,
    p_status => 'active'
  );
  v_lot := public.registrar_est_entrada_mp_idempotente(
    '10500000-0000-4000-8000-000000000001', v_mp, 25, 'disponivel',
    current_date - 1, current_date + 365, 'FORN-E2E-0105', 'DOC-E2E-0105',
    current_date, 'KG', 250, 10, 4, 'informed', 'DIFAL sintetico', 5, 'MG',
    'Entrada sintetica E2E'
  );
  if public.registrar_est_entrada_mp_idempotente(
    '10500000-0000-4000-8000-000000000001', v_mp, 25, 'disponivel',
    current_date - 1, current_date + 365, 'FORN-E2E-0105', 'DOC-E2E-0105',
    current_date, 'KG', 250, 10, 4, 'informed', 'DIFAL sintetico', 5, 'MG',
    'Entrada sintetica E2E'
  ) <> v_lot then raise exception 'stock entry retry did not return original lot'; end if;
  if (select count(*) from public.est_movimentos_mp_valores valor join public.est_movimentos_mp mov on mov.id = valor.movimento_mp_id where mov.lote_mp_id = v_lot) <> 1 then
    raise exception 'stock entry duplicated value layer';
  end if;
  if (select custo_aquisicao_total from public.est_movimentos_mp_valores valor join public.est_movimentos_mp mov on mov.id = valor.movimento_mp_id where mov.lote_mp_id = v_lot) <> 269 then
    raise exception 'stock entry cost is inconsistent';
  end if;
  begin
    perform public.registrar_est_entrada_mp_idempotente(
      '10500000-0000-4000-8000-000000000001', v_mp, 26, 'disponivel',
      current_date - 1, current_date + 365, 'FORN-E2E-0105', 'DOC-E2E-0105',
      current_date, 'KG', 250, 10, 4, 'informed', 'DIFAL sintetico', 5, 'MG',
      'Entrada sintetica E2E'
    );
    raise exception 'changed stock payload reused idempotency key';
  exception when others then
    if sqlerrm = 'changed stock payload reused idempotency key'
       or sqlerrm not like 'idempotency key reused with different stock entry request%' then raise; end if;
  end;

  v_product := public.create_cad_produto_base('1050', 'Produto E2E 0105', 'PRODUTO E2E 0105', 'active', 24);
  v_package := public.create_cad_embalagem('Embalagem E2E 0105', 'EMBALAGEM E2E 0105', 'UN', 'active', 5, false, null);
  v_presentation := public.create_cad_produto_embalagem(v_product, v_package, '1050-5L', 'active');
  insert into public.cad_clientes(nome, nome_norm, cidade, uf, status, created_by, updated_by)
  values ('Cliente E2E 0105', 'cliente e2e 0105', 'Campinas', 'SP', 'active', v_actor, v_actor)
  returning id into v_client;
  insert into public.com_pedidos(codigo_pedido, cliente_id, tipo_pedido, status, data_pedido, valor_total, created_by, updated_by)
  values ('PED-E2E-0105', v_client, 'venda', 'open', current_date, 1000, v_actor, v_actor)
  returning id into v_order;
  insert into public.com_pedido_itens(pedido_id, produto_embalagem_id, tipo_item, quantidade, valor_unitario, percentual_desconto, valor_total, status, created_by, updated_by)
  values (v_order, v_presentation, 'venda', 10, 100, 0, 1000, 'active', v_actor, v_actor)
  returning id into v_order_item;
  insert into public.exp_romaneios(codigo_romaneio, pedido_id, tipo_separacao, status, data_romaneio, created_by, updated_by)
  values ('ROM-E2E-0105', v_order, 'parcial', 'draft', current_date, v_actor, v_actor)
  returning id into v_romaneio;
  insert into public.exp_romaneio_itens(romaneio_id, pedido_id, pedido_item_id, produto_embalagem_id, quantidade_romaneada, quantidade_reservada, status, created_by, updated_by)
  values (v_romaneio, v_order, v_order_item, v_presentation, 4, 0, 'draft', v_actor, v_actor)
  returning id into v_romaneio_item;

  select count(*) into v_before_movements from public.est_movimentos_pa;
  select count(*) into v_before_commissions from public.com_comissao_liberacoes;
  v_simple := public.registrar_fat_referencia_externa_idempotente(
    '10500000-0000-4000-8000-000000000010', v_order, 'simples_faturamento',
    'SF-E2E-0105', '1', current_date, null, null, 'Registro externo sintetico'
  );
  if public.registrar_fat_referencia_externa_idempotente(
    '10500000-0000-4000-8000-000000000010', v_order, 'simples_faturamento',
    'SF-E2E-0105', '1', current_date, null, null, 'Registro externo sintetico'
  ) <> v_simple then raise exception 'simple reference retry did not return original document'; end if;
  v_shipping := public.registrar_fat_referencia_externa_idempotente(
    '10500000-0000-4000-8000-000000000011', v_order, 'remessa_vinculada',
    'REM-E2E-0105', '1', current_date, v_romaneio, v_simple, 'Remessa externa sintetica'
  );
  if (select count(*) from public.fat_nota_fiscal_itens where nota_fiscal_id = v_shipping and romaneio_item_id = v_romaneio_item) <> 1 then
    raise exception 'shipping reference did not inherit romaneio items';
  end if;
  if (select count(*) from public.est_movimentos_pa) <> v_before_movements then raise exception 'external reference moved stock'; end if;
  if (select count(*) from public.com_comissao_liberacoes) <> v_before_commissions then raise exception 'external reference released commission'; end if;

  v_correction := public.corrigir_fat_referencia_externa_numero_idempotente(
    '10500000-0000-4000-8000-000000000012', v_shipping,
    'REM-E2E-0105-CORR', '2', 'Correcao sintetica auditada'
  );
  if public.corrigir_fat_referencia_externa_numero_idempotente(
    '10500000-0000-4000-8000-000000000012', v_shipping,
    'REM-E2E-0105-CORR', '2', 'Correcao sintetica auditada'
  ) <> v_correction then raise exception 'reference correction retry duplicated event'; end if;
  if not exists (
    select 1 from public.fat_nota_fiscal_eventos event
     where event.id = v_correction
       and event.payload_json->>'numero_anterior' = 'REM-E2E-0105'
       and event.payload_json->>'numero_novo' = 'REM-E2E-0105-CORR'
  ) then raise exception 'reference correction did not preserve before and after'; end if;

  perform set_config('request.jwt.claim.sub', v_denied::text, true);
  begin
    perform public.registrar_fat_referencia_externa_idempotente(
      '10500000-0000-4000-8000-000000000020', v_order, 'simples_faturamento',
      'DENIED-0105', null, current_date, null, null, 'Tentativa sem alcada'
    );
    raise exception 'user without authority registered external reference';
  exception when others then
    if sqlerrm = 'user without authority registered external reference'
       or sqlerrm not like 'not allowed:%' then raise; end if;
  end;

  if has_function_privilege('authenticated', 'public.emitir_fat_nota_fiscal_idempotente(uuid,bigint,text,jsonb,text,text,text,date,numeric,bigint,bigint,bigint,jsonb,text)', 'EXECUTE') then
    raise exception 'legacy fiscal emission RPC remains executable';
  end if;
  if has_function_privilege('anon', 'public.registrar_fat_referencia_externa_idempotente(uuid,bigint,text,text,text,date,bigint,bigint,text)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'public.registrar_fat_referencia_externa_idempotente(uuid,bigint,text,text,text,date,bigint,bigint,text)', 'EXECUTE') then
    raise exception 'external reference grants are incorrect';
  end if;
end;
$test$;

set local role authenticated;
do $direct_write$
begin
  begin
    insert into public.fat_notas_fiscais(pedido_id, numero, data_emissao, valor_nf, tipo, status_atual)
    values (1, 'DIRECT', current_date, 0, 'simples_faturamento', 'emitida');
    raise exception 'authenticated direct fiscal write succeeded';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.est_entrada_mp_requisicoes(idempotency_key, lote_mp_id, movimento_mp_id, actor_id, payload_hash)
    values (gen_random_uuid(), 1, 1, gen_random_uuid(), 'x');
    raise exception 'authenticated direct request write succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$direct_write$;
reset role;

rollback;

select 'PG_VALIDATE_0105_OPERATIONAL_ENTRY_EXTERNAL_FISCAL_REFS_OK' as result;
