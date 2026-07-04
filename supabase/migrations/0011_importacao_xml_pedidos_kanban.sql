alter table public.cad_pessoas_comerciais
  add column if not exists user_profile_id uuid references public.user_profiles(id);

create unique index if not exists idx_cad_pessoas_comerciais_user_profile
  on public.cad_pessoas_comerciais(user_profile_id)
  where user_profile_id is not null;

create table if not exists public.cad_areas_comerciais (
  id bigint generated always as identity primary key,
  nome text not null,
  nome_norm text not null unique,
  status text not null default 'active',
  gerente_id bigint references public.cad_pessoas_comerciais(id),
  observacao text,
  created_by uuid references public.user_profiles(id),
  updated_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cad_areas_comerciais_status_check check (status in ('active', 'inactive', 'pending_review'))
);

create table if not exists public.cad_pessoa_areas_comerciais (
  id bigint generated always as identity primary key,
  pessoa_id bigint not null references public.cad_pessoas_comerciais(id),
  area_id bigint not null references public.cad_areas_comerciais(id),
  papel_area text not null default 'vendedor',
  status text not null default 'active',
  vigencia_inicio date,
  vigencia_fim date,
  created_by uuid references public.user_profiles(id),
  updated_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cad_pessoa_areas_papel_check check (papel_area in ('vendedor', 'gerente', 'supervisor', 'apoio')),
  constraint cad_pessoa_areas_status_check check (status in ('active', 'inactive', 'pending_review')),
  constraint cad_pessoa_areas_vigencia_check check (
    vigencia_inicio is null
    or vigencia_fim is null
    or vigencia_fim >= vigencia_inicio
  ),
  constraint cad_pessoa_areas_key unique (pessoa_id, area_id, papel_area, vigencia_inicio)
);

alter table public.com_pedidos
  add column if not exists propriedade_id bigint references public.cad_cliente_propriedades(id),
  add column if not exists sequencia_propriedade integer,
  add column if not exists vendedor_gerador_id bigint references public.cad_pessoas_comerciais(id);

create unique index if not exists idx_cad_cliente_propriedades_id_cliente
  on public.cad_cliente_propriedades(id, cliente_id);

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'com_pedidos_propriedade_cliente_fk'
      and conrelid = 'public.com_pedidos'::regclass
  ) then
    alter table public.com_pedidos
      add constraint com_pedidos_propriedade_cliente_fk
      foreign key (propriedade_id, cliente_id)
      references public.cad_cliente_propriedades(id, cliente_id);
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'com_pedidos_sequencia_propriedade_check'
      and conrelid = 'public.com_pedidos'::regclass
  ) then
    alter table public.com_pedidos
      add constraint com_pedidos_sequencia_propriedade_check
      check (sequencia_propriedade is null or sequencia_propriedade > 0);
  end if;
end;
$$;

create unique index if not exists idx_com_pedidos_propriedade_sequencia
  on public.com_pedidos(propriedade_id, sequencia_propriedade)
  where propriedade_id is not null and sequencia_propriedade is not null;

create unique index if not exists idx_com_pedidos_cliente_sequencia_sem_propriedade
  on public.com_pedidos(cliente_id, sequencia_propriedade)
  where propriedade_id is null and sequencia_propriedade is not null;

create index if not exists idx_com_pedidos_vendedor_status
  on public.com_pedidos(vendedor_gerador_id, status, data_pedido desc);

create index if not exists idx_com_pedidos_propriedade_status
  on public.com_pedidos(propriedade_id, status, data_pedido desc);

create table if not exists public.com_pedido_sequencias_propriedade (
  id bigint generated always as identity primary key,
  cliente_id bigint not null references public.cad_clientes(id),
  propriedade_id bigint references public.cad_cliente_propriedades(id),
  proxima_sequencia integer not null default 1,
  created_by uuid references public.user_profiles(id),
  updated_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint com_pedido_sequencias_numero_check check (proxima_sequencia > 0)
);

create unique index if not exists idx_com_pedido_sequencias_cliente_prop_key
  on public.com_pedido_sequencias_propriedade(cliente_id, coalesce(propriedade_id, 0));

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'com_pedido_sequencias_propriedade_cliente_fk'
      and conrelid = 'public.com_pedido_sequencias_propriedade'::regclass
  ) then
    alter table public.com_pedido_sequencias_propriedade
      add constraint com_pedido_sequencias_propriedade_cliente_fk
      foreign key (propriedade_id, cliente_id)
      references public.cad_cliente_propriedades(id, cliente_id);
  end if;
end;
$$;

create table if not exists public.imp_nfe_xmls (
  id bigint generated always as identity primary key,
  chave_acesso text not null,
  chave_acesso_norm text not null unique,
  numero text,
  serie text,
  emitente_cnpj text,
  emitente_cnpj_norm text,
  emitente_nome text,
  data_emissao date,
  status text not null default 'importada',
  payload_resumo_json jsonb not null default '{}'::jsonb,
  created_by uuid references public.user_profiles(id),
  updated_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint imp_nfe_xmls_chave_check check (length(chave_acesso_norm) = 44),
  constraint imp_nfe_xmls_status_check check (status in ('importada', 'em_conferencia', 'conferida', 'lotes_gerados', 'cancelada'))
);

create table if not exists public.imp_nfe_xml_itens (
  id bigint generated always as identity primary key,
  nfe_id bigint not null references public.imp_nfe_xmls(id) on delete cascade,
  numero_item integer not null,
  codigo_fornecedor text,
  descricao_fornecedor text not null,
  descricao_norm text not null,
  ncm text,
  cfop text,
  unidade_xml text not null,
  quantidade_xml numeric not null,
  valor_total numeric not null default 0,
  lote_fornecedor text,
  data_fabricacao date,
  data_validade date,
  status text not null default 'pendente_match',
  materia_prima_sugerida_id bigint references public.cad_materias_primas(id),
  materia_prima_confirmada_id bigint references public.cad_materias_primas(id),
  unidade_destino text,
  fator_conversao numeric,
  quantidade_convertida numeric,
  payload_item_json jsonb not null default '{}'::jsonb,
  created_by uuid references public.user_profiles(id),
  updated_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint imp_nfe_xml_itens_key unique (nfe_id, numero_item),
  constraint imp_nfe_xml_itens_numero_check check (numero_item > 0),
  constraint imp_nfe_xml_itens_qtd_check check (quantidade_xml > 0),
  constraint imp_nfe_xml_itens_valor_check check (valor_total >= 0),
  constraint imp_nfe_xml_itens_fator_check check (fator_conversao is null or fator_conversao > 0),
  constraint imp_nfe_xml_itens_qtd_convertida_check check (quantidade_convertida is null or quantidade_convertida > 0),
  constraint imp_nfe_xml_itens_status_check check (status in ('pendente_match', 'match_sugerido', 'match_confirmado', 'ignorado', 'lote_gerado')),
  constraint imp_nfe_xml_itens_datas_check check (
    data_fabricacao is null
    or data_validade is null
    or data_validade >= data_fabricacao
  )
);

