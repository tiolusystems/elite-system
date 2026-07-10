-- Security email login provisioning and residual guard helper consolidation.
-- Temporary passwords are generated and delivered by the application boundary;
-- the database records only authorization/sent facts without credentials.

insert into public.permission_actions(action_key, module, description, default_allowed, sort_order)
values
  ('security.change_own_password', 'seguranca', 'Trocar propria senha temporaria', true, 25)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order;

create or replace function public.resolve_com_pedido_create_action_key(
  p_vendedor_id bigint
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
begin
  v_actor := public.current_actor_id();

  if p_vendedor_id is not null and exists (
    select 1
      from public.cad_pessoas_comerciais vendedor
     where vendedor.id = p_vendedor_id
       and vendedor.user_profile_id = v_actor
  ) then
    return 'pedidos.create.own';
  end if;

  return 'pedidos.create.any';
end;
$$;

comment on function public.resolve_com_pedido_create_action_key(bigint) is
  'Centraliza a decisao own/any para criacao de pedido. A leitura pre-guard e restrita a escolher action_key e nao retorna dados operacionais.';

create or replace function public.resolve_pcp_formula_action_key(
  p_produto_id bigint,
  p_tipo_receita text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
      from public.pcp_formula_versoes versao
     where versao.produto_id = p_produto_id
       and versao.tipo_receita = p_tipo_receita
  ) then
    return 'pcp.formula.change';
  end if;

  return 'pcp.formula.create';
end;
$$;

comment on function public.resolve_pcp_formula_action_key(bigint, text) is
  'Centraliza a decisao create/change para versao de formula. A leitura pre-guard e restrita a escolher action_key e nao retorna dados operacionais.';

create or replace function public.create_com_pedido_operacional(
  p_cliente_id bigint,
  p_produto_embalagem_id bigint,
  p_quantidade numeric,
  p_valor_unitario numeric,
  p_propriedade_id bigint default null,
  p_tipo_pedido text default 'venda',
  p_status text default 'draft',
  p_data_pedido date default current_date,
  p_vendedor_id bigint default null,
  p_percentual_comissao numeric default null,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_action_key text;
begin
  v_action_key := public.resolve_com_pedido_create_action_key(p_vendedor_id);
  perform public.require_current_user_permission(v_action_key);

  return public.create_com_pedido_operacional_impl_0037(
    p_cliente_id,
    p_produto_embalagem_id,
    p_quantidade,
    p_valor_unitario,
    p_propriedade_id,
    p_tipo_pedido,
    p_status,
    p_data_pedido,
    p_vendedor_id,
    p_percentual_comissao,
    p_observacao
  );
end;
$$;

create or replace function public.create_pcp_formula_versao(
  p_produto_id bigint,
  p_tipo_receita text,
  p_justificativa text,
  p_componentes_jsonb jsonb default '[]'::jsonb,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_action_key text;
begin
  v_action_key := public.resolve_pcp_formula_action_key(p_produto_id, p_tipo_receita);
  perform public.require_current_user_permission(v_action_key);

  return public.create_pcp_formula_versao_impl_0037(
    p_produto_id,
    p_tipo_receita,
    p_justificativa,
    p_componentes_jsonb,
    p_observacao
  );
end;
$$;

create or replace function public.authorize_security_auth_user_provision(
  p_email text,
  p_display_name text,
  p_role text,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_email_hash text;
  v_display_name text;
  v_role text;
  v_status text;
  v_permission_context jsonb;
begin
  v_email := lower(nullif(trim(p_email), ''));
  v_display_name := nullif(trim(p_display_name), '');
  v_role := lower(nullif(trim(p_role), ''));
  v_status := lower(nullif(trim(p_status), ''));

  if v_email is null or v_email !~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'invalid email';
  end if;
  if v_display_name is null then
    raise exception 'display name is required';
  end if;
  if v_role not in ('admin', 'comercial', 'producao', 'estoque', 'expedicao', 'auditoria') then
    raise exception 'invalid user role';
  end if;
  if v_status not in ('active', 'inactive') then
    raise exception 'invalid user status';
  end if;

  v_email_hash := encode(extensions.digest(v_email, 'sha256'), 'hex');

  v_permission_context := public.begin_audited_rpc(
    'security.manage_users',
    'seguranca',
    'auth.users',
    'change_type',
    jsonb_build_object(
      'event', 'auth_user_temp_password_provision_authorized',
      'email_hash', v_email_hash,
      'provision_mode', 'temporary_password_email'
    )
  );

  perform public.log_audited_rpc_change(
    'seguranca',
    'auth.users',
    v_email_hash,
    'seguranca.auth_user_temp_password_authorized',
    'security.manage_users',
    v_permission_context,
    null,
    jsonb_build_object(
      'email_hash', v_email_hash,
      'display_name', v_display_name,
      'role', v_role,
      'status', v_status,
      'provision_mode', 'temporary_password_email',
      'contains_password', false
    ),
    jsonb_build_object(
      'source', 'authorize_security_auth_user_provision',
      'credential_logged', false
    )
  );

  return jsonb_build_object(
    'email_hash', v_email_hash,
    'provision_mode', 'temporary_password_email'
  );
end;
$$;

comment on function public.authorize_security_auth_user_provision(text, text, text, text) is
  'Autoriza provisionamento de usuario Auth por senha temporaria. Nao recebe nem grava senha, token ou credencial.';

create or replace function public.record_security_auth_user_temp_password_sent(
  p_user_id uuid,
  p_email text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_email_hash text;
  v_permission_context jsonb;
  v_log_id bigint;
begin
  v_email := lower(nullif(trim(p_email), ''));

  if p_user_id is null then
    raise exception 'target user id is required';
  end if;
  if v_email is null or v_email !~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'invalid email';
  end if;
  if not exists (select 1 from auth.users where id = p_user_id) then
    raise exception 'auth user must exist before recording temporary password delivery';
  end if;

  v_email_hash := encode(extensions.digest(v_email, 'sha256'), 'hex');

  v_permission_context := public.begin_audited_rpc(
    'security.manage_users',
    'seguranca',
    'auth.users',
    'change_type',
    jsonb_build_object(
      'event', 'auth_user_temp_password_email_sent',
      'email_hash', v_email_hash,
      'target_user_id', p_user_id,
      'provision_mode', 'temporary_password_email'
    )
  );

  v_log_id := public.log_audited_rpc_change(
    'seguranca',
    'auth.users',
    p_user_id::text,
    'seguranca.auth_user_temp_password_sent',
    'security.manage_users',
    v_permission_context,
    null,
    jsonb_build_object(
      'target_user_id', p_user_id,
      'email_hash', v_email_hash,
      'provision_mode', 'temporary_password_email',
      'contains_password', false
    ),
    jsonb_build_object(
      'source', 'record_security_auth_user_temp_password_sent',
      'credential_logged', false
    )
  );

  return v_log_id;
end;
$$;

comment on function public.record_security_auth_user_temp_password_sent(uuid, text) is
  'Registra envio de senha temporaria sem gravar senha, token ou credencial.';

create or replace function public.record_security_own_password_changed()
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_permission_context jsonb;
  v_log_id bigint;
begin
  v_actor := public.current_actor_id();

  if v_actor is null then
    raise exception 'active user profile is required';
  end if;

  v_permission_context := public.begin_audited_rpc(
    'security.change_own_password',
    'seguranca',
    'auth.users',
    'change_type',
    jsonb_build_object(
      'event', 'own_temporary_password_changed',
      'target_user_id', v_actor,
      'credential_logged', false
    )
  );

  v_log_id := public.log_audited_rpc_change(
    'seguranca',
    'auth.users',
    v_actor::text,
    'seguranca.own_temporary_password_changed',
    'security.change_own_password',
    v_permission_context,
    null,
    jsonb_build_object(
      'target_user_id', v_actor,
      'temporary_password_bootstrap', false,
      'contains_password', false
    ),
    jsonb_build_object(
      'source', 'record_security_own_password_changed',
      'credential_logged', false
    )
  );

  return v_log_id;
end;
$$;

comment on function public.record_security_own_password_changed() is
  'Registra troca da propria senha temporaria sem gravar senha, token ou credencial.';

revoke all on function public.resolve_com_pedido_create_action_key(bigint) from public, authenticated;
revoke all on function public.resolve_pcp_formula_action_key(bigint, text) from public, authenticated;
revoke all on function public.authorize_security_auth_user_provision(text, text, text, text) from public;
revoke all on function public.record_security_auth_user_temp_password_sent(uuid, text) from public;
revoke all on function public.record_security_own_password_changed() from public;
revoke all on function public.create_com_pedido_operacional(bigint, bigint, numeric, numeric, bigint, text, text, date, bigint, numeric, text) from public;
revoke all on function public.create_pcp_formula_versao(bigint, text, text, jsonb, text) from public;

grant execute on function public.authorize_security_auth_user_provision(text, text, text, text) to authenticated;
grant execute on function public.record_security_auth_user_temp_password_sent(uuid, text) to authenticated;
grant execute on function public.record_security_own_password_changed() to authenticated;
grant execute on function public.create_com_pedido_operacional(bigint, bigint, numeric, numeric, bigint, text, text, date, bigint, numeric, text) to authenticated;
grant execute on function public.create_pcp_formula_versao(bigint, text, text, jsonb, text) to authenticated;
