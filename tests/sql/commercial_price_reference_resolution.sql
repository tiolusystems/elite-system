\set ON_ERROR_STOP on
begin;

do $$
begin
  if not exists (
    select 1 from public.permission_actions
     where action_key = 'pedidos.price_reference.resolve'
       and default_allowed = false
       and runtime_module_key = 'pedidos'
       and runtime_access_kind = 'read'
  ) then
    raise exception 'permissao do resolvedor nao nasceu default deny';
  end if;
  if not has_function_privilege('authenticated', 'public.resolver_com_referencia_comercial(date,numeric,bigint,bigint,text,bigint,bigint[],bigint)', 'EXECUTE')
     or has_function_privilege('anon', 'public.resolver_com_referencia_comercial(date,numeric,bigint,bigint,text,bigint,bigint[],bigint)', 'EXECUTE')
     or has_function_privilege('public', 'public.resolver_com_referencia_comercial(date,numeric,bigint,bigint,text,bigint,bigint[],bigint)', 'EXECUTE') then
    raise exception 'grants do resolvedor excedem o contrato governado';
  end if;
  if has_table_privilege('authenticated', 'public.com_listas_preco', 'INSERT')
     or has_table_privilege('authenticated', 'public.com_lista_preco_publicacoes', 'UPDATE') then
    raise exception 'resolvedor ampliou escrita direta em listas';
  end if;
end
$$;

insert into auth.users(id, email) values
  ('12700000-0000-4000-8000-000000000001', 'price-resolver-authorized@test.invalid'),
  ('12700000-0000-4000-8000-000000000002', 'price-resolver-denied@test.invalid'),
  ('12700000-0000-4000-8000-000000000003', 'price-resolver-setup@test.invalid');
insert into public.user_profiles(id, display_name, role, status) values
  ('12700000-0000-4000-8000-000000000001', 'Resolvedor autorizado 0127', 'comercial', 'active'),
  ('12700000-0000-4000-8000-000000000002', 'Resolvedor negado 0127', 'comercial', 'active'),
  ('12700000-0000-4000-8000-000000000003', 'Setup resolvedor 0127', 'admin', 'active');
insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
values ('12700000-0000-4000-8000-000000000001', 'pedidos.price_reference.resolve', true, '12700000-0000-4000-8000-000000000003')
on conflict (user_id, action_key) do update set allowed = true, updated_by = excluded.updated_by;
insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
values ('12700000-0000-4000-8000-000000000003', 'system.admin', true, '12700000-0000-4000-8000-000000000003')
on conflict (user_id, action_key) do update set allowed = true, updated_by = excluded.updated_by;

select set_config('request.jwt.claim.sub', '12700000-0000-4000-8000-000000000003', true);
select public.set_system_runtime_environment('test', 'test_reset', 'Smoke de resolucao comercial 0127')
 where public.current_system_environment() = 'unconfigured';

insert into public.cad_pessoas_comerciais(nome, nome_norm, tipo_comercial, papeis_json, status, created_by, updated_by)
values ('Agente resolver 0127', 'agente resolver 0127', 'agente_vinculado', '["agente"]'::jsonb, 'active',
  '12700000-0000-4000-8000-000000000003', '12700000-0000-4000-8000-000000000003');
insert into public.cad_pessoas_comerciais(nome, nome_norm, tipo_comercial, papeis_json, status, created_by, updated_by)
values ('Participante adicional 0127', 'participante adicional 0127', 'vendedor_direto_elite', '["vendedor"]'::jsonb, 'active',
  '12700000-0000-4000-8000-000000000003', '12700000-0000-4000-8000-000000000003');
insert into public.cad_areas_comerciais(nome, nome_norm, status, created_by, updated_by)
values ('Area resolver 0127', 'area resolver 0127', 'active',
  '12700000-0000-4000-8000-000000000003', '12700000-0000-4000-8000-000000000003');
insert into public.cad_clientes(nome, nome_norm, cidade, uf, status, created_by, updated_by)
values ('Cliente resolver 0127', 'cliente resolver 0127', 'Campinas', 'SP', 'active',
  '12700000-0000-4000-8000-000000000003', '12700000-0000-4000-8000-000000000003');
