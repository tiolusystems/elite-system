-- ORD-01 tranche 1E: generic commercial pricing units, additive over the BRL/L contract.

alter table public.com_lista_preco_versao_itens
  add column if not exists unidade_precificacao_id bigint references public.cad_unidades_medida(id) on delete restrict,
  add column if not exists quantidade_unidade_precificacao_por_apresentacao numeric;

alter table public.com_lista_preco_versao_itens
  add constraint com_lista_preco_item_unidade_comercial_pair_check check (
    (unidade_precificacao_id is null and quantidade_unidade_precificacao_por_apresentacao is null)
    or (
      unidade_precificacao_id is not null
      and quantidade_unidade_precificacao_por_apresentacao is not null
      and quantidade_unidade_precificacao_por_apresentacao > 0
    )
  );

alter table public.com_lista_preco_versao_precos
  alter column valor_centavos_por_litro drop not null,
  add column if not exists valor_centavos_por_unidade_precificacao bigint;

alter table public.com_lista_preco_versao_precos
  add constraint com_lista_preco_precos_fonte_comercial_check check (
    valor_centavos_por_litro is not null
    or valor_centavos_por_unidade_precificacao is not null
  ),
  add constraint com_lista_preco_precos_unidade_valor_check check (
    valor_centavos_por_unidade_precificacao is null
    or valor_centavos_por_unidade_precificacao > 0
  );

alter table public.com_pedido_item_referencias_comerciais
  alter column preco_referencia_centavos_por_litro drop not null,
  add column if not exists unidade_precificacao_id bigint references public.cad_unidades_medida(id) on delete restrict,
  add column if not exists quantidade_unidade_precificacao_por_apresentacao numeric,
  add column if not exists preco_referencia_centavos_por_unidade_precificacao bigint;

alter table public.com_pedido_item_referencias_comerciais
  add constraint com_pedido_item_referencias_unidade_comercial_valor_check check (
    (unidade_precificacao_id is null
      and quantidade_unidade_precificacao_por_apresentacao is null
      and preco_referencia_centavos_por_unidade_precificacao is null)
    or (
      unidade_precificacao_id is not null
      and quantidade_unidade_precificacao_por_apresentacao is not null
      and quantidade_unidade_precificacao_por_apresentacao > 0
      and preco_referencia_centavos_por_unidade_precificacao is not null
      and preco_referencia_centavos_por_unidade_precificacao > 0
    )
  );

create or replace function public.normalize_com_lista_preco_item_unidade_comercial()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_unidade_l_id bigint;
  v_fator numeric;
begin
  if new.unidade_precificacao_id is null
     and new.quantidade_unidade_precificacao_por_apresentacao is null then
    select unidade.id, embalagem.volume_litros
      into v_unidade_l_id, v_fator
      from public.cad_produto_embalagens presentation
      join public.cad_embalagens embalagem on embalagem.id = presentation.embalagem_id
      join public.cad_unidades_medida unidade on lower(unidade.codigo) = 'l' and unidade.status = 'active'
     where presentation.id = new.produto_embalagem_id;
    if v_unidade_l_id is null or v_fator is null or v_fator <= 0 then
      raise exception 'item legado exige capacidade positiva da apresentacao para congelar a unidade comercial L';
    end if;
    new.unidade_precificacao_id := v_unidade_l_id;
    new.quantidade_unidade_precificacao_por_apresentacao := v_fator;
  elsif new.unidade_precificacao_id is null
     or new.quantidade_unidade_precificacao_por_apresentacao is null
     or new.quantidade_unidade_precificacao_por_apresentacao <= 0 then
    raise exception 'item comercial exige unidade e fator congelados';
  end if;
  return new;
end;
$$;

revoke all on function public.normalize_com_lista_preco_item_unidade_comercial()
  from public, anon, authenticated;

create trigger trg_com_lista_preco_itens_unidade_comercial
before insert or update on public.com_lista_preco_versao_itens
for each row execute function public.normalize_com_lista_preco_item_unidade_comercial();

create or replace function public.validate_com_lista_preco_valor_unidade_comercial()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_unidade_id bigint;
  v_fator numeric;
  v_codigo text;
begin
  select item.unidade_precificacao_id, item.quantidade_unidade_precificacao_por_apresentacao,
         unidade.codigo
    into v_unidade_id, v_fator, v_codigo
    from public.com_lista_preco_versao_itens item
    left join public.cad_unidades_medida unidade on unidade.id = item.unidade_precificacao_id
   where item.id = new.versao_item_id;

  if v_unidade_id is null or v_fator is null or v_fator <= 0 or v_codigo is null then
    raise exception 'item comercial exige unidade e fator congelados';
  elsif lower(v_codigo) = 'l' then
    if new.valor_centavos_por_litro is null
       and new.valor_centavos_por_unidade_precificacao is null then
      raise exception 'preco em litro exige valor comercial';
    elsif new.valor_centavos_por_litro is null then
      new.valor_centavos_por_litro := new.valor_centavos_por_unidade_precificacao;
    elsif new.valor_centavos_por_unidade_precificacao is null then
      new.valor_centavos_por_unidade_precificacao := new.valor_centavos_por_litro;
    elsif new.valor_centavos_por_litro <> new.valor_centavos_por_unidade_precificacao then
      raise exception 'preco generico em litro exige espelho legado identico';
    end if;
  elsif new.valor_centavos_por_litro is not null
     or new.valor_centavos_por_unidade_precificacao is null then
    raise exception 'preco generico fora de litro nao possui valor legado por litro';
  end if;
  return new;
end;
$$;

revoke all on function public.validate_com_lista_preco_valor_unidade_comercial()
  from public, anon, authenticated;

create trigger trg_com_lista_preco_precos_unidade_comercial
before insert or update on public.com_lista_preco_versao_precos
for each row execute function public.validate_com_lista_preco_valor_unidade_comercial();

-- Retains only versions whose published document changed through this deterministic schema upgrade.
create temporary table _ord_0129_versoes_normalizadas (
  versao_id bigint primary key
) on commit preserve rows;

do $$
declare
  v_unidade_l_id bigint;
