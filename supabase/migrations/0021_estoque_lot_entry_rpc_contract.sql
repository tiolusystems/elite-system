create or replace function public.create_est_lote_pa_auto(
  p_produto_embalagem_id bigint,
  p_quantidade_entrada numeric,
  p_tipo_entrada text default 'importacao_inicial',
  p_status text default 'disponivel',
  p_data_fabricacao date default null,
  p_data_validade date default null,
  p_origem_ref text default null,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_lote_id bigint;
  v_movimento_id bigint;
  v_codigo_lote text;
  v_produto_embalagem_status text;
  v_after jsonb;
  v_permission_context jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'estoque.pa.lots.create',
    'estoque',
    'est_lotes_pa',
    'movement_event',
    jsonb_build_object('familia', 'PA', 'event', 'entry', 'source', 'create_est_lote_pa_auto')
  );

  if p_produto_embalagem_id is null or p_produto_embalagem_id <= 0 then
    raise exception 'produto_embalagem_id is required';
  end if;
  if p_quantidade_entrada is null or p_quantidade_entrada <= 0 then
    raise exception 'quantidade_entrada must be greater than zero';
  end if;
  if p_tipo_entrada not in ('importacao_inicial', 'entrada_producao', 'ajuste_entrada', 'transformacao_entrada') then
    raise exception 'invalid tipo_entrada';
  end if;
  if p_status not in ('disponivel', 'bloqueado') then
    raise exception 'invalid initial PA lot status';
  end if;
  if p_data_fabricacao is not null and p_data_validade is not null and p_data_validade < p_data_fabricacao then
    raise exception 'data_validade must be greater than or equal to data_fabricacao';
  end if;

  select status
    into v_produto_embalagem_status
    from public.cad_produto_embalagens
   where id = p_produto_embalagem_id;

  if v_produto_embalagem_status is null then
    raise exception 'produto_embalagem not found';
  end if;
  if v_produto_embalagem_status <> 'active' then
    raise exception 'produto_embalagem status does not allow PA lot creation';
  end if;

  v_actor := public.current_actor_id();
  v_codigo_lote := public.next_est_codigo_lote('PA');

  insert into public.est_lotes_pa(
    produto_embalagem_id,
    codigo_lote,
    status,
    data_fabricacao,
    data_validade,
    origem_ref,
    observacao,
    created_by,
    updated_by
  )
  values (
    p_produto_embalagem_id,
    v_codigo_lote,
    p_status,
    p_data_fabricacao,
    p_data_validade,
    nullif(trim(p_origem_ref), ''),
    nullif(trim(p_observacao), ''),
    v_actor,
    v_actor
  )
  returning id into v_lote_id;

  insert into public.est_movimentos_pa(
    lote_pa_id,
    produto_embalagem_id,
    tipo_movimento,
    quantidade,
    origem_modulo,
    origem_tabela,
    origem_id,
    observacao,
    created_by
  )
  values (
    v_lote_id,
    p_produto_embalagem_id,
    p_tipo_entrada,
    p_quantidade_entrada,
    'estoque_pa',
    'est_lotes_pa',
    v_lote_id::text,
    nullif(trim(p_observacao), ''),
    v_actor
  )
  returning id into v_movimento_id;

  if p_status <> 'bloqueado' then
    perform public.sync_est_lote_pa_status(v_lote_id);
  end if;

  select to_jsonb(saldo)
    into v_after
    from public.est_lotes_pa_saldos saldo
   where saldo.lote_pa_id = v_lote_id;

  perform public.log_audited_rpc_change(
    'estoque',
    'est_lotes_pa',
    v_lote_id::text,
    'estoque.pa_lote_auto_created',
    'estoque.pa.lots.create',
    v_permission_context,
    null,
    v_after,
    jsonb_build_object(
      'source', 'create_est_lote_pa_auto',
      'movimento_id', v_movimento_id,
      'codigo_lote', v_codigo_lote,
      'tipo_movimento', p_tipo_entrada,
      'quantidade', p_quantidade_entrada,
      'origem_ref', nullif(trim(p_origem_ref), '')
    ),
    'database_rpc'
  );

  return v_lote_id;
end;
$$;

