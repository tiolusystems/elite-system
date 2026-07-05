do $$
begin
  alter type public.audit_axis add value if not exists 'fiscal_event';
exception
  when duplicate_object then null;
end;
$$;

create or replace function public.normalize_audit_axis(p_axis text)
returns public.audit_axis
language plpgsql
immutable
set search_path = public
as $$
declare
  v_axis text;
begin
  v_axis := lower(nullif(trim(p_axis), ''));

  if v_axis = 'event_movement' then
    v_axis := 'movement_event';
  end if;

  if v_axis in ('own_any', 'change_type', 'field_risk', 'movement_event', 'fiscal_event', 'status_transition') then
    return v_axis::public.audit_axis;
  end if;

  raise exception 'invalid audit axis: %', p_axis;
end;
$$;

insert into public.permission_actions(action_key, module, description, default_allowed, sort_order)
values
  ('faturamento.nf.view', 'faturamento', 'Ver dossie fiscal de pedido, romaneio e cliente', true, 501),
  ('faturamento.nf.issue', 'faturamento', 'Emitir ou registrar NF fiscal auditada', true, 502),
  ('faturamento.nf.cancel', 'faturamento', 'Cancelar ou inutilizar NF com evento auditado', true, 503),
  ('faturamento.nf.correct', 'faturamento', 'Registrar carta de correcao de NF', true, 504),
  ('faturamento.nf.complement', 'faturamento', 'Registrar complemento fiscal de NF', true, 505),
  ('faturamento.nf.substitute', 'faturamento', 'Registrar substituicao fiscal de NF', true, 506)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order;

create table if not exists public.fat_notas_fiscais (
  id bigint generated always as identity primary key,
  pedido_id bigint not null references public.com_pedidos(id),
  romaneio_id bigint references public.exp_romaneios(id),
  nota_pai_id bigint references public.fat_notas_fiscais(id),
  nota_complementada_id bigint references public.fat_notas_fiscais(id),
  chave_nfe text,
  numero text,
  serie text,
  data_emissao date not null default current_date,
  valor_nf numeric not null default 0,
  tipo text not null,
  status_atual text not null default 'emitida',
  observacao text,
  created_by uuid references public.user_profiles(id),
  updated_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint fat_notas_fiscais_tipo_check check (
    tipo in ('remessa_total', 'simples_faturamento', 'remessa_vinculada', 'complementar')
  ),
  constraint fat_notas_fiscais_status_check check (
    status_atual in ('emitida', 'cancelada', 'substituida', 'inutilizada')
  ),
  constraint fat_notas_fiscais_valor_check check (valor_nf >= 0),
  constraint fat_notas_fiscais_ref_exclusiva_check check (
    nota_pai_id is null or nota_complementada_id is null
  ),
  constraint fat_notas_fiscais_tipo_ref_check check (
    (
      tipo = 'remessa_total'
      and romaneio_id is not null
      and nota_pai_id is null
      and nota_complementada_id is null
    )
    or (
      tipo = 'simples_faturamento'
      and romaneio_id is null
      and nota_pai_id is null
      and nota_complementada_id is null
    )
    or (
      tipo = 'remessa_vinculada'
      and romaneio_id is not null
      and nota_pai_id is not null
      and nota_complementada_id is null
    )
    or (
      tipo = 'complementar'
      and nota_pai_id is null
      and nota_complementada_id is not null
    )
  )
);

create table if not exists public.fat_nota_fiscal_itens (
  id bigint generated always as identity primary key,
  nota_fiscal_id bigint not null references public.fat_notas_fiscais(id),
  pedido_id bigint not null references public.com_pedidos(id),
  pedido_item_id bigint not null references public.com_pedido_itens(id),
  romaneio_id bigint references public.exp_romaneios(id),
  romaneio_item_id bigint references public.exp_romaneio_itens(id),
  produto_embalagem_id bigint not null references public.cad_produto_embalagens(id),
  quantidade numeric not null default 0,
  valor_item numeric not null default 0,
  created_at timestamptz not null default now(),
  constraint fat_nf_itens_qtd_check check (quantidade >= 0),
  constraint fat_nf_itens_valor_check check (valor_item >= 0),
  constraint fat_nf_itens_conteudo_check check (quantidade > 0 or valor_item > 0),
  constraint fat_nf_itens_romaneio_check check (
    (romaneio_item_id is null and romaneio_id is null)
    or (romaneio_item_id is not null and romaneio_id is not null)
  )
);

