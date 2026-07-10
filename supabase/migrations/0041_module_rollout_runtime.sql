-- Progressive module rollout contract.
-- The database, not the frontend, is authoritative for environment and module access.

do $$
begin
  create type public.sys_environment as enum (
    'unconfigured',
    'development',
    'test',
    'staging',
    'production'
  );
exception
  when duplicate_object then null;
end;
$$;

do $$
begin
  create type public.sys_module_lifecycle as enum (
    'construction',
    'technical_validation',
    'business_validation',
    'pilot',
    'operational',
    'suspended'
  );
exception
  when duplicate_object then null;
end;
$$;

do $$
begin
  create type public.sys_module_access_mode as enum (
    'disabled',
    'read_only',
    'read_write'
  );
exception
  when duplicate_object then null;
end;
$$;

do $$
begin
  create type public.sys_action_access_kind as enum ('read', 'write');
exception
  when duplicate_object then null;
end;
$$;

create table if not exists public.sys_modules (
  module_key text primary key,
  display_name text not null,
  description text not null,
  owner_domain text not null,
  is_core boolean not null default false,
  sort_order integer not null,
  created_at timestamptz not null default now(),
  constraint sys_modules_key_check check (module_key ~ '^[a-z][a-z0-9_]*$'),
  constraint sys_modules_name_check check (nullif(trim(display_name), '') is not null),
  constraint sys_modules_description_check check (nullif(trim(description), '') is not null),
  constraint sys_modules_owner_check check (nullif(trim(owner_domain), '') is not null),
  constraint sys_modules_sort_order_check check (sort_order >= 0)
);

create table if not exists public.sys_module_routes (
  route_prefix text primary key,
  module_key text not null references public.sys_modules(module_key),
  match_children boolean not null default true,
  created_at timestamptz not null default now(),
  constraint sys_module_routes_prefix_check check (
    route_prefix = '/' or (route_prefix ~ '^/[a-z0-9][a-z0-9/-]*$' and right(route_prefix, 1) <> '/')
  )
);

create table if not exists public.sys_module_dependencies (
  module_key text not null references public.sys_modules(module_key),
  depends_on_module_key text not null references public.sys_modules(module_key),
  minimum_access public.sys_module_access_mode not null default 'read_only',
  required boolean not null default true,
  reason text not null,
  created_at timestamptz not null default now(),
  primary key (module_key, depends_on_module_key),
  constraint sys_module_dependencies_self_check check (module_key <> depends_on_module_key),
  constraint sys_module_dependencies_minimum_check check (minimum_access <> 'disabled'),
  constraint sys_module_dependencies_reason_check check (nullif(trim(reason), '') is not null)
);

create table if not exists public.sys_runtime_environment_events (
  id bigint generated always as identity primary key,
  environment public.sys_environment not null,
  reason_code text not null,
  reason_detail text,
  actor_id uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint sys_runtime_environment_reason_check check (
    reason_code in ('migration_seed', 'initial_configuration', 'deployment_promotion', 'rollback', 'incident', 'test_reset', 'other')
  ),
  constraint sys_runtime_environment_detail_check check (
    reason_code <> 'other' or nullif(trim(reason_detail), '') is not null
  ),
  constraint sys_runtime_environment_actor_check check (
    actor_id is not null or reason_code = 'migration_seed'
  )
);

create table if not exists public.sys_module_rollout_events (
  id bigint generated always as identity primary key,
  environment public.sys_environment not null,
  module_key text not null references public.sys_modules(module_key),
  lifecycle public.sys_module_lifecycle not null,
  access_mode public.sys_module_access_mode not null,
  reason_code text not null,
  reason_detail text,
  actor_id uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint sys_module_rollout_reason_check check (
    reason_code in ('migration_seed', 'technical_validation', 'business_validation', 'pilot_start', 'production_release', 'rollback', 'incident', 'dependency_change', 'other')
  ),
  constraint sys_module_rollout_detail_check check (
    reason_code <> 'other' or nullif(trim(reason_detail), '') is not null
  ),
  constraint sys_module_rollout_actor_check check (
    actor_id is not null or reason_code = 'migration_seed'
  )
);

create index if not exists idx_sys_module_routes_module
  on public.sys_module_routes(module_key);
create index if not exists idx_sys_module_dependencies_dependency
  on public.sys_module_dependencies(depends_on_module_key, module_key);
create index if not exists idx_sys_runtime_environment_latest
  on public.sys_runtime_environment_events(id desc);
create index if not exists idx_sys_module_rollout_latest
  on public.sys_module_rollout_events(environment, module_key, id desc);

comment on table public.sys_modules is
  'Catalogo estatico e versionado dos modulos do Elite System.';
comment on table public.sys_module_dependencies is
  'Grafo relacional de dependencias. Escrita cruzada continua pertencendo ao modulo proprietario.';
comment on table public.sys_runtime_environment_events is
  'Ledger append-only do ambiente autoritativo do banco.';
comment on table public.sys_module_rollout_events is
  'Ledger append-only de maturidade e acesso de cada modulo por ambiente.';

