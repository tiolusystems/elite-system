-- UX-01H: romaneio starts from an order, is saved explicitly with all selected
-- items, and only issues PA after an emitted NF and complete logistics.

alter table public.cad_produto_embalagens
  add column if not exists unidades_por_volume_logistico numeric;

alter table public.cad_produto_embalagens
  drop constraint if exists cad_produto_embalagens_volume_logistico_check,
  add constraint cad_produto_embalagens_volume_logistico_check check (
    unidades_por_volume_logistico is null or unidades_por_volume_logistico > 0
  );

comment on column public.cad_produto_embalagens.unidades_por_volume_logistico is
  'Quantidade de unidades comerciais que compoe um volume logistico. Fracoes usam arredondamento para cima. Nulo significa configuracao pendente.';

create or replace function public.update_cad_apresentacao_logistica(
  p_apresentacao_id bigint,
  p_unidades_por_volume numeric,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_context jsonb;
  v_before jsonb;
  v_after jsonb;
begin
  v_context := public.begin_audited_rpc(
    'cadastros.produtos.update.technical', 'cadastros', 'cad_produto_embalagens', 'field_risk',
    jsonb_build_object('field_group', 'logistics', 'source', 'update_cad_apresentacao_logistica')
  );
  if p_apresentacao_id is null or p_apresentacao_id <= 0 then raise exception 'presentation is required'; end if;
  if p_unidades_por_volume is null or p_unidades_por_volume <= 0 then raise exception 'units per logistic volume must be greater than zero'; end if;
  if nullif(btrim(p_motivo), '') is null or length(btrim(p_motivo)) < 5 then raise exception 'reason is required'; end if;

  select to_jsonb(item) into v_before from public.cad_produto_embalagens item where item.id = p_apresentacao_id for update;
  if v_before is null then raise exception 'presentation not found'; end if;
  update public.cad_produto_embalagens
     set unidades_por_volume_logistico = p_unidades_por_volume, updated_by = public.current_actor_id()
   where id = p_apresentacao_id;
  select to_jsonb(item) into v_after from public.cad_produto_embalagens item where item.id = p_apresentacao_id;
  perform public.log_audited_rpc_change(
    'cadastros', 'cad_produto_embalagens', p_apresentacao_id::text,
    'cadastros.apresentacao_logistics_updated', 'cadastros.produtos.update.technical', v_context,
    v_before, v_after, jsonb_build_object('motivo', btrim(p_motivo)), 'database_rpc'
  );
  return p_apresentacao_id;
end;
$$;

revoke all on function public.update_cad_apresentacao_logistica(bigint, numeric, text) from public, anon;
grant execute on function public.update_cad_apresentacao_logistica(bigint, numeric, text) to authenticated;

create or replace function public.gravar_exp_romaneio_pedido(
  p_pedido_id bigint,
  p_itens jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_context jsonb;
  v_actor uuid;
  v_pedido record;
  v_item_json jsonb;
  v_item record;
  v_romaneio_id bigint;
  v_codigo text;
  v_quantidade numeric;
  v_disponivel numeric;
  v_itens_criados jsonb := '[]'::jsonb;
begin
  v_context := public.begin_audited_rpc(
    'romaneios.create', 'expedicao', 'exp_romaneios', 'movement_event',
    jsonb_build_object('event', 'order_load_saved', 'source', 'gravar_exp_romaneio_pedido')
  );

  if p_pedido_id is null or p_pedido_id <= 0 then
    raise exception 'pedido_id is required';
  end if;
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'select at least one order item';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_itens) element
    group by (element->>'pedido_item_id')
    having count(*) > 1
  ) then
    raise exception 'order item cannot be repeated';
  end if;

  select pedido.id, pedido.status, pedido.tipo_pedido
    into v_pedido
    from public.com_pedidos pedido
   where pedido.id = p_pedido_id
   for update;

  if not found then raise exception 'pedido not found'; end if;
  if v_pedido.status <> 'open' then raise exception 'pedido status does not allow romaneio'; end if;
  if v_pedido.tipo_pedido not in ('venda', 'troca') then raise exception 'pedido type does not allow romaneio'; end if;

  -- Lock every selected order item before any availability check. This makes
  -- double clicks and concurrent romaneios serialize on the business rows.
  perform 1
    from public.com_pedido_itens pedido_item
   where pedido_item.pedido_id = p_pedido_id
     and pedido_item.id in (
       select (element->>'pedido_item_id')::bigint from jsonb_array_elements(p_itens) element
     )
   order by pedido_item.id
   for update;

  v_actor := public.current_actor_id();
  v_codigo := concat('ROM-', to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS'), '-', upper(substr(md5(random()::text), 1, 4)));

  insert into public.exp_romaneios(
    codigo_romaneio, pedido_id, tipo_separacao, status, data_romaneio,
    observacao, created_by, updated_by
  ) values (
    v_codigo, p_pedido_id, 'parcial', 'draft', current_date,
    null, v_actor, v_actor
  ) returning id into v_romaneio_id;

  for v_item_json in select value from jsonb_array_elements(p_itens)
  loop
    v_quantidade := nullif(v_item_json->>'quantidade', '')::numeric;
    if v_quantidade is null or v_quantidade <= 0 then
      raise exception 'item quantity must be greater than zero';
    end if;

    select item.id, item.produto_embalagem_id, item.status
      into v_item
      from public.com_pedido_itens item
     where item.id = (v_item_json->>'pedido_item_id')::bigint
       and item.pedido_id = p_pedido_id;

    if not found or v_item.status <> 'active' then
      raise exception 'order item is not active or does not belong to order';
    end if;

    select saldo.quantidade_disponivel_romaneio
      into v_disponivel
      from public.exp_pedido_item_romaneio_saldos saldo
     where saldo.pedido_item_id = v_item.id;

    if v_quantidade > coalesce(v_disponivel, 0) then
      raise exception 'romaneio exceeds pending order quantity';
    end if;

    insert into public.exp_romaneio_itens(
      romaneio_id, pedido_id, pedido_item_id, produto_embalagem_id,
      quantidade_romaneada, quantidade_reservada, status, created_by, updated_by
    ) values (
      v_romaneio_id, p_pedido_id, v_item.id, v_item.produto_embalagem_id,
      v_quantidade, 0, 'draft', v_actor, v_actor
    );

    v_itens_criados := v_itens_criados || jsonb_build_array(jsonb_build_object(
      'pedido_item_id', v_item.id,
      'produto_embalagem_id', v_item.produto_embalagem_id,
      'quantidade', v_quantidade
    ));
  end loop;

  perform public.log_audited_rpc_change(
    'expedicao', 'exp_romaneios', v_romaneio_id::text,
    'expedicao.romaneio_order_load_saved', 'romaneios.create', v_context,
    null,
    jsonb_build_object('id', v_romaneio_id, 'codigo_romaneio', v_codigo, 'pedido_id', p_pedido_id, 'itens', v_itens_criados),
    jsonb_build_object('source', 'gravar_exp_romaneio_pedido', 'correlation_id', format('romaneio:%s:create', v_romaneio_id))
  );
  return v_romaneio_id;
end;
$$;

revoke all on function public.gravar_exp_romaneio_pedido(bigint, jsonb) from public, anon;
grant execute on function public.gravar_exp_romaneio_pedido(bigint, jsonb) to authenticated;

-- Keep the validated stock movement implementation internal. The public path
-- below adds fiscal and logistics preconditions before delegating atomically.
alter function public.confirmar_exp_romaneio(bigint, text)
  rename to confirmar_exp_romaneio_impl_0071;
revoke all on function public.confirmar_exp_romaneio_impl_0071(bigint, text) from public, anon, authenticated;

create or replace function public.confirmar_exp_romaneio(
  p_romaneio_id bigint,
  p_nota_fiscal_id bigint
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pedido_id bigint;
  v_nf record;
begin
  perform public.require_current_user_permission('romaneios.confirm');

  select romaneio.pedido_id
    into v_pedido_id
    from public.exp_romaneios romaneio
   where romaneio.id = p_romaneio_id
   for update;
  if v_pedido_id is null then raise exception 'romaneio not found'; end if;

  if not exists (
    select 1 from public.exp_romaneio_logistica_atual logistics
     where logistics.romaneio_id = p_romaneio_id
       and logistics.entregador_id is not null
       and logistics.veiculo_id is not null
  ) then
    raise exception 'driver and vehicle are required before stock issue';
  end if;

  select nf.id, nf.pedido_id, nf.romaneio_id, nf.status_atual, nf.tipo
    into v_nf
    from public.fat_notas_fiscais nf
   where nf.id = p_nota_fiscal_id
   for update;

  if not found or v_nf.pedido_id <> v_pedido_id or v_nf.romaneio_id <> p_romaneio_id then
    raise exception 'invoice must belong to the selected romaneio and order';
  end if;
  if v_nf.status_atual <> 'emitida' or v_nf.tipo not in ('remessa_total', 'remessa_vinculada') then
    raise exception 'an emitted shipping invoice is required';
  end if;
  if exists (
    select 1
      from public.exp_romaneio_itens item
      left join (
        select nf_item.romaneio_item_id, sum(nf_item.quantidade) quantidade
          from public.fat_nota_fiscal_itens nf_item
         where nf_item.nota_fiscal_id = p_nota_fiscal_id
         group by nf_item.romaneio_item_id
      ) fiscal on fiscal.romaneio_item_id = item.id
     where item.romaneio_id = p_romaneio_id
       and item.status in ('draft', 'reservado')
       and coalesce(fiscal.quantidade, 0) <> item.quantidade_romaneada
  ) then
    raise exception 'invoice items must match romaneio quantities';
  end if;

  if not exists (
    select 1 from public.exp_romaneio_carga_resumo carga
     where carga.romaneio_id = p_romaneio_id
       and carga.volumes_logisticos is not null
       and carga.peso_liquido_kg is not null
       and carga.peso_bruto_kg is not null
  ) then
    raise exception 'load volumes and weights must be fully configured before stock issue';
  end if;

  return public.confirmar_exp_romaneio_impl_0071(p_romaneio_id, null);
end;
$$;

revoke all on function public.confirmar_exp_romaneio(bigint, bigint) from public, anon;
grant execute on function public.confirmar_exp_romaneio(bigint, bigint) to authenticated;

create or replace view public.exp_romaneio_carga_resumo
with (security_invoker = true)
as
with item_base as (
  select
    item.id as romaneio_item_id, item.romaneio_id, item.quantidade_romaneada,
    embalagem.volume_litros, apresentacao.unidades_por_volume_logistico,
    versao.peso_tara_kg
  from public.exp_romaneio_itens item
  join public.cad_produto_embalagens apresentacao on apresentacao.id = item.produto_embalagem_id
  join public.cad_embalagens embalagem on embalagem.id = apresentacao.embalagem_id
  left join public.cad_embalagem_configuracoes_atuais versao on versao.embalagem_id = embalagem.id
  where item.status not in ('cancelado', 'estornado')
), item_massas as (
  select
    base.romaneio_item_id,
    sum(reserva.quantidade_reservada) as quantidade_com_densidade,
    sum(reserva.quantidade_reservada * base.volume_litros * cq.densidade_kg_l) as peso_liquido_kg
  from item_base base
  join public.est_reservas_pa reserva on reserva.romaneio_item_id = base.romaneio_item_id and reserva.status in ('ativa', 'baixada')
  join public.pcp_op_produtos_gerados gerado on gerado.lote_pa_id = reserva.lote_pa_id
  join public.pcp_op_cq_resultados cq on cq.op_id = gerado.op_id
  group by base.romaneio_item_id
)
select
  romaneio.id as romaneio_id,
  coalesce(sum(base.quantidade_romaneada * base.volume_litros), 0) as volume_liquido_l,
  case when count(*) filter (where base.unidades_por_volume_logistico is null) > 0 then null
       else sum(ceil(base.quantidade_romaneada / base.unidades_por_volume_logistico)) end as volumes_logisticos,
  case when count(*) filter (where coalesce(massas.quantidade_com_densidade, 0) <> base.quantidade_romaneada) > 0 then null
       else sum(massas.peso_liquido_kg) end as peso_liquido_kg,
  case when count(*) filter (
         where coalesce(massas.quantidade_com_densidade, 0) <> base.quantidade_romaneada
            or base.peso_tara_kg is null or base.unidades_por_volume_logistico is null
       ) > 0 then null
       else sum(massas.peso_liquido_kg)
          + sum(ceil(base.quantidade_romaneada / base.unidades_por_volume_logistico) * base.peso_tara_kg) end as peso_bruto_kg,
  count(*) filter (where base.unidades_por_volume_logistico is null) as itens_sem_volume_configurado,
  count(*) filter (where coalesce(massas.quantidade_com_densidade, 0) <> base.quantidade_romaneada) as itens_sem_densidade,
  count(*) filter (where base.peso_tara_kg is null) as itens_sem_tara
from public.exp_romaneios romaneio
join item_base base on base.romaneio_id = romaneio.id
left join item_massas massas on massas.romaneio_item_id = base.romaneio_item_id
group by romaneio.id;

revoke all on public.exp_romaneio_carga_resumo from public, anon;
grant select on public.exp_romaneio_carga_resumo to authenticated;

comment on view public.exp_romaneio_carga_resumo is
  'Resumo calculado da carga. Valores ficam nulos quando densidade, tara ou unidades por volume nao estao governados; nenhum dado ausente e inventado.';

create table public.est_reserva_pa_eventos (
  id bigint generated always as identity primary key,
  reserva_id bigint not null references public.est_reservas_pa(id) on delete restrict,
  lote_pa_id bigint not null references public.est_lotes_pa(id) on delete restrict,
  romaneio_id bigint not null references public.exp_romaneios(id) on delete restrict,
  romaneio_item_id bigint not null references public.exp_romaneio_itens(id) on delete restrict,
  produto_embalagem_id bigint not null references public.cad_produto_embalagens(id) on delete restrict,
  status text not null,
  quantidade numeric not null check (quantidade > 0),
  ocorrido_em timestamptz not null default now(),
  created_by uuid references public.user_profiles(id),
  constraint est_reserva_pa_eventos_status_check check (status in ('ativa', 'baixada', 'liberada', 'estornada'))
);

create index idx_est_reserva_pa_eventos_asof
  on public.est_reserva_pa_eventos(reserva_id, ocorrido_em desc, id desc);
create index idx_est_reserva_pa_eventos_lote
  on public.est_reserva_pa_eventos(lote_pa_id, ocorrido_em desc, id desc);

create or replace function public.capture_est_reserva_pa_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' or old.status is distinct from new.status or old.quantidade_reservada is distinct from new.quantidade_reservada then
    insert into public.est_reserva_pa_eventos(
      reserva_id, lote_pa_id, romaneio_id, romaneio_item_id, produto_embalagem_id,
      status, quantidade, ocorrido_em, created_by
    ) values (
      new.id, new.lote_pa_id, new.romaneio_id, new.romaneio_item_id, new.produto_embalagem_id,
      new.status, new.quantidade_reservada, coalesce(new.updated_at, new.created_at, now()), coalesce(new.updated_by, new.created_by)
    );
  end if;
  return new;
end;
$$;

revoke all on function public.capture_est_reserva_pa_event() from public, anon, authenticated;
create trigger trg_est_reserva_pa_event
after insert or update of status, quantidade_reservada on public.est_reservas_pa
for each row execute function public.capture_est_reserva_pa_event();

-- Existing reservations receive an explicit baseline. This does not fabricate
-- earlier transitions; historical commitment reporting starts at this baseline.
insert into public.est_reserva_pa_eventos(
  reserva_id, lote_pa_id, romaneio_id, romaneio_item_id, produto_embalagem_id,
  status, quantidade, ocorrido_em, created_by
)
select reserva.id, reserva.lote_pa_id, reserva.romaneio_id, reserva.romaneio_item_id,
       reserva.produto_embalagem_id, reserva.status, reserva.quantidade_reservada,
       now(), coalesce(reserva.updated_by, reserva.created_by)
from public.est_reservas_pa reserva;

alter table public.est_reserva_pa_eventos enable row level security;
create policy "authenticated read est_reserva_pa_eventos"
  on public.est_reserva_pa_eventos for select to authenticated
  using (public.current_actor_id() is not null);
revoke all on public.est_reserva_pa_eventos from public, anon;
revoke insert, update, delete, truncate on public.est_reserva_pa_eventos from authenticated;
grant select on public.est_reserva_pa_eventos to authenticated;

create or replace function public.consultar_est_estoque_pa_posicao(p_data_corte date)
returns table (
  lote_pa_id bigint,
  produto_embalagem_id bigint,
  codigo_lote text,
  saldo_fisico numeric,
  saldo_empenhado numeric,
  saldo_disponivel numeric,
  litros_fisicos numeric,
  volumes_fisicos numeric,
  litros_empenhados numeric,
  volumes_empenhados numeric
)
language sql
stable
security invoker
set search_path = public
as $$
  with movimentos as (
    select movimento.lote_pa_id, sum(movimento.quantidade) saldo_fisico
    from public.est_movimentos_pa movimento
    where movimento.created_at < (p_data_corte + 1)::timestamptz
    group by movimento.lote_pa_id
  ), reserva_ultimo_evento as (
    select distinct on (evento.reserva_id)
      evento.reserva_id, evento.lote_pa_id, evento.status, evento.quantidade
    from public.est_reserva_pa_eventos evento
    where evento.ocorrido_em < (p_data_corte + 1)::timestamptz
    order by evento.reserva_id, evento.ocorrido_em desc, evento.id desc
  ), empenhos as (
    select evento.lote_pa_id, sum(evento.quantidade) saldo_empenhado
    from reserva_ultimo_evento evento
    where evento.status = 'ativa'
    group by evento.lote_pa_id
  )
  select
    lote.id, lote.produto_embalagem_id, lote.codigo_lote,
    coalesce(movimentos.saldo_fisico, 0), coalesce(empenhos.saldo_empenhado, 0),
    coalesce(movimentos.saldo_fisico, 0) - coalesce(empenhos.saldo_empenhado, 0),
    coalesce(movimentos.saldo_fisico, 0) * embalagem.volume_litros,
    case when apresentacao.unidades_por_volume_logistico is null then null else ceil(coalesce(movimentos.saldo_fisico, 0) / apresentacao.unidades_por_volume_logistico) end,
    coalesce(empenhos.saldo_empenhado, 0) * embalagem.volume_litros,
    case when apresentacao.unidades_por_volume_logistico is null then null else ceil(coalesce(empenhos.saldo_empenhado, 0) / apresentacao.unidades_por_volume_logistico) end
  from public.est_lotes_pa lote
  join public.cad_produto_embalagens apresentacao on apresentacao.id = lote.produto_embalagem_id
  join public.cad_embalagens embalagem on embalagem.id = apresentacao.embalagem_id
  left join movimentos on movimentos.lote_pa_id = lote.id
  left join empenhos on empenhos.lote_pa_id = lote.id
  order by lote.produto_embalagem_id, lote.codigo_lote;
$$;

revoke all on function public.consultar_est_estoque_pa_posicao(date) from public, anon;
grant execute on function public.consultar_est_estoque_pa_posicao(date) to authenticated;

comment on function public.consultar_est_estoque_pa_posicao(date) is
  'Posicao PA no fim da data: saldo fisico por movimentos e empenhado pelo ultimo evento append-only de cada reserva. Historico de reservas anterior a 0071 existe apenas como baseline.';
