-- PRC-03B: governed, versioned raw-material valuation snapshots.
-- This migration reads Stock/Cadastros facts but never writes Stock or PCP.

insert into public.permission_actions(
  action_key, module, description, default_allowed, sort_order,
  runtime_module_key, runtime_access_kind
)
values
  ('precificacao.valuation.manage', 'precificacao', 'Criar politicas e referencias versionadas de valoracao', false, 859, 'precificacao', 'write'),
  ('precificacao.valuation.review', 'precificacao', 'Aprovar ou rejeitar politicas e referencias de valoracao', false, 860, 'precificacao', 'write'),
  ('precificacao.valuation.lifecycle', 'precificacao', 'Ativar, substituir ou retirar contratos de valoracao', false, 861, 'precificacao', 'write'),
  ('precificacao.valuation.execute', 'precificacao', 'Executar snapshot de valoracao de materia-prima', false, 862, 'precificacao', 'write')
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

create sequence public.prc_valoracao_codigo_seq
  as bigint minvalue 1 maxvalue 99999999 no cycle;
create sequence public.prc_valoracao_referencia_codigo_seq
  as bigint minvalue 1 maxvalue 99999999 no cycle;

revoke all on sequence public.prc_valoracao_codigo_seq from public, anon, authenticated;
revoke all on sequence public.prc_valoracao_referencia_codigo_seq from public, anon, authenticated;

create table public.prc_valoracao_politicas (
  id bigint generated always as identity primary key,
  codigo text not null unique check (codigo ~ '^VAL-[0-9]{8}$'),
  nome text not null check (length(btrim(nome)) between 3 and 120),
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp()
);

create table public.prc_valoracao_versoes (
  id bigint generated always as identity primary key,
  politica_id bigint not null references public.prc_valoracao_politicas(id) on delete restrict,
  versao integer not null check (versao > 0),
  source_kind text not null check (source_kind in ('STOCK_ACQUISITION_LAYER','APPROVED_MANUAL_REFERENCE')),
  valuation_method text not null check (valuation_method in (
    'WEIGHTED_AVAILABLE_BALANCE','LATEST_ELIGIBLE_ACQUISITION','APPROVED_MANUAL_REFERENCE'
  )),
  time_basis text not null check (time_basis = 'CURRENT_STATE'),
  missing_expiry_behavior text not null check (missing_expiry_behavior = 'ALLOW_UNKNOWN'),
  currency_behavior text not null check (currency_behavior = 'SINGLE_CURRENCY_ONLY'),
  algorithm_version text not null check (algorithm_version = 'prc-valuation-v1'),
  manual_reference_kind text check (manual_reference_kind in ('MARKET','STANDARD','REPLACEMENT')),
  documento_json jsonb not null check (jsonb_typeof(documento_json) = 'object'),
  documento_sha256 text not null check (documento_sha256 ~ '^[0-9a-f]{64}$'),
  motivo text not null check (length(btrim(motivo)) >= 10),
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  unique (politica_id, versao),
  check (
    (source_kind = 'STOCK_ACQUISITION_LAYER'
      and valuation_method in ('WEIGHTED_AVAILABLE_BALANCE','LATEST_ELIGIBLE_ACQUISITION')
      and manual_reference_kind is null)
    or
    (source_kind = 'APPROVED_MANUAL_REFERENCE'
      and valuation_method = 'APPROVED_MANUAL_REFERENCE'
      and manual_reference_kind is not null)
  )
);

create table public.prc_valoracao_revisoes (
  id bigint generated always as identity primary key,
  valoracao_versao_id bigint not null references public.prc_valoracao_versoes(id) on delete restrict,
  decisao text not null check (decisao in ('PENDING','APPROVED','REJECTED')),
  justificativa text not null check (length(btrim(justificativa)) >= 10),
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp()
);
create unique index uq_prc_valoracao_revisao_final
  on public.prc_valoracao_revisoes(valoracao_versao_id)
  where decisao in ('APPROVED','REJECTED');

create table public.prc_valoracao_lifecycle_eventos (
  id bigint generated always as identity primary key,
  valoracao_versao_id bigint not null references public.prc_valoracao_versoes(id) on delete restrict,
  estado text not null check (estado in ('ACTIVE','SUPERSEDED','WITHDRAWN')),
  justificativa text not null check (length(btrim(justificativa)) >= 10),
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp()
);

create table public.prc_valoracao_referencias (
  id bigint generated always as identity primary key,
  codigo text not null unique check (codigo ~ '^REF-[0-9]{8}$'),
  materia_prima_id bigint not null references public.cad_materias_primas(id) on delete restrict,
  reference_kind text not null check (reference_kind in ('MARKET','STANDARD','REPLACEMENT')),
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp()
);

create table public.prc_valoracao_referencia_versoes (
  id bigint generated always as identity primary key,
  referencia_id bigint not null references public.prc_valoracao_referencias(id) on delete restrict,
  versao integer not null check (versao > 0),
  moeda text not null check (moeda ~ '^[A-Z]{3}$'),
  unidade_base text not null check (length(btrim(unidade_base)) > 0),
  valor_unitario numeric not null check (valor_unitario >= 0),
  data_referencia date not null,
  vigencia_inicio timestamptz not null,
  vigencia_fim timestamptz,
  fonte text not null check (length(btrim(fonte)) >= 3),
  documento_referencia text,
  motivo text not null check (length(btrim(motivo)) >= 10),
  documento_json jsonb not null check (jsonb_typeof(documento_json) = 'object'),
  documento_sha256 text not null check (documento_sha256 ~ '^[0-9a-f]{64}$'),
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  unique (referencia_id, versao),
  check (vigencia_fim is null or vigencia_fim >= vigencia_inicio)
);

create table public.prc_valoracao_referencia_revisoes (
  id bigint generated always as identity primary key,
  referencia_versao_id bigint not null references public.prc_valoracao_referencia_versoes(id) on delete restrict,
  decisao text not null check (decisao in ('PENDING','APPROVED','REJECTED')),
  justificativa text not null check (length(btrim(justificativa)) >= 10),
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp()
);
create unique index uq_prc_val_ref_revisao_final
  on public.prc_valoracao_referencia_revisoes(referencia_versao_id)
  where decisao in ('APPROVED','REJECTED');

create table public.prc_valoracao_referencia_lifecycle_eventos (
  id bigint generated always as identity primary key,
  referencia_versao_id bigint not null references public.prc_valoracao_referencia_versoes(id) on delete restrict,
  estado text not null check (estado in ('ACTIVE','SUPERSEDED','WITHDRAWN')),
  justificativa text not null check (length(btrim(justificativa)) >= 10),
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp()
);