insert into public.sys_modules(module_key, display_name, description, owner_domain, is_core, sort_order)
values
  ('core', 'Nucleo', 'Sessao, painel, configuracao e diagnostico do sistema', 'sistema', true, 10),
  ('seguranca', 'Seguranca', 'Usuarios, perfis, senhas e alcadas', 'seguranca', true, 20),
  ('cadastros', 'Cadastros', 'Clientes, pessoas, materias-primas, produtos e embalagens', 'cadastros', false, 100),
  ('pedidos', 'Pedidos', 'Pedido, credito, Kanban e ciclo comercial', 'pedidos', false, 200),
  ('estoque', 'Estoque', 'Lotes, movimentos, reservas, saldos e inventario', 'estoque', false, 300),
  ('pcp', 'PCP e CQ', 'Formulas, ordens de producao, consumo, geracao e controle de qualidade', 'pcp', false, 400),
  ('expedicao', 'Romaneio e expedicao', 'Separacao, reserva multilote, confirmacao e estorno', 'expedicao', false, 500),
  ('importacao', 'Importacao XML', 'Staging, conferencia e entrada de materia-prima por NF XML', 'importacao', false, 600),
  ('faturamento', 'Faturamento', 'Notas fiscais, remessas, complementos e eventos fiscais', 'faturamento', false, 700),
  ('financeiro', 'Financeiro e comissoes', 'Recebimentos, alocacoes, liberacoes e conta corrente de comissao', 'financeiro', false, 800),
  ('metas', 'Metas comerciais', 'Periodos e ledger append-only de metas', 'metas', false, 900),
  ('relatorios', 'Relatorios', 'Read models, reconciliacoes e relatorios operacionais', 'relatorios', false, 1000),
  ('auditoria', 'Auditoria e migracao', 'Fonte historica, importacao, issues e reconciliacoes', 'auditoria', false, 1100)
on conflict (module_key) do update set
  display_name = excluded.display_name,
  description = excluded.description,
  owner_domain = excluded.owner_domain,
  is_core = excluded.is_core,
  sort_order = excluded.sort_order;

insert into public.sys_module_routes(route_prefix, module_key, match_children)
values
  ('/', 'core', false),
  ('/modulos', 'core', true),
  ('/modulo-indisponivel', 'core', true),
  ('/login/trocar-senha', 'seguranca', true),
  ('/seguranca', 'seguranca', true),
  ('/cadastros', 'cadastros', true),
  ('/pedidos', 'pedidos', true),
  ('/kanban', 'pedidos', true),
  ('/importacao-xml', 'importacao', true),
  ('/pcp', 'pcp', true),
  ('/romaneios', 'expedicao', true),
  ('/relatorios', 'relatorios', true)
on conflict (route_prefix) do update set
  module_key = excluded.module_key,
  match_children = excluded.match_children;

