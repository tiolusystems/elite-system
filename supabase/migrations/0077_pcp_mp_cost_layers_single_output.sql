-- DEC-013: MP acquisition layers and one product/lot per production OP.

insert into public.permission_actions(action_key, module, description, default_allowed, sort_order, runtime_module_key, runtime_access_kind)
values ('pcp.cost.read', 'pcp', 'Consultar custo direto e pendencias de custo da producao', false, 326, 'pcp', 'read')
on conflict (action_key) do nothing;

create table if not exists public.est_movimentos_mp_custo_alocacoes (
  id bigint generated always as identity primary key,
  movimento_saida_id bigint not null references public.est_movimentos_mp(id),
  movimento_valor_id bigint not null references public.est_movimentos_mp_valores(id),
  quantidade_alocada numeric not null,
  moeda text not null,
  custo_unitario_snapshot numeric not null,
  custo_total numeric generated always as (quantidade_alocada * custo_unitario_snapshot) stored,
  created_at timestamptz not null default now(),
  constraint est_mp_custo_aloc_qtd_check check (quantidade_alocada > 0),
  constraint est_mp_custo_aloc_moeda_check check (moeda ~ '^[A-Z]{3}$'),
  constraint est_mp_custo_aloc_unit_check check (custo_unitario_snapshot >= 0),
  constraint est_mp_custo_aloc_pair_key unique (movimento_saida_id, movimento_valor_id)
);

create index if not exists idx_est_mp_custo_aloc_valor
  on public.est_movimentos_mp_custo_alocacoes(movimento_valor_id);

create table if not exists public.pcp_op_perdas_processo (
  id bigint generated always as identity primary key,
  op_id bigint not null unique references public.pcp_ordens_producao(id),
  volume_planejado_l numeric not null,
  volume_real_l numeric not null,
  volume_perdido_l numeric generated always as (volume_planejado_l - volume_real_l) stored,
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint pcp_op_perda_volumes_check check (
    volume_planejado_l > 0 and volume_real_l >= 0 and volume_real_l < volume_planejado_l
  )
);

create table if not exists public.est_lotes_pi_custo_camadas (
  id bigint generated always as identity primary key,
  lote_pi_id bigint not null references public.est_lotes_pi(id),
  op_id bigint not null references public.pcp_ordens_producao(id),
  quantidade_base numeric not null,
  created_at timestamptz not null default now(),
  constraint est_pi_custo_qtd_check check (quantidade_base > 0),
  constraint est_pi_custo_lote_key unique (lote_pi_id)
);

create table if not exists public.est_lotes_pi_custo_componentes (
  id bigint generated always as identity primary key,
  lote_custo_id bigint not null references public.est_lotes_pi_custo_camadas(id),
  moeda text not null,
  custo_total numeric not null,
  created_at timestamptz not null default now(),
  constraint est_pi_custo_comp_total_check check (custo_total >= 0),
  constraint est_pi_custo_comp_moeda_check check (moeda ~ '^[A-Z]{3}$'),
  constraint est_pi_custo_comp_key unique (lote_custo_id, moeda)
);

create table if not exists public.est_movimentos_pi_custo_alocacoes (
  id bigint generated always as identity primary key,
  movimento_saida_id bigint not null references public.est_movimentos_pi(id),
  lote_custo_id bigint not null references public.est_lotes_pi_custo_camadas(id),
  quantidade_alocada numeric not null,
  created_at timestamptz not null default now(),
  constraint est_pi_custo_aloc_qtd_check check (quantidade_alocada > 0),
  constraint est_pi_custo_aloc_pair_key unique (movimento_saida_id, lote_custo_id)
);

create table if not exists public.est_lotes_pa_custo_camadas (
  id bigint generated always as identity primary key,
  lote_pa_id bigint not null references public.est_lotes_pa(id),
  ordem_envase_id bigint not null references public.pcp_ordens_envase(id),
  quantidade_embalagens numeric not null,
  created_at timestamptz not null default now(),
  constraint est_pa_custo_qtd_check check (quantidade_embalagens > 0),
  constraint est_pa_custo_lote_key unique (lote_pa_id)
);

create table if not exists public.est_lotes_pa_custo_componentes (
  id bigint generated always as identity primary key,
  lote_custo_id bigint not null references public.est_lotes_pa_custo_camadas(id),
  moeda text not null,
  custo_total numeric not null,
  created_at timestamptz not null default now(),
  constraint est_pa_custo_comp_total_check check (custo_total >= 0),
  constraint est_pa_custo_comp_moeda_check check (moeda ~ '^[A-Z]{3}$'),
  constraint est_pa_custo_comp_key unique (lote_custo_id, moeda)
);

