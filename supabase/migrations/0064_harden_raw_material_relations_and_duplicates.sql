-- UX-01C.4 final technical gate: relational units and duplicate protection.

create or replace function public.normalize_cad_mp_sku(p_value text)
returns text
language sql
immutable
parallel safe
set search_path = public
as $$
  select nullif(upper(regexp_replace(btrim(p_value), '[^[:alnum:]]+', '', 'g')), '')
$$;

revoke all on function public.normalize_cad_mp_sku(text) from public, anon, authenticated;

do $$
begin
  if exists (
    select 1
      from public.cad_materias_primas
     group by public.normalize_cad_mp_sku(sku_corrigido)
    having count(*) > 1
  ) then
    raise exception 'normalized duplicate SKU exists; reconcile before migration 0064';
  end if;
end;
$$;

create unique index cad_materias_primas_sku_norm_key
  on public.cad_materias_primas(public.normalize_cad_mp_sku(sku_corrigido));

comment on index public.cad_materias_primas_sku_norm_key is
  'Absolute SKU uniqueness after removing case, whitespace and formatting differences.';

create or replace function public.find_cad_materia_prima_possible_duplicates(
  p_nome text,
  p_codigo_legado text default null
)
returns table (
  materia_prima_id bigint,
  sku_corrigido text,
  nome text,
  tipo_insumo_nome text,
  unidade_nome text,
  codigo_legado text,
  motivos text[]
)
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_permission('cadastros.materias_primas.create');
  if public.normalize_catalog_term(p_nome) is null then
    raise exception 'nome is required';
  end if;

  return query
  select
    mp.id,
    mp.sku_corrigido,
    mp.nome,
    tipo.nome,
    unidade.nome,
    mp.codigo_legado,
    array_remove(array[
      case when public.normalize_catalog_term(mp.nome) = public.normalize_catalog_term(p_nome)
        then 'Mesmo nome normalizado' end,
      case when nullif(public.normalize_catalog_term(p_codigo_legado), '') is not null
             and public.normalize_catalog_term(mp.codigo_legado) = public.normalize_catalog_term(p_codigo_legado)
        then 'Mesmo codigo legado' end
    ], null)::text[]
  from public.cad_materias_primas mp
  left join public.cad_tipos_insumo tipo on tipo.id = mp.tipo_insumo_id
  join public.cad_unidades_medida unidade on unidade.id = mp.unidade_base_estoque_id
  where public.normalize_catalog_term(mp.nome) = public.normalize_catalog_term(p_nome)
     or (
       nullif(public.normalize_catalog_term(p_codigo_legado), '') is not null
       and public.normalize_catalog_term(mp.codigo_legado) = public.normalize_catalog_term(p_codigo_legado)
     )
  order by mp.nome, mp.id;
end;
$$;

revoke all on function public.find_cad_materia_prima_possible_duplicates(text, text) from public, anon;
grant execute on function public.find_cad_materia_prima_possible_duplicates(text, text) to authenticated;

-- Keep the compatibility signature, but make the legacy free-text field immutable.
create or replace function public.update_cad_materia_prima_identity(
  p_materia_prima_id bigint,
  p_nome text,
  p_nome_norm text,
  p_tipo text default null,
  p_motivo text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_before jsonb;
  v_after jsonb;
  v_permission_context jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'cadastros.materias_primas.update.identity', 'cadastros', 'cad_materias_primas',
    'field_risk', jsonb_build_object('correlation_id', 'materia_prima:' || p_materia_prima_id || ':identity')
  );
  if nullif(btrim(p_tipo), '') is not null then raise exception 'legacy free-text input type is read-only'; end if;
  if nullif(btrim(p_nome), '') is null or nullif(btrim(p_nome_norm), '') is null then raise exception 'nome is required'; end if;
  if nullif(btrim(p_motivo), '') is null then raise exception 'motivo is required'; end if;
  select to_jsonb(mp) into v_before from public.cad_materias_primas mp where mp.id = p_materia_prima_id for update;
  if not found then raise exception 'materia-prima not found'; end if;
  v_actor := public.current_actor_id();
  update public.cad_materias_primas
     set nome = btrim(p_nome), nome_norm = btrim(p_nome_norm), updated_by = v_actor
   where id = p_materia_prima_id;
  select to_jsonb(mp) into v_after from public.cad_materias_primas mp where mp.id = p_materia_prima_id;
  perform public.log_audited_rpc_change(
    'cadastros', 'cad_materias_primas', p_materia_prima_id::text,
    'cadastros.materia_prima_identity_updated', 'cadastros.materias_primas.update.identity',
    v_permission_context, v_before, v_after,
    jsonb_build_object('motivo', btrim(p_motivo), 'legacy_tipo_unchanged', true), 'database_rpc'
  );
  return p_materia_prima_id;
