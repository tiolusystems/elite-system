-- Compatibility between per-liter operational formula units and physical guarantee calculation.
-- Component quantities are already scaled to the OP volume before consumption is recorded.

create or replace function public.calcular_pcp_garantias_op(
  p_op_id bigint,
  p_justificativa text
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_op record;
  v_output record;
  v_target record;
  v_consumption record;
  v_lot_guarantee record;
  v_reference record;
  v_cq record;
  v_calculo_versao integer;
  v_completed_date date;
  v_status_resultado text;
  v_atende boolean;
  v_output_count integer := 0;
  v_output_result_count integer;
  v_result_count integer := 0;
  v_before jsonb;
  v_after jsonb;
  v_permission_context jsonb;
  v_correlation_id text;
  v_inputs jsonb;
  v_missing jsonb;
  v_total_nutrient_kg numeric;
  v_consumed_mass_kg numeric;
  v_consumed_volume_l numeric;
  v_density_id bigint;
  v_density numeric;
  v_has_incomplete_basis boolean;
  v_has_missing_guarantee boolean;
  v_calculated numeric;
begin
  v_permission_context := public.begin_audited_rpc(
    'pcp.guarantee.calculate',
    'pcp',
    'pcp_ordens_producao',
    'target_event',
    jsonb_build_object('op_id', p_op_id, 'event', 'calculate_physical_guarantees')
  );

  if p_op_id is null or p_op_id <= 0 then raise exception 'op_id is required'; end if;
  if nullif(btrim(p_justificativa), '') is null then raise exception 'justificativa is required'; end if;

  perform pg_advisory_xact_lock(hashtextextended(concat('elite:pcp:guarantee:', p_op_id), 0));

  select op.* into v_op
    from public.pcp_ordens_producao op
   where op.id = p_op_id
   for update;
  if not found then raise exception 'OP not found'; end if;
  if v_op.status <> 'completed' then raise exception 'OP must be completed before guarantee calculation'; end if;
  if v_op.tipo_op = 'mapa_documental' then raise exception 'MAPA documental OP has no generated lot guarantee calculation'; end if;

  select cq.* into v_cq
    from public.pcp_op_cq_resultados cq
   where cq.op_id = p_op_id;
  if not found then raise exception 'completed operational OP requires CQ physical basis'; end if;

  v_completed_date := coalesce(v_op.completed_at::date, current_date);
  select coalesce(max(result.calculo_versao), 0) + 1 into v_calculo_versao
    from public.pcp_op_garantia_resultados result where result.op_id = p_op_id;
  select coalesce(jsonb_agg(to_jsonb(result) order by result.produto_gerado_id, result.id), '[]'::jsonb)
    into v_before
    from public.pcp_op_garantia_resultados result
   where result.op_id = p_op_id and result.calculo_versao = v_calculo_versao - 1;

  v_actor := public.current_actor_id();
  v_correlation_id := concat('pcp_op:', p_op_id, ':physical_guarantee:', v_calculo_versao);

  for v_output in
    select output.*, case when output.tipo_produto = 'PA' then item.produto_id else output.produto_id end as produto_base_id
      from public.pcp_op_produtos_gerados output
      left join public.cad_produto_embalagens item on item.id = output.produto_embalagem_id
     where output.op_id = p_op_id order by output.id
  loop
    v_output_count := v_output_count + 1;
    v_output_result_count := 0;

    for v_target in
      with reference_keys as (
        select distinct on (guarantee.nutriente_id)
               guarantee.nutriente_id, guarantee.unidade_id
          from public.cad_garantias_produto_mapa guarantee
         where guarantee.produto_id = v_output.produto_base_id
           and guarantee.natureza = 'mapa_documental'
           and guarantee.review_status = 'approved'
           and (guarantee.vigencia_inicio is null or guarantee.vigencia_inicio <= v_completed_date)
           and (guarantee.vigencia_fim is null or guarantee.vigencia_fim >= v_completed_date)
         order by guarantee.nutriente_id,
                  coalesce(guarantee.vigencia_inicio, '-infinity'::date) desc,
                  guarantee.id desc
      ), lot_keys as (
        select distinct on (guarantee.nutriente_id)
               guarantee.nutriente_id, guarantee.unidade_id
          from public.pcp_op_consumos_componentes consumption
          join public.cad_garantias_lote_mp guarantee on guarantee.lote_mp_id = consumption.lote_mp_id
         where consumption.op_id = p_op_id
           and consumption.tipo_componente = 'MP'
           and guarantee.review_status = 'approved'
           and guarantee.data_referencia <= v_completed_date
         order by guarantee.nutriente_id, guarantee.data_referencia desc, guarantee.id desc
      ), target_keys as (
        select reference.nutriente_id, reference.unidade_id
          from reference_keys reference
        union all
        select lot.nutriente_id, lot.unidade_id
          from lot_keys lot
         where not exists (
           select 1 from reference_keys reference
            where reference.nutriente_id = lot.nutriente_id
         )
      )
      select nutrient.id as nutriente_id, nutrient.nome as nutriente,
             unit.id as unidade_id, unit.simbolo as unidade, unit.codigo_norm as unit_code
        from target_keys key_row
        join public.cad_nutrientes nutrient on nutrient.id = key_row.nutriente_id
        join public.cad_unidades_medida unit on unit.id = key_row.unidade_id
       order by nutrient.nome, unit.codigo_norm
    loop
      v_inputs := '[]'::jsonb;
      v_missing := '[]'::jsonb;
      v_total_nutrient_kg := 0;
      v_has_incomplete_basis := false;
      v_has_missing_guarantee := false;
      v_calculated := null;
      v_atende := null;

      select guarantee.* into v_reference
        from public.cad_garantias_produto_mapa guarantee
       where guarantee.produto_id = v_output.produto_base_id
         and guarantee.nutriente_id = v_target.nutriente_id
         and guarantee.unidade_id = v_target.unidade_id
         and guarantee.natureza = 'mapa_documental'
         and guarantee.review_status = 'approved'
         and (guarantee.vigencia_inicio is null or guarantee.vigencia_inicio <= v_completed_date)
         and (guarantee.vigencia_fim is null or guarantee.vigencia_fim >= v_completed_date)
       order by coalesce(guarantee.vigencia_inicio, '-infinity'::date) desc, guarantee.id desc
       limit 1;

      for v_consumption in
        select consumption.*, component.materia_prima_id,
               unit.codigo_norm as consumption_unit_code
          from public.pcp_op_consumos_componentes consumption
          join public.pcp_op_componentes_planejados component on component.id = consumption.op_componente_id
          left join public.pcp_formula_itens formula_item on formula_item.id = component.formula_item_id
          left join public.cad_unidades_medida unit on unit.id = formula_item.unidade_id
         where consumption.op_id = p_op_id and consumption.tipo_componente = 'MP'
         order by consumption.id
      loop
        v_consumed_mass_kg := null;
        v_consumed_volume_l := null;
        v_density_id := null;
        v_density := null;

        select parameter.id, parameter.densidade_kg_l
          into v_density_id, v_density
          from public.cad_lote_mp_parametros_tecnicos parameter
         where parameter.lote_mp_id = v_consumption.lote_mp_id
           and parameter.data_referencia <= v_completed_date
         order by parameter.data_referencia desc, parameter.id desc
         limit 1;

        select guarantee.*, unit.codigo_norm as guarantee_unit_code
          into v_lot_guarantee
          from public.cad_garantias_lote_mp guarantee
          join public.cad_unidades_medida unit on unit.id = guarantee.unidade_id
         where guarantee.lote_mp_id = v_consumption.lote_mp_id
           and guarantee.nutriente_id = v_target.nutriente_id
           and guarantee.review_status = 'approved'
           and guarantee.data_referencia <= v_completed_date
           and unit.codigo_norm in ('percent', 'kg/l')
         order by case when guarantee.unidade_id = v_target.unidade_id then 0 else 1 end,
                  guarantee.data_referencia desc, guarantee.id desc
         limit 1;

        if not found then
          v_has_missing_guarantee := true;
          v_missing := v_missing || jsonb_build_array(jsonb_build_object(
            'lote_mp_id', v_consumption.lote_mp_id,
            'materia_prima_id', v_consumption.materia_prima_id,
            'motivo', 'garantia_lote_ausente'
          ));
          continue;
        end if;

        if v_consumption.consumption_unit_code in ('kg', 'kg_l_produzido') then
          v_consumed_mass_kg := v_consumption.quantidade_consumida;
          if v_density is not null then v_consumed_volume_l := v_consumed_mass_kg / v_density; end if;
        elsif v_consumption.consumption_unit_code in ('l', 'l_l_produzido') then
          v_consumed_volume_l := v_consumption.quantidade_consumida;
          if v_density is not null then v_consumed_mass_kg := v_consumed_volume_l * v_density; end if;
        else
          v_has_incomplete_basis := true;
          v_missing := v_missing || jsonb_build_array(jsonb_build_object(
            'lote_mp_id', v_consumption.lote_mp_id,
            'motivo', 'unidade_consumo_nao_suportada',
            'unidade', v_consumption.consumption_unit_code
          ));
          continue;
        end if;

        if v_lot_guarantee.guarantee_unit_code = 'percent' then
          if v_consumed_mass_kg is null then
            v_has_incomplete_basis := true;
            v_missing := v_missing || jsonb_build_array(jsonb_build_object(
              'lote_mp_id', v_consumption.lote_mp_id,
              'motivo', 'densidade_lote_ausente_para_percentual'
            ));
            continue;
          end if;
          v_total_nutrient_kg := v_total_nutrient_kg
            + (v_consumed_mass_kg * v_lot_guarantee.valor / 100);
        elsif v_lot_guarantee.guarantee_unit_code = 'kg/l' then
          if v_consumed_volume_l is null then
            v_has_incomplete_basis := true;
            v_missing := v_missing || jsonb_build_array(jsonb_build_object(
              'lote_mp_id', v_consumption.lote_mp_id,
              'motivo', 'densidade_lote_ausente_para_concentracao'
            ));
            continue;
          end if;
          v_total_nutrient_kg := v_total_nutrient_kg
            + (v_consumed_volume_l * v_lot_guarantee.valor);
        else
          v_has_incomplete_basis := true;
          continue;
        end if;

        v_inputs := v_inputs || jsonb_build_array(jsonb_build_object(
          'consumo_id', v_consumption.id,
          'lote_mp_id', v_consumption.lote_mp_id,
          'materia_prima_id', v_consumption.materia_prima_id,
          'quantidade_consumida', v_consumption.quantidade_consumida,
          'unidade_consumo', v_consumption.consumption_unit_code,
          'parametro_lote_id', v_density_id,
          'densidade_kg_l', v_density,
          'massa_consumida_kg', v_consumed_mass_kg,
          'volume_consumido_l', v_consumed_volume_l,
          'garantia_lote_id', v_lot_guarantee.id,
          'valor_garantia', v_lot_guarantee.valor,
          'unidade_garantia', v_lot_guarantee.guarantee_unit_code
        ));
      end loop;

      if v_has_missing_guarantee then
        v_status_resultado := 'sem_dados_lote';
      elsif v_has_incomplete_basis then
        v_status_resultado := 'base_incompleta';
      elsif v_target.unit_code = 'percent' then
        v_calculated := v_total_nutrient_kg / nullif(v_cq.massa_kg, 0) * 100;
      elsif v_target.unit_code = 'kg/l' then
        v_calculated := v_total_nutrient_kg / nullif(v_cq.volume_l, 0);
      else
        v_status_resultado := 'unidade_incompativel';
      end if;

      if not v_has_missing_guarantee and not v_has_incomplete_basis
         and v_target.unit_code in ('percent', 'kg/l') then
        if v_reference.id is null then
          v_status_resultado := 'sem_referencia_mapa';
        elsif v_reference.tipo_limite = 'minimo' then
          v_atende := v_calculated >= v_reference.valor;
          v_status_resultado := case when v_atende then 'atende' else 'nao_atende' end;
        elsif v_reference.tipo_limite = 'maximo' then
          v_atende := v_calculated <= v_reference.valor;
          v_status_resultado := case when v_atende then 'atende' else 'nao_atende' end;
        elsif v_reference.tipo_limite = 'faixa' then
          v_atende := v_calculated between v_reference.valor and v_reference.valor_maximo;
          v_status_resultado := case when v_atende then 'atende' else 'nao_atende' end;
        else
          v_status_resultado := 'informativo';
        end if;
      end if;

      insert into public.pcp_op_garantia_resultados(
        op_id, produto_gerado_id, produto_id, calculo_versao,
        nutriente, unidade, valor_calculado, garantia_produto_id,
        tipo_limite, valor_referencia, valor_maximo_referencia,
        status_resultado, atende, base_calculo_json, justificativa,
        correlation_id, created_by, nutriente_id, unidade_id
      ) values (
        p_op_id, v_output.id, v_output.produto_base_id, v_calculo_versao,
        v_target.nutriente, v_target.unidade, v_calculated, v_reference.id,
        v_reference.tipo_limite, v_reference.valor, v_reference.valor_maximo,
        v_status_resultado, v_atende,
        jsonb_build_object(
          'metodo', 'balanco_fisico_v1',
          'inputs', v_inputs,
          'pendencias', v_missing,
          'massa_nutriente_kg', case when v_calculated is null then null else v_total_nutrient_kg end,
          'cq', jsonb_build_object(
            'densidade_kg_l', v_cq.densidade_kg_l,
            'volume_l', v_cq.volume_l,
            'massa_kg', v_cq.massa_kg
          ),
          'unidade_resultado', v_target.unit_code,
          'op_completed_date', v_completed_date,
          'calculation_version', v_calculo_versao
        ),
        btrim(p_justificativa), v_correlation_id, v_actor,
        v_target.nutriente_id, v_target.unidade_id
      );
      v_output_result_count := v_output_result_count + 1;
      v_result_count := v_result_count + 1;
    end loop;

    if v_output_result_count = 0 then
      raise exception 'guarantee calculation has no configured nutrient basis';
    end if;
  end loop;

  if v_output_count = 0 then raise exception 'completed OP has no generated products'; end if;

  select coalesce(jsonb_agg(to_jsonb(result) order by result.produto_gerado_id, result.id), '[]'::jsonb)
    into v_after from public.pcp_op_garantia_resultados result
   where result.op_id = p_op_id and result.calculo_versao = v_calculo_versao;

  perform public.log_audited_rpc_change(
    'pcp', 'pcp_ordens_producao', p_op_id::text,
    'pcp.garantias_op_calculadas', 'pcp.guarantee.calculate',
    v_permission_context, v_before, v_after,
    jsonb_build_object(
      'source', 'calcular_pcp_garantias_op',
      'method', 'balanco_fisico_v1',
      'op_id', p_op_id,
      'calculo_versao', v_calculo_versao,
      'result_count', v_result_count,
      'correlation_id', v_correlation_id
    )
  );
  return v_calculo_versao;
end;
$$;

comment on function public.calcular_pcp_garantias_op(bigint, text) is
  'Calcula garantias por balanco fisico e reconhece unidades operacionais por litro ja escaladas na OP.';

revoke all on function public.calcular_pcp_garantias_op(bigint, text) from public, anon;
grant execute on function public.calcular_pcp_garantias_op(bigint, text) to authenticated;
