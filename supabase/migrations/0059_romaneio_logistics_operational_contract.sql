-- Bloco 6: operational logistics is an audited, append-only concern owned by
-- expedicao. The current assignment is derived from DEC-008 logistics events.

insert into public.permission_actions(
  action_key,
  module,
  description,
  default_allowed,
  sort_order,
  runtime_module_key,
  runtime_access_kind
)
values
  (
    'romaneios.logistics.assign',
    'romaneios',
    'Atribuir entregador e/ou veiculo ao romaneio',
    true,
    406,
    'expedicao',
    'write'
  ),
  (
    'romaneios.logistics.remove',
    'romaneios',
    'Remover entregador e veiculo do romaneio com motivo auditavel',
    true,
    407,
    'expedicao',
    'write'
  )
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

create or replace function public.registrar_exp_romaneio_logistica_atribuicao(
  p_romaneio_id bigint,
  p_entregador_id bigint default null,
  p_veiculo_id bigint default null,
  p_motivo text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_permission_context jsonb;
  v_actor uuid;
  v_romaneio public.exp_romaneios%rowtype;
  v_entregador_nome text;
  v_veiculo_descricao text;
  v_current record;
  v_event_id bigint;
  v_ocorrido_em timestamptz := clock_timestamp();
  v_before jsonb;
  v_after jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'romaneios.logistics.assign',
    'expedicao',
    'exp_romaneios',
    'movement_event',
    jsonb_build_object(
      'event', 'logistics_assignment',
      'source', 'registrar_exp_romaneio_logistica_atribuicao'
    )
  );

  if p_romaneio_id is null or p_romaneio_id <= 0 then
    raise exception 'romaneio_id is required';
  end if;
  if p_entregador_id is null and p_veiculo_id is null then
    raise exception 'entregador_id or veiculo_id is required';
  end if;

  select romaneio.*
    into v_romaneio
    from public.exp_romaneios romaneio
   where romaneio.id = p_romaneio_id
   for update;

  if not found then
    raise exception 'romaneio not found';
  end if;
  if v_romaneio.status not in ('draft', 'separacao', 'confirmado') then
    raise exception 'romaneio status does not allow logistics assignment';
  end if;

  if p_entregador_id is not null then
    select pessoa.nome
      into v_entregador_nome
      from public.cad_pessoas_comerciais pessoa
      join public.cad_pessoa_papeis papel
        on papel.pessoa_id = pessoa.id
       and papel.papel = 'entregador'
       and papel.status = 'active'
       and papel.vigencia_inicio <= v_ocorrido_em
       and (papel.vigencia_fim is null or papel.vigencia_fim >= v_ocorrido_em)
     where pessoa.id = p_entregador_id
       and pessoa.status = 'active';

    if not found then
      raise exception 'active entregador not found';
    end if;
  end if;

  if p_veiculo_id is not null then
    select veiculo.descricao
      into v_veiculo_descricao
      from public.cad_veiculos veiculo
     where veiculo.id = p_veiculo_id
       and veiculo.status = 'active';

    if not found then
      raise exception 'active vehicle not found';
    end if;
  end if;

  select atual.evento_id, atual.entregador_id, atual.veiculo_id, atual.ocorrido_em
    into v_current
    from public.exp_romaneio_logistica_atual atual
   where atual.romaneio_id = p_romaneio_id;

  if found then
    v_before := jsonb_build_object(
      'evento_id', v_current.evento_id,
      'entregador_id', v_current.entregador_id,
      'veiculo_id', v_current.veiculo_id,
      'ocorrido_em', v_current.ocorrido_em
    );

    if v_current.entregador_id is not distinct from p_entregador_id
       and v_current.veiculo_id is not distinct from p_veiculo_id then
      raise exception 'logistics assignment already active';
    end if;
  end if;

  v_actor := public.current_actor_id();

  insert into public.exp_romaneio_logistica_eventos(
    romaneio_id,
    tipo_evento,
    entregador_id,
    veiculo_id,
    ocorrido_em,
    motivo,
    review_status,
    origem_dados,
    created_by
  )
  values (
    p_romaneio_id,
    'atribuicao',
    p_entregador_id,
    p_veiculo_id,
    v_ocorrido_em,
    nullif(trim(p_motivo), ''),
    'approved',
    'sistema',
    v_actor
  )
  returning id into v_event_id;

  v_after := jsonb_build_object(
    'evento_id', v_event_id,
    'entregador_id', p_entregador_id,
    'entregador_nome', v_entregador_nome,
    'veiculo_id', p_veiculo_id,
    'veiculo_descricao', v_veiculo_descricao,
    'ocorrido_em', v_ocorrido_em
  );

  perform public.log_audited_rpc_change(
    'expedicao',
    'exp_romaneios',
    p_romaneio_id::text,
    'expedicao.romaneio_logistica_atribuida',
    'romaneios.logistics.assign',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'registrar_exp_romaneio_logistica_atribuicao',
      'correlation_id', format('romaneio:%s:logistics', p_romaneio_id),
      'pedido_id', v_romaneio.pedido_id,
      'motivo', nullif(trim(p_motivo), '')
    )
  );

  return v_event_id;
