-- DEC-009: normalized payment schedules and explicit legacy opening positions.
-- Historical positions never fabricate receipts, commission payments or fiscal documents.

do $$
begin
  if public.historical_migration_actor_id() is null then
    raise exception 'Migracao Historica system actor is required by DEC-009';
  end if;
end;
$$;

create table public.fin_pedido_planos_pagamento (
  id bigint generated always as identity primary key,
  pedido_id bigint not null references public.com_pedidos(id),
  versao integer not null,
  vigencia_inicio date,
  vigencia_fim date,
  review_status text not null default 'approved',
  origem_dados text not null default 'sistema',
  source_batch_id bigint references public.migration_batches(id),
  source_row_id bigint references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint fin_pedido_planos_versao_check check (versao > 0),
  constraint fin_pedido_planos_vigencia_check check (
    vigencia_inicio is null or vigencia_fim is null or vigencia_fim >= vigencia_inicio
  ),
  constraint fin_pedido_planos_operacional_inicio_check check (
    origem_dados = 'excel_legado'
    or review_status <> 'approved'
    or vigencia_inicio is not null
  ),
  constraint fin_pedido_planos_review_check check (
    review_status in ('approved', 'pending_review', 'rejected')
  ),
  constraint fin_pedido_planos_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  constraint fin_pedido_planos_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  ),
  constraint fin_pedido_planos_key unique (pedido_id, versao)
);

create unique index idx_fin_pedido_planos_source_once
  on public.fin_pedido_planos_pagamento(source_batch_id, source_row_id)
  where origem_dados = 'excel_legado';

create table public.fin_pedido_parcelas (
  id bigint generated always as identity primary key,
  plano_pagamento_id bigint not null references public.fin_pedido_planos_pagamento(id),
  numero_parcela integer not null,
  data_vencimento date not null,
  valor_previsto numeric,
  review_status text not null default 'approved',
  origem_dados text not null default 'sistema',
  source_batch_id bigint references public.migration_batches(id),
  source_row_id bigint references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint fin_pedido_parcelas_numero_check check (numero_parcela between 1 and 999),
  constraint fin_pedido_parcelas_valor_check check (
    valor_previsto is null or valor_previsto >= 0
  ),
  constraint fin_pedido_parcelas_review_check check (
    review_status in ('approved', 'pending_review', 'rejected')
  ),
  constraint fin_pedido_parcelas_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  constraint fin_pedido_parcelas_source_pair_check check (
    (source_batch_id is null and source_row_id is null)
    or (source_batch_id is not null and source_row_id is not null)
  ),
  constraint fin_pedido_parcelas_key unique (plano_pagamento_id, numero_parcela)
);

create unique index idx_fin_pedido_parcelas_source_once
  on public.fin_pedido_parcelas(source_batch_id, source_row_id, numero_parcela)
  where origem_dados = 'excel_legado';

create table public.fin_recebimento_posicoes_historicas (
  id bigint generated always as identity primary key,
  pedido_id bigint not null references public.com_pedidos(id),
  status_recebimento_legado text not null,
  classificacao_normalizada text,
  data_posicao date,
  review_status text not null default 'pending_review',
  origem_dados text not null default 'excel_legado',
  source_batch_id bigint not null references public.migration_batches(id),
  source_row_id bigint not null references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint fin_recebimento_posicoes_status_text_check check (
    nullif(btrim(status_recebimento_legado), '') is not null
  ),
  constraint fin_recebimento_posicoes_classificacao_check check (
    classificacao_normalizada is null
    or classificacao_normalizada in (
      'em_aberto', 'parcial', 'recebido', 'vencido', 'cancelado', 'nao_mapeado'
    )
  ),
  constraint fin_recebimento_posicoes_review_check check (
    review_status in ('pending_review', 'rejected')
  ),
  constraint fin_recebimento_posicoes_origem_check check (
    origem_dados = 'excel_legado'
  )
);

create unique index idx_fin_recebimento_posicoes_source_once
  on public.fin_recebimento_posicoes_historicas(source_batch_id, source_row_id, pedido_id);

