do $$
declare
  v_actor uuid := public.historical_migration_actor_id();
begin
  insert into public.cad_produtos_base(
    codigo_produto, nome, nome_norm, grupo, status, payload_origem_json,
    created_by, updated_by, origem_dados
  ) values (
    'DEC010-UPGRADE', 'DEC-010 upgrade product', 'dec-010 upgrade product',
    'Grupo upgrade DEC-010', 'active', '{}'::jsonb,
    v_actor, v_actor, 'sistema'
  );
end;
$$;
