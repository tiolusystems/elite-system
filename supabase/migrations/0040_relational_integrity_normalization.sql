-- Relational integrity and controlled-normalization gate.
-- Raw import payloads and audit snapshots may remain JSON. Operational
-- relationships must have typed keys, relational rows, and database guards.

-- Historical source lineage -------------------------------------------------

alter table public.cad_clientes
  add constraint cad_clientes_source_row_fk
    foreign key (source_row_id) references public.source_rows(id) not valid,
  add constraint cad_clientes_source_batch_fk
    foreign key (source_batch_id) references public.migration_batches(id) not valid;

alter table public.cad_pessoas_comerciais
  add constraint cad_pessoas_source_row_fk
    foreign key (source_row_id) references public.source_rows(id) not valid,
  add constraint cad_pessoas_source_batch_fk
    foreign key (source_batch_id) references public.migration_batches(id) not valid;

alter table public.cad_materias_primas
  add constraint cad_mp_source_row_fk
    foreign key (source_row_id) references public.source_rows(id) not valid,
  add constraint cad_mp_source_batch_fk
    foreign key (source_batch_id) references public.migration_batches(id) not valid;

alter table public.cad_produtos_base
  add constraint cad_produtos_source_row_fk
    foreign key (source_row_id) references public.source_rows(id) not valid,
  add constraint cad_produtos_source_batch_fk
    foreign key (source_batch_id) references public.migration_batches(id) not valid;

alter table public.cadastro_validation_issues
  add constraint cadastro_issues_source_batch_fk
    foreign key (source_batch_id) references public.migration_batches(id) not valid;

alter table public.cad_clientes validate constraint cad_clientes_source_row_fk;
alter table public.cad_clientes validate constraint cad_clientes_source_batch_fk;
alter table public.cad_pessoas_comerciais validate constraint cad_pessoas_source_row_fk;
alter table public.cad_pessoas_comerciais validate constraint cad_pessoas_source_batch_fk;
alter table public.cad_materias_primas validate constraint cad_mp_source_row_fk;
alter table public.cad_materias_primas validate constraint cad_mp_source_batch_fk;
alter table public.cad_produtos_base validate constraint cad_produtos_source_row_fk;
alter table public.cad_produtos_base validate constraint cad_produtos_source_batch_fk;
alter table public.cadastro_validation_issues validate constraint cadastro_issues_source_batch_fk;

create index if not exists idx_cad_clientes_source_row
  on public.cad_clientes(source_row_id) where source_row_id is not null;
create index if not exists idx_cad_clientes_source_batch
  on public.cad_clientes(source_batch_id) where source_batch_id is not null;
create index if not exists idx_cad_pessoas_source_row
  on public.cad_pessoas_comerciais(source_row_id) where source_row_id is not null;
create index if not exists idx_cad_pessoas_source_batch
  on public.cad_pessoas_comerciais(source_batch_id) where source_batch_id is not null;
create index if not exists idx_cad_mp_source_row
  on public.cad_materias_primas(source_row_id) where source_row_id is not null;
create index if not exists idx_cad_mp_source_batch
  on public.cad_materias_primas(source_batch_id) where source_batch_id is not null;
create index if not exists idx_cad_produtos_source_row
  on public.cad_produtos_base(source_row_id) where source_row_id is not null;
create index if not exists idx_cad_produtos_source_batch
  on public.cad_produtos_base(source_batch_id) where source_batch_id is not null;
create index if not exists idx_cadastro_issues_source_batch
  on public.cadastro_validation_issues(source_batch_id) where source_batch_id is not null;

create or replace function public.enforce_cad_source_lineage()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_batch_id bigint;
begin
  if new.source_row_id is null then
    return new;
  end if;

  select source_table.batch_id
    into v_batch_id
    from public.source_rows source_row
    join public.source_tables source_table on source_table.id = source_row.table_id
   where source_row.id = new.source_row_id;

  if not found then
    raise exception 'source_row_id does not exist';
  end if;

  if new.source_batch_id is null then
    new.source_batch_id := v_batch_id;
  elsif new.source_batch_id <> v_batch_id then
    raise exception 'source_row_id does not belong to source_batch_id';
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_cad_source_lineage() from public, anon, authenticated;

do $$
declare
  v_table text;
  v_trigger text;
