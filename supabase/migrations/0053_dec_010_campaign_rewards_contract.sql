-- DEC-010: versioned campaigns and separate append-only ledgers for points,
-- rewards, vouchers and financial payout events.

create table public.cad_grupos_produto (
  id bigint generated always as identity primary key,
  codigo text not null,
  codigo_norm text generated always as (public.normalize_catalog_term(codigo)) stored,
  nome text not null,
  status text not null default 'pending_review',
  origem_dados text not null default 'sistema',
  source_batch_id bigint references public.migration_batches(id),
  source_row_id bigint references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint cad_grupos_produto_codigo_check check (codigo_norm is not null),
  constraint cad_grupos_produto_nome_check check (nullif(btrim(nome), '') is not null),
  constraint cad_grupos_produto_status_check check (
    status in ('active', 'inactive', 'pending_review')
  ),
  constraint cad_grupos_produto_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  constraint cad_grupos_produto_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  ),
  constraint cad_grupos_produto_key unique (codigo_norm)
);

create unique index idx_cad_grupos_produto_source_once
  on public.cad_grupos_produto(source_batch_id, source_row_id)
  where origem_dados = 'excel_legado';

alter table public.cad_produtos_base
  add column if not exists grupo_id bigint;

do $$
declare
  v_actor uuid := public.historical_migration_actor_id();
  v_group text;
begin
  if v_actor is null then
    raise exception 'Migracao Historica system actor is required by DEC-010';
  end if;

  for v_group in
    select distinct nullif(btrim(product.grupo), '')
      from public.cad_produtos_base product
     where nullif(btrim(product.grupo), '') is not null
  loop
    insert into public.cad_grupos_produto(
      codigo, nome, status, origem_dados, created_by
    ) values (
      v_group, v_group, 'active', 'sistema', v_actor
    ) on conflict (codigo_norm) do nothing;
  end loop;
end;
$$;

update public.cad_produtos_base product
   set grupo_id = group_catalog.id
  from public.cad_grupos_produto group_catalog
 where group_catalog.codigo_norm = public.normalize_catalog_term(product.grupo)
   and product.grupo_id is null;

alter table public.cad_produtos_base
  add constraint cad_produtos_grupo_fk foreign key (grupo_id)
    references public.cad_grupos_produto(id) not valid,
  add constraint cad_produtos_grupo_pair_check check (
    grupo is null or grupo_id is not null or status = 'pending_review'
  );
alter table public.cad_produtos_base validate constraint cad_produtos_grupo_fk;

create table public.com_campanhas (
  id bigint generated always as identity primary key,
  codigo text not null,
  codigo_norm text generated always as (public.normalize_catalog_term(codigo)) stored,
  nome text not null,
  status text not null default 'pending_review',
  origem_dados text not null default 'sistema',
  source_batch_id bigint references public.migration_batches(id),
  source_row_id bigint references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint com_campanhas_codigo_check check (codigo_norm is not null),
  constraint com_campanhas_nome_check check (nullif(btrim(nome), '') is not null),
  constraint com_campanhas_status_check check (
    status in ('draft', 'active', 'closed', 'cancelled', 'pending_review')
  ),
  constraint com_campanhas_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  constraint com_campanhas_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  ),
  constraint com_campanhas_key unique (codigo_norm)
);

create unique index idx_com_campanhas_source_once
  on public.com_campanhas(source_batch_id, source_row_id)
  where origem_dados = 'excel_legado';

create table public.com_campanha_versoes (
  id bigint generated always as identity primary key,
  campanha_id bigint not null references public.com_campanhas(id),
  versao integer not null,
  data_inicio date,
  data_fim date,
  review_status text not null default 'pending_review',
  justificativa text,
  origem_dados text not null default 'sistema',
  source_batch_id bigint references public.migration_batches(id),
  source_row_id bigint references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint com_campanha_versoes_versao_check check (versao > 0),
  constraint com_campanha_versoes_datas_check check (
    data_inicio is null or data_fim is null or data_fim >= data_inicio
  ),
  constraint com_campanha_versoes_review_check check (
    review_status in ('approved', 'pending_review', 'rejected')
  ),
  constraint com_campanha_versoes_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  constraint com_campanha_versoes_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  ),
  constraint com_campanha_versoes_key unique (campanha_id, versao)
);