create table public.prc_valoracao_snapshots (
  id bigint generated always as identity primary key,
  valoracao_versao_id bigint not null references public.prc_valoracao_versoes(id) on delete restrict,
  referencia_versao_id bigint references public.prc_valoracao_referencia_versoes(id) on delete restrict,
  materia_prima_id bigint not null references public.cad_materias_primas(id) on delete restrict,
  source_kind text not null check (source_kind in ('STOCK_ACQUISITION_LAYER','APPROVED_MANUAL_REFERENCE')),
  valuation_method text not null check (valuation_method in (
    'WEIGHTED_AVAILABLE_BALANCE','LATEST_ELIGIBLE_ACQUISITION','APPROVED_MANUAL_REFERENCE'
  )),
  evaluated_at timestamptz not null,
  moeda text not null check (moeda ~ '^[A-Z]{3}$'),
  unidade_base text not null check (length(btrim(unidade_base)) > 0),
  quantidade_total numeric not null check (quantidade_total > 0),
  custo_total numeric not null check (custo_total >= 0),
  custo_unitario_exato numeric not null check (custo_unitario_exato >= 0),
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  documento_json jsonb not null check (jsonb_typeof(documento_json) = 'object'),
  documento_sha256 text not null check (documento_sha256 ~ '^[0-9a-f]{64}$'),
  input_sha256 text not null check (input_sha256 ~ '^[0-9a-f]{64}$'),
  result_sha256 text not null check (result_sha256 ~ '^[0-9a-f]{64}$'),
  motivo text not null check (length(btrim(motivo)) >= 10),
  created_at timestamptz not null default clock_timestamp()
);

create table public.prc_valoracao_snapshot_camadas (
  id bigint generated always as identity primary key,
  snapshot_id bigint not null references public.prc_valoracao_snapshots(id) on delete restrict,
  lote_mp_id bigint not null references public.est_lotes_mp(id) on delete restrict,
  movimento_mp_id bigint not null references public.est_movimentos_mp(id) on delete restrict,
  movimento_valor_id bigint not null references public.est_movimentos_mp_valores(id) on delete restrict,
  ordem_fifo integer not null check (ordem_fifo > 0),
  quantidade_original numeric not null check (quantidade_original > 0),
  quantidade_consumida numeric not null check (quantidade_consumida >= 0),
  quantidade_remanescente numeric not null check (quantidade_remanescente >= 0),
  quantidade_reservada_atribuida numeric not null check (quantidade_reservada_atribuida >= 0),
  quantidade_disponivel_usada numeric not null check (quantidade_disponivel_usada >= 0),
  custo_unitario numeric not null check (custo_unitario >= 0),
  moeda text not null check (moeda ~ '^[A-Z]{3}$'),
  contribuicao_custo_total numeric not null check (contribuicao_custo_total >= 0),
  unique (snapshot_id, movimento_valor_id),
  check (quantidade_reservada_atribuida <= quantidade_remanescente),
  check (quantidade_disponivel_usada <= quantidade_remanescente),
  check (quantidade_reservada_atribuida + quantidade_disponivel_usada <= quantidade_remanescente),
  check (quantidade_disponivel_usada > 0 or contribuicao_custo_total = 0)
);

create table public.prc_valoracao_snapshot_exclusoes (
  id bigint generated always as identity primary key,
  snapshot_id bigint not null references public.prc_valoracao_snapshots(id) on delete restrict,
  lote_mp_id bigint references public.est_lotes_mp(id) on delete restrict,
  movimento_valor_id bigint references public.est_movimentos_mp_valores(id) on delete restrict,
  reason_code text not null check (reason_code in ('EXPIRY_UNKNOWN_ALLOWED','MANUAL_REFERENCE')),
  detalhes_json jsonb not null default '{}'::jsonb check (jsonb_typeof(detalhes_json) = 'object')
);

alter table public.prc_requisicoes
  drop constraint if exists prc_requisicoes_request_type_check;
alter table public.prc_requisicoes
  add constraint prc_requisicoes_request_type_check check (request_type in (
    'policy','policy_review','scenario','calculation','calculation_review',
    'formula_grid','formula_version','formula_review','formula_lifecycle','formula_shadow',
    'valuation_policy','valuation_policy_review','valuation_policy_lifecycle',
    'valuation_reference','valuation_reference_review','valuation_reference_lifecycle',
    'valuation_execute'
  ));

create or replace function public.prevent_prc_valoracao_fact_changes()
returns trigger language plpgsql set search_path = public as $$
begin
  raise exception 'fato de valoracao e append-only';
end;
$$;

do $$
declare v_table text;
begin
  foreach v_table in array array[
    'prc_valoracao_politicas','prc_valoracao_versoes','prc_valoracao_revisoes',
    'prc_valoracao_lifecycle_eventos','prc_valoracao_referencias',
    'prc_valoracao_referencia_versoes','prc_valoracao_referencia_revisoes',
    'prc_valoracao_referencia_lifecycle_eventos','prc_valoracao_snapshots',
    'prc_valoracao_snapshot_camadas','prc_valoracao_snapshot_exclusoes'
  ] loop
    execute format('create trigger %I before update or delete on public.%I for each row execute function public.prevent_prc_valoracao_fact_changes()', 'trg_' || v_table || '_append_only', v_table);
    execute format('create trigger %I before truncate on public.%I for each statement execute function public.prevent_prc_valoracao_fact_changes()', 'trg_' || v_table || '_no_truncate', v_table);
    execute format('alter table public.%I enable row level security', v_table);
    execute format('revoke all on table public.%I from public, anon, authenticated', v_table);
  end loop;
end;
$$;

create schema if not exists precificacao_internal;
revoke all on schema precificacao_internal from public, anon, authenticated;

create or replace function precificacao_internal.prc_valoracao_versao_sha256(p_versao_id bigint)
returns text language plpgsql security definer set search_path = public as $$
declare v public.prc_valoracao_versoes%rowtype;
begin
  select * into v from public.prc_valoracao_versoes where id = p_versao_id;
  if not found then raise exception 'versao de valoracao inexistente'; end if;
  if v.documento_sha256 is distinct from public.prc_sha256(v.documento_json) then
    raise exception 'hash da politica de valoracao diverge';
  end if;
  return v.documento_sha256;
end;
$$;

create or replace function precificacao_internal.prc_valoracao_referencia_sha256(p_versao_id bigint)
returns text language plpgsql security definer set search_path = public as $$
declare v public.prc_valoracao_referencia_versoes%rowtype;
begin
  select * into v from public.prc_valoracao_referencia_versoes where id = p_versao_id;
  if not found then raise exception 'referencia de valoracao inexistente'; end if;
  if v.documento_sha256 is distinct from public.prc_sha256(v.documento_json) then
    raise exception 'hash da referencia de valoracao diverge';
  end if;
  return v.documento_sha256;
end;
$$;

create or replace function precificacao_internal.prc_valoracao_snapshot_sha256(p_snapshot_id bigint)
returns text language plpgsql security definer set search_path = public as $$
declare v public.prc_valoracao_snapshots%rowtype;
begin
  select * into v from public.prc_valoracao_snapshots where id = p_snapshot_id;
  if not found then raise exception 'snapshot de valoracao inexistente'; end if;
  if v.documento_sha256 is distinct from public.prc_sha256(v.documento_json) then
    raise exception 'hash integral do snapshot de valoracao diverge';
  end if;
  return v.documento_sha256;
