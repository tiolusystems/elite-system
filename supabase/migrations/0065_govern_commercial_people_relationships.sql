-- UX-01C: governed commercial people, duplicate review, temporal areas and reactivation.

insert into public.permission_actions(
  action_key, module, description, default_allowed, sort_order,
  runtime_module_key, runtime_access_kind
)
values
  ('cadastros.pessoas.candidates.read', 'cadastros', 'Consultar possiveis pessoas duplicadas', true, 78, 'cadastros', 'read'),
  ('cadastros.pessoas.areas.manage', 'cadastros', 'Gerenciar areas comerciais da pessoa', true, 79, 'cadastros', 'write'),
  ('cadastros.pessoas.reactivate', 'cadastros', 'Reativar pessoa comercial', true, 80, 'cadastros', 'write')
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

create or replace function public.normalize_cad_pessoa_legacy_code(p_value text)
returns text
language sql
immutable
parallel safe
set search_path = public
as $$
  select nullif(upper(regexp_replace(btrim(p_value), '[^[:alnum:]]+', '', 'g')), '')
$$;

revoke all on function public.normalize_cad_pessoa_legacy_code(text) from public, anon, authenticated;

do $$
begin
  if exists (
    select 1
      from public.cad_pessoas_comerciais
     where public.normalize_cad_pessoa_legacy_code(codigo_legado) is not null
     group by public.normalize_cad_pessoa_legacy_code(codigo_legado)
    having count(*) > 1
  ) then
    raise exception 'normalized duplicate commercial person legacy code exists; reconcile before migration 0065';
  end if;

  if exists (
    select 1
      from public.cad_pessoa_aliases
     group by pessoa_id, alias_norm
    having count(*) > 1
  ) then
    raise exception 'duplicate alias within the same person exists; reconcile before migration 0065';
  end if;
end;
$$;

alter table public.cad_pessoa_aliases
  drop constraint if exists cad_pessoa_aliases_alias_norm_key;

alter table public.cad_pessoa_aliases
  add constraint cad_pessoa_aliases_person_norm_key unique (pessoa_id, alias_norm);

create index if not exists idx_cad_pessoa_aliases_alias_norm
  on public.cad_pessoa_aliases(alias_norm);

create unique index if not exists idx_cad_pessoas_codigo_legado_norm
  on public.cad_pessoas_comerciais(public.normalize_cad_pessoa_legacy_code(codigo_legado))
  where public.normalize_cad_pessoa_legacy_code(codigo_legado) is not null;