begin
  foreach v_table in array array[
    'cad_clientes',
    'cad_pessoas_comerciais',
    'cad_materias_primas',
    'cad_produtos_base'
  ]
  loop
    v_trigger := 'trg_' || v_table || '_source_lineage';
    execute format('drop trigger if exists %I on public.%I', v_trigger, v_table);
    execute format(
      'create trigger %I before insert or update of source_row_id, source_batch_id on public.%I for each row execute function public.enforce_cad_source_lineage()',
      v_trigger,
      v_table
    );
  end loop;
end;
$$;

-- Raw-material lot guarantees ----------------------------------------------

do $$
begin
  if exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'cad_garantias_lote_mp'
       and column_name = 'lote_mp_id'
       and data_type = 'text'
  ) then
    alter table public.cad_garantias_lote_mp
      rename column lote_mp_id to lote_mp_ref_legado;
  end if;
end;
$$;

alter table public.cad_garantias_lote_mp
  add column if not exists lote_mp_id bigint;

update public.cad_garantias_lote_mp garantia
   set lote_mp_id = lote.id
  from public.est_lotes_mp lote
 where garantia.lote_mp_id is null
   and garantia.materia_prima_id = lote.materia_prima_id
   and lower(btrim(garantia.lote_mp_ref_legado)) = lote.codigo_lote_norm;

update public.cad_garantias_lote_mp garantia
   set lote_mp_id = lote.id
  from public.est_lotes_mp lote
 where garantia.lote_mp_id is null
   and garantia.lote_mp_ref_legado ~ '^[0-9]+$'
   and lote.id = garantia.lote_mp_ref_legado::bigint
   and lote.materia_prima_id = garantia.materia_prima_id;

alter table public.cad_garantias_lote_mp
  add constraint cad_garantias_lote_mp_lote_fk
    foreign key (lote_mp_id) references public.est_lotes_mp(id) not valid;

alter table public.cad_garantias_lote_mp
  validate constraint cad_garantias_lote_mp_lote_fk;

create index if not exists idx_cad_garantias_lote_mp_lote
  on public.cad_garantias_lote_mp(lote_mp_id)
  where lote_mp_id is not null;

create or replace function public.require_cad_garantia_lote_mp_link()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.lote_mp_id is null then
    raise exception 'lote_mp_id relational link is required for new or changed guarantees';
  end if;
  return new;
end;
$$;

revoke all on function public.require_cad_garantia_lote_mp_link() from public, anon, authenticated;

drop trigger if exists trg_cad_garantia_lote_mp_link on public.cad_garantias_lote_mp;
create trigger trg_cad_garantia_lote_mp_link
before insert or update on public.cad_garantias_lote_mp
for each row execute function public.require_cad_garantia_lote_mp_link();

comment on column public.cad_garantias_lote_mp.lote_mp_id is
  'Typed operational link to est_lotes_mp. Required for every new or changed guarantee.';
comment on column public.cad_garantias_lote_mp.lote_mp_ref_legado is
  'Original free-text lot reference retained only for migration reconciliation.';

create or replace view public.cad_garantias_lote_mp_pendentes_vinculo
with (security_invoker = true)
as
select
  garantia.id,
  garantia.materia_prima_id,
  garantia.lote_mp_ref_legado,
  garantia.nutriente,
  garantia.fonte,
  garantia.created_at
from public.cad_garantias_lote_mp garantia
where garantia.lote_mp_id is null;

grant select on public.cad_garantias_lote_mp_pendentes_vinculo to authenticated;

-- Commercial person roles --------------------------------------------------

alter table public.cad_pessoas_comerciais
  add constraint cad_pessoas_papeis_array_check
  check (jsonb_typeof(papeis_json) = 'array') not valid;

alter table public.cad_pessoas_comerciais
  validate constraint cad_pessoas_papeis_array_check;

