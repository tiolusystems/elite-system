-- UX-01C.4: governed input types for raw materials.
-- The legacy cad_materias_primas.tipo value is preserved for reconciliation,
-- but it is no longer an operational source of truth.

create table public.cad_tipos_insumo (
  id bigint generated always as identity primary key,
  codigo text not null,
  codigo_norm text generated always as (public.normalize_catalog_term(codigo)) stored,
  nome text not null,
  nome_norm text generated always as (public.normalize_catalog_term(nome)) stored,
  descricao text,
  status text not null default 'pending_review',
  ordem_exibicao integer not null default 100,
  origem_dados text not null default 'sistema',
  created_by uuid not null references public.user_profiles(id),
  updated_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cad_tipos_insumo_codigo_check check (
    codigo_norm is not null and char_length(codigo) <= 60
  ),
  constraint cad_tipos_insumo_nome_check check (
    nome_norm is not null and char_length(nome) <= 120
  ),
  constraint cad_tipos_insumo_descricao_check check (
    descricao is null or char_length(descricao) <= 500
  ),
  constraint cad_tipos_insumo_status_check check (
    status in ('active', 'pending_review', 'inactive')
  ),
  constraint cad_tipos_insumo_origem_check check (
    origem_dados in ('sistema', 'excel_legado')
  ),
  constraint cad_tipos_insumo_ordem_check check (ordem_exibicao >= 0),
  constraint cad_tipos_insumo_codigo_key unique (codigo_norm),
  constraint cad_tipos_insumo_nome_key unique (nome_norm)
);

create trigger trg_cad_tipos_insumo_updated_at
before update on public.cad_tipos_insumo
for each row execute function public.touch_updated_at();

alter table public.cad_materias_primas
  add column tipo_insumo_id bigint,
  add column tipo_insumo_review_status text not null default 'pending_review',
  add column tipo_insumo_source text;

alter table public.cad_materias_primas
  add constraint cad_materias_tipo_insumo_fk
    foreign key (tipo_insumo_id) references public.cad_tipos_insumo(id) not valid,
  add constraint cad_materias_tipo_review_check check (
    tipo_insumo_review_status in ('approved', 'pending_review')
  ),
  add constraint cad_materias_tipo_source_check check (
    (tipo_insumo_id is null and tipo_insumo_review_status = 'pending_review' and tipo_insumo_source is null)
    or
    (tipo_insumo_id is not null and tipo_insumo_review_status = 'approved'
      and tipo_insumo_source in ('manual_governado', 'fonte_governada'))
  );

alter table public.cad_materias_primas validate constraint cad_materias_tipo_insumo_fk;

create index idx_cad_materias_tipo_insumo
  on public.cad_materias_primas(tipo_insumo_id, tipo_insumo_review_status);

comment on column public.cad_materias_primas.tipo is
  'Valor textual legado preservado somente para reconciliacao. Nao usar como fonte operacional.';
comment on column public.cad_materias_primas.tipo_insumo_id is
  'Classificacao governada da materia-prima por FK. Nulo significa Tipo de insumo nao definido.';
comment on column public.cad_materias_primas.tipo_insumo_source is
  'Fonte auditavel da classificacao aplicada; nunca inferida por nome ou palavra-chave.';

create or replace function public.freeze_cad_materia_prima_legacy_tipo()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'INSERT' and new.tipo is not null then
    raise exception 'legacy free-text input type is read-only';
  end if;
  if tg_op = 'UPDATE' and new.tipo is distinct from old.tipo then
    raise exception 'legacy free-text input type is read-only';
  end if;
  return new;
end;
$$;

create trigger trg_cad_materias_freeze_legacy_tipo
before insert or update of tipo on public.cad_materias_primas
for each row execute function public.freeze_cad_materia_prima_legacy_tipo();

revoke all on function public.freeze_cad_materia_prima_legacy_tipo() from public, anon, authenticated;