create or replace function public.find_cad_pessoa_possible_duplicates(
  p_nome text,
  p_codigo_legado text default null,
  p_apelidos_json jsonb default '[]'::jsonb,
  p_grafias_incorretas_json jsonb default '[]'::jsonb,
  p_vendedor_responsavel_id bigint default null,
  p_papeis_json jsonb default '[]'::jsonb
)
returns table (
  pessoa_id bigint,
  nome text,
  codigo_legado text,
  status text,
  tipo_comercial text,
  vendedor_responsavel_id bigint,
  vendedor_responsavel_nome text,
  papeis text[],
  areas text[],
  motivos text[]
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nome_norm text;
  v_codigo_norm text;
  v_input_aliases text[];
begin
  perform public.require_current_user_permission('cadastros.pessoas.candidates.read');
  if nullif(btrim(p_nome), '') is null then raise exception 'nome is required'; end if;
  if jsonb_typeof(coalesce(p_apelidos_json, '[]'::jsonb)) <> 'array' then raise exception 'apelidos_json must be an array'; end if;
  if jsonb_typeof(coalesce(p_grafias_incorretas_json, '[]'::jsonb)) <> 'array' then raise exception 'grafias_incorretas_json must be an array'; end if;
  if jsonb_typeof(coalesce(p_papeis_json, '[]'::jsonb)) <> 'array' then raise exception 'papeis_json must be an array'; end if;

  v_nome_norm := public.normalize_catalog_term(p_nome);
  v_codigo_norm := public.normalize_cad_pessoa_legacy_code(p_codigo_legado);
  select coalesce(array_agg(distinct public.normalize_catalog_term(value)), array[]::text[])
    into v_input_aliases
    from jsonb_array_elements_text(coalesce(p_apelidos_json, '[]'::jsonb) || coalesce(p_grafias_incorretas_json, '[]'::jsonb)) item(value)
   where public.normalize_catalog_term(value) is not null;

  return query
  with candidate as (
    select
      person.id,
      array_remove(array[
        case when v_codigo_norm is not null and public.normalize_cad_pessoa_legacy_code(person.codigo_legado) = v_codigo_norm then 'same_legacy_code' end,
        case when public.normalize_catalog_term(person.nome) = v_nome_norm then 'same_normalized_name' end,
        case when exists (
          select 1 from public.cad_pessoa_aliases alias_row
           where alias_row.pessoa_id = person.id
             and public.normalize_catalog_term(alias_row.alias) = v_nome_norm
             and alias_row.tipo <> 'nome'
        ) then 'name_matches_existing_alias' end,
        case when exists (
          select 1 from unnest(v_input_aliases) input_alias
           where input_alias = public.normalize_catalog_term(person.nome)
        ) then 'input_alias_matches_existing_name' end,
        case when exists (
          select 1
            from public.cad_pessoa_aliases alias_row
            join unnest(v_input_aliases) input_alias
              on input_alias = public.normalize_catalog_term(alias_row.alias)
           where alias_row.pessoa_id = person.id
             and alias_row.tipo = 'grafia_incorreta'
        ) then 'same_historical_spelling' end
      ], null)::text[] motivos
    from public.cad_pessoas_comerciais person
  )
  select
    person.id,
    person.nome,
    person.codigo_legado,
    person.status,
    person.tipo_comercial,
    person.vendedor_responsavel_id,
    responsible.nome,
    coalesce((
      select array_agg(distinct role_row.papel order by role_row.papel)
        from public.cad_pessoa_papeis role_row
       where role_row.pessoa_id = person.id and role_row.status = 'active'
    ), array[]::text[]),
    coalesce((
      select array_agg(distinct area.nome order by area.nome)
        from public.cad_pessoa_areas_comerciais membership
        join public.cad_areas_comerciais area on area.id = membership.area_id
       where membership.pessoa_id = person.id and membership.status = 'active'
    ), array[]::text[]),
    candidate.motivos
  from candidate
  join public.cad_pessoas_comerciais person on person.id = candidate.id
  left join public.cad_pessoas_comerciais responsible on responsible.id = person.vendedor_responsavel_id
  where cardinality(candidate.motivos) > 0
  order by person.nome, person.id;
end;
$$;

revoke all on function public.find_cad_pessoa_possible_duplicates(text, text, jsonb, jsonb, bigint, jsonb) from public, anon;
grant execute on function public.find_cad_pessoa_possible_duplicates(text, text, jsonb, jsonb, bigint, jsonb) to authenticated;

drop function public.create_cad_pessoa_comercial(text, text, jsonb, text, text, text, bigint, jsonb, jsonb, jsonb);

create function public.create_cad_pessoa_comercial(
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
  if p_tipo_comercial = 'agente_vinculado' and p_vendedor_responsavel_id is null then raise exception 'vendedor_responsavel_id is required'; end if;
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

revoke all on function public.create_cad_pessoa_comercial(text, text, jsonb, text, text, text, bigint, jsonb, jsonb, jsonb, boolean, text, bigint[]) from public, anon;
grant execute on function public.create_cad_pessoa_comercial(text, text, jsonb, text, text, text, bigint, jsonb, jsonb, jsonb, boolean, text, bigint[]) to authenticated;

create or replace function public.link_cad_pessoa_area_comercial(
  p_pessoa_id bigint,
  p_area_id bigint,
  p_papel_area text,
  p_vigencia_inicio date,
  p_motivo text
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
begin
  v_permission_context := public.begin_audited_rpc(
    'cadastros.pessoas.areas.manage', 'cadastros', 'cad_pessoa_areas_comerciais',
    'change_type', jsonb_build_object('correlation_id', 'pessoa:' || p_pessoa_id || ':area:' || p_area_id)
  );
  if p_pessoa_id is null or p_area_id is null then raise exception 'pessoa_id and area_id are required'; end if;
  if p_papel_area not in ('vendedor', 'gerente', 'supervisor', 'apoio') then raise exception 'invalid area role'; end if;
  if p_vigencia_inicio is null then raise exception 'start date is required'; end if;
  if length(btrim(coalesce(p_motivo, ''))) < 10 then raise exception 'reason must have at least 10 characters'; end if;
  perform 1 from public.cad_pessoas_comerciais where id = p_pessoa_id and status = 'active' for update;
  if not found then raise exception 'active commercial person not found'; end if;
  perform 1 from public.cad_areas_comerciais where id = p_area_id and status = 'active' for update;
  if not found then raise exception 'active commercial area not found'; end if;
  if exists (
    select 1 from public.cad_pessoa_areas_comerciais membership
     where membership.pessoa_id = p_pessoa_id and membership.area_id = p_area_id
       and membership.papel_area = p_papel_area and membership.status = 'active'
       and daterange(coalesce(membership.vigencia_inicio, '-infinity'::date), coalesce(membership.vigencia_fim, 'infinity'::date), '[]')
           && daterange(p_vigencia_inicio, 'infinity'::date, '[]')
  ) then raise exception 'active commercial area membership overlaps an existing period'; end if;
  v_actor := public.current_actor_id();
  insert into public.cad_pessoa_areas_comerciais(
    pessoa_id, area_id, papel_area, status, vigencia_inicio, created_by, updated_by, origem_dados
  ) values (p_pessoa_id, p_area_id, p_papel_area, 'active', p_vigencia_inicio, v_actor, v_actor, 'sistema')
  returning id into v_id;
  select to_jsonb(membership) into v_after from public.cad_pessoa_areas_comerciais membership where membership.id = v_id;
  perform public.log_audited_rpc_change(
    'cadastros', 'cad_pessoa_areas_comerciais', v_id::text, 'cadastros.pessoa_area_linked',
    'cadastros.pessoas.areas.manage', v_permission_context, null, v_after,
    jsonb_build_object('motivo', btrim(p_motivo), 'source', 'link_cad_pessoa_area_comercial'), 'database_rpc'
  );
  return v_id;
end;
$$;

create or replace function public.close_cad_pessoa_area_comercial(
  p_vinculo_id bigint,
  p_vigencia_fim date,
  p_motivo text
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
  v_start date;
  v_status text;
  v_permission_context jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'cadastros.pessoas.areas.manage', 'cadastros', 'cad_pessoa_areas_comerciais',
    'change_type', jsonb_build_object('correlation_id', 'pessoa_area:' || p_vinculo_id || ':close')
  );
  if p_vigencia_fim is null then raise exception 'end date is required'; end if;
  if length(btrim(coalesce(p_motivo, ''))) < 10 then raise exception 'reason must have at least 10 characters'; end if;
  select to_jsonb(membership), membership.vigencia_inicio, membership.status
    into v_before, v_start, v_status
    from public.cad_pessoa_areas_comerciais membership where membership.id = p_vinculo_id for update;
  if not found then raise exception 'commercial area membership not found'; end if;
  if v_status <> 'active' then raise exception 'commercial area membership is not active'; end if;
  if v_start is not null and p_vigencia_fim < v_start then raise exception 'end date cannot precede start date'; end if;
  v_actor := public.current_actor_id();
  update public.cad_pessoa_areas_comerciais
     set status = 'inactive', vigencia_fim = p_vigencia_fim, updated_by = v_actor
   where id = p_vinculo_id;
  select to_jsonb(membership) into v_after from public.cad_pessoa_areas_comerciais membership where membership.id = p_vinculo_id;
  perform public.log_audited_rpc_change(
    'cadastros', 'cad_pessoa_areas_comerciais', p_vinculo_id::text, 'cadastros.pessoa_area_closed',
    'cadastros.pessoas.areas.manage', v_permission_context, v_before, v_after,
    jsonb_build_object('motivo', btrim(p_motivo), 'source', 'close_cad_pessoa_area_comercial'), 'database_rpc'
  );
  return p_vinculo_id;
end;
$$;

create or replace function public.list_cad_pessoa_area_history(p_pessoa_id bigint)
returns table (
  vinculo_id bigint, pessoa_id bigint, area_id bigint, area_nome text,
  papel_area text, status text, vigencia_inicio date, vigencia_fim date
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_permission('cadastros.pessoas.areas.manage');
  return query
  select membership.id, membership.pessoa_id, membership.area_id, area.nome,
         membership.papel_area, membership.status, membership.vigencia_inicio, membership.vigencia_fim
    from public.cad_pessoa_areas_comerciais membership
    join public.cad_areas_comerciais area on area.id = membership.area_id
   where membership.pessoa_id = p_pessoa_id
   order by membership.vigencia_inicio desc nulls last, membership.id desc;
end;
$$;

revoke all on function public.link_cad_pessoa_area_comercial(bigint, bigint, text, date, text) from public, anon;
revoke all on function public.close_cad_pessoa_area_comercial(bigint, date, text) from public, anon;
revoke all on function public.list_cad_pessoa_area_history(bigint) from public, anon;
grant execute on function public.link_cad_pessoa_area_comercial(bigint, bigint, text, date, text) to authenticated;
grant execute on function public.close_cad_pessoa_area_comercial(bigint, date, text) to authenticated;
grant execute on function public.list_cad_pessoa_area_history(bigint) to authenticated;

create or replace function public.reactivate_cad_pessoa_comercial(p_pessoa_id bigint, p_motivo text)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_before jsonb;
  v_after jsonb;
  v_permission_context jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'cadastros.pessoas.reactivate', 'cadastros', 'cad_pessoas_comerciais',
    'change_type', jsonb_build_object('correlation_id', 'pessoa:' || p_pessoa_id || ':reactivate')
  );
  if length(btrim(coalesce(p_motivo, ''))) < 10 then raise exception 'reason must have at least 10 characters'; end if;
  select to_jsonb(person) into v_before from public.cad_pessoas_comerciais person where person.id = p_pessoa_id for update;
  if not found then raise exception 'commercial person not found'; end if;
  if v_before->>'status' <> 'inactive' then raise exception 'commercial person is not inactive'; end if;
  v_actor := public.current_actor_id();
  update public.cad_pessoas_comerciais set status = 'active', updated_by = v_actor where id = p_pessoa_id;
  select to_jsonb(person) into v_after from public.cad_pessoas_comerciais person where person.id = p_pessoa_id;
  perform public.log_audited_rpc_change(
    'cadastros', 'cad_pessoas_comerciais', p_pessoa_id::text, 'cadastros.pessoa_comercial_reactivated',
    'cadastros.pessoas.reactivate', v_permission_context, v_before, v_after,
    jsonb_build_object('motivo', btrim(p_motivo), 'relationships_reopened', false, 'source', 'reactivate_cad_pessoa_comercial'),
    'database_rpc'
  );
  return p_pessoa_id;
end;
$$;

revoke all on function public.reactivate_cad_pessoa_comercial(bigint, text) from public, anon;
grant execute on function public.reactivate_cad_pessoa_comercial(bigint, text) to authenticated;

comment on function public.create_cad_pessoa_comercial(text, text, jsonb, text, text, text, bigint, jsonb, jsonb, jsonb, boolean, text, bigint[]) is
  'Creates a commercial person after transactional duplicate review. Homonyms require confirmation; normalized legacy codes remain absolute.';
comment on function public.link_cad_pessoa_area_comercial(bigint, bigint, text, date, text) is
  'Creates an audited temporal commercial-area membership using existing relational catalogs.';
comment on function public.reactivate_cad_pessoa_comercial(bigint, text) is
  'Reactivates the same commercial person without reopening historical relationships.';
