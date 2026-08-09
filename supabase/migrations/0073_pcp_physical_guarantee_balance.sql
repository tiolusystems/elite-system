-- PCP guarantees: lot-specific density and physical mass/volume balance.

insert into public.permission_actions(
  action_key, module, description, default_allowed, sort_order,
  runtime_module_key, runtime_access_kind
)
values (
  'pcp.guarantee.mp_lot.parameters.register', 'pcp',
  'Registrar parametros tecnicos versionados do lote de materia-prima',
  true, 313, 'pcp', 'write'
)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

create table public.cad_lote_mp_parametros_tecnicos (
  id bigint generated always as identity primary key,
  lote_mp_id bigint not null references public.est_lotes_mp(id) on delete restrict,
  densidade_kg_l numeric not null,
  data_referencia date not null,
  fonte text not null,
  documento_referencia text,
  justificativa text not null,
  supersedes_id bigint references public.cad_lote_mp_parametros_tecnicos(id) on delete restrict,
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint cad_lote_mp_parametros_densidade_check check (densidade_kg_l > 0),
  constraint cad_lote_mp_parametros_fonte_check check (
    fonte in ('manual', 'laboratorio', 'fornecedor')
  ),
  constraint cad_lote_mp_parametros_documento_check check (
    fonte = 'manual' or nullif(btrim(coalesce(documento_referencia, '')), '') is not null
  ),
  constraint cad_lote_mp_parametros_justificativa_check check (
    nullif(btrim(justificativa), '') is not null
  ),
  constraint cad_lote_mp_parametros_supersedes_self_check check (
    supersedes_id is null or supersedes_id <> id
  )
);

create index idx_cad_lote_mp_parametros_current
  on public.cad_lote_mp_parametros_tecnicos(lote_mp_id, data_referencia desc, id desc);
create index idx_cad_lote_mp_parametros_supersedes
  on public.cad_lote_mp_parametros_tecnicos(supersedes_id)
  where supersedes_id is not null;

create trigger trg_cad_lote_mp_parametros_append_only
before update or delete on public.cad_lote_mp_parametros_tecnicos
for each row execute function public.prevent_production_guarantee_changes();

create trigger trg_cad_lote_mp_parametros_no_truncate
before truncate on public.cad_lote_mp_parametros_tecnicos
for each statement execute function public.prevent_production_guarantee_changes();

alter table public.cad_lote_mp_parametros_tecnicos enable row level security;

create policy "active user read cad_lote_mp_parametros_tecnicos"
  on public.cad_lote_mp_parametros_tecnicos
  for select to authenticated
  using (public.current_actor_id() is not null);

grant select on public.cad_lote_mp_parametros_tecnicos to authenticated;
revoke insert, update, delete, truncate on public.cad_lote_mp_parametros_tecnicos from authenticated;
revoke all on public.cad_lote_mp_parametros_tecnicos from anon;

create view public.cad_lote_mp_parametros_tecnicos_atuais
with (security_invoker = true)
as
select current_parameter.*
from (
  select
    parameter.*,
    row_number() over (
      partition by parameter.lote_mp_id
      order by parameter.data_referencia desc, parameter.id desc
    ) as parameter_rank
  from public.cad_lote_mp_parametros_tecnicos parameter
) current_parameter
where current_parameter.parameter_rank = 1;

grant select on public.cad_lote_mp_parametros_tecnicos_atuais to authenticated;
revoke all on public.cad_lote_mp_parametros_tecnicos_atuais from anon, public;

