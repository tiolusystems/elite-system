do $$
declare
  v_actor uuid := public.historical_migration_actor_id();
  v_product_id bigint;
  v_mp_id bigint;
  v_formula_id bigint;
begin
  insert into public.cad_produtos_base(
    codigo_produto, nome, nome_norm, status, payload_origem_json,
    created_by, updated_by, origem_dados
  ) values (
    'DEC006-UPGRADE', 'DEC-006 upgrade product', 'dec-006 upgrade product',
    'active', '{}'::jsonb, v_actor, v_actor, 'sistema'
  ) returning id into v_product_id;
  insert into public.cad_materias_primas(
    sku_corrigido, nome, nome_norm, unidade_base_estoque, status,
    payload_origem_json, created_by, updated_by, origem_dados
  ) values (
    'DEC006-UPGRADE-MP', 'DEC-006 upgrade MP', 'dec-006 upgrade mp',
    'kg', 'active', '{}'::jsonb, v_actor, v_actor, 'sistema'
  ) returning id into v_mp_id;
  insert into public.pcp_formula_versoes(
    produto_id, tipo_receita, versao, justificativa, entry_hash, created_by
  ) values (
    v_product_id, 'producao', 1, 'Upgrade fixture', repeat('d', 64), v_actor
  ) returning id into v_formula_id;
  insert into public.pcp_formula_itens(
    formula_versao_id, tipo_componente, materia_prima_id,
    quantidade, unidade, unidade_id
  ) values (
    v_formula_id, 'MP', v_mp_id, 1, 'kg', public.resolve_cad_unidade_id('kg')
  );
  insert into public.pcp_ordens_producao(
    codigo_op, formula_versao_id, tipo_op, status,
    quantidade_planejada, created_by, updated_by
  ) values (
    'DEC006-UPGRADE-OP', v_formula_id, 'estoque', 'completed', 10,
    v_actor, v_actor
  );
end;
$$;
