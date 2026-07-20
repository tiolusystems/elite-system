\set ON_ERROR_STOP on

do $gate$
declare
  v_table record;
  v_function record;
  v_privilege text;
begin
  for v_table in
    select c.oid, c.relname, c.relrowsecurity
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relkind in ('r', 'p')
  loop
    if not v_table.relrowsecurity then
      raise exception 'RLS disabled on public table %', v_table.relname;
    end if;

    if exists (
      select 1
        from pg_policies
       where schemaname = 'public'
         and tablename = v_table.relname
         and upper(cmd) in ('ALL', 'INSERT', 'UPDATE', 'DELETE')
    ) then
      raise exception 'write-capable policy survived on public table %', v_table.relname;
    end if;

    foreach v_privilege in array array['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']
    loop
      if has_table_privilege('anon', v_table.oid, v_privilege) then
        raise exception 'anon retains % on public table %', v_privilege, v_table.relname;
      end if;
      if has_table_privilege('authenticated', v_table.oid, v_privilege) then
        raise exception 'authenticated retains % on public table %', v_privilege, v_table.relname;
      end if;
    end loop;
  end loop;

  for v_function in
    select p.oid, p.oid::regprocedure as signature, p.prosecdef, p.proconfig,
           pg_get_functiondef(p.oid) as definition
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
  loop
    if has_function_privilege('anon', v_function.oid, 'EXECUTE') then
      raise exception 'anon retains EXECUTE on public function %', v_function.signature;
    end if;

    if exists (
      select 1
        from aclexplode(coalesce(
          (select proacl from pg_proc where oid = v_function.oid),
          acldefault('f', (select proowner from pg_proc where oid = v_function.oid))
        )) acl
       where acl.grantee = 0
         and acl.privilege_type = 'EXECUTE'
    ) then
      raise exception 'PUBLIC retains EXECUTE on public function %', v_function.signature;
    end if;

    if has_function_privilege('authenticated', v_function.oid, 'EXECUTE') then
      if not v_function.prosecdef then
        raise exception 'authenticated RPC is not SECURITY DEFINER: %', v_function.signature;
      end if;
      if not exists (
        select 1
          from unnest(coalesce(v_function.proconfig, array[]::text[])) config
         where lower(config) ~ '^search_path\s*=\s*public$'
      ) then
        raise exception 'authenticated RPC lacks fixed search_path: %', v_function.signature;
      end if;
      if v_function.definition !~* '(begin_audited_rpc|require_current_user_permission|require_current_user_admin_role|require_current_user_security_admin|can_current_user|auth\.uid\(\)|current_actor_id\(\)|registrar_fin_recebimento_alocado\(|log_audit_event\()' then
        raise exception 'authenticated RPC lacks an apparent permission guard: %', v_function.signature;
      end if;
    end if;
  end loop;

  if exists (
    select 1
      from pg_default_acl d
      left join pg_namespace n on n.oid = d.defaclnamespace
      cross join lateral aclexplode(d.defaclacl) acl
     where (n.nspname = 'public' or d.defaclnamespace = 0)
       and pg_get_userbyid(d.defaclrole) = 'postgres'
       and (
         (d.defaclobjtype = 'r' and acl.privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'))
         or (d.defaclobjtype = 'f' and acl.privilege_type = 'EXECUTE')
         or (d.defaclobjtype = 'S' and acl.privilege_type in ('SELECT', 'UPDATE', 'USAGE'))
       )
       and (acl.grantee = 0 or pg_get_userbyid(acl.grantee) in ('anon', 'authenticated'))
  ) then
    raise exception 'unsafe postgres-owned future default privileges survived for API roles';
  end if;
end;
$gate$;

\echo ELITE_SECURITY_ZERO_DIRECT_WRITE_GATE_OK
