alter table public.pcp_op_reservas_componentes
  add column if not exists observacao text;

alter table public.pcp_op_reservas_componentes
  drop constraint if exists pcp_op_reservas_observacao_length_check;

alter table public.pcp_op_reservas_componentes
  add constraint pcp_op_reservas_observacao_length_check
  check (observacao is null or char_length(observacao) <= 2000)
  not valid;

alter table public.pcp_op_reservas_componentes
  validate constraint pcp_op_reservas_observacao_length_check;

comment on column public.pcp_op_reservas_componentes.observacao is
  'Observacao operacional da reserva, persistida pela RPC reservar_pcp_op_componente.';

create or replace function public.next_com_pedido_sequencia(
  p_cliente_id bigint,
  p_propriedade_id bigint default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_row_id bigint;
  v_sequencia integer;
begin
  if p_cliente_id is null or p_cliente_id <= 0 then
    raise exception 'cliente_id is required';
  end if;
  if not exists (select 1 from public.cad_clientes where id = p_cliente_id) then
    raise exception 'cliente not found';
  end if;
  if p_propriedade_id is not null and not exists (
    select 1
    from public.cad_cliente_propriedades
    where id = p_propriedade_id
      and cliente_id = p_cliente_id
  ) then
    raise exception 'propriedade does not belong to cliente';
  end if;

  v_actor := public.current_actor_id();

  loop
    select id, proxima_sequencia
      into v_row_id, v_sequencia
      from public.com_pedido_sequencias_propriedade
      where cliente_id = p_cliente_id
        and coalesce(propriedade_id, 0) = coalesce(p_propriedade_id, 0)
      for update;

    if found then
      update public.com_pedido_sequencias_propriedade
         set proxima_sequencia = v_sequencia + 1,
             updated_by = v_actor
       where id = v_row_id;
      return v_sequencia;
    end if;

    begin
      insert into public.com_pedido_sequencias_propriedade(
        cliente_id,
        propriedade_id,
        proxima_sequencia,
        created_by,
        updated_by
      )
      values (
        p_cliente_id,
        p_propriedade_id,
        2,
        v_actor,
        v_actor
      );
      return 1;
    exception when unique_violation then
      null;
    end;
  end loop;

  raise exception 'order sequence allocation reached an invalid state';
end;
$$;

revoke all on function public.next_com_pedido_sequencia(bigint, bigint) from public;
revoke all on function public.next_com_pedido_sequencia(bigint, bigint) from anon;
revoke all on function public.next_com_pedido_sequencia(bigint, bigint) from authenticated;

create or replace function public.reservar_pcp_op_componente(
  p_op_componente_id bigint,
  p_lote_mp_id bigint default null,
  p_lote_pa_id bigint default null,
  p_lote_pi_id bigint default null,
  p_quantidade_reservada numeric default null,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_comp record;
  v_lote record;
  v_reserva_existente record;
  v_reserva_id bigint;
  v_quantidade_reservada numeric;
  v_total_outros numeric;
  v_saldo_disponivel numeric;
  v_observacao text;
  v_observacao_final text;
  v_tem_reserva_existente boolean := false;
begin
  perform public.require_current_user_permission('pcp.op.reserve_components');
  if p_op_componente_id is null or p_op_componente_id <= 0 then
    raise exception 'op_componente_id is required';
  end if;

  v_observacao := nullif(btrim(p_observacao), '');
  if v_observacao is not null and char_length(v_observacao) > 2000 then
    raise exception 'observacao must have at most 2000 characters';
  end if;

  select comp.*, op.status as op_status, op.tipo_op
    into v_comp
    from public.pcp_op_componentes_planejados comp
    join public.pcp_ordens_producao op on op.id = comp.op_id
    where comp.id = p_op_componente_id
    for update of comp, op;

  if not found then
    raise exception 'OP component not found';
  end if;
  if v_comp.tipo_op = 'mapa_documental' then
    raise exception 'MAPA documental OP does not reserve stock';
  end if;
  if v_comp.op_status not in ('draft', 'planned') then
    raise exception 'OP status does not allow reservation';
  end if;
  if v_comp.status not in ('pending', 'reserved') then
    raise exception 'OP component status does not allow reservation';
  end if;

  v_quantidade_reservada := coalesce(p_quantidade_reservada, v_comp.quantidade_planejada);
  if v_quantidade_reservada <= 0 then
    raise exception 'quantidade_reservada must be greater than zero';
  end if;

  if v_comp.tipo_componente = 'MP' then
    if p_lote_mp_id is null or p_lote_pa_id is not null or p_lote_pi_id is not null then
      raise exception 'MP reservation requires lote_mp_id only';
    end if;
    select lote.*, saldo.saldo_disponivel
      into v_lote
      from public.est_lotes_mp lote
      join public.est_lotes_mp_saldos saldo on saldo.lote_mp_id = lote.id
      where lote.id = p_lote_mp_id
      for update of lote;
    if not found then
      raise exception 'MP lot not found';
    end if;
    if v_lote.materia_prima_id <> v_comp.materia_prima_id then
      raise exception 'MP lot does not match OP component';
    end if;
  elsif v_comp.tipo_componente = 'PA' then
    if p_lote_pa_id is null or p_lote_mp_id is not null or p_lote_pi_id is not null then
      raise exception 'PA reservation requires lote_pa_id only';
    end if;
    select lote.*, saldo.saldo_disponivel
      into v_lote
      from public.est_lotes_pa lote
      join public.est_lotes_pa_saldos saldo on saldo.lote_pa_id = lote.id
      where lote.id = p_lote_pa_id
      for update of lote;
    if not found then
      raise exception 'PA lot not found';
    end if;
    if v_lote.produto_embalagem_id <> v_comp.produto_embalagem_id then
      raise exception 'PA lot does not match OP component';
    end if;
  else
    if p_lote_pi_id is null or p_lote_mp_id is not null or p_lote_pa_id is not null then
      raise exception 'PI reservation requires lote_pi_id only';
    end if;
    select lote.*, saldo.saldo_disponivel
      into v_lote
      from public.est_lotes_pi lote
      join public.est_lotes_pi_saldos saldo on saldo.lote_pi_id = lote.id
      where lote.id = p_lote_pi_id
      for update of lote;
    if not found then
      raise exception 'PI lot not found';
    end if;
    if v_lote.produto_id <> v_comp.produto_id then
      raise exception 'PI lot does not match OP component';
    end if;
  end if;

  if v_lote.status <> 'disponivel' then
    raise exception 'lot status does not allow OP reservation';
  end if;

  select *
    into v_reserva_existente
    from public.pcp_op_reservas_componentes
    where op_componente_id = p_op_componente_id
      and status = 'ativa'
      and (
        (v_comp.tipo_componente = 'MP' and lote_mp_id = p_lote_mp_id)
        or (v_comp.tipo_componente = 'PA' and lote_pa_id = p_lote_pa_id)
        or (v_comp.tipo_componente = 'PI' and lote_pi_id = p_lote_pi_id)
      )
    for update;
  v_tem_reserva_existente := found;

  select coalesce(sum(quantidade_reservada), 0)
    into v_total_outros
    from public.pcp_op_reservas_componentes
    where op_componente_id = p_op_componente_id
      and status = 'ativa'
      and (
        not v_tem_reserva_existente
        or id <> v_reserva_existente.id
      );

  if v_total_outros + v_quantidade_reservada > v_comp.quantidade_planejada then
    raise exception 'OP reservation exceeds planned component quantity';
  end if;

  v_saldo_disponivel := coalesce(v_lote.saldo_disponivel, 0);
  if v_tem_reserva_existente then
    v_saldo_disponivel := v_saldo_disponivel + v_reserva_existente.quantidade_reservada;
  end if;

  if v_saldo_disponivel < v_quantidade_reservada then
    raise exception 'insufficient stock available for OP reservation';
  end if;

  v_actor := public.current_actor_id();

  if v_tem_reserva_existente then
    update public.pcp_op_reservas_componentes as reserva
       set quantidade_reservada = v_quantidade_reservada,
           observacao = coalesce(v_observacao, reserva.observacao),
           updated_by = v_actor
     where reserva.id = v_reserva_existente.id
     returning reserva.id, reserva.observacao
          into v_reserva_id, v_observacao_final;
  else
    insert into public.pcp_op_reservas_componentes(
      op_id,
      op_componente_id,
      tipo_componente,
      lote_mp_id,
      lote_pa_id,
      lote_pi_id,
      quantidade_reservada,
      status,
      observacao,
      created_by,
      updated_by
    )
    values (
      v_comp.op_id,
      p_op_componente_id,
      v_comp.tipo_componente,
      p_lote_mp_id,
      p_lote_pa_id,
      p_lote_pi_id,
      v_quantidade_reservada,
      'ativa',
      v_observacao,
      v_actor,
      v_actor
    )
    returning id, observacao into v_reserva_id, v_observacao_final;
  end if;

  update public.pcp_op_componentes_planejados
     set status = case
       when (
         select coalesce(sum(quantidade_reservada), 0)
         from public.pcp_op_reservas_componentes
         where op_componente_id = p_op_componente_id
           and status = 'ativa'
       ) >= quantidade_planejada then 'reserved'
       else 'pending'
     end
   where id = p_op_componente_id;

  update public.pcp_ordens_producao
     set status = 'planned',
         updated_by = v_actor
   where id = v_comp.op_id
     and status = 'draft';

  perform public.log_action(
    'pcp.op_componente_reservado',
    'pcp_op_reservas_componentes',
    v_reserva_id::text,
    'success',
    null,
    jsonb_build_object(
      'op_id', v_comp.op_id,
      'op_componente_id', p_op_componente_id,
      'tipo_componente', v_comp.tipo_componente,
      'quantidade_reservada', v_quantidade_reservada,
      'observacao', v_observacao_final
    ),
    jsonb_build_object('source', 'reservar_pcp_op_componente')
  );

  return v_reserva_id;
end;
$$;

alter function public.normalize_audit_axis(text) stable;
alter function public.list_system_module_runtime(text) volatile;
alter function public.get_current_route_module_access(text) volatile;

comment on function public.normalize_audit_axis(text) is
  'Normaliza o eixo de auditoria; STABLE porque depende da resolucao do tipo enum no catalogo.';
comment on function public.list_system_module_runtime(text) is
  'Lista o runtime modular para o ator atual; VOLATILE porque resolve identidade e estado de sessao.';
comment on function public.get_current_route_module_access(text) is
  'Resolve acesso da rota para o ator atual; VOLATILE porque resolve identidade e estado de sessao.';
