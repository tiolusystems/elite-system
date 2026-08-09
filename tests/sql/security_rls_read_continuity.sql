\set ON_ERROR_STOP on

begin;

do $privileges$
begin
  if not has_function_privilege('authenticated', 'public.current_actor_id()', 'EXECUTE') then
    raise exception 'authenticated cannot execute current_actor_id()';
  end if;
  if has_function_privilege('anon', 'public.current_actor_id()', 'EXECUTE') then
    raise exception 'anon can execute current_actor_id()';
  end if;
  if exists (
    select 1
      from aclexplode(coalesce(
        (select proacl from pg_proc where oid = 'public.current_actor_id()'::regprocedure),
        acldefault('f', (select proowner from pg_proc where oid = 'public.current_actor_id()'::regprocedure))
      )) acl
     where acl.grantee = 0
       and acl.privilege_type = 'EXECUTE'
  ) then
    raise exception 'PUBLIC can execute current_actor_id()';
  end if;
end;
$privileges$;

insert into auth.users(id)
values ('00000000-0000-4000-8000-000000000067')
on conflict (id) do nothing;

insert into public.user_profiles(id, display_name, role, status)
values (
  '00000000-0000-4000-8000-000000000067',
  'RLS Read 0067',
  'admin',
  'active'
)
on conflict (id) do update set status = excluded.status;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000067","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000067',
  true
);

do $read_smoke$
declare
  v_actor uuid;
  v_count bigint;
begin
  select public.current_actor_id() into v_actor;
  if v_actor is distinct from '00000000-0000-4000-8000-000000000067'::uuid then
    raise exception 'current_actor_id returned unexpected actor %', v_actor;
  end if;

  select count(*) into v_count from public.cad_pessoas_comerciais;
  select count(*) into v_count from public.cadastro_validation_issues;
  select count(*) into v_count from public.est_lotes_pa;
  select count(*) into v_count from public.com_pedidos;
end;
$read_smoke$;

do $write_denied$
begin
  begin
    insert into public.cad_clientes(nome, nome_norm, cidade, uf)
    values ('Write must fail', 'write must fail', 'Teste', 'SP');
    raise exception 'authenticated direct write unexpectedly succeeded';
  exception
    when insufficient_privilege then null;
  end;
end;
$write_denied$;

reset role;
rollback;

\echo ELITE_SECURITY_RLS_READ_CONTINUITY_OK
