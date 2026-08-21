-- ORD-01 F2B: seller commercial preview and immutable confirmation.

insert into public.permission_actions(
  action_key, module, description, default_allowed, sort_order,
  runtime_module_key, runtime_access_kind
)
values
  ('pedidos.commercial_review.preview', 'pedidos', 'Previsualizar revisao comercial de venda', false, 137, 'pedidos', 'read'),
  ('pedidos.commercial_review.confirm', 'pedidos', 'Confirmar revisao comercial de venda', false, 138, 'pedidos', 'write')
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

create table public.com_pedido_confirmacoes_comerciais (
  id bigint generated always as identity primary key,
  pedido_id bigint not null references public.com_pedidos(id) on delete restrict,
  numero_versao integer not null check (numero_versao > 0),
  versao_anterior_id bigint references public.com_pedido_confirmacoes_comerciais(id) on delete restrict,
  possui_desconto boolean not null,
  justificativa_comercial text,
  descontos_confirmados boolean not null default false,
  comparacao_sha256 text not null check (comparacao_sha256 ~ '^[0-9a-f]{64}$'),
  preview_hash text not null check (preview_hash ~ '^[0-9a-f]{64}$'),
  documento_canonico_json jsonb not null,
  documento_canonico_sha256 text not null check (documento_canonico_sha256 ~ '^[0-9a-f]{64}$'),
  confirmed_by uuid not null references public.user_profiles(id) on delete restrict,
  confirmed_at timestamptz not null,
  constraint com_pedido_confirmacoes_comerciais_versao_key unique (pedido_id, numero_versao),
  constraint com_pedido_confirmacoes_comerciais_anterior_key unique (versao_anterior_id),
  constraint com_pedido_confirmacoes_comerciais_desconto_check check (
    (possui_desconto and descontos_confirmados and length(btrim(coalesce(justificativa_comercial, ''))) >= 10)
    or (not possui_desconto and not descontos_confirmados and justificativa_comercial is null)
  ),
  constraint com_pedido_confirmacoes_comerciais_documento_check check (
    jsonb_typeof(documento_canonico_json) = 'object'
  )
);

create index idx_com_pedido_confirmacoes_comerciais_pedido
  on public.com_pedido_confirmacoes_comerciais(pedido_id, numero_versao desc);

create table public.com_pedido_confirmacao_comercial_requisicoes (
  idempotency_key uuid primary key,
  pedido_id bigint not null references public.com_pedidos(id) on delete restrict,
  confirmacao_comercial_id bigint not null references public.com_pedido_confirmacoes_comerciais(id) on delete restrict,
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default clock_timestamp()
);

alter table public.com_pedido_credito_decisoes
  add column if not exists confirmacao_comercial_id bigint
    references public.com_pedido_confirmacoes_comerciais(id) on delete restrict,
  add column if not exists documento_comercial_sha256 text;

alter table public.com_pedido_credito_decisoes
  add constraint com_pedido_credito_documento_sha256_check
  check (documento_comercial_sha256 is null or documento_comercial_sha256 ~ '^[0-9a-f]{64}$'),
  add constraint com_pedido_credito_confirmacao_documento_check
  check ((confirmacao_comercial_id is null) = (documento_comercial_sha256 is null));

create trigger trg_com_pedido_confirmacoes_comerciais_append_only
before update or delete on public.com_pedido_confirmacoes_comerciais
for each row execute function public.prevent_dec009_fact_changes();
create trigger trg_com_pedido_confirmacoes_comerciais_no_truncate
before truncate on public.com_pedido_confirmacoes_comerciais
for each statement execute function public.prevent_dec009_fact_changes();
create trigger trg_com_pedido_confirmacao_requisicoes_append_only
before update or delete on public.com_pedido_confirmacao_comercial_requisicoes
for each row execute function public.prevent_dec009_fact_changes();
create trigger trg_com_pedido_confirmacao_requisicoes_no_truncate
before truncate on public.com_pedido_confirmacao_comercial_requisicoes
for each statement execute function public.prevent_dec009_fact_changes();

alter table public.com_pedido_confirmacoes_comerciais enable row level security;
alter table public.com_pedido_confirmacao_comercial_requisicoes enable row level security;
revoke all on public.com_pedido_confirmacoes_comerciais from public, anon, authenticated;
revoke all on public.com_pedido_confirmacao_comercial_requisicoes from public, anon, authenticated;