end;
$$;

drop function public.create_cad_materia_prima_governada(text, text, text, text, bigint, text, text, numeric, numeric, text, text, text, jsonb);

create function public.create_cad_materia_prima_governada(
  p_nome text,
  p_nome_norm text,
  p_sku_corrigido text,
  p_unidade_base_estoque_id bigint,
  p_tipo_insumo_id bigint default null,
  p_status text default 'active',
  p_codigo_legado text default null,
  p_densidade numeric default null,
  p_estoque_minimo numeric default null,
  p_ncm text default null,
  p_ibama text default null,
  p_codigo_ads text default null,
  p_payload_origem_json jsonb default '{}'::jsonb,
  p_confirmar_possivel_duplicidade boolean default false,
  p_motivo_duplicidade text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_id bigint;
  v_after jsonb;
  v_permission_context jsonb;
  v_unit public.cad_unidades_medida%rowtype;
  v_candidate_ids bigint[];
begin
  v_permission_context := public.begin_audited_rpc(
    'cadastros.materias_primas.create', 'cadastros', 'cad_materias_primas',
    'field_risk', jsonb_build_object('correlation_id', gen_random_uuid()::text, 'governed_relations', true)
  );
  if nullif(btrim(p_nome), '') is null or nullif(btrim(p_nome_norm), '') is null then raise exception 'nome is required'; end if;
  if public.normalize_cad_mp_sku(p_sku_corrigido) is null then raise exception 'sku_corrigido is required'; end if;
  if p_status not in ('active', 'inactive', 'pending_review') then raise exception 'invalid status'; end if;
  if p_densidade is not null and p_densidade <= 0 then raise exception 'densidade must be greater than zero'; end if;
  if p_estoque_minimo is not null and p_estoque_minimo < 0 then raise exception 'estoque_minimo must be non-negative'; end if;
  select * into v_unit from public.cad_unidades_medida where id = p_unidade_base_estoque_id and status = 'active';
  if not found then raise exception 'active base unit not found'; end if;
  if p_tipo_insumo_id is not null and not exists (
    select 1 from public.cad_tipos_insumo where id = p_tipo_insumo_id and status = 'active'
  ) then raise exception 'active input type not found'; end if;

  select array_agg(candidate.materia_prima_id order by candidate.materia_prima_id)
    into v_candidate_ids
    from public.find_cad_materia_prima_possible_duplicates(p_nome, p_codigo_legado) candidate;
  if coalesce(cardinality(v_candidate_ids), 0) > 0 then
    if not p_confirmar_possivel_duplicidade then
      raise exception 'possible raw material duplicate requires confirmation';
    end if;
    if nullif(btrim(p_motivo_duplicidade), '') is null then
      raise exception 'duplicate confirmation reason is required';
    end if;
  end if;

  v_actor := public.current_actor_id();
  insert into public.cad_materias_primas(
    codigo_legado, sku_corrigido, nome, nome_norm, unidade_base_estoque, unidade_base_estoque_id,
    status, tipo, tipo_insumo_id, tipo_insumo_review_status, tipo_insumo_source,
    densidade, estoque_minimo, ncm, ibama, codigo_ads, payload_origem_json, created_by, updated_by
  ) values (
    nullif(btrim(p_codigo_legado), ''), upper(btrim(p_sku_corrigido)), btrim(p_nome), btrim(p_nome_norm),
    v_unit.simbolo, v_unit.id, p_status, null, p_tipo_insumo_id,
    case when p_tipo_insumo_id is null then 'pending_review' else 'approved' end,
    case when p_tipo_insumo_id is null then null else 'manual_governado' end,
    p_densidade, p_estoque_minimo, public.validate_cad_mp_ncm(p_ncm),
    nullif(btrim(p_ibama), ''), nullif(btrim(p_codigo_ads), ''),
    coalesce(p_payload_origem_json, '{}'::jsonb), v_actor, v_actor
  ) returning id into v_id;
  select to_jsonb(mp) into v_after from public.cad_materias_primas mp where mp.id = v_id;
  perform public.log_audited_rpc_change(
    'cadastros', 'cad_materias_primas', v_id::text, 'cadastros.materia_prima_created',
    'cadastros.materias_primas.create', v_permission_context, null, v_after,
    jsonb_build_object(
      'source', 'create_cad_materia_prima_governada',
      'possible_duplicate_confirmed', coalesce(cardinality(v_candidate_ids), 0) > 0,
      'candidate_ids', coalesce(to_jsonb(v_candidate_ids), '[]'::jsonb),
      'duplicate_reason', nullif(btrim(p_motivo_duplicidade), '')
    ), 'database_rpc'
  );
  return v_id;
end;
$$;

revoke all on function public.create_cad_materia_prima_governada(text, text, text, bigint, bigint, text, text, numeric, numeric, text, text, text, jsonb, boolean, text) from public, anon;
grant execute on function public.create_cad_materia_prima_governada(text, text, text, bigint, bigint, text, text, numeric, numeric, text, text, text, jsonb, boolean, text) to authenticated;

create or replace function public.update_cad_materia_prima_technical_governada(
  p_materia_prima_id bigint,
  p_unidade_base_estoque_id bigint,
  p_densidade numeric default null,
  p_motivo text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_before jsonb;
  v_after jsonb;
  v_unit public.cad_unidades_medida%rowtype;
  v_permission_context jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'cadastros.materias_primas.update.technical', 'cadastros', 'cad_materias_primas',
    'field_risk', jsonb_build_object('correlation_id', 'materia_prima:' || p_materia_prima_id || ':technical')
  );
  if p_densidade is not null and p_densidade <= 0 then raise exception 'densidade must be greater than zero'; end if;
  if nullif(btrim(p_motivo), '') is null then raise exception 'motivo is required'; end if;
  select * into v_unit from public.cad_unidades_medida where id = p_unidade_base_estoque_id and status = 'active';
  if not found then raise exception 'active base unit not found'; end if;
  select to_jsonb(mp) into v_before from public.cad_materias_primas mp where mp.id = p_materia_prima_id for update;
  if not found then raise exception 'materia-prima not found'; end if;
  v_actor := public.current_actor_id();
  update public.cad_materias_primas
     set unidade_base_estoque_id = v_unit.id, unidade_base_estoque = v_unit.simbolo,
         densidade = p_densidade, updated_by = v_actor
   where id = p_materia_prima_id;
  select to_jsonb(mp) into v_after from public.cad_materias_primas mp where mp.id = p_materia_prima_id;
  perform public.log_audited_rpc_change(
    'cadastros', 'cad_materias_primas', p_materia_prima_id::text,
    'cadastros.materia_prima_technical_updated', 'cadastros.materias_primas.update.technical',
    v_permission_context, v_before, v_after,
    jsonb_build_object('motivo', btrim(p_motivo), 'unit_relation_governed', true), 'database_rpc'
  );
  return p_materia_prima_id;
end;
$$;

revoke all on function public.update_cad_materia_prima_technical_governada(bigint, bigint, numeric, text) from public, anon;
grant execute on function public.update_cad_materia_prima_technical_governada(bigint, bigint, numeric, text) to authenticated;
