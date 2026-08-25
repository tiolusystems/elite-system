-- ORD-01 Phase 0: the legacy single-item entrypoint must not remain a public API.

do $$
declare
  v_expected oid := to_regprocedure(
    'public.create_com_pedido_operacional(bigint,bigint,numeric,numeric,bigint,text,text,date,bigint,numeric,text)'
  );
  v_function_oids oid[];
  v_function_signatures text[];
begin
  select
    array_agg(proc.oid order by proc.oid),
    array_agg(proc.oid::regprocedure::text order by proc.oid)
    into v_function_oids, v_function_signatures
  from pg_proc proc
  join pg_namespace namespace on namespace.oid = proc.pronamespace
  where namespace.nspname = 'public'
    and proc.proname = 'create_com_pedido_operacional';

  if coalesce(array_length(v_function_oids, 1), 0) <> 1
     or v_expected is null
     or v_function_oids[1] <> v_expected then
    raise exception
      'ORD-01 Phase 0 expected exactly public.create_com_pedido_operacional(bigint,bigint,numeric,numeric,bigint,text,text,date,bigint,numeric,text); found %',
      coalesce(array_to_string(v_function_signatures, ', '), '<none>');
  end if;
end;
$$;

revoke execute on function public.create_com_pedido_operacional(
  bigint, bigint, numeric, numeric, bigint, text, text, date, bigint, numeric, text
) from public, anon, authenticated;

comment on function public.create_com_pedido_operacional(
  bigint, bigint, numeric, numeric, bigint, text, text, date, bigint, numeric, text
) is
  'LEGADO ORD-01 Fase 0: entrypoint preservado somente para compatibilidade historica. Deixou de ser API operacional publica; criacao operacional deve usar os fluxos canonicos governados.';
