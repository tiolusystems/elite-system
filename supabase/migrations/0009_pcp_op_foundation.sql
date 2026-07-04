create sequence if not exists public.est_lote_codigo_seq;
create sequence if not exists public.pcp_op_codigo_seq;

create or replace function public.current_actor_id()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
begin
  v_actor := auth.uid();
  if v_actor is not null and not exists (
    select 1 from public.user_profiles where id = v_actor and status = 'active'
  ) then
    v_actor := null;
  end if;
  return v_actor;
end;
$$;

create or replace function public.can_current_user(p_action_key text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_default_allowed boolean;
  v_override_allowed boolean;
begin
  if nullif(trim(p_action_key), '') is null then
    return false;
  end if;

  v_actor := auth.uid();
  if v_actor is null then
    return true;
  end if;

  if not exists (
    select 1 from public.user_profiles
    where id = v_actor
      and status = 'active'
  ) then
    return false;
  end if;

  select allowed
    into v_override_allowed
    from public.user_permission_overrides
    where user_id = v_actor
      and action_key = trim(p_action_key);

  if found then
    return v_override_allowed;
  end if;

  select default_allowed
    into v_default_allowed
    from public.permission_actions
    where action_key = trim(p_action_key);

  if found then
    return v_default_allowed;
  end if;

  return true;
end;
$$;

create or replace function public.require_current_user_permission(p_action_key text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.can_current_user(p_action_key) then
    perform public.log_action(
      'seguranca.permissao_negada',
      'permission_actions',
      trim(p_action_key),
      'denied',
      null,
      jsonb_build_object('action_key', trim(p_action_key)),
      jsonb_build_object('source', 'require_current_user_permission')
    );
    raise exception 'not allowed: %', trim(p_action_key);
  end if;
end;
$$;

create or replace function public.next_est_codigo_lote(p_prefix text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prefix text;
begin
  v_prefix := upper(nullif(trim(p_prefix), ''));
  if v_prefix is null then
    raise exception 'lot prefix is required';
  end if;

  return concat(
    v_prefix,
    '-',
    to_char(current_date, 'YYYYMMDD'),
    '-',
    lpad(nextval('public.est_lote_codigo_seq')::text, 7, '0')
  );
end;
$$;

create or replace function public.next_pcp_codigo_op()
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  return concat(
    'OP-',
    to_char(current_date, 'YYYYMMDD'),
    '-',
    lpad(nextval('public.pcp_op_codigo_seq')::text, 7, '0')
  );
end;
$$;

alter table public.est_movimentos_pa
  drop constraint if exists est_movimentos_pa_tipo_check;

alter table public.est_movimentos_pa
  drop constraint if exists est_movimentos_pa_quantidade_check;

alter table public.est_movimentos_pa
  add constraint est_movimentos_pa_tipo_check check (
    tipo_movimento in (
      'importacao_inicial',
      'entrada_producao',
      'ajuste_entrada',
      'estorno_saida',
      'transformacao_entrada',
      'saida_romaneio',
      'consumo_op',
      'ajuste_saida',
      'transformacao_saida'
    )
  );

alter table public.est_movimentos_pa
  add constraint est_movimentos_pa_quantidade_check check (
    (
      tipo_movimento in (
        'importacao_inicial',
        'entrada_producao',
        'ajuste_entrada',
        'estorno_saida',
        'transformacao_entrada'
      )
      and quantidade > 0
    )
    or (
      tipo_movimento in (
        'saida_romaneio',
        'consumo_op',
        'ajuste_saida',
        'transformacao_saida'
      )
      and quantidade < 0
    )
  );

create table if not exists public.est_lotes_mp (
  id bigint generated always as identity primary key,
  materia_prima_id bigint not null references public.cad_materias_primas(id),
  codigo_lote text not null,
  codigo_lote_norm text generated always as (lower(btrim(codigo_lote))) stored,
  status text not null default 'disponivel',
  data_fabricacao date,
  data_validade date,
  origem_ref text,
  observacao text,
  created_by uuid references public.user_profiles(id),
  updated_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint est_lotes_mp_status_check check (status in ('disponivel', 'bloqueado', 'esgotado', 'cancelado')),
  constraint est_lotes_mp_codigo_check check (length(btrim(codigo_lote)) > 0),
  constraint est_lotes_mp_datas_check check (
    data_fabricacao is null
    or data_validade is null
    or data_validade >= data_fabricacao
  ),
  constraint est_lotes_mp_key unique (materia_prima_id, codigo_lote_norm)
);

create table if not exists public.est_movimentos_mp (
  id bigint generated always as identity primary key,
  lote_mp_id bigint not null references public.est_lotes_mp(id),
  materia_prima_id bigint not null references public.cad_materias_primas(id),
  tipo_movimento text not null,
  quantidade numeric not null,
  origem_modulo text not null,
  origem_tabela text,
  origem_id text,
  observacao text,
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint est_movimentos_mp_tipo_check check (
    tipo_movimento in (
      'importacao_inicial',
      'entrada_compra',
      'ajuste_entrada',
      'estorno_consumo',
      'consumo_op',
      'ajuste_saida'
    )
  ),
  constraint est_movimentos_mp_quantidade_check check (
    (
      tipo_movimento in ('importacao_inicial', 'entrada_compra', 'ajuste_entrada', 'estorno_consumo')
      and quantidade > 0
    )
    or (
      tipo_movimento in ('consumo_op', 'ajuste_saida')
      and quantidade < 0
    )
  )
);

create table if not exists public.est_lotes_pi (
  id bigint generated always as identity primary key,
  produto_id bigint not null references public.cad_produtos_base(id),
  codigo_lote text not null,
  codigo_lote_norm text generated always as (lower(btrim(codigo_lote))) stored,
  status text not null default 'disponivel',
  data_fabricacao date,
  data_validade date,
  origem_ref text,
  observacao text,
  created_by uuid references public.user_profiles(id),
  updated_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint est_lotes_pi_status_check check (status in ('disponivel', 'bloqueado', 'esgotado', 'cancelado')),
  constraint est_lotes_pi_codigo_check check (length(btrim(codigo_lote)) > 0),
  constraint est_lotes_pi_datas_check check (
    data_fabricacao is null
    or data_validade is null
    or data_validade >= data_fabricacao
  ),
  constraint est_lotes_pi_key unique (produto_id, codigo_lote_norm)
);

create table if not exists public.est_movimentos_pi (
  id bigint generated always as identity primary key,
  lote_pi_id bigint not null references public.est_lotes_pi(id),
  produto_id bigint not null references public.cad_produtos_base(id),
  tipo_movimento text not null,
  quantidade numeric not null,
  origem_modulo text not null,
  origem_tabela text,
  origem_id text,
  observacao text,
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint est_movimentos_pi_tipo_check check (
    tipo_movimento in (
      'importacao_inicial',
      'entrada_producao',
      'ajuste_entrada',
      'estorno_consumo',
      'transformacao_entrada',
      'consumo_op',
      'ajuste_saida',
      'transformacao_saida'
    )
  ),
  constraint est_movimentos_pi_quantidade_check check (
    (
      tipo_movimento in (
        'importacao_inicial',
        'entrada_producao',
        'ajuste_entrada',
        'estorno_consumo',
        'transformacao_entrada'
      )
      and quantidade > 0
    )
    or (
      tipo_movimento in ('consumo_op', 'ajuste_saida', 'transformacao_saida')
      and quantidade < 0
    )
  )
);

create table if not exists public.pcp_formula_versoes (
  id bigint generated always as identity primary key,
  produto_id bigint not null references public.cad_produtos_base(id),
  tipo_receita text not null,
  versao integer not null,
  justificativa text not null,
  observacao text,
  previous_hash text,
  entry_hash text not null,
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint pcp_formula_versoes_tipo_check check (tipo_receita in ('producao', 'mapa')),
  constraint pcp_formula_versoes_versao_check check (versao > 0),
  constraint pcp_formula_versoes_justificativa_check check (length(btrim(justificativa)) > 0),
  constraint pcp_formula_versoes_key unique (produto_id, tipo_receita, versao)
);

create table if not exists public.pcp_formula_itens (
  id bigint generated always as identity primary key,
  formula_versao_id bigint not null references public.pcp_formula_versoes(id) on delete cascade,
  tipo_componente text not null,
  materia_prima_id bigint references public.cad_materias_primas(id),
  produto_embalagem_id bigint references public.cad_produto_embalagens(id),
  produto_id bigint references public.cad_produtos_base(id),
  quantidade numeric not null,
  unidade text,
  observacao text,
  created_at timestamptz not null default now(),
  constraint pcp_formula_itens_tipo_check check (tipo_componente in ('MP', 'PA', 'PI')),
  constraint pcp_formula_itens_quantidade_check check (quantidade > 0),
  constraint pcp_formula_itens_alvo_check check (
    (tipo_componente = 'MP' and materia_prima_id is not null and produto_embalagem_id is null and produto_id is null)
    or (tipo_componente = 'PA' and materia_prima_id is null and produto_embalagem_id is not null and produto_id is null)
    or (tipo_componente = 'PI' and materia_prima_id is null and produto_embalagem_id is null and produto_id is not null)
  )
);

create table if not exists public.pcp_formula_ativacoes (
  id bigint generated always as identity primary key,
  formula_versao_id bigint not null references public.pcp_formula_versoes(id),
  produto_id bigint not null references public.cad_produtos_base(id),
  tipo_receita text not null,
  motivo text not null,
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint pcp_formula_ativacoes_tipo_check check (tipo_receita in ('producao', 'mapa')),
  constraint pcp_formula_ativacoes_motivo_check check (length(btrim(motivo)) > 0)
);

create table if not exists public.pcp_ordens_producao (
  id bigint generated always as identity primary key,
  codigo_op text not null unique,
  formula_versao_id bigint not null references public.pcp_formula_versoes(id),
  tipo_op text not null,
  status text not null default 'draft',
  quantidade_planejada numeric,
  observacao text,
  cq_status text,
  created_by uuid references public.user_profiles(id),
  updated_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  constraint pcp_ordens_tipo_check check (tipo_op in ('estoque', 'experimental', 'desenvolvimento', 'reprocessamento', 'mapa_documental')),
  constraint pcp_ordens_status_check check (status in ('draft', 'planned', 'in_process', 'completed', 'cancelled', 'reversed')),
  constraint pcp_ordens_qtd_check check (quantidade_planejada is null or quantidade_planejada > 0),
  constraint pcp_ordens_cq_status_check check (cq_status is null or cq_status in ('aprovado', 'bloqueado', 'reprovado'))
);

create table if not exists public.pcp_op_componentes_planejados (
  id bigint generated always as identity primary key,
  op_id bigint not null references public.pcp_ordens_producao(id) on delete cascade,
  formula_item_id bigint references public.pcp_formula_itens(id),
  tipo_componente text not null,
  materia_prima_id bigint references public.cad_materias_primas(id),
  produto_embalagem_id bigint references public.cad_produto_embalagens(id),
  produto_id bigint references public.cad_produtos_base(id),
  quantidade_planejada numeric not null,
  unidade text,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  constraint pcp_op_comp_tipo_check check (tipo_componente in ('MP', 'PA', 'PI')),
  constraint pcp_op_comp_qtd_check check (quantidade_planejada > 0),
  constraint pcp_op_comp_status_check check (status in ('pending', 'reserved', 'consumed', 'cancelled')),
  constraint pcp_op_comp_alvo_check check (
    (tipo_componente = 'MP' and materia_prima_id is not null and produto_embalagem_id is null and produto_id is null)
    or (tipo_componente = 'PA' and materia_prima_id is null and produto_embalagem_id is not null and produto_id is null)
    or (tipo_componente = 'PI' and materia_prima_id is null and produto_embalagem_id is null and produto_id is not null)
  )
);

create table if not exists public.pcp_op_reservas_componentes (
  id bigint generated always as identity primary key,
  op_id bigint not null references public.pcp_ordens_producao(id) on delete cascade,
  op_componente_id bigint not null references public.pcp_op_componentes_planejados(id) on delete cascade,
  tipo_componente text not null,
  lote_mp_id bigint references public.est_lotes_mp(id),
  lote_pa_id bigint references public.est_lotes_pa(id),
  lote_pi_id bigint references public.est_lotes_pi(id),
  quantidade_reservada numeric not null,
  status text not null default 'ativa',
  motivo_liberacao text,
  created_by uuid references public.user_profiles(id),
  updated_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pcp_op_reservas_tipo_check check (tipo_componente in ('MP', 'PA', 'PI')),
  constraint pcp_op_reservas_status_check check (status in ('ativa', 'baixada', 'liberada', 'estornada')),
  constraint pcp_op_reservas_qtd_check check (quantidade_reservada > 0),
  constraint pcp_op_reservas_lote_check check (
    (tipo_componente = 'MP' and lote_mp_id is not null and lote_pa_id is null and lote_pi_id is null)
    or (tipo_componente = 'PA' and lote_mp_id is null and lote_pa_id is not null and lote_pi_id is null)
    or (tipo_componente = 'PI' and lote_mp_id is null and lote_pa_id is null and lote_pi_id is not null)
  )
);

create table if not exists public.pcp_op_consumos_componentes (
  id bigint generated always as identity primary key,
  op_id bigint not null references public.pcp_ordens_producao(id),
  op_componente_id bigint not null references public.pcp_op_componentes_planejados(id),
  reserva_id bigint not null references public.pcp_op_reservas_componentes(id),
  tipo_componente text not null,
  lote_mp_id bigint references public.est_lotes_mp(id),
  lote_pa_id bigint references public.est_lotes_pa(id),
  lote_pi_id bigint references public.est_lotes_pi(id),
  quantidade_consumida numeric not null,
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint pcp_op_consumos_tipo_check check (tipo_componente in ('MP', 'PA', 'PI')),
  constraint pcp_op_consumos_qtd_check check (quantidade_consumida > 0)
);

create table if not exists public.pcp_op_cq_resultados (
  id bigint generated always as identity primary key,
  op_id bigint not null unique references public.pcp_ordens_producao(id) on delete cascade,
  cq_status text not null,
  ph numeric not null,
  densidade_kg_l numeric not null,
  volume_l numeric not null,
  massa_kg numeric not null,
  temperatura_c numeric not null,
  separador_mp text not null,
  conferente_mp text not null,
  formuladores_json jsonb not null,
  observacao text,
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint pcp_op_cq_status_check check (cq_status in ('aprovado', 'bloqueado', 'reprovado')),
  constraint pcp_op_cq_numeros_check check (
    ph >= 0
    and densidade_kg_l > 0
    and volume_l > 0
    and massa_kg > 0
  ),
  constraint pcp_op_cq_pessoas_check check (
    length(btrim(separador_mp)) > 0
    and length(btrim(conferente_mp)) > 0
    and jsonb_typeof(formuladores_json) = 'array'
    and jsonb_array_length(formuladores_json) > 0
  )
);

create table if not exists public.pcp_op_produtos_gerados (
  id bigint generated always as identity primary key,
  op_id bigint not null references public.pcp_ordens_producao(id) on delete cascade,
  tipo_produto text not null,
  produto_embalagem_id bigint references public.cad_produto_embalagens(id),
  produto_id bigint references public.cad_produtos_base(id),
  lote_pa_id bigint references public.est_lotes_pa(id),
  lote_pi_id bigint references public.est_lotes_pi(id),
  quantidade numeric not null,
  status_lote text not null,
  observacao text,
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint pcp_op_produtos_tipo_check check (tipo_produto in ('PA', 'PI')),
  constraint pcp_op_produtos_qtd_check check (quantidade > 0),
  constraint pcp_op_produtos_status_check check (status_lote in ('disponivel', 'bloqueado', 'esgotado', 'cancelado')),
  constraint pcp_op_produtos_alvo_check check (
    (tipo_produto = 'PA' and produto_embalagem_id is not null and produto_id is null and lote_pa_id is not null and lote_pi_id is null)
    or (tipo_produto = 'PI' and produto_embalagem_id is null and produto_id is not null and lote_pa_id is null and lote_pi_id is not null)
  )
);

drop index if exists public.ux_est_reservas_pa_item_ativa;

create unique index if not exists ux_est_reservas_pa_item_lote_ativa
  on public.est_reservas_pa(romaneio_item_id, lote_pa_id)
  where status = 'ativa';

create unique index if not exists ux_pcp_reserva_mp_ativa
  on public.pcp_op_reservas_componentes(op_componente_id, lote_mp_id)
  where status = 'ativa' and lote_mp_id is not null;

create unique index if not exists ux_pcp_reserva_pa_ativa
  on public.pcp_op_reservas_componentes(op_componente_id, lote_pa_id)
  where status = 'ativa' and lote_pa_id is not null;

create unique index if not exists ux_pcp_reserva_pi_ativa
  on public.pcp_op_reservas_componentes(op_componente_id, lote_pi_id)
  where status = 'ativa' and lote_pi_id is not null;

create index if not exists idx_est_lotes_mp_materia_status
  on public.est_lotes_mp(materia_prima_id, status);
create index if not exists idx_est_movimentos_mp_lote
  on public.est_movimentos_mp(lote_mp_id, created_at desc);
create index if not exists idx_est_lotes_pi_produto_status
  on public.est_lotes_pi(produto_id, status);
create index if not exists idx_est_movimentos_pi_lote
  on public.est_movimentos_pi(lote_pi_id, created_at desc);
create index if not exists idx_pcp_formula_produto_tipo
  on public.pcp_formula_versoes(produto_id, tipo_receita, versao desc);
create index if not exists idx_pcp_op_status_tipo
  on public.pcp_ordens_producao(status, tipo_op, created_at desc);
create index if not exists idx_pcp_op_reservas_status
  on public.pcp_op_reservas_componentes(op_id, status);
create index if not exists idx_pcp_op_produtos
  on public.pcp_op_produtos_gerados(op_id, tipo_produto);

drop trigger if exists trg_est_lotes_mp_updated_at on public.est_lotes_mp;
create trigger trg_est_lotes_mp_updated_at before update on public.est_lotes_mp
for each row execute function public.touch_updated_at();

drop trigger if exists trg_est_lotes_pi_updated_at on public.est_lotes_pi;
create trigger trg_est_lotes_pi_updated_at before update on public.est_lotes_pi
for each row execute function public.touch_updated_at();

drop trigger if exists trg_pcp_ordens_updated_at on public.pcp_ordens_producao;
create trigger trg_pcp_ordens_updated_at before update on public.pcp_ordens_producao
for each row execute function public.touch_updated_at();

drop trigger if exists trg_pcp_op_reservas_updated_at on public.pcp_op_reservas_componentes;
create trigger trg_pcp_op_reservas_updated_at before update on public.pcp_op_reservas_componentes
for each row execute function public.touch_updated_at();

create or replace function public.prevent_est_movimentos_mp_changes()
returns trigger
language plpgsql
as $$
begin
  raise exception 'est_movimentos_mp is append-only';
end;
$$;

create or replace function public.prevent_est_movimentos_pi_changes()
returns trigger
language plpgsql
as $$
begin
  raise exception 'est_movimentos_pi is append-only';
end;
$$;

create or replace function public.prevent_pcp_formula_changes()
returns trigger
language plpgsql
as $$
begin
  raise exception 'PCP formula records are append-only';
end;
$$;

drop trigger if exists trg_est_movimentos_mp_no_update on public.est_movimentos_mp;
create trigger trg_est_movimentos_mp_no_update
before update or delete on public.est_movimentos_mp
for each row execute function public.prevent_est_movimentos_mp_changes();

drop trigger if exists trg_est_movimentos_pi_no_update on public.est_movimentos_pi;
create trigger trg_est_movimentos_pi_no_update
before update or delete on public.est_movimentos_pi
for each row execute function public.prevent_est_movimentos_pi_changes();

drop trigger if exists trg_pcp_formula_versoes_no_update on public.pcp_formula_versoes;
create trigger trg_pcp_formula_versoes_no_update
before update or delete on public.pcp_formula_versoes
for each row execute function public.prevent_pcp_formula_changes();

drop trigger if exists trg_pcp_formula_itens_no_update on public.pcp_formula_itens;
create trigger trg_pcp_formula_itens_no_update
before update or delete on public.pcp_formula_itens
for each row execute function public.prevent_pcp_formula_changes();

drop trigger if exists trg_pcp_formula_ativacoes_no_update on public.pcp_formula_ativacoes;
create trigger trg_pcp_formula_ativacoes_no_update
before update or delete on public.pcp_formula_ativacoes
for each row execute function public.prevent_pcp_formula_changes();

alter table public.est_lotes_mp enable row level security;
alter table public.est_movimentos_mp enable row level security;
alter table public.est_lotes_pi enable row level security;
alter table public.est_movimentos_pi enable row level security;
alter table public.pcp_formula_versoes enable row level security;
alter table public.pcp_formula_itens enable row level security;
alter table public.pcp_formula_ativacoes enable row level security;
alter table public.pcp_ordens_producao enable row level security;
alter table public.pcp_op_componentes_planejados enable row level security;
alter table public.pcp_op_reservas_componentes enable row level security;
alter table public.pcp_op_consumos_componentes enable row level security;
alter table public.pcp_op_cq_resultados enable row level security;
alter table public.pcp_op_produtos_gerados enable row level security;

create policy "authenticated full MP lot access" on public.est_lotes_mp
for all to authenticated using (true) with check (true);
create policy "authenticated full MP movement access" on public.est_movimentos_mp
for all to authenticated using (true) with check (true);
create policy "authenticated full PI lot access" on public.est_lotes_pi
for all to authenticated using (true) with check (true);
create policy "authenticated full PI movement access" on public.est_movimentos_pi
for all to authenticated using (true) with check (true);
create policy "authenticated full PCP formula version access" on public.pcp_formula_versoes
for all to authenticated using (true) with check (true);
create policy "authenticated full PCP formula item access" on public.pcp_formula_itens
for all to authenticated using (true) with check (true);
create policy "authenticated full PCP formula activation access" on public.pcp_formula_ativacoes
for all to authenticated using (true) with check (true);
create policy "authenticated full PCP order access" on public.pcp_ordens_producao
for all to authenticated using (true) with check (true);
create policy "authenticated full PCP planned component access" on public.pcp_op_componentes_planejados
for all to authenticated using (true) with check (true);
create policy "authenticated full PCP reservation access" on public.pcp_op_reservas_componentes
for all to authenticated using (true) with check (true);
create policy "authenticated full PCP consumption access" on public.pcp_op_consumos_componentes
for all to authenticated using (true) with check (true);
create policy "authenticated full PCP CQ access" on public.pcp_op_cq_resultados
for all to authenticated using (true) with check (true);
create policy "authenticated full PCP generated product access" on public.pcp_op_produtos_gerados
for all to authenticated using (true) with check (true);

insert into public.permission_actions(action_key, module, description, default_allowed, sort_order)
values
  ('estoque.mp.lots.create', 'estoque_mp', 'Criar lote de materia-prima com codigo automatico ou informado', true, 260),
  ('estoque.pi.lots.create', 'estoque_pi', 'Criar lote de produto intermediario com codigo automatico ou informado', true, 261),
  ('pcp.formula.create', 'pcp', 'Criar versao de formula de producao ou MAPA', true, 300),
  ('pcp.formula.change', 'pcp', 'Alterar formula criando nova versao auditavel', true, 301),
  ('pcp.op.create', 'pcp', 'Criar OP de estoque, experimental, desenvolvimento, reprocessamento ou MAPA documental', true, 302),
  ('pcp.op.reserve_components', 'pcp', 'Reservar MP, PA ou PI para OP', true, 303),
  ('pcp.op.start', 'pcp', 'Iniciar OP planejada', true, 304),
  ('pcp.op.finish', 'pcp', 'Finalizar OP com CQ e movimentacao de estoque', true, 305),
  ('pcp.op.cancel', 'pcp', 'Cancelar OP liberando reservas', true, 306),
  ('pcp.cq.record', 'pcp', 'Registrar CQ de OP', true, 307),
  ('pcp.experimental.release', 'pcp', 'Liberar lote experimental ou desenvolvimento bloqueado', true, 308)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order;

create or replace view public.est_lotes_pa_saldos as
with movimentos as (
  select
    lote_pa_id,
    sum(case when quantidade > 0 then quantidade else 0 end) as quantidade_entrada,
    sum(case when quantidade < 0 then -1 * quantidade else 0 end) as quantidade_saida,
    sum(quantidade) as saldo_fisico
  from public.est_movimentos_pa
  group by lote_pa_id
),
reservas as (
  select lote_pa_id, sum(quantidade_reservada) as quantidade_reservada
  from (
    select lote_pa_id, quantidade_reservada
    from public.est_reservas_pa
    where status = 'ativa'
    union all
    select lote_pa_id, quantidade_reservada
    from public.pcp_op_reservas_componentes
    where status = 'ativa'
      and tipo_componente = 'PA'
  ) reserva
  group by lote_pa_id
)
select
  lote.id as lote_pa_id,
  lote.produto_embalagem_id,
  lote.codigo_lote,
  lote.status,
  lote.data_fabricacao,
  lote.data_validade,
  coalesce(movimentos.quantidade_entrada, 0) as quantidade_entrada,
  coalesce(movimentos.quantidade_saida, 0) as quantidade_saida,
  coalesce(movimentos.saldo_fisico, 0) as saldo_fisico,
  coalesce(reservas.quantidade_reservada, 0) as quantidade_reservada,
  coalesce(movimentos.saldo_fisico, 0) - coalesce(reservas.quantidade_reservada, 0) as saldo_disponivel,
  lote.origem_ref,
  lote.observacao,
  lote.created_at,
  lote.updated_at
from public.est_lotes_pa lote
left join movimentos on movimentos.lote_pa_id = lote.id
left join reservas on reservas.lote_pa_id = lote.id;

grant select on public.est_lotes_pa_saldos to authenticated;

create or replace view public.est_lotes_mp_saldos as
with movimentos as (
  select
    lote_mp_id,
    sum(case when quantidade > 0 then quantidade else 0 end) as quantidade_entrada,
    sum(case when quantidade < 0 then -1 * quantidade else 0 end) as quantidade_saida,
    sum(quantidade) as saldo_fisico
  from public.est_movimentos_mp
  group by lote_mp_id
),
reservas as (
  select lote_mp_id, sum(quantidade_reservada) as quantidade_reservada
  from public.pcp_op_reservas_componentes
  where status = 'ativa'
    and tipo_componente = 'MP'
  group by lote_mp_id
)
select
  lote.id as lote_mp_id,
  lote.materia_prima_id,
  lote.codigo_lote,
  lote.status,
  lote.data_fabricacao,
  lote.data_validade,
  coalesce(movimentos.quantidade_entrada, 0) as quantidade_entrada,
  coalesce(movimentos.quantidade_saida, 0) as quantidade_saida,
  coalesce(movimentos.saldo_fisico, 0) as saldo_fisico,
  coalesce(reservas.quantidade_reservada, 0) as quantidade_reservada,
  coalesce(movimentos.saldo_fisico, 0) - coalesce(reservas.quantidade_reservada, 0) as saldo_disponivel,
  lote.origem_ref,
  lote.observacao,
  lote.created_at,
  lote.updated_at
from public.est_lotes_mp lote
left join movimentos on movimentos.lote_mp_id = lote.id
left join reservas on reservas.lote_mp_id = lote.id;

create or replace view public.est_lotes_pi_saldos as
with movimentos as (
  select
    lote_pi_id,
    sum(case when quantidade > 0 then quantidade else 0 end) as quantidade_entrada,
    sum(case when quantidade < 0 then -1 * quantidade else 0 end) as quantidade_saida,
    sum(quantidade) as saldo_fisico
  from public.est_movimentos_pi
  group by lote_pi_id
),
reservas as (
  select lote_pi_id, sum(quantidade_reservada) as quantidade_reservada
  from public.pcp_op_reservas_componentes
  where status = 'ativa'
    and tipo_componente = 'PI'
  group by lote_pi_id
)
select
  lote.id as lote_pi_id,
  lote.produto_id,
  lote.codigo_lote,
  lote.status,
  lote.data_fabricacao,
  lote.data_validade,
  coalesce(movimentos.quantidade_entrada, 0) as quantidade_entrada,
  coalesce(movimentos.quantidade_saida, 0) as quantidade_saida,
  coalesce(movimentos.saldo_fisico, 0) as saldo_fisico,
  coalesce(reservas.quantidade_reservada, 0) as quantidade_reservada,
  coalesce(movimentos.saldo_fisico, 0) - coalesce(reservas.quantidade_reservada, 0) as saldo_disponivel,
  lote.origem_ref,
  lote.observacao,
  lote.created_at,
  lote.updated_at
from public.est_lotes_pi lote
left join movimentos on movimentos.lote_pi_id = lote.id
left join reservas on reservas.lote_pi_id = lote.id;

grant select on public.est_lotes_mp_saldos to authenticated;
grant select on public.est_lotes_pi_saldos to authenticated;

create or replace view public.pcp_formula_ativa as
select distinct on (formula.produto_id, formula.tipo_receita)
  formula.id as formula_versao_id,
  formula.produto_id,
  formula.tipo_receita,
  formula.versao,
  formula.justificativa,
  formula.observacao,
  formula.entry_hash,
  ativacao.id as ativacao_id,
  ativacao.motivo as motivo_ativacao,
  ativacao.created_at as ativada_at,
  ativacao.created_by as ativada_by
from public.pcp_formula_ativacoes ativacao
join public.pcp_formula_versoes formula on formula.id = ativacao.formula_versao_id
order by formula.produto_id, formula.tipo_receita, ativacao.created_at desc, ativacao.id desc;

grant select on public.pcp_formula_ativa to authenticated;

create or replace function public.sync_est_lote_mp_status(p_lote_mp_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_saldo_fisico numeric;
begin
  select status
    into v_status
    from public.est_lotes_mp
    where id = p_lote_mp_id
    for update;

  if not found then
    raise exception 'MP lot not found';
  end if;

  select saldo_fisico
    into v_saldo_fisico
    from public.est_lotes_mp_saldos
    where lote_mp_id = p_lote_mp_id;

  if v_status in ('disponivel', 'esgotado') then
    update public.est_lotes_mp
       set status = case when coalesce(v_saldo_fisico, 0) <= 0 then 'esgotado' else 'disponivel' end
     where id = p_lote_mp_id;
  end if;
end;
$$;

create or replace function public.sync_est_lote_pi_status(p_lote_pi_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_saldo_fisico numeric;
begin
  select status
    into v_status
    from public.est_lotes_pi
    where id = p_lote_pi_id
    for update;

  if not found then
    raise exception 'PI lot not found';
  end if;

  select saldo_fisico
    into v_saldo_fisico
    from public.est_lotes_pi_saldos
    where lote_pi_id = p_lote_pi_id;

  if v_status in ('disponivel', 'esgotado') then
    update public.est_lotes_pi
       set status = case when coalesce(v_saldo_fisico, 0) <= 0 then 'esgotado' else 'disponivel' end
     where id = p_lote_pi_id;
  end if;
end;
$$;

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
  v_codigo_lote text;
  v_produto_embalagem_status text;
begin
  perform public.require_current_user_permission('estoque.pa.lots.create');
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
  );

  if p_status <> 'bloqueado' then
    perform public.sync_est_lote_pa_status(v_lote_id);
  end if;

  perform public.log_action(
    'estoque.pa_lote_auto_created',
    'est_lotes_pa',
    v_lote_id::text,
    'success',
    null,
    jsonb_build_object(
      'produto_embalagem_id', p_produto_embalagem_id,
      'codigo_lote', v_codigo_lote,
      'quantidade_entrada', p_quantidade_entrada,
      'tipo_entrada', p_tipo_entrada,
      'status', p_status
    ),
    jsonb_build_object('source', 'create_est_lote_pa_auto')
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
  v_codigo_lote text;
  v_mp_status text;
begin
  perform public.require_current_user_permission('estoque.mp.lots.create');
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
  );

  if p_status <> 'bloqueado' then
    perform public.sync_est_lote_mp_status(v_lote_id);
  end if;

  perform public.log_action(
    'estoque.mp_lote_created',
    'est_lotes_mp',
    v_lote_id::text,
    'success',
    null,
    jsonb_build_object('materia_prima_id', p_materia_prima_id, 'codigo_lote', v_codigo_lote, 'quantidade_entrada', p_quantidade_entrada),
    jsonb_build_object('source', 'create_est_lote_mp')
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
  v_codigo_lote text;
  v_produto_status text;
begin
  perform public.require_current_user_permission('estoque.pi.lots.create');
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
  );

  if p_status <> 'bloqueado' then
    perform public.sync_est_lote_pi_status(v_lote_id);
  end if;

  perform public.log_action(
    'estoque.pi_lote_created',
    'est_lotes_pi',
    v_lote_id::text,
    'success',
    null,
    jsonb_build_object('produto_id', p_produto_id, 'codigo_lote', v_codigo_lote, 'quantidade_entrada', p_quantidade_entrada),
    jsonb_build_object('source', 'create_est_lote_pi')
  );

  return v_lote_id;
end;
$$;

create or replace function public.create_pcp_formula_versao(
  p_produto_id bigint,
  p_tipo_receita text,
  p_justificativa text,
  p_componentes_jsonb jsonb default '[]'::jsonb,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_formula_id bigint;
  v_versao integer;
  v_previous_hash text;
  v_entry_hash text;
  v_component jsonb;
  v_tipo_componente text;
  v_quantidade numeric;
  v_existing_count integer;
begin
  if p_produto_id is null or p_produto_id <= 0 then
    raise exception 'produto_id is required';
  end if;
  if p_tipo_receita not in ('producao', 'mapa') then
    raise exception 'invalid tipo_receita';
  end if;
  if nullif(trim(p_justificativa), '') is null then
    raise exception 'justificativa is required';
  end if;
  if p_componentes_jsonb is null or jsonb_typeof(p_componentes_jsonb) <> 'array' then
    raise exception 'componentes_jsonb must be an array';
  end if;
  if p_tipo_receita = 'producao' and jsonb_array_length(p_componentes_jsonb) = 0 then
    raise exception 'production recipe requires at least one component';
  end if;

  select count(*)
    into v_existing_count
    from public.pcp_formula_versoes
    where produto_id = p_produto_id
      and tipo_receita = p_tipo_receita;

  if v_existing_count = 0 then
    perform public.require_current_user_permission('pcp.formula.create');
  else
    perform public.require_current_user_permission('pcp.formula.change');
  end if;

  v_actor := public.current_actor_id();

  select coalesce(max(versao), 0) + 1
    into v_versao
    from public.pcp_formula_versoes
    where produto_id = p_produto_id
      and tipo_receita = p_tipo_receita;

  select entry_hash
    into v_previous_hash
    from public.pcp_formula_versoes
    where produto_id = p_produto_id
      and tipo_receita = p_tipo_receita
    order by versao desc
    limit 1;

  v_entry_hash := encode(
    extensions.digest(
      concat_ws(
        '|',
        coalesce(v_previous_hash, ''),
        p_produto_id::text,
        p_tipo_receita,
        v_versao::text,
        trim(p_justificativa),
        coalesce(p_componentes_jsonb::text, ''),
        clock_timestamp()::text
      ),
      'sha256'
    ),
    'hex'
  );

  insert into public.pcp_formula_versoes(
    produto_id,
    tipo_receita,
    versao,
    justificativa,
    observacao,
    previous_hash,
    entry_hash,
    created_by
  )
  values (
    p_produto_id,
    p_tipo_receita,
    v_versao,
    trim(p_justificativa),
    nullif(trim(p_observacao), ''),
    v_previous_hash,
    v_entry_hash,
    v_actor
  )
  returning id into v_formula_id;

  for v_component in
    select value from jsonb_array_elements(p_componentes_jsonb)
  loop
    v_tipo_componente := upper(nullif(trim(v_component->>'tipo_componente'), ''));
    if v_tipo_componente not in ('MP', 'PA', 'PI') then
      raise exception 'invalid formula component type';
    end if;
    if nullif(trim(v_component->>'quantidade'), '') is null then
      raise exception 'formula component quantity is required';
    end if;
    v_quantidade := (v_component->>'quantidade')::numeric;
    if v_quantidade <= 0 then
      raise exception 'formula component quantity must be greater than zero';
    end if;

    insert into public.pcp_formula_itens(
      formula_versao_id,
      tipo_componente,
      materia_prima_id,
      produto_embalagem_id,
      produto_id,
      quantidade,
      unidade,
      observacao
    )
    values (
      v_formula_id,
      v_tipo_componente,
      case when v_tipo_componente = 'MP' then (v_component->>'materia_prima_id')::bigint else null end,
      case when v_tipo_componente = 'PA' then (v_component->>'produto_embalagem_id')::bigint else null end,
      case when v_tipo_componente = 'PI' then (v_component->>'produto_id')::bigint else null end,
      v_quantidade,
      nullif(trim(v_component->>'unidade'), ''),
      nullif(trim(v_component->>'observacao'), '')
    );
  end loop;

  perform public.log_action(
    'pcp.formula_versao_created',
    'pcp_formula_versoes',
    v_formula_id::text,
    'success',
    null,
    jsonb_build_object(
      'produto_id', p_produto_id,
      'tipo_receita', p_tipo_receita,
      'versao', v_versao,
      'componentes', jsonb_array_length(p_componentes_jsonb)
    ),
    jsonb_build_object('source', 'create_pcp_formula_versao')
  );

  return v_formula_id;
end;
$$;

create or replace function public.activate_pcp_formula_versao(
  p_formula_versao_id bigint,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_formula record;
  v_ativacao_id bigint;
begin
  perform public.require_current_user_permission('pcp.formula.change');
  if p_formula_versao_id is null or p_formula_versao_id <= 0 then
    raise exception 'formula_versao_id is required';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;

  select *
    into v_formula
    from public.pcp_formula_versoes
    where id = p_formula_versao_id;

  if not found then
    raise exception 'formula version not found';
  end if;

  v_actor := public.current_actor_id();

  insert into public.pcp_formula_ativacoes(
    formula_versao_id,
    produto_id,
    tipo_receita,
    motivo,
    created_by
  )
  values (
    p_formula_versao_id,
    v_formula.produto_id,
    v_formula.tipo_receita,
    trim(p_motivo),
    v_actor
  )
  returning id into v_ativacao_id;

  perform public.log_action(
    'pcp.formula_versao_activated',
    'pcp_formula_ativacoes',
    v_ativacao_id::text,
    'success',
    null,
    jsonb_build_object(
      'formula_versao_id', p_formula_versao_id,
      'produto_id', v_formula.produto_id,
      'tipo_receita', v_formula.tipo_receita,
      'motivo', trim(p_motivo)
    ),
    jsonb_build_object('source', 'activate_pcp_formula_versao')
  );

  return v_ativacao_id;
end;
$$;

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
declare
  v_actor uuid;
  v_formula record;
  v_op_id bigint;
  v_codigo_op text;
  v_status text;
begin
  perform public.require_current_user_permission('pcp.op.create');
  if p_formula_versao_id is null or p_formula_versao_id <= 0 then
    raise exception 'formula_versao_id is required';
  end if;
  if p_tipo_op not in ('estoque', 'experimental', 'desenvolvimento', 'reprocessamento', 'mapa_documental') then
    raise exception 'invalid tipo_op';
  end if;
  if p_quantidade_planejada is not null and p_quantidade_planejada <= 0 then
    raise exception 'quantidade_planejada must be greater than zero';
  end if;

  select *
    into v_formula
    from public.pcp_formula_versoes
    where id = p_formula_versao_id;

  if not found then
    raise exception 'formula version not found';
  end if;

  if p_tipo_op = 'mapa_documental' and v_formula.tipo_receita <> 'mapa' then
    raise exception 'MAPA documental OP requires MAPA recipe';
  end if;
  if p_tipo_op <> 'mapa_documental' and v_formula.tipo_receita <> 'producao' then
    raise exception 'operational OP requires production recipe';
  end if;

  v_actor := public.current_actor_id();
  v_codigo_op := public.next_pcp_codigo_op();
  v_status := case when p_tipo_op = 'mapa_documental' then 'completed' else 'draft' end;

  insert into public.pcp_ordens_producao(
    codigo_op,
    formula_versao_id,
    tipo_op,
    status,
    quantidade_planejada,
    observacao,
    created_by,
    updated_by,
    completed_at
  )
  values (
    v_codigo_op,
    p_formula_versao_id,
    p_tipo_op,
    v_status,
    p_quantidade_planejada,
    nullif(trim(p_observacao), ''),
    v_actor,
    v_actor,
    case when p_tipo_op = 'mapa_documental' then now() else null end
  )
  returning id into v_op_id;

  if p_tipo_op <> 'mapa_documental' then
    insert into public.pcp_op_componentes_planejados(
      op_id,
      formula_item_id,
      tipo_componente,
      materia_prima_id,
      produto_embalagem_id,
      produto_id,
      quantidade_planejada,
      unidade
    )
    select
      v_op_id,
      item.id,
      item.tipo_componente,
      item.materia_prima_id,
      item.produto_embalagem_id,
      item.produto_id,
      item.quantidade,
      item.unidade
    from public.pcp_formula_itens item
    where item.formula_versao_id = p_formula_versao_id;
  end if;

  perform public.log_action(
    'pcp.op_created',
    'pcp_ordens_producao',
    v_op_id::text,
    'success',
    null,
    jsonb_build_object(
      'codigo_op', v_codigo_op,
      'formula_versao_id', p_formula_versao_id,
      'tipo_op', p_tipo_op,
      'status', v_status
    ),
    jsonb_build_object('source', 'create_pcp_op')
  );

  return v_op_id;
end;
$$;

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
  v_op record;
  v_lote record;
  v_reserva_existente record;
  v_reserva_id bigint;
  v_quantidade_reservada numeric;
  v_total_outros numeric;
  v_saldo_disponivel numeric;
  v_tem_reserva_existente boolean := false;
begin
  perform public.require_current_user_permission('pcp.op.reserve_components');
  if p_op_componente_id is null or p_op_componente_id <= 0 then
    raise exception 'op_componente_id is required';
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
    update public.pcp_op_reservas_componentes
       set quantidade_reservada = v_quantidade_reservada,
           updated_by = v_actor
     where id = v_reserva_existente.id
     returning id into v_reserva_id;
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
      v_actor,
      v_actor
    )
    returning id into v_reserva_id;
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
      'quantidade_reservada', v_quantidade_reservada
    ),
    jsonb_build_object('source', 'reservar_pcp_op_componente')
  );

  return v_reserva_id;
end;
$$;

create or replace function public.iniciar_pcp_op(
  p_op_id bigint,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_op record;
begin
  perform public.require_current_user_permission('pcp.op.start');
  if p_op_id is null or p_op_id <= 0 then
    raise exception 'op_id is required';
  end if;

  select *
    into v_op
    from public.pcp_ordens_producao
    where id = p_op_id
    for update;

  if not found then
    raise exception 'OP not found';
  end if;
  if v_op.tipo_op = 'mapa_documental' then
    raise exception 'MAPA documental OP does not start production';
  end if;
  if v_op.status not in ('draft', 'planned') then
    raise exception 'OP status does not allow start';
  end if;
  if exists (
    select 1
    from public.pcp_op_componentes_planejados comp
    where comp.op_id = p_op_id
      and coalesce((
        select sum(reserva.quantidade_reservada)
        from public.pcp_op_reservas_componentes reserva
        where reserva.op_componente_id = comp.id
          and reserva.status = 'ativa'
      ), 0) < comp.quantidade_planejada
  ) then
    raise exception 'OP has components without full active reservation';
  end if;

  v_actor := public.current_actor_id();

  update public.pcp_ordens_producao
     set status = 'in_process',
         started_at = coalesce(started_at, now()),
         observacao = coalesce(nullif(trim(p_observacao), ''), observacao),
         updated_by = v_actor
   where id = p_op_id;

  perform public.log_action(
    'pcp.op_started',
    'pcp_ordens_producao',
    p_op_id::text,
    'success',
    jsonb_build_object('status', v_op.status),
    jsonb_build_object('status', 'in_process', 'observacao', nullif(trim(p_observacao), '')),
    jsonb_build_object('source', 'iniciar_pcp_op')
  );

  return p_op_id;
end;
$$;

create or replace function public.finalizar_pcp_op(
  p_op_id bigint,
  p_outputs_jsonb jsonb,
  p_cq_status text,
  p_ph numeric,
  p_densidade_kg_l numeric,
  p_volume_l numeric,
  p_massa_kg numeric,
  p_temperatura_c numeric,
  p_separador_mp text,
  p_conferente_mp text,
  p_formuladores_jsonb jsonb,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_op record;
  v_reserva record;
  v_output jsonb;
  v_tipo_produto text;
  v_quantidade numeric;
  v_status_lote text;
  v_codigo_lote text;
  v_lote_pa_id bigint;
  v_lote_pi_id bigint;
  v_tipo_entrada text;
begin
  perform public.require_current_user_permission('pcp.op.finish');
  perform public.require_current_user_permission('pcp.cq.record');
  if p_op_id is null or p_op_id <= 0 then
    raise exception 'op_id is required';
  end if;
  if p_outputs_jsonb is null or jsonb_typeof(p_outputs_jsonb) <> 'array' or jsonb_array_length(p_outputs_jsonb) = 0 then
    raise exception 'outputs_jsonb must be a non-empty array';
  end if;
  if p_cq_status not in ('aprovado', 'bloqueado', 'reprovado') then
    raise exception 'invalid cq_status';
  end if;
  if p_ph is null or p_ph < 0 then
    raise exception 'ph is required';
  end if;
  if p_densidade_kg_l is null or p_densidade_kg_l <= 0 then
    raise exception 'densidade_kg_l is required';
  end if;
  if p_volume_l is null or p_volume_l <= 0 then
    raise exception 'volume_l is required';
  end if;
  if p_massa_kg is null or p_massa_kg <= 0 then
    raise exception 'massa_kg is required';
  end if;
  if p_temperatura_c is null then
    raise exception 'temperatura_c is required';
  end if;
  if nullif(trim(p_separador_mp), '') is null then
    raise exception 'separador_mp is required';
  end if;
  if nullif(trim(p_conferente_mp), '') is null then
    raise exception 'conferente_mp is required';
  end if;
  if p_formuladores_jsonb is null or jsonb_typeof(p_formuladores_jsonb) <> 'array' or jsonb_array_length(p_formuladores_jsonb) = 0 then
    raise exception 'formuladores_jsonb must be a non-empty array';
  end if;

  select *
    into v_op
    from public.pcp_ordens_producao
    where id = p_op_id
    for update;

  if not found then
    raise exception 'OP not found';
  end if;
  if v_op.tipo_op = 'mapa_documental' then
    raise exception 'MAPA documental OP does not finish stock production';
  end if;
  if v_op.status not in ('planned', 'in_process') then
    raise exception 'OP status does not allow finish';
  end if;
  if exists (select 1 from public.pcp_op_cq_resultados where op_id = p_op_id) then
    raise exception 'OP already has CQ result';
  end if;
  if exists (
    select 1
    from public.pcp_op_componentes_planejados comp
    where comp.op_id = p_op_id
      and coalesce((
        select sum(reserva.quantidade_reservada)
        from public.pcp_op_reservas_componentes reserva
        where reserva.op_componente_id = comp.id
          and reserva.status = 'ativa'
      ), 0) <> comp.quantidade_planejada
  ) then
    raise exception 'OP active reservations must match planned component quantities before finish';
  end if;

  v_actor := public.current_actor_id();
  v_status_lote := case
    when v_op.tipo_op in ('experimental', 'desenvolvimento') or p_cq_status <> 'aprovado' then 'bloqueado'
    else 'disponivel'
  end;
  v_tipo_entrada := case
    when v_op.tipo_op = 'reprocessamento' then 'transformacao_entrada'
    else 'entrada_producao'
  end;

  insert into public.pcp_op_cq_resultados(
    op_id,
    cq_status,
    ph,
    densidade_kg_l,
    volume_l,
    massa_kg,
    temperatura_c,
    separador_mp,
    conferente_mp,
    formuladores_json,
    observacao,
    created_by
  )
  values (
    p_op_id,
    p_cq_status,
    p_ph,
    p_densidade_kg_l,
    p_volume_l,
    p_massa_kg,
    p_temperatura_c,
    trim(p_separador_mp),
    trim(p_conferente_mp),
    p_formuladores_jsonb,
    nullif(trim(p_observacao), ''),
    v_actor
  );

  for v_reserva in
    select reserva.*, comp.materia_prima_id, comp.produto_embalagem_id, comp.produto_id
      from public.pcp_op_reservas_componentes reserva
      join public.pcp_op_componentes_planejados comp on comp.id = reserva.op_componente_id
      where reserva.op_id = p_op_id
        and reserva.status = 'ativa'
      for update of reserva
  loop
    if v_reserva.tipo_componente = 'MP' then
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
        v_reserva.lote_mp_id,
        v_reserva.materia_prima_id,
        'consumo_op',
        -1 * v_reserva.quantidade_reservada,
        'pcp',
        'pcp_ordens_producao',
        p_op_id::text,
        nullif(trim(p_observacao), ''),
        v_actor
      );
      perform public.sync_est_lote_mp_status(v_reserva.lote_mp_id);
    elsif v_reserva.tipo_componente = 'PA' then
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
        v_reserva.lote_pa_id,
        v_reserva.produto_embalagem_id,
        'consumo_op',
        -1 * v_reserva.quantidade_reservada,
        'pcp',
        'pcp_ordens_producao',
        p_op_id::text,
        nullif(trim(p_observacao), ''),
        v_actor
      );
      perform public.sync_est_lote_pa_status(v_reserva.lote_pa_id);
    else
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
        v_reserva.lote_pi_id,
        v_reserva.produto_id,
        'consumo_op',
        -1 * v_reserva.quantidade_reservada,
        'pcp',
        'pcp_ordens_producao',
        p_op_id::text,
        nullif(trim(p_observacao), ''),
        v_actor
      );
      perform public.sync_est_lote_pi_status(v_reserva.lote_pi_id);
    end if;

    insert into public.pcp_op_consumos_componentes(
      op_id,
      op_componente_id,
      reserva_id,
      tipo_componente,
      lote_mp_id,
      lote_pa_id,
      lote_pi_id,
      quantidade_consumida,
      created_by
    )
    values (
      p_op_id,
      v_reserva.op_componente_id,
      v_reserva.id,
      v_reserva.tipo_componente,
      v_reserva.lote_mp_id,
      v_reserva.lote_pa_id,
      v_reserva.lote_pi_id,
      v_reserva.quantidade_reservada,
      v_actor
    );

    update public.pcp_op_reservas_componentes
       set status = 'baixada',
           updated_by = v_actor
     where id = v_reserva.id;

    update public.pcp_op_componentes_planejados
       set status = 'consumed'
     where id = v_reserva.op_componente_id;
  end loop;

  for v_output in
    select value from jsonb_array_elements(p_outputs_jsonb)
  loop
    v_tipo_produto := upper(nullif(trim(v_output->>'tipo_produto'), ''));
    if v_tipo_produto not in ('PA', 'PI') then
      raise exception 'invalid generated product type';
    end if;
    if nullif(trim(v_output->>'quantidade'), '') is null then
      raise exception 'generated product quantity is required';
    end if;
    v_quantidade := (v_output->>'quantidade')::numeric;
    if v_quantidade <= 0 then
      raise exception 'generated product quantity must be greater than zero';
    end if;

    if v_tipo_produto = 'PA' then
      if nullif(trim(v_output->>'produto_embalagem_id'), '') is null then
        raise exception 'PA output requires produto_embalagem_id';
      end if;
      v_codigo_lote := public.next_est_codigo_lote('PA');
      insert into public.est_lotes_pa(
        produto_embalagem_id,
        codigo_lote,
        status,
        data_fabricacao,
        origem_ref,
        observacao,
        created_by,
        updated_by
      )
      values (
        (v_output->>'produto_embalagem_id')::bigint,
        v_codigo_lote,
        v_status_lote,
        current_date,
        v_op.codigo_op,
        nullif(trim(v_output->>'observacao'), ''),
        v_actor,
        v_actor
      )
      returning id into v_lote_pa_id;

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
        v_lote_pa_id,
        (v_output->>'produto_embalagem_id')::bigint,
        v_tipo_entrada,
        v_quantidade,
        'pcp',
        'pcp_ordens_producao',
        p_op_id::text,
        nullif(trim(v_output->>'observacao'), ''),
        v_actor
      );

      if v_status_lote <> 'bloqueado' then
        perform public.sync_est_lote_pa_status(v_lote_pa_id);
      end if;

      insert into public.pcp_op_produtos_gerados(
        op_id,
        tipo_produto,
        produto_embalagem_id,
        lote_pa_id,
        quantidade,
        status_lote,
        observacao,
        created_by
      )
      values (
        p_op_id,
        'PA',
        (v_output->>'produto_embalagem_id')::bigint,
        v_lote_pa_id,
        v_quantidade,
        v_status_lote,
        nullif(trim(v_output->>'observacao'), ''),
        v_actor
      );
    else
      if nullif(trim(v_output->>'produto_id'), '') is null then
        raise exception 'PI output requires produto_id';
      end if;
      v_codigo_lote := public.next_est_codigo_lote('PI');
      insert into public.est_lotes_pi(
        produto_id,
        codigo_lote,
        status,
        data_fabricacao,
        origem_ref,
        observacao,
        created_by,
        updated_by
      )
      values (
        (v_output->>'produto_id')::bigint,
        v_codigo_lote,
        v_status_lote,
        current_date,
        v_op.codigo_op,
        nullif(trim(v_output->>'observacao'), ''),
        v_actor,
        v_actor
      )
      returning id into v_lote_pi_id;

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
        v_lote_pi_id,
        (v_output->>'produto_id')::bigint,
        v_tipo_entrada,
        v_quantidade,
        'pcp',
        'pcp_ordens_producao',
        p_op_id::text,
        nullif(trim(v_output->>'observacao'), ''),
        v_actor
      );

      if v_status_lote <> 'bloqueado' then
        perform public.sync_est_lote_pi_status(v_lote_pi_id);
      end if;

      insert into public.pcp_op_produtos_gerados(
        op_id,
        tipo_produto,
        produto_id,
        lote_pi_id,
        quantidade,
        status_lote,
        observacao,
        created_by
      )
      values (
        p_op_id,
        'PI',
        (v_output->>'produto_id')::bigint,
        v_lote_pi_id,
        v_quantidade,
        v_status_lote,
        nullif(trim(v_output->>'observacao'), ''),
        v_actor
      );
    end if;
  end loop;

  update public.pcp_ordens_producao
     set status = 'completed',
         cq_status = p_cq_status,
         completed_at = now(),
         updated_by = v_actor,
         observacao = coalesce(nullif(trim(p_observacao), ''), observacao)
   where id = p_op_id;

  perform public.log_action(
    'pcp.op_finished',
    'pcp_ordens_producao',
    p_op_id::text,
    'success',
    jsonb_build_object('status', v_op.status),
    jsonb_build_object(
      'status', 'completed',
      'cq_status', p_cq_status,
      'status_lote', v_status_lote,
      'outputs', jsonb_array_length(p_outputs_jsonb)
    ),
    jsonb_build_object('source', 'finalizar_pcp_op')
  );

  return p_op_id;