create or replace function public.com_revisao_comercial_venda_calcular(p_proposta jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_vendedor_id bigint;
  v_vinculo public.cad_cliente_vendedores%rowtype;
  v_data_pedido date;
  v_origem_id bigint;
  v_area_id bigint;
  v_uf text;
  v_participantes bigint[] := '{}'::bigint[];
  v_parcela jsonb;
  v_parcelas jsonb := '[]'::jsonb;
  v_numeros integer[] := '{}'::integer[];
  v_numero integer;
  v_forma text;
  v_vencimento date;
  v_valor_parcela bigint;
  v_total_parcelas bigint := 0;
  v_peso_pmp numeric := 0;
  v_pmp numeric(18,6);
  v_item jsonb;
  v_itens jsonb := '[]'::jsonb;
  v_item_index integer := 0;
  v_apresentacao_id bigint;
  v_quantidade numeric;
  v_preco_praticado bigint;
  v_referencia record;
  v_quantidade_comercial numeric;
  v_diferenca bigint;
  v_percentual numeric(18,6);
  v_valor_referencia bigint;
  v_valor_praticado bigint;
  v_impacto bigint;
  v_classificacao text;
  v_complete boolean := true;
  v_total_referencia bigint := 0;
  v_total_praticado bigint := 0;
  v_descontos bigint := 0;
  v_overprice bigint := 0;
  v_resultado bigint := 0;
  v_entrega jsonb;
  v_entregas jsonb := '[]'::jsonb;
  v_entrega_index integer := 0;
  v_data_entrega date;
  v_propriedade_id bigint;
  v_estabelecimento_id bigint;
  v_endereco_id bigint;
  v_alocacao jsonb;
  v_alocacoes jsonb;
  v_alocacao_index integer;
  v_alocacao_quantidade numeric;
  v_soma_alocada numeric;
  v_documento jsonb;
  v_hash text;
  v_produto_nome text;
  v_apresentacao_codigo text;
  v_embalagem_nome text;
begin
  if jsonb_typeof(p_proposta) <> 'object' then raise exception 'proposta comercial deve ser um objeto'; end if;
  if coalesce(p_proposta->>'cliente_vendedor_vinculo_id', '') !~ '^[1-9][0-9]*$' then
    raise exception 'cliente da carteira e obrigatorio';
  end if;
  if coalesce(p_proposta->>'data_pedido', '') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
    raise exception 'data do pedido invalida';
  end if;
  if coalesce(p_proposta->>'origem_comercial_id', '') !~ '^[1-9][0-9]*$' then
    raise exception 'origem comercial e obrigatoria';
  end if;
  begin
    v_data_pedido := (p_proposta->>'data_pedido')::date;
    v_origem_id := (p_proposta->>'origem_comercial_id')::bigint;
    v_area_id := nullif(p_proposta->>'area_comercial_id', '')::bigint;
  exception when others then
    raise exception 'contexto comercial invalido';
  end;
  v_uf := nullif(upper(btrim(p_proposta->>'uf')), '');
  if jsonb_typeof(coalesce(p_proposta->'pessoa_papel_ids', '[]'::jsonb)) <> 'array' then
    raise exception 'participantes comerciais devem ser uma lista';
  end if;
  begin
    select coalesce(array_agg(distinct value::bigint order by value::bigint), '{}'::bigint[])
      into v_participantes
      from jsonb_array_elements_text(coalesce(p_proposta->'pessoa_papel_ids', '[]'::jsonb));
  exception when others then
    raise exception 'participante comercial invalido';
  end;
  if cardinality(v_participantes) <> jsonb_array_length(coalesce(p_proposta->'pessoa_papel_ids', '[]'::jsonb)) then
    raise exception 'participante comercial informado mais de uma vez';
  end if;

  v_vendedor_id := public.current_commercial_person_id();
  if v_vendedor_id is null then raise exception 'identidade comercial nao vinculada a conta atual'; end if;
  select * into v_vinculo
    from public.cad_cliente_vendedores relation
   where relation.id = (p_proposta->>'cliente_vendedor_vinculo_id')::bigint;
  if not found or v_vinculo.pessoa_id <> v_vendedor_id or v_vinculo.status <> 'active' then
    raise exception 'cliente fora da carteira do vendedor';
  end if;
  if (v_vinculo.vigencia_inicio is not null and v_vinculo.vigencia_inicio > v_data_pedido)
     or (v_vinculo.vigencia_fim is not null and v_vinculo.vigencia_fim < v_data_pedido) then
    raise exception 'vinculo entre cliente e vendedor fora da vigencia';
  end if;

  if jsonb_typeof(p_proposta->'parcelas') <> 'array' or jsonb_array_length(p_proposta->'parcelas') = 0 then
    raise exception 'condicao financeira exige ao menos uma parcela';
  end if;
  for v_parcela in select value from jsonb_array_elements(p_proposta->'parcelas')
  loop
    if jsonb_typeof(v_parcela) <> 'object' then raise exception 'cada parcela deve ser um objeto'; end if;
    begin
      v_numero := (v_parcela->>'numero_parcela')::integer;
      v_valor_parcela := (v_parcela->>'valor_centavos')::bigint;
      v_vencimento := (v_parcela->>'data_vencimento')::date;
    exception when others then
      raise exception 'parcela possui numero, valor ou vencimento invalido';
    end;
    v_forma := lower(btrim(coalesce(v_parcela->>'forma_pagamento', '')));
    if v_numero < 1 or v_numero > 999 or v_numero = any(v_numeros) then raise exception 'numero da parcela invalido ou repetido'; end if;
    if v_forma not in ('boleto', 'pix', 'ted', 'cessao_credito') then raise exception 'forma de pagamento invalida'; end if;
    if v_valor_parcela <= 0 then raise exception 'valor da parcela deve ser maior que zero'; end if;
    if v_vencimento < v_data_pedido then raise exception 'vencimento nao pode ser anterior a data do pedido'; end if;
    v_numeros := array_append(v_numeros, v_numero);
    v_total_parcelas := v_total_parcelas + v_valor_parcela;
    v_peso_pmp := v_peso_pmp + v_valor_parcela::numeric * (v_vencimento - v_data_pedido)::numeric;
    v_parcelas := v_parcelas || jsonb_build_array(jsonb_build_object(
      'numero_parcela', v_numero,
      'forma_pagamento', v_forma,
      'valor_centavos', v_valor_parcela,
      'data_vencimento', v_vencimento,
      'dias_prazo', v_vencimento - v_data_pedido
    ));
  end loop;
  select coalesce(jsonb_agg(value order by (value->>'numero_parcela')::integer), '[]'::jsonb)
    into v_parcelas from jsonb_array_elements(v_parcelas);
  v_pmp := round(v_peso_pmp / v_total_parcelas::numeric, 6);

  if jsonb_typeof(p_proposta->'itens') <> 'array' or jsonb_array_length(p_proposta->'itens') = 0
     or jsonb_array_length(p_proposta->'itens') > 100 then
    raise exception 'pedido deve conter entre 1 e 100 itens';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_proposta->'itens') entry
    group by entry->>'produto_embalagem_id' having count(*) > 1
  ) then raise exception 'apresentacao repetida no pedido'; end if;

  for v_item in select value from jsonb_array_elements(p_proposta->'itens')
  loop
    v_item_index := v_item_index + 1;
    begin
      v_apresentacao_id := (v_item->>'produto_embalagem_id')::bigint;
      v_quantidade := (v_item->>'quantidade')::numeric;
    exception when others then
      raise exception 'item % possui apresentacao ou quantidade invalida', v_item_index;
    end;
    if v_apresentacao_id <= 0 or v_quantidade <= 0 then raise exception 'item % deve possuir apresentacao e quantidade positiva', v_item_index; end if;
    select product.nome, presentation.codigo_item, packaging.descricao
      into v_produto_nome, v_apresentacao_codigo, v_embalagem_nome
      from public.cad_produto_embalagens presentation
      join public.cad_produtos_base product on product.id = presentation.produto_id
      join public.cad_embalagens packaging on packaging.id = presentation.embalagem_id
     where presentation.id = v_apresentacao_id and presentation.status = 'active';
    if not found then raise exception 'apresentacao ativa nao encontrada no item %', v_item_index; end if;

    select * into v_referencia from public.resolver_com_referencia_comercial_unidade(
      v_data_pedido, v_pmp, v_origem_id, v_area_id, v_uf,
      v_vinculo.cliente_id, v_participantes, v_apresentacao_id
    );
    v_quantidade_comercial := v_quantidade * v_referencia.quantidade_unidade_precificacao_por_apresentacao;
    v_valor_referencia := round(v_quantidade_comercial * v_referencia.preco_referencia_centavos_por_unidade_precificacao::numeric, 0)::bigint;
    v_total_referencia := v_total_referencia + v_valor_referencia;
    v_preco_praticado := null;
    v_diferenca := null;
    v_percentual := null;
    v_valor_praticado := null;
    v_impacto := null;
    v_classificacao := null;
    if nullif(v_item->>'preco_praticado_centavos_por_unidade_precificacao', '') is null then
      v_complete := false;
    else
      if (v_item->>'preco_praticado_centavos_por_unidade_precificacao') !~ '^[1-9][0-9]*$' then
        raise exception 'preco praticado de venda deve ser maior que zero em centavos inteiros';
      end if;
      begin
        v_preco_praticado := (v_item->>'preco_praticado_centavos_por_unidade_precificacao')::bigint;
      exception when others then
        raise exception 'preco praticado fora da faixa permitida';
      end;
      v_diferenca := v_preco_praticado - v_referencia.preco_referencia_centavos_por_unidade_precificacao;
      v_percentual := round(v_diferenca::numeric * 100 / v_referencia.preco_referencia_centavos_por_unidade_precificacao::numeric, 6);
      v_valor_praticado := round(v_quantidade_comercial * v_preco_praticado::numeric, 0)::bigint;
      if v_valor_praticado <= 0 then raise exception 'quantidade comercial nao produz valor economico positivo em centavos'; end if;
      v_impacto := v_valor_praticado - v_valor_referencia;
      v_classificacao := case when v_diferenca < 0 then 'BELOW_REFERENCE' when v_diferenca = 0 then 'AT_REFERENCE' else 'ABOVE_REFERENCE' end;
      v_total_praticado := v_total_praticado + v_valor_praticado;
      v_resultado := v_resultado + v_impacto;
      if v_impacto < 0 then v_descontos := v_descontos + abs(v_impacto); end if;
      if v_impacto > 0 then v_overprice := v_overprice + v_impacto; end if;
    end if;
    v_itens := v_itens || jsonb_build_array(jsonb_build_object(
      'item_index', v_item_index,
      'produto_embalagem_id', v_apresentacao_id,
      'produto_nome', v_produto_nome,
      'apresentacao_codigo', v_apresentacao_codigo,
      'embalagem_nome', v_embalagem_nome,
      'quantidade_apresentacoes', v_quantidade,
      'unidade_precificacao_id', v_referencia.unidade_precificacao_id,
      'unidade_precificacao_codigo', (select unidade.codigo from public.cad_unidades_medida unidade where unidade.id = v_referencia.unidade_precificacao_id),
      'unidade_precificacao_simbolo', (select unidade.simbolo from public.cad_unidades_medida unidade where unidade.id = v_referencia.unidade_precificacao_id),
      'quantidade_unidade_precificacao_por_apresentacao', v_referencia.quantidade_unidade_precificacao_por_apresentacao,
      'quantidade_unidade_precificacao', v_quantidade_comercial,
      'preco_referencia_centavos_por_unidade_precificacao', v_referencia.preco_referencia_centavos_por_unidade_precificacao,
      'preco_praticado_centavos_por_unidade_precificacao', v_preco_praticado,
      'diferenca_centavos_por_unidade_precificacao', v_diferenca,
      'percentual_diferenca', v_percentual,
      'valor_referencia_centavos', v_valor_referencia,
      'valor_praticado_centavos', v_valor_praticado,
      'impacto_financeiro_centavos', v_impacto,
      'classificacao', v_classificacao,
      'lista_id', v_referencia.lista_id,
      'lista_versao_id', v_referencia.versao_id,
      'publicacao_id', v_referencia.publicacao_id,
      'regra_id', v_referencia.regra_id,
      'prazo_faixa_dias', v_referencia.prazo_faixa_dias
    ));
  end loop;

  if jsonb_typeof(p_proposta->'entregas') <> 'array' or jsonb_array_length(p_proposta->'entregas') = 0 then
    raise exception 'programacao de entregas e obrigatoria';
  end if;
  for v_entrega in select value from jsonb_array_elements(p_proposta->'entregas')
  loop
    v_entrega_index := v_entrega_index + 1;
    begin
      v_data_entrega := (v_entrega->>'data_prevista')::date;
      v_propriedade_id := nullif(v_entrega->>'propriedade_id', '')::bigint;
      v_estabelecimento_id := nullif(v_entrega->>'estabelecimento_id', '')::bigint;
      v_endereco_id := nullif(v_entrega->>'endereco_id', '')::bigint;
    exception when others then
      raise exception 'entrega % possui data ou local invalido', v_entrega_index;
    end;
    if v_data_entrega < v_data_pedido then raise exception 'data de entrega nao pode anteceder a data do pedido'; end if;
    if num_nonnulls(v_propriedade_id, v_estabelecimento_id, v_endereco_id) <> 1 then raise exception 'cada entrega exige exatamente um local'; end if;
    if v_propriedade_id is not null and not exists (select 1 from public.cad_cliente_propriedades x where x.id = v_propriedade_id and x.cliente_id = v_vinculo.cliente_id and x.status = 'active') then raise exception 'propriedade de entrega invalida'; end if;
    if v_estabelecimento_id is not null and not exists (select 1 from public.cad_cliente_estabelecimentos x where x.id = v_estabelecimento_id and x.cliente_id = v_vinculo.cliente_id and x.status = 'active') then raise exception 'estabelecimento de entrega invalido'; end if;
    if v_endereco_id is not null and not exists (select 1 from public.cad_cliente_enderecos x where x.id = v_endereco_id and x.cliente_id = v_vinculo.cliente_id and x.status = 'active' and x.tipo = 'entrega') then raise exception 'endereco de entrega invalido'; end if;
    if jsonb_typeof(v_entrega->'itens') <> 'array' or jsonb_array_length(v_entrega->'itens') = 0 then raise exception 'entrega exige itens distribuidos'; end if;
    v_alocacoes := '[]'::jsonb;
    for v_alocacao in select value from jsonb_array_elements(v_entrega->'itens')
    loop
      begin
        v_alocacao_index := (v_alocacao->>'item_index')::integer;
        v_alocacao_quantidade := (v_alocacao->>'quantidade')::numeric;
      exception when others then raise exception 'distribuicao de entrega invalida'; end;
      if v_alocacao_index < 1 or v_alocacao_index > v_item_index or v_alocacao_quantidade <= 0 then raise exception 'distribuicao de entrega invalida'; end if;
      if exists (select 1 from jsonb_array_elements(v_alocacoes) x where (x->>'item_index')::integer = v_alocacao_index) then raise exception 'item repetido na mesma entrega'; end if;
      v_alocacoes := v_alocacoes || jsonb_build_array(jsonb_build_object('item_index', v_alocacao_index, 'quantidade', v_alocacao_quantidade));
    end loop;
    v_entregas := v_entregas || jsonb_build_array(jsonb_build_object(
      'sequencia', v_entrega_index, 'data_prevista', v_data_entrega,
      'propriedade_id', v_propriedade_id, 'estabelecimento_id', v_estabelecimento_id,
      'endereco_id', v_endereco_id, 'observacao', nullif(btrim(v_entrega->>'observacao'), ''),
      'itens', v_alocacoes
    ));
  end loop;
  for v_item in select value from jsonb_array_elements(v_itens)
  loop
    select coalesce(sum((allocation->>'quantidade')::numeric), 0) into v_soma_alocada
      from jsonb_array_elements(v_entregas) delivery
      cross join lateral jsonb_array_elements(delivery->'itens') allocation
     where (allocation->>'item_index')::integer = (v_item->>'item_index')::integer;
    if v_soma_alocada is distinct from (v_item->>'quantidade_apresentacoes')::numeric then
      raise exception 'programacao de entregas nao cobre integralmente o item %', v_item->>'item_index';
    end if;
  end loop;

  if v_complete and v_total_parcelas <> v_total_praticado then
    raise exception 'soma das parcelas nao reconcilia com o valor praticado do pedido';
  end if;
  v_documento := jsonb_build_object(
    'schema_version', 1,
    'complete_for_confirmation', v_complete,
    'cliente_vendedor_vinculo_id', v_vinculo.id,
    'cliente_id', v_vinculo.cliente_id,
    'vendedor_id', v_vendedor_id,
    'data_pedido', v_data_pedido,
    'origem_comercial_id', v_origem_id,
    'area_comercial_id', v_area_id,
    'uf', v_uf,
    'pessoa_papel_ids', to_jsonb(v_participantes),
    'pmp_dias', v_pmp,
    'parcelas', v_parcelas,
    'itens', v_itens,
    'entregas', v_entregas,
    'observacao', nullif(btrim(p_proposta->>'observacao'), ''),
    'totais', jsonb_build_object(
      'total_referencia_centavos', v_total_referencia,
      'total_praticado_centavos', case when v_complete then v_total_praticado else null end,
      'descontos_brutos_centavos', case when v_complete then v_descontos else null end,
      'overprice_bruto_centavos', case when v_complete then v_overprice else null end,
      'resultado_liquido_centavos', case when v_complete then v_resultado else null end,
      'percentual_resultado_liquido', case when v_complete and v_total_referencia > 0 then round(v_resultado::numeric * 100 / v_total_referencia::numeric, 6) else null end,
      'total_parcelas_centavos', v_total_parcelas
    )
  );
  v_hash := encode(extensions.digest(convert_to(v_documento::text, 'UTF8'), 'sha256'), 'hex');
  return v_documento || jsonb_build_object('preview_hash', v_hash);
