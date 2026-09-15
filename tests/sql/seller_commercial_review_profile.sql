\set ON_ERROR_STOP on
begin;
set local time zone 'America/Sao_Paulo';

do $$
declare
  v_seller uuid := '14900000-0000-4000-8000-000000000001';
  v_setup uuid := '14900000-0000-4000-8000-000000000002';
  v_profile_id bigint;
  v_action text;
  v_f2b_actions text[] := array[
    'pedidos.create.own', 'pedidos.price_reference.resolve',
    'pedidos.payment_terms.manage', 'pedidos.commercial_context.manage',
    'pedidos.practiced_price.record', 'pedidos.commercial_review.preview',
    'pedidos.commercial_review.confirm'
  ];
begin
  insert into auth.users(id, email) values
    (v_seller, 'seller-profile-0149@test.invalid'),
    (v_setup, 'setup-profile-0149@test.invalid');
  insert into public.user_profiles(id, display_name, role, status) values
    (v_seller, 'Seller profile 0149', 'comercial', 'active'),
    (v_setup, 'Setup profile 0149', 'admin', 'active');
  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  values (v_setup, 'system.admin', true, v_setup)
  on conflict (user_id, action_key) do update
    set allowed = excluded.allowed, updated_by = excluded.updated_by;
  perform set_config('request.jwt.claim.sub', v_setup::text, true);
  perform public.set_system_runtime_environment(
    'test', 'test_reset', 'Seller profile 0149 runtime fixture'
  ) where public.current_system_environment() = 'unconfigured';

  select id into v_profile_id
    from public.security_access_profiles
   where profile_key = 'comercial_vendedor' and status = 'active'
   order by version desc limit 1;
  if v_profile_id is null then raise exception 'comercial_vendedor profile is missing'; end if;
  insert into public.security_user_access_profiles(
    user_id, profile_id, profile_key, assigned_by, reason, correlation_id
  ) values (
    v_seller, v_profile_id, 'comercial_vendedor', v_setup,
    'Fixture profile adoption for seller F2B.', 'seller-0149-profile'
  );
  foreach v_action in array v_f2b_actions loop
    if exists (
      select 1 from public.user_permission_overrides
       where user_id = v_seller and action_key = v_action and allowed
    ) then raise exception 'seller F2B action % leaked through an individual override', v_action;
    end if;
  end loop;
end
$$;

insert into public.cad_pessoas_comerciais(
  nome, nome_norm, tipo_comercial, papeis_json, status, user_profile_id, created_by, updated_by
) values
  ('Seller profile 0149', 'seller profile 0149', 'vendedor_direto_elite',
   '["funcionario", "vendedor"]', 'active', '14900000-0000-4000-8000-000000000001',
   '14900000-0000-4000-8000-000000000002', '14900000-0000-4000-8000-000000000002'),
  ('Other seller profile 0149', 'other seller profile 0149', 'vendedor_direto_elite',
   '["funcionario", "vendedor"]', 'active', null,
   '14900000-0000-4000-8000-000000000002', '14900000-0000-4000-8000-000000000002');
insert into public.cad_clientes(nome, nome_norm, cidade, uf, status, created_by, updated_by) values
  ('Own client profile 0149', 'own client profile 0149', 'Campinas', 'SP', 'active',
   '14900000-0000-4000-8000-000000000002', '14900000-0000-4000-8000-000000000002'),
  ('Foreign client profile 0149', 'foreign client profile 0149', 'Campinas', 'SP', 'active',
   '14900000-0000-4000-8000-000000000002', '14900000-0000-4000-8000-000000000002');
insert into public.cad_cliente_propriedades(cliente_id, nome, cidade, uf, status, created_by, updated_by)
select client.id, case client.nome_norm when 'own client profile 0149'
  then 'Own property profile 0149' else 'Foreign property profile 0149' end,
  'Campinas', 'SP', 'active',
  '14900000-0000-4000-8000-000000000002', '14900000-0000-4000-8000-000000000002'
  from public.cad_clientes client
 where client.nome_norm in ('own client profile 0149', 'foreign client profile 0149');
