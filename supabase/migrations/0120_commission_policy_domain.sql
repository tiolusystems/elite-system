-- COMM-01 / Financeiro: dominio governado de comissoes.
-- Regras centrais:
-- 1) somente vendas geram direitos de comissao;
-- 2) uma venda pode ter multiplos participantes;
-- 3) relacionamentos agente->vendedor e vendedor->gerente sao opcionais e temporais;
-- 4) politicas por pessoa/grupo/papel sao versionadas;
-- 5) alteracoes manuais de comissao usam proposta + confirmacao;
-- 6) recebimento nao impede inclusao posterior; ele controla liberacao financeira;
-- 7) fatos historicos nao sao reinterpretados silenciosamente.

insert into public.permission_actions(
  action_key, module, description, default_allowed, sort_order,
  runtime_module_key, runtime_access_kind
)
values
  ('cadastros.pessoas.relationships.manage', 'cadastros',
   'Gerenciar relacionamentos comerciais temporais entre pessoas', false, 81,
   'cadastros', 'write'),
  ('financeiro.commissions.policy.view', 'financeiro',
   'Consultar politicas versionadas de comissao', false, 616,
   'financeiro', 'read'),
  ('financeiro.commissions.policy.manage', 'financeiro',
   'Configurar e publicar politicas versionadas de comissao', false, 617,
   'financeiro', 'write'),
  ('financeiro.commissions.revision.request', 'financeiro',
   'Preparar alteracao de comissao para revisao antes da gravacao', false, 618,
   'financeiro', 'write'),
  ('financeiro.commissions.revision.confirm', 'financeiro',
   'Confirmar alteracao de comissao revisada com impacto conhecido', false, 619,
   'financeiro', 'write')
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

-- ---------------------------------------------------------------------------
-- Relacionamentos comerciais temporais
-- ---------------------------------------------------------------------------

create table if not exists public.cad_pessoa_relacionamentos_comerciais (
  id bigint generated always as identity primary key,
  pessoa_origem_id bigint not null references public.cad_pessoas_comerciais(id),
  pessoa_destino_id bigint not null references public.cad_pessoas_comerciais(id),
  tipo_relacionamento text not null,
  vigencia_inicio date not null,
  vigencia_fim date,
  status text not null default 'active',
  motivo_inicio text not null,
  motivo_fim text,
  created_by uuid references public.user_profiles(id),
  closed_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  closed_at timestamptz,
  constraint cad_pessoa_rel_comercial_distinct_check
    check (pessoa_origem_id <> pessoa_destino_id),
  constraint cad_pessoa_rel_comercial_tipo_check
    check (tipo_relacionamento in ('agente_vendedor', 'vendedor_gerente')),
  constraint cad_pessoa_rel_comercial_datas_check
    check (vigencia_fim is null or vigencia_fim >= vigencia_inicio),
  constraint cad_pessoa_rel_comercial_status_check
    check (status in ('active', 'closed', 'cancelled')),
  constraint cad_pessoa_rel_comercial_motivo_inicio_check
    check (char_length(btrim(motivo_inicio)) >= 10),
  constraint cad_pessoa_rel_comercial_motivo_fim_check
    check (motivo_fim is null or char_length(btrim(motivo_fim)) >= 10)
);

create index if not exists idx_cad_pessoa_rel_comercial_origem
  on public.cad_pessoa_relacionamentos_comerciais(
    pessoa_origem_id, tipo_relacionamento, vigencia_inicio desc
  );

create index if not exists idx_cad_pessoa_rel_comercial_destino
  on public.cad_pessoa_relacionamentos_comerciais(
    pessoa_destino_id, tipo_relacionamento, vigencia_inicio desc
  );

create unique index if not exists idx_cad_pessoa_rel_comercial_current_once
  on public.cad_pessoa_relacionamentos_comerciais(
    pessoa_origem_id, tipo_relacionamento
  )
  where status = 'active' and vigencia_fim is null;

alter table public.cad_pessoa_relacionamentos_comerciais enable row level security;
drop policy if exists "governed read cad_pessoa_relacionamentos_comerciais"
  on public.cad_pessoa_relacionamentos_comerciais;
create policy "governed read cad_pessoa_relacionamentos_comerciais"
on public.cad_pessoa_relacionamentos_comerciais
for select to authenticated
using (public.current_actor_id() is not null);

grant select on public.cad_pessoa_relacionamentos_comerciais to authenticated;
revoke insert, update, delete, truncate
  on public.cad_pessoa_relacionamentos_comerciais
  from public, anon, authenticated;

comment on table public.cad_pessoa_relacionamentos_comerciais is
  'Relacionamentos comerciais opcionais e temporais. A cadeia vigente pode ser fotografada no pedido, mas alteracoes posteriores no cadastro nao reescrevem fatos historicos.';

create or replace function public.registrar_cad_pessoa_relacionamento_comercial(
  p_pessoa_origem_id bigint,
  p_pessoa_destino_id bigint,
  p_tipo_relacionamento text,
  p_vigencia_inicio date,
  p_vigencia_fim date default null,
  p_motivo text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_id bigint;
  v_context jsonb;
  v_after jsonb;
begin
  v_context := public.begin_audited_rpc(
    'cadastros.pessoas.relationships.manage',
    'cadastros',
    'cad_pessoa_relacionamentos_comerciais',
    'change_type',
    jsonb_build_object('event', 'commercial_relationship_create')
  );

  if p_pessoa_origem_id is null or p_pessoa_destino_id is null then
    raise exception 'relationship people are required';
  end if;
  if p_pessoa_origem_id = p_pessoa_destino_id then
    raise exception 'commercial relationship cannot reference the same person';
  end if;
  if p_tipo_relacionamento not in ('agente_vendedor', 'vendedor_gerente') then
    raise exception 'invalid commercial relationship type';
  end if;
  if p_vigencia_inicio is null then
    raise exception 'relationship start date is required';
  end if;
  if p_vigencia_fim is not null and p_vigencia_fim < p_vigencia_inicio then
    raise exception 'relationship end date is before start date';
  end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 10 then
    raise exception 'relationship reason must have at least 10 characters';
  end if;

  perform 1 from public.cad_pessoas_comerciais
   where id = p_pessoa_origem_id and status = 'active';
  if not found then raise exception 'active origin commercial person not found'; end if;

  perform 1 from public.cad_pessoas_comerciais
   where id = p_pessoa_destino_id and status = 'active';
  if not found then raise exception 'active destination commercial person not found'; end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'commercial_relationship:' || p_pessoa_origem_id::text || ':' || p_tipo_relacionamento,
      0
    )
  );

  if exists (
    select 1
      from public.cad_pessoa_relacionamentos_comerciais relation
     where relation.pessoa_origem_id = p_pessoa_origem_id
       and relation.tipo_relacionamento = p_tipo_relacionamento
       and relation.status <> 'cancelled'
       and daterange(
             relation.vigencia_inicio,
             coalesce(relation.vigencia_fim, 'infinity'::date),
             '[]'
           )
           &&
           daterange(
             p_vigencia_inicio,
             coalesce(p_vigencia_fim, 'infinity'::date),
             '[]'
           )
  ) then
    raise exception 'commercial relationship effective period overlaps an active relationship';
  end if;

  v_actor := public.current_actor_id();

  insert into public.cad_pessoa_relacionamentos_comerciais(
    pessoa_origem_id,
    pessoa_destino_id,
    tipo_relacionamento,
    vigencia_inicio,
    vigencia_fim,
    status,
    motivo_inicio,
    created_by
  )
  values (
    p_pessoa_origem_id,
    p_pessoa_destino_id,
    p_tipo_relacionamento,
    p_vigencia_inicio,
    p_vigencia_fim,
    'active',
    btrim(p_motivo),
    v_actor
  )
  returning id into v_id;

  select to_jsonb(relation)
    into v_after
    from public.cad_pessoa_relacionamentos_comerciais relation
   where relation.id = v_id;

  perform public.log_audited_rpc_change(
    'cadastros',
    'cad_pessoa_relacionamentos_comerciais',
    v_id::text,
    'cadastros.pessoa_relacionamento_comercial_created',
    'cadastros.pessoas.relationships.manage',
    v_context,
    null,
    v_after,
    jsonb_build_object(
      'source', 'registrar_cad_pessoa_relacionamento_comercial',
      'motivo', btrim(p_motivo)
    )
  );

  return v_id;