end;
$$;

revoke all on function public.com_revisao_comercial_venda_calcular(jsonb) from public, anon, authenticated;

create or replace function public.prever_com_revisao_comercial_venda(p_proposta jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_permission('pedidos.create.own');
  perform public.require_current_user_permission('pedidos.price_reference.resolve');
  perform public.require_current_user_permission('pedidos.commercial_review.preview');
  return public.com_revisao_comercial_venda_calcular(p_proposta);
end;
$$;

revoke all on function public.prever_com_revisao_comercial_venda(jsonb) from public, anon;
grant execute on function public.prever_com_revisao_comercial_venda(jsonb) to authenticated;

create or replace function public.consultar_com_opcoes_revisao_comercial()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_permission('pedidos.commercial_review.preview');
  return jsonb_build_object(
    'origens', coalesce((
      select jsonb_agg(jsonb_build_object('id', origin.id, 'codigo', origin.codigo, 'nome', origin.nome) order by origin.nome, origin.id)
        from public.com_origens_comerciais origin
    ), '[]'::jsonb),
    'areas', coalesce((
      select jsonb_agg(jsonb_build_object('id', area.id, 'nome', area.nome) order by area.nome, area.id)
        from public.cad_areas_comerciais area
       where area.status = 'active'
    ), '[]'::jsonb),
    'participantes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'pessoa_papel_id', role.id,
        'pessoa_id', person.id,
        'nome', person.nome,
        'papel', role.papel
      ) order by person.nome, role.papel, role.id)
        from public.cad_pessoa_papeis role
        join public.cad_pessoas_comerciais person on person.id = role.pessoa_id
       where role.status = 'active'
         and person.status = 'active'
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.consultar_com_opcoes_revisao_comercial() from public, anon;
grant execute on function public.consultar_com_opcoes_revisao_comercial() to authenticated;

