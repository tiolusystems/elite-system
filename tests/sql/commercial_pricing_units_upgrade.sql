\set ON_ERROR_STOP on
begin;

insert into auth.users(id, email) values
  ('12900000-0000-4000-8000-000000000101', 'pricing-upgrade-author@test.invalid');
insert into public.user_profiles(id, display_name, role, status) values
  ('12900000-0000-4000-8000-000000000101', 'Autor upgrade unidade comercial 0129', 'admin', 'active');

create temporary table upgrade_0129_context (
  versao_id bigint primary key,
  publicacao_id bigint not null,
  published_at timestamptz not null,
  published_by uuid not null,
  lifecycle_count integer not null,
  legacy_hash text not null
) on commit drop;

insert into public.cad_produtos_base(codigo_produto, nome, nome_norm, status, created_by, updated_by)
values ('1298', 'Produto upgrade unidade comercial 0129', 'produto upgrade unidade comercial 0129', 'active', '12900000-0000-4000-8000-000000000101', '12900000-0000-4000-8000-000000000101');
insert into public.cad_embalagens(descricao, descricao_norm, unidade, volume_litros, status, unidade_id, origem_dados, created_by, updated_by)
values ('Embalagem upgrade unidade comercial 0129', 'embalagem upgrade unidade comercial 0129', 'UN', 20, 'active', (select id from public.cad_unidades_medida where lower(codigo) = 'un'), 'sistema', '12900000-0000-4000-8000-000000000101', '12900000-0000-4000-8000-000000000101');
insert into public.cad_produto_embalagens(produto_id, embalagem_id, codigo_item, status, origem_dados, created_by, updated_by)
select produto.id, embalagem.id, 'P0129UP', 'active', 'sistema', '12900000-0000-4000-8000-000000000101', '12900000-0000-4000-8000-000000000101'
  from public.cad_produtos_base produto
 cross join public.cad_embalagens embalagem
 where produto.codigo_produto = '1298'
   and embalagem.descricao = 'Embalagem upgrade unidade comercial 0129';

do $$
declare
  v_lista_id bigint;
  v_versao_id bigint;
  v_item_id bigint;
  v_publicacao_id bigint;
  v_hash text;
begin
  insert into public.com_listas_preco(codigo, nome, created_by)
  values ('UP0129', 'Lista legado para upgrade 0129', '12900000-0000-4000-8000-000000000101')
  returning id into v_lista_id;
  insert into public.com_lista_preco_versoes(lista_id, numero, vigencia_inicio, motivo, created_by, updated_by)
  values (v_lista_id, 1, current_date, 'Publicacao legado BRL/L para upgrade da unidade comercial', '12900000-0000-4000-8000-000000000101', '12900000-0000-4000-8000-000000000101')
  returning id into v_versao_id;
  insert into public.com_lista_preco_versao_itens(versao_id, produto_embalagem_id, created_by)
  values (v_versao_id, (select id from public.cad_produto_embalagens where codigo_item = 'P0129UP'), '12900000-0000-4000-8000-000000000101')
  returning id into v_item_id;
  insert into public.com_lista_preco_versao_precos(versao_item_id, prazo_dias, valor_centavos_por_litro, created_by)
  values (v_item_id, 30, 3126, '12900000-0000-4000-8000-000000000101');
  select md5(public.com_lista_preco_versao_documento(v_versao_id)::text) into v_hash;
  insert into public.com_lista_preco_publicacoes(versao_id, conteudo_hash, motivo, published_by)
  values (v_versao_id, v_hash, 'Publicacao legado valida antes da evolucao de schema', '12900000-0000-4000-8000-000000000101')
  returning id into v_publicacao_id;
  insert into public.com_lista_preco_lifecycle_eventos(publicacao_id, tipo, efetivo_em, motivo, created_by)
  values (v_publicacao_id, 'withdrawn', current_date + 1, 'Lifecycle legado preservado no upgrade de schema', '12900000-0000-4000-8000-000000000101');
  insert into upgrade_0129_context(versao_id, publicacao_id, published_at, published_by, lifecycle_count, legacy_hash)
  select publication.versao_id, publication.id, publication.published_at, publication.published_by,
         (select count(*)::integer from public.com_lista_preco_lifecycle_eventos event where event.publicacao_id = publication.id),
         publication.conteudo_hash
    from public.com_lista_preco_publicacoes publication
   where publication.id = v_publicacao_id;
  if v_hash is distinct from (select legacy_hash from upgrade_0129_context where versao_id = v_versao_id) then
    raise exception 'publicacao legado deveria iniciar com checksum valido';
  end if;
