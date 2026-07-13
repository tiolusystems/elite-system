do $$
begin
  if not exists (
    select 1
      from public.pcp_ordens_producao op
      join public.pcp_formula_versoes version on version.id = op.formula_versao_id
     where op.codigo_op = 'DEC006-UPGRADE-OP'
       and op.produto_id = version.produto_id
       and op.formula_referencia_historica_id is null
       and op.review_status = 'approved'
       and op.origem_dados = 'sistema'
  ) then
    raise exception 'DEC-006 upgrade did not preserve live OP/formula relation';
  end if;

  if not exists (
    select 1 from public.pcp_formula_itens item
    where item.review_status = 'approved'
      and item.origem_dados = 'sistema'
      and item.created_by is not null
  ) then
    raise exception 'DEC-006 upgrade did not backfill formula item governance';
  end if;

  if exists (select 1 from public.pcp_formula_rendimentos)
     or exists (select 1 from public.pcp_formula_referencias_historicas)
     or exists (select 1 from public.pcp_op_saidas_historicas)
     or exists (select 1 from public.pcp_op_cq_historico_parcial) then
    raise exception 'DEC-006 upgrade fabricated formula/OP historical facts';
  end if;
end;
$$;

select 'DEC_006_UPGRADE_CHAIN_OK' as result;
