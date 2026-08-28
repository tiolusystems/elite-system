\set ON_ERROR_STOP on

do $gate$
declare
  v_table record;
  v_function record;
  v_policy_dependency record;
  v_contract record;
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

  for v_policy_dependency in
    select distinct
           pol.polname as policy_name,
           rel.relname as table_name,
           proc.oid as function_oid,
           proc.oid::regprocedure as function_signature
      from pg_policy pol
      join pg_class rel on rel.oid = pol.polrelid
      join pg_namespace rel_ns on rel_ns.oid = rel.relnamespace
      join pg_depend dep
        on dep.classid = 'pg_policy'::regclass
       and dep.objid = pol.oid
       and dep.refclassid = 'pg_proc'::regclass
      join pg_proc proc on proc.oid = dep.refobjid
      join pg_namespace proc_ns on proc_ns.oid = proc.pronamespace
     where rel_ns.nspname = 'public'
       and proc_ns.nspname = 'public'
       and (
         0::oid = any(pol.polroles)
         or (select oid from pg_roles where rolname = 'authenticated') = any(pol.polroles)
       )
  loop
    if not has_function_privilege('authenticated', v_policy_dependency.function_oid, 'EXECUTE') then
      raise exception 'authenticated policy %.% depends on non-executable function %',
        v_policy_dependency.table_name,
        v_policy_dependency.policy_name,
        v_policy_dependency.function_signature;
    end if;
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
      select *
        into v_contract
        from public.security_sql_surface_contracts contract
       where replace(contract.function_signature, 'public.', '') =
             v_function.signature::text;
      if found and v_contract.surface = 'GOVERNED_READ_INVOKER_RLS' then
        if v_function.prosecdef or not v_contract.read_only
           or not v_contract.rls_preserved or not v_contract.explicit_contract then
          raise exception 'governed read contract is invalid: %', v_function.signature;
        end if;
        if v_function.definition ~* '\m(insert|update|delete|truncate|merge|perform)\M' then
          raise exception 'governed read contains a write operation: %', v_function.signature;
        end if;
        if v_contract.authorization_marker <> 'RLS'
           and v_function.definition !~* 'current_actor_id\(\)' then
          raise exception 'governed read lacks actor marker: %', v_function.signature;
        end if;
        if exists (
          select 1 from unnest(v_contract.dependency_tables) dependency(table_name)
          left join pg_class dependency_class
            on dependency_class.relname = dependency.table_name
           and dependency_class.relnamespace = 'public'::regnamespace
          where dependency_class.oid is null or not dependency_class.relrowsecurity
        ) then
          raise exception 'governed read dependency lacks RLS: %', v_function.signature;
        end if;
      elsif found and v_contract.surface = 'READ_SUPPORT_HELPER' then
        if v_function.prosecdef or v_function.definition ~* '\m(insert|update|delete|truncate|merge|perform)\M' then
          raise exception 'read support helper is not invoker read-only: %', v_function.signature;
        end if;
      elsif found and v_contract.surface in ('GOVERNED_SCOPE_HELPER', 'GOVERNED_RPC_DEFINER') then
        if not v_contract.explicit_contract or not v_contract.read_only then
          raise exception 'governed definer surface lacks a read-only explicit contract: %', v_function.signature;
        end if;
        if not v_function.prosecdef then
          raise exception 'governed definer surface is not SECURITY DEFINER: %', v_function.signature;
        end if;
        if not exists (
          select 1 from unnest(coalesce(v_function.proconfig, array[]::text[])) config
          where lower(config) ~ '^search_path\s*=\s*public$'
        ) then
          raise exception 'governed definer surface lacks fixed search_path: %', v_function.signature;
        end if;
        if v_function.definition !~* v_contract.authorization_marker then
          raise exception 'governed definer surface lacks declared guard: %', v_function.signature;
        end if;
        if v_function.definition ~* '\\m(insert|update|delete|truncate|merge)\\M' then
          raise exception 'governed definer surface contains a write operation: %', v_function.signature;
        end if;
        if v_contract.rls_preserved and exists (
          select 1
            from unnest(v_contract.dependency_tables) dependency(table_name)
            left join pg_class dependency_class
              on dependency_class.relname = dependency.table_name
             and dependency_class.relnamespace = 'public'::regnamespace
           where dependency_class.oid is null or not dependency_class.relrowsecurity
        ) then
          raise exception 'governed definer read dependency lacks RLS: %', v_function.signature;
        end if;
      else
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