end;
$$;

create or replace function precificacao_internal.prc_valoracao_unidade_compativel(
  p_materia_prima_id bigint, p_unidade_origem text, p_unidade_base text, p_at timestamptz
)
returns boolean language sql stable security definer set search_path = public as $$
  select lower(btrim(p_unidade_origem)) = lower(btrim(p_unidade_base))
  or exists (
    select 1
      from public.cad_conversoes_unidade_mp c
     where c.materia_prima_id = p_materia_prima_id
       and lower(btrim(c.unidade_origem)) = lower(btrim(p_unidade_origem))
       and lower(btrim(c.unidade_destino)) = lower(btrim(p_unidade_base))
       and c.review_status = 'approved'
       and (c.vigencia_inicio is null or c.vigencia_inicio <= p_at::date)
       and (c.vigencia_fim is null or c.vigencia_fim >= p_at::date)
  );
$$;

create or replace function public.salvar_prc_valoracao_versao_idempotente(
  p_key uuid,
  p_politica_id bigint,
  p_nome text,
  p_source_kind text,
  p_valuation_method text,
  p_missing_expiry_behavior text,
  p_manual_reference_kind text,
  p_motivo text
)
returns bigint language plpgsql security definer set search_path = public as $$
declare
  v_ctx jsonb; v_actor uuid; v_payload jsonb; v_existing bigint;
  v_policy public.prc_valoracao_politicas%rowtype; v_versao integer;
  v_doc jsonb; v_id bigint; v_codigo_num bigint;
begin
  v_ctx := public.begin_audited_rpc('precificacao.valuation.manage','precificacao','prc_valoracao_versoes','change_type',jsonb_build_object('correlation_id',p_key::text));
  v_actor := public.current_actor_id();
  v_payload := jsonb_build_object(
    'politica_id',p_politica_id,'nome',case when p_politica_id is null then btrim(p_nome) else null end,
    'source_kind',upper(btrim(p_source_kind)),'valuation_method',upper(btrim(p_valuation_method)),
    'missing_expiry_behavior',upper(btrim(p_missing_expiry_behavior)),
    'manual_reference_kind',upper(nullif(btrim(p_manual_reference_kind),'')),'motivo',btrim(p_motivo)
  );
  perform public.prc_lock_idempotency_key(p_key);
  v_existing := public.prc_idempotent_result(p_key,'valuation_policy',v_payload);
  if v_existing is not null then return v_existing; end if;
  if upper(btrim(p_source_kind)) not in ('STOCK_ACQUISITION_LAYER','APPROVED_MANUAL_REFERENCE')
     or upper(btrim(p_valuation_method)) not in ('WEIGHTED_AVAILABLE_BALANCE','LATEST_ELIGIBLE_ACQUISITION','APPROVED_MANUAL_REFERENCE')
     or upper(btrim(p_missing_expiry_behavior)) <> 'ALLOW_UNKNOWN'
     or length(btrim(coalesce(p_motivo,''))) < 10 then
    raise exception 'politica de valoracao invalida';
  end if;
  if (upper(btrim(p_source_kind))='STOCK_ACQUISITION_LAYER' and (
        upper(btrim(p_valuation_method)) not in ('WEIGHTED_AVAILABLE_BALANCE','LATEST_ELIGIBLE_ACQUISITION')
        or nullif(btrim(p_manual_reference_kind),'') is not null))
     or (upper(btrim(p_source_kind))='APPROVED_MANUAL_REFERENCE' and (
        upper(btrim(p_valuation_method)) <> 'APPROVED_MANUAL_REFERENCE'
        or upper(nullif(btrim(p_manual_reference_kind),'')) not in ('MARKET','STANDARD','REPLACEMENT'))) then
    raise exception 'source e metodo de valoracao incompativeis';
  end if;
  if p_politica_id is null then
    if length(btrim(coalesce(p_nome,''))) not between 3 and 120 then raise exception 'nome de politica de valoracao invalido'; end if;
    begin v_codigo_num := nextval('public.prc_valoracao_codigo_seq');
    exception when sqlstate '2200H' then raise exception 'codigo de valoracao esgotado'; end;
    insert into public.prc_valoracao_politicas(codigo,nome,created_by)
    values(format('VAL-%s',lpad(v_codigo_num::text,8,'0')),btrim(p_nome),v_actor) returning * into v_policy;
  else
    select * into v_policy from public.prc_valoracao_politicas where id=p_politica_id;
    if not found then raise exception 'politica de valoracao inexistente'; end if;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('prc-valuation-policy:'||v_policy.id::text,0));
  select coalesce(max(versao),0)+1 into v_versao from public.prc_valoracao_versoes where politica_id=v_policy.id;
  v_doc := jsonb_build_object(
    'schema','prc-valuation-policy-v1','algorithm_version','prc-valuation-v1',
    'policy_id',v_policy.id,'code',v_policy.codigo,'name',v_policy.nome,'version',v_versao,
    'source_kind',upper(btrim(p_source_kind)),'valuation_method',upper(btrim(p_valuation_method)),
    'time_basis','CURRENT_STATE','missing_expiry_behavior','ALLOW_UNKNOWN',
    'currency_behavior','SINGLE_CURRENCY_ONLY',
    'manual_reference_kind',upper(nullif(btrim(p_manual_reference_kind),''))
  );
  insert into public.prc_valoracao_versoes(
    politica_id,versao,source_kind,valuation_method,time_basis,missing_expiry_behavior,
    currency_behavior,algorithm_version,manual_reference_kind,documento_json,documento_sha256,motivo,created_by
  ) values (
    v_policy.id,v_versao,upper(btrim(p_source_kind)),upper(btrim(p_valuation_method)),'CURRENT_STATE',
    'ALLOW_UNKNOWN','SINGLE_CURRENCY_ONLY','prc-valuation-v1',upper(nullif(btrim(p_manual_reference_kind),'')),
    v_doc,public.prc_sha256(v_doc),btrim(p_motivo),v_actor
  ) returning id into v_id;
  insert into public.prc_valoracao_revisoes(valoracao_versao_id,decisao,justificativa,actor_id)
  values(v_id,'PENDING','Aguardando revisao segregada da politica de valoracao',v_actor);
  insert into public.prc_requisicoes values(p_key,'valuation_policy',v_actor,public.prc_sha256(v_payload),v_id,clock_timestamp());
  perform public.log_audited_rpc_change('precificacao','prc_valoracao_versoes',v_id::text,'precificacao.valoracao_politica_criada','precificacao.valuation.manage',v_ctx,null,v_doc,jsonb_build_object('motivo',btrim(p_motivo)),'database_rpc');
  return v_id;
end;
$$;

