\set ON_ERROR_STOP on
begin;

do $catalog$
begin
  if not exists (
    select 1
    from public.permission_actions
    where action_key = 'pcp.pop.read'
      and module = 'pcp'
      and default_allowed
      and runtime_module_key = 'pcp'
      and runtime_access_kind = 'read'
  ) then
    raise exception 'POP read permission is invalid';
  end if;
  if exists (
    select 1
    from public.permission_actions
    where action_key in (
      'pcp.pop.version.create',
      'pcp.pop.publish',
      'pcp.pop.state.manage',
      'pcp.pop.applicability.manage',
      'pcp.pop.cq.record'
    )
      and default_allowed
  ) then
    raise exception 'sensitive POP permissions must default to denied';
  end if;
  if has_table_privilege('authenticated', 'public.pcp_pop_versoes', 'SELECT')
     or has_table_privilege('authenticated', 'public.pcp_pop_versoes', 'INSERT')
     or has_table_privilege('anon', 'public.pcp_pop_versoes', 'SELECT')
     or exists (
       select 1
       from pg_class relation
       cross join lateral aclexplode(
         coalesce(relation.relacl, acldefault('r', relation.relowner))
       ) privilege
       where relation.oid = 'public.pcp_pop_versoes'::regclass
         and privilege.grantee = 0
     ) then
    raise exception 'controlled procedure tables have broad direct privileges';
  end if;
  if has_function_privilege(
       'anon',
       'public.create_pcp_pop_version(bigint,text,text,text,text,date,text,text,text)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'authenticated',
       'public.create_pcp_pop_version(bigint,text,text,text,text,date,text,text,text)',
       'EXECUTE'
     ) then
    raise exception 'controlled procedure RPC grants are invalid';
  end if;
end
$catalog$;

insert into auth.users(id, email) values
  ('11500000-0000-4000-8000-000000000001', 'pop-author-0115@test.invalid'),
  ('11500000-0000-4000-8000-000000000002', 'pop-reader-0115@test.invalid'),
  ('11500000-0000-4000-8000-000000000003', 'pop-runtime-admin-0115@test.invalid');

insert into public.user_profiles(id, display_name, role, status) values
  ('11500000-0000-4000-8000-000000000001', 'Autor sintetico de POP', 'producao', 'active'),
  ('11500000-0000-4000-8000-000000000002', 'Leitor sintetico de POP', 'producao', 'active'),
  ('11500000-0000-4000-8000-000000000003', 'Administrador sintetico 0115', 'admin', 'active');

insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
select
  '11500000-0000-4000-8000-000000000001',
  action_key,
  true,
  '11500000-0000-4000-8000-000000000001'
from public.permission_actions
where action_key like 'pcp.%'
   or action_key in ('cadastros.produtos.create', 'system.admin')
on conflict (user_id, action_key) do update
set allowed = excluded.allowed, updated_by = excluded.updated_by;

insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
values (
  '11500000-0000-4000-8000-000000000003',
  'system.admin',
  true,
  '11500000-0000-4000-8000-000000000003'
);

select set_config('request.jwt.claim.sub', '11500000-0000-4000-8000-000000000003', true);
select public.set_system_runtime_environment('test', 'initial_configuration', 'Smoke descartavel 0115')
where public.current_system_environment() = 'unconfigured';

set local role authenticated;
select set_config('request.jwt.claim.sub', '11500000-0000-4000-8000-000000000002', true);

do $reader_denied$
begin
  if not public.can_current_user('pcp.pop.read') then
    raise exception 'active reader cannot consult POP catalog';
  end if;
  perform public.list_pcp_pop_catalog();
  begin
    perform public.create_pcp_pop_version(
      null, 'POP-0115-DENIED', 'Denied', 'Denied', '00',
      current_date, 'DOC-DENIED', 'Denied content',
      'Denied creation must fail'
    );
    raise exception 'reader created a POP without atomic permission';
  exception when others then
    if sqlerrm = 'reader created a POP without atomic permission' then raise; end if;
    if sqlerrm not like 'not allowed: pcp.pop.version.create%' then raise; end if;
  end;
end
$reader_denied$;

select set_config('request.jwt.claim.sub', '11500000-0000-4000-8000-000000000001', true);

do $governance$
declare
  v_pop_version bigint;
  v_pop_id bigint;
  v_product_id bigint;
  v_unit_id bigint;
  v_mp_id bigint;
  v_formula_id bigint;
  v_op_id bigint;
  v_snapshot record;
  v_second_version bigint;