create table if not exists public.imp_nfe_item_match_candidatos (
  id bigint generated always as identity primary key,
  item_id bigint not null references public.imp_nfe_xml_itens(id) on delete cascade,
  materia_prima_id bigint not null references public.cad_materias_primas(id),
  score numeric not null,
  motivo text not null,
  status text not null default 'sugerido',
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint imp_nfe_item_match_candidatos_key unique (item_id, materia_prima_id),
  constraint imp_nfe_item_match_score_check check (score >= 0 and score <= 100),
  constraint imp_nfe_item_match_status_check check (status in ('sugerido', 'aceito', 'rejeitado'))
);

create table if not exists public.imp_nfe_item_resolucoes (
  id bigint generated always as identity primary key,
  item_id bigint not null references public.imp_nfe_xml_itens(id) on delete cascade,
  materia_prima_id bigint not null references public.cad_materias_primas(id),
  unidade_destino text not null,
  fator_conversao numeric not null,
  quantidade_convertida numeric not null,
  lote_fornecedor text,
  data_fabricacao date,
  data_validade date,
  motivo text not null,
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint imp_nfe_item_resolucoes_fator_check check (fator_conversao > 0),
  constraint imp_nfe_item_resolucoes_qtd_check check (quantidade_convertida > 0),
  constraint imp_nfe_item_resolucoes_motivo_check check (length(btrim(motivo)) > 0),
  constraint imp_nfe_item_resolucoes_datas_check check (
    data_fabricacao is null
    or data_validade is null
    or data_validade >= data_fabricacao
  )
);

create table if not exists public.imp_nfe_item_lotes_mp (
  id bigint generated always as identity primary key,
  item_id bigint not null unique references public.imp_nfe_xml_itens(id) on delete cascade,
  lote_mp_id bigint not null unique references public.est_lotes_mp(id),
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now()
);

create index if not exists idx_cad_areas_gerente_status
  on public.cad_areas_comerciais(gerente_id, status);
create index if not exists idx_cad_pessoa_areas_pessoa_status
  on public.cad_pessoa_areas_comerciais(pessoa_id, status);
create index if not exists idx_cad_pessoa_areas_area_status
  on public.cad_pessoa_areas_comerciais(area_id, status);
create index if not exists idx_imp_nfe_xmls_status_data
  on public.imp_nfe_xmls(status, data_emissao desc, id desc);
create index if not exists idx_imp_nfe_xml_itens_status
  on public.imp_nfe_xml_itens(status, nfe_id);
create index if not exists idx_imp_nfe_xml_itens_confirmada
  on public.imp_nfe_xml_itens(materia_prima_confirmada_id, status);
create index if not exists idx_imp_nfe_match_item_score
  on public.imp_nfe_item_match_candidatos(item_id, score desc);
create index if not exists idx_imp_nfe_resolucoes_item
  on public.imp_nfe_item_resolucoes(item_id, created_at desc);

drop trigger if exists trg_cad_areas_comerciais_updated_at on public.cad_areas_comerciais;
create trigger trg_cad_areas_comerciais_updated_at before update on public.cad_areas_comerciais
for each row execute function public.touch_updated_at();

drop trigger if exists trg_cad_pessoa_areas_comerciais_updated_at on public.cad_pessoa_areas_comerciais;
create trigger trg_cad_pessoa_areas_comerciais_updated_at before update on public.cad_pessoa_areas_comerciais
for each row execute function public.touch_updated_at();

drop trigger if exists trg_com_pedido_sequencias_updated_at on public.com_pedido_sequencias_propriedade;
create trigger trg_com_pedido_sequencias_updated_at before update on public.com_pedido_sequencias_propriedade
for each row execute function public.touch_updated_at();

drop trigger if exists trg_imp_nfe_xmls_updated_at on public.imp_nfe_xmls;
create trigger trg_imp_nfe_xmls_updated_at before update on public.imp_nfe_xmls
for each row execute function public.touch_updated_at();

drop trigger if exists trg_imp_nfe_xml_itens_updated_at on public.imp_nfe_xml_itens;
create trigger trg_imp_nfe_xml_itens_updated_at before update on public.imp_nfe_xml_itens
for each row execute function public.touch_updated_at();

create or replace function public.prevent_imp_nfe_append_only_changes()
returns trigger
language plpgsql
as $$
begin
  raise exception 'NFe import audit table is append-only';
end;
$$;

drop trigger if exists trg_imp_nfe_resolucoes_append_only on public.imp_nfe_item_resolucoes;
create trigger trg_imp_nfe_resolucoes_append_only
before update or delete on public.imp_nfe_item_resolucoes
for each row execute function public.prevent_imp_nfe_append_only_changes();

drop trigger if exists trg_imp_nfe_lotes_append_only on public.imp_nfe_item_lotes_mp;
create trigger trg_imp_nfe_lotes_append_only
before update or delete on public.imp_nfe_item_lotes_mp
for each row execute function public.prevent_imp_nfe_append_only_changes();

alter table public.cad_areas_comerciais enable row level security;
alter table public.cad_pessoa_areas_comerciais enable row level security;
alter table public.com_pedido_sequencias_propriedade enable row level security;
alter table public.imp_nfe_xmls enable row level security;
alter table public.imp_nfe_xml_itens enable row level security;
alter table public.imp_nfe_item_match_candidatos enable row level security;
alter table public.imp_nfe_item_resolucoes enable row level security;
alter table public.imp_nfe_item_lotes_mp enable row level security;

