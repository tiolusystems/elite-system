-- Operational XLSX workspace for governed price-list analysis and atomic publication.

create table public.com_lista_preco_xlsx_analises (
  id bigint generated always as identity primary key,
  idempotency_key uuid not null unique,
  workbook_id bigint not null unique references public.source_workbooks(id) on delete restrict,
  batch_id bigint not null unique references public.migration_batches(id) on delete restrict,
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{64}$'),
  canonical_payload_sha256 text not null check (canonical_payload_sha256 ~ '^[0-9a-f]{64}$'),
  lista_id bigint references public.com_listas_preco(id) on delete restrict,
  codigo_lista text not null,
  nome_lista text not null,
  nome_lista_canonico text,
  avisos_json jsonb not null default '[]'::jsonb check (jsonb_typeof(avisos_json) = 'array'),
  vigencia_inicio date not null,
  vigencia_fim date,
  uf text,
  origem_comercial_id bigint references public.com_origens_comerciais(id) on delete restrict,
  observacao text,
  status text not null check (status in ('ready', 'blocked')),
  total_linhas integer not null,
  linhas_aprovadas integer not null,
  linhas_aviso integer not null,
  linhas_erro integer not null,
  produtos_count integer not null,
  apresentacoes_count integer not null,
  faixas_count integer not null,
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  constraint com_lista_preco_xlsx_analises_codigo_check check (length(btrim(codigo_lista)) > 0),
  constraint com_lista_preco_xlsx_analises_nome_check check (length(btrim(nome_lista)) > 0),
  constraint com_lista_preco_xlsx_analises_vigencia_check check (vigencia_fim is null or vigencia_fim >= vigencia_inicio),
  constraint com_lista_preco_xlsx_analises_uf_check check (
    uf is null or uf in ('AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA','PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO')
  ),
  constraint com_lista_preco_xlsx_analises_counts_check check (
    total_linhas >= 0 and linhas_aprovadas >= 0 and linhas_aviso >= 0 and linhas_erro >= 0
    and total_linhas = linhas_aprovadas + linhas_aviso + linhas_erro
    and produtos_count >= 0 and apresentacoes_count >= 0 and faixas_count >= 0
  )
);

create table public.com_lista_preco_xlsx_linhas (
  id bigint generated always as identity primary key,
  analise_id bigint not null references public.com_lista_preco_xlsx_analises(id) on delete restrict,
  source_row_id bigint not null references public.source_rows(id) on delete restrict,
  excel_row integer not null check (excel_row > 1),
  codigo_produto text,
  nome_produto_importado text,
  produto_id bigint references public.cad_produtos_base(id) on delete restrict,
  nome_produto_canonico text,
  codigo_apresentacao text,
  nome_apresentacao_importado text,
  produto_embalagem_id bigint references public.cad_produto_embalagens(id) on delete restrict,
  nome_apresentacao_canonico text,
  unidade_precificacao_codigo text,
  unidade_precificacao_id bigint references public.cad_unidades_medida(id) on delete restrict,
  fator_por_apresentacao numeric,
  pmp_min_dias integer,
  pmp_max_dias integer,
  preco_unitario numeric,
  preco_centavos_por_unidade bigint,
  observacao text,
  status text not null,
  avisos_json jsonb not null default '[]'::jsonb check (jsonb_typeof(avisos_json) = 'array'),
  erros_json jsonb not null default '[]'::jsonb check (jsonb_typeof(erros_json) = 'array'),
  celulas_json jsonb not null check (jsonb_typeof(celulas_json) = 'object'),
  created_at timestamptz not null default clock_timestamp(),
  constraint com_lista_preco_xlsx_linhas_key unique (analise_id, excel_row),
  constraint com_lista_preco_xlsx_linhas_numeric_check check (
    (fator_por_apresentacao is null or fator_por_apresentacao > 0)
    and (pmp_min_dias is null or pmp_min_dias >= 0)
    and (pmp_max_dias is null or pmp_max_dias >= 0)
    and (preco_unitario is null or preco_unitario > 0)
    and (preco_centavos_por_unidade is null or preco_centavos_por_unidade > 0)
  ),
  constraint com_lista_preco_xlsx_linhas_status_check check (
    (status = 'ERRO' and jsonb_array_length(erros_json) > 0)
    or (status = 'AVISO' and jsonb_array_length(erros_json) = 0 and jsonb_array_length(avisos_json) > 0)
    or (status = 'APROVADA' and jsonb_array_length(erros_json) = 0 and jsonb_array_length(avisos_json) = 0)
  )
);

create table public.com_lista_preco_xlsx_publicacoes (
  analise_id bigint primary key references public.com_lista_preco_xlsx_analises(id) on delete restrict,
  lista_id bigint not null references public.com_listas_preco(id) on delete restrict,
  versao_id bigint not null unique references public.com_lista_preco_versoes(id) on delete restrict,
  publicacao_id bigint not null unique references public.com_lista_preco_publicacoes(id) on delete restrict,
  workbook_sha256 text not null check (workbook_sha256 ~ '^[0-9a-f]{64}$'),
  canonical_payload_sha256 text not null check (canonical_payload_sha256 ~ '^[0-9a-f]{64}$'),
  published_by uuid not null references public.user_profiles(id) on delete restrict,
  published_at timestamptz not null default clock_timestamp()
);

create table public.com_lista_preco_xlsx_requisicoes (
  idempotency_key uuid primary key,
  tipo text not null check (tipo in ('analisar', 'publicar')),
  analise_id bigint not null references public.com_lista_preco_xlsx_analises(id) on delete restrict,
  publicacao_id bigint references public.com_lista_preco_publicacoes(id) on delete restrict,
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default clock_timestamp(),
  constraint com_lista_preco_xlsx_requisicoes_result_check check (
    (tipo = 'analisar' and publicacao_id is null) or (tipo = 'publicar' and publicacao_id is not null)
  )
);

create index idx_com_lista_preco_xlsx_analises_created on public.com_lista_preco_xlsx_analises(created_at desc, id desc);
create index idx_com_lista_preco_xlsx_linhas_status on public.com_lista_preco_xlsx_linhas(analise_id, status, excel_row);

create or replace function public.prevent_com_lista_preco_xlsx_fact_changes()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_table_name in ('com_lista_preco_xlsx_analises', 'com_lista_preco_xlsx_linhas')
     and tg_op = 'UPDATE'
     and old.xmin::text::bigint = txid_current() then
    return new;
  end if;
  raise exception 'fatos de analise e publicacao XLSX sao append-only';
end;
$$;