insert into public.sys_module_dependencies(
  module_key,
  depends_on_module_key,
  minimum_access,
  required,
  reason
)
values
  ('seguranca', 'core', 'read_write', true, 'Administracao depende de sessao e configuracao central'),
  ('cadastros', 'core', 'read_write', true, 'Cadastro exige sessao e runtime central'),
  ('cadastros', 'seguranca', 'read_only', true, 'Cadastro exige ator ativo e alçada'),
  ('pedidos', 'core', 'read_write', true, 'Pedido exige sessao e runtime central'),
  ('pedidos', 'seguranca', 'read_only', true, 'Pedido exige ator ativo e alçada'),
  ('pedidos', 'cadastros', 'read_only', true, 'Pedido referencia cliente, propriedade, produto e vendedor'),
  ('estoque', 'core', 'read_write', true, 'Estoque exige runtime central'),
  ('estoque', 'seguranca', 'read_only', true, 'Movimento exige ator e alçada'),
  ('estoque', 'cadastros', 'read_only', true, 'Lotes referenciam MP, PA, PI e embalagens'),
  ('pcp', 'core', 'read_write', true, 'PCP exige runtime central'),
  ('pcp', 'seguranca', 'read_only', true, 'OP e CQ exigem ator e alçada'),
  ('pcp', 'cadastros', 'read_only', true, 'Formula e OP referenciam produtos e insumos'),
  ('pcp', 'estoque', 'read_write', true, 'Finalizacao de OP consome e gera estoque'),
  ('expedicao', 'core', 'read_write', true, 'Expedicao exige runtime central'),
  ('expedicao', 'seguranca', 'read_only', true, 'Romaneio exige ator e alçada'),
  ('expedicao', 'pedidos', 'read_write', true, 'Romaneio confirma quantidades do pedido'),
  ('expedicao', 'estoque', 'read_write', true, 'Romaneio reserva e baixa PA'),
  ('importacao', 'core', 'read_write', true, 'Importacao exige runtime central'),
  ('importacao', 'seguranca', 'read_only', true, 'Conferencia exige ator e alçada'),
  ('importacao', 'cadastros', 'read_write', true, 'Match e conversao dependem do cadastro de MP'),
  ('importacao', 'estoque', 'read_write', true, 'Item confirmado pode gerar lote e entrada de MP'),
  ('faturamento', 'core', 'read_write', true, 'Faturamento exige runtime central'),
  ('faturamento', 'seguranca', 'read_only', true, 'Evento fiscal exige ator e alçada'),
  ('faturamento', 'pedidos', 'read_write', true, 'NF referencia pedido e itens comerciais'),
  ('faturamento', 'expedicao', 'read_only', true, 'NF de remessa pode referenciar romaneio'),
  ('financeiro', 'core', 'read_write', true, 'Financeiro exige runtime central'),
  ('financeiro', 'seguranca', 'read_only', true, 'Recebimento e comissao exigem ator e alçada'),
  ('financeiro', 'pedidos', 'read_only', true, 'Recebimento aloca valores de pedidos'),
  ('financeiro', 'faturamento', 'read_only', true, 'Alocacao pode referenciar notas fiscais'),
  ('metas', 'core', 'read_write', true, 'Metas exigem runtime central'),
  ('metas', 'seguranca', 'read_only', true, 'Movimento de meta exige ator e alçada'),
  ('metas', 'pedidos', 'read_only', true, 'Meta deriva de eventos comerciais'),
  ('relatorios', 'core', 'read_write', true, 'Relatorios exigem runtime central'),
  ('relatorios', 'seguranca', 'read_only', true, 'Consulta respeita ator e alçada'),
  ('relatorios', 'cadastros', 'read_only', false, 'Relatorios podem agregar cadastros'),
  ('relatorios', 'pedidos', 'read_only', false, 'Relatorios podem agregar pedidos'),
  ('relatorios', 'estoque', 'read_only', false, 'Relatorios podem agregar estoque'),
  ('relatorios', 'pcp', 'read_only', false, 'Relatorios podem agregar PCP'),
  ('relatorios', 'expedicao', 'read_only', false, 'Relatorios podem agregar expedicao'),
  ('relatorios', 'faturamento', 'read_only', false, 'Relatorios podem agregar faturamento'),
  ('relatorios', 'financeiro', 'read_only', false, 'Relatorios podem agregar financeiro'),
  ('relatorios', 'metas', 'read_only', false, 'Relatorios podem agregar metas'),
  ('auditoria', 'core', 'read_write', true, 'Auditoria exige runtime central'),
  ('auditoria', 'seguranca', 'read_only', true, 'Auditoria exige ator e alçada'),
  ('auditoria', 'cadastros', 'read_only', false, 'Reconciliacao pode ler cadastros'),
  ('auditoria', 'pedidos', 'read_only', false, 'Reconciliacao pode ler pedidos'),
  ('auditoria', 'estoque', 'read_only', false, 'Reconciliacao pode ler estoque'),
  ('auditoria', 'pcp', 'read_only', false, 'Reconciliacao pode ler PCP')
on conflict (module_key, depends_on_module_key) do update set
  minimum_access = excluded.minimum_access,
  required = excluded.required,
  reason = excluded.reason;

create or replace function public.prevent_system_runtime_event_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception '% is append-only; create a new event', tg_table_name;
end;
$$;

drop trigger if exists trg_sys_runtime_environment_append_only on public.sys_runtime_environment_events;
create trigger trg_sys_runtime_environment_append_only
before update or delete on public.sys_runtime_environment_events
for each row execute function public.prevent_system_runtime_event_mutation();

drop trigger if exists trg_sys_runtime_environment_no_truncate on public.sys_runtime_environment_events;
create trigger trg_sys_runtime_environment_no_truncate
before truncate on public.sys_runtime_environment_events
for each statement execute function public.prevent_system_runtime_event_mutation();

drop trigger if exists trg_sys_module_rollout_append_only on public.sys_module_rollout_events;
create trigger trg_sys_module_rollout_append_only
before update or delete on public.sys_module_rollout_events
for each row execute function public.prevent_system_runtime_event_mutation();

drop trigger if exists trg_sys_module_rollout_no_truncate on public.sys_module_rollout_events;
create trigger trg_sys_module_rollout_no_truncate
before truncate on public.sys_module_rollout_events
for each statement execute function public.prevent_system_runtime_event_mutation();

create or replace function public.prevent_system_module_dependency_cycle()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if exists (
    with recursive reachable(module_key) as (
      select dependency.depends_on_module_key
        from public.sys_module_dependencies dependency
       where dependency.module_key = new.depends_on_module_key
         and dependency.required
      union
      select dependency.depends_on_module_key
        from public.sys_module_dependencies dependency
        join reachable on reachable.module_key = dependency.module_key
       where dependency.required
    )
    select 1 from reachable where module_key = new.module_key
  ) then
    raise exception 'module dependency cycle: % -> %', new.module_key, new.depends_on_module_key;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_sys_module_dependency_cycle on public.sys_module_dependencies;
create trigger trg_sys_module_dependency_cycle
before insert or update on public.sys_module_dependencies
for each row execute function public.prevent_system_module_dependency_cycle();

