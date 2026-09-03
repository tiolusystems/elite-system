-- IAM-01A: versioned, combinable human access profiles.
-- user_profiles.role remains a compatibility field during the controlled transition.

create table if not exists public.security_access_profiles (
  id bigint generated always as identity primary key,
  profile_key text not null,
  name text not null,
  description text not null,
  version integer not null default 1,
  status text not null default 'active',
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint security_access_profiles_key_check check (profile_key ~ '^[a-z0-9_]+$'),
  constraint security_access_profiles_version_check check (version > 0),
  constraint security_access_profiles_status_check check (status in ('active', 'inactive')),
  constraint security_access_profiles_key_version_unique unique (profile_key, version)
);

create table if not exists public.security_access_profile_permissions (
  profile_id bigint not null references public.security_access_profiles(id) on delete restrict,
  action_key text not null references public.permission_actions(action_key) on delete restrict,
  granted boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  primary key (profile_id, action_key)
);

create table if not exists public.security_user_access_profiles (
  user_id uuid not null references public.user_profiles(id) on delete cascade,
  profile_id bigint not null references public.security_access_profiles(id) on delete restrict,
  assigned_by uuid not null references public.user_profiles(id) on delete restrict,
  reason text not null,
  correlation_id text not null,
  assigned_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz,
  primary key (user_id, profile_id),
  constraint security_user_access_profiles_reason_check check (length(btrim(reason)) >= 10),
  constraint security_user_access_profiles_correlation_check check (length(btrim(correlation_id)) >= 8)
);

create index if not exists idx_security_user_access_profiles_user
  on public.security_user_access_profiles(user_id, assigned_at desc);
create index if not exists idx_security_user_access_profiles_profile
  on public.security_user_access_profiles(profile_id, user_id);

alter table public.security_access_profiles enable row level security;
alter table public.security_access_profile_permissions enable row level security;
alter table public.security_user_access_profiles enable row level security;
revoke all on table public.security_access_profiles from public, anon, authenticated;
revoke all on table public.security_access_profile_permissions from public, anon, authenticated;
revoke all on table public.security_user_access_profiles from public, anon, authenticated;

insert into public.security_access_profiles(profile_key, name, description)
values
  ('administrador_sistema', 'Administrador do Sistema', 'Governa identidade, perfis, permissoes, suporte e configuracao.'),
  ('diretoria', 'Diretoria', 'Consulta transversal e aprovacao conforme alcada explicita.'),
  ('comercial_vendedor', 'Comercial / Vendedor', 'Opera clientes, carteira e pedidos comerciais.'),
  ('gerencia_comercial', 'Gerencia Comercial', 'Opera e revisa a cadeia comercial e suas alcadas.'),
  ('pcp_producao', 'PCP / Producao', 'Opera formulas, ordens, qualidade e movimentos originados pela producao.'),
  ('estoque', 'Estoque', 'Opera lotes, reservas, inventario e movimentos de estoque.'),
  ('expedicao_faturamento', 'Expedicao / Faturamento', 'Opera separacao, romaneio, expedicao e documentos fiscais.'),
  ('financeiro', 'Financeiro', 'Opera recebimentos, alocacoes e comissoes financeiras.'),
  ('qualidade', 'Qualidade', 'Opera registros e revisoes de qualidade governados.'),
  ('consulta_auditoria', 'Consulta / Auditoria', 'Consulta rastreabilidade, relatorios e evidencias sem escrita operacional.')
on conflict (profile_key, version) do update set
  name = excluded.name,
  description = excluded.description,
  status = 'active',
  updated_at = clock_timestamp();

-- These rows are the materialized catalog. Patterns are used only while seeding;
-- authorization at runtime joins these explicit rows and never evaluates a wildcard.
insert into public.security_access_profile_permissions(profile_id, action_key)
select profile.id, action.action_key
  from public.security_access_profiles profile
  join public.permission_actions action on (
    (profile.profile_key = 'administrador_sistema' and (action.action_key like 'security.%' or action.action_key in ('system.admin', 'audit.view')))
    or (profile.profile_key = 'diretoria' and (action.action_key like '%.view' or action.module in ('auditoria', 'relatorios')))
    or (profile.profile_key = 'comercial_vendedor' and action.module in ('cadastros', 'pedidos') and action.action_key not like '%approve%')
    or (profile.profile_key = 'gerencia_comercial' and action.module in ('cadastros', 'pedidos'))
    or (profile.profile_key = 'pcp_producao' and (action.module = 'pcp' or action.action_key like 'estoque.%'))
    or (profile.profile_key = 'estoque' and action.module = 'estoque')
    or (profile.profile_key = 'expedicao_faturamento' and action.module in ('expedicao', 'faturamento', 'romaneios'))
    or (profile.profile_key = 'financeiro' and action.module = 'financeiro')
    or (profile.profile_key = 'qualidade' and (action.module = 'qualidade' or action.action_key like '%cq%'))
    or (profile.profile_key = 'consulta_auditoria' and (action.action_key like '%.view' or action.module in ('auditoria', 'relatorios')))
  )
