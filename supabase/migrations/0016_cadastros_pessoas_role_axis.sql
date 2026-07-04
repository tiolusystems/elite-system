insert into public.permission_actions(action_key, module, description, default_allowed, sort_order)
values
  ('cadastros.pessoas.update.identity', 'cadastros', 'Editar identidade de pessoa comercial', true, 75),
  ('cadastros.pessoas.update.role', 'cadastros', 'Editar papeis comerciais sensiveis', true, 76),
  ('cadastros.pessoas.deactivate', 'cadastros', 'Desativar pessoa comercial', true, 77)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order;

create or replace function public.validate_cad_pessoa_role_reason(
  p_motivo_codigo text,
  p_motivo_detalhe text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_motivo_codigo text;
begin
  v_motivo_codigo := lower(nullif(trim(p_motivo_codigo), ''));

  if v_motivo_codigo is null then
    raise exception 'motivo_codigo is required';
  end if;

  if v_motivo_codigo not in (
    'promocao',
    'correcao_cadastro',
    'transferencia_carteira',
    'desligamento_funcao',
    'mudanca_comissao',
    'outro'
  ) then
    raise exception 'invalid motivo_codigo';
  end if;

  if v_motivo_codigo = 'outro' and nullif(trim(p_motivo_detalhe), '') is null then
    raise exception 'motivo_detalhe is required when motivo_codigo is outro';
  end if;

  return v_motivo_codigo;
end;
$$;

revoke all on function public.validate_cad_pessoa_role_reason(text, text) from public;

create or replace function public.validate_cad_pessoa_papeis_json(p_papeis_json jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_papeis_json is null or jsonb_typeof(p_papeis_json) <> 'array' or jsonb_array_length(p_papeis_json) = 0 then
    raise exception 'papeis_json must have at least one item';
  end if;

  if exists (
    select 1
      from jsonb_array_elements_text(p_papeis_json) as papel(value)
     where papel.value not in (
       'funcionario',
       'vendedor',
       'agente',
       'tecnico_campo',
       'entregador',
       'gerente',
       'comissionado'
     )
  ) then
    raise exception 'invalid papel in papeis_json';
  end if;
end;
$$;

revoke all on function public.validate_cad_pessoa_papeis_json(jsonb) from public;

create or replace function public.update_cad_pessoa_comercial_identity(
  p_pessoa_id bigint,
  p_nome text,
  p_nome_norm text,
  p_codigo_legado text default null,
  p_apelidos_json jsonb default '[]'::jsonb,
  p_grafias_incorretas_json jsonb default '[]'::jsonb,
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
  perform public.require_current_user_permission('cadastros.pessoas.update.identity');

  if p_pessoa_id is null or p_pessoa_id <= 0 then
    raise exception 'pessoa_id is required';
  end if;
  if nullif(trim(p_nome), '') is null then
    raise exception 'nome is required';
  end if;
  if nullif(trim(p_nome_norm), '') is null then
    raise exception 'nome_norm is required';
  end if;
  if p_apelidos_json is not null and jsonb_typeof(p_apelidos_json) <> 'array' then
    raise exception 'apelidos_json must be an array';
  end if;
  if p_grafias_incorretas_json is not null and jsonb_typeof(p_grafias_incorretas_json) <> 'array' then
    raise exception 'grafias_incorretas_json must be an array';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;

  select to_jsonb(p)
    into v_before
    from public.cad_pessoas_comerciais p
   where p.id = p_pessoa_id
   for update;

  if not found then
    raise exception 'pessoa comercial not found';
  end if;

  v_actor := public.current_actor_id();

  update public.cad_pessoas_comerciais
     set codigo_legado = nullif(trim(p_codigo_legado), ''),
         nome = trim(p_nome),
         nome_norm = trim(p_nome_norm),
         apelidos_json = coalesce(p_apelidos_json, '[]'::jsonb),
         grafias_incorretas_json = coalesce(p_grafias_incorretas_json, '[]'::jsonb),
         updated_by = v_actor
   where id = p_pessoa_id;

  delete from public.cad_pessoa_aliases
   where pessoa_id = p_pessoa_id
     and tipo in ('nome', 'apelido', 'grafia_incorreta');

  insert into public.cad_pessoa_aliases(pessoa_id, alias, alias_norm, tipo)
  values (p_pessoa_id, trim(p_nome), trim(p_nome_norm), 'nome');

  insert into public.cad_pessoa_aliases(pessoa_id, alias, alias_norm, tipo)
  select p_pessoa_id, min(trim(alias_value)), upper(trim(alias_value)), 'apelido'
    from jsonb_array_elements_text(coalesce(p_apelidos_json, '[]'::jsonb)) as aliases(alias_value)
   where nullif(trim(alias_value), '') is not null
     and upper(trim(alias_value)) <> trim(p_nome_norm)
   group by upper(trim(alias_value));

  insert into public.cad_pessoa_aliases(pessoa_id, alias, alias_norm, tipo)
  select p_pessoa_id, min(trim(alias_value)), upper(trim(alias_value)), 'grafia_incorreta'
    from jsonb_array_elements_text(coalesce(p_grafias_incorretas_json, '[]'::jsonb)) as aliases(alias_value)
   where nullif(trim(alias_value), '') is not null
     and upper(trim(alias_value)) <> trim(p_nome_norm)
     and not exists (
       select 1
         from public.cad_pessoa_aliases existing
        where existing.pessoa_id = p_pessoa_id
          and existing.alias_norm = upper(trim(alias_value))
     )
   group by upper(trim(alias_value));

  select to_jsonb(p)
    into v_after
    from public.cad_pessoas_comerciais p
   where p.id = p_pessoa_id;

  perform public.log_audit_event(
    'cadastros',
    'cad_pessoas_comerciais',
    p_pessoa_id::text,
    'cadastros.pessoa_comercial_identity_updated',
    'cadastros.pessoas.update.identity',
    'success',
    v_before,
    v_after,
    jsonb_build_object('alcada_usada', 'cadastros.pessoas.update.identity', 'axis', 'identity'),
    'database_rpc',
    jsonb_build_object('source', 'update_cad_pessoa_comercial_identity', 'motivo', trim(p_motivo))
  );

  return p_pessoa_id;
end;
$$;

revoke all on function public.update_cad_pessoa_comercial_identity(bigint, text, text, text, jsonb, jsonb, text) from public;
grant execute on function public.update_cad_pessoa_comercial_identity(bigint, text, text, text, jsonb, jsonb, text) to authenticated;

create or replace function public.update_cad_pessoa_comercial_role(
  p_pessoa_id bigint,
  p_tipo_comercial text,
  p_papeis_json jsonb,
  p_vendedor_responsavel_id bigint default null,
  p_motivo_codigo text default null,
  p_motivo_detalhe text default null
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
  v_motivo_codigo text;
  v_papeis_adicionados jsonb;
  v_papeis_removidos jsonb;
begin
  perform public.require_current_user_permission('cadastros.pessoas.update.role');

  -- Papeis comerciais sao alcada de negocio. Isto nao altera user_profiles.role,
  -- que controla perfil de login/autenticacao do sistema.
  if p_pessoa_id is null or p_pessoa_id <= 0 then
    raise exception 'pessoa_id is required';
  end if;
  if p_tipo_comercial is not null and p_tipo_comercial not in (
    'funcionario_elite',
    'agente_vinculado',
    'agente_direto_elite',
    'vendedor_direto_elite',
    'tecnico_campo',
    'entregador',
    'gerente',
    'vendedor_gerente'
  ) then
    raise exception 'invalid tipo_comercial';
  end if;
  perform public.validate_cad_pessoa_papeis_json(p_papeis_json);
  if p_tipo_comercial = 'agente_vinculado' and p_vendedor_responsavel_id is null then
    raise exception 'vendedor_responsavel_id is required';
  end if;
  if p_vendedor_responsavel_id = p_pessoa_id then
    raise exception 'vendedor_responsavel_id cannot reference same pessoa';
  end if;

  v_motivo_codigo := public.validate_cad_pessoa_role_reason(p_motivo_codigo, p_motivo_detalhe);

  select to_jsonb(p)
    into v_before
    from public.cad_pessoas_comerciais p
   where p.id = p_pessoa_id
   for update;

  if not found then
    raise exception 'pessoa comercial not found';
  end if;

  select coalesce(jsonb_agg(added.value order by added.value), '[]'::jsonb)
    into v_papeis_adicionados
    from (
      select value from jsonb_array_elements_text(p_papeis_json)
      except
      select value from jsonb_array_elements_text(coalesce(v_before->'papeis_json', '[]'::jsonb))
    ) as added(value);

  select coalesce(jsonb_agg(removed.value order by removed.value), '[]'::jsonb)
    into v_papeis_removidos
    from (
      select value from jsonb_array_elements_text(coalesce(v_before->'papeis_json', '[]'::jsonb))
      except
      select value from jsonb_array_elements_text(p_papeis_json)
    ) as removed(value);

  v_actor := public.current_actor_id();

  update public.cad_pessoas_comerciais
     set tipo_comercial = p_tipo_comercial,
         papeis_json = p_papeis_json,
         vendedor_responsavel_id = p_vendedor_responsavel_id,
         updated_by = v_actor
   where id = p_pessoa_id;

  select to_jsonb(p)
    into v_after
    from public.cad_pessoas_comerciais p
   where p.id = p_pessoa_id;

  perform public.log_audit_event(
    'cadastros',
    'cad_pessoas_comerciais',
    p_pessoa_id::text,
    'cadastros.pessoa_comercial_role_updated',
    'cadastros.pessoas.update.role',
    'success',
    v_before,
    v_after,
    jsonb_build_object('alcada_usada', 'cadastros.pessoas.update.role', 'axis', 'role'),
    'database_rpc',
    jsonb_build_object(
      'source', 'update_cad_pessoa_comercial_role',
      'motivo_codigo', v_motivo_codigo,
      'motivo_detalhe', nullif(trim(p_motivo_detalhe), ''),
      'papeis_adicionados', v_papeis_adicionados,
      'papeis_removidos', v_papeis_removidos,
      'tipo_comercial_before', v_before->>'tipo_comercial',
      'tipo_comercial_after', v_after->>'tipo_comercial',
      'vendedor_responsavel_before', v_before->>'vendedor_responsavel_id',
      'vendedor_responsavel_after', v_after->>'vendedor_responsavel_id'
    )
  );

  return p_pessoa_id;
end;
$$;

comment on function public.update_cad_pessoa_comercial_role(bigint, text, jsonb, bigint, text, text)
is 'Atualiza papeis comerciais de negocio. Nao altera user_profiles.role de autenticacao.';

revoke all on function public.update_cad_pessoa_comercial_role(bigint, text, jsonb, bigint, text, text) from public;
grant execute on function public.update_cad_pessoa_comercial_role(bigint, text, jsonb, bigint, text, text) to authenticated;

create or replace function public.deactivate_cad_pessoa_comercial(
  p_pessoa_id bigint,
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
  perform public.require_current_user_permission('cadastros.pessoas.deactivate');

  if p_pessoa_id is null or p_pessoa_id <= 0 then
    raise exception 'pessoa_id is required';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;

  select to_jsonb(p), p.status
    into v_before, v_status
    from public.cad_pessoas_comerciais p
   where p.id = p_pessoa_id
   for update;

  if not found then
    raise exception 'pessoa comercial not found';
  end if;
  if v_status = 'inactive' then
    raise exception 'pessoa comercial already inactive';
  end if;

  v_actor := public.current_actor_id();

  update public.cad_pessoas_comerciais
     set status = 'inactive',
         updated_by = v_actor
   where id = p_pessoa_id;

  select to_jsonb(p)
    into v_after
    from public.cad_pessoas_comerciais p
   where p.id = p_pessoa_id;

  perform public.log_audit_event(
    'cadastros',
    'cad_pessoas_comerciais',
    p_pessoa_id::text,
    'cadastros.pessoa_comercial_deactivated',
    'cadastros.pessoas.deactivate',
    'success',
    v_before,
    v_after,
    jsonb_build_object('alcada_usada', 'cadastros.pessoas.deactivate', 'axis', 'deactivate'),
    'database_rpc',
    jsonb_build_object('source', 'deactivate_cad_pessoa_comercial', 'motivo', trim(p_motivo))
  );

  return p_pessoa_id;
end;
$$;

revoke all on function public.deactivate_cad_pessoa_comercial(bigint, text) from public;
grant execute on function public.deactivate_cad_pessoa_comercial(bigint, text) to authenticated;
