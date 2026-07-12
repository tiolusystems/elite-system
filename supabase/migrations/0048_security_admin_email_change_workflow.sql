-- Users request an email change; a system administrator chooses the target address.
-- The authenticated user can only dispatch the exact address approved by the administrator.

update public.permission_actions
   set description = 'Legado desativado: troca direta do proprio email',
       default_allowed = false
 where action_key = 'security.change_own_email';

insert into public.permission_actions(
  action_key,
  module,
  description,
  default_allowed,
  sort_order,
  runtime_module_key,
  runtime_access_kind
)
values
  (
    'security.email_change.request',
    'seguranca',
    'Solicitar revisao administrativa para troca do proprio email',
    true,
    27,
    'seguranca',
    'write'
  ),
  (
    'security.email_change.review',
    'seguranca',
    'Aprovar ou rejeitar troca de email como administrador do sistema',
    true,
    28,
    'seguranca',
    'write'
  ),
  (
    'security.email_change.dispatch_approved',
    'seguranca',
    'Enviar confirmacao somente para email previamente aprovado pelo administrador',
    true,
    29,
    'seguranca',
    'write'
  )
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

create table if not exists public.security_email_change_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_profiles(id),
  status text not null default 'pending_admin'
    check (status in ('pending_admin', 'approved', 'confirmation_pending', 'completed', 'rejected')),
  request_reason_code text not null
    check (request_reason_code in ('lost_access', 'registration_correction', 'professional_change', 'other')),
  request_reason_detail text,
  requested_by uuid not null references public.user_profiles(id),
  requested_at timestamptz not null default now(),
  new_email text,
  new_email_hash text,
  reviewed_by uuid references public.user_profiles(id),
  reviewed_at timestamptz,
  review_reason text,
  confirmation_requested_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  check (request_reason_code <> 'other' or nullif(trim(request_reason_detail), '') is not null),
  check (new_email is null or new_email = lower(trim(new_email))),
  check (new_email_hash is null or new_email_hash ~ '^[0-9a-f]{64}$')
);

create unique index if not exists idx_security_email_change_one_active_per_user
  on public.security_email_change_requests(user_id)
  where status in ('pending_admin', 'approved', 'confirmation_pending');

create index if not exists idx_security_email_change_admin_queue
  on public.security_email_change_requests(status, requested_at, user_id);

create table if not exists public.security_email_change_request_events (
  id bigint generated always as identity primary key,
  request_id uuid not null references public.security_email_change_requests(id),
  event_type text not null
    check (event_type in ('requested', 'approved', 'rejected', 'confirmation_dispatched', 'completed')),
  actor_id uuid not null references public.user_profiles(id),
  metadata_json jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (jsonb_typeof(metadata_json) = 'object')
);

create index if not exists idx_security_email_change_events_request
  on public.security_email_change_request_events(request_id, id);

create or replace function public.prevent_security_email_change_event_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'security email change events are append-only';
end;
$$;

drop trigger if exists trg_security_email_change_events_append_only
  on public.security_email_change_request_events;
create trigger trg_security_email_change_events_append_only
before update or delete on public.security_email_change_request_events
for each row execute function public.prevent_security_email_change_event_mutation();

alter table public.security_email_change_requests enable row level security;
alter table public.security_email_change_request_events enable row level security;

revoke all on public.security_email_change_requests from public, anon, authenticated;
revoke all on public.security_email_change_request_events from public, anon, authenticated;

create or replace function public.require_current_user_admin_role()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
begin
  v_actor := public.current_actor_id();

  if v_actor is null or not exists (
    select 1
      from public.user_profiles profile
     where profile.id = v_actor
       and profile.status = 'active'
       and profile.role = 'admin'
       and not profile.is_system_actor
  ) then
    raise exception 'system administrator role is required';
  end if;

  return v_actor;
end;
$$;