create or replace function public.com_pedido_documento_comercial_canonico(
  p_pedido_id bigint,
  p_numero_versao integer,
  p_confirmado_por uuid,
  p_confirmado_em timestamptz,
  p_justificativa_comercial text,
  p_descontos_confirmados boolean
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with pedido as (
    select order_row.*, client.nome as cliente_nome, seller.nome as vendedor_nome,
           origin.codigo as origem_comercial_codigo, origin.nome as origem_comercial_nome,
           area.nome as area_comercial_nome
      from public.com_pedidos order_row
      join public.cad_clientes client on client.id = order_row.cliente_id
      left join public.cad_pessoas_comerciais seller on seller.id = order_row.vendedor_gerador_id
      left join public.com_origens_comerciais origin on origin.id = order_row.origem_comercial_id
      left join public.cad_areas_comerciais area on area.id = (
        select snapshot.area_comercial_id
          from public.com_pedido_item_referencias_comerciais snapshot
         where snapshot.pedido_id = order_row.id order by snapshot.pedido_item_id limit 1
      )
     where order_row.id = p_pedido_id
  ), plano as (
    select plan.* from public.fin_pedido_planos_pagamento plan
     where plan.pedido_id = p_pedido_id
       and plan.origem_dados = 'sistema'
       and plan.review_status = 'approved'
       and plan.vigencia_inicio <= current_date
       and (plan.vigencia_fim is null or plan.vigencia_fim >= current_date)
       and plan.pmp_dias is not null
     order by plan.versao desc, plan.id desc limit 1
  )
  select jsonb_build_object(
    'schema_version', 1,
    'pedido', jsonb_build_object(
      'pedido_id', pedido.id,
      'codigo', pedido.codigo_pedido,
      'tipo', pedido.tipo_pedido,
      'status_no_congelamento', pedido.status,
      'data_pedido', pedido.data_pedido,
      'cliente_id', pedido.cliente_id,
      'cliente_nome', pedido.cliente_nome,
      'vendedor_id', pedido.vendedor_gerador_id,
      'vendedor_nome', pedido.vendedor_nome,
      'observacao', pedido.observacao
    ),
    'versao_comercial', jsonb_build_object(
      'numero', p_numero_versao,
      'confirmado_por', p_confirmado_por,
      'confirmado_em', p_confirmado_em,
      'justificativa_comercial', p_justificativa_comercial,
      'descontos_confirmados', p_descontos_confirmados
    ),
    'contexto_comercial', jsonb_build_object(
      'origem_comercial_id', pedido.origem_comercial_id,
      'origem_comercial_codigo', pedido.origem_comercial_codigo,
      'origem_comercial_nome', pedido.origem_comercial_nome,
      'area_comercial_id', (select snapshot.area_comercial_id from public.com_pedido_item_referencias_comerciais snapshot where snapshot.pedido_id = p_pedido_id order by snapshot.pedido_item_id limit 1),
      'area_comercial_nome', pedido.area_comercial_nome,
      'uf', (select snapshot.uf from public.com_pedido_item_referencias_comerciais snapshot where snapshot.pedido_id = p_pedido_id order by snapshot.pedido_item_id limit 1),
      'pessoa_papel_ids', coalesce((select to_jsonb(snapshot.pessoa_papel_ids) from public.com_pedido_item_referencias_comerciais snapshot where snapshot.pedido_id = p_pedido_id order by snapshot.pedido_item_id limit 1), '[]'::jsonb)
    ),
    'condicao_financeira', jsonb_build_object(
      'plano_pagamento_id', plano.id,
      'versao', plano.versao,
      'data_base', plano.data_base,
      'valor_total_centavos', plano.valor_total_centavos,
      'pmp_dias', plano.pmp_dias,
      'parcelas', coalesce((
        select jsonb_agg(jsonb_build_object(
          'numero_parcela', installment.numero_parcela,
          'forma_pagamento', installment.forma_pagamento,
          'valor_centavos', installment.valor_centavos,
          'data_vencimento', installment.data_vencimento,
          'dias_prazo', installment.dias_prazo
        ) order by installment.numero_parcela)
        from public.fin_pedido_parcelas installment where installment.plano_pagamento_id = plano.id
      ), '[]'::jsonb)
    ),
    'itens', coalesce((
      select jsonb_agg(jsonb_build_object(
        'pedido_item_id', item.id,
        'produto_embalagem_id', item.produto_embalagem_id,
        'produto_nome', product.nome,
        'apresentacao_codigo', presentation.codigo_item,
        'embalagem_nome', packaging.descricao,
        'quantidade_apresentacoes', fact.quantidade_apresentacoes,
        'unidade_precificacao_id', fact.unidade_precificacao_id,
        'unidade_precificacao_codigo', unit.codigo,
        'unidade_precificacao_simbolo', unit.simbolo,
        'quantidade_unidade_precificacao_por_apresentacao', fact.quantidade_unidade_precificacao_por_apresentacao,
        'quantidade_unidade_precificacao', fact.quantidade_unidade_precificacao,
        'referencia_comercial_id', fact.referencia_comercial_id,
        'preco_referencia_centavos_por_unidade_precificacao', fact.preco_referencia_centavos_por_unidade_precificacao,
        'preco_praticado_centavos_por_unidade_precificacao', fact.preco_praticado_centavos_por_unidade_precificacao,
        'diferenca_centavos_por_unidade_precificacao', fact.diferenca_centavos_por_unidade_precificacao,
        'percentual_diferenca', fact.percentual_diferenca,
        'valor_referencia_centavos', fact.valor_referencia_centavos,
        'valor_praticado_centavos', fact.valor_praticado_centavos,
        'impacto_financeiro_centavos', fact.impacto_financeiro_centavos,
        'classificacao', fact.classificacao
      ) order by item.id)
      from public.com_pedido_itens item
      join public.com_pedido_item_precos_praticados fact on fact.pedido_item_id = item.id
      join public.cad_produto_embalagens presentation on presentation.id = item.produto_embalagem_id
      join public.cad_produtos_base product on product.id = presentation.produto_id
      join public.cad_embalagens packaging on packaging.id = presentation.embalagem_id
      join public.cad_unidades_medida unit on unit.id = fact.unidade_precificacao_id
      where item.pedido_id = p_pedido_id and item.status = 'active'
    ), '[]'::jsonb),
    'entregas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'entrega_id', delivery.id,
        'sequencia', delivery.sequencia,
        'data_prevista', delivery.data_prevista,
        'propriedade_id', delivery.propriedade_id,
        'estabelecimento_id', delivery.estabelecimento_id,
        'endereco_id', delivery.endereco_id,
        'observacao', delivery.observacao,
        'itens', coalesce((
          select jsonb_agg(jsonb_build_object(
            'pedido_item_id', allocation.pedido_item_id,
            'quantidade_prevista', allocation.quantidade_prevista
          ) order by allocation.pedido_item_id)
          from public.com_pedido_entrega_itens allocation where allocation.entrega_id = delivery.id
        ), '[]'::jsonb)
      ) order by delivery.sequencia)
      from public.com_pedido_entregas delivery where delivery.pedido_id = p_pedido_id
    ), '[]'::jsonb),
    'comparacao_comercial', public.com_pedido_comparacao_comercial_documento(p_pedido_id)
  )
  from pedido cross join plano;
