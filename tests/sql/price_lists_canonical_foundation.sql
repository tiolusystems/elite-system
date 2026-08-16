\set ON_ERROR_STOP on
begin;
set local time zone 'UTC';

do $$
begin
  if (select count(*) from public.com_origens_comerciais) <> 2
     or not exists (select 1 from public.com_origens_comerciais where codigo = 'direto_elite')
     or not exists (select 1 from public.com_origens_comerciais where codigo = 'agente') then
    raise exception 'canonical commercial origins were not seeded exactly';
  end if;
  if exists (
    select 1 from public.permission_actions
     where action_key like 'pedidos.price_lists.%' and default_allowed
  ) then raise exception 'price list permissions are not default deny'; end if;
  if not has_function_privilege(
    'authenticated',
    'public.publish_com_lista_preco_versao_idempotente(uuid,bigint,text)',
    'EXECUTE'
  ) then raise exception 'authenticated cannot execute governed publication RPC'; end if;
  if has_function_privilege(
    'anon',
    'public.publish_com_lista_preco_versao_idempotente(uuid,bigint,text)',
    'EXECUTE'
  ) or has_function_privilege(
    'public',
    'public.publish_com_lista_preco_versao_idempotente(uuid,bigint,text)',
    'EXECUTE'
  ) then raise exception 'publication RPC is exposed to anon or PUBLIC'; end if;
  if has_table_privilege('authenticated', 'public.com_listas_preco', 'INSERT')
     or has_table_privilege('authenticated', 'public.com_lista_preco_versao_precos', 'UPDATE')
     or has_table_privilege('authenticated', 'public.com_lista_preco_publicacoes', 'DELETE') then
    raise exception 'direct price list write is exposed';
  end if;
end
$$;

insert into auth.users(id, email) values
  ('12400000-0000-4000-8000-000000000001', 'price-author-0124@test.invalid'),
  ('12400000-0000-4000-8000-000000000002', 'price-setup-0124@test.invalid'),
  ('12400000-0000-4000-8000-000000000003', 'price-denied-0124@test.invalid');
insert into public.user_profiles(id, display_name, role, status) values
  ('12400000-0000-4000-8000-000000000001', 'Autor de precos 0124', 'comercial', 'active'),
  ('12400000-0000-4000-8000-000000000002', 'Setup 0124', 'admin', 'active'),
  ('12400000-0000-4000-8000-000000000003', 'Sem alcada 0124', 'comercial', 'active');

insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
select profile.id, action.action_key, true, '12400000-0000-4000-8000-000000000002'
  from public.user_profiles profile
 cross join public.permission_actions action
 where profile.id = '12400000-0000-4000-8000-000000000002'
on conflict (user_id, action_key)
do update set allowed = true, updated_by = excluded.updated_by;

insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
select '12400000-0000-4000-8000-000000000001', action.action_key, true,
       '12400000-0000-4000-8000-000000000002'
  from public.permission_actions action
 where action.action_key like 'pedidos.price_lists.%'
on conflict (user_id, action_key)
do update set allowed = true, updated_by = excluded.updated_by;

select set_config('request.jwt.claim.sub', '12400000-0000-4000-8000-000000000002', true);
select public.set_system_runtime_environment('test', 'test_reset', 'Smoke de listas 0124')
 where public.current_system_environment() = 'unconfigured';