insert into public.cad_produtos_base(codigo_produto, nome, nome_norm, status, created_by, updated_by)
values ('0127', 'Produto resolver 0127', 'produto resolver 0127', 'active',
  '12700000-0000-4000-8000-000000000003', '12700000-0000-4000-8000-000000000003');
insert into public.cad_embalagens(descricao, descricao_norm, unidade, volume_litros, status, unidade_id, origem_dados, created_by, updated_by)
values
  ('Bomba resolver 0127 20 L', 'bomba resolver 0127 20 l', 'UN', 20, 'active', 6, 'sistema', '12700000-0000-4000-8000-000000000003', '12700000-0000-4000-8000-000000000003'),
  ('Bomba sem lista 0127 10 L', 'bomba sem lista 0127 10 l', 'UN', 10, 'active', 6, 'sistema', '12700000-0000-4000-8000-000000000003', '12700000-0000-4000-8000-000000000003');
insert into public.cad_produto_embalagens(produto_id, embalagem_id, codigo_item, status, origem_dados, created_by, updated_by)
select product.id, packaging.id,
  case when packaging.descricao = 'Bomba resolver 0127 20 L' then 'P0127-20L' else 'P0127-10L' end,
  'active', 'sistema', '12700000-0000-4000-8000-000000000003', '12700000-0000-4000-8000-000000000003'
from public.cad_produtos_base product
join public.cad_embalagens packaging on packaging.descricao in ('Bomba resolver 0127 20 L', 'Bomba sem lista 0127 10 L')
where product.codigo_produto = '0127';

create temporary table resolver_context(
  presentation_id bigint, uncovered_presentation_id bigint, product_id bigint, client_id bigint, area_id bigint,
  person_role_id bigint, other_person_role_id bigint, direct_origin_id bigint, agent_origin_id bigint, commercial_date date
) on commit drop;
insert into resolver_context
select
  max(presentation.id) filter (where presentation.codigo_item = 'P0127-20L'),
  max(presentation.id) filter (where presentation.codigo_item = 'P0127-10L'),
  product.id, client.id, area.id, role.id,
  (select other_role.id from public.cad_pessoa_papeis other_role
    join public.cad_pessoas_comerciais other_person on other_person.id = other_role.pessoa_id
   where other_person.nome = 'Participante adicional 0127' and other_role.papel = 'vendedor' and other_role.status = 'active'),
  max(origin.id) filter (where origin.codigo = 'direto_elite'),
  max(origin.id) filter (where origin.codigo = 'agente'),
  (clock_timestamp() at time zone 'America/Sao_Paulo')::date
from public.cad_produtos_base product
join public.cad_produto_embalagens presentation on presentation.produto_id = product.id
cross join public.cad_clientes client
cross join public.cad_areas_comerciais area
cross join public.cad_pessoa_papeis role
join public.cad_pessoas_comerciais person on person.id = role.pessoa_id
cross join public.com_origens_comerciais origin
where product.codigo_produto = '0127'
  and client.nome = 'Cliente resolver 0127'
  and area.nome = 'Area resolver 0127'
  and person.nome = 'Agente resolver 0127'
  and role.papel = 'agente' and role.status = 'active'
group by product.id, client.id, area.id, role.id;
grant select on resolver_context to authenticated;

do $$
declare
  v resolver_context%rowtype;
  v_general_version bigint;
  v_agent_version bigint;
  v_ambiguous_version bigint;
  v_future_version bigint;
  v_fixture record;
  v_fixture_lista_id bigint;
  v_fixture_versao_id bigint;
  v_rule_agent bigint;
