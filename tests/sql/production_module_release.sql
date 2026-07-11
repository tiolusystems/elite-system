\set ON_ERROR_STOP on

begin;

do $production_release$
declare
  v_actor uuid := '00000000-0000-4000-8000-000000000044';
  v_materia_prima_id bigint;
  v_produto_id bigint;
  v_lote_mp_id bigint;
  v_formula_id bigint;
  v_op_id bigint;
  v_componente_id bigint;
  v_garantia_produto_1 bigint;
  v_garantia_produto_2 bigint;
  v_garantia_lote bigint;
  v_calculo_1 integer;
  v_calculo_2 integer;
  v_valor numeric;
  v_status text;
  v_supersedes_id bigint;
begin
  insert into auth.users(id)
  values (v_actor)
  on conflict (id) do nothing;

  insert into public.user_profiles(id, display_name, role, status)
  values (v_actor, 'Production Release Smoke Actor', 'admin', 'active')
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
      'Smoke da publicacao do modulo Producao'
    );
  elsif public.current_system_environment() <> 'test' then
    raise exception 'production release smoke requires unconfigured or test environment';
  end if;

  if not exists (
    select 1
    from public.sys_module_routes route
    where route.route_prefix = '/producao'
      and route.module_key = 'pcp'
  ) then
    raise exception 'production route is not owned by PCP module';
  end if;

  if not exists (
    select 1
    from public.permission_actions action
    where action.action_key = 'pcp.guarantee.calculate'
      and action.runtime_module_key = 'pcp'
      and action.runtime_access_kind = 'write'
  ) then
    raise exception 'production guarantee permission is not mapped to PCP write runtime';
  end if;

  v_materia_prima_id := public.create_cad_materia_prima(
    'Materia Prima Smoke 0044',
    'MATERIA PRIMA SMOKE 0044',
    'MP-SMOKE-0044',
    'KG'
  );
  v_produto_id := public.create_cad_produto_base(
    '9844',
    'Produto Smoke 0044',
    'PRODUTO SMOKE 0044'
  );
  v_lote_mp_id := public.create_est_lote_mp(
    v_materia_prima_id,
    100,
    null,
    'importacao_inicial',
    'disponivel',
    current_date,
    current_date + 365,
    'smoke-0044',
    'Lote do smoke de Producao'
  );

  begin
    perform public.registrar_pcp_garantia_produto(
      v_produto_id,
      'N',
      'minimo',
      8,
      null,
      '%',
      'laboratorio',
      current_date,
      null,
      null,
      'Documento ausente deve falhar'
    );
    raise exception 'laboratory product guarantee without document was accepted';
  exception
    when others then
      if sqlerrm <> 'documento_referencia is required for laboratorio or fornecedor' then
        raise;
      end if;
  end;

  begin
    perform public.registrar_pcp_garantia_lote_mp(
      v_lote_mp_id,
      'N',
      10,
      '%',
      'fornecedor',
      current_date,
      null,
      'Documento ausente deve falhar'
    );
    raise exception 'supplier MP guarantee without document was accepted';
  exception
    when others then
      if sqlerrm <> 'documento_referencia is required for laboratorio or fornecedor' then
        raise;
      end if;
  end;

  v_garantia_produto_1 := public.registrar_pcp_garantia_produto(
    v_produto_id,
    'N',
    'minimo',
    8,
    null,
    '%',
    'mapa',
    current_date,
    null,
    'REG-MAPA-0044',
    'Garantia inicial para o smoke'
  );
  v_garantia_lote := public.registrar_pcp_garantia_lote_mp(
    v_lote_mp_id,
    'N',
    10,
    '%',
    'laboratorio',
    current_date,
    'LAUDO-0044',
    'Analise do lote para o smoke'
  );

  if v_garantia_produto_1 is null or v_garantia_lote is null then
    raise exception 'guarantee registration did not return ids';
  end if;

  v_formula_id := public.create_pcp_formula_versao(
    v_produto_id,
    'producao',
    'Formula do smoke de Producao',
    jsonb_build_array(
      jsonb_build_object(
        'tipo_componente', 'MP',
        'materia_prima_id', v_materia_prima_id,
        'quantidade', 10,
        'unidade', 'KG'
      )
    )
  );
  perform public.activate_pcp_formula_versao(v_formula_id, 'Ativacao do smoke de Producao');
  v_op_id := public.create_pcp_op(v_formula_id, 'estoque', 1, 'OP do smoke de Producao');

  select component.id
    into v_componente_id
    from public.pcp_op_componentes_planejados component
   where component.op_id = v_op_id
     and component.tipo_componente = 'MP';

  perform public.reservar_pcp_op_componente(
    v_componente_id,
    v_lote_mp_id,
    null,
    null,
    10,
    'Reserva do smoke de Producao'
  );
  perform public.iniciar_pcp_op(v_op_id, 'Inicio do smoke de Producao');
  perform public.finalizar_pcp_op(
    v_op_id,
    jsonb_build_array(
      jsonb_build_object(
        'tipo_produto', 'PI',
        'produto_id', v_produto_id,
        'quantidade', 10,
        'observacao', 'PI do smoke de Producao'
      )
    ),
    'aprovado',
    6.5,
    1.1,
    10,
    11,
    25,
    'Separador Smoke 0044',
    'Conferente Smoke 0044',
    '["Formulador Smoke 0044"]'::jsonb,
    'Finalizacao do smoke de Producao'
  );

  v_calculo_1 := public.calcular_pcp_garantias_op(v_op_id, 'Calculo inicial do smoke');
  select result.valor_calculado, result.status_resultado
    into v_valor, v_status
    from public.pcp_op_garantia_resultados result
   where result.op_id = v_op_id
     and result.calculo_versao = v_calculo_1
     and result.nutriente = 'N'
     and result.unidade = '%';

  if v_valor <> 10 or v_status <> 'atende' then
    raise exception 'weighted guarantee calculation mismatch: value %, status %', v_valor, v_status;
  end if;

  v_garantia_produto_2 := public.registrar_pcp_garantia_produto(
    v_produto_id,
    'N',
    'minimo',
    12,
    null,
    '%',
    'mapa',
    current_date,
    null,
    'REG-MAPA-0044-V2',
    'Nova versao mais restritiva para o smoke'
  );
  select guarantee.supersedes_id
    into v_supersedes_id
    from public.cad_garantias_produto_mapa guarantee
   where guarantee.id = v_garantia_produto_2;
  if v_supersedes_id <> v_garantia_produto_1 then
    raise exception 'product guarantee version chain is broken';
  end if;

  v_calculo_2 := public.calcular_pcp_garantias_op(v_op_id, 'Recalculo versionado do smoke');
  select result.valor_calculado, result.status_resultado
    into v_valor, v_status
    from public.pcp_op_garantia_resultados result
   where result.op_id = v_op_id
     and result.calculo_versao = v_calculo_2
     and result.nutriente = 'N'
     and result.unidade = '%';

  if v_calculo_2 <> v_calculo_1 + 1 or v_valor <> 10 or v_status <> 'nao_atende' then
    raise exception 'versioned guarantee recalculation mismatch';
  end if;
  if not exists (
    select 1
    from public.pcp_op_garantia_resultados result
    where result.op_id = v_op_id
      and result.calculo_versao = v_calculo_1
      and result.status_resultado = 'atende'
  ) then
    raise exception 'previous guarantee calculation was not preserved';
  end if;

  begin
    update public.cad_garantias_produto_mapa
       set valor = 99
     where id = v_garantia_produto_1;
    raise exception 'product guarantee update was accepted';
  exception
    when others then
      if sqlerrm not like 'cad_garantias_produto_mapa is append-only%' then
        raise;
      end if;
  end;

  begin
    delete from public.cad_garantias_lote_mp
     where id = v_garantia_lote;
    raise exception 'MP lot guarantee delete was accepted';
  exception
    when others then
      if sqlerrm not like 'cad_garantias_lote_mp is append-only%' then
        raise;
      end if;
  end;

  begin
    update public.pcp_op_garantia_resultados
       set status_resultado = 'informativo'
     where op_id = v_op_id;
    raise exception 'guarantee result update was accepted';
  exception
    when others then
      if sqlerrm not like 'pcp_op_garantia_resultados is append-only%' then
        raise;
      end if;
  end;

  if (
    select count(distinct log.action_key)
    from public.action_logs log
    where log.actor_user_id = v_actor
      and log.action_key in (
        'pcp.guarantee.product.register',
        'pcp.guarantee.mp_lot.register',
        'pcp.guarantee.calculate'
      )
      and log.status = 'success'
  ) <> 3 then
    raise exception 'production guarantee audit logs are incomplete';
  end if;
end;
$production_release$;

rollback;

\echo PG_PRODUCTION_MODULE_RELEASE_OK
