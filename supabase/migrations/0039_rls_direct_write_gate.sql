-- Close legacy direct-write policies left by the foundation migrations.
-- Authenticated users keep active-profile reads; every write must use an
-- audited SECURITY DEFINER RPC owned by the corresponding domain.

drop policy if exists "authenticated full romaneio access" on public.exp_romaneios;
drop policy if exists "authenticated full romaneio item access" on public.exp_romaneio_itens;
drop policy if exists "authenticated full romaneio pa movement access" on public.exp_romaneio_movimentos_pa;

drop policy if exists "authenticated full PCP formula version access" on public.pcp_formula_versoes;
drop policy if exists "authenticated full PCP formula item access" on public.pcp_formula_itens;
drop policy if exists "authenticated full PCP formula activation access" on public.pcp_formula_ativacoes;
drop policy if exists "authenticated full PCP order access" on public.pcp_ordens_producao;
drop policy if exists "authenticated full PCP planned component access" on public.pcp_op_componentes_planejados;
drop policy if exists "authenticated full PCP reservation access" on public.pcp_op_reservas_componentes;
drop policy if exists "authenticated full PCP consumption access" on public.pcp_op_consumos_componentes;
drop policy if exists "authenticated full PCP CQ access" on public.pcp_op_cq_resultados;
drop policy if exists "authenticated full PCP generated product access" on public.pcp_op_produtos_gerados;

drop policy if exists "authenticated full commercial area access" on public.cad_areas_comerciais;
drop policy if exists "authenticated full commercial area membership access" on public.cad_pessoa_areas_comerciais;
drop policy if exists "authenticated full NFe XML access" on public.imp_nfe_xmls;
drop policy if exists "authenticated full NFe XML item access" on public.imp_nfe_xml_itens;
drop policy if exists "authenticated full NFe match candidate access" on public.imp_nfe_item_match_candidatos;
drop policy if exists "authenticated full NFe resolution access" on public.imp_nfe_item_resolucoes;
drop policy if exists "authenticated full NFe MP lot link access" on public.imp_nfe_item_lotes_mp;

drop policy if exists "authenticated full source workbook access" on public.source_workbooks;
drop policy if exists "authenticated full migration batch access" on public.migration_batches;
drop policy if exists "authenticated full source table access" on public.source_tables;
drop policy if exists "authenticated full source row access" on public.source_rows;
drop policy if exists "authenticated full migration issue access" on public.migration_issues;
drop policy if exists "authenticated full imported record access" on public.imported_records;
drop policy if exists "authenticated full audit snapshot access" on public.audit_snapshots;
drop policy if exists "authenticated full expected metric access" on public.source_expected_metrics;
drop policy if exists "authenticated full reconciliation run access" on public.audit_reconciliation_runs;
drop policy if exists "authenticated full value reconciliation access" on public.value_reconciliations;
drop policy if exists "authenticated full reconciliation detail access" on public.reconciliation_details;

do $$
declare
  v_table text;
  v_policy text;
begin
  foreach v_table in array array[
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
  ]
  loop
    v_policy := 'active user read ' || v_table;
    execute format('drop policy if exists %I on public.%I', v_policy, v_table);
    execute format(
      'create policy %I on public.%I for select to authenticated using (public.current_actor_id() is not null)',
      v_policy,
      v_table
    );
    execute format('grant select on public.%I to authenticated', v_table);
    execute format(
      'revoke insert, update, delete, truncate, references, trigger on public.%I from authenticated',
      v_table
    );
    execute format('revoke all on public.%I from anon', v_table);
  end loop;
end;
$$;

-- TRUNCATE bypasses RLS. Remove every non-read table privilege from the web
-- roles across the current schema, including domains hardened earlier.
do $$
declare
  v_table text;
begin
  for v_table in
    select tablename
      from pg_tables
     where schemaname = 'public'
  loop
    execute format(
      'revoke insert, update, delete, truncate, references, trigger on public.%I from authenticated',
      v_table
    );
    execute format('revoke all on public.%I from anon', v_table);
  end loop;
end;
$$;

alter default privileges for role postgres in schema public
  revoke insert, update, delete, truncate, references, trigger on tables from authenticated;
alter default privileges for role postgres in schema public
  revoke all on tables from anon;

comment on policy "active user read exp_romaneios" on public.exp_romaneios is
  'Writes are available only through audited romaneio RPCs; direct authenticated DML is revoked.';

comment on policy "active user read pcp_ordens_producao" on public.pcp_ordens_producao is
  'Writes are available only through audited PCP RPCs; direct authenticated DML is revoked.';

comment on policy "active user read imp_nfe_xmls" on public.imp_nfe_xmls is
  'Writes are available only through audited import RPCs; direct authenticated DML is revoked.';

comment on policy "active user read source_workbooks" on public.source_workbooks is
  'Raw migration and reconciliation facts are written only by controlled import/audit boundaries.';
