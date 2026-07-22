\set ON_ERROR_STOP on

begin;

do $production_release$
declare
  v_actor uuid := '00000000-0000-4000-8000-000000000044';
  v_materia_prima_id bigint;
  v_produto_id bigint;
  v_lote_mp_id bigint;
  v_lote_sem_densidade_id bigint;
  v_lote_sem_garantia_id bigint;
  v_unidade_kg_l_id bigint;
  v_unidade_l_l_id bigint;
  v_formula_id bigint;
  v_op_id bigint;
  v_op_sem_densidade_id bigint;
  v_op_sem_garantia_id bigint;
  v_componente_id bigint;
  v_garantia_produto_1 bigint;
  v_garantia_produto_2 bigint;
  v_garantia_lote bigint;
  v_parametro_lote bigint;
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

  if has_table_privilege('authenticated', 'public.cad_lote_mp_parametros_tecnicos', 'INSERT')
     or has_table_privilege('authenticated', 'public.cad_lote_mp_parametros_tecnicos', 'UPDATE')
     or has_table_privilege('authenticated', 'public.cad_lote_mp_parametros_tecnicos', 'DELETE') then
    raise exception 'authenticated still has direct write on MP lot physical parameters';
  end if;
  if has_table_privilege('anon', 'public.cad_lote_mp_parametros_tecnicos', 'SELECT') then
    raise exception 'anon can read MP lot physical parameters';
  end if;
  if has_function_privilege(
    'anon',
    'public.registrar_pcp_parametros_lote_mp(bigint,numeric,date,text,text,text)',
    'EXECUTE'
  ) then
    raise exception 'anon can execute MP lot physical parameter RPC';
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
  v_parametro_lote := public.registrar_pcp_parametros_lote_mp(
    v_lote_mp_id,
    1,
    current_date,
    'manual',
    null,
    'Densidade medida para o smoke de balanco fisico'
  );

  if v_garantia_produto_1 is null or v_garantia_lote is null or v_parametro_lote is null then
    raise exception 'guarantee registration did not return ids';
  end if;

  begin
    perform public.registrar_pcp_garantia_lote_mp(
      v_lote_mp_id,
      'N',
      101,
      '%',
      'manual',
      current_date,
      null,
      'Percentual acima de cem deve falhar'
    );
    raise exception 'percentage above 100 was accepted';
  exception
    when others then
      if sqlerrm <> 'percentage guarantee must be between zero and 100' then
        raise;
      end if;
  end;

  select id into v_unidade_kg_l_id from public.cad_unidades_medida
   where codigo = 'kg_l_produzido' and status = 'active';
  select id into v_unidade_l_l_id from public.cad_unidades_medida
   where codigo = 'l_l_produzido' and status = 'active';
  if v_unidade_kg_l_id is null or v_unidade_l_l_id is null then
    raise exception 'governed formula units are missing from production release fixture';
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
        'unidade_id', v_unidade_kg_l_id,
        'unidade', 'kg_l_produzido'
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
    1,
    10,
    10,
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
    raise exception 'physical guarantee calculation mismatch: value %, status %', v_valor, v_status;
  end if;

  if not exists (
    select 1
      from public.pcp_op_garantia_resultados result
     where result.op_id = v_op_id
       and result.calculo_versao = v_calculo_1
       and result.base_calculo_json ->> 'metodo' = 'balanco_fisico_v1'
       and jsonb_array_length(result.base_calculo_json -> 'inputs') = 1
       and nullif(result.base_calculo_json #>> '{inputs,0,garantia_lote_id}', '') is not null
  ) then
    raise exception 'physical guarantee calculation evidence is incomplete';
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

  v_lote_sem_densidade_id := public.create_est_lote_mp(
    v_materia_prima_id, 100, null, 'importacao_inicial', 'disponivel',
    current_date, current_date + 365, 'smoke-0044-sem-densidade',
    'Lote sem densidade para validar fechamento seguro'
  );
  perform public.registrar_pcp_garantia_lote_mp(
    v_lote_sem_densidade_id, 'N', 10, '%', 'manual', current_date, null,
    'Garantia sem densidade para validar base incompleta'
  );

  v_formula_id := public.create_pcp_formula_versao(
    v_produto_id, 'producao', 'Formula em litros para validar densidade obrigatoria',
    jsonb_build_array(jsonb_build_object(
      'tipo_componente', 'MP', 'materia_prima_id', v_materia_prima_id,
      'quantidade', 10, 'unidade_id', v_unidade_l_l_id, 'unidade', 'l_l_produzido'
    ))
  );
  perform public.activate_pcp_formula_versao(v_formula_id, 'Ativacao do teste de base incompleta');
  v_op_sem_densidade_id := public.create_pcp_op(v_formula_id, 'estoque', 1, 'OP sem densidade do lote');
  select id into v_componente_id from public.pcp_op_componentes_planejados
   where op_id = v_op_sem_densidade_id and tipo_componente = 'MP';
  perform public.reservar_pcp_op_componente(
    v_componente_id, v_lote_sem_densidade_id, null, null, 10, 'Reserva sem densidade'
  );
  perform public.iniciar_pcp_op(v_op_sem_densidade_id, 'Inicio sem densidade');
  perform public.finalizar_pcp_op(
    v_op_sem_densidade_id,
    jsonb_build_array(jsonb_build_object(
      'tipo_produto', 'PI', 'produto_id', v_produto_id,
      'quantidade', 10, 'observacao', 'PI com base fisica incompleta'
    )),
    'aprovado', 6.5, 1, 10, 10, 25,
    'Separador Smoke', 'Conferente Smoke', '["Formulador Smoke"]'::jsonb,
    'Finalizacao sem densidade'
  );
  perform public.calcular_pcp_garantias_op(v_op_sem_densidade_id, 'Calculo deve fechar sem estimativa');
  if not exists (
    select 1 from public.pcp_op_garantia_resultados
     where op_id = v_op_sem_densidade_id
       and status_resultado = 'base_incompleta'
       and valor_calculado is null
       and base_calculo_json -> 'pendencias' @> '[{"motivo":"densidade_lote_ausente_para_percentual"}]'::jsonb
  ) then
    raise exception 'missing lot density did not produce base_incompleta';
  end if;

  v_lote_sem_garantia_id := public.create_est_lote_mp(
    v_materia_prima_id, 100, null, 'importacao_inicial', 'disponivel',
    current_date, current_date + 365, 'smoke-0044-sem-garantia',
    'Lote sem garantia para validar fechamento seguro'
  );
  v_op_sem_garantia_id := public.create_pcp_op(v_formula_id, 'estoque', 1, 'OP sem garantia do lote');
  select id into v_componente_id from public.pcp_op_componentes_planejados
   where op_id = v_op_sem_garantia_id and tipo_componente = 'MP';
  perform public.reservar_pcp_op_componente(
    v_componente_id, v_lote_sem_garantia_id, null, null, 10, 'Reserva sem garantia'
  );
  perform public.iniciar_pcp_op(v_op_sem_garantia_id, 'Inicio sem garantia');
  perform public.finalizar_pcp_op(
    v_op_sem_garantia_id,
    jsonb_build_array(jsonb_build_object(
      'tipo_produto', 'PI', 'produto_id', v_produto_id,
      'quantidade', 10, 'observacao', 'PI sem garantia do lote'
    )),
    'aprovado', 6.5, 1, 10, 10, 25,
    'Separador Smoke', 'Conferente Smoke', '["Formulador Smoke"]'::jsonb,
    'Finalizacao sem garantia'
  );
  perform public.calcular_pcp_garantias_op(v_op_sem_garantia_id, 'Calculo deve apontar garantia ausente');
  if not exists (
    select 1 from public.pcp_op_garantia_resultados
     where op_id = v_op_sem_garantia_id
       and status_resultado = 'sem_dados_lote'
       and valor_calculado is null
       and base_calculo_json -> 'pendencias' @> '[{"motivo":"garantia_lote_ausente"}]'::jsonb
  ) then
    raise exception 'missing lot guarantee did not produce sem_dados_lote';
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
        'pcp.guarantee.mp_lot.parameters.register',
        'pcp.guarantee.calculate'
      )
      and log.status = 'success'
  ) <> 4 then
    raise exception 'production guarantee audit logs are incomplete';
  end if;
end;
$production_release$;

rollback;

\echo PG_PRODUCTION_MODULE_RELEASE_OK
