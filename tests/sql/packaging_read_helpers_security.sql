\set ON_ERROR_STOP on

begin;

do $metadata$
declare
  v_function regprocedure;
  v_owner text;
  v_view text;
begin
  foreach v_function in array array[
    'public.current_cad_embalagem_versao_review_status(bigint)'::regprocedure,
    'public.is_cad_embalagem_componente_active(bigint)'::regprocedure
  ] loop
    select pg_get_userbyid(proc.proowner)
      into v_owner
      from pg_proc proc
     where proc.oid = v_function;

    if v_owner <> 'postgres' then
      raise exception 'private packaging helper % has unexpected owner %', v_function, v_owner;
    end if;
    if has_function_privilege('authenticated', v_function, 'EXECUTE')
       or has_function_privilege('anon', v_function, 'EXECUTE') then
      raise exception 'API role retained EXECUTE on private packaging helper %', v_function;
    end if;
    if exists (
      select 1
      from pg_proc proc
      cross join lateral aclexplode(coalesce(proc.proacl, acldefault('f', proc.proowner))) acl
      where proc.oid = v_function
        and acl.grantee = 0
        and acl.privilege_type = 'EXECUTE'
    ) then
      raise exception 'PUBLIC retained EXECUTE on private packaging helper %', v_function;
    end if;
  end loop;

  foreach v_view in array array[
    'cad_embalagem_configuracoes_atuais',
    'cad_embalagem_componentes_atuais'
  ] loop
    if not exists (
      select 1
      from pg_class relation
      join pg_namespace namespace on namespace.oid = relation.relnamespace
      where namespace.nspname = 'public'
        and relation.relname = v_view
        and relation.relkind = 'v'
        and 'security_invoker=true' = any(coalesce(relation.reloptions, array[]::text[]))
    ) then
      raise exception 'packaging view % is not security_invoker', v_view;
    end if;
    if not has_table_privilege('authenticated', format('public.%I', v_view), 'SELECT') then
      raise exception 'authenticated lost SELECT on packaging view %', v_view;
    end if;
  end loop;

  if pg_get_viewdef('public.cad_embalagem_configuracoes_atuais'::regclass, true)
       like '%current_cad_embalagem_versao_review_status%'
     or pg_get_viewdef('public.cad_embalagem_componentes_atuais'::regclass, true)
       like '%is_cad_embalagem_componente_active%'
     or pg_get_viewdef('public.cad_embalagem_componentes_atuais'::regclass, true)
       like '%current_cad_embalagem_versao_review_status%' then
    raise exception 'authenticated packaging view still depends on a private helper';
  end if;
end;
$metadata$;

do $actor$
declare
  v_actor constant uuid := '00000000-0000-4000-8000-000000000139';
begin
  insert into auth.users(id) values (v_actor) on conflict (id) do nothing;
  insert into public.user_profiles(id, display_name, role, status)
  values (v_actor, 'Packaging Read Helper Smoke', 'auditoria', 'active')
  on conflict (id) do update
    set display_name = excluded.display_name,
        role = excluded.role,
        status = excluded.status;
end;
$actor$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000139', true);

select count(*) from public.cad_embalagem_configuracoes_atuais;
select count(*) from public.cad_embalagem_componentes_atuais;

do $private_helpers$
begin
  begin
    perform public.current_cad_embalagem_versao_review_status(1);
    raise exception 'authenticated invoked private review-status helper';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.is_cad_embalagem_componente_active(1);
    raise exception 'authenticated invoked private active-component helper';
  exception
    when insufficient_privilege then null;
  end;
end;
$private_helpers$;

reset role;
rollback;

\echo ELITE_PACKAGING_READ_HELPERS_SECURITY_OK
