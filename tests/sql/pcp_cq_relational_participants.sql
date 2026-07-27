begin;

do $contract$
begin
  if not exists (
    select 1
      from pg_constraint
     where conrelid = 'public.pcp_op_cq_participantes'::regclass
       and conname = 'pcp_cq_participantes_papel_check'
       and pg_get_constraintdef(oid) like '%responsavel_cq%'
       and pg_get_constraintdef(oid) like '%responsavel_liberacao%'
  ) then
    raise exception 'CQ participant roles were not extended';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.finalizar_pcp_op_relacional(bigint,jsonb,text,numeric,numeric,numeric,numeric,numeric,bigint,bigint,bigint[],bigint,bigint,text)',
    'EXECUTE'
  ) then
    raise exception 'authenticated cannot execute relational OP finalization';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.finalizar_pcp_op(bigint,jsonb,text,numeric,numeric,numeric,numeric,numeric,text,text,jsonb,text)',
    'EXECUTE'
  ) then
    raise exception 'authenticated can still execute legacy text participant finalization';
  end if;

  if has_function_privilege(
    'anon',
    'public.finalizar_pcp_op_relacional(bigint,jsonb,text,numeric,numeric,numeric,numeric,numeric,bigint,bigint,bigint[],bigint,bigint,text)',
    'EXECUTE'
  ) or has_function_privilege(
    'public',
    'public.finalizar_pcp_op_relacional(bigint,jsonb,text,numeric,numeric,numeric,numeric,numeric,bigint,bigint,bigint[],bigint,bigint,text)',
    'EXECUTE'
  ) then
    raise exception 'anon or PUBLIC can execute relational OP finalization';
  end if;
end;
$contract$;

do $inactive_person$
declare
  v_actor uuid := '00000000-0000-4000-8000-000000000114';
  v_person_id bigint;
begin
  insert into auth.users(id) values (v_actor) on conflict (id) do nothing;
  insert into public.user_profiles(id, display_name, role, status)
  values (v_actor, 'CQ relational contract actor', 'admin', 'active')
  on conflict (id) do update set status = 'active';
  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  values
    (v_actor, 'pcp.op.finish', true, v_actor),
    (v_actor, 'system.admin', true, v_actor)
  on conflict (user_id, action_key) do update set allowed = true, updated_by = excluded.updated_by;
  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  if public.current_system_environment() = 'unconfigured' then
    perform public.set_system_runtime_environment(
      'test',
      'test_reset',
      'CQ relational participant contract in disposable environment'
    );
  end if;

  insert into public.cad_pessoas_comerciais(nome, nome_norm, papeis_json, status)
  values (
    'HOM CQ Pessoa Inativa',
    'HOM CQ PESSOA INATIVA',
    '["funcionario"]'::jsonb,
    'inactive'
  )
  returning id into v_person_id;

  begin
    perform public.finalizar_pcp_op_relacional(
      -1,
      '[]'::jsonb,
      'aprovado',
      7,
      1,
      1,
      1,
      20,
      v_person_id,
      v_person_id,
      array[v_person_id],
      v_person_id,
      v_person_id,
      null
    );
    raise exception 'inactive participant was accepted';
  exception
    when others then
      if sqlerrm not like '%active registered people%' then
        raise;
      end if;
  end;

  delete from public.cad_pessoas_comerciais where id = v_person_id;
end;
$inactive_person$;

rollback;
