-- DEC-013: operational formulas are expressed per 1 L of finished product.
-- Legacy versions remain readable and are never reinterpreted automatically.

do $$
declare
  v_actor uuid := public.historical_migration_actor_id();
begin
  if v_actor is null then raise exception 'Migracao Historica system actor is required by DEC-013'; end if;
  insert into public.cad_unidades_medida(codigo, nome, simbolo, dimensao, status, origem_dados, created_by)
  values
    ('kg_l_produzido', 'Quilograma por litro produzido', 'kg/L produzido', 'concentracao', 'active', 'sistema', v_actor),
    ('l_l_produzido', 'Litro por litro produzido', 'L/L produzido', 'concentracao', 'active', 'sistema', v_actor),
    ('un_l_produzido', 'Unidade por litro produzido', 'UN/L produzido', 'concentracao', 'active', 'sistema', v_actor)
  on conflict (codigo_norm) do nothing;
end;
$$;

alter table public.pcp_formula_versoes
  add column if not exists base_calculo text not null default 'legado_nao_comprovado';

alter table public.pcp_formula_versoes disable trigger trg_pcp_formula_versoes_no_update;
update public.pcp_formula_versoes set base_calculo = case
  when tipo_receita = 'mapa' then 'documental_mapa' else 'legado_nao_comprovado' end;
alter table public.pcp_formula_versoes enable trigger trg_pcp_formula_versoes_no_update;

alter table public.pcp_formula_versoes
  drop constraint if exists pcp_formula_versoes_base_calculo_check,
  add constraint pcp_formula_versoes_base_calculo_check check (
    (tipo_receita = 'producao' and base_calculo in ('por_litro', 'legado_nao_comprovado'))
    or (tipo_receita = 'mapa' and base_calculo = 'documental_mapa')
  );

alter table public.pcp_ordens_producao
  add column if not exists volume_planejado_l numeric,
  add column if not exists formula_base_calculo text,
  drop constraint if exists pcp_ordens_volume_planejado_l_check,
  add constraint pcp_ordens_volume_planejado_l_check check (volume_planejado_l is null or volume_planejado_l > 0);

alter table public.pcp_op_componentes_planejados
  add column if not exists quantidade_formula_por_litro numeric,
  add column if not exists volume_planejado_l numeric,
  add column if not exists unidade_formula_id bigint references public.cad_unidades_medida(id) on delete restrict,
  drop constraint if exists pcp_op_comp_formula_por_litro_check,
  drop constraint if exists pcp_op_comp_volume_l_check,
  add constraint pcp_op_comp_formula_por_litro_check check (quantidade_formula_por_litro is null or quantidade_formula_por_litro > 0),
  add constraint pcp_op_comp_volume_l_check check (volume_planejado_l is null or volume_planejado_l > 0);

create or replace function public.set_pcp_formula_basis_on_insert()
returns trigger language plpgsql set search_path = public as $$
declare v_requested_basis text := nullif(current_setting('elite.formula_basis', true), '');
begin
  if new.tipo_receita = 'mapa' then new.base_calculo := 'documental_mapa';
  elsif v_requested_basis = 'por_litro' then new.base_calculo := 'por_litro';
  else new.base_calculo := 'legado_nao_comprovado'; end if;
  return new;
end;
$$;

drop trigger if exists trg_00_pcp_formula_basis on public.pcp_formula_versoes;
create trigger trg_00_pcp_formula_basis before insert on public.pcp_formula_versoes
for each row execute function public.set_pcp_formula_basis_on_insert();

create or replace function public.create_pcp_formula_versao(
  p_produto_id bigint, p_tipo_receita text, p_justificativa text,
  p_componentes_jsonb jsonb default '[]'::jsonb, p_observacao text default null
) returns bigint language plpgsql security definer set search_path = public as $$
declare
  v_action_key text; v_component jsonb; v_unit record;
  v_formula_id bigint;
  v_normalized_components jsonb := '[]'::jsonb;
