\set ON_ERROR_STOP on

do $assert$
declare v_policy_active integer; v_reference_active integer;
begin
  select count(*) into v_policy_active
    from public.prc03_lifecycle_concurrency_probe p
    join public.prc_valoracao_versoes v on v.politica_id=p.identity_id
    join lateral (
      select e.estado from public.prc_valoracao_lifecycle_eventos e
       where e.valoracao_versao_id=v.id order by e.created_at desc,e.id desc limit 1
    ) state on true
   where p.target_kind='policy' and state.estado='ACTIVE';
  if v_policy_active<>1 then
    raise exception 'policy lifecycle concurrency left % ACTIVE versions',v_policy_active;
  end if;

  select count(*) into v_reference_active
    from public.prc03_lifecycle_concurrency_probe p
    join public.prc_valoracao_referencia_versoes v on v.referencia_id=p.identity_id
    join lateral (
      select e.estado from public.prc_valoracao_referencia_lifecycle_eventos e
       where e.referencia_versao_id=v.id order by e.created_at desc,e.id desc limit 1
    ) state on true
   where p.target_kind='reference' and state.estado='ACTIVE';
  if v_reference_active<>1 then
    raise exception 'reference lifecycle concurrency left % ACTIVE versions',v_reference_active;
  end if;

  if (select count(*) from public.prc_requisicoes where idempotency_key in (
    '15230000-0000-4000-8000-000000000021'::uuid,
    '15230000-0000-4000-8000-000000000022'::uuid,
    '15230000-0000-4000-8000-000000000023'::uuid,
    '15230000-0000-4000-8000-000000000024'::uuid
  ))<>4 then
    raise exception 'concurrent lifecycle requests were not all recorded';
  end if;
end;
$assert$;

\echo PG_PRC03_LIFECYCLE_CONCURRENCY_OK
