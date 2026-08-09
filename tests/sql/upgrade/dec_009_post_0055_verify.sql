do $$
begin
  if not exists (
    select 1
      from public.com_pedidos order_record
      join public.com_pedido_comissionados commissioned
        on commissioned.pedido_id = order_record.id
     where order_record.codigo_pedido = 'DEC009-UPGRADE'
       and order_record.condicao_pagamento = '30/60'
       and commissioned.status = 'paga'
  ) then
    raise exception 'DEC-009 upgrade did not preserve legacy order and commission state';
  end if;

  if exists (select 1 from public.fin_pedido_planos_pagamento)
     or exists (select 1 from public.fin_pedido_parcelas)
     or exists (select 1 from public.fin_recebimento_posicoes_historicas)
     or exists (select 1 from public.fin_comissao_posicoes_historicas)
     or exists (select 1 from public.fat_referencias_fiscais_historicas) then
    raise exception 'DEC-009 upgrade fabricated financial or fiscal legacy facts';
  end if;
end;
$$;

select 'DEC_009_UPGRADE_CHAIN_OK' as result;