create or replace function public.revisar_prc_valoracao_versao_idempotente(
  p_key uuid,p_versao_id bigint,p_decisao text,p_justificativa text
) returns bigint language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb; v_actor uuid; v_payload jsonb; v_existing bigint; v_creator uuid; v_id bigint;
begin
  v_ctx:=public.begin_audited_rpc('precificacao.valuation.review','precificacao','prc_valoracao_revisoes','status_transition',jsonb_build_object('correlation_id',p_key::text));
  v_actor:=public.current_actor_id();
  v_payload:=jsonb_build_object('versao_id',p_versao_id,'decisao',upper(btrim(p_decisao)),'justificativa',btrim(p_justificativa));
  perform public.prc_lock_idempotency_key(p_key); v_existing:=public.prc_idempotent_result(p_key,'valuation_policy_review',v_payload); if v_existing is not null then return v_existing; end if;
  select created_by into v_creator from public.prc_valoracao_versoes where id=p_versao_id;
  if v_creator is null or v_creator=v_actor then raise exception 'criador nao pode aprovar ou rejeitar a propria politica de valoracao'; end if;
  if upper(btrim(p_decisao)) not in ('APPROVED','REJECTED') or length(btrim(coalesce(p_justificativa,'')))<10 then raise exception 'revisao de valoracao invalida'; end if;
  insert into public.prc_valoracao_revisoes(valoracao_versao_id,decisao,justificativa,actor_id) values(p_versao_id,upper(btrim(p_decisao)),btrim(p_justificativa),v_actor) returning id into v_id;
  insert into public.prc_requisicoes values(p_key,'valuation_policy_review',v_actor,public.prc_sha256(v_payload),v_id,clock_timestamp());
  perform public.log_audited_rpc_change('precificacao','prc_valoracao_revisoes',v_id::text,'precificacao.valoracao_politica_revisada','precificacao.valuation.review',v_ctx,null,jsonb_build_object('decisao',upper(btrim(p_decisao))),jsonb_build_object('versao_id',p_versao_id),'database_rpc');
  return v_id;
end;
$$;

create or replace function public.alterar_prc_valoracao_lifecycle_idempotente(
  p_key uuid,p_versao_id bigint,p_estado text,p_justificativa text
) returns bigint language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb; v_actor uuid; v_payload jsonb; v_existing bigint; v_policy bigint; v_decisao text; v_state text; v_old record; v_id bigint;
begin
  v_ctx:=public.begin_audited_rpc('precificacao.valuation.lifecycle','precificacao','prc_valoracao_lifecycle_eventos','status_transition',jsonb_build_object('correlation_id',p_key::text));
  v_actor:=public.current_actor_id();
  v_payload:=jsonb_build_object('versao_id',p_versao_id,'estado',upper(btrim(p_estado)),'justificativa',btrim(p_justificativa));
  perform public.prc_lock_idempotency_key(p_key); v_existing:=public.prc_idempotent_result(p_key,'valuation_policy_lifecycle',v_payload); if v_existing is not null then return v_existing; end if;
  select politica_id into v_policy from public.prc_valoracao_versoes where id=p_versao_id;
  if v_policy is null then raise exception 'lifecycle de valoracao invalido'; end if;
  perform pg_advisory_xact_lock(hashtextextended('prc-valuation-policy-lifecycle:'||v_policy::text,0));
  select decisao into v_decisao from public.prc_valoracao_revisoes where valoracao_versao_id=p_versao_id order by created_at desc,id desc limit 1;
  select estado into v_state from public.prc_valoracao_lifecycle_eventos where valoracao_versao_id=p_versao_id order by created_at desc,id desc limit 1;
  if upper(btrim(p_estado)) not in ('ACTIVE','WITHDRAWN') or length(btrim(coalesce(p_justificativa,'')))<10 then raise exception 'lifecycle de valoracao invalido'; end if;
  if upper(btrim(p_estado))='ACTIVE' then
    if v_decisao<>'APPROVED' then raise exception 'somente politica de valoracao aprovada pode ser ativada'; end if;
    if v_state in ('SUPERSEDED','WITHDRAWN') then raise exception 'politica de valoracao historica nao pode ser reativada'; end if;
    for v_old in
      select v.id from public.prc_valoracao_versoes v
      join lateral (select e.estado from public.prc_valoracao_lifecycle_eventos e where e.valoracao_versao_id=v.id order by e.created_at desc,e.id desc limit 1) e on true
      where v.politica_id=v_policy and e.estado='ACTIVE' and v.id<>p_versao_id
    loop
      insert into public.prc_valoracao_lifecycle_eventos(valoracao_versao_id,estado,justificativa,actor_id)
      values(v_old.id,'SUPERSEDED','Substituida por nova politica de valoracao ativa',v_actor);
    end loop;
  elsif v_state is null then
    raise exception 'somente politica de valoracao ativa pode ser retirada';
  end if;
  insert into public.prc_valoracao_lifecycle_eventos(valoracao_versao_id,estado,justificativa,actor_id) values(p_versao_id,upper(btrim(p_estado)),btrim(p_justificativa),v_actor) returning id into v_id;
  insert into public.prc_requisicoes values(p_key,'valuation_policy_lifecycle',v_actor,public.prc_sha256(v_payload),v_id,clock_timestamp());
  perform public.log_audited_rpc_change('precificacao','prc_valoracao_lifecycle_eventos',v_id::text,'precificacao.valoracao_politica_lifecycle','precificacao.valuation.lifecycle',v_ctx,null,jsonb_build_object('estado',upper(btrim(p_estado))),jsonb_build_object('versao_id',p_versao_id),'database_rpc');
  return v_id;
end;
$$;

create or replace function public.salvar_prc_valoracao_referencia_versao_idempotente(
  p_key uuid,p_referencia_id bigint,p_materia_prima_id bigint,p_reference_kind text,p_moeda text,p_unidade_base text,
  p_valor_unitario numeric,p_data_referencia date,p_vigencia_inicio timestamptz,p_vigencia_fim timestamptz,
  p_fonte text,p_documento_referencia text,p_motivo text
) returns bigint language plpgsql security definer set search_path=public as $$
declare
  v_ctx jsonb; v_actor uuid; v_payload jsonb; v_existing bigint; v_ref public.prc_valoracao_referencias%rowtype;
  v_versao integer; v_doc jsonb; v_id bigint; v_codigo_num bigint; v_base text;