insert into public.cad_pessoas_comerciais(
  nome, nome_norm, tipo_comercial, papeis_json, status, created_by, updated_by
) values (
  'Agente de preco 0124', 'agente de preco 0124', 'agente_vinculado',
  '["agente"]'::jsonb, 'active',
  '12400000-0000-4000-8000-000000000002',
  '12400000-0000-4000-8000-000000000002'
);
insert into public.cad_areas_comerciais(
  nome, nome_norm, status, created_by, updated_by
) values (
  'Area 0124', 'area 0124', 'active',
  '12400000-0000-4000-8000-000000000002',
  '12400000-0000-4000-8000-000000000002'
);
insert into public.cad_clientes(
  nome, nome_norm, cidade, uf, status, created_by, updated_by
) values (
  'Cliente 0124', 'cliente 0124', 'Campinas', 'SP', 'active',
  '12400000-0000-4000-8000-000000000002',
  '12400000-0000-4000-8000-000000000002'
);
insert into public.cad_produtos_base(
  codigo_produto, nome, nome_norm, status, created_by, updated_by
) values (
  '0124', 'Produto 0124', 'produto 0124', 'active',
  '12400000-0000-4000-8000-000000000002',
  '12400000-0000-4000-8000-000000000002'
);
insert into public.cad_embalagens(
  descricao, descricao_norm, unidade, volume_litros, status, unidade_id,
  origem_dados, created_by, updated_by
) values (
  'Bomba 0124 20 L', 'bomba 0124 20 l', 'UN', 20, 'active', 6,
  'sistema', '12400000-0000-4000-8000-000000000002',
  '12400000-0000-4000-8000-000000000002'
);
insert into public.cad_produto_embalagens(
  produto_id, embalagem_id, codigo_item, status, origem_dados, created_by, updated_by
)
select product.id, packaging.id, 'P0124-20L', 'active', 'sistema',
       '12400000-0000-4000-8000-000000000002',
       '12400000-0000-4000-8000-000000000002'
  from public.cad_produtos_base product
 cross join public.cad_embalagens packaging
 where product.codigo_produto = '0124'
   and packaging.descricao = 'Bomba 0124 20 L';

create temporary table price_list_test_context(
  presentation_id bigint,
  product_id bigint,
  client_id bigint,
  area_id bigint,
  person_role_id bigint,
  origin_id bigint
) on commit drop;
insert into price_list_test_context
select presentation.id, product.id, client.id, area.id, role.id, origin.id
  from public.cad_produto_embalagens presentation
  join public.cad_produtos_base product on product.id = presentation.produto_id
 cross join public.cad_clientes client
 cross join public.cad_areas_comerciais area
 cross join public.cad_pessoa_papeis role
 join public.cad_pessoas_comerciais person on person.id = role.pessoa_id
 cross join public.com_origens_comerciais origin
 where presentation.codigo_item = 'P0124-20L'
   and client.nome = 'Cliente 0124'
   and area.nome = 'Area 0124'
   and person.nome = 'Agente de preco 0124'
   and role.papel = 'agente' and role.status = 'active'
   and origin.codigo = 'agente';
grant select on price_list_test_context to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', '12400000-0000-4000-8000-000000000003', true);
do $$
begin
  begin
    perform public.create_com_lista_preco_rascunho_idempotente(
      '12400000-0000-4000-8000-000000000005',
      'NEGADA0124', 'Lista sem alcada 0124', 'Payload valido para testar default deny',
      current_date, current_date + 30, 'Tentativa valida sem permissao de listas'
    );
    raise exception 'usuario sem alcada criou lista de preco';
  exception when others then
    if sqlerrm = 'usuario sem alcada criou lista de preco' then raise; end if;
    if sqlerrm <> 'not allowed: pedidos.price_lists.draft.manage' then
      raise exception 'negacao nao veio da camada de permissao: %', sqlerrm;
    end if;
  end;
end
$$;

reset role;
select set_config('request.jwt.claim.sub', '12400000-0000-4000-8000-000000000001', true);
do $$
declare
  v_ids price_list_test_context%rowtype;
  v_version bigint;
  v_retry bigint;
  v_publication bigint;
  v_event bigint;
  v_draft bigint;
  v_same_day_publication bigint;
  v_future_version bigint;
  v_future_publication bigint;
  v_other_version bigint;
  v_published_item bigint;
  v_published_price bigint;
  v_published_rule bigint;
  v_item_count bigint;
  v_price_count bigint;
  v_rule_count bigint;
  v_scope_count bigint;
  v_commercial_date date := (clock_timestamp() at time zone 'America/Sao_Paulo')::date;
  v_document jsonb;
  v_items jsonb;
  v_rules jsonb;
