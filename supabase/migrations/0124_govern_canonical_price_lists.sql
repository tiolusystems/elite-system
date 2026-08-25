-- ORD-01 tranche 1A.1: canonical, governed and immutable commercial price lists.

insert into public.permission_actions(
  action_key, module, description, default_allowed, sort_order,
  runtime_module_key, runtime_access_kind
)
values
  ('pedidos.price_lists.view', 'pedidos', 'Consultar listas de preco', false, 126, 'pedidos', 'read'),
  ('pedidos.price_lists.draft.manage', 'pedidos', 'Gerenciar rascunhos de listas de preco', false, 127, 'pedidos', 'write'),
  ('pedidos.price_lists.publish', 'pedidos', 'Publicar versoes de listas de preco', false, 128, 'pedidos', 'write'),
  ('pedidos.price_lists.withdraw', 'pedidos', 'Retirar publicacoes de listas de preco', false, 129, 'pedidos', 'write')
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

create table public.com_origens_comerciais (
  id bigint generated always as identity primary key,
  codigo text not null unique,
  nome text not null,
  created_at timestamptz not null default now(),
  constraint com_origens_comerciais_codigo_check
    check (codigo = lower(btrim(codigo)) and codigo ~ '^[a-z][a-z0-9_]*$'),
  constraint com_origens_comerciais_nome_check check (length(btrim(nome)) > 0)
);

insert into public.com_origens_comerciais(codigo, nome)
values
  ('direto_elite', 'Direto Elite'),
  ('agente', 'Agente');

create table public.com_listas_preco (
  id bigint generated always as identity primary key,
  codigo text not null,
  codigo_norm text generated always as (public.normalize_catalog_term(codigo)) stored,
  nome text not null,
  descricao text,
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint com_listas_preco_codigo_check check (length(btrim(codigo)) > 0),
  constraint com_listas_preco_nome_check check (length(btrim(nome)) > 0),
  constraint com_listas_preco_codigo_norm_key unique (codigo_norm)
);

create table public.com_lista_preco_versoes (
  id bigint generated always as identity primary key,
  lista_id bigint not null references public.com_listas_preco(id) on delete restrict,
  numero integer not null,
  versao_anterior_id bigint,
  descricao text,
  vigencia_inicio date not null,
  vigencia_fim date,
  motivo text not null,
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_by uuid not null references public.user_profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  constraint com_lista_preco_versoes_numero_check check (numero > 0),
  constraint com_lista_preco_versoes_vigencia_check
    check (vigencia_fim is null or vigencia_fim >= vigencia_inicio),
  constraint com_lista_preco_versoes_motivo_check check (length(btrim(motivo)) >= 10),
  constraint com_lista_preco_versoes_lista_numero_key unique (lista_id, numero),
  constraint com_lista_preco_versoes_lista_id_id_key unique (lista_id, id),
  constraint com_lista_preco_versoes_anterior_key unique (versao_anterior_id),
  constraint com_lista_preco_versoes_anterior_mesma_lista_fk
    foreign key (lista_id, versao_anterior_id)
    references public.com_lista_preco_versoes(lista_id, id) on delete restrict,
  constraint com_lista_preco_versoes_not_self check (versao_anterior_id is distinct from id)
);

create table public.com_lista_preco_versao_itens (
  id bigint generated always as identity primary key,
  versao_id bigint not null references public.com_lista_preco_versoes(id) on delete cascade,
  produto_embalagem_id bigint not null references public.cad_produto_embalagens(id) on delete restrict,
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint com_lista_preco_versao_itens_key unique (versao_id, produto_embalagem_id)
);

create table public.com_lista_preco_versao_precos (
  id bigint generated always as identity primary key,
  versao_item_id bigint not null references public.com_lista_preco_versao_itens(id) on delete cascade,
  prazo_dias integer not null,
  valor_centavos_por_litro bigint not null,
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint com_lista_preco_versao_precos_prazo_check check (prazo_dias >= 0),
  constraint com_lista_preco_versao_precos_valor_check check (valor_centavos_por_litro > 0),
  constraint com_lista_preco_versao_precos_key unique (versao_item_id, prazo_dias)
);

create table public.com_lista_preco_regras (
  id bigint generated always as identity primary key,
  versao_id bigint not null references public.com_lista_preco_versoes(id) on delete cascade,
  codigo text not null,
  codigo_norm text generated always as (public.normalize_catalog_term(codigo)) stored,
  descricao text not null,
  prioridade integer,
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint com_lista_preco_regras_codigo_check check (length(btrim(codigo)) > 0),
  constraint com_lista_preco_regras_descricao_check check (length(btrim(descricao)) > 0),
  constraint com_lista_preco_regras_prioridade_check check (prioridade is null or prioridade >= 0),
  constraint com_lista_preco_regras_key unique (versao_id, codigo_norm)
);

create table public.com_lista_preco_regra_origens (
  regra_id bigint not null references public.com_lista_preco_regras(id) on delete cascade,
  origem_comercial_id bigint not null references public.com_origens_comerciais(id) on delete restrict,
  primary key (regra_id, origem_comercial_id)
);

create table public.com_lista_preco_regra_pessoas (
  regra_id bigint not null references public.com_lista_preco_regras(id) on delete cascade,
  pessoa_papel_id bigint not null references public.cad_pessoa_papeis(id) on delete restrict,
  primary key (regra_id, pessoa_papel_id)
);

create table public.com_lista_preco_regra_areas (
  regra_id bigint not null references public.com_lista_preco_regras(id) on delete cascade,
  area_id bigint not null references public.cad_areas_comerciais(id) on delete restrict,
  primary key (regra_id, area_id)
);

create table public.com_lista_preco_regra_ufs (
  regra_id bigint not null references public.com_lista_preco_regras(id) on delete cascade,
  uf text not null,
  primary key (regra_id, uf),
  constraint com_lista_preco_regra_ufs_check check (
    uf in ('AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA',
           'PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO')
  )
);

create table public.com_lista_preco_regra_clientes (
  regra_id bigint not null references public.com_lista_preco_regras(id) on delete cascade,
  cliente_id bigint not null references public.cad_clientes(id) on delete restrict,
  primary key (regra_id, cliente_id)
);