create unique index idx_com_campanha_versoes_source_once
  on public.com_campanha_versoes(source_batch_id, source_row_id)
  where origem_dados = 'excel_legado';

create table public.com_campanha_regras (
  id bigint generated always as identity primary key,
  campanha_versao_id bigint not null references public.com_campanha_versoes(id),
  codigo text not null,
  base_tipo text not null,
  produto_id bigint references public.cad_produtos_base(id),
  grupo_produto_id bigint references public.cad_grupos_produto(id),
  limiar_minimo numeric not null,
  limiar_maximo numeric,
  review_status text not null default 'pending_review',
  origem_dados text not null default 'sistema',
  source_batch_id bigint references public.migration_batches(id),
  source_row_id bigint references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint com_campanha_regras_codigo_check check (nullif(btrim(codigo), '') is not null),
  constraint com_campanha_regras_base_check check (
    base_tipo in ('volume_litros', 'valor_venda')
  ),
  constraint com_campanha_regras_alvo_check check (
    not (produto_id is not null and grupo_produto_id is not null)
  ),
  constraint com_campanha_regras_limite_check check (
    limiar_minimo >= 0 and (limiar_maximo is null or limiar_maximo >= limiar_minimo)
  ),
  constraint com_campanha_regras_review_check check (
    review_status in ('approved', 'pending_review', 'rejected')
  ),
  constraint com_campanha_regras_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  constraint com_campanha_regras_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  ),
  constraint com_campanha_regras_key unique (campanha_versao_id, codigo)
);

create unique index idx_com_campanha_regras_source_once
  on public.com_campanha_regras(source_batch_id, source_row_id, codigo)
  where origem_dados = 'excel_legado';

create table public.com_campanha_regra_recompensas (
  id bigint generated always as identity primary key,
  regra_id bigint not null references public.com_campanha_regras(id),
  tipo_recompensa text not null,
  pontos numeric,
  valor_monetario numeric,
  descricao text,
  review_status text not null default 'pending_review',
  origem_dados text not null default 'sistema',
  source_batch_id bigint references public.migration_batches(id),
  source_row_id bigint references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint com_campanha_recompensas_tipo_check check (
    tipo_recompensa in ('pontos', 'monetario', 'voucher_viagem', 'beneficio')
  ),
  constraint com_campanha_recompensas_valor_check check (
    (tipo_recompensa = 'pontos' and pontos > 0 and valor_monetario is null)
    or (tipo_recompensa = 'monetario' and valor_monetario > 0 and pontos is null)
    or (
      tipo_recompensa in ('voucher_viagem', 'beneficio')
      and nullif(btrim(coalesce(descricao, '')), '') is not null
      and pontos is null
    )
  ),
  constraint com_campanha_recompensas_review_check check (
    review_status in ('approved', 'pending_review', 'rejected')
  ),
  constraint com_campanha_recompensas_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  constraint com_campanha_recompensas_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  ),
  constraint com_campanha_recompensas_key unique (regra_id, tipo_recompensa)
);

create unique index idx_com_campanha_recompensas_source_once
  on public.com_campanha_regra_recompensas(
    source_batch_id, source_row_id, tipo_recompensa
  ) where origem_dados = 'excel_legado';

