\set ON_ERROR_STOP on

do $setup$
declare
  v_zero_actor uuid := '00000000-0000-4000-8000-000000000037';
  v_scope_modules text[] := array[
    'cadastros',
    'estoque',
    'estoque_mp',
    'estoque_pi',
    'pcp',
    'faturamento',
    'financeiro',
    'pedidos',
    'romaneios',
    'importacao',
    'metas'
  ];
begin
  insert into auth.users(id)
  values (v_zero_actor)
  on conflict (id) do nothing;

  insert into public.user_profiles(id, display_name, role, status)
  values (v_zero_actor, 'Zero Grant Sweep Actor', 'auditoria', 'active')
  on conflict (id) do update
    set display_name = excluded.display_name,
        role = excluded.role,
        status = excluded.status;

  delete from public.user_permission_overrides
   where user_id = v_zero_actor;

  update public.permission_actions
     set default_allowed = false
   where module = any(v_scope_modules)
      or action_key ~ '^(cadastros|estoque|pcp|faturamento|financeiro|pedidos|romaneios|importacao|metas)\.';
end;
$setup$;

do $sweep$
declare
  v_zero_actor uuid := '00000000-0000-4000-8000-000000000037';
  v_action_pattern text := '^(cadastros|estoque|pcp|faturamento|financeiro|pedidos|romaneios|importacao|metas)\.';
  v_target record;
  v_call_sql text;
  v_denied_action_key text;
  v_denied_log_before bigint;
  v_denied_log_after bigint;
  v_table_count_diff integer;
  v_targets_count integer := 0;
  v_denied_count integer := 0;
  v_failures jsonb := '[]'::jsonb;