insert into public.permission_actions(
  action_key, module, description, default_allowed, sort_order,
  runtime_module_key, runtime_access_kind
)
values
  ('cadastros.tipos_insumo.create', 'cadastros', 'Criar tipo de insumo', true, 84, 'cadastros', 'write'),
  ('cadastros.tipos_insumo.update', 'cadastros', 'Editar tipo de insumo', true, 85, 'cadastros', 'write'),
  ('cadastros.tipos_insumo.activate', 'cadastros', 'Ativar tipo de insumo', true, 86, 'cadastros', 'write'),
  ('cadastros.tipos_insumo.deactivate', 'cadastros', 'Inativar tipo de insumo', true, 87, 'cadastros', 'write'),
  ('cadastros.materias_primas.update.input_type', 'cadastros', 'Classificar tipo de insumo da materia-prima', true, 88, 'cadastros', 'write')
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

alter table public.cad_tipos_insumo enable row level security;

create policy "active user read cad_tipos_insumo"
  on public.cad_tipos_insumo
  for select to authenticated
  using (public.current_actor_id() is not null);

revoke all on public.cad_tipos_insumo from public, anon;
revoke insert, update, delete, truncate on public.cad_tipos_insumo from authenticated;
grant select on public.cad_tipos_insumo to authenticated;

create or replace function public.prevent_cad_tipo_insumo_delete()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'input type records are append-preserved; deactivate instead';
end;
$$;

create trigger trg_cad_tipos_insumo_no_delete
before delete on public.cad_tipos_insumo
for each row execute function public.prevent_cad_tipo_insumo_delete();

revoke all on function public.prevent_cad_tipo_insumo_delete() from public, anon, authenticated;

create or replace function public.create_cad_tipo_insumo(
  p_codigo text,
  p_nome text,
  p_descricao text default null,
  p_status text default 'pending_review',
  p_ordem_exibicao integer default 100,
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
  v_after jsonb;
  v_permission_context jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'cadastros.tipos_insumo.create', 'cadastros', 'cad_tipos_insumo',
    'field_risk', jsonb_build_object('correlation_id', gen_random_uuid()::text)
  );
  if public.normalize_catalog_term(p_codigo) is null then raise exception 'codigo is required'; end if;
  if public.normalize_catalog_term(p_nome) is null then raise exception 'nome is required'; end if;
  if p_status not in ('active', 'pending_review') then raise exception 'invalid initial status'; end if;
  if p_ordem_exibicao is null or p_ordem_exibicao < 0 then raise exception 'invalid display order'; end if;
  if nullif(btrim(p_motivo), '') is null then raise exception 'motivo is required'; end if;

  v_actor := public.current_actor_id();
  insert into public.cad_tipos_insumo(
    codigo, nome, descricao, status, ordem_exibicao, created_by, updated_by
  ) values (
    upper(btrim(p_codigo)), btrim(p_nome), nullif(btrim(p_descricao), ''),
    p_status, p_ordem_exibicao, v_actor, v_actor
  ) returning id into v_id;

  select to_jsonb(item) into v_after from public.cad_tipos_insumo item where item.id = v_id;
  perform public.log_audited_rpc_change(
    'cadastros', 'cad_tipos_insumo', v_id::text, 'cadastros.tipo_insumo_created',
    'cadastros.tipos_insumo.create', v_permission_context, null, v_after,
    jsonb_build_object('motivo', btrim(p_motivo)), 'database_rpc'
  );
  return v_id;
end;
$$;

