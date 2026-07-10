\set ON_ERROR_STOP on

begin;

do $contract$
declare
  v_table text;
  v_privilege text;
  v_tables text[] := array[
    'exp_romaneios',
    'exp_romaneio_itens',
    'exp_romaneio_movimentos_pa',
    'pcp_formula_versoes',
    'pcp_formula_itens',
    'pcp_formula_ativacoes',
    'pcp_ordens_producao',
    'pcp_op_componentes_planejados',
    'pcp_op_reservas_componentes',
    'pcp_op_consumos_componentes',
    'pcp_op_cq_resultados',
    'pcp_op_produtos_gerados',
    'imp_nfe_xmls',
    'imp_nfe_xml_itens',
    'imp_nfe_item_match_candidatos',
    'imp_nfe_item_resolucoes',
    'imp_nfe_item_lotes_mp',
    'source_workbooks',
    'migration_batches',
    'source_tables',
    'source_rows',
    'migration_issues',
    'imported_records',
    'audit_snapshots',
    'source_expected_metrics',
    'audit_reconciliation_runs',
    'value_reconciliations',
    'reconciliation_details'
  ];
  v_required_constraints text[] := array[
    'cad_clientes_source_row_fk',
    'cad_clientes_source_batch_fk',
    'cad_pessoas_source_row_fk',
    'cad_pessoas_source_batch_fk',
    'cad_mp_source_row_fk',
    'cad_mp_source_batch_fk',
    'cad_produtos_source_row_fk',
    'cad_produtos_source_batch_fk',
    'cadastro_issues_source_batch_fk',
    'cad_garantias_lote_mp_lote_fk',
    'pcp_cq_participantes_resultado_op_fk',
    'est_movimentos_pa_lote_produto_fk',
    'est_movimentos_mp_lote_materia_fk',
    'est_movimentos_pi_lote_produto_fk',
    'est_reservas_pa_lote_produto_fk',
    'est_reservas_pa_romaneio_item_fk',
    'exp_romaneio_itens_romaneio_pedido_fk',
    'exp_romaneio_itens_pedido_item_fk',
    'exp_mov_pa_romaneio_item_identity_fk',
    'exp_mov_pa_lote_produto_fk',
    'fat_nf_itens_nota_pedido_fk',
    'fat_nf_itens_nota_romaneio_fk',
    'fat_nf_itens_pedido_item_fk',
    'fat_nf_itens_romaneio_item_fk',
    'pcp_formula_ativacoes_identity_fk',
    'pcp_reservas_componente_op_fk',
    'pcp_consumos_componente_op_fk',
    'pcp_consumos_reserva_identity_fk'
  ];
begin
  foreach v_table in array v_tables
  loop
    if exists (
      select 1
        from pg_policies
       where schemaname = 'public'
         and tablename = v_table
         and upper(cmd) in ('ALL', 'INSERT', 'UPDATE', 'DELETE')
    ) then
      raise exception 'write-capable RLS policy survived for table %', v_table;
    end if;

    if not has_table_privilege('authenticated', format('public.%I', v_table), 'SELECT') then
      raise exception 'authenticated read grant missing for table %', v_table;
    end if;

    foreach v_privilege in array array['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']
    loop
      if has_table_privilege('authenticated', format('public.%I', v_table), v_privilege) then
        raise exception 'authenticated still has % on table %', v_privilege, v_table;
      end if;
    end loop;
  end loop;

  if exists (
    select 1
      from pg_constraint
     where conname = any(v_required_constraints)
       and not convalidated
  ) then
    raise exception 'one or more architecture constraints are not validated';
  end if;

  if (
    select count(*)
      from pg_constraint
     where conname = any(v_required_constraints)
  ) <> cardinality(v_required_constraints) then
    raise exception 'one or more architecture constraints are missing';
  end if;

  if exists (
    select 1
      from pg_constraint constraint_def
     where constraint_def.conname = any(v_required_constraints)
       and not exists (
         select 1
           from pg_index index_def
          where index_def.indrelid = constraint_def.conrelid
            and index_def.indisvalid
            and index_def.indkey[0] = constraint_def.conkey[1]
       )
  ) then
    raise exception 'one or more architecture foreign keys lack a supporting child index';
  end if;

  if not exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'cad_garantias_lote_mp'
       and column_name = 'lote_mp_id'
       and data_type = 'bigint'
  ) then
    raise exception 'cad_garantias_lote_mp.lote_mp_id is not a typed bigint relation';
  end if;

  if not exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'cad_pessoa_papeis'
  ) then
    raise exception 'cad_pessoa_papeis relational table is missing';
  end if;

  if not exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'pcp_op_cq_participantes'
  ) then
    raise exception 'pcp_op_cq_participantes relational table is missing';
  end if;