begin
  select * into v from resolver_context;

  insert into public.com_listas_preco(codigo, nome, created_by)
  values ('GERAL0127', 'Lista geral 0127', '12700000-0000-4000-8000-000000000003')
  returning id into strict v_general_version;
  insert into public.com_lista_preco_versoes(lista_id, numero, vigencia_inicio, vigencia_fim, motivo, created_by, updated_by)
  values (v_general_version, 1, v.commercial_date - 1, v.commercial_date + 60, 'Versao geral valida para smoke 0127',
    '12700000-0000-4000-8000-000000000003', '12700000-0000-4000-8000-000000000003')
  returning id into v_general_version;
  insert into public.com_lista_preco_versao_itens(versao_id, produto_embalagem_id, created_by)
  values (v_general_version, v.presentation_id, '12700000-0000-4000-8000-000000000003');
  insert into public.com_lista_preco_versao_precos(versao_item_id, prazo_dias, valor_centavos_por_litro, created_by)
  select item.id, price.prazo, price.valor, '12700000-0000-4000-8000-000000000003'
  from public.com_lista_preco_versao_itens item
  cross join (values (0, 3000::bigint), (30, 3100::bigint), (60, 3200::bigint)) as price(prazo, valor)
  where item.versao_id = v_general_version;
  insert into public.com_lista_preco_regras(versao_id, codigo, descricao, prioridade, created_by)
  values (v_general_version, 'GERAL', 'Regra geral com escopos curinga para resolver', 0, '12700000-0000-4000-8000-000000000003');
  insert into public.com_lista_preco_publicacoes(versao_id, conteudo_hash, motivo, published_by, published_at)
  values (v_general_version, md5('GERAL0127'), 'Publicacao geral valida no smoke 0127', '12700000-0000-4000-8000-000000000003', clock_timestamp() - interval '1 day');

  insert into public.com_listas_preco(codigo, nome, created_by)
  values ('AGENTE0127', 'Lista agente 0127', '12700000-0000-4000-8000-000000000003')
  returning id into strict v_agent_version;
  insert into public.com_lista_preco_versoes(lista_id, numero, vigencia_inicio, vigencia_fim, motivo, created_by, updated_by)
  values (v_agent_version, 1, v.commercial_date - 1, v.commercial_date + 60, 'Versao agente valida para smoke 0127',
    '12700000-0000-4000-8000-000000000003', '12700000-0000-4000-8000-000000000003')
  returning id into v_agent_version;
  insert into public.com_lista_preco_versao_itens(versao_id, produto_embalagem_id, created_by)
  values (v_agent_version, v.presentation_id, '12700000-0000-4000-8000-000000000003');
  insert into public.com_lista_preco_versao_precos(versao_item_id, prazo_dias, valor_centavos_por_litro, created_by)
  select item.id, price.prazo, price.valor, '12700000-0000-4000-8000-000000000003'
  from public.com_lista_preco_versao_itens item
  cross join (values (0, 4000::bigint), (30, 4100::bigint), (60, 4200::bigint)) as price(prazo, valor)
  where item.versao_id = v_agent_version;
  insert into public.com_lista_preco_regras(versao_id, codigo, descricao, prioridade, created_by)
  values (v_agent_version, 'AGENTE_ESPECIFICO', 'Regra de agente especifico para resolver', 100, '12700000-0000-4000-8000-000000000003')
  returning id into v_rule_agent;
  insert into public.com_lista_preco_regra_origens(regra_id, origem_comercial_id) values (v_rule_agent, v.agent_origin_id);
  insert into public.com_lista_preco_regra_origens(regra_id, origem_comercial_id) values (v_rule_agent, v.direct_origin_id);
  insert into public.com_lista_preco_regra_pessoas(regra_id, pessoa_papel_id) values (v_rule_agent, v.person_role_id);
  insert into public.com_lista_preco_regra_areas(regra_id, area_id) values (v_rule_agent, v.area_id);
  insert into public.com_lista_preco_regra_ufs(regra_id, uf) values (v_rule_agent, 'SP');
  insert into public.com_lista_preco_regra_clientes(regra_id, cliente_id) values (v_rule_agent, v.client_id);
  insert into public.com_lista_preco_regra_produtos(regra_id, produto_id) values (v_rule_agent, v.product_id);
  insert into public.com_lista_preco_regra_apresentacoes(regra_id, produto_embalagem_id) values (v_rule_agent, v.presentation_id);
  insert into public.com_lista_preco_publicacoes(versao_id, conteudo_hash, motivo, published_by, published_at)
  values (v_agent_version, md5('AGENTE0127'), 'Publicacao de agente valida no smoke 0127', '12700000-0000-4000-8000-000000000003', clock_timestamp() - interval '1 day');

  insert into public.com_listas_preco(codigo, nome, created_by)
  values ('AMB0127', 'Lista ambigua 0127', '12700000-0000-4000-8000-000000000003')
  returning id into strict v_ambiguous_version;
  insert into public.com_lista_preco_versoes(lista_id, numero, vigencia_inicio, vigencia_fim, motivo, created_by, updated_by)
  values (v_ambiguous_version, 1, v.commercial_date - 1, v.commercial_date + 60, 'Versao ambigua valida para smoke 0127',
    '12700000-0000-4000-8000-000000000003', '12700000-0000-4000-8000-000000000003')
  returning id into v_ambiguous_version;
  insert into public.com_lista_preco_versao_itens(versao_id, produto_embalagem_id, created_by)
  values (v_ambiguous_version, v.presentation_id, '12700000-0000-4000-8000-000000000003');
  insert into public.com_lista_preco_versao_precos(versao_item_id, prazo_dias, valor_centavos_por_litro, created_by)
  select item.id, 0, 5000, '12700000-0000-4000-8000-000000000003'
  from public.com_lista_preco_versao_itens item where item.versao_id = v_ambiguous_version;
  insert into public.com_lista_preco_regras(versao_id, codigo, descricao, prioridade, created_by)
  values (v_ambiguous_version, 'AMBIGUA', 'Regra de mesma precedencia para testar bloqueio', 0, '12700000-0000-4000-8000-000000000003');
  insert into public.com_lista_preco_publicacoes(versao_id, conteudo_hash, motivo, published_by, published_at)
  values (v_ambiguous_version, md5('AMB0127'), 'Publicacao ambigua valida no smoke 0127', '12700000-0000-4000-8000-000000000003', clock_timestamp() - interval '1 day');

  insert into public.com_listas_preco(codigo, nome, created_by)
  values ('FUTURA0127', 'Lista futura 0127', '12700000-0000-4000-8000-000000000003')
  returning id into strict v_future_version;
  insert into public.com_lista_preco_versoes(lista_id, numero, vigencia_inicio, vigencia_fim, motivo, created_by, updated_by)
  values (v_future_version, 1, v.commercial_date - 1, v.commercial_date + 60, 'Versao futura valida para smoke 0127',
    '12700000-0000-4000-8000-000000000003', '12700000-0000-4000-8000-000000000003')
  returning id into v_future_version;
  insert into public.com_lista_preco_versao_itens(versao_id, produto_embalagem_id, created_by)
  values (v_future_version, v.presentation_id, '12700000-0000-4000-8000-000000000003');
  insert into public.com_lista_preco_versao_precos(versao_item_id, prazo_dias, valor_centavos_por_litro, created_by)
  select item.id, 0, 6000, '12700000-0000-4000-8000-000000000003'
  from public.com_lista_preco_versao_itens item where item.versao_id = v_future_version;
  insert into public.com_lista_preco_regras(versao_id, codigo, descricao, prioridade, created_by)
  values (v_future_version, 'FUTURA', 'Regra futura de maior prioridade para resolver', 1, '12700000-0000-4000-8000-000000000003');
  insert into public.com_lista_preco_publicacoes(versao_id, conteudo_hash, motivo, published_by, published_at)
  values (v_future_version, md5('FUTURA0127'), 'Publicacao futura para nao reinterpretar historico', '12700000-0000-4000-8000-000000000003', clock_timestamp() + interval '2 days');

  for v_fixture in
    select *
      from (values
        ('PRIO10', 'Lista prioridade 10 0127', 10::integer, 7000::bigint),
        ('PRIO20', 'Lista prioridade 20 0127', 20::integer, 7100::bigint),
        ('SEMPRIO0127', 'Lista sem prioridade 0127', null::integer, 7200::bigint)
      ) as fixture(codigo, nome, prioridade, preco)
  loop
    insert into public.com_listas_preco(codigo, nome, created_by)
    values (v_fixture.codigo, v_fixture.nome, '12700000-0000-4000-8000-000000000003')
    returning id into v_fixture_lista_id;
    insert into public.com_lista_preco_versoes(lista_id, numero, vigencia_inicio, vigencia_fim, motivo, created_by, updated_by)
    values (v_fixture_lista_id, 1, v.commercial_date - 1, v.commercial_date + 60, 'Versao de prioridade para smoke 0127',
      '12700000-0000-4000-8000-000000000003', '12700000-0000-4000-8000-000000000003')
    returning id into v_fixture_versao_id;
    insert into public.com_lista_preco_versao_itens(versao_id, produto_embalagem_id, created_by)
    values (v_fixture_versao_id, v.presentation_id, '12700000-0000-4000-8000-000000000003');
    insert into public.com_lista_preco_versao_precos(versao_item_id, prazo_dias, valor_centavos_por_litro, created_by)
    select item.id, 0, v_fixture.preco, '12700000-0000-4000-8000-000000000003'
      from public.com_lista_preco_versao_itens item
     where item.versao_id = v_fixture_versao_id;
    insert into public.com_lista_preco_regras(versao_id, codigo, descricao, prioridade, created_by)
    values (v_fixture_versao_id, v_fixture.codigo, 'Regra generica de prioridade para smoke 0127', v_fixture.prioridade,
      '12700000-0000-4000-8000-000000000003');
    insert into public.com_lista_preco_publicacoes(versao_id, conteudo_hash, motivo, published_by, published_at)
    values (v_fixture_versao_id, md5(v_fixture.codigo), 'Publicacao de prioridade para smoke 0127',
      '12700000-0000-4000-8000-000000000003', clock_timestamp() - interval '1 day');
  end loop;