begin
  select unidade.id into v_unidade_l_id
    from public.cad_unidades_medida unidade
   where lower(unidade.codigo) = 'l' and unidade.status = 'active';
  if v_unidade_l_id is null then
    raise exception 'unidade comercial L ativa e obrigatoria para normalizar listas BRL/L existentes';
  end if;

  alter table public.com_lista_preco_versao_itens disable trigger trg_com_lista_preco_itens_published_immutable;
  alter table public.com_lista_preco_versao_precos disable trigger trg_com_lista_preco_precos_published_immutable;
  begin
    with itens_normalizados as (
      update public.com_lista_preco_versao_itens item
         set unidade_precificacao_id = v_unidade_l_id,
             quantidade_unidade_precificacao_por_apresentacao = embalagem.volume_litros
        from public.cad_produto_embalagens presentation
        join public.cad_embalagens embalagem on embalagem.id = presentation.embalagem_id
       where item.produto_embalagem_id = presentation.id
         and item.unidade_precificacao_id is null
         and item.quantidade_unidade_precificacao_por_apresentacao is null
         and embalagem.volume_litros > 0
      returning item.versao_id
    )
    insert into _ord_0129_versoes_normalizadas(versao_id)
    select distinct versao_id from itens_normalizados
    on conflict (versao_id) do nothing;

    update public.com_lista_preco_versao_precos price
       set valor_centavos_por_unidade_precificacao = price.valor_centavos_por_litro
      from public.com_lista_preco_versao_itens item
     where price.versao_item_id = item.id
       and item.unidade_precificacao_id = v_unidade_l_id
       and price.valor_centavos_por_litro is not null
       and price.valor_centavos_por_unidade_precificacao is null;
  exception when others then
    alter table public.com_lista_preco_versao_itens enable trigger trg_com_lista_preco_itens_published_immutable;
    alter table public.com_lista_preco_versao_precos enable trigger trg_com_lista_preco_precos_published_immutable;
    raise;
  end;
  alter table public.com_lista_preco_versao_itens enable trigger trg_com_lista_preco_itens_published_immutable;
  alter table public.com_lista_preco_versao_precos enable trigger trg_com_lista_preco_precos_published_immutable;
end;
$$;

create or replace function public.validate_com_pedido_referencia_unidade_comercial()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_codigo text;
begin
  if new.unidade_precificacao_id is null
     or new.quantidade_unidade_precificacao_por_apresentacao is null
     or new.quantidade_unidade_precificacao_por_apresentacao <= 0
     or new.preco_referencia_centavos_por_unidade_precificacao is null
     or new.preco_referencia_centavos_por_unidade_precificacao <= 0 then
    raise exception 'snapshot comercial exige unidade, fator e preco genericos congelados';
  end if;

  select unidade.codigo into v_codigo
    from public.cad_unidades_medida unidade
   where unidade.id = new.unidade_precificacao_id;
  if v_codigo is null then raise exception 'unidade comercial nao encontrada'; end if;
  if lower(v_codigo) = 'l' then
    if new.preco_referencia_centavos_por_litro is distinct from new.preco_referencia_centavos_por_unidade_precificacao then
      raise exception 'snapshot em litro exige preco legado identico ao preco generico';
    end if;
  elsif new.preco_referencia_centavos_por_litro is not null then
    raise exception 'snapshot fora de litro nao possui preco legado por litro';
  end if;
  return new;
end;
$$;

revoke all on function public.validate_com_pedido_referencia_unidade_comercial()
  from public, anon, authenticated;

create trigger trg_com_pedido_referencias_unidade_comercial
before insert on public.com_pedido_item_referencias_comerciais
for each row execute function public.validate_com_pedido_referencia_unidade_comercial();

create or replace function public.protect_com_lista_preco_published_content()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_old_versao_id bigint;
  v_new_versao_id bigint;
begin
  if tg_argv[0] not in ('version', 'item', 'price', 'rule', 'scope') then
    raise exception 'invalid price list immutable trigger configuration';
  end if;
  if tg_op in ('UPDATE', 'DELETE') then
    if tg_argv[0] = 'version' then v_old_versao_id := old.id;
    elsif tg_argv[0] = 'item' then v_old_versao_id := old.versao_id;
    elsif tg_argv[0] = 'price' then
      select item.versao_id into v_old_versao_id from public.com_lista_preco_versao_itens item where item.id = old.versao_item_id;
    elsif tg_argv[0] = 'rule' then v_old_versao_id := old.versao_id;
    else
      select rule.versao_id into v_old_versao_id from public.com_lista_preco_regras rule where rule.id = old.regra_id;
    end if;
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    if tg_argv[0] = 'version' then v_new_versao_id := new.id;
    elsif tg_argv[0] = 'item' then v_new_versao_id := new.versao_id;
    elsif tg_argv[0] = 'price' then
      select item.versao_id into v_new_versao_id from public.com_lista_preco_versao_itens item where item.id = new.versao_item_id;
    elsif tg_argv[0] = 'rule' then v_new_versao_id := new.versao_id;
    else
      select rule.versao_id into v_new_versao_id from public.com_lista_preco_regras rule where rule.id = new.regra_id;
    end if;
  end if;
  if exists (select 1 from public.com_lista_preco_publicacoes publication where publication.versao_id in (v_old_versao_id, v_new_versao_id)) then
    raise exception 'versao publicada e imutavel; crie uma nova versao';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create or replace function public.com_lista_preco_versao_documento(p_versao_id bigint)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'versao', jsonb_build_object(
      'id', version.id, 'lista_id', version.lista_id, 'numero', version.numero,
      'versao_anterior_id', version.versao_anterior_id, 'descricao', version.descricao,
      'vigencia_inicio', version.vigencia_inicio, 'vigencia_fim', version.vigencia_fim
    ),
    'itens', coalesce((
      select jsonb_agg(
        case when item.unidade_precificacao_id is null then
          jsonb_build_object(
            'id', item.id, 'produto_embalagem_id', item.produto_embalagem_id,
            'precos', coalesce((select jsonb_agg(jsonb_build_object(
              'prazo_dias', price.prazo_dias, 'valor_centavos_por_litro', price.valor_centavos_por_litro
            ) order by price.prazo_dias) from public.com_lista_preco_versao_precos price where price.versao_item_id = item.id), '[]'::jsonb)
          )
        else
          jsonb_build_object(
            'id', item.id, 'produto_embalagem_id', item.produto_embalagem_id,
            'unidade_precificacao_id', item.unidade_precificacao_id,
            'quantidade_unidade_precificacao_por_apresentacao', item.quantidade_unidade_precificacao_por_apresentacao,
            'precos', coalesce((select jsonb_agg(jsonb_build_object(
              'prazo_dias', price.prazo_dias,
              'valor_centavos_por_unidade_precificacao', price.valor_centavos_por_unidade_precificacao,
              'valor_centavos_por_litro', price.valor_centavos_por_litro
            ) order by price.prazo_dias) from public.com_lista_preco_versao_precos price where price.versao_item_id = item.id), '[]'::jsonb)
          )
        end order by item.produto_embalagem_id
      ) from public.com_lista_preco_versao_itens item where item.versao_id = version.id
    ), '[]'::jsonb),
    'regras', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', rule.id, 'codigo', rule.codigo, 'descricao', rule.descricao, 'prioridade', rule.prioridade,
        'origens_comerciais', coalesce((select jsonb_agg(scope.origem_comercial_id order by scope.origem_comercial_id) from public.com_lista_preco_regra_origens scope where scope.regra_id = rule.id), '[]'::jsonb),
        'pessoa_papel_ids', coalesce((select jsonb_agg(scope.pessoa_papel_id order by scope.pessoa_papel_id) from public.com_lista_preco_regra_pessoas scope where scope.regra_id = rule.id), '[]'::jsonb),
        'areas_comerciais', coalesce((select jsonb_agg(scope.area_id order by scope.area_id) from public.com_lista_preco_regra_areas scope where scope.regra_id = rule.id), '[]'::jsonb),
        'ufs', coalesce((select jsonb_agg(scope.uf order by scope.uf) from public.com_lista_preco_regra_ufs scope where scope.regra_id = rule.id), '[]'::jsonb),
        'clientes', coalesce((select jsonb_agg(scope.cliente_id order by scope.cliente_id) from public.com_lista_preco_regra_clientes scope where scope.regra_id = rule.id), '[]'::jsonb),
        'produtos', coalesce((select jsonb_agg(scope.produto_id order by scope.produto_id) from public.com_lista_preco_regra_produtos scope where scope.regra_id = rule.id), '[]'::jsonb),
        'apresentacoes', coalesce((select jsonb_agg(scope.produto_embalagem_id order by scope.produto_embalagem_id) from public.com_lista_preco_regra_apresentacoes scope where scope.regra_id = rule.id), '[]'::jsonb)
      ) order by rule.codigo_norm) from public.com_lista_preco_regras rule where rule.versao_id = version.id
    ), '[]'::jsonb)
  ) from public.com_lista_preco_versoes version where version.id = p_versao_id;
