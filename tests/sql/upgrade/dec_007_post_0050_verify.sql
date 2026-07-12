do $$
begin
  if not exists (
    select 1
      from public.cad_materias_primas material
      join public.cad_unidades_medida unit on unit.id = material.unidade_base_estoque_id
     where material.sku_corrigido = 'DEC007-UPGRADE-MP'
       and unit.codigo_norm = 'kg'
  ) then
    raise exception 'DEC-007 upgrade did not map quilogramas alias to kg';
  end if;

  if not exists (
    select 1
      from public.pcp_formula_itens item
      join public.cad_unidades_medida unit on unit.id = item.unidade_id
      join public.pcp_formula_versoes version on version.id = item.formula_versao_id
      join public.cad_produtos_base product on product.id = version.produto_id
     where product.codigo_produto = 'DEC007-UPGRADE-PROD'
       and unit.codigo_norm = 'l'
  ) then
    raise exception 'DEC-007 upgrade did not map litros alias to l';
  end if;

  if not exists (
    select 1
      from public.cad_garantias_produto_mapa guarantee
     where guarantee.nutriente_id is not null
       and guarantee.unidade_id is not null
       and guarantee.natureza = 'mapa_documental'
       and guarantee.review_status = 'approved'
  ) then
    raise exception 'DEC-007 upgrade did not backfill guarantee catalog FKs';
  end if;
end;
$$;

select 'DEC_007_UPGRADE_CHAIN_OK' as result;
