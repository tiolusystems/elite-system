insert into public.permission_actions(action_key, module, description, default_allowed, sort_order)
values
  ('cadastros.materias_primas.update.identity', 'cadastros', 'Editar identidade de materia-prima', true, 78),
  ('cadastros.materias_primas.update.sku', 'cadastros', 'Editar SKU de materia-prima', true, 79),
  ('cadastros.materias_primas.update.technical', 'cadastros', 'Editar dados tecnicos de materia-prima', true, 80),
  ('cadastros.materias_primas.update.stock_policy', 'cadastros', 'Editar politica de estoque de materia-prima', true, 81),
  ('cadastros.materias_primas.update.regulatory', 'cadastros', 'Editar dados regulatorios de materia-prima', true, 82),
  ('cadastros.materias_primas.deactivate', 'cadastros', 'Desativar materia-prima', true, 83)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order;

create or replace function public.validate_cad_mp_ncm(p_ncm text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ncm text;
begin
  v_ncm := nullif(regexp_replace(coalesce(p_ncm, ''), '[^0-9]', '', 'g'), '');

  if v_ncm is not null and v_ncm !~ '^[0-9]{8}$' then
    raise exception 'ncm must have exactly 8 digits';
  end if;

  return v_ncm;
end;
$$;

revoke all on function public.validate_cad_mp_ncm(text) from public;

create or replace function public.validate_cad_mp_sku(p_sku_corrigido text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sku text;
begin
  v_sku := upper(nullif(trim(p_sku_corrigido), ''));

  if v_sku is null then
    raise exception 'sku_corrigido is required';
  end if;
  if v_sku ~ '\s' then
    raise exception 'sku_corrigido cannot contain whitespace';
  end if;
  if char_length(v_sku) > 80 then
    raise exception 'sku_corrigido is too long';
  end if;

  return v_sku;
end;
$$;

revoke all on function public.validate_cad_mp_sku(text) from public;

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
begin
  perform public.require_current_user_permission('cadastros.materias_primas.update.identity');

  if p_materia_prima_id is null or p_materia_prima_id <= 0 then
    raise exception 'materia_prima_id is required';
  end if;
  if nullif(trim(p_nome), '') is null then
    raise exception 'nome is required';
  end if;
  if nullif(trim(p_nome_norm), '') is null then
    raise exception 'nome_norm is required';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;

  select to_jsonb(mp)
    into v_before
    from public.cad_materias_primas mp
   where mp.id = p_materia_prima_id
   for update;

  if not found then
    raise exception 'materia-prima not found';
  end if;

  v_actor := public.current_actor_id();

  update public.cad_materias_primas
     set nome = trim(p_nome),
         nome_norm = trim(p_nome_norm),
         tipo = nullif(trim(p_tipo), ''),
         updated_by = v_actor
   where id = p_materia_prima_id;

  select to_jsonb(mp)
    into v_after
    from public.cad_materias_primas mp
   where mp.id = p_materia_prima_id;

  perform public.log_audit_event(
    'cadastros',
    'cad_materias_primas',
    p_materia_prima_id::text,
    'cadastros.materia_prima_identity_updated',
    'cadastros.materias_primas.update.identity',
    'success',
    v_before,
    v_after,
    jsonb_build_object('alcada_usada', 'cadastros.materias_primas.update.identity', 'axis', 'identity'),
    'database_rpc',
    jsonb_build_object('source', 'update_cad_materia_prima_identity', 'motivo', trim(p_motivo))
  );

  return p_materia_prima_id;
end;
$$;

revoke all on function public.update_cad_materia_prima_identity(bigint, text, text, text, text) from public;
grant execute on function public.update_cad_materia_prima_identity(bigint, text, text, text, text) to authenticated;

create or replace function public.update_cad_materia_prima_sku(
  p_materia_prima_id bigint,
  p_sku_corrigido text,
  p_codigo_legado text default null,
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
  v_sku_corrigido text;
begin
  perform public.require_current_user_permission('cadastros.materias_primas.update.sku');

  if p_materia_prima_id is null or p_materia_prima_id <= 0 then
    raise exception 'materia_prima_id is required';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;

  v_sku_corrigido := public.validate_cad_mp_sku(p_sku_corrigido);

  select to_jsonb(mp)
    into v_before
    from public.cad_materias_primas mp
   where mp.id = p_materia_prima_id
   for update;

  if not found then
    raise exception 'materia-prima not found';
  end if;

  v_actor := public.current_actor_id();

  update public.cad_materias_primas
     set sku_corrigido = v_sku_corrigido,
         codigo_legado = nullif(trim(p_codigo_legado), ''),
         updated_by = v_actor
   where id = p_materia_prima_id;

  select to_jsonb(mp)
    into v_after
    from public.cad_materias_primas mp
   where mp.id = p_materia_prima_id;

  perform public.log_audit_event(
    'cadastros',
    'cad_materias_primas',
    p_materia_prima_id::text,
    'cadastros.materia_prima_sku_updated',
    'cadastros.materias_primas.update.sku',
    'success',
    v_before,
    v_after,
    jsonb_build_object('alcada_usada', 'cadastros.materias_primas.update.sku', 'axis', 'sku'),
    'database_rpc',
    jsonb_build_object(
      'source', 'update_cad_materia_prima_sku',
      'motivo', trim(p_motivo),
      'sku_before', v_before->>'sku_corrigido',
      'sku_after', v_after->>'sku_corrigido'
    )
  );

  return p_materia_prima_id;
end;
$$;

revoke all on function public.update_cad_materia_prima_sku(bigint, text, text, text) from public;
grant execute on function public.update_cad_materia_prima_sku(bigint, text, text, text) to authenticated;

create or replace function public.update_cad_materia_prima_technical(
  p_materia_prima_id bigint,
  p_unidade_base_estoque text,
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
begin
  perform public.require_current_user_permission('cadastros.materias_primas.update.technical');

  if p_materia_prima_id is null or p_materia_prima_id <= 0 then
    raise exception 'materia_prima_id is required';
  end if;
  if nullif(trim(p_unidade_base_estoque), '') is null then
    raise exception 'unidade_base_estoque is required';
  end if;
  if p_densidade is not null and p_densidade <= 0 then
    raise exception 'densidade must be greater than zero';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;

  select to_jsonb(mp)
    into v_before
    from public.cad_materias_primas mp
   where mp.id = p_materia_prima_id
   for update;

  if not found then
    raise exception 'materia-prima not found';
  end if;

  v_actor := public.current_actor_id();

  update public.cad_materias_primas
     set unidade_base_estoque = upper(trim(p_unidade_base_estoque)),
         densidade = p_densidade,
         updated_by = v_actor
   where id = p_materia_prima_id;

  select to_jsonb(mp)
    into v_after
    from public.cad_materias_primas mp
   where mp.id = p_materia_prima_id;

  perform public.log_audit_event(
    'cadastros',
    'cad_materias_primas',
    p_materia_prima_id::text,
    'cadastros.materia_prima_technical_updated',
    'cadastros.materias_primas.update.technical',
    'success',
    v_before,
    v_after,
    jsonb_build_object('alcada_usada', 'cadastros.materias_primas.update.technical', 'axis', 'technical'),
    'database_rpc',
    jsonb_build_object(
      'source', 'update_cad_materia_prima_technical',
      'motivo', trim(p_motivo),
      'unidade_before', v_before->>'unidade_base_estoque',
      'unidade_after', v_after->>'unidade_base_estoque',
      'densidade_before', v_before->>'densidade',
      'densidade_after', v_after->>'densidade'
    )
  );

  return p_materia_prima_id;
end;
$$;

revoke all on function public.update_cad_materia_prima_technical(bigint, text, numeric, text) from public;
grant execute on function public.update_cad_materia_prima_technical(bigint, text, numeric, text) to authenticated;

create or replace function public.update_cad_materia_prima_stock_policy(
  p_materia_prima_id bigint,
  p_estoque_minimo numeric default null,
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
begin
  perform public.require_current_user_permission('cadastros.materias_primas.update.stock_policy');

  if p_materia_prima_id is null or p_materia_prima_id <= 0 then
    raise exception 'materia_prima_id is required';
  end if;
  if p_estoque_minimo is not null and p_estoque_minimo < 0 then
    raise exception 'estoque_minimo must be greater than or equal to zero';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;

  select to_jsonb(mp)
    into v_before
    from public.cad_materias_primas mp
   where mp.id = p_materia_prima_id
   for update;

  if not found then
    raise exception 'materia-prima not found';
  end if;

  v_actor := public.current_actor_id();

  update public.cad_materias_primas
     set estoque_minimo = p_estoque_minimo,
         updated_by = v_actor
   where id = p_materia_prima_id;

  select to_jsonb(mp)
    into v_after
    from public.cad_materias_primas mp
   where mp.id = p_materia_prima_id;

  perform public.log_audit_event(
    'cadastros',
    'cad_materias_primas',
    p_materia_prima_id::text,
    'cadastros.materia_prima_stock_policy_updated',
    'cadastros.materias_primas.update.stock_policy',
    'success',
    v_before,
    v_after,
    jsonb_build_object('alcada_usada', 'cadastros.materias_primas.update.stock_policy', 'axis', 'stock_policy'),
    'database_rpc',
    jsonb_build_object(
      'source', 'update_cad_materia_prima_stock_policy',
      'motivo', trim(p_motivo),
      'estoque_minimo_before', v_before->>'estoque_minimo',
      'estoque_minimo_after', v_after->>'estoque_minimo'
    )
  );

  return p_materia_prima_id;
end;
$$;

revoke all on function public.update_cad_materia_prima_stock_policy(bigint, numeric, text) from public;
grant execute on function public.update_cad_materia_prima_stock_policy(bigint, numeric, text) to authenticated;

create or replace function public.update_cad_materia_prima_regulatory(
  p_materia_prima_id bigint,
  p_ncm text default null,
  p_ibama text default null,
  p_codigo_ads text default null,
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
  v_ncm text;
begin
  perform public.require_current_user_permission('cadastros.materias_primas.update.regulatory');

  if p_materia_prima_id is null or p_materia_prima_id <= 0 then
    raise exception 'materia_prima_id is required';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;

  v_ncm := public.validate_cad_mp_ncm(p_ncm);

  select to_jsonb(mp)
    into v_before
    from public.cad_materias_primas mp
   where mp.id = p_materia_prima_id
   for update;

  if not found then
    raise exception 'materia-prima not found';
  end if;

  v_actor := public.current_actor_id();

  update public.cad_materias_primas
     set ncm = v_ncm,
         ibama = nullif(trim(p_ibama), ''),
         codigo_ads = nullif(trim(p_codigo_ads), ''),
         updated_by = v_actor
   where id = p_materia_prima_id;

  select to_jsonb(mp)
    into v_after
    from public.cad_materias_primas mp
   where mp.id = p_materia_prima_id;

  perform public.log_audit_event(
    'cadastros',
    'cad_materias_primas',
    p_materia_prima_id::text,
    'cadastros.materia_prima_regulatory_updated',
    'cadastros.materias_primas.update.regulatory',
    'success',
    v_before,
    v_after,
    jsonb_build_object('alcada_usada', 'cadastros.materias_primas.update.regulatory', 'axis', 'regulatory'),
    'database_rpc',
    jsonb_build_object(
      'source', 'update_cad_materia_prima_regulatory',
      'motivo', trim(p_motivo),
      'ncm_before', v_before->>'ncm',
      'ncm_after', v_after->>'ncm',
      'ibama_before', v_before->>'ibama',
      'ibama_after', v_after->>'ibama',
      'codigo_ads_before', v_before->>'codigo_ads',
      'codigo_ads_after', v_after->>'codigo_ads'
    )
  );

  return p_materia_prima_id;
end;
$$;

revoke all on function public.update_cad_materia_prima_regulatory(bigint, text, text, text, text) from public;
grant execute on function public.update_cad_materia_prima_regulatory(bigint, text, text, text, text) to authenticated;

create or replace function public.deactivate_cad_materia_prima(
  p_materia_prima_id bigint,
  p_motivo text
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
  v_status text;
begin
  perform public.require_current_user_permission('cadastros.materias_primas.deactivate');

  if p_materia_prima_id is null or p_materia_prima_id <= 0 then
    raise exception 'materia_prima_id is required';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;

  select to_jsonb(mp), mp.status
    into v_before, v_status
    from public.cad_materias_primas mp
   where mp.id = p_materia_prima_id
   for update;

  if not found then
    raise exception 'materia-prima not found';
  end if;
  if v_status = 'inactive' then
    raise exception 'materia-prima already inactive';
  end if;

  v_actor := public.current_actor_id();

  update public.cad_materias_primas
     set status = 'inactive',
         updated_by = v_actor
   where id = p_materia_prima_id;

  select to_jsonb(mp)
    into v_after
    from public.cad_materias_primas mp
   where mp.id = p_materia_prima_id;

  perform public.log_audit_event(
    'cadastros',
    'cad_materias_primas',
    p_materia_prima_id::text,
    'cadastros.materia_prima_deactivated',
    'cadastros.materias_primas.deactivate',
    'success',
    v_before,
    v_after,
    jsonb_build_object('alcada_usada', 'cadastros.materias_primas.deactivate', 'axis', 'deactivate'),
    'database_rpc',
    jsonb_build_object('source', 'deactivate_cad_materia_prima', 'motivo', trim(p_motivo))
  );

  return p_materia_prima_id;
end;
$$;

revoke all on function public.deactivate_cad_materia_prima(bigint, text) from public;
grant execute on function public.deactivate_cad_materia_prima(bigint, text) to authenticated;
