-- PCP: OP MAPA documental emits one operational packaging order.
-- Stock reservation and consumption are intentionally introduced by the next contract.

insert into public.permission_actions(
  action_key, module, description, default_allowed, sort_order,
  runtime_module_key, runtime_access_kind
)
values
  ('pcp.envase.view', 'pcp', 'Consultar ordens de envase', true, 320, 'pcp', 'read'),
  ('pcp.envase.issue', 'pcp', 'Emitir OP MAPA e ordem de envase vinculada', true, 321, 'pcp', 'write')
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

create table public.pcp_ordens_envase (
  id bigint generated always as identity primary key,
  codigo_ordem text not null unique,
  op_mapa_id bigint not null unique references public.pcp_ordens_producao(id) on delete restrict,
  lote_pi_origem_id bigint not null references public.est_lotes_pi(id) on delete restrict,
  produto_embalagem_id bigint not null references public.cad_produto_embalagens(id) on delete restrict,
  embalagem_versao_id bigint not null references public.cad_embalagem_versoes(id) on delete restrict,
  volume_planejado_l numeric not null,
  quantidade_pa_planejada numeric not null,
  status text not null default 'emitida',
  terminal_emissor text not null,
  observacao text,
  emitida_por uuid not null references public.user_profiles(id) on delete restrict,
  emitida_em timestamptz not null default now(),
  iniciada_em timestamptz,
  finalizada_em timestamptz,
  correlation_id text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pcp_ordens_envase_volume_check check (volume_planejado_l > 0),
  constraint pcp_ordens_envase_quantidade_pa_check check (
    quantidade_pa_planejada > 0 and quantidade_pa_planejada = trunc(quantidade_pa_planejada)
  ),
  constraint pcp_ordens_envase_status_check check (
    status in ('emitida', 'em_separacao', 'em_envase', 'finalizada', 'cancelada')
  ),
  constraint pcp_ordens_envase_terminal_check check (nullif(btrim(terminal_emissor), '') is not null),
  constraint pcp_ordens_envase_tempo_check check (
    (iniciada_em is null or iniciada_em >= emitida_em)
    and (finalizada_em is null or iniciada_em is not null)
    and (finalizada_em is null or finalizada_em >= iniciada_em)
  )
);

comment on table public.pcp_ordens_envase is
  'Operational packaging order emitted atomically with a documentary MAPA OP. Physical operator signatures remain on the printed document.';
comment on column public.pcp_ordens_envase.terminal_emissor is
  'Emission terminal snapshot supplied by the authenticated server session. Global session/IP/geolocation governance belongs to Security.';

create table public.pcp_ordem_envase_embalagens (
  id bigint generated always as identity primary key,
  ordem_envase_id bigint not null references public.pcp_ordens_envase(id) on delete restrict,
  embalagem_componente_id bigint not null references public.cad_embalagem_componentes(id) on delete restrict,
  materia_prima_id bigint not null references public.cad_materias_primas(id) on delete restrict,
  unidade_id bigint not null references public.cad_unidades_medida(id) on delete restrict,
  quantidade_un_l numeric not null,
  quantidade_planejada numeric not null,
  created_at timestamptz not null default now(),
  constraint pcp_ordem_envase_embalagens_un_l_check check (quantidade_un_l > 0),
  constraint pcp_ordem_envase_embalagens_quantidade_check check (quantidade_planejada > 0),
  constraint pcp_ordem_envase_embalagens_key unique (ordem_envase_id, embalagem_componente_id)
);

create index idx_pcp_ordens_envase_lote_pi on public.pcp_ordens_envase(lote_pi_origem_id, status);
create index idx_pcp_ordens_envase_apresentacao on public.pcp_ordens_envase(produto_embalagem_id, status);
create index idx_pcp_ordens_envase_emitida_em on public.pcp_ordens_envase(emitida_em desc, id desc);
create index idx_pcp_ordem_envase_embalagens_mp
  on public.pcp_ordem_envase_embalagens(materia_prima_id, ordem_envase_id);