create table public.fin_comissao_posicoes_historicas (
  id bigint generated always as identity primary key,
  comissionado_id bigint not null references public.com_pedido_comissionados(id),
  valor_pago_informado numeric not null,
  data_posicao date,
  review_status text not null default 'pending_review',
  origem_dados text not null default 'excel_legado',
  source_batch_id bigint not null references public.migration_batches(id),
  source_row_id bigint not null references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint fin_comissao_posicoes_valor_check check (valor_pago_informado >= 0),
  constraint fin_comissao_posicoes_review_check check (
    review_status in ('pending_review', 'rejected')
  ),
  constraint fin_comissao_posicoes_origem_check check (
    origem_dados = 'excel_legado'
  )
);

create unique index idx_fin_comissao_posicoes_source_once
  on public.fin_comissao_posicoes_historicas(
    source_batch_id, source_row_id, comissionado_id
  );

create table public.fat_referencias_fiscais_historicas (
  id bigint generated always as identity primary key,
  pedido_id bigint not null references public.com_pedidos(id),
  referencia_legada text not null,
  referencia_norm text generated always as (lower(btrim(referencia_legada))) stored,
  data_emissao_informada date,
  review_status text not null default 'pending_review',
  origem_dados text not null default 'excel_legado',
  source_batch_id bigint not null references public.migration_batches(id),
  source_row_id bigint not null references public.source_rows(id),
  created_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint fat_referencias_historicas_text_check check (
    nullif(btrim(referencia_legada), '') is not null
  ),
  constraint fat_referencias_historicas_review_check check (
    review_status in ('pending_review', 'rejected')
  ),
  constraint fat_referencias_historicas_origem_check check (
    origem_dados = 'excel_legado'
  ),
  constraint fat_referencias_historicas_key unique (pedido_id, referencia_norm)
);

create unique index idx_fat_referencias_historicas_source_once
  on public.fat_referencias_fiscais_historicas(
    source_batch_id, source_row_id, referencia_norm
  );

create or replace function public.validate_dec009_payment_plan_child()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_origin text;
  v_batch_id bigint;
  v_row_id bigint;
  v_review_status text;
begin
  select plan.origem_dados, plan.source_batch_id, plan.source_row_id, plan.review_status
    into v_origin, v_batch_id, v_row_id, v_review_status
    from public.fin_pedido_planos_pagamento plan
   where plan.id = new.plano_pagamento_id;

  if v_origin is null then
    raise exception 'payment plan not found';
  end if;
  if new.origem_dados <> v_origin
     or new.source_batch_id is distinct from v_batch_id
     or new.source_row_id is distinct from v_row_id
     or new.review_status <> v_review_status then
    raise exception 'payment installment must share origin, lineage and review with its plan';
  end if;

  return new;
end;
$$;

revoke all on function public.validate_dec009_payment_plan_child()
from public, anon, authenticated;

create trigger trg_fin_pedido_parcelas_plan_lineage
before insert on public.fin_pedido_parcelas
for each row execute function public.validate_dec009_payment_plan_child();

create or replace function public.prevent_dec009_fact_changes()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception '% is append-only; create a new version or historical position', tg_table_name;
end;
$$;

revoke all on function public.prevent_dec009_fact_changes()
from public, anon, authenticated;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'fin_pedido_planos_pagamento',
    'fin_pedido_parcelas',
    'fin_recebimento_posicoes_historicas',
    'fin_comissao_posicoes_historicas',
    'fat_referencias_fiscais_historicas'
  ]
  loop
    execute format(
      'create trigger %I before update or delete on public.%I for each row execute function public.prevent_dec009_fact_changes()',
      'trg_' || v_table || '_append_only', v_table
    );
    execute format(
      'create trigger %I before truncate on public.%I for each statement execute function public.prevent_dec009_fact_changes()',
      'trg_' || v_table || '_no_truncate', v_table
    );
  end loop;
end;
$$;