create table if not exists public.cad_pessoa_papeis (
  id bigint generated always as identity primary key,
  pessoa_id bigint not null references public.cad_pessoas_comerciais(id) on delete cascade,
  papel text not null,
  status text not null default 'active',
  vigencia_inicio timestamptz not null default now(),
  vigencia_fim timestamptz,
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint cad_pessoa_papeis_papel_check check (
    papel in ('funcionario', 'vendedor', 'agente', 'tecnico_campo', 'entregador', 'gerente', 'comissionado')
  ),
  constraint cad_pessoa_papeis_status_check check (status in ('active', 'inactive')),
  constraint cad_pessoa_papeis_vigencia_check check (
    (status = 'active' and vigencia_fim is null)
    or (status = 'inactive' and vigencia_fim is not null and vigencia_fim >= vigencia_inicio)
  )
);

create unique index if not exists ux_cad_pessoa_papeis_active
  on public.cad_pessoa_papeis(pessoa_id, papel)
  where status = 'active';
create index if not exists idx_cad_pessoa_papeis_papel_status
  on public.cad_pessoa_papeis(papel, status, pessoa_id);

insert into public.cad_pessoa_papeis(pessoa_id, papel, status, vigencia_inicio, created_by)
select distinct
  pessoa.id,
  papel.value,
  'active',
  pessoa.created_at,
  coalesce(pessoa.updated_by, pessoa.created_by)
from public.cad_pessoas_comerciais pessoa
cross join lateral jsonb_array_elements_text(
  case when jsonb_typeof(pessoa.papeis_json) = 'array' then pessoa.papeis_json else '[]'::jsonb end
) as papel(value)
where papel.value in ('funcionario', 'vendedor', 'agente', 'tecnico_campo', 'entregador', 'gerente', 'comissionado')
  and not exists (
    select 1
      from public.cad_pessoa_papeis existente
     where existente.pessoa_id = pessoa.id
       and existente.papel = papel.value
       and existente.status = 'active'
  );

create or replace function public.sync_cad_pessoa_papeis()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_papel text;
begin
  perform public.validate_cad_pessoa_papeis_json(new.papeis_json);
  v_actor := coalesce(public.current_actor_id(), new.updated_by, new.created_by);

  update public.cad_pessoa_papeis papel
     set status = 'inactive',
         vigencia_fim = clock_timestamp()
   where papel.pessoa_id = new.id
     and papel.status = 'active'
     and not exists (
       select 1
         from jsonb_array_elements_text(new.papeis_json) atual(value)
        where atual.value = papel.papel
     );

  for v_papel in
    select distinct value
      from jsonb_array_elements_text(new.papeis_json) atual(value)
  loop
    if not exists (
      select 1
        from public.cad_pessoa_papeis existente
       where existente.pessoa_id = new.id
         and existente.papel = v_papel
         and existente.status = 'active'
    ) then
      insert into public.cad_pessoa_papeis(pessoa_id, papel, created_by)
      values (new.id, v_papel, v_actor);
    end if;
  end loop;

  return new;
end;
$$;

revoke all on function public.sync_cad_pessoa_papeis() from public, anon, authenticated;

drop trigger if exists trg_cad_pessoas_sync_papeis on public.cad_pessoas_comerciais;
create trigger trg_cad_pessoas_sync_papeis
after insert or update of papeis_json on public.cad_pessoas_comerciais
for each row execute function public.sync_cad_pessoa_papeis();

alter table public.cad_pessoa_papeis enable row level security;
drop policy if exists "active user read cad_pessoa_papeis" on public.cad_pessoa_papeis;
create policy "active user read cad_pessoa_papeis" on public.cad_pessoa_papeis
for select to authenticated using (public.current_actor_id() is not null);
grant select on public.cad_pessoa_papeis to authenticated;
revoke insert, update, delete, truncate, references, trigger on public.cad_pessoa_papeis from authenticated;
revoke all on public.cad_pessoa_papeis from anon;

create or replace view public.cad_pessoas_comerciais_papeis_ativos
with (security_invoker = true)
as
select pessoa_id, papel, vigencia_inicio
from public.cad_pessoa_papeis
where status = 'active';

grant select on public.cad_pessoas_comerciais_papeis_ativos to authenticated;

comment on table public.cad_pessoa_papeis is
  'Relational and historized source for commercial roles. cad_pessoas_comerciais.papeis_json remains a compatibility input/cache.';

-- PCP quality-control participants -----------------------------------------