create or replace function public.registrar_pcp_parametros_lote_mp(
  p_lote_mp_id bigint,
  p_densidade_kg_l numeric,
  p_data_referencia date,
  p_fonte text,
  p_documento_referencia text default null,
  p_justificativa text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lote record;
  v_fonte text := lower(nullif(btrim(p_fonte), ''));
  v_previous_id bigint;
  v_parameter_id bigint;
  v_actor uuid;
  v_before jsonb;
  v_after jsonb;
  v_permission_context jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'pcp.guarantee.mp_lot.parameters.register',
    'pcp',
    'cad_lote_mp_parametros_tecnicos',
    'field_risk',
    jsonb_build_object('lote_mp_id', p_lote_mp_id, 'event', 'register_mp_lot_parameters')
  );

  if p_lote_mp_id is null or p_lote_mp_id <= 0 then
    raise exception 'lote_mp_id is required';
  end if;
  if p_densidade_kg_l is null or p_densidade_kg_l <= 0 then
    raise exception 'densidade_kg_l must be greater than zero';
  end if;
  if p_data_referencia is null then
    raise exception 'data_referencia is required';
  end if;
  if v_fonte not in ('manual', 'laboratorio', 'fornecedor') then
    raise exception 'invalid MP lot parameter source';
  end if;
  if v_fonte in ('laboratorio', 'fornecedor')
     and nullif(btrim(p_documento_referencia), '') is null then
    raise exception 'documento_referencia is required for laboratorio or fornecedor';
  end if;
  if nullif(btrim(p_justificativa), '') is null then
    raise exception 'justificativa is required';
  end if;

  select lot.id, lot.codigo_lote, lot.status
    into v_lote
    from public.est_lotes_mp lot
   where lot.id = p_lote_mp_id
   for update;
  if not found then
    raise exception 'MP lot not found';
  end if;
  if v_lote.status = 'cancelado' then
    raise exception 'cancelled MP lot does not allow technical parameters';
  end if;

  select parameter.id, to_jsonb(parameter)
    into v_previous_id, v_before
    from public.cad_lote_mp_parametros_tecnicos parameter
   where parameter.lote_mp_id = p_lote_mp_id
   order by parameter.data_referencia desc, parameter.id desc
   limit 1;

  v_actor := public.current_actor_id();
  insert into public.cad_lote_mp_parametros_tecnicos(
    lote_mp_id, densidade_kg_l, data_referencia, fonte,
    documento_referencia, justificativa, supersedes_id, created_by
  ) values (
    p_lote_mp_id, p_densidade_kg_l, p_data_referencia, v_fonte,
    nullif(btrim(p_documento_referencia), ''), btrim(p_justificativa),
    v_previous_id, v_actor
  ) returning id into v_parameter_id;

  select to_jsonb(parameter) into v_after
    from public.cad_lote_mp_parametros_tecnicos parameter
   where parameter.id = v_parameter_id;

  perform public.log_audited_rpc_change(
    'pcp',
    'cad_lote_mp_parametros_tecnicos',
    v_parameter_id::text,
    'pcp.parametros_lote_mp_registrados',
    'pcp.guarantee.mp_lot.parameters.register',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'registrar_pcp_parametros_lote_mp',
      'lote_mp_id', p_lote_mp_id,
      'supersedes_id', v_previous_id,
      'correlation_id', concat('lote_mp:', p_lote_mp_id, ':parametros:', v_parameter_id)
    )
  );

  return v_parameter_id;
end;
$$;

revoke all on function public.registrar_pcp_parametros_lote_mp(
  bigint, numeric, date, text, text, text
) from public, anon;
grant execute on function public.registrar_pcp_parametros_lote_mp(
  bigint, numeric, date, text, text, text
) to authenticated;

create or replace function public.validate_pcp_guarantee_value_basis()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_unit_code text;
begin
  select unit.codigo_norm into v_unit_code
    from public.cad_unidades_medida unit
   where unit.id = new.unidade_id;
  if v_unit_code = 'percent' and new.valor > 100 then
    raise exception 'percentage guarantee must be between zero and 100';
  end if;
  return new;
end;
$$;

revoke all on function public.validate_pcp_guarantee_value_basis() from public, anon, authenticated;

drop trigger if exists trg_15_cad_garantia_produto_value on public.cad_garantias_produto_mapa;
create trigger trg_15_cad_garantia_produto_value
before insert on public.cad_garantias_produto_mapa
for each row execute function public.validate_pcp_guarantee_value_basis();

drop trigger if exists trg_15_cad_garantia_lote_value on public.cad_garantias_lote_mp;
create trigger trg_15_cad_garantia_lote_value
before insert on public.cad_garantias_lote_mp
for each row execute function public.validate_pcp_guarantee_value_basis();

alter table public.pcp_op_garantia_resultados
  drop constraint pcp_op_garantia_status_check,
  add constraint pcp_op_garantia_status_check check (
    status_resultado in (
      'atende', 'nao_atende', 'informativo', 'sem_referencia_mapa',
      'sem_dados_lote', 'unidade_incompativel', 'base_incompleta'
    )
  );

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

        if v_consumption.consumption_unit_code = 'kg' then
          v_consumed_mass_kg := v_consumption.quantidade_consumida;
          if v_density is not null then v_consumed_volume_l := v_consumed_mass_kg / v_density; end if;
        elsif v_consumption.consumption_unit_code = 'l' then
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
  'Calcula garantias por balanco fisico dos lotes consumidos contra massa e volume finais do CQ. Base incompleta nunca gera valor estimado.';

revoke all on function public.calcular_pcp_garantias_op(bigint, text) from public, anon;
grant execute on function public.calcular_pcp_garantias_op(bigint, text) to authenticated;