create table public.com_campanha_elegibilidades (
  id bigint generated always as identity primary key,
  campanha_versao_id bigint not null references public.com_campanha_versoes(id),
  escopo_tipo text not null,
  pessoa_id bigint references public.cad_pessoas_comerciais(id),
  area_id bigint references public.cad_areas_comerciais(id),
  cliente_id bigint references public.cad_clientes(id),
  review_status text not null default 'pending_review',
  origem_dados text not null default 'sistema',
  source_batch_id bigint references public.migration_batches(id),
  source_row_id bigint references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint com_campanha_elegibilidades_escopo_check check (
    (escopo_tipo = 'todos' and pessoa_id is null and area_id is null and cliente_id is null)
    or (escopo_tipo = 'pessoa' and pessoa_id is not null and area_id is null and cliente_id is null)
    or (escopo_tipo = 'area' and pessoa_id is null and area_id is not null and cliente_id is null)
    or (escopo_tipo = 'cliente' and pessoa_id is null and area_id is null and cliente_id is not null)
  ),
  constraint com_campanha_elegibilidades_review_check check (
    review_status in ('approved', 'pending_review', 'rejected')
  ),
  constraint com_campanha_elegibilidades_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  constraint com_campanha_elegibilidades_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  )
);

create unique index idx_com_campanha_elegibilidades_natural_key
  on public.com_campanha_elegibilidades(
    campanha_versao_id, escopo_tipo,
    coalesce(pessoa_id, 0), coalesce(area_id, 0), coalesce(cliente_id, 0)
  );
create unique index idx_com_campanha_elegibilidades_source_once
  on public.com_campanha_elegibilidades(source_batch_id, source_row_id, escopo_tipo)
  where origem_dados = 'excel_legado';

create table public.com_campanha_versao_ativacoes (
  id bigint generated always as identity primary key,
  campanha_versao_id bigint not null references public.com_campanha_versoes(id),
  tipo_evento text not null,
  motivo text not null,
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint com_campanha_ativacoes_tipo_check check (
    tipo_evento in ('ativacao', 'desativacao')
  ),
  constraint com_campanha_ativacoes_motivo_check check (
    nullif(btrim(motivo), '') is not null
  )
);

create table public.com_campanha_pontos_movimentos (
  id bigint generated always as identity primary key,
  campanha_versao_id bigint not null references public.com_campanha_versoes(id),
  regra_id bigint references public.com_campanha_regras(id),
  pessoa_id bigint not null references public.cad_pessoas_comerciais(id),
  pedido_id bigint references public.com_pedidos(id),
  pedido_item_id bigint references public.com_pedido_itens(id),
  nota_fiscal_id bigint references public.fat_notas_fiscais(id),
  nota_fiscal_item_id bigint references public.fat_nota_fiscal_itens(id),
  produto_id bigint references public.cad_produtos_base(id),
  grupo_produto_id bigint references public.cad_grupos_produto(id),
  tipo_movimento text not null,
  pontos numeric not null,
  base_quantidade numeric,
  data_competencia date,
  review_status text not null default 'approved',
  origem_dados text not null default 'sistema',
  source_batch_id bigint references public.migration_batches(id),
  source_row_id bigint references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint com_campanha_pontos_tipo_check check (
    tipo_movimento in ('credito', 'estorno', 'ajuste')
  ),
  constraint com_campanha_pontos_valor_check check (
    pontos <> 0
    and (tipo_movimento <> 'credito' or pontos > 0)
    and (tipo_movimento <> 'estorno' or pontos < 0)
  ),
  constraint com_campanha_pontos_base_check check (
    base_quantidade is null or base_quantidade >= 0
  ),
  constraint com_campanha_pontos_review_check check (
    review_status in ('approved', 'pending_review', 'rejected')
    and (review_status = 'pending_review' or data_competencia is not null)
  ),
  constraint com_campanha_pontos_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  constraint com_campanha_pontos_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  )
);

create unique index idx_com_campanha_pontos_source_once
  on public.com_campanha_pontos_movimentos(
    source_batch_id, source_row_id, pessoa_id, coalesce(produto_id, 0)
  ) where origem_dados = 'excel_legado';

