create table if not exists public.com_recebimentos (
  id bigint generated always as identity primary key,
  pedido_id bigint not null references public.com_pedidos(id),
  valor_recebido numeric not null,
  data_recebimento date not null default current_date,
  forma_recebimento text,
  observacao text,
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint com_recebimentos_valor_check check (valor_recebido > 0)
);

create table if not exists public.com_comissao_liberacoes (
  id bigint generated always as identity primary key,
  recebimento_id bigint not null references public.com_recebimentos(id),
  pedido_id bigint not null references public.com_pedidos(id),
  comissionado_id bigint not null references public.com_pedido_comissionados(id),
  pessoa_id bigint not null references public.cad_pessoas_comerciais(id),
  valor_liberado numeric not null,
  percentual_recebido_snapshot numeric not null,
  status text not null default 'liberada',
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint com_comissao_liberacoes_status_check check (status in ('liberada', 'bloqueada', 'estornada')),
  constraint com_comissao_liberacoes_valor_check check (valor_liberado <> 0),
  constraint com_comissao_liberacoes_percentual_check check (percentual_recebido_snapshot >= 0)
);

create index if not exists idx_com_recebimentos_pedido on public.com_recebimentos(pedido_id, data_recebimento desc);
create index if not exists idx_com_recebimentos_data on public.com_recebimentos(data_recebimento desc, id desc);
create index if not exists idx_com_comissao_liberacoes_pedido on public.com_comissao_liberacoes(pedido_id, created_at desc);
create index if not exists idx_com_comissao_liberacoes_pessoa on public.com_comissao_liberacoes(pessoa_id, status, created_at desc);

alter table public.com_recebimentos enable row level security;
alter table public.com_comissao_liberacoes enable row level security;

create policy "authenticated full receipt access" on public.com_recebimentos
for all to authenticated using (true) with check (true);
create policy "authenticated full commission release access" on public.com_comissao_liberacoes
for all to authenticated using (true) with check (true);

insert into public.permission_actions(action_key, module, description, default_allowed, sort_order)
values
  ('pedidos.receipts.create', 'pedidos', 'Registrar recebimentos e liberar comissao proporcional', true, 104)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order;

create or replace function public.registrar_com_recebimento(
  p_pedido_id bigint,
  p_valor_recebido numeric,
  p_data_recebimento date default current_date,
  p_forma_recebimento text default null,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_status text;
  v_tipo_pedido text;
  v_valor_total numeric;
  v_total_recebido_anterior numeric;
  v_total_recebido_atual numeric;
  v_percentual_recebido numeric;
  v_recebimento_id bigint;
  v_comissionado record;
  v_valor_ja_liberado numeric;
  v_valor_alvo_liberado numeric;
  v_valor_liberar numeric;
begin
  if p_pedido_id is null or p_pedido_id <= 0 then
    raise exception 'pedido_id is required';
  end if;
  if p_valor_recebido is null or p_valor_recebido <= 0 then
    raise exception 'valor_recebido must be greater than zero';
  end if;
  if p_data_recebimento is null then
    raise exception 'data_recebimento is required';
  end if;

  select status, tipo_pedido, valor_total
    into v_status, v_tipo_pedido, v_valor_total
    from public.com_pedidos
    where id = p_pedido_id
    for update;

  if v_status is null then
    raise exception 'pedido not found';
  end if;
  if v_status in ('draft', 'blocked', 'cancelled') then
    raise exception 'pedido status does not allow receipt';
  end if;
  if v_tipo_pedido <> 'venda' or v_valor_total <= 0 then
    raise exception 'pedido does not allow receipt';
  end if;

  select coalesce(sum(valor_recebido), 0)
    into v_total_recebido_anterior
    from public.com_recebimentos
    where pedido_id = p_pedido_id;

  if v_total_recebido_anterior + p_valor_recebido > v_valor_total then
    raise exception 'receipt exceeds order balance';
  end if;

  v_actor := auth.uid();
  if v_actor is not null and not exists (
    select 1 from public.user_profiles where id = v_actor
  ) then
    v_actor := null;
  end if;

  insert into public.com_recebimentos(
    pedido_id,
    valor_recebido,
    data_recebimento,
    forma_recebimento,
    observacao,
    created_by
  )
  values (
    p_pedido_id,
    p_valor_recebido,
    p_data_recebimento,
    nullif(trim(p_forma_recebimento), ''),
    nullif(trim(p_observacao), ''),
    v_actor
  )
  returning id into v_recebimento_id;

  v_total_recebido_atual := v_total_recebido_anterior + p_valor_recebido;
  v_percentual_recebido := least(v_total_recebido_atual / v_valor_total, 1);

  for v_comissionado in
    select id, pessoa_id, valor_previsto
      from public.com_pedido_comissionados
      where pedido_id = p_pedido_id
        and status in ('prevista', 'liberada')
        and valor_previsto <> 0
  loop
    select coalesce(sum(valor_liberado), 0)
      into v_valor_ja_liberado
      from public.com_comissao_liberacoes
      where comissionado_id = v_comissionado.id
        and status = 'liberada';

    v_valor_alvo_liberado := v_comissionado.valor_previsto * v_percentual_recebido;
    v_valor_liberar := v_valor_alvo_liberado - v_valor_ja_liberado;

    if v_valor_liberar <> 0 then
      insert into public.com_comissao_liberacoes(
        recebimento_id,
        pedido_id,
        comissionado_id,
        pessoa_id,
        valor_liberado,
        percentual_recebido_snapshot,
        created_by
      )
      values (
        v_recebimento_id,
        p_pedido_id,
        v_comissionado.id,
        v_comissionado.pessoa_id,
        v_valor_liberar,
        v_percentual_recebido,
        v_actor
      );

      update public.com_pedido_comissionados
         set status = 'liberada',
             updated_by = v_actor
       where id = v_comissionado.id;
    end if;
  end loop;

  perform public.log_action(
    'comercial.recebimento_registrado',
    'com_recebimentos',
    v_recebimento_id::text,
    'success',
    null,
    jsonb_build_object(
      'pedido_id', p_pedido_id,
      'valor_recebido', p_valor_recebido,
      'data_recebimento', p_data_recebimento,
      'forma_recebimento', nullif(trim(p_forma_recebimento), ''),
      'total_recebido_anterior', v_total_recebido_anterior,
      'total_recebido_atual', v_total_recebido_atual,
      'percentual_recebido', v_percentual_recebido
    ),
    jsonb_build_object('source', 'registrar_com_recebimento')
  );

  return v_recebimento_id;
end;
$$;

revoke all on function public.registrar_com_recebimento(bigint, numeric, date, text, text) from public;
grant execute on function public.registrar_com_recebimento(bigint, numeric, date, text, text) to authenticated;
