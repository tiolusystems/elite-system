\set ON_ERROR_STOP on

begin;

do $identity_client_links$
declare
  v_actor uuid := '00000000-0000-4000-8000-000000000110';
  v_target uuid := '00000000-0000-4000-8000-000000000111';
  v_denied uuid := '00000000-0000-4000-8000-000000000112';
  v_person_id bigint;
  v_client_id bigint;
  v_role_id bigint;
  v_link_id bigint;
begin
  insert into auth.users(id)
  values (v_actor), (v_target), (v_denied)
  on conflict (id) do nothing;

  insert into public.user_profiles(id, display_name, role, status)
  values
    (v_actor, 'Identity Link Actor', 'admin', 'active'),
    (v_target, 'Identity Link Target', 'comercial', 'active'),
    (v_denied, 'Identity Link Denied', 'auditoria', 'active')
  on conflict (id) do update set status = excluded.status;

  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  values
    (v_actor, 'security.identity.person.link', true, v_actor),
    (v_actor, 'cadastros.clientes.commercial_links.manage', true, v_actor),
    (v_actor, 'system.admin', true, v_actor)
  on conflict (user_id, action_key) do update
    set allowed = excluded.allowed,
        updated_by = excluded.updated_by;

  perform set_config('request.jwt.claim.sub', v_actor::text, true);
  if public.current_system_environment() = 'unconfigured' then
    perform public.set_system_runtime_environment(
      'test',
      'test_reset',
      'Identity and client link governance smoke'
    );
  elsif public.current_system_environment() <> 'test' then
    raise exception 'identity/client link smoke requires unconfigured or test environment';
  end if;

  insert into public.cad_pessoas_comerciais(
    codigo_legado,
    nome,
    nome_norm,
    tipo_comercial,
    papeis_json,
    status,
    created_by,
    updated_by
  )
  values (
    'HOM-E2E-0110-PERSON',
    'Pessoa HOM-E2E 0110',
    'pessoa hom e2e 0110',
    'vendedor_direto_elite',
    '["vendedor"]'::jsonb,
    'active',
    v_actor,
    v_actor
  )
  returning id into v_person_id;

  if not exists (
    select 1
      from public.cad_pessoa_papeis role_assignment
     where role_assignment.pessoa_id = v_person_id
       and role_assignment.papel = 'vendedor'
       and role_assignment.status = 'active'
  ) then
    raise exception 'commercial person role was not synchronized';
  end if;

  insert into public.cad_clientes(
    codigo_legado,
    nome,
    nome_norm,
    cidade,
    uf,
    status,
    created_by,
    updated_by
  )
  values (
    'HOM-E2E-0110-CLIENT',
    'Cliente HOM-E2E 0110',
    'cliente hom e2e 0110',
    'Campinas',
    'SP',
    'active',
    v_actor,
    v_actor
  )
  returning id into v_client_id;

  select role_catalog.id
    into v_role_id
    from public.cad_cliente_vinculo_papeis role_catalog
   where role_catalog.codigo_norm = 'atende'
     and role_catalog.status = 'active';

  perform public.link_security_user_commercial_person(
    v_target,
    v_person_id,
    'Vinculo de identidade no smoke 0110'
  );

  if (
    select person.user_profile_id
      from public.cad_pessoas_comerciais person
     where person.id = v_person_id
  ) <> v_target then
    raise exception 'user profile was not linked to the commercial person';
  end if;

  if public.link_security_user_commercial_person(
    v_target,
    v_person_id,
    'Retry idempotente do vinculo 0110'
  ) <> v_person_id then
    raise exception 'identity link retry changed the result';
  end if;

  v_link_id := public.link_cad_cliente_commercial_person(
    v_client_id,
    v_person_id,
    v_role_id,
    null,
    current_date,
    'Atribuicao da carteira no smoke 0110'
  );

  if not exists (
    select 1
      from public.cad_cliente_vendedores link
     where link.id = v_link_id
       and link.cliente_id = v_client_id
       and link.pessoa_id = v_person_id
       and link.papel_vinculo_id = v_role_id
       and link.status = 'active'
  ) then
    raise exception 'client commercial link was not created';
  end if;

  begin
    perform public.link_cad_cliente_commercial_person(
      v_client_id,
      v_person_id,
      v_role_id,
      null,
      current_date,
      'Tentativa concorrente simulada no smoke'
    );
    raise exception 'overlapping client commercial link was accepted';
  exception
    when unique_violation then null;
    when others then
      if sqlerrm not like '%overlaps an existing period%' then
        raise;
      end if;
  end;

  perform public.close_cad_cliente_commercial_person(
    v_link_id,
    current_date,
    'Encerramento governado no smoke 0110'
  );

  if not exists (
    select 1
      from public.cad_cliente_vendedores link
     where link.id = v_link_id
       and link.status = 'inactive'
       and link.vigencia_fim = current_date
  ) then
    raise exception 'client commercial link history was not closed';
  end if;

  if (
    select count(*)
      from public.action_logs
     where (
       entity_type = 'cad_pessoas_comerciais'
       and entity_id = v_person_id::text
       and action = 'seguranca.conta_pessoa_vinculada'
     ) or (
       entity_type = 'cad_cliente_vendedores'
       and entity_id = v_link_id::text
       and action in (
         'cadastros.cliente_responsavel_vinculado',
         'cadastros.cliente_responsavel_encerrado'
       )
     )
  ) <> 3 then
    raise exception 'identity/client link audit history is incomplete';
  end if;

  perform set_config('request.jwt.claim.sub', v_denied::text, true);
  begin
    perform public.link_security_user_commercial_person(
      v_denied,
      v_person_id,
      'Tentativa sem alcada no smoke 0110'
    );
    raise exception 'user without permission linked an identity';
  exception
    when others then
      if sqlerrm not like '%not allowed: security.identity.person.link%' then
        raise;
      end if;
  end;

  begin
    perform public.link_cad_cliente_commercial_person(
      v_client_id,
      v_person_id,
      v_role_id,
      null,
      current_date + 1,
      'Tentativa de carteira sem alcada 0110'
    );
    raise exception 'user without permission created a client commercial link';
  exception
    when others then
      if sqlerrm not like '%not allowed: cadastros.clientes.commercial_links.manage%' then
        raise;
      end if;
  end;

  if has_function_privilege(
    'anon',
    'public.link_security_user_commercial_person(uuid,bigint,text)',
    'EXECUTE'
  ) then
    raise exception 'anon can link identity';
  end if;
  if has_function_privilege(
    'anon',
    'public.link_cad_cliente_commercial_person(bigint,bigint,bigint,bigint,date,text)',
    'EXECUTE'
  ) then
    raise exception 'anon can create client commercial links';
  end if;
  if exists (
    select 1
      from pg_proc function_definition
      cross join lateral aclexplode(
        coalesce(
          function_definition.proacl,
          acldefault('f', function_definition.proowner)
        )
      ) privilege
     where function_definition.oid =
       'public.close_cad_cliente_commercial_person(bigint,date,text)'::regprocedure
       and privilege.grantee = 0
       and privilege.privilege_type = 'EXECUTE'
  ) then
    raise exception 'PUBLIC can close client commercial links';
  end if;
end;
$identity_client_links$;

set local role authenticated;
do $direct_write$
begin
  begin
    update public.cad_pessoas_comerciais
       set user_profile_id = null
     where codigo_legado = 'HOM-E2E-0110-PERSON';
    raise exception 'direct authenticated identity write was accepted';
  exception
    when insufficient_privilege then null;
  end;

  begin
    update public.cad_cliente_vendedores
       set status = 'active'
     where false;
    raise exception 'direct authenticated client link write was accepted';
  exception
    when insufficient_privilege then null;
  end;
end;
$direct_write$;
reset role;

rollback;
select 'PG_IDENTITY_CLIENT_LINK_GOVERNANCE_OK' as result;