create trigger trg_com_lista_preco_xlsx_analises_append_only
before update or delete on public.com_lista_preco_xlsx_analises
for each row execute function public.prevent_com_lista_preco_xlsx_fact_changes();
create trigger trg_com_lista_preco_xlsx_linhas_append_only
before update or delete on public.com_lista_preco_xlsx_linhas
for each row execute function public.prevent_com_lista_preco_xlsx_fact_changes();
create trigger trg_com_lista_preco_xlsx_publicacoes_append_only
before update or delete on public.com_lista_preco_xlsx_publicacoes
for each row execute function public.prevent_com_lista_preco_xlsx_fact_changes();
create trigger trg_com_lista_preco_xlsx_requisicoes_append_only
before update or delete on public.com_lista_preco_xlsx_requisicoes
for each row execute function public.prevent_com_lista_preco_xlsx_fact_changes();
create trigger trg_com_lista_preco_xlsx_analises_no_truncate
before truncate on public.com_lista_preco_xlsx_analises
for each statement execute function public.prevent_com_lista_preco_xlsx_fact_changes();
create trigger trg_com_lista_preco_xlsx_linhas_no_truncate
before truncate on public.com_lista_preco_xlsx_linhas
for each statement execute function public.prevent_com_lista_preco_xlsx_fact_changes();
create trigger trg_com_lista_preco_xlsx_publicacoes_no_truncate
before truncate on public.com_lista_preco_xlsx_publicacoes
for each statement execute function public.prevent_com_lista_preco_xlsx_fact_changes();
create trigger trg_com_lista_preco_xlsx_requisicoes_no_truncate
before truncate on public.com_lista_preco_xlsx_requisicoes
for each statement execute function public.prevent_com_lista_preco_xlsx_fact_changes();