end;
$$;

create or replace function public.registrar_exp_romaneio_logistica_remocao(
  p_romaneio_id bigint,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_permission_context jsonb;
  v_actor uuid;
  v_romaneio public.exp_romaneios%rowtype;
  v_current record;
  v_event_id bigint;
  v_ocorrido_em timestamptz := clock_timestamp();
  v_before jsonb;
  v_after jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'romaneios.logistics.remove',
    'expedicao',
    'exp_romaneios',
    'movement_event',
    jsonb_build_object(
      'event', 'logistics_removal',
      'source', 'registrar_exp_romaneio_logistica_remocao'
    )
  );

  if p_romaneio_id is null or p_romaneio_id <= 0 then
    raise exception 'romaneio_id is required';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;

  select romaneio.*
    into v_romaneio
    from public.exp_romaneios romaneio
   where romaneio.id = p_romaneio_id
   for update;

  if not found then
    raise exception 'romaneio not found';
  end if;
  if v_romaneio.status not in ('draft', 'separacao', 'confirmado') then
    raise exception 'romaneio status does not allow logistics removal';
  end if;

  select atual.evento_id, atual.entregador_id, atual.veiculo_id, atual.ocorrido_em
    into v_current
    from public.exp_romaneio_logistica_atual atual
   where atual.romaneio_id = p_romaneio_id;

  if not found then
    raise exception 'romaneio has no active logistics assignment';
  end if;

  v_before := jsonb_build_object(
    'evento_id', v_current.evento_id,
    'entregador_id', v_current.entregador_id,
    'veiculo_id', v_current.veiculo_id,
    'ocorrido_em', v_current.ocorrido_em
  );

  v_actor := public.current_actor_id();

  insert into public.exp_romaneio_logistica_eventos(
    romaneio_id,
    tipo_evento,
    ocorrido_em,
    motivo,
    review_status,
    origem_dados,
    created_by
  )
  values (
    p_romaneio_id,
    'remocao',
    v_ocorrido_em,
    trim(p_motivo),
    'approved',
    'sistema',
    v_actor
  )
  returning id into v_event_id;

  v_after := jsonb_build_object(
    'evento_id', v_event_id,
    'entregador_id', null,
    'veiculo_id', null,
    'ocorrido_em', v_ocorrido_em,
    'motivo', trim(p_motivo)
  );

  perform public.log_audited_rpc_change(
    'expedicao',
    'exp_romaneios',
    p_romaneio_id::text,
    'expedicao.romaneio_logistica_removida',
    'romaneios.logistics.remove',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'registrar_exp_romaneio_logistica_remocao',
      'correlation_id', format('romaneio:%s:logistics', p_romaneio_id),
      'pedido_id', v_romaneio.pedido_id,
      'motivo', trim(p_motivo)
    )
  );

  return v_event_id;
end;
$$;

revoke all on function public.registrar_exp_romaneio_logistica_atribuicao(bigint, bigint, bigint, text)
  from public, anon;
revoke all on function public.registrar_exp_romaneio_logistica_remocao(bigint, text)
  from public, anon;
grant execute on function public.registrar_exp_romaneio_logistica_atribuicao(bigint, bigint, bigint, text)
  to authenticated;
grant execute on function public.registrar_exp_romaneio_logistica_remocao(bigint, text)
  to authenticated;

comment on function public.registrar_exp_romaneio_logistica_atribuicao(bigint, bigint, bigint, text) is
  'Appends an audited courier/vehicle assignment to a draft, separating or confirmed romaneio.';
comment on function public.registrar_exp_romaneio_logistica_remocao(bigint, text) is
  'Appends an audited logistics removal without changing or deleting prior assignments.';