end;
$$;

create or replace function public.encerrar_cad_pessoa_relacionamento_comercial(
  p_relacionamento_id bigint,
  p_vigencia_fim date,
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
  v_after jsonb;
  v_start date;
  v_status text;
  v_context jsonb;
begin
  v_context := public.begin_audited_rpc(
    'cadastros.pessoas.relationships.manage',
    'cadastros',
    'cad_pessoa_relacionamentos_comerciais',
    'status_transition',
    jsonb_build_object('event', 'commercial_relationship_close')
  );

  if p_relacionamento_id is null or p_relacionamento_id <= 0 then
    raise exception 'relationship id is required';
  end if;
  if p_vigencia_fim is null then
    raise exception 'relationship end date is required';
  end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 10 then
    raise exception 'relationship close reason must have at least 10 characters';
  end if;

  select to_jsonb(relation), relation.vigencia_inicio, relation.status
    into v_before, v_start, v_status
    from public.cad_pessoa_relacionamentos_comerciais relation
   where relation.id = p_relacionamento_id
   for update;

  if not found then raise exception 'commercial relationship not found'; end if;
  if v_status <> 'active' then raise exception 'commercial relationship is not active'; end if;
  if p_vigencia_fim < v_start then raise exception 'relationship end date is before start date'; end if;

  v_actor := public.current_actor_id();

  update public.cad_pessoa_relacionamentos_comerciais
     set vigencia_fim = p_vigencia_fim,
         status = 'closed',
         motivo_fim = btrim(p_motivo),
         closed_by = v_actor,
         closed_at = now()
   where id = p_relacionamento_id;

  select to_jsonb(relation)
    into v_after
    from public.cad_pessoa_relacionamentos_comerciais relation
   where relation.id = p_relacionamento_id;

  perform public.log_audited_rpc_change(
    'cadastros',
    'cad_pessoa_relacionamentos_comerciais',
    p_relacionamento_id::text,
    'cadastros.pessoa_relacionamento_comercial_closed',
    'cadastros.pessoas.relationships.manage',
    v_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'encerrar_cad_pessoa_relacionamento_comercial',
      'motivo', btrim(p_motivo)
    )
  );

  return p_relacionamento_id;
end;
$$;

revoke all on function public.registrar_cad_pessoa_relacionamento_comercial(
  bigint, bigint, text, date, date, text
) from public, anon;
revoke all on function public.encerrar_cad_pessoa_relacionamento_comercial(
  bigint, date, text
) from public, anon;
grant execute on function public.registrar_cad_pessoa_relacionamento_comercial(
  bigint, bigint, text, date, date, text
) to authenticated;
grant execute on function public.encerrar_cad_pessoa_relacionamento_comercial(
  bigint, date, text
) to authenticated;

-- ---------------------------------------------------------------------------
-- Politicas versionadas de comissao por pessoa / grupo / papel
-- ---------------------------------------------------------------------------

create table if not exists public.com_comissao_politicas_pessoa (
  id bigint generated always as identity primary key,
  pessoa_id bigint not null references public.cad_pessoas_comerciais(id),
  versao integer not null,
  comissionavel boolean not null default true,
  vigencia_inicio date not null,
  vigencia_fim date,
  status text not null default 'draft',
  motivo text not null,
  created_by uuid references public.user_profiles(id),
  published_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  published_at timestamptz,
  constraint com_comissao_politica_versao_check check (versao > 0),
  constraint com_comissao_politica_datas_check
    check (vigencia_fim is null or vigencia_fim >= vigencia_inicio),
  constraint com_comissao_politica_status_check
    check (status in ('draft', 'published', 'closed', 'cancelled')),
  constraint com_comissao_politica_motivo_check
    check (char_length(btrim(motivo)) >= 10),
  unique (pessoa_id, versao)
);

create table if not exists public.com_comissao_politica_taxas_grupo (
  id bigint generated always as identity primary key,
  politica_id bigint not null references public.com_comissao_politicas_pessoa(id) on delete restrict,
  grupo_produto_id bigint not null references public.cad_grupos_produto(id),
  papel_comissao text not null,
  percentual numeric not null,
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint com_comissao_taxa_papel_check
    check (papel_comissao in ('vendedor', 'agente', 'gerente', 'tecnico_campo', 'outro')),
  constraint com_comissao_taxa_percentual_check
    check (percentual > 0 and percentual <= 100),
  unique (politica_id, grupo_produto_id, papel_comissao)
);

create index if not exists idx_com_comissao_politica_pessoa_vigencia
  on public.com_comissao_politicas_pessoa(
    pessoa_id, status, vigencia_inicio desc, vigencia_fim
  );

create index if not exists idx_com_comissao_taxa_grupo
  on public.com_comissao_politica_taxas_grupo(
    grupo_produto_id, papel_comissao, politica_id
  );

alter table public.com_comissao_politicas_pessoa enable row level security;
alter table public.com_comissao_politica_taxas_grupo enable row level security;