create table if not exists public.pcp_op_cq_participantes (
  id bigint generated always as identity primary key,
  cq_resultado_id bigint not null references public.pcp_op_cq_resultados(id) on delete cascade,
  op_id bigint not null references public.pcp_ordens_producao(id),
  papel text not null,
  ordem integer not null default 1,
  nome_snapshot text not null,
  user_profile_id uuid references public.user_profiles(id),
  pessoa_comercial_id bigint references public.cad_pessoas_comerciais(id),
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint pcp_cq_participantes_papel_check check (
    papel in ('separador_mp', 'conferente_mp', 'formulador')
  ),
  constraint pcp_cq_participantes_ordem_check check (ordem > 0),
  constraint pcp_cq_participantes_nome_check check (length(btrim(nome_snapshot)) > 0),
  constraint pcp_cq_participantes_key unique (cq_resultado_id, papel, ordem)
);

create unique index if not exists ux_pcp_cq_resultados_id_op
  on public.pcp_op_cq_resultados(id, op_id);

alter table public.pcp_op_cq_participantes
  add constraint pcp_cq_participantes_resultado_op_fk
  foreign key (cq_resultado_id, op_id)
  references public.pcp_op_cq_resultados(id, op_id) not valid;

alter table public.pcp_op_cq_participantes
  validate constraint pcp_cq_participantes_resultado_op_fk;

create index if not exists idx_pcp_cq_participantes_op
  on public.pcp_op_cq_participantes(op_id, papel);
create index if not exists idx_pcp_cq_participantes_user
  on public.pcp_op_cq_participantes(user_profile_id)
  where user_profile_id is not null;
create index if not exists idx_pcp_cq_participantes_pessoa
  on public.pcp_op_cq_participantes(pessoa_comercial_id)
  where pessoa_comercial_id is not null;

create or replace function public.expand_pcp_cq_participantes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.pcp_op_cq_participantes(
    cq_resultado_id, op_id, papel, ordem, nome_snapshot, created_by
  )
  values
    (new.id, new.op_id, 'separador_mp', 1, btrim(new.separador_mp), new.created_by),
    (new.id, new.op_id, 'conferente_mp', 1, btrim(new.conferente_mp), new.created_by);

  insert into public.pcp_op_cq_participantes(
    cq_resultado_id, op_id, papel, ordem, nome_snapshot, created_by
  )
  select
    new.id,
    new.op_id,
    'formulador',
    formulador.ordem::integer,
    btrim(formulador.nome),
    new.created_by
  from jsonb_array_elements_text(new.formuladores_json)
       with ordinality as formulador(nome, ordem)
  where nullif(btrim(formulador.nome), '') is not null;

  return new;
end;
$$;

revoke all on function public.expand_pcp_cq_participantes() from public, anon, authenticated;

insert into public.pcp_op_cq_participantes(
  cq_resultado_id, op_id, papel, ordem, nome_snapshot, created_by, created_at
)
select cq.id, cq.op_id, 'separador_mp', 1, btrim(cq.separador_mp), cq.created_by, cq.created_at
from public.pcp_op_cq_resultados cq
where nullif(btrim(cq.separador_mp), '') is not null
  and not exists (
    select 1 from public.pcp_op_cq_participantes p
    where p.cq_resultado_id = cq.id and p.papel = 'separador_mp' and p.ordem = 1
  );

insert into public.pcp_op_cq_participantes(
  cq_resultado_id, op_id, papel, ordem, nome_snapshot, created_by, created_at
)
select cq.id, cq.op_id, 'conferente_mp', 1, btrim(cq.conferente_mp), cq.created_by, cq.created_at
from public.pcp_op_cq_resultados cq
where nullif(btrim(cq.conferente_mp), '') is not null
  and not exists (
    select 1 from public.pcp_op_cq_participantes p
    where p.cq_resultado_id = cq.id and p.papel = 'conferente_mp' and p.ordem = 1
  );

insert into public.pcp_op_cq_participantes(
  cq_resultado_id, op_id, papel, ordem, nome_snapshot, created_by, created_at
)
select
  cq.id,
  cq.op_id,
  'formulador',
  formulador.ordem::integer,
  btrim(formulador.nome),
  cq.created_by,
  cq.created_at
from public.pcp_op_cq_resultados cq
cross join lateral jsonb_array_elements_text(cq.formuladores_json)
  with ordinality as formulador(nome, ordem)