create table if not exists public.fat_nota_fiscal_eventos (
  id bigint generated always as identity primary key,
  nota_fiscal_id bigint not null references public.fat_notas_fiscais(id),
  tipo_evento text not null,
  data_evento timestamptz not null default now(),
  motivo text,
  payload_json jsonb not null default '{}'::jsonb,
  created_by uuid references public.user_profiles(id),
  created_at timestamptz not null default now(),
  constraint fat_nf_eventos_tipo_check check (
    tipo_evento in ('emitida', 'cancelada', 'carta_correcao', 'substituida', 'inutilizada', 'complementada')
  ),
  constraint fat_nf_eventos_payload_object_check check (jsonb_typeof(payload_json) = 'object')
);

create unique index if not exists idx_fat_notas_fiscais_chave_nfe
  on public.fat_notas_fiscais(chave_nfe)
  where chave_nfe is not null;

create index if not exists idx_fat_nf_pedido_tipo on public.fat_notas_fiscais(pedido_id, tipo, status_atual);
create index if not exists idx_fat_nf_romaneio on public.fat_notas_fiscais(romaneio_id) where romaneio_id is not null;
create index if not exists idx_fat_nf_pai on public.fat_notas_fiscais(nota_pai_id) where nota_pai_id is not null;
create index if not exists idx_fat_nf_complementada on public.fat_notas_fiscais(nota_complementada_id) where nota_complementada_id is not null;
create index if not exists idx_fat_nf_itens_pedido_item on public.fat_nota_fiscal_itens(pedido_item_id, nota_fiscal_id);
create index if not exists idx_fat_nf_itens_romaneio_item on public.fat_nota_fiscal_itens(romaneio_item_id) where romaneio_item_id is not null;
create index if not exists idx_fat_nf_eventos_nota on public.fat_nota_fiscal_eventos(nota_fiscal_id, created_at desc);

drop trigger if exists trg_fat_notas_fiscais_updated_at on public.fat_notas_fiscais;
create trigger trg_fat_notas_fiscais_updated_at before update on public.fat_notas_fiscais
for each row execute function public.touch_updated_at();

comment on column public.fat_notas_fiscais.nota_pai_id is
  'Usado apenas para remessa_vinculada -> simples_faturamento. Complementar usa nota_complementada_id.';
comment on column public.fat_notas_fiscais.nota_complementada_id is
  'Usado apenas para NF complementar -> NF original complementada. Nao usar para remessa vinculada.';
comment on table public.fat_nota_fiscal_itens is
  'Itens fiscais por pedido/romaneio. NFs de carga herdam romaneio_item_id; simples faturamento referencia pedido_item_id.';
comment on column public.fat_nota_fiscal_eventos.payload_json is
  'Contrato por tipo_evento: emitida(protocolo_autorizacao, ambiente), cancelada(protocolo_cancelamento, justificativa), carta_correcao(sequencia_cce, texto_correcao), substituida(nota_substituta_id, motivo_substituicao), inutilizada(numero_inicial, numero_final, protocolo_inutilizacao, justificativa), complementada(nota_complementar_id, motivo_complemento).';

alter table public.fat_notas_fiscais enable row level security;
alter table public.fat_nota_fiscal_itens enable row level security;
alter table public.fat_nota_fiscal_eventos enable row level security;

drop policy if exists "authenticated read fat_notas_fiscais" on public.fat_notas_fiscais;
drop policy if exists "authenticated read fat_nota_fiscal_itens" on public.fat_nota_fiscal_itens;
drop policy if exists "authenticated read fat_nota_fiscal_eventos" on public.fat_nota_fiscal_eventos;

create policy "authenticated read fat_notas_fiscais" on public.fat_notas_fiscais
for select to authenticated using (public.current_actor_id() is not null);
create policy "authenticated read fat_nota_fiscal_itens" on public.fat_nota_fiscal_itens
for select to authenticated using (public.current_actor_id() is not null);
create policy "authenticated read fat_nota_fiscal_eventos" on public.fat_nota_fiscal_eventos
for select to authenticated using (public.current_actor_id() is not null);

