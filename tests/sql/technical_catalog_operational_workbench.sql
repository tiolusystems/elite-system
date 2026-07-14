\set ON_ERROR_STOP on

begin;

do $technical_catalog_workbench$
declare
  v_actor uuid := '00000000-0000-4000-8000-000000000056';
  v_product_id bigint;
  v_legacy_call_id bigint;
  v_invalid_count integer;
  v_validity integer;
begin
  insert into auth.users(id)
  values (v_actor)
  on conflict (id) do nothing;

  insert into public.user_profiles(id, display_name, role, status)
  values (v_actor, 'Technical Catalog Smoke Actor', 'admin', 'active')
  on conflict (id) do update set
    display_name = excluded.display_name,
    role = excluded.role,
    status = excluded.status;

  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  select v_actor, action.action_key, true, v_actor
    from public.permission_actions action
  on conflict (user_id, action_key) do update set
    allowed = excluded.allowed,
    updated_by = excluded.updated_by;

  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  if public.current_system_environment() = 'unconfigured' then
    perform public.set_system_runtime_environment(
      'test',
      'test_reset',
      'Smoke F1.1 dos cadastros tecnicos'
    );
  elsif public.current_system_environment() <> 'test' then
    raise exception 'technical catalog smoke requires unconfigured or test environment';
  end if;

  insert into public.cad_grupos_produto(
    codigo, nome, status, origem_dados, created_by
  ) values (
    'SMOKE-0057', 'Grupo Smoke 0057', 'active', 'sistema', v_actor
  ) on conflict (codigo_norm) do nothing;

  v_product_id := public.create_cad_produto_base(
    '9856',
    'Produto Smoke 0056',
    'PRODUTO SMOKE 0056',
    'active',
    'SMOKE-0057',
    1.2,
    null,
    null,
    null,
    null,
    '{}'::jsonb,
    18
  );

  select prazo_validade_meses
    into v_validity
    from public.cad_produtos_base
   where id = v_product_id;
  if v_validity <> 18 then
    raise exception 'initial product validity was not persisted atomically';
  end if;

  if not exists (
    select 1
      from public.cad_produtos_base product
      join public.cad_grupos_produto product_group on product_group.id = product.grupo_id
     where product.id = v_product_id
       and product_group.codigo = 'SMOKE-0057'
  ) then
    raise exception 'product group was not resolved relationally';
  end if;

  if not exists (
    select 1
      from public.action_logs
     where entity_type = 'cad_produtos_base'
       and entity_id = v_product_id::text
       and action_key = 'cadastros.produtos.create'
       and after_json->>'prazo_validade_meses' = '18'
  ) then
    raise exception 'atomic product audit log was not recorded';
  end if;

  begin
    perform public.create_cad_produto_base(
      '9857',
      'Produto Invalido Smoke 0056',
      'PRODUTO INVALIDO SMOKE 0056',
      'active',
      null,
      null,
      null,
      null,
      null,
      null,
      '{}'::jsonb,
      241
    );
    raise exception 'invalid product validity was accepted';
  exception
    when others then
      if sqlerrm <> 'prazo_validade_meses must be between 1 and 240' then
        raise;
      end if;
  end;

  select count(*)
    into v_invalid_count
    from public.cad_produtos_base
   where codigo_produto = '9857';
  if v_invalid_count <> 0 then
    raise exception 'invalid product survived the atomic rollback';
  end if;

  v_legacy_call_id := public.create_cad_produto_base(
    '9858',
    'Produto Compatibilidade Smoke 0056',
    'PRODUTO COMPATIBILIDADE SMOKE 0056'
  );
  if v_legacy_call_id is null then
    raise exception 'legacy positional product call is no longer compatible';
  end if;
end;
$technical_catalog_workbench$;

rollback;

select 'PG_TECHNICAL_CATALOG_WORKBENCH_OK' as result;