end;
$contract$;

do $behavior$
declare
  v_mp_id bigint;
  v_other_mp_id bigint;
  v_lote_id bigint;
  v_pessoa_id bigint;
begin
  insert into public.cad_pessoas_comerciais(
    nome, nome_norm, papeis_json, status
  )
  values (
    'Architecture Gate Person',
    'ARCHITECTURE GATE PERSON',
    '["vendedor", "entregador"]'::jsonb,
    'active'
  )
  returning id into v_pessoa_id;

  if (
    select count(*)
      from public.cad_pessoa_papeis
     where pessoa_id = v_pessoa_id and status = 'active'
  ) <> 2 then
    raise exception 'commercial roles were not expanded into relational rows';
  end if;

  update public.cad_pessoas_comerciais
     set papeis_json = '["vendedor", "gerente"]'::jsonb
   where id = v_pessoa_id;

  if not exists (
    select 1 from public.cad_pessoa_papeis
    where pessoa_id = v_pessoa_id and papel = 'entregador' and status = 'inactive'
  ) or not exists (
    select 1 from public.cad_pessoa_papeis
    where pessoa_id = v_pessoa_id and papel = 'gerente' and status = 'active'
  ) then
    raise exception 'commercial role history was not synchronized';
  end if;

  insert into public.cad_materias_primas(
    sku_corrigido, nome, nome_norm, unidade_base_estoque, status
  )
  values ('ARCH-GATE-MP-1', 'Architecture Gate MP 1', 'ARCHITECTURE GATE MP 1', 'KG', 'active')
  returning id into v_mp_id;

  insert into public.cad_materias_primas(
    sku_corrigido, nome, nome_norm, unidade_base_estoque, status
  )
  values ('ARCH-GATE-MP-2', 'Architecture Gate MP 2', 'ARCHITECTURE GATE MP 2', 'KG', 'active')
  returning id into v_other_mp_id;

  insert into public.est_lotes_mp(materia_prima_id, codigo_lote, status)
  values (v_mp_id, 'ARCH-GATE-LOT', 'disponivel')
  returning id into v_lote_id;

  insert into public.est_movimentos_mp(
    lote_mp_id, materia_prima_id, tipo_movimento, quantidade, origem_modulo
  )
  values (v_lote_id, v_mp_id, 'importacao_inicial', 10, 'architecture_gate');

  begin
    update public.cad_materias_primas
       set unidade_base_estoque = 'T'
     where id = v_mp_id;
    raise exception 'unit guard did not reject a historical unit change';
  exception
    when others then
      if sqlerrm = 'unit guard did not reject a historical unit change'
         or sqlerrm not like 'unidade_base_estoque cannot change after the first MP movement%' then
        raise;
      end if;
  end;

  begin
    insert into public.est_movimentos_mp(
      lote_mp_id, materia_prima_id, tipo_movimento, quantidade, origem_modulo
    )
    values (v_lote_id, v_other_mp_id, 'importacao_inicial', 1, 'architecture_gate');
    raise exception 'composite stock identity FK did not reject a mismatched material';
  exception
    when foreign_key_violation then
      null;
    when others then
      raise;
  end;
end;
$behavior$;

rollback;

\echo PG_ARCHITECTURE_INTEGRITY_GATE_OK
