begin;

create or replace function public.consultar_prc_snapshot_aprovado(p_calculo_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_snapshot jsonb; v_hash text; v_decisao text; v_approved_by uuid; v_approved_at timestamptz;
begin
  perform public.begin_audited_rpc('precificacao.view','precificacao','prc_calculos','own_any',jsonb_build_object('calculo_id',p_calculo_id));
  select k.intermediarios_json,k.result_sha256,d.decisao,d.actor_id,d.created_at into v_snapshot,v_hash,v_decisao,v_approved_by,v_approved_at
    from public.prc_calculos k join public.prc_calculo_decisoes d on d.calculo_id=k.id where k.id=p_calculo_id;
  if not found then raise exception 'calculo aprovado inexistente'; end if;
  if v_decisao <> 'APPROVED' then raise exception 'somente calculos aprovados podem ser exportados'; end if;
  if v_snapshot is null or v_hash is null or public.prc_sha256(v_snapshot)<>v_hash then raise exception 'snapshot do calculo invalido'; end if;
  return jsonb_build_object('calculo_id',p_calculo_id,'snapshot_json',v_snapshot,'result_sha256',v_hash,'decision',v_decisao,'approved_by',v_approved_by,'approved_at',v_approved_at);
end;
$$;
revoke all on function public.consultar_prc_snapshot_aprovado(bigint) from public,anon;
grant execute on function public.consultar_prc_snapshot_aprovado(bigint) to authenticated;
comment on function public.consultar_prc_snapshot_aprovado(bigint) is 'Leitura governada do snapshot PRC aprovado; exportadores nao recalculam nem leem tabelas diretamente.';
commit;