end;
$$;

create or replace function public.cancelar_pcp_op(
  p_op_id bigint,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_op record;
begin
  perform public.require_current_user_permission('pcp.op.cancel');
  if p_op_id is null or p_op_id <= 0 then
    raise exception 'op_id is required';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;

  select *
    into v_op
    from public.pcp_ordens_producao
    where id = p_op_id
    for update;

  if not found then
    raise exception 'OP not found';
  end if;
  if v_op.status not in ('draft', 'planned') then
    raise exception 'OP status does not allow cancellation';
  end if;

  v_actor := public.current_actor_id();

  update public.pcp_op_reservas_componentes
     set status = 'liberada',
         motivo_liberacao = trim(p_motivo),
         updated_by = v_actor
   where op_id = p_op_id
     and status = 'ativa';

  update public.pcp_op_componentes_planejados
     set status = 'cancelled'
   where op_id = p_op_id
     and status in ('pending', 'reserved');

  update public.pcp_ordens_producao
     set status = 'cancelled',
         cancelled_at = now(),
         updated_by = v_actor,
         observacao = concat_ws(' | ', observacao, concat('cancelado: ', trim(p_motivo)))
   where id = p_op_id;

  perform public.log_action(
    'pcp.op_cancelled',
    'pcp_ordens_producao',
    p_op_id::text,
    'success',
    jsonb_build_object('status', v_op.status),
    jsonb_build_object('status', 'cancelled', 'motivo', trim(p_motivo)),
    jsonb_build_object('source', 'cancelar_pcp_op')
  );

  return p_op_id;
end;
$$;

create or replace function public.liberar_pcp_lote_bloqueado(
  p_tipo_lote text,
  p_lote_id bigint,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
begin
  perform public.require_current_user_permission('pcp.experimental.release');
  if p_tipo_lote not in ('PA', 'PI') then
    raise exception 'tipo_lote must be PA or PI';
  end if;
  if p_lote_id is null or p_lote_id <= 0 then
    raise exception 'lote_id is required';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;

  v_actor := public.current_actor_id();

  if p_tipo_lote = 'PA' then
    update public.est_lotes_pa
       set status = 'disponivel',
           updated_by = v_actor,
           observacao = concat_ws(' | ', observacao, concat('liberado: ', trim(p_motivo)))
     where id = p_lote_id
       and status = 'bloqueado';
  else
    update public.est_lotes_pi
       set status = 'disponivel',
           updated_by = v_actor,
           observacao = concat_ws(' | ', observacao, concat('liberado: ', trim(p_motivo)))
     where id = p_lote_id
       and status = 'bloqueado';
  end if;

  if not found then
    raise exception 'blocked lot not found';
  end if;

  perform public.log_action(
    'pcp.lote_bloqueado_liberado',
    case when p_tipo_lote = 'PA' then 'est_lotes_pa' else 'est_lotes_pi' end,
    p_lote_id::text,
    'success',
    jsonb_build_object('status', 'bloqueado'),
    jsonb_build_object('status', 'disponivel', 'motivo', trim(p_motivo)),
    jsonb_build_object('source', 'liberar_pcp_lote_bloqueado')
  );

  return p_lote_id;
end;
$$;

create or replace function public.registrar_est_reserva_pa(
  p_romaneio_item_id bigint,
  p_lote_pa_id bigint,
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
  v_romaneio_item record;
  v_lote record;
  v_reserva_existente record;
  v_quantidade_reservada numeric;
  v_saldo_disponivel numeric;
  v_total_outros numeric;
  v_total_ativo numeric;
  v_reserva_id bigint;
  v_tem_reserva_existente boolean := false;
begin
  perform public.require_current_user_permission('estoque.pa.reserve');
  if p_romaneio_item_id is null or p_romaneio_item_id <= 0 then
    raise exception 'romaneio_item_id is required';
  end if;
  if p_lote_pa_id is null or p_lote_pa_id <= 0 then
    raise exception 'lote_pa_id is required';
  end if;

  select
      rom_item.id,
      rom_item.romaneio_id,
      rom_item.pedido_id,
      rom_item.pedido_item_id,
      rom_item.produto_embalagem_id,
      rom_item.quantidade_romaneada,
      rom_item.status as item_status,
      rom.status as romaneio_status,
      pedido.status as pedido_status
    into v_romaneio_item
    from public.exp_romaneio_itens rom_item
    join public.exp_romaneios rom on rom.id = rom_item.romaneio_id
    join public.com_pedidos pedido on pedido.id = rom_item.pedido_id
    where rom_item.id = p_romaneio_item_id
    for update of rom_item, rom;

  if not found then
    raise exception 'romaneio item not found';
  end if;
  if v_romaneio_item.pedido_status <> 'open' then
    raise exception 'pedido status does not allow PA reservation';
  end if;
  if v_romaneio_item.romaneio_status not in ('draft', 'separacao') then
    raise exception 'romaneio status does not allow PA reservation';
  end if;
  if v_romaneio_item.item_status not in ('draft', 'reservado') then
    raise exception 'romaneio item status does not allow PA reservation';
  end if;

  v_quantidade_reservada := coalesce(p_quantidade_reservada, v_romaneio_item.quantidade_romaneada);
  if v_quantidade_reservada <= 0 then
    raise exception 'quantidade_reservada must be greater than zero';
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
  if v_lote.status <> 'disponivel' then
    raise exception 'PA lot status does not allow reservation';
  end if;
  if v_lote.produto_embalagem_id <> v_romaneio_item.produto_embalagem_id then
    raise exception 'PA lot product does not match romaneio item';
  end if;

  select *
    into v_reserva_existente
    from public.est_reservas_pa
    where romaneio_item_id = p_romaneio_item_id
      and lote_pa_id = p_lote_pa_id
      and status = 'ativa'
    for update;
  v_tem_reserva_existente := found;

  select coalesce(sum(quantidade_reservada), 0)
    into v_total_outros
    from public.est_reservas_pa
    where romaneio_item_id = p_romaneio_item_id
      and status = 'ativa'
      and (
        not v_tem_reserva_existente
        or id <> v_reserva_existente.id
      );

  if v_total_outros + v_quantidade_reservada > v_romaneio_item.quantidade_romaneada then
    raise exception 'PA reservations exceed romaneio item quantity';
  end if;

  v_saldo_disponivel := coalesce(v_lote.saldo_disponivel, 0);
  if v_tem_reserva_existente then
    v_saldo_disponivel := v_saldo_disponivel + v_reserva_existente.quantidade_reservada;
  end if;

  if v_saldo_disponivel < v_quantidade_reservada then
    raise exception 'insufficient PA available balance for reservation';
  end if;

  v_actor := public.current_actor_id();

  if v_tem_reserva_existente then
    update public.est_reservas_pa
       set quantidade_reservada = v_quantidade_reservada,
           updated_by = v_actor
     where id = v_reserva_existente.id
     returning id into v_reserva_id;
  else
    insert into public.est_reservas_pa(
      lote_pa_id,
      romaneio_id,
      romaneio_item_id,
      produto_embalagem_id,
      quantidade_reservada,
      status,
      created_by,
      updated_by
    )
    values (
      p_lote_pa_id,
      v_romaneio_item.romaneio_id,
      p_romaneio_item_id,
      v_romaneio_item.produto_embalagem_id,
      v_quantidade_reservada,
      'ativa',
      v_actor,
      v_actor
    )
    returning id into v_reserva_id;
  end if;

  select coalesce(sum(quantidade_reservada), 0)
    into v_total_ativo
    from public.est_reservas_pa
    where romaneio_item_id = p_romaneio_item_id
      and status = 'ativa';

  update public.exp_romaneio_itens
     set lote_pa_id = case
           when (select count(*) from public.est_reservas_pa where romaneio_item_id = p_romaneio_item_id and status = 'ativa') = 1
             then p_lote_pa_id
           else null
         end,
         lote_pa_ref = case
           when (select count(*) from public.est_reservas_pa where romaneio_item_id = p_romaneio_item_id and status = 'ativa') = 1
             then v_lote.codigo_lote
           else 'MULTILOTE'
         end,
         quantidade_reservada = v_total_ativo,
         status = 'reservado',
         updated_by = v_actor
   where id = p_romaneio_item_id;

  update public.exp_romaneios
     set status = 'separacao',
         updated_by = v_actor,
         observacao = coalesce(nullif(trim(p_observacao), ''), observacao)
   where id = v_romaneio_item.romaneio_id
     and status = 'draft';

  perform public.log_action(
    'estoque.pa_reserva_registrada',
    'est_reservas_pa',
    v_reserva_id::text,
    'success',
    null,
    jsonb_build_object(
      'romaneio_id', v_romaneio_item.romaneio_id,
      'romaneio_item_id', p_romaneio_item_id,
      'lote_pa_id', p_lote_pa_id,
      'codigo_lote', v_lote.codigo_lote,
      'quantidade_reservada', v_quantidade_reservada,
      'quantidade_reservada_total_item', v_total_ativo
    ),
    jsonb_build_object('source', 'registrar_est_reserva_pa_multilote')
  );

  return v_reserva_id;
end;
$$;

create or replace function public.confirmar_exp_romaneio(
  p_romaneio_id bigint,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_pedido_id bigint;
  v_status_anterior text;
  v_pedido_status text;
  v_item record;
  v_reserva record;
  v_total_reservado numeric;
  v_saldo_fisico numeric;
  v_quantidade_confirmada_outros numeric;
begin
  perform public.require_current_user_permission('romaneios.confirm');
  if p_romaneio_id is null or p_romaneio_id <= 0 then
    raise exception 'romaneio_id is required';
  end if;

  select pedido_id, status
    into v_pedido_id, v_status_anterior
    from public.exp_romaneios
    where id = p_romaneio_id
    for update;

  if v_pedido_id is null then
    raise exception 'romaneio not found';
  end if;
  if v_status_anterior not in ('draft', 'separacao') then
    raise exception 'romaneio status does not allow confirmation';
  end if;

  select status
    into v_pedido_status
    from public.com_pedidos
    where id = v_pedido_id
    for update;

  if v_pedido_status <> 'open' then
    raise exception 'pedido status does not allow romaneio confirmation';
  end if;

  if not exists (
    select 1 from public.exp_romaneio_itens
    where romaneio_id = p_romaneio_id
      and status in ('draft', 'reservado')
  ) then
    raise exception 'romaneio has no active items';
  end if;

  v_actor := public.current_actor_id();

  for v_item in
    select
      rom_item.id,
      rom_item.pedido_id,
      rom_item.pedido_item_id,
      rom_item.produto_embalagem_id,
      rom_item.quantidade_romaneada,
      pedido_item.quantidade as quantidade_pedido,
      pedido_item.status as pedido_item_status
    from public.exp_romaneio_itens rom_item
    join public.com_pedido_itens pedido_item on pedido_item.id = rom_item.pedido_item_id
    where rom_item.romaneio_id = p_romaneio_id
      and rom_item.status in ('draft', 'reservado')
    for update of rom_item
  loop
    if v_item.pedido_item_status <> 'active' then
      raise exception 'pedido item status does not allow romaneio confirmation';
    end if;

    select coalesce(sum(quantidade_reservada), 0)
      into v_total_reservado
      from public.est_reservas_pa
      where romaneio_item_id = v_item.id
        and status = 'ativa';

    if v_total_reservado <> v_item.quantidade_romaneada then
      raise exception 'active PA reservations must match romaneio item quantity';
    end if;

    select coalesce(sum(outro_item.quantidade_romaneada), 0)
      into v_quantidade_confirmada_outros
      from public.exp_romaneio_itens outro_item
      join public.exp_romaneios outro_rom on outro_rom.id = outro_item.romaneio_id
      where outro_item.pedido_item_id = v_item.pedido_item_id
        and outro_rom.id <> p_romaneio_id
        and outro_rom.status = 'confirmado'
        and outro_item.status = 'confirmado';

    if v_quantidade_confirmada_outros + v_item.quantidade_romaneada > v_item.quantidade_pedido then
      raise exception 'romaneio confirmation exceeds pending order quantity';
    end if;

    for v_reserva in
      select
          reserva.id,
          reserva.lote_pa_id,
          reserva.quantidade_reservada,
          lote.codigo_lote,
          lote.produto_embalagem_id,
          lote.status as lote_status
        from public.est_reservas_pa reserva
        join public.est_lotes_pa lote on lote.id = reserva.lote_pa_id
        where reserva.romaneio_item_id = v_item.id
          and reserva.status = 'ativa'
        for update of reserva, lote
    loop
      if v_reserva.produto_embalagem_id <> v_item.produto_embalagem_id then
        raise exception 'PA reservation product does not match romaneio item';
      end if;
      if v_reserva.lote_status not in ('disponivel', 'esgotado') then
        raise exception 'PA lot status does not allow confirmation';
      end if;

      select saldo_fisico
        into v_saldo_fisico
        from public.est_lotes_pa_saldos
        where lote_pa_id = v_reserva.lote_pa_id;

      if coalesce(v_saldo_fisico, 0) < v_reserva.quantidade_reservada then
        raise exception 'PA physical balance is lower than reservation';
      end if;

      insert into public.exp_romaneio_movimentos_pa(
        romaneio_id,
        romaneio_item_id,
        pedido_id,
        pedido_item_id,
        produto_embalagem_id,
        lote_pa_ref,
        lote_pa_id,
        tipo_movimento,
        quantidade,
        observacao,
        created_by
      )
      values (
        p_romaneio_id,
        v_item.id,
        v_item.pedido_id,
        v_item.pedido_item_id,
        v_item.produto_embalagem_id,
        v_reserva.codigo_lote,
        v_reserva.lote_pa_id,
        'baixa',
        v_reserva.quantidade_reservada,
        nullif(trim(p_observacao), ''),
        v_actor
      );

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
        v_reserva.lote_pa_id,
        v_item.produto_embalagem_id,
        'saida_romaneio',
        -1 * v_reserva.quantidade_reservada,
        'romaneio',
        'exp_romaneios',
        p_romaneio_id::text,
        nullif(trim(p_observacao), ''),
        v_actor
      );

      update public.est_reservas_pa
         set status = 'baixada',
             updated_by = v_actor
       where id = v_reserva.id;

      perform public.sync_est_lote_pa_status(v_reserva.lote_pa_id);
    end loop;
  end loop;

  update public.exp_romaneio_itens
     set status = 'confirmado',
         quantidade_reservada = 0,
         updated_by = v_actor
   where romaneio_id = p_romaneio_id
     and status in ('draft', 'reservado');

  update public.exp_romaneios
     set status = 'confirmado',
         confirmado_at = now(),
         updated_by = v_actor,
         observacao = coalesce(nullif(trim(p_observacao), ''), observacao)
   where id = p_romaneio_id;

  if not exists (
    select 1
      from public.com_pedido_itens pedido_item
      left join (
        select rom_item.pedido_item_id, sum(rom_item.quantidade_romaneada) as quantidade_confirmada
          from public.exp_romaneio_itens rom_item
          join public.exp_romaneios rom on rom.id = rom_item.romaneio_id
          where rom.pedido_id = v_pedido_id
            and rom.status = 'confirmado'
            and rom_item.status = 'confirmado'
          group by rom_item.pedido_item_id
      ) confirmado on confirmado.pedido_item_id = pedido_item.id
      where pedido_item.pedido_id = v_pedido_id
        and pedido_item.status = 'active'
        and coalesce(confirmado.quantidade_confirmada, 0) < pedido_item.quantidade
  ) then
    update public.com_pedidos
       set status = 'fulfilled',
           updated_by = v_actor
     where id = v_pedido_id
       and status = 'open';
  end if;

  perform public.log_action(
    'expedicao.romaneio_confirmado',
    'exp_romaneios',
    p_romaneio_id::text,
    'success',
    jsonb_build_object('status', v_status_anterior),
    jsonb_build_object(
      'status', 'confirmado',
      'pedido_id', v_pedido_id,
      'observacao', nullif(trim(p_observacao), ''),
      'estoque_pa_integrado', true,
      'multilote', true
    ),
    jsonb_build_object('source', 'confirmar_exp_romaneio_multilote')
  );

  return p_romaneio_id;
end;
$$;

revoke all on function public.current_actor_id() from public;
revoke all on function public.can_current_user(text) from public;
revoke all on function public.require_current_user_permission(text) from public;
revoke all on function public.next_est_codigo_lote(text) from public;
revoke all on function public.next_pcp_codigo_op() from public;
revoke all on function public.prevent_est_movimentos_mp_changes() from public;
revoke all on function public.prevent_est_movimentos_pi_changes() from public;
revoke all on function public.prevent_pcp_formula_changes() from public;
revoke all on function public.sync_est_lote_mp_status(bigint) from public;
revoke all on function public.sync_est_lote_pi_status(bigint) from public;

revoke all on function public.create_est_lote_pa_auto(bigint, numeric, text, text, date, date, text, text) from public;
grant execute on function public.create_est_lote_pa_auto(bigint, numeric, text, text, date, date, text, text) to authenticated;

revoke all on function public.create_est_lote_mp(bigint, numeric, text, text, text, date, date, text, text) from public;
grant execute on function public.create_est_lote_mp(bigint, numeric, text, text, text, date, date, text, text) to authenticated;

revoke all on function public.create_est_lote_pi(bigint, numeric, text, text, text, date, date, text, text) from public;
grant execute on function public.create_est_lote_pi(bigint, numeric, text, text, text, date, date, text, text) to authenticated;

revoke all on function public.create_pcp_formula_versao(bigint, text, text, jsonb, text) from public;
grant execute on function public.create_pcp_formula_versao(bigint, text, text, jsonb, text) to authenticated;

revoke all on function public.activate_pcp_formula_versao(bigint, text) from public;
grant execute on function public.activate_pcp_formula_versao(bigint, text) to authenticated;

revoke all on function public.create_pcp_op(bigint, text, numeric, text) from public;
grant execute on function public.create_pcp_op(bigint, text, numeric, text) to authenticated;

revoke all on function public.reservar_pcp_op_componente(bigint, bigint, bigint, bigint, numeric, text) from public;
grant execute on function public.reservar_pcp_op_componente(bigint, bigint, bigint, bigint, numeric, text) to authenticated;

revoke all on function public.iniciar_pcp_op(bigint, text) from public;
grant execute on function public.iniciar_pcp_op(bigint, text) to authenticated;

revoke all on function public.finalizar_pcp_op(bigint, jsonb, text, numeric, numeric, numeric, numeric, numeric, text, text, jsonb, text) from public;
grant execute on function public.finalizar_pcp_op(bigint, jsonb, text, numeric, numeric, numeric, numeric, numeric, text, text, jsonb, text) to authenticated;

revoke all on function public.cancelar_pcp_op(bigint, text) from public;
grant execute on function public.cancelar_pcp_op(bigint, text) to authenticated;

revoke all on function public.liberar_pcp_lote_bloqueado(text, bigint, text) from public;
grant execute on function public.liberar_pcp_lote_bloqueado(text, bigint, text) to authenticated;

revoke all on function public.registrar_est_reserva_pa(bigint, bigint, numeric, text) from public;
grant execute on function public.registrar_est_reserva_pa(bigint, bigint, numeric, text) to authenticated;

revoke all on function public.confirmar_exp_romaneio(bigint, text) from public;
grant execute on function public.confirmar_exp_romaneio(bigint, text) to authenticated;