create or replace function public.create_est_lote_mp(
  p_materia_prima_id bigint,
  p_quantidade_entrada numeric,
  p_codigo_lote text default null,
  p_tipo_entrada text default 'importacao_inicial',
  p_status text default 'disponivel',
  p_data_fabricacao date default null,
  p_data_validade date default null,
  p_origem_ref text default null,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_lote_id bigint;
  v_movimento_id bigint;
  v_codigo_lote text;
  v_mp_status text;
  v_after jsonb;
  v_permission_context jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'estoque.mp.lots.create',
    'estoque',
    'est_lotes_mp',
    'movement_event',
    jsonb_build_object('familia', 'MP', 'event', 'entry', 'source', 'create_est_lote_mp')
  );

  if p_materia_prima_id is null or p_materia_prima_id <= 0 then
    raise exception 'materia_prima_id is required';
  end if;
  if p_quantidade_entrada is null or p_quantidade_entrada <= 0 then
    raise exception 'quantidade_entrada must be greater than zero';
  end if;
  if p_tipo_entrada not in ('importacao_inicial', 'entrada_compra', 'ajuste_entrada') then
    raise exception 'invalid tipo_entrada';
  end if;
  if p_status not in ('disponivel', 'bloqueado') then
    raise exception 'invalid initial MP lot status';
  end if;
  if p_data_fabricacao is not null and p_data_validade is not null and p_data_validade < p_data_fabricacao then
    raise exception 'data_validade must be greater than or equal to data_fabricacao';
  end if;

  select status
    into v_mp_status
    from public.cad_materias_primas
   where id = p_materia_prima_id;

  if v_mp_status is null then
    raise exception 'materia_prima not found';
  end if;
  if v_mp_status <> 'active' then
    raise exception 'materia_prima status does not allow MP lot creation';
  end if;

  v_actor := public.current_actor_id();
  v_codigo_lote := coalesce(nullif(trim(p_codigo_lote), ''), public.next_est_codigo_lote('MP'));

  insert into public.est_lotes_mp(
    materia_prima_id,
    codigo_lote,
    status,
    data_fabricacao,
    data_validade,
    origem_ref,
    observacao,
    created_by,
    updated_by
  )
  values (
    p_materia_prima_id,
    v_codigo_lote,
    p_status,
    p_data_fabricacao,
    p_data_validade,
    nullif(trim(p_origem_ref), ''),
    nullif(trim(p_observacao), ''),
    v_actor,
    v_actor
  )
  returning id into v_lote_id;

  insert into public.est_movimentos_mp(
    lote_mp_id,
    materia_prima_id,
    tipo_movimento,
    quantidade,
    origem_modulo,
    origem_tabela,
    origem_id,
    observacao,
    created_by
  )
  values (
    v_lote_id,
    p_materia_prima_id,
    p_tipo_entrada,
    p_quantidade_entrada,
    'estoque_mp',
    'est_lotes_mp',
    v_lote_id::text,
    nullif(trim(p_observacao), ''),
    v_actor
  )
  returning id into v_movimento_id;

  if p_status <> 'bloqueado' then
    perform public.sync_est_lote_mp_status(v_lote_id);
  end if;

  select to_jsonb(saldo)
    into v_after
    from public.est_lotes_mp_saldos saldo
   where saldo.lote_mp_id = v_lote_id;

  perform public.log_audited_rpc_change(
    'estoque',
    'est_lotes_mp',
    v_lote_id::text,
    'estoque.mp_lote_created',
    'estoque.mp.lots.create',
    v_permission_context,
    null,
    v_after,
    jsonb_build_object(
      'source', 'create_est_lote_mp',
      'movimento_id', v_movimento_id,
      'codigo_lote', v_codigo_lote,
      'tipo_movimento', p_tipo_entrada,
      'quantidade', p_quantidade_entrada,
      'origem_ref', nullif(trim(p_origem_ref), '')
    ),
    'database_rpc'
  );

  return v_lote_id;
end;
$$;