create table public.com_lista_preco_regra_produtos (
  regra_id bigint not null references public.com_lista_preco_regras(id) on delete cascade,
  produto_id bigint not null references public.cad_produtos_base(id) on delete restrict,
  primary key (regra_id, produto_id)
);

create table public.com_lista_preco_regra_apresentacoes (
  regra_id bigint not null references public.com_lista_preco_regras(id) on delete cascade,
  produto_embalagem_id bigint not null references public.cad_produto_embalagens(id) on delete restrict,
  primary key (regra_id, produto_embalagem_id)
);

create table public.com_lista_preco_publicacoes (
  id bigint generated always as identity primary key,
  versao_id bigint not null unique references public.com_lista_preco_versoes(id) on delete restrict,
  conteudo_hash text not null,
  motivo text not null,
  published_by uuid not null references public.user_profiles(id) on delete restrict,
  published_at timestamptz not null default clock_timestamp(),
  constraint com_lista_preco_publicacoes_hash_check check (conteudo_hash ~ '^[0-9a-f]{32}$'),
  constraint com_lista_preco_publicacoes_motivo_check check (length(btrim(motivo)) >= 10)
);

create table public.com_lista_preco_lifecycle_eventos (
  id bigint generated always as identity primary key,
  publicacao_id bigint not null references public.com_lista_preco_publicacoes(id) on delete restrict,
  tipo text not null,
  publicacao_relacionada_id bigint references public.com_lista_preco_publicacoes(id) on delete restrict,
  efetivo_em date not null,
  motivo text not null,
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  constraint com_lista_preco_lifecycle_tipo_check check (tipo in ('superseded', 'withdrawn')),
  constraint com_lista_preco_lifecycle_motivo_check check (length(btrim(motivo)) >= 10),
  constraint com_lista_preco_lifecycle_relation_check check (
    (tipo = 'superseded' and publicacao_relacionada_id is not null and publicacao_relacionada_id <> publicacao_id)
    or (tipo = 'withdrawn' and publicacao_relacionada_id is null)
  ),
  constraint com_lista_preco_lifecycle_key unique (publicacao_id, tipo)
);

create table public.com_lista_preco_requisicoes (
  idempotency_key uuid primary key,
  tipo_operacao text not null,
  lista_id bigint not null references public.com_listas_preco(id) on delete restrict,
  versao_id bigint not null references public.com_lista_preco_versoes(id) on delete restrict,
  publicacao_id bigint references public.com_lista_preco_publicacoes(id) on delete restrict,
  lifecycle_evento_id bigint references public.com_lista_preco_lifecycle_eventos(id) on delete restrict,
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  payload_hash text not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint com_lista_preco_requisicoes_tipo_check check (
    tipo_operacao in ('lista_criar', 'versao_criar', 'rascunho_substituir', 'publicar', 'retirar')
  ),
  constraint com_lista_preco_requisicoes_hash_check check (payload_hash ~ '^[0-9a-f]{32}$'),
  constraint com_lista_preco_requisicoes_resultado_check check (
    (tipo_operacao in ('lista_criar', 'versao_criar', 'rascunho_substituir')
      and publicacao_id is null and lifecycle_evento_id is null)
    or (tipo_operacao = 'publicar' and publicacao_id is not null and lifecycle_evento_id is null)
    or (tipo_operacao = 'retirar' and publicacao_id is not null and lifecycle_evento_id is not null)
  )
);

create index idx_com_lista_preco_versoes_lista_created
  on public.com_lista_preco_versoes(lista_id, created_at desc);
create index idx_com_lista_preco_itens_apresentacao
  on public.com_lista_preco_versao_itens(produto_embalagem_id, versao_id);
create index idx_com_lista_preco_precos_prazo
  on public.com_lista_preco_versao_precos(prazo_dias, versao_item_id);
create index idx_com_lista_preco_regras_versao_prioridade
  on public.com_lista_preco_regras(versao_id, prioridade, id);
create index idx_com_lista_preco_publicacoes_data
  on public.com_lista_preco_publicacoes(published_at desc, id desc);
create index idx_com_lista_preco_lifecycle_publicacao_data
  on public.com_lista_preco_lifecycle_eventos(publicacao_id, efetivo_em desc, id desc);

create or replace function public.com_lista_preco_versao_documento(p_versao_id bigint)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'versao', jsonb_build_object(
      'id', version.id,
      'lista_id', version.lista_id,
      'numero', version.numero,
      'versao_anterior_id', version.versao_anterior_id,
      'descricao', version.descricao,
      'vigencia_inicio', version.vigencia_inicio,
      'vigencia_fim', version.vigencia_fim
    ),
    'itens', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', item.id,
          'produto_embalagem_id', item.produto_embalagem_id,
          'precos', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'prazo_dias', price.prazo_dias,
                'valor_centavos_por_litro', price.valor_centavos_por_litro
              ) order by price.prazo_dias
            )
              from public.com_lista_preco_versao_precos price
             where price.versao_item_id = item.id
          ), '[]'::jsonb)
        ) order by item.produto_embalagem_id
      )
        from public.com_lista_preco_versao_itens item
       where item.versao_id = version.id
    ), '[]'::jsonb),
    'regras', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', rule.id,
          'codigo', rule.codigo,
          'descricao', rule.descricao,
          'prioridade', rule.prioridade,
          'origens_comerciais', coalesce((select jsonb_agg(scope.origem_comercial_id order by scope.origem_comercial_id) from public.com_lista_preco_regra_origens scope where scope.regra_id = rule.id), '[]'::jsonb),
          'pessoa_papel_ids', coalesce((select jsonb_agg(scope.pessoa_papel_id order by scope.pessoa_papel_id) from public.com_lista_preco_regra_pessoas scope where scope.regra_id = rule.id), '[]'::jsonb),
          'areas_comerciais', coalesce((select jsonb_agg(scope.area_id order by scope.area_id) from public.com_lista_preco_regra_areas scope where scope.regra_id = rule.id), '[]'::jsonb),
          'ufs', coalesce((select jsonb_agg(scope.uf order by scope.uf) from public.com_lista_preco_regra_ufs scope where scope.regra_id = rule.id), '[]'::jsonb),
          'clientes', coalesce((select jsonb_agg(scope.cliente_id order by scope.cliente_id) from public.com_lista_preco_regra_clientes scope where scope.regra_id = rule.id), '[]'::jsonb),
          'produtos', coalesce((select jsonb_agg(scope.produto_id order by scope.produto_id) from public.com_lista_preco_regra_produtos scope where scope.regra_id = rule.id), '[]'::jsonb),
          'apresentacoes', coalesce((select jsonb_agg(scope.produto_embalagem_id order by scope.produto_embalagem_id) from public.com_lista_preco_regra_apresentacoes scope where scope.regra_id = rule.id), '[]'::jsonb)
        ) order by rule.codigo_norm
      )
        from public.com_lista_preco_regras rule
       where rule.versao_id = version.id
    ), '[]'::jsonb)
  )
    from public.com_lista_preco_versoes version
   where version.id = p_versao_id;