create or replace function public.security_email_change_request_snapshot(p_request_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select to_jsonb(request_row) - 'new_email'
    from public.security_email_change_requests request_row
   where request_row.id = p_request_id;
$$;

create or replace function public.request_security_own_email_change(
  p_reason_code text,
  p_reason_detail text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_reason_code text;
  v_reason_detail text;
  v_request_id uuid;
  v_permission_context jsonb;
  v_after jsonb;
begin
  v_reason_code := lower(nullif(trim(p_reason_code), ''));
  v_reason_detail := nullif(trim(p_reason_detail), '');

  if v_reason_code not in ('lost_access', 'registration_correction', 'professional_change', 'other') then
    raise exception 'invalid email change request reason';
  end if;
  if v_reason_code = 'other' and v_reason_detail is null then
    raise exception 'email change request detail is required for other reason';
  end if;

  v_permission_context := public.begin_audited_rpc(
    'security.email_change.request',
    'seguranca',
    'security_email_change_requests',
    'status_transition',
    jsonb_build_object('event', 'email_change_requested')
  );
  v_actor := public.current_actor_id();

  if v_actor is null then
    raise exception 'active user profile is required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_actor::text || ':security_email_change', 0));

  if exists (
    select 1
      from public.security_email_change_requests request_row
     where request_row.user_id = v_actor
       and request_row.status in ('pending_admin', 'approved', 'confirmation_pending')
  ) then
    raise exception 'active email change request already exists';
  end if;

  insert into public.security_email_change_requests(
    user_id,
    request_reason_code,
    request_reason_detail,
    requested_by
  )
  values (
    v_actor,
    v_reason_code,
    v_reason_detail,
    v_actor
  )
  returning id into v_request_id;

  insert into public.security_email_change_request_events(
    request_id,
    event_type,
    actor_id,
    metadata_json
  )
  values (
    v_request_id,
    'requested',
    v_actor,
    jsonb_build_object(
      'reason_code', v_reason_code,
      'reason_detail_present', v_reason_detail is not null,
      'email_supplied_by_user', false
    )
  );

  v_after := public.security_email_change_request_snapshot(v_request_id);

  perform public.log_audited_rpc_change(
    'seguranca',
    'security_email_change_requests',
    v_request_id::text,
    'seguranca.email_change_requested',
    'security.email_change.request',
    v_permission_context,
    null,
    v_after,
    jsonb_build_object(
      'source', 'request_security_own_email_change',
      'target_user_id', v_actor,
      'email_supplied_by_user', false,
      'credential_logged', false
    )
  );

  return v_request_id;
end;
$$;

create or replace function public.review_security_email_change_request(
  p_request_id uuid,
  p_decision text,
  p_new_email text default null,
  p_review_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_decision text;
  v_new_email text;
  v_new_email_hash text;
  v_review_reason text;
  v_request public.security_email_change_requests%rowtype;
  v_permission_context jsonb;
  v_before jsonb;
  v_after jsonb;
begin
  if p_request_id is null then
    raise exception 'email change request id is required';
  end if;

  v_decision := lower(nullif(trim(p_decision), ''));
  v_new_email := lower(nullif(trim(p_new_email), ''));
  v_review_reason := nullif(trim(p_review_reason), '');

  if v_decision not in ('approve', 'reject') then
    raise exception 'invalid email change review decision';
  end if;
  if v_review_reason is null then
    raise exception 'email change review reason is required';
  end if;

  v_actor := public.require_current_user_admin_role();
  v_permission_context := public.begin_audited_rpc(
    'security.email_change.review',
    'seguranca',
    'security_email_change_requests',
    'status_transition',
    jsonb_build_object(
      'event', 'email_change_reviewed',
      'request_id', p_request_id,
      'decision', v_decision
    )
  );

  select *
    into v_request
    from public.security_email_change_requests request_row
   where request_row.id = p_request_id
   for update;

  if v_request.id is null then
    raise exception 'email change request not found';
  end if;
  if v_request.status <> 'pending_admin' then
    raise exception 'email change request is not pending administrator review';
  end if;

  v_before := public.security_email_change_request_snapshot(p_request_id);

  if v_decision = 'approve' then
    if v_new_email is null or v_new_email !~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
      raise exception 'invalid email';
    end if;
    if public.is_reserved_access_email(v_new_email) then
      raise exception 'fictitious email is not allowed';
    end if;
    if exists (
      select 1
        from auth.users auth_user
       where lower(auth_user.email) = v_new_email
         and auth_user.id <> v_request.user_id
    ) then
      raise exception 'email already belongs to another auth user';
    end if;
    if exists (
      select 1
        from auth.users auth_user
       where auth_user.id = v_request.user_id
         and lower(auth_user.email) = v_new_email
    ) then
      raise exception 'new email matches current auth email';
    end if;

    v_new_email_hash := encode(extensions.digest(v_new_email, 'sha256'), 'hex');

    update public.security_email_change_requests
       set status = 'approved',
           new_email = v_new_email,
           new_email_hash = v_new_email_hash,
           reviewed_by = v_actor,
           reviewed_at = now(),
           review_reason = v_review_reason,
           updated_at = now()
     where id = p_request_id;

    insert into public.security_email_change_request_events(
      request_id,
      event_type,
      actor_id,
      metadata_json
    )
    values (
      p_request_id,
      'approved',
      v_actor,
      jsonb_build_object(
        'target_user_id', v_request.user_id,
        'new_email_hash', v_new_email_hash,
        'review_reason_present', true,
        'confirmation_required', true
      )
    );
  else
    update public.security_email_change_requests
       set status = 'rejected',
           reviewed_by = v_actor,
           reviewed_at = now(),
           review_reason = v_review_reason,
           updated_at = now()
     where id = p_request_id;

    insert into public.security_email_change_request_events(
      request_id,
      event_type,
      actor_id,
      metadata_json
    )
    values (
      p_request_id,
      'rejected',
      v_actor,
      jsonb_build_object(
        'target_user_id', v_request.user_id,
        'review_reason_present', true
      )
    );
  end if;

  v_after := public.security_email_change_request_snapshot(p_request_id);

  perform public.log_audited_rpc_change(
    'seguranca',
    'security_email_change_requests',
    p_request_id::text,
    case when v_decision = 'approve'
      then 'seguranca.email_change_approved'
      else 'seguranca.email_change_rejected'
    end,
    'security.email_change.review',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'review_security_email_change_request',
      'target_user_id', v_request.user_id,
      'decision', v_decision,
      'new_email_hash', v_new_email_hash,
      'email_logged', false,
      'credential_logged', false
    )
  );

  return p_request_id;
end;
$$;

create or replace function public.get_security_own_email_change_request()
returns table (
  request_id uuid,
  status text,
  request_reason_code text,
  request_reason_detail text,
  new_email text,
  review_reason text,
  requested_at timestamptz,
  reviewed_at timestamptz,
  confirmation_requested_at timestamptz,
  completed_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
begin
  perform public.require_current_user_permission('security.email_change.request');
  v_actor := public.current_actor_id();

  if v_actor is null then
    raise exception 'active user profile is required';
  end if;

  return query
  select
    request_row.id,
    request_row.status,
    request_row.request_reason_code,
    request_row.request_reason_detail,
    request_row.new_email,
    request_row.review_reason,
    request_row.requested_at,
    request_row.reviewed_at,
    request_row.confirmation_requested_at,
    request_row.completed_at
  from public.security_email_change_requests request_row
  where request_row.user_id = v_actor
  order by request_row.requested_at desc, request_row.id desc
  limit 1;
end;
$$;

create or replace function public.list_security_email_change_requests(
  p_user_id uuid default null,
  p_include_closed boolean default false
)
returns table (
  request_id uuid,
  user_id uuid,
  display_name text,
  status text,
  request_reason_code text,
  request_reason_detail text,
  new_email text,
  review_reason text,
  requested_at timestamptz,
  reviewed_at timestamptz,
  confirmation_requested_at timestamptz,
  completed_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_admin_role();
  perform public.require_current_user_permission('security.email_change.review');

  return query
  select
    request_row.id,
    request_row.user_id,
    profile.display_name,
    request_row.status,
    request_row.request_reason_code,
    request_row.request_reason_detail,
    request_row.new_email,
    request_row.review_reason,
    request_row.requested_at,
    request_row.reviewed_at,
    request_row.confirmation_requested_at,
    request_row.completed_at
  from public.security_email_change_requests request_row
  join public.user_profiles profile on profile.id = request_row.user_id
  where (p_user_id is null or request_row.user_id = p_user_id)
    and (
      coalesce(p_include_closed, false)
      or request_row.status in ('pending_admin', 'approved', 'confirmation_pending')
    )
  order by
    case request_row.status
      when 'pending_admin' then 1
      when 'approved' then 2
      when 'confirmation_pending' then 3
      else 4
    end,
    request_row.requested_at;
end;
$$;

create or replace function public.get_security_approved_own_email_change()
returns table (
  request_id uuid,
  new_email text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
begin
  perform public.require_current_user_permission('security.email_change.dispatch_approved');
  v_actor := public.current_actor_id();

  if v_actor is null then
    raise exception 'active user profile is required';
  end if;

  return query
  select request_row.id, request_row.new_email
    from public.security_email_change_requests request_row
   where request_row.user_id = v_actor
     and request_row.status in ('approved', 'confirmation_pending')
     and request_row.new_email is not null
   order by request_row.reviewed_at desc
   limit 1;
end;
$$;

create or replace function public.mark_security_email_change_confirmation_pending(
  p_request_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_request public.security_email_change_requests%rowtype;
  v_auth_pending_email text;
  v_permission_context jsonb;
  v_before jsonb;
  v_after jsonb;
begin
  if p_request_id is null then
    raise exception 'email change request id is required';
  end if;

  v_permission_context := public.begin_audited_rpc(
    'security.email_change.dispatch_approved',
    'seguranca',
    'security_email_change_requests',
    'status_transition',
    jsonb_build_object(
      'event', 'email_change_confirmation_dispatched',
      'request_id', p_request_id
    )
  );
  v_actor := public.current_actor_id();

  select *
    into v_request
    from public.security_email_change_requests request_row
   where request_row.id = p_request_id
     and request_row.user_id = v_actor
   for update;

  if v_request.id is null or v_request.status not in ('approved', 'confirmation_pending') then
    raise exception 'approved email change request not found';
  end if;

  select lower(nullif(trim(auth_user.email_change), ''))
    into v_auth_pending_email
    from auth.users auth_user
   where auth_user.id = v_actor;

  if v_auth_pending_email is distinct from v_request.new_email then
    raise exception 'auth pending email does not match administrator approval';
  end if;

  v_before := public.security_email_change_request_snapshot(p_request_id);

  update public.security_email_change_requests
     set status = 'confirmation_pending',
         confirmation_requested_at = now(),
         updated_at = now()
   where id = p_request_id;

  insert into public.security_email_change_request_events(
    request_id,
    event_type,
    actor_id,
    metadata_json
  )
  values (
    p_request_id,
    'confirmation_dispatched',
    v_actor,
    jsonb_build_object(
      'new_email_hash', v_request.new_email_hash,
      'approved_by', v_request.reviewed_by,
      'email_logged', false
    )
  );

  v_after := public.security_email_change_request_snapshot(p_request_id);

  perform public.log_audited_rpc_change(
    'seguranca',
    'security_email_change_requests',
    p_request_id::text,
    'seguranca.email_change_confirmation_dispatched',
    'security.email_change.dispatch_approved',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'mark_security_email_change_confirmation_pending',
      'target_user_id', v_actor,
      'new_email_hash', v_request.new_email_hash,
      'approved_by', v_request.reviewed_by,
      'email_logged', false,
      'credential_logged', false
    )
  );

  return p_request_id;
end;
$$;

create or replace function public.complete_security_email_change_request()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_confirmed_email text;
  v_confirmed_at timestamptz;
  v_request public.security_email_change_requests%rowtype;
  v_permission_context jsonb;
  v_before jsonb;
  v_after jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'security.email_change.dispatch_approved',
    'seguranca',
    'security_email_change_requests',
    'status_transition',
    jsonb_build_object('event', 'email_change_completed')
  );
  v_actor := public.current_actor_id();

  select lower(auth_user.email), auth_user.email_confirmed_at
    into v_confirmed_email, v_confirmed_at
    from auth.users auth_user
   where auth_user.id = v_actor;

  select *
    into v_request
    from public.security_email_change_requests request_row
   where request_row.user_id = v_actor
     and request_row.status = 'confirmation_pending'
   order by request_row.confirmation_requested_at desc
   limit 1
   for update;

  if v_request.id is null
     or v_confirmed_at is null
     or v_confirmed_email is distinct from v_request.new_email then
    raise exception 'confirmed administrator-approved email change request not found';
  end if;

  v_before := public.security_email_change_request_snapshot(v_request.id);

  update public.security_email_change_requests
     set status = 'completed',
         completed_at = now(),
         updated_at = now()
   where id = v_request.id;

  insert into public.security_email_change_request_events(
    request_id,
    event_type,
    actor_id,
    metadata_json
  )
  values (
    v_request.id,
    'completed',
    v_actor,
    jsonb_build_object(
      'new_email_hash', v_request.new_email_hash,
      'confirmed_at', v_confirmed_at,
      'email_logged', false
    )
  );

  v_after := public.security_email_change_request_snapshot(v_request.id);

  perform public.log_audited_rpc_change(
    'seguranca',
    'security_email_change_requests',
    v_request.id::text,
    'seguranca.email_change_completed',
    'security.email_change.dispatch_approved',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'complete_security_email_change_request',
      'target_user_id', v_actor,
      'new_email_hash', v_request.new_email_hash,
      'approved_by', v_request.reviewed_by,
      'email_logged', false,
      'credential_logged', false
    )
  );

  return v_request.id;
end;
$$;

comment on table public.security_email_change_requests is
  'Estado governado da solicitacao: usuario pede, administrador define o novo email e o titular apenas confirma.';
comment on table public.security_email_change_request_events is
  'Ledger append-only das solicitacoes, revisoes, envios e confirmacoes de troca de email.';

revoke all on function public.prevent_security_email_change_event_mutation() from public;
revoke all on function public.require_current_user_admin_role() from public;
revoke all on function public.security_email_change_request_snapshot(uuid) from public;
revoke all on function public.request_security_own_email_change(text, text) from public;
revoke all on function public.review_security_email_change_request(uuid, text, text, text) from public;
revoke all on function public.get_security_own_email_change_request() from public;
revoke all on function public.list_security_email_change_requests(uuid, boolean) from public;
revoke all on function public.get_security_approved_own_email_change() from public;
revoke all on function public.mark_security_email_change_confirmation_pending(uuid) from public;
revoke all on function public.complete_security_email_change_request() from public;

revoke all on function public.authorize_security_own_email_change(text) from authenticated;
revoke all on function public.record_security_own_email_change_requested(text) from authenticated;
revoke all on function public.record_security_own_email_changed() from authenticated;

grant execute on function public.request_security_own_email_change(text, text) to authenticated;
grant execute on function public.review_security_email_change_request(uuid, text, text, text) to authenticated;
grant execute on function public.get_security_own_email_change_request() to authenticated;
grant execute on function public.list_security_email_change_requests(uuid, boolean) to authenticated;
grant execute on function public.get_security_approved_own_email_change() to authenticated;
grant execute on function public.mark_security_email_change_confirmation_pending(uuid) to authenticated;
grant execute on function public.complete_security_email_change_request() to authenticated;