create or replace function public.ord01_price_list_xlsx_source_value(p_value jsonb)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select case jsonb_typeof(p_value)
    when 'number' then jsonb_build_array('number', ((p_value #>> '{}')::numeric)::text)
    when 'string' then jsonb_build_array('string', p_value #>> '{}')
    when 'boolean' then jsonb_build_array('boolean', p_value #>> '{}')
    when 'null' then jsonb_build_array('null', null)
    else jsonb_build_array('null', null)
  end;
$$;

create or replace function public.ord01_price_list_xlsx_row_document(p_line jsonb)
returns text
language sql
immutable
set search_path = public
as $$
  select jsonb_build_array(
    'price-list-row-v1',
    case when jsonb_typeof(p_line->'excel_row') = 'number' then (p_line->>'excel_row')::integer end,
    p_line->>'codigo_produto',
    p_line->>'nome_produto',
    p_line->>'codigo_apresentacao',
    p_line->>'nome_apresentacao',
    p_line->>'unidade_precificacao',
    case when jsonb_typeof(p_line->'fator_por_apresentacao') = 'number' then ((p_line->>'fator_por_apresentacao')::numeric)::text end,
    case when jsonb_typeof(p_line->'pmp_min_dias') = 'number' then (p_line->>'pmp_min_dias')::integer end,
    case when jsonb_typeof(p_line->'pmp_max_dias') = 'number' then (p_line->>'pmp_max_dias')::integer end,
    case when jsonb_typeof(p_line->'preco_unitario') = 'number' then ((p_line->>'preco_unitario')::numeric)::text end,
    p_line->>'observacao',
    jsonb_build_array(
      public.ord01_price_list_xlsx_source_value(p_line->'source_payload'->'A'),
      public.ord01_price_list_xlsx_source_value(p_line->'source_payload'->'B'),
      public.ord01_price_list_xlsx_source_value(p_line->'source_payload'->'C'),
      public.ord01_price_list_xlsx_source_value(p_line->'source_payload'->'D'),
      public.ord01_price_list_xlsx_source_value(p_line->'source_payload'->'E'),
      public.ord01_price_list_xlsx_source_value(p_line->'source_payload'->'F'),
      public.ord01_price_list_xlsx_source_value(p_line->'source_payload'->'G'),
      public.ord01_price_list_xlsx_source_value(p_line->'source_payload'->'H'),
      public.ord01_price_list_xlsx_source_value(p_line->'source_payload'->'I'),
      public.ord01_price_list_xlsx_source_value(p_line->'source_payload'->'J')
    ),
    jsonb_build_array(
      p_line->'formulas'->>'A', p_line->'formulas'->>'B', p_line->'formulas'->>'C', p_line->'formulas'->>'D', p_line->'formulas'->>'E',
      p_line->'formulas'->>'F', p_line->'formulas'->>'G', p_line->'formulas'->>'H', p_line->'formulas'->>'I', p_line->'formulas'->>'J'
    ),
    jsonb_build_array(
      p_line->'celulas'->>'codigo_produto', p_line->'celulas'->>'nome_produto',
      p_line->'celulas'->>'codigo_apresentacao', p_line->'celulas'->>'nome_apresentacao',
      p_line->'celulas'->>'unidade_precificacao', p_line->'celulas'->>'fator_por_apresentacao',
      p_line->'celulas'->>'pmp_min_dias', p_line->'celulas'->>'pmp_max_dias',
      p_line->'celulas'->>'preco_unitario', p_line->'celulas'->>'observacao'
    )
  )::text;
$$;

create or replace function public.ord01_price_list_xlsx_row_sha256(p_line jsonb)
returns text
language sql
immutable
set search_path = public
as $$
  select encode(extensions.digest(convert_to(public.ord01_price_list_xlsx_row_document(p_line), 'UTF8'), 'sha256'), 'hex');
$$;

create or replace function public.analisar_com_lista_preco_xlsx_operacional_idempotente(
  p_idempotency_key uuid,
  p_file_name text,
  p_workbook_sha256 text,
  p_size_bytes bigint,
  p_lista jsonb,
  p_linhas jsonb,
  p_motivo text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_context jsonb; v_actor uuid; v_payload_hash text; v_expected_hash text;
  v_existing_request public.com_lista_preco_xlsx_requisicoes%rowtype;
  v_existing_analysis public.com_lista_preco_xlsx_analises%rowtype;
  v_workbook_id bigint; v_batch_id bigint; v_table_id bigint; v_analysis_id bigint;
  v_lista_id bigint; v_lista_nome_canonico text; v_analysis_warnings jsonb := '[]'::jsonb;
  v_codigo_lista text; v_nome_lista text; v_vigencia_inicio date; v_vigencia_fim date;
  v_uf text; v_canal text; v_origem_id bigint; v_observacao text;
  v_line jsonb; v_payload jsonb; v_formulas jsonb; v_row_id bigint; v_row_hash text; v_recomputed_row_hash text;
  v_excel_row integer; v_codigo_produto text; v_codigo_apresentacao text; v_codigo_unidade text;
  v_nome_produto_importado text; v_nome_apresentacao_importado text;
  v_produto record; v_apresentacao record; v_unidade record;
  v_fator numeric; v_pmp_min integer; v_pmp_max integer; v_preco numeric; v_centavos bigint;
  v_warnings jsonb; v_errors jsonb; v_status text; v_cells jsonb;
  v_approved integer := 0; v_warning_count integer := 0; v_error_count integer := 0;
  v_products integer := 0; v_presentations integer := 0; v_total integer := 0;
begin
  v_context := public.begin_audited_rpc(
    'pedidos.price_lists.import.stage', 'pedidos', 'com_lista_preco_xlsx_analises',
    'field_risk', jsonb_build_object('correlation_id', coalesce(p_idempotency_key::text, 'missing'))
  );
  if p_idempotency_key is null then raise exception 'chave de idempotencia e obrigatoria'; end if;
  if nullif(btrim(p_file_name), '') is null or right(lower(btrim(p_file_name)), 5) <> '.xlsx' then raise exception 'arquivo XLSX valido e obrigatorio'; end if;
  if p_size_bytes is null or p_size_bytes <= 0 or p_size_bytes > 10485760 then raise exception 'arquivo deve possuir no maximo 10 MB'; end if;
  if coalesce(p_workbook_sha256, '') !~ '^[0-9a-f]{64}$' then raise exception 'SHA-256 do arquivo invalido'; end if;
  if jsonb_typeof(p_lista) <> 'object' or jsonb_typeof(p_linhas) <> 'array' or jsonb_array_length(p_linhas) < 1 or jsonb_array_length(p_linhas) > 10000 then raise exception 'estrutura operacional do workbook invalida'; end if;
  if length(btrim(coalesce(p_motivo, ''))) < 10 then raise exception 'motivo deve ter ao menos 10 caracteres'; end if;

  v_expected_hash := encode(extensions.digest(convert_to(jsonb_build_object('lista', p_lista, 'precos', p_linhas)::text, 'UTF8'), 'sha256'), 'hex');
  v_actor := public.current_actor_id();
  v_payload_hash := encode(extensions.digest(convert_to(jsonb_build_object(
    'file_name', btrim(p_file_name), 'workbook_sha256', lower(p_workbook_sha256), 'size_bytes', p_size_bytes,
    'canonical_payload_sha256', v_expected_hash, 'motivo', btrim(p_motivo)
  )::text, 'UTF8'), 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  perform pg_advisory_xact_lock(hashtextextended('price_list_workbook:' || lower(p_workbook_sha256), 0));
  select * into v_existing_request from public.com_lista_preco_xlsx_requisicoes where idempotency_key = p_idempotency_key;
  if found then
    if v_existing_request.tipo <> 'analisar' or v_existing_request.actor_id is distinct from v_actor or v_existing_request.payload_hash is distinct from v_payload_hash then raise exception 'chave de idempotencia reutilizada com conteudo diferente'; end if;
    select * into v_existing_analysis from public.com_lista_preco_xlsx_analises where id = v_existing_request.analise_id;
    return jsonb_build_object('analise_id', v_existing_analysis.id, 'status', v_existing_analysis.status,
      'canonical_payload_sha256', v_existing_analysis.canonical_payload_sha256, 'idempotente', true, 'workbook_repetido', false);
  end if;
  select analysis.* into v_existing_analysis
    from public.com_lista_preco_xlsx_analises analysis
    join public.source_workbooks workbook on workbook.id = analysis.workbook_id
   where workbook.sha256 = lower(p_workbook_sha256);
  if found then
    if v_existing_analysis.canonical_payload_sha256 is distinct from v_expected_hash then
      raise exception 'SHA-256 ja registrado com payload canonico divergente';
    end if;
    insert into public.com_lista_preco_xlsx_requisicoes(idempotency_key, tipo, analise_id, actor_id, payload_hash)
    values (p_idempotency_key, 'analisar', v_existing_analysis.id, v_actor, v_payload_hash);
    perform public.log_audited_rpc_change('pedidos', 'com_lista_preco_xlsx_analises', v_existing_analysis.id::text,
      'pedidos.lista_preco_xlsx_repetida', 'pedidos.price_lists.import.stage', v_context, null,
      jsonb_build_object('workbook_repetido', true, 'status', v_existing_analysis.status),
      jsonb_build_object('workbook_sha256', lower(p_workbook_sha256)), 'database_rpc');
    return jsonb_build_object('analise_id', v_existing_analysis.id, 'status', v_existing_analysis.status,
      'canonical_payload_sha256', v_existing_analysis.canonical_payload_sha256, 'idempotente', false, 'workbook_repetido', true);
  end if;

  if exists (
    select 1 from public.source_workbooks workbook
     where workbook.sha256 = lower(p_workbook_sha256)
  ) then
    raise exception 'esta planilha ja foi registrada por outro fluxo; gere um novo arquivo pelo modelo operacional';
  end if;

  v_codigo_lista := upper(btrim(coalesce(p_lista->>'codigo_lista', '')));
  v_nome_lista := btrim(coalesce(p_lista->>'nome_lista', ''));
  if public.normalize_catalog_term(v_codigo_lista) is null or public.normalize_catalog_term(v_nome_lista) is null then raise exception 'codigo e nome da lista sao obrigatorios'; end if;
  select list.id, list.nome into v_lista_id, v_lista_nome_canonico
    from public.com_listas_preco list
   where list.codigo_norm = public.normalize_catalog_term(v_codigo_lista);
  if v_lista_id is not null
     and public.normalize_catalog_term(v_nome_lista) is distinct from public.normalize_catalog_term(v_lista_nome_canonico) then
    v_analysis_warnings := v_analysis_warnings || jsonb_build_array(
      'Nome da lista importado difere do cadastro; o codigo identificou a lista existente e o nome cadastrado sera preservado.'
    );
  end if;
  begin v_vigencia_inicio := (p_lista->>'vigencia_inicio')::date; exception when others then raise exception 'vigencia inicial invalida'; end;
  begin v_vigencia_fim := nullif(p_lista->>'vigencia_fim', '')::date; exception when others then raise exception 'vigencia final invalida'; end;
  if v_vigencia_inicio is null or (v_vigencia_fim is not null and v_vigencia_fim < v_vigencia_inicio) then raise exception 'periodo de vigencia invalido'; end if;
  v_uf := nullif(upper(btrim(coalesce(p_lista->>'uf', ''))), '');
  if v_uf is not null and v_uf not in ('AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA','PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO') then raise exception 'UF da lista invalida'; end if;
  v_canal := nullif(lower(btrim(coalesce(p_lista->>'canal', ''))), '');
  if v_canal is not null then
    select id into v_origem_id from public.com_origens_comerciais where codigo = v_canal;
    if v_origem_id is null then raise exception 'canal comercial nao encontrado'; end if;
  end if;
  v_observacao := nullif(btrim(p_lista->>'observacao'), '');

  insert into public.source_workbooks(file_name, sha256, size_bytes, metadata_json, created_by)
  values (btrim(p_file_name), lower(p_workbook_sha256), p_size_bytes,
    jsonb_build_object('kind', 'price_list_operational_xlsx', 'schema_version', 1), v_actor)
  returning id into v_workbook_id;
  insert into public.migration_batches(workbook_id, status, notes, finished_at, created_by, updated_by)
  values (v_workbook_id, 'completed', 'Analise operacional governada de lista de preco XLSX', clock_timestamp(), v_actor, v_actor)
  returning id into v_batch_id;
  insert into public.source_tables(workbook_id, sheet_name, table_name, ref, header_row, data_first_row, data_last_row, column_count, row_count, metadata_json)
  values (v_workbook_id, 'PRECOS', 'tb_precos', 'A1:J' || (jsonb_array_length(p_linhas) + 1)::text, 1, 2,
    jsonb_array_length(p_linhas) + 1, 10, jsonb_array_length(p_linhas), jsonb_build_object('schema_version', 1))
  returning id into v_table_id;

  -- The header/list structure was validated by the server-side workbook parser. The database
  -- revalidates every business identity and numeric value before recording the analysis.
  for v_line in select value from jsonb_array_elements(p_linhas) loop
    v_total := v_total + 1; v_warnings := '[]'::jsonb; v_errors := '[]'::jsonb;
    select null::bigint as id, null::text as codigo_produto, null::text as nome, null::text as status into v_produto;
    select null::bigint as id, null::bigint as produto_id, null::text as codigo_item,
      null::text as status, null::text as descricao, null::text as packaging_status,
      null::numeric as volume_litros into v_apresentacao;
    select null::bigint as id, null::text as codigo, null::text as simbolo, null::text as status into v_unidade;
    v_excel_row := nullif(v_line->>'excel_row', '')::integer;
    v_codigo_produto := upper(btrim(coalesce(v_line->>'codigo_produto', '')));
    v_codigo_apresentacao := upper(btrim(coalesce(v_line->>'codigo_apresentacao', '')));
    v_codigo_unidade := lower(btrim(coalesce(v_line->>'unidade_precificacao', '')));
    v_nome_produto_importado := nullif(btrim(v_line->>'nome_produto'), '');
    v_nome_apresentacao_importado := nullif(btrim(v_line->>'nome_apresentacao'), '');
    v_payload := coalesce(v_line->'source_payload', '{}'::jsonb);
    v_formulas := coalesce(v_line->'formulas', '{}'::jsonb);
    v_cells := coalesce(v_line->'celulas', '{}'::jsonb);
    v_row_hash := lower(coalesce(v_line->>'row_sha256', ''));
    if v_excel_row is null or v_excel_row <= 1 or v_row_hash !~ '^[0-9a-f]{64}$' or jsonb_typeof(v_payload) <> 'object' or jsonb_typeof(v_formulas) <> 'object' or jsonb_typeof(v_cells) <> 'object' then raise exception 'lineage XLSX invalido'; end if;
    v_recomputed_row_hash := public.ord01_price_list_xlsx_row_sha256(v_line - 'row_sha256');
    if v_row_hash is distinct from v_recomputed_row_hash then raise exception 'hash canonico da linha XLSX diverge do conteudo informado'; end if;
    insert into public.source_rows(table_id, excel_row_number, row_index, row_hash, payload_json, formulas_json)
    values (v_table_id, v_excel_row, v_excel_row - 2, v_row_hash, v_payload, v_formulas) returning id into v_row_id;
    if v_formulas <> '{}'::jsonb then v_errors := v_errors || jsonb_build_array('Formula nao permitida em campo autoritativo.'); end if;
    if v_codigo_produto = '' then
      v_errors := v_errors || jsonb_build_array('Codigo do produto e obrigatorio.');
    else
      select product.id, product.codigo_produto, product.nome, product.status into v_produto
        from public.cad_produtos_base product where upper(btrim(product.codigo_produto)) = v_codigo_produto;
      if v_produto.id is null then v_errors := v_errors || jsonb_build_array('Codigo de produto nao encontrado.');
      elsif v_produto.status <> 'active' then v_errors := v_errors || jsonb_build_array('Produto nao esta ativo.');
      elsif v_nome_produto_importado is not null and public.normalize_catalog_term(v_nome_produto_importado) is distinct from public.normalize_catalog_term(v_produto.nome) then
        v_warnings := v_warnings || jsonb_build_array('Nome importado difere do cadastro; o codigo foi mantido como identidade.');
      end if;
    end if;
    if v_codigo_apresentacao = '' then
      v_errors := v_errors || jsonb_build_array('Codigo da apresentacao e obrigatorio.');
    else
      select presentation.id, presentation.produto_id, presentation.codigo_item, presentation.status,
             packaging.descricao, packaging.status as packaging_status, packaging.volume_litros
        into v_apresentacao
        from public.cad_produto_embalagens presentation
        join public.cad_embalagens packaging on packaging.id = presentation.embalagem_id
       where upper(btrim(presentation.codigo_item)) = v_codigo_apresentacao;
      if v_apresentacao.id is null then v_errors := v_errors || jsonb_build_array('Codigo de apresentacao nao encontrado.');
      elsif v_apresentacao.status <> 'active' or v_apresentacao.packaging_status <> 'active' then v_errors := v_errors || jsonb_build_array('Apresentacao nao esta ativa.');
      elsif v_produto.id is not null and v_apresentacao.produto_id <> v_produto.id then v_errors := v_errors || jsonb_build_array('Apresentacao nao pertence ao produto informado.');
      elsif v_nome_apresentacao_importado is not null and public.normalize_catalog_term(v_nome_apresentacao_importado) is distinct from public.normalize_catalog_term(v_apresentacao.descricao) then
        v_warnings := v_warnings || jsonb_build_array('Nome da apresentacao difere do cadastro; o codigo foi mantido como identidade.');
      end if;
    end if;
    if v_codigo_unidade = '' then
      v_errors := v_errors || jsonb_build_array('Unidade de precificacao e obrigatoria.');
    else
      select unit.id, unit.codigo, unit.simbolo, unit.status into v_unidade
        from public.cad_unidades_medida unit where lower(btrim(unit.codigo)) = v_codigo_unidade;
      if v_unidade.id is null then v_errors := v_errors || jsonb_build_array('Unidade de precificacao nao encontrada.');
      elsif v_unidade.status <> 'active' then v_errors := v_errors || jsonb_build_array('Unidade de precificacao nao esta ativa.'); end if;
    end if;
    begin v_fator := (v_line->>'fator_por_apresentacao')::numeric; exception when others then v_fator := null; end;
    if v_fator is null or v_fator <= 0 then v_errors := v_errors || jsonb_build_array('Fator por apresentacao deve ser numerico e positivo.'); end if;
    if lower(coalesce(v_unidade.codigo, '')) = 'l' and (v_apresentacao.volume_litros is null or v_fator is distinct from v_apresentacao.volume_litros) then
      v_errors := v_errors || jsonb_build_array('Para L, o fator deve coincidir com a capacidade em litros da apresentacao.');
    end if;
    begin v_pmp_min := (v_line->>'pmp_min_dias')::integer; exception when others then v_pmp_min := null; end;
    begin v_pmp_max := (v_line->>'pmp_max_dias')::integer; exception when others then v_pmp_max := null; end;
    if v_pmp_min is null or v_pmp_max is null or v_pmp_min < 0 or v_pmp_max < 0 or v_pmp_min > v_pmp_max then v_errors := v_errors || jsonb_build_array('Faixa de PMP invalida.'); end if;
    if jsonb_typeof(v_line->'preco_unitario') <> 'number' then
      v_preco := null; v_errors := v_errors || jsonb_build_array('Preco deve ser uma celula numerica positiva, sem texto ou formula.');
    else
      begin v_preco := (v_line->>'preco_unitario')::numeric; exception when others then v_preco := null; end;
      if v_preco is null or v_preco <= 0 or round(v_preco, 2) <= 0 then v_errors := v_errors || jsonb_build_array('Preco deve resultar em ao menos um centavo por unidade.'); end if;
    end if;
    v_centavos := case when v_preco is not null and round(v_preco, 2) > 0 then (round(v_preco, 2) * 100)::bigint end;
    -- Analysis header is inserted lazily before the first recorded line.
    if v_analysis_id is null then
      insert into public.com_lista_preco_xlsx_analises(
        idempotency_key, workbook_id, batch_id, payload_hash, canonical_payload_sha256,
        lista_id, codigo_lista, nome_lista, nome_lista_canonico, avisos_json,
        vigencia_inicio, vigencia_fim, uf, origem_comercial_id, observacao,
        status, total_linhas, linhas_aprovadas, linhas_aviso, linhas_erro, produtos_count, apresentacoes_count, faixas_count, created_by
      ) values (
        p_idempotency_key, v_workbook_id, v_batch_id, v_payload_hash, v_expected_hash,
        v_lista_id, v_codigo_lista, v_nome_lista, v_lista_nome_canonico, v_analysis_warnings,
        v_vigencia_inicio, v_vigencia_fim, v_uf, v_origem_id, v_observacao,
        'blocked', jsonb_array_length(p_linhas), 0, 0, jsonb_array_length(p_linhas), 0, 0, jsonb_array_length(p_linhas), v_actor
      ) returning id into v_analysis_id;
    end if;
    v_status := case when jsonb_array_length(v_errors) > 0 then 'ERRO' when jsonb_array_length(v_warnings) > 0 then 'AVISO' else 'APROVADA' end;
    insert into public.com_lista_preco_xlsx_linhas(
      analise_id, source_row_id, excel_row, codigo_produto, nome_produto_importado, produto_id, nome_produto_canonico,
      codigo_apresentacao, nome_apresentacao_importado, produto_embalagem_id, nome_apresentacao_canonico,
      unidade_precificacao_codigo, unidade_precificacao_id, fator_por_apresentacao, pmp_min_dias, pmp_max_dias,
      preco_unitario, preco_centavos_por_unidade, observacao, status, avisos_json, erros_json, celulas_json
    ) values (
      v_analysis_id, v_row_id, v_excel_row, nullif(v_codigo_produto, ''), v_nome_produto_importado, v_produto.id, v_produto.nome,
      nullif(v_codigo_apresentacao, ''), v_nome_apresentacao_importado, v_apresentacao.id, v_apresentacao.descricao,
      nullif(v_codigo_unidade, ''), v_unidade.id, v_fator, v_pmp_min, v_pmp_max,
      v_preco, v_centavos, nullif(btrim(v_line->>'observacao'), ''), v_status, v_warnings, v_errors, v_cells
    );
    if v_status = 'ERRO' then v_error_count := v_error_count + 1;
    elsif v_status = 'AVISO' then v_warning_count := v_warning_count + 1;
    else v_approved := v_approved + 1; end if;
  end loop;

  -- The canonical resolver stores only each interval ceiling. A publishable workbook must
  -- therefore define a total, contiguous threshold partition beginning at day zero.
  with inconsistent_presentation as (
    select produto_embalagem_id
      from public.com_lista_preco_xlsx_linhas
     where analise_id = v_analysis_id and produto_embalagem_id is not null
     group by produto_embalagem_id
    having count(distinct unidade_precificacao_id) > 1
        or count(distinct fator_por_apresentacao) > 1
  )
  update public.com_lista_preco_xlsx_linhas line
     set erros_json = line.erros_json || jsonb_build_array('Uma apresentacao deve usar uma unica unidade e fator dentro da versao.'),
         status = 'ERRO'
   where line.analise_id = v_analysis_id
     and line.produto_embalagem_id in (select produto_embalagem_id from inconsistent_presentation);

  with ordered as (
    select line.id, line.pmp_min_dias, line.pmp_max_dias,
      row_number() over (partition by line.produto_embalagem_id order by line.pmp_min_dias, line.pmp_max_dias, line.excel_row) as position,
      lag(line.pmp_max_dias) over (partition by line.produto_embalagem_id order by line.pmp_min_dias, line.pmp_max_dias, line.excel_row) as previous_max,
      count(*) over (partition by line.produto_embalagem_id, line.pmp_max_dias) as threshold_count
    from public.com_lista_preco_xlsx_linhas line
    where line.analise_id = v_analysis_id
      and line.produto_embalagem_id is not null
      and line.pmp_min_dias is not null and line.pmp_max_dias is not null
      and line.pmp_min_dias >= 0 and line.pmp_max_dias >= line.pmp_min_dias
  ), diagnostics as (
    select id,
      (case when position = 1 and pmp_min_dias <> 0
        then jsonb_build_array('A primeira faixa de PMP da apresentacao deve iniciar em 0.') else '[]'::jsonb end)
      || (case when position > 1 and pmp_min_dias > previous_max + 1
        then jsonb_build_array('As faixas de PMP da apresentacao possuem lacuna; a proxima faixa deve iniciar no dia seguinte ao limite anterior.') else '[]'::jsonb end)
      || (case when position > 1 and pmp_min_dias <= previous_max
        then jsonb_build_array('Faixa de PMP duplicada ou sobreposta para a mesma apresentacao.') else '[]'::jsonb end)
      || (case when threshold_count > 1
        then jsonb_build_array('O limite superior da faixa de PMP deve ser unico para a apresentacao.') else '[]'::jsonb end) as errors
    from ordered
  )
  update public.com_lista_preco_xlsx_linhas line
     set erros_json = line.erros_json || diagnostics.errors,
         status = 'ERRO'
    from diagnostics
   where line.id = diagnostics.id and jsonb_array_length(diagnostics.errors) > 0;

  update public.com_lista_preco_xlsx_linhas line
     set status = case when jsonb_array_length(line.erros_json) > 0 then 'ERRO'
                       when jsonb_array_length(line.avisos_json) > 0 then 'AVISO' else 'APROVADA' end
   where line.analise_id = v_analysis_id;

  select count(*) filter (where status = 'APROVADA'), count(*) filter (where status = 'AVISO'),
         count(*) filter (where status = 'ERRO')
    into v_approved, v_warning_count, v_error_count
    from public.com_lista_preco_xlsx_linhas where analise_id = v_analysis_id;

  -- The trigger accepts this summary update only in the transaction that created the fact.
  select count(distinct produto_id), count(distinct produto_embalagem_id) into v_products, v_presentations
    from public.com_lista_preco_xlsx_linhas where analise_id = v_analysis_id and status <> 'ERRO';
  update public.com_lista_preco_xlsx_analises set
    status = case when v_error_count = 0 then 'ready' else 'blocked' end,
    linhas_aprovadas = v_approved, linhas_aviso = v_warning_count, linhas_erro = v_error_count,
    produtos_count = v_products, apresentacoes_count = v_presentations
  where id = v_analysis_id;
  insert into public.com_lista_preco_xlsx_requisicoes(idempotency_key, tipo, analise_id, actor_id, payload_hash)
  values (p_idempotency_key, 'analisar', v_analysis_id, v_actor, v_payload_hash);
  perform public.log_audited_rpc_change('pedidos', 'com_lista_preco_xlsx_analises', v_analysis_id::text,
    'pedidos.lista_preco_xlsx_analisada', 'pedidos.price_lists.import.stage', v_context, null,
    jsonb_build_object('status', case when v_error_count = 0 then 'ready' else 'blocked' end,
      'linhas', v_total, 'avisos', v_warning_count, 'erros', v_error_count,
      'workbook_sha256', lower(p_workbook_sha256), 'canonical_payload_sha256', v_expected_hash),
    jsonb_build_object('file_name', btrim(p_file_name)), 'database_rpc');
  return jsonb_build_object('analise_id', v_analysis_id, 'status', case when v_error_count = 0 then 'ready' else 'blocked' end,
    'canonical_payload_sha256', v_expected_hash, 'idempotente', false, 'workbook_repetido', false,
    'avisos', v_warning_count, 'erros', v_error_count);
end;
$$;

create or replace function public.publicar_com_lista_preco_xlsx_operacional_idempotente(
  p_idempotency_key uuid,
  p_analise_id bigint,
  p_canonical_payload_sha256 text,
  p_confirmar_avisos boolean,
  p_motivo text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_context jsonb; v_actor uuid; v_payload_hash text; v_request public.com_lista_preco_xlsx_requisicoes%rowtype;
  v_analysis public.com_lista_preco_xlsx_analises%rowtype; v_lista_id bigint; v_versao_id bigint; v_publicacao_id bigint;
  v_items jsonb; v_rules jsonb; v_workbook_sha text;
  v_create_key uuid := md5(p_idempotency_key::text || ':create')::uuid;
  v_replace_key uuid := md5(p_idempotency_key::text || ':replace')::uuid;
  v_publish_key uuid := md5(p_idempotency_key::text || ':publish')::uuid;
begin
  v_context := public.begin_audited_rpc('pedidos.price_lists.publish', 'pedidos', 'com_lista_preco_xlsx_publicacoes',
    'status_transition', jsonb_build_object('correlation_id', coalesce(p_idempotency_key::text, 'missing')));
  perform public.require_current_user_permission('pedidos.price_lists.draft.manage');
  if p_idempotency_key is null or p_analise_id is null then raise exception 'chave e analise sao obrigatorias'; end if;
  if lower(coalesce(p_canonical_payload_sha256, '')) !~ '^[0-9a-f]{64}$' then raise exception 'hash canonico invalido'; end if;
  if length(btrim(coalesce(p_motivo, ''))) < 10 then raise exception 'motivo deve ter ao menos 10 caracteres'; end if;
  v_actor := public.current_actor_id();
  v_payload_hash := encode(extensions.digest(convert_to(jsonb_build_object('analise_id', p_analise_id,
    'canonical_payload_sha256', lower(p_canonical_payload_sha256), 'confirmar_avisos', coalesce(p_confirmar_avisos, false),
    'motivo', btrim(p_motivo))::text, 'UTF8'), 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_request from public.com_lista_preco_xlsx_requisicoes where idempotency_key = p_idempotency_key;
  if found then
    if v_request.tipo <> 'publicar' or v_request.actor_id is distinct from v_actor or v_request.payload_hash is distinct from v_payload_hash then raise exception 'chave de idempotencia reutilizada com conteudo diferente'; end if;
    select publication.versao_id into v_versao_id from public.com_lista_preco_publicacoes publication where publication.id = v_request.publicacao_id;
    return jsonb_build_object('analise_id', v_request.analise_id, 'versao_id', v_versao_id, 'publicacao_id', v_request.publicacao_id, 'idempotente', true);
  end if;
  select * into v_analysis from public.com_lista_preco_xlsx_analises where id = p_analise_id for share;
  if not found then raise exception 'analise XLSX nao encontrada'; end if;
  if v_analysis.status <> 'ready' or v_analysis.linhas_erro <> 0 then raise exception 'analise possui erros e nao pode ser publicada'; end if;
  if (v_analysis.linhas_aviso > 0 or jsonb_array_length(v_analysis.avisos_json) > 0)
     and coalesce(p_confirmar_avisos, false) is not true then raise exception 'confirme os avisos antes de publicar'; end if;
  if v_analysis.canonical_payload_sha256 is distinct from lower(p_canonical_payload_sha256) then raise exception 'conteudo analisado diverge da confirmacao'; end if;
  if exists (select 1 from public.com_lista_preco_xlsx_publicacoes where analise_id = p_analise_id) then raise exception 'analise ja publicada com outra chave'; end if;

  v_lista_id := v_analysis.lista_id;
  if v_lista_id is not null then
    if not exists (
      select 1 from public.com_listas_preco list
       where list.id = v_lista_id and list.codigo_norm = public.normalize_catalog_term(v_analysis.codigo_lista)
    ) then raise exception 'lista vinculada na analise nao corresponde mais ao codigo informado'; end if;
    perform pg_advisory_xact_lock(hashtextextended('price_list_id:' || v_lista_id::text, 0));
    if not exists (
      select 1 from public.com_lista_preco_versoes version where version.lista_id = v_lista_id
    ) then
      insert into public.com_lista_preco_versoes(
        lista_id, numero, descricao, vigencia_inicio, vigencia_fim, motivo, created_by, updated_by
      ) values (
        v_lista_id, 1, v_analysis.observacao, v_analysis.vigencia_inicio, v_analysis.vigencia_fim,
        btrim(p_motivo), v_actor, v_actor
      ) returning id into v_versao_id;
    end if;
  else
    if exists (select 1 from public.com_listas_preco list where list.codigo_norm = public.normalize_catalog_term(v_analysis.codigo_lista)) then
      raise exception 'o codigo da lista passou a existir depois da analise; analise novamente antes de publicar';
    end if;
    v_versao_id := public.create_com_lista_preco_rascunho_idempotente(v_create_key, v_analysis.codigo_lista,
      v_analysis.nome_lista, v_analysis.observacao, v_analysis.vigencia_inicio, v_analysis.vigencia_fim, btrim(p_motivo));
    select version.lista_id into v_lista_id from public.com_lista_preco_versoes version where version.id = v_versao_id;
  end if;
  if v_versao_id is null then
    v_versao_id := public.create_com_lista_preco_versao_idempotente(v_create_key, v_lista_id,
      v_analysis.vigencia_inicio, v_analysis.vigencia_fim, v_analysis.observacao, btrim(p_motivo));
  end if;
  select jsonb_agg(jsonb_build_object(
    'produto_embalagem_id', grouped.produto_embalagem_id,
    'unidade_precificacao_id', grouped.unidade_precificacao_id,
    'quantidade_unidade_precificacao_por_apresentacao', grouped.fator_por_apresentacao,
    'precos', grouped.precos
  ) order by grouped.produto_embalagem_id) into v_items
  from (
    select line.produto_embalagem_id, max(line.unidade_precificacao_id) as unidade_precificacao_id,
      max(line.fator_por_apresentacao) as fator_por_apresentacao,
      jsonb_agg(jsonb_build_object('prazo_dias', line.pmp_max_dias,
        'valor_centavos_por_unidade_precificacao', line.preco_centavos_por_unidade) order by line.pmp_max_dias) as precos
    from public.com_lista_preco_xlsx_linhas line
    where line.analise_id = p_analise_id and line.status in ('APROVADA', 'AVISO')
    group by line.produto_embalagem_id
  ) grouped;
  v_rules := jsonb_build_array(jsonb_build_object(
    'codigo', 'XLSX_' || v_analysis.codigo_lista,
    'descricao', 'Abrangencia importada da planilha ' || v_analysis.codigo_lista,
    'prioridade', null,
    'origens_comerciais', case when v_analysis.origem_comercial_id is null then '[]'::jsonb else jsonb_build_array(v_analysis.origem_comercial_id) end,
    'pessoa_papel_ids', '[]'::jsonb, 'areas_comerciais', '[]'::jsonb,
    'ufs', case when v_analysis.uf is null then '[]'::jsonb else jsonb_build_array(v_analysis.uf) end,
    'clientes', '[]'::jsonb, 'produtos', '[]'::jsonb, 'apresentacoes', '[]'::jsonb
  ));
  perform public.replace_com_lista_preco_rascunho_idempotente(v_replace_key, v_versao_id,
    v_analysis.vigencia_inicio, v_analysis.vigencia_fim, v_analysis.observacao, v_items, v_rules, btrim(p_motivo));
  v_publicacao_id := public.publish_com_lista_preco_versao_idempotente(v_publish_key, v_versao_id, btrim(p_motivo));
  select workbook.sha256 into v_workbook_sha from public.source_workbooks workbook where workbook.id = v_analysis.workbook_id;
  insert into public.com_lista_preco_xlsx_publicacoes(
    analise_id, lista_id, versao_id, publicacao_id, workbook_sha256, canonical_payload_sha256, published_by
  ) values (p_analise_id, v_lista_id, v_versao_id, v_publicacao_id, v_workbook_sha, v_analysis.canonical_payload_sha256, v_actor);
  insert into public.com_lista_preco_xlsx_requisicoes(idempotency_key, tipo, analise_id, publicacao_id, actor_id, payload_hash)
  values (p_idempotency_key, 'publicar', p_analise_id, v_publicacao_id, v_actor, v_payload_hash);
  perform public.log_audited_rpc_change('pedidos', 'com_lista_preco_xlsx_publicacoes', p_analise_id::text,
    'pedidos.lista_preco_xlsx_publicada', 'pedidos.price_lists.publish', v_context, null,
    jsonb_build_object('lista_id', v_lista_id, 'versao_id', v_versao_id, 'publicacao_id', v_publicacao_id,
      'workbook_sha256', v_workbook_sha, 'canonical_payload_sha256', v_analysis.canonical_payload_sha256),
    jsonb_build_object('motivo', btrim(p_motivo)), 'database_rpc');
  return jsonb_build_object('analise_id', p_analise_id, 'lista_id', v_lista_id, 'versao_id', v_versao_id,
    'publicacao_id', v_publicacao_id, 'idempotente', false);
end;
$$;

create or replace function public.consultar_com_listas_preco_workspace()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_permission('pedidos.price_lists.view');
  return jsonb_build_object(
    'listas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'codigo', list.codigo, 'nome', list.nome, 'descricao', list.descricao,
        'versoes', coalesce((select jsonb_agg(jsonb_build_object(
          'numero', version.numero, 'vigencia_inicio', version.vigencia_inicio, 'vigencia_fim', version.vigencia_fim,
          'situacao', case when publication.id is null then 'RASCUNHO'
            when withdrawn.id is not null then 'RETIRADA'
            when superseded.id is not null then 'SUBSTITUIDA' else 'PUBLICADA' end,
          'published_at', publication.published_at, 'published_by', profile.display_name
        ) order by version.numero desc)
          from public.com_lista_preco_versoes version
          left join public.com_lista_preco_publicacoes publication on publication.versao_id = version.id
          left join public.com_lista_preco_lifecycle_eventos withdrawn on withdrawn.publicacao_id = publication.id and withdrawn.tipo = 'withdrawn'
          left join public.com_lista_preco_lifecycle_eventos superseded on superseded.publicacao_id = publication.id and superseded.tipo = 'superseded'
          left join public.user_profiles profile on profile.id = publication.published_by
          where version.lista_id = list.id), '[]'::jsonb)
      ) order by list.codigo_norm) from public.com_listas_preco list
    ), '[]'::jsonb),
    'analises', coalesce((select jsonb_agg(jsonb_build_object(
      'id', analysis.id, 'codigo_lista', analysis.codigo_lista, 'nome_lista', analysis.nome_lista,
      'status', analysis.status, 'total_linhas', analysis.total_linhas, 'linhas_aviso', analysis.linhas_aviso,
      'linhas_erro', analysis.linhas_erro, 'created_at', analysis.created_at,
      'publicacao_id', publication.publicacao_id, 'versao_id', publication.versao_id
    ) order by analysis.created_at desc, analysis.id desc) from (select * from public.com_lista_preco_xlsx_analises order by created_at desc, id desc limit 20) analysis
      left join public.com_lista_preco_xlsx_publicacoes publication on publication.analise_id = analysis.id), '[]'::jsonb),
    'catalogos', jsonb_build_object(
      'produtos', coalesce((select jsonb_agg(jsonb_build_object('codigo', product.codigo_produto, 'nome', product.nome) order by product.codigo_produto) from public.cad_produtos_base product where product.status = 'active'), '[]'::jsonb),
      'apresentacoes', coalesce((select jsonb_agg(jsonb_build_object('codigo', presentation.codigo_item, 'produto_codigo', product.codigo_produto,
        'nome', packaging.descricao, 'volume_litros', packaging.volume_litros) order by presentation.codigo_item)
        from public.cad_produto_embalagens presentation join public.cad_produtos_base product on product.id = presentation.produto_id
        join public.cad_embalagens packaging on packaging.id = presentation.embalagem_id
        where presentation.status = 'active' and product.status = 'active' and packaging.status = 'active'), '[]'::jsonb),
      'unidades', coalesce((select jsonb_agg(jsonb_build_object('codigo', unit.codigo, 'nome', unit.nome, 'simbolo', unit.simbolo) order by unit.codigo_norm) from public.cad_unidades_medida unit where unit.status = 'active'), '[]'::jsonb),
      'canais', coalesce((select jsonb_agg(jsonb_build_object('codigo', origin.codigo, 'nome', origin.nome) order by origin.codigo) from public.com_origens_comerciais origin), '[]'::jsonb)
    )
  );
end;
$$;

create or replace function public.consultar_com_lista_preco_xlsx_analise(p_analise_id bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_analysis public.com_lista_preco_xlsx_analises%rowtype;
begin
  perform public.require_current_user_permission('pedidos.price_lists.view');
  select * into v_analysis from public.com_lista_preco_xlsx_analises where id = p_analise_id;
  if not found then raise exception 'analise XLSX nao encontrada'; end if;
  return jsonb_build_object(
    'id', v_analysis.id, 'lista_id', v_analysis.lista_id, 'codigo_lista', v_analysis.codigo_lista,
    'nome_lista', v_analysis.nome_lista, 'nome_lista_canonico', v_analysis.nome_lista_canonico,
    'avisos', v_analysis.avisos_json,
    'vigencia_inicio', v_analysis.vigencia_inicio, 'vigencia_fim', v_analysis.vigencia_fim,
    'uf', v_analysis.uf, 'canal', (select codigo from public.com_origens_comerciais where id = v_analysis.origem_comercial_id),
    'observacao', v_analysis.observacao, 'status', v_analysis.status,
    'total_linhas', v_analysis.total_linhas, 'linhas_aprovadas', v_analysis.linhas_aprovadas,
    'linhas_aviso', v_analysis.linhas_aviso, 'linhas_erro', v_analysis.linhas_erro,
    'produtos_count', v_analysis.produtos_count, 'apresentacoes_count', v_analysis.apresentacoes_count,
    'faixas_count', v_analysis.faixas_count, 'canonical_payload_sha256', v_analysis.canonical_payload_sha256,
    'linhas', coalesce((select jsonb_agg(jsonb_build_object(
      'excel_row', line.excel_row, 'codigo_produto', line.codigo_produto,
      'nome_produto_importado', line.nome_produto_importado, 'nome_produto_canonico', line.nome_produto_canonico,
      'codigo_apresentacao', line.codigo_apresentacao, 'nome_apresentacao_importado', line.nome_apresentacao_importado,
      'nome_apresentacao_canonico', line.nome_apresentacao_canonico, 'unidade_precificacao', line.unidade_precificacao_codigo,
      'fator_por_apresentacao', line.fator_por_apresentacao, 'pmp_min_dias', line.pmp_min_dias,
      'pmp_max_dias', line.pmp_max_dias, 'preco_unitario', line.preco_unitario,
      'preco_centavos_por_unidade', line.preco_centavos_por_unidade,
      'celulas', line.celulas_json,
      'status', line.status, 'avisos', line.avisos_json, 'erros', line.erros_json, 'observacao', line.observacao
    ) order by line.excel_row) from public.com_lista_preco_xlsx_linhas line where line.analise_id = v_analysis.id), '[]'::jsonb),
    'publicacao', (select jsonb_build_object('versao_id', publication.versao_id, 'publicacao_id', publication.publicacao_id,
      'published_at', publication.published_at) from public.com_lista_preco_xlsx_publicacoes publication where publication.analise_id = v_analysis.id)
  );
end;
$$;

alter table public.com_lista_preco_xlsx_analises enable row level security;
alter table public.com_lista_preco_xlsx_linhas enable row level security;
alter table public.com_lista_preco_xlsx_publicacoes enable row level security;
alter table public.com_lista_preco_xlsx_requisicoes enable row level security;
revoke all on table public.com_lista_preco_xlsx_analises, public.com_lista_preco_xlsx_linhas,
  public.com_lista_preco_xlsx_publicacoes, public.com_lista_preco_xlsx_requisicoes from public, anon, authenticated;
revoke all on function public.prevent_com_lista_preco_xlsx_fact_changes() from public, anon, authenticated;
revoke all on function public.analisar_com_lista_preco_xlsx_operacional_idempotente(uuid,text,text,bigint,jsonb,jsonb,text) from public, anon;
revoke all on function public.publicar_com_lista_preco_xlsx_operacional_idempotente(uuid,bigint,text,boolean,text) from public, anon;
revoke all on function public.consultar_com_listas_preco_workspace() from public, anon;
revoke all on function public.consultar_com_lista_preco_xlsx_analise(bigint) from public, anon;
revoke all on function public.ord01_price_list_xlsx_source_value(jsonb) from public, anon, authenticated;
revoke all on function public.ord01_price_list_xlsx_row_document(jsonb) from public, anon, authenticated;
revoke all on function public.ord01_price_list_xlsx_row_sha256(jsonb) from public, anon, authenticated;
grant execute on function public.analisar_com_lista_preco_xlsx_operacional_idempotente(uuid,text,text,bigint,jsonb,jsonb,text) to authenticated;
grant execute on function public.publicar_com_lista_preco_xlsx_operacional_idempotente(uuid,bigint,text,boolean,text) to authenticated;
grant execute on function public.consultar_com_listas_preco_workspace() to authenticated;
grant execute on function public.consultar_com_lista_preco_xlsx_analise(bigint) to authenticated;

-- The name-authoritative legacy staging/apply entrypoints remain available to the owner for
-- historical tooling, but they are no longer public operational APIs after the code-governed UI.
revoke execute on function public.stage_com_lista_preco_xlsx_import_idempotente(uuid,text,text,bigint,jsonb,jsonb,jsonb,text) from authenticated;
revoke execute on function public.apply_com_lista_preco_import_idempotente(uuid,bigint,bigint,date,date,text,jsonb,text) from authenticated;

comment on table public.com_lista_preco_xlsx_analises is
  'Analise operacional append-only de workbook XLSX; codigos governados sao identidade e nomes servem apenas para confirmacao humana.';
comment on function public.publicar_com_lista_preco_xlsx_operacional_idempotente(uuid,bigint,text,boolean,text) is
  'Cria a proxima versao, materializa a analise exata e publica atomicamente pelos contratos canonicos 0124-0129.';