where nullif(btrim(formulador.nome), '') is not null
  and not exists (
    select 1 from public.pcp_op_cq_participantes p
    where p.cq_resultado_id = cq.id and p.papel = 'formulador' and p.ordem = formulador.ordem
  );

drop trigger if exists trg_pcp_cq_expand_participantes on public.pcp_op_cq_resultados;
create trigger trg_pcp_cq_expand_participantes
after insert on public.pcp_op_cq_resultados
for each row execute function public.expand_pcp_cq_participantes();

alter table public.pcp_op_cq_participantes enable row level security;
drop policy if exists "active user read pcp_op_cq_participantes" on public.pcp_op_cq_participantes;
create policy "active user read pcp_op_cq_participantes" on public.pcp_op_cq_participantes
for select to authenticated using (public.current_actor_id() is not null);
grant select on public.pcp_op_cq_participantes to authenticated;
revoke insert, update, delete, truncate, references, trigger on public.pcp_op_cq_participantes from authenticated;
revoke all on public.pcp_op_cq_participantes from anon;

create or replace view public.pcp_op_cq_participantes_pendentes_vinculo
with (security_invoker = true)
as
select id, cq_resultado_id, op_id, papel, ordem, nome_snapshot, created_at
from public.pcp_op_cq_participantes
where user_profile_id is null and pessoa_comercial_id is null;

grant select on public.pcp_op_cq_participantes_pendentes_vinculo to authenticated;

comment on table public.pcp_op_cq_participantes is
  'Atomic CQ participation rows. nome_snapshot preserves legacy text while typed user/person links are resolved.';

-- Stable stock units --------------------------------------------------------

create or replace function public.prevent_mp_base_unit_change_after_movement()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.unidade_base_estoque := upper(btrim(new.unidade_base_estoque));

  if upper(btrim(old.unidade_base_estoque)) is distinct from new.unidade_base_estoque
     and exists (
       select 1
         from public.est_movimentos_mp movimento
        where movimento.materia_prima_id = old.id
     ) then
    raise exception 'unidade_base_estoque cannot change after the first MP movement; use source-unit conversion';
  end if;

  return new;
end;
$$;

revoke all on function public.prevent_mp_base_unit_change_after_movement() from public, anon, authenticated;

drop trigger if exists trg_cad_mp_immutable_base_unit on public.cad_materias_primas;
create trigger trg_cad_mp_immutable_base_unit
before update of unidade_base_estoque on public.cad_materias_primas
for each row execute function public.prevent_mp_base_unit_change_after_movement();

comment on column public.cad_materias_primas.unidade_base_estoque is
  'Canonical stock unit. It is immutable after the first stock movement; XML/NF source units are converted.';
comment on column public.est_movimentos_mp.quantidade is
  'Quantity expressed in the immutable canonical unit of the referenced raw material.';

-- Cross-table identity constraints -----------------------------------------

create unique index if not exists ux_est_lotes_pa_id_produto
  on public.est_lotes_pa(id, produto_embalagem_id);
create unique index if not exists ux_est_lotes_mp_id_materia
  on public.est_lotes_mp(id, materia_prima_id);
create unique index if not exists ux_est_lotes_pi_id_produto
  on public.est_lotes_pi(id, produto_id);
create unique index if not exists ux_com_pedido_itens_identity
  on public.com_pedido_itens(id, pedido_id, produto_embalagem_id);
create unique index if not exists ux_exp_romaneios_id_pedido
  on public.exp_romaneios(id, pedido_id);
create unique index if not exists ux_exp_romaneio_itens_identity
  on public.exp_romaneio_itens(id, romaneio_id, pedido_id, pedido_item_id, produto_embalagem_id);
create unique index if not exists ux_exp_romaneio_itens_fiscal
  on public.exp_romaneio_itens(id, romaneio_id, pedido_item_id, produto_embalagem_id);
create unique index if not exists ux_exp_romaneio_itens_reserva
  on public.exp_romaneio_itens(id, romaneio_id, produto_embalagem_id);
create unique index if not exists ux_fat_notas_id_pedido
  on public.fat_notas_fiscais(id, pedido_id);
create unique index if not exists ux_fat_notas_id_romaneio
  on public.fat_notas_fiscais(id, romaneio_id);
create unique index if not exists ux_pcp_componentes_id_op
  on public.pcp_op_componentes_planejados(id, op_id);
