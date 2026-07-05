comment on function public.confirmar_exp_romaneio(bigint, text) is
  'Concurrency invariant: PA reservations for a romaneio item must only be changed by RPCs that lock the parent exp_romaneio_itens row first; confirmar_exp_romaneio relies on that invariant before summing active reservations and then locking est_reservas_pa rows.';

create or replace function public.gerar_lote_mp_from_imp_nfe_item(
  p_item_id bigint,
  p_status text default 'disponivel',
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_item record;
  v_lote_id bigint;
  v_codigo_lote text;
  v_origem_ref text;
  v_before jsonb;
  v_after jsonb;
  v_permission_context jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'importacao.nfe_xml.generate_mp_lot',
    'importacao_xml',
    'imp_nfe_xml_itens',
    'movement_event',
    jsonb_build_object(
      'familia', 'MP',
      'event', 'entry',
      'origem', 'nfe_xml',
      'stock_action_key', 'estoque.mp.lots.create',
      'source', 'gerar_lote_mp_from_imp_nfe_item'
    )
  );

  if p_item_id is null or p_item_id <= 0 then
    raise exception 'item_id is required';
  end if;
  if p_status not in ('disponivel', 'bloqueado') then
    raise exception 'invalid initial MP lot status';
  end if;

  select
      item.*,
      nfe.chave_acesso_norm,
      nfe.numero as nfe_numero,
      nfe.serie as nfe_serie
    into v_item
    from public.imp_nfe_xml_itens item
    join public.imp_nfe_xmls nfe on nfe.id = item.nfe_id
   where item.id = p_item_id
   for update of item;

  if not found then
    raise exception 'NFe XML item not found';
  end if;
  if v_item.status <> 'match_confirmado' then
    raise exception 'NFe XML item must be matched before MP lot generation';
  end if;
  if v_item.materia_prima_confirmada_id is null or v_item.quantidade_convertida is null or v_item.quantidade_convertida <= 0 then
    raise exception 'NFe XML item match is incomplete';
  end if;
  if exists (select 1 from public.imp_nfe_item_lotes_mp where item_id = p_item_id) then
    raise exception 'NFe XML item already has generated MP lot';
  end if;

  select jsonb_build_object(
      'nfe', to_jsonb(nfe),
      'item', to_jsonb(item),
      'resolucoes', coalesce((
        select jsonb_agg(to_jsonb(resolucao) order by resolucao.id)
          from public.imp_nfe_item_resolucoes resolucao
         where resolucao.item_id = p_item_id
      ), '[]'::jsonb),
      'lotes_mp', coalesce((
        select jsonb_agg(to_jsonb(link) order by link.id)
          from public.imp_nfe_item_lotes_mp link
         where link.item_id = p_item_id
      ), '[]'::jsonb)
    )
    into v_before
    from public.imp_nfe_xml_itens item
    join public.imp_nfe_xmls nfe on nfe.id = item.nfe_id
   where item.id = p_item_id;

  v_actor := public.current_actor_id();
  v_codigo_lote := concat('MP-NFE-', right(v_item.chave_acesso_norm, 8), '-', lpad(v_item.numero_item::text, 3, '0'));
  v_origem_ref := concat_ws(
    ' ',
    'NFe',
    nullif(v_item.nfe_numero, ''),
    case when nullif(v_item.nfe_serie, '') is null then null else concat('serie ', v_item.nfe_serie) end,
    concat('chave ', v_item.chave_acesso_norm),
    concat('item ', v_item.numero_item::text)
  );

  v_lote_id := public.create_est_lote_mp(
    v_item.materia_prima_confirmada_id,
    v_item.quantidade_convertida,
    v_codigo_lote,
    'entrada_compra',
    p_status,
    v_item.data_fabricacao,
    v_item.data_validade,
    v_origem_ref,
    concat_ws(
      ' | ',
      nullif(trim(p_observacao), ''),
      case when nullif(v_item.lote_fornecedor, '') is null then null else concat('lote fornecedor: ', v_item.lote_fornecedor) end,
      concat('unidade XML: ', v_item.unidade_xml),
      concat('fator conversao: ', v_item.fator_conversao::text)
    )
  );

  insert into public.imp_nfe_item_lotes_mp(item_id, lote_mp_id, created_by)
  values (p_item_id, v_lote_id, v_actor);

  update public.imp_nfe_xml_itens
     set status = 'lote_gerado',
         updated_by = v_actor
   where id = p_item_id;

  perform public.sync_imp_nfe_xml_status(v_item.nfe_id);

  select jsonb_build_object(
      'nfe', to_jsonb(nfe),
      'item', to_jsonb(item),
      'item_lote_mp', to_jsonb(link),
      'lote_mp', to_jsonb(lote),
      'mp_saldo', to_jsonb(saldo),
      'resolucoes', coalesce((
        select jsonb_agg(to_jsonb(resolucao) order by resolucao.id)
          from public.imp_nfe_item_resolucoes resolucao
         where resolucao.item_id = p_item_id
      ), '[]'::jsonb)
    )
    into v_after
    from public.imp_nfe_xml_itens item
    join public.imp_nfe_xmls nfe on nfe.id = item.nfe_id
    join public.imp_nfe_item_lotes_mp link on link.item_id = item.id
    join public.est_lotes_mp lote on lote.id = link.lote_mp_id
    left join public.est_lotes_mp_saldos saldo on saldo.lote_mp_id = lote.id
   where item.id = p_item_id;

  perform public.log_audited_rpc_change(
    'importacao_xml',
    'imp_nfe_xml_itens',
    p_item_id::text,
    'importacao.nfe_xml_item_lote_mp_generated',
    'importacao.nfe_xml.generate_mp_lot',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'gerar_lote_mp_from_imp_nfe_item',
      'estoque_action_key', 'estoque.mp.lots.create',
      'lote_mp_id', v_lote_id,
      'codigo_lote', v_codigo_lote,
      'materia_prima_id', v_item.materia_prima_confirmada_id,
      'quantidade_convertida', v_item.quantidade_convertida,
      'unidade_xml', v_item.unidade_xml,
      'unidade_destino', v_item.unidade_destino,
      'fator_conversao', v_item.fator_conversao,
      'origem_ref', v_origem_ref
    ),
    'database_rpc'
  );

  return v_lote_id;
end;
$$;

revoke all on function public.gerar_lote_mp_from_imp_nfe_item(bigint, text, text) from public;
grant execute on function public.gerar_lote_mp_from_imp_nfe_item(bigint, text, text) to authenticated;