create table if not exists public.est_movimentos_pa_custo_alocacoes (
  id bigint generated always as identity primary key,
  movimento_saida_id bigint not null references public.est_movimentos_pa(id),
  lote_custo_id bigint not null references public.est_lotes_pa_custo_camadas(id),
  quantidade_alocada numeric not null,
  created_at timestamptz not null default now(),
  constraint est_pa_custo_aloc_qtd_check check (quantidade_alocada > 0),
  constraint est_pa_custo_aloc_pair_key unique (movimento_saida_id, lote_custo_id)
);

create or replace function public.allocate_est_movimento_mp_cost(p_movimento_saida_id bigint)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
declare
  v_movement record;
  v_layer record;
  v_remaining numeric;
  v_quantity numeric;
begin
  select movement.* into v_movement
    from public.est_movimentos_mp movement
   where movement.id = p_movimento_saida_id
   for update;
  if not found or v_movement.quantidade >= 0 then return 0; end if;

  perform pg_advisory_xact_lock(hashtextextended('mp_cost_lot:' || v_movement.lote_mp_id::text, 0));
  select greatest(abs(v_movement.quantidade) - coalesce(sum(allocation.quantidade_alocada), 0), 0)
    into v_remaining
    from public.est_movimentos_mp_custo_alocacoes allocation
   where allocation.movimento_saida_id = p_movimento_saida_id;

  for v_layer in
    select value.id value_id, value.moeda, value.custo_unitario_base,
      greatest(value.quantidade_base - coalesce((
        select sum(allocation.quantidade_alocada)
          from public.est_movimentos_mp_custo_alocacoes allocation
         where allocation.movimento_valor_id = value.id
      ), 0), 0) available_quantity
      from public.est_movimentos_mp_valores value
      join public.est_movimentos_mp entry on entry.id = value.movimento_mp_id
     where entry.lote_mp_id = v_movement.lote_mp_id
     order by entry.created_at, entry.id, value.id
  loop
    exit when v_remaining <= 0;
    if v_layer.available_quantity <= 0 then continue; end if;
    v_quantity := least(v_remaining, v_layer.available_quantity);
    insert into public.est_movimentos_mp_custo_alocacoes(
      movimento_saida_id, movimento_valor_id, quantidade_alocada, moeda, custo_unitario_snapshot
    ) values (
      p_movimento_saida_id, v_layer.value_id, v_quantity, v_layer.moeda, v_layer.custo_unitario_base
    ) on conflict (movimento_saida_id, movimento_valor_id) do nothing;
    v_remaining := v_remaining - v_quantity;
  end loop;
  return v_remaining;
end;
$$;

create or replace function public.allocate_new_est_movimento_mp_cost()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.quantidade < 0 then perform public.allocate_est_movimento_mp_cost(new.id); end if;
  return new;
end;
$$;

create or replace function public.reconcile_mp_cost_after_value_insert()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_movement record;
begin
  for v_movement in
    select output.id
      from public.est_movimentos_mp output
      join public.est_movimentos_mp entry on entry.id = new.movimento_mp_id
     where output.lote_mp_id = entry.lote_mp_id and output.quantidade < 0
     order by output.created_at, output.id
  loop
    perform public.allocate_est_movimento_mp_cost(v_movement.id);
  end loop;
  return new;
end;
$$;

create or replace function public.allocate_est_movimento_pi_cost(p_movimento_saida_id bigint)
returns numeric language plpgsql security definer set search_path = public as $$
declare v_movement record; v_layer record; v_remaining numeric; v_quantity numeric;
begin
  select * into v_movement from public.est_movimentos_pi where id = p_movimento_saida_id for update;
  if not found or v_movement.quantidade >= 0 then return 0; end if;
  perform pg_advisory_xact_lock(hashtextextended('pi_cost_lot:' || v_movement.lote_pi_id::text, 0));
  select greatest(abs(v_movement.quantidade) - coalesce(sum(quantidade_alocada), 0), 0)
    into v_remaining from public.est_movimentos_pi_custo_alocacoes where movimento_saida_id = p_movimento_saida_id;
  for v_layer in
    select layer.*, greatest(layer.quantidade_base - coalesce((select sum(a.quantidade_alocada)
      from public.est_movimentos_pi_custo_alocacoes a where a.lote_custo_id = layer.id), 0), 0) available_quantity
    from public.est_lotes_pi_custo_camadas layer where layer.lote_pi_id = v_movement.lote_pi_id
    order by layer.created_at, layer.id
  loop
    exit when v_remaining <= 0;
    if v_layer.available_quantity <= 0 then continue; end if;
    v_quantity := least(v_remaining, v_layer.available_quantity);
    insert into public.est_movimentos_pi_custo_alocacoes(
      movimento_saida_id,lote_custo_id,quantidade_alocada
    ) values (p_movimento_saida_id,v_layer.id,v_quantity);
    v_remaining := v_remaining - v_quantity;
  end loop;
  return v_remaining;