begin
  v_pop_version := public.create_pcp_pop_version(
    null,
    'POP-HOM-0115',
    'Procedimento sintetico de formulacao',
    'Orientar a formulacao do ensaio descartavel',
    '01',
    current_date,
    'DOC-HOM-0115',
    'Executar a formulacao conforme os controles sinteticos do ensaio.',
    'Criacao controlada para validar a migration 0115'
  );
  select pop_id into v_pop_id
    from public.list_pcp_pop_catalog()
   where pop_versao_id = v_pop_version;
  perform public.publish_pcp_pop_version(
    v_pop_version,
    'Publicacao sintetica para validar imutabilidade'
  );
  perform public.set_pcp_pop_active_state(
    v_pop_id,
    true,
    'Ativacao sintetica para novas ordens'
  );

  v_product_id := public.create_cad_produto_base_governado(
    p_codigo_produto => '9115',
    p_nome => 'Produto sintetico POP 0115',
    p_grupo_id => null,
    p_status => 'active',
    p_prazo_validade_meses => 12
  );
  select id into v_unit_id
    from public.cad_unidades_medida
   where codigo = 'kg_l_produzido'
     and status = 'active';
  v_mp_id := public.create_cad_materia_prima_governada(
    p_nome => 'Materia-prima sintetica POP 0115',
    p_nome_norm => 'MATERIA PRIMA SINTETICA POP 0115',
    p_sku_corrigido => 'MP-POP-0115',
    p_unidade_base_estoque_id => v_unit_id,
    p_status => 'active'
  );
  v_formula_id := public.create_pcp_formula_versao_idempotente(
    '11500000-0000-4000-8000-000000000010',
    v_product_id,
    'producao',
    'Formula operacional sintetica POP 0115',
    jsonb_build_array(jsonb_build_object(
      'tipo_componente', 'MP',
      'materia_prima_id', v_mp_id,
      'quantidade', 1,
      'unidade_id', v_unit_id,
      'unidade', 'kg_l_produzido'
    )),
    'Formula de um litro para testar o congelamento'
  );
  perform public.activate_pcp_formula_versao(
    v_formula_id,
    'Ativacao sintetica da formula operacional'
  );
  perform public.set_pcp_pop_applicability(
    v_pop_version,
    'producao',
    v_formula_id,
    true,
    10,
    'Vinculo sintetico especifico com a formula'
  );
  v_op_id := public.create_pcp_op_idempotente(
    '11500000-0000-4000-8000-000000000011',
    v_formula_id,
    'estoque',
    1,
    'OP operacional sintetica para congelamento de POP'
  );

  select * into v_snapshot
  from public.list_pcp_op_pop_references(v_op_id)
  where pop_versao_id = v_pop_version;
  if not found
     or v_snapshot.codigo <> 'POP-HOM-0115'
     or v_snapshot.revisao <> '01' then
    raise exception 'new OP did not freeze the applicable POP version';
  end if;

  v_second_version := public.create_pcp_pop_version(
    v_pop_id,
    'POP-HOM-0115',
    'Procedimento sintetico de formulacao revisado',
    'Orientar a formulacao do ensaio descartavel',
    '02',
    current_date + 1,
    'DOC-HOM-0115-R02',
    'Nova revisao sintetica sem alterar ordens historicas.',
    'Nova revisao para validar preservacao da OP'
  );
  if v_second_version is null then raise exception 'new POP version was not created'; end if;
  if (
    select revisao from public.list_pcp_op_pop_references(v_op_id)
    where pop_versao_id = v_pop_version
  ) <> '01' then
    raise exception 'historical OP snapshot changed after a new POP revision';
  end if;

  begin
    update public.pcp_pop_versoes set titulo = 'Mutacao proibida' where id = v_pop_version;
    raise exception 'authenticated updated a published POP version directly';
  exception when others then
    if sqlerrm = 'authenticated updated a published POP version directly' then raise; end if;
    if sqlerrm not like 'permission denied for table pcp_pop_versoes%' then raise; end if;
  end;

  begin
    perform public.create_pcp_pop_version(
      v_pop_id, 'POP-HOM-0115', 'Duplicada', 'Duplicada', '02',
      current_date + 2, 'DOC-DUP', 'Conteudo duplicado',
      'Duplicidade de revisao deve ser recusada'
    );
    raise exception 'duplicate POP revision was accepted';
  exception when unique_violation then null;
  end;

  perform public.set_pcp_pop_active_state(
    v_pop_id,
    false,
    'Inativacao sintetica preservando a OP historica'
  );
  if not exists (
    select 1 from public.list_pcp_op_pop_references(v_op_id)
    where pop_versao_id = v_pop_version
  ) then
    raise exception 'inactivation removed the historical OP snapshot';
  end if;
end
$governance$;

reset role;

do $owner_immutability$
begin
  begin
    update public.pcp_pop_versoes
       set titulo = 'Mutacao proibida pelo proprietario'
     where revisao = '01'
       and pop_id = (
         select id from public.pcp_pops where codigo = 'POP-HOM-0115'
       );
    raise exception 'published POP version was updated by its table owner';
  exception when others then
    if sqlerrm = 'published POP version was updated by its table owner' then raise; end if;
    if sqlerrm not like 'published POP versions are immutable%' then raise; end if;
  end;
end
$owner_immutability$;

rollback;
