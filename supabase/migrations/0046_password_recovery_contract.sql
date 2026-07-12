-- Password recovery and voluntary password changes reuse Supabase Auth.
-- The application audit records only the change fact, never credentials or recovery secrets.

update public.permission_actions
   set description = 'Alterar a propria senha'
 where action_key = 'security.change_own_password';

create or replace function public.record_security_own_password_changed()
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_permission_context jsonb;
  v_log_id bigint;
  v_session_id text;
begin
  v_actor := public.current_actor_id();

  if v_actor is null then
    raise exception 'active user profile is required';
  end if;

  v_session_id := nullif(auth.jwt() ->> 'session_id', '');

  v_permission_context := public.begin_audited_rpc(
    'security.change_own_password',
    'seguranca',
    'auth.users',
    'change_type',
    jsonb_build_object(
      'event', 'own_password_changed',
      'target_user_id', v_actor,
      'auth_session_id', v_session_id,
      'credential_logged', false
    )
  );

  v_log_id := public.log_audited_rpc_change(
    'seguranca',
    'auth.users',
    v_actor::text,
    'seguranca.own_password_changed',
    'security.change_own_password',
    v_permission_context,
    null,
    jsonb_build_object(
      'target_user_id', v_actor,
      'temporary_password_bootstrap', false,
      'contains_password', false
    ),
    jsonb_build_object(
      'source', 'record_security_own_password_changed',
      'auth_session_id', v_session_id,
      'credential_logged', false
    )
  );

  return v_log_id;
end;
$$;

comment on function public.record_security_own_password_changed() is
  'Registra troca da propria senha, temporaria, voluntaria ou recuperada, sem gravar senha ou segredo de recuperacao.';

revoke all on function public.record_security_own_password_changed() from public;
grant execute on function public.record_security_own_password_changed() to authenticated;