create policy "authenticated full commercial area access" on public.cad_areas_comerciais
for all to authenticated using (true) with check (true);
create policy "authenticated full commercial area membership access" on public.cad_pessoa_areas_comerciais
for all to authenticated using (true) with check (true);
create policy "authenticated full order sequence access" on public.com_pedido_sequencias_propriedade
for all to authenticated using (true) with check (true);
create policy "authenticated full NFe XML access" on public.imp_nfe_xmls
for all to authenticated using (true) with check (true);
create policy "authenticated full NFe XML item access" on public.imp_nfe_xml_itens
for all to authenticated using (true) with check (true);
create policy "authenticated full NFe match candidate access" on public.imp_nfe_item_match_candidatos
for all to authenticated using (true) with check (true);
create policy "authenticated full NFe resolution access" on public.imp_nfe_item_resolucoes
for all to authenticated using (true) with check (true);
create policy "authenticated full NFe MP lot link access" on public.imp_nfe_item_lotes_mp
for all to authenticated using (true) with check (true);

insert into public.permission_actions(action_key, module, description, default_allowed, sort_order)
values
  ('importacao.nfe_xml.stage', 'importacao', 'Importar cabecalho e itens de NF XML para conferencia', true, 180),
  ('importacao.nfe_xml.match', 'importacao', 'Confirmar MP, conversao e resolucao de item XML', true, 181),
  ('importacao.nfe_xml.generate_mp_lot', 'importacao', 'Gerar lote de MP a partir de item XML conferido', true, 182),
  ('importacao.nfe_xml.ignore_item', 'importacao', 'Ignorar item XML que nao deve gerar estoque de MP', true, 183),
  ('pedidos.kanban.view', 'pedidos', 'Ver pedidos em quadro Kanban por vendedor, gerente e area', true, 112),
  ('cadastros.areas.manage', 'cadastros', 'Criar e manter areas comerciais e vinculos vendedor-gerente', true, 63)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order;