begin
  select * into v_ids from price_list_test_context;
  v_version := public.create_com_lista_preco_rascunho_idempotente(
    '12400000-0000-4000-8000-000000000010',
    'L0124', 'Lista canonica 0124', 'Lista criada no smoke da tranche 1A.1',
    v_commercial_date - 30, v_commercial_date + 180, 'Criacao governada da lista 0124'
  );
  v_retry := public.create_com_lista_preco_rascunho_idempotente(
    '12400000-0000-4000-8000-000000000010',
    'L0124', 'Lista canonica 0124', 'Lista criada no smoke da tranche 1A.1',
    v_commercial_date - 30, v_commercial_date + 180, 'Criacao governada da lista 0124'
  );
  if v_retry is distinct from v_version then raise exception 'retry da criacao nao retornou a versao original'; end if;

  v_items := jsonb_build_array(jsonb_build_object(
    'produto_embalagem_id', v_ids.presentation_id,
    'precos', jsonb_build_array(
      jsonb_build_object('prazo_dias', 0, 'valor_centavos_por_litro', 3126),
      jsonb_build_object('prazo_dias', 30, 'valor_centavos_por_litro', 3275)
    )
  ));
  v_rules := jsonb_build_array(jsonb_build_object(
    'codigo', 'AGENTE_SP', 'descricao', 'Agentes autorizados na area e cliente do smoke',
    'prioridade', 10,
    'origens_comerciais', jsonb_build_array(v_ids.origin_id),
    'pessoa_papel_ids', jsonb_build_array(v_ids.person_role_id),
    'areas_comerciais', jsonb_build_array(v_ids.area_id),
    'ufs', jsonb_build_array('SP'),
    'clientes', jsonb_build_array(v_ids.client_id),
    'produtos', jsonb_build_array(v_ids.product_id),
    'apresentacoes', jsonb_build_array(v_ids.presentation_id)
  ));
  perform public.replace_com_lista_preco_rascunho_idempotente(
    '12400000-0000-4000-8000-000000000011', v_version,
    v_commercial_date - 30, v_commercial_date + 180, 'Rascunho completo 0124',
    v_items, v_rules, 'Configuracao integral do rascunho 0124'
  );
  v_retry := public.replace_com_lista_preco_rascunho_idempotente(
    '12400000-0000-4000-8000-000000000011', v_version,
    v_commercial_date - 30, v_commercial_date + 180, 'Rascunho completo 0124',
    v_items, v_rules, 'Configuracao integral do rascunho 0124'
  );
  if v_retry is distinct from v_version then raise exception 'retry do rascunho nao retornou a versao original'; end if;

  begin
    perform public.replace_com_lista_preco_rascunho_idempotente(
      '12400000-0000-4000-8000-000000000011', v_version,
      current_date, current_date + 181, 'Payload divergente',
      v_items, v_rules, 'Conteudo divergente com a mesma chave'
    );
    raise exception 'payload divergente foi aceito na mesma chave';
  exception when others then
    if sqlerrm = 'payload divergente foi aceito na mesma chave' then raise; end if;
  end;

  begin
    perform public.replace_com_lista_preco_rascunho_idempotente(
      '12400000-0000-4000-8000-000000000012', v_version,
      current_date, current_date + 180, 'Prazo negativo',
      jsonb_build_array(jsonb_build_object(
        'produto_embalagem_id', v_ids.presentation_id,
        'precos', jsonb_build_array(jsonb_build_object('prazo_dias', -1, 'valor_centavos_por_litro', 3126))
      )), v_rules, 'Validacao de prazo negativo no rascunho'
    );
    raise exception 'prazo negativo foi aceito';
  exception when check_violation then null;
  end;

  begin
    perform public.replace_com_lista_preco_rascunho_idempotente(
      '12400000-0000-4000-8000-000000000013', v_version,
      current_date, current_date + 180, 'Preco zerado',
      jsonb_build_array(jsonb_build_object(
        'produto_embalagem_id', v_ids.presentation_id,
        'precos', jsonb_build_array(jsonb_build_object('prazo_dias', 0, 'valor_centavos_por_litro', 0))
      )), v_rules, 'Validacao de preco comercial zerado'
    );
    raise exception 'preco zerado foi aceito';
  exception when check_violation then null;
  end;

  begin
    perform public.replace_com_lista_preco_rascunho_idempotente(
      '12400000-0000-4000-8000-000000000017', v_version,
      current_date, current_date + 180, 'Faixa duplicada',
      jsonb_build_array(jsonb_build_object(
        'produto_embalagem_id', v_ids.presentation_id,
        'precos', jsonb_build_array(
          jsonb_build_object('prazo_dias', 30, 'valor_centavos_por_litro', 3126),
          jsonb_build_object('prazo_dias', 30, 'valor_centavos_por_litro', 3275)
        )
      )), v_rules, 'Validacao de faixa duplicada no rascunho'
    );
    raise exception 'faixa duplicada foi aceita';
  exception when unique_violation then null;
  end;

  v_publication := public.publish_com_lista_preco_versao_idempotente(
    '12400000-0000-4000-8000-000000000014', v_version,
    'Publicacao governada da lista de teste 0124'
  );
  v_retry := public.publish_com_lista_preco_versao_idempotente(
    '12400000-0000-4000-8000-000000000014', v_version,
    'Publicacao governada da lista de teste 0124'
  );
  if v_retry is distinct from v_publication then raise exception 'retry da publicacao duplicou o fato'; end if;

  v_document := public.consultar_com_lista_preco_versao(v_version);
  if v_document#>>'{documento,itens,0,precos,0,prazo_dias}' <> '0'
     or v_document#>>'{documento,itens,0,precos,0,valor_centavos_por_litro}' <> '3126' then
    raise exception 'consulta governada nao preservou prazo zero e centavos por litro';
  end if;
  if (select vigencia_inicio from public.com_lista_preco_versoes where id = v_version) >= v_commercial_date then
    raise exception 'primeira publicacao retroativa nao foi exercitada';
  end if;

  v_draft := public.create_com_lista_preco_versao_idempotente(
    '12400000-0000-4000-8000-000000000030',
    (select lista_id from public.com_lista_preco_versoes where id = v_version),
    v_commercial_date - 1, v_commercial_date + 180, 'Sucessora retroativa 0124',
    'Criacao da sucessora retroativa para teste'
  );
  perform public.replace_com_lista_preco_rascunho_idempotente(
    '12400000-0000-4000-8000-000000000031', v_draft,
    v_commercial_date - 1, v_commercial_date + 180, 'Sucessora retroativa completa',
    v_items, v_rules, 'Configuracao da sucessora retroativa de teste'
  );
  v_other_version := public.create_com_lista_preco_rascunho_idempotente(
    '12400000-0000-4000-8000-000000000032',
    'OUTRA0124', 'Outra lista 0124', 'Lista independente para validar a linhagem',
    v_commercial_date, v_commercial_date + 30, 'Criacao da lista independente de teste'
  );

  begin
    update public.com_lista_preco_versoes
       set versao_anterior_id = v_other_version
     where id = v_draft;
    raise exception 'predecessor de outra lista foi aceito';
  exception when foreign_key_violation then null;
  end;
  if (select versao_anterior_id from public.com_lista_preco_versoes where id = v_draft) is distinct from v_version then
    raise exception 'falha de linhagem alterou o predecessor valido';
  end if;

  select item.id, price.id, rule.id
    into v_published_item, v_published_price, v_published_rule
    from public.com_lista_preco_versao_itens item
    join public.com_lista_preco_versao_precos price on price.versao_item_id = item.id and price.prazo_dias = 0
    join public.com_lista_preco_regras rule on rule.versao_id = item.versao_id
   where item.versao_id = v_version;
  select count(*) into v_item_count from public.com_lista_preco_versao_itens where versao_id = v_version;
  select count(*) into v_price_count
    from public.com_lista_preco_versao_precos price
    join public.com_lista_preco_versao_itens item on item.id = price.versao_item_id
   where item.versao_id = v_version;
  select count(*) into v_rule_count from public.com_lista_preco_regras where versao_id = v_version;
  select count(*) into v_scope_count from public.com_lista_preco_regra_ufs where regra_id = v_published_rule;

  begin
    update public.com_lista_preco_versao_itens
       set versao_id = v_draft
     where id = v_published_item;
    raise exception 'reparent de item publicado foi aceito';
  exception when others then
    if sqlerrm = 'reparent de item publicado foi aceito' then raise; end if;
    if sqlerrm not like 'versao publicada e imutavel%' then raise; end if;
  end;
  v_document := public.com_lista_preco_versao_documento(v_version);
  if md5(v_document::text) is distinct from (select conteudo_hash from public.com_lista_preco_publicacoes where id = v_publication)
     or not exists (select 1 from public.com_lista_preco_versao_itens where id = v_published_item and versao_id = v_version) then
    raise exception 'reparent de item alterou o documento publicado';
  end if;

  begin
    update public.com_lista_preco_versao_precos
       set versao_item_id = (
         select id from public.com_lista_preco_versao_itens
          where versao_id = v_draft order by id limit 1
       )
     where id = v_published_price;
    raise exception 'reparent de preco publicado foi aceito';
  exception when others then
    if sqlerrm = 'reparent de preco publicado foi aceito' then raise; end if;
    if sqlerrm not like 'versao publicada e imutavel%' then raise; end if;
  end;
  v_document := public.com_lista_preco_versao_documento(v_version);
  if md5(v_document::text) is distinct from (select conteudo_hash from public.com_lista_preco_publicacoes where id = v_publication)
     or not exists (select 1 from public.com_lista_preco_versao_precos where id = v_published_price and versao_item_id = v_published_item) then
    raise exception 'reparent de preco alterou o documento publicado';
  end if;

  begin
    update public.com_lista_preco_regras
       set versao_id = v_draft
     where id = v_published_rule;
    raise exception 'reparent de regra publicada foi aceito';
  exception when others then
    if sqlerrm = 'reparent de regra publicada foi aceito' then raise; end if;
    if sqlerrm not like 'versao publicada e imutavel%' then raise; end if;
  end;
  v_document := public.com_lista_preco_versao_documento(v_version);
  if md5(v_document::text) is distinct from (select conteudo_hash from public.com_lista_preco_publicacoes where id = v_publication)
     or not exists (select 1 from public.com_lista_preco_regras where id = v_published_rule and versao_id = v_version) then
    raise exception 'reparent de regra alterou o documento publicado';
  end if;

  begin
    update public.com_lista_preco_regra_ufs
       set regra_id = (
         select id from public.com_lista_preco_regras
          where versao_id = v_draft order by id limit 1
       )
     where regra_id = v_published_rule and uf = 'SP';
    raise exception 'reparent de escopo publicado foi aceito';
  exception when others then
    if sqlerrm = 'reparent de escopo publicado foi aceito' then raise; end if;
    if sqlerrm not like 'versao publicada e imutavel%' then raise; end if;
  end;
  v_document := public.com_lista_preco_versao_documento(v_version);
  if md5(v_document::text) is distinct from (select conteudo_hash from public.com_lista_preco_publicacoes where id = v_publication)
     or not exists (select 1 from public.com_lista_preco_regra_ufs where regra_id = v_published_rule and uf = 'SP') then
    raise exception 'reparent de escopo alterou o documento publicado';
  end if;

  begin
    insert into public.com_lista_preco_versao_itens(versao_id, produto_embalagem_id, created_by)
    values (v_version, v_ids.presentation_id, '12400000-0000-4000-8000-000000000001');
    raise exception 'insert de item em versao publicada foi aceito';
  exception when others then
    if sqlerrm = 'insert de item em versao publicada foi aceito' then raise; end if;
    if sqlerrm not like 'versao publicada e imutavel%' then raise; end if;
  end;
  v_document := public.com_lista_preco_versao_documento(v_version);
  if md5(v_document::text) is distinct from (select conteudo_hash from public.com_lista_preco_publicacoes where id = v_publication)
     or (select count(*) from public.com_lista_preco_versao_itens where versao_id = v_version) <> v_item_count then
    raise exception 'insert de item alterou o documento publicado';
  end if;

  begin
    insert into public.com_lista_preco_versao_precos(
      versao_item_id, prazo_dias, valor_centavos_por_litro, created_by
    ) values (v_published_item, 60, 3500, '12400000-0000-4000-8000-000000000001');
    raise exception 'insert de preco em versao publicada foi aceito';
  exception when others then
    if sqlerrm = 'insert de preco em versao publicada foi aceito' then raise; end if;
    if sqlerrm not like 'versao publicada e imutavel%' then raise; end if;
  end;
  v_document := public.com_lista_preco_versao_documento(v_version);
  if md5(v_document::text) is distinct from (select conteudo_hash from public.com_lista_preco_publicacoes where id = v_publication)
     or (select count(*) from public.com_lista_preco_versao_precos price join public.com_lista_preco_versao_itens item on item.id = price.versao_item_id where item.versao_id = v_version) <> v_price_count then
    raise exception 'insert de preco alterou o documento publicado';
  end if;

  begin
    insert into public.com_lista_preco_regras(
      versao_id, codigo, descricao, prioridade, created_by
    ) values (
      v_version, 'REGRA_NOVA', 'Regra indevida em versao publicada', 20,
      '12400000-0000-4000-8000-000000000001'
    );
    raise exception 'insert de regra em versao publicada foi aceito';
  exception when others then
    if sqlerrm = 'insert de regra em versao publicada foi aceito' then raise; end if;
    if sqlerrm not like 'versao publicada e imutavel%' then raise; end if;
  end;
  v_document := public.com_lista_preco_versao_documento(v_version);
  if md5(v_document::text) is distinct from (select conteudo_hash from public.com_lista_preco_publicacoes where id = v_publication)
     or (select count(*) from public.com_lista_preco_regras where versao_id = v_version) <> v_rule_count then
    raise exception 'insert de regra alterou o documento publicado';
  end if;

  begin
    insert into public.com_lista_preco_regra_ufs(regra_id, uf)
    values (v_published_rule, 'MG');
    raise exception 'insert de escopo em versao publicada foi aceito';
  exception when others then
    if sqlerrm = 'insert de escopo em versao publicada foi aceito' then raise; end if;
    if sqlerrm not like 'versao publicada e imutavel%' then raise; end if;
  end;
  v_document := public.com_lista_preco_versao_documento(v_version);
  if md5(v_document::text) is distinct from (select conteudo_hash from public.com_lista_preco_publicacoes where id = v_publication)
     or (select count(*) from public.com_lista_preco_regra_ufs where regra_id = v_published_rule) <> v_scope_count then
    raise exception 'insert de escopo alterou o documento publicado';
  end if;

  begin
    perform public.publish_com_lista_preco_versao_idempotente(
      '12400000-0000-4000-8000-000000000033', v_draft,
      'Tentativa de sucessao retroativa normal'
    );
    raise exception 'sucessao retroativa foi aceita';
  exception when others then
    if sqlerrm = 'sucessao retroativa foi aceita' then raise; end if;
    if sqlerrm <> 'publicacao sucessora nao permite vigencia retroativa' then raise; end if;
  end;
  if exists (select 1 from public.com_lista_preco_publicacoes where versao_id = v_draft)
     or exists (select 1 from public.com_lista_preco_lifecycle_eventos where publicacao_id = v_publication and tipo = 'superseded')
     or exists (select 1 from public.com_lista_preco_requisicoes where idempotency_key = '12400000-0000-4000-8000-000000000033') then
    raise exception 'tentativa retroativa deixou efeito parcial';
  end if;

  perform public.replace_com_lista_preco_rascunho_idempotente(
    '12400000-0000-4000-8000-000000000034', v_draft,
    v_commercial_date, v_commercial_date + 180, 'Sucessora vigente hoje',
    v_items, v_rules, 'Correcao da vigencia sucessora para hoje'
  );
  v_same_day_publication := public.publish_com_lista_preco_versao_idempotente(
    '12400000-0000-4000-8000-000000000035', v_draft,
    'Publicacao sucessora com vigencia na data atual'
  );
  if not exists (select 1 from public.com_lista_preco_publicacoes where id = v_same_day_publication and versao_id = v_draft) then
    raise exception 'sucessora com vigencia atual nao foi publicada';
  end if;

  v_future_version := public.create_com_lista_preco_versao_idempotente(
    '12400000-0000-4000-8000-000000000036',
    (select lista_id from public.com_lista_preco_versoes where id = v_version),
    v_commercial_date + 30, v_commercial_date + 210, 'Sucessora futura 0124',
    'Criacao da sucessora futura para teste'
  );
  perform public.replace_com_lista_preco_rascunho_idempotente(
    '12400000-0000-4000-8000-000000000037', v_future_version,
    v_commercial_date + 30, v_commercial_date + 210, 'Sucessora futura completa',
    v_items, v_rules, 'Configuracao da sucessora futura de teste'
  );
  v_future_publication := public.publish_com_lista_preco_versao_idempotente(
    '12400000-0000-4000-8000-000000000038', v_future_version,
    'Publicacao sucessora com vigencia futura'
  );
  if not exists (select 1 from public.com_lista_preco_publicacoes where id = v_future_publication and versao_id = v_future_version) then
    raise exception 'sucessora com vigencia futura nao foi publicada';
  end if;

  begin
    perform public.replace_com_lista_preco_rascunho_idempotente(
      '12400000-0000-4000-8000-000000000015', v_version,
      current_date, current_date + 180, 'Tentativa publicada',
      v_items, v_rules, 'Tentativa de alterar uma versao publicada'
    );
    raise exception 'versao publicada foi alterada por RPC';
  exception when others then
    if sqlerrm = 'versao publicada foi alterada por RPC' then raise; end if;
  end;

  v_event := public.withdraw_com_lista_preco_publicacao_idempotente(
    '12400000-0000-4000-8000-000000000016', v_publication,
    'Retirada governada da publicacao de teste 0124'
  );
  v_retry := public.withdraw_com_lista_preco_publicacao_idempotente(
    '12400000-0000-4000-8000-000000000016', v_publication,
    'Retirada governada da publicacao de teste 0124'
  );
  if v_retry is distinct from v_event then raise exception 'retry da retirada duplicou o evento'; end if;

