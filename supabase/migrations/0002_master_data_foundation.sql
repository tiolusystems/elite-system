create table if not exists public.cad_clientes (
  id bigint generated always as identity primary key,
  codigo_legado text unique,
  nome text not null,
  nome_norm text not null,
  cidade text not null,
  uf text not null,
  status text not null default 'active',
  apelidos_json jsonb not null default '[]'::jsonb,
  valor_total_compras numeric,
  source_row_id bigint,
  source_batch_id bigint,
  payload_origem_json jsonb not null default '{}'::jsonb,
  created_by uuid references public.user_profiles(id),
  updated_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cad_clientes_status_check check (status in ('active', 'inactive', 'pending_review')),
  constraint cad_clientes_uf_check check (char_length(uf) = 2),
  constraint cad_clientes_valor_total_check check (valor_total_compras is null or valor_total_compras >= 0)
);

create table if not exists public.cad_cliente_propriedades (
  id bigint generated always as identity primary key,
  cliente_id bigint not null references public.cad_clientes(id),
  nome text not null,
  cnpj text,
  cnpj_norm text unique,
  cidade text,
  uf text,
  status text not null default 'active',
  created_by uuid references public.user_profiles(id),
  updated_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cad_cliente_propriedades_status_check check (status in ('active', 'inactive', 'pending_review'))
);

create table if not exists public.cad_cliente_documentos (
  id bigint generated always as identity primary key,
  cliente_id bigint not null references public.cad_clientes(id),
  propriedade_id bigint references public.cad_cliente_propriedades(id),
  tipo text not null,
  numero text not null,
  numero_norm text not null,
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint cad_cliente_documentos_tipo_check check (tipo in ('cpf', 'cnpj', 'ie', 'outro')),
  constraint cad_cliente_documentos_tipo_numero_key unique (tipo, numero_norm)
);

create table if not exists public.cad_cliente_contatos (
  id bigint generated always as identity primary key,
  cliente_id bigint not null references public.cad_clientes(id),
  propriedade_id bigint references public.cad_cliente_propriedades(id),
  nome text not null,
  papel text not null,
  telefone text,
  email text,
  status text not null default 'active',
  created_by uuid references public.user_profiles(id),
  updated_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cad_cliente_contatos_status_check check (status in ('active', 'inactive', 'pending_review')),
  constraint cad_cliente_contatos_contato_check check (telefone is not null or email is not null)
);

create table if not exists public.cad_pessoas_comerciais (
  id bigint generated always as identity primary key,
  codigo_legado text unique,
  nome text not null,
  nome_norm text not null,
  tipo_comercial text,
  papeis_json jsonb not null,
  status text not null default 'active',
  vendedor_responsavel_id bigint references public.cad_pessoas_comerciais(id),
  apelidos_json jsonb not null default '[]'::jsonb,
  grafias_incorretas_json jsonb not null default '[]'::jsonb,
  source_row_id bigint,
  source_batch_id bigint,
  payload_origem_json jsonb not null default '{}'::jsonb,
  created_by uuid references public.user_profiles(id),
  updated_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cad_pessoas_status_check check (status in ('active', 'inactive', 'pending_review')),
  constraint cad_pessoas_tipo_check check (
    tipo_comercial is null or tipo_comercial in (
      'funcionario_elite',
      'agente_vinculado',
      'agente_direto_elite',
      'vendedor_direto_elite',
      'tecnico_campo',
      'entregador',
      'gerente',
      'vendedor_gerente'
    )
  )
);

create table if not exists public.cad_pessoa_aliases (
  id bigint generated always as identity primary key,
  pessoa_id bigint not null references public.cad_pessoas_comerciais(id),
  alias text not null,
  alias_norm text not null unique,
  tipo text not null default 'apelido',
  created_at timestamptz not null default now(),
  constraint cad_pessoa_aliases_tipo_check check (tipo in ('nome', 'apelido', 'grafia_incorreta'))
);