create or replace function public.update_cad_tipo_insumo(
  p_tipo_insumo_id bigint,
  p_codigo text,
  p_nome text,
  p_descricao text default null,
  p_ordem_exibicao integer default 100,
  p_motivo text default null
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
  v_permission_context jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'cadastros.tipos_insumo.update', 'cadastros', 'cad_tipos_insumo',
    'field_risk', jsonb_build_object('correlation_id', 'tipo_insumo:' || p_tipo_insumo_id || ':update')
  );
  if public.normalize_catalog_term(p_codigo) is null then raise exception 'codigo is required'; end if;
  if public.normalize_catalog_term(p_nome) is null then raise exception 'nome is required'; end if;
  if p_ordem_exibicao is null or p_ordem_exibicao < 0 then raise exception 'invalid display order'; end if;
  if nullif(btrim(p_motivo), '') is null then raise exception 'motivo is required'; end if;

  select to_jsonb(item) into v_before
  from public.cad_tipos_insumo item where item.id = p_tipo_insumo_id for update;
  if not found then raise exception 'input type not found'; end if;

  v_actor := public.current_actor_id();
  update public.cad_tipos_insumo
     set codigo = upper(btrim(p_codigo)), nome = btrim(p_nome),
         descricao = nullif(btrim(p_descricao), ''), ordem_exibicao = p_ordem_exibicao,
         updated_by = v_actor
   where id = p_tipo_insumo_id;
  select to_jsonb(item) into v_after from public.cad_tipos_insumo item where item.id = p_tipo_insumo_id;
  perform public.log_audited_rpc_change(
    'cadastros', 'cad_tipos_insumo', p_tipo_insumo_id::text, 'cadastros.tipo_insumo_updated',
    'cadastros.tipos_insumo.update', v_permission_context, v_before, v_after,
    jsonb_build_object('motivo', btrim(p_motivo)), 'database_rpc'
  );
  return p_tipo_insumo_id;
end;
$$;

create or replace function public.activate_cad_tipo_insumo(
  p_tipo_insumo_id bigint,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before jsonb;
  v_after jsonb;
  v_permission_context jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'cadastros.tipos_insumo.activate', 'cadastros', 'cad_tipos_insumo',
    'status_transition', jsonb_build_object('correlation_id', 'tipo_insumo:' || p_tipo_insumo_id || ':activate')
  );
  if nullif(btrim(p_motivo), '') is null then raise exception 'motivo is required'; end if;
  select to_jsonb(item) into v_before from public.cad_tipos_insumo item
   where item.id = p_tipo_insumo_id for update;
  if not found then raise exception 'input type not found'; end if;
  update public.cad_tipos_insumo set status = 'active', updated_by = public.current_actor_id()
   where id = p_tipo_insumo_id;
  select to_jsonb(item) into v_after from public.cad_tipos_insumo item where item.id = p_tipo_insumo_id;
  perform public.log_audited_rpc_change(
    'cadastros', 'cad_tipos_insumo', p_tipo_insumo_id::text, 'cadastros.tipo_insumo_activated',
    'cadastros.tipos_insumo.activate', v_permission_context, v_before, v_after,
    jsonb_build_object('motivo', btrim(p_motivo)), 'database_rpc'
  );
  return p_tipo_insumo_id;
end;
$$;

create or replace function public.deactivate_cad_tipo_insumo(
  p_tipo_insumo_id bigint,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before jsonb;
  v_after jsonb;
  v_permission_context jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'cadastros.tipos_insumo.deactivate', 'cadastros', 'cad_tipos_insumo',
    'status_transition', jsonb_build_object('correlation_id', 'tipo_insumo:' || p_tipo_insumo_id || ':deactivate')
  );
  if nullif(btrim(p_motivo), '') is null then raise exception 'motivo is required'; end if;
  select to_jsonb(item) into v_before from public.cad_tipos_insumo item
   where item.id = p_tipo_insumo_id for update;
  if not found then raise exception 'input type not found'; end if;
  update public.cad_tipos_insumo set status = 'inactive', updated_by = public.current_actor_id()
   where id = p_tipo_insumo_id;
  select to_jsonb(item) into v_after from public.cad_tipos_insumo item where item.id = p_tipo_insumo_id;
  perform public.log_audited_rpc_change(
    'cadastros', 'cad_tipos_insumo', p_tipo_insumo_id::text, 'cadastros.tipo_insumo_deactivated',
    'cadastros.tipos_insumo.deactivate', v_permission_context, v_before, v_after,
    jsonb_build_object('motivo', btrim(p_motivo)), 'database_rpc'
  );
  return p_tipo_insumo_id;
end;
$$;

