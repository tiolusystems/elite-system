-- Govern controlled operating procedures and freeze their applicable versions on new PCP orders.

insert into public.permission_actions(
  action_key, module, description, default_allowed, sort_order,
  runtime_module_key, runtime_access_kind
)
values
  ('pcp.pop.read', 'pcp', 'Consultar POPs e documentos controlados', true, 325, 'pcp', 'read'),
  ('pcp.pop.version.create', 'pcp', 'Criar versao de POP', false, 326, 'pcp', 'write'),
  ('pcp.pop.publish', 'pcp', 'Publicar versao de POP', false, 327, 'pcp', 'write'),
  ('pcp.pop.state.manage', 'pcp', 'Ativar ou inativar POP', false, 328, 'pcp', 'write'),
  ('pcp.pop.applicability.manage', 'pcp', 'Gerenciar aplicacao de POP nos processos', false, 329, 'pcp', 'write'),
  ('pcp.pop.cq.record', 'pcp', 'Registrar observacao de POP no controle de qualidade', false, 330, 'pcp', 'write')
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

insert into public.sys_module_routes(route_prefix, module_key, match_children)
values ('/qualidade/pops', 'pcp', true)
on conflict (route_prefix) do update set
  module_key = excluded.module_key,
  match_children = excluded.match_children;

create table public.pcp_pops (
  id bigint generated always as identity primary key,
  codigo text not null,
  codigo_norm text generated always as (public.normalize_catalog_term(codigo)) stored,
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint pcp_pops_codigo_check check (
    nullif(btrim(codigo), '') is not null and char_length(codigo) <= 50
  ),
  constraint pcp_pops_codigo_norm_key unique (codigo_norm)
);

create table public.pcp_pop_versoes (
  id bigint generated always as identity primary key,
  pop_id bigint not null references public.pcp_pops(id) on delete restrict,
  titulo text not null,
  finalidade text not null,
  revisao text not null,
  revisao_norm text generated always as (public.normalize_catalog_term(revisao)) stored,
  vigencia_inicio date not null,
  status text not null default 'draft',
  referencia_documental text not null,
  conteudo text not null,
  justificativa text not null,
  supersedes_id bigint references public.pcp_pop_versoes(id) on delete restrict,
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  published_by uuid references public.user_profiles(id),
  published_at timestamptz,
  constraint pcp_pop_versoes_status_check check (status in ('draft', 'published')),
  constraint pcp_pop_versoes_text_check check (
    nullif(btrim(titulo), '') is not null
    and nullif(btrim(finalidade), '') is not null
    and nullif(btrim(revisao), '') is not null
    and nullif(btrim(referencia_documental), '') is not null
    and nullif(btrim(conteudo), '') is not null
    and length(btrim(justificativa)) >= 10
  ),
  constraint pcp_pop_versoes_publicacao_check check (
    (status = 'draft' and published_by is null and published_at is null)
    or (status = 'published' and published_by is not null and published_at is not null)
  ),
  constraint pcp_pop_versoes_revision_key unique (pop_id, revisao_norm)
);

create table public.pcp_pop_estado_eventos (
  id bigint generated always as identity primary key,
  pop_id bigint not null references public.pcp_pops(id) on delete restrict,
  pop_versao_id bigint not null references public.pcp_pop_versoes(id) on delete restrict,
  status text not null,
  motivo text not null,
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint pcp_pop_estado_status_check check (status in ('active', 'inactive')),
  constraint pcp_pop_estado_motivo_check check (length(btrim(motivo)) >= 10)
);

create table public.pcp_pop_aplicabilidade_eventos (
  id bigint generated always as identity primary key,
  pop_versao_id bigint not null references public.pcp_pop_versoes(id) on delete restrict,
  etapa text not null,
  formula_versao_id bigint references public.pcp_formula_versoes(id) on delete restrict,
  status text not null,
  ordem_exibicao integer not null default 0,
  motivo text not null,
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint pcp_pop_aplicabilidade_etapa_check check (
    etapa in (
      'producao',
      'separacao_mp',
      'conferencia_mp',
      'formulacao',
      'amostragem',
      'controle_qualidade',
      'limpeza_equipamento',
      'liberacao_equipamento',
      'envase'
    )
  ),
  constraint pcp_pop_aplicabilidade_status_check check (status in ('active', 'inactive')),
  constraint pcp_pop_aplicabilidade_ordem_check check (ordem_exibicao >= 0),
  constraint pcp_pop_aplicabilidade_motivo_check check (length(btrim(motivo)) >= 10)
);

