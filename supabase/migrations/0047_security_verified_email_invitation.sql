-- Verified email invitation supersedes temporary-password provisioning for new users.
-- Full email addresses remain in Supabase Auth; operational logs store only hashes.

create or replace function public.is_reserved_access_email(p_email text)
returns boolean
language sql
immutable
strict
set search_path = public
as $$
  select split_part(lower(trim(p_email)), '@', 2) ~* '(^|\.)(local|invalid|test)$'
      or split_part(lower(trim(p_email)), '@', 2) in ('example.com', 'example.net', 'example.org');
$$;

comment on function public.is_reserved_access_email(text) is
  'Fonte unica no banco para bloquear dominios ficticios ou reservados em acessos humanos.';

insert into public.permission_actions(
  action_key,
  module,
  description,
  default_allowed,
  sort_order,
  runtime_module_key,
  runtime_access_kind
)
values (
  'security.change_own_email',
  'seguranca',
  'Solicitar alteracao do proprio email com confirmacao',
  true,
  26,
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

create or replace function public.authorize_security_auth_user_provision(
  p_email text,
  p_display_name text,
  p_role text,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_email_hash text;
  v_display_name text;
  v_role text;
  v_status text;
  v_permission_context jsonb;
begin
  v_email := lower(nullif(trim(p_email), ''));
  v_display_name := nullif(trim(p_display_name), '');
  v_role := lower(nullif(trim(p_role), ''));
  v_status := lower(nullif(trim(p_status), ''));

  if v_email is null or v_email !~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'invalid email';
  end if;
  if public.is_reserved_access_email(v_email) then
    raise exception 'fictitious email is not allowed';
  end if;
  if v_display_name is null then
    raise exception 'display name is required';
  end if;
  if v_role not in ('admin', 'comercial', 'producao', 'estoque', 'expedicao', 'auditoria') then
    raise exception 'invalid user role';
  end if;
  if v_status not in ('active', 'inactive') then
    raise exception 'invalid user status';
  end if;

  v_email_hash := encode(extensions.digest(v_email, 'sha256'), 'hex');

  v_permission_context := public.begin_audited_rpc(
    'security.manage_users',
    'seguranca',
    'auth.users',
    'change_type',
    jsonb_build_object(
      'event', 'auth_user_invitation_authorized',
      'email_hash', v_email_hash,
      'provision_mode', 'verified_email_invitation'
    )
  );

  perform public.log_audited_rpc_change(
    'seguranca',
    'auth.users',
    v_email_hash,
    'seguranca.auth_user_invitation_authorized',
    'security.manage_users',
    v_permission_context,
    null,
    jsonb_build_object(
      'email_hash', v_email_hash,
      'display_name', v_display_name,
      'role', v_role,
      'status', v_status,
      'provision_mode', 'verified_email_invitation',
      'contains_credential', false
    ),
    jsonb_build_object(
      'source', 'authorize_security_auth_user_provision',
      'credential_logged', false
    )
  );

  return jsonb_build_object(
    'email_hash', v_email_hash,
    'provision_mode', 'verified_email_invitation'
  );
end;
$$;

comment on function public.authorize_security_auth_user_provision(text, text, text, text) is
  'Autoriza convite de usuario por email verificavel sem receber ou gravar credencial.';

create or replace function public.record_security_auth_user_invitation_sent(
  p_user_id uuid,
  p_email text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_email_hash text;
  v_permission_context jsonb;
  v_log_id bigint;
begin
  v_email := lower(nullif(trim(p_email), ''));

  if p_user_id is null then
    raise exception 'target user id is required';
  end if;
  if v_email is null or v_email !~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'invalid email';
  end if;
  if not exists (
    select 1
      from auth.users auth_user
     where auth_user.id = p_user_id
       and lower(auth_user.email) = v_email
       and auth_user.email_confirmed_at is null
  ) then
    raise exception 'pending auth invitation must exist before recording delivery';
  end if;

  v_email_hash := encode(extensions.digest(v_email, 'sha256'), 'hex');

  v_permission_context := public.begin_audited_rpc(
    'security.manage_users',
    'seguranca',
    'auth.users',
    'change_type',
    jsonb_build_object(
      'event', 'auth_user_invitation_sent',
      'email_hash', v_email_hash,
      'target_user_id', p_user_id,
      'provision_mode', 'verified_email_invitation'
    )
  );

  v_log_id := public.log_audited_rpc_change(
    'seguranca',
    'auth.users',
    p_user_id::text,
    'seguranca.auth_user_invitation_sent',
    'security.manage_users',
    v_permission_context,
    null,
    jsonb_build_object(
      'target_user_id', p_user_id,
      'email_hash', v_email_hash,
      'email_confirmed', false,
      'provision_mode', 'verified_email_invitation',
      'contains_credential', false
    ),
    jsonb_build_object(
      'source', 'record_security_auth_user_invitation_sent',
      'credential_logged', false
    )
  );

  return v_log_id;
end;
$$;

comment on function public.record_security_auth_user_invitation_sent(uuid, text) is
  'Registra envio de convite sem gravar email completo, link, token ou credencial.';

create or replace function public.authorize_security_own_email_change(
  p_new_email text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_email text;
  v_email_hash text;
  v_permission_context jsonb;
begin
  v_actor := public.current_actor_id();
  v_email := lower(nullif(trim(p_new_email), ''));

  if v_actor is null then
    raise exception 'active user profile is required';
  end if;
  if v_email is null or v_email !~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'invalid email';
  end if;
  if public.is_reserved_access_email(v_email) then
    raise exception 'fictitious email is not allowed';
  end if;

  v_email_hash := encode(extensions.digest(v_email, 'sha256'), 'hex');
  v_permission_context := public.begin_audited_rpc(
    'security.change_own_email',
    'seguranca',
    'auth.users',
    'change_type',
    jsonb_build_object(
      'event', 'own_email_change_authorized',
      'target_user_id', v_actor,
      'new_email_hash', v_email_hash
    )
  );

  perform public.log_audited_rpc_change(
    'seguranca',
    'auth.users',
    v_actor::text,
    'seguranca.own_email_change_authorized',
    'security.change_own_email',
    v_permission_context,
    null,
    jsonb_build_object(
      'target_user_id', v_actor,
      'new_email_hash', v_email_hash,
      'confirmation_required', true,
      'contains_credential', false
    ),
    jsonb_build_object(
      'source', 'authorize_security_own_email_change',
      'credential_logged', false
    )
  );

  return jsonb_build_object(
    'new_email_hash', v_email_hash,
    'confirmation_required', true
  );
end;
$$;

comment on function public.authorize_security_own_email_change(text) is
  'Autoriza troca do proprio email antes da chamada ao Supabase Auth; registra somente hash.';

create or replace function public.record_security_own_email_change_requested(
  p_new_email text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_email text;
  v_email_hash text;
  v_permission_context jsonb;
begin
  v_actor := public.current_actor_id();
  v_email := lower(nullif(trim(p_new_email), ''));

  if v_actor is null then
    raise exception 'active user profile is required';
  end if;
  if v_email is null or v_email !~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'invalid email';
  end if;
  if public.is_reserved_access_email(v_email) then
    raise exception 'fictitious email is not allowed';
  end if;

  v_email_hash := encode(extensions.digest(v_email, 'sha256'), 'hex');
  v_permission_context := public.begin_audited_rpc(
    'security.change_own_email',
    'seguranca',
    'auth.users',
    'change_type',
    jsonb_build_object(
      'event', 'own_email_change_requested',
      'target_user_id', v_actor,
      'new_email_hash', v_email_hash
    )
  );

  return public.log_audited_rpc_change(
    'seguranca',
    'auth.users',
    v_actor::text,
    'seguranca.own_email_change_requested',
    'security.change_own_email',
    v_permission_context,
    null,
    jsonb_build_object(
      'target_user_id', v_actor,
      'new_email_hash', v_email_hash,
      'confirmation_pending', true,
      'contains_credential', false
    ),
    jsonb_build_object(
      'source', 'record_security_own_email_change_requested',
      'credential_logged', false
    )
  );
end;
$$;

create or replace function public.record_security_own_email_changed()
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_email text;
  v_email_hash text;
  v_confirmed_at timestamptz;
  v_permission_context jsonb;
begin
  v_actor := public.current_actor_id();

  if v_actor is null then
    raise exception 'active user profile is required';
  end if;

  select lower(auth_user.email), auth_user.email_confirmed_at
    into v_email, v_confirmed_at
    from auth.users auth_user
   where auth_user.id = v_actor;

  if v_email is null or v_confirmed_at is null then
    raise exception 'confirmed auth email is required';
  end if;

  v_email_hash := encode(extensions.digest(v_email, 'sha256'), 'hex');
  v_permission_context := public.begin_audited_rpc(
    'security.change_own_email',
    'seguranca',
    'auth.users',
    'change_type',
    jsonb_build_object(
      'event', 'own_email_changed',
      'target_user_id', v_actor,
      'email_hash', v_email_hash
    )
  );

  return public.log_audited_rpc_change(
    'seguranca',
    'auth.users',
    v_actor::text,
    'seguranca.own_email_changed',
    'security.change_own_email',
    v_permission_context,
    null,
    jsonb_build_object(
      'target_user_id', v_actor,
      'email_hash', v_email_hash,
      'email_confirmed', true,
      'confirmed_at', v_confirmed_at,
      'contains_credential', false
    ),
    jsonb_build_object(
      'source', 'record_security_own_email_changed',
      'credential_logged', false
    )
  );
end;
$$;

comment on function public.record_security_own_email_change_requested(text) is
  'Registra solicitacao de troca do proprio email usando somente hash do novo endereco.';
comment on function public.record_security_own_email_changed() is
  'Registra confirmacao da troca do proprio email sem gravar endereco completo ou token.';

revoke all on function public.is_reserved_access_email(text) from public;
revoke all on function public.authorize_security_auth_user_provision(text, text, text, text) from public;
revoke all on function public.record_security_auth_user_invitation_sent(uuid, text) from public;
revoke all on function public.authorize_security_own_email_change(text) from public;
revoke all on function public.record_security_own_email_change_requested(text) from public;
revoke all on function public.record_security_own_email_changed() from public;

grant execute on function public.authorize_security_auth_user_provision(text, text, text, text) to authenticated;
grant execute on function public.record_security_auth_user_invitation_sent(uuid, text) to authenticated;
grant execute on function public.authorize_security_own_email_change(text) to authenticated;
grant execute on function public.record_security_own_email_change_requested(text) to authenticated;
grant execute on function public.record_security_own_email_changed() to authenticated;