$$;

-- This is a deterministic checksum normalization for a schema-evolved document, not republication.
-- It preserves the publication fact and temporarily bypasses only its append-only trigger.
do $$
begin
  if exists (
    select 1
      from public.com_lista_preco_publicacoes publication
      join _ord_0129_versoes_normalizadas normalized on normalized.versao_id = publication.versao_id
  ) then
    alter table public.com_lista_preco_publicacoes disable trigger trg_com_lista_preco_publicacoes_append_only;
    begin
      update public.com_lista_preco_publicacoes publication
         set conteudo_hash = md5(public.com_lista_preco_versao_documento(publication.versao_id)::text)
        from _ord_0129_versoes_normalizadas normalized
       where publication.versao_id = normalized.versao_id
         and publication.conteudo_hash is distinct from md5(public.com_lista_preco_versao_documento(publication.versao_id)::text);
    exception when others then
      alter table public.com_lista_preco_publicacoes enable trigger trg_com_lista_preco_publicacoes_append_only;
      raise;
    end;
    alter table public.com_lista_preco_publicacoes enable trigger trg_com_lista_preco_publicacoes_append_only;
  end if;
end;
$$;

drop table _ord_0129_versoes_normalizadas;

create or replace function public.replace_com_lista_preco_rascunho_idempotente(
  p_idempotency_key uuid, p_versao_id bigint, p_vigencia_inicio date, p_vigencia_fim date,
  p_descricao text, p_itens jsonb, p_regras jsonb, p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_context jsonb; v_actor uuid; v_payload_hash text; v_existing public.com_lista_preco_requisicoes%rowtype;
  v_lista_id bigint; v_before jsonb; v_item jsonb; v_price jsonb; v_rule jsonb; v_value text;
  v_item_id bigint; v_rule_id bigint; v_unidade_id bigint; v_fator numeric; v_codigo_unidade text; v_valor bigint;
  v_produto_embalagem_id bigint;
begin
  v_context := public.begin_audited_rpc('pedidos.price_lists.draft.manage', 'pedidos', 'com_lista_preco_versoes', 'field_risk', jsonb_build_object('correlation_id', coalesce(p_idempotency_key::text, 'missing')));
  if p_idempotency_key is null then raise exception 'chave de idempotencia e obrigatoria'; end if;
  if p_versao_id is null or p_vigencia_inicio is null then raise exception 'versao e inicio da vigencia sao obrigatorios'; end if;
  if p_vigencia_fim is not null and p_vigencia_fim < p_vigencia_inicio then raise exception 'fim da vigencia e invalido'; end if;
  if jsonb_typeof(p_itens) <> 'array' or jsonb_typeof(p_regras) <> 'array' then raise exception 'itens e regras devem ser listas'; end if;
  if length(btrim(coalesce(p_motivo, ''))) < 10 then raise exception 'motivo deve ter ao menos 10 caracteres'; end if;
  v_actor := public.current_actor_id();
  v_payload_hash := md5(jsonb_build_object('tipo', 'rascunho_substituir', 'versao_id', p_versao_id, 'vigencia_inicio', p_vigencia_inicio, 'vigencia_fim', p_vigencia_fim, 'descricao', nullif(btrim(p_descricao), ''), 'itens', p_itens, 'regras', p_regras, 'motivo', btrim(p_motivo))::text);
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing from public.com_lista_preco_requisicoes request where request.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.tipo_operacao <> 'rascunho_substituir' or v_existing.actor_id is distinct from v_actor or v_existing.payload_hash is distinct from v_payload_hash then raise exception 'chave de idempotencia reutilizada com conteudo diferente'; end if;
    return v_existing.versao_id;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('price_list_version:' || p_versao_id::text, 0));
  select version.lista_id into v_lista_id from public.com_lista_preco_versoes version where version.id = p_versao_id for update;
  if not found then raise exception 'versao de lista nao encontrada'; end if;
  if exists (select 1 from public.com_lista_preco_publicacoes publication where publication.versao_id = p_versao_id) then raise exception 'versao publicada e imutavel; crie uma nova versao'; end if;
  v_before := public.com_lista_preco_versao_documento(p_versao_id);
  delete from public.com_lista_preco_regras where versao_id = p_versao_id;
  delete from public.com_lista_preco_versao_itens where versao_id = p_versao_id;
  update public.com_lista_preco_versoes set vigencia_inicio = p_vigencia_inicio, vigencia_fim = p_vigencia_fim, descricao = nullif(btrim(p_descricao), ''), motivo = btrim(p_motivo), updated_by = v_actor, updated_at = clock_timestamp() where id = p_versao_id;

  for v_item in select value from jsonb_array_elements(p_itens) loop
    v_unidade_id := null; v_fator := null; v_codigo_unidade := null;
    if nullif(v_item->>'produto_embalagem_id', '') is null then raise exception 'item exige apresentacao'; end if;
    v_produto_embalagem_id := (v_item->>'produto_embalagem_id')::bigint;
    if jsonb_typeof(v_item->'precos') <> 'array' then raise exception 'precos do item devem ser uma lista'; end if;
    if (v_item ? 'unidade_precificacao_id') or (v_item ? 'quantidade_unidade_precificacao_por_apresentacao') then
      if nullif(v_item->>'unidade_precificacao_id', '') is null or nullif(v_item->>'quantidade_unidade_precificacao_por_apresentacao', '') is null then raise exception 'item generico exige unidade e fator comercial'; end if;
      v_unidade_id := (v_item->>'unidade_precificacao_id')::bigint;
      v_fator := (v_item->>'quantidade_unidade_precificacao_por_apresentacao')::numeric;
      select unidade.codigo into v_codigo_unidade from public.cad_unidades_medida unidade where unidade.id = v_unidade_id and unidade.status = 'active';
      if v_codigo_unidade is null or v_fator <= 0 then raise exception 'unidade ou fator comercial invalido'; end if;
    else
      if jsonb_array_length(v_item->'precos') = 0 or exists (
        select 1 from jsonb_array_elements(v_item->'precos') price(value)
         where not (price.value ? 'valor_centavos_por_litro')
            or price.value ? 'valor_centavos_por_unidade_precificacao'
      ) then
        raise exception 'item generico exige unidade e fator comercial';
      end if;
      select unidade.id, embalagem.volume_litros, unidade.codigo
        into v_unidade_id, v_fator, v_codigo_unidade
        from public.cad_produto_embalagens presentation
        join public.cad_embalagens embalagem on embalagem.id = presentation.embalagem_id
        join public.cad_unidades_medida unidade on lower(unidade.codigo) = 'l' and unidade.status = 'active'
       where presentation.id = v_produto_embalagem_id;
      if v_unidade_id is null or v_fator is null or v_fator <= 0 then
        raise exception 'item legado exige capacidade positiva da apresentacao para congelar a unidade comercial L';
      end if;
    end if;
    insert into public.com_lista_preco_versao_itens(versao_id, produto_embalagem_id, unidade_precificacao_id, quantidade_unidade_precificacao_por_apresentacao, created_by)
    values (p_versao_id, v_produto_embalagem_id, v_unidade_id, v_fator, v_actor) returning id into v_item_id;
    for v_price in select value from jsonb_array_elements(v_item->'precos') loop
      if v_price ? 'valor_centavos_por_unidade_precificacao' then
        v_valor := (v_price->>'valor_centavos_por_unidade_precificacao')::bigint;
        if lower(v_codigo_unidade) = 'l'
           and v_price ? 'valor_centavos_por_litro'
           and (v_price->>'valor_centavos_por_litro')::bigint <> v_valor then
          raise exception 'preco generico em litro exige espelho legado identico';
        end if;
        if lower(v_codigo_unidade) <> 'l' and v_price ? 'valor_centavos_por_litro' then
          raise exception 'preco generico fora de litro nao aceita preco legado';
        end if;
      elsif v_price ? 'valor_centavos_por_litro' then
        if lower(v_codigo_unidade) <> 'l' then raise exception 'preco legado exige unidade comercial L'; end if;
        v_valor := (v_price->>'valor_centavos_por_litro')::bigint;
      else
        raise exception 'item exige preco por unidade comercial';
      end if;
      insert into public.com_lista_preco_versao_precos(versao_item_id, prazo_dias, valor_centavos_por_litro, valor_centavos_por_unidade_precificacao, created_by)
      values (v_item_id, (v_price->>'prazo_dias')::integer,
        case when lower(v_codigo_unidade) = 'l' then v_valor else null end, v_valor, v_actor);
    end loop;
  end loop;

  for v_rule in select value from jsonb_array_elements(p_regras) loop
    insert into public.com_lista_preco_regras(versao_id, codigo, descricao, prioridade, created_by)
    values (p_versao_id, btrim(v_rule->>'codigo'), btrim(v_rule->>'descricao'), nullif(v_rule->>'prioridade', '')::integer, v_actor) returning id into v_rule_id;
    for v_value in select value from jsonb_array_elements_text(coalesce(v_rule->'origens_comerciais', '[]'::jsonb)) loop insert into public.com_lista_preco_regra_origens values (v_rule_id, v_value::bigint); end loop;
    for v_value in select value from jsonb_array_elements_text(coalesce(v_rule->'pessoa_papel_ids', '[]'::jsonb)) loop insert into public.com_lista_preco_regra_pessoas values (v_rule_id, v_value::bigint); end loop;
    for v_value in select value from jsonb_array_elements_text(coalesce(v_rule->'areas_comerciais', '[]'::jsonb)) loop insert into public.com_lista_preco_regra_areas values (v_rule_id, v_value::bigint); end loop;
    for v_value in select value from jsonb_array_elements_text(coalesce(v_rule->'ufs', '[]'::jsonb)) loop insert into public.com_lista_preco_regra_ufs values (v_rule_id, upper(btrim(v_value))); end loop;
    for v_value in select value from jsonb_array_elements_text(coalesce(v_rule->'clientes', '[]'::jsonb)) loop insert into public.com_lista_preco_regra_clientes values (v_rule_id, v_value::bigint); end loop;
    for v_value in select value from jsonb_array_elements_text(coalesce(v_rule->'produtos', '[]'::jsonb)) loop insert into public.com_lista_preco_regra_produtos values (v_rule_id, v_value::bigint); end loop;
    for v_value in select value from jsonb_array_elements_text(coalesce(v_rule->'apresentacoes', '[]'::jsonb)) loop insert into public.com_lista_preco_regra_apresentacoes values (v_rule_id, v_value::bigint); end loop;
  end loop;
  insert into public.com_lista_preco_requisicoes(idempotency_key, tipo_operacao, lista_id, versao_id, actor_id, payload_hash)
  values (p_idempotency_key, 'rascunho_substituir', v_lista_id, p_versao_id, v_actor, v_payload_hash);
  perform public.log_audited_rpc_change('pedidos', 'com_lista_preco_versoes', p_versao_id::text, 'pedidos.lista_preco_rascunho_substituido', 'pedidos.price_lists.draft.manage', v_context, v_before, public.com_lista_preco_versao_documento(p_versao_id), jsonb_build_object('source', 'replace_com_lista_preco_rascunho_idempotente', 'unidade_comercial_generica', true));
  return p_versao_id;