end;
$$;

\i supabase/migrations/0129_govern_commercial_pricing_units.sql

do $$
declare
  v_l_id bigint;
  v_fator numeric;
  v_preco_generico bigint;
  v_preco_legado bigint;
  v_publicacao record;
begin
  select id into v_l_id from public.cad_unidades_medida where lower(codigo) = 'l' and status = 'active';
  select item.quantidade_unidade_precificacao_por_apresentacao,
         price.valor_centavos_por_unidade_precificacao,
         price.valor_centavos_por_litro
    into v_fator, v_preco_generico, v_preco_legado
    from public.com_lista_preco_versao_itens item
    join public.com_lista_preco_versao_precos price on price.versao_item_id = item.id
   where item.versao_id = (select versao_id from upgrade_0129_context);
  if not exists (
    select 1 from public.com_lista_preco_versao_itens item
     where item.versao_id = (select versao_id from upgrade_0129_context)
       and item.unidade_precificacao_id = v_l_id
  ) or v_fator <> 20 or v_preco_generico <> 3126 or v_preco_legado <> 3126 then
    raise exception 'upgrade 0129 nao congelou o contrato generico L legado';
  end if;

  select publication.* into v_publicacao
    from public.com_lista_preco_publicacoes publication
   where publication.versao_id = (select versao_id from upgrade_0129_context);
  if v_publicacao.id <> (select publicacao_id from upgrade_0129_context)
     or v_publicacao.published_at is distinct from (select published_at from upgrade_0129_context)
     or v_publicacao.published_by is distinct from (select published_by from upgrade_0129_context)
     or v_publicacao.conteudo_hash is distinct from md5(public.com_lista_preco_versao_documento(v_publicacao.versao_id)::text)
     or v_publicacao.conteudo_hash = (select legacy_hash from upgrade_0129_context) then
    raise exception 'upgrade 0129 alterou fato de publicacao ou nao recompos checksum canonico';
  end if;
  if (select count(*)::integer from public.com_lista_preco_lifecycle_eventos event where event.publicacao_id = v_publicacao.id)
       <> (select lifecycle_count from upgrade_0129_context) then
    raise exception 'upgrade 0129 alterou lifecycle de publicacao';
  end if;
  if exists (
    select 1 from pg_trigger trigger
     where trigger.tgrelid in ('public.com_lista_preco_versao_itens'::regclass, 'public.com_lista_preco_versao_precos'::regclass, 'public.com_lista_preco_publicacoes'::regclass)
       and trigger.tgname in ('trg_com_lista_preco_itens_published_immutable', 'trg_com_lista_preco_precos_published_immutable', 'trg_com_lista_preco_publicacoes_append_only')
       and trigger.tgenabled <> 'O'
  ) then
    raise exception 'upgrade 0129 nao restaurou guards de imutabilidade';
  end if;

  begin
    update public.com_lista_preco_publicacoes
       set conteudo_hash = md5('tentativa indevida')
     where id = v_publicacao.id;
    raise exception 'guard append-only de publicacao deveria permanecer ativo';
  exception when others then
    if position('append-only' in sqlerrm) = 0 then raise; end if;
  end;
  begin
    update public.com_lista_preco_versao_itens
       set quantidade_unidade_precificacao_por_apresentacao = 21
     where versao_id = v_publicacao.versao_id;
    raise exception 'guard de imutabilidade da versao deveria permanecer ativo';
  exception when others then
    if position('versao publicada e imutavel' in sqlerrm) = 0 then raise; end if;
  end;
end;
$$;

rollback;
\echo COMMERCIAL_PRICING_UNITS_UPGRADE_OK