create table if not exists public.cad_cliente_vendedores (
  id bigint generated always as identity primary key,
  cliente_id bigint not null references public.cad_clientes(id),
  pessoa_id bigint not null references public.cad_pessoas_comerciais(id),
  status text not null default 'active',
  vigencia_inicio date,
  vigencia_fim date,
  created_by uuid references public.user_profiles(id),
  updated_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cad_cliente_vendedores_status_check check (status in ('active', 'inactive', 'pending_review')),
  constraint cad_cliente_vendedores_key unique (cliente_id, pessoa_id, vigencia_inicio)
);

create table if not exists public.cad_materias_primas (
  id bigint generated always as identity primary key,
  codigo_legado text,
  sku_corrigido text not null unique,
  nome text not null,
  nome_norm text not null,
  unidade_base_estoque text not null,
  status text not null default 'active',
  tipo text,
  densidade numeric,
  estoque_minimo numeric,
  ncm text,
  ibama text,
  codigo_ads text,
  source_row_id bigint,
  source_batch_id bigint,
  payload_origem_json jsonb not null default '{}'::jsonb,
  created_by uuid references public.user_profiles(id),
  updated_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cad_materias_status_check check (status in ('active', 'inactive', 'pending_review')),
  constraint cad_materias_densidade_check check (densidade is null or densidade > 0),
  constraint cad_materias_estoque_minimo_check check (estoque_minimo is null or estoque_minimo >= 0)
);

create table if not exists public.cad_conversoes_unidade_mp (
  id bigint generated always as identity primary key,
  materia_prima_id bigint not null references public.cad_materias_primas(id),
  unidade_origem text not null,
  unidade_destino text not null,
  fator numeric not null,
  vigencia_inicio date,
  vigencia_fim date,
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint cad_conversoes_fator_check check (fator > 0),
  constraint cad_conversoes_key unique (materia_prima_id, unidade_origem, unidade_destino, vigencia_inicio)
);

create table if not exists public.cad_produtos_base (
  id bigint generated always as identity primary key,
  codigo_produto text not null unique,
  nome text not null,
  nome_norm text not null,
  status text not null default 'active',
  grupo text,
  densidade_kg_l numeric,
  reg_mapa text,
  ncm text,
  ibama text,
  ads text,
  source_row_id bigint,
  source_batch_id bigint,
  payload_origem_json jsonb not null default '{}'::jsonb,
  created_by uuid references public.user_profiles(id),
  updated_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cad_produtos_status_check check (status in ('active', 'inactive', 'pending_review')),
  constraint cad_produtos_densidade_check check (densidade_kg_l is null or densidade_kg_l > 0)
);

create table if not exists public.cad_embalagens (
  id bigint generated always as identity primary key,
  codigo_legado text,
  descricao text not null,
  descricao_norm text not null unique,
  unidade text not null,
  volume_litros numeric,
  controla_estoque boolean not null default false,
  materia_prima_id bigint references public.cad_materias_primas(id),
  status text not null default 'active',
  created_by uuid references public.user_profiles(id),
  updated_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cad_embalagens_status_check check (status in ('active', 'inactive', 'pending_review')),
  constraint cad_embalagens_volume_check check (volume_litros is null or volume_litros > 0),
  constraint cad_embalagens_estoque_check check (controla_estoque = false or materia_prima_id is not null)
);

create table if not exists public.cad_produto_embalagens (
  id bigint generated always as identity primary key,
  produto_id bigint not null references public.cad_produtos_base(id),
  embalagem_id bigint not null references public.cad_embalagens(id),
  codigo_item text not null unique,
  status text not null default 'active',
  created_by uuid references public.user_profiles(id),
  updated_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cad_produto_embalagens_status_check check (status in ('active', 'inactive', 'pending_review')),
  constraint cad_produto_embalagens_key unique (produto_id, embalagem_id)
);