create unique index if not exists ux_pcp_reservas_id_op_componente
  on public.pcp_op_reservas_componentes(id, op_id, op_componente_id);
create unique index if not exists ux_pcp_formula_versao_identity
  on public.pcp_formula_versoes(id, produto_id, tipo_receita);

create index if not exists idx_exp_mov_pa_romaneio_item_identity
  on public.exp_romaneio_movimentos_pa(
    romaneio_item_id, romaneio_id, pedido_id, pedido_item_id, produto_embalagem_id
  );
create index if not exists idx_est_reservas_pa_romaneio_item_identity
  on public.est_reservas_pa(romaneio_item_id, romaneio_id, produto_embalagem_id);
create index if not exists idx_fat_nf_itens_nota_pedido
  on public.fat_nota_fiscal_itens(nota_fiscal_id, pedido_id);
create index if not exists idx_fat_nf_itens_nota_romaneio
  on public.fat_nota_fiscal_itens(nota_fiscal_id, romaneio_id)
  where romaneio_id is not null;
create index if not exists idx_fat_nf_itens_pedido_identity
  on public.fat_nota_fiscal_itens(pedido_item_id, pedido_id, produto_embalagem_id);
create index if not exists idx_fat_nf_itens_romaneio_identity
  on public.fat_nota_fiscal_itens(
    romaneio_item_id, romaneio_id, pedido_item_id, produto_embalagem_id
  ) where romaneio_item_id is not null;
create index if not exists idx_pcp_formula_ativacoes_identity
  on public.pcp_formula_ativacoes(formula_versao_id, produto_id, tipo_receita);
create index if not exists idx_pcp_reservas_componente_op
  on public.pcp_op_reservas_componentes(op_componente_id, op_id);
create index if not exists idx_pcp_consumos_componente_op
  on public.pcp_op_consumos_componentes(op_componente_id, op_id);
create index if not exists idx_pcp_consumos_reserva_identity
  on public.pcp_op_consumos_componentes(reserva_id, op_id, op_componente_id);

alter table public.est_movimentos_pa
  add constraint est_movimentos_pa_lote_produto_fk
  foreign key (lote_pa_id, produto_embalagem_id)
  references public.est_lotes_pa(id, produto_embalagem_id) not valid;

alter table public.est_movimentos_mp
  add constraint est_movimentos_mp_lote_materia_fk
  foreign key (lote_mp_id, materia_prima_id)
  references public.est_lotes_mp(id, materia_prima_id) not valid;

alter table public.est_movimentos_pi
  add constraint est_movimentos_pi_lote_produto_fk
  foreign key (lote_pi_id, produto_id)
  references public.est_lotes_pi(id, produto_id) not valid;

alter table public.est_reservas_pa
  add constraint est_reservas_pa_lote_produto_fk
  foreign key (lote_pa_id, produto_embalagem_id)
  references public.est_lotes_pa(id, produto_embalagem_id) not valid,
  add constraint est_reservas_pa_romaneio_item_fk
  foreign key (romaneio_item_id, romaneio_id, produto_embalagem_id)
  references public.exp_romaneio_itens(id, romaneio_id, produto_embalagem_id) not valid;

alter table public.exp_romaneio_itens
  add constraint exp_romaneio_itens_romaneio_pedido_fk
  foreign key (romaneio_id, pedido_id)
  references public.exp_romaneios(id, pedido_id) not valid,
  add constraint exp_romaneio_itens_pedido_item_fk
  foreign key (pedido_item_id, pedido_id, produto_embalagem_id)
  references public.com_pedido_itens(id, pedido_id, produto_embalagem_id) not valid;

alter table public.exp_romaneio_movimentos_pa
  add constraint exp_mov_pa_romaneio_item_identity_fk
  foreign key (romaneio_item_id, romaneio_id, pedido_id, pedido_item_id, produto_embalagem_id)
  references public.exp_romaneio_itens(id, romaneio_id, pedido_id, pedido_item_id, produto_embalagem_id) not valid,
  add constraint exp_mov_pa_lote_produto_fk
  foreign key (lote_pa_id, produto_embalagem_id)
  references public.est_lotes_pa(id, produto_embalagem_id) not valid;