$$;

create or replace view public.com_lista_preco_publicacoes_estado
with (security_invoker = true)
as
select
  publication.id as publicacao_id,
  version.lista_id,
  publication.versao_id,
  version.numero,
  version.vigencia_inicio,
  version.vigencia_fim,
  publication.published_at,
  case
    when exists (
      select 1 from public.com_lista_preco_lifecycle_eventos event
       where event.publicacao_id = publication.id
         and event.tipo = 'withdrawn'
         and event.efetivo_em <= current_date
    ) then 'retirada'
    when exists (
      select 1 from public.com_lista_preco_lifecycle_eventos event
       where event.publicacao_id = publication.id
         and event.tipo = 'superseded'
         and event.efetivo_em <= current_date
    ) then 'sucedida'
    when current_date < version.vigencia_inicio then 'programada'
    when version.vigencia_fim is not null and current_date > version.vigencia_fim then 'expirada'
    else 'vigente'
  end as situacao
from public.com_lista_preco_publicacoes publication
join public.com_lista_preco_versoes version on version.id = publication.versao_id;

create or replace function public.prevent_com_lista_preco_fact_changes()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception '% e append-only', tg_table_name;
end;
$$;

create or replace function public.protect_com_lista_preco_published_content()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_old_versao_id bigint;
  v_new_versao_id bigint;
begin
  if tg_argv[0] not in ('version', 'item', 'price', 'rule', 'scope') then
    raise exception 'invalid price list immutable trigger configuration';
  end if;

  if tg_op in ('UPDATE', 'DELETE') then
    if tg_argv[0] = 'version' then
      v_old_versao_id := old.id;
    elsif tg_argv[0] = 'item' then
      v_old_versao_id := old.versao_id;
    elsif tg_argv[0] = 'price' then
      select item.versao_id into v_old_versao_id
        from public.com_lista_preco_versao_itens item
       where item.id = old.versao_item_id;
    elsif tg_argv[0] = 'rule' then
      v_old_versao_id := old.versao_id;
    elsif tg_argv[0] = 'scope' then
      select rule.versao_id into v_old_versao_id
        from public.com_lista_preco_regras rule
       where rule.id = old.regra_id;
    end if;
  end if;

  if tg_op in ('INSERT', 'UPDATE') then
    if tg_argv[0] = 'version' then
      v_new_versao_id := new.id;
    elsif tg_argv[0] = 'item' then
      v_new_versao_id := new.versao_id;
    elsif tg_argv[0] = 'price' then
      select item.versao_id into v_new_versao_id
        from public.com_lista_preco_versao_itens item
       where item.id = new.versao_item_id;
    elsif tg_argv[0] = 'rule' then
      v_new_versao_id := new.versao_id;
    elsif tg_argv[0] = 'scope' then
      select rule.versao_id into v_new_versao_id
        from public.com_lista_preco_regras rule
       where rule.id = new.regra_id;
    end if;
  end if;

  if exists (
    select 1 from public.com_lista_preco_publicacoes publication
     where publication.versao_id in (v_old_versao_id, v_new_versao_id)
  ) then
    raise exception 'versao publicada e imutavel; crie uma nova versao';
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger trg_com_lista_preco_versoes_published_immutable
before insert or update or delete on public.com_lista_preco_versoes
for each row execute function public.protect_com_lista_preco_published_content('version');
create trigger trg_com_lista_preco_itens_published_immutable
before insert or update or delete on public.com_lista_preco_versao_itens
for each row execute function public.protect_com_lista_preco_published_content('item');
create trigger trg_com_lista_preco_precos_published_immutable
before insert or update or delete on public.com_lista_preco_versao_precos
for each row execute function public.protect_com_lista_preco_published_content('price');
create trigger trg_com_lista_preco_regras_published_immutable
before insert or update or delete on public.com_lista_preco_regras
for each row execute function public.protect_com_lista_preco_published_content('rule');

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'com_lista_preco_regra_origens',
    'com_lista_preco_regra_pessoas',
    'com_lista_preco_regra_areas',
    'com_lista_preco_regra_ufs',
    'com_lista_preco_regra_clientes',
    'com_lista_preco_regra_produtos',
    'com_lista_preco_regra_apresentacoes'
  ] loop
    execute format(
      'create trigger %I before insert or update or delete on public.%I for each row execute function public.protect_com_lista_preco_published_content(''scope'')',
      'trg_' || v_table || '_published_immutable', v_table
    );
  end loop;
end;
$$;

create trigger trg_com_lista_preco_publicacoes_append_only
before update or delete on public.com_lista_preco_publicacoes
for each row execute function public.prevent_com_lista_preco_fact_changes();
create trigger trg_com_lista_preco_lifecycle_append_only
before update or delete on public.com_lista_preco_lifecycle_eventos
for each row execute function public.prevent_com_lista_preco_fact_changes();
create trigger trg_com_lista_preco_requisicoes_append_only
before update or delete on public.com_lista_preco_requisicoes
for each row execute function public.prevent_com_lista_preco_fact_changes();