create table public.com_campanha_premios (
  id bigint generated always as identity primary key,
  campanha_versao_id bigint not null references public.com_campanha_versoes(id),
  recompensa_id bigint references public.com_campanha_regra_recompensas(id),
  pessoa_id bigint not null references public.cad_pessoas_comerciais(id),
  tipo_premio text not null,
  valor_monetario numeric,
  descricao text,
  review_status text not null default 'approved',
  origem_dados text not null default 'sistema',
  source_batch_id bigint references public.migration_batches(id),
  source_row_id bigint references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint com_campanha_premios_tipo_check check (
    tipo_premio in ('monetario', 'voucher_viagem', 'beneficio')
  ),
  constraint com_campanha_premios_valor_check check (
    (tipo_premio = 'monetario' and valor_monetario > 0)
    or (
      tipo_premio in ('voucher_viagem', 'beneficio')
      and nullif(btrim(coalesce(descricao, '')), '') is not null
    )
  ),
  constraint com_campanha_premios_review_check check (
    review_status in ('approved', 'pending_review', 'rejected')
  ),
  constraint com_campanha_premios_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  constraint com_campanha_premios_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  )
);

create unique index idx_com_campanha_premios_source_once
  on public.com_campanha_premios(source_batch_id, source_row_id, pessoa_id, tipo_premio)
  where origem_dados = 'excel_legado';

create table public.com_campanha_premio_eventos (
  id bigint generated always as identity primary key,
  premio_id bigint not null references public.com_campanha_premios(id),
  tipo_evento text not null,
  motivo text,
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint com_campanha_premio_eventos_tipo_check check (
    tipo_evento in ('gerado', 'aprovado', 'entregue', 'cancelado')
  )
);

create table public.com_campanha_vouchers (
  id bigint generated always as identity primary key,
  premio_id bigint not null unique references public.com_campanha_premios(id),
  codigo text,
  validade_inicio date,
  validade_fim date,
  review_status text not null default 'approved',
  origem_dados text not null default 'sistema',
  source_batch_id bigint references public.migration_batches(id),
  source_row_id bigint references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint com_campanha_vouchers_datas_check check (
    validade_inicio is null or validade_fim is null or validade_fim >= validade_inicio
  ),
  constraint com_campanha_vouchers_review_check check (
    review_status in ('approved', 'pending_review', 'rejected')
  ),
  constraint com_campanha_vouchers_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  constraint com_campanha_vouchers_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  )
);

create unique index idx_com_campanha_vouchers_codigo
  on public.com_campanha_vouchers(codigo) where codigo is not null;
create unique index idx_com_campanha_vouchers_source_once
  on public.com_campanha_vouchers(source_batch_id, source_row_id)
  where origem_dados = 'excel_legado';

create table public.com_campanha_voucher_eventos (
  id bigint generated always as identity primary key,
  voucher_id bigint not null references public.com_campanha_vouchers(id),
  tipo_evento text not null,
  motivo text,
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint com_campanha_voucher_eventos_tipo_check check (
    tipo_evento in ('emitido', 'utilizado', 'expirado', 'cancelado')
  )
);

create table public.fin_campanha_premio_pagamentos (
  id bigint generated always as identity primary key,
  premio_id bigint not null references public.com_campanha_premios(id),
  tipo_evento text not null,
  valor numeric not null,
  data_evento date,
  motivo text,
  review_status text not null default 'approved',
  origem_dados text not null default 'sistema',
  source_batch_id bigint references public.migration_batches(id),
  source_row_id bigint references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint fin_campanha_premio_pagamentos_tipo_check check (
    tipo_evento in ('programado', 'pago', 'estornado')
  ),
  constraint fin_campanha_premio_pagamentos_valor_check check (valor > 0),
  constraint fin_campanha_premio_pagamentos_data_check check (
    tipo_evento = 'programado' or data_evento is not null or review_status = 'pending_review'
  ),
  constraint fin_campanha_premio_pagamentos_review_check check (
    review_status in ('approved', 'pending_review', 'rejected')
  ),
  constraint fin_campanha_premio_pagamentos_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  constraint fin_campanha_premio_pagamentos_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  )
);

create unique index idx_fin_campanha_premio_pagamentos_source_once
  on public.fin_campanha_premio_pagamentos(source_batch_id, source_row_id, premio_id)
  where origem_dados = 'excel_legado';

alter table public.com_pedido_comissionados
  add column if not exists campanha_versao_id bigint references public.com_campanha_versoes(id);