grant select on
  public.fat_notas_fiscais,
  public.fat_nota_fiscal_itens,
  public.fat_nota_fiscal_eventos
to authenticated;

revoke insert, update, delete on
  public.fat_notas_fiscais,
  public.fat_nota_fiscal_itens,
  public.fat_nota_fiscal_eventos
from authenticated;

create or replace view public.fat_pedido_item_cobertura_fiscal
with (security_invoker = true) as
select
  item.id as pedido_item_id,
  item.pedido_id,
  item.produto_embalagem_id,
  item.quantidade as quantidade_pedido,
  coalesce(sum(case
    when nf.status_atual not in ('cancelada', 'inutilizada')
      and nf.tipo in ('remessa_total', 'simples_faturamento', 'complementar')
    then nf_item.quantidade
    else 0
  end), 0) as quantidade_faturada,
  coalesce(sum(case
    when nf.status_atual not in ('cancelada', 'inutilizada')
      and nf.tipo in ('remessa_total', 'remessa_vinculada')
    then nf_item.quantidade
    else 0
  end), 0) as quantidade_remetida_fiscal,
  item.quantidade - coalesce(sum(case
    when nf.status_atual not in ('cancelada', 'inutilizada')
      and nf.tipo in ('remessa_total', 'simples_faturamento', 'complementar')
    then nf_item.quantidade
    else 0
  end), 0) as quantidade_a_faturar
from public.com_pedido_itens item
left join public.fat_nota_fiscal_itens nf_item on nf_item.pedido_item_id = item.id
left join public.fat_notas_fiscais nf on nf.id = nf_item.nota_fiscal_id
where item.status = 'active'
group by item.id, item.pedido_id, item.produto_embalagem_id, item.quantidade;

create or replace view public.fat_pedido_dossie_fiscal
with (security_invoker = true) as
select
  pedido.id as pedido_id,
  pedido.codigo_pedido,
  pedido.cliente_id,
  coalesce(jsonb_agg(
    jsonb_build_object(
      'nota_fiscal', to_jsonb(nf),
      'itens', coalesce((
        select jsonb_agg(to_jsonb(nf_item) order by nf_item.id)
          from public.fat_nota_fiscal_itens nf_item
         where nf_item.nota_fiscal_id = nf.id
      ), '[]'::jsonb),
      'eventos', coalesce((
        select jsonb_agg(to_jsonb(evento) order by evento.created_at, evento.id)
          from public.fat_nota_fiscal_eventos evento
         where evento.nota_fiscal_id = nf.id
      ), '[]'::jsonb)
    )
    order by nf.data_emissao, nf.id
  ) filter (where nf.id is not null), '[]'::jsonb) as notas_fiscais,
  coalesce((
    select jsonb_agg(to_jsonb(cobertura) order by cobertura.pedido_item_id)
      from public.fat_pedido_item_cobertura_fiscal cobertura
     where cobertura.pedido_id = pedido.id
  ), '[]'::jsonb) as cobertura_itens
from public.com_pedidos pedido
left join public.fat_notas_fiscais nf on nf.pedido_id = pedido.id
group by pedido.id, pedido.codigo_pedido, pedido.cliente_id;

grant select on public.fat_pedido_item_cobertura_fiscal to authenticated;
grant select on public.fat_pedido_dossie_fiscal to authenticated;