begin
  v_action_key := public.resolve_pcp_formula_action_key(p_produto_id, p_tipo_receita);
  perform public.require_current_user_permission(v_action_key);
  if p_tipo_receita = 'producao' then
    if jsonb_typeof(p_componentes_jsonb) <> 'array' or jsonb_array_length(p_componentes_jsonb) = 0 then
      raise exception 'production recipe requires at least one component';
    end if;
    perform set_config('elite.formula_basis', 'por_litro', true);
  else
    perform set_config('elite.formula_basis', 'documental_mapa', true);
  end if;

  for v_component in select value from jsonb_array_elements(p_componentes_jsonb) loop
    if nullif(v_component->>'unidade_id', '') is null then raise exception 'governed formula unit is required'; end if;
    select unit.id, unit.codigo into v_unit from public.cad_unidades_medida unit
     where unit.id = (v_component->>'unidade_id')::bigint and unit.status = 'active'
       and (p_tipo_receita <> 'producao'
         or unit.codigo in ('kg_l_produzido', 'l_l_produzido', 'un_l_produzido'));
    if not found then
      if p_tipo_receita = 'producao' then raise exception 'invalid per-liter formula unit';
      else raise exception 'invalid governed formula unit'; end if;
    end if;
    v_normalized_components := v_normalized_components || jsonb_build_array(
      (v_component - 'unidade') || jsonb_build_object('unidade', v_unit.codigo, 'unidade_id', v_unit.id));
  end loop;
  v_formula_id := public.create_pcp_formula_versao_impl_0037(
    p_produto_id, p_tipo_receita, p_justificativa, v_normalized_components, p_observacao);
  perform set_config('elite.formula_basis', '', true);
  return v_formula_id;
end;
$$;

create or replace function public.create_pcp_op(
  p_formula_versao_id bigint, p_tipo_op text,
  p_quantidade_planejada numeric default null, p_observacao text default null
) returns bigint language plpgsql security definer set search_path = public as $$
declare v_formula public.pcp_formula_versoes%rowtype; v_op_id bigint;
begin
  perform public.require_current_user_permission('pcp.op.create');
  if p_tipo_op = 'mapa_documental' then raise exception 'MAPA documentary OP must be emitted with its packaging order'; end if;
  if p_quantidade_planejada is null or p_quantidade_planejada <= 0 then
    raise exception 'planned production volume in liters is required';
  end if;
  select * into v_formula from public.pcp_formula_versoes where id = p_formula_versao_id;
  if not found then raise exception 'formula version not found'; end if;
  if v_formula.tipo_receita <> 'producao' then raise exception 'operational OP requires production recipe'; end if;
  if v_formula.base_calculo <> 'por_litro' then raise exception 'legacy formula requires a reviewed per-liter version'; end if;
  v_op_id := public.create_pcp_op_operational_impl_0069(
    p_formula_versao_id, p_tipo_op, p_quantidade_planejada, p_observacao);
  update public.pcp_ordens_producao set volume_planejado_l = p_quantidade_planejada,
    formula_base_calculo = 'por_litro' where id = v_op_id;
  update public.pcp_op_componentes_planejados component
     set quantidade_formula_por_litro = item.quantidade,
         volume_planejado_l = p_quantidade_planejada,
         unidade_formula_id = item.unidade_id,
         quantidade_planejada = item.quantidade * p_quantidade_planejada
    from public.pcp_formula_itens item
   where component.op_id = v_op_id and component.formula_item_id = item.id;
  return v_op_id;
end;
$$;

comment on column public.pcp_formula_versoes.base_calculo is
  'por_litro for governed operational formulas; legacy versions are never reinterpreted; MAPA is documentary.';
comment on column public.pcp_op_componentes_planejados.quantidade_formula_por_litro is
  'Formula quantity snapshot per liter used to calculate the OP total.';

revoke all on function public.set_pcp_formula_basis_on_insert() from public, anon, authenticated;
revoke all on function public.create_pcp_formula_versao(bigint, text, text, jsonb, text) from public, anon;
revoke all on function public.create_pcp_op(bigint, text, numeric, text) from public, anon;
grant execute on function public.create_pcp_formula_versao(bigint, text, text, jsonb, text) to authenticated;
grant execute on function public.create_pcp_op(bigint, text, numeric, text) to authenticated;
