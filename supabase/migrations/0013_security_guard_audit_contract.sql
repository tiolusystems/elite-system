alter table public.action_logs
  add column if not exists domain text,
  add column if not exists action_key text references public.permission_actions(action_key),
  add column if not exists origin text not null default 'database_rpc',
  add column if not exists permission_context jsonb not null default '{}'::jsonb;

create index if not exists idx_action_logs_domain_created_at
  on public.action_logs(domain, created_at desc);

create index if not exists idx_action_logs_action_key_created_at
  on public.action_logs(action_key, created_at desc);

create or replace function public.current_actor_id()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
begin
  v_actor := auth.uid();
  if v_actor is not null and not exists (
    select 1 from public.user_profiles where id = v_actor and status = 'active'
  ) then
    v_actor := null;
  end if;
  return v_actor;
end;
$$;

create or replace function public.can_current_user(p_action_key text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_default_allowed boolean;
  v_override_allowed boolean;
begin
  if nullif(trim(p_action_key), '') is null then
    return false;
  end if;

  v_actor := auth.uid();
  if v_actor is null then
    return false;
  end if;

  if not exists (
    select 1 from public.user_profiles
    where id = v_actor
      and status = 'active'
  ) then
    return false;
  end if;

  select allowed
    into v_override_allowed
    from public.user_permission_overrides
    where user_id = v_actor
      and action_key = trim(p_action_key);

  if found then
    return v_override_allowed;
  end if;

  select default_allowed
    into v_default_allowed
    from public.permission_actions
    where action_key = trim(p_action_key);

  if found then
    return v_default_allowed;
  end if;

  return false;
end;
$$;

create or replace function public.log_audit_event(
  p_domain text,
  p_entity_type text,
  p_entity_id text,
  p_action text,
  p_action_key text default null,
  p_status text default 'success',
  p_before_json jsonb default null,
  p_after_json jsonb default null,
  p_permission_context jsonb default '{}'::jsonb,
  p_origin text default 'database_rpc',
  p_metadata_json jsonb default '{}'::jsonb
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
  v_domain text;
  v_action text;
  v_action_key text;
  v_origin text;
  v_status text;
  v_permission_context jsonb;
  v_metadata_json jsonb;
begin
  v_domain := lower(nullif(trim(p_domain), ''));
  v_action := nullif(trim(p_action), '');
  v_action_key := nullif(trim(p_action_key), '');
  v_origin := coalesce(nullif(trim(p_origin), ''), 'database_rpc');
  v_status := coalesce(nullif(trim(p_status), ''), 'success');
  v_permission_context := coalesce(p_permission_context, '{}'::jsonb);
  v_metadata_json := coalesce(p_metadata_json, '{}'::jsonb);

  if v_domain is null then
    raise exception 'audit domain is required';
  end if;

  if v_action is null then
    raise exception 'audit action is required';
  end if;

  if v_status not in ('success', 'denied', 'failed') then
    raise exception 'invalid audit status: %', v_status;
  end if;

  if v_action_key is not null and not exists (
    select 1 from public.permission_actions where action_key = v_action_key
  ) then
    raise exception 'unknown permission action: %', v_action_key;
  end if;

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
        v_domain,
        v_action,
        coalesce(v_action_key, ''),
        coalesce(p_entity_type, ''),
        coalesce(p_entity_id, ''),
        v_status,
        coalesce(p_before_json::text, ''),
        coalesce(p_after_json::text, ''),
        v_permission_context::text,
        v_origin,
        v_metadata_json::text,
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
    entry_hash,
    domain,
    action_key,
    origin,
    permission_context
  )
  values (
    v_actor,
    v_action,
    p_entity_type,
    p_entity_id,
    v_status,
    p_before_json,
    p_after_json,
    v_metadata_json,
    v_previous_hash,
    v_entry_hash,
    v_domain,
    v_action_key,
    v_origin,
    v_permission_context
  )
  returning id into v_log_id;

  return v_log_id;
end;
$$;

create or replace function public.require_current_user_permission(p_action_key text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_action_key text;
  v_logged_action_key text;
begin
  v_action_key := nullif(trim(p_action_key), '');

  if not public.can_current_user(v_action_key) then
    select action_key
      into v_logged_action_key
      from public.permission_actions
      where action_key = v_action_key;

    perform public.log_audit_event(
      'seguranca',
      'permission_actions',
      v_action_key,
      'seguranca.permissao_negada',
      v_logged_action_key,
      'denied',
      null,
      jsonb_build_object('action_key', v_action_key),
      jsonb_build_object('alcada_usada', v_action_key, 'decision', 'denied'),
      'database_rpc',
      jsonb_build_object('source', 'require_current_user_permission')
    );
    raise exception 'not allowed: %', v_action_key;
  end if;
end;
$$;

revoke all on function public.log_audit_event(text, text, text, text, text, text, jsonb, jsonb, jsonb, text, jsonb) from public;
revoke all on function public.log_action(text, text, text, text, jsonb, jsonb, jsonb) from public;

grant execute on function public.current_actor_id() to authenticated;
grant execute on function public.can_current_user(text) to authenticated;
grant execute on function public.require_current_user_permission(text) to authenticated;