begin
  v_ctx:=public.begin_audited_rpc('precificacao.valuation.manage','precificacao','prc_valoracao_referencia_versoes','change_type',jsonb_build_object('correlation_id',p_key::text));
  v_actor:=public.current_actor_id();
  v_payload:=jsonb_build_object('referencia_id',p_referencia_id,'materia_prima_id',p_materia_prima_id,'reference_kind',upper(btrim(p_reference_kind)),'moeda',upper(btrim(p_moeda)),'unidade_base',lower(btrim(p_unidade_base)),'valor_unitario',p_valor_unitario,'data_referencia',p_data_referencia,'vigencia_inicio',p_vigencia_inicio,'vigencia_fim',p_vigencia_fim,'fonte',btrim(p_fonte),'documento_referencia',nullif(btrim(p_documento_referencia),''),'motivo',btrim(p_motivo));
  perform public.prc_lock_idempotency_key(p_key); v_existing:=public.prc_idempotent_result(p_key,'valuation_reference',v_payload); if v_existing is not null then return v_existing; end if;
  if upper(btrim(p_reference_kind)) not in ('MARKET','STANDARD','REPLACEMENT') or upper(btrim(p_moeda)) !~ '^[A-Z]{3}$'
     or p_valor_unitario is null or p_valor_unitario<0 or p_data_referencia is null or p_vigencia_inicio is null
     or (p_vigencia_fim is not null and p_vigencia_fim<p_vigencia_inicio)
     or length(btrim(coalesce(p_fonte,'')))<3 or length(btrim(coalesce(p_motivo,'')))<10 then raise exception 'referencia de valoracao invalida'; end if;
  select unidade_base_estoque into v_base from public.cad_materias_primas where id=p_materia_prima_id;
  if v_base is null or not precificacao_internal.prc_valoracao_unidade_compativel(p_materia_prima_id,p_unidade_base,v_base,transaction_timestamp()) then raise exception 'unidade da referencia incompativel'; end if;
  if p_referencia_id is null then
    begin v_codigo_num:=nextval('public.prc_valoracao_referencia_codigo_seq'); exception when sqlstate '2200H' then raise exception 'codigo de referencia esgotado'; end;
    insert into public.prc_valoracao_referencias(codigo,materia_prima_id,reference_kind,created_by)
    values(format('REF-%s',lpad(v_codigo_num::text,8,'0')),p_materia_prima_id,upper(btrim(p_reference_kind)),v_actor) returning * into v_ref;
  else
    select * into v_ref from public.prc_valoracao_referencias where id=p_referencia_id;
    if not found or v_ref.materia_prima_id<>p_materia_prima_id or v_ref.reference_kind<>upper(btrim(p_reference_kind)) then raise exception 'identidade da referencia diverge'; end if;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('prc-valuation-reference:'||v_ref.id::text,0));
  select coalesce(max(versao),0)+1 into v_versao from public.prc_valoracao_referencia_versoes where referencia_id=v_ref.id;
  v_doc:=jsonb_build_object('schema','prc-valuation-reference-v1','reference_id',v_ref.id,'code',v_ref.codigo,'version',v_versao,'materia_prima_id',v_ref.materia_prima_id,'reference_kind',v_ref.reference_kind,'currency',upper(btrim(p_moeda)),'base_unit',lower(btrim(p_unidade_base)),'unit_value',p_valor_unitario::text,'reference_date',p_data_referencia,'valid_from',p_vigencia_inicio,'valid_until',p_vigencia_fim,'source',btrim(p_fonte),'source_document',nullif(btrim(p_documento_referencia),''));
  insert into public.prc_valoracao_referencia_versoes(referencia_id,versao,moeda,unidade_base,valor_unitario,data_referencia,vigencia_inicio,vigencia_fim,fonte,documento_referencia,motivo,documento_json,documento_sha256,created_by)
  values(v_ref.id,v_versao,upper(btrim(p_moeda)),lower(btrim(p_unidade_base)),p_valor_unitario,p_data_referencia,p_vigencia_inicio,p_vigencia_fim,btrim(p_fonte),nullif(btrim(p_documento_referencia),''),btrim(p_motivo),v_doc,public.prc_sha256(v_doc),v_actor) returning id into v_id;
  insert into public.prc_valoracao_referencia_revisoes(referencia_versao_id,decisao,justificativa,actor_id)
  values(v_id,'PENDING','Aguardando revisao segregada da referencia de valoracao',v_actor);
  insert into public.prc_requisicoes values(p_key,'valuation_reference',v_actor,public.prc_sha256(v_payload),v_id,clock_timestamp());
  perform public.log_audited_rpc_change('precificacao','prc_valoracao_referencia_versoes',v_id::text,'precificacao.valoracao_referencia_criada','precificacao.valuation.manage',v_ctx,null,v_doc,jsonb_build_object('motivo',btrim(p_motivo)),'database_rpc');
  return v_id;
end;
$$;

create or replace function public.revisar_prc_valoracao_referencia_idempotente(
  p_key uuid,p_versao_id bigint,p_decisao text,p_justificativa text
) returns bigint language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb; v_actor uuid; v_payload jsonb; v_existing bigint; v_creator uuid; v_id bigint;
begin
  v_ctx:=public.begin_audited_rpc('precificacao.valuation.review','precificacao','prc_valoracao_referencia_revisoes','status_transition',jsonb_build_object('correlation_id',p_key::text)); v_actor:=public.current_actor_id();
  v_payload:=jsonb_build_object('versao_id',p_versao_id,'decisao',upper(btrim(p_decisao)),'justificativa',btrim(p_justificativa));
  perform public.prc_lock_idempotency_key(p_key); v_existing:=public.prc_idempotent_result(p_key,'valuation_reference_review',v_payload); if v_existing is not null then return v_existing; end if;
  select created_by into v_creator from public.prc_valoracao_referencia_versoes where id=p_versao_id;
  if v_creator is null or v_creator=v_actor then raise exception 'criador nao pode aprovar ou rejeitar a propria referencia'; end if;
  if upper(btrim(p_decisao)) not in ('APPROVED','REJECTED') or length(btrim(coalesce(p_justificativa,'')))<10 then raise exception 'revisao de referencia invalida'; end if;
  insert into public.prc_valoracao_referencia_revisoes(referencia_versao_id,decisao,justificativa,actor_id) values(p_versao_id,upper(btrim(p_decisao)),btrim(p_justificativa),v_actor) returning id into v_id;
  insert into public.prc_requisicoes values(p_key,'valuation_reference_review',v_actor,public.prc_sha256(v_payload),v_id,clock_timestamp());
  perform public.log_audited_rpc_change('precificacao','prc_valoracao_referencia_revisoes',v_id::text,'precificacao.valoracao_referencia_revisada','precificacao.valuation.review',v_ctx,null,jsonb_build_object('decisao',upper(btrim(p_decisao))),jsonb_build_object('versao_id',p_versao_id),'database_rpc'); return v_id;
end;
$$;

