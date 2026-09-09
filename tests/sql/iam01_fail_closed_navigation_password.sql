\set ON_ERROR_STOP on

begin;

do $contract$
declare
  v_admin uuid := '14800000-0000-4000-8000-000000000001';
  v_seller uuid := '14800000-0000-4000-8000-000000000002';
  v_other uuid := '14800000-0000-4000-8000-000000000003';
  v_pcp uuid := '14800000-0000-4000-8000-000000000004';
  v_seller_person bigint;
  v_other_person bigint;
  v_product_id bigint;
  v_material_id bigint;
  v_formula_id bigint;
  v_op_id bigint;
  v_component_id bigint;
  v_lote_mp_id bigint;
  v_client bigint;
  v_own_order bigint;
  v_other_order bigint;
  v_seller_profile bigint;
  v_pcp_profile bigint;
  v_route record;
  v_path text;
begin
  if exists (
    select 1
      from public.security_access_profile_permissions permission
      join public.security_access_profiles profile on profile.id = permission.profile_id
     where profile.profile_key = 'comercial_vendedor'
       and permission.action_key = 'pedidos.price_lists.view'
  ) then
    raise exception 'seller profile still exposes commercial price lists';
  end if;

  if (select count(distinct profile.id)
        from public.security_access_profiles profile
        join public.security_access_profile_permissions permission on permission.profile_id = profile.id
       where profile.status = 'active'
         and permission.action_key = 'security.change_own_password'
         and permission.granted) <>
     (select count(*) from public.security_access_profiles where status = 'active') then
    raise exception 'every active human profile must retain self-service password change';
  end if;

  insert into auth.users(id) values (v_admin), (v_seller), (v_other), (v_pcp)
  on conflict (id) do nothing;
  insert into public.user_profiles(id, display_name, role, status, is_system_actor)
  values
    (v_admin, 'IAM 0148 Admin', 'admin', 'active', false),
    (v_seller, 'IAM 0148 Seller', 'comercial', 'active', false),
    (v_other, 'IAM 0148 Other Seller', 'comercial', 'active', false),
    (v_pcp, 'IAM 0148 PCP', 'producao', 'active', false)
  on conflict (id) do nothing;

  insert into public.cad_pessoas_comerciais(
    nome, nome_norm, tipo_comercial, papeis_json, status, user_profile_id, created_by, updated_by
  ) values (
    'IAM 0148 Seller', 'IAM 0148 SELLER', null, '["funcionario"]'::jsonb, 'active', v_seller, v_admin, v_admin
  )
  returning id into v_seller_person;
  insert into public.cad_pessoas_comerciais(
    nome, nome_norm, tipo_comercial, papeis_json, status, user_profile_id, created_by, updated_by
  ) values (
    'IAM 0148 Other Seller', 'IAM 0148 OTHER SELLER', null, '["funcionario"]'::jsonb, 'active', v_other, v_admin, v_admin
  );
  select id into v_other_person from public.cad_pessoas_comerciais where user_profile_id = v_other;

  select id into v_seller_profile
    from public.security_access_profiles
   where profile_key = 'comercial_vendedor' and version = 1;
  insert into public.security_user_access_profiles(user_id, profile_id, profile_key, assigned_by, reason, correlation_id)
  values
    (v_seller, v_seller_profile, 'comercial_vendedor', v_admin, 'Seller profile for IAM 0148 fail-closed smoke', 'iam:0148:seller'),
    (v_other, v_seller_profile, 'comercial_vendedor', v_admin, 'Other seller profile for IAM 0148 fail-closed smoke', 'iam:0148:other')
  on conflict (user_id, profile_key) do update set profile_id = excluded.profile_id;

  select id into v_pcp_profile
    from public.security_access_profiles
   where profile_key = 'pcp_producao' and version = 1;
  insert into public.security_user_access_profiles(user_id, profile_id, profile_key, assigned_by, reason, correlation_id)
  values (
    v_pcp, v_pcp_profile, 'pcp_producao', v_admin,
    'PCP profile for IAM 0148 fail-closed smoke', 'iam:0148:pcp'
  ) on conflict (user_id, profile_key) do update set profile_id = excluded.profile_id;

  insert into public.cad_produtos_base(codigo_produto, nome, nome_norm, status)
  values ('8148', 'Produto sentinela IAM 0148', 'PRODUTO SENTINELA IAM 0148', 'active')
  returning id into v_product_id;
  insert into public.cad_materias_primas(sku_corrigido, nome, nome_norm, unidade_base_estoque, status)
  values ('IAM148MP', 'Materia-prima sentinela IAM 0148', 'MATERIA-PRIMA SENTINELA IAM 0148', 'KG', 'active')
  returning id into v_material_id;
  insert into public.est_lotes_mp(materia_prima_id, codigo_lote, status, created_by, updated_by)
  values (v_material_id, 'IAM148-LOT', 'disponivel', v_admin, v_admin)
  returning id into v_lote_mp_id;
  insert into public.est_movimentos_mp(lote_mp_id, materia_prima_id, tipo_movimento, quantidade, origem_modulo, created_by)
  values (v_lote_mp_id, v_material_id, 'importacao_inicial', 10, 'iam0148', v_admin);
  insert into public.pcp_formula_versoes(produto_id, tipo_receita, versao, justificativa, entry_hash, created_by)
  values (v_product_id, 'producao', 1, 'Formula sentinela IAM 0148', 'iam0148', v_admin)
  returning id into v_formula_id;
  insert into public.pcp_ordens_producao(
    codigo_op, formula_versao_id, produto_id, tipo_op, status, quantidade_planejada,
    review_status, origem_dados, created_by, updated_by
  ) values (
    'OP-IAM0148', v_formula_id, v_product_id, 'estoque', 'draft', 1,
    'approved', 'sistema', v_admin, v_admin
  ) returning id into v_op_id;
  insert into public.pcp_op_componentes_planejados(
    op_id, tipo_componente, materia_prima_id, quantidade_planejada, unidade
  ) values (v_op_id, 'MP', v_material_id, 1, 'KG')
  returning id into v_component_id;
  insert into public.pcp_op_reservas_componentes(
    op_id, op_componente_id, tipo_componente, lote_mp_id, quantidade_reservada, created_by, updated_by
  ) values (v_op_id, v_component_id, 'MP', v_lote_mp_id, 1, v_admin, v_admin);

  insert into public.cad_clientes(nome, nome_norm, cidade, uf, status, created_by)
  values ('Cliente IAM 0148', 'CLIENTE IAM 0148', 'Campinas', 'SP', 'active', v_admin)
  returning id into v_client;
  insert into public.com_pedidos(
    codigo_pedido, cliente_id, tipo_pedido, status, valor_total, vendedor_gerador_id, created_by, updated_by
  ) values (
    'IAM0148-OWN', v_client, 'venda', 'draft', 10, v_seller_person, v_admin, v_admin
  ) returning id into v_own_order;
  insert into public.com_pedidos(
    codigo_pedido, cliente_id, tipo_pedido, status, valor_total, vendedor_gerador_id, created_by, updated_by
  ) values (
    'IAM0148-OTHER', v_client, 'venda', 'draft', 20, v_other_person, v_admin, v_admin
  ) returning id into v_other_order;

  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', v_seller::text, true);
  set local role authenticated;

  if not public.can_current_user('security.change_own_password') then
    raise exception 'seller lost own password capability';
  end if;
  if public.can_current_user('pedidos.price_lists.view') then
    raise exception 'seller inherited price-list capability';
  end if;
  if not public.can_current_user_view_order(v_own_order)
     or public.can_current_user_view_order(v_other_order) then
    raise exception 'seller order visibility is not own-scoped';
  end if;
  if exists (select 1 from public.com_pedidos where id = v_other_order) then
    raise exception 'RLS exposed another seller order';
  end if;
  if exists (select 1 from public.com_pedidos_kanban where pedido_id = v_other_order) then
    raise exception 'kanban exposed another seller order';
  end if;
  if exists (select 1 from public.pcp_ordens_producao where id = v_op_id)
     or exists (select 1 from public.pcp_op_componentes_planejados where op_id = v_op_id) then
    raise exception 'seller direct PCP read was not denied';
  end if;
  if exists (select 1 from public.est_lotes_mp where id = v_lote_mp_id)
     or exists (select 1 from public.est_movimentos_mp where lote_mp_id = v_lote_mp_id)
     or exists (select 1 from public.est_lotes_mp_saldos where lote_mp_id = v_lote_mp_id) then
    raise exception 'seller direct MP stock read was not denied';
  end if;
  select * into v_route from public.get_current_route_capability_access('/producao/ordens/' || v_op_id::text || '/imprimir');
  if v_route.allowed or v_route.reason <> 'permission_denied' then
    raise exception 'seller OP print route did not fail closed: %', row_to_json(v_route);
  end if;

  foreach v_path in array array[
    '/producao', '/romaneios', '/importacao-xml', '/qualidade/pops',
    '/qualidade/rastreabilidade', '/relatorios', '/seguranca', '/pedidos/listas-precos'
  ] loop
    select * into v_route from public.get_current_route_capability_access(v_path);
    if v_route.allowed or v_route.reason <> 'permission_denied' then
      raise exception 'seller route did not fail closed for %: %', v_path, row_to_json(v_route);
    end if;
  end loop;
  foreach v_path in array array['/pedidos', '/kanban', '/login/trocar-senha'] loop
    select * into v_route from public.get_current_route_capability_access(v_path);
    if not v_route.allowed then
      raise exception 'seller permitted route was denied for %: %', v_path, row_to_json(v_route);
    end if;
  end loop;

  reset role;
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', v_pcp::text, true);
  set local role authenticated;
  if not public.can_current_user('pcp.op.view')
     or not exists (select 1 from public.pcp_ordens_producao where id = v_op_id) then
    raise exception 'PCP profile lost OP read access';
  end if;
  if not public.can_current_user('estoque.mp.view')
     or not exists (select 1 from public.est_lotes_mp where id = v_lote_mp_id)
     or not exists (select 1 from public.est_lotes_mp_saldos where lote_mp_id = v_lote_mp_id) then
    raise exception 'PCP profile lost MP stock read access';
  end if;
  select * into v_route from public.get_current_route_capability_access('/producao/ordens/' || v_op_id::text || '/imprimir');
  if not v_route.allowed then
    raise exception 'PCP OP print route was denied: %', row_to_json(v_route);
  end if;
end;
$contract$;

rollback;

\echo ELITE_IAM01_FAIL_CLOSED_NAVIGATION_PASSWORD_OK