create table public.pcp_op_pops_congelados (
  id bigint generated always as identity primary key,
  op_id bigint not null references public.pcp_ordens_producao(id) on delete restrict,
  pop_versao_id bigint not null references public.pcp_pop_versoes(id) on delete restrict,
  etapa text not null,
  codigo_snapshot text not null,
  titulo_snapshot text not null,
  revisao_snapshot text not null,
  vigencia_snapshot date not null,
  ordem_exibicao integer not null default 0,
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint pcp_op_pops_snapshot_key unique (op_id, pop_versao_id, etapa)
);

create table public.pcp_op_cq_pop_registros (
  id bigint generated always as identity primary key,
  cq_resultado_id bigint not null references public.pcp_op_cq_resultados(id) on delete restrict,
  op_id bigint not null references public.pcp_ordens_producao(id) on delete restrict,
  op_pop_congelado_id bigint not null references public.pcp_op_pops_congelados(id) on delete restrict,
  resultado text not null,
  etapa_controle text not null,
  observacao text,
  acao_corretiva text,
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint pcp_op_cq_pop_resultado_check check (
    resultado in ('conforme', 'desvio', 'nao_conforme')
  ),
  constraint pcp_op_cq_pop_etapa_check check (nullif(btrim(etapa_controle), '') is not null),
  constraint pcp_op_cq_pop_desvio_check check (
    resultado = 'conforme'
    or nullif(btrim(observacao), '') is not null
  ),
  constraint pcp_op_cq_pop_key unique (cq_resultado_id, op_pop_congelado_id)
);

create index idx_pcp_pop_versoes_pop_status
  on public.pcp_pop_versoes(pop_id, status, vigencia_inicio desc, id desc);
create index idx_pcp_pop_estado_pop
  on public.pcp_pop_estado_eventos(pop_id, created_at desc, id desc);
create index idx_pcp_pop_aplicabilidade_lookup
  on public.pcp_pop_aplicabilidade_eventos(
    pop_versao_id, etapa, formula_versao_id, created_at desc, id desc
  );
create index idx_pcp_op_pops_op
  on public.pcp_op_pops_congelados(op_id, ordem_exibicao, id);
create index idx_pcp_op_cq_pop_op
  on public.pcp_op_cq_pop_registros(op_id, created_at desc, id desc);

alter table public.pcp_pops enable row level security;
alter table public.pcp_pop_versoes enable row level security;
alter table public.pcp_pop_estado_eventos enable row level security;
alter table public.pcp_pop_aplicabilidade_eventos enable row level security;
alter table public.pcp_op_pops_congelados enable row level security;
alter table public.pcp_op_cq_pop_registros enable row level security;

revoke all on table public.pcp_pops from public, anon, authenticated;
revoke all on table public.pcp_pop_versoes from public, anon, authenticated;
revoke all on table public.pcp_pop_estado_eventos from public, anon, authenticated;
revoke all on table public.pcp_pop_aplicabilidade_eventos from public, anon, authenticated;
revoke all on table public.pcp_op_pops_congelados from public, anon, authenticated;
revoke all on table public.pcp_op_cq_pop_registros from public, anon, authenticated;

create or replace function public.prevent_pcp_pop_append_only_changes()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception '% is append-only', tg_table_name;
end;
$$;