create or replace function public.validate_campaign_activation()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_review text;
  v_status text;
  v_start date;
  v_end date;
begin
  if not exists (
    select 1 from public.user_profiles profile
    where profile.id = new.created_by
      and profile.status = 'active'
      and profile.is_system_actor = false
  ) then
    raise exception 'only active human profiles can activate campaign versions';
  end if;

  select version.review_status, campaign.status, version.data_inicio, version.data_fim
    into v_review, v_status, v_start, v_end
    from public.com_campanha_versoes version
    join public.com_campanhas campaign on campaign.id = version.campanha_id
   where version.id = new.campanha_versao_id;

  if new.tipo_evento = 'ativacao'
     and (v_review <> 'approved' or v_status <> 'active') then
    raise exception 'only approved versions of active campaigns can be activated';
  end if;
  if new.tipo_evento = 'ativacao' and (v_start is null or v_end is null) then
    raise exception 'campaign activation requires a proven start and end date';
  end if;
  if new.tipo_evento = 'ativacao' and not exists (
    select 1
      from public.com_campanha_regras rule
     where rule.campanha_versao_id = new.campanha_versao_id
       and rule.review_status = 'approved'
       and exists (
         select 1 from public.com_campanha_regra_recompensas reward
          where reward.regra_id = rule.id and reward.review_status = 'approved'
       )
  ) then
    raise exception 'campaign activation requires an approved rule with reward';
  end if;
  if new.tipo_evento = 'ativacao' and not exists (
    select 1 from public.com_campanha_elegibilidades eligibility
     where eligibility.campanha_versao_id = new.campanha_versao_id
       and eligibility.review_status = 'approved'
  ) then
    raise exception 'campaign activation requires approved eligibility';
  end if;
  return new;
end;
$$;

revoke all on function public.validate_campaign_activation() from public, anon, authenticated;

create trigger trg_com_campanha_activation_human
before insert on public.com_campanha_versao_ativacoes
for each row execute function public.validate_campaign_activation();

create or replace function public.prevent_campaign_fact_changes()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception '% is append-only; create a new version or event', tg_table_name;
end;
$$;

revoke all on function public.prevent_campaign_fact_changes() from public, anon, authenticated;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'com_campanha_versoes', 'com_campanha_regras',
    'com_campanha_regra_recompensas', 'com_campanha_elegibilidades',
    'com_campanha_versao_ativacoes', 'com_campanha_pontos_movimentos',
    'com_campanha_premios', 'com_campanha_premio_eventos',
    'com_campanha_vouchers', 'com_campanha_voucher_eventos',
    'fin_campanha_premio_pagamentos'
  ]
  loop
    execute format(
      'create trigger %I before update or delete on public.%I for each row execute function public.prevent_campaign_fact_changes()',
      'trg_' || v_table || '_append_only', v_table
    );
    execute format(
      'create trigger %I before truncate on public.%I for each statement execute function public.prevent_campaign_fact_changes()',
      'trg_' || v_table || '_no_truncate', v_table
    );
  end loop;
end;
$$;

do $$
declare
  v_table text;
  v_review text;
begin
  foreach v_table in array array[
    'cad_grupos_produto', 'com_campanhas', 'com_campanha_versoes',
    'com_campanha_regras', 'com_campanha_regra_recompensas',
    'com_campanha_elegibilidades', 'com_campanha_pontos_movimentos',
    'com_campanha_premios', 'com_campanha_vouchers',
    'fin_campanha_premio_pagamentos'
  ]
  loop
    v_review := case
      when v_table in ('cad_grupos_produto', 'com_campanhas') then 'status'
      else 'review_status'
    end;
    if v_table in ('cad_grupos_produto', 'com_campanhas') then
      execute format(
        'create trigger %I before insert or update of origem_dados, source_batch_id, source_row_id, created_by, status on public.%I for each row execute function public.enforce_historical_record_contract(%L, %L)',
        'trg_' || v_table || '_historical_contract', v_table, v_review, 'pending_review'
      );
    else
      execute format(
        'create trigger %I before insert on public.%I for each row execute function public.enforce_historical_record_contract(%L, %L)',
        'trg_' || v_table || '_historical_contract', v_table, v_review, 'pending_review'
      );
    end if;
  end loop;
