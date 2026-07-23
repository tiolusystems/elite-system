\set ON_ERROR_STOP on

begin;

do $traceability_contract$
declare
  v_denied_actor uuid := '00000000-0000-4000-8000-000000000106';
  v_action text;
begin
  foreach v_action in array array[
    'qualidade.rastreabilidade.view',
    'qualidade.rastreabilidade.recall_simulate',
    'qualidade.rastreabilidade.export'
  ] loop
    if not exists (
      select 1 from public.permission_actions action
       where action.action_key = v_action
         and action.default_allowed = false
         and action.runtime_access_kind = 'read'
    ) then raise exception 'traceability action is not deny-by-default: %', v_action; end if;
  end loop;

  if has_table_privilege('authenticated', 'public.rel_rastreabilidade_arestas', 'SELECT')
     or has_table_privilege('authenticated', 'public.rel_rastreabilidade_lotes_resumo', 'SELECT')
     or has_table_privilege('authenticated', 'public.rel_rastreabilidade_destinos_cliente', 'SELECT')
     or has_table_privilege('authenticated', 'public.rel_rastreabilidade_conciliacao', 'SELECT')
     or has_table_privilege('anon', 'public.rel_rastreabilidade_arestas', 'SELECT') then
    raise exception 'traceability views are directly exposed';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.consultar_rel_rastreabilidade(text,text,bigint,bigint,bigint,text,text,integer)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'public.consultar_rel_rastreabilidade(text,text,bigint,bigint,bigint,text,text,integer)',
    'EXECUTE'
  ) then raise exception 'traceability query grants are invalid'; end if;

  if not has_function_privilege('authenticated', 'public.simular_rel_recolhimento(text,bigint)', 'EXECUTE')
     or has_function_privilege('anon', 'public.simular_rel_recolhimento(text,bigint)', 'EXECUTE')
     or not has_function_privilege(
       'authenticated',
       'public.exportar_rel_rastreabilidade(text,text,bigint,bigint,bigint,text,text)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'public.exportar_rel_rastreabilidade(text,text,bigint,bigint,bigint,text,text)',
       'EXECUTE'
     ) then raise exception 'recall or export grants are invalid'; end if;

  insert into auth.users(id) values (v_denied_actor) on conflict (id) do nothing;
  insert into public.user_profiles(id, display_name, role, status)
  values (v_denied_actor, 'Traceability denied actor', 'auditoria', 'active')
  on conflict (id) do update set status = 'active';
  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  select v_denied_actor, action.action_key, false, v_denied_actor
    from public.permission_actions action
   where action.action_key like 'qualidade.rastreabilidade.%'
  on conflict (user_id, action_key) do update set allowed = false;
  perform set_config('request.jwt.claim.sub', v_denied_actor::text, true);
  begin
    perform * from public.consultar_rel_rastreabilidade('MP', 'SEM-LOTE', null, null, null, null, 'frente', 10);
    raise exception 'actor without traceability permission reached query validation';
  exception when others then
    if sqlerrm <> 'not allowed: qualidade.rastreabilidade.view' then raise; end if;
  end;
end;
$traceability_contract$;

rollback;

select 'PG_TOTAL_TRACEABILITY_CONTRACT_OK' as result;