create or replace function public.protect_pcp_envase_immutable_fields()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'packaging order history is append-only';
  end if;
  if new.codigo_ordem is distinct from old.codigo_ordem
     or new.op_mapa_id is distinct from old.op_mapa_id
     or new.lote_pi_origem_id is distinct from old.lote_pi_origem_id
     or new.produto_embalagem_id is distinct from old.produto_embalagem_id
     or new.embalagem_versao_id is distinct from old.embalagem_versao_id
     or new.volume_planejado_l is distinct from old.volume_planejado_l
     or new.quantidade_pa_planejada is distinct from old.quantidade_pa_planejada
     or new.terminal_emissor is distinct from old.terminal_emissor
     or new.emitida_por is distinct from old.emitida_por
     or new.emitida_em is distinct from old.emitida_em
     or new.correlation_id is distinct from old.correlation_id
     or new.created_at is distinct from old.created_at then
    raise exception 'packaging order identity and emission evidence are immutable';
  end if;
  return new;
end;
$$;

create or replace function public.block_pcp_envase_history_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'packaging order history is append-only';
end;
$$;

create trigger trg_pcp_ordens_envase_immutable
before update or delete on public.pcp_ordens_envase
for each row execute function public.protect_pcp_envase_immutable_fields();

create trigger trg_pcp_ordens_envase_no_truncate
before truncate on public.pcp_ordens_envase
for each statement execute function public.block_pcp_envase_history_mutation();

create trigger trg_pcp_ordem_envase_embalagens_append_only
before update or delete on public.pcp_ordem_envase_embalagens
for each row execute function public.block_pcp_envase_history_mutation();

create trigger trg_pcp_ordem_envase_embalagens_no_truncate
before truncate on public.pcp_ordem_envase_embalagens
for each statement execute function public.block_pcp_envase_history_mutation();

alter table public.pcp_ordens_envase enable row level security;
alter table public.pcp_ordem_envase_embalagens enable row level security;

create policy "authorized read pcp_ordens_envase"
  on public.pcp_ordens_envase for select to authenticated
  using (public.can_current_user('pcp.envase.view'));
create policy "authorized read pcp_ordem_envase_embalagens"
  on public.pcp_ordem_envase_embalagens for select to authenticated
  using (public.can_current_user('pcp.envase.view'));

create or replace function public.next_pcp_codigo_ordem_envase()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_next bigint;
begin
  perform pg_advisory_xact_lock(hashtextextended('elite:pcp:ordem_envase:codigo', 0));
  select coalesce(max(substring(codigo_ordem from '[0-9]+$')::bigint), 0) + 1
    into v_next
    from public.pcp_ordens_envase;
  return 'ENV-' || lpad(v_next::text, 8, '0');
end;
$$;

create or replace function public.pcp_envase_volume_pi_disponivel(p_lote_pi_id bigint)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce((select sum(movement.quantidade) from public.est_movimentos_pi movement
      where movement.lote_pi_id = p_lote_pi_id), 0)
    - coalesce((select sum(packaging_order.volume_planejado_l)
        from public.pcp_ordens_envase packaging_order
       where packaging_order.lote_pi_origem_id = p_lote_pi_id
         and packaging_order.status not in ('cancelada', 'finalizada')), 0)
$$;

-- OP MAPA must never be created without its packaging order. The governed
-- emitter below is the only public business path for this document.
alter function public.create_pcp_op(bigint, text, numeric, text)
  rename to create_pcp_op_operational_impl_0069;

