\set ON_ERROR_STOP on

begin;

do $products_packaging$
declare
  v_actor uuid := '00000000-0000-4000-8000-000000000068';
  v_unit_kg bigint;
  v_unit_un bigint;
  v_material_id bigint;
  v_product_id bigint;
  v_package_id bigint;
  v_sale_item_id bigint;
  v_version_id bigint;
  v_component_id bigint;
  v_ratio numeric;
begin
  insert into auth.users(id) values (v_actor) on conflict (id) do nothing;
  insert into public.user_profiles(id, display_name, role, status)
  values (v_actor, 'Products Packaging Smoke Actor', 'admin', 'active')
  on conflict (id) do update set display_name = excluded.display_name, role = excluded.role, status = excluded.status;
  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  select v_actor, action.action_key, true, v_actor from public.permission_actions action
  on conflict (user_id, action_key) do update set allowed = true, updated_by = excluded.updated_by;
  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  perform public.set_system_runtime_environment('test', 'test_reset', 'Smoke transacional da migration 0068');

  select id into v_unit_kg from public.cad_unidades_medida where lower(codigo) = 'kg' and status = 'active';
  select id into v_unit_un from public.cad_unidades_medida where lower(codigo) = 'un' and status = 'active';
  if v_unit_kg is null or v_unit_un is null then raise exception 'canonical KG/UN units not found'; end if;

  v_material_id := public.create_cad_materia_prima_governada(
    p_nome => 'Componente sintetico 0068',
    p_nome_norm => 'COMPONENTE SINTETICO 0068',
    p_sku_corrigido => 'MP-0068-COMP',
    p_unidade_base_estoque_id => v_unit_un,
    p_status => 'active'
  );

  v_product_id := public.create_cad_produto_base(
    p_codigo_produto => '0681', p_nome => 'Produto sintetico 0068',
    p_nome_norm => 'PRODUTO SINTETICO 0068', p_status => 'active',
    p_prazo_validade_meses => 24
  );

  v_package_id := public.create_cad_embalagem(
    p_descricao => 'Galao sintetico 5 L 0068',
    p_descricao_norm => 'GALAO SINTETICO 5 L 0068',
    p_unidade => 'UN', p_status => 'active', p_volume_litros => 5,
    p_controla_estoque => true, p_materia_prima_id => v_material_id
  );

  v_sale_item_id := public.create_cad_produto_embalagem(
    v_product_id, v_package_id, '0681-5L', 'active'
  );

  perform public.update_cad_produto_identity(
    v_product_id, '0681', 'Produto sintetico revisado 0068', null,
    'Ajuste de identidade para o smoke 0068'
  );
  perform public.update_cad_produto_technical(
    v_product_id, 1.15, 30, 'Atualizacao tecnica controlada para o smoke'
  );
  perform public.update_cad_produto_regulatory(
    v_product_id, 'MAPA-0068', '12345678', null, null,
    'Atualizacao regulatoria controlada para o smoke'
  );
  perform public.update_cad_embalagem_identity(
    v_package_id, 'Galao sintetico revisado 5 L 0068', null,
    'Ajuste de identidade da embalagem no smoke'
  );
  perform public.update_cad_embalagem_physical(
    v_package_id, v_unit_un, 5, true, v_material_id,
    'Confirmacao da capacidade de cinco litros'
  );

  v_version_id := public.create_cad_embalagem_versao_un_l(
    v_package_id, date '2026-01-01', null, 0.25, 0.02,
    'Primeira composicao sintetica normalizada'
  );
  select unidades_embalagem_por_litro into v_ratio
    from public.cad_embalagem_versoes where id = v_version_id;
  if v_ratio <> 0.2 then raise exception '5 L package ratio is %, expected 0.2 UN/L', v_ratio; end if;

  v_component_id := public.add_cad_embalagem_componente_un_l(
    v_version_id, v_material_id, 0.2,
    'Um componente por galao de cinco litros'
  );
  if not exists (
    select 1 from public.cad_embalagem_componentes
     where id = v_component_id and quantidade_un_l = 0.2 and status = 'active'
  ) then raise exception 'normalized component was not persisted'; end if;

  perform public.review_cad_embalagem_versao(
    v_version_id, 'approved', 'Composicao sintetica conferida'
  );
  perform public.activate_cad_embalagem_versao(
    v_version_id, true, 'Ativacao sintetica para validacao'
  );

  if not exists (
    select 1 from public.cad_embalagem_configuracoes_atuais
     where embalagem_id = v_package_id and unidades_embalagem_por_litro = 0.2
  ) then raise exception 'active package configuration did not expose UN/L'; end if;
  if not exists (
    select 1 from public.cad_embalagem_componentes_atuais
     where componente_id = v_component_id and quantidade_un_l = 0.2
  ) then raise exception 'active package component did not expose UN/L'; end if;

  perform public.set_cad_apresentacao_active_state(
    v_sale_item_id, false, 'Desativacao sintetica da apresentacao'
  );
  perform public.set_cad_embalagem_active_state(
    v_package_id, false, 'Desativacao sintetica da embalagem'
  );
  perform public.set_cad_embalagem_active_state(
    v_package_id, true, 'Reativacao sintetica da embalagem'
  );
  perform public.set_cad_produto_active_state(
    v_product_id, false, 'Desativacao sintetica do produto'
  );
  perform public.set_cad_produto_active_state(
    v_product_id, true, 'Reativacao sintetica do produto'
  );

  if not exists (
    select 1 from public.action_logs
     where entity_type = 'cad_embalagem_versoes'
       and entity_id = v_version_id::text
       and action_key = 'cadastros.embalagens.composition.version.create'
       and metadata_json->>'normalized_basis' = 'UN/L'
  ) then raise exception 'package version UN/L audit log was not found'; end if;

  begin
    insert into public.cad_embalagens(
      descricao, descricao_norm, unidade, volume_litros, status, created_by, updated_by
    ) values (
      'Embalagem invalida 0068', 'EMBALAGEM INVALIDA 0068', 'KG', 5, 'active', v_actor, v_actor
    );
    raise exception 'system package outside UN was accepted';
  exception when others then
    if sqlerrm <> 'system package requires UN unit and positive liter capacity' then raise; end if;
  end;