create or replace function public.guard_pcp_pop_version_publication()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.status = 'draft'
     and new.status = 'published'
     and new.published_by is not null
     and new.published_at is not null
     and new.pop_id = old.pop_id
     and new.titulo = old.titulo
     and new.finalidade = old.finalidade
     and new.revisao = old.revisao
     and new.vigencia_inicio = old.vigencia_inicio
     and new.referencia_documental = old.referencia_documental
     and new.conteudo = old.conteudo
     and new.justificativa = old.justificativa
     and new.supersedes_id is not distinct from old.supersedes_id
     and new.created_by = old.created_by
     and new.created_at = old.created_at then
    return new;
  end if;
  raise exception 'published POP versions are immutable; create a new version';
end;
$$;

create trigger trg_pcp_pops_append_only
before update or delete on public.pcp_pops
for each row execute function public.prevent_pcp_pop_append_only_changes();
create trigger trg_pcp_pop_versoes_guard
before update or delete on public.pcp_pop_versoes
for each row execute function public.guard_pcp_pop_version_publication();
create trigger trg_pcp_pop_estado_append_only
before update or delete on public.pcp_pop_estado_eventos
for each row execute function public.prevent_pcp_pop_append_only_changes();
create trigger trg_pcp_pop_aplicabilidade_append_only
before update or delete on public.pcp_pop_aplicabilidade_eventos
for each row execute function public.prevent_pcp_pop_append_only_changes();
create trigger trg_pcp_op_pops_append_only
before update or delete on public.pcp_op_pops_congelados
for each row execute function public.prevent_pcp_pop_append_only_changes();
create trigger trg_pcp_op_cq_pop_append_only
before update or delete on public.pcp_op_cq_pop_registros
for each row execute function public.prevent_pcp_pop_append_only_changes();

