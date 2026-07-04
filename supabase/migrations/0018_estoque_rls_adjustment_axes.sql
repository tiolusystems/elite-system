insert into public.permission_actions(action_key, module, description, default_allowed, sort_order)
values
  ('estoque.mp.view', 'estoque', 'Ver lotes, movimentos, reservas e saldos de materia-prima', true, 234),
  ('estoque.pi.view', 'estoque', 'Ver lotes, movimentos, reservas e saldos de produto intermediario', true, 235),
  ('estoque.mp.adjust', 'estoque', 'Registrar ajuste manual auditado de materia-prima', true, 236),
  ('estoque.pa.adjust', 'estoque', 'Registrar ajuste manual auditado de produto acabado', true, 237),
  ('estoque.pi.adjust', 'estoque', 'Registrar ajuste manual auditado de produto intermediario', true, 238)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order;

drop policy if exists "authenticated full PA lot access" on public.est_lotes_pa;
drop policy if exists "authenticated full PA movement access" on public.est_movimentos_pa;
drop policy if exists "authenticated full PA reservation access" on public.est_reservas_pa;
drop policy if exists "authenticated full MP lot access" on public.est_lotes_mp;
drop policy if exists "authenticated full MP movement access" on public.est_movimentos_mp;
drop policy if exists "authenticated full PI lot access" on public.est_lotes_pi;
drop policy if exists "authenticated full PI movement access" on public.est_movimentos_pi;

drop policy if exists "authenticated read est_lotes_pa" on public.est_lotes_pa;
drop policy if exists "authenticated read est_movimentos_pa" on public.est_movimentos_pa;
drop policy if exists "authenticated read est_reservas_pa" on public.est_reservas_pa;
drop policy if exists "authenticated read est_lotes_mp" on public.est_lotes_mp;
drop policy if exists "authenticated read est_movimentos_mp" on public.est_movimentos_mp;
drop policy if exists "authenticated read est_lotes_pi" on public.est_lotes_pi;
drop policy if exists "authenticated read est_movimentos_pi" on public.est_movimentos_pi;

create policy "authenticated read est_lotes_pa" on public.est_lotes_pa
for select to authenticated using (public.current_actor_id() is not null);
create policy "authenticated read est_movimentos_pa" on public.est_movimentos_pa
for select to authenticated using (public.current_actor_id() is not null);
create policy "authenticated read est_reservas_pa" on public.est_reservas_pa
for select to authenticated using (public.current_actor_id() is not null);
create policy "authenticated read est_lotes_mp" on public.est_lotes_mp
for select to authenticated using (public.current_actor_id() is not null);
create policy "authenticated read est_movimentos_mp" on public.est_movimentos_mp
for select to authenticated using (public.current_actor_id() is not null);
create policy "authenticated read est_lotes_pi" on public.est_lotes_pi
for select to authenticated using (public.current_actor_id() is not null);
create policy "authenticated read est_movimentos_pi" on public.est_movimentos_pi
for select to authenticated using (public.current_actor_id() is not null);

grant select on
  public.est_lotes_pa,
  public.est_movimentos_pa,
  public.est_reservas_pa,
  public.est_lotes_mp,
  public.est_movimentos_mp,
  public.est_lotes_pi,
  public.est_movimentos_pi
to authenticated;

revoke insert, update, delete on
  public.est_lotes_pa,
  public.est_movimentos_pa,
  public.est_reservas_pa,
  public.est_lotes_mp,
  public.est_movimentos_mp,
  public.est_lotes_pi,
  public.est_movimentos_pi
from authenticated;