create or replace function public.fat_validate_event_payload(
  p_tipo_evento text,
  p_payload_json jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tipo_evento text;
  v_payload jsonb;
begin
  v_tipo_evento := nullif(trim(p_tipo_evento), '');
  v_payload := coalesce(p_payload_json, '{}'::jsonb);

  if v_tipo_evento not in ('emitida', 'cancelada', 'carta_correcao', 'substituida', 'inutilizada', 'complementada') then
    raise exception 'invalid fiscal event type';
  end if;
  if jsonb_typeof(v_payload) <> 'object' then
    raise exception 'payload_json must be a json object';
  end if;

  if v_tipo_evento = 'emitida' and not (v_payload ? 'protocolo_autorizacao' and v_payload ? 'ambiente') then
    raise exception 'payload_json for emitida requires protocolo_autorizacao and ambiente';
  elsif v_tipo_evento = 'cancelada' and not (v_payload ? 'protocolo_cancelamento' and v_payload ? 'justificativa') then
    raise exception 'payload_json for cancelada requires protocolo_cancelamento and justificativa';
  elsif v_tipo_evento = 'carta_correcao' and not (v_payload ? 'sequencia_cce' and v_payload ? 'texto_correcao') then
    raise exception 'payload_json for carta_correcao requires sequencia_cce and texto_correcao';
  elsif v_tipo_evento = 'substituida' and not (v_payload ? 'nota_substituta_id' and v_payload ? 'motivo_substituicao') then
    raise exception 'payload_json for substituida requires nota_substituta_id and motivo_substituicao';
  elsif v_tipo_evento = 'inutilizada' and not (v_payload ? 'numero_inicial' and v_payload ? 'numero_final' and v_payload ? 'protocolo_inutilizacao' and v_payload ? 'justificativa') then
    raise exception 'payload_json for inutilizada requires numero_inicial, numero_final, protocolo_inutilizacao and justificativa';
  elsif v_tipo_evento = 'complementada' and not (v_payload ? 'nota_complementar_id' and v_payload ? 'motivo_complemento') then
    raise exception 'payload_json for complementada requires nota_complementar_id and motivo_complemento';
  end if;
end;
$$;

create or replace function public.fat_nota_fiscal_audit_snapshot(p_nota_fiscal_id bigint)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'nota_fiscal', (
      select to_jsonb(nf)
        from public.fat_notas_fiscais nf
       where nf.id = p_nota_fiscal_id
    ),
    'itens', coalesce((
      select jsonb_agg(to_jsonb(nf_item) order by nf_item.id)
        from public.fat_nota_fiscal_itens nf_item
       where nf_item.nota_fiscal_id = p_nota_fiscal_id
    ), '[]'::jsonb),
    'eventos', coalesce((
      select jsonb_agg(to_jsonb(evento) order by evento.id)
        from public.fat_nota_fiscal_eventos evento
       where evento.nota_fiscal_id = p_nota_fiscal_id
    ), '[]'::jsonb),
    'cobertura_itens', coalesce((
      select jsonb_agg(to_jsonb(cobertura) order by cobertura.pedido_item_id)
        from public.fat_pedido_item_cobertura_fiscal cobertura
       where cobertura.pedido_id = (
         select nf.pedido_id from public.fat_notas_fiscais nf where nf.id = p_nota_fiscal_id
       )
    ), '[]'::jsonb)
  );
$$;