create or replace function public.create_pcp_pop_version(
  p_pop_id bigint,
  p_codigo text,
  p_titulo text,
  p_finalidade text,
  p_revisao text,
  p_vigencia_inicio date,
  p_referencia_documental text,
  p_conteudo text,
  p_justificativa text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_context jsonb;
  v_pop_id bigint;
  v_version_id bigint;
  v_supersedes_id bigint;
  v_after jsonb;
begin
  v_context := public.begin_audited_rpc(
    'pcp.pop.version.create', 'pcp', 'pcp_pop_versoes', 'change_type',
    jsonb_build_object('correlation_id', gen_random_uuid()::text)
  );
  if public.normalize_catalog_term(p_codigo) is null
     or nullif(btrim(p_titulo), '') is null
     or nullif(btrim(p_finalidade), '') is null
     or public.normalize_catalog_term(p_revisao) is null
     or p_vigencia_inicio is null
     or nullif(btrim(p_referencia_documental), '') is null
     or nullif(btrim(p_conteudo), '') is null then
    raise exception 'required POP version fields are missing';
  end if;
  if length(btrim(coalesce(p_justificativa, ''))) < 10 then
    raise exception 'reason must have at least 10 characters';
  end if;

  v_actor := public.current_actor_id();
  if p_pop_id is null then
    perform pg_advisory_xact_lock(
      hashtextextended('pcp_pop:' || public.normalize_catalog_term(p_codigo), 0)
    );
    insert into public.pcp_pops(codigo, created_by)
    values (upper(btrim(p_codigo)), v_actor)
    returning id into v_pop_id;
  else
    perform pg_advisory_xact_lock(hashtextextended('pcp_pop_id:' || p_pop_id, 0));
    select id into v_pop_id
      from public.pcp_pops
     where id = p_pop_id
       and codigo_norm = public.normalize_catalog_term(p_codigo);
    if not found then
      raise exception 'controlled procedure not found or code does not match';
    end if;
  end if;

  select version.id into v_supersedes_id
    from public.pcp_pop_versoes version
   where version.pop_id = v_pop_id
   order by version.created_at desc, version.id desc
   limit 1;

  insert into public.pcp_pop_versoes(
    pop_id, titulo, finalidade, revisao, vigencia_inicio,
    referencia_documental, conteudo, justificativa, supersedes_id, created_by
  ) values (
    v_pop_id, btrim(p_titulo), btrim(p_finalidade), btrim(p_revisao),
    p_vigencia_inicio, btrim(p_referencia_documental), btrim(p_conteudo),
    btrim(p_justificativa), v_supersedes_id, v_actor
  )
  returning id into v_version_id;

  select to_jsonb(version) into v_after
    from public.pcp_pop_versoes version where version.id = v_version_id;
  perform public.log_audited_rpc_change(
    'pcp', 'pcp_pop_versoes', v_version_id::text, 'pcp.pop_version_created',
    'pcp.pop.version.create', v_context, null, v_after,
    jsonb_build_object('pop_id', v_pop_id), 'database_rpc'
  );
  return v_version_id;
end;
$$;

create or replace function public.publish_pcp_pop_version(
  p_pop_versao_id bigint,
  p_justificativa text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_context jsonb;
  v_before jsonb;
  v_after jsonb;
begin
  v_context := public.begin_audited_rpc(
    'pcp.pop.publish', 'pcp', 'pcp_pop_versoes', 'status_transition',
    jsonb_build_object('correlation_id', 'pcp_pop_version:' || p_pop_versao_id || ':publish')
  );
  if length(btrim(coalesce(p_justificativa, ''))) < 10 then
    raise exception 'reason must have at least 10 characters';
  end if;
  select to_jsonb(version) into v_before
    from public.pcp_pop_versoes version
   where version.id = p_pop_versao_id
   for update;
  if not found or v_before->>'status' <> 'draft' then
    raise exception 'only a draft POP version can be published';
  end if;
  v_actor := public.current_actor_id();
  update public.pcp_pop_versoes
     set status = 'published', published_by = v_actor, published_at = now()
   where id = p_pop_versao_id;
  select to_jsonb(version) into v_after
    from public.pcp_pop_versoes version where version.id = p_pop_versao_id;
  perform public.log_audited_rpc_change(
    'pcp', 'pcp_pop_versoes', p_pop_versao_id::text, 'pcp.pop_version_published',
    'pcp.pop.publish', v_context, v_before, v_after,
    jsonb_build_object('motivo', btrim(p_justificativa)), 'database_rpc'
  );
  return p_pop_versao_id;
end;
$$;

create or replace function public.set_pcp_pop_active_state(
  p_pop_id bigint,
  p_active boolean,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_context jsonb;
  v_version_id bigint;
  v_current text;
  v_event_id bigint;
  v_after jsonb;
begin
  v_context := public.begin_audited_rpc(
    'pcp.pop.state.manage', 'pcp', 'pcp_pop_estado_eventos', 'status_transition',
    jsonb_build_object('correlation_id', 'pcp_pop:' || p_pop_id || ':state')
  );
  if length(btrim(coalesce(p_motivo, ''))) < 10 then
    raise exception 'reason must have at least 10 characters';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('pcp_pop_id:' || p_pop_id, 0));
  select version.id into v_version_id
    from public.pcp_pop_versoes version
   where version.pop_id = p_pop_id
     and version.status = 'published'
     and version.vigencia_inicio <= current_date
   order by version.vigencia_inicio desc, version.id desc
   limit 1;
  if v_version_id is null then
    raise exception 'a published and effective POP version is required';
  end if;
  select event.status into v_current
    from public.pcp_pop_estado_eventos event
   where event.pop_id = p_pop_id
   order by event.created_at desc, event.id desc
   limit 1;
  if v_current = case when p_active then 'active' else 'inactive' end then
    raise exception 'controlled procedure already has the requested state';
  end if;
  v_actor := public.current_actor_id();
  insert into public.pcp_pop_estado_eventos(
    pop_id, pop_versao_id, status, motivo, created_by
  ) values (
    p_pop_id, v_version_id, case when p_active then 'active' else 'inactive' end,
    btrim(p_motivo), v_actor
  )
  returning id into v_event_id;
  select to_jsonb(event) into v_after
    from public.pcp_pop_estado_eventos event where event.id = v_event_id;
  perform public.log_audited_rpc_change(
    'pcp', 'pcp_pop_estado_eventos', v_event_id::text,
    case when p_active then 'pcp.pop_activated' else 'pcp.pop_deactivated' end,
    'pcp.pop.state.manage', v_context, null, v_after,
    jsonb_build_object('motivo', btrim(p_motivo), 'history_preserved', true),
    'database_rpc'
  );
  return v_event_id;
end;
$$;

create or replace function public.set_pcp_pop_applicability(
  p_pop_versao_id bigint,
  p_etapa text,
  p_formula_versao_id bigint,
  p_active boolean,
  p_ordem_exibicao integer,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_context jsonb;
  v_event_id bigint;
  v_current text;
  v_pop_id bigint;
  v_pop_state text;
  v_after jsonb;
  v_key text;
begin
  v_context := public.begin_audited_rpc(
    'pcp.pop.applicability.manage', 'pcp', 'pcp_pop_aplicabilidade_eventos',
    'change_type', jsonb_build_object('correlation_id', gen_random_uuid()::text)
  );
  if p_etapa not in (
    'producao', 'separacao_mp', 'conferencia_mp', 'formulacao', 'amostragem',
    'controle_qualidade', 'limpeza_equipamento', 'liberacao_equipamento', 'envase'
  ) then
    raise exception 'invalid controlled procedure stage';
  end if;
  if coalesce(p_ordem_exibicao, 0) < 0 then
    raise exception 'display order must be non-negative';
  end if;
  if length(btrim(coalesce(p_motivo, ''))) < 10 then
    raise exception 'reason must have at least 10 characters';
  end if;
  select version.pop_id into v_pop_id
    from public.pcp_pop_versoes version
   where version.id = p_pop_versao_id and version.status = 'published';
  if not found then
    raise exception 'published POP version not found';
  end if;
  select event.status into v_pop_state
    from public.pcp_pop_estado_eventos event
   where event.pop_id = v_pop_id
   order by event.created_at desc, event.id desc
   limit 1;
  if p_active and v_pop_state is distinct from 'active' then
    raise exception 'controlled procedure must be active before linking';
  end if;
  if p_formula_versao_id is not null and not exists (
    select 1 from public.pcp_formula_versoes where id = p_formula_versao_id
  ) then
    raise exception 'formula version not found';
  end if;

  v_key := p_pop_versao_id || ':' || p_etapa || ':' || coalesce(p_formula_versao_id::text, 'all');
  perform pg_advisory_xact_lock(hashtextextended('pcp_pop_applicability:' || v_key, 0));
  select event.status into v_current
    from public.pcp_pop_aplicabilidade_eventos event
   where event.pop_versao_id = p_pop_versao_id
     and event.etapa = p_etapa
     and event.formula_versao_id is not distinct from p_formula_versao_id
   order by event.created_at desc, event.id desc
   limit 1;
  if v_current = case when p_active then 'active' else 'inactive' end then
    raise exception 'controlled procedure applicability already has the requested state';
  end if;

  v_actor := public.current_actor_id();
  insert into public.pcp_pop_aplicabilidade_eventos(
    pop_versao_id, etapa, formula_versao_id, status,
    ordem_exibicao, motivo, created_by
  ) values (
    p_pop_versao_id, p_etapa, p_formula_versao_id,
    case when p_active then 'active' else 'inactive' end,
    coalesce(p_ordem_exibicao, 0), btrim(p_motivo), v_actor
  )
  returning id into v_event_id;
  select to_jsonb(event) into v_after
    from public.pcp_pop_aplicabilidade_eventos event where event.id = v_event_id;
  perform public.log_audited_rpc_change(
    'pcp', 'pcp_pop_aplicabilidade_eventos', v_event_id::text,
    case when p_active then 'pcp.pop_applicability_added' else 'pcp.pop_applicability_removed' end,
    'pcp.pop.applicability.manage', v_context, null, v_after,
    jsonb_build_object('motivo', btrim(p_motivo)), 'database_rpc'
  );
  return v_event_id;
end;
$$;

create or replace function public.freeze_pcp_op_pop_versions()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.pcp_op_pops_congelados(
    op_id, pop_versao_id, etapa, codigo_snapshot, titulo_snapshot,
    revisao_snapshot, vigencia_snapshot, ordem_exibicao, created_by
  )
  select
    new.id,
    applicable.pop_versao_id,
    applicable.etapa,
    pop.codigo,
    version.titulo,
    version.revisao,
    version.vigencia_inicio,
    applicable.ordem_exibicao,
    new.created_by
  from (
    select distinct on (latest.pop_versao_id, latest.etapa)
      latest.pop_versao_id,
      latest.etapa,
      latest.formula_versao_id,
      latest.ordem_exibicao
    from (
      select distinct on (event.pop_versao_id, event.etapa, event.formula_versao_id)
        event.pop_versao_id,
        event.etapa,
        event.formula_versao_id,
        event.status,
        event.ordem_exibicao,
        event.created_at,
        event.id
      from public.pcp_pop_aplicabilidade_eventos event
      where event.formula_versao_id is null
         or event.formula_versao_id = new.formula_versao_id
      order by
        event.pop_versao_id, event.etapa, event.formula_versao_id,
        event.created_at desc, event.id desc
    ) latest
    where latest.status = 'active'
    order by
      latest.pop_versao_id,
      latest.etapa,
      (latest.formula_versao_id is not null) desc,
      latest.created_at desc,
      latest.id desc
  ) applicable
  join public.pcp_pop_versoes version
    on version.id = applicable.pop_versao_id
   and version.status = 'published'
   and version.vigencia_inicio <= current_date
  join public.pcp_pops pop on pop.id = version.pop_id
  where (
    select state.status
    from public.pcp_pop_estado_eventos state
    where state.pop_id = pop.id
    order by state.created_at desc, state.id desc
    limit 1
  ) = 'active'
  order by applicable.ordem_exibicao, pop.codigo, applicable.etapa;
  return new;
end;
$$;

create trigger trg_pcp_op_freeze_pop_versions
after insert on public.pcp_ordens_producao
for each row execute function public.freeze_pcp_op_pop_versions();

create or replace function public.list_pcp_pop_catalog()
returns table(
  pop_id bigint,
  pop_versao_id bigint,
  codigo text,
  titulo text,
  finalidade text,
  revisao text,
  vigencia_inicio date,
  version_status text,
  pop_status text,
  referencia_documental text,
  conteudo text,
  justificativa text,
  supersedes_id bigint,
  created_at timestamptz,
  published_at timestamptz,
  applicability_count bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_permission('pcp.pop.read');
  return query
    select
      pop.id,
      version.id,
      pop.codigo,
      version.titulo,
      version.finalidade,
      version.revisao,
      version.vigencia_inicio,
      version.status,
      coalesce((
        select state.status
        from public.pcp_pop_estado_eventos state
        where state.pop_id = pop.id
        order by state.created_at desc, state.id desc
        limit 1
      ), 'inactive'),
      version.referencia_documental,
      version.conteudo,
      version.justificativa,
      version.supersedes_id,
      version.created_at,
      version.published_at,
      (
        select count(*)
        from (
          select distinct on (event.etapa, event.formula_versao_id)
            event.status
          from public.pcp_pop_aplicabilidade_eventos event
          where event.pop_versao_id = version.id
          order by
            event.etapa, event.formula_versao_id,
            event.created_at desc, event.id desc
        ) current_app
        where current_app.status = 'active'
      )
    from public.pcp_pops pop
    join public.pcp_pop_versoes version on version.pop_id = pop.id
    order by pop.codigo, version.vigencia_inicio desc, version.id desc;
end;
$$;

create or replace function public.list_pcp_pop_applicabilities()
returns table(
  pop_versao_id bigint,
  etapa text,
  formula_versao_id bigint,
  status text,
  ordem_exibicao integer,
  motivo text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_permission('pcp.pop.read');
  return query
    select distinct on (event.pop_versao_id, event.etapa, event.formula_versao_id)
      event.pop_versao_id,
      event.etapa,
      event.formula_versao_id,
      event.status,
      event.ordem_exibicao,
      event.motivo,
      event.created_at
    from public.pcp_pop_aplicabilidade_eventos event
    order by
      event.pop_versao_id, event.etapa, event.formula_versao_id,
      event.created_at desc, event.id desc;
end;
$$;

create or replace function public.list_pcp_op_pop_references(p_op_id bigint default null)
returns table(
  id bigint,
  op_id bigint,
  pop_versao_id bigint,
  etapa text,
  codigo text,
  titulo text,
  revisao text,
  vigencia_inicio date,
  ordem_exibicao integer,
  cq_resultado text,
  cq_etapa_controle text,
  cq_observacao text,
  cq_acao_corretiva text,
  cq_created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_permission('pcp.pop.read');
  return query
    select
      snapshot.id,
      snapshot.op_id,
      snapshot.pop_versao_id,
      snapshot.etapa,
      snapshot.codigo_snapshot,
      snapshot.titulo_snapshot,
      snapshot.revisao_snapshot,
      snapshot.vigencia_snapshot,
      snapshot.ordem_exibicao,
      result.resultado,
      result.etapa_controle,
      result.observacao,
      result.acao_corretiva,
      result.created_at
    from public.pcp_op_pops_congelados snapshot
    left join public.pcp_op_cq_pop_registros result
      on result.op_pop_congelado_id = snapshot.id
    where p_op_id is null or snapshot.op_id = p_op_id
    order by snapshot.op_id desc, snapshot.ordem_exibicao, snapshot.id;
end;
$$;

create or replace function public.finalizar_pcp_op_relacional_com_pops(
  p_op_id bigint,
  p_outputs_jsonb jsonb,
  p_cq_status text,
  p_ph numeric,
  p_densidade_kg_l numeric,
  p_volume_l numeric,
  p_massa_kg numeric,
  p_temperatura_c numeric,
  p_separador_pessoa_id bigint,
  p_conferente_pessoa_id bigint,
  p_formulador_pessoa_ids bigint[],
  p_responsavel_cq_pessoa_id bigint,
  p_responsavel_liberacao_pessoa_id bigint,
  p_pop_resultados_jsonb jsonb default '[]'::jsonb,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result bigint;
  v_cq_resultado_id bigint;
  v_actor uuid;
  v_context jsonb;
  v_item jsonb;
  v_snapshot_id bigint;
  v_resultado text;
  v_etapa text;
  v_observacao text;
  v_acao text;
  v_record_id bigint;
  v_after jsonb;
begin
  if jsonb_typeof(coalesce(p_pop_resultados_jsonb, '[]'::jsonb)) <> 'array' then
    raise exception 'controlled procedure results must be an array';
  end if;

  v_result := public.finalizar_pcp_op_relacional(
    p_op_id,
    p_outputs_jsonb,
    p_cq_status,
    p_ph,
    p_densidade_kg_l,
    p_volume_l,
    p_massa_kg,
    p_temperatura_c,
    p_separador_pessoa_id,
    p_conferente_pessoa_id,
    p_formulador_pessoa_ids,
    p_responsavel_cq_pessoa_id,
    p_responsavel_liberacao_pessoa_id,
    p_observacao
  );

  if jsonb_array_length(coalesce(p_pop_resultados_jsonb, '[]'::jsonb)) = 0 then
    return v_result;
  end if;

  v_context := public.begin_audited_rpc(
    'pcp.pop.cq.record', 'pcp', 'pcp_op_cq_pop_registros', 'movement_event',
    jsonb_build_object('correlation_id', 'pcp_op:' || p_op_id || ':pop_cq')
  );
  v_actor := public.current_actor_id();
  select cq.id into v_cq_resultado_id
    from public.pcp_op_cq_resultados cq
   where cq.op_id = p_op_id;

  for v_item in select value from jsonb_array_elements(p_pop_resultados_jsonb)
  loop
    v_snapshot_id := nullif(v_item->>'op_pop_congelado_id', '')::bigint;
    v_resultado := lower(nullif(btrim(v_item->>'resultado'), ''));
    v_etapa := nullif(btrim(v_item->>'etapa_controle'), '');
    v_observacao := nullif(btrim(v_item->>'observacao'), '');
    v_acao := nullif(btrim(v_item->>'acao_corretiva'), '');
    if v_resultado not in ('conforme', 'desvio', 'nao_conforme')
       or v_etapa is null then
      raise exception 'invalid controlled procedure CQ result';
    end if;
    if v_resultado <> 'conforme' and v_observacao is null then
      raise exception 'deviation or nonconformity requires an observation';
    end if;
    if not exists (
      select 1 from public.pcp_op_pops_congelados snapshot
      where snapshot.id = v_snapshot_id and snapshot.op_id = p_op_id
    ) then
      raise exception 'controlled procedure snapshot does not belong to this order';
    end if;

    insert into public.pcp_op_cq_pop_registros(
      cq_resultado_id, op_id, op_pop_congelado_id, resultado,
      etapa_controle, observacao, acao_corretiva, created_by
    ) values (
      v_cq_resultado_id, p_op_id, v_snapshot_id, v_resultado,
      v_etapa, v_observacao, v_acao, v_actor
    )
    returning id into v_record_id;
    select to_jsonb(record) into v_after
      from public.pcp_op_cq_pop_registros record where record.id = v_record_id;
    perform public.log_audited_rpc_change(
      'pcp', 'pcp_op_cq_pop_registros', v_record_id::text,
      'pcp.pop_cq_result_recorded', 'pcp.pop.cq.record', v_context,
      null, v_after, jsonb_build_object('op_id', p_op_id), 'database_rpc'
    );
  end loop;
  return v_result;
end;
$$;

revoke all on function public.prevent_pcp_pop_append_only_changes() from public, anon, authenticated;
revoke all on function public.guard_pcp_pop_version_publication() from public, anon, authenticated;
revoke all on function public.freeze_pcp_op_pop_versions() from public, anon, authenticated;
revoke all on function public.create_pcp_pop_version(bigint, text, text, text, text, date, text, text, text) from public, anon;
revoke all on function public.publish_pcp_pop_version(bigint, text) from public, anon;
revoke all on function public.set_pcp_pop_active_state(bigint, boolean, text) from public, anon;
revoke all on function public.set_pcp_pop_applicability(bigint, text, bigint, boolean, integer, text) from public, anon;
revoke all on function public.list_pcp_pop_catalog() from public, anon;
revoke all on function public.list_pcp_pop_applicabilities() from public, anon;
revoke all on function public.list_pcp_op_pop_references(bigint) from public, anon;
revoke all on function public.finalizar_pcp_op_relacional_com_pops(
  bigint, jsonb, text, numeric, numeric, numeric, numeric, numeric,
  bigint, bigint, bigint[], bigint, bigint, jsonb, text
) from public, anon;

grant execute on function public.create_pcp_pop_version(bigint, text, text, text, text, date, text, text, text) to authenticated;
grant execute on function public.publish_pcp_pop_version(bigint, text) to authenticated;
grant execute on function public.set_pcp_pop_active_state(bigint, boolean, text) to authenticated;
grant execute on function public.set_pcp_pop_applicability(bigint, text, bigint, boolean, integer, text) to authenticated;
grant execute on function public.list_pcp_pop_catalog() to authenticated;
grant execute on function public.list_pcp_pop_applicabilities() to authenticated;
grant execute on function public.list_pcp_op_pop_references(bigint) to authenticated;
grant execute on function public.finalizar_pcp_op_relacional_com_pops(
  bigint, jsonb, text, numeric, numeric, numeric, numeric, numeric,
  bigint, bigint, bigint[], bigint, bigint, jsonb, text
) to authenticated;

comment on table public.pcp_pop_versoes is
  'Versioned controlled procedures. Published content is immutable and corrections create a new version.';
comment on table public.pcp_op_pops_congelados is
  'Immutable POP references frozen when a production order is created.';
comment on table public.pcp_op_cq_pop_registros is
  'Append-only CQ observations for the POP versions frozen on an order.';
