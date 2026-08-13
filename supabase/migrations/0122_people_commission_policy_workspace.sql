-- COMM-02B1: pessoas, relacionamentos comerciais opcionais e politicas de comissao.

create or replace function public.create_cad_pessoa_comercial(
  p_nome text,
  p_nome_norm text,
  p_papeis_json jsonb,
  p_codigo_legado text default null,
  p_tipo_comercial text default null,
  p_status text default 'active',
  p_vendedor_responsavel_id bigint default null,
  p_apelidos_json jsonb default '[]'::jsonb,
  p_grafias_incorretas_json jsonb default '[]'::jsonb,
  p_payload_origem_json jsonb default '{}'::jsonb,
  p_confirmar_possivel_duplicidade boolean default false,
  p_motivo_duplicidade text default null,
  p_candidatos_apresentados bigint[] default array[]::bigint[]
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_id bigint;
  v_after jsonb;
  v_permission_context jsonb;
  v_candidates jsonb;
  v_candidate_ids bigint[];
  v_alias text;
begin
  v_permission_context := public.begin_audited_rpc(
    'cadastros.pessoas.create', 'cadastros', 'cad_pessoas_comerciais',
    'change_type', jsonb_build_object('correlation_id', gen_random_uuid()::text, 'duplicate_review', true)
  );
  perform public.require_current_user_permission('cadastros.pessoas.candidates.read');
  perform pg_advisory_xact_lock(hashtextextended('cad_pessoas_comerciais:create', 0));

  if nullif(btrim(p_nome), '') is null or nullif(btrim(p_nome_norm), '') is null then raise exception 'nome is required'; end if;
  perform public.validate_cad_pessoa_papeis_json(p_papeis_json);
  if p_status not in ('active', 'inactive', 'pending_review') then raise exception 'invalid status'; end if;
  -- COMM-02B1: relacionamento comercial e opcional e pertence ao cadastro temporal de vinculos.
  if exists (
    select 1
      from (
        select public.normalize_catalog_term(p_nome) normalized_value
        union all
        select public.normalize_catalog_term(value)
          from jsonb_array_elements_text(coalesce(p_apelidos_json, '[]'::jsonb)) item(value)
        union all
        select public.normalize_catalog_term(value)
          from jsonb_array_elements_text(coalesce(p_grafias_incorretas_json, '[]'::jsonb)) item(value)
      ) input_identity
     where normalized_value is not null
     group by normalized_value
    having count(*) > 1
  ) then raise exception 'alias repeated within the same person'; end if;
  if p_vendedor_responsavel_id is not null and not exists (
    select 1 from public.cad_pessoas_comerciais person where person.id = p_vendedor_responsavel_id and person.status = 'active'
  ) then raise exception 'active responsible seller not found'; end if;

  select coalesce(jsonb_agg(to_jsonb(candidate) order by candidate.pessoa_id), '[]'::jsonb),
         coalesce(array_agg(candidate.pessoa_id order by candidate.pessoa_id), array[]::bigint[])
    into v_candidates, v_candidate_ids
    from public.find_cad_pessoa_possible_duplicates(
      p_nome, p_codigo_legado, p_apelidos_json, p_grafias_incorretas_json,
      p_vendedor_responsavel_id, p_papeis_json
    ) candidate;

  if exists (
    select 1 from jsonb_array_elements(v_candidates) item
     where item->'motivos' ? 'same_legacy_code'
  ) then raise exception 'normalized legacy code already exists'; end if;

  if cardinality(v_candidate_ids) > 0 then
    if not p_confirmar_possivel_duplicidade then raise exception 'possible commercial person duplicate requires confirmation'; end if;
    if length(btrim(coalesce(p_motivo_duplicidade, ''))) < 10 then raise exception 'duplicate confirmation reason must have at least 10 characters'; end if;
    if v_candidate_ids <> coalesce((select array_agg(id order by id) from unnest(p_candidatos_apresentados) id), array[]::bigint[]) then
      raise exception 'duplicate candidates changed; review again';
    end if;
  end if;

  v_actor := public.current_actor_id();
  insert into public.cad_pessoas_comerciais(
    codigo_legado, nome, nome_norm, tipo_comercial, papeis_json, status,
    vendedor_responsavel_id, apelidos_json, grafias_incorretas_json,
    payload_origem_json, created_by, updated_by
  ) values (
    nullif(btrim(p_codigo_legado), ''), btrim(p_nome), btrim(p_nome_norm), p_tipo_comercial,
    p_papeis_json, p_status, p_vendedor_responsavel_id,
    coalesce(p_apelidos_json, '[]'::jsonb), coalesce(p_grafias_incorretas_json, '[]'::jsonb),
    coalesce(p_payload_origem_json, '{}'::jsonb), v_actor, v_actor
  ) returning id into v_id;

  insert into public.cad_pessoa_aliases(pessoa_id, alias, alias_norm, tipo)
  values (v_id, btrim(p_nome), public.normalize_catalog_term(p_nome), 'nome');
  for v_alias in select jsonb_array_elements_text(coalesce(p_apelidos_json, '[]'::jsonb)) loop
    if public.normalize_catalog_term(v_alias) is not null then
      insert into public.cad_pessoa_aliases(pessoa_id, alias, alias_norm, tipo)
      values (v_id, btrim(v_alias), public.normalize_catalog_term(v_alias), 'apelido')
      on conflict (pessoa_id, alias_norm) do nothing;
    end if;
  end loop;
  for v_alias in select jsonb_array_elements_text(coalesce(p_grafias_incorretas_json, '[]'::jsonb)) loop
    if public.normalize_catalog_term(v_alias) is not null then
      insert into public.cad_pessoa_aliases(pessoa_id, alias, alias_norm, tipo)
      values (v_id, btrim(v_alias), public.normalize_catalog_term(v_alias), 'grafia_incorreta')
      on conflict (pessoa_id, alias_norm) do nothing;
    end if;
  end loop;

  select to_jsonb(person) into v_after from public.cad_pessoas_comerciais person where person.id = v_id;
  perform public.log_audited_rpc_change(
    'cadastros', 'cad_pessoas_comerciais', v_id::text, 'cadastros.pessoa_comercial_created',
    'cadastros.pessoas.create', v_permission_context, null, v_after,
    jsonb_build_object(
      'possible_duplicate_confirmed', cardinality(v_candidate_ids) > 0,
      'candidates', v_candidates,
      'duplicate_reason', nullif(btrim(p_motivo_duplicidade), ''),
      'source', 'create_cad_pessoa_comercial'
    ), 'database_rpc'
  );
  return v_id;
end;
$$;

create or replace function public.update_cad_pessoa_comercial_role(
  p_pessoa_id bigint,
  p_tipo_comercial text,
  p_papeis_json jsonb,
  p_vendedor_responsavel_id bigint default null,
  p_motivo_codigo text default null,
  p_motivo_detalhe text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_before jsonb;
  v_after jsonb;
  v_motivo_codigo text;
  v_papeis_adicionados jsonb;
  v_papeis_removidos jsonb;
begin
  perform public.require_current_user_permission('cadastros.pessoas.update.role');

  -- Papeis comerciais sao alcada de negocio. Isto nao altera user_profiles.role,
  -- que controla perfil de login/autenticacao do sistema.
  if p_pessoa_id is null or p_pessoa_id <= 0 then
    raise exception 'pessoa_id is required';
  end if;
  if p_tipo_comercial is not null and p_tipo_comercial not in (
    'funcionario_elite',
    'agente_vinculado',
    'agente_direto_elite',
    'vendedor_direto_elite',
    'tecnico_campo',
    'entregador',
    'gerente',
    'vendedor_gerente'
  ) then
    raise exception 'invalid tipo_comercial';
  end if;
  perform public.validate_cad_pessoa_papeis_json(p_papeis_json);
  -- COMM-02B1: agente, vendedor e gerente podem existir sem relacionamento hierarquico.
  if p_vendedor_responsavel_id = p_pessoa_id then
    raise exception 'vendedor_responsavel_id cannot reference same pessoa';
  end if;

  v_motivo_codigo := public.validate_cad_pessoa_role_reason(p_motivo_codigo, p_motivo_detalhe);

  select to_jsonb(p)
    into v_before
    from public.cad_pessoas_comerciais p
   where p.id = p_pessoa_id
   for update;

  if not found then
    raise exception 'pessoa comercial not found';
  end if;

  select coalesce(jsonb_agg(added.value order by added.value), '[]'::jsonb)
    into v_papeis_adicionados
    from (
      select value from jsonb_array_elements_text(p_papeis_json)
      except
      select value from jsonb_array_elements_text(coalesce(v_before->'papeis_json', '[]'::jsonb))
    ) as added(value);

  select coalesce(jsonb_agg(removed.value order by removed.value), '[]'::jsonb)
    into v_papeis_removidos
    from (
      select value from jsonb_array_elements_text(coalesce(v_before->'papeis_json', '[]'::jsonb))
      except
      select value from jsonb_array_elements_text(p_papeis_json)
    ) as removed(value);

  v_actor := public.current_actor_id();

  update public.cad_pessoas_comerciais
     set tipo_comercial = p_tipo_comercial,
         papeis_json = p_papeis_json,
         vendedor_responsavel_id = p_vendedor_responsavel_id,
         updated_by = v_actor
   where id = p_pessoa_id;

  select to_jsonb(p)
    into v_after
    from public.cad_pessoas_comerciais p
   where p.id = p_pessoa_id;

  perform public.log_audit_event(
    'cadastros',
    'cad_pessoas_comerciais',
    p_pessoa_id::text,
    'cadastros.pessoa_comercial_role_updated',
    'cadastros.pessoas.update.role',
    'success',
    v_before,
    v_after,
    jsonb_build_object('alcada_usada', 'cadastros.pessoas.update.role', 'axis', 'role'),
    'database_rpc',
    jsonb_build_object(
      'source', 'update_cad_pessoa_comercial_role',
      'motivo_codigo', v_motivo_codigo,
      'motivo_detalhe', nullif(trim(p_motivo_detalhe), ''),
      'papeis_adicionados', v_papeis_adicionados,
      'papeis_removidos', v_papeis_removidos,
      'tipo_comercial_before', v_before->>'tipo_comercial',
      'tipo_comercial_after', v_after->>'tipo_comercial',
      'vendedor_responsavel_before', v_before->>'vendedor_responsavel_id',
      'vendedor_responsavel_after', v_after->>'vendedor_responsavel_id'
    )
  );

  return p_pessoa_id;
end;
$$;

create or replace function public.registrar_cad_pessoa_relacionamento_comercial(
  p_pessoa_origem_id bigint,
  p_pessoa_destino_id bigint,
  p_tipo_relacionamento text,
  p_vigencia_inicio date,
  p_vigencia_fim date default null,
  p_motivo text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_id bigint;
  v_context jsonb;
  v_after jsonb;
begin
  v_context := public.begin_audited_rpc(
    'cadastros.pessoas.relationships.manage',
    'cadastros',
    'cad_pessoa_relacionamentos_comerciais',
    'change_type',
    jsonb_build_object('event', 'commercial_relationship_create')
  );

  if p_pessoa_origem_id is null or p_pessoa_destino_id is null then
    raise exception 'relationship people are required';
  end if;
  if p_pessoa_origem_id = p_pessoa_destino_id then
    raise exception 'commercial relationship cannot reference the same person';
  end if;
  if p_tipo_relacionamento not in ('agente_vendedor', 'vendedor_gerente') then
    raise exception 'invalid commercial relationship type';
  end if;
  if p_vigencia_inicio is null then
    raise exception 'relationship start date is required';
  end if;
  if p_vigencia_fim is not null and p_vigencia_fim < p_vigencia_inicio then
    raise exception 'relationship end date is before start date';
  end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 10 then
    raise exception 'relationship reason must have at least 10 characters';
  end if;

  perform 1 from public.cad_pessoas_comerciais
   where id = p_pessoa_origem_id and status = 'active';
  if not found then raise exception 'active origin commercial person not found'; end if;

  perform 1 from public.cad_pessoas_comerciais
   where id = p_pessoa_destino_id and status = 'active';
  if not found then raise exception 'active destination commercial person not found'; end if;

  if p_tipo_relacionamento = 'agente_vendedor' then
    perform 1
      from public.cad_pessoas_comerciais_papeis_ativos role_row
     where role_row.pessoa_id = p_pessoa_origem_id
       and role_row.papel = 'agente';
    if not found then raise exception 'origin person must have active agent role'; end if;

    perform 1
      from public.cad_pessoas_comerciais_papeis_ativos role_row
     where role_row.pessoa_id = p_pessoa_destino_id
       and role_row.papel = 'vendedor';
    if not found then raise exception 'destination person must have active seller role'; end if;
  else
    perform 1
      from public.cad_pessoas_comerciais_papeis_ativos role_row
     where role_row.pessoa_id = p_pessoa_origem_id
       and role_row.papel = 'vendedor';
    if not found then raise exception 'origin person must have active seller role'; end if;

    perform 1
      from public.cad_pessoas_comerciais_papeis_ativos role_row
     where role_row.pessoa_id = p_pessoa_destino_id
       and role_row.papel = 'gerente';
    if not found then raise exception 'destination person must have active manager role'; end if;
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'commercial_relationship:' || p_pessoa_origem_id::text || ':' || p_tipo_relacionamento,
      0
    )
  );

  if exists (
    select 1
      from public.cad_pessoa_relacionamentos_comerciais relation
     where relation.pessoa_origem_id = p_pessoa_origem_id
       and relation.tipo_relacionamento = p_tipo_relacionamento
       and relation.status <> 'cancelled'
       and daterange(
             relation.vigencia_inicio,
             coalesce(relation.vigencia_fim, 'infinity'::date),
             '[]'
           )
           &&
           daterange(
             p_vigencia_inicio,
             coalesce(p_vigencia_fim, 'infinity'::date),
             '[]'
           )
  ) then
    raise exception 'commercial relationship effective period overlaps an active relationship';
  end if;

  v_actor := public.current_actor_id();

  insert into public.cad_pessoa_relacionamentos_comerciais(
    pessoa_origem_id,
    pessoa_destino_id,
    tipo_relacionamento,
    vigencia_inicio,
    vigencia_fim,
    status,
    motivo_inicio,
    created_by
  )
  values (
    p_pessoa_origem_id,
    p_pessoa_destino_id,
    p_tipo_relacionamento,
    p_vigencia_inicio,
    p_vigencia_fim,
    'active',
    btrim(p_motivo),
    v_actor
  )
  returning id into v_id;

  select to_jsonb(relation)
    into v_after
    from public.cad_pessoa_relacionamentos_comerciais relation
   where relation.id = v_id;

  perform public.log_audited_rpc_change(
    'cadastros',
    'cad_pessoa_relacionamentos_comerciais',
    v_id::text,
    'cadastros.pessoa_relacionamento_comercial_created',
    'cadastros.pessoas.relationships.manage',
    v_context,
    null,
    v_after,
    jsonb_build_object(
      'source', 'registrar_cad_pessoa_relacionamento_comercial',
      'motivo', btrim(p_motivo)
    )
  );

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Compatibilidade do campo legado e migracao para relacionamentos temporais.
-- ---------------------------------------------------------------------------

comment on column public.cad_pessoas_comerciais.vendedor_responsavel_id is
  'Campo legado de compatibilidade. Novas operacoes usam cad_pessoa_relacionamentos_comerciais; nao e fonte canonica da hierarquia.';

with inferred as (
  select
    person.id as pessoa_origem_id,
    person.vendedor_responsavel_id as pessoa_destino_id,
    case
      when exists (
        select 1
          from public.cad_pessoas_comerciais_papeis_ativos role_row
         where role_row.pessoa_id = person.id
           and role_row.papel = 'agente'
      ) and exists (
        select 1
          from public.cad_pessoas_comerciais_papeis_ativos role_row
         where role_row.pessoa_id = person.vendedor_responsavel_id
           and role_row.papel = 'vendedor'
      ) then 'agente_vendedor'
      when exists (
        select 1
          from public.cad_pessoas_comerciais_papeis_ativos role_row
         where role_row.pessoa_id = person.id
           and role_row.papel = 'vendedor'
      ) and exists (
        select 1
          from public.cad_pessoas_comerciais_papeis_ativos role_row
         where role_row.pessoa_id = person.vendedor_responsavel_id
           and role_row.papel = 'gerente'
      ) then 'vendedor_gerente'
      else null
    end as tipo_relacionamento,
    coalesce(person.created_at::date, current_date) as vigencia_inicio,
    person.updated_by
  from public.cad_pessoas_comerciais person
  where person.vendedor_responsavel_id is not null
)
insert into public.cad_pessoa_relacionamentos_comerciais(
  pessoa_origem_id,
  pessoa_destino_id,
  tipo_relacionamento,
  vigencia_inicio,
  status,
  motivo_inicio,
  created_by
)
select
  inferred.pessoa_origem_id,
  inferred.pessoa_destino_id,
  inferred.tipo_relacionamento,
  inferred.vigencia_inicio,
  'active',
  'Migracao governada do vinculo comercial legado.',
  inferred.updated_by
from inferred
where inferred.tipo_relacionamento is not null
  and not exists (
    select 1
      from public.cad_pessoa_relacionamentos_comerciais relation
     where relation.pessoa_origem_id = inferred.pessoa_origem_id
       and relation.tipo_relacionamento = inferred.tipo_relacionamento
       and relation.status <> 'cancelled'
  );

-- ---------------------------------------------------------------------------
-- Escopo gerencial passa a reconhecer a hierarquia temporal canonica.
-- Areas comerciais continuam sendo uma fonte valida de escopo.
-- O campo legado e apenas fallback de transicao para registros nao inferiveis.
-- ---------------------------------------------------------------------------

create or replace function public.current_user_manages_seller(p_seller_id bigint)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  with actor as (
    select public.current_commercial_person_id() as person_id
  ),
  seller_manager as (
    select relation.pessoa_destino_id as manager_id
      from public.cad_pessoa_relacionamentos_comerciais relation
     where relation.pessoa_origem_id = p_seller_id
       and relation.tipo_relacionamento = 'vendedor_gerente'
       and relation.status = 'active'
       and relation.vigencia_inicio <= current_date
       and (relation.vigencia_fim is null or relation.vigencia_fim >= current_date)
  ),
  agent_seller as (
    select relation.pessoa_destino_id as seller_id
      from public.cad_pessoa_relacionamentos_comerciais relation
     where relation.pessoa_origem_id = p_seller_id
       and relation.tipo_relacionamento = 'agente_vendedor'
       and relation.status = 'active'
       and relation.vigencia_inicio <= current_date
       and (relation.vigencia_fim is null or relation.vigencia_fim >= current_date)
  )
  select public.current_user_is_admin()
    or exists (
      select 1 from seller_manager, actor
       where seller_manager.manager_id = actor.person_id
    )
    or exists (
      select 1
        from agent_seller
        join public.cad_pessoa_relacionamentos_comerciais relation
          on relation.pessoa_origem_id = agent_seller.seller_id
         and relation.tipo_relacionamento = 'vendedor_gerente'
         and relation.status = 'active'
         and relation.vigencia_inicio <= current_date
         and (relation.vigencia_fim is null or relation.vigencia_fim >= current_date)
        cross join actor
       where relation.pessoa_destino_id = actor.person_id
    )
    or exists (
      select 1
        from public.cad_pessoa_areas_comerciais seller_area
        join public.cad_areas_comerciais area
          on area.id = seller_area.area_id
         and area.status = 'active'
        cross join actor
       where seller_area.pessoa_id = p_seller_id
         and seller_area.status = 'active'
         and (seller_area.vigencia_inicio is null or seller_area.vigencia_inicio <= current_date)
         and (seller_area.vigencia_fim is null or seller_area.vigencia_fim >= current_date)
         and (
           area.gerente_id = actor.person_id
           or exists (
             select 1
               from public.cad_pessoa_areas_comerciais manager_area
              where manager_area.area_id = area.id
                and manager_area.pessoa_id = actor.person_id
                and manager_area.papel_area in ('gerente', 'supervisor')
                and manager_area.status = 'active'
                and (manager_area.vigencia_inicio is null or manager_area.vigencia_inicio <= current_date)
                and (manager_area.vigencia_fim is null or manager_area.vigencia_fim >= current_date)
           )
         )
    )
    or exists (
      select 1
        from public.cad_pessoas_comerciais legacy, actor
       where legacy.id = p_seller_id
         and legacy.vendedor_responsavel_id = actor.person_id
         and not exists (
           select 1
             from public.cad_pessoa_relacionamentos_comerciais relation
            where relation.pessoa_origem_id = p_seller_id
              and relation.status <> 'cancelled'
         )
    )
$$;

revoke all on function public.current_user_manages_seller(bigint) from public, anon;
grant execute on function public.current_user_manages_seller(bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- Resolve somente a cadeia ascendente da pessoa que efetivamente gerou a venda.
-- Nao busca agentes vinculados "para baixo" a partir de um vendedor.
-- ---------------------------------------------------------------------------

create or replace function public.resolver_cad_pessoa_cadeia_comercial(
  p_pessoa_origem_id bigint,
  p_data_referencia date
)
returns table (
  ordem_cadeia integer,
  pessoa_id bigint,
  papel_comissao text,
  relacionamento_id bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_origin_role text;
  v_seller_id bigint;
  v_relation_id bigint;
  v_manager_id bigint;
begin
  if p_pessoa_origem_id is null or p_data_referencia is null then
    raise exception 'origin person and reference date are required';
  end if;

  if exists (
    select 1
      from public.cad_pessoas_comerciais_papeis_ativos role_row
     where role_row.pessoa_id = p_pessoa_origem_id
       and role_row.papel = 'vendedor'
  ) then
    v_origin_role := 'vendedor';
  elsif exists (
    select 1
      from public.cad_pessoas_comerciais_papeis_ativos role_row
     where role_row.pessoa_id = p_pessoa_origem_id
       and role_row.papel = 'agente'
  ) then
    v_origin_role := 'agente';
  else
    return;
  end if;

  ordem_cadeia := 0;
  pessoa_id := p_pessoa_origem_id;
  papel_comissao := v_origin_role;
  relacionamento_id := null;
  return next;

  if v_origin_role = 'agente' then
    select relation.id, relation.pessoa_destino_id
      into v_relation_id, v_seller_id
      from public.cad_pessoa_relacionamentos_comerciais relation
     where relation.pessoa_origem_id = p_pessoa_origem_id
       and relation.tipo_relacionamento = 'agente_vendedor'
       and relation.status <> 'cancelled'
       and relation.vigencia_inicio <= p_data_referencia
       and (relation.vigencia_fim is null or relation.vigencia_fim >= p_data_referencia)
     order by relation.vigencia_inicio desc, relation.id desc
     limit 1;

    if v_seller_id is null then
      return;
    end if;

    ordem_cadeia := 1;
    pessoa_id := v_seller_id;
    papel_comissao := 'vendedor';
    relacionamento_id := v_relation_id;
    return next;
  else
    v_seller_id := p_pessoa_origem_id;
  end if;

  select relation.id, relation.pessoa_destino_id
    into v_relation_id, v_manager_id
    from public.cad_pessoa_relacionamentos_comerciais relation
   where relation.pessoa_origem_id = v_seller_id
     and relation.tipo_relacionamento = 'vendedor_gerente'
     and relation.status <> 'cancelled'
     and relation.vigencia_inicio <= p_data_referencia
     and (relation.vigencia_fim is null or relation.vigencia_fim >= p_data_referencia)
   order by relation.vigencia_inicio desc, relation.id desc
   limit 1;

  if v_manager_id is not null then
    ordem_cadeia := case when v_origin_role = 'agente' then 2 else 1 end;
    pessoa_id := v_manager_id;
    papel_comissao := 'gerente';
    relacionamento_id := v_relation_id;
    return next;
  end if;
end;
$$;

revoke all on function public.resolver_cad_pessoa_cadeia_comercial(bigint, date)
  from public, anon;
grant execute on function public.resolver_cad_pessoa_cadeia_comercial(bigint, date)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Publicacao versionada. A versao anterior permanece publicada e historica,
-- mas sua vigencia e encerrada no dia anterior ao inicio da nova versao.
-- ---------------------------------------------------------------------------

create or replace function public.publicar_com_comissao_politica_v2(
  p_politica_id bigint,
  p_confirmacao boolean,
  p_motivo_confirmacao text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_policy public.com_comissao_politicas_pessoa%rowtype;
  v_previous public.com_comissao_politicas_pessoa%rowtype;
  v_context jsonb;
  v_before jsonb;
  v_after jsonb;
begin
  v_context := public.begin_audited_rpc(
    'financeiro.commissions.policy.manage',
    'financeiro',
    'com_comissao_politicas_pessoa',
    'status_transition',
    jsonb_build_object('event', 'commission_policy_replace')
  );

  if p_confirmacao is distinct from true then
    raise exception 'explicit policy confirmation is required';
  end if;
  if char_length(btrim(coalesce(p_motivo_confirmacao, ''))) < 10 then
    raise exception 'policy confirmation reason must have at least 10 characters';
  end if;

  select * into v_policy
    from public.com_comissao_politicas_pessoa
   where id = p_politica_id
   for update;

  if not found then raise exception 'commission policy not found'; end if;
  if v_policy.status <> 'draft' then raise exception 'commission policy is not draft'; end if;
  if v_policy.vigencia_inicio < current_date then
    raise exception 'new commission policy cannot start in the past';
  end if;

  select * into v_previous
    from public.com_comissao_politicas_pessoa previous
   where previous.pessoa_id = v_policy.pessoa_id
     and previous.id <> v_policy.id
     and previous.status = 'published'
     and previous.vigencia_inicio <= v_policy.vigencia_inicio
     and (previous.vigencia_fim is null or previous.vigencia_fim >= v_policy.vigencia_inicio)
   order by previous.vigencia_inicio desc, previous.id desc
   limit 1
   for update;

  if v_previous.id is not null then
    if v_policy.vigencia_inicio <= v_previous.vigencia_inicio then
      raise exception 'replacement policy must start after the previous policy';
    end if;

    v_before := to_jsonb(v_previous);

    update public.com_comissao_politicas_pessoa
       set vigencia_fim = v_policy.vigencia_inicio - 1
     where id = v_previous.id;

    select to_jsonb(previous)
      into v_after
      from public.com_comissao_politicas_pessoa previous
     where previous.id = v_previous.id;

    perform public.log_audited_rpc_change(
      'financeiro',
      'com_comissao_politicas_pessoa',
      v_previous.id::text,
      'financeiro.comissao_politica_vigencia_encerrada',
      'financeiro.commissions.policy.manage',
      v_context,
      v_before,
      v_after,
      jsonb_build_object(
        'source', 'publicar_com_comissao_politica_v2',
        'replacement_policy_id', v_policy.id,
        'motivo', btrim(p_motivo_confirmacao)
      )
    );
  end if;

  return public.publicar_com_comissao_politica(
    p_politica_id,
    true,
    p_motivo_confirmacao
  );
end;
$$;

revoke all on function public.publicar_com_comissao_politica_v2(
  bigint, boolean, text
) from public, anon;
grant execute on function public.publicar_com_comissao_politica_v2(
  bigint, boolean, text
) to authenticated;

revoke execute on function public.publicar_com_comissao_politica(
  bigint, boolean, text
) from authenticated;

create or replace function public.remover_com_comissao_politica_taxa(
  p_taxa_id bigint,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rate public.com_comissao_politica_taxas_grupo%rowtype;
  v_context jsonb;
begin
  v_context := public.begin_audited_rpc(
    'financeiro.commissions.policy.manage',
    'financeiro',
    'com_comissao_politica_taxas_grupo',
    'change_type',
    jsonb_build_object('event', 'commission_policy_rate_remove')
  );

  if char_length(btrim(coalesce(p_motivo, ''))) < 10 then
    raise exception 'rate removal reason must have at least 10 characters';
  end if;

  select rate.*
    into v_rate
    from public.com_comissao_politica_taxas_grupo rate
    join public.com_comissao_politicas_pessoa policy
      on policy.id = rate.politica_id
   where rate.id = p_taxa_id
     and policy.status = 'draft'
   for update of rate;

  if not found then raise exception 'draft commission rate not found'; end if;

  delete from public.com_comissao_politica_taxas_grupo
   where id = p_taxa_id;

  perform public.log_audited_rpc_change(
    'financeiro',
    'com_comissao_politica_taxas_grupo',
    p_taxa_id::text,
    'financeiro.comissao_politica_taxa_removed',
    'financeiro.commissions.policy.manage',
    v_context,
    to_jsonb(v_rate),
    null,
    jsonb_build_object(
      'source', 'remover_com_comissao_politica_taxa',
      'motivo', btrim(p_motivo)
    )
  );

  return p_taxa_id;
end;
$$;

revoke all on function public.remover_com_comissao_politica_taxa(bigint, text)
  from public, anon;
grant execute on function public.remover_com_comissao_politica_taxa(bigint, text)
  to authenticated;
