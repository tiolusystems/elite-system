\set ON_ERROR_STOP on

begin;

do $product_groups$
declare
  v_actor uuid := '00000000-0000-4000-8000-000000000103';
  v_group_id bigint;
  v_product_id bigint;
begin
  insert into auth.users(id) values (v_actor) on conflict (id) do nothing;
  insert into public.user_profiles(id, display_name, role, status)
  values (v_actor, 'Product Group Smoke Actor', 'admin', 'active')
  on conflict (id) do update set role = excluded.role, status = excluded.status;
  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  select v_actor, action_key, true, v_actor from public.permission_actions
  on conflict (user_id, action_key) do update set allowed = true, updated_by = excluded.updated_by;
  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  if public.current_system_environment() = 'unconfigured' then
    perform public.set_system_runtime_environment('test', 'test_reset', 'Product group governance smoke');
  elsif public.current_system_environment() <> 'test' then
    raise exception 'product group smoke requires unconfigured or test environment';
  end if;

  v_group_id := public.create_cad_grupo_produto('SMK103', 'Grupo Smoke 0103', 'Somente dados sinteticos', 10);
  v_product_id := public.create_cad_produto_base_governado(
    '9103', 'Produto Smoke 0103', v_group_id, 'active', 1.1, null, null, null, null, '{}'::jsonb, 12
  );

  if not exists (select 1 from public.cad_produtos_base where id = v_product_id and grupo_id = v_group_id) then
    raise exception 'governed product did not persist group_id';
  end if;

  begin
    perform public.create_cad_grupo_produto(' smk103 ', 'Outro nome', null, 0);
    raise exception 'normalized duplicate group code was accepted';
  exception when unique_violation then null;
  end;
  begin
    perform public.create_cad_grupo_produto('OTHER103', ' grupo smoke 0103 ', null, 0);
    raise exception 'normalized duplicate group name was accepted';
  exception when unique_violation then null;
  end;

  perform public.update_cad_grupo_produto(v_group_id, 'SMK103', 'Grupo Smoke 0103', 'Descricao alterada no smoke', 11, 'Ajuste controlado no smoke');
  perform public.set_cad_grupo_produto_active_state(v_group_id, false, 'Inativacao controlada no smoke');
  if not exists (select 1 from public.cad_produtos_base where id = v_product_id and grupo_id = v_group_id) then
    raise exception 'inactivation removed historical product relationship';
  end if;
  begin
    perform public.create_cad_produto_base_governado(
      '9104', 'Produto Invalido Smoke 0103', v_group_id, 'active', null, null, null, null, null, '{}'::jsonb, 12
    );
    raise exception 'inactive group was accepted by new product';
  exception when others then
    if sqlerrm <> 'active product group not found' then raise; end if;
  end;
  perform public.set_cad_grupo_produto_active_state(v_group_id, true, 'Reativacao controlada no smoke');

  if (select count(*) from public.list_cad_grupo_produto_history(v_group_id)) < 4 then
    raise exception 'audited product group history is incomplete';
  end if;
  if has_function_privilege('anon', 'public.create_cad_grupo_produto(text,text,text,integer)', 'EXECUTE') then
    raise exception 'anon can execute product group creation';
  end if;
end;
$product_groups$;

set local role authenticated;
do $direct_write$
begin
  begin
    insert into public.cad_grupos_produto(codigo, nome, status, origem_dados, created_by)
    values ('DIRECT103', 'Direct write', 'active', 'sistema', '00000000-0000-4000-8000-000000000103');
    raise exception 'direct authenticated write was accepted';
  exception when insufficient_privilege then null;
  end;
end;
$direct_write$;
reset role;

rollback;
select 'PG_PRODUCT_GROUPS_GOVERNANCE_OK' as result;