end;
$$;

create or replace function public.allocate_est_movimento_pa_cost(p_movimento_saida_id bigint)
returns numeric language plpgsql security definer set search_path = public as $$
declare v_movement record; v_layer record; v_remaining numeric; v_quantity numeric;
begin
  select * into v_movement from public.est_movimentos_pa where id = p_movimento_saida_id for update;
  if not found or v_movement.quantidade >= 0 then return 0; end if;
  perform pg_advisory_xact_lock(hashtextextended('pa_cost_lot:' || v_movement.lote_pa_id::text, 0));
  select greatest(abs(v_movement.quantidade) - coalesce(sum(quantidade_alocada), 0), 0)
    into v_remaining from public.est_movimentos_pa_custo_alocacoes where movimento_saida_id = p_movimento_saida_id;
  for v_layer in
    select layer.*, greatest(layer.quantidade_embalagens - coalesce((select sum(a.quantidade_alocada)
      from public.est_movimentos_pa_custo_alocacoes a where a.lote_custo_id = layer.id), 0), 0) available_quantity
    from public.est_lotes_pa_custo_camadas layer where layer.lote_pa_id = v_movement.lote_pa_id
    order by layer.created_at, layer.id
  loop
    exit when v_remaining <= 0;
    if v_layer.available_quantity <= 0 then continue; end if;
    v_quantity := least(v_remaining, v_layer.available_quantity);
    insert into public.est_movimentos_pa_custo_alocacoes(
      movimento_saida_id,lote_custo_id,quantidade_alocada
    ) values (p_movimento_saida_id,v_layer.id,v_quantity);
    v_remaining := v_remaining - v_quantity;
  end loop;
  return v_remaining;
end;
$$;