on conflict (profile_id, action_key) do nothing;

create or replace function public.security_user_has_profile_permission(
  p_user_id uuid,
  p_action_key text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.security_user_access_profiles assignment
      join public.security_access_profiles profile
        on profile.id = assignment.profile_id
       and profile.status = 'active'
       and profile.version = (select max(latest.version) from public.security_access_profiles latest where latest.profile_key = profile.profile_key)
      join public.security_access_profile_permissions permission
        on permission.profile_id = profile.id
       and permission.action_key = p_action_key
       and permission.granted
     where assignment.user_id = p_user_id
       and (assignment.expires_at is null or assignment.expires_at > clock_timestamp())
  );
$$;

-- During transition, users without an assignment retain the legacy resolution.
-- Once assigned, explicit profiles become the authorization source for that user.
create or replace function public.can_current_user(p_action_key text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_has_profiles boolean;
  v_override_allowed boolean;
  v_default_allowed boolean;
begin
  if nullif(trim(p_action_key), '') is null then return false; end if;
  v_actor := auth.uid();
  if v_actor is null or not exists (
    select 1 from public.user_profiles profile
     where profile.id = v_actor and profile.status = 'active' and not coalesce(profile.is_system_actor, false)
  ) then return false; end if;

  select exists (select 1 from public.security_user_access_profiles assignment where assignment.user_id = v_actor
    and (assignment.expires_at is null or assignment.expires_at > clock_timestamp())) into v_has_profiles;
  select override_row.allowed into v_override_allowed
    from public.user_permission_overrides override_row
   where override_row.user_id = v_actor and override_row.action_key = trim(p_action_key);
  if found then return v_override_allowed; end if;

  if v_has_profiles then
    return public.security_user_has_profile_permission(v_actor, trim(p_action_key));
  end if;

  select action.default_allowed into v_default_allowed
    from public.permission_actions action where action.action_key = trim(p_action_key);
  return coalesce(v_default_allowed, false);
end;
$$;

create or replace function public.list_security_access_profiles()
returns table (id bigint, profile_key text, name text, description text, version integer, status text, permission_count bigint)
language plpgsql security definer set search_path = public
as $$
begin
  perform public.require_current_user_security_admin('security.manage_permissions');
  return query
    select profile.id, profile.profile_key, profile.name, profile.description, profile.version, profile.status,
           count(permission.action_key)::bigint
      from public.security_access_profiles profile
      left join public.security_access_profile_permissions permission on permission.profile_id = profile.id and permission.granted
     group by profile.id, profile.profile_key, profile.name, profile.description, profile.version, profile.status
     order by profile.name;
end;
$$;

create or replace function public.list_security_user_access_profiles(p_user_id uuid)
returns table (profile_id bigint, profile_key text, profile_name text, profile_version integer, assigned_at timestamptz, expires_at timestamptz, assigned_by uuid, reason text, correlation_id text)
language plpgsql security definer set search_path = public
as $$
begin
  perform public.require_current_user_security_admin('security.manage_permissions');
  if not exists (select 1 from public.user_profiles where id = p_user_id) then raise exception 'target user profile not found'; end if;
  return query
    select profile.id, profile.profile_key, profile.name, profile.version, assignment.assigned_at, assignment.expires_at,
           assignment.assigned_by, assignment.reason, assignment.correlation_id
      from public.security_user_access_profiles assignment
      join public.security_access_profiles profile on profile.id = assignment.profile_id
     where assignment.user_id = p_user_id
     order by profile.name;
end;
$$;

create or replace function public.assign_security_access_profile(
  p_user_id uuid,
  p_profile_id bigint,
  p_reason text,
  p_correlation_id text default null
)
returns boolean
language plpgsql security definer set search_path = public
as $$
declare
  v_actor uuid;
  v_context jsonb;
  v_correlation_id text := coalesce(nullif(trim(p_correlation_id), ''), 'iam:' || gen_random_uuid()::text);
  v_before jsonb;
  v_after jsonb;
begin
  v_actor := public.require_current_user_security_admin('security.manage_permissions');
  if p_user_id is null or p_profile_id is null then raise exception 'user and access profile are required'; end if;
  if length(btrim(coalesce(p_reason, ''))) < 10 then raise exception 'reason must have at least 10 characters'; end if;
  if p_user_id = v_actor then raise exception 'self access profile changes are not allowed'; end if;
  if not exists (select 1 from public.user_profiles where id = p_user_id and status = 'active' and not coalesce(is_system_actor, false)) then raise exception 'target human profile not active'; end if;
  if not exists (select 1 from public.security_access_profiles where id = p_profile_id and status = 'active') then raise exception 'access profile not active'; end if;
  perform pg_advisory_xact_lock(hashtextextended('iam:user:' || p_user_id::text, 0));
  select coalesce(jsonb_agg(to_jsonb(assignment) order by assignment.profile_id), '[]'::jsonb) into v_before
    from public.security_user_access_profiles assignment where assignment.user_id = p_user_id;
  v_context := public.begin_audited_rpc('security.manage_permissions', 'seguranca', 'security_user_access_profiles', 'change_type', jsonb_build_object('correlation_id', v_correlation_id));
  insert into public.security_user_access_profiles(user_id, profile_id, assigned_by, reason, correlation_id)
  values (p_user_id, p_profile_id, v_actor, btrim(p_reason), v_correlation_id)
  on conflict (user_id, profile_id) do update set reason = excluded.reason, correlation_id = excluded.correlation_id, assigned_by = excluded.assigned_by, assigned_at = clock_timestamp();
  select coalesce(jsonb_agg(to_jsonb(assignment) order by assignment.profile_id), '[]'::jsonb) into v_after
    from public.security_user_access_profiles assignment where assignment.user_id = p_user_id;
  perform public.log_audited_rpc_change('seguranca', 'security_user_access_profiles', p_user_id::text, 'seguranca.access_profile_assigned', 'security.manage_permissions', v_context, v_before, v_after, jsonb_build_object('profile_id', p_profile_id, 'reason', btrim(p_reason), 'correlation_id', v_correlation_id));
  return true;
end;
$$;

create or replace function public.remove_security_access_profile(p_user_id uuid, p_profile_id bigint, p_reason text)
returns boolean language plpgsql security definer set search_path = public
as $$
declare v_actor uuid; v_context jsonb; v_before jsonb;
begin
  v_actor := public.require_current_user_security_admin('security.manage_permissions');
  if length(btrim(coalesce(p_reason, ''))) < 10 then raise exception 'reason must have at least 10 characters'; end if;
  if p_user_id = v_actor then raise exception 'self access profile changes are not allowed'; end if;
  select to_jsonb(assignment) into v_before from public.security_user_access_profiles assignment where assignment.user_id = p_user_id and assignment.profile_id = p_profile_id for update;
  if v_before is null then return false; end if;
  v_context := public.begin_audited_rpc('security.manage_permissions', 'seguranca', 'security_user_access_profiles', 'change_type', jsonb_build_object('correlation_id', 'iam:remove:' || gen_random_uuid()::text));
  delete from public.security_user_access_profiles where user_id = p_user_id and profile_id = p_profile_id;
  perform public.log_audited_rpc_change('seguranca', 'security_user_access_profiles', p_user_id::text, 'seguranca.access_profile_removed', 'security.manage_permissions', v_context, v_before, null, jsonb_build_object('profile_id', p_profile_id, 'reason', btrim(p_reason)));
  return true;
end;
$$;

create or replace function public.list_security_effective_permissions(p_user_id uuid)
returns table (action_key text, module text, description text, default_allowed boolean, override_allowed boolean, effective_allowed boolean, sort_order integer)
language plpgsql security definer set search_path = public
as $$
begin
  if p_user_id is null then raise exception 'user_id is required'; end if;
  perform public.require_current_user_security_admin('security.manage_permissions');
  if not exists (select 1 from public.user_profiles where id = p_user_id) then raise exception 'target user profile not found'; end if;
  return query
    select action.action_key, action.module, action.description, action.default_allowed, override_row.allowed,
      case when override_row.allowed is not null then override_row.allowed
           when exists (select 1 from public.security_user_access_profiles assignment where assignment.user_id = p_user_id and (assignment.expires_at is null or assignment.expires_at > clock_timestamp()))
             then public.security_user_has_profile_permission(p_user_id, action.action_key)
           else action.default_allowed end,
      action.sort_order
    from public.permission_actions action
    left join public.user_permission_overrides override_row on override_row.user_id = p_user_id and override_row.action_key = action.action_key
    order by action.module, action.sort_order, action.action_key;
end;
$$;

revoke all on function public.security_user_has_profile_permission(uuid, text) from public, anon, authenticated;
revoke all on function public.list_security_access_profiles() from public, anon;
revoke all on function public.list_security_user_access_profiles(uuid) from public, anon;
revoke all on function public.assign_security_access_profile(uuid, bigint, text, text) from public, anon;
revoke all on function public.remove_security_access_profile(uuid, bigint, text) from public, anon;
grant execute on function public.list_security_access_profiles() to authenticated;
grant execute on function public.list_security_user_access_profiles(uuid) to authenticated;
grant execute on function public.assign_security_access_profile(uuid, bigint, text, text) to authenticated;
grant execute on function public.remove_security_access_profile(uuid, bigint, text) to authenticated;

comment on table public.security_access_profiles is 'Versioned canonical access profiles; profile assignment is independent from commercial role.';
comment on table public.security_user_access_profiles is 'Audited many-to-many human account to access profile assignments.';
comment on function public.can_current_user(text) is 'Central effective permission resolver: inactive deny, individual override, active profile union, legacy fallback only during transition.';