end
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '12400000-0000-4000-8000-000000000001', true);
do $$
begin
  begin
    insert into public.com_listas_preco(codigo, nome, created_by)
    values ('DIRETA-0124', 'Escrita direta indevida', '12400000-0000-4000-8000-000000000001');
    raise exception 'escrita direta autenticada foi aceita';
  exception when insufficient_privilege then null;
  end;
end
$$;

reset role;

do $$
declare
  v_version bigint;
  v_item bigint;
  v_rule bigint;
  v_publication bigint;
begin
  select version.id, item.id, rule.id, publication.id
    into v_version, v_item, v_rule, v_publication
    from public.com_lista_preco_versoes version
    join public.com_lista_preco_versao_itens item on item.versao_id = version.id
    join public.com_lista_preco_regras rule on rule.versao_id = version.id
    join public.com_lista_preco_publicacoes publication on publication.versao_id = version.id
   where version.numero = 1
     and exists (select 1 from public.com_listas_preco list where list.id = version.lista_id and list.codigo = 'L0124');

  if (select count(*) from public.com_lista_preco_publicacoes where versao_id = v_version) <> 1 then
    raise exception 'publication source of truth was duplicated';
  end if;
  if exists (select 1 from public.com_lista_preco_lifecycle_eventos where tipo = 'published') then
    raise exception 'publication was duplicated in lifecycle events';
  end if;
  if (select count(*) from public.com_lista_preco_lifecycle_eventos where publicacao_id = v_publication and tipo = 'withdrawn') <> 1 then
    raise exception 'withdrawal lifecycle event was not append-only and unique';
  end if;
  if (select situacao from public.com_lista_preco_publicacoes_estado where publicacao_id = v_publication) <> 'retirada' then
    raise exception 'withdrawn publication projection is incorrect';
  end if;

  begin
    update public.com_lista_preco_versoes
       set descricao = 'Alteracao indevida'
     where id = v_version;
    raise exception 'published version was mutable';
  exception when others then
    if sqlerrm = 'published version was mutable' then raise; end if;
  end;
  begin
    delete from public.com_lista_preco_versao_itens where id = v_item;
    raise exception 'published item was mutable';
  exception when others then
    if sqlerrm = 'published item was mutable' then raise; end if;
  end;
  begin
    update public.com_lista_preco_versao_precos
       set valor_centavos_por_litro = 9999
     where versao_item_id = v_item;
    raise exception 'published price was mutable';
  exception when others then
    if sqlerrm = 'published price was mutable' then raise; end if;
  end;
  begin
    update public.com_lista_preco_regras
       set descricao = 'Alteracao indevida'
     where id = v_rule;
    raise exception 'published rule was mutable';
  exception when others then
    if sqlerrm = 'published rule was mutable' then raise; end if;
  end;
  begin
    delete from public.com_lista_preco_regra_ufs
     where regra_id = v_rule and uf = 'SP';
    raise exception 'published scope was mutable';
  exception when others then
    if sqlerrm = 'published scope was mutable' then raise; end if;
  end;
  begin
    delete from public.com_lista_preco_publicacoes where id = v_publication;
    raise exception 'publication fact was deletable';
  exception when others then
    if sqlerrm = 'publication fact was deletable' then raise; end if;
  end;
end
$$;

rollback;
select 'PRICE_LISTS_CANONICAL_FOUNDATION_OK';