create or replace function public.set_cad_materia_prima_tipo(
  p_materia_prima_id bigint,
  p_tipo_insumo_id bigint default null,
  p_motivo text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before jsonb;
  v_after jsonb;
  v_permission_context jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'cadastros.materias_primas.update.input_type', 'cadastros', 'cad_materias_primas',
    'field_risk', jsonb_build_object('correlation_id', 'materia_prima:' || p_materia_prima_id || ':input_type')
  );
  if p_materia_prima_id is null or p_materia_prima_id <= 0 then raise exception 'materia_prima_id is required'; end if;
  if nullif(btrim(p_motivo), '') is null then raise exception 'motivo is required'; end if;
  if p_tipo_insumo_id is not null and not exists (
    select 1 from public.cad_tipos_insumo item where item.id = p_tipo_insumo_id and item.status = 'active'
  ) then
    raise exception 'active input type not found';
  end if;

  select to_jsonb(mp) into v_before from public.cad_materias_primas mp
   where mp.id = p_materia_prima_id for update;
  if not found then raise exception 'materia-prima not found'; end if;

  update public.cad_materias_primas
     set tipo_insumo_id = p_tipo_insumo_id,
         tipo_insumo_review_status = case when p_tipo_insumo_id is null then 'pending_review' else 'approved' end,
         tipo_insumo_source = case when p_tipo_insumo_id is null then null else 'manual_governado' end,
         updated_by = public.current_actor_id()
   where id = p_materia_prima_id;
  select to_jsonb(mp) into v_after from public.cad_materias_primas mp where mp.id = p_materia_prima_id;
  perform public.log_audited_rpc_change(
    'cadastros', 'cad_materias_primas', p_materia_prima_id::text,
    'cadastros.materia_prima_input_type_set', 'cadastros.materias_primas.update.input_type',
    v_permission_context, v_before, v_after,
    jsonb_build_object('motivo', btrim(p_motivo), 'legacy_tipo_preserved', v_before->>'tipo'),
    'database_rpc'
  );
  return p_materia_prima_id;
end;
$$;

-- New governed create RPC. The old create RPC loses authenticated execution so
-- no new free-text type can enter through an older client.
create or replace function public.create_cad_materia_prima_governada(
  p_nome text,
  p_nome_norm text,
  p_sku_corrigido text,
  p_unidade_base_estoque text,
  p_tipo_insumo_id bigint default null,
  p_status text default 'active',
  p_codigo_legado text default null,
  p_densidade numeric default null,
  p_estoque_minimo numeric default null,
  p_ncm text default null,
  p_ibama text default null,
  p_codigo_ads text default null,
  p_payload_origem_json jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_id bigint;
  v_after jsonb;
  v_permission_context jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'cadastros.materias_primas.create', 'cadastros', 'cad_materias_primas',
    'field_risk', jsonb_build_object('correlation_id', gen_random_uuid()::text, 'governed_input_type', true)
  );
  if nullif(btrim(p_nome), '') is null then raise exception 'nome is required'; end if;
  if nullif(btrim(p_nome_norm), '') is null then raise exception 'nome_norm is required'; end if;
  if nullif(btrim(p_sku_corrigido), '') is null then raise exception 'sku_corrigido is required'; end if;
  if nullif(btrim(p_unidade_base_estoque), '') is null then raise exception 'unidade_base_estoque is required'; end if;
  if p_status not in ('active', 'inactive', 'pending_review') then raise exception 'invalid status'; end if;
  if p_densidade is not null and p_densidade <= 0 then raise exception 'densidade must be greater than zero'; end if;
  if p_estoque_minimo is not null and p_estoque_minimo < 0 then raise exception 'estoque_minimo must be non-negative'; end if;
  if p_tipo_insumo_id is not null and not exists (
    select 1 from public.cad_tipos_insumo item where item.id = p_tipo_insumo_id and item.status = 'active'
  ) then raise exception 'active input type not found'; end if;

  v_actor := public.current_actor_id();
  insert into public.cad_materias_primas(
    codigo_legado, sku_corrigido, nome, nome_norm, unidade_base_estoque,
    status, tipo, tipo_insumo_id, tipo_insumo_review_status, tipo_insumo_source,
    densidade, estoque_minimo, ncm, ibama, codigo_ads, payload_origem_json,
    created_by, updated_by
  ) values (
    nullif(btrim(p_codigo_legado), ''), upper(btrim(p_sku_corrigido)), btrim(p_nome), btrim(p_nome_norm),
    upper(btrim(p_unidade_base_estoque)), p_status, null, p_tipo_insumo_id,
    case when p_tipo_insumo_id is null then 'pending_review' else 'approved' end,
    case when p_tipo_insumo_id is null then null else 'manual_governado' end,
    p_densidade, p_estoque_minimo, public.validate_cad_mp_ncm(p_ncm),
    nullif(btrim(p_ibama), ''), nullif(btrim(p_codigo_ads), ''),
    coalesce(p_payload_origem_json, '{}'::jsonb), v_actor, v_actor
  ) returning id into v_id;
  select to_jsonb(mp) into v_after from public.cad_materias_primas mp where mp.id = v_id;
  perform public.log_audited_rpc_change(
    'cadastros', 'cad_materias_primas', v_id::text, 'cadastros.materia_prima_created',
    'cadastros.materias_primas.create', v_permission_context, null, v_after,
    jsonb_build_object('source', 'create_cad_materia_prima_governada'), 'database_rpc'
  );
  return v_id;