drop policy if exists "governed read com_comissao_politicas_pessoa"
  on public.com_comissao_politicas_pessoa;
create policy "governed read com_comissao_politicas_pessoa"
on public.com_comissao_politicas_pessoa
for select to authenticated
using (public.can_current_user('financeiro.commissions.policy.view')
       or public.can_current_user('financeiro.commissions.policy.manage'));

drop policy if exists "governed read com_comissao_politica_taxas_grupo"
  on public.com_comissao_politica_taxas_grupo;
create policy "governed read com_comissao_politica_taxas_grupo"
on public.com_comissao_politica_taxas_grupo
for select to authenticated
using (public.can_current_user('financeiro.commissions.policy.view')
       or public.can_current_user('financeiro.commissions.policy.manage'));

grant select on public.com_comissao_politicas_pessoa,
                public.com_comissao_politica_taxas_grupo
to authenticated;

revoke insert, update, delete, truncate
  on public.com_comissao_politicas_pessoa,
     public.com_comissao_politica_taxas_grupo
  from public, anon, authenticated;

comment on table public.com_comissao_politicas_pessoa is
  'Politica versionada da pessoa. Alterar percentual cria nova versao; pedidos historicos preservam a politica efetivamente aplicada.';
comment on table public.com_comissao_politica_taxas_grupo is
  'Taxas normalizadas por politica, grupo de produto e papel. Percentuais de negocio nao ficam em JSON nem em constantes de codigo.';