end
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '12700000-0000-4000-8000-000000000002', true);
do $$
declare v resolver_context%rowtype;
begin
  select * into v from resolver_context;
  begin
    perform public.resolver_com_referencia_comercial(v.commercial_date, 0, v.direct_origin_id, null, null, v.client_id, null::bigint[], v.presentation_id);
    raise exception 'usuario sem alcada resolveu referencia comercial';
  exception when others then
    if sqlerrm = 'usuario sem alcada resolveu referencia comercial' then raise; end if;
    if sqlerrm <> 'not allowed: pedidos.price_reference.resolve' then raise; end if;
  end;
end
$$;

reset role;
select set_config('request.jwt.claim.sub', '12700000-0000-4000-8000-000000000001', true);
do $$
declare
  v resolver_context%rowtype;
  v_result record;
  v_general_version bigint;
  v_agent_version bigint;
  v_ambiguous_version bigint;
  v_future_version bigint;
  v_prio10_version bigint;
  v_prio20_version bigint;
  v_semprio_version bigint;
  v_listas_antes bigint;
  v_planos_antes bigint;
  v_parcelas_antes bigint;
  v_contexto_invalido record;
begin
  select * into v from resolver_context;
  select version.id into v_general_version from public.com_lista_preco_versoes version join public.com_listas_preco list on list.id = version.lista_id where list.codigo = 'GERAL0127';
  select version.id into v_agent_version from public.com_lista_preco_versoes version join public.com_listas_preco list on list.id = version.lista_id where list.codigo = 'AGENTE0127';
  select version.id into v_ambiguous_version from public.com_lista_preco_versoes version join public.com_listas_preco list on list.id = version.lista_id where list.codigo = 'AMB0127';
  select version.id into v_future_version from public.com_lista_preco_versoes version join public.com_listas_preco list on list.id = version.lista_id where list.codigo = 'FUTURA0127';
  select version.id into v_prio10_version from public.com_lista_preco_versoes version join public.com_listas_preco list on list.id = version.lista_id where list.codigo = 'PRIO10';
  select version.id into v_prio20_version from public.com_lista_preco_versoes version join public.com_listas_preco list on list.id = version.lista_id where list.codigo = 'PRIO20';
  select version.id into v_semprio_version from public.com_lista_preco_versoes version join public.com_listas_preco list on list.id = version.lista_id where list.codigo = 'SEMPRIO0127';
  select count(*) into v_listas_antes from public.com_listas_preco;
  select count(*) into v_planos_antes from public.fin_pedido_planos_pagamento;
  select count(*) into v_parcelas_antes from public.fin_pedido_parcelas;

  for v_contexto_invalido in
    select * from (values
      ('origem nula', null::bigint, v.client_id, null::bigint, null::text, null::bigint[], 'origem comercial e obrigatoria'),
      ('origem inexistente', -127::bigint, v.client_id, null::bigint, null::text, null::bigint[], 'origem comercial nao encontrada'),
      ('cliente nulo', v.direct_origin_id, null::bigint, null::bigint, null::text, null::bigint[], 'cliente e obrigatorio'),
      ('cliente inexistente', v.direct_origin_id, -127::bigint, null::bigint, null::text, null::bigint[], 'cliente nao encontrado'),
      ('area inexistente', v.direct_origin_id, v.client_id, -127::bigint, null::text, null::bigint[], 'area comercial nao encontrada'),
      ('participante inexistente', v.direct_origin_id, v.client_id, null::bigint, null::text, array[-127::bigint], 'participante comercial nao encontrado'),
      ('participante nulo', v.direct_origin_id, v.client_id, null::bigint, null::text, array[v.person_role_id, null::bigint], 'participantes comerciais nao podem conter valor nulo'),
      ('UF invalida', v.direct_origin_id, v.client_id, null::bigint, 'ZZ'::text, null::bigint[], 'UF invalida')
    ) as invalid_context(label, origem_id, cliente_id, area_id, uf, pessoa_papel_ids, mensagem)
  loop
    begin
      perform public.resolver_com_referencia_comercial(
        v.commercial_date, 0, v_contexto_invalido.origem_id, v_contexto_invalido.area_id,
        v_contexto_invalido.uf, v_contexto_invalido.cliente_id, v_contexto_invalido.pessoa_papel_ids, v.presentation_id
      );
      raise exception 'contexto invalido foi aceito: %', v_contexto_invalido.label;
    exception when others then
      if sqlerrm = format('contexto invalido foi aceito: %s', v_contexto_invalido.label) then raise; end if;
      if sqlerrm <> v_contexto_invalido.mensagem then
        raise exception 'erro inesperado para contexto invalido %: %', v_contexto_invalido.label, sqlerrm;
      end if;
    end;
  end loop;

  begin
    perform public.resolver_com_referencia_comercial(v.commercial_date, 0, v.direct_origin_id, null, null, v.client_id, null::bigint[], v.uncovered_presentation_id);
    raise exception 'apresentacao sem cobertura resolveu lista';
  exception when others then
    if sqlerrm = 'apresentacao sem cobertura resolveu lista' then raise; end if;
    if sqlerrm <> 'nenhuma lista comercial aplicavel ao contexto' then raise; end if;
  end;

  begin
    perform public.resolver_com_referencia_comercial(v.commercial_date, 0, v.direct_origin_id, null, null, v.client_id, null::bigint[], v.presentation_id);
    raise exception 'listas de mesma precedencia foram escolhidas arbitrariamente';
  exception when others then
    if sqlerrm = 'listas de mesma precedencia foram escolhidas arbitrariamente' then raise; end if;
    if sqlerrm <> 'ambiguidade entre listas comerciais de mesma precedencia e especificidade' then raise; end if;
  end;

  insert into public.com_lista_preco_lifecycle_eventos(publicacao_id, tipo, efetivo_em, motivo, created_by)
  select publication.id, 'withdrawn', v.commercial_date, 'Bloqueio controlado da lista ambigua do smoke', '12700000-0000-4000-8000-000000000003'
  from public.com_lista_preco_publicacoes publication where publication.versao_id = v_ambiguous_version;

  select * into v_result from public.resolver_com_referencia_comercial(v.commercial_date, 0, v.direct_origin_id, null, null, v.client_id, null::bigint[], v.presentation_id);
  if v_result.versao_id <> v_general_version or v_result.prazo_faixa_dias <> 0 or v_result.preco_referencia_centavos_por_litro <> 3000 then
    raise exception 'lista geral ou PMP zero nao foram resolvidos corretamente';
  end if;
  select * into v_result from public.resolver_com_referencia_comercial(v.commercial_date, 30, v.direct_origin_id, null, null, v.client_id, null::bigint[], v.presentation_id);
  if v_result.prazo_faixa_dias <> 30 or v_result.preco_referencia_centavos_por_litro <> 3100 then raise exception 'PMP exato nao usou a faixa exata'; end if;
  select * into v_result from public.resolver_com_referencia_comercial(v.commercial_date, 47, v.direct_origin_id, null, null, v.client_id, null::bigint[], v.presentation_id);
  if v_result.prazo_faixa_dias <> 60 or v_result.preco_referencia_centavos_por_litro <> 3200 then raise exception 'PMP entre faixas nao usou o teto'; end if;
  begin
    perform public.resolver_com_referencia_comercial(v.commercial_date, 61, v.direct_origin_id, null, null, v.client_id, null::bigint[], v.presentation_id);
    raise exception 'PMP acima da maior faixa foi aceito';
  exception when others then
    if sqlerrm = 'PMP acima da maior faixa foi aceito' then raise; end if;
    if sqlerrm <> 'nao ha faixa de preco aplicavel ao PMP informado' then raise; end if;
  end;
  select * into v_result from public.resolver_com_referencia_comercial(v.commercial_date, 0, v.agent_origin_id, v.area_id, 'SP', v.client_id, array[v.other_person_role_id, v.person_role_id], v.presentation_id);
  if v_result.versao_id <> v_agent_version or v_result.especificidade <> 7 or v_result.prioridade <> 100 then raise exception 'regra especifica nao prevaleceu sobre regra geral de prioridade superior'; end if;
  select * into v_result from public.resolver_com_referencia_comercial(v.commercial_date, 0, v.agent_origin_id, v.area_id, 'SP', v.client_id, null::bigint[], v.presentation_id);
  if v_result.versao_id <> v_general_version then raise exception 'regra com participante casou sem participante no contexto'; end if;
  select * into v_result from public.resolver_com_referencia_comercial(v.commercial_date, 0, v.direct_origin_id, v.area_id, 'SP', v.client_id, array[v.person_role_id], v.presentation_id);
  if v_result.versao_id <> v_agent_version then raise exception 'OR dentro do escopo de origem nao foi respeitado'; end if;
  select * into v_result from public.resolver_com_referencia_comercial(v.commercial_date, 0, v.agent_origin_id, null, null, v.client_id, null::bigint[], v.presentation_id);
  if v_result.versao_id <> v_general_version then raise exception 'origem agente forçou lista agente sem escopo especifico'; end if;
  if exists (select 1 from public.com_lista_preco_publicacoes publication where publication.versao_id = v_future_version and (publication.published_at at time zone 'America/Sao_Paulo')::date <= v.commercial_date) then
    raise exception 'fixture futura nao ficou futura';
  end if;
  select * into v_result from public.resolver_com_referencia_comercial(v.commercial_date, 0, v.direct_origin_id, null, null, v.client_id, null::bigint[], v.presentation_id);
  if v_result.versao_id <> v_general_version then raise exception 'publicacao futura reinterpretou resolucao historica'; end if;
  begin
    perform public.resolver_com_referencia_comercial(v.commercial_date + 61, 0, v.direct_origin_id, null, null, v.client_id, null::bigint[], v.presentation_id);
    raise exception 'publicacao fora da vigencia resolveu referencia';
  exception when others then
    if sqlerrm = 'publicacao fora da vigencia resolveu referencia' then raise; end if;
    if sqlerrm <> 'nenhuma lista comercial aplicavel ao contexto' then raise; end if;
  end;
  insert into public.com_lista_preco_lifecycle_eventos(publicacao_id, tipo, efetivo_em, motivo, created_by)
  select publication.id, 'withdrawn', v.commercial_date, 'Retirada controlada da lista geral para teste de prioridade', '12700000-0000-4000-8000-000000000003'
    from public.com_lista_preco_publicacoes publication where publication.versao_id = v_general_version;
  select * into v_result from public.resolver_com_referencia_comercial(v.commercial_date, 0, v.direct_origin_id, null, null, v.client_id, null::bigint[], v.presentation_id);
  if v_result.versao_id <> v_prio10_version or v_result.prioridade <> 10 then
    raise exception 'prioridade 10 nao prevaleceu sobre prioridade 20 na mesma especificidade';
  end if;
  insert into public.com_lista_preco_lifecycle_eventos(publicacao_id, tipo, efetivo_em, motivo, created_by)
  select publication.id, 'withdrawn', v.commercial_date, 'Retirada controlada da prioridade 20 para teste de prioridade nula', '12700000-0000-4000-8000-000000000003'
    from public.com_lista_preco_publicacoes publication where publication.versao_id = v_prio20_version;
  select * into v_result from public.resolver_com_referencia_comercial(v.commercial_date, 0, v.direct_origin_id, null, null, v.client_id, null::bigint[], v.presentation_id);
  if v_result.versao_id <> v_prio10_version or v_result.prioridade <> 10 then
    raise exception 'prioridade numerica nao prevaleceu sobre prioridade nula na mesma especificidade';
  end if;
  if (select count(*) from public.com_listas_preco) <> v_listas_antes
     or (select count(*) from public.fin_pedido_planos_pagamento) <> v_planos_antes
     or (select count(*) from public.fin_pedido_parcelas) <> v_parcelas_antes then
    raise exception 'resolvedor alterou fatos comerciais ou financeiros';
  end if;
end
$$;

rollback;
