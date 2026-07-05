do $$
begin
  create type public.audit_axis as enum (
    'own_any',
    'change_type',
    'field_risk',
    'movement_event',
    'status_transition'
  );
exception
  when duplicate_object then null;
end;
$$;

create or replace function public.normalize_audit_axis(p_axis text)
returns public.audit_axis
language plpgsql
immutable
set search_path = public
as $$
declare
  v_axis text;
begin
  v_axis := lower(nullif(trim(p_axis), ''));

  if v_axis = 'event_movement' then
    v_axis := 'movement_event';
  end if;

  if v_axis in ('own_any', 'change_type', 'field_risk', 'movement_event', 'status_transition') then
    return v_axis::public.audit_axis;
  end if;

  raise exception 'invalid audit axis: %', p_axis;
end;
$$;

create or replace function public.begin_audited_rpc(
  p_action_key text,
  p_domain text,
  p_entity_type text,
  p_axis text,
  p_context jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_action_key text;
  v_domain text;
  v_entity_type text;
  v_axis public.audit_axis;
  v_context jsonb;
begin
  v_action_key := nullif(trim(p_action_key), '');
  v_domain := lower(nullif(trim(p_domain), ''));
  v_entity_type := nullif(trim(p_entity_type), '');
  v_axis := public.normalize_audit_axis(p_axis);
  v_context := coalesce(p_context, '{}'::jsonb);

  if v_action_key is null then
    raise exception 'action_key is required';
  end if;
  if v_domain is null then
    raise exception 'audit domain is required';
  end if;
  if v_entity_type is null then
    raise exception 'audit entity_type is required';
  end if;
  if jsonb_typeof(v_context) <> 'object' then
    raise exception 'audit context must be a json object';
  end if;
  if v_context ?| array['alcada_usada', 'axis', 'domain', 'entity_type'] then
    raise exception 'audit context contains reserved key';
  end if;

  perform public.require_current_user_permission(v_action_key);

  return jsonb_build_object(
    'alcada_usada', v_action_key,
    'axis', v_axis::text,
    'domain', v_domain,
    'entity_type', v_entity_type
  ) || v_context;
end;
$$;

create or replace function public.log_audited_rpc_change(
  p_domain text,
  p_entity_type text,
  p_entity_id text,
  p_action text,
  p_action_key text,
  p_permission_context jsonb,
  p_before_json jsonb default null,
  p_after_json jsonb default null,
  p_metadata_json jsonb default '{}'::jsonb,
  p_origin text default 'database_rpc'
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_domain text;
  v_entity_type text;
  v_action_key text;
  v_permission_context jsonb;
  v_axis public.audit_axis;
begin
  v_domain := lower(nullif(trim(p_domain), ''));
  v_entity_type := nullif(trim(p_entity_type), '');
  v_action_key := nullif(trim(p_action_key), '');
  v_permission_context := coalesce(p_permission_context, '{}'::jsonb);

  if v_domain is null then
    raise exception 'audit domain is required';
  end if;
  if v_entity_type is null then
    raise exception 'audit entity_type is required';
  end if;
  if v_action_key is null then
    raise exception 'action_key is required';
  end if;
  if jsonb_typeof(v_permission_context) <> 'object' then
    raise exception 'permission_context must be a json object';
  end if;
  if nullif(v_permission_context->>'alcada_usada', '') is null then
    raise exception 'permission_context.alcada_usada is required';
  end if;
  if v_permission_context->>'alcada_usada' <> v_action_key then
    raise exception 'permission_context.alcada_usada does not match action_key';
  end if;
  if nullif(v_permission_context->>'axis', '') is null then
    raise exception 'permission_context.axis is required';
  end if;

  v_axis := public.normalize_audit_axis(v_permission_context->>'axis');
  v_permission_context := jsonb_set(v_permission_context, '{axis}', to_jsonb(v_axis::text), false);

  if v_permission_context->>'domain' is not null and v_permission_context->>'domain' <> v_domain then
    raise exception 'permission_context.domain does not match audit domain';
  end if;
  if v_permission_context->>'entity_type' is not null and v_permission_context->>'entity_type' <> v_entity_type then
    raise exception 'permission_context.entity_type does not match audit entity_type';
  end if;

  return public.log_audit_event(
    v_domain,
    v_entity_type,
    p_entity_id,
    p_action,
    v_action_key,
    'success',
    p_before_json,
    p_after_json,
    v_permission_context,
    coalesce(nullif(trim(p_origin), ''), 'database_rpc'),
    coalesce(p_metadata_json, '{}'::jsonb)
  );
end;
$$;

revoke all on function public.normalize_audit_axis(text) from public;
revoke all on function public.begin_audited_rpc(text, text, text, text, jsonb) from public;
revoke all on function public.log_audited_rpc_change(text, text, text, text, text, jsonb, jsonb, jsonb, jsonb, text) from public;