create table if not exists public.cad_veiculos (
  id bigint generated always as identity primary key,
  codigo_legado text,
  descricao text not null,
  descricao_norm text not null,
  placa text,
  placa_norm text unique,
  status text not null default 'active',
  capacidade numeric,
  created_by uuid references public.user_profiles(id),
  updated_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cad_veiculos_status_check check (status in ('active', 'inactive', 'pending_review')),
  constraint cad_veiculos_capacidade_check check (capacidade is null or capacidade > 0)
);

create table if not exists public.cad_garantias_produto_mapa (
  id bigint generated always as identity primary key,
  produto_id bigint not null references public.cad_produtos_base(id),
  nutriente text not null,
  tipo_limite text not null,
  valor numeric not null,
  unidade text not null,
  fonte text not null default 'mapa',
  vigencia_inicio date,
  vigencia_fim date,
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint cad_garantias_produto_limite_check check (tipo_limite in ('minimo', 'maximo', 'faixa', 'declarado')),
  constraint cad_garantias_produto_fonte_check check (fonte in ('mapa', 'manual', 'laboratorio', 'fornecedor', 'calculado')),
  constraint cad_garantias_produto_valor_check check (valor >= 0)
);

create table if not exists public.cad_garantias_lote_mp (
  id bigint generated always as identity primary key,
  materia_prima_id bigint not null references public.cad_materias_primas(id),
  lote_mp_id text not null,
  nutriente text not null,
  valor numeric not null,
  unidade text not null,
  fonte text not null,
  documento_referencia text,
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint cad_garantias_lote_fonte_check check (fonte in ('mapa', 'manual', 'laboratorio', 'fornecedor', 'calculado')),
  constraint cad_garantias_lote_valor_check check (valor >= 0),
  constraint cad_garantias_lote_autor_check check (fonte not in ('manual', 'laboratorio') or created_by is not null)
);

create table if not exists public.cad_limites_credito_cliente (
  id bigint generated always as identity primary key,
  cliente_id bigint not null references public.cad_clientes(id),
  limite_manual numeric,
  limite_calculado numeric,
  limite_disponivel numeric not null,
  status_credito text not null,
  motivo text,
  updated_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cad_limites_manual_check check (limite_manual is null or limite_manual >= 0),
  constraint cad_limites_calculado_check check (limite_calculado is null or limite_calculado >= 0),
  constraint cad_limites_disponivel_check check (limite_disponivel >= 0),
  constraint cad_limites_status_check check (status_credito in ('liberado', 'reduzido', 'bloqueado', 'pendente_aprovacao')),
  constraint cad_limites_motivo_check check (status_credito = 'liberado' or motivo is not null)
);

create table if not exists public.cadastro_validation_issues (
  id bigint generated always as identity primary key,
  entity text not null,
  entity_key text,
  severity text not null,
  code text not null,
  message text not null,
  field text,
  payload_json jsonb not null default '{}'::jsonb,
  status text not null default 'pending',
  source_batch_id bigint,
  created_by uuid references public.user_profiles(id),
  resolved_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  constraint cadastro_validation_issues_severity_check check (severity in ('error', 'warning')),
  constraint cadastro_validation_issues_status_check check (status in ('pending', 'accepted', 'resolved', 'dismissed'))
);

create index if not exists idx_cad_clientes_nome_norm on public.cad_clientes(nome_norm);
create index if not exists idx_cad_pessoas_nome_norm on public.cad_pessoas_comerciais(nome_norm);
create index if not exists idx_cad_materias_nome_norm on public.cad_materias_primas(nome_norm);
create index if not exists idx_cad_produtos_nome_norm on public.cad_produtos_base(nome_norm);
create index if not exists idx_cad_limites_credito_cliente on public.cad_limites_credito_cliente(cliente_id, created_at desc);
create index if not exists idx_cadastro_validation_issues_status on public.cadastro_validation_issues(status, severity);

drop trigger if exists trg_cad_clientes_updated_at on public.cad_clientes;
create trigger trg_cad_clientes_updated_at before update on public.cad_clientes
for each row execute function public.touch_updated_at();