create or replace function public.sync_imp_nfe_xml_status(p_nfe_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total integer;
  v_pendente integer;
  v_confirmado integer;
  v_lote_gerado integer;
  v_nfe_status text;
begin
  if p_nfe_id is null or p_nfe_id <= 0 then
    raise exception 'nfe_id is required';
  end if;

  select status
    into v_nfe_status
    from public.imp_nfe_xmls
    where id = p_nfe_id;

  if v_nfe_status is null then
    raise exception 'NFe XML not found';
  end if;
  if v_nfe_status = 'cancelada' then
    return;
  end if;

  select
      count(*)::integer,
      count(*) filter (where status in ('pendente_match', 'match_sugerido'))::integer,
      count(*) filter (where status = 'match_confirmado')::integer,
      count(*) filter (where status = 'lote_gerado')::integer
    into v_total, v_pendente, v_confirmado, v_lote_gerado
    from public.imp_nfe_xml_itens
    where nfe_id = p_nfe_id;

  update public.imp_nfe_xmls
     set status = case
         when v_total = 0 then 'importada'
         when v_pendente > 0 then 'em_conferencia'
         when v_confirmado > 0 then 'conferida'
         when v_lote_gerado > 0 then 'lotes_gerados'
         else 'conferida'
       end,
       updated_by = public.current_actor_id()
   where id = p_nfe_id;
end;
$$;

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
end;
$$;

create or replace function public.create_com_pedido_operacional(
  p_cliente_id bigint,
  p_produto_embalagem_id bigint,
  p_quantidade numeric,
  p_valor_unitario numeric,
  p_propriedade_id bigint default null,
  p_tipo_pedido text default 'venda',
  p_status text default 'draft',
  p_data_pedido date default current_date,
  p_vendedor_id bigint default null,
  p_percentual_comissao numeric default null,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_codigo_pedido text;
  v_pedido_id bigint;
  v_item_id bigint;
  v_item_valor_total numeric;
  v_valor_base_comissao numeric;
  v_valor_previsto_comissao numeric;
  v_sequencia integer;
  v_produto_embalagem_status text;
begin
  perform public.require_current_user_permission('pedidos.create');

  if p_cliente_id is null or p_cliente_id <= 0 then
    raise exception 'cliente_id is required';
  end if;
  if p_produto_embalagem_id is null or p_produto_embalagem_id <= 0 then
    raise exception 'produto_embalagem_id is required';
  end if;
  if p_quantidade is null or p_quantidade <= 0 then
    raise exception 'quantidade must be greater than zero';
  end if;
  if p_valor_unitario is null or p_valor_unitario < 0 then
    raise exception 'valor_unitario must be greater than or equal to zero';
  end if;
  if p_tipo_pedido not in ('venda', 'bonificacao', 'devolucao') then
    raise exception 'invalid tipo_pedido';
  end if;
  if p_status not in ('draft', 'open', 'blocked') then
    raise exception 'invalid initial status';
  end if;
  if p_percentual_comissao is not null and p_percentual_comissao < 0 then
    raise exception 'percentual_comissao must be greater than or equal to zero';
  end if;
  if p_data_pedido is null then
    raise exception 'data_pedido is required';
  end if;
  if not exists (select 1 from public.cad_clientes where id = p_cliente_id and status = 'active') then
    raise exception 'active cliente not found';
  end if;
  if p_propriedade_id is not null and not exists (
    select 1
    from public.cad_cliente_propriedades
    where id = p_propriedade_id
      and cliente_id = p_cliente_id
      and status = 'active'
  ) then
    raise exception 'active propriedade does not belong to cliente';
  end if;
  if p_vendedor_id is not null and not exists (
    select 1
    from public.cad_pessoas_comerciais
    where id = p_vendedor_id
      and status = 'active'
  ) then
    raise exception 'active vendedor not found';
  end if;

  select status
    into v_produto_embalagem_status
    from public.cad_produto_embalagens
    where id = p_produto_embalagem_id;

  if v_produto_embalagem_status is null then
    raise exception 'produto_embalagem not found';
  end if;
  if v_produto_embalagem_status <> 'active' then
    raise exception 'produto_embalagem status does not allow order creation';
  end if;

  v_actor := public.current_actor_id();
  v_sequencia := public.next_com_pedido_sequencia(p_cliente_id, p_propriedade_id);

  v_codigo_pedido := concat(
    'PED-',
    case
      when p_propriedade_id is null then concat('C', p_cliente_id::text)
      else concat('P', p_propriedade_id::text)
    end,
    '-',
    lpad(v_sequencia::text, 6, '0')
  );

  if p_tipo_pedido = 'bonificacao' then
    v_item_valor_total := 0;
  elsif p_tipo_pedido = 'devolucao' then
    v_item_valor_total := -1 * p_quantidade * p_valor_unitario;
  else
    v_item_valor_total := p_quantidade * p_valor_unitario;
  end if;

  insert into public.com_pedidos(
    codigo_pedido,
    cliente_id,
    propriedade_id,
    sequencia_propriedade,
    vendedor_gerador_id,
    tipo_pedido,
    status,
    data_pedido,
    origem_canal,
    valor_total,
    observacao,
    created_by,
    updated_by
  )
  values (
    v_codigo_pedido,
    p_cliente_id,
    p_propriedade_id,
    v_sequencia,
    p_vendedor_id,
    p_tipo_pedido,
    p_status,
    p_data_pedido,
    case when p_vendedor_id is null then 'interno' else 'vendedor' end,
    v_item_valor_total,
    nullif(trim(p_observacao), ''),
    v_actor,
    v_actor
  )
  returning id into v_pedido_id;

  insert into public.com_pedido_itens(
    pedido_id,
    produto_embalagem_id,
    tipo_item,
    quantidade,
    valor_unitario,
    valor_total,
    created_by,
    updated_by
  )
  values (
    v_pedido_id,
    p_produto_embalagem_id,
    p_tipo_pedido,
    p_quantidade,
    p_valor_unitario,
    v_item_valor_total,
    v_actor,
    v_actor
  )
  returning id into v_item_id;

  if p_vendedor_id is not null and p_percentual_comissao is not null and p_percentual_comissao > 0 and p_tipo_pedido <> 'bonificacao' then
    v_valor_base_comissao := v_item_valor_total;
    v_valor_previsto_comissao := v_valor_base_comissao * p_percentual_comissao / 100;

    insert into public.com_pedido_comissionados(
      pedido_id,
      pedido_item_id,
      pessoa_id,
      papel_comissao,
      percentual_comissao,
      valor_base,
      valor_previsto,
      created_by,
      updated_by
    )
    values (
      v_pedido_id,
      v_item_id,
      p_vendedor_id,
      'vendedor',
      p_percentual_comissao,
      v_valor_base_comissao,
      v_valor_previsto_comissao,
      v_actor,
      v_actor
    );
  end if;

  perform public.log_action(
    'comercial.pedido_operacional_created',
    'com_pedidos',
    v_pedido_id::text,
    'success',
    null,
    jsonb_build_object(
      'codigo_pedido', v_codigo_pedido,
      'cliente_id', p_cliente_id,
      'propriedade_id', p_propriedade_id,
      'sequencia_propriedade', v_sequencia,
      'produto_embalagem_id', p_produto_embalagem_id,
      'tipo_pedido', p_tipo_pedido,
      'status', p_status,
      'quantidade', p_quantidade,
      'valor_unitario', p_valor_unitario,
      'valor_total', v_item_valor_total,
      'vendedor_id', p_vendedor_id,
      'percentual_comissao', p_percentual_comissao
    ),
    jsonb_build_object('source', 'create_com_pedido_operacional')
  );

  return v_pedido_id;
end;
$$;

create or replace function public.stage_imp_nfe_xml(
  p_chave_acesso text,
  p_numero text default null,
  p_serie text default null,
  p_emitente_cnpj text default null,
  p_emitente_nome text default null,
  p_data_emissao date default null,
  p_payload_resumo_json jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_nfe_id bigint;
  v_chave_norm text;
  v_cnpj_norm text;
begin
  perform public.require_current_user_permission('importacao.nfe_xml.stage');

  v_chave_norm := regexp_replace(coalesce(p_chave_acesso, ''), '\D', '', 'g');
  if length(v_chave_norm) <> 44 then
    raise exception 'chave_acesso must have 44 digits';
  end if;

  v_cnpj_norm := nullif(regexp_replace(coalesce(p_emitente_cnpj, ''), '\D', '', 'g'), '');
  v_actor := public.current_actor_id();

  insert into public.imp_nfe_xmls(
    chave_acesso,
    chave_acesso_norm,
    numero,
    serie,
    emitente_cnpj,
    emitente_cnpj_norm,
    emitente_nome,
    data_emissao,
    status,
    payload_resumo_json,
    created_by,
    updated_by
  )
  values (
    trim(p_chave_acesso),
    v_chave_norm,
    nullif(trim(p_numero), ''),
    nullif(trim(p_serie), ''),
    nullif(trim(p_emitente_cnpj), ''),
    v_cnpj_norm,
    nullif(trim(p_emitente_nome), ''),
    p_data_emissao,
    'em_conferencia',
    coalesce(p_payload_resumo_json, '{}'::jsonb),
    v_actor,
    v_actor
  )
  on conflict (chave_acesso_norm) do update set
    numero = excluded.numero,
    serie = excluded.serie,
    emitente_cnpj = excluded.emitente_cnpj,
    emitente_cnpj_norm = excluded.emitente_cnpj_norm,
    emitente_nome = excluded.emitente_nome,
    data_emissao = excluded.data_emissao,
    status = case
      when public.imp_nfe_xmls.status = 'lotes_gerados' then public.imp_nfe_xmls.status
      when public.imp_nfe_xmls.status = 'cancelada' then public.imp_nfe_xmls.status
      else 'em_conferencia'
    end,
    payload_resumo_json = excluded.payload_resumo_json,
    updated_by = v_actor
  returning id into v_nfe_id;

  perform public.log_action(
    'importacao.nfe_xml_staged',
    'imp_nfe_xmls',
    v_nfe_id::text,
    'success',
    null,
    jsonb_build_object('chave_acesso_norm', v_chave_norm, 'numero', nullif(trim(p_numero), '')),
    jsonb_build_object('source', 'stage_imp_nfe_xml')
  );

  return v_nfe_id;
end;
$$;

create or replace function public.stage_imp_nfe_xml_item(
  p_nfe_id bigint,
  p_numero_item integer,
  p_codigo_fornecedor text,
  p_descricao_fornecedor text,
  p_ncm text,
  p_cfop text,
  p_unidade_xml text,
  p_quantidade_xml numeric,
  p_valor_total numeric default 0,
  p_lote_fornecedor text default null,
  p_data_fabricacao date default null,
  p_data_validade date default null,
  p_payload_item_json jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_item_id bigint;
  v_status_atual text;
  v_descricao_norm text;
  v_codigo_norm text;
  v_ncm_norm text;
  v_sugerida_id bigint;
begin
  perform public.require_current_user_permission('importacao.nfe_xml.stage');

  if p_nfe_id is null or p_nfe_id <= 0 then
    raise exception 'nfe_id is required';
  end if;
  if p_numero_item is null or p_numero_item <= 0 then
    raise exception 'numero_item must be greater than zero';
  end if;
  if nullif(trim(p_descricao_fornecedor), '') is null then
    raise exception 'descricao_fornecedor is required';
  end if;
  if nullif(trim(p_unidade_xml), '') is null then
    raise exception 'unidade_xml is required';
  end if;
  if p_quantidade_xml is null or p_quantidade_xml <= 0 then
    raise exception 'quantidade_xml must be greater than zero';
  end if;
  if p_valor_total is null or p_valor_total < 0 then
    raise exception 'valor_total must be greater than or equal to zero';
  end if;
  if p_data_fabricacao is not null and p_data_validade is not null and p_data_validade < p_data_fabricacao then
    raise exception 'data_validade must be greater than or equal to data_fabricacao';
  end if;
  if not exists (select 1 from public.imp_nfe_xmls where id = p_nfe_id and status <> 'cancelada') then
    raise exception 'active NFe XML not found';
  end if;

  select status
    into v_status_atual
    from public.imp_nfe_xml_itens
    where nfe_id = p_nfe_id
      and numero_item = p_numero_item;

  if v_status_atual = 'lote_gerado' then
    raise exception 'NFe XML item already generated MP lot';
  end if;

  v_actor := public.current_actor_id();
  v_descricao_norm := upper(trim(p_descricao_fornecedor));
  v_codigo_norm := upper(nullif(trim(p_codigo_fornecedor), ''));
  v_ncm_norm := nullif(regexp_replace(coalesce(p_ncm, ''), '\D', '', 'g'), '');

  insert into public.imp_nfe_xml_itens(
    nfe_id,
    numero_item,
    codigo_fornecedor,
    descricao_fornecedor,
    descricao_norm,
    ncm,
    cfop,
    unidade_xml,
    quantidade_xml,
    valor_total,
    lote_fornecedor,
    data_fabricacao,
    data_validade,
    status,
    payload_item_json,
    created_by,
    updated_by
  )
  values (
    p_nfe_id,
    p_numero_item,
    nullif(trim(p_codigo_fornecedor), ''),
    trim(p_descricao_fornecedor),
    v_descricao_norm,
    v_ncm_norm,
    nullif(trim(p_cfop), ''),
    upper(trim(p_unidade_xml)),
    p_quantidade_xml,
    p_valor_total,
    nullif(trim(p_lote_fornecedor), ''),
    p_data_fabricacao,
    p_data_validade,
    'pendente_match',
    coalesce(p_payload_item_json, '{}'::jsonb),
    v_actor,
    v_actor
  )
  on conflict (nfe_id, numero_item) do update set
    codigo_fornecedor = excluded.codigo_fornecedor,
    descricao_fornecedor = excluded.descricao_fornecedor,
    descricao_norm = excluded.descricao_norm,
    ncm = excluded.ncm,
    cfop = excluded.cfop,
    unidade_xml = excluded.unidade_xml,
    quantidade_xml = excluded.quantidade_xml,
    valor_total = excluded.valor_total,
    lote_fornecedor = excluded.lote_fornecedor,
    data_fabricacao = excluded.data_fabricacao,
    data_validade = excluded.data_validade,
    status = case
      when public.imp_nfe_xml_itens.status in ('match_confirmado', 'ignorado') then public.imp_nfe_xml_itens.status
      else 'pendente_match'
    end,
    payload_item_json = excluded.payload_item_json,
    updated_by = v_actor
  returning id into v_item_id;

  insert into public.imp_nfe_item_match_candidatos(
    item_id,
    materia_prima_id,
    score,
    motivo,
    created_by
  )
  select
    v_item_id,
    mp.id,
    case
      when v_codigo_norm is not null and upper(trim(mp.sku_corrigido)) = v_codigo_norm then 100
      when upper(trim(mp.nome_norm)) = v_descricao_norm then 90
      when upper(trim(mp.nome)) = v_descricao_norm then 85
      when v_ncm_norm is not null and regexp_replace(coalesce(mp.ncm, ''), '\D', '', 'g') = v_ncm_norm then 65
      else 40
    end as score,
    case
      when v_codigo_norm is not null and upper(trim(mp.sku_corrigido)) = v_codigo_norm then 'SKU fornecedor igual ao SKU corrigido da MP'
      when upper(trim(mp.nome_norm)) = v_descricao_norm then 'Descricao XML igual ao nome normalizado da MP'
      when upper(trim(mp.nome)) = v_descricao_norm then 'Descricao XML igual ao nome da MP'
      when v_ncm_norm is not null and regexp_replace(coalesce(mp.ncm, ''), '\D', '', 'g') = v_ncm_norm then 'NCM XML igual ao NCM da MP'
      else 'Candidato manual preservado para conferencia'
    end as motivo,
    v_actor
  from public.cad_materias_primas mp
  where mp.status = 'active'
    and (
      (v_codigo_norm is not null and upper(trim(mp.sku_corrigido)) = v_codigo_norm)
      or upper(trim(mp.nome_norm)) = v_descricao_norm
      or upper(trim(mp.nome)) = v_descricao_norm
      or (v_ncm_norm is not null and regexp_replace(coalesce(mp.ncm, ''), '\D', '', 'g') = v_ncm_norm)
    )
  on conflict (item_id, materia_prima_id) do update set
    score = greatest(public.imp_nfe_item_match_candidatos.score, excluded.score),
    motivo = case
      when excluded.score >= public.imp_nfe_item_match_candidatos.score then excluded.motivo
      else public.imp_nfe_item_match_candidatos.motivo
    end;

  select materia_prima_id
    into v_sugerida_id
    from public.imp_nfe_item_match_candidatos
    where item_id = v_item_id
    order by score desc, id
    limit 1;

  update public.imp_nfe_xml_itens
     set materia_prima_sugerida_id = v_sugerida_id,
         status = case
           when status in ('match_confirmado', 'ignorado') then status
           when v_sugerida_id is null then 'pendente_match'
           else 'match_sugerido'
         end,
         updated_by = v_actor
   where id = v_item_id;

  perform public.sync_imp_nfe_xml_status(p_nfe_id);

  perform public.log_action(
    'importacao.nfe_xml_item_staged',
    'imp_nfe_xml_itens',
    v_item_id::text,
    'success',
    null,
    jsonb_build_object('nfe_id', p_nfe_id, 'numero_item', p_numero_item, 'materia_prima_sugerida_id', v_sugerida_id),
    jsonb_build_object('source', 'stage_imp_nfe_xml_item')
  );

  return v_item_id;
end;
$$;

create or replace function public.confirm_imp_nfe_item_match(
  p_item_id bigint,
  p_materia_prima_id bigint,
  p_unidade_destino text default null,
  p_fator_conversao numeric default null,
  p_lote_fornecedor text default null,
  p_data_fabricacao date default null,
  p_data_validade date default null,
  p_motivo text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_item public.imp_nfe_xml_itens%rowtype;
  v_mp public.cad_materias_primas%rowtype;
  v_unidade_destino text;
  v_fator numeric;
  v_quantidade_convertida numeric;
  v_lote_fornecedor text;
  v_data_fabricacao date;
  v_data_validade date;
  v_resolucao_id bigint;
begin
  perform public.require_current_user_permission('importacao.nfe_xml.match');

  if p_item_id is null or p_item_id <= 0 then
    raise exception 'item_id is required';
  end if;
  if p_materia_prima_id is null or p_materia_prima_id <= 0 then
    raise exception 'materia_prima_id is required';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;

  select *
    into v_item
    from public.imp_nfe_xml_itens
    where id = p_item_id
    for update;

  if not found then
    raise exception 'NFe XML item not found';
  end if;
  if v_item.status = 'lote_gerado' then
    raise exception 'NFe XML item already generated MP lot';
  end if;
  if v_item.status = 'ignorado' then
    raise exception 'ignored NFe XML item cannot be matched';
  end if;

  select *
    into v_mp
    from public.cad_materias_primas
    where id = p_materia_prima_id
      and status = 'active';

  if not found then
    raise exception 'active materia_prima not found';
  end if;

  v_unidade_destino := upper(coalesce(nullif(trim(p_unidade_destino), ''), v_mp.unidade_base_estoque));

  if p_fator_conversao is not null then
    v_fator := p_fator_conversao;
  elsif upper(trim(v_item.unidade_xml)) = v_unidade_destino then
    v_fator := 1;
  else
    select fator
      into v_fator
      from public.cad_conversoes_unidade_mp
      where materia_prima_id = p_materia_prima_id
        and upper(trim(unidade_origem)) = upper(trim(v_item.unidade_xml))
        and upper(trim(unidade_destino)) = v_unidade_destino
        and (vigencia_inicio is null or vigencia_inicio <= current_date)
        and (vigencia_fim is null or vigencia_fim >= current_date)
      order by vigencia_inicio desc nulls last, id desc
      limit 1;
  end if;

  if v_fator is null or v_fator <= 0 then
    raise exception 'unit conversion factor is required';
  end if;

  v_quantidade_convertida := v_item.quantidade_xml * v_fator;
  v_lote_fornecedor := coalesce(nullif(trim(p_lote_fornecedor), ''), v_item.lote_fornecedor);
  v_data_fabricacao := coalesce(p_data_fabricacao, v_item.data_fabricacao);
  v_data_validade := coalesce(p_data_validade, v_item.data_validade);

  if v_data_fabricacao is not null and v_data_validade is not null and v_data_validade < v_data_fabricacao then
    raise exception 'data_validade must be greater than or equal to data_fabricacao';
  end if;

  v_actor := public.current_actor_id();

  update public.imp_nfe_item_match_candidatos
     set status = case when materia_prima_id = p_materia_prima_id then 'aceito' else status end
   where item_id = p_item_id;

  update public.imp_nfe_xml_itens
     set status = 'match_confirmado',
         materia_prima_confirmada_id = p_materia_prima_id,
         unidade_destino = v_unidade_destino,
         fator_conversao = v_fator,
         quantidade_convertida = v_quantidade_convertida,
         lote_fornecedor = v_lote_fornecedor,
         data_fabricacao = v_data_fabricacao,
         data_validade = v_data_validade,
         updated_by = v_actor
   where id = p_item_id;

  insert into public.imp_nfe_item_resolucoes(
    item_id,
    materia_prima_id,
    unidade_destino,
    fator_conversao,
    quantidade_convertida,
    lote_fornecedor,
    data_fabricacao,
    data_validade,
    motivo,
    created_by
  )
  values (
    p_item_id,
    p_materia_prima_id,
    v_unidade_destino,
    v_fator,
    v_quantidade_convertida,
    v_lote_fornecedor,
    v_data_fabricacao,
    v_data_validade,
    trim(p_motivo),
    v_actor
  )
  returning id into v_resolucao_id;

  perform public.sync_imp_nfe_xml_status(v_item.nfe_id);

  perform public.log_action(
    'importacao.nfe_xml_item_matched',
    'imp_nfe_xml_itens',
    p_item_id::text,
    'success',
    null,
    jsonb_build_object(
      'materia_prima_id', p_materia_prima_id,
      'unidade_destino', v_unidade_destino,
      'fator_conversao', v_fator,
      'quantidade_convertida', v_quantidade_convertida
    ),
    jsonb_build_object('source', 'confirm_imp_nfe_item_match', 'resolucao_id', v_resolucao_id)
  );

  return v_resolucao_id;
end;
$$;

create or replace function public.ignore_imp_nfe_xml_item(
  p_item_id bigint,
  p_motivo text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_item public.imp_nfe_xml_itens%rowtype;
begin
  perform public.require_current_user_permission('importacao.nfe_xml.ignore_item');

  if p_item_id is null or p_item_id <= 0 then
    raise exception 'item_id is required';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;

  select *
    into v_item
    from public.imp_nfe_xml_itens
    where id = p_item_id
    for update;

  if not found then
    raise exception 'NFe XML item not found';
  end if;
  if v_item.status = 'lote_gerado' then
    raise exception 'NFe XML item already generated MP lot';
  end if;

  v_actor := public.current_actor_id();

  update public.imp_nfe_xml_itens
     set status = 'ignorado',
         updated_by = v_actor,
         payload_item_json = payload_item_json || jsonb_build_object('motivo_ignorado', trim(p_motivo))
   where id = p_item_id;

  perform public.sync_imp_nfe_xml_status(v_item.nfe_id);

  perform public.log_action(
    'importacao.nfe_xml_item_ignored',
    'imp_nfe_xml_itens',
    p_item_id::text,
    'success',
    null,
    jsonb_build_object('motivo', trim(p_motivo)),
    jsonb_build_object('source', 'ignore_imp_nfe_xml_item')
  );
end;
$$;

create or replace function public.gerar_lote_mp_from_imp_nfe_item(
  p_item_id bigint,
  p_status text default 'disponivel',
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_item record;
  v_lote_id bigint;
  v_codigo_lote text;
  v_origem_ref text;
begin
  perform public.require_current_user_permission('importacao.nfe_xml.generate_mp_lot');

  if p_item_id is null or p_item_id <= 0 then
    raise exception 'item_id is required';
  end if;
  if p_status not in ('disponivel', 'bloqueado') then
    raise exception 'invalid initial MP lot status';
  end if;

  select
      item.*,
      nfe.chave_acesso_norm,
      nfe.numero as nfe_numero,
      nfe.serie as nfe_serie
    into v_item
    from public.imp_nfe_xml_itens item
    join public.imp_nfe_xmls nfe on nfe.id = item.nfe_id
    where item.id = p_item_id
    for update of item;

  if not found then
    raise exception 'NFe XML item not found';
  end if;
  if v_item.status <> 'match_confirmado' then
    raise exception 'NFe XML item must be matched before MP lot generation';
  end if;
  if v_item.materia_prima_confirmada_id is null or v_item.quantidade_convertida is null or v_item.quantidade_convertida <= 0 then
    raise exception 'NFe XML item match is incomplete';
  end if;
  if exists (select 1 from public.imp_nfe_item_lotes_mp where item_id = p_item_id) then
    raise exception 'NFe XML item already has generated MP lot';
  end if;

  v_actor := public.current_actor_id();
  v_codigo_lote := concat('MP-NFE-', right(v_item.chave_acesso_norm, 8), '-', lpad(v_item.numero_item::text, 3, '0'));
  v_origem_ref := concat_ws(
    ' ',
    'NFe',
    nullif(v_item.nfe_numero, ''),
    case when nullif(v_item.nfe_serie, '') is null then null else concat('serie ', v_item.nfe_serie) end,
    concat('chave ', v_item.chave_acesso_norm),
    concat('item ', v_item.numero_item::text)
  );

  v_lote_id := public.create_est_lote_mp(
    v_item.materia_prima_confirmada_id,
    v_item.quantidade_convertida,
    v_codigo_lote,
    'entrada_compra',
    p_status,
    v_item.data_fabricacao,
    v_item.data_validade,
    v_origem_ref,
    concat_ws(
      ' | ',
      nullif(trim(p_observacao), ''),
      case when nullif(v_item.lote_fornecedor, '') is null then null else concat('lote fornecedor: ', v_item.lote_fornecedor) end,
      concat('unidade XML: ', v_item.unidade_xml),
      concat('fator conversao: ', v_item.fator_conversao::text)
    )
  );

  insert into public.imp_nfe_item_lotes_mp(item_id, lote_mp_id, created_by)
  values (p_item_id, v_lote_id, v_actor);

  update public.imp_nfe_xml_itens
     set status = 'lote_gerado',
         updated_by = v_actor
   where id = p_item_id;

  perform public.sync_imp_nfe_xml_status(v_item.nfe_id);

  perform public.log_action(
    'importacao.nfe_xml_item_lote_mp_generated',
    'imp_nfe_xml_itens',
    p_item_id::text,
    'success',
    null,
    jsonb_build_object('lote_mp_id', v_lote_id, 'codigo_lote', v_codigo_lote),
    jsonb_build_object('source', 'gerar_lote_mp_from_imp_nfe_item')
  );

  return v_lote_id;
end;
$$;

create or replace view public.imp_nfe_xml_itens_pendentes_match as
select
  item.id as item_id,
  item.nfe_id,
  nfe.chave_acesso_norm,
  nfe.numero as nfe_numero,
  nfe.serie as nfe_serie,
  nfe.emitente_nome,
  nfe.emitente_cnpj_norm,
  item.numero_item,
  item.codigo_fornecedor,
  item.descricao_fornecedor,
  item.ncm,
  item.cfop,
  item.unidade_xml,
  item.quantidade_xml,
  item.valor_total,
  item.status,
  item.materia_prima_sugerida_id,
  mp_sugerida.sku_corrigido as materia_prima_sugerida_sku,
  mp_sugerida.nome as materia_prima_sugerida_nome,
  melhor.score as melhor_score,
  melhor.motivo as melhor_motivo,
  coalesce(candidatos.total_candidatos, 0) as total_candidatos,
  item.created_at,
  item.updated_at
from public.imp_nfe_xml_itens item
join public.imp_nfe_xmls nfe on nfe.id = item.nfe_id
left join public.cad_materias_primas mp_sugerida on mp_sugerida.id = item.materia_prima_sugerida_id
left join lateral (
  select cand.score, cand.motivo
  from public.imp_nfe_item_match_candidatos cand
  where cand.item_id = item.id
  order by cand.score desc, cand.id
  limit 1
) melhor on true
left join lateral (
  select count(*)::integer as total_candidatos
  from public.imp_nfe_item_match_candidatos cand
  where cand.item_id = item.id
) candidatos on true
where item.status in ('pendente_match', 'match_sugerido');

create or replace view public.imp_nfe_xml_resumo as
select
  nfe.id as nfe_id,
  nfe.chave_acesso_norm,
  nfe.numero,
  nfe.serie,
  nfe.emitente_nome,
  nfe.emitente_cnpj_norm,
  nfe.data_emissao,
  nfe.status,
  count(item.id)::integer as total_itens,
  count(item.id) filter (where item.status in ('pendente_match', 'match_sugerido'))::integer as itens_pendentes_match,
  count(item.id) filter (where item.status = 'match_confirmado')::integer as itens_confirmados,
  count(item.id) filter (where item.status = 'lote_gerado')::integer as itens_com_lote_mp,
  count(item.id) filter (where item.status = 'ignorado')::integer as itens_ignorados,
  coalesce(sum(item.valor_total), 0) as valor_total_xml,
  nfe.created_at,
  nfe.updated_at
from public.imp_nfe_xmls nfe
left join public.imp_nfe_xml_itens item on item.nfe_id = nfe.id
group by
  nfe.id,
  nfe.chave_acesso_norm,
  nfe.numero,
  nfe.serie,
  nfe.emitente_nome,
  nfe.emitente_cnpj_norm,
  nfe.data_emissao,
  nfe.status,
  nfe.created_at,
  nfe.updated_at;

create or replace view public.com_pedidos_kanban as
select
  pedido.id as pedido_id,
  pedido.codigo_pedido,
  pedido.status,
  case pedido.status
    when 'draft' then 'rascunho'
    when 'open' then 'aberto'
    when 'blocked' then 'bloqueado'
    when 'fulfilled' then 'concluido'
    when 'cancelled' then 'cancelado'
    else pedido.status
  end as coluna_kanban,
  pedido.tipo_pedido,
  pedido.data_pedido,
  pedido.previsao_entrega,
  pedido.valor_total,
  pedido.cliente_id,
  cliente.nome as cliente_nome,
  pedido.propriedade_id,
  propriedade.nome as propriedade_nome,
  propriedade.cidade as propriedade_cidade,
  propriedade.uf as propriedade_uf,
  pedido.sequencia_propriedade,
  pedido.vendedor_gerador_id,
  vendedor.nome as vendedor_gerador_nome,
  vendedor.user_profile_id as vendedor_user_id,
  vendedor.vendedor_responsavel_id as gerente_vinculado_id,
  gerente_vinculado.nome as gerente_vinculado_nome,
  gerente_vinculado.user_profile_id as gerente_vinculado_user_id,
  area.area_id,
  area.area_nome,
  area.gerente_area_id,
  gerente_area.nome as gerente_area_nome,
  gerente_area.user_profile_id as gerente_area_user_id,
  pedido.created_at,
  pedido.updated_at
from public.com_pedidos pedido
join public.cad_clientes cliente on cliente.id = pedido.cliente_id
left join public.cad_cliente_propriedades propriedade on propriedade.id = pedido.propriedade_id
left join public.cad_pessoas_comerciais vendedor on vendedor.id = pedido.vendedor_gerador_id
left join public.cad_pessoas_comerciais gerente_vinculado on gerente_vinculado.id = vendedor.vendedor_responsavel_id
left join lateral (
  select
    area.id as area_id,
    area.nome as area_nome,
    area.gerente_id as gerente_area_id
  from public.cad_pessoa_areas_comerciais vinculo
  join public.cad_areas_comerciais area on area.id = vinculo.area_id
  where vinculo.pessoa_id = pedido.vendedor_gerador_id
    and vinculo.status = 'active'
    and area.status = 'active'
    and (vinculo.vigencia_inicio is null or vinculo.vigencia_inicio <= current_date)
    and (vinculo.vigencia_fim is null or vinculo.vigencia_fim >= current_date)
  order by vinculo.vigencia_inicio desc nulls last, vinculo.id desc
  limit 1
) area on true
left join public.cad_pessoas_comerciais gerente_area on gerente_area.id = area.gerente_area_id;

grant select on public.imp_nfe_xml_itens_pendentes_match to authenticated;
grant select on public.imp_nfe_xml_resumo to authenticated;
grant select on public.com_pedidos_kanban to authenticated;

revoke all on function public.prevent_imp_nfe_append_only_changes() from public;
revoke all on function public.sync_imp_nfe_xml_status(bigint) from public;
revoke all on function public.next_com_pedido_sequencia(bigint, bigint) from public;
revoke all on function public.create_com_pedido_operacional(bigint, bigint, numeric, numeric, bigint, text, text, date, bigint, numeric, text) from public;
revoke all on function public.stage_imp_nfe_xml(text, text, text, text, text, date, jsonb) from public;
revoke all on function public.stage_imp_nfe_xml_item(bigint, integer, text, text, text, text, text, numeric, numeric, text, date, date, jsonb) from public;
revoke all on function public.confirm_imp_nfe_item_match(bigint, bigint, text, numeric, text, date, date, text) from public;
revoke all on function public.ignore_imp_nfe_xml_item(bigint, text) from public;
revoke all on function public.gerar_lote_mp_from_imp_nfe_item(bigint, text, text) from public;

grant execute on function public.next_com_pedido_sequencia(bigint, bigint) to authenticated;
grant execute on function public.create_com_pedido_operacional(bigint, bigint, numeric, numeric, bigint, text, text, date, bigint, numeric, text) to authenticated;
grant execute on function public.stage_imp_nfe_xml(text, text, text, text, text, date, jsonb) to authenticated;
grant execute on function public.stage_imp_nfe_xml_item(bigint, integer, text, text, text, text, text, numeric, numeric, text, date, date, jsonb) to authenticated;
grant execute on function public.confirm_imp_nfe_item_match(bigint, bigint, text, numeric, text, date, date, text) to authenticated;
grant execute on function public.ignore_imp_nfe_xml_item(bigint, text) to authenticated;
grant execute on function public.gerar_lote_mp_from_imp_nfe_item(bigint, text, text) to authenticated;