create or replace function public.create_pcp_op(
  p_formula_versao_id bigint,
  p_tipo_op text,
  p_quantidade_planejada numeric default null,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_permission('pcp.op.create');
  if p_tipo_op = 'mapa_documental' then
    raise exception 'MAPA documentary OP must be emitted with its packaging order';
  end if;
  return public.create_pcp_op_operational_impl_0069(
    p_formula_versao_id,
    p_tipo_op,
    p_quantidade_planejada,
    p_observacao
  );
end;
$$;

create or replace function public.emitir_pcp_op_mapa_com_envase(
  p_formula_mapa_versao_id bigint,
  p_lote_pi_origem_id bigint,
  p_produto_embalagem_id bigint,
  p_volume_planejado_l numeric,
  p_terminal_emissor text,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_formula record;
  v_lote_pi record;
  v_apresentacao record;
  v_configuracao record;
  v_op_mapa_id bigint;
  v_ordem_envase_id bigint;
  v_codigo_ordem text;
  v_quantidade_pa numeric;
  v_component_count integer;
  v_correlation_id text;
  v_permission_context jsonb;
  v_after jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'pcp.envase.issue', 'pcp', 'pcp_ordens_envase', 'movement_event',
    jsonb_build_object('event', 'issue_mapa_and_packaging_order')
  );
  if p_formula_mapa_versao_id is null or p_formula_mapa_versao_id <= 0 then
    raise exception 'formula_mapa_versao_id is required';
  end if;
  if p_lote_pi_origem_id is null or p_lote_pi_origem_id <= 0 then
    raise exception 'lote_pi_origem_id is required';
  end if;
  if p_produto_embalagem_id is null or p_produto_embalagem_id <= 0 then
    raise exception 'produto_embalagem_id is required';
  end if;
  if p_volume_planejado_l is null or p_volume_planejado_l <= 0 then
    raise exception 'volume_planejado_l must be greater than zero';
  end if;
  if nullif(btrim(p_terminal_emissor), '') is null then
    raise exception 'terminal_emissor is required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('elite:pcp:envase:lote_pi:' || p_lote_pi_origem_id, 0));

  select formula.*
    into v_formula
    from public.pcp_formula_versoes formula
   where formula.id = p_formula_mapa_versao_id
     and formula.tipo_receita = 'mapa'
     and exists (
       select 1 from public.pcp_formula_ativa active_formula
        where active_formula.formula_versao_id = formula.id
          and active_formula.tipo_receita = 'mapa'
     );
  if not found then raise exception 'active MAPA formula version not found'; end if;

  select balance.*
    into v_lote_pi
    from public.est_lotes_pi_saldos balance
   where balance.lote_pi_id = p_lote_pi_origem_id;
  if not found then raise exception 'PI lot not found'; end if;
  if v_lote_pi.status <> 'disponivel' then raise exception 'PI lot is not released by CQ'; end if;
  if public.pcp_envase_volume_pi_disponivel(p_lote_pi_origem_id) < p_volume_planejado_l then
    raise exception 'insufficient available PI balance after issued packaging orders';
  end if;

  select item.*, package.id as embalagem_id
    into v_apresentacao
    from public.cad_produto_embalagens item
    join public.cad_embalagens package on package.id = item.embalagem_id
   where item.id = p_produto_embalagem_id
     and item.status = 'active'
     and package.status = 'active';
  if not found then raise exception 'active product presentation not found'; end if;
  if v_apresentacao.produto_id <> v_formula.produto_id
     or v_apresentacao.produto_id <> v_lote_pi.produto_id then
    raise exception 'MAPA formula, PI lot and product presentation must reference the same product';
  end if;

  select configuration.*
    into v_configuracao
    from public.cad_embalagem_configuracoes_atuais configuration
   where configuration.embalagem_id = v_apresentacao.embalagem_id;
  if not found then raise exception 'approved active packaging composition not found'; end if;

  v_quantidade_pa := p_volume_planejado_l * v_configuracao.unidades_embalagem_por_litro;
  if v_quantidade_pa <= 0 or v_quantidade_pa <> trunc(v_quantidade_pa) then
    raise exception 'planned volume must result in a whole number of finished packages';
  end if;

  v_actor := public.current_actor_id();
  v_op_mapa_id := public.create_pcp_op_operational_impl_0069(
    p_formula_mapa_versao_id, 'mapa_documental', p_volume_planejado_l, p_observacao
  );
  v_codigo_ordem := public.next_pcp_codigo_ordem_envase();
  v_correlation_id := 'pcp_op_mapa:' || v_op_mapa_id || ':envase';

  insert into public.pcp_ordens_envase(
    codigo_ordem, op_mapa_id, lote_pi_origem_id, produto_embalagem_id,
    embalagem_versao_id, volume_planejado_l, quantidade_pa_planejada,
    terminal_emissor, observacao, emitida_por, correlation_id
  ) values (
    v_codigo_ordem, v_op_mapa_id, p_lote_pi_origem_id, p_produto_embalagem_id,
    v_configuracao.embalagem_versao_id, p_volume_planejado_l, v_quantidade_pa,
    btrim(p_terminal_emissor), nullif(btrim(p_observacao), ''), v_actor, v_correlation_id
  ) returning id into v_ordem_envase_id;

  insert into public.pcp_ordem_envase_embalagens(
    ordem_envase_id, embalagem_componente_id, materia_prima_id, unidade_id,
    quantidade_un_l, quantidade_planejada
  )
  select
    v_ordem_envase_id, component.componente_id, component.materia_prima_id,
    component.unidade_id, component.quantidade_un_l,
    component.quantidade_un_l * p_volume_planejado_l
  from public.cad_embalagem_componentes_atuais component
  where component.embalagem_versao_id = v_configuracao.embalagem_versao_id;

  get diagnostics v_component_count = row_count;
  if v_component_count = 0 then raise exception 'packaging order requires at least one governed packaging component'; end if;

  select jsonb_build_object(
    'ordem', to_jsonb(packaging_order),
    'embalagens', (
      select jsonb_agg(to_jsonb(component) order by component.id)
      from public.pcp_ordem_envase_embalagens component
      where component.ordem_envase_id = packaging_order.id
    )
  ) into v_after
  from public.pcp_ordens_envase packaging_order
  where packaging_order.id = v_ordem_envase_id;

  perform public.log_audited_rpc_change(
    'pcp', 'pcp_ordens_envase', v_ordem_envase_id::text,
    'pcp.packaging_order_issued', 'pcp.envase.issue', v_permission_context,
    null, v_after,
    jsonb_build_object(
      'op_mapa_id', v_op_mapa_id,
      'lote_pi_origem_id', p_lote_pi_origem_id,
      'correlation_id', v_correlation_id,
      'terminal_emissor', btrim(p_terminal_emissor)
    ),
    'database_rpc'
  );
  return v_ordem_envase_id;
end;
$$;

create or replace view public.pcp_ordens_envase_dossie
with (security_invoker = true)
as
select
  packaging_order.*,
  mapa_op.codigo_op as codigo_op_mapa,
  formula.versao as formula_mapa_versao,
  pi_lot.codigo_lote as lote_pi_origem,
  product.codigo_produto,
  product.nome as produto_nome,
  sale_item.codigo_item,
  package.descricao as embalagem_descricao,
  profile.display_name as emissor_nome
from public.pcp_ordens_envase packaging_order
join public.pcp_ordens_producao mapa_op on mapa_op.id = packaging_order.op_mapa_id
join public.pcp_formula_versoes formula on formula.id = mapa_op.formula_versao_id
join public.est_lotes_pi pi_lot on pi_lot.id = packaging_order.lote_pi_origem_id
join public.cad_produto_embalagens sale_item on sale_item.id = packaging_order.produto_embalagem_id
join public.cad_produtos_base product on product.id = sale_item.produto_id
join public.cad_embalagens package on package.id = sale_item.embalagem_id
join public.user_profiles profile on profile.id = packaging_order.emitida_por;

revoke all on function public.protect_pcp_envase_immutable_fields() from public, anon, authenticated;
revoke all on function public.block_pcp_envase_history_mutation() from public, anon, authenticated;
revoke all on function public.next_pcp_codigo_ordem_envase() from public, anon, authenticated;
revoke all on function public.pcp_envase_volume_pi_disponivel(bigint) from public, anon, authenticated;
revoke all on function public.emitir_pcp_op_mapa_com_envase(bigint, bigint, bigint, numeric, text, text)
  from public, anon;
grant execute on function public.emitir_pcp_op_mapa_com_envase(bigint, bigint, bigint, numeric, text, text)
  to authenticated;

revoke all on public.pcp_ordens_envase from public, anon;
revoke all on public.pcp_ordem_envase_embalagens from public, anon;
revoke insert, update, delete, truncate on public.pcp_ordens_envase from authenticated;
revoke insert, update, delete, truncate on public.pcp_ordem_envase_embalagens from authenticated;
grant select on public.pcp_ordens_envase to authenticated;
grant select on public.pcp_ordem_envase_embalagens to authenticated;
grant select on public.pcp_ordens_envase_dossie to authenticated;
revoke all on public.pcp_ordens_envase_dossie from public, anon;