drop trigger if exists trg_cad_cliente_propriedades_updated_at on public.cad_cliente_propriedades;
create trigger trg_cad_cliente_propriedades_updated_at before update on public.cad_cliente_propriedades
for each row execute function public.touch_updated_at();

drop trigger if exists trg_cad_cliente_contatos_updated_at on public.cad_cliente_contatos;
create trigger trg_cad_cliente_contatos_updated_at before update on public.cad_cliente_contatos
for each row execute function public.touch_updated_at();

drop trigger if exists trg_cad_pessoas_updated_at on public.cad_pessoas_comerciais;
create trigger trg_cad_pessoas_updated_at before update on public.cad_pessoas_comerciais
for each row execute function public.touch_updated_at();

drop trigger if exists trg_cad_cliente_vendedores_updated_at on public.cad_cliente_vendedores;
create trigger trg_cad_cliente_vendedores_updated_at before update on public.cad_cliente_vendedores
for each row execute function public.touch_updated_at();

drop trigger if exists trg_cad_materias_updated_at on public.cad_materias_primas;
create trigger trg_cad_materias_updated_at before update on public.cad_materias_primas
for each row execute function public.touch_updated_at();

drop trigger if exists trg_cad_produtos_updated_at on public.cad_produtos_base;
create trigger trg_cad_produtos_updated_at before update on public.cad_produtos_base
for each row execute function public.touch_updated_at();

drop trigger if exists trg_cad_embalagens_updated_at on public.cad_embalagens;
create trigger trg_cad_embalagens_updated_at before update on public.cad_embalagens
for each row execute function public.touch_updated_at();

drop trigger if exists trg_cad_produto_embalagens_updated_at on public.cad_produto_embalagens;
create trigger trg_cad_produto_embalagens_updated_at before update on public.cad_produto_embalagens
for each row execute function public.touch_updated_at();

drop trigger if exists trg_cad_veiculos_updated_at on public.cad_veiculos;
create trigger trg_cad_veiculos_updated_at before update on public.cad_veiculos
for each row execute function public.touch_updated_at();

drop trigger if exists trg_cad_limites_credito_updated_at on public.cad_limites_credito_cliente;
create trigger trg_cad_limites_credito_updated_at before update on public.cad_limites_credito_cliente
for each row execute function public.touch_updated_at();

alter table public.cad_clientes enable row level security;
alter table public.cad_cliente_propriedades enable row level security;
alter table public.cad_cliente_documentos enable row level security;
alter table public.cad_cliente_contatos enable row level security;
alter table public.cad_pessoas_comerciais enable row level security;
alter table public.cad_pessoa_aliases enable row level security;
alter table public.cad_cliente_vendedores enable row level security;
alter table public.cad_materias_primas enable row level security;
alter table public.cad_conversoes_unidade_mp enable row level security;
alter table public.cad_produtos_base enable row level security;
alter table public.cad_embalagens enable row level security;
alter table public.cad_produto_embalagens enable row level security;
alter table public.cad_veiculos enable row level security;
alter table public.cad_garantias_produto_mapa enable row level security;
alter table public.cad_garantias_lote_mp enable row level security;
alter table public.cad_limites_credito_cliente enable row level security;
alter table public.cadastro_validation_issues enable row level security;