create trigger trg_fin_pedido_planos_historical_contract
before insert on public.fin_pedido_planos_pagamento
for each row execute function public.enforce_historical_record_contract(
  'review_status', 'pending_review'
);

create trigger trg_fin_pedido_parcelas_historical_contract
before insert on public.fin_pedido_parcelas
for each row execute function public.enforce_historical_record_contract(
  'review_status', 'pending_review'
);

create trigger trg_fin_recebimento_posicoes_historical_contract
before insert on public.fin_recebimento_posicoes_historicas
for each row execute function public.enforce_historical_record_contract(
  'review_status', 'pending_review'
);

create trigger trg_fin_comissao_posicoes_historical_contract
before insert on public.fin_comissao_posicoes_historicas
for each row execute function public.enforce_historical_record_contract(
  'review_status', 'pending_review'
);

create trigger trg_fat_referencias_historicas_historical_contract
before insert on public.fat_referencias_fiscais_historicas
for each row execute function public.enforce_historical_record_contract(
  'review_status', 'pending_review'
);

create or replace view public.fin_pedido_parcelas_atuais
with (security_invoker = true)
as
with current_plan as (
  select distinct on (plan.pedido_id)
    plan.id,
    plan.pedido_id,
    plan.versao,
    plan.vigencia_inicio,
    plan.vigencia_fim
  from public.fin_pedido_planos_pagamento plan
  where plan.origem_dados = 'sistema'
    and plan.review_status = 'approved'
    and plan.vigencia_inicio <= current_date
    and (plan.vigencia_fim is null or plan.vigencia_fim >= current_date)
  order by plan.pedido_id, plan.versao desc, plan.id desc
)
select
  current_plan.pedido_id,
  current_plan.id as plano_pagamento_id,
  current_plan.versao,
  installment.id as parcela_id,
  installment.numero_parcela,
  installment.data_vencimento,
  installment.valor_previsto
from current_plan
join public.fin_pedido_parcelas installment
  on installment.plano_pagamento_id = current_plan.id
where installment.origem_dados = 'sistema'
  and installment.review_status = 'approved';

comment on table public.fin_pedido_planos_pagamento is
  'Financeiro: versoes relacionais do plano de pagamento. Versao posterior substitui a anterior no read model sem editar historia.';
comment on table public.fin_pedido_parcelas is
  'Financeiro: vencimentos normalizados. Recebimento real permanece em com_recebimentos/fin_recebimento_alocacoes.';
comment on table public.fin_recebimento_posicoes_historicas is
  'Financeiro: snapshot legado de status recebido, sem criar recebimento, data ou valor inexistente.';
comment on table public.fin_comissao_posicoes_historicas is
  'Financeiro: saldo pago informado no Excel, sem criar pagamento ou movimento de comissao.';
comment on table public.fat_referencias_fiscais_historicas is
  'Faturamento: referencia fiscal incompleta, sem promocao automatica para fat_notas_fiscais.';
comment on column public.fin_recebimento_posicoes_historicas.data_posicao is
  'Data da posicao somente quando declarada pela fonte; created_at e data tecnica de importacao.';
comment on column public.fin_comissao_posicoes_historicas.data_posicao is
  'Data da posicao somente quando declarada pela fonte; nao representa data de pagamento.';

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'fin_pedido_planos_pagamento',
    'fin_pedido_parcelas',
    'fin_recebimento_posicoes_historicas',
    'fin_comissao_posicoes_historicas',
    'fat_referencias_fiscais_historicas'
  ]
  loop
    execute format('alter table public.%I enable row level security', v_table);
    execute format(
      'create policy %I on public.%I for select to authenticated using (public.current_actor_id() is not null)',
      'authenticated read ' || v_table, v_table
    );
    execute format('grant select on public.%I to authenticated', v_table);
    execute format(
      'revoke insert, update, delete, truncate on public.%I from public, anon, authenticated',
      v_table
    );
  end loop;
end;
$$;

grant select on public.fin_pedido_parcelas_atuais to authenticated;
