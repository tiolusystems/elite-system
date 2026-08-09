\set ON_ERROR_STOP on

begin;

do $security_admin_email_change_smoke$
declare
  v_user uuid := '00000000-0000-4000-8000-000000000481';
  v_admin uuid := '00000000-0000-4000-8000-000000000482';
  v_request_id uuid;
  v_approved_email text := 'approved-email-change@validation.elite.com.br';
  v_returned_email text;
  v_status text;
  v_event_count integer;
begin
  insert into auth.users(id, email, email_confirmed_at)
  values
    (v_user, 'current-email-change@validation.elite.com.br', now()),
    (v_admin, 'admin-email-change@validation.elite.com.br', now())
  on conflict (id) do update set
    email = excluded.email,
    email_confirmed_at = excluded.email_confirmed_at;

  insert into public.user_profiles(id, display_name, role, status)
  values
    (v_user, 'Email Change User Smoke', 'comercial', 'active'),
    (v_admin, 'Email Change Admin Smoke', 'admin', 'active')
  on conflict (id) do update set
    display_name = excluded.display_name,
    role = excluded.role,
    status = excluded.status;

  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  select actor.id, action.action_key, true, v_admin
    from (values (v_user), (v_admin)) actor(id)
    cross join public.permission_actions action
  on conflict (user_id, action_key) do update set
    allowed = excluded.allowed,
    updated_by = excluded.updated_by;

  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);

  if public.current_system_environment() = 'unconfigured' then
    perform public.set_system_runtime_environment(
      'test',
      'test_reset',
      'Smoke do fluxo administrativo de troca de email'
    );
  elsif public.current_system_environment() <> 'test' then
    raise exception 'email change smoke requires unconfigured or test environment';
  end if;

  perform set_config('request.jwt.claim.sub', v_user::text, true);
  v_request_id := public.request_security_own_email_change('lost_access', null);

  select request_row.status
    into v_status
    from public.security_email_change_requests request_row
   where request_row.id = v_request_id;

  if v_status <> 'pending_admin' then
    raise exception 'user request did not enter pending_admin';
  end if;
  if exists (
    select 1
      from public.security_email_change_requests request_row
     where request_row.id = v_request_id
       and request_row.new_email is not null
  ) then
    raise exception 'user supplied an email before administrator review';
  end if;

  begin
    perform public.review_security_email_change_request(
      v_request_id,
      'approve',
      v_approved_email,
      'Unauthorized review attempt'
    );
    raise exception 'non-admin review guard missing';
  exception
    when others then
      if sqlerrm = 'non-admin review guard missing'
         or sqlerrm not like '%system administrator role%required%' then
        raise;
      end if;
  end;

  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform public.review_security_email_change_request(
    v_request_id,
    'approve',
    v_approved_email,
    'Address checked by system administrator'
  );

  select request_row.status
    into v_status
    from public.security_email_change_requests request_row
   where request_row.id = v_request_id;

  if v_status <> 'approved' then
    raise exception 'administrator review did not approve request';
  end if;

  perform set_config('request.jwt.claim.sub', v_user::text, true);
  select approved.new_email
    into v_returned_email
    from public.get_security_approved_own_email_change() approved;

  if v_returned_email is distinct from v_approved_email then
    raise exception 'dispatch did not return the administrator-approved email';
  end if;

  update auth.users
     set email_change = v_approved_email,
         email_change_sent_at = now()
   where id = v_user;

  perform public.mark_security_email_change_confirmation_pending(v_request_id);

  update auth.users
     set email = v_approved_email,
         email_change = '',
         email_confirmed_at = now()
   where id = v_user;

  perform public.complete_security_email_change_request();

  select request_row.status
    into v_status
    from public.security_email_change_requests request_row
   where request_row.id = v_request_id;

  if v_status <> 'completed' then
    raise exception 'confirmed email change request was not completed';
  end if;

  select count(*)
    into v_event_count
    from public.security_email_change_request_events event_row
   where event_row.request_id = v_request_id;

  if v_event_count <> 4 then
    raise exception 'expected 4 email change events, found %', v_event_count;
  end if;

  begin
    update public.security_email_change_request_events
       set metadata_json = '{}'::jsonb
     where request_id = v_request_id;
    raise exception 'append-only guard missing';
  exception
    when others then
      if sqlerrm = 'append-only guard missing'
         or sqlerrm not like '%append-only%' then
        raise;
      end if;
  end;

  if has_function_privilege(
    'authenticated',
    'public.authorize_security_own_email_change(text)',
    'EXECUTE'
  ) then
    raise exception 'legacy direct email change authorization remains executable';
  end if;

  raise notice 'PG_VALIDATE_0048_ADMIN_EMAIL_CHANGE_WORKFLOW_OK';
end;
$security_admin_email_change_smoke$;

rollback;