create or replace function public.criar_com_comissao_politica_rascunho(
  p_pessoa_id bigint,
  p_comissionavel boolean,
  p_vigencia_inicio date,
  p_vigencia_fim date default null,
  p_motivo text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_versao integer;
  v_id bigint;
  v_context jsonb;
begin
  v_context := public.begin_audited_rpc(
    'financeiro.commissions.policy.manage',
    'financeiro',
    'com_comissao_politicas_pessoa',
    'change_type',
    jsonb_build_object('event', 'commission_policy_draft')
  );

  if p_pessoa_id is null or p_pessoa_id <= 0 then raise exception 'person is required'; end if;
  if p_vigencia_inicio is null then raise exception 'policy start date is required'; end if;
  if p_vigencia_fim is not null and p_vigencia_fim < p_vigencia_inicio then
    raise exception 'policy end date is before start date';
  end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 10 then
    raise exception 'policy reason must have at least 10 characters';
  end if;

  perform 1 from public.cad_pessoas_comerciais
   where id = p_pessoa_id and status = 'active';
  if not found then raise exception 'active commercial person not found'; end if;

  perform pg_advisory_xact_lock(hashtextextended('commission_policy:' || p_pessoa_id::text, 0));

  if exists (
    select 1 from public.com_comissao_politicas_pessoa policy
     where policy.pessoa_id = p_pessoa_id
       and policy.status = 'draft'
  ) then
    raise exception 'person already has a commission policy draft';
  end if;

  select coalesce(max(policy.versao), 0) + 1
    into v_versao
    from public.com_comissao_politicas_pessoa policy
   where policy.pessoa_id = p_pessoa_id;

  v_actor := public.current_actor_id();

  insert into public.com_comissao_politicas_pessoa(
    pessoa_id, versao, comissionavel, vigencia_inicio, vigencia_fim,
    status, motivo, created_by
  )
  values (
    p_pessoa_id, v_versao, coalesce(p_comissionavel, false),
    p_vigencia_inicio, p_vigencia_fim, 'draft', btrim(p_motivo), v_actor
  )
  returning id into v_id;

  perform public.log_audited_rpc_change(
    'financeiro', 'com_comissao_politicas_pessoa', v_id::text,
    'financeiro.comissao_politica_rascunho_created',
    'financeiro.commissions.policy.manage',
    v_context, null,
    (select to_jsonb(policy) from public.com_comissao_politicas_pessoa policy where policy.id = v_id),
    jsonb_build_object('source', 'criar_com_comissao_politica_rascunho')
  );

  return v_id;
end;
$$;

create or replace function public.definir_com_comissao_politica_taxa(
  p_politica_id bigint,
  p_grupo_produto_id bigint,
  p_papel_comissao text,
  p_percentual numeric
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_id bigint;
  v_context jsonb;
begin
  v_context := public.begin_audited_rpc(
    'financeiro.commissions.policy.manage',
    'financeiro',
    'com_comissao_politica_taxas_grupo',
    'field_risk',
    jsonb_build_object('event', 'commission_policy_rate')
  );

  if p_papel_comissao not in ('vendedor', 'agente', 'gerente', 'tecnico_campo', 'outro') then
    raise exception 'invalid commission role';
  end if;
  if p_percentual is null or p_percentual <= 0 or p_percentual > 100 then
    raise exception 'commission percentage must be greater than zero and at most 100';
  end if;

  perform 1 from public.com_comissao_politicas_pessoa
   where id = p_politica_id and status = 'draft'
   for update;
  if not found then raise exception 'commission policy must be draft to change rates'; end if;

  perform 1 from public.cad_grupos_produto
   where id = p_grupo_produto_id and status = 'active';
  if not found then raise exception 'active product group not found'; end if;

  v_actor := public.current_actor_id();

  insert into public.com_comissao_politica_taxas_grupo(
    politica_id, grupo_produto_id, papel_comissao, percentual, created_by
  )
  values (
    p_politica_id, p_grupo_produto_id, p_papel_comissao, p_percentual, v_actor
  )
  on conflict (politica_id, grupo_produto_id, papel_comissao)
  do update set percentual = excluded.percentual
  returning id into v_id;

  perform public.log_audited_rpc_change(
    'financeiro', 'com_comissao_politica_taxas_grupo', v_id::text,
    'financeiro.comissao_politica_taxa_saved',
    'financeiro.commissions.policy.manage',
    v_context, null,
    (select to_jsonb(rate) from public.com_comissao_politica_taxas_grupo rate where rate.id = v_id),
    jsonb_build_object('source', 'definir_com_comissao_politica_taxa')
  );

  return v_id;
end;
$$;

create or replace function public.publicar_com_comissao_politica(
  p_politica_id bigint,
  p_confirmacao boolean,
  p_motivo_confirmacao text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_policy public.com_comissao_politicas_pessoa%rowtype;
  v_context jsonb;
  v_before jsonb;
  v_after jsonb;
begin
  v_context := public.begin_audited_rpc(
    'financeiro.commissions.policy.manage',
    'financeiro',
    'com_comissao_politicas_pessoa',
    'status_transition',
    jsonb_build_object('event', 'commission_policy_publish')
  );

  if p_confirmacao is distinct from true then
    raise exception 'explicit policy confirmation is required';
  end if;
  if char_length(btrim(coalesce(p_motivo_confirmacao, ''))) < 10 then
    raise exception 'policy confirmation reason must have at least 10 characters';
  end if;

  select *
    into v_policy
    from public.com_comissao_politicas_pessoa
   where id = p_politica_id
   for update;

  if v_policy.id is null then raise exception 'commission policy not found'; end if;
  if v_policy.status <> 'draft' then raise exception 'commission policy is not draft'; end if;
  if v_policy.comissionavel and not exists (
    select 1 from public.com_comissao_politica_taxas_grupo rate
     where rate.politica_id = v_policy.id
  ) then
    raise exception 'commissionable policy requires at least one group rate';
  end if;

  if not v_policy.comissionavel and exists (
    select 1 from public.com_comissao_politica_taxas_grupo rate
     where rate.politica_id = v_policy.id
  ) then
    raise exception 'non-commissionable policy cannot publish group rates';
  end if;

  if exists (
    select 1
      from public.com_comissao_politicas_pessoa other_policy
     where other_policy.pessoa_id = v_policy.pessoa_id
       and other_policy.id <> v_policy.id
       and other_policy.status in ('published', 'closed')
       and daterange(
             other_policy.vigencia_inicio,
             coalesce(other_policy.vigencia_fim, 'infinity'::date),
             '[]'
           )
           &&
           daterange(
             v_policy.vigencia_inicio,
             coalesce(v_policy.vigencia_fim, 'infinity'::date),
             '[]'
           )
  ) then
    raise exception 'published commission policy effective period overlaps another policy';
  end if;

  v_before := to_jsonb(v_policy);
  v_actor := public.current_actor_id();

  update public.com_comissao_politicas_pessoa
     set status = 'published',
         published_by = v_actor,
         published_at = now()
   where id = v_policy.id;

  select to_jsonb(policy)
    into v_after
    from public.com_comissao_politicas_pessoa policy
   where policy.id = v_policy.id;

  perform public.log_audited_rpc_change(
    'financeiro', 'com_comissao_politicas_pessoa', v_policy.id::text,
    'financeiro.comissao_politica_published',
    'financeiro.commissions.policy.manage',
    v_context, v_before, v_after,
    jsonb_build_object(
      'source', 'publicar_com_comissao_politica',
      'confirmacao_explicita', true,
      'motivo_confirmacao', btrim(p_motivo_confirmacao)
    )
  );

  return v_policy.id;
end;
$$;

revoke all on function public.criar_com_comissao_politica_rascunho(
  bigint, boolean, date, date, text
) from public, anon;
revoke all on function public.definir_com_comissao_politica_taxa(
  bigint, bigint, text, numeric
) from public, anon;
revoke all on function public.publicar_com_comissao_politica(
  bigint, boolean, text
) from public, anon;

grant execute on function public.criar_com_comissao_politica_rascunho(
  bigint, boolean, date, date, text
) to authenticated;
grant execute on function public.definir_com_comissao_politica_taxa(
  bigint, bigint, text, numeric
) to authenticated;
grant execute on function public.publicar_com_comissao_politica(
  bigint, boolean, text
) to authenticated;

-- ---------------------------------------------------------------------------
-- Snapshot da estrutura comercial no pedido
-- ---------------------------------------------------------------------------

create table if not exists public.com_comissao_estrutura_snapshots (
  id bigint generated always as identity primary key,
  pedido_id bigint not null references public.com_pedidos(id),
  versao integer not null,
  pessoa_origem_id bigint references public.cad_pessoas_comerciais(id),
  data_referencia date not null,
  origem text not null default 'automatic',
  motivo text,
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint com_comissao_snapshot_versao_check check (versao > 0),
  constraint com_comissao_snapshot_origem_check
    check (origem in ('automatic', 'manual_revision')),
  constraint com_comissao_snapshot_motivo_check
    check (origem <> 'manual_revision' or char_length(btrim(coalesce(motivo, ''))) >= 10),
  unique (pedido_id, versao)
);

create table if not exists public.com_comissao_estrutura_snapshot_participantes (
  id bigint generated always as identity primary key,
  snapshot_id bigint not null references public.com_comissao_estrutura_snapshots(id) on delete restrict,
  pessoa_id bigint not null references public.cad_pessoas_comerciais(id),
  papel_comissao text not null,
  relacionamento_id bigint references public.cad_pessoa_relacionamentos_comerciais(id),
  ordem_cadeia integer not null,
  origem_participacao text not null,
  created_at timestamptz not null default now(),
  constraint com_comissao_snapshot_participante_papel_check
    check (papel_comissao in ('vendedor', 'agente', 'gerente', 'tecnico_campo', 'outro')),
  constraint com_comissao_snapshot_participante_ordem_check check (ordem_cadeia >= 0),
  constraint com_comissao_snapshot_participante_origem_check
    check (origem_participacao in ('pedido', 'relacionamento', 'manual_revision')),
  unique (snapshot_id, pessoa_id, papel_comissao)
);

alter table public.com_comissao_estrutura_snapshots enable row level security;
alter table public.com_comissao_estrutura_snapshot_participantes enable row level security;

drop policy if exists "governed read com_comissao_estrutura_snapshots"
  on public.com_comissao_estrutura_snapshots;
create policy "governed read com_comissao_estrutura_snapshots"
on public.com_comissao_estrutura_snapshots
for select to authenticated
using (public.current_actor_id() is not null);

drop policy if exists "governed read com_comissao_estrutura_snapshot_participantes"
  on public.com_comissao_estrutura_snapshot_participantes;
create policy "governed read com_comissao_estrutura_snapshot_participantes"
on public.com_comissao_estrutura_snapshot_participantes
for select to authenticated
using (public.current_actor_id() is not null);

grant select on public.com_comissao_estrutura_snapshots,
                public.com_comissao_estrutura_snapshot_participantes
to authenticated;
revoke insert, update, delete, truncate
  on public.com_comissao_estrutura_snapshots,
     public.com_comissao_estrutura_snapshot_participantes
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Metadados de origem do direito de comissao
-- ---------------------------------------------------------------------------

alter table public.com_pedido_comissionados
  add column if not exists origem_comissao text not null default 'legado',
  add column if not exists politica_id bigint references public.com_comissao_politicas_pessoa(id),
  add column if not exists politica_taxa_id bigint references public.com_comissao_politica_taxas_grupo(id),
  add column if not exists grupo_produto_id bigint references public.cad_grupos_produto(id),
  add column if not exists estrutura_snapshot_id bigint references public.com_comissao_estrutura_snapshots(id),
  add column if not exists justificativa_registro text,
  add column if not exists memoria_regra_json jsonb not null default '{}'::jsonb;

do $$
begin
  alter table public.com_pedido_comissionados
    add constraint com_pedido_comissionados_origem_check check (
      origem_comissao in (
        'legado',
        'automatica_politica',
        'estrutura_comercial',
        'manual_adicional',
        'revisao_estrutural'
      )
    );
exception when duplicate_object then null;
end;
$$;

do $$
begin
  alter table public.com_pedido_comissionados
    add constraint com_pedido_comissionados_memoria_regra_check
      check (jsonb_typeof(memoria_regra_json) = 'object');
exception when duplicate_object then null;
end;
$$;

create index if not exists idx_com_pedido_comissionados_policy
  on public.com_pedido_comissionados(politica_id, politica_taxa_id)
  where politica_id is not null;

-- ---------------------------------------------------------------------------
-- Alteracao manual em duas etapas: proposta -> confirmacao
-- ---------------------------------------------------------------------------

create table if not exists public.com_comissao_alteracao_solicitacoes (
  id uuid primary key default gen_random_uuid(),
  pedido_id bigint not null references public.com_pedidos(id),
  pessoa_id bigint not null references public.cad_pessoas_comerciais(id),
  papel_comissao text not null,
  percentual_comissao numeric not null,
  justificativa text not null,
  tipo_alteracao text not null default 'adicionar_participante',
  status text not null default 'pending',
  contexto_hash text not null,
  preview_json jsonb not null,
  comissionado_id bigint references public.com_pedido_comissionados(id),
  requested_by uuid not null references public.user_profiles(id),
  confirmed_by uuid references public.user_profiles(id),
  requested_at timestamptz not null default now(),
  confirmed_at timestamptz,
  expires_at timestamptz not null default (now() + interval '30 minutes'),
  constraint com_comissao_alt_papel_check
    check (papel_comissao in ('vendedor', 'agente', 'gerente', 'tecnico_campo', 'outro')),
  constraint com_comissao_alt_percentual_check
    check (percentual_comissao > 0 and percentual_comissao <= 100),
  constraint com_comissao_alt_justificativa_check
    check (char_length(btrim(justificativa)) >= 10),
  constraint com_comissao_alt_tipo_check
    check (tipo_alteracao in ('adicionar_participante')),
  constraint com_comissao_alt_status_check
    check (status in ('pending', 'confirmed', 'cancelled', 'expired')),
  constraint com_comissao_alt_hash_check
    check (contexto_hash ~ '^[0-9a-f]{32}$'),
  constraint com_comissao_alt_preview_check
    check (jsonb_typeof(preview_json) = 'object')
);

create index if not exists idx_com_comissao_alt_pedido_pending
  on public.com_comissao_alteracao_solicitacoes(pedido_id, requested_at desc)
  where status = 'pending';

alter table public.com_comissao_alteracao_solicitacoes enable row level security;
drop policy if exists "own read com_comissao_alteracao_solicitacoes"
  on public.com_comissao_alteracao_solicitacoes;
create policy "own read com_comissao_alteracao_solicitacoes"
on public.com_comissao_alteracao_solicitacoes
for select to authenticated
using (requested_by = public.current_actor_id());

grant select on public.com_comissao_alteracao_solicitacoes to authenticated;
revoke insert, update, delete, truncate
  on public.com_comissao_alteracao_solicitacoes
  from public, anon, authenticated;

create or replace function public.com_comissao_contexto_adicao_participante(
  p_pedido_id bigint,
  p_pessoa_id bigint,
  p_papel_comissao text
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'pedido_id', orders.id,
    'pedido_updated_at', orders.updated_at,
    'pedido_tipo', orders.tipo_pedido,
    'pedido_status', orders.status,
    'pedido_valor_total', orders.valor_total,
    'pessoa_id', person.id,
    'pessoa_updated_at', person.updated_at,
    'pessoa_status', person.status,
    'papel_comissao', p_papel_comissao,
    'recebido_ativo', coalesce((
      select sum(allocation.valor_alocado)
        from public.fin_recebimento_alocacoes allocation
        join public.com_recebimentos receipt
          on receipt.id = allocation.recebimento_id
       where allocation.pedido_id = orders.id
         and allocation.tipo_alocacao = 'recebimento'
         and receipt.status = 'active'
    ), 0),
    'comissionados_ativos_count', (
      select count(*)
        from public.com_pedido_comissionados assignment
       where assignment.pedido_id = orders.id
         and assignment.status not in ('cancelada', 'estornada')
    ),
    'comissionados_ativos_updated_at', (
      select max(assignment.updated_at)
        from public.com_pedido_comissionados assignment
       where assignment.pedido_id = orders.id
         and assignment.status not in ('cancelada', 'estornada')
    )
  )
  from public.com_pedidos orders
  join public.cad_pessoas_comerciais person on person.id = p_pessoa_id
  where orders.id = p_pedido_id
$$;

revoke all on function public.com_comissao_contexto_adicao_participante(
  bigint, bigint, text
) from public, anon;

create or replace function public.propor_com_pedido_comissao(
  p_pedido_id bigint,
  p_pessoa_id bigint,
  p_papel_comissao text,
  p_percentual_comissao numeric,
  p_justificativa text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_order public.com_pedidos%rowtype;
  v_person public.cad_pessoas_comerciais%rowtype;
  v_context jsonb;
  v_context_hash text;
  v_preview jsonb;
  v_received numeric;
  v_expected numeric;
  v_immediate numeric;
  v_id uuid;
  v_permission_context jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'financeiro.commissions.revision.request',
    'financeiro',
    'com_comissao_alteracao_solicitacoes',
    'change_type',
    jsonb_build_object('event', 'commission_change_prepare')
  );
  perform public.require_current_user_permission('pedidos.commissions.assign');

  if p_pedido_id is null or p_pedido_id <= 0 then raise exception 'pedido_id is required'; end if;
  if p_pessoa_id is null or p_pessoa_id <= 0 then raise exception 'pessoa_id is required'; end if;
  if p_papel_comissao not in ('vendedor', 'agente', 'gerente', 'tecnico_campo', 'outro') then
    raise exception 'invalid commission role';
  end if;
  if p_percentual_comissao is null or p_percentual_comissao <= 0 or p_percentual_comissao > 100 then
    raise exception 'commission percentage must be greater than zero and at most 100';
  end if;
  if char_length(btrim(coalesce(p_justificativa, ''))) < 10 then
    raise exception 'commission justification must have at least 10 characters';
  end if;

  select * into v_order
    from public.com_pedidos
   where id = p_pedido_id
   for share;

  if v_order.id is null then raise exception 'pedido not found'; end if;
  if v_order.tipo_pedido <> 'venda' then
    raise exception 'only sale orders generate commission';
  end if;
  if v_order.status not in ('open', 'fulfilled') then
    raise exception 'order status does not allow commission assignment';
  end if;

  select * into v_person
    from public.cad_pessoas_comerciais
   where id = p_pessoa_id
   for share;

  if v_person.id is null or v_person.status <> 'active' then
    raise exception 'commission person must be active';
  end if;

  if exists (
    select 1
      from public.com_pedido_comissionados assignment
     where assignment.pedido_id = p_pedido_id
       and assignment.pessoa_id = p_pessoa_id
       and assignment.papel_comissao = p_papel_comissao
       and assignment.status not in ('cancelada', 'estornada')
  ) then
    raise exception 'commission participant already exists; use structural revision flow';
  end if;

  v_context := public.com_comissao_contexto_adicao_participante(
    p_pedido_id, p_pessoa_id, p_papel_comissao
  );
  if v_context is null then raise exception 'commission context could not be resolved'; end if;
  v_context_hash := md5(v_context::text);

  v_received := greatest(coalesce((v_context->>'recebido_ativo')::numeric, 0), 0);
  v_expected := v_order.valor_total * p_percentual_comissao / 100;
  v_immediate := case
    when v_order.valor_total <= 0 then 0
    else v_expected * least(v_received / v_order.valor_total, 1)
  end;

  v_preview := jsonb_build_object(
    'pedido_id', v_order.id,
    'pedido_codigo', v_order.codigo_pedido,
    'pedido_valor_total', v_order.valor_total,
    'pessoa_id', v_person.id,
    'pessoa_nome', v_person.nome,
    'papel_comissao', p_papel_comissao,
    'percentual_comissao', p_percentual_comissao,
    'valor_previsto', v_expected,
    'valor_recebido_ativo', v_received,
    'valor_liberavel_imediato_estimado', v_immediate,
    'justificativa', btrim(p_justificativa),
    'contexto_hash', v_context_hash
  );

  v_actor := public.current_actor_id();

  insert into public.com_comissao_alteracao_solicitacoes(
    pedido_id, pessoa_id, papel_comissao, percentual_comissao,
    justificativa, tipo_alteracao, status, contexto_hash,
    preview_json, requested_by
  )
  values (
    p_pedido_id, p_pessoa_id, p_papel_comissao, p_percentual_comissao,
    btrim(p_justificativa), 'adicionar_participante', 'pending',
    v_context_hash, v_preview, v_actor
  )
  returning id into v_id;

  perform public.log_audited_rpc_change(
    'financeiro',
    'com_comissao_alteracao_solicitacoes',
    v_id::text,
    'financeiro.comissao_alteracao_preparada',
    'financeiro.commissions.revision.request',
    v_permission_context,
    null,
    jsonb_build_object('id', v_id, 'status', 'pending', 'preview', v_preview),
    jsonb_build_object(
      'source', 'propor_com_pedido_comissao',
      'double_confirmation_step', 1
    )
  );

  return jsonb_build_object(
    'solicitacao_id', v_id,
    'status', 'pending',
    'expires_at', now() + interval '30 minutes',
    'preview', v_preview
  );
end;
$$;

-- Libera, para UM novo comissionado, somente os recebimentos historicos que ainda
-- nao possuem o par allocation + commission. Nao reprocessa outros participantes.
create or replace function public.liberar_fin_comissionado_recebimentos_existentes(
  p_comissionado_id bigint
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_assignment public.com_pedido_comissionados%rowtype;
  v_order public.com_pedidos%rowtype;
  v_row record;
  v_percentage numeric;
  v_value numeric;
  v_release_id bigint;
  v_count integer := 0;
  v_context jsonb;
begin
  v_context := public.begin_audited_rpc(
    'financeiro.commissions.release',
    'financeiro',
    'com_pedido_comissionados',
    'financial_event',
    jsonb_build_object('event', 'commission_release_existing_receipts')
  );

  select * into v_assignment
    from public.com_pedido_comissionados
   where id = p_comissionado_id
   for update;

  if v_assignment.id is null then raise exception 'commission assignment not found'; end if;

  select * into v_order
    from public.com_pedidos
   where id = v_assignment.pedido_id
   for share;

  if v_order.tipo_pedido <> 'venda' or v_order.status not in ('open', 'fulfilled') then
    raise exception 'order does not allow commission release';
  end if;
  if v_order.valor_total <= 0 then return 0; end if;

  v_actor := public.current_actor_id();

  for v_row in
    select
      allocation.id as allocation_id,
      allocation.recebimento_id,
      allocation.valor_alocado,
      receipt.correlation_id
    from public.fin_recebimento_alocacoes allocation
    join public.com_recebimentos receipt
      on receipt.id = allocation.recebimento_id
   where allocation.pedido_id = v_assignment.pedido_id
     and allocation.tipo_alocacao = 'recebimento'
     and receipt.status = 'active'
     and not exists (
       select 1
         from public.com_comissao_liberacoes release
        where release.alocacao_id = allocation.id
          and release.comissionado_id = v_assignment.id
          and release.status = 'liberada'
     )
   order by allocation.id
  loop
    v_percentage := least(v_row.valor_alocado / v_order.valor_total, 1);
    v_value := v_assignment.valor_previsto * v_percentage;

    if v_value <= 0 then continue; end if;

    insert into public.com_comissao_liberacoes(
      recebimento_id, alocacao_id, pedido_id, comissionado_id,
      pessoa_id, valor_liberado, percentual_recebido_snapshot,
      status, memoria_calculo_json, correlation_id, created_by
    )
    values (
      v_row.recebimento_id,
      v_row.allocation_id,
      v_assignment.pedido_id,
      v_assignment.id,
      v_assignment.pessoa_id,
      v_value,
      v_percentage,
      'liberada',
      jsonb_build_object(
        'modelo_calculo', 'novo_participante_pos_recebimento',
        'valor_previsto_total', v_assignment.valor_previsto,
        'valor_alocado_recebimento', v_row.valor_alocado,
        'valor_liberado_neste_recebimento', v_value,
        'percentual_recebido_snapshot', v_percentage,
        'comissionado_id', v_assignment.id
      ),
      v_row.correlation_id,
      v_actor
    )
    returning id into v_release_id;

    insert into public.fin_comissao_movimentos(
      pessoa_id, pedido_id, recebimento_id, alocacao_id, liberacao_id,
      tipo_movimento, valor, memoria_calculo_json, created_by
    )
    values (
      v_assignment.pessoa_id,
      v_assignment.pedido_id,
      v_row.recebimento_id,
      v_row.allocation_id,
      v_release_id,
      'credito_liberacao',
      v_value,
      jsonb_build_object(
        'source', 'liberar_fin_comissionado_recebimentos_existentes',
        'modelo_calculo', 'novo_participante_pos_recebimento',
        'comissionado_id', v_assignment.id,
        'percentual_recebido_snapshot', v_percentage
      ),
      v_actor
    );

    v_count := v_count + 1;
  end loop;

  if v_count > 0 then
    update public.com_pedido_comissionados
       set status = 'liberada',
           updated_by = v_actor
     where id = v_assignment.id;
  end if;

  perform public.log_audited_rpc_change(
    'financeiro',
    'com_pedido_comissionados',
    v_assignment.id::text,
    'financeiro.comissao_recebimentos_existentes_liberados',
    'financeiro.commissions.release',
    v_context,
    null,
    jsonb_build_object(
      'comissionado_id', v_assignment.id,
      'pedido_id', v_assignment.pedido_id,
      'liberacoes_count', v_count
    ),
    jsonb_build_object(
      'source', 'liberar_fin_comissionado_recebimentos_existentes'
    )
  );

  return v_count;
end;
$$;

create or replace function public.confirmar_com_pedido_comissao(
  p_solicitacao_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_request public.com_comissao_alteracao_solicitacoes%rowtype;
  v_order public.com_pedidos%rowtype;
  v_context jsonb;
  v_hash text;
  v_assignment_id bigint;
  v_releases integer := 0;
  v_permission_context jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'financeiro.commissions.revision.confirm',
    'financeiro',
    'com_comissao_alteracao_solicitacoes',
    'change_type',
    jsonb_build_object('event', 'commission_change_confirm')
  );
  perform public.require_current_user_permission('pedidos.commissions.assign');

  v_actor := public.current_actor_id();

  select * into v_request
    from public.com_comissao_alteracao_solicitacoes
   where id = p_solicitacao_id
   for update;

  if v_request.id is null then raise exception 'commission change request not found'; end if;
  if v_request.status <> 'pending' then raise exception 'commission change request is not pending'; end if;
  if v_request.requested_by <> v_actor then
    raise exception 'commission change request must be confirmed by the requesting operator';
  end if;
  if v_request.expires_at <= now() then
    raise exception 'commission change request expired; prepare a new review';
  end if;

  select * into v_order
    from public.com_pedidos
   where id = v_request.pedido_id
   for update;

  if v_order.id is null then raise exception 'pedido not found'; end if;
  if v_order.tipo_pedido <> 'venda' then raise exception 'only sale orders generate commission'; end if;
  if v_order.status not in ('open', 'fulfilled') then
    raise exception 'order status does not allow commission assignment';
  end if;

  v_context := public.com_comissao_contexto_adicao_participante(
    v_request.pedido_id, v_request.pessoa_id, v_request.papel_comissao
  );
  v_hash := md5(v_context::text);

  if v_hash is distinct from v_request.contexto_hash then
    raise exception 'commission context changed after review; prepare a new confirmation';
  end if;

  if exists (
    select 1
      from public.com_pedido_comissionados assignment
     where assignment.pedido_id = v_request.pedido_id
       and assignment.pessoa_id = v_request.pessoa_id
       and assignment.papel_comissao = v_request.papel_comissao
       and assignment.status not in ('cancelada', 'estornada')
  ) then
    raise exception 'commission participant already exists; prepare a structural revision';
  end if;

  if exists (
    select 1
      from public.fin_recebimento_alocacoes allocation
      join public.com_recebimentos receipt on receipt.id = allocation.recebimento_id
     where allocation.pedido_id = v_request.pedido_id
       and allocation.tipo_alocacao = 'recebimento'
       and receipt.status = 'active'
  ) and not public.can_current_user('financeiro.commissions.release') then
    raise exception 'not allowed: financeiro.commissions.release';
  end if;

  insert into public.com_pedido_comissionados(
    pedido_id,
    pessoa_id,
    papel_comissao,
    percentual_comissao,
    valor_base,
    valor_previsto,
    status,
    origem_comissao,
    justificativa_registro,
    memoria_regra_json,
    created_by,
    updated_by
  )
  values (
    v_request.pedido_id,
    v_request.pessoa_id,
    v_request.papel_comissao,
    v_request.percentual_comissao,
    v_order.valor_total,
    v_order.valor_total * v_request.percentual_comissao / 100,
    'prevista',
    'manual_adicional',
    v_request.justificativa,
    jsonb_build_object(
      'source', 'confirmar_com_pedido_comissao',
      'solicitacao_id', v_request.id,
      'double_confirmation', true,
      'contexto_hash', v_request.contexto_hash
    ),
    v_actor,
    v_actor
  )
  returning id into v_assignment_id;

  if exists (
    select 1
      from public.fin_recebimento_alocacoes allocation
      join public.com_recebimentos receipt on receipt.id = allocation.recebimento_id
     where allocation.pedido_id = v_request.pedido_id
       and allocation.tipo_alocacao = 'recebimento'
       and receipt.status = 'active'
  ) then
    v_releases := public.liberar_fin_comissionado_recebimentos_existentes(v_assignment_id);
  end if;

  update public.com_comissao_alteracao_solicitacoes
     set status = 'confirmed',
         comissionado_id = v_assignment_id,
         confirmed_by = v_actor,
         confirmed_at = now()
   where id = v_request.id;

  perform public.log_audited_rpc_change(
    'financeiro',
    'com_comissao_alteracao_solicitacoes',
    v_request.id::text,
    'financeiro.comissao_alteracao_confirmada',
    'financeiro.commissions.revision.confirm',
    v_permission_context,
    jsonb_build_object('status', 'pending', 'preview', v_request.preview_json),
    jsonb_build_object(
      'status', 'confirmed',
      'comissionado_id', v_assignment_id,
      'liberacoes_recebimentos_existentes', v_releases
    ),
    jsonb_build_object(
      'source', 'confirmar_com_pedido_comissao',
      'double_confirmation_step', 2,
      'contexto_hash_validado', true
    )
  );

  return jsonb_build_object(
    'solicitacao_id', v_request.id,
    'status', 'confirmed',
    'comissionado_id', v_assignment_id,
    'liberacoes_recebimentos_existentes', v_releases
  );
end;
$$;

create or replace function public.cancelar_proposta_com_pedido_comissao(
  p_solicitacao_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
begin
  perform public.require_current_user_permission('financeiro.commissions.revision.request');
  v_actor := public.current_actor_id();

  update public.com_comissao_alteracao_solicitacoes
     set status = 'cancelled'
   where id = p_solicitacao_id
     and status = 'pending'
     and requested_by = v_actor;

  if not found then raise exception 'pending commission change request not found'; end if;
  return p_solicitacao_id;
end;
$$;

revoke all on function public.propor_com_pedido_comissao(
  bigint, bigint, text, numeric, text
) from public, anon;
revoke all on function public.liberar_fin_comissionado_recebimentos_existentes(
  bigint
) from public, anon;
revoke all on function public.confirmar_com_pedido_comissao(uuid)
  from public, anon;
revoke all on function public.cancelar_proposta_com_pedido_comissao(uuid)
  from public, anon;

grant execute on function public.propor_com_pedido_comissao(
  bigint, bigint, text, numeric, text
) to authenticated;
grant execute on function public.liberar_fin_comissionado_recebimentos_existentes(
  bigint
) to authenticated;
grant execute on function public.confirmar_com_pedido_comissao(uuid)
  to authenticated;
grant execute on function public.cancelar_proposta_com_pedido_comissao(uuid)
  to authenticated;

-- O entrypoint antigo permitia gravacao em uma etapa. Ele deixa de ser uma API
-- publica para evitar bypass da confirmacao revisada.
revoke execute on function public.definir_com_pedido_comissao_idempotente(
  uuid, bigint, bigint, text, numeric, text
) from authenticated;

-- ---------------------------------------------------------------------------
-- Consulta operacional: recebimento nao torna uma venda inelegivel.
-- Somente tipo e estado do pedido controlam a selecao.
-- ---------------------------------------------------------------------------

create or replace function public.buscar_fin_pedidos_comissionamento(
  p_query text default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  pedido_id bigint,
  codigo_pedido text,
  cliente_nome text,
  valor_total numeric,
  status text,
  comissionados jsonb,
  total_percentual numeric,
  total_count bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_query text := lower(nullif(btrim(p_query), ''));
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
begin
  perform public.require_current_user_permission('pedidos.commissions.assign');

  return query
  with candidates as (
    select
      orders.id,
      orders.codigo_pedido,
      clients.nome as client_name,
      orders.valor_total,
      orders.status
    from public.com_pedidos orders
    join public.cad_clientes clients on clients.id = orders.cliente_id
    where orders.tipo_pedido = 'venda'
      and orders.status in ('open', 'fulfilled')
      and (
        v_query is null
        or lower(orders.codigo_pedido) like '%' || v_query || '%'
        or lower(clients.nome) like '%' || v_query || '%'
      )
  ),
  counted as (
    select candidates.*, count(*) over() as row_count
    from candidates
  )
  select
    counted.id,
    counted.codigo_pedido,
    counted.client_name,
    counted.valor_total,
    counted.status,
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'pessoa_id', assignment.pessoa_id,
        'pessoa_nome', person.nome,
        'papel', assignment.papel_comissao,
        'percentual', assignment.percentual_comissao,
        'valor_previsto', assignment.valor_previsto,
        'status', assignment.status,
        'origem', assignment.origem_comissao
      ) order by assignment.id)
      from public.com_pedido_comissionados assignment
      join public.cad_pessoas_comerciais person on person.id = assignment.pessoa_id
      where assignment.pedido_id = counted.id
        and assignment.status not in ('estornada', 'cancelada')
    ), '[]'::jsonb),
    coalesce((
      select sum(assignment.percentual_comissao)
      from public.com_pedido_comissionados assignment
      where assignment.pedido_id = counted.id
        and assignment.status not in ('estornada', 'cancelada')
    ), 0)::numeric,
    counted.row_count
  from counted
  order by counted.codigo_pedido desc
  limit v_limit offset v_offset;
end;
$$;

create or replace function public.consultar_fin_pedido_comissionamento(
  p_pedido_id bigint
)
returns table (
  pedido_id bigint,
  codigo_pedido text,
  cliente_nome text,
  valor_total numeric,
  status text,
  tipo_pedido text,
  elegivel boolean,
  motivo_inelegibilidade text,
  valor_recebido numeric,
  comissionados jsonb,
  total_percentual numeric
)
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_permission('pedidos.commissions.assign');

  return query
  select
    orders.id,
    orders.codigo_pedido,
    client.nome,
    orders.valor_total,
    orders.status,
    orders.tipo_pedido,
    (orders.tipo_pedido = 'venda' and orders.status in ('open', 'fulfilled')) as eligible,
    case
      when orders.tipo_pedido <> 'venda'
        then 'Somente pedidos de venda podem gerar comissao.'
      when orders.status not in ('open', 'fulfilled')
        then 'O pedido ainda nao esta em situacao operacional que permita comissionamento.'
      else null
    end,
    coalesce((
      select sum(allocation.valor_alocado)
        from public.fin_recebimento_alocacoes allocation
        join public.com_recebimentos receipt
          on receipt.id = allocation.recebimento_id
       where allocation.pedido_id = orders.id
         and allocation.tipo_alocacao = 'recebimento'
         and receipt.status = 'active'
    ), 0)::numeric,
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'pessoa_id', assignment.pessoa_id,
        'pessoa_nome', person.nome,
        'papel', assignment.papel_comissao,
        'percentual', assignment.percentual_comissao,
        'valor_previsto', assignment.valor_previsto,
        'status', assignment.status,
        'origem', assignment.origem_comissao
      ) order by assignment.id)
      from public.com_pedido_comissionados assignment
      join public.cad_pessoas_comerciais person on person.id = assignment.pessoa_id
      where assignment.pedido_id = orders.id
        and assignment.status not in ('estornada', 'cancelada')
    ), '[]'::jsonb),
    coalesce((
      select sum(assignment.percentual_comissao)
        from public.com_pedido_comissionados assignment
       where assignment.pedido_id = orders.id
         and assignment.status not in ('estornada', 'cancelada')
    ), 0)::numeric
  from public.com_pedidos orders
  join public.cad_clientes client on client.id = orders.cliente_id
  where orders.id = p_pedido_id;
end;
$$;

revoke all on function public.buscar_fin_pedidos_comissionamento(
  text, integer, integer
) from public, anon;
revoke all on function public.consultar_fin_pedido_comissionamento(bigint)
  from public, anon;
grant execute on function public.buscar_fin_pedidos_comissionamento(
  text, integer, integer
) to authenticated;
grant execute on function public.consultar_fin_pedido_comissionamento(bigint)
  to authenticated;

comment on function public.buscar_fin_pedidos_comissionamento(text, integer, integer) is
  'Lista vendas open/fulfilled para comissionamento. Recebimento parcial ou total nao remove elegibilidade.';
comment on function public.consultar_fin_pedido_comissionamento(bigint) is
  'Resolve o pedido diretamente por ID e explica inelegibilidade; nao depende da pagina atual da listagem.';
