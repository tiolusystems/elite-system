-- ORD-01 tranche 1C: deterministic, read-only commercial price reference resolver.

insert into public.permission_actions(
  action_key, module, description, default_allowed, sort_order,
  runtime_module_key, runtime_access_kind
)
values (
  'pedidos.price_reference.resolve', 'pedidos', 'Resolver lista e preco comercial de referencia', false, 133,
  'pedidos', 'read'
)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

create or replace function public.resolver_com_referencia_comercial(
  p_data_comercial date,
  p_pmp_dias numeric,
  p_origem_comercial_id bigint,
  p_area_comercial_id bigint,
  p_uf text,
  p_cliente_id bigint,
  p_pessoa_papel_ids bigint[],
  p_produto_embalagem_id bigint
)
returns table(
  lista_id bigint,
  versao_id bigint,
  publicacao_id bigint,
  regra_id bigint,
  produto_id bigint,
  produto_embalagem_id bigint,
  data_comercial date,
  pmp_dias numeric,
  prazo_faixa_dias integer,
  preco_referencia_centavos_por_litro bigint,
  prioridade integer,
  especificidade integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_produto_id bigint;
  v_candidate jsonb;
  v_candidate_count integer;
  v_uf_normalizada text;
begin
  perform public.require_current_user_permission('pedidos.price_reference.resolve');

  if p_data_comercial is null then
    raise exception 'data comercial e obrigatoria';
  end if;
  if p_pmp_dias is null or p_pmp_dias < 0 then
    raise exception 'PMP deve ser um numero nao negativo';
  end if;
  if p_origem_comercial_id is null then
    raise exception 'origem comercial e obrigatoria';
  end if;
  if not exists (select 1 from public.com_origens_comerciais origin where origin.id = p_origem_comercial_id) then
    raise exception 'origem comercial nao encontrada';
  end if;
  if p_cliente_id is null then
    raise exception 'cliente e obrigatorio';
  end if;
  if not exists (select 1 from public.cad_clientes client where client.id = p_cliente_id) then
    raise exception 'cliente nao encontrado';
  end if;
  if p_area_comercial_id is not null
     and not exists (select 1 from public.cad_areas_comerciais area where area.id = p_area_comercial_id) then
    raise exception 'area comercial nao encontrada';
  end if;
  if p_pessoa_papel_ids is not null and array_position(p_pessoa_papel_ids, null) is not null then
    raise exception 'participantes comerciais nao podem conter valor nulo';
  end if;
  if p_pessoa_papel_ids is not null and exists (
    select 1
      from unnest(p_pessoa_papel_ids) participant(id)
      left join public.cad_pessoa_papeis role on role.id = participant.id
     where role.id is null
  ) then
    raise exception 'participante comercial nao encontrado';
  end if;
  if p_produto_embalagem_id is null then
    raise exception 'apresentacao e obrigatoria';
  end if;
  if p_uf is not null then
    v_uf_normalizada := upper(btrim(p_uf));
  end if;
  if p_uf is not null and v_uf_normalizada not in (
    'AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA',
    'PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO'
  ) then
    raise exception 'UF invalida';
  end if;

  select presentation.produto_id into v_produto_id
    from public.cad_produto_embalagens presentation
   where presentation.id = p_produto_embalagem_id;
  if v_produto_id is null then
    raise exception 'apresentacao nao encontrada';
  end if;

  with candidatas as (
    select
      list.id as lista_id,
      version.id as versao_id,
      publication.id as publicacao_id,
      rule.id as regra_id,
      rule.prioridade,
      (
        case when exists (select 1 from public.com_lista_preco_regra_origens scope where scope.regra_id = rule.id) then 1 else 0 end +
        case when exists (select 1 from public.com_lista_preco_regra_areas scope where scope.regra_id = rule.id) then 1 else 0 end +
        case when exists (select 1 from public.com_lista_preco_regra_ufs scope where scope.regra_id = rule.id) then 1 else 0 end +
        case when exists (select 1 from public.com_lista_preco_regra_clientes scope where scope.regra_id = rule.id) then 1 else 0 end +
        case when exists (select 1 from public.com_lista_preco_regra_pessoas scope where scope.regra_id = rule.id) then 1 else 0 end +
        case when exists (select 1 from public.com_lista_preco_regra_produtos scope where scope.regra_id = rule.id) then 1 else 0 end +
        case when exists (select 1 from public.com_lista_preco_regra_apresentacoes scope where scope.regra_id = rule.id) then 1 else 0 end
      )::integer as especificidade
    from public.com_lista_preco_publicacoes publication
    join public.com_lista_preco_versoes version on version.id = publication.versao_id
    join public.com_listas_preco list on list.id = version.lista_id
    join public.com_lista_preco_versao_itens item
      on item.versao_id = version.id
     and item.produto_embalagem_id = p_produto_embalagem_id
    join public.com_lista_preco_regras rule on rule.versao_id = version.id
    where version.vigencia_inicio <= p_data_comercial
      and (version.vigencia_fim is null or version.vigencia_fim >= p_data_comercial)
      and (publication.published_at at time zone 'America/Sao_Paulo')::date <= p_data_comercial
      and not exists (
        select 1 from public.com_lista_preco_lifecycle_eventos event
         where event.publicacao_id = publication.id
           and event.tipo in ('withdrawn', 'superseded')
           and event.efetivo_em <= p_data_comercial
      )
      and (
        not exists (select 1 from public.com_lista_preco_regra_origens scope where scope.regra_id = rule.id)
        or (p_origem_comercial_id is not null and exists (
          select 1 from public.com_lista_preco_regra_origens scope
           where scope.regra_id = rule.id and scope.origem_comercial_id = p_origem_comercial_id
        ))
      )
      and (
        not exists (select 1 from public.com_lista_preco_regra_areas scope where scope.regra_id = rule.id)
        or (p_area_comercial_id is not null and exists (
          select 1 from public.com_lista_preco_regra_areas scope
           where scope.regra_id = rule.id and scope.area_id = p_area_comercial_id
        ))
      )
      and (
        not exists (select 1 from public.com_lista_preco_regra_ufs scope where scope.regra_id = rule.id)
        or (v_uf_normalizada is not null and exists (
          select 1 from public.com_lista_preco_regra_ufs scope
           where scope.regra_id = rule.id and scope.uf = v_uf_normalizada
        ))
      )
      and (
        not exists (select 1 from public.com_lista_preco_regra_clientes scope where scope.regra_id = rule.id)
        or (p_cliente_id is not null and exists (
          select 1 from public.com_lista_preco_regra_clientes scope
           where scope.regra_id = rule.id and scope.cliente_id = p_cliente_id
        ))
      )
      and (
        not exists (select 1 from public.com_lista_preco_regra_pessoas scope where scope.regra_id = rule.id)
        or (cardinality(coalesce(p_pessoa_papel_ids, '{}'::bigint[])) > 0 and exists (
          select 1 from public.com_lista_preco_regra_pessoas scope
           where scope.regra_id = rule.id and scope.pessoa_papel_id = any(p_pessoa_papel_ids)
        ))
      )
      and (
        not exists (select 1 from public.com_lista_preco_regra_produtos scope where scope.regra_id = rule.id)
        or exists (
          select 1 from public.com_lista_preco_regra_produtos scope
           where scope.regra_id = rule.id and scope.produto_id = v_produto_id
        )
      )
      and (
        not exists (select 1 from public.com_lista_preco_regra_apresentacoes scope where scope.regra_id = rule.id)
        or exists (
          select 1 from public.com_lista_preco_regra_apresentacoes scope
           where scope.regra_id = rule.id and scope.produto_embalagem_id = p_produto_embalagem_id
        )
      )
  ), classificadas as (
    select candidate.*,
      dense_rank() over (
        order by
          candidate.especificidade desc,
          case when candidate.prioridade is null then 1 else 0 end,
          candidate.prioridade asc nulls last
      ) as classificacao
    from candidatas candidate
  )
  select count(*), jsonb_agg(jsonb_build_object(
    'lista_id', ranked.lista_id,
    'versao_id', ranked.versao_id,
    'publicacao_id', ranked.publicacao_id,
    'regra_id', ranked.regra_id,
    'prioridade', ranked.prioridade,
    'especificidade', ranked.especificidade
  )) -> 0
    into v_candidate_count, v_candidate
    from classificadas ranked
   where ranked.classificacao = 1;

  if v_candidate_count = 0 then
    raise exception 'nenhuma lista comercial aplicavel ao contexto';
  end if;
  if v_candidate_count > 1 then
    raise exception 'ambiguidade entre listas comerciais de mesma precedencia e especificidade';
  end if;

  select price.prazo_dias, price.valor_centavos_por_litro
    into prazo_faixa_dias, preco_referencia_centavos_por_litro
    from public.com_lista_preco_versao_itens item
    join public.com_lista_preco_versao_precos price on price.versao_item_id = item.id
   where item.versao_id = (v_candidate->>'versao_id')::bigint
     and item.produto_embalagem_id = p_produto_embalagem_id
     and price.prazo_dias::numeric >= p_pmp_dias
   order by price.prazo_dias asc;
  if prazo_faixa_dias is null then
    raise exception 'nao ha faixa de preco aplicavel ao PMP informado';
  end if;

  lista_id := (v_candidate->>'lista_id')::bigint;
  versao_id := (v_candidate->>'versao_id')::bigint;
  publicacao_id := (v_candidate->>'publicacao_id')::bigint;
  regra_id := (v_candidate->>'regra_id')::bigint;
  produto_id := v_produto_id;
  produto_embalagem_id := p_produto_embalagem_id;
  data_comercial := p_data_comercial;
  pmp_dias := p_pmp_dias;
  prioridade := (v_candidate->>'prioridade')::integer;
  especificidade := (v_candidate->>'especificidade')::integer;
  return next;
end;
$$;

revoke all on function public.resolver_com_referencia_comercial(date, numeric, bigint, bigint, text, bigint, bigint[], bigint)
  from public, anon, authenticated;
grant execute on function public.resolver_com_referencia_comercial(date, numeric, bigint, bigint, text, bigint, bigint[], bigint)
  to authenticated;

comment on function public.resolver_com_referencia_comercial(date, numeric, bigint, bigint, text, bigint, bigint[], bigint) is
  'ORD-01 1C: resolvedor somente leitura, fail-closed, da unica referencia comercial por data, contexto relacional e PMP exato.';