begin
  perform set_config('request.jwt.claim.sub', v_zero_actor::text, true);

  create temporary table zero_grant_table_counts_before as
  select
    cls.oid,
    format('%I.%I', nsp.nspname, cls.relname) as table_name,
    (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', nsp.nspname, cls.relname), false, true, '')))[1]::text::bigint as row_count
  from pg_class cls
  join pg_namespace nsp on nsp.oid = cls.relnamespace
  where nsp.nspname = 'public'
    and cls.relkind in ('r', 'p')
    and cls.relname not in (
      'action_logs',
      'permission_actions',
      'user_profiles',
      'user_permission_overrides'
    );

  create temporary table zero_grant_sweep_targets as
  with funcs as (
    select
      proc.oid,
      proc.proname,
      pg_get_function_identity_arguments(proc.oid) as identity_args,
      pg_get_functiondef(proc.oid) as definition,
      (
        select string_agg(
          case typ.typname
            when 'int2' then '0::smallint'
            when 'int4' then '0::integer'
            when 'int8' then '0::bigint'
            when 'numeric' then '0::numeric'
            when 'float4' then '0::real'
            when 'float8' then '0::double precision'
            when 'bool' then 'false::boolean'
            when 'date' then 'current_date::date'
            when 'timestamp' then 'clock_timestamp()::timestamp'
            when 'timestamptz' then 'clock_timestamp()::timestamptz'
            when 'uuid' then quote_literal('00000000-0000-4000-8000-000000000037') || '::uuid'
            when 'jsonb' then quote_literal('{}') || '::jsonb'
            when 'json' then quote_literal('{}') || '::json'
            else quote_literal('__zero_grant_sweep__') || '::' || format_type(arg_type, null)
          end,
          ', ' order by arg_ord
        )
        from unnest(proc.proargtypes::oid[]) with ordinality as args(arg_type, arg_ord)
        join pg_type typ on typ.oid = args.arg_type
      ) as dummy_args,
      coalesce(
        (
          select array_agg(distinct match[1] order by match[1])
          from regexp_matches(
            pg_get_functiondef(proc.oid),
            '''((?:cadastros|estoque|pcp|faturamento|financeiro|pedidos|romaneios|importacao|metas)\.[a-z0-9_.]+)''',
            'g'
          ) as match
        ),
        '{}'::text[]
      ) as action_keys
    from pg_proc proc
    join pg_namespace nsp on nsp.oid = proc.pronamespace
    where nsp.nspname = 'public'
      and proc.prokind = 'f'
  )
  select *
  from funcs
  where action_keys <> '{}'::text[]
    and (
      definition ilike '%begin_audited_rpc(%'
      or definition ilike '%require_current_user_permission(%'
    )
    and proname not in (
      'begin_audited_rpc',
      'can_current_user',
      'current_actor_id',
      'log_action',
      'log_audit_event',
      'log_audited_rpc_change',
      'log_permission_denied',
      'log_rpc_failed',
      'require_current_user_permission'
    )
    and proname not like 'list_security_%'
    and proname not like '%security_%'
    and proname not like '%_impl_0037'
  order by proname, identity_args;

  select count(*) into v_targets_count from zero_grant_sweep_targets;

  if v_targets_count = 0 then
    raise exception 'zero grant sweep discovered no RPC targets';
  end if;

  for v_target in
    select * from zero_grant_sweep_targets
  loop
    v_call_sql := format(
      'select public.%I(%s)',
      v_target.proname,
      coalesce(v_target.dummy_args, '')
    );

    begin
      execute v_call_sql;
      v_failures := v_failures || jsonb_build_array(jsonb_build_object(
        'function', v_target.proname,
        'identity_args', v_target.identity_args,
        'failure', 'rpc_returned_success_for_zero_grant_actor',
        'action_keys', v_target.action_keys
      ));
    exception
      when others then
        if sqlerrm like 'not allowed:%' then
          v_denied_action_key := trim(substring(sqlerrm from length('not allowed:') + 1));

          if v_denied_action_key !~ v_action_pattern then
            v_failures := v_failures || jsonb_build_array(jsonb_build_object(
              'function', v_target.proname,
              'identity_args', v_target.identity_args,
              'failure', 'denied_action_key_outside_sweep_scope',
              'message', sqlerrm
            ));
          elsif not (v_denied_action_key = any(v_target.action_keys)) then
            v_failures := v_failures || jsonb_build_array(jsonb_build_object(
              'function', v_target.proname,
              'identity_args', v_target.identity_args,
              'failure', 'denied_action_key_not_declared_in_rpc_body',
              'message', sqlerrm,
              'declared_action_keys', v_target.action_keys
            ));
          else
            select count(*)
              into v_denied_log_before
              from public.action_logs
             where actor_user_id = v_zero_actor
               and status = 'denied'
               and action_key = v_denied_action_key
               and origin = 'zero_grant_sweep';

            perform public.log_permission_denied(
              v_denied_action_key,
              'zero_grant_sweep',
              jsonb_build_object(
                'sweep', 'zero_grant_default_deny',
                'function', v_target.proname,
                'identity_args', v_target.identity_args
              )
            );

            select count(*)
              into v_denied_log_after
              from public.action_logs
             where actor_user_id = v_zero_actor
               and status = 'denied'
               and action_key = v_denied_action_key
               and origin = 'zero_grant_sweep';

            if v_denied_log_after <> v_denied_log_before + 1 then
              v_failures := v_failures || jsonb_build_array(jsonb_build_object(
                'function', v_target.proname,
                'identity_args', v_target.identity_args,
                'failure', 'permission_denied_log_not_persisted',
                'action_key', v_denied_action_key
              ));
            else
              v_denied_count := v_denied_count + 1;
            end if;
          end if;
        else
          v_failures := v_failures || jsonb_build_array(jsonb_build_object(
            'function', v_target.proname,
            'identity_args', v_target.identity_args,
            'failure', 'unexpected_exception_before_permission_denial',
            'message', sqlerrm,
            'action_keys', v_target.action_keys
          ));
        end if;
    end;

    select count(*)
      into v_table_count_diff
      from zero_grant_table_counts_before before_count
      join pg_class cls on cls.oid = before_count.oid
      join pg_namespace nsp on nsp.oid = cls.relnamespace
     where before_count.row_count <>
       (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', nsp.nspname, cls.relname), false, true, '')))[1]::text::bigint;

    if v_table_count_diff <> 0 then
      v_failures := v_failures || jsonb_build_array(jsonb_build_object(
        'function', v_target.proname,
        'identity_args', v_target.identity_args,
        'failure', 'non_audit_table_count_changed_after_denied_call'
      ));
    end if;
  end loop;

  if jsonb_array_length(v_failures) > 0 then
    raise exception 'ZERO_GRANT_SWEEP_FAILED: %', v_failures;
  end if;

  raise notice 'ZERO_GRANT_SWEEP_OK: targets=%, denied=%, actor=%', v_targets_count, v_denied_count, v_zero_actor;
end;
$sweep$;