create or replace function public.alterar_prc_valoracao_referencia_lifecycle_idempotente(
  p_key uuid,p_versao_id bigint,p_estado text,p_justificativa text
) returns bigint language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb; v_actor uuid; v_payload jsonb; v_existing bigint; v_ref bigint; v_decisao text; v_state text; v_old record; v_id bigint;
begin
  v_ctx:=public.begin_audited_rpc('precificacao.valuation.lifecycle','precificacao','prc_valoracao_referencia_lifecycle_eventos','status_transition',jsonb_build_object('correlation_id',p_key::text)); v_actor:=public.current_actor_id();
  v_payload:=jsonb_build_object('versao_id',p_versao_id,'estado',upper(btrim(p_estado)),'justificativa',btrim(p_justificativa));
  perform public.prc_lock_idempotency_key(p_key); v_existing:=public.prc_idempotent_result(p_key,'valuation_reference_lifecycle',v_payload); if v_existing is not null then return v_existing; end if;
  select referencia_id into v_ref from public.prc_valoracao_referencia_versoes where id=p_versao_id;
  if v_ref is null then raise exception 'lifecycle de referencia invalido'; end if;
  perform pg_advisory_xact_lock(hashtextextended('prc-valuation-reference-lifecycle:'||v_ref::text,0));
  select decisao into v_decisao from public.prc_valoracao_referencia_revisoes where referencia_versao_id=p_versao_id order by created_at desc,id desc limit 1;
  select estado into v_state from public.prc_valoracao_referencia_lifecycle_eventos where referencia_versao_id=p_versao_id order by created_at desc,id desc limit 1;
  if upper(btrim(p_estado)) not in ('ACTIVE','WITHDRAWN') or length(btrim(coalesce(p_justificativa,'')))<10 then raise exception 'lifecycle de referencia invalido'; end if;
  if upper(btrim(p_estado))='ACTIVE' then
    if v_decisao<>'APPROVED' then raise exception 'somente referencia aprovada pode ser ativada'; end if;
    if v_state in ('SUPERSEDED','WITHDRAWN') then raise exception 'referencia historica nao pode ser reativada'; end if;
    for v_old in select r.id from public.prc_valoracao_referencia_versoes r join lateral (select e.estado from public.prc_valoracao_referencia_lifecycle_eventos e where e.referencia_versao_id=r.id order by e.created_at desc,e.id desc limit 1)e on true where r.referencia_id=v_ref and e.estado='ACTIVE' and r.id<>p_versao_id loop
      insert into public.prc_valoracao_referencia_lifecycle_eventos(referencia_versao_id,estado,justificativa,actor_id) values(v_old.id,'SUPERSEDED','Substituida por nova referencia ativa',v_actor);
    end loop;
  elsif v_state is null then raise exception 'somente referencia ativa pode ser retirada'; end if;
  insert into public.prc_valoracao_referencia_lifecycle_eventos(referencia_versao_id,estado,justificativa,actor_id) values(p_versao_id,upper(btrim(p_estado)),btrim(p_justificativa),v_actor) returning id into v_id;
  insert into public.prc_requisicoes values(p_key,'valuation_reference_lifecycle',v_actor,public.prc_sha256(v_payload),v_id,clock_timestamp());
  perform public.log_audited_rpc_change('precificacao','prc_valoracao_referencia_lifecycle_eventos',v_id::text,'precificacao.valoracao_referencia_lifecycle','precificacao.valuation.lifecycle',v_ctx,null,jsonb_build_object('estado',upper(btrim(p_estado))),jsonb_build_object('versao_id',p_versao_id),'database_rpc'); return v_id;
end;
$$;

create or replace function public.executar_prc_valoracao_idempotente(
  p_key uuid,p_valoracao_versao_id bigint,p_materia_prima_id bigint,p_motivo text
) returns bigint language plpgsql security definer set search_path=public as $$
declare
  v_ctx jsonb; v_actor uuid; v_payload jsonb; v_existing bigint; v_policy public.prc_valoracao_versoes%rowtype;
  v_policy_sha text; v_eval timestamptz:=transaction_timestamp(); v_base_unit text; v_lot record; v_layer record;
  v_physical numeric; v_reserved numeric; v_reserve_left numeric; v_layer_total numeric; v_used numeric;
  v_consumed numeric; v_remaining numeric; v_reserved_take numeric; v_available numeric; v_total_qty numeric:=0;
  v_total_cost numeric:=0; v_currency text; v_line_order integer:=0; v_lines jsonb:='[]'::jsonb; v_latest jsonb;
  v_reference public.prc_valoracao_referencia_versoes%rowtype; v_reference_count integer; v_reference_sha text;
  v_input jsonb; v_result jsonb; v_document jsonb; v_input_sha text; v_result_sha text; v_document_sha text; v_snapshot bigint; v_id bigint;
