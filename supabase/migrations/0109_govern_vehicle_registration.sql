-- Minimal governed vehicle registration required by the Romaneio workflow.
-- Vehicles remain master data; logistics events continue to own assignments.

insert into public.permission_actions(
  action_key, module, description, default_allowed, sort_order,
  runtime_module_key, runtime_access_kind
)
values
  ('cadastros.veiculos.create', 'cadastros', 'Cadastrar veiculo', false, 186, 'cadastros', 'write'),
  ('cadastros.veiculos.status.manage', 'cadastros', 'Alterar situacao de veiculo', false, 187, 'cadastros', 'write')
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = false,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

create or replace function public.create_cad_veiculo_governado(
  p_descricao text,
  p_placa text,
  p_codigo_legado text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_id bigint;
  v_placa_norm text;
  v_after jsonb;
  v_context jsonb;
begin
  v_context := public.begin_audited_rpc(
    'cadastros.veiculos.create',
    'cadastros',
    'cad_veiculos',
    'change_type',
    jsonb_build_object('correlation_id', gen_random_uuid()::text)
  );

  if public.normalize_catalog_term(p_descricao) is null then
    raise exception 'vehicle description is required';
  end if;

  v_placa_norm := regexp_replace(upper(coalesce(p_placa, '')), '[^A-Z0-9]', '', 'g');
  if v_placa_norm = '' then
    raise exception 'vehicle plate is required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('cad_veiculos:placa:' || v_placa_norm, 0));
  if exists (select 1 from public.cad_veiculos where placa_norm = v_placa_norm) then
    raise exception 'vehicle plate already exists' using errcode = '23505';
  end if;

  v_actor := public.current_actor_id();
  insert into public.cad_veiculos(
    codigo_legado,
    descricao,
    descricao_norm,
    placa,
    placa_norm,
    status,
    origem_dados,
    created_by,
    updated_by
  )
  values (
    nullif(btrim(p_codigo_legado), ''),
    btrim(p_descricao),
    public.normalize_catalog_term(p_descricao),
    upper(btrim(p_placa)),
    v_placa_norm,
    'active',
    'sistema',
    v_actor,
    v_actor
  )
  returning id into v_id;

  select to_jsonb(vehicle) into v_after
    from public.cad_veiculos vehicle
   where vehicle.id = v_id;

  perform public.log_audited_rpc_change(
    'cadastros',
    'cad_veiculos',
    v_id::text,
    'cadastros.veiculo_created',
    'cadastros.veiculos.create',
    v_context,
    null,
    v_after,
    jsonb_build_object('source', 'create_cad_veiculo_governado'),
    'database_rpc'
  );

  return v_id;
end;
$$;

create or replace function public.set_cad_veiculo_active_state(
  p_veiculo_id bigint,
  p_active boolean,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before jsonb;
  v_after jsonb;
  v_context jsonb;
begin
  v_context := public.begin_audited_rpc(
    'cadastros.veiculos.status.manage',
    'cadastros',
    'cad_veiculos',
    'status_transition',
    jsonb_build_object('correlation_id', 'cad_veiculos:' || p_veiculo_id || ':active_state')
  );

  if length(btrim(coalesce(p_motivo, ''))) < 10 then
    raise exception 'reason must have at least 10 characters';
  end if;

  select to_jsonb(vehicle) into v_before
    from public.cad_veiculos vehicle
   where vehicle.id = p_veiculo_id
   for update;

  if not found then
    raise exception 'vehicle not found';
  end if;
  if p_active and v_before->>'status' <> 'inactive' then
    raise exception 'vehicle is not inactive';
  end if;
  if not p_active and v_before->>'status' <> 'active' then
    raise exception 'vehicle is not active';
  end if;

  update public.cad_veiculos
     set status = case when p_active then 'active' else 'inactive' end,
         updated_by = public.current_actor_id(),
         updated_at = now()
   where id = p_veiculo_id;

  select to_jsonb(vehicle) into v_after
    from public.cad_veiculos vehicle
   where vehicle.id = p_veiculo_id;

  perform public.log_audited_rpc_change(
    'cadastros',
    'cad_veiculos',
    p_veiculo_id::text,
    case when p_active then 'cadastros.veiculo_reactivated' else 'cadastros.veiculo_deactivated' end,
    'cadastros.veiculos.status.manage',
    v_context,
    v_before,
    v_after,
    jsonb_build_object('motivo', btrim(p_motivo), 'history_preserved', true),
    'database_rpc'
  );

  return p_veiculo_id;
end;
$$;

revoke all on function public.create_cad_veiculo_governado(text, text, text) from public, anon;
revoke all on function public.set_cad_veiculo_active_state(bigint, boolean, text) from public, anon;
grant execute on function public.create_cad_veiculo_governado(text, text, text) to authenticated;
grant execute on function public.set_cad_veiculo_active_state(bigint, boolean, text) to authenticated;

revoke insert, update, delete, truncate on public.cad_veiculos from public, anon, authenticated;

comment on function public.create_cad_veiculo_governado(text, text, text) is
  'Creates an active vehicle through an audited, individually authorized write path.';
comment on function public.set_cad_veiculo_active_state(bigint, boolean, text) is
  'Inactivates or reactivates a vehicle without deleting its logistics history.';