create or replace function public.emitir_fat_nota_fiscal(
  p_pedido_id bigint,
  p_tipo text,
  p_itens_jsonb jsonb,
  p_chave_nfe text default null,
  p_numero text default null,
  p_serie text default null,
  p_data_emissao date default current_date,
  p_valor_nf numeric default 0,
  p_romaneio_id bigint default null,
  p_nota_pai_id bigint default null,
  p_nota_complementada_id bigint default null,
  p_payload_json jsonb default '{}'::jsonb,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_tipo text;
  v_pedido_status text;
  v_nf_id bigint;
  v_item_json jsonb;
  v_pedido_item_id bigint;
  v_romaneio_item_id bigint;
  v_produto_embalagem_id bigint;
  v_quantidade numeric;
  v_valor_item numeric;
  v_pedido_item record;
  v_romaneio record;
  v_romaneio_item record;
  v_nota_pai record;
  v_nota_complementada record;
  v_qtd_faturada_anterior numeric;
  v_qtd_pai numeric;
  v_qtd_vinculada_anterior numeric;
  v_before jsonb;
  v_after jsonb;
  v_permission_context jsonb;
begin
  v_tipo := nullif(trim(p_tipo), '');
  if p_pedido_id is null or p_pedido_id <= 0 then
    raise exception 'pedido_id is required';
  end if;
  if v_tipo not in ('remessa_total', 'simples_faturamento', 'remessa_vinculada', 'complementar') then
    raise exception 'invalid fiscal invoice type';
  end if;
  if p_itens_jsonb is null or jsonb_typeof(p_itens_jsonb) <> 'array' or jsonb_array_length(p_itens_jsonb) = 0 then
    raise exception 'itens_jsonb must be a non-empty array';
  end if;
  if p_data_emissao is null then
    raise exception 'data_emissao is required';
  end if;
  if p_valor_nf is null or p_valor_nf < 0 then
    raise exception 'valor_nf must be greater than or equal to zero';
  end if;

  perform public.fat_validate_event_payload('emitida', p_payload_json);

  v_permission_context := public.begin_audited_rpc(
    'faturamento.nf.issue',
    'faturamento',
    'fat_notas_fiscais',
    'fiscal_event',
    jsonb_build_object('event', 'issue', 'tipo', v_tipo, 'source', 'emitir_fat_nota_fiscal')
  );

  select status
    into v_pedido_status
    from public.com_pedidos
   where id = p_pedido_id
   for update;

  if not found then
    raise exception 'pedido not found';
  end if;
  if v_pedido_status in ('draft', 'blocked', 'cancelled') then
    raise exception 'pedido status does not allow fiscal invoice';
  end if;

  if v_tipo = 'remessa_total' then
    if p_romaneio_id is null or p_nota_pai_id is not null or p_nota_complementada_id is not null then
      raise exception 'remessa_total requires romaneio_id and no fiscal parent';
    end if;
  elsif v_tipo = 'simples_faturamento' then
    if p_romaneio_id is not null or p_nota_pai_id is not null or p_nota_complementada_id is not null then
      raise exception 'simples_faturamento cannot reference romaneio or parent invoice';
    end if;
  elsif v_tipo = 'remessa_vinculada' then
    if p_romaneio_id is null or p_nota_pai_id is null or p_nota_complementada_id is not null then
      raise exception 'remessa_vinculada requires romaneio_id and nota_pai_id';
    end if;

    select *
      into v_nota_pai
      from public.fat_notas_fiscais
     where id = p_nota_pai_id
     for update;

    if not found then
      raise exception 'nota_pai not found';
    end if;
    if v_nota_pai.tipo <> 'simples_faturamento' or v_nota_pai.pedido_id <> p_pedido_id or v_nota_pai.status_atual <> 'emitida' then
      raise exception 'nota_pai must be an active simples_faturamento invoice for the same pedido';
    end if;
  else
    if p_nota_pai_id is not null or p_nota_complementada_id is null then
      raise exception 'complementar requires nota_complementada_id and no nota_pai_id';
    end if;

    select *
      into v_nota_complementada
      from public.fat_notas_fiscais
     where id = p_nota_complementada_id
     for update;

    if not found then
      raise exception 'nota_complementada not found';
    end if;
    if v_nota_complementada.pedido_id <> p_pedido_id or v_nota_complementada.status_atual in ('cancelada', 'inutilizada') then
      raise exception 'nota_complementada must be active and belong to the same pedido';
    end if;
  end if;

  if p_romaneio_id is not null then
    select id, pedido_id, status
      into v_romaneio
      from public.exp_romaneios
     where id = p_romaneio_id
     for update;

    if not found then
      raise exception 'romaneio not found';
    end if;
    if v_romaneio.pedido_id <> p_pedido_id then
      raise exception 'romaneio does not belong to pedido';
    end if;
    if v_romaneio.status <> 'confirmado' then
      raise exception 'romaneio must be confirmed before fiscal invoice';
    end if;
  end if;

  v_actor := public.current_actor_id();

  insert into public.fat_notas_fiscais(
    pedido_id,
    romaneio_id,
    nota_pai_id,
    nota_complementada_id,
    chave_nfe,
    numero,
    serie,
    data_emissao,
    valor_nf,
    tipo,
    status_atual,
    observacao,
    created_by,
    updated_by
  )
  values (
    p_pedido_id,
    p_romaneio_id,
    p_nota_pai_id,
    p_nota_complementada_id,
    nullif(trim(p_chave_nfe), ''),
    nullif(trim(p_numero), ''),
    nullif(trim(p_serie), ''),
    p_data_emissao,
    p_valor_nf,
    v_tipo,
    'emitida',
    nullif(trim(p_observacao), ''),
    v_actor,
    v_actor
  )
  returning id into v_nf_id;

  for v_item_json in
    select value from jsonb_array_elements(p_itens_jsonb)
  loop
    v_pedido_item_id := case
      when nullif(trim(v_item_json->>'pedido_item_id'), '') is null then null
      else (v_item_json->>'pedido_item_id')::bigint
    end;
    v_romaneio_item_id := case
      when nullif(trim(v_item_json->>'romaneio_item_id'), '') is null then null
      else (v_item_json->>'romaneio_item_id')::bigint
    end;
    v_quantidade := case
      when nullif(trim(v_item_json->>'quantidade'), '') is null then null
      else (v_item_json->>'quantidade')::numeric
    end;
    v_valor_item := coalesce(case
      when nullif(trim(v_item_json->>'valor_item'), '') is null then null
      else (v_item_json->>'valor_item')::numeric
    end, 0);

    if v_tipo in ('remessa_total', 'remessa_vinculada') then
      if v_romaneio_item_id is null then
        raise exception 'romaneio_item_id is required for fiscal invoice from cargo';
      end if;

      select
          rom_item.id,
          rom_item.pedido_id,
          rom_item.pedido_item_id,
          rom_item.produto_embalagem_id,
          rom_item.quantidade_romaneada,
          rom_item.status
        into v_romaneio_item
        from public.exp_romaneio_itens rom_item
       where rom_item.id = v_romaneio_item_id
         and rom_item.romaneio_id = p_romaneio_id
       for update;

      if not found then
        raise exception 'romaneio_item not found';
      end if;
      if v_romaneio_item.pedido_id <> p_pedido_id then
        raise exception 'romaneio item does not belong to pedido';
      end if;
      if v_romaneio_item.status <> 'confirmado' then
        raise exception 'romaneio item must be confirmed before fiscal invoice';
      end if;
      if v_pedido_item_id is not null and v_pedido_item_id <> v_romaneio_item.pedido_item_id then
        raise exception 'pedido_item_id does not match romaneio item';
      end if;
      if v_quantidade is not null and v_quantidade <> v_romaneio_item.quantidade_romaneada then
        raise exception 'fiscal item quantity must match confirmed romaneio item quantity';
      end if;

      if exists (
        select 1
          from public.fat_nota_fiscal_itens nf_item
          join public.fat_notas_fiscais nf on nf.id = nf_item.nota_fiscal_id
         where nf_item.romaneio_item_id = v_romaneio_item_id
           and nf.status_atual not in ('cancelada', 'inutilizada')
      ) then
        raise exception 'romaneio item already has active fiscal document';
      end if;

      v_pedido_item_id := v_romaneio_item.pedido_item_id;
      v_produto_embalagem_id := v_romaneio_item.produto_embalagem_id;
      v_quantidade := v_romaneio_item.quantidade_romaneada;
    else
      if v_pedido_item_id is null then
        raise exception 'pedido_item_id is required';
      end if;
      if v_romaneio_item_id is not null then
        raise exception 'romaneio_item_id is not allowed for this fiscal invoice type';
      end if;

      select id, pedido_id, produto_embalagem_id, quantidade, status
        into v_pedido_item
        from public.com_pedido_itens
       where id = v_pedido_item_id
       for update;

      if not found then
        raise exception 'pedido item not found';
      end if;
      if v_pedido_item.pedido_id <> p_pedido_id then
        raise exception 'pedido item does not belong to pedido';
      end if;
      if v_pedido_item.status <> 'active' then
        raise exception 'pedido item status does not allow fiscal invoice';
      end if;
      if v_quantidade is null then
        raise exception 'quantidade is required';
      end if;
      v_produto_embalagem_id := v_pedido_item.produto_embalagem_id;
    end if;

    if v_quantidade is null or v_quantidade < 0 then
      raise exception 'quantidade must be greater than or equal to zero';
    end if;
    if v_valor_item < 0 then
      raise exception 'valor_item must be greater than or equal to zero';
    end if;
    if v_quantidade = 0 and v_valor_item = 0 then
      raise exception 'fiscal item must have quantity or value';
    end if;

    select id, pedido_id, produto_embalagem_id, quantidade, status
      into v_pedido_item
      from public.com_pedido_itens
     where id = v_pedido_item_id
     for update;

    if v_tipo in ('remessa_total', 'simples_faturamento', 'complementar') and v_quantidade > 0 then
      select coalesce(sum(nf_item.quantidade), 0)
        into v_qtd_faturada_anterior
        from public.fat_nota_fiscal_itens nf_item
        join public.fat_notas_fiscais nf on nf.id = nf_item.nota_fiscal_id
       where nf_item.pedido_item_id = v_pedido_item_id
         and nf.status_atual not in ('cancelada', 'inutilizada')
         and nf.tipo in ('remessa_total', 'simples_faturamento', 'complementar');

      if v_qtd_faturada_anterior + v_quantidade > v_pedido_item.quantidade then
        raise exception 'fiscal commercial quantity exceeds order item quantity';
      end if;
    end if;

    if v_tipo = 'remessa_vinculada' then
      select coalesce(sum(nf_item.quantidade), 0)
        into v_qtd_pai
        from public.fat_nota_fiscal_itens nf_item
       where nf_item.nota_fiscal_id = p_nota_pai_id
         and nf_item.pedido_item_id = v_pedido_item_id;

      if v_qtd_pai <= 0 then
        raise exception 'parent simple invoice does not cover this order item';
      end if;

      select coalesce(sum(nf_item.quantidade), 0)
        into v_qtd_vinculada_anterior
        from public.fat_nota_fiscal_itens nf_item
        join public.fat_notas_fiscais nf on nf.id = nf_item.nota_fiscal_id
       where nf.nota_pai_id = p_nota_pai_id
         and nf.tipo = 'remessa_vinculada'
         and nf.status_atual not in ('cancelada', 'inutilizada')
         and nf_item.pedido_item_id = v_pedido_item_id;

      if v_qtd_vinculada_anterior + v_quantidade > v_qtd_pai then
        raise exception 'linked remittance quantity exceeds parent simple invoice quantity';
      end if;
    end if;

    insert into public.fat_nota_fiscal_itens(
      nota_fiscal_id,
      pedido_id,
      pedido_item_id,
      romaneio_id,
      romaneio_item_id,
      produto_embalagem_id,
      quantidade,
      valor_item
    )
    values (
      v_nf_id,
      p_pedido_id,
      v_pedido_item_id,
      case when v_tipo in ('remessa_total', 'remessa_vinculada') then p_romaneio_id else null end,
      case when v_tipo in ('remessa_total', 'remessa_vinculada') then v_romaneio_item_id else null end,
      v_produto_embalagem_id,
      v_quantidade,
      v_valor_item
    );
  end loop;

  insert into public.fat_nota_fiscal_eventos(
    nota_fiscal_id,
    tipo_evento,
    data_evento,
    motivo,
    payload_json,
    created_by
  )
  values (
    v_nf_id,
    'emitida',
    now(),
    nullif(trim(p_observacao), ''),
    p_payload_json,
    v_actor
  );

  if v_tipo = 'complementar' then
    insert into public.fat_nota_fiscal_eventos(
      nota_fiscal_id,
      tipo_evento,
      data_evento,
      motivo,
      payload_json,
      created_by
    )
    values (
      p_nota_complementada_id,
      'complementada',
      now(),
      coalesce(nullif(trim(p_observacao), ''), 'NF complementar emitida'),
      jsonb_build_object(
        'nota_complementar_id', v_nf_id,
        'motivo_complemento', coalesce(nullif(trim(p_observacao), ''), 'NF complementar emitida'),
        'valor_complementar', p_valor_nf
      ),
      v_actor
    );
  end if;

  v_after := public.fat_nota_fiscal_audit_snapshot(v_nf_id);

  perform public.log_audited_rpc_change(
    'faturamento',
    'fat_notas_fiscais',
    v_nf_id::text,
    'faturamento.nf_emitida',
    'faturamento.nf.issue',
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'emitir_fat_nota_fiscal',
      'pedido_id', p_pedido_id,
      'romaneio_id', p_romaneio_id,
      'tipo', v_tipo,
      'nota_pai_id', p_nota_pai_id,
      'nota_complementada_id', p_nota_complementada_id,
      'itens', jsonb_array_length(p_itens_jsonb),
      'commercial_quantity_validated', true,
      'romaneio_item_required_for_cargo_invoice', v_tipo in ('remessa_total', 'remessa_vinculada')
    ),
    'database_rpc'
  );

  return v_nf_id;
