-- E2E-01: governed operational stock entry and external fiscal references.
-- Elite does not issue fiscal documents. It only records identifiers produced
-- by an external fiscal system and uses the shipping reference as a gate for
-- the governed Romaneio stock movement.

insert into public.permission_actions(
  action_key, module, description, default_allowed, sort_order,
  runtime_module_key, runtime_access_kind
)
values
  (
    'faturamento.external_references.register', 'faturamento',
    'Registrar referencia fiscal externa', false, 541,
    'faturamento', 'write'
  ),
  (
    'faturamento.external_references.correct', 'faturamento',
    'Corrigir numero de referencia fiscal externa', false, 542,
    'faturamento', 'write'
  )
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

create table public.est_entrada_mp_requisicoes (
  idempotency_key uuid primary key,
  lote_mp_id bigint not null unique references public.est_lotes_mp(id) on delete restrict,
  movimento_mp_id bigint not null unique references public.est_movimentos_mp(id) on delete restrict,
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  payload_hash text not null,
  created_at timestamptz not null default now()
);

alter table public.est_entrada_mp_requisicoes enable row level security;
revoke all on public.est_entrada_mp_requisicoes from public, anon, authenticated;

create or replace function public.registrar_est_entrada_mp_idempotente(
  p_idempotency_key uuid,
  p_materia_prima_id bigint,
  p_quantidade numeric,
  p_status_lote text,
  p_data_fabricacao date,
  p_data_validade date,
  p_codigo_lote_fornecedor text,
  p_documento_ref text,
  p_data_documento date,
  p_unidade_origem text,
  p_valor_materia_prima numeric,
  p_frete numeric default 0,
  p_difal_icms numeric default 0,
  p_difal_status text default 'not_applicable',
  p_difal_motivo text default null,
  p_outras_despesas numeric default 0,
  p_uf_emitente text default null,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_payload_hash text;
  v_existing public.est_entrada_mp_requisicoes%rowtype;
  v_lote_id bigint;
  v_movimento_id bigint;
  v_context jsonb;
  v_status text := lower(btrim(coalesce(p_status_lote, '')));
  v_difal_status text := lower(btrim(coalesce(p_difal_status, '')));
  v_uf text := nullif(upper(btrim(coalesce(p_uf_emitente, ''))), '');
begin
  perform public.require_current_user_permission('estoque.mp.lots.create');
  perform public.require_current_user_permission('estoque.mp.acquisition_value.register');
  if p_idempotency_key is null then raise exception 'idempotency_key is required'; end if;
  if p_materia_prima_id is null or p_materia_prima_id <= 0 then raise exception 'raw material is required'; end if;
  if p_quantidade is null or p_quantidade <= 0 then raise exception 'quantity must be greater than zero'; end if;
  if v_status not in ('disponivel', 'bloqueado') then raise exception 'invalid lot quality status'; end if;
  if nullif(btrim(coalesce(p_codigo_lote_fornecedor, '')), '') is null then raise exception 'supplier lot is required'; end if;
  if nullif(btrim(coalesce(p_documento_ref, '')), '') is null then raise exception 'source document is required'; end if;
  if nullif(btrim(coalesce(p_unidade_origem, '')), '') is null then raise exception 'source unit is required'; end if;
  if coalesce(p_valor_materia_prima, 0) < 0 or coalesce(p_frete, 0) < 0
     or coalesce(p_difal_icms, 0) < 0 or coalesce(p_outras_despesas, 0) < 0 then
    raise exception 'cost components must be non-negative';
  end if;
  if v_difal_status not in ('informed', 'not_applicable', 'pending_review') then raise exception 'invalid DIFAL status'; end if;
  if coalesce(p_difal_icms, 0) > 0 and v_difal_status <> 'informed' then raise exception 'informed DIFAL value requires informed status'; end if;
  if coalesce(p_difal_icms, 0) = 0 and v_difal_status = 'pending_review'
     and nullif(btrim(coalesce(p_difal_motivo, '')), '') is null then raise exception 'pending DIFAL requires reason'; end if;
  if v_uf = 'SP' and coalesce(p_difal_icms, 0) <> 0 then raise exception 'SP source cannot include DIFAL'; end if;

  v_actor := public.current_actor_id();
  v_payload_hash := md5(jsonb_build_object(
    'materia_prima_id', p_materia_prima_id,
    'quantidade', p_quantidade,
    'status_lote', v_status,
    'data_fabricacao', p_data_fabricacao,
    'data_validade', p_data_validade,
    'codigo_lote_fornecedor', btrim(p_codigo_lote_fornecedor),
    'documento_ref', btrim(p_documento_ref),
    'data_documento', p_data_documento,
    'unidade_origem', upper(btrim(p_unidade_origem)),
    'valor_materia_prima', coalesce(p_valor_materia_prima, 0),
    'frete', coalesce(p_frete, 0),
    'difal_icms', coalesce(p_difal_icms, 0),
    'difal_status', v_difal_status,
    'difal_motivo', nullif(btrim(coalesce(p_difal_motivo, '')), ''),
    'outras_despesas', coalesce(p_outras_despesas, 0),
    'uf_emitente', v_uf,
    'observacao', nullif(btrim(coalesce(p_observacao, '')), '')
  )::text);

  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing
    from public.est_entrada_mp_requisicoes request
   where request.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.actor_id is distinct from v_actor or v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'idempotency key reused with different stock entry request';
    end if;
    return v_existing.lote_mp_id;
  end if;

  v_context := public.begin_audited_rpc(
    'estoque.mp.acquisition_value.register', 'estoque', 'est_movimentos_mp_valores', 'movement_event',
    jsonb_build_object('event', 'valued_stock_entry', 'idempotency_key', p_idempotency_key)
  );

  v_lote_id := public.create_est_lote_mp(
    p_materia_prima_id,
    p_quantidade,
    null,
    'entrada_compra',
    v_status,
    p_data_fabricacao,
    p_data_validade,
    btrim(p_codigo_lote_fornecedor),
    nullif(btrim(coalesce(p_observacao, '')), '')
  );

  update public.est_lotes_mp
     set codigo_lote_fornecedor = btrim(p_codigo_lote_fornecedor),
         origem_ref = btrim(p_documento_ref),
         updated_by = v_actor,
         updated_at = now()
   where id = v_lote_id;

  select movimento.id into v_movimento_id
    from public.est_movimentos_mp movimento
   where movimento.lote_mp_id = v_lote_id
     and movimento.tipo_movimento = 'entrada_compra'
   order by movimento.id
   limit 1;

  if v_movimento_id is null then raise exception 'stock entry movement was not generated'; end if;

  insert into public.est_movimentos_mp_valores(
    movimento_mp_id, quantidade_origem, unidade_origem, quantidade_base,
    moeda, valor_materia_prima, frete, difal_icms, difal_status, difal_motivo,
    outras_despesas, documento_ref, data_documento, uf_emitente,
    origem_dados, created_by
  ) values (
    v_movimento_id, p_quantidade, upper(btrim(p_unidade_origem)), p_quantidade,
    'BRL', coalesce(p_valor_materia_prima, 0), coalesce(p_frete, 0),
    coalesce(p_difal_icms, 0), v_difal_status,
    nullif(btrim(coalesce(p_difal_motivo, '')), ''), coalesce(p_outras_despesas, 0),
    btrim(p_documento_ref), p_data_documento, v_uf, 'sistema', v_actor
  );

  insert into public.est_entrada_mp_requisicoes(
    idempotency_key, lote_mp_id, movimento_mp_id, actor_id, payload_hash
  ) values (p_idempotency_key, v_lote_id, v_movimento_id, v_actor, v_payload_hash);

  perform public.log_audited_rpc_change(
    'estoque', 'est_movimentos_mp_valores', v_movimento_id::text,
    'estoque.mp_valued_entry_registered', 'estoque.mp.acquisition_value.register', v_context,
    null,
    (select to_jsonb(valor) from public.est_movimentos_mp_valores valor where valor.movimento_mp_id = v_movimento_id),
    jsonb_build_object(
      'lote_mp_id', v_lote_id,
      'documento_ref', btrim(p_documento_ref),
      'idempotency_key', p_idempotency_key
    )
  );

  return v_lote_id;
end;
$$;

revoke all on function public.registrar_est_entrada_mp_idempotente(
  uuid, bigint, numeric, text, date, date, text, text, date, text,
  numeric, numeric, numeric, text, text, numeric, text, text
) from public, anon;
grant execute on function public.registrar_est_entrada_mp_idempotente(
  uuid, bigint, numeric, text, date, date, text, text, date, text,
  numeric, numeric, numeric, text, text, numeric, text, text
) to authenticated;

alter table public.fat_notas_fiscais
  add column origem_registro text;

alter table public.fat_notas_fiscais
  add constraint fat_notas_fiscais_origem_registro_check
  check (origem_registro is null or origem_registro = 'externa');

create unique index uq_fat_nf_externa_simples_ativa_pedido
  on public.fat_notas_fiscais(pedido_id)
  where origem_registro = 'externa'
    and tipo = 'simples_faturamento'
    and status_atual = 'emitida';

create unique index uq_fat_nf_externa_remessa_ativa_romaneio
  on public.fat_notas_fiscais(romaneio_id)
  where origem_registro = 'externa'
    and tipo in ('remessa_total', 'remessa_vinculada')
    and status_atual = 'emitida';

alter table public.fat_nota_fiscal_eventos
  drop constraint fat_nf_eventos_tipo_check;
alter table public.fat_nota_fiscal_eventos
  add constraint fat_nf_eventos_tipo_check check (tipo_evento in (
    'emitida', 'cancelada', 'carta_correcao', 'substituida', 'inutilizada',
    'complementada', 'referencia_externa_registrada', 'numero_referencia_corrigido'
  ));

create table public.fat_referencia_externa_requisicoes (
  idempotency_key uuid primary key,
  operacao text not null check (operacao in ('registrar', 'corrigir_numero')),
  nota_fiscal_id bigint not null references public.fat_notas_fiscais(id) on delete restrict,
  evento_id bigint references public.fat_nota_fiscal_eventos(id) on delete restrict,
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  payload_hash text not null,
  created_at timestamptz not null default now()
);

alter table public.fat_referencia_externa_requisicoes enable row level security;
revoke all on public.fat_referencia_externa_requisicoes from public, anon, authenticated;

create or replace function public.registrar_fat_referencia_externa_idempotente(
  p_idempotency_key uuid,
  p_pedido_id bigint,
  p_tipo text,
  p_numero text,
  p_serie text default null,
  p_data_documento date default current_date,
  p_romaneio_id bigint default null,
  p_referencia_pai_id bigint default null,
  p_motivo text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_tipo text := lower(btrim(coalesce(p_tipo, '')));
  v_numero text := nullif(btrim(coalesce(p_numero, '')), '');
  v_serie text := nullif(btrim(coalesce(p_serie, '')), '');
  v_payload_hash text;
  v_existing public.fat_referencia_externa_requisicoes%rowtype;
  v_pedido public.com_pedidos%rowtype;
  v_romaneio public.exp_romaneios%rowtype;
  v_pai public.fat_notas_fiscais%rowtype;
  v_nota_id bigint;
  v_evento_id bigint;
  v_valor numeric := 0;
  v_context jsonb;
begin
  perform public.require_current_user_permission('faturamento.external_references.register');
  if p_idempotency_key is null then raise exception 'idempotency_key is required'; end if;
  if p_pedido_id is null or p_pedido_id <= 0 then raise exception 'order is required'; end if;
  if v_numero is null then raise exception 'external fiscal reference number is required'; end if;
  if p_data_documento is null then raise exception 'document date is required'; end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 5 then raise exception 'reason must have at least 5 characters'; end if;
  if v_tipo not in ('simples_faturamento', 'remessa_total', 'remessa_vinculada') then
    raise exception 'invalid external fiscal reference type';
  end if;

  v_actor := public.current_actor_id();
  v_payload_hash := md5(jsonb_build_object(
    'pedido_id', p_pedido_id, 'tipo', v_tipo, 'numero', v_numero,
    'serie', v_serie, 'data_documento', p_data_documento,
    'romaneio_id', p_romaneio_id, 'referencia_pai_id', p_referencia_pai_id,
    'motivo', btrim(p_motivo)
  )::text);
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing from public.fat_referencia_externa_requisicoes request
   where request.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.operacao <> 'registrar'
       or v_existing.actor_id is distinct from v_actor
       or v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'idempotency key reused with different external fiscal reference request';
    end if;
    return v_existing.nota_fiscal_id;
  end if;

  select * into v_pedido from public.com_pedidos pedido where pedido.id = p_pedido_id for update;
  if not found then raise exception 'order not found'; end if;
  if v_pedido.status not in ('open', 'fulfilled') then raise exception 'order status does not allow external fiscal reference'; end if;

  if v_tipo = 'simples_faturamento' then
    if p_romaneio_id is not null or p_referencia_pai_id is not null then
      raise exception 'simple billing reference cannot have shipping record or parent';
    end if;
  else
    if p_romaneio_id is null then raise exception 'shipping reference requires romaneio'; end if;
    select * into v_romaneio from public.exp_romaneios romaneio where romaneio.id = p_romaneio_id for update;
    if not found or v_romaneio.pedido_id <> p_pedido_id then raise exception 'romaneio must belong to order'; end if;
    if v_romaneio.status not in ('draft', 'separacao') then raise exception 'romaneio status does not allow external fiscal reference'; end if;
    if v_tipo = 'remessa_vinculada' then
      if p_referencia_pai_id is null then raise exception 'linked shipping reference requires parent simple reference'; end if;
      select * into v_pai from public.fat_notas_fiscais nf where nf.id = p_referencia_pai_id for update;
      if not found or v_pai.pedido_id <> p_pedido_id or v_pai.tipo <> 'simples_faturamento'
         or v_pai.status_atual <> 'emitida' or v_pai.origem_registro <> 'externa' then
        raise exception 'parent must be an active external simple billing reference for the same order';
      end if;
    elsif p_referencia_pai_id is not null then
      raise exception 'single shipping reference cannot have parent';
    end if;
  end if;

  v_context := public.begin_audited_rpc(
    'faturamento.external_references.register', 'faturamento', 'fat_notas_fiscais',
    'fiscal_event', jsonb_build_object('event', 'external_reference_registered', 'tipo', v_tipo)
  );

  insert into public.fat_notas_fiscais(
    pedido_id, romaneio_id, nota_pai_id, chave_nfe, numero, serie,
    data_emissao, valor_nf, tipo, status_atual, observacao,
    origem_registro, created_by, updated_by
  ) values (
    p_pedido_id, p_romaneio_id, p_referencia_pai_id, null, v_numero, v_serie,
    p_data_documento, 0, v_tipo, 'emitida', btrim(p_motivo),
    'externa', v_actor, v_actor
  ) returning id into v_nota_id;

  if v_tipo = 'simples_faturamento' then
    insert into public.fat_nota_fiscal_itens(
      nota_fiscal_id, pedido_id, pedido_item_id, produto_embalagem_id,
      quantidade, valor_item
    )
    select v_nota_id, item.pedido_id, item.id, item.produto_embalagem_id,
           item.quantidade, item.valor_total
      from public.com_pedido_itens item
     where item.pedido_id = p_pedido_id and item.status = 'active';
  else
    insert into public.fat_nota_fiscal_itens(
      nota_fiscal_id, pedido_id, pedido_item_id, romaneio_id, romaneio_item_id,
      produto_embalagem_id, quantidade, valor_item
    )
    select v_nota_id, item.pedido_id, item.pedido_item_id, item.romaneio_id, item.id,
           item.produto_embalagem_id, item.quantidade_romaneada,
           round(item.quantidade_romaneada * pedido_item.valor_unitario
             * (1 - pedido_item.percentual_desconto / 100), 2)
      from public.exp_romaneio_itens item
      join public.com_pedido_itens pedido_item on pedido_item.id = item.pedido_item_id
     where item.romaneio_id = p_romaneio_id and item.status in ('draft', 'reservado');
  end if;

  if not exists (select 1 from public.fat_nota_fiscal_itens item where item.nota_fiscal_id = v_nota_id) then
    raise exception 'external fiscal reference has no operational items';
  end if;

  select sum(item.valor_item) into v_valor
    from public.fat_nota_fiscal_itens item where item.nota_fiscal_id = v_nota_id;
  update public.fat_notas_fiscais set valor_nf = coalesce(v_valor, 0) where id = v_nota_id;

  insert into public.fat_nota_fiscal_eventos(
    nota_fiscal_id, tipo_evento, motivo, payload_json, created_by
  ) values (
    v_nota_id, 'referencia_externa_registrada', btrim(p_motivo),
    jsonb_build_object(
      'numero', v_numero, 'serie', v_serie, 'tipo', v_tipo,
      'origem', 'sistema_fiscal_externo', 'movimenta_estoque', false,
      'libera_comissao', false
    ), v_actor
  ) returning id into v_evento_id;

  insert into public.fat_referencia_externa_requisicoes(
    idempotency_key, operacao, nota_fiscal_id, evento_id, actor_id, payload_hash
  ) values (p_idempotency_key, 'registrar', v_nota_id, v_evento_id, v_actor, v_payload_hash);

  perform public.log_audited_rpc_change(
    'faturamento', 'fat_notas_fiscais', v_nota_id::text,
    'faturamento.external_reference_registered',
    'faturamento.external_references.register', v_context, null,
    public.fat_nota_fiscal_audit_snapshot(v_nota_id),
    jsonb_build_object(
      'pedido_id', p_pedido_id, 'romaneio_id', p_romaneio_id,
      'tipo', v_tipo, 'numero', v_numero, 'idempotency_key', p_idempotency_key,
      'external_only', true, 'stock_unchanged', true, 'commission_unchanged', true
    )
  );
  return v_nota_id;
end;
$$;

create or replace function public.corrigir_fat_referencia_externa_numero_idempotente(
  p_idempotency_key uuid,
  p_nota_fiscal_id bigint,
  p_numero_novo text,
  p_serie_nova text,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_numero text := nullif(btrim(coalesce(p_numero_novo, '')), '');
  v_serie text := nullif(btrim(coalesce(p_serie_nova, '')), '');
  v_payload_hash text;
  v_existing public.fat_referencia_externa_requisicoes%rowtype;
  v_before public.fat_notas_fiscais%rowtype;
  v_evento_id bigint;
  v_context jsonb;
begin
  perform public.require_current_user_permission('faturamento.external_references.correct');
  if p_idempotency_key is null then raise exception 'idempotency_key is required'; end if;
  if p_nota_fiscal_id is null or p_nota_fiscal_id <= 0 then raise exception 'external reference is required'; end if;
  if v_numero is null then raise exception 'new external reference number is required'; end if;
  if char_length(btrim(coalesce(p_motivo, ''))) < 10 then raise exception 'correction reason must have at least 10 characters'; end if;
  v_actor := public.current_actor_id();
  v_payload_hash := md5(jsonb_build_object(
    'nota_fiscal_id', p_nota_fiscal_id, 'numero_novo', v_numero,
    'serie_nova', v_serie, 'motivo', btrim(p_motivo)
  )::text);
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing from public.fat_referencia_externa_requisicoes request
   where request.idempotency_key = p_idempotency_key;
  if found then
    if v_existing.operacao <> 'corrigir_numero'
       or v_existing.actor_id is distinct from v_actor
       or v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'idempotency key reused with different external fiscal correction request';
    end if;
    return v_existing.evento_id;
  end if;

  select * into v_before from public.fat_notas_fiscais nf
   where nf.id = p_nota_fiscal_id and nf.origem_registro = 'externa' for update;
  if not found then raise exception 'external fiscal reference not found'; end if;
  if v_before.status_atual <> 'emitida' then raise exception 'external fiscal reference status does not allow correction'; end if;
  if v_before.numero = v_numero and v_before.serie is not distinct from v_serie then
    raise exception 'external fiscal reference number did not change';
  end if;

  v_context := public.begin_audited_rpc(
    'faturamento.external_references.correct', 'faturamento', 'fat_notas_fiscais',
    'fiscal_event', jsonb_build_object('event', 'external_reference_number_corrected')
  );
  update public.fat_notas_fiscais
     set numero = v_numero, serie = v_serie, updated_by = v_actor, updated_at = now()
   where id = p_nota_fiscal_id;
  insert into public.fat_nota_fiscal_eventos(
    nota_fiscal_id, tipo_evento, motivo, payload_json, created_by
  ) values (
    p_nota_fiscal_id, 'numero_referencia_corrigido', btrim(p_motivo),
    jsonb_build_object(
      'numero_anterior', v_before.numero, 'serie_anterior', v_before.serie,
      'numero_novo', v_numero, 'serie_nova', v_serie
    ), v_actor
  ) returning id into v_evento_id;
  insert into public.fat_referencia_externa_requisicoes(
    idempotency_key, operacao, nota_fiscal_id, evento_id, actor_id, payload_hash
  ) values (p_idempotency_key, 'corrigir_numero', p_nota_fiscal_id, v_evento_id, v_actor, v_payload_hash);
  perform public.log_audited_rpc_change(
    'faturamento', 'fat_notas_fiscais', p_nota_fiscal_id::text,
    'faturamento.external_reference_number_corrected',
    'faturamento.external_references.correct', v_context, to_jsonb(v_before),
    (select to_jsonb(nf) from public.fat_notas_fiscais nf where nf.id = p_nota_fiscal_id),
    jsonb_build_object('motivo', btrim(p_motivo), 'idempotency_key', p_idempotency_key)
  );
  return v_evento_id;
end;
$$;

revoke all on function public.registrar_fat_referencia_externa_idempotente(
  uuid, bigint, text, text, text, date, bigint, bigint, text
) from public, anon;
grant execute on function public.registrar_fat_referencia_externa_idempotente(
  uuid, bigint, text, text, text, date, bigint, bigint, text
) to authenticated;
revoke all on function public.corrigir_fat_referencia_externa_numero_idempotente(
  uuid, bigint, text, text, text
) from public, anon;
grant execute on function public.corrigir_fat_referencia_externa_numero_idempotente(
  uuid, bigint, text, text, text
) to authenticated;

-- The previous RPC only persisted fiscal data, but its public name and action
-- represented issuance. Keep it internal for historical compatibility and
-- expose only the external-reference contract in this phase.
revoke execute on function public.emitir_fat_nota_fiscal_idempotente(
  uuid, bigint, text, jsonb, text, text, text, date, numeric,
  bigint, bigint, bigint, jsonb, text
) from authenticated;
revoke execute on function public.registrar_fat_nota_fiscal_evento(
  bigint, text, text, jsonb
) from authenticated;

comment on column public.fat_notas_fiscais.origem_registro is
  'EXTERNA identifica documento emitido fora do Elite. Nulo preserva registros anteriores sem inferencia.';
comment on function public.registrar_fat_referencia_externa_idempotente(
  uuid, bigint, text, text, text, date, bigint, bigint, text
) is 'Registra somente numero e itens de documento fiscal externo. Nao emite NF, nao baixa estoque e nao libera comissao.';
comment on function public.corrigir_fat_referencia_externa_numero_idempotente(
  uuid, bigint, text, text, text
) is 'Corrige numero externo com motivo, valores anterior/novo e auditoria append-only.';

-- The first governed entry must be reachable before a material has any lot.
-- Keep PA/PI focused on positive availability, but include active MP catalog
-- rows with a zero-lot count so the operator can create their initial layer.
create or replace function public.consultar_est_estoque_produtos(
  p_busca text,
  p_familia text default 'all',
  p_limite integer default 30
)
returns table (
  familia text,
  produto_id bigint,
  codigo text,
  nome text,
  apresentacoes bigint,
  lotes_disponiveis bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with itens as (
    select
      'MP'::text as familia,
      materia.id as produto_id,
      materia.sku_corrigido as codigo,
      materia.nome,
      1::bigint as apresentacoes,
      count(saldo.lote_mp_id) filter (where saldo.saldo_disponivel > 0)::bigint as lotes_disponiveis
    from public.cad_materias_primas materia
    left join public.est_lotes_mp_saldos saldo
      on saldo.materia_prima_id = materia.id
    where public.can_current_user('estoque.mp.view')
      and materia.status = 'active'
    group by materia.id, materia.sku_corrigido, materia.nome

    union all

    select
      'PI',
      produto.id,
      produto.codigo_produto,
      produto.nome,
      1::bigint,
      count(*)::bigint
    from public.est_lotes_pi_saldos saldo
    join public.cad_produtos_base produto
      on produto.id = saldo.produto_id
    where public.can_current_user('estoque.pi.view')
      and saldo.saldo_disponivel > 0
    group by produto.id, produto.codigo_produto, produto.nome

    union all

    select
      'PA',
      produto.id,
      produto.codigo_produto,
      produto.nome,
      count(distinct apresentacao.id)::bigint,
      count(*)::bigint
    from public.est_lotes_pa_saldos saldo
    join public.cad_produto_embalagens apresentacao
      on apresentacao.id = saldo.produto_embalagem_id
    join public.cad_produtos_base produto
      on produto.id = apresentacao.produto_id
    where public.can_current_user('estoque.pa.view')
      and saldo.saldo_disponivel > 0
    group by produto.id, produto.codigo_produto, produto.nome
  )
  select
    item.familia,
    item.produto_id,
    item.codigo,
    item.nome,
    item.apresentacoes,
    item.lotes_disponiveis
  from itens item
  where nullif(btrim(p_busca), '') is not null
    and (p_familia = 'all' or item.familia = p_familia)
    and lower(concat_ws(' ', item.codigo, item.nome))
      like '%' || lower(btrim(p_busca)) || '%'
  order by item.nome, item.familia
  limit least(greatest(coalesce(p_limite, 30), 1), 100)
$$;

comment on function public.consultar_est_estoque_produtos(text, text, integer) is
  'Pesquisa alvos do estoque. Materias-primas ativas aparecem antes da primeira entrada; PA e PI exigem saldo disponivel.';

create or replace function public.consultar_est_estoque_lotes_alvo(
  p_familia text,
  p_alvo_id bigint,
  p_limite integer default 24,
  p_offset integer default 0
)
returns table (
  lote_id bigint,
  familia text,
  alvo_id bigint,
  alvo_label text,
  codigo_lote text,
  status text,
  saldo_fisico numeric,
  quantidade_reservada numeric,
  saldo_disponivel numeric,
  data_validade date,
  origem_ref text,
  created_at timestamptz,
  updated_at timestamptz,
  total_count bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_familia not in ('MP', 'PA', 'PI') or p_alvo_id is null then
    raise exception 'invalid stock target';
  end if;
  if not public.can_current_user('estoque.' || lower(p_familia) || '.view') then
    raise exception 'not allowed: estoque.view';
  end if;

  return query
  with lotes(
    lote_id,
    familia,
    alvo_id,
    alvo_label,
    codigo_lote,
    status,
    saldo_fisico,
    quantidade_reservada,
    saldo_disponivel,
    data_validade,
    origem_ref,
    created_at,
    updated_at
  ) as (
    select
      saldo.lote_mp_id,
      'MP'::text,
      saldo.materia_prima_id,
      concat_ws(' - ', materia.sku_corrigido, materia.nome),
      saldo.codigo_lote,
      saldo.status,
      saldo.saldo_fisico,
      saldo.quantidade_reservada,
      saldo.saldo_disponivel,
      saldo.data_validade,
      saldo.origem_ref,
      saldo.created_at,
      saldo.updated_at
    from public.est_lotes_mp_saldos saldo
    join public.cad_materias_primas materia
      on materia.id = saldo.materia_prima_id
    where p_familia = 'MP'
      and saldo.materia_prima_id = p_alvo_id
      and saldo.saldo_disponivel > 0

    union all

    select
      saldo.lote_pa_id,
      'PA',
      saldo.produto_embalagem_id,
      concat_ws(' - ', apresentacao.codigo_item, produto.nome, embalagem.descricao),
      saldo.codigo_lote,
      saldo.status,
      saldo.saldo_fisico,
      saldo.quantidade_reservada,
      saldo.saldo_disponivel,
      saldo.data_validade,
      saldo.origem_ref,
      saldo.created_at,
      saldo.updated_at
    from public.est_lotes_pa_saldos saldo
    join public.cad_produto_embalagens apresentacao
      on apresentacao.id = saldo.produto_embalagem_id
    join public.cad_produtos_base produto
      on produto.id = apresentacao.produto_id
    join public.cad_embalagens embalagem
      on embalagem.id = apresentacao.embalagem_id
    where p_familia = 'PA'
      and saldo.produto_embalagem_id = p_alvo_id
      and saldo.saldo_disponivel > 0

    union all

    select
      saldo.lote_pi_id,
      'PI',
      saldo.produto_id,
      concat_ws(' - ', produto.codigo_produto, produto.nome),
      saldo.codigo_lote,
      saldo.status,
      saldo.saldo_fisico,
      saldo.quantidade_reservada,
      saldo.saldo_disponivel,
      saldo.data_validade,
      saldo.origem_ref,
      saldo.created_at,
      saldo.updated_at
    from public.est_lotes_pi_saldos saldo
    join public.cad_produtos_base produto
      on produto.id = saldo.produto_id
    where p_familia = 'PI'
      and saldo.produto_id = p_alvo_id
      and saldo.saldo_disponivel > 0
  )
  select
    lotes.lote_id,
    lotes.familia,
    lotes.alvo_id,
    lotes.alvo_label,
    lotes.codigo_lote,
    lotes.status,
    lotes.saldo_fisico,
    lotes.quantidade_reservada,
    lotes.saldo_disponivel,
    lotes.data_validade,
    lotes.origem_ref,
    lotes.created_at,
    lotes.updated_at,
    count(*) over ()
  from lotes
  order by lotes.updated_at desc
  limit least(greatest(coalesce(p_limite, 24), 1), 100)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

comment on function public.consultar_est_estoque_lotes_alvo(text, bigint, integer, integer) is
  'Lista saldos positivos do alvo sem ambiguidade entre colunas e parametros de retorno.';
