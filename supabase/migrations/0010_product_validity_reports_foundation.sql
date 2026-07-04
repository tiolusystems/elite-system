alter table public.cad_produtos_base
  add column if not exists prazo_validade_meses integer;

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conname = 'cad_produtos_prazo_validade_meses_check'
       and conrelid = 'public.cad_produtos_base'::regclass
  ) then
    alter table public.cad_produtos_base
      add constraint cad_produtos_prazo_validade_meses_check
      check (prazo_validade_meses is null or prazo_validade_meses between 1 and 240);
  end if;
end;
$$;

insert into public.permission_actions(action_key, module, description, default_allowed, sort_order)
values
  ('reports.view', 'relatorios', 'Visualizar relatorios e dashboards operacionais', true, 110)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order;

create or replace function public.set_cad_produto_prazo_validade(
  p_produto_id bigint,
  p_prazo_validade_meses integer,
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
begin
  perform public.require_current_user_permission('cadastros.manage');
  if p_produto_id is null or p_produto_id <= 0 then
    raise exception 'produto_id is required';
  end if;
  if p_prazo_validade_meses is not null and (p_prazo_validade_meses < 1 or p_prazo_validade_meses > 240) then
    raise exception 'prazo_validade_meses must be between 1 and 240';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;

  select jsonb_build_object(
      'prazo_validade_meses', prazo_validade_meses,
      'updated_at', updated_at
    )
    into v_before
    from public.cad_produtos_base
   where id = p_produto_id
   for update;

  if not found then
    raise exception 'produto not found';
  end if;

  v_actor := public.current_actor_id();

  update public.cad_produtos_base
     set prazo_validade_meses = p_prazo_validade_meses,
         updated_by = v_actor
   where id = p_produto_id;

  perform public.log_action(
    'cadastros.produto_prazo_validade_set',
    'cad_produtos_base',
    p_produto_id::text,
    'success',
    v_before,
    jsonb_build_object(
      'prazo_validade_meses', p_prazo_validade_meses,
      'motivo', trim(p_motivo)
    ),
    jsonb_build_object('source', 'set_cad_produto_prazo_validade')
  );

  return p_produto_id;
end;
$$;

create or replace function public.apply_est_lote_pa_validade_from_produto()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_prazo_validade_meses integer;
begin
  if new.data_validade is null and new.data_fabricacao is not null then
    select produto.prazo_validade_meses
      into v_prazo_validade_meses
      from public.cad_produto_embalagens produto_embalagem
      join public.cad_produtos_base produto on produto.id = produto_embalagem.produto_id
     where produto_embalagem.id = new.produto_embalagem_id;

    if v_prazo_validade_meses is not null then
      new.data_validade := (new.data_fabricacao + make_interval(months => v_prazo_validade_meses))::date;
    end if;
  end if;

  return new;
end;
$$;

create or replace function public.apply_est_lote_pi_validade_from_produto()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_prazo_validade_meses integer;
begin
  if new.data_validade is null and new.data_fabricacao is not null then
    select produto.prazo_validade_meses
      into v_prazo_validade_meses
      from public.cad_produtos_base produto
     where produto.id = new.produto_id;

    if v_prazo_validade_meses is not null then
      new.data_validade := (new.data_fabricacao + make_interval(months => v_prazo_validade_meses))::date;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_est_lotes_pa_validade_produto on public.est_lotes_pa;
create trigger trg_est_lotes_pa_validade_produto
before insert or update of produto_embalagem_id, data_fabricacao, data_validade
on public.est_lotes_pa
for each row execute function public.apply_est_lote_pa_validade_from_produto();

drop trigger if exists trg_est_lotes_pi_validade_produto on public.est_lotes_pi;
create trigger trg_est_lotes_pi_validade_produto
before insert or update of produto_id, data_fabricacao, data_validade
on public.est_lotes_pi
for each row execute function public.apply_est_lote_pi_validade_from_produto();

create table if not exists public.relatorio_catalogo (
  id bigint generated always as identity primary key,
  codigo text not null unique,
  modulo text not null,
  nome text not null,
  descricao text not null,
  fonte_principal text not null,
  status text not null default 'ativo',
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  constraint relatorio_catalogo_status_check check (status in ('ativo', 'planejado', 'inativo'))
);

alter table public.relatorio_catalogo enable row level security;

drop policy if exists "authenticated read report catalog" on public.relatorio_catalogo;
create policy "authenticated read report catalog" on public.relatorio_catalogo
for select to authenticated using (true);

insert into public.relatorio_catalogo(codigo, modulo, nome, descricao, fonte_principal, status, sort_order)
values
  ('estoque_lotes_vencimento', 'estoque', 'Lotes por vencimento', 'PA, PI e MP com data de validade, saldo e situacao de vencimento.', 'rel_estoque_lotes_vencimento', 'ativo', 100),
  ('estoque_reprocessamento_candidatos', 'estoque', 'Candidatos a reprocessamento', 'Lotes vencidos ou bloqueados com saldo disponivel para avaliacao de reprocessamento.', 'rel_estoque_reprocessamento_candidatos', 'ativo', 101),
  ('pcp_op_status', 'pcp', 'Status de OP', 'Ordens de producao por status, tipo e CQ.', 'pcp_ordens_producao', 'planejado', 200),
  ('comercial_pedidos_abertos', 'comercial', 'Pedidos em aberto', 'Pedidos abertos, bloqueados, pendentes e faturamento previsto.', 'com_pedidos', 'planejado', 300),
  ('romaneio_pendencias', 'romaneio', 'Pendencias de romaneio', 'Pedidos e itens com saldo pendente de separacao, reserva ou baixa.', 'exp_pedido_item_romaneio_saldos', 'planejado', 400),
  ('auditoria_reconciliacao', 'auditoria', 'Reconciliacao contra Excel', 'Metricas do sistema contra valores esperados da migracao.', 'value_reconciliations', 'ativo', 500)
on conflict (codigo) do update set
  modulo = excluded.modulo,
  nome = excluded.nome,
  descricao = excluded.descricao,
  fonte_principal = excluded.fonte_principal,
  status = excluded.status,
  sort_order = excluded.sort_order;

create or replace view public.rel_estoque_lotes_vencimento as
select
  'PA'::text as tipo_lote,
  saldo.lote_pa_id as lote_id,
  saldo.codigo_lote,
  produto.id as cadastro_id,
  produto.codigo_produto as codigo_cadastro,
  produto.nome as nome_cadastro,
  embalagem.descricao as embalagem,
  saldo.status,
  saldo.saldo_fisico,
  saldo.quantidade_reservada,
  saldo.saldo_disponivel,
  saldo.data_fabricacao,
  saldo.data_validade,
  produto.prazo_validade_meses,
  case when saldo.data_validade is null then null else saldo.data_validade - current_date end as dias_para_vencer,
  case
    when saldo.data_validade is null then 'sem_validade'
    when saldo.data_validade < current_date and saldo.saldo_disponivel > 0 then 'vencido_com_saldo'
    when saldo.data_validade < current_date then 'vencido_sem_saldo'
    when saldo.data_validade <= current_date + interval '30 days' then 'vence_30_dias'
    when saldo.data_validade <= current_date + interval '60 days' then 'vence_60_dias'
    else 'vigente'
  end as status_vencimento,
  saldo.origem_ref,
  saldo.observacao
from public.est_lotes_pa_saldos saldo
join public.cad_produto_embalagens produto_embalagem on produto_embalagem.id = saldo.produto_embalagem_id
join public.cad_produtos_base produto on produto.id = produto_embalagem.produto_id
join public.cad_embalagens embalagem on embalagem.id = produto_embalagem.embalagem_id

union all

select
  'PI'::text as tipo_lote,
  saldo.lote_pi_id as lote_id,
  saldo.codigo_lote,
  produto.id as cadastro_id,
  produto.codigo_produto as codigo_cadastro,
  produto.nome as nome_cadastro,
  null::text as embalagem,
  saldo.status,
  saldo.saldo_fisico,
  saldo.quantidade_reservada,
  saldo.saldo_disponivel,
  saldo.data_fabricacao,
  saldo.data_validade,
  produto.prazo_validade_meses,
  case when saldo.data_validade is null then null else saldo.data_validade - current_date end as dias_para_vencer,
  case
    when saldo.data_validade is null then 'sem_validade'
    when saldo.data_validade < current_date and saldo.saldo_disponivel > 0 then 'vencido_com_saldo'
    when saldo.data_validade < current_date then 'vencido_sem_saldo'
    when saldo.data_validade <= current_date + interval '30 days' then 'vence_30_dias'
    when saldo.data_validade <= current_date + interval '60 days' then 'vence_60_dias'
    else 'vigente'
  end as status_vencimento,
  saldo.origem_ref,
  saldo.observacao
from public.est_lotes_pi_saldos saldo
join public.cad_produtos_base produto on produto.id = saldo.produto_id

union all

select
  'MP'::text as tipo_lote,
  saldo.lote_mp_id as lote_id,
  saldo.codigo_lote,
  mp.id as cadastro_id,
  mp.sku_corrigido as codigo_cadastro,
  mp.nome as nome_cadastro,
  null::text as embalagem,
  saldo.status,
  saldo.saldo_fisico,
  saldo.quantidade_reservada,
  saldo.saldo_disponivel,
  saldo.data_fabricacao,
  saldo.data_validade,
  null::integer as prazo_validade_meses,
  case when saldo.data_validade is null then null else saldo.data_validade - current_date end as dias_para_vencer,
  case
    when saldo.data_validade is null then 'sem_validade'
    when saldo.data_validade < current_date and saldo.saldo_disponivel > 0 then 'vencido_com_saldo'
    when saldo.data_validade < current_date then 'vencido_sem_saldo'
    when saldo.data_validade <= current_date + interval '30 days' then 'vence_30_dias'
    when saldo.data_validade <= current_date + interval '60 days' then 'vence_60_dias'
    else 'vigente'
  end as status_vencimento,
  saldo.origem_ref,
  saldo.observacao
from public.est_lotes_mp_saldos saldo
join public.cad_materias_primas mp on mp.id = saldo.materia_prima_id;

create or replace view public.rel_estoque_reprocessamento_candidatos as
select
  tipo_lote,
  lote_id,
  codigo_lote,
  codigo_cadastro,
  nome_cadastro,
  embalagem,
  status,
  saldo_fisico,
  quantidade_reservada,
  saldo_disponivel,
  data_fabricacao,
  data_validade,
  dias_para_vencer,
  status_vencimento,
  case
    when status_vencimento = 'vencido_com_saldo' then 'alta'
    when status = 'bloqueado' and saldo_disponivel > 0 then 'alta'
    when status_vencimento = 'vence_30_dias' then 'media'
    else 'baixa'
  end as prioridade_reprocessamento,
  origem_ref,
  observacao
from public.rel_estoque_lotes_vencimento
where saldo_disponivel > 0
  and (
    status_vencimento in ('vencido_com_saldo', 'vence_30_dias')
    or status = 'bloqueado'
  );

grant select on public.relatorio_catalogo to authenticated;
grant select on public.rel_estoque_lotes_vencimento to authenticated;
grant select on public.rel_estoque_reprocessamento_candidatos to authenticated;

revoke all on function public.set_cad_produto_prazo_validade(bigint, integer, text) from public;
grant execute on function public.set_cad_produto_prazo_validade(bigint, integer, text) to authenticated;

revoke all on function public.apply_est_lote_pa_validade_from_produto() from public;
revoke all on function public.apply_est_lote_pi_validade_from_produto() from public;
