do $$
begin
  if not exists (
    select 1
      from public.cad_produtos_base product
      join public.cad_grupos_produto group_catalog on group_catalog.id = product.grupo_id
     where product.codigo_produto = 'DEC010-UPGRADE'
       and group_catalog.codigo_norm = 'grupo upgrade dec-010'
       and group_catalog.status = 'active'
  ) then
    raise exception 'DEC-010 upgrade did not normalize existing product group';
  end if;

  if exists (select 1 from public.com_campanhas)
     or exists (select 1 from public.com_campanha_pontos_movimentos)
     or exists (select 1 from public.com_campanha_premios)
     or exists (select 1 from public.fin_campanha_premio_pagamentos) then
    raise exception 'DEC-010 upgrade fabricated campaign facts';
  end if;

  if to_regclass('public.com_campanha_regras') is null
     or to_regclass('public.com_campanha_vouchers') is null
     or to_regclass('public.fin_campanha_premio_pagamentos') is null then
    raise exception 'DEC-010 relational campaign contract is incomplete';
  end if;
end;
$$;

select 'DEC_010_UPGRADE_CHAIN_OK' as result;
