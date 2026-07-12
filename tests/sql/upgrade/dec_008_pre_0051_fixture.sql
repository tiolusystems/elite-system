do $$
declare
  v_actor uuid := public.historical_migration_actor_id();
  v_mp_id bigint;
begin
  if v_actor is null then
    raise exception 'DEC-008 upgrade fixture requires Migracao Historica actor';
  end if;

  insert into public.cad_materias_primas(
    sku_corrigido, nome, nome_norm, unidade_base_estoque, status,
    payload_origem_json, created_by, updated_by, origem_dados
  ) values (
    'DEC008-UPGRADE-MP', 'DEC-008 upgrade MP', 'dec-008 upgrade mp',
    'kg', 'active', '{}'::jsonb, v_actor, v_actor, 'sistema'
  ) returning id into v_mp_id;

  insert into public.cad_embalagens(
    descricao, descricao_norm, unidade, volume_litros, controla_estoque,
    status, created_by, updated_by, origem_dados
  ) values (
    'DEC-008 upgrade package', 'dec-008 upgrade package', 'litros', 20,
    false, 'active', v_actor, v_actor, 'sistema'
  );

  insert into public.cad_conversoes_unidade_mp(
    materia_prima_id, unidade_origem, unidade_destino, fator, created_by
  ) values (
    v_mp_id, 'quilogramas', 'toneladas', 0.001, v_actor
  );

  insert into public.cad_veiculos(
    descricao, descricao_norm, status, capacidade, created_by, updated_by
  ) values (
    'DEC-008 upgrade vehicle', 'dec-008 upgrade vehicle', 'active', 100,
    v_actor, v_actor
  );
end;
$$;
