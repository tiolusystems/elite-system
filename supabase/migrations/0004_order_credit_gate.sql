create table if not exists public.com_pedido_credito_decisoes (
  id bigint generated always as identity primary key,
  pedido_id bigint not null references public.com_pedidos(id),
  decisao text not null,
  status_anterior text not null,
  status_resultante text not null,
  motivo text,
  limite_disponivel_snapshot numeric,
  inadimplencia_snapshot numeric,
  observacao text,
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint com_pedido_credito_decisao_check check (decisao in ('liberado', 'bloqueado', 'pendente_aprovacao')),
  constraint com_pedido_credito_status_resultante_check check (status_resultante in ('open', 'blocked')),
  constraint com_pedido_credito_motivo_check check (decisao = 'liberado' or motivo is not null),
  constraint com_pedido_credito_limite_check check (limite_disponivel_snapshot is null or limite_disponivel_snapshot >= 0),
  constraint com_pedido_credito_inadimplencia_check check (inadimplencia_snapshot is null or inadimplencia_snapshot >= 0)
);

create index if not exists idx_com_pedido_credito_pedido on public.com_pedido_credito_decisoes(pedido_id, created_at desc);
create index if not exists idx_com_pedido_credito_decisao on public.com_pedido_credito_decisoes(decisao, created_at desc);

alter table public.com_pedido_credito_decisoes enable row level security;

create policy "authenticated full order credit access" on public.com_pedido_credito_decisoes
for all to authenticated using (true) with check (true);

insert into public.permission_actions(action_key, module, description, default_allowed, sort_order)
values
  ('pedidos.credit.review', 'pedidos', 'Liberar, bloquear ou enviar pedido para aprovacao de credito', true, 103)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order;

create or replace function public.registrar_com_pedido_decisao_credito(
  p_pedido_id bigint,
  p_decisao text,
  p_motivo text default null,
  p_limite_disponivel_snapshot numeric default null,
  p_inadimplencia_snapshot numeric default null,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_status_anterior text;
  v_status_resultante text;
  v_decisao_id bigint;
begin
  if p_pedido_id is null or p_pedido_id <= 0 then
    raise exception 'pedido_id is required';
  end if;
  if p_decisao not in ('liberado', 'bloqueado', 'pendente_aprovacao') then
    raise exception 'invalid decisao';
  end if;
  if p_decisao <> 'liberado' and nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required when decisao is not liberado';
  end if;
  if p_limite_disponivel_snapshot is not null and p_limite_disponivel_snapshot < 0 then
    raise exception 'limite_disponivel_snapshot must be greater than or equal to zero';
  end if;
  if p_inadimplencia_snapshot is not null and p_inadimplencia_snapshot < 0 then
    raise exception 'inadimplencia_snapshot must be greater than or equal to zero';
  end if;

  select status
    into v_status_anterior
    from public.com_pedidos
    where id = p_pedido_id
    for update;

  if v_status_anterior is null then
    raise exception 'pedido not found';
  end if;
  if v_status_anterior in ('cancelled', 'fulfilled') then
    raise exception 'pedido status does not allow credit decision';
  end if;

  if p_decisao = 'liberado' then
    v_status_resultante := 'open';
  else
    v_status_resultante := 'blocked';
  end if;

  v_actor := auth.uid();
  if v_actor is not null and not exists (
    select 1 from public.user_profiles where id = v_actor
  ) then
    v_actor := null;
  end if;

  insert into public.com_pedido_credito_decisoes(
    pedido_id,
    decisao,
    status_anterior,
    status_resultante,
    motivo,
    limite_disponivel_snapshot,
    inadimplencia_snapshot,
    observacao,
    created_by
  )
  values (
    p_pedido_id,
    p_decisao,
    v_status_anterior,
    v_status_resultante,
    nullif(trim(p_motivo), ''),
    p_limite_disponivel_snapshot,
    p_inadimplencia_snapshot,
    nullif(trim(p_observacao), ''),
    v_actor
  )
  returning id into v_decisao_id;

  update public.com_pedidos
     set status = v_status_resultante,
         updated_by = v_actor
   where id = p_pedido_id;

  perform public.log_action(
    'comercial.pedido_credito_decidido',
    'com_pedidos',
    p_pedido_id::text,
    'success',
    jsonb_build_object('status', v_status_anterior),
    jsonb_build_object(
      'status', v_status_resultante,
      'decisao', p_decisao,
      'motivo', nullif(trim(p_motivo), ''),
      'limite_disponivel_snapshot', p_limite_disponivel_snapshot,
      'inadimplencia_snapshot', p_inadimplencia_snapshot,
      'decisao_id', v_decisao_id
    ),
    jsonb_build_object('source', 'registrar_com_pedido_decisao_credito')
  );

  return v_decisao_id;
end;
$$;

revoke all on function public.registrar_com_pedido_decisao_credito(bigint, text, text, numeric, numeric, text) from public;
grant execute on function public.registrar_com_pedido_decisao_credito(bigint, text, text, numeric, numeric, text) to authenticated;
