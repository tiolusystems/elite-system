do $$
declare
  v_actor uuid := '00000000-0000-4000-8000-000000000034';
  v_product_id bigint;
  v_formula_id bigint;
begin
  insert into auth.users(id)
  values (v_actor)
  on conflict (id) do nothing;

  insert into public.user_profiles(
    id, display_name, role, status, is_system_actor, system_actor_key
  ) values (
    v_actor, 'Migracao Historica', 'auditoria', 'inactive', true, 'migracao_historica'
  )
  on conflict (id) do update set
    display_name = excluded.display_name,
    role = excluded.role,
    status = excluded.status,
    is_system_actor = excluded.is_system_actor,
    system_actor_key = excluded.system_actor_key;

  insert into public.cad_materias_primas(
    sku_corrigido, nome, nome_norm, unidade_base_estoque, status,
    payload_origem_json, created_by, updated_by
  ) values (
    'DEC007-UPGRADE-MP', 'DEC-007 upgrade MP', 'dec-007 upgrade mp',
    'quilogramas', 'active', '{}'::jsonb, v_actor, v_actor
  );

  insert into public.cad_produtos_base(
    codigo_produto, nome, nome_norm, status, payload_origem_json,
    created_by, updated_by
  ) values (
    'DEC007-UPGRADE-PROD', 'DEC-007 upgrade product', 'dec-007 upgrade product',
    'active', '{}'::jsonb, v_actor, v_actor
  ) returning id into v_product_id;

  insert into public.cad_garantias_produto_mapa(
    produto_id, nutriente, tipo_limite, valor, unidade, fonte,
    justificativa, created_by
  ) values (
    v_product_id, 'DEC-007 upgrade nutrient', 'declarado', 1,
    'percentual', 'mapa', 'DEC-007 upgrade fixture', v_actor
  );

  insert into public.pcp_formula_versoes(
    produto_id, tipo_receita, versao, justificativa, entry_hash, created_by
  ) values (
    v_product_id, 'producao', 1, 'DEC-007 upgrade fixture',
    repeat('a', 64), v_actor
  ) returning id into v_formula_id;

  insert into public.pcp_formula_itens(
    formula_versao_id, tipo_componente, materia_prima_id,
    quantidade, unidade
  ) values (
    v_formula_id, 'MP',
    (select id from public.cad_materias_primas where sku_corrigido = 'DEC007-UPGRADE-MP'),
    1, 'litros'
  );
end;
$$;