end;
$products_packaging$;

do $denied_user$
declare
  v_actor uuid := '00000000-0000-4000-8000-000000000168';
begin
  insert into auth.users(id) values (v_actor) on conflict (id) do nothing;
  insert into public.user_profiles(id, display_name, role, status)
  values (v_actor, 'Products Packaging Denied Actor', 'auditoria', 'active')
  on conflict (id) do update set status = 'active';
  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  values (v_actor, 'cadastros.produtos.update.identity', false, v_actor)
  on conflict (user_id, action_key) do update set allowed = false, updated_by = excluded.updated_by;
  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  begin
    perform public.update_cad_produto_identity(1, '9999', 'Negado', null, 'Operacao sem alcada');
    raise exception 'user without product identity permission was accepted';
  exception when others then
    if sqlerrm not like '%not allowed: cadastros.produtos.update.identity%' then raise; end if;
  end;
end;
$denied_user$;

do $privileges$
declare
  v_function text;
begin
  foreach v_function in array array[
    'public.update_cad_produto_identity(bigint,text,text,bigint,text)',
    'public.update_cad_embalagem_physical(bigint,bigint,numeric,boolean,bigint,text)',
    'public.create_cad_embalagem_versao_un_l(bigint,date,date,numeric,numeric,text)',
    'public.add_cad_embalagem_componente_un_l(bigint,bigint,numeric,text)',
    'public.activate_cad_embalagem_versao(bigint,boolean,text)'
  ] loop
    if has_function_privilege('anon', v_function, 'EXECUTE') then
      raise exception 'anon retained execute on %', v_function;
    end if;
    if exists (
      select 1
        from pg_proc function_definition
        cross join lateral aclexplode(
          coalesce(
            function_definition.proacl,
            acldefault('f', function_definition.proowner)
          )
        ) function_acl
       where function_definition.oid = to_regprocedure(v_function)
         and function_acl.grantee = 0
         and function_acl.privilege_type = 'EXECUTE'
    ) then
      raise exception 'PUBLIC retained execute on %', v_function;
    end if;
  end loop;
  if has_table_privilege('authenticated', 'public.cad_produtos_base', 'INSERT,UPDATE,DELETE') then
    raise exception 'authenticated retained direct product writes';
  end if;
  if has_table_privilege('authenticated', 'public.cad_embalagem_componentes', 'INSERT,UPDATE,DELETE') then
    raise exception 'authenticated retained direct package component writes';
  end if;
end;
$privileges$;

rollback;

select 'PG_VALIDATE_0068_WITH_SMOKE_OK' as result;