create or replace function public.allocate_new_est_movimento_pi_pa_cost()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.quantidade < 0 and tg_table_name = 'est_movimentos_pi' then
    perform public.allocate_est_movimento_pi_cost(new.id);
  elsif new.quantidade < 0 and tg_table_name = 'est_movimentos_pa' then
    perform public.allocate_est_movimento_pa_cost(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_est_movimentos_mp_allocate_cost on public.est_movimentos_mp;
create trigger trg_est_movimentos_mp_allocate_cost
after insert on public.est_movimentos_mp
for each row execute function public.allocate_new_est_movimento_mp_cost();

drop trigger if exists trg_est_mp_values_reconcile_cost on public.est_movimentos_mp_valores;
create trigger trg_est_mp_values_reconcile_cost
after insert on public.est_movimentos_mp_valores
for each row execute function public.reconcile_mp_cost_after_value_insert();

drop trigger if exists trg_est_movimentos_pi_allocate_cost on public.est_movimentos_pi;
create trigger trg_est_movimentos_pi_allocate_cost after insert on public.est_movimentos_pi
for each row execute function public.allocate_new_est_movimento_pi_pa_cost();

drop trigger if exists trg_est_movimentos_pa_allocate_cost on public.est_movimentos_pa;
create trigger trg_est_movimentos_pa_allocate_cost after insert on public.est_movimentos_pa
for each row execute function public.allocate_new_est_movimento_pi_pa_cost();

drop trigger if exists trg_est_mp_cost_allocations_append_only on public.est_movimentos_mp_custo_alocacoes;
create trigger trg_est_mp_cost_allocations_append_only
before update or delete on public.est_movimentos_mp_custo_alocacoes
for each row execute function public.prevent_historical_mp_fact_changes();

drop trigger if exists trg_est_mp_cost_allocations_no_truncate on public.est_movimentos_mp_custo_alocacoes;
create trigger trg_est_mp_cost_allocations_no_truncate
before truncate on public.est_movimentos_mp_custo_alocacoes
for each statement execute function public.prevent_historical_mp_fact_changes();

drop trigger if exists trg_pcp_op_process_losses_append_only on public.pcp_op_perdas_processo;
create trigger trg_pcp_op_process_losses_append_only
before update or delete on public.pcp_op_perdas_processo
for each row execute function public.prevent_historical_mp_fact_changes();

drop trigger if exists trg_pcp_op_process_losses_no_truncate on public.pcp_op_perdas_processo;
create trigger trg_pcp_op_process_losses_no_truncate
before truncate on public.pcp_op_perdas_processo
for each statement execute function public.prevent_historical_mp_fact_changes();

do $$
declare v_table text;
begin
  foreach v_table in array array['est_lotes_pi_custo_camadas','est_lotes_pi_custo_componentes',
    'est_movimentos_pi_custo_alocacoes','est_lotes_pa_custo_camadas',
    'est_lotes_pa_custo_componentes','est_movimentos_pa_custo_alocacoes'] loop
    execute format('drop trigger if exists trg_%s_append_only on public.%I', v_table, v_table);
    execute format('create trigger trg_%s_append_only before update or delete on public.%I for each row execute function public.prevent_historical_mp_fact_changes()', v_table, v_table);
    execute format('drop trigger if exists trg_%s_no_truncate on public.%I', v_table, v_table);
    execute format('create trigger trg_%s_no_truncate before truncate on public.%I for each statement execute function public.prevent_historical_mp_fact_changes()', v_table, v_table);
  end loop;
end;
$$;

do $$
declare v_movement record;
begin
  for v_movement in
    select id from public.est_movimentos_mp where quantidade < 0 order by created_at, id
  loop
    perform public.allocate_est_movimento_mp_cost(v_movement.id);
  end loop;
end;
$$;

create or replace view public.est_movimentos_mp_custos_atuais
with (security_invoker = true)
as
select movement.id movimento_mp_id, movement.lote_mp_id, movement.origem_tabela,
  movement.origem_id, abs(movement.quantidade) quantidade_consumida,
  coalesce(sum(allocation.quantidade_alocada), 0) quantidade_com_custo,
  greatest(abs(movement.quantidade) - coalesce(sum(allocation.quantidade_alocada), 0), 0) quantidade_sem_custo,
  case when coalesce(sum(allocation.quantidade_alocada), 0) = abs(movement.quantidade)
    then 'completo' else 'pendente' end status_custo
from public.est_movimentos_mp movement
left join public.est_movimentos_mp_custo_alocacoes allocation on allocation.movimento_saida_id = movement.id
where movement.quantidade < 0
group by movement.id;

create or replace view public.pcp_op_custos_mp_atuais
with (security_invoker = true)
as
select op.id op_id, allocation.moeda,
  sum(allocation.custo_total) custo_direto_mp,
  coalesce((select sum(cost.quantidade_sem_custo)
    from public.est_movimentos_mp_custos_atuais cost
    where cost.origem_tabela = 'pcp_ordens_producao' and cost.origem_id = op.id::text), 0) quantidade_mp_sem_custo,
  (select count(*) from public.pcp_op_consumos_componentes consumption
    where consumption.op_id = op.id and consumption.tipo_componente in ('PI', 'PA')) componentes_pi_pa_sem_camada
from public.pcp_ordens_producao op
left join public.est_movimentos_mp movement
  on movement.origem_tabela = 'pcp_ordens_producao' and movement.origem_id = op.id::text and movement.quantidade < 0
left join public.est_movimentos_mp_custo_alocacoes allocation on allocation.movimento_saida_id = movement.id
group by op.id, allocation.moeda;

create or replace view public.pcp_op_perdas_custos_atuais
with (security_invoker = true)
as
select loss.op_id, cost.moeda, loss.volume_planejado_l, loss.volume_real_l,
  loss.volume_perdido_l,
  case when cost.quantidade_mp_sem_custo = 0 and cost.componentes_pi_pa_sem_camada = 0
    then cost.custo_direto_mp * loss.volume_perdido_l / loss.volume_planejado_l else null end custo_perda_processo,
  case when cost.quantidade_mp_sem_custo = 0 and cost.componentes_pi_pa_sem_camada = 0
    then 'completo_mp' else 'pendente' end status_custo
from public.pcp_op_perdas_processo loss
join public.pcp_op_custos_mp_atuais cost on cost.op_id = loss.op_id;

create or replace view public.est_perdas_mp_custos_atuais
with (security_invoker = true)
as
select movement.id movimento_mp_id, movement.lote_mp_id, abs(movement.quantidade) quantidade_perdida,
  allocation.moeda, sum(allocation.custo_total) custo_perda_estoque,
  max(cost.status_custo) status_custo
from public.est_movimentos_mp movement
left join public.est_movimentos_mp_custo_alocacoes allocation on allocation.movimento_saida_id = movement.id
join public.est_movimentos_mp_custos_atuais cost on cost.movimento_mp_id = movement.id
where movement.tipo_movimento = 'ajuste_saida'
group by movement.id, allocation.moeda;

create or replace view public.pcp_op_lote_custo_direto_atual
with (security_invoker = true)
as
select output.op_id, output.id produto_gerado_id, output.tipo_produto,
  output.lote_pa_id, output.lote_pi_id, output.quantidade, cost.moeda,
  cost.custo_direto_mp - coalesce(loss_cost.custo_perda_processo, 0) custo_direto_produto,
  loss_cost.custo_perda_processo,
  case when cost.quantidade_mp_sem_custo = 0 and cost.componentes_pi_pa_sem_camada = 0
    then (cost.custo_direto_mp - coalesce(loss_cost.custo_perda_processo, 0)) / nullif(output.quantidade, 0) else null end custo_unitario_direto,
  case when cost.quantidade_mp_sem_custo = 0 and cost.componentes_pi_pa_sem_camada = 0
    then 'completo_mp' else 'pendente' end status_custo
from public.pcp_op_produtos_gerados output
left join public.pcp_op_custos_mp_atuais cost on cost.op_id = output.op_id
left join public.pcp_op_perdas_custos_atuais loss_cost
  on loss_cost.op_id = output.op_id and loss_cost.moeda is not distinct from cost.moeda;

create or replace view public.est_lotes_pa_custos_atuais
with (security_invoker = true)
as
select layer.lote_pa_id, lot.produto_embalagem_id, component.moeda,
  layer.quantidade_embalagens,
  component.custo_total,
  component.custo_total / nullif(layer.quantidade_embalagens, 0) custo_unitario_embalagem
from public.est_lotes_pa_custo_camadas layer
join public.est_lotes_pa_custo_componentes component on component.lote_custo_id = layer.id
join public.est_lotes_pa lot on lot.id = layer.lote_pa_id
;

create or replace view public.est_movimentos_pi_custos_atuais
with (security_invoker = true)
as
select movement.id movimento_pi_id, movement.lote_pi_id, movement.tipo_movimento,
  movement.origem_tabela, movement.origem_id, abs(movement.quantidade) quantidade,
  component.moeda,
  sum(allocation.quantidade_alocada*component.custo_total/layer.quantidade_base) custo_total,
  greatest(abs(movement.quantidade)-coalesce((select sum(a.quantidade_alocada)
    from public.est_movimentos_pi_custo_alocacoes a where a.movimento_saida_id=movement.id),0),0) quantidade_sem_camada
from public.est_movimentos_pi movement
left join public.est_movimentos_pi_custo_alocacoes allocation on allocation.movimento_saida_id=movement.id
left join public.est_lotes_pi_custo_camadas layer on layer.id=allocation.lote_custo_id
left join public.est_lotes_pi_custo_componentes component on component.lote_custo_id=layer.id
where movement.quantidade<0
group by movement.id,component.moeda;

create or replace view public.est_movimentos_pa_custos_atuais
with (security_invoker = true)
as
select movement.id movimento_pa_id, movement.lote_pa_id, movement.tipo_movimento,
  movement.origem_tabela, movement.origem_id, abs(movement.quantidade) quantidade,
  component.moeda,
  sum(allocation.quantidade_alocada*component.custo_total/layer.quantidade_embalagens) custo_total,
  greatest(abs(movement.quantidade)-coalesce((select sum(a.quantidade_alocada)
    from public.est_movimentos_pa_custo_alocacoes a where a.movimento_saida_id=movement.id),0),0) quantidade_sem_camada
from public.est_movimentos_pa movement
left join public.est_movimentos_pa_custo_alocacoes allocation on allocation.movimento_saida_id=movement.id
left join public.est_lotes_pa_custo_camadas layer on layer.id=allocation.lote_custo_id
left join public.est_lotes_pa_custo_componentes component on component.lote_custo_id=layer.id
where movement.quantidade<0
group by movement.id,component.moeda;

create or replace view public.est_perdas_pi_custos_atuais
with (security_invoker = true)
as select * from public.est_movimentos_pi_custos_atuais where tipo_movimento='ajuste_saida';

create or replace view public.est_perdas_pa_custos_atuais
with (security_invoker = true)
as select * from public.est_movimentos_pa_custos_atuais where tipo_movimento='ajuste_saida';

create or replace function public.materialize_pcp_op_pi_cost(p_op_id bigint)
returns integer language plpgsql security definer set search_path = public as $$
declare v_output record; v_cost record; v_layer_id bigint; v_count integer := 0;
begin
  select output.lote_pi_id, output.quantidade into v_output
    from public.pcp_op_produtos_gerados output
   where output.op_id = p_op_id and output.tipo_produto = 'PI';
  if not found then return 0; end if;
  if exists (
    select 1 from public.pcp_op_lote_custo_direto_atual cost
     where cost.op_id = p_op_id and cost.status_custo <> 'completo_mp'
  ) then return 0; end if;
  insert into public.est_lotes_pi_custo_camadas(lote_pi_id,op_id,quantidade_base)
  values(v_output.lote_pi_id,p_op_id,v_output.quantidade)
  on conflict(lote_pi_id) do nothing
  returning id into v_layer_id;
  if v_layer_id is null then
    select id into v_layer_id from public.est_lotes_pi_custo_camadas
     where lote_pi_id=v_output.lote_pi_id;
  end if;
  for v_cost in
    select cost.moeda, cost.custo_direto_produto
      from public.pcp_op_lote_custo_direto_atual cost
     where cost.op_id = p_op_id and cost.moeda is not null
  loop
    insert into public.est_lotes_pi_custo_componentes(lote_custo_id,moeda,custo_total)
    values(v_layer_id,v_cost.moeda,v_cost.custo_direto_produto)
    on conflict(lote_custo_id,moeda) do nothing;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

create or replace function public.materialize_pcp_envase_pa_cost(p_ordem_envase_id bigint)
returns integer language plpgsql security definer set search_path = public as $$
declare v_pending numeric; v_total_output numeric; v_output record; v_cost record;
  v_layer_id bigint; v_count integer := 0;
begin
  select coalesce(sum(greatest(abs(m.quantidade) - coalesce((select sum(a.quantidade_alocada)
    from public.est_movimentos_pi_custo_alocacoes a where a.movimento_saida_id=m.id),0),0)),0)
    into v_pending from public.est_movimentos_pi m
    where m.origem_tabela='pcp_ordens_envase' and m.origem_id=p_ordem_envase_id::text and m.quantidade<0;
  select v_pending + coalesce(sum(cost.quantidade_sem_custo),0) into v_pending
    from public.est_movimentos_mp_custos_atuais cost
    where cost.origem_tabela='pcp_ordens_envase' and cost.origem_id=p_ordem_envase_id::text;
  if v_pending > 0 then return 0; end if;
  select sum(output.quantidade) into v_total_output
    from public.pcp_ordem_envase_lotes_pa output where output.ordem_envase_id=p_ordem_envase_id;
  for v_output in select * from public.pcp_ordem_envase_lotes_pa where ordem_envase_id=p_ordem_envase_id loop
    insert into public.est_lotes_pa_custo_camadas(
      lote_pa_id,ordem_envase_id,quantidade_embalagens
    ) values (v_output.lote_pa_id,p_ordem_envase_id,v_output.quantidade)
    on conflict(lote_pa_id) do nothing
    returning id into v_layer_id;
    if v_layer_id is null then
      select id into v_layer_id from public.est_lotes_pa_custo_camadas
       where lote_pa_id=v_output.lote_pa_id;
    end if;
    for v_cost in
      select costs.moeda, sum(costs.custo_total) custo_total from (
        select component.moeda,
          a.quantidade_alocada * component.custo_total / layer.quantidade_base custo_total
        from public.est_movimentos_pi m
        join public.est_movimentos_pi_custo_alocacoes a on a.movimento_saida_id=m.id
        join public.est_lotes_pi_custo_camadas layer on layer.id=a.lote_custo_id
        join public.est_lotes_pi_custo_componentes component on component.lote_custo_id=layer.id
        where m.origem_tabela='pcp_ordens_envase' and m.origem_id=p_ordem_envase_id::text
        union all
        select a.moeda,a.custo_total from public.est_movimentos_mp m
        join public.est_movimentos_mp_custo_alocacoes a on a.movimento_saida_id=m.id
        where m.origem_tabela='pcp_ordens_envase' and m.origem_id=p_ordem_envase_id::text
      ) costs group by costs.moeda
    loop
      insert into public.est_lotes_pa_custo_componentes(lote_custo_id,moeda,custo_total)
      values(v_layer_id,v_cost.moeda,v_cost.custo_total*v_output.quantidade/nullif(v_total_output,0))
      on conflict(lote_custo_id,moeda) do nothing;
      v_count := v_count + 1;
    end loop;
  end loop;
  return v_count;
end;
$$;

alter function public.finalizar_pcp_op(bigint,jsonb,text,numeric,numeric,numeric,numeric,numeric,text,text,jsonb,text)
  rename to finalizar_pcp_op_impl_0077;

create or replace function public.finalizar_pcp_op(
  p_op_id bigint, p_outputs_jsonb jsonb, p_cq_status text, p_ph numeric,
  p_densidade_kg_l numeric, p_volume_l numeric, p_massa_kg numeric,
  p_temperatura_c numeric, p_separador_mp text, p_conferente_mp text,
  p_formuladores_jsonb jsonb, p_observacao text default null
) returns bigint language plpgsql security definer set search_path = public as $$
declare v_output jsonb; v_formula_product_id bigint; v_output_product_id bigint; v_type text;
  v_planned_volume numeric; v_result bigint; v_actor uuid;
begin
  perform public.require_current_user_permission('pcp.op.finish');
  if p_outputs_jsonb is null or jsonb_typeof(p_outputs_jsonb) <> 'array'
     or jsonb_array_length(p_outputs_jsonb) <> 1 then
    raise exception 'production OP must generate exactly one product lot';
  end if;
  select formula.produto_id, op.volume_planejado_l into v_formula_product_id, v_planned_volume
    from public.pcp_ordens_producao op
    join public.pcp_formula_versoes formula on formula.id = op.formula_versao_id
   where op.id = p_op_id;
  if v_formula_product_id is null then raise exception 'OP formula product not found'; end if;
  v_output := p_outputs_jsonb->0;
  v_type := upper(nullif(btrim(v_output->>'tipo_produto'), ''));
  if v_type = 'PI' then
    v_output_product_id := nullif(btrim(v_output->>'produto_id'), '')::bigint;
  elsif v_type = 'PA' then
    raise exception 'production OP generates PI; PA must be generated by packaging order';
  else raise exception 'invalid generated product type'; end if;
  if v_output_product_id is distinct from v_formula_product_id then
    raise exception 'generated product must match OP formula product';
  end if;
  v_result := public.finalizar_pcp_op_impl_0077(
    p_op_id, p_outputs_jsonb, p_cq_status, p_ph, p_densidade_kg_l, p_volume_l,
    p_massa_kg, p_temperatura_c, p_separador_mp, p_conferente_mp,
    p_formuladores_jsonb, p_observacao
  );
  if p_volume_l < v_planned_volume then
    v_actor := public.current_actor_id();
    insert into public.pcp_op_perdas_processo(op_id, volume_planejado_l, volume_real_l, created_by)
    values (p_op_id, v_planned_volume, p_volume_l, v_actor);
  end if;
  perform public.materialize_pcp_op_pi_cost(p_op_id);
  return v_result;
end;
$$;

alter function public.finalizar_pcp_ordem_envase(bigint,jsonb,text)
  rename to finalizar_pcp_ordem_envase_impl_0077;

create or replace function public.finalizar_pcp_ordem_envase(
  p_ordem_envase_id bigint, p_lotes_pa_jsonb jsonb, p_observacao text default null
) returns bigint language plpgsql security definer set search_path=public as $$
declare v_result bigint;
begin
  perform public.require_current_user_permission('pcp.envase.finish');
  v_result := public.finalizar_pcp_ordem_envase_impl_0077(p_ordem_envase_id,p_lotes_pa_jsonb,p_observacao);
  perform public.materialize_pcp_envase_pa_cost(p_ordem_envase_id);
  return v_result;
end;
$$;

alter table public.est_movimentos_mp_custo_alocacoes enable row level security;
alter table public.pcp_op_perdas_processo enable row level security;
alter table public.est_lotes_pi_custo_camadas enable row level security;
alter table public.est_lotes_pi_custo_componentes enable row level security;
alter table public.est_movimentos_pi_custo_alocacoes enable row level security;
alter table public.est_lotes_pa_custo_camadas enable row level security;
alter table public.est_lotes_pa_custo_componentes enable row level security;
alter table public.est_movimentos_pa_custo_alocacoes enable row level security;
drop policy if exists "permitted read MP cost allocations" on public.est_movimentos_mp_custo_alocacoes;
create policy "permitted read MP cost allocations" on public.est_movimentos_mp_custo_alocacoes
for select to authenticated using (public.can_current_user('pcp.cost.read'));
drop policy if exists "permitted read PCP process losses" on public.pcp_op_perdas_processo;
create policy "permitted read PCP process losses" on public.pcp_op_perdas_processo
for select to authenticated using (public.can_current_user('pcp.cost.read'));
do $$
declare v_table text;
begin
  foreach v_table in array array['est_lotes_pi_custo_camadas','est_lotes_pi_custo_componentes',
    'est_movimentos_pi_custo_alocacoes','est_lotes_pa_custo_camadas',
    'est_lotes_pa_custo_componentes','est_movimentos_pa_custo_alocacoes'] loop
    execute format('drop policy if exists "permitted read production cost" on public.%I',v_table);
    execute format('create policy "permitted read production cost" on public.%I for select to authenticated using (public.can_current_user(''pcp.cost.read''))',v_table);
  end loop;
end;
$$;

revoke all on public.est_movimentos_mp_custo_alocacoes from public, anon, authenticated;
revoke all on public.pcp_op_perdas_processo from public, anon, authenticated;
revoke all on public.est_lotes_pi_custo_camadas,public.est_lotes_pi_custo_componentes,
  public.est_movimentos_pi_custo_alocacoes,public.est_lotes_pa_custo_camadas,
  public.est_lotes_pa_custo_componentes,public.est_movimentos_pa_custo_alocacoes
  from public,anon,authenticated;
grant select on public.est_movimentos_mp_custo_alocacoes to authenticated;
grant select on public.pcp_op_perdas_processo to authenticated;
grant select on public.est_lotes_pi_custo_camadas,public.est_lotes_pi_custo_componentes,
  public.est_movimentos_pi_custo_alocacoes,public.est_lotes_pa_custo_camadas,
  public.est_lotes_pa_custo_componentes,public.est_movimentos_pa_custo_alocacoes to authenticated;
grant select on public.est_movimentos_mp_custos_atuais, public.pcp_op_custos_mp_atuais,
  public.pcp_op_lote_custo_direto_atual, public.pcp_op_perdas_custos_atuais,
  public.est_perdas_mp_custos_atuais, public.est_lotes_pa_custos_atuais,
  public.est_movimentos_pi_custos_atuais,public.est_movimentos_pa_custos_atuais,
  public.est_perdas_pi_custos_atuais,public.est_perdas_pa_custos_atuais to authenticated;
revoke all on function public.allocate_est_movimento_mp_cost(bigint) from public, anon, authenticated;
revoke all on function public.allocate_new_est_movimento_mp_cost() from public, anon, authenticated;
revoke all on function public.reconcile_mp_cost_after_value_insert() from public, anon, authenticated;
revoke all on function public.allocate_est_movimento_pi_cost(bigint) from public,anon,authenticated;
revoke all on function public.allocate_est_movimento_pa_cost(bigint) from public,anon,authenticated;
revoke all on function public.allocate_new_est_movimento_pi_pa_cost() from public,anon,authenticated;
revoke all on function public.materialize_pcp_op_pi_cost(bigint) from public,anon,authenticated;
revoke all on function public.materialize_pcp_envase_pa_cost(bigint) from public,anon,authenticated;
revoke all on function public.finalizar_pcp_op_impl_0077(bigint,jsonb,text,numeric,numeric,numeric,numeric,numeric,text,text,jsonb,text)
  from public, anon, authenticated;
revoke all on function public.finalizar_pcp_op(bigint,jsonb,text,numeric,numeric,numeric,numeric,numeric,text,text,jsonb,text)
  from public, anon;
grant execute on function public.finalizar_pcp_op(bigint,jsonb,text,numeric,numeric,numeric,numeric,numeric,text,text,jsonb,text)
  to authenticated;
revoke all on function public.finalizar_pcp_ordem_envase_impl_0077(bigint,jsonb,text) from public,anon,authenticated;
revoke all on function public.finalizar_pcp_ordem_envase(bigint,jsonb,text) from public,anon;
grant execute on function public.finalizar_pcp_ordem_envase(bigint,jsonb,text) to authenticated;

comment on table public.est_movimentos_mp_custo_alocacoes is
  'Alocacao append-only da saida de MP contra cada camada de entrada com preco proprio.';
comment on view public.pcp_op_lote_custo_direto_atual is
  'Custo direto de MP do unico lote gerado pela OP; custo ausente ou componente PI/PA permanece pendente.';
comment on table public.pcp_op_perdas_processo is
  'Perda fisica da OP em litros; distinta da perda de estoque e valorizada pelas camadas de insumos consumidas.';
comment on table public.est_lotes_pa_custo_camadas is
  'Custo material do PA: custo do PI consumido mais embalagens consumidas no envase; operacao e indiretos excluidos.';