$$;

revoke all on function public.com_pedido_documento_comercial_canonico(bigint, integer, uuid, timestamptz, text, boolean)
  from public, anon, authenticated;

create or replace function public.validate_com_pedido_confirmacao_comercial()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pedido public.com_pedidos%rowtype;
  v_comparacao jsonb;
  v_possui_desconto boolean;
begin
  select * into v_pedido from public.com_pedidos where id = new.pedido_id;
  if not found or v_pedido.tipo_pedido <> 'venda' or v_pedido.status <> 'blocked' then
    raise exception 'confirmacao comercial exige pedido de venda bloqueado';
  end if;
  if new.numero_versao = 1 and new.versao_anterior_id is not null then raise exception 'primeira versao comercial nao possui antecessora'; end if;
  if new.numero_versao > 1 then raise exception 'nova versao comercial exige revisao governada futura'; end if;
  v_comparacao := public.com_pedido_comparacao_comercial_documento(new.pedido_id);
  if jsonb_array_length(v_comparacao->'itens') = 0 then raise exception 'confirmacao comercial exige comparacao F2A completa'; end if;
  if exists (
    select 1
      from public.com_pedido_itens item
     where item.pedido_id = new.pedido_id
       and item.status = 'active'
       and not exists (
         select 1
           from public.com_pedido_item_precos_praticados fact
          where fact.pedido_item_id = item.id
       )
  ) then
    raise exception 'confirmacao comercial exige comparacao F2A de todos os itens ativos';
  end if;
  v_possui_desconto := exists (
    select 1 from jsonb_array_elements(v_comparacao->'itens') item where item->>'classificacao' = 'BELOW_REFERENCE'
  );
  if new.possui_desconto is distinct from v_possui_desconto then raise exception 'classificacao de desconto diverge da comparacao F2A'; end if;
  if new.comparacao_sha256 is distinct from encode(extensions.digest(convert_to(v_comparacao::text, 'UTF8'), 'sha256'), 'hex') then
    raise exception 'fingerprint da comparacao F2A divergente';
  end if;
  if new.documento_canonico_sha256 is distinct from encode(extensions.digest(convert_to(new.documento_canonico_json::text, 'UTF8'), 'sha256'), 'hex') then
    raise exception 'hash do documento comercial divergente';
  end if;
  if (new.documento_canonico_json#>>'{pedido,pedido_id}')::bigint is distinct from new.pedido_id
     or (new.documento_canonico_json#>>'{versao_comercial,numero}')::integer is distinct from new.numero_versao then
    raise exception 'documento comercial diverge da identidade da versao';
  end if;
  return new;
end;
$$;

revoke all on function public.validate_com_pedido_confirmacao_comercial() from public, anon, authenticated;
create trigger trg_com_pedido_confirmacoes_comerciais_validate
before insert on public.com_pedido_confirmacoes_comerciais
for each row execute function public.validate_com_pedido_confirmacao_comercial();

create or replace function public.com_revisao_comercial_venda_comparacao_esperada(
  p_pedido_id bigint,
  p_preview jsonb
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with order_items as (
    select item.id, row_number() over (order by item.id) as item_index
      from public.com_pedido_itens item
     where item.pedido_id = p_pedido_id and item.status = 'active'
  ), preview_items as (
    select value, ordinality as item_index
      from jsonb_array_elements(p_preview->'itens') with ordinality
  ), mapped as (
    select order_item.id as pedido_item_id, preview_item.value
      from order_items order_item
      join preview_items preview_item on preview_item.item_index = order_item.item_index
  )
  select jsonb_build_object(
    'schema_version', 1,
    'pedido_id', p_pedido_id,
    'itens', coalesce((
      select jsonb_agg(jsonb_build_object(
        'pedido_item_id', item.pedido_item_id,
        'produto_embalagem_id', (item.value->>'produto_embalagem_id')::bigint,
        'origem_comercial_id', (p_preview->>'origem_comercial_id')::bigint,
        'cliente_id', (p_preview->>'cliente_id')::bigint,
        'area_comercial_id', nullif(p_preview->>'area_comercial_id', '')::bigint,
        'uf', nullif(p_preview->>'uf', ''),
        'pessoa_papel_ids', coalesce(p_preview->'pessoa_papel_ids', '[]'::jsonb),
        'data_comercial', (p_preview->>'data_pedido')::date,
        'pmp_dias', trim_scale((p_preview->>'pmp_dias')::numeric),
        'lista_id', (item.value->>'lista_id')::bigint,
        'lista_versao_id', (item.value->>'lista_versao_id')::bigint,
        'publicacao_id', (item.value->>'publicacao_id')::bigint,
        'regra_id', (item.value->>'regra_id')::bigint,
        'prazo_faixa_dias', (item.value->>'prazo_faixa_dias')::integer,
        'unidade_precificacao_id', (item.value->>'unidade_precificacao_id')::bigint,
        'quantidade_apresentacoes', trim_scale((item.value->>'quantidade_apresentacoes')::numeric),
        'quantidade_unidade_precificacao_por_apresentacao', trim_scale((item.value->>'quantidade_unidade_precificacao_por_apresentacao')::numeric),
        'quantidade_unidade_precificacao', trim_scale((item.value->>'quantidade_unidade_precificacao')::numeric),
        'preco_referencia_centavos_por_unidade_precificacao', (item.value->>'preco_referencia_centavos_por_unidade_precificacao')::bigint,
        'preco_praticado_centavos_por_unidade_precificacao', (item.value->>'preco_praticado_centavos_por_unidade_precificacao')::bigint,
        'diferenca_centavos_por_unidade_precificacao', (item.value->>'diferenca_centavos_por_unidade_precificacao')::bigint,
        'percentual_diferenca', trim_scale((item.value->>'percentual_diferenca')::numeric),
        'valor_referencia_centavos', (item.value->>'valor_referencia_centavos')::bigint,
        'valor_praticado_centavos', (item.value->>'valor_praticado_centavos')::bigint,
        'impacto_financeiro_centavos', (item.value->>'impacto_financeiro_centavos')::bigint,
        'classificacao', item.value->>'classificacao'
      ) order by item.pedido_item_id)
        from mapped item
    ), '[]'::jsonb),
    'totais', jsonb_build_object(
      'total_referencia_centavos', (p_preview#>>'{totais,total_referencia_centavos}')::bigint,
      'total_praticado_centavos', (p_preview#>>'{totais,total_praticado_centavos}')::bigint,
      'descontos_brutos_centavos', (p_preview#>>'{totais,descontos_brutos_centavos}')::bigint,
      'overprice_bruto_centavos', (p_preview#>>'{totais,overprice_bruto_centavos}')::bigint,
      'resultado_liquido_centavos', (p_preview#>>'{totais,resultado_liquido_centavos}')::bigint,
      'percentual_resultado_liquido', trim_scale((p_preview#>>'{totais,percentual_resultado_liquido}')::numeric)
    )
  );
$$;

revoke all on function public.com_revisao_comercial_venda_comparacao_esperada(bigint, jsonb)
  from public, anon, authenticated;

create or replace function public.com_revisao_comercial_venda_comparacao_persistida(p_pedido_id bigint)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with comparison as (
    select public.com_pedido_comparacao_comercial_documento(p_pedido_id) as document
  )
  select jsonb_build_object(
    'schema_version', 1,
    'pedido_id', p_pedido_id,
    'itens', coalesce((
      select jsonb_agg(jsonb_build_object(
        'pedido_item_id', fact.pedido_item_id,
        'produto_embalagem_id', snapshot.produto_embalagem_id,
        'origem_comercial_id', snapshot.origem_comercial_id,
        'cliente_id', snapshot.cliente_id,
        'area_comercial_id', snapshot.area_comercial_id,
        'uf', snapshot.uf,
        'pessoa_papel_ids', to_jsonb(snapshot.pessoa_papel_ids),
        'data_comercial', snapshot.data_comercial,
        'pmp_dias', trim_scale(snapshot.pmp_dias),
        'lista_id', snapshot.lista_id,
        'lista_versao_id', snapshot.lista_versao_id,
        'publicacao_id', snapshot.publicacao_id,
        'regra_id', snapshot.regra_id,
        'prazo_faixa_dias', snapshot.prazo_faixa_dias,
        'unidade_precificacao_id', fact.unidade_precificacao_id,
        'quantidade_apresentacoes', trim_scale(fact.quantidade_apresentacoes),
        'quantidade_unidade_precificacao_por_apresentacao', trim_scale(fact.quantidade_unidade_precificacao_por_apresentacao),
        'quantidade_unidade_precificacao', trim_scale(fact.quantidade_unidade_precificacao),
        'preco_referencia_centavos_por_unidade_precificacao', fact.preco_referencia_centavos_por_unidade_precificacao,
        'preco_praticado_centavos_por_unidade_precificacao', fact.preco_praticado_centavos_por_unidade_precificacao,
        'diferenca_centavos_por_unidade_precificacao', fact.diferenca_centavos_por_unidade_precificacao,
        'percentual_diferenca', trim_scale(fact.percentual_diferenca),
        'valor_referencia_centavos', fact.valor_referencia_centavos,
        'valor_praticado_centavos', fact.valor_praticado_centavos,
        'impacto_financeiro_centavos', fact.impacto_financeiro_centavos,
        'classificacao', fact.classificacao
      ) order by fact.pedido_item_id)
        from public.com_pedido_item_precos_praticados fact
        join public.com_pedido_item_referencias_comerciais snapshot
          on snapshot.id = fact.referencia_comercial_id
       where fact.pedido_id = p_pedido_id
    ), '[]'::jsonb),
    'totais', jsonb_build_object(
      'total_referencia_centavos', ((select document#>>'{totais,total_referencia_centavos}' from comparison))::bigint,
      'total_praticado_centavos', ((select document#>>'{totais,total_praticado_centavos}' from comparison))::bigint,
      'descontos_brutos_centavos', ((select document#>>'{totais,descontos_brutos_centavos}' from comparison))::bigint,
      'overprice_bruto_centavos', ((select document#>>'{totais,overprice_bruto_centavos}' from comparison))::bigint,
      'resultado_liquido_centavos', ((select document#>>'{totais,resultado_liquido_centavos}' from comparison))::bigint,
      'percentual_resultado_liquido', trim_scale(((select document#>>'{totais,percentual_resultado_liquido}' from comparison))::numeric)
    )
  );
$$;

revoke all on function public.com_revisao_comercial_venda_comparacao_persistida(bigint)
  from public, anon, authenticated;

create or replace function public.confirmar_com_revisao_comercial_venda_idempotente(
  p_idempotency_key uuid,
  p_proposta jsonb,
  p_preview_hash text,
  p_justificativa_comercial text,
  p_confirmacao_descontos boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_context jsonb;
  v_actor uuid;
  v_payload_hash text;
  v_existing public.com_pedido_confirmacao_comercial_requisicoes%rowtype;
  v_preview jsonb;
  v_itens_criacao jsonb;
  v_pedido_id bigint;
  v_item_map record;
  v_plano_id bigint;
  v_comparacao jsonb;
  v_comparacao_hash text;
  v_comparacao_esperada jsonb;
  v_comparacao_persistida jsonb;
  v_comparacao_esperada_hash text;
  v_comparacao_persistida_hash text;
  v_possui_desconto boolean;
  v_confirmado_em timestamptz;
  v_documento jsonb;
  v_documento_hash text;
  v_confirmacao_id bigint;
begin
  perform public.require_current_user_permission('pedidos.create.own');
  perform public.require_current_user_permission('pedidos.price_reference.resolve');
  perform public.require_current_user_permission('pedidos.payment_terms.manage');
  perform public.require_current_user_permission('pedidos.commercial_context.manage');
  perform public.require_current_user_permission('pedidos.practiced_price.record');
  v_context := public.begin_audited_rpc(
    'pedidos.commercial_review.confirm', 'pedidos', 'com_pedido_confirmacoes_comerciais',
    'change_type', jsonb_build_object('correlation_id', coalesce(p_idempotency_key::text, 'missing'))
  );
  if p_idempotency_key is null then raise exception 'chave de idempotencia e obrigatoria'; end if;
  if coalesce(p_preview_hash, '') !~ '^[0-9a-f]{64}$' then raise exception 'hash da previsualizacao e obrigatorio'; end if;
  v_actor := public.current_actor_id();
  v_payload_hash := encode(extensions.digest(convert_to(jsonb_build_object(
    'proposta', p_proposta,
    'preview_hash', p_preview_hash,
    'justificativa_comercial', nullif(btrim(p_justificativa_comercial), ''),
    'confirmacao_descontos', coalesce(p_confirmacao_descontos, false)
  )::text, 'UTF8'), 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing from public.com_pedido_confirmacao_comercial_requisicoes
   where idempotency_key = p_idempotency_key;
  if found then
    if v_existing.actor_id is distinct from v_actor or v_existing.payload_hash is distinct from v_payload_hash then
      raise exception 'chave de idempotencia reutilizada com conteudo diferente';
    end if;
    return jsonb_build_object(
      'pedido_id', v_existing.pedido_id,
      'confirmacao_comercial_id', v_existing.confirmacao_comercial_id,
      'idempotent_retry', true
    );
  end if;

  v_preview := public.com_revisao_comercial_venda_calcular(p_proposta);
  if v_preview->>'preview_hash' is distinct from p_preview_hash then raise exception 'previsualizacao comercial desatualizada; calcule novamente'; end if;
  if coalesce((v_preview->>'complete_for_confirmation')::boolean, false) is not true then raise exception 'previsualizacao comercial incompleta'; end if;
  v_possui_desconto := exists (select 1 from jsonb_array_elements(v_preview->'itens') item where item->>'classificacao' = 'BELOW_REFERENCE');
  if v_possui_desconto and length(btrim(coalesce(p_justificativa_comercial, ''))) < 10 then
    raise exception 'pedido com desconto exige justificativa comercial com ao menos 10 caracteres';
  end if;
  if v_possui_desconto and coalesce(p_confirmacao_descontos, false) is not true then
    raise exception 'pedido com desconto exige confirmacao explicita do vendedor';
  end if;
  if not v_possui_desconto and (nullif(btrim(p_justificativa_comercial), '') is not null or coalesce(p_confirmacao_descontos, false)) then
    raise exception 'pedido sem desconto nao aceita solicitacao de desconto';
  end if;

  select jsonb_agg(jsonb_build_object(
    'produto_embalagem_id', item->>'produto_embalagem_id',
    'quantidade', item->>'quantidade_apresentacoes',
    'valor_unitario', ((item->>'valor_praticado_centavos')::numeric / 100) / (item->>'quantidade_apresentacoes')::numeric
  ) order by (item->>'item_index')::integer)
  into v_itens_criacao from jsonb_array_elements(v_preview->'itens') item;

  v_pedido_id := public.create_com_pedido_vendedor_programado_idempotente(
    md5(p_idempotency_key::text || ':order')::uuid,
    (v_preview->>'cliente_vendedor_vinculo_id')::bigint,
    v_itens_criacao,
    v_preview->'entregas',
    (v_preview->>'data_pedido')::date,
    v_preview->>'observacao'
  );
  perform pg_advisory_xact_lock(hashtextextended('order_commercial_confirmation:' || v_pedido_id::text, 0));

  for v_item_map in
    select order_item.id as pedido_item_id, preview_item.value as preview_item
      from (
        select item.id, row_number() over (order by item.id) as item_index
          from public.com_pedido_itens item where item.pedido_id = v_pedido_id and item.status = 'active'
      ) order_item
      join lateral jsonb_array_elements(v_preview->'itens') with ordinality preview_item(value, ordinality)
        on preview_item.ordinality = order_item.item_index
     order by order_item.item_index
  loop
    update public.com_pedido_itens
       set valor_total = (v_item_map.preview_item->>'valor_praticado_centavos')::numeric / 100,
           valor_unitario = ((v_item_map.preview_item->>'valor_praticado_centavos')::numeric / 100)
             / (v_item_map.preview_item->>'quantidade_apresentacoes')::numeric,
           percentual_desconto = 0,
           updated_by = v_actor
     where id = v_item_map.pedido_item_id;
  end loop;
  update public.com_pedidos
     set valor_total = (v_preview#>>'{totais,total_praticado_centavos}')::numeric / 100,
         updated_by = v_actor
   where id = v_pedido_id;

  v_plano_id := public.replace_com_pedido_condicao_financeira_idempotente(
    md5(p_idempotency_key::text || ':payment')::uuid,
    v_pedido_id,
    v_preview->'parcelas',
    'Condicao financeira confirmada na revisao comercial'
  );
  perform public.resolver_com_referencias_comerciais_pedido_idempotente(
    md5(p_idempotency_key::text || ':reference')::uuid,
    v_pedido_id,
    (v_preview->>'origem_comercial_id')::bigint,
    nullif(v_preview->>'area_comercial_id', '')::bigint,
    v_preview->>'uf',
    array(select jsonb_array_elements_text(v_preview->'pessoa_papel_ids')::bigint),
    'Referencias congeladas na confirmacao comercial do vendedor'
  );
  perform public.registrar_com_precos_praticados_pedido_idempotente(
    md5(p_idempotency_key::text || ':practiced')::uuid,
    v_pedido_id,
    (select jsonb_agg(jsonb_build_object(
      'pedido_item_id', order_item.id,
      'preco_praticado_centavos_por_unidade_precificacao', preview_item.value->>'preco_praticado_centavos_por_unidade_precificacao'
    ) order by order_item.id)
      from (select item.id, row_number() over (order by item.id) as item_index from public.com_pedido_itens item where item.pedido_id = v_pedido_id and item.status = 'active') order_item
      join lateral jsonb_array_elements(v_preview->'itens') with ordinality preview_item(value, ordinality)
        on preview_item.ordinality = order_item.item_index),
    'Precos praticados confirmados pelo vendedor'
  );

  v_comparacao_esperada := public.com_revisao_comercial_venda_comparacao_esperada(v_pedido_id, v_preview);
  v_comparacao_persistida := public.com_revisao_comercial_venda_comparacao_persistida(v_pedido_id);
  v_comparacao_esperada_hash := encode(
    extensions.digest(convert_to(v_comparacao_esperada::text, 'UTF8'), 'sha256'), 'hex'
  );
  v_comparacao_persistida_hash := encode(
    extensions.digest(convert_to(v_comparacao_persistida::text, 'UTF8'), 'sha256'), 'hex'
  );
  if v_comparacao_esperada_hash is distinct from v_comparacao_persistida_hash then
    raise exception 'fatos comerciais persistidos divergem da previsualizacao confirmada';
  end if;

  v_comparacao := public.com_pedido_comparacao_comercial_documento(v_pedido_id);
  v_comparacao_hash := encode(extensions.digest(convert_to(v_comparacao::text, 'UTF8'), 'sha256'), 'hex');
  v_confirmado_em := clock_timestamp();
  v_documento := public.com_pedido_documento_comercial_canonico(
    v_pedido_id, 1, v_actor, v_confirmado_em,
    case when v_possui_desconto then btrim(p_justificativa_comercial) else null end,
    case when v_possui_desconto then true else false end
  );
  v_documento_hash := encode(extensions.digest(convert_to(v_documento::text, 'UTF8'), 'sha256'), 'hex');
  insert into public.com_pedido_confirmacoes_comerciais(
    pedido_id, numero_versao, possui_desconto, justificativa_comercial, descontos_confirmados,
    comparacao_sha256, preview_hash, documento_canonico_json, documento_canonico_sha256,
    confirmed_by, confirmed_at
  ) values (
    v_pedido_id, 1, v_possui_desconto,
    case when v_possui_desconto then btrim(p_justificativa_comercial) else null end,
    case when v_possui_desconto then true else false end,
    v_comparacao_hash, p_preview_hash, v_documento, v_documento_hash,
    v_actor, v_confirmado_em
  ) returning id into v_confirmacao_id;

  insert into public.com_pedido_confirmacao_comercial_requisicoes(
    idempotency_key, pedido_id, confirmacao_comercial_id, actor_id, payload_hash
  ) values (p_idempotency_key, v_pedido_id, v_confirmacao_id, v_actor, v_payload_hash);
  perform public.log_audited_rpc_change(
    'pedidos', 'com_pedido_confirmacoes_comerciais', v_confirmacao_id::text,
    'pedidos.revisao_comercial_confirmada', 'pedidos.commercial_review.confirm', v_context,
    null, jsonb_build_object(
      'pedido_id', v_pedido_id,
      'confirmacao_comercial_id', v_confirmacao_id,
      'numero_versao', 1,
      'documento_canonico_sha256', v_documento_hash,
      'possui_desconto', v_possui_desconto,
      'status', 'blocked'
    ),
    jsonb_build_object('plano_pagamento_id', v_plano_id, 'preview_hash', p_preview_hash),
    'database_rpc'
  );
  return jsonb_build_object(
    'pedido_id', v_pedido_id,
    'confirmacao_comercial_id', v_confirmacao_id,
    'numero_versao', 1,
    'documento_canonico_sha256', v_documento_hash,
    'status', 'blocked',
    'idempotent_retry', false
  );
end;
$$;

revoke all on function public.confirmar_com_revisao_comercial_venda_idempotente(uuid, jsonb, text, text, boolean)
  from public, anon;
grant execute on function public.confirmar_com_revisao_comercial_venda_idempotente(uuid, jsonb, text, text, boolean)
  to authenticated;

create or replace function public.consultar_com_confirmacao_comercial_pedido(p_pedido_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_result jsonb;
begin
  perform public.require_current_user_permission('pedidos.commercial_comparison.view');
  if not public.can_current_user_view_order(p_pedido_id) then raise exception 'pedido fora do escopo do usuario'; end if;
  select jsonb_build_object(
    'confirmacao_comercial_id', confirmation.id,
    'pedido_id', confirmation.pedido_id,
    'numero_versao', confirmation.numero_versao,
    'possui_desconto', confirmation.possui_desconto,
    'documento_canonico_sha256', confirmation.documento_canonico_sha256,
    'confirmed_by', confirmation.confirmed_by,
    'confirmed_at', confirmation.confirmed_at,
    'documento', confirmation.documento_canonico_json
  ) into v_result
    from public.com_pedido_confirmacoes_comerciais confirmation
   where confirmation.pedido_id = p_pedido_id
   order by confirmation.numero_versao desc limit 1;
  if v_result is null then raise exception 'pedido nao possui confirmacao comercial'; end if;
  return v_result;
end;
$$;

revoke all on function public.consultar_com_confirmacao_comercial_pedido(bigint) from public, anon;
grant execute on function public.consultar_com_confirmacao_comercial_pedido(bigint) to authenticated;

create or replace function public.registrar_com_pedido_decisao_credito(
  p_pedido_id bigint,
  p_decisao text,
  p_motivo text default null,
  p_limite_disponivel_snapshot numeric default null,
  p_inadimplencia_snapshot numeric default null,
  p_observacao text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_pedido public.com_pedidos%rowtype;
  v_confirmacao public.com_pedido_confirmacoes_comerciais%rowtype;
  v_decisao_id bigint;
  v_context jsonb;
begin
  perform public.require_current_user_permission('pedidos.credit.review');
  select * into v_pedido from public.com_pedidos where id = p_pedido_id for update;
  if not found or v_pedido.vendedor_gerador_id is null then raise exception 'pedido nao encontrado ou sem vendedor'; end if;
  if not public.current_user_manages_seller(v_pedido.vendedor_gerador_id) then raise exception 'pedido fora da equipe do responsavel'; end if;
  if v_pedido.tipo_pedido <> 'venda' or v_pedido.status <> 'blocked' then
    return public.registrar_com_pedido_decisao_credito_impl_0037(
      p_pedido_id, p_decisao, p_motivo, p_limite_disponivel_snapshot,
      p_inadimplencia_snapshot, p_observacao
    );
  end if;
  if p_decisao not in ('liberado', 'bloqueado', 'pendente_aprovacao') then raise exception 'decisao de credito invalida'; end if;
  if p_decisao <> 'liberado' and length(btrim(coalesce(p_motivo, ''))) < 10 then raise exception 'decisao exige motivo com ao menos 10 caracteres'; end if;
  select * into v_confirmacao from public.com_pedido_confirmacoes_comerciais confirmation
   where confirmation.pedido_id = p_pedido_id order by confirmation.numero_versao desc limit 1;
  if p_decisao = 'liberado' and not found then
    raise exception 'venda exige revisao comercial confirmada antes da aprovacao de credito';
  end if;
  v_actor := public.current_actor_id();
  v_context := public.begin_audited_rpc(
    'pedidos.credit.review', 'pedidos', 'com_pedido_credito_decisoes',
    'status_transition', jsonb_build_object('pedido_id', p_pedido_id, 'status_preservado', 'blocked')
  );
  insert into public.com_pedido_credito_decisoes(
    pedido_id, decisao, status_anterior, status_resultante, motivo,
    limite_disponivel_snapshot, inadimplencia_snapshot, observacao, created_by,
    confirmacao_comercial_id, documento_comercial_sha256
  ) values (
    p_pedido_id, p_decisao, 'blocked', 'blocked', nullif(btrim(p_motivo), ''),
    p_limite_disponivel_snapshot, p_inadimplencia_snapshot, nullif(btrim(p_observacao), ''), v_actor,
    case when v_confirmacao.id is null then null else v_confirmacao.id end,
    case when v_confirmacao.id is null then null else v_confirmacao.documento_canonico_sha256 end
  ) returning id into v_decisao_id;
  perform public.log_audited_rpc_change(
    'pedidos', 'com_pedido_credito_decisoes', v_decisao_id::text,
    case when p_decisao = 'liberado' then 'pedidos.credito_aprovado_aguardando_efetivacao' else 'pedidos.credito_decidido' end,
    'pedidos.credit.review', v_context,
    jsonb_build_object('status', 'blocked'),
    jsonb_build_object('status', 'blocked', 'decisao', p_decisao, 'confirmacao_comercial_id', v_confirmacao.id),
    jsonb_build_object('pedido_permanece_bloqueado', true), 'database_rpc'
  );
  return v_decisao_id;
end;
$$;

revoke all on function public.registrar_com_pedido_decisao_credito(bigint, text, text, numeric, numeric, text)
  from public, anon, authenticated;

comment on table public.com_pedido_confirmacoes_comerciais is
  'ORD-01 F2B: ancora imutavel da versao comercial confirmada pelo vendedor. A identidade contratual e id mais SHA-256 do documento canonico.';
comment on function public.prever_com_revisao_comercial_venda(jsonb) is
  'ORD-01 F2B: previsualizacao sem persistencia, calculada no PostgreSQL com contratos 1B, 1D/1E e F2A.';
comment on function public.consultar_com_opcoes_revisao_comercial() is
  'ORD-01 F2B: opcoes humanas do contexto comercial, expostas somente a quem pode previsualizar a revisao.';
comment on function public.confirmar_com_revisao_comercial_venda_idempotente(uuid, jsonb, text, text, boolean) is
  'ORD-01 F2B: cria atomicamente pedido bloqueado e todos os fatos comerciais governados, vinculados a versao imutavel confirmada.';
comment on column public.com_pedido_confirmacoes_comerciais.documento_canonico_sha256 is
  'SHA-256 do documento comercial canonico. Futuras aprovacoes e assinaturas devem referenciar este hash e a confirmacao.';