create trigger trg_com_lista_preco_publicacoes_no_truncate
before truncate on public.com_lista_preco_publicacoes
for each statement execute function public.prevent_com_lista_preco_fact_changes();
create trigger trg_com_lista_preco_lifecycle_no_truncate
before truncate on public.com_lista_preco_lifecycle_eventos
for each statement execute function public.prevent_com_lista_preco_fact_changes();
create trigger trg_com_lista_preco_requisicoes_no_truncate
before truncate on public.com_lista_preco_requisicoes
for each statement execute function public.prevent_com_lista_preco_fact_changes();

create or replace function public.create_com_lista_preco_rascunho_idempotente(
  p_idempotency_key uuid,
  p_codigo text,
  p_nome text,
  p_descricao text,
  p_vigencia_inicio date,
  p_vigencia_fim date,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_context jsonb;
  v_actor uuid;
  v_payload_hash text;
  v_existing public.com_lista_preco_requisicoes%rowtype;
  v_lista_id bigint;
  v_versao_id bigint;
begin
  v_context := public.begin_audited_rpc(
    'pedidos.price_lists.draft.manage', 'pedidos', 'com_lista_preco_versoes',
    'change_type', jsonb_build_object('correlation_id', coalesce(p_idempotency_key::text, 'missing'))
  );
  if p_idempotency_key is null then raise exception 'chave de idempotencia e obrigatoria'; end if;
  if public.normalize_catalog_term(p_codigo) is null then raise exception 'codigo da lista e obrigatorio'; end if;
  if public.normalize_catalog_term(p_nome) is null then raise exception 'nome da lista e obrigatorio'; end if;
  if p_vigencia_inicio is null then raise exception 'inicio da vigencia e obrigatorio'; end if;
  if p_vigencia_fim is not null and p_vigencia_fim < p_vigencia_inicio then raise exception 'fim da vigencia e invalido'; end if;
  if length(btrim(coalesce(p_motivo, ''))) < 10 then raise exception 'motivo deve ter ao menos 10 caracteres'; end if;

  v_actor := public.current_actor_id();
  v_payload_hash := md5(jsonb_build_object(
    'tipo', 'lista_criar', 'codigo', upper(btrim(p_codigo)), 'nome', btrim(p_nome),
    'descricao', nullif(btrim(p_descricao), ''), 'vigencia_inicio', p_vigencia_inicio,
    'vigencia_fim', p_vigencia_fim, 'motivo', btrim(p_motivo)
  )::text);
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing from public.com_lista_preco_requisicoes request
   where request.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.tipo_operacao <> 'lista_criar'
       or v_existing.actor_id is distinct from v_actor
       or v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'chave de idempotencia reutilizada com conteudo diferente';
    end if;
    return v_existing.versao_id;
  end if;

  perform pg_advisory_xact_lock(hashtextextended('price_list:' || public.normalize_catalog_term(p_codigo), 0));
  insert into public.com_listas_preco(codigo, nome, descricao, created_by)
  values (upper(btrim(p_codigo)), btrim(p_nome), nullif(btrim(p_descricao), ''), v_actor)
  returning id into v_lista_id;

  insert into public.com_lista_preco_versoes(
    lista_id, numero, descricao, vigencia_inicio, vigencia_fim, motivo,
    created_by, updated_by
  ) values (
    v_lista_id, 1, nullif(btrim(p_descricao), ''), p_vigencia_inicio, p_vigencia_fim,
    btrim(p_motivo), v_actor, v_actor
  ) returning id into v_versao_id;

  insert into public.com_lista_preco_requisicoes(
    idempotency_key, tipo_operacao, lista_id, versao_id, actor_id, payload_hash
  ) values (p_idempotency_key, 'lista_criar', v_lista_id, v_versao_id, v_actor, v_payload_hash);

  perform public.log_audited_rpc_change(
    'pedidos', 'com_lista_preco_versoes', v_versao_id::text,
    'pedidos.lista_preco_rascunho_criado', 'pedidos.price_lists.draft.manage', v_context,
    null, public.com_lista_preco_versao_documento(v_versao_id),
    jsonb_build_object('lista_id', v_lista_id, 'source', 'create_com_lista_preco_rascunho_idempotente')
  );
  return v_versao_id;
end;
$$;

create or replace function public.create_com_lista_preco_versao_idempotente(
  p_idempotency_key uuid,
  p_lista_id bigint,
  p_vigencia_inicio date,
  p_vigencia_fim date,
  p_descricao text,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_context jsonb;
  v_actor uuid;
  v_payload_hash text;
  v_existing public.com_lista_preco_requisicoes%rowtype;
  v_versao_id bigint;
  v_numero integer;
  v_anterior_id bigint;
begin
  v_context := public.begin_audited_rpc(
    'pedidos.price_lists.draft.manage', 'pedidos', 'com_lista_preco_versoes',
    'change_type', jsonb_build_object('correlation_id', coalesce(p_idempotency_key::text, 'missing'))
  );
  if p_idempotency_key is null then raise exception 'chave de idempotencia e obrigatoria'; end if;
  if p_lista_id is null then raise exception 'lista e obrigatoria'; end if;
  if p_vigencia_inicio is null then raise exception 'inicio da vigencia e obrigatorio'; end if;
  if p_vigencia_fim is not null and p_vigencia_fim < p_vigencia_inicio then raise exception 'fim da vigencia e invalido'; end if;
  if length(btrim(coalesce(p_motivo, ''))) < 10 then raise exception 'motivo deve ter ao menos 10 caracteres'; end if;

  v_actor := public.current_actor_id();
  v_payload_hash := md5(jsonb_build_object(
    'tipo', 'versao_criar', 'lista_id', p_lista_id, 'vigencia_inicio', p_vigencia_inicio,
    'vigencia_fim', p_vigencia_fim, 'descricao', nullif(btrim(p_descricao), ''),
    'motivo', btrim(p_motivo)
  )::text);
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing from public.com_lista_preco_requisicoes request
   where request.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.tipo_operacao <> 'versao_criar'
       or v_existing.actor_id is distinct from v_actor
       or v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'chave de idempotencia reutilizada com conteudo diferente';
    end if;
    return v_existing.versao_id;
  end if;

  perform pg_advisory_xact_lock(hashtextextended('price_list_id:' || p_lista_id::text, 0));
  perform 1 from public.com_listas_preco where id = p_lista_id;
  if not found then raise exception 'lista de preco nao encontrada'; end if;
  if exists (
    select 1 from public.com_lista_preco_versoes version
     where version.lista_id = p_lista_id
       and not exists (select 1 from public.com_lista_preco_publicacoes publication where publication.versao_id = version.id)
  ) then raise exception 'a lista ja possui um rascunho em aberto'; end if;

  select version.id, version.numero + 1 into v_anterior_id, v_numero
    from public.com_lista_preco_versoes version
   where version.lista_id = p_lista_id
     and exists (select 1 from public.com_lista_preco_publicacoes publication where publication.versao_id = version.id)
   order by version.numero desc limit 1;
  if v_anterior_id is null then raise exception 'a lista ainda nao possui versao publicada'; end if;

  insert into public.com_lista_preco_versoes(
    lista_id, numero, versao_anterior_id, descricao, vigencia_inicio, vigencia_fim,
    motivo, created_by, updated_by
  ) values (
    p_lista_id, v_numero, v_anterior_id, nullif(btrim(p_descricao), ''),
    p_vigencia_inicio, p_vigencia_fim, btrim(p_motivo), v_actor, v_actor
  ) returning id into v_versao_id;

  insert into public.com_lista_preco_requisicoes(
    idempotency_key, tipo_operacao, lista_id, versao_id, actor_id, payload_hash
  ) values (p_idempotency_key, 'versao_criar', p_lista_id, v_versao_id, v_actor, v_payload_hash);
  perform public.log_audited_rpc_change(
    'pedidos', 'com_lista_preco_versoes', v_versao_id::text,
    'pedidos.lista_preco_versao_criada', 'pedidos.price_lists.draft.manage', v_context,
    null, public.com_lista_preco_versao_documento(v_versao_id),
    jsonb_build_object('lista_id', p_lista_id, 'versao_anterior_id', v_anterior_id)
  );
  return v_versao_id;
end;
$$;

create or replace function public.replace_com_lista_preco_rascunho_idempotente(
  p_idempotency_key uuid,
  p_versao_id bigint,
  p_vigencia_inicio date,
  p_vigencia_fim date,
  p_descricao text,
  p_itens jsonb,
  p_regras jsonb,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_context jsonb;
  v_actor uuid;
  v_payload_hash text;
  v_existing public.com_lista_preco_requisicoes%rowtype;
  v_lista_id bigint;
  v_before jsonb;
  v_item jsonb;
  v_price jsonb;
  v_rule jsonb;
  v_value text;
  v_item_id bigint;
  v_rule_id bigint;
begin
  v_context := public.begin_audited_rpc(
    'pedidos.price_lists.draft.manage', 'pedidos', 'com_lista_preco_versoes',
    'field_risk', jsonb_build_object('correlation_id', coalesce(p_idempotency_key::text, 'missing'))
  );
  if p_idempotency_key is null then raise exception 'chave de idempotencia e obrigatoria'; end if;
  if p_versao_id is null then raise exception 'versao e obrigatoria'; end if;
  if p_vigencia_inicio is null then raise exception 'inicio da vigencia e obrigatorio'; end if;
  if p_vigencia_fim is not null and p_vigencia_fim < p_vigencia_inicio then raise exception 'fim da vigencia e invalido'; end if;
  if jsonb_typeof(p_itens) <> 'array' or jsonb_typeof(p_regras) <> 'array' then
    raise exception 'itens e regras devem ser listas';
  end if;
  if length(btrim(coalesce(p_motivo, ''))) < 10 then raise exception 'motivo deve ter ao menos 10 caracteres'; end if;

  v_actor := public.current_actor_id();
  v_payload_hash := md5(jsonb_build_object(
    'tipo', 'rascunho_substituir', 'versao_id', p_versao_id,
    'vigencia_inicio', p_vigencia_inicio, 'vigencia_fim', p_vigencia_fim,
    'descricao', nullif(btrim(p_descricao), ''), 'itens', p_itens,
    'regras', p_regras, 'motivo', btrim(p_motivo)
  )::text);
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing from public.com_lista_preco_requisicoes request
   where request.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.tipo_operacao <> 'rascunho_substituir'
       or v_existing.actor_id is distinct from v_actor
       or v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'chave de idempotencia reutilizada com conteudo diferente';
    end if;
    return v_existing.versao_id;
  end if;

  perform pg_advisory_xact_lock(hashtextextended('price_list_version:' || p_versao_id::text, 0));
  select version.lista_id into v_lista_id
    from public.com_lista_preco_versoes version where version.id = p_versao_id for update;
  if not found then raise exception 'versao de lista nao encontrada'; end if;
  if exists (select 1 from public.com_lista_preco_publicacoes publication where publication.versao_id = p_versao_id) then
    raise exception 'versao publicada e imutavel; crie uma nova versao';
  end if;
  v_before := public.com_lista_preco_versao_documento(p_versao_id);

  delete from public.com_lista_preco_regras where versao_id = p_versao_id;
  delete from public.com_lista_preco_versao_itens where versao_id = p_versao_id;
  update public.com_lista_preco_versoes
     set vigencia_inicio = p_vigencia_inicio,
         vigencia_fim = p_vigencia_fim,
         descricao = nullif(btrim(p_descricao), ''),
         motivo = btrim(p_motivo),
         updated_by = v_actor,
         updated_at = clock_timestamp()
   where id = p_versao_id;

  for v_item in select value from jsonb_array_elements(p_itens)
  loop
    insert into public.com_lista_preco_versao_itens(
      versao_id, produto_embalagem_id, created_by
    ) values (
      p_versao_id, (v_item->>'produto_embalagem_id')::bigint, v_actor
    ) returning id into v_item_id;
    if jsonb_typeof(v_item->'precos') <> 'array' then raise exception 'precos do item devem ser uma lista'; end if;
    for v_price in select value from jsonb_array_elements(v_item->'precos')
    loop
      insert into public.com_lista_preco_versao_precos(
        versao_item_id, prazo_dias, valor_centavos_por_litro, created_by
      ) values (
        v_item_id, (v_price->>'prazo_dias')::integer,
        (v_price->>'valor_centavos_por_litro')::bigint, v_actor
      );
    end loop;
  end loop;

  for v_rule in select value from jsonb_array_elements(p_regras)
  loop
    insert into public.com_lista_preco_regras(
      versao_id, codigo, descricao, prioridade, created_by
    ) values (
      p_versao_id, btrim(v_rule->>'codigo'), btrim(v_rule->>'descricao'),
      nullif(v_rule->>'prioridade', '')::integer, v_actor
    ) returning id into v_rule_id;

    for v_value in select value from jsonb_array_elements_text(coalesce(v_rule->'origens_comerciais', '[]'::jsonb))
    loop insert into public.com_lista_preco_regra_origens values (v_rule_id, v_value::bigint); end loop;
    for v_value in select value from jsonb_array_elements_text(coalesce(v_rule->'pessoa_papel_ids', '[]'::jsonb))
    loop insert into public.com_lista_preco_regra_pessoas values (v_rule_id, v_value::bigint); end loop;
    for v_value in select value from jsonb_array_elements_text(coalesce(v_rule->'areas_comerciais', '[]'::jsonb))
    loop insert into public.com_lista_preco_regra_areas values (v_rule_id, v_value::bigint); end loop;
    for v_value in select value from jsonb_array_elements_text(coalesce(v_rule->'ufs', '[]'::jsonb))
    loop insert into public.com_lista_preco_regra_ufs values (v_rule_id, upper(btrim(v_value))); end loop;
    for v_value in select value from jsonb_array_elements_text(coalesce(v_rule->'clientes', '[]'::jsonb))
    loop insert into public.com_lista_preco_regra_clientes values (v_rule_id, v_value::bigint); end loop;
    for v_value in select value from jsonb_array_elements_text(coalesce(v_rule->'produtos', '[]'::jsonb))
    loop insert into public.com_lista_preco_regra_produtos values (v_rule_id, v_value::bigint); end loop;
    for v_value in select value from jsonb_array_elements_text(coalesce(v_rule->'apresentacoes', '[]'::jsonb))
    loop insert into public.com_lista_preco_regra_apresentacoes values (v_rule_id, v_value::bigint); end loop;
  end loop;

  insert into public.com_lista_preco_requisicoes(
    idempotency_key, tipo_operacao, lista_id, versao_id, actor_id, payload_hash
  ) values (p_idempotency_key, 'rascunho_substituir', v_lista_id, p_versao_id, v_actor, v_payload_hash);
  perform public.log_audited_rpc_change(
    'pedidos', 'com_lista_preco_versoes', p_versao_id::text,
    'pedidos.lista_preco_rascunho_substituido', 'pedidos.price_lists.draft.manage', v_context,
    v_before, public.com_lista_preco_versao_documento(p_versao_id),
    jsonb_build_object('source', 'replace_com_lista_preco_rascunho_idempotente')
  );
  return p_versao_id;
end;
$$;

create or replace function public.publish_com_lista_preco_versao_idempotente(
  p_idempotency_key uuid,
  p_versao_id bigint,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_context jsonb;
  v_actor uuid;
  v_payload_hash text;
  v_existing public.com_lista_preco_requisicoes%rowtype;
  v_version public.com_lista_preco_versoes%rowtype;
  v_document jsonb;
  v_publicacao_id bigint;
  v_previous_publication_id bigint;
begin
  v_context := public.begin_audited_rpc(
    'pedidos.price_lists.publish', 'pedidos', 'com_lista_preco_publicacoes',
    'status_transition', jsonb_build_object('correlation_id', coalesce(p_idempotency_key::text, 'missing'))
  );
  if p_idempotency_key is null then raise exception 'chave de idempotencia e obrigatoria'; end if;
  if p_versao_id is null then raise exception 'versao e obrigatoria'; end if;
  if length(btrim(coalesce(p_motivo, ''))) < 10 then raise exception 'motivo deve ter ao menos 10 caracteres'; end if;
  v_actor := public.current_actor_id();
  v_payload_hash := md5(jsonb_build_object(
    'tipo', 'publicar', 'versao_id', p_versao_id, 'motivo', btrim(p_motivo)
  )::text);
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing from public.com_lista_preco_requisicoes request
   where request.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.tipo_operacao <> 'publicar'
       or v_existing.actor_id is distinct from v_actor
       or v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'chave de idempotencia reutilizada com conteudo diferente';
    end if;
    return v_existing.publicacao_id;
  end if;

  select * into v_version from public.com_lista_preco_versoes version
   where version.id = p_versao_id for update;
  if not found then raise exception 'versao de lista nao encontrada'; end if;
  perform pg_advisory_xact_lock(hashtextextended('price_list_id:' || v_version.lista_id::text, 0));
  if exists (select 1 from public.com_lista_preco_publicacoes publication where publication.versao_id = p_versao_id) then
    raise exception 'versao ja publicada';
  end if;
  if not exists (select 1 from public.com_lista_preco_versao_itens item where item.versao_id = p_versao_id) then
    raise exception 'publicacao exige ao menos uma apresentacao coberta';
  end if;
  if exists (
    select 1 from public.com_lista_preco_versao_itens item
     where item.versao_id = p_versao_id
       and not exists (select 1 from public.com_lista_preco_versao_precos price where price.versao_item_id = item.id)
  ) then raise exception 'apresentacao coberta sem faixa de preco'; end if;
  if not exists (select 1 from public.com_lista_preco_regras rule where rule.versao_id = p_versao_id) then
    raise exception 'publicacao exige ao menos uma regra de elegibilidade';
  end if;
  if exists (
    select 1
      from public.com_lista_preco_regra_apresentacoes scope
      join public.com_lista_preco_regras rule on rule.id = scope.regra_id
     where rule.versao_id = p_versao_id
       and not exists (
         select 1 from public.com_lista_preco_versao_itens item
          where item.versao_id = p_versao_id
            and item.produto_embalagem_id = scope.produto_embalagem_id
       )
  ) then raise exception 'escopo de apresentacao fora da cobertura publicada'; end if;
  if exists (
    select 1
      from public.com_lista_preco_regra_apresentacoes presentation_scope
      join public.com_lista_preco_regras rule on rule.id = presentation_scope.regra_id
      join public.cad_produto_embalagens presentation on presentation.id = presentation_scope.produto_embalagem_id
     where rule.versao_id = p_versao_id
       and exists (select 1 from public.com_lista_preco_regra_produtos product_scope where product_scope.regra_id = rule.id)
       and not exists (
         select 1 from public.com_lista_preco_regra_produtos product_scope
          where product_scope.regra_id = rule.id and product_scope.produto_id = presentation.produto_id
       )
  ) then raise exception 'escopos de produto e apresentacao sao contraditorios'; end if;
  if exists (
    select 1
      from public.com_lista_preco_versao_itens item
      join public.cad_produto_embalagens presentation on presentation.id = item.produto_embalagem_id
      join public.cad_produtos_base product on product.id = presentation.produto_id
     where item.versao_id = p_versao_id
       and (presentation.status <> 'active' or product.status <> 'active')
  ) then raise exception 'publicacao contem apresentacao ou produto inativo'; end if;
  if exists (
    select 1
      from public.com_lista_preco_regra_pessoas scope
      join public.cad_pessoa_papeis role on role.id = scope.pessoa_papel_id
      join public.cad_pessoas_comerciais person on person.id = role.pessoa_id
      join public.com_lista_preco_regras rule on rule.id = scope.regra_id
     where rule.versao_id = p_versao_id and (role.status <> 'active' or person.status <> 'active')
  ) then raise exception 'publicacao contem pessoa ou papel inativo'; end if;

  if v_version.versao_anterior_id is not null then
    select publication.id into v_previous_publication_id
      from public.com_lista_preco_publicacoes publication
     where publication.versao_id = v_version.versao_anterior_id;
    if v_previous_publication_id is null then raise exception 'versao anterior ainda nao foi publicada'; end if;
    if v_version.vigencia_inicio < (clock_timestamp() at time zone 'America/Sao_Paulo')::date then
      raise exception 'publicacao sucessora nao permite vigencia retroativa';
    end if;
  elsif exists (
    select 1 from public.com_lista_preco_publicacoes publication
    join public.com_lista_preco_versoes version on version.id = publication.versao_id
    where version.lista_id = v_version.lista_id
  ) then raise exception 'nova publicacao deve suceder a versao publicada anterior'; end if;

  v_document := public.com_lista_preco_versao_documento(p_versao_id);
  insert into public.com_lista_preco_publicacoes(
    versao_id, conteudo_hash, motivo, published_by
  ) values (p_versao_id, md5(v_document::text), btrim(p_motivo), v_actor)
  returning id into v_publicacao_id;

  if v_previous_publication_id is not null then
    insert into public.com_lista_preco_lifecycle_eventos(
      publicacao_id, tipo, publicacao_relacionada_id, efetivo_em, motivo, created_by
    ) values (
      v_previous_publication_id, 'superseded', v_publicacao_id,
      v_version.vigencia_inicio, btrim(p_motivo), v_actor
    );
  end if;

  insert into public.com_lista_preco_requisicoes(
    idempotency_key, tipo_operacao, lista_id, versao_id, publicacao_id,
    actor_id, payload_hash
  ) values (
    p_idempotency_key, 'publicar', v_version.lista_id, p_versao_id,
    v_publicacao_id, v_actor, v_payload_hash
  );
  perform public.log_audited_rpc_change(
    'pedidos', 'com_lista_preco_publicacoes', v_publicacao_id::text,
    'pedidos.lista_preco_publicada', 'pedidos.price_lists.publish', v_context,
    null, jsonb_build_object('publicacao_id', v_publicacao_id, 'versao', v_document),
    jsonb_build_object('conteudo_hash', md5(v_document::text), 'versao_anterior_publicacao_id', v_previous_publication_id)
  );
  return v_publicacao_id;
end;
$$;

create or replace function public.withdraw_com_lista_preco_publicacao_idempotente(
  p_idempotency_key uuid,
  p_publicacao_id bigint,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_context jsonb;
  v_actor uuid;
  v_payload_hash text;
  v_existing public.com_lista_preco_requisicoes%rowtype;
  v_lista_id bigint;
  v_versao_id bigint;
  v_event_id bigint;
begin
  v_context := public.begin_audited_rpc(
    'pedidos.price_lists.withdraw', 'pedidos', 'com_lista_preco_lifecycle_eventos',
    'status_transition', jsonb_build_object('correlation_id', coalesce(p_idempotency_key::text, 'missing'))
  );
  if p_idempotency_key is null then raise exception 'chave de idempotencia e obrigatoria'; end if;
  if p_publicacao_id is null then raise exception 'publicacao e obrigatoria'; end if;
  if length(btrim(coalesce(p_motivo, ''))) < 10 then raise exception 'motivo deve ter ao menos 10 caracteres'; end if;
  v_actor := public.current_actor_id();
  v_payload_hash := md5(jsonb_build_object(
    'tipo', 'retirar', 'publicacao_id', p_publicacao_id, 'motivo', btrim(p_motivo)
  )::text);
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing from public.com_lista_preco_requisicoes request
   where request.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.tipo_operacao <> 'retirar'
       or v_existing.actor_id is distinct from v_actor
       or v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'chave de idempotencia reutilizada com conteudo diferente';
    end if;
    return v_existing.lifecycle_evento_id;
  end if;

  select version.lista_id, publication.versao_id into v_lista_id, v_versao_id
    from public.com_lista_preco_publicacoes publication
    join public.com_lista_preco_versoes version on version.id = publication.versao_id
   where publication.id = p_publicacao_id for update;
  if not found then raise exception 'publicacao de lista nao encontrada'; end if;
  perform pg_advisory_xact_lock(hashtextextended('price_list_id:' || v_lista_id::text, 0));
  if exists (
    select 1 from public.com_lista_preco_lifecycle_eventos event
     where event.publicacao_id = p_publicacao_id and event.tipo = 'withdrawn'
  ) then raise exception 'publicacao ja retirada'; end if;

  insert into public.com_lista_preco_lifecycle_eventos(
    publicacao_id, tipo, efetivo_em, motivo, created_by
  ) values (p_publicacao_id, 'withdrawn', current_date, btrim(p_motivo), v_actor)
  returning id into v_event_id;
  insert into public.com_lista_preco_requisicoes(
    idempotency_key, tipo_operacao, lista_id, versao_id, publicacao_id,
    lifecycle_evento_id, actor_id, payload_hash
  ) values (
    p_idempotency_key, 'retirar', v_lista_id, v_versao_id, p_publicacao_id,
    v_event_id, v_actor, v_payload_hash
  );
  perform public.log_audited_rpc_change(
    'pedidos', 'com_lista_preco_lifecycle_eventos', v_event_id::text,
    'pedidos.lista_preco_retirada', 'pedidos.price_lists.withdraw', v_context,
    null, jsonb_build_object('publicacao_id', p_publicacao_id, 'tipo', 'withdrawn', 'efetivo_em', current_date),
    jsonb_build_object('motivo', btrim(p_motivo))
  );
  return v_event_id;
end;
$$;

create or replace function public.consultar_com_lista_preco_versao(p_versao_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_document jsonb;
  v_publication jsonb;
begin
  perform public.require_current_user_permission('pedidos.price_lists.view');
  v_document := public.com_lista_preco_versao_documento(p_versao_id);
  if v_document is null then raise exception 'versao de lista nao encontrada'; end if;
  select to_jsonb(state) into v_publication
    from public.com_lista_preco_publicacoes_estado state
   where state.versao_id = p_versao_id;
  return jsonb_build_object('documento', v_document, 'publicacao', v_publication);
end;
$$;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'com_origens_comerciais', 'com_listas_preco', 'com_lista_preco_versoes',
    'com_lista_preco_versao_itens', 'com_lista_preco_versao_precos',
    'com_lista_preco_regras', 'com_lista_preco_regra_origens',
    'com_lista_preco_regra_pessoas', 'com_lista_preco_regra_areas',
    'com_lista_preco_regra_ufs', 'com_lista_preco_regra_clientes',
    'com_lista_preco_regra_produtos', 'com_lista_preco_regra_apresentacoes',
    'com_lista_preco_publicacoes', 'com_lista_preco_lifecycle_eventos',
    'com_lista_preco_requisicoes'
  ] loop
    execute format('alter table public.%I enable row level security', v_table);
    execute format('revoke all on table public.%I from public, anon, authenticated', v_table);
  end loop;
end;
$$;

revoke all on function public.com_lista_preco_versao_documento(bigint) from public, anon, authenticated;
revoke all on function public.prevent_com_lista_preco_fact_changes() from public, anon, authenticated;
revoke all on function public.protect_com_lista_preco_published_content() from public, anon, authenticated;
revoke all on function public.create_com_lista_preco_rascunho_idempotente(uuid, text, text, text, date, date, text) from public, anon;
revoke all on function public.create_com_lista_preco_versao_idempotente(uuid, bigint, date, date, text, text) from public, anon;
revoke all on function public.replace_com_lista_preco_rascunho_idempotente(uuid, bigint, date, date, text, jsonb, jsonb, text) from public, anon;
revoke all on function public.publish_com_lista_preco_versao_idempotente(uuid, bigint, text) from public, anon;
revoke all on function public.withdraw_com_lista_preco_publicacao_idempotente(uuid, bigint, text) from public, anon;
revoke all on function public.consultar_com_lista_preco_versao(bigint) from public, anon;

grant execute on function public.create_com_lista_preco_rascunho_idempotente(uuid, text, text, text, date, date, text) to authenticated;
grant execute on function public.create_com_lista_preco_versao_idempotente(uuid, bigint, date, date, text, text) to authenticated;
grant execute on function public.replace_com_lista_preco_rascunho_idempotente(uuid, bigint, date, date, text, jsonb, jsonb, text) to authenticated;
grant execute on function public.publish_com_lista_preco_versao_idempotente(uuid, bigint, text) to authenticated;
grant execute on function public.withdraw_com_lista_preco_publicacao_idempotente(uuid, bigint, text) to authenticated;
grant execute on function public.consultar_com_lista_preco_versao(bigint) to authenticated;

comment on table public.com_origens_comerciais is
  'Catalogo governado de origem comercial. A origem futura e fato explicito da operacao, nunca inferencia de relacionamento.';
comment on table public.com_lista_preco_versao_itens is
  'Cobertura explicita por apresentacao canonica. Ausencia significa que a lista nao e candidata para a apresentacao.';
comment on table public.com_lista_preco_versao_precos is
  'Precos comerciais publicados em centavos de BRL por litro. Prazo zero representa pagamento a vista.';
comment on table public.com_lista_preco_regras is
  'Regras alternativas de elegibilidade. Dimensoes associadas usam AND; valores na mesma dimensao usam OR; dimensao vazia e curinga.';
comment on table public.com_lista_preco_regra_pessoas is
  'Escopo extensivel por atribuicao canonica de pessoa e papel, sem tabelas rigidas por agente, vendedor ou gerente.';
comment on table public.com_lista_preco_publicacoes is
  'Fonte canonica unica do fato de publicacao de uma versao imutavel de lista de preco.';
comment on table public.com_lista_preco_lifecycle_eventos is
  'Ledger append-only de fatos posteriores a publicacao: sucessao e retirada. Nao duplica o fato de publicacao.';
comment on function public.replace_com_lista_preco_rascunho_idempotente(uuid, bigint, date, date, text, jsonb, jsonb, text) is
  'Substitui atomicamente o agregado de um rascunho. JSON e somente transporte; identidades sao persistidas em tabelas relacionais com FKs reais.';
comment on function public.publish_com_lista_preco_versao_idempotente(uuid, bigint, text) is
  'Publica uma versao validada e a torna imutavel. Nao resolve PMP, Pedido, desconto, COMM ou overprice.';