end;
$$;

create or replace view public.com_campanha_configuracoes_atuais
with (security_invoker = true)
as
with latest_event as (
  select distinct on (version.campanha_id)
    version.campanha_id,
    activation.campanha_versao_id,
    activation.tipo_evento,
    activation.created_at
  from public.com_campanha_versao_ativacoes activation
  join public.com_campanha_versoes version on version.id = activation.campanha_versao_id
  order by version.campanha_id, activation.created_at desc, activation.id desc
)
select
  campaign.id as campanha_id,
  campaign.codigo,
  campaign.nome,
  version.id as campanha_versao_id,
  version.versao,
  version.data_inicio,
  version.data_fim
from latest_event
join public.com_campanha_versoes version on version.id = latest_event.campanha_versao_id
join public.com_campanhas campaign on campaign.id = version.campanha_id
where latest_event.tipo_evento = 'ativacao'
  and campaign.status = 'active'
  and campaign.origem_dados = 'sistema'
  and version.review_status = 'approved'
  and (version.data_inicio is null or version.data_inicio <= current_date)
  and (version.data_fim is null or version.data_fim >= current_date);

create or replace view public.com_campanha_pontos_saldos
with (security_invoker = true)
as
select
  movement.campanha_versao_id,
  movement.pessoa_id,
  sum(movement.pontos)::numeric as pontos_saldo,
  count(*)::integer as movimentos_count,
  max(movement.created_at) as ultimo_movimento_at
from public.com_campanha_pontos_movimentos movement
where movement.review_status = 'approved'
  and movement.origem_dados = 'sistema'
group by movement.campanha_versao_id, movement.pessoa_id;

create or replace view public.com_campanha_premios_status_atual
with (security_invoker = true)
as
select distinct on (prize.id)
  prize.id as premio_id,
  prize.campanha_versao_id,
  prize.pessoa_id,
  prize.tipo_premio,
  prize.valor_monetario,
  event.tipo_evento as status_atual,
  event.created_at as status_at
from public.com_campanha_premios prize
join public.com_campanha_premio_eventos event on event.premio_id = prize.id
where prize.review_status = 'approved'
  and prize.origem_dados = 'sistema'
order by prize.id, event.created_at desc, event.id desc;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'cad_grupos_produto', 'com_campanhas', 'com_campanha_versoes',
    'com_campanha_regras', 'com_campanha_regra_recompensas',
    'com_campanha_elegibilidades', 'com_campanha_versao_ativacoes',
    'com_campanha_pontos_movimentos', 'com_campanha_premios',
    'com_campanha_premio_eventos', 'com_campanha_vouchers',
    'com_campanha_voucher_eventos', 'fin_campanha_premio_pagamentos'
  ]
  loop
    execute format('alter table public.%I enable row level security', v_table);
    execute format(
      'create policy %I on public.%I for select to authenticated using (public.current_actor_id() is not null)',
      'active user read ' || v_table, v_table
    );
    execute format('revoke insert, update, delete, truncate on public.%I from public, anon, authenticated', v_table);
    execute format('grant select on public.%I to authenticated', v_table);
  end loop;
end;
$$;

grant select on public.com_campanha_configuracoes_atuais to authenticated;
grant select on public.com_campanha_pontos_saldos to authenticated;
grant select on public.com_campanha_premios_status_atual to authenticated;

comment on table public.com_campanha_pontos_movimentos is
  'Ledger append-only de pontos. Nao e ledger de comissao.';
comment on table public.com_campanha_premios is
  'Premios de campanha separados da conta corrente de comissoes.';
comment on table public.fin_campanha_premio_pagamentos is
  'Eventos financeiros append-only de premio monetario; pagamento nao altera comissao.';
comment on column public.com_pedido_comissionados.campanha_ref is
  'Cache textual legado. A referencia relacional, quando comprovada, e campanha_versao_id.';