insert into public.cad_cliente_vendedores(
  cliente_id, pessoa_id, papel_vinculo_id, status, vigencia_inicio, origem_dados, created_by, updated_by
)
select client.id, seller.id,
       (select id from public.cad_cliente_vinculo_papeis where codigo_norm = 'atende'),
       'active', current_date, 'sistema',
       '14900000-0000-4000-8000-000000000002', '14900000-0000-4000-8000-000000000002'
  from public.cad_clientes client
  join public.cad_pessoas_comerciais seller on seller.nome_norm = case client.nome_norm
    when 'own client profile 0149' then 'seller profile 0149'
    else 'other seller profile 0149' end
 where client.nome_norm in ('own client profile 0149', 'foreign client profile 0149');

insert into public.cad_produtos_base(codigo_produto, nome, nome_norm, status, created_by, updated_by)
values ('1490', 'Product profile 0149', 'product profile 0149', 'active',
  '14900000-0000-4000-8000-000000000002', '14900000-0000-4000-8000-000000000002');
insert into public.cad_embalagens(
  descricao, descricao_norm, unidade, volume_litros, status, unidade_id, origem_dados, created_by, updated_by
) values ('Package profile 0149', 'package profile 0149', 'UN', 20, 'active',
  (select id from public.cad_unidades_medida where lower(codigo) = 'un'), 'sistema',
  '14900000-0000-4000-8000-000000000002', '14900000-0000-4000-8000-000000000002');
insert into public.cad_produto_embalagens(
  produto_id, embalagem_id, codigo_item, status, origem_dados, created_by, updated_by
)
select product.id, packaging.id, 'P0149A', 'active', 'sistema',
  '14900000-0000-4000-8000-000000000002', '14900000-0000-4000-8000-000000000002'
  from public.cad_produtos_base product
  join public.cad_embalagens packaging on packaging.descricao_norm = 'package profile 0149'
 where product.codigo_produto = '1490';

do $$
declare v_list_id bigint; v_version_id bigint; v_item_id bigint; v_unit_id bigint;
begin
  select id into v_unit_id from public.cad_unidades_medida where lower(codigo) = 'l';
  insert into public.com_listas_preco(codigo, nome, created_by)
  values ('F2B0149', 'Price list profile 0149', '14900000-0000-4000-8000-000000000002')
  returning id into v_list_id;
  insert into public.com_lista_preco_versoes(lista_id, numero, vigencia_inicio, motivo, created_by, updated_by)
  values (v_list_id, 1, current_date, 'Profile seller fixture',
    '14900000-0000-4000-8000-000000000002', '14900000-0000-4000-8000-000000000002')
  returning id into v_version_id;
  insert into public.com_lista_preco_versao_itens(
    versao_id, produto_embalagem_id, unidade_precificacao_id,
    quantidade_unidade_precificacao_por_apresentacao, created_by
  ) values (
    v_version_id, (select id from public.cad_produto_embalagens where codigo_item = 'P0149A'),
    v_unit_id, 20, '14900000-0000-4000-8000-000000000002'
  ) returning id into v_item_id;
  insert into public.com_lista_preco_versao_precos(
    versao_item_id, prazo_dias, valor_centavos_por_litro,
    valor_centavos_por_unidade_precificacao, created_by
  ) values (v_item_id, 0, 100, 100, '14900000-0000-4000-8000-000000000002');
  insert into public.com_lista_preco_regras(versao_id, codigo, descricao, prioridade, created_by)
  values (v_version_id, 'GERAL', 'General profile seller rule', 0,
    '14900000-0000-4000-8000-000000000002');
  insert into public.com_lista_preco_publicacoes(versao_id, conteudo_hash, motivo, published_by, published_at)
  values (v_version_id, md5('F2B0149'), 'Profile seller fixture publication',
    '14900000-0000-4000-8000-000000000002', clock_timestamp());
end
$$;