begin
  v_ctx:=public.begin_audited_rpc('precificacao.valuation.execute','precificacao','prc_valoracao_snapshots','field_risk',jsonb_build_object('correlation_id',p_key::text));
  v_actor:=public.current_actor_id();
  v_payload:=jsonb_build_object('valoracao_versao_id',p_valoracao_versao_id,'materia_prima_id',p_materia_prima_id,'motivo',btrim(p_motivo));
  perform public.prc_lock_idempotency_key(p_key); v_existing:=public.prc_idempotent_result(p_key,'valuation_execute',v_payload); if v_existing is not null then return v_existing; end if;
  if length(btrim(coalesce(p_motivo,'')))<10 then raise exception 'motivo de valoracao invalido'; end if;
  select * into v_policy from public.prc_valoracao_versoes where id=p_valoracao_versao_id;
  if not found then raise exception 'versao de valoracao inexistente'; end if;
  v_policy_sha:=precificacao_internal.prc_valoracao_versao_sha256(v_policy.id);
  if (select decisao from public.prc_valoracao_revisoes where valoracao_versao_id=v_policy.id order by created_at desc,id desc limit 1)<>'APPROVED'
     or (select estado from public.prc_valoracao_lifecycle_eventos where valoracao_versao_id=v_policy.id order by created_at desc,id desc limit 1)<>'ACTIVE' then
    raise exception 'politica de valoracao nao esta aprovada e ativa';
  end if;
  select unidade_base_estoque into v_base_unit from public.cad_materias_primas where id=p_materia_prima_id and status='active';
  if v_base_unit is null then raise exception 'materia-prima ativa ou unidade base inexistente'; end if;

  if v_policy.source_kind='APPROVED_MANUAL_REFERENCE' then
    select count(*) into v_reference_count
      from public.prc_valoracao_referencia_versoes rv
      join public.prc_valoracao_referencias r on r.id=rv.referencia_id
      join lateral (select decisao from public.prc_valoracao_referencia_revisoes x where x.referencia_versao_id=rv.id order by x.created_at desc,x.id desc limit 1) review on true
      join lateral (select estado from public.prc_valoracao_referencia_lifecycle_eventos x where x.referencia_versao_id=rv.id order by x.created_at desc,x.id desc limit 1) life on true
     where r.materia_prima_id=p_materia_prima_id and r.reference_kind=v_policy.manual_reference_kind
       and review.decisao='APPROVED' and life.estado='ACTIVE'
       and rv.vigencia_inicio<=v_eval and (rv.vigencia_fim is null or rv.vigencia_fim>=v_eval)
       and precificacao_internal.prc_valoracao_unidade_compativel(p_materia_prima_id,rv.unidade_base,v_base_unit,v_eval);
    if v_reference_count<>1 then raise exception 'referencia manual aprovada ativa deve ser unica'; end if;
    select rv.* into v_reference
      from public.prc_valoracao_referencia_versoes rv
      join public.prc_valoracao_referencias r on r.id=rv.referencia_id
      join lateral (select decisao from public.prc_valoracao_referencia_revisoes x where x.referencia_versao_id=rv.id order by x.created_at desc,x.id desc limit 1) review on true
      join lateral (select estado from public.prc_valoracao_referencia_lifecycle_eventos x where x.referencia_versao_id=rv.id order by x.created_at desc,x.id desc limit 1) life on true
     where r.materia_prima_id=p_materia_prima_id and r.reference_kind=v_policy.manual_reference_kind
       and review.decisao='APPROVED' and life.estado='ACTIVE'
       and rv.vigencia_inicio<=v_eval and (rv.vigencia_fim is null or rv.vigencia_fim>=v_eval)
       and precificacao_internal.prc_valoracao_unidade_compativel(p_materia_prima_id,rv.unidade_base,v_base_unit,v_eval);
    v_reference_sha:=precificacao_internal.prc_valoracao_referencia_sha256(v_reference.id);
    v_currency:=v_reference.moeda; v_total_qty:=1; v_total_cost:=v_reference.valor_unitario;
    v_lines:=jsonb_build_array(jsonb_build_object('source','manual_reference','reference_version_id',v_reference.id,'reference_sha256',v_reference_sha,'quantity','1','unit_cost',v_reference.valor_unitario::text,'currency',v_reference.moeda));
  else
    for v_lot in
      select s.* from public.est_lotes_mp_saldos s
       where s.materia_prima_id=p_materia_prima_id and s.status='disponivel' and s.saldo_disponivel>0
       order by s.created_at,s.lote_mp_id
    loop
      if v_lot.data_validade is not null and v_lot.data_validade<v_eval::date then raise exception 'lote disponivel vencido impede valoracao'; end if;
      v_physical:=v_lot.saldo_fisico; v_reserved:=v_lot.quantidade_reservada; v_layer_total:=0; v_reserve_left:=v_reserved;
      for v_layer in
        select value.id movimento_valor_id,entry.id movimento_mp_id,entry.created_at entrada_at,value.quantidade_base,
          value.unidade_origem,value.moeda,value.custo_unitario_base
          from public.est_movimentos_mp_valores value join public.est_movimentos_mp entry on entry.id=value.movimento_mp_id
         where entry.lote_mp_id=v_lot.lote_mp_id and entry.quantidade>0
         order by entry.created_at,entry.id,value.id
      loop
        select coalesce(sum(a.quantidade_alocada),0) into v_consumed from public.est_movimentos_mp_custo_alocacoes a where a.movimento_valor_id=v_layer.movimento_valor_id;
        v_remaining:=v_layer.quantidade_base-v_consumed;
        if v_remaining<0 then raise exception 'camada de custo possui quantidade negativa'; end if;
        v_layer_total:=v_layer_total+v_remaining;
        v_reserved_take:=least(v_reserve_left,v_remaining); v_reserve_left:=v_reserve_left-v_reserved_take; v_available:=v_remaining-v_reserved_take;
        if not precificacao_internal.prc_valoracao_unidade_compativel(p_materia_prima_id,v_layer.unidade_origem,v_base_unit,v_eval) then raise exception 'unidade da camada incompativel com unidade base'; end if;
        v_line_order:=v_line_order+1;
        v_lines:=v_lines || jsonb_build_array(jsonb_build_object('lote_mp_id',v_lot.lote_mp_id,'movimento_mp_id',v_layer.movimento_mp_id,'movimento_valor_id',v_layer.movimento_valor_id,'entrada_at',v_layer.entrada_at,'ordem_fifo',v_line_order,'quantidade_original',v_layer.quantidade_base::text,'quantidade_consumida',v_consumed::text,'quantidade_remanescente',v_remaining::text,'quantidade_reservada_atribuida',v_reserved_take::text,'quantidade_disponivel_usada',v_available::text,'custo_unitario',v_layer.custo_unitario_base::text,'moeda',v_layer.moeda,'contribuicao_custo_total',(v_available*v_layer.custo_unitario_base)::text,'expiry_unknown',v_lot.data_validade is null));
        if v_available>0 then
          if v_currency is null then v_currency:=v_layer.moeda; elsif v_currency<>v_layer.moeda then raise exception 'mixed_currency'; end if;
          v_total_qty:=v_total_qty+v_available; v_total_cost:=v_total_cost+v_available*v_layer.custo_unitario_base;
        end if;
      end loop;
      if v_layer_total is distinct from v_physical then raise exception 'saldo fisico sem camada explicavel'; end if;
      if v_reserve_left<>0 or v_layer_total-v_reserved is distinct from v_lot.saldo_disponivel then raise exception 'saldo disponivel nao reconciliavel'; end if;
    end loop;
    if v_total_qty<=0 or v_currency is null then raise exception 'saldo elegivel sem custo'; end if;
    if v_policy.valuation_method='LATEST_ELIGIBLE_ACQUISITION' then
      select layer into v_latest
        from jsonb_array_elements(v_lines) as eligible(layer)
       where (layer->>'quantidade_disponivel_usada')::numeric > 0
       order by (layer->>'entrada_at')::timestamptz desc,
                (layer->>'movimento_mp_id')::bigint desc,
                (layer->>'movimento_valor_id')::bigint desc
       limit 1;
      if v_latest is null then raise exception 'aquisicao elegivel mais recente inexistente'; end if;
      v_total_qty:=(v_latest->>'quantidade_disponivel_usada')::numeric;
      v_total_cost:=v_total_qty*(v_latest->>'custo_unitario')::numeric;
      v_lines:=jsonb_build_array(v_latest);
    end if;
  end if;
  v_input:=jsonb_build_object('schema','prc-valuation-input-v1','policy_version_id',v_policy.id,'policy_sha256',v_policy_sha,'source_kind',v_policy.source_kind,'valuation_method',v_policy.valuation_method,'materia_prima_id',p_materia_prima_id,'base_unit',v_base_unit,'layers',v_lines);
  v_result:=jsonb_build_object('schema','prc-valuation-result-v1','policy_version_id',v_policy.id,'policy_sha256',v_policy_sha,'source_kind',v_policy.source_kind,'valuation_method',v_policy.valuation_method,'materia_prima_id',p_materia_prima_id,'currency',v_currency,'base_unit',v_base_unit,'quantity_total',v_total_qty::text,'total_cost',v_total_cost::text,'unit_cost',(v_total_cost/v_total_qty)::text,'layers',v_lines);
  v_input_sha:=public.prc_sha256(v_input); v_result_sha:=public.prc_sha256(v_result);
  v_document:=jsonb_build_object('schema','prc-valuation-v1','evaluation',jsonb_build_object('evaluated_at',v_eval,'actor_id',v_actor),'input',v_input,'result',v_result,'input_sha256',v_input_sha,'result_sha256',v_result_sha);
  v_document_sha:=public.prc_sha256(v_document);
  insert into public.prc_valoracao_snapshots(valoracao_versao_id,referencia_versao_id,materia_prima_id,source_kind,valuation_method,evaluated_at,moeda,unidade_base,quantidade_total,custo_total,custo_unitario_exato,actor_id,documento_json,documento_sha256,input_sha256,result_sha256,motivo)
  values(v_policy.id,case when v_policy.source_kind='APPROVED_MANUAL_REFERENCE' then v_reference.id else null end,p_materia_prima_id,v_policy.source_kind,v_policy.valuation_method,v_eval,v_currency,v_base_unit,v_total_qty,v_total_cost,v_total_cost/v_total_qty,v_actor,v_document,v_document_sha,v_input_sha,v_result_sha,btrim(p_motivo)) returning id into v_snapshot;
  if v_policy.source_kind='STOCK_ACQUISITION_LAYER' then
    insert into public.prc_valoracao_snapshot_camadas(snapshot_id,lote_mp_id,movimento_mp_id,movimento_valor_id,ordem_fifo,quantidade_original,quantidade_consumida,quantidade_remanescente,quantidade_reservada_atribuida,quantidade_disponivel_usada,custo_unitario,moeda,contribuicao_custo_total)
    select v_snapshot,(x->>'lote_mp_id')::bigint,(x->>'movimento_mp_id')::bigint,(x->>'movimento_valor_id')::bigint,(x->>'ordem_fifo')::integer,(x->>'quantidade_original')::numeric,(x->>'quantidade_consumida')::numeric,(x->>'quantidade_remanescente')::numeric,(x->>'quantidade_reservada_atribuida')::numeric,(x->>'quantidade_disponivel_usada')::numeric,(x->>'custo_unitario')::numeric,x->>'moeda',(x->>'contribuicao_custo_total')::numeric from jsonb_array_elements(v_lines) x;
    insert into public.prc_valoracao_snapshot_exclusoes(snapshot_id,lote_mp_id,reason_code,detalhes_json)
    select v_snapshot,(x->>'lote_mp_id')::bigint,'EXPIRY_UNKNOWN_ALLOWED',jsonb_build_object('expiry_unknown',true)
      from jsonb_array_elements(v_lines)x where coalesce((x->>'expiry_unknown')::boolean,false);
  else
    insert into public.prc_valoracao_snapshot_exclusoes(snapshot_id,reason_code,detalhes_json)
    values(v_snapshot,'MANUAL_REFERENCE',jsonb_build_object('reference_version_id',v_reference.id,'reference_sha256',v_reference_sha));
  end if;
  insert into public.prc_requisicoes values(p_key,'valuation_execute',v_actor,public.prc_sha256(v_payload),v_snapshot,clock_timestamp());
  perform public.log_audited_rpc_change('precificacao','prc_valoracao_snapshots',v_snapshot::text,'precificacao.valoracao_executada','precificacao.valuation.execute',v_ctx,null,v_document,jsonb_build_object('motivo',btrim(p_motivo),'result_sha256',v_result_sha),'database_rpc');
  return v_snapshot;