end;
$$;

create or replace function public.resolver_com_referencia_comercial_unidade(
  p_data_comercial date, p_pmp_dias numeric, p_origem_comercial_id bigint, p_area_comercial_id bigint,
  p_uf text, p_cliente_id bigint, p_pessoa_papel_ids bigint[], p_produto_embalagem_id bigint
)
returns table(
  lista_id bigint, versao_id bigint, publicacao_id bigint, regra_id bigint, produto_id bigint,
  produto_embalagem_id bigint, data_comercial date, pmp_dias numeric, prazo_faixa_dias integer,
  unidade_precificacao_id bigint, quantidade_unidade_precificacao_por_apresentacao numeric,
  preco_referencia_centavos_por_unidade_precificacao bigint, preco_referencia_centavos_por_litro bigint,
  prioridade integer, especificidade integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_produto_id bigint; v_candidate jsonb; v_candidate_count integer; v_uf_normalizada text;
  v_item record; v_preco record;
begin
  perform public.require_current_user_permission('pedidos.price_reference.resolve');
  if p_data_comercial is null then raise exception 'data comercial e obrigatoria'; end if;
  if p_pmp_dias is null or p_pmp_dias < 0 then raise exception 'PMP deve ser um numero nao negativo'; end if;
  if p_origem_comercial_id is null then raise exception 'origem comercial e obrigatoria'; end if;
  if not exists (select 1 from public.com_origens_comerciais origin where origin.id = p_origem_comercial_id) then raise exception 'origem comercial nao encontrada'; end if;
  if p_cliente_id is null then raise exception 'cliente e obrigatorio'; end if;
  if not exists (select 1 from public.cad_clientes client where client.id = p_cliente_id) then raise exception 'cliente nao encontrado'; end if;
  if p_area_comercial_id is not null and not exists (select 1 from public.cad_areas_comerciais area where area.id = p_area_comercial_id) then raise exception 'area comercial nao encontrada'; end if;
  if p_pessoa_papel_ids is not null and array_position(p_pessoa_papel_ids, null) is not null then raise exception 'participantes comerciais nao podem conter valor nulo'; end if;
  if p_pessoa_papel_ids is not null and exists (select 1 from unnest(p_pessoa_papel_ids) participant(id) left join public.cad_pessoa_papeis role on role.id = participant.id where role.id is null) then raise exception 'participante comercial nao encontrado'; end if;
  if p_produto_embalagem_id is null then raise exception 'apresentacao e obrigatoria'; end if;
  v_uf_normalizada := case when p_uf is null then null else upper(btrim(p_uf)) end;
  if v_uf_normalizada is not null and v_uf_normalizada not in ('AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA','PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO') then raise exception 'UF invalida'; end if;
  select presentation.produto_id into v_produto_id from public.cad_produto_embalagens presentation where presentation.id = p_produto_embalagem_id;
  if v_produto_id is null then raise exception 'apresentacao nao encontrada'; end if;

  with candidatas as (
    select list.id as lista_id, version.id as versao_id, publication.id as publicacao_id, rule.id as regra_id, rule.prioridade,
      (case when exists (select 1 from public.com_lista_preco_regra_origens scope where scope.regra_id = rule.id) then 1 else 0 end +
       case when exists (select 1 from public.com_lista_preco_regra_areas scope where scope.regra_id = rule.id) then 1 else 0 end +
       case when exists (select 1 from public.com_lista_preco_regra_ufs scope where scope.regra_id = rule.id) then 1 else 0 end +
       case when exists (select 1 from public.com_lista_preco_regra_clientes scope where scope.regra_id = rule.id) then 1 else 0 end +
       case when exists (select 1 from public.com_lista_preco_regra_pessoas scope where scope.regra_id = rule.id) then 1 else 0 end +
       case when exists (select 1 from public.com_lista_preco_regra_produtos scope where scope.regra_id = rule.id) then 1 else 0 end +
       case when exists (select 1 from public.com_lista_preco_regra_apresentacoes scope where scope.regra_id = rule.id) then 1 else 0 end)::integer as especificidade
    from public.com_lista_preco_publicacoes publication
    join public.com_lista_preco_versoes version on version.id = publication.versao_id
    join public.com_listas_preco list on list.id = version.lista_id
    join public.com_lista_preco_versao_itens item on item.versao_id = version.id and item.produto_embalagem_id = p_produto_embalagem_id
    join public.com_lista_preco_regras rule on rule.versao_id = version.id
    where version.vigencia_inicio <= p_data_comercial and (version.vigencia_fim is null or version.vigencia_fim >= p_data_comercial)
      and (publication.published_at at time zone 'America/Sao_Paulo')::date <= p_data_comercial
      and not exists (select 1 from public.com_lista_preco_lifecycle_eventos event where event.publicacao_id = publication.id and event.tipo in ('withdrawn', 'superseded') and event.efetivo_em <= p_data_comercial)
      and (not exists (select 1 from public.com_lista_preco_regra_origens scope where scope.regra_id = rule.id) or exists (select 1 from public.com_lista_preco_regra_origens scope where scope.regra_id = rule.id and scope.origem_comercial_id = p_origem_comercial_id))
      and (not exists (select 1 from public.com_lista_preco_regra_areas scope where scope.regra_id = rule.id) or (p_area_comercial_id is not null and exists (select 1 from public.com_lista_preco_regra_areas scope where scope.regra_id = rule.id and scope.area_id = p_area_comercial_id)))
      and (not exists (select 1 from public.com_lista_preco_regra_ufs scope where scope.regra_id = rule.id) or (v_uf_normalizada is not null and exists (select 1 from public.com_lista_preco_regra_ufs scope where scope.regra_id = rule.id and scope.uf = v_uf_normalizada)))
      and (not exists (select 1 from public.com_lista_preco_regra_clientes scope where scope.regra_id = rule.id) or exists (select 1 from public.com_lista_preco_regra_clientes scope where scope.regra_id = rule.id and scope.cliente_id = p_cliente_id))
      and (not exists (select 1 from public.com_lista_preco_regra_pessoas scope where scope.regra_id = rule.id) or (cardinality(coalesce(p_pessoa_papel_ids, '{}'::bigint[])) > 0 and exists (select 1 from public.com_lista_preco_regra_pessoas scope where scope.regra_id = rule.id and scope.pessoa_papel_id = any(p_pessoa_papel_ids))))
      and (not exists (select 1 from public.com_lista_preco_regra_produtos scope where scope.regra_id = rule.id) or exists (select 1 from public.com_lista_preco_regra_produtos scope where scope.regra_id = rule.id and scope.produto_id = v_produto_id))
      and (not exists (select 1 from public.com_lista_preco_regra_apresentacoes scope where scope.regra_id = rule.id) or exists (select 1 from public.com_lista_preco_regra_apresentacoes scope where scope.regra_id = rule.id and scope.produto_embalagem_id = p_produto_embalagem_id))
  ), classificadas as (
    select candidate.*, dense_rank() over (order by candidate.especificidade desc, case when candidate.prioridade is null then 1 else 0 end, candidate.prioridade asc nulls last) as classificacao
    from candidatas candidate
  )
  select count(*), jsonb_agg(jsonb_build_object('lista_id', ranked.lista_id, 'versao_id', ranked.versao_id, 'publicacao_id', ranked.publicacao_id, 'regra_id', ranked.regra_id, 'prioridade', ranked.prioridade, 'especificidade', ranked.especificidade)) -> 0
    into v_candidate_count, v_candidate from classificadas ranked where ranked.classificacao = 1;
  if v_candidate_count = 0 then raise exception 'nenhuma lista comercial aplicavel ao contexto'; end if;
  if v_candidate_count > 1 then raise exception 'ambiguidade entre listas comerciais de mesma precedencia e especificidade'; end if;

  select item.* into v_item
    from public.com_lista_preco_versao_itens item
   where item.versao_id = (v_candidate->>'versao_id')::bigint and item.produto_embalagem_id = p_produto_embalagem_id;
  select price.prazo_dias, price.valor_centavos_por_litro, price.valor_centavos_por_unidade_precificacao into v_preco
    from public.com_lista_preco_versao_precos price
   where price.versao_item_id = v_item.id and price.prazo_dias::numeric >= p_pmp_dias
   order by price.prazo_dias asc limit 1;
  if v_preco.prazo_dias is null then raise exception 'nao ha faixa de preco aplicavel ao PMP informado'; end if;
  if v_item.unidade_precificacao_id is null
     or v_item.quantidade_unidade_precificacao_por_apresentacao is null
     or v_item.quantidade_unidade_precificacao_por_apresentacao <= 0 then
    raise exception 'referencia comercial historica sem unidade e fator genericos congelados';
  end if;
  unidade_precificacao_id := v_item.unidade_precificacao_id;
  quantidade_unidade_precificacao_por_apresentacao := v_item.quantidade_unidade_precificacao_por_apresentacao;
  preco_referencia_centavos_por_unidade_precificacao := v_preco.valor_centavos_por_unidade_precificacao;
  preco_referencia_centavos_por_litro := v_preco.valor_centavos_por_litro;
  if preco_referencia_centavos_por_unidade_precificacao is null then raise exception 'preco comercial generico ausente'; end if;
  lista_id := (v_candidate->>'lista_id')::bigint; versao_id := (v_candidate->>'versao_id')::bigint; publicacao_id := (v_candidate->>'publicacao_id')::bigint; regra_id := (v_candidate->>'regra_id')::bigint;
  produto_id := v_produto_id; produto_embalagem_id := p_produto_embalagem_id; data_comercial := p_data_comercial; pmp_dias := p_pmp_dias;
  prazo_faixa_dias := v_preco.prazo_dias; prioridade := (v_candidate->>'prioridade')::integer; especificidade := (v_candidate->>'especificidade')::integer;
  return next;
end;
$$;

create or replace function public.resolver_com_referencia_comercial(
  p_data_comercial date, p_pmp_dias numeric, p_origem_comercial_id bigint, p_area_comercial_id bigint,
  p_uf text, p_cliente_id bigint, p_pessoa_papel_ids bigint[], p_produto_embalagem_id bigint
)
returns table(
  lista_id bigint, versao_id bigint, publicacao_id bigint, regra_id bigint, produto_id bigint,
  produto_embalagem_id bigint, data_comercial date, pmp_dias numeric, prazo_faixa_dias integer,
  preco_referencia_centavos_por_litro bigint, prioridade integer, especificidade integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_referencia record; v_codigo text;
begin
  select * into v_referencia from public.resolver_com_referencia_comercial_unidade(
    p_data_comercial, p_pmp_dias, p_origem_comercial_id, p_area_comercial_id, p_uf, p_cliente_id, p_pessoa_papel_ids, p_produto_embalagem_id
  );
  select unidade.codigo into v_codigo from public.cad_unidades_medida unidade where unidade.id = v_referencia.unidade_precificacao_id;
  if lower(coalesce(v_codigo, '')) <> 'l' or v_referencia.preco_referencia_centavos_por_litro is null then
    raise exception 'referencia comercial usa unidade generica; utilize o resolvedor de unidade comercial';
  end if;
  lista_id := v_referencia.lista_id; versao_id := v_referencia.versao_id; publicacao_id := v_referencia.publicacao_id; regra_id := v_referencia.regra_id;
  produto_id := v_referencia.produto_id; produto_embalagem_id := v_referencia.produto_embalagem_id; data_comercial := v_referencia.data_comercial;
  pmp_dias := v_referencia.pmp_dias; prazo_faixa_dias := v_referencia.prazo_faixa_dias; preco_referencia_centavos_por_litro := v_referencia.preco_referencia_centavos_por_litro;
  prioridade := v_referencia.prioridade; especificidade := v_referencia.especificidade;
  return next;
end;
$$;

create or replace function public.resolver_com_referencias_comerciais_pedido_idempotente(
  p_idempotency_key uuid, p_pedido_id bigint, p_origem_comercial_id bigint, p_area_comercial_id bigint,
  p_uf text, p_pessoa_papel_ids bigint[], p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_context jsonb; v_actor uuid; v_payload_hash text; v_existing public.com_pedido_referencia_comercial_requisicoes%rowtype;
  v_pedido public.com_pedidos%rowtype; v_plano public.fin_pedido_planos_pagamento%rowtype; v_participantes bigint[] := '{}'::bigint[];
  v_uf_normalizada text; v_item record; v_referencia record; v_snapshot_id bigint;
begin
  v_context := public.begin_audited_rpc('pedidos.commercial_context.manage', 'pedidos', 'com_pedido_item_referencias_comerciais', 'change_type', jsonb_build_object('correlation_id', coalesce(p_idempotency_key::text, 'missing')));
  if p_idempotency_key is null then raise exception 'chave de idempotencia e obrigatoria'; end if;
  if p_pedido_id is null or p_pedido_id <= 0 then raise exception 'pedido e obrigatorio'; end if;
  if length(btrim(coalesce(p_motivo, ''))) < 10 then raise exception 'motivo deve ter ao menos 10 caracteres'; end if;
  if p_pessoa_papel_ids is not null and array_position(p_pessoa_papel_ids, null) is not null then raise exception 'participantes comerciais nao podem conter valor nulo'; end if;
  select coalesce(array_agg(distinct participant.id order by participant.id), '{}'::bigint[]) into v_participantes from unnest(coalesce(p_pessoa_papel_ids, '{}'::bigint[])) participant(id);
  if cardinality(v_participantes) <> cardinality(coalesce(p_pessoa_papel_ids, '{}'::bigint[])) then raise exception 'participante comercial informado mais de uma vez'; end if;
  v_uf_normalizada := case when p_uf is null then null else upper(btrim(p_uf)) end;
  v_actor := public.current_actor_id();
  v_payload_hash := md5(jsonb_build_object('tipo', 'order_commercial_reference', 'pedido_id', p_pedido_id, 'origem_comercial_id', p_origem_comercial_id, 'area_comercial_id', p_area_comercial_id, 'uf', v_uf_normalizada, 'pessoa_papel_ids', v_participantes, 'motivo', btrim(p_motivo))::text);
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  perform pg_advisory_xact_lock(hashtextextended('order_commercial_reference:' || p_pedido_id::text, 0));
  select * into v_existing from public.com_pedido_referencia_comercial_requisicoes request where request.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.actor_id is distinct from v_actor or v_existing.pedido_id <> p_pedido_id or v_existing.payload_hash is distinct from v_payload_hash then raise exception 'chave de idempotencia reutilizada com conteudo diferente'; end if;
    return v_existing.pedido_id;
  end if;
  select * into v_pedido from public.com_pedidos order_header where order_header.id = p_pedido_id for update;
  if not found then raise exception 'pedido nao encontrado'; end if;
  if v_pedido.status <> 'blocked' then raise exception 'referencia comercial exige pedido bloqueado'; end if;
  if exists (select 1 from public.com_pedido_item_referencias_comerciais snapshot where snapshot.pedido_id = p_pedido_id) then raise exception 'pedido ja possui referencia comercial imutavel'; end if;
  if v_pedido.origem_comercial_id is not null and v_pedido.origem_comercial_id <> p_origem_comercial_id then raise exception 'origem comercial do pedido ja foi definida'; end if;
  if exists (select 1 from public.com_pedido_participantes_comerciais participant where participant.pedido_id = p_pedido_id) then raise exception 'participantes comerciais do pedido ja foram definidos'; end if;
  select * into v_plano from public.fin_pedido_planos_pagamento plan where plan.pedido_id = p_pedido_id and plan.origem_dados = 'sistema' and plan.review_status = 'approved' and plan.vigencia_inicio <= current_date and (plan.vigencia_fim is null or plan.vigencia_fim >= current_date) and plan.pmp_dias is not null order by plan.versao desc, plan.id desc limit 1 for share;
  if not found then raise exception 'pedido nao possui condicao financeira governada com PMP'; end if;
  for v_item in select item.id, item.produto_embalagem_id from public.com_pedido_itens item where item.pedido_id = p_pedido_id and item.status = 'active' order by item.id for update loop
    select * into v_referencia from public.resolver_com_referencia_comercial_unidade(v_pedido.data_pedido, v_plano.pmp_dias, p_origem_comercial_id, p_area_comercial_id, v_uf_normalizada, v_pedido.cliente_id, v_participantes, v_item.produto_embalagem_id);
    insert into public.com_pedido_item_referencias_comerciais(
      pedido_id, pedido_item_id, origem_comercial_id, cliente_id, area_comercial_id, uf, pessoa_papel_ids, produto_embalagem_id,
      data_comercial, plano_pagamento_id, pmp_dias, lista_id, lista_versao_id, publicacao_id, regra_id, prazo_faixa_dias,
      preco_referencia_centavos_por_litro, unidade_precificacao_id, quantidade_unidade_precificacao_por_apresentacao,
      preco_referencia_centavos_por_unidade_precificacao, resolved_by, lineage_json
    ) values (
      p_pedido_id, v_item.id, p_origem_comercial_id, v_pedido.cliente_id, p_area_comercial_id, v_uf_normalizada, v_participantes, v_item.produto_embalagem_id,
      v_pedido.data_pedido, v_plano.id, v_plano.pmp_dias, v_referencia.lista_id, v_referencia.versao_id, v_referencia.publicacao_id, v_referencia.regra_id, v_referencia.prazo_faixa_dias,
      v_referencia.preco_referencia_centavos_por_litro, v_referencia.unidade_precificacao_id, v_referencia.quantidade_unidade_precificacao_por_apresentacao,
      v_referencia.preco_referencia_centavos_por_unidade_precificacao, v_actor,
      jsonb_build_object('resolver', '0129', 'especificidade', v_referencia.especificidade, 'prioridade', v_referencia.prioridade, 'plano_pagamento_versao', v_plano.versao,
        'unidade_precificacao_id', v_referencia.unidade_precificacao_id, 'fator_por_apresentacao', v_referencia.quantidade_unidade_precificacao_por_apresentacao)
    ) returning id into v_snapshot_id;
    perform public.log_audited_rpc_change('pedidos', 'com_pedido_item_referencias_comerciais', v_snapshot_id::text, 'pedidos.referencia_comercial_congelada', 'pedidos.commercial_context.manage', v_context, null,
      jsonb_build_object('pedido_id', p_pedido_id, 'pedido_item_id', v_item.id, 'lista_versao_id', v_referencia.versao_id, 'unidade_precificacao_id', v_referencia.unidade_precificacao_id, 'preco_centavos_por_unidade', v_referencia.preco_referencia_centavos_por_unidade_precificacao), jsonb_build_object('motivo', btrim(p_motivo)), 'database_rpc');
  end loop;
  if v_snapshot_id is null then raise exception 'pedido nao possui itens ativos para resolver'; end if;
  update public.com_pedidos set origem_comercial_id = p_origem_comercial_id, updated_by = v_actor where id = p_pedido_id;
  insert into public.com_pedido_participantes_comerciais(pedido_id, pessoa_papel_id, created_by) select p_pedido_id, participant.id, v_actor from unnest(v_participantes) participant(id);
  insert into public.com_pedido_referencia_comercial_requisicoes(idempotency_key, pedido_id, actor_id, payload_hash) values (p_idempotency_key, p_pedido_id, v_actor, v_payload_hash);
  return p_pedido_id;
end;
$$;

create or replace function public.apply_com_lista_preco_import_idempotente(
  p_idempotency_key uuid, p_importacao_id bigint, p_versao_id bigint, p_vigencia_inicio date,
  p_vigencia_fim date, p_descricao text, p_regras jsonb, p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_context jsonb; v_actor uuid; v_payload_hash text; v_existing public.com_lista_preco_import_requisicoes%rowtype;
  v_import public.com_lista_preco_importacoes%rowtype; v_items jsonb; v_result bigint; v_unidade_l_id bigint;
begin
  v_context := public.begin_audited_rpc('pedidos.price_lists.import.apply', 'pedidos', 'com_lista_preco_import_aplicacoes', 'change_type', jsonb_build_object('correlation_id', coalesce(p_idempotency_key::text, 'missing')));
  if p_idempotency_key is null or p_importacao_id is null or p_versao_id is null then raise exception 'chave, importacao e versao sao obrigatorias'; end if;
  if jsonb_typeof(p_regras) <> 'array' then raise exception 'regras devem ser informadas explicitamente como lista'; end if;
  if length(btrim(coalesce(p_motivo, ''))) < 10 then raise exception 'motivo deve ter ao menos 10 caracteres'; end if;
  v_actor := public.current_actor_id();
  v_payload_hash := md5(jsonb_build_object('tipo', 'price_list_import_apply', 'importacao_id', p_importacao_id, 'versao_id', p_versao_id, 'vigencia_inicio', p_vigencia_inicio, 'vigencia_fim', p_vigencia_fim, 'descricao', nullif(btrim(p_descricao), ''), 'regras', p_regras, 'motivo', btrim(p_motivo))::text);
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing from public.com_lista_preco_import_requisicoes where idempotency_key = p_idempotency_key;
  if found then
    if v_existing.tipo_operacao <> 'apply' or v_existing.actor_id is distinct from v_actor or v_existing.payload_hash is distinct from v_payload_hash then raise exception 'chave de idempotencia reutilizada com conteudo diferente'; end if;
    return v_existing.versao_id;
  end if;
  select * into v_import from public.com_lista_preco_importacoes where id = p_importacao_id for update;
  if not found then raise exception 'importacao de lista nao encontrada'; end if;
  if v_import.status <> 'ready' or v_import.linhas_com_erro <> 0 then raise exception 'importacao possui linhas nao conciliadas; nao pode aplicar'; end if;
  if exists (select 1 from public.com_lista_preco_import_aplicacoes where importacao_id = p_importacao_id) or exists (select 1 from public.com_lista_preco_import_aplicacoes where versao_id = p_versao_id) then raise exception 'importacao ou versao ja foi aplicada'; end if;
  select unidade.id into v_unidade_l_id from public.cad_unidades_medida unidade where lower(unidade.codigo) = 'l' and unidade.status = 'active';
  if v_unidade_l_id is null then raise exception 'unidade comercial L ativa nao encontrada'; end if;
  if exists (select 1 from public.com_lista_preco_import_linhas line join public.cad_produto_embalagens presentation on presentation.id = line.produto_embalagem_id join public.cad_embalagens embalagem on embalagem.id = presentation.embalagem_id where line.importacao_id = p_importacao_id and line.status_reconciliacao = 'valid' and (embalagem.volume_litros is null or embalagem.volume_litros <= 0)) then raise exception 'importacao R$/L exige capacidade positiva da apresentacao'; end if;
  select jsonb_agg(jsonb_build_object('produto_embalagem_id', grouped.produto_embalagem_id, 'unidade_precificacao_id', v_unidade_l_id, 'quantidade_unidade_precificacao_por_apresentacao', grouped.fator, 'precos', grouped.precos) order by grouped.produto_embalagem_id) into v_items
  from (
    select line.produto_embalagem_id, max(embalagem.volume_litros) as fator,
      jsonb_agg(jsonb_build_object('prazo_dias', line.prazo_dias, 'valor_centavos_por_unidade_precificacao', line.valor_centavos_por_litro) order by line.prazo_dias) as precos
    from public.com_lista_preco_import_linhas line
    join public.cad_produto_embalagens presentation on presentation.id = line.produto_embalagem_id
    join public.cad_embalagens embalagem on embalagem.id = presentation.embalagem_id
    where line.importacao_id = p_importacao_id and line.status_reconciliacao = 'valid'
    group by line.produto_embalagem_id
  ) grouped;
  if v_items is null then raise exception 'importacao nao possui linhas validas para aplicar'; end if;
  v_result := public.replace_com_lista_preco_rascunho_idempotente(p_idempotency_key, p_versao_id, p_vigencia_inicio, p_vigencia_fim, p_descricao, v_items, p_regras, p_motivo);
  insert into public.com_lista_preco_import_aplicacoes(importacao_id, versao_id, applied_by, motivo) values (p_importacao_id, v_result, v_actor, btrim(p_motivo));
  update public.com_lista_preco_importacoes set status = 'applied', applied_at = clock_timestamp() where id = p_importacao_id;
  insert into public.com_lista_preco_import_requisicoes(idempotency_key, tipo_operacao, importacao_id, versao_id, actor_id, payload_hash) values (p_idempotency_key, 'apply', p_importacao_id, v_result, v_actor, v_payload_hash);
  perform public.log_audited_rpc_change('pedidos', 'com_lista_preco_import_aplicacoes', p_importacao_id::text, 'pedidos.lista_preco_importacao_aplicada', 'pedidos.price_lists.import.apply', v_context, null, jsonb_build_object('versao_id', v_result, 'unidade_comercial', 'L'), jsonb_build_object('source', 'apply_com_lista_preco_import_idempotente'), 'database_rpc');
  return v_result;
end;
$$;

alter table public.com_lista_preco_versao_precos enable row level security;
revoke all on table public.com_lista_preco_versao_precos from public, anon, authenticated;
revoke all on function public.resolver_com_referencia_comercial_unidade(date, numeric, bigint, bigint, text, bigint, bigint[], bigint) from public, anon;
grant execute on function public.resolver_com_referencia_comercial_unidade(date, numeric, bigint, bigint, text, bigint, bigint[], bigint) to authenticated;

comment on column public.com_lista_preco_versao_itens.unidade_precificacao_id is
  'Unidade comercial congelada no item versionado da lista; a mesma apresentacao pode usar unidades distintas em versoes ou listas distintas.';
comment on column public.com_lista_preco_versao_itens.quantidade_unidade_precificacao_por_apresentacao is
  'Fator comercial explicito: quantidade da unidade de precificacao correspondente a uma apresentacao fisica.';
comment on column public.com_lista_preco_versao_precos.valor_centavos_por_unidade_precificacao is
  'Preco operacional generico em centavos BRL por unidade comercial congelada no item versionado.';
comment on function public.resolver_com_referencia_comercial_unidade(date, numeric, bigint, bigint, text, bigint, bigint[], bigint) is
  'ORD-01 1E: resolvedor generico fail-closed que devolve preco, unidade comercial e fator congelados pela lista vencedora.';
