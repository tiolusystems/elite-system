do $$
begin
  if not exists (
    select 1
      from public.cad_embalagens package
      join public.cad_unidades_medida unit on unit.id = package.unidade_id
     where package.descricao_norm = 'dec-008 upgrade package'
       and unit.codigo_norm = 'l'
       and package.origem_dados = 'sistema'
  ) then
    raise exception 'DEC-008 upgrade did not canonicalize packaging unit';
  end if;

  if not exists (
    select 1
      from public.cad_conversoes_unidade_mp conversion
      join public.cad_unidades_medida source_unit on source_unit.id = conversion.unidade_origem_id
      join public.cad_unidades_medida target_unit on target_unit.id = conversion.unidade_destino_id
     where source_unit.codigo_norm = 'kg'
       and target_unit.codigo_norm = 't'
       and conversion.review_status = 'approved'
       and conversion.origem_dados = 'sistema'
  ) then
    raise exception 'DEC-008 upgrade did not canonicalize MP conversion';
  end if;

  if not exists (
    select 1
      from public.cad_veiculos vehicle
     where vehicle.descricao_norm = 'dec-008 upgrade vehicle'
       and vehicle.capacidade = 100
       and vehicle.capacidade_unidade_id is null
       and vehicle.status = 'pending_review'
  ) then
    raise exception 'DEC-008 upgrade invented vehicle capacity unit or left it operational';
  end if;

  if exists (select 1 from public.cad_embalagem_versoes) then
    raise exception 'DEC-008 upgrade fabricated package versions from incomplete legacy fields';
  end if;

  if to_regclass('public.exp_romaneio_logistica_eventos') is null
     or to_regclass('public.est_transformacoes') is null
     or to_regclass('public.est_transformacao_origens') is null
     or to_regclass('public.est_transformacao_destinos') is null then
    raise exception 'DEC-008 relational tables are incomplete after upgrade';
  end if;
end;
$$;

select 'DEC_008_UPGRADE_CHAIN_OK' as result;