end;
$$;

revoke execute on function public.create_cad_materia_prima(text, text, text, text, text, text, text, numeric, numeric, text, text, text, jsonb)
  from authenticated;

revoke all on function public.create_cad_tipo_insumo(text, text, text, text, integer, text) from public, anon;
revoke all on function public.update_cad_tipo_insumo(bigint, text, text, text, integer, text) from public, anon;
revoke all on function public.activate_cad_tipo_insumo(bigint, text) from public, anon;
revoke all on function public.deactivate_cad_tipo_insumo(bigint, text) from public, anon;
revoke all on function public.set_cad_materia_prima_tipo(bigint, bigint, text) from public, anon;
revoke all on function public.create_cad_materia_prima_governada(text, text, text, text, bigint, text, text, numeric, numeric, text, text, text, jsonb) from public, anon;

grant execute on function public.create_cad_tipo_insumo(text, text, text, text, integer, text) to authenticated;
grant execute on function public.update_cad_tipo_insumo(bigint, text, text, text, integer, text) to authenticated;
grant execute on function public.activate_cad_tipo_insumo(bigint, text) to authenticated;
grant execute on function public.deactivate_cad_tipo_insumo(bigint, text) to authenticated;
grant execute on function public.set_cad_materia_prima_tipo(bigint, bigint, text) to authenticated;
grant execute on function public.create_cad_materia_prima_governada(text, text, text, text, bigint, text, text, numeric, numeric, text, text, text, jsonb) to authenticated;

create or replace view public.cad_materias_primas_tipos_revisao
with (security_invoker = true)
as
select
  mp.id as materia_prima_id,
  mp.sku_corrigido,
  mp.nome as materia_prima_nome,
  mp.tipo as tipo_legado,
  mp.tipo_insumo_id,
  coalesce(tipo.nome, 'Tipo de insumo nao definido') as tipo_insumo_nome,
  mp.tipo_insumo_review_status,
  mp.tipo_insumo_source,
  mp.status as materia_prima_status
from public.cad_materias_primas mp
left join public.cad_tipos_insumo tipo on tipo.id = mp.tipo_insumo_id;

create or replace view public.cad_materias_primas_tipos_resumo
with (security_invoker = true)
as
select
  count(*)::integer as total_materias_primas,
  count(*) filter (where tipo_insumo_id is not null)::integer as total_classificadas,
  count(*) filter (where tipo_insumo_id is null)::integer as total_sem_classificacao,
  count(*) filter (where tipo_insumo_source = 'fonte_governada')::integer as classificadas_fonte_governada,
  count(*) filter (where tipo_insumo_source = 'manual_governado')::integer as classificadas_manual_governado,
  0::integer as classificadas_por_inferencia
from public.cad_materias_primas;

grant select on public.cad_materias_primas_tipos_revisao to authenticated;
grant select on public.cad_materias_primas_tipos_resumo to authenticated;
revoke all on public.cad_materias_primas_tipos_revisao from public, anon;
revoke all on public.cad_materias_primas_tipos_resumo from public, anon;

comment on view public.cad_materias_primas_tipos_resumo is
  'Relatorio de backfill. classificadas_por_inferencia deve permanecer sempre zero.';