insert into public.sys_runtime_environment_events(
  environment,
  reason_code,
  reason_detail,
  actor_id
)
values (
  'unconfigured',
  'migration_seed',
  'Banco nasce fechado ate configuracao auditada do ambiente',
  null
);

insert into public.sys_module_rollout_events(
  environment,
  module_key,
  lifecycle,
  access_mode,
  reason_code,
  reason_detail,
  actor_id
)
select
  environment.environment,
  module.module_key,
  case
    when module.module_key in ('core', 'seguranca') then 'operational'::public.sys_module_lifecycle
    else 'technical_validation'::public.sys_module_lifecycle
  end,
  case
    when module.module_key in ('core', 'seguranca') then 'read_write'::public.sys_module_access_mode
    when environment.environment in ('development', 'test') then 'read_write'::public.sys_module_access_mode
    else 'disabled'::public.sys_module_access_mode
  end,
  'migration_seed',
  'Linha de base segura da migration 0041',
  null
from unnest(array[
  'development'::public.sys_environment,
  'test'::public.sys_environment,
  'staging'::public.sys_environment,
  'production'::public.sys_environment
]) as environment(environment)
cross join public.sys_modules module;

insert into public.sys_module_rollout_events(
  environment,
  module_key,
  lifecycle,
  access_mode,
  reason_code,
  reason_detail,
  actor_id
)
select
  'unconfigured'::public.sys_environment,
  module.module_key,
  'operational'::public.sys_module_lifecycle,
  'read_write'::public.sys_module_access_mode,
  'migration_seed',
  'Bootstrap seguro para configuracao do ambiente',
  null
from public.sys_modules module
where module.module_key in ('core', 'seguranca');

create or replace view public.sys_runtime_environment_current as
select
  event.id,
  event.environment,
  event.reason_code,
  event.reason_detail,
  event.actor_id,
  event.created_at
from public.sys_runtime_environment_events event
order by event.id desc
limit 1;

create or replace view public.sys_module_rollouts_current as
select distinct on (event.environment, event.module_key)
  event.id,
  event.environment,
  event.module_key,
  event.lifecycle,
  event.access_mode,
  event.reason_code,
  event.reason_detail,
  event.actor_id,
  event.created_at
from public.sys_module_rollout_events event
order by event.environment, event.module_key, event.id desc;

create or replace function public.system_module_access_rank(p_access public.sys_module_access_mode)
returns integer
language sql
immutable
set search_path = public
as $$
  select case p_access
    when 'disabled' then 0
    when 'read_only' then 1
    when 'read_write' then 2
  end;
$$;

create or replace function public.system_module_lifecycle_allows(
  p_environment public.sys_environment,
  p_lifecycle public.sys_module_lifecycle,
  p_access public.sys_module_access_mode
)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
begin
  if p_access = 'disabled' then
    return true;
  end if;
  if p_lifecycle = 'suspended' then
    return false;
  end if;

  if p_environment in ('development', 'test') then
    return true;
  end if;

  if p_environment = 'unconfigured' then
    return p_lifecycle = 'operational';
  end if;

  if p_environment = 'staging' then
    if p_access = 'read_only' then
      return p_lifecycle in ('technical_validation', 'business_validation', 'pilot', 'operational');
    end if;
    return p_lifecycle in ('business_validation', 'pilot', 'operational');
  end if;

  if p_environment = 'production' then
    if p_access = 'read_only' then
      return p_lifecycle in ('pilot', 'operational');
    end if;
    return p_lifecycle = 'operational';
  end if;

  return false;
end;
$$;

create or replace function public.current_system_environment()
returns public.sys_environment
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select runtime_row.environment from public.sys_runtime_environment_current runtime_row),
    'unconfigured'::public.sys_environment
  );
$$;

create or replace function public.system_module_dependency_blockers(
  p_environment public.sys_environment,
  p_module_key text
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with recursive dependency_tree as (
    select
      dependency.depends_on_module_key as dependency_module_key,
      public.system_module_access_rank(dependency.minimum_access) as minimum_rank,
      array[dependency.module_key, dependency.depends_on_module_key]::text[] as path
    from public.sys_module_dependencies dependency
    where dependency.module_key = p_module_key
      and dependency.required

    union all

    select
      dependency.depends_on_module_key,
      public.system_module_access_rank(dependency.minimum_access),
      tree.path || dependency.depends_on_module_key
    from dependency_tree tree
    join public.sys_module_dependencies dependency
      on dependency.module_key = tree.dependency_module_key
     and dependency.required
    where not dependency.depends_on_module_key = any(tree.path)
  ), requirements as (
    select dependency_module_key, max(minimum_rank) as minimum_rank
    from dependency_tree
    group by dependency_module_key
  ), blockers as (
    select
      requirement.dependency_module_key,
      case requirement.minimum_rank when 2 then 'read_write' else 'read_only' end as required_access,
      rollout.lifecycle,
      rollout.access_mode,
      case
        when rollout.module_key is null then 'rollout_missing'
        when public.system_module_access_rank(rollout.access_mode) < requirement.minimum_rank then 'access_insufficient'
        when not public.system_module_lifecycle_allows(p_environment, rollout.lifecycle, rollout.access_mode) then 'lifecycle_not_allowed'
        else null
      end as blocker_reason
    from requirements requirement
    left join public.sys_module_rollouts_current rollout
      on rollout.environment = p_environment
     and rollout.module_key = requirement.dependency_module_key
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'module_key', blocker.dependency_module_key,
        'required_access', blocker.required_access,
        'configured_access', blocker.access_mode,
        'lifecycle', blocker.lifecycle,
        'reason', blocker.blocker_reason
      ) order by blocker.dependency_module_key
    ) filter (where blocker.blocker_reason is not null),
    '[]'::jsonb
  )
  from blockers blocker;