end;
$$;

create or replace function public.consultar_prc_valoracao_snapshot(p_snapshot_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v public.prc_valoracao_snapshots%rowtype;
begin
  perform public.begin_audited_rpc('precificacao.valuation.execute','precificacao','prc_valoracao_snapshots','own_any',jsonb_build_object('snapshot_id',p_snapshot_id));
  select * into v from public.prc_valoracao_snapshots where id=p_snapshot_id;
  if not found then raise exception 'snapshot de valoracao inexistente'; end if;
  perform precificacao_internal.prc_valoracao_snapshot_sha256(v.id);
  return jsonb_build_object(
    'snapshot_id',v.id,'valoracao_versao_id',v.valoracao_versao_id,
    'documento_json',v.documento_json,'documento_sha256',v.documento_sha256,
    'input_sha256',v.input_sha256,'result_sha256',v.result_sha256
  );
end;
$$;

revoke all on all functions in schema precificacao_internal from public, anon, authenticated;
revoke all on function public.prevent_prc_valoracao_fact_changes() from public, anon, authenticated;
revoke all on function public.salvar_prc_valoracao_versao_idempotente(uuid,bigint,text,text,text,text,text,text) from public, anon;
revoke all on function public.revisar_prc_valoracao_versao_idempotente(uuid,bigint,text,text) from public, anon;
revoke all on function public.alterar_prc_valoracao_lifecycle_idempotente(uuid,bigint,text,text) from public, anon;
revoke all on function public.salvar_prc_valoracao_referencia_versao_idempotente(uuid,bigint,bigint,text,text,text,numeric,date,timestamptz,timestamptz,text,text,text) from public, anon;
revoke all on function public.revisar_prc_valoracao_referencia_idempotente(uuid,bigint,text,text) from public, anon;
revoke all on function public.alterar_prc_valoracao_referencia_lifecycle_idempotente(uuid,bigint,text,text) from public, anon;
revoke all on function public.executar_prc_valoracao_idempotente(uuid,bigint,bigint,text) from public, anon;
revoke all on function public.consultar_prc_valoracao_snapshot(bigint) from public, anon;
grant execute on function public.salvar_prc_valoracao_versao_idempotente(uuid,bigint,text,text,text,text,text,text) to authenticated;
grant execute on function public.revisar_prc_valoracao_versao_idempotente(uuid,bigint,text,text) to authenticated;
grant execute on function public.alterar_prc_valoracao_lifecycle_idempotente(uuid,bigint,text,text) to authenticated;
grant execute on function public.salvar_prc_valoracao_referencia_versao_idempotente(uuid,bigint,bigint,text,text,text,numeric,date,timestamptz,timestamptz,text,text,text) to authenticated;
grant execute on function public.revisar_prc_valoracao_referencia_idempotente(uuid,bigint,text,text) to authenticated;
grant execute on function public.alterar_prc_valoracao_referencia_lifecycle_idempotente(uuid,bigint,text,text) to authenticated;
grant execute on function public.executar_prc_valoracao_idempotente(uuid,bigint,bigint,text) to authenticated;
grant execute on function public.consultar_prc_valoracao_snapshot(bigint) to authenticated;

comment on table public.prc_valoracao_snapshots is
  'PRC-03 append-only valuation fact. Reads Stock layers without changing Stock or PCP.';
comment on function public.executar_prc_valoracao_idempotente(uuid,bigint,bigint,text) is
  'Governed PRC-03 valuation. CURRENT_STATE only; mixed currency, unreconciled stock and inconsistent layers fail closed.';
comment on function public.consultar_prc_valoracao_snapshot(bigint) is
  'Governed PRC-03 snapshot read. The integral document hash is verified before return.';