end;
$$;

create or replace function public.registrar_fat_nota_fiscal_evento(
  p_nota_fiscal_id bigint,
  p_tipo_evento text,
  p_motivo text,
  p_payload_json jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_tipo_evento text;
  v_action_key text;
  v_before jsonb;
  v_after jsonb;
  v_evento_id bigint;
  v_permission_context jsonb;
begin
  v_tipo_evento := nullif(trim(p_tipo_evento), '');
  if p_nota_fiscal_id is null or p_nota_fiscal_id <= 0 then
    raise exception 'nota_fiscal_id is required';
  end if;
  if v_tipo_evento = 'emitida' then
    v_action_key := 'faturamento.nf.issue';
  elsif v_tipo_evento in ('cancelada', 'inutilizada') then
    v_action_key := 'faturamento.nf.cancel';
  elsif v_tipo_evento = 'carta_correcao' then
    v_action_key := 'faturamento.nf.correct';
  elsif v_tipo_evento = 'substituida' then
    v_action_key := 'faturamento.nf.substitute';
  elsif v_tipo_evento = 'complementada' then
    v_action_key := 'faturamento.nf.complement';
  else
    raise exception 'invalid fiscal event type';
  end if;

  perform public.fat_validate_event_payload(v_tipo_evento, p_payload_json);

  if v_tipo_evento in ('cancelada', 'carta_correcao', 'substituida', 'inutilizada', 'complementada')
     and nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required for fiscal event';
  end if;

  v_permission_context := public.begin_audited_rpc(
    v_action_key,
    'faturamento',
    'fat_nota_fiscal_eventos',
    'fiscal_event',
    jsonb_build_object('event', v_tipo_evento, 'source', 'registrar_fat_nota_fiscal_evento')
  );

  if not exists (
    select 1
      from public.fat_notas_fiscais
     where id = p_nota_fiscal_id
     for update
  ) then
    raise exception 'nota_fiscal not found';
  end if;

  v_before := public.fat_nota_fiscal_audit_snapshot(p_nota_fiscal_id);
  v_actor := public.current_actor_id();

  insert into public.fat_nota_fiscal_eventos(
    nota_fiscal_id,
    tipo_evento,
    data_evento,
    motivo,
    payload_json,
    created_by
  )
  values (
    p_nota_fiscal_id,
    v_tipo_evento,
    now(),
    nullif(trim(p_motivo), ''),
    p_payload_json,
    v_actor
  )
  returning id into v_evento_id;

  if v_tipo_evento in ('cancelada', 'substituida', 'inutilizada') then
    update public.fat_notas_fiscais
       set status_atual = v_tipo_evento,
           updated_by = v_actor
     where id = p_nota_fiscal_id;
  end if;

  v_after := public.fat_nota_fiscal_audit_snapshot(p_nota_fiscal_id);

  perform public.log_audited_rpc_change(
    'faturamento',
    'fat_nota_fiscal_eventos',
    v_evento_id::text,
    concat('faturamento.nf_', v_tipo_evento),
    v_action_key,
    v_permission_context,
    v_before,
    v_after,
    jsonb_build_object(
      'source', 'registrar_fat_nota_fiscal_evento',
      'nota_fiscal_id', p_nota_fiscal_id,
      'tipo_evento', v_tipo_evento,
      'motivo', nullif(trim(p_motivo), '')
    ),
    'database_rpc'
  );

  return v_evento_id;
end;
$$;

revoke all on function public.fat_validate_event_payload(text, jsonb) from public;
revoke all on function public.fat_nota_fiscal_audit_snapshot(bigint) from public;

revoke all on function public.emitir_fat_nota_fiscal(bigint, text, jsonb, text, text, text, date, numeric, bigint, bigint, bigint, jsonb, text) from public;
grant execute on function public.emitir_fat_nota_fiscal(bigint, text, jsonb, text, text, text, date, numeric, bigint, bigint, bigint, jsonb, text) to authenticated;

revoke all on function public.registrar_fat_nota_fiscal_evento(bigint, text, text, jsonb) from public;
grant execute on function public.registrar_fat_nota_fiscal_evento(bigint, text, text, jsonb) to authenticated;