alter table public.fat_nota_fiscal_itens
  add constraint fat_nf_itens_nota_pedido_fk
  foreign key (nota_fiscal_id, pedido_id)
  references public.fat_notas_fiscais(id, pedido_id) not valid,
  add constraint fat_nf_itens_nota_romaneio_fk
  foreign key (nota_fiscal_id, romaneio_id)
  references public.fat_notas_fiscais(id, romaneio_id) not valid,
  add constraint fat_nf_itens_pedido_item_fk
  foreign key (pedido_item_id, pedido_id, produto_embalagem_id)
  references public.com_pedido_itens(id, pedido_id, produto_embalagem_id) not valid,
  add constraint fat_nf_itens_romaneio_item_fk
  foreign key (romaneio_item_id, romaneio_id, pedido_item_id, produto_embalagem_id)
  references public.exp_romaneio_itens(id, romaneio_id, pedido_item_id, produto_embalagem_id) not valid;

alter table public.pcp_formula_ativacoes
  add constraint pcp_formula_ativacoes_identity_fk
  foreign key (formula_versao_id, produto_id, tipo_receita)
  references public.pcp_formula_versoes(id, produto_id, tipo_receita) not valid;

alter table public.pcp_op_reservas_componentes
  add constraint pcp_reservas_componente_op_fk
  foreign key (op_componente_id, op_id)
  references public.pcp_op_componentes_planejados(id, op_id) not valid;

alter table public.pcp_op_consumos_componentes
  add constraint pcp_consumos_componente_op_fk
  foreign key (op_componente_id, op_id)
  references public.pcp_op_componentes_planejados(id, op_id) not valid,
  add constraint pcp_consumos_reserva_identity_fk
  foreign key (reserva_id, op_id, op_componente_id)
  references public.pcp_op_reservas_componentes(id, op_id, op_componente_id) not valid;

do $$
declare
  v_item record;
begin
  for v_item in
    select * from (values
      ('est_movimentos_pa', 'est_movimentos_pa_lote_produto_fk'),
      ('est_movimentos_mp', 'est_movimentos_mp_lote_materia_fk'),
      ('est_movimentos_pi', 'est_movimentos_pi_lote_produto_fk'),
      ('est_reservas_pa', 'est_reservas_pa_lote_produto_fk'),
      ('est_reservas_pa', 'est_reservas_pa_romaneio_item_fk'),
      ('exp_romaneio_itens', 'exp_romaneio_itens_romaneio_pedido_fk'),
      ('exp_romaneio_itens', 'exp_romaneio_itens_pedido_item_fk'),
      ('exp_romaneio_movimentos_pa', 'exp_mov_pa_romaneio_item_identity_fk'),
      ('exp_romaneio_movimentos_pa', 'exp_mov_pa_lote_produto_fk'),
      ('fat_nota_fiscal_itens', 'fat_nf_itens_nota_pedido_fk'),
      ('fat_nota_fiscal_itens', 'fat_nf_itens_nota_romaneio_fk'),
      ('fat_nota_fiscal_itens', 'fat_nf_itens_pedido_item_fk'),
      ('fat_nota_fiscal_itens', 'fat_nf_itens_romaneio_item_fk'),
      ('pcp_formula_ativacoes', 'pcp_formula_ativacoes_identity_fk'),
      ('pcp_op_reservas_componentes', 'pcp_reservas_componente_op_fk'),
      ('pcp_op_consumos_componentes', 'pcp_consumos_componente_op_fk'),
      ('pcp_op_consumos_componentes', 'pcp_consumos_reserva_identity_fk')
    ) as constraints_to_validate(table_name, constraint_name)
  loop
    execute format(
      'alter table public.%I validate constraint %I',
      v_item.table_name,
      v_item.constraint_name
    );
  end loop;
end;
$$;

comment on constraint exp_romaneio_itens_pedido_item_fk on public.exp_romaneio_itens is
  'Prevents a romaneio item from combining an order, order item, and sellable product that do not belong together.';
comment on constraint fat_nf_itens_pedido_item_fk on public.fat_nota_fiscal_itens is
  'Prevents fiscal items from combining unrelated order and product identities.';
comment on constraint est_movimentos_mp_lote_materia_fk on public.est_movimentos_mp is
  'Prevents an MP movement from repeating a material different from the referenced lot.';