create temporary table seller_profile_context(
  own_relation_id bigint, foreign_relation_id bigint, own_property_id bigint,
  foreign_property_id bigint, presentation_id bigint, origin_id bigint,
  own_proposal jsonb, foreign_proposal jsonb, own_preview jsonb,
  order_id bigint, confirmation_id bigint, discount_before bigint, credit_before bigint
) on commit drop;
insert into seller_profile_context(
  own_relation_id, foreign_relation_id, own_property_id, foreign_property_id, presentation_id, origin_id
)
select
  (select relation.id from public.cad_cliente_vendedores relation join public.cad_clientes client on client.id = relation.cliente_id where client.nome_norm = 'own client profile 0149'),
  (select relation.id from public.cad_cliente_vendedores relation join public.cad_clientes client on client.id = relation.cliente_id where client.nome_norm = 'foreign client profile 0149'),
  (select property.id from public.cad_cliente_propriedades property join public.cad_clientes client on client.id = property.cliente_id where client.nome_norm = 'own client profile 0149'),
  (select property.id from public.cad_cliente_propriedades property join public.cad_clientes client on client.id = property.cliente_id where client.nome_norm = 'foreign client profile 0149'),
  (select id from public.cad_produto_embalagens where codigo_item = 'P0149A'),
  (select id from public.com_origens_comerciais where codigo = 'direto_elite');
update seller_profile_context
   set own_proposal = jsonb_build_object(
         'cliente_vendedor_vinculo_id', own_relation_id, 'data_pedido', current_date,
         'origem_comercial_id', origin_id, 'area_comercial_id', null, 'uf', 'SP',
         'pessoa_papel_ids', '[]'::jsonb,
         'itens', jsonb_build_array(jsonb_build_object('produto_embalagem_id', presentation_id, 'quantidade', 1, 'preco_praticado_centavos_por_unidade_precificacao', 100)),
         'parcelas', jsonb_build_array(jsonb_build_object('numero_parcela', 1, 'forma_pagamento', 'pix', 'valor_centavos', 2000, 'data_vencimento', current_date)),
         'entregas', jsonb_build_array(jsonb_build_object('data_prevista', current_date, 'propriedade_id', own_property_id, 'estabelecimento_id', null, 'endereco_id', null, 'itens', jsonb_build_array(jsonb_build_object('item_index', 1, 'quantidade', 1)))),
         'observacao', 'Own portfolio profile seller fixture'
       ),
       foreign_proposal = jsonb_build_object(
         'cliente_vendedor_vinculo_id', foreign_relation_id, 'data_pedido', current_date,
         'origem_comercial_id', origin_id, 'area_comercial_id', null, 'uf', 'SP',
         'pessoa_papel_ids', '[]'::jsonb,
         'itens', jsonb_build_array(jsonb_build_object('produto_embalagem_id', presentation_id, 'quantidade', 1, 'preco_praticado_centavos_por_unidade_precificacao', 100)),
         'parcelas', jsonb_build_array(jsonb_build_object('numero_parcela', 1, 'forma_pagamento', 'pix', 'valor_centavos', 2000, 'data_vencimento', current_date)),
         'entregas', jsonb_build_array(jsonb_build_object('data_prevista', current_date, 'propriedade_id', foreign_property_id, 'estabelecimento_id', null, 'endereco_id', null, 'itens', jsonb_build_array(jsonb_build_object('item_index', 1, 'quantidade', 1)))),
         'observacao', 'Foreign portfolio profile seller fixture'
       );
grant select, update on seller_profile_context to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', '14900000-0000-4000-8000-000000000001', true);
do $$
declare
  v_required text;
  v_forbidden text;
  v_required_actions text[] := array[
    'pedidos.create.own', 'pedidos.price_reference.resolve',
    'pedidos.payment_terms.manage', 'pedidos.commercial_context.manage',
    'pedidos.practiced_price.record', 'pedidos.commercial_review.preview',
    'pedidos.commercial_review.confirm'
  ];
  v_forbidden_actions text[] := array[
    'pedidos.commercial_discount.review', 'pedidos.credit.review',
    'pedidos.commercial_comparison.view', 'system.admin', 'security.manage_users',
    'pcp.op.view', 'estoque.mp.view', 'financeiro.receivables.view', 'qualidade.rastreabilidade.view'
  ];
