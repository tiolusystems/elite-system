\set ON_ERROR_STOP on

begin;

do $production_catalog_view_access$
declare
  v_view text;
  v_table text;
begin
  foreach v_view in array array[
    'cad_garantias_produto_mapa_atuais',
    'cad_garantias_lote_mp_atuais'
  ]
  loop
    if not has_table_privilege('authenticated', format('public.%I', v_view), 'SELECT') then
      raise exception 'authenticated cannot read public.%', v_view;
    end if;
    if has_table_privilege('anon', format('public.%I', v_view), 'SELECT') then
      raise exception 'anon can read protected view public.%', v_view;
    end if;
    if has_table_privilege('public', format('public.%I', v_view), 'SELECT') then
      raise exception 'PUBLIC can read protected view public.%', v_view;
    end if;
    if not exists (
      select 1
        from pg_class relation
        join pg_namespace namespace on namespace.oid = relation.relnamespace
       where namespace.nspname = 'public'
         and relation.relname = v_view
         and relation.relkind = 'v'
         and coalesce(relation.reloptions, array[]::text[]) @> array['security_invoker=true']
    ) then
      raise exception 'public.% is not a security-invoker view', v_view;
    end if;
  end loop;

  foreach v_table in array array[
    'cad_garantias_produto_mapa',
    'cad_garantias_lote_mp'
  ]
  loop
    if not exists (
      select 1
        from pg_tables
       where schemaname = 'public'
         and tablename = v_table
         and rowsecurity
    ) then
      raise exception 'RLS is not enabled on public.%', v_table;
    end if;
    if not exists (
      select 1
        from pg_policies
       where schemaname = 'public'
         and tablename = v_table
         and cmd = 'SELECT'
         and 'authenticated' = any(roles)
         and qual ilike '%current_actor_id()%'
    ) then
      raise exception 'active-actor read policy is missing on public.%', v_table;
    end if;
  end loop;
end;
$production_catalog_view_access$;

insert into auth.users(id)
values ('00000000-0000-4000-8000-000000000058')
on conflict (id) do nothing;

insert into public.user_profiles(id, display_name, role, status)
values (
  '00000000-0000-4000-8000-000000000058',
  'Production Catalog Access Smoke Actor',
  'admin',
  'active'
)
on conflict (id) do update set
  display_name = excluded.display_name,
  role = excluded.role,
  status = excluded.status;

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000058',
  true
);

set local role authenticated;
select count(*) from public.cad_garantias_produto_mapa_atuais;
select count(*) from public.cad_garantias_lote_mp_atuais;
reset role;

rollback;

select 'PG_PRODUCTION_CATALOG_VIEW_ACCESS_OK' as result;