$$;

create or replace function public.system_module_status(
  p_environment public.sys_environment,
  p_module_key text,
  p_required_access public.sys_module_access_mode default 'read_only'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_rollout public.sys_module_rollouts_current%rowtype;
  v_blockers jsonb := '[]'::jsonb;
  v_reason text;
  v_available boolean := false;
begin
  if not exists (select 1 from public.sys_modules module where module.module_key = p_module_key) then
    return jsonb_build_object(
      'environment', p_environment,
      'module_key', p_module_key,
      'lifecycle', null,
      'configured_access', 'disabled',
      'effective_access', 'disabled',
      'available', false,
      'reason', 'module_not_registered',
      'blockers', '[]'::jsonb
    );
  end if;

  select rollout.*
    into v_rollout
    from public.sys_module_rollouts_current rollout
   where rollout.environment = p_environment
     and rollout.module_key = p_module_key;

  if not found then
    v_reason := case when p_environment = 'unconfigured' then 'environment_unconfigured' else 'rollout_missing' end;
  elsif v_rollout.lifecycle = 'suspended' then
    v_reason := 'module_suspended';
  elsif public.system_module_access_rank(v_rollout.access_mode) < public.system_module_access_rank(p_required_access) then
    v_reason := case when v_rollout.access_mode = 'disabled' then 'module_disabled' else 'access_insufficient' end;
  elsif not public.system_module_lifecycle_allows(p_environment, v_rollout.lifecycle, v_rollout.access_mode) then
    v_reason := 'lifecycle_not_allowed';
  else
    v_blockers := public.system_module_dependency_blockers(p_environment, p_module_key);
    if jsonb_array_length(v_blockers) > 0 then
      v_reason := 'dependency_unavailable';
    else
      v_reason := 'available';
      v_available := true;
    end if;
  end if;

  return jsonb_build_object(
    'environment', p_environment,
    'module_key', p_module_key,
    'lifecycle', v_rollout.lifecycle,
    'configured_access', coalesce(v_rollout.access_mode::text, 'disabled'),
    'effective_access', case when v_available then v_rollout.access_mode::text else 'disabled' end,
    'available', v_available,
    'reason', v_reason,
    'blockers', v_blockers
  );
end;
$$;

alter table public.permission_actions
  add column if not exists runtime_module_key text,
  add column if not exists runtime_access_kind public.sys_action_access_kind;

update public.permission_actions action
set runtime_module_key = case
      when action.action_key = 'pedidos.receipts.create' then 'financeiro'
      when action.module = 'sistema' then 'core'
      when action.module = 'seguranca' then 'seguranca'
      when action.module = 'cadastros' then 'cadastros'
      when action.module in ('comercial', 'pedidos') then 'pedidos'
      when action.module in ('estoque', 'estoque_mp', 'estoque_pi') then 'estoque'
      when action.module in ('producao', 'pcp') then 'pcp'
      when action.module in ('expedicao', 'romaneios') then 'expedicao'
      when action.module = 'importacao' then 'importacao'
      when action.module = 'faturamento' then 'faturamento'
      when action.module = 'financeiro' then 'financeiro'
      when action.module = 'metas' then 'metas'
      when action.module = 'relatorios' then 'relatorios'
      when action.module in ('auditoria', 'migracao') then 'auditoria'
      else null
    end,
    runtime_access_kind = case
      when action.action_key in ('audit.view', 'reports.view', 'pedidos.kanban.view')
        or action.action_key like '%.view'
      then 'read'::public.sys_action_access_kind
      else 'write'::public.sys_action_access_kind
    end;

do $$
declare
  v_unmapped text;
begin
  select string_agg(action.action_key, ', ' order by action.action_key)
    into v_unmapped
    from public.permission_actions action
   where action.runtime_module_key is null
      or action.runtime_access_kind is null;

  if v_unmapped is not null then
    raise exception 'permission actions without runtime module ownership: %', v_unmapped;
  end if;
end;
$$;

alter table public.permission_actions
  alter column runtime_module_key set not null,
  alter column runtime_access_kind set not null;

alter table public.permission_actions
  drop constraint if exists permission_actions_runtime_module_fk;
alter table public.permission_actions
  add constraint permission_actions_runtime_module_fk
  foreign key (runtime_module_key) references public.sys_modules(module_key)
  not valid;
alter table public.permission_actions
  validate constraint permission_actions_runtime_module_fk;

create index if not exists idx_permission_actions_runtime_module
  on public.permission_actions(runtime_module_key, runtime_access_kind, action_key);

comment on column public.permission_actions.runtime_module_key is
  'Modulo proprietario obrigatorio usado pelo gate central de rollout.';
comment on column public.permission_actions.runtime_access_kind is
  'Tipo de acesso exigido pela action key: read ou write.';

create or replace function public.require_current_user_permission(p_action_key text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_action_key text;
  v_module_key text;
  v_access_kind public.sys_action_access_kind;
  v_required_access public.sys_module_access_mode;
  v_environment public.sys_environment;
  v_status jsonb;
begin
  v_action_key := nullif(trim(p_action_key), '');

  if not public.can_current_user(v_action_key) then
    raise exception 'not allowed: %', v_action_key;
  end if;

  select action.runtime_module_key, action.runtime_access_kind
    into v_module_key, v_access_kind
    from public.permission_actions action
   where action.action_key = v_action_key;

  if v_module_key is null or v_access_kind is null then
    raise exception 'action runtime contract missing: %', v_action_key;
  end if;

  v_environment := public.current_system_environment();
  v_required_access := case
    when v_access_kind = 'write' then 'read_write'::public.sys_module_access_mode
    else 'read_only'::public.sys_module_access_mode
  end;
  v_status := public.system_module_status(v_environment, v_module_key, v_required_access);

  if not coalesce((v_status->>'available')::boolean, false) then
    raise exception 'module unavailable: % (%)', v_module_key, coalesce(v_status->>'reason', 'unknown');
  end if;
end;
$$;

drop function if exists public.list_system_module_runtime();
create or replace function public.list_system_module_runtime(
  p_environment text default null
)
returns table (
  environment text,
  active_environment text,
  module_key text,
  display_name text,
  description text,
  owner_domain text,
  is_core boolean,
  lifecycle text,
  configured_access text,
  effective_access text,
  available boolean,
  reason text,
  blockers jsonb,
  sort_order integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_environment public.sys_environment;
  v_active_environment public.sys_environment;
begin
  if public.current_actor_id() is null then
    raise exception 'active user profile required';
  end if;

  v_active_environment := public.current_system_environment();
  if nullif(trim(p_environment), '') is null then
    v_environment := v_active_environment;
  else
    begin
      v_environment := lower(trim(p_environment))::public.sys_environment;
    exception
      when invalid_text_representation then raise exception 'invalid system environment';
    end;
  end if;

  return query
  select
    v_environment::text,
    v_active_environment::text,
    module.module_key,
    module.display_name,
    module.description,
    module.owner_domain,
    module.is_core,
    runtime_status.value->>'lifecycle',
    runtime_status.value->>'configured_access',
    runtime_status.value->>'effective_access',
    coalesce((runtime_status.value->>'available')::boolean, false),
    runtime_status.value->>'reason',
    coalesce(runtime_status.value->'blockers', '[]'::jsonb),
    module.sort_order
  from public.sys_modules module
  cross join lateral (
    select public.system_module_status(v_environment, module.module_key, 'read_only') as value
  ) runtime_status
  order by module.sort_order, module.module_key;
end;
$$;

create or replace function public.get_current_route_module_access(p_pathname text)
returns table (
  pathname text,
  module_key text,
  module_name text,
  environment text,
  lifecycle text,
  configured_access text,
  effective_access text,
  available boolean,
  reason text,
  blockers jsonb
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_pathname text;
  v_environment public.sys_environment;
  v_module public.sys_modules%rowtype;
  v_status jsonb;
begin
  if public.current_actor_id() is null then
    raise exception 'active user profile required';
  end if;

  v_pathname := coalesce(nullif(split_part(trim(p_pathname), '?', 1), ''), '/');
  if left(v_pathname, 1) <> '/' then
    v_pathname := '/' || v_pathname;
  end if;

  select module.*
    into v_module
    from public.sys_module_routes route
    join public.sys_modules module on module.module_key = route.module_key
   where v_pathname = route.route_prefix
      or (
        route.match_children
        and route.route_prefix <> '/'
        and v_pathname like route.route_prefix || '/%'
      )
   order by length(route.route_prefix) desc
   limit 1;

  v_environment := public.current_system_environment();

  if not found then
    return query select
      v_pathname,
      null::text,
      null::text,
      v_environment::text,
      null::text,
      'disabled'::text,
      'disabled'::text,
      false,
      'route_not_registered'::text,
      '[]'::jsonb;
    return;
  end if;

  v_status := public.system_module_status(v_environment, v_module.module_key, 'read_only');

  return query select
    v_pathname,
    v_module.module_key,
    v_module.display_name,
    v_environment::text,
    v_status->>'lifecycle',
    v_status->>'configured_access',
    v_status->>'effective_access',
    coalesce((v_status->>'available')::boolean, false),
    v_status->>'reason',
    coalesce(v_status->'blockers', '[]'::jsonb);
end;
$$;

create or replace function public.set_system_runtime_environment(
  p_environment text,
  p_reason_code text,
  p_reason_detail text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_environment public.sys_environment;
  v_reason_code text;
  v_actor uuid;
  v_permission_context jsonb;
  v_before jsonb;
  v_after jsonb;
  v_event_id bigint;
  v_core_status jsonb;
  v_security_status jsonb;
begin
  begin
    v_environment := lower(nullif(trim(p_environment), ''))::public.sys_environment;
  exception
    when invalid_text_representation then raise exception 'invalid system environment';
  end;

  if v_environment is null then
    raise exception 'system environment is required';
  end if;

  v_reason_code := lower(nullif(trim(p_reason_code), ''));
  if v_reason_code is null or v_reason_code not in ('initial_configuration', 'deployment_promotion', 'rollback', 'incident', 'test_reset', 'other') then
    raise exception 'invalid runtime environment reason';
  end if;
  if v_reason_code = 'other' and nullif(trim(p_reason_detail), '') is null then
    raise exception 'reason detail is required for other';
  end if;

  v_permission_context := public.begin_audited_rpc(
    'system.admin',
    'sistema',
    'sys_runtime_environment_events',
    'change_type',
    jsonb_build_object('event', 'runtime_environment_change', 'target_environment', v_environment)
  );

  perform pg_advisory_xact_lock(hashtextextended('elite:runtime-environment', 0));

  v_core_status := public.system_module_status(v_environment, 'core', 'read_write');
  v_security_status := public.system_module_status(v_environment, 'seguranca', 'read_write');
  if not coalesce((v_core_status->>'available')::boolean, false) then
    raise exception 'target environment core unavailable: %', v_core_status->>'reason';
  end if;
  if not coalesce((v_security_status->>'available')::boolean, false) then
    raise exception 'target environment security unavailable: %', v_security_status->>'reason';
  end if;

  select to_jsonb(runtime_row) into v_before
    from public.sys_runtime_environment_current runtime_row;

  v_actor := public.current_actor_id();
  insert into public.sys_runtime_environment_events(
    environment,
    reason_code,
    reason_detail,
    actor_id
  ) values (
    v_environment,
    v_reason_code,
    nullif(trim(p_reason_detail), ''),
    v_actor
  ) returning id into v_event_id;

  select to_jsonb(runtime_row) into v_after
    from public.sys_runtime_environment_current runtime_row;

  perform public.log_audited_rpc_change(
    'sistema',
    'sys_runtime_environment_events',
    v_event_id::text,
    'sistema.runtime_environment_changed',
    'system.admin',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'environment', v_environment,
      'reason_code', v_reason_code,
      'correlation_id', concat('runtime_environment:', v_event_id)
    )
  );

  return v_event_id;
end;
$$;

create or replace function public.set_system_module_rollout(
  p_environment text,
  p_module_key text,
  p_lifecycle text,
  p_access_mode text,
  p_reason_code text,
  p_reason_detail text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_environment public.sys_environment;
  v_module_key text;
  v_lifecycle public.sys_module_lifecycle;
  v_access_mode public.sys_module_access_mode;
  v_reason_code text;
  v_actor uuid;
  v_is_core boolean;
  v_blockers jsonb := '[]'::jsonb;
  v_permission_context jsonb;
  v_before jsonb;
  v_after jsonb;
  v_event_id bigint;
begin
  begin
    v_environment := lower(nullif(trim(p_environment), ''))::public.sys_environment;
    v_lifecycle := lower(nullif(trim(p_lifecycle), ''))::public.sys_module_lifecycle;
    v_access_mode := lower(nullif(trim(p_access_mode), ''))::public.sys_module_access_mode;
  exception
    when invalid_text_representation then raise exception 'invalid module rollout value';
  end;

  v_module_key := lower(nullif(trim(p_module_key), ''));
  v_reason_code := lower(nullif(trim(p_reason_code), ''));

  if v_environment is null or v_lifecycle is null or v_access_mode is null then
    raise exception 'environment, lifecycle and access mode are required';
  end if;
  if v_module_key is null then
    raise exception 'module key is required';
  end if;
  if v_environment = 'unconfigured' then
    raise exception 'unconfigured rollout is reserved for migration bootstrap';
  end if;
  if v_reason_code is null or v_reason_code not in ('technical_validation', 'business_validation', 'pilot_start', 'production_release', 'rollback', 'incident', 'dependency_change', 'other') then
    raise exception 'invalid module rollout reason';
  end if;
  if v_reason_code = 'other' and nullif(trim(p_reason_detail), '') is null then
    raise exception 'reason detail is required for other';
  end if;

  select module.is_core
    into v_is_core
    from public.sys_modules module
   where module.module_key = v_module_key;
  if not found then
    raise exception 'module not registered';
  end if;

  if v_is_core and (v_lifecycle <> 'operational' or v_access_mode <> 'read_write') then
    raise exception 'core module must remain operational and read_write';
  end if;
  if not public.system_module_lifecycle_allows(v_environment, v_lifecycle, v_access_mode) then
    raise exception 'module lifecycle does not allow requested access in environment';
  end if;

  v_permission_context := public.begin_audited_rpc(
    'system.admin',
    'sistema',
    'sys_module_rollout_events',
    'change_type',
    jsonb_build_object(
      'event', 'module_rollout_change',
      'target_environment', v_environment,
      'target_module', v_module_key
    )
  );

  perform pg_advisory_xact_lock(hashtextextended(concat('elite:module:', v_environment, ':', v_module_key), 0));

  if v_access_mode <> 'disabled' then
    v_blockers := public.system_module_dependency_blockers(v_environment, v_module_key);
    if jsonb_array_length(v_blockers) > 0 then
      raise exception 'module dependencies unavailable: %', v_blockers::text;
    end if;
  end if;

  select to_jsonb(rollout_row) into v_before
    from public.sys_module_rollouts_current rollout_row
   where rollout_row.environment = v_environment
     and rollout_row.module_key = v_module_key;

  v_actor := public.current_actor_id();
  insert into public.sys_module_rollout_events(
    environment,
    module_key,
    lifecycle,
    access_mode,
    reason_code,
    reason_detail,
    actor_id
  ) values (
    v_environment,
    v_module_key,
    v_lifecycle,
    v_access_mode,
    v_reason_code,
    nullif(trim(p_reason_detail), ''),
    v_actor
  ) returning id into v_event_id;

  select to_jsonb(rollout_row) into v_after
    from public.sys_module_rollouts_current rollout_row
   where rollout_row.environment = v_environment
     and rollout_row.module_key = v_module_key;

  perform public.log_audited_rpc_change(
    'sistema',
    'sys_module_rollout_events',
    v_event_id::text,
    'sistema.module_rollout_changed',
    'system.admin',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'environment', v_environment,
      'module_key', v_module_key,
      'lifecycle', v_lifecycle,
      'access_mode', v_access_mode,
      'reason_code', v_reason_code,
      'correlation_id', concat('module_rollout:', v_environment, ':', v_module_key, ':', v_event_id)
    )
  );

  return v_event_id;
end;
$$;

alter table public.sys_modules enable row level security;
alter table public.sys_module_routes enable row level security;
alter table public.sys_module_dependencies enable row level security;
alter table public.sys_runtime_environment_events enable row level security;
alter table public.sys_module_rollout_events enable row level security;

drop policy if exists "active users read module catalog" on public.sys_modules;
create policy "active users read module catalog"
on public.sys_modules for select to authenticated
using (public.current_actor_id() is not null);

drop policy if exists "active users read module routes" on public.sys_module_routes;
create policy "active users read module routes"
on public.sys_module_routes for select to authenticated
using (public.current_actor_id() is not null);

drop policy if exists "active users read module dependencies" on public.sys_module_dependencies;
create policy "active users read module dependencies"
on public.sys_module_dependencies for select to authenticated
using (public.current_actor_id() is not null);

revoke all on public.sys_modules from anon, authenticated;
revoke all on public.sys_module_routes from anon, authenticated;
revoke all on public.sys_module_dependencies from anon, authenticated;
revoke all on public.sys_runtime_environment_events from anon, authenticated;
revoke all on public.sys_module_rollout_events from anon, authenticated;
revoke all on public.sys_runtime_environment_current from anon, authenticated;
revoke all on public.sys_module_rollouts_current from anon, authenticated;

grant select on public.sys_modules to authenticated;
grant select on public.sys_module_routes to authenticated;
grant select on public.sys_module_dependencies to authenticated;

revoke all on function public.prevent_system_runtime_event_mutation() from public;
revoke all on function public.prevent_system_module_dependency_cycle() from public;
revoke all on function public.system_module_access_rank(public.sys_module_access_mode) from public;
revoke all on function public.system_module_lifecycle_allows(public.sys_environment, public.sys_module_lifecycle, public.sys_module_access_mode) from public;
revoke all on function public.current_system_environment() from public;
revoke all on function public.system_module_dependency_blockers(public.sys_environment, text) from public;
revoke all on function public.system_module_status(public.sys_environment, text, public.sys_module_access_mode) from public;
revoke all on function public.list_system_module_runtime(text) from public;
revoke all on function public.get_current_route_module_access(text) from public;
revoke all on function public.set_system_runtime_environment(text, text, text) from public;
revoke all on function public.set_system_module_rollout(text, text, text, text, text, text) from public;

grant execute on function public.current_system_environment() to authenticated;
grant execute on function public.list_system_module_runtime(text) to authenticated;
grant execute on function public.get_current_route_module_access(text) to authenticated;
grant execute on function public.set_system_runtime_environment(text, text, text) to authenticated;
grant execute on function public.set_system_module_rollout(text, text, text, text, text, text) to authenticated;