create or replace function public.create_est_lote_pa(
  p_produto_embalagem_id bigint,
  p_codigo_lote text,
  p_quantidade_entrada numeric,
  p_tipo_entrada text default 'importacao_inicial',
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
  v_produto_embalagem_status text;
  v_after jsonb;
begin
  perform public.require_current_user_permission('estoque.pa.lots.create');
  if p_produto_embalagem_id is null or p_produto_embalagem_id <= 0 then
    raise exception 'produto_embalagem_id is required';
  end if;
  if nullif(trim(p_codigo_lote), '') is null then
    raise exception 'codigo_lote is required';
  end if;
  if p_quantidade_entrada is null or p_quantidade_entrada <= 0 then
    raise exception 'quantidade_entrada must be greater than zero';
  end if;
  if p_tipo_entrada not in ('importacao_inicial', 'entrada_producao', 'ajuste_entrada', 'transformacao_entrada') then
    raise exception 'invalid tipo_entrada';
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

  insert into public.est_lotes_pa(
    produto_embalagem_id,
    codigo_lote,
    data_fabricacao,
    data_validade,
    origem_ref,
    observacao,
    created_by,
    updated_by
  )
  values (
    p_produto_embalagem_id,
    trim(p_codigo_lote),
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
  );

  perform public.sync_est_lote_pa_status(v_lote_id);

  select to_jsonb(saldo)
    into v_after
    from public.est_lotes_pa_saldos saldo
    where saldo.lote_pa_id = v_lote_id;

  perform public.log_audit_event(
    'estoque',
    'est_lotes_pa',
    v_lote_id::text,
    'estoque.pa_lote_created',
    'estoque.pa.lots.create',
    'success',
    null,
    v_after,
    jsonb_build_object('alcada_usada', 'estoque.pa.lots.create', 'axis', 'event_movement', 'familia', 'PA', 'event', 'entry'),
    'database_rpc',
    jsonb_build_object(
      'source', 'create_est_lote_pa',
      'tipo_movimento', p_tipo_entrada,
      'quantidade', p_quantidade_entrada,
      'origem_ref', nullif(trim(p_origem_ref), '')
    )
  );

  return v_lote_id;
end;
$$;

revoke all on function public.create_est_lote_pa(bigint, text, numeric, text, date, date, text, text) from public;
grant execute on function public.create_est_lote_pa(bigint, text, numeric, text, date, date, text, text) to authenticated;

create or replace function public.registrar_est_ajuste_pa(
  p_lote_pa_id bigint,
  p_quantidade numeric,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_lote record;
  v_saldo_disponivel numeric;
  v_before jsonb;
  v_after jsonb;
  v_movimento_id bigint;
  v_tipo_movimento text;
begin
  perform public.require_current_user_permission('estoque.pa.adjust');
  if p_lote_pa_id is null or p_lote_pa_id <= 0 then
    raise exception 'lote_pa_id is required';
  end if;
  if p_quantidade is null or p_quantidade = 0 then
    raise exception 'quantidade must be different from zero';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;

  select *
    into v_lote
    from public.est_lotes_pa
    where id = p_lote_pa_id
    for update;

  if not found then
    raise exception 'PA lot not found';
  end if;
  if v_lote.status = 'cancelado' then
    raise exception 'cancelled PA lot does not allow adjustment';
  end if;

  select to_jsonb(saldo), saldo.saldo_disponivel
    into v_before, v_saldo_disponivel
    from public.est_lotes_pa_saldos saldo
    where saldo.lote_pa_id = p_lote_pa_id;

  if p_quantidade < 0 and coalesce(v_saldo_disponivel, 0) < abs(p_quantidade) then
    raise exception 'adjustment exceeds available PA balance';
  end if;

  v_actor := public.current_actor_id();
  v_tipo_movimento := case when p_quantidade > 0 then 'ajuste_entrada' else 'ajuste_saida' end;

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
    p_lote_pa_id,
    v_lote.produto_embalagem_id,
    v_tipo_movimento,
    p_quantidade,
    'estoque_pa',
    'est_lotes_pa',
    p_lote_pa_id::text,
    trim(p_motivo),
    v_actor
  )
  returning id into v_movimento_id;

  perform public.sync_est_lote_pa_status(p_lote_pa_id);

  select to_jsonb(saldo)
    into v_after
    from public.est_lotes_pa_saldos saldo
    where saldo.lote_pa_id = p_lote_pa_id;

  perform public.log_audit_event(
    'estoque',
    'est_lotes_pa',
    p_lote_pa_id::text,
    'estoque.pa_ajuste_registrado',
    'estoque.pa.adjust',
    'success',
    v_before,
    v_after,
    jsonb_build_object('alcada_usada', 'estoque.pa.adjust', 'axis', 'event_movement', 'familia', 'PA', 'event', 'adjust'),
    'database_rpc',
    jsonb_build_object(
      'source', 'registrar_est_ajuste_pa',
      'movimento_id', v_movimento_id,
      'tipo_movimento', v_tipo_movimento,
      'quantidade', p_quantidade,
      'motivo', trim(p_motivo)
    )
  );

  return v_movimento_id;
end;
$$;

create or replace function public.registrar_est_ajuste_mp(
  p_lote_mp_id bigint,
  p_quantidade numeric,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_lote record;
  v_saldo_disponivel numeric;
  v_before jsonb;
  v_after jsonb;
  v_movimento_id bigint;
  v_tipo_movimento text;
begin
  perform public.require_current_user_permission('estoque.mp.adjust');
  if p_lote_mp_id is null or p_lote_mp_id <= 0 then
    raise exception 'lote_mp_id is required';
  end if;
  if p_quantidade is null or p_quantidade = 0 then
    raise exception 'quantidade must be different from zero';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;

  select *
    into v_lote
    from public.est_lotes_mp
    where id = p_lote_mp_id
    for update;

  if not found then
    raise exception 'MP lot not found';
  end if;
  if v_lote.status = 'cancelado' then
    raise exception 'cancelled MP lot does not allow adjustment';
  end if;

  select to_jsonb(saldo), saldo.saldo_disponivel
    into v_before, v_saldo_disponivel
    from public.est_lotes_mp_saldos saldo
    where saldo.lote_mp_id = p_lote_mp_id;

  if p_quantidade < 0 and coalesce(v_saldo_disponivel, 0) < abs(p_quantidade) then
    raise exception 'adjustment exceeds available MP balance';
  end if;

  v_actor := public.current_actor_id();
  v_tipo_movimento := case when p_quantidade > 0 then 'ajuste_entrada' else 'ajuste_saida' end;

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
    p_lote_mp_id,
    v_lote.materia_prima_id,
    v_tipo_movimento,
    p_quantidade,
    'estoque_mp',
    'est_lotes_mp',
    p_lote_mp_id::text,
    trim(p_motivo),
    v_actor
  )
  returning id into v_movimento_id;

  perform public.sync_est_lote_mp_status(p_lote_mp_id);

  select to_jsonb(saldo)
    into v_after
    from public.est_lotes_mp_saldos saldo
    where saldo.lote_mp_id = p_lote_mp_id;

  perform public.log_audit_event(
    'estoque',
    'est_lotes_mp',
    p_lote_mp_id::text,
    'estoque.mp_ajuste_registrado',
    'estoque.mp.adjust',
    'success',
    v_before,
    v_after,
    jsonb_build_object('alcada_usada', 'estoque.mp.adjust', 'axis', 'event_movement', 'familia', 'MP', 'event', 'adjust'),
    'database_rpc',
    jsonb_build_object(
      'source', 'registrar_est_ajuste_mp',
      'movimento_id', v_movimento_id,
      'tipo_movimento', v_tipo_movimento,
      'quantidade', p_quantidade,
      'motivo', trim(p_motivo)
    )
  );

  return v_movimento_id;
end;
$$;

create or replace function public.registrar_est_ajuste_pi(
  p_lote_pi_id bigint,
  p_quantidade numeric,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_lote record;
  v_saldo_disponivel numeric;
  v_before jsonb;
  v_after jsonb;
  v_movimento_id bigint;
  v_tipo_movimento text;
begin
  perform public.require_current_user_permission('estoque.pi.adjust');
  if p_lote_pi_id is null or p_lote_pi_id <= 0 then
    raise exception 'lote_pi_id is required';
  end if;
  if p_quantidade is null or p_quantidade = 0 then
    raise exception 'quantidade must be different from zero';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;

  select *
    into v_lote
    from public.est_lotes_pi
    where id = p_lote_pi_id
    for update;

  if not found then
    raise exception 'PI lot not found';
  end if;
  if v_lote.status = 'cancelado' then
    raise exception 'cancelled PI lot does not allow adjustment';
  end if;

  select to_jsonb(saldo), saldo.saldo_disponivel
    into v_before, v_saldo_disponivel
    from public.est_lotes_pi_saldos saldo
    where saldo.lote_pi_id = p_lote_pi_id;

  if p_quantidade < 0 and coalesce(v_saldo_disponivel, 0) < abs(p_quantidade) then
    raise exception 'adjustment exceeds available PI balance';
  end if;

  v_actor := public.current_actor_id();
  v_tipo_movimento := case when p_quantidade > 0 then 'ajuste_entrada' else 'ajuste_saida' end;

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
    p_lote_pi_id,
    v_lote.produto_id,
    v_tipo_movimento,
    p_quantidade,
    'estoque_pi',
    'est_lotes_pi',
    p_lote_pi_id::text,
    trim(p_motivo),
    v_actor
  )
  returning id into v_movimento_id;

  perform public.sync_est_lote_pi_status(p_lote_pi_id);

  select to_jsonb(saldo)
    into v_after
    from public.est_lotes_pi_saldos saldo
    where saldo.lote_pi_id = p_lote_pi_id;

  perform public.log_audit_event(
    'estoque',
    'est_lotes_pi',
    p_lote_pi_id::text,
    'estoque.pi_ajuste_registrado',
    'estoque.pi.adjust',
    'success',
    v_before,
    v_after,
    jsonb_build_object('alcada_usada', 'estoque.pi.adjust', 'axis', 'event_movement', 'familia', 'PI', 'event', 'adjust'),
    'database_rpc',
    jsonb_build_object(
      'source', 'registrar_est_ajuste_pi',
      'movimento_id', v_movimento_id,
      'tipo_movimento', v_tipo_movimento,
      'quantidade', p_quantidade,
      'motivo', trim(p_motivo)
    )
  );

  return v_movimento_id;
end;
$$;

revoke all on function public.registrar_est_ajuste_pa(bigint, numeric, text) from public;
grant execute on function public.registrar_est_ajuste_pa(bigint, numeric, text) to authenticated;

revoke all on function public.registrar_est_ajuste_mp(bigint, numeric, text) from public;
grant execute on function public.registrar_est_ajuste_mp(bigint, numeric, text) to authenticated;

revoke all on function public.registrar_est_ajuste_pi(bigint, numeric, text) from public;
grant execute on function public.registrar_est_ajuste_pi(bigint, numeric, text) to authenticated;
