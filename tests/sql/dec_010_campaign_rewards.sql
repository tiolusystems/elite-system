\set ON_ERROR_STOP on

begin;

do $dec010$
declare
  v_migration_actor uuid := public.historical_migration_actor_id();
  v_human_actor uuid := '00000000-0000-4000-8000-000000000753';
  v_workbook_id bigint;
  v_batch_id bigint;
  v_table_id bigint;
  v_source_row_id bigint;
  v_person_id bigint;
  v_group_id bigint;
  v_product_id bigint;
  v_campaign_id bigint;
  v_version_id bigint;
  v_rule_id bigint;
  v_money_reward_id bigint;
  v_voucher_reward_id bigint;
  v_points_movement_id bigint;
  v_prize_id bigint;
  v_voucher_prize_id bigint;
  v_voucher_id bigint;
  v_second_campaign_id bigint;
  v_second_version_id bigint;
  v_second_rule_id bigint;
  v_historical_campaign_id bigint;
  v_historical_version_id bigint;
  v_commission_count_before bigint;
begin
  if v_migration_actor is null then
    raise exception 'DEC-010 smoke requires Migracao Historica actor';
  end if;

  insert into auth.users(id) values (v_human_actor)
  on conflict (id) do nothing;
  insert into public.user_profiles(id, display_name, role, status)
  values (v_human_actor, 'DEC-010 Human Reviewer', 'admin', 'active')
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
    'test', 'test_reset', 'Validacao transacional da DEC-010 em PostgreSQL local'
  );
  select count(*) into v_commission_count_before
    from public.fin_comissao_movimentos;

  insert into public.source_workbooks(
    file_name, sha256, size_bytes, metadata_json, created_by
  ) values (
    'dec010-fixture.xlsx', repeat('3', 64), 1000,
    '{"fixture":true}'::jsonb, v_migration_actor
  ) returning id into v_workbook_id;
  insert into public.migration_batches(workbook_id, status, notes, created_by, updated_by)
  values (v_workbook_id, 'running', 'DEC-010 fixture', v_migration_actor, v_migration_actor)
  returning id into v_batch_id;
  insert into public.source_tables(
    workbook_id, sheet_name, table_name, ref, header_row, data_first_row,
    data_last_row, column_count, row_count, metadata_json
  ) values (
    v_workbook_id, 'Pontuacao', 'DEC010Fixture', 'A1:H2', 1, 2, 2, 8, 1, '{}'::jsonb
  ) returning id into v_table_id;
  insert into public.source_rows(
    table_id, excel_row_number, row_index, row_hash, payload_json, formulas_json
  ) values (
    v_table_id, 2, 0, repeat('4', 64), '{"fixture":true}'::jsonb, '{}'::jsonb
  ) returning id into v_source_row_id;

  insert into public.cad_pessoas_comerciais(
    nome, nome_norm, papeis_json, status, payload_origem_json,
    created_by, updated_by, origem_dados
  ) values (
    'Vendedor DEC-010', 'vendedor dec-010', '["vendedor"]'::jsonb,
    'active', '{}'::jsonb, v_human_actor, v_human_actor, 'sistema'
  ) returning id into v_person_id;

  insert into public.cad_grupos_produto(
    codigo, nome, status, origem_dados, created_by
  ) values (
    'GRUPO-DEC010', 'Grupo DEC-010', 'active', 'sistema', v_human_actor
  ) returning id into v_group_id;

  insert into public.cad_produtos_base(
    codigo_produto, nome, nome_norm, grupo, grupo_id, status,
    payload_origem_json, created_by, updated_by, origem_dados
  ) values (
    '8010', 'Produto DEC-010', 'produto dec-010', 'GRUPO-DEC010', v_group_id,
    'active', '{}'::jsonb, v_human_actor, v_human_actor, 'sistema'
  ) returning id into v_product_id;

  insert into public.com_campanhas(
    codigo, nome, status, origem_dados, created_by
  ) values (
    'CAMP-DEC010-A', 'Campanha DEC-010 A', 'active', 'sistema', v_human_actor
  ) returning id into v_campaign_id;
  insert into public.com_campanha_versoes(
    campanha_id, versao, data_inicio, data_fim, review_status,
    justificativa, origem_dados, created_by
  ) values (
    v_campaign_id, 1, current_date - 1, current_date + 30, 'approved',
    'Fixture aprovada', 'sistema', v_human_actor
  ) returning id into v_version_id;
  insert into public.com_campanha_regras(
    campanha_versao_id, codigo, base_tipo, grupo_produto_id,
    limiar_minimo, limiar_maximo, review_status, origem_dados, created_by
  ) values (
    v_version_id, 'FAIXA-1', 'volume_litros', v_group_id,
    100, 500, 'approved', 'sistema', v_human_actor
  ) returning id into v_rule_id;
  insert into public.com_campanha_regra_recompensas(
    regra_id, tipo_recompensa, pontos, review_status, origem_dados, created_by
  ) values (
    v_rule_id, 'pontos', 100, 'approved', 'sistema', v_human_actor
  );
  insert into public.com_campanha_regra_recompensas(
    regra_id, tipo_recompensa, valor_monetario, review_status, origem_dados, created_by
  ) values (
    v_rule_id, 'monetario', 500, 'approved', 'sistema', v_human_actor
  ) returning id into v_money_reward_id;
  insert into public.com_campanha_regra_recompensas(
    regra_id, tipo_recompensa, descricao, review_status, origem_dados, created_by
  ) values (
    v_rule_id, 'voucher_viagem', 'Voucher de viagem DEC-010',
    'approved', 'sistema', v_human_actor
  ) returning id into v_voucher_reward_id;
  insert into public.com_campanha_elegibilidades(
    campanha_versao_id, escopo_tipo, pessoa_id,
    review_status, origem_dados, created_by
  ) values (
    v_version_id, 'pessoa', v_person_id, 'approved', 'sistema', v_human_actor
  );
  insert into public.com_campanha_versao_ativacoes(
    campanha_versao_id, tipo_evento, motivo, created_by
  ) values (v_version_id, 'ativacao', 'Fixture DEC-010', v_human_actor);

  if not exists (
    select 1 from public.com_campanha_configuracoes_atuais current_campaign
    where current_campaign.campanha_versao_id = v_version_id
  ) then
    raise exception 'approved campaign version did not reach current view';
  end if;

  begin
    insert into public.com_campanha_versao_ativacoes(
      campanha_versao_id, tipo_evento, motivo, created_by
    ) values (v_version_id, 'ativacao', 'System actor attempt', v_migration_actor);
    raise exception 'system actor activated campaign';
  exception when others then
    if sqlerrm <> 'only active human profiles can activate campaign versions' then
      raise;
    end if;
  end;

  insert into public.com_campanha_pontos_movimentos(
    campanha_versao_id, regra_id, pessoa_id, produto_id, grupo_produto_id,
    tipo_movimento, pontos, base_quantidade, data_competencia,
    review_status, origem_dados, created_by
  ) values (
    v_version_id, v_rule_id, v_person_id, v_product_id, v_group_id,
    'credito', 100, 120, current_date, 'approved', 'sistema', v_human_actor
  ) returning id into v_points_movement_id;
  insert into public.com_campanha_pontos_movimentos(
    campanha_versao_id, regra_id, pessoa_id, produto_id, grupo_produto_id,
    tipo_movimento, pontos, data_competencia,
    review_status, origem_dados, created_by
  ) values (
    v_version_id, v_rule_id, v_person_id, v_product_id, v_group_id,
    'estorno', -20, current_date, 'approved', 'sistema', v_human_actor
  );

  if (select pontos_saldo from public.com_campanha_pontos_saldos
      where campanha_versao_id = v_version_id and pessoa_id = v_person_id) <> 80 then
    raise exception 'campaign points ledger balance is incorrect';
  end if;

  begin
    update public.com_campanha_pontos_movimentos set pontos = 90
    where id = v_points_movement_id;
    raise exception 'campaign points ledger was updated';
  exception when others then
    if sqlerrm not like 'com_campanha_pontos_movimentos is append-only%' then
      raise;
    end if;
  end;

  insert into public.com_campanha_premios(
    campanha_versao_id, recompensa_id, pessoa_id, tipo_premio,
    valor_monetario, review_status, origem_dados, created_by
  ) values (
    v_version_id, v_money_reward_id, v_person_id, 'monetario',
    500, 'approved', 'sistema', v_human_actor
  ) returning id into v_prize_id;
  insert into public.com_campanha_premio_eventos(premio_id, tipo_evento, created_by)
  values (v_prize_id, 'gerado', v_human_actor), (v_prize_id, 'aprovado', v_human_actor);
  insert into public.fin_campanha_premio_pagamentos(
    premio_id, tipo_evento, valor, data_evento,
    review_status, origem_dados, created_by
  ) values (
    v_prize_id, 'pago', 500, current_date, 'approved', 'sistema', v_human_actor
  );

  if not exists (
    select 1 from public.com_campanha_premios_status_atual
    where premio_id = v_prize_id and status_atual = 'aprovado'
  ) then
    raise exception 'prize lifecycle view is incorrect';
  end if;

  insert into public.com_campanha_premios(
    campanha_versao_id, recompensa_id, pessoa_id, tipo_premio,
    descricao, review_status, origem_dados, created_by
  ) values (
    v_version_id, v_voucher_reward_id, v_person_id, 'voucher_viagem',
    'Voucher de viagem DEC-010', 'approved', 'sistema', v_human_actor
  ) returning id into v_voucher_prize_id;
  insert into public.com_campanha_vouchers(
    premio_id, codigo, validade_inicio, validade_fim,
    review_status, origem_dados, created_by
  ) values (
    v_voucher_prize_id, 'VOUCHER-DEC010', current_date, current_date + 365,
    'approved', 'sistema', v_human_actor
  ) returning id into v_voucher_id;
  insert into public.com_campanha_voucher_eventos(voucher_id, tipo_evento, created_by)
  values (v_voucher_id, 'emitido', v_human_actor);

  if (select count(*) from public.fin_comissao_movimentos) <> v_commission_count_before then
    raise exception 'campaign reward polluted commission ledger';
  end if;

  insert into public.com_campanhas(
    codigo, nome, status, origem_dados, created_by
  ) values (
    'CAMP-DEC010-B', 'Campanha DEC-010 B', 'active', 'sistema', v_human_actor
  ) returning id into v_second_campaign_id;
  insert into public.com_campanha_versoes(
    campanha_id, versao, data_inicio, data_fim, review_status,
    origem_dados, created_by
  ) values (
    v_second_campaign_id, 1, current_date - 1, current_date + 10,
    'approved', 'sistema', v_human_actor
  ) returning id into v_second_version_id;
  insert into public.com_campanha_regras(
    campanha_versao_id, codigo, base_tipo, limiar_minimo,
    review_status, origem_dados, created_by
  ) values (
    v_second_version_id, 'GLOBAL', 'valor_venda', 1,
    'approved', 'sistema', v_human_actor
  ) returning id into v_second_rule_id;
  insert into public.com_campanha_regra_recompensas(
    regra_id, tipo_recompensa, pontos, review_status, origem_dados, created_by
  ) values (
    v_second_rule_id, 'pontos', 1, 'approved', 'sistema', v_human_actor
  );
  insert into public.com_campanha_elegibilidades(
    campanha_versao_id, escopo_tipo, review_status, origem_dados, created_by
  ) values (
    v_second_version_id, 'todos', 'approved', 'sistema', v_human_actor
  );
  insert into public.com_campanha_versao_ativacoes(
    campanha_versao_id, tipo_evento, motivo, created_by
  ) values (v_second_version_id, 'ativacao', 'Concorrencia permitida', v_human_actor);

  if (select count(*) from public.com_campanha_configuracoes_atuais) <> 2 then
    raise exception 'simultaneous active campaigns were not preserved';
  end if;

  insert into public.com_campanhas(
    codigo, nome, status, origem_dados, source_batch_id, source_row_id, created_by
  ) values (
    'CAMP-LEGADO', 'Campanha legado', 'pending_review',
    'excel_legado', v_batch_id, v_source_row_id, v_migration_actor
  ) returning id into v_historical_campaign_id;
  insert into public.com_campanha_versoes(
    campanha_id, versao, review_status, origem_dados,
    source_batch_id, source_row_id, created_by
  ) values (
    v_historical_campaign_id, 1, 'pending_review', 'excel_legado',
    v_batch_id, v_source_row_id, v_migration_actor
  ) returning id into v_historical_version_id;
  insert into public.com_campanha_pontos_movimentos(
    campanha_versao_id, pessoa_id, tipo_movimento, pontos,
    review_status, origem_dados, source_batch_id, source_row_id, created_by
  ) values (
    v_historical_version_id, v_person_id, 'credito', 10,
    'pending_review', 'excel_legado', v_batch_id, v_source_row_id, v_migration_actor
  );

  if exists (
    select 1 from public.com_campanha_pontos_saldos
    where campanha_versao_id = v_historical_version_id
  ) then
    raise exception 'historical pending points reached approved balance';
  end if;

  begin
    update public.com_campanhas set status = 'active'
    where id = v_historical_campaign_id;
    raise exception 'historical campaign was promoted by update';
  exception when others then
    if sqlerrm not like 'excel_legado requires status = pending_review%' then
      raise;
    end if;
  end;
end;
$dec010$;

rollback;

select 'DEC_010_CAMPAIGN_REWARDS_SMOKE_OK' as result;
