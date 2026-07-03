create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.user_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  role text not null default 'comercial',
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_profiles_role_check check (
    role in ('admin', 'comercial', 'producao', 'estoque', 'expedicao', 'auditoria')
  ),
  constraint user_profiles_status_check check (status in ('active', 'inactive'))
);

create table if not exists public.permission_actions (
  action_key text primary key,
  module text not null,
  description text not null,
  default_allowed boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamptz not null default now()
);

create table if not exists public.user_permission_overrides (
  user_id uuid not null references public.user_profiles(id) on delete cascade,
  action_key text not null references public.permission_actions(action_key) on delete cascade,
  allowed boolean not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.user_profiles(id),
  primary key (user_id, action_key)
);

create table if not exists public.action_logs (
  id bigint generated always as identity primary key,
  actor_user_id uuid references public.user_profiles(id),
  action text not null,
  entity_type text,
  entity_id text,
  status text not null default 'success',
  before_json jsonb,
  after_json jsonb,
  metadata_json jsonb,
  previous_hash text,
  entry_hash text not null,
  created_at timestamptz not null default now(),
  constraint action_logs_status_check check (status in ('success', 'denied', 'failed'))
);

create index if not exists idx_action_logs_actor_created_at
  on public.action_logs(actor_user_id, created_at desc);

create index if not exists idx_action_logs_entity
  on public.action_logs(entity_type, entity_id);

create or replace function public.prevent_action_log_changes()
returns trigger
language plpgsql
as $$
begin
  raise exception 'action_logs is append-only';
end;
$$;

drop trigger if exists trg_action_logs_no_update on public.action_logs;
create trigger trg_action_logs_no_update
before update or delete on public.action_logs
for each row execute function public.prevent_action_log_changes();

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_user_profiles_updated_at on public.user_profiles;
create trigger trg_user_profiles_updated_at
before update on public.user_profiles
for each row execute function public.touch_updated_at();

drop trigger if exists trg_user_permission_overrides_updated_at on public.user_permission_overrides;
create trigger trg_user_permission_overrides_updated_at
before update on public.user_permission_overrides
for each row execute function public.touch_updated_at();

create or replace function public.log_action(
  p_action text,
  p_entity_type text default null,
  p_entity_id text default null,
  p_status text default 'success',
  p_before_json jsonb default null,
  p_after_json jsonb default null,
  p_metadata_json jsonb default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_previous_hash text;
  v_entry_hash text;
  v_log_id bigint;
begin
  v_actor := auth.uid();

  if v_actor is not null and not exists (
    select 1 from public.user_profiles where id = v_actor
  ) then
    v_actor := null;
  end if;

  select entry_hash
    into v_previous_hash
    from public.action_logs
    order by id desc
    limit 1;

  v_entry_hash := encode(
    extensions.digest(
      concat_ws(
        '|',
        coalesce(v_previous_hash, ''),
        coalesce(v_actor::text, ''),
        p_action,
        coalesce(p_entity_type, ''),
        coalesce(p_entity_id, ''),
        p_status,
        coalesce(p_before_json::text, ''),
        coalesce(p_after_json::text, ''),
        coalesce(p_metadata_json::text, ''),
        clock_timestamp()::text
      ),
      'sha256'
    ),
    'hex'
  );

  insert into public.action_logs(
    actor_user_id,
    action,
    entity_type,
    entity_id,
    status,
    before_json,
    after_json,
    metadata_json,
    previous_hash,
    entry_hash
  )
  values (
    v_actor,
    p_action,
    p_entity_type,
    p_entity_id,
    p_status,
    p_before_json,
    p_after_json,
    p_metadata_json,
    v_previous_hash,
    v_entry_hash
  )
  returning id into v_log_id;

  return v_log_id;
end;
$$;

alter table public.user_profiles enable row level security;
alter table public.permission_actions enable row level security;
alter table public.user_permission_overrides enable row level security;
alter table public.action_logs enable row level security;

create policy "authenticated users read own profile"
on public.user_profiles
for select
to authenticated
using (id = auth.uid());

create policy "authenticated users read permission catalog"
on public.permission_actions
for select
to authenticated
using (true);

create policy "authenticated users read own overrides"
on public.user_permission_overrides
for select
to authenticated
using (user_id = auth.uid());

create policy "authenticated users read own action logs"
on public.action_logs
for select
to authenticated
using (actor_user_id = auth.uid());

revoke all on function public.log_action(text, text, text, text, jsonb, jsonb, jsonb) from public;
grant execute on function public.log_action(text, text, text, text, jsonb, jsonb, jsonb) to authenticated;

insert into public.permission_actions(action_key, module, description, default_allowed, sort_order)
values
  ('system.admin', 'sistema', 'Administrar configuracoes gerais do sistema', true, 10),
  ('security.manage_users', 'seguranca', 'Criar e manter usuarios', true, 20),
  ('security.manage_permissions', 'seguranca', 'Definir alcadas e permissoes', true, 30),
  ('comercial.manage', 'comercial', 'Operar pedidos, clientes e faturamento', true, 100),
  ('estoque.manage', 'estoque', 'Operar entradas, saidas e saldos de estoque', true, 200),
  ('producao.manage', 'producao', 'Operar fichas, lotes e ordens de producao', true, 300),
  ('expedicao.manage', 'expedicao', 'Operar romaneio, cargas e entregas', true, 400),
  ('audit.view', 'auditoria', 'Ver auditorias e reconciliacoes', true, 500)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order;
