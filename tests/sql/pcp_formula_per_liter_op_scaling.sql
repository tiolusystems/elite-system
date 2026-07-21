begin;

do $$
declare
  v_actor uuid := '00000000-0000-4000-8000-000000000775';
  v_product_id bigint;
  v_input_product_id bigint;
  v_unit_id bigint;
  v_formula_id bigint;
  v_legacy_formula_id bigint;
  v_op_id bigint;
  v_component_total numeric;
begin
  insert into auth.users(id) values (v_actor) on conflict (id) do nothing;
  insert into public.user_profiles(id, display_name, role, status)
  values (v_actor, 'Formula scaling reviewer', 'admin', 'active')
  on conflict (id) do update set status = 'active';
  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  values
    (v_actor, 'system.admin', true, v_actor),
    (v_actor, 'pcp.formula.create', true, v_actor),
    (v_actor, 'pcp.formula.change', true, v_actor),
    (v_actor, 'pcp.op.create', true, v_actor)
  on conflict (user_id, action_key) do update set allowed = true, updated_by = excluded.updated_by;
  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  if public.current_system_environment() = 'unconfigured' then
    perform public.set_system_runtime_environment('test', 'test_reset', '0075 disposable formula scaling smoke');
  elsif public.current_system_environment() <> 'test' then
    raise exception '0075 smoke requires disposable test environment';
  end if;

  insert into public.cad_produtos_base(codigo_produto, nome, nome_norm, status, payload_origem_json, created_by, updated_by, origem_dados)
  values ('9775', 'Finished product fixture', 'finished product fixture', 'active', '{}', v_actor, v_actor, 'sistema')
  returning id into v_product_id;
  insert into public.cad_produtos_base(codigo_produto, nome, nome_norm, status, payload_origem_json, created_by, updated_by, origem_dados)
  values ('9776', 'Intermediate input fixture', 'intermediate input fixture', 'active', '{}', v_actor, v_actor, 'sistema')
  returning id into v_input_product_id;
  select id into v_unit_id from public.cad_unidades_medida where codigo = 'kg_l_produzido';

  v_formula_id := public.create_pcp_formula_versao(
    v_product_id, 'producao', 'Formula por litro para teste',
    jsonb_build_array(jsonb_build_object(
      'tipo_componente', 'PI', 'produto_id', v_input_product_id,
      'quantidade', 0.25, 'unidade_id', v_unit_id
    )), null
  );
  if (select base_calculo from public.pcp_formula_versoes where id = v_formula_id) <> 'por_litro' then
    raise exception 'new production formula did not freeze per-liter basis';
  end if;

  v_op_id := public.create_pcp_op(v_formula_id, 'estoque', 1000, 'Scaling fixture');
  select quantidade_planejada into v_component_total
    from public.pcp_op_componentes_planejados where op_id = v_op_id;
  if v_component_total <> 250 then raise exception 'expected 250 total component units, got %', v_component_total; end if;
  if not exists (
    select 1 from public.pcp_op_componentes_planejados
     where op_id = v_op_id and quantidade_formula_por_litro = 0.25
       and volume_planejado_l = 1000 and unidade_formula_id = v_unit_id
  ) then raise exception 'OP did not freeze formula scaling evidence'; end if;

  insert into public.pcp_formula_versoes(
    produto_id, tipo_receita, versao, justificativa, entry_hash, created_by
  ) values (
    v_product_id, 'producao', 99, 'Legacy fixture', repeat('9', 64), v_actor
  ) returning id into v_legacy_formula_id;
  begin
    perform public.create_pcp_op(v_legacy_formula_id, 'estoque', 100, null);
    raise exception 'legacy formula should not open an operational OP';
  exception when others then
    if sqlerrm not like 'legacy formula requires%' then raise; end if;
  end;

  begin
    perform public.create_pcp_op(v_formula_id, 'estoque', null, null);
    raise exception 'OP without planned liters should have failed';
  exception when others then
    if sqlerrm not like 'planned production volume%' then raise; end if;
  end;

  begin
    perform public.create_pcp_formula_versao(
      v_product_id, 'producao', 'Invalid unit fixture',
      jsonb_build_array(jsonb_build_object(
        'tipo_componente', 'PI', 'produto_id', v_input_product_id,
        'quantidade', 1, 'unidade_id', (select id from public.cad_unidades_medida where codigo = 'kg')
      )), null
    );
    raise exception 'non per-liter unit should have failed';
  exception when others then
    if sqlerrm not like 'invalid per-liter formula unit%' then raise; end if;
  end;

  if has_function_privilege('anon', 'public.create_pcp_op(bigint,text,numeric,text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.create_pcp_formula_versao(bigint,text,text,jsonb,text)', 'EXECUTE') then
    raise exception 'anon can execute governed formula or OP creation';
  end if;
end;
$$;

rollback;
select 'PG_VALIDATE_0075_PCP_FORMULA_PER_LITER_OP_SCALING_OK' as result;