begin
  foreach v_required in array v_required_actions loop
    if not public.can_current_user(v_required) then raise exception 'adopted seller profile did not grant %', v_required; end if;
  end loop;
  foreach v_forbidden in array v_forbidden_actions loop
    if public.can_current_user(v_forbidden) then raise exception 'adopted seller profile incorrectly granted %', v_forbidden; end if;
  end loop;
end
$$;

do $$
declare v seller_profile_context%rowtype; v_result jsonb; v_preview jsonb;
begin
  select * into v from seller_profile_context;
  v_preview := public.prever_com_revisao_comercial_venda(v.own_proposal);
  if coalesce((v_preview->>'complete_for_confirmation')::boolean, false) is not true then raise exception 'seller profile preview was not complete'; end if;
  update seller_profile_context set own_preview = v_preview;
  begin
    perform public.prever_com_revisao_comercial_venda(v.foreign_proposal);
    raise exception 'foreign portfolio preview was accepted';
  exception when others then
    if position('cliente fora da carteira do vendedor' in lower(sqlerrm)) = 0 then raise exception 'foreign preview failed before portfolio guard: %', sqlerrm; end if;
  end;
  select result into v_result from (select public.confirmar_com_revisao_comercial_venda_idempotente(
    '14900000-0000-4000-8000-000000000010', v.own_proposal, v_preview->>'preview_hash', null, false
  ) result) confirmed;
  update seller_profile_context set order_id = (v_result->>'pedido_id')::bigint, confirmation_id = (v_result->>'confirmacao_comercial_id')::bigint;
  begin
    perform public.confirmar_com_revisao_comercial_venda_idempotente(
      '14900000-0000-4000-8000-000000000011', v.foreign_proposal, v_preview->>'preview_hash', null, false
    );
    raise exception 'foreign portfolio confirmation was accepted';
  exception when others then
    if position('cliente fora da carteira do vendedor' in lower(sqlerrm)) = 0 then raise exception 'foreign confirmation failed before portfolio guard: %', sqlerrm; end if;
  end;
end
$$;

reset role;
update seller_profile_context
   set discount_before = (select count(*) from public.com_pedido_decisoes_desconto),
       credit_before = (select count(*) from public.com_pedido_credito_decisoes);
set local role authenticated;
do $$
declare v seller_profile_context%rowtype;
begin
  select * into v from seller_profile_context;
  begin
    perform public.registrar_com_pedido_decisao_desconto_idempotente(
      '14900000-0000-4000-8000-000000000020', v.order_id, v.confirmation_id,
      repeat('0', 64), 'APPROVED', 'Seller must not approve own commercial discount.'
    );
    raise exception 'seller approved a commercial discount';
  exception when others then
    if position('not allowed' in lower(sqlerrm)) = 0 then raise exception 'discount denial did not reach authorization guard: %', sqlerrm; end if;
  end;
  begin
    perform public.registrar_com_pedido_decisao_gerencial_idempotente(
      '14900000-0000-4000-8000-000000000021', v.order_id, 'liberado', 'Seller must not review commercial credit.'
    );
    raise exception 'seller reviewed commercial credit';
  exception when others then
    if position('not allowed' in lower(sqlerrm)) = 0 then raise exception 'credit denial did not reach authorization guard: %', sqlerrm; end if;
  end;
end
$$;
reset role;
do $$
declare v seller_profile_context%rowtype;
begin
  select * into v from seller_profile_context;
  if (select count(*) from public.com_pedido_decisoes_desconto) <> v.discount_before then raise exception 'discount decision persisted despite denied seller authorization'; end if;
  if (select count(*) from public.com_pedido_credito_decisoes) <> v.credit_before then raise exception 'credit decision persisted despite denied seller authorization'; end if;
end
$$;

rollback;
\echo PG_SELLER_COMMERCIAL_REVIEW_PROFILE_OK