create or replace function public.create_est_lote_pi(
  p_produto_id bigint,
  p_quantidade_entrada numeric,
  p_codigo_lote text default null,
  p_tipo_entrada text default 'importacao_inicial',
  p_status text default 'disponivel',
  p_data_fabricacao date default null,
  p_data_validade date default null,
  p_origem_ref text default null,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_lote_id bigint;
  v_movimento_id bigint;
  v_codigo_lote text;
  v_produto_status text;
  v_after jsonb;
  v_permission_context jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'estoque.pi.lots.create',
    'estoque',
    'est_lotes_pi',
    'movement_event',
    jsonb_build_object('familia', 'PI', 'event', 'entry', 'source', 'create_est_lote_pi')
  );

  if p_produto_id is null or p_produto_id <= 0 then
    raise exception 'produto_id is required';
  end if;
  if p_quantidade_entrada is null or p_quantidade_entrada <= 0 then
    raise exception 'quantidade_entrada must be greater than zero';
  end if;
  if p_tipo_entrada not in ('importacao_inicial', 'entrada_producao', 'ajuste_entrada', 'transformacao_entrada') then
    raise exception 'invalid tipo_entrada';
  end if;
  if p_status not in ('disponivel', 'bloqueado') then
    raise exception 'invalid initial PI lot status';
  end if;
  if p_data_fabricacao is not null and p_data_validade is not null and p_data_validade < p_data_fabricacao then
    raise exception 'data_validade must be greater than or equal to data_fabricacao';
  end if;

  select status
    into v_produto_status
    from public.cad_produtos_base
   where id = p_produto_id;

  if v_produto_status is null then
    raise exception 'produto not found';
  end if;
  if v_produto_status <> 'active' then
    raise exception 'produto status does not allow PI lot creation';
  end if;

  v_actor := public.current_actor_id();
  v_codigo_lote := coalesce(nullif(trim(p_codigo_lote), ''), public.next_est_codigo_lote('PI'));

  insert into public.est_lotes_pi(
    produto_id,
    codigo_lote,
    status,
    data_fabricacao,
    data_validade,
    origem_ref,
    observacao,
    created_by,
    updated_by
  )
  values (
    p_produto_id,
    v_codigo_lote,
    p_status,
    p_data_fabricacao,
    p_data_validade,
    nullif(trim(p_origem_ref), ''),
    nullif(trim(p_observacao), ''),
    v_actor,
    v_actor
  )
  returning id into v_lote_id;

  insert into public.est_movimentos_pi(
    lote_pi_id,
    produto_id,
    tipo_movimento,
    quantidade,
    origem_modulo,
    origem_tabela,
    origem_id,
    observacao,
    created_by
  )
  values (
    v_lote_id,
    p_produto_id,
    p_tipo_entrada,
    p_quantidade_entrada,
    'estoque_pi',
    'est_lotes_pi',
    v_lote_id::text,
    nullif(trim(p_observacao), ''),
    v_actor
  )
  returning id into v_movimento_id;

  if p_status <> 'bloqueado' then
    perform public.sync_est_lote_pi_status(v_lote_id);
  end if;

  select to_jsonb(saldo)
    into v_after
    from public.est_lotes_pi_saldos saldo
   where saldo.lote_pi_id = v_lote_id;

  perform public.log_audited_rpc_change(
    'estoque',
    'est_lotes_pi',
    v_lote_id::text,
    'estoque.pi_lote_created',
    'estoque.pi.lots.create',
    v_permission_context,
    null,
    v_after,
    jsonb_build_object(
      'source', 'create_est_lote_pi',
      'movimento_id', v_movimento_id,
      'codigo_lote', v_codigo_lote,
      'tipo_movimento', p_tipo_entrada,
      'quantidade', p_quantidade_entrada,
      'origem_ref', nullif(trim(p_origem_ref), '')
    ),
    'database_rpc'
  );

  return v_lote_id;
end;
$$;

revoke all on function public.create_est_lote_pa_auto(bigint, numeric, text, text, date, date, text, text) from public;
grant execute on function public.create_est_lote_pa_auto(bigint, numeric, text, text, date, date, text, text) to authenticated;

revoke all on function public.create_est_lote_mp(bigint, numeric, text, text, text, date, date, text, text) from public;
grant execute on function public.create_est_lote_mp(bigint, numeric, text, text, text, date, date, text, text) to authenticated;

revoke all on function public.create_est_lote_pi(bigint, numeric, text, text, text, date, date, text, text) from public;
grant execute on function public.create_est_lote_pi(bigint, numeric, text, text, text, date, date, text, text) to authenticated;
