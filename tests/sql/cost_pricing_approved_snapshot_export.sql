\set ON_ERROR_STOP on
do $$
declare
  v_public boolean;
  v_anon boolean;
  v_definer boolean;
begin
  select has_function_privilege('public','public.consultar_prc_snapshot_aprovado(bigint)','EXECUTE'),
         has_function_privilege('anon','public.consultar_prc_snapshot_aprovado(bigint)','EXECUTE'),
         p.prosecdef
    into v_public,v_anon,v_definer
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='consultar_prc_snapshot_aprovado'
    and pg_get_function_identity_arguments(p.oid)='p_calculo_id bigint';
  if v_public or v_anon or not v_definer then
    raise exception 'approved snapshot RPC has an unsafe executable surface';
  end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='consultar_prc_snapshot_aprovado') then
    raise exception 'approved snapshot RPC is missing';
  end if;
end $$;