create policy "authenticated full master data access" on public.cad_clientes
for all to authenticated using (true) with check (true);
create policy "authenticated full property access" on public.cad_cliente_propriedades
for all to authenticated using (true) with check (true);
create policy "authenticated full document access" on public.cad_cliente_documentos
for all to authenticated using (true) with check (true);
create policy "authenticated full contact access" on public.cad_cliente_contatos
for all to authenticated using (true) with check (true);
create policy "authenticated full commercial person access" on public.cad_pessoas_comerciais
for all to authenticated using (true) with check (true);
create policy "authenticated full alias access" on public.cad_pessoa_aliases
for all to authenticated using (true) with check (true);
create policy "authenticated full client seller access" on public.cad_cliente_vendedores
for all to authenticated using (true) with check (true);
create policy "authenticated full raw material access" on public.cad_materias_primas
for all to authenticated using (true) with check (true);
create policy "authenticated full unit conversion access" on public.cad_conversoes_unidade_mp
for all to authenticated using (true) with check (true);
create policy "authenticated full product access" on public.cad_produtos_base
for all to authenticated using (true) with check (true);
create policy "authenticated full package access" on public.cad_embalagens
for all to authenticated using (true) with check (true);
create policy "authenticated full product package access" on public.cad_produto_embalagens
for all to authenticated using (true) with check (true);
create policy "authenticated full vehicle access" on public.cad_veiculos
for all to authenticated using (true) with check (true);
create policy "authenticated full product guarantee access" on public.cad_garantias_produto_mapa
for all to authenticated using (true) with check (true);
create policy "authenticated full mp lot guarantee access" on public.cad_garantias_lote_mp
for all to authenticated using (true) with check (true);
create policy "authenticated full credit limit access" on public.cad_limites_credito_cliente
for all to authenticated using (true) with check (true);
create policy "authenticated full validation issue access" on public.cadastro_validation_issues
for all to authenticated using (true) with check (true);

insert into public.permission_actions(action_key, module, description, default_allowed, sort_order)
values
  ('cadastros.manage', 'cadastros', 'Criar e editar cadastros mestres', true, 60),
  ('cadastros.validate', 'cadastros', 'Executar validacoes e filas de revisao de cadastros', true, 61),
  ('cadastros.credit.manage', 'cadastros', 'Definir limite de credito e bloqueios de clientes', true, 62)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order;

create or replace function public.create_cad_cliente(
  p_nome text,
  p_nome_norm text,
  p_cidade text,
  p_uf text,
  p_status text default 'active',
  p_codigo_legado text default null,
  p_apelidos_json jsonb default '[]'::jsonb,
  p_payload_origem_json jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_cliente_id bigint;
begin
  if nullif(trim(p_nome), '') is null then
    raise exception 'nome is required';
  end if;
  if nullif(trim(p_cidade), '') is null then
    raise exception 'cidade is required';
  end if;
  if char_length(trim(p_uf)) <> 2 then
    raise exception 'uf must have exactly two letters';
  end if;
  if p_status not in ('active', 'inactive', 'pending_review') then
    raise exception 'invalid status';
  end if;

  v_actor := auth.uid();
  if v_actor is not null and not exists (
    select 1 from public.user_profiles where id = v_actor
  ) then
    v_actor := null;
  end if;

  insert into public.cad_clientes(
    codigo_legado,
    nome,
    nome_norm,
    cidade,
    uf,
    status,
    apelidos_json,
    payload_origem_json,
    created_by,
    updated_by
  )
  values (
    nullif(trim(p_codigo_legado), ''),
    trim(p_nome),
    trim(p_nome_norm),
    trim(p_cidade),
    upper(trim(p_uf)),
    p_status,
    coalesce(p_apelidos_json, '[]'::jsonb),
    coalesce(p_payload_origem_json, '{}'::jsonb),
    v_actor,
    v_actor
  )
  returning id into v_cliente_id;

  perform public.log_action(
    'cadastros.cliente_created',
    'cad_clientes',
    v_cliente_id::text,
    'success',
    null,
    jsonb_build_object(
      'nome', trim(p_nome),
      'cidade', trim(p_cidade),
      'uf', upper(trim(p_uf)),
      'status', p_status
    ),
    jsonb_build_object('source', 'create_cad_cliente')
  );

  return v_cliente_id;
end;
$$;

revoke all on function public.create_cad_cliente(text, text, text, text, text, text, jsonb, jsonb) from public;
grant execute on function public.create_cad_cliente(text, text, text, text, text, text, jsonb, jsonb) to authenticated;
