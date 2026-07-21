\set ON_ERROR_STOP on

begin;

do $cost_layers$
declare
  v_actor uuid := '00000000-0000-4000-8000-000000000077';
  v_mp_id bigint;
  v_product_id bigint;
  v_unit_id bigint;
  v_lot_id bigint;
  v_entry_1 bigint;
  v_entry_2 bigint;
  v_formula_id bigint;
  v_op_id bigint;
  v_component_id bigint;
  v_pi_lot_id bigint;
  v_cost numeric;
  v_loss numeric;
  v_remaining numeric;
begin
  insert into auth.users(id) values(v_actor) on conflict(id) do nothing;
  insert into public.user_profiles(id,display_name,role,status)
  values(v_actor,'Cost Layer Smoke Actor','admin','active')
  on conflict(id) do update set status='active';
  insert into public.user_permission_overrides(user_id,action_key,allowed,updated_by)
  select v_actor,action_key,true,v_actor from public.permission_actions
  on conflict(user_id,action_key) do update set allowed=true,updated_by=excluded.updated_by;
  perform set_config('request.jwt.claim.sub',v_actor::text,true);
  if public.current_system_environment()='unconfigured' then
    perform public.set_system_runtime_environment('test','test_reset','Smoke 0077');
  end if;
  if has_table_privilege('authenticated','public.est_lotes_pi_custo_camadas','INSERT')
     or has_table_privilege('authenticated','public.est_lotes_pa_custo_camadas','UPDATE')
     or has_table_privilege('authenticated','public.est_movimentos_mp_custo_alocacoes','DELETE') then
    raise exception 'authenticated retained direct write on cost facts';
  end if;
  if has_table_privilege('anon','public.est_lotes_pa_custo_componentes','SELECT')
     or has_function_privilege('anon','public.finalizar_pcp_op(bigint,jsonb,text,numeric,numeric,numeric,numeric,numeric,text,text,jsonb,text)','EXECUTE') then
    raise exception 'anon can access governed production cost flow';
  end if;

  v_mp_id := public.create_cad_materia_prima(
    'Materia Prima Custo 0077','MATERIA PRIMA CUSTO 0077','MP-CUSTO-0077','KG'
  );
  v_product_id := public.create_cad_produto_base('9777','PI Custo 0077','PI CUSTO 0077');
  select id into v_unit_id from public.cad_unidades_medida
   where codigo='kg_l_produzido' and status='active';
  v_lot_id := public.create_est_lote_mp(
    v_mp_id,6,null,'entrada_compra','disponivel',current_date,current_date+365,
    'LOTE-CUSTO-0077','Primeira entrada da mesma partida'
  );
  select id into v_entry_1 from public.est_movimentos_mp
   where lote_mp_id=v_lot_id order by id limit 1;
  insert into public.est_movimentos_mp(
    lote_mp_id,materia_prima_id,tipo_movimento,quantidade,origem_modulo,
    origem_tabela,origem_id,observacao,created_by
  ) values(v_lot_id,v_mp_id,'entrada_compra',6,'estoque','nf_entrada','NF-2',
    'Segunda entrada da mesma partida com outro preco',v_actor)
  returning id into v_entry_2;

  insert into public.est_movimentos_mp_valores(
    movimento_mp_id,quantidade_origem,unidade_origem,quantidade_base,moeda,
    valor_materia_prima,difal_status,documento_ref,origem_dados,created_by
  ) values
    (v_entry_1,6,'KG',6,'BRL',60,'not_applicable','NF-1','sistema',v_actor),
    (v_entry_2,6,'KG',6,'BRL',120,'not_applicable','NF-2','sistema',v_actor);

  v_formula_id := public.create_pcp_formula_versao(
    v_product_id,'producao','Formula custo por litro 0077',
    jsonb_build_array(jsonb_build_object(
      'tipo_componente','MP','materia_prima_id',v_mp_id,'quantidade',1,
      'unidade_id',v_unit_id,'unidade','kg_l_produzido'
    ))
  );
  perform public.activate_pcp_formula_versao(v_formula_id,'Ativacao smoke 0077');
  v_op_id := public.create_pcp_op(v_formula_id,'estoque',10,'OP custo 0077');
  select id into v_component_id from public.pcp_op_componentes_planejados
   where op_id=v_op_id and tipo_componente='MP';
  perform public.reservar_pcp_op_componente(
    v_component_id,v_lot_id,null,null,10,'Reserva das duas camadas da partida'
  );
  perform public.iniciar_pcp_op(v_op_id,'Inicio smoke custo 0077');

  begin
    perform public.finalizar_pcp_op(
      v_op_id,
      jsonb_build_array(
        jsonb_build_object('tipo_produto','PI','produto_id',v_product_id,'quantidade',8),
        jsonb_build_object('tipo_produto','PI','produto_id',v_product_id,'quantidade',1)
      ),
      'aprovado',6.5,1,9,9,25,'Separador','Conferente','["Formulador"]'::jsonb,
      'Duas saidas devem falhar'
    );
    raise exception 'OP accepted more than one generated lot';
  exception when others then
    if sqlerrm <> 'production OP must generate exactly one product lot' then raise; end if;
  end;

  perform public.finalizar_pcp_op(
    v_op_id,
    jsonb_build_array(jsonb_build_object(
      'tipo_produto','PI','produto_id',v_product_id,'quantidade',9,
      'observacao','Unico lote PI do smoke 0077'
    )),
    'aprovado',6.5,1,9,9,25,'Separador','Conferente','["Formulador"]'::jsonb,
    'Perda de processo de um litro'
  );

  select sum(custo_total) into v_cost
    from public.est_movimentos_mp_custo_alocacoes allocation
    join public.est_movimentos_mp movement on movement.id=allocation.movimento_saida_id
   where movement.origem_tabela='pcp_ordens_producao' and movement.origem_id=v_op_id::text;
  if v_cost <> 140 then raise exception 'FIFO cost expected 140, got %',v_cost; end if;

  select custo_perda_processo into v_loss from public.pcp_op_perdas_custos_atuais
   where op_id=v_op_id and moeda='BRL';
  if v_loss <> 14 then raise exception 'process loss expected 14, got %',v_loss; end if;

  select output.lote_pi_id into v_pi_lot_id from public.pcp_op_produtos_gerados output
   where output.op_id=v_op_id;
  select component.custo_total into v_cost
    from public.est_lotes_pi_custo_camadas layer
    join public.est_lotes_pi_custo_componentes component on component.lote_custo_id=layer.id
   where layer.lote_pi_id=v_pi_lot_id and component.moeda='BRL';
  if v_cost <> 126 then raise exception 'PI material cost expected 126, got %',v_cost; end if;

  select value.quantidade_base-coalesce(sum(allocation.quantidade_alocada),0) into v_remaining
    from public.est_movimentos_mp_valores value
    left join public.est_movimentos_mp_custo_alocacoes allocation
      on allocation.movimento_valor_id=value.id
   where value.movimento_mp_id=v_entry_2 group by value.id;
  if v_remaining <> 2 then raise exception 'second entry layer expected remaining 2, got %',v_remaining; end if;

  if (select count(*) from public.pcp_op_produtos_gerados where op_id=v_op_id) <> 1 then
    raise exception 'production OP did not preserve exactly one output';
  end if;
end;
$cost_layers$;

rollback;
\echo PG_VALIDATE_0077_COST_LAYERS_OK
