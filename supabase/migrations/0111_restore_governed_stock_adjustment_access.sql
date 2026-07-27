-- Restore the audited stock-adjustment RPCs closed by the 0066 allowlist.

do $contract$
begin
  if to_regprocedure('public.registrar_est_ajuste_mp(bigint,numeric,text)') is null
     or to_regprocedure('public.registrar_est_ajuste_pi(bigint,numeric,text)') is null
     or to_regprocedure('public.registrar_est_ajuste_pa(bigint,numeric,text)') is null then
    raise exception 'governed stock-adjustment RPC contract is incomplete';
  end if;
end;
$contract$;

revoke all on function public.registrar_est_ajuste_mp(bigint, numeric, text)
  from public, anon, authenticated;
revoke all on function public.registrar_est_ajuste_pi(bigint, numeric, text)
  from public, anon, authenticated;
revoke all on function public.registrar_est_ajuste_pa(bigint, numeric, text)
  from public, anon, authenticated;

grant execute on function public.registrar_est_ajuste_mp(bigint, numeric, text)
  to authenticated;
grant execute on function public.registrar_est_ajuste_pi(bigint, numeric, text)
  to authenticated;
grant execute on function public.registrar_est_ajuste_pa(bigint, numeric, text)
  to authenticated;

comment on function public.registrar_est_ajuste_mp(bigint, numeric, text) is
  'Governed MP stock adjustment. Requires estoque.mp.adjust and records an append-only movement plus audit.';
comment on function public.registrar_est_ajuste_pi(bigint, numeric, text) is
  'Governed PI stock adjustment. Requires estoque.pi.adjust and records an append-only movement plus audit.';
comment on function public.registrar_est_ajuste_pa(bigint, numeric, text) is
  'Governed PA stock adjustment. Requires estoque.pa.adjust and records an append-only movement plus audit.';
