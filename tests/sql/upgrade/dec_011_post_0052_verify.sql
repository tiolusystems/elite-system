do $$
begin
  if not exists (
    select 1
      from public.cad_cliente_vendedores relation
      join public.cad_cliente_vinculo_papeis role_catalog
        on role_catalog.id = relation.papel_vinculo_id
     where role_catalog.codigo_norm = 'atende'
       and relation.origem_dados = 'sistema'
       and relation.status = 'active'
       and relation.vigencia_inicio = date '2020-01-01'
  ) then
    raise exception 'DEC-011 upgrade did not preserve old link as atende';
  end if;

  if not exists (
    select 1 from public.cad_pessoa_areas_comerciais relation
    where relation.origem_dados = 'sistema'
      and relation.status = 'active'
      and relation.vigencia_inicio = date '2020-01-01'
  ) then
    raise exception 'DEC-011 upgrade did not preserve person/area link';
  end if;

  if exists (select 1 from public.cad_cliente_areas_comerciais) then
    raise exception 'DEC-011 upgrade fabricated client/area relations';
  end if;

  if exists (
    select 1 from public.com_pedidos where cliente_vendedor_vinculo_id is not null
  ) then
    raise exception 'DEC-011 upgrade fabricated order/link references';
  end if;

  if not exists (
    select 1 from public.cad_cliente_vinculo_papeis
    where codigo_norm = 'cadastrou' and concede_visibilidade = false
  ) then
    raise exception 'DEC-011 role catalog is incomplete';
  end if;
end;
$$;

select 'DEC_011_UPGRADE_CHAIN_OK' as result;
