-- ORD-01 tranche 1A.2: append-only XLSX staging and canonical price-list reconciliation.

insert into public.permission_actions(
  action_key, module, description, default_allowed, sort_order,
  runtime_module_key, runtime_access_kind
)
values
  ('pedidos.price_lists.import.stage', 'pedidos', 'Registrar importacao de lista de preco', false, 130, 'pedidos', 'write'),
  ('pedidos.price_lists.import.apply', 'pedidos', 'Aplicar importacao reconciliada em rascunho', false, 131, 'pedidos', 'write')
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

create table public.com_lista_preco_importacoes (
  id bigint generated always as identity primary key,
  idempotency_key uuid not null unique,
  workbook_id bigint not null references public.source_workbooks(id) on delete restrict,
  batch_id bigint not null unique references public.migration_batches(id) on delete restrict,
  payload_hash text not null,
  status text not null,
  total_linhas integer not null default 0,
  linhas_validas integer not null default 0,
  linhas_com_erro integer not null default 0,
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  applied_at timestamptz,
  constraint com_lista_preco_importacoes_status_check
    check (status in ('ready', 'blocked', 'applied')),
  constraint com_lista_preco_importacoes_counts_check
    check (total_linhas >= 0 and linhas_validas >= 0 and linhas_com_erro >= 0
       and total_linhas = linhas_validas + linhas_com_erro),
  constraint com_lista_preco_importacoes_hash_check check (payload_hash ~ '^[0-9a-f]{32}$')
);

create table public.com_lista_preco_import_linhas (
  id bigint generated always as identity primary key,
  importacao_id bigint not null references public.com_lista_preco_importacoes(id) on delete restrict,
  source_row_id bigint not null references public.source_rows(id) on delete restrict,
  coluna_produto text not null check (coluna_produto ~ '^[A-Z]+$'),
  coluna_embalagem text not null check (coluna_embalagem ~ '^[A-Z]+$'),
  coluna_grupo text check (coluna_grupo is null or coluna_grupo ~ '^[A-Z]+$'),
  coluna_preco text not null check (coluna_preco ~ '^[A-Z]+$'),
  celula_preco text not null check (celula_preco ~ '^[A-Z]+[1-9][0-9]*$'),
  prazo_dias integer not null,
  grupo_bruto text,
  produto_bruto text,
  embalagem_bruta text,
  valor_bruto_texto text,
  valor_bruto numeric,
  valor_normalizado numeric(20,2),
  valor_centavos_por_litro bigint,
  produto_id bigint references public.cad_produtos_base(id) on delete restrict,
  produto_embalagem_id bigint references public.cad_produto_embalagens(id) on delete restrict,
  status_reconciliacao text not null,
  motivo_erro text,
  candidatos_json jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  constraint com_lista_preco_import_linhas_source_key unique (importacao_id, source_row_id, prazo_dias, celula_preco),
  constraint com_lista_preco_import_linhas_prazo_check check (prazo_dias >= 0),
  constraint com_lista_preco_import_linhas_valor_check check (
    (status_reconciliacao = 'valid' and valor_bruto > 0 and valor_normalizado > 0
      and valor_centavos_por_litro > 0 and produto_id is not null and produto_embalagem_id is not null)
    or status_reconciliacao <> 'valid'
  ),
  constraint com_lista_preco_import_linhas_status_check check (status_reconciliacao in (
    'valid', 'produto_nao_encontrado', 'produto_ambiguo',
    'apresentacao_nao_encontrada', 'apresentacao_ambigua',
    'valor_invalido', 'prazo_invalido', 'duplicidade_preco', 'linha_invalida'
  ))
);

create table public.com_lista_preco_import_requisicoes (
  idempotency_key uuid primary key,
  tipo_operacao text not null check (tipo_operacao in ('stage', 'apply')),
  importacao_id bigint not null references public.com_lista_preco_importacoes(id) on delete restrict,
  versao_id bigint references public.com_lista_preco_versoes(id) on delete restrict,
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{32}$'),
  created_at timestamptz not null default clock_timestamp()
);

create table public.com_lista_preco_import_aplicacoes (
  importacao_id bigint primary key references public.com_lista_preco_importacoes(id) on delete restrict,
  versao_id bigint not null unique references public.com_lista_preco_versoes(id) on delete restrict,
  applied_by uuid not null references public.user_profiles(id) on delete restrict,
  applied_at timestamptz not null default clock_timestamp(),
  motivo text not null check (length(btrim(motivo)) >= 10)
);

create index idx_com_lista_preco_import_linhas_status
  on public.com_lista_preco_import_linhas(importacao_id, status_reconciliacao, produto_embalagem_id);
create index idx_com_lista_preco_import_linhas_source
  on public.com_lista_preco_import_linhas(source_row_id, prazo_dias);

create or replace function public.prevent_com_lista_preco_import_fact_changes()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'price list import facts are append-only';
end;
$$;

create trigger trg_com_lista_preco_import_linhas_no_change
before update or delete on public.com_lista_preco_import_linhas
for each row execute function public.prevent_com_lista_preco_import_fact_changes();
create trigger trg_com_lista_preco_import_requisicoes_no_change
before update or delete on public.com_lista_preco_import_requisicoes
for each row execute function public.prevent_com_lista_preco_import_fact_changes();
create trigger trg_com_lista_preco_import_aplicacoes_no_change
before update or delete on public.com_lista_preco_import_aplicacoes
for each row execute function public.prevent_com_lista_preco_import_fact_changes();

create or replace function public.parse_com_lista_preco_valor_bruto(p_valor text)
returns numeric
language plpgsql
immutable
set search_path = public
as $$
declare
  v_valor text := nullif(btrim(p_valor), '');
begin
  if v_valor is null or v_valor !~ '^[0-9]+(\.[0-9]+)?$' then
    raise exception 'valor bruto deve chegar normalizado como decimal positivo';
  end if;
  return v_valor::numeric;
end;
$$;

create or replace function public.normalizar_com_lista_preco_valor_bruto(p_valor text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  v_valor text := regexp_replace(coalesce(p_valor, ''), '[[:space:]]+', '', 'g');
begin
  v_valor := regexp_replace(v_valor, '^R\$', '', 'i');
  if v_valor ~ '^[0-9]{1,3}(\.[0-9]{3})+,[0-9]+$' then
    return replace(replace(v_valor, '.', ''), ',', '.');
  end if;
  if v_valor ~ '^[0-9]+,[0-9]+$' then return replace(v_valor, ',', '.'); end if;
  if v_valor ~ '^[0-9]+(\.[0-9]+)?$' then return v_valor; end if;
  raise exception 'valor bruto de preco invalido';
end;
$$;

create or replace function public.stage_com_lista_preco_xlsx_import_idempotente(
  p_idempotency_key uuid,
  p_file_name text,
  p_workbook_sha256 text,
  p_size_bytes bigint,
  p_tabelas jsonb,
  p_linhas_origem jsonb,
  p_linhas_preco jsonb,
  p_motivo text
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
  v_existing public.com_lista_preco_importacoes%rowtype;
  v_workbook_id bigint;
  v_batch_id bigint;
  v_importacao_id bigint;
  v_tabela jsonb;
  v_linha_origem jsonb;
  v_linha_preco jsonb;
  v_table_id bigint;
  v_source_row_id bigint;
  v_source_excel_row integer;
  v_source_payload jsonb;
  v_produto_ids bigint[];
  v_apresentacao_ids bigint[];
  v_produto_id bigint;
  v_apresentacao_id bigint;
  v_produto_norm text;
  v_embalagem_norm text;
  v_prazo integer;
  v_valor numeric;
  v_valor_normalizado text;
  v_status text;
  v_erro text;
  v_candidatos jsonb;
  v_alertas jsonb := '[]'::jsonb;
  v_total integer := 0;
  v_validas integer := 0;
  v_erros integer := 0;
begin
  v_context := public.begin_audited_rpc(
    'pedidos.price_lists.import.stage', 'pedidos', 'com_lista_preco_importacoes',
    'change_type', jsonb_build_object('correlation_id', coalesce(p_idempotency_key::text, 'missing'))
  );
  if p_idempotency_key is null then raise exception 'chave de idempotencia e obrigatoria'; end if;
  if nullif(btrim(p_file_name), '') is null or right(lower(btrim(p_file_name)), 5) <> '.xlsx' then
    raise exception 'arquivo XLSX valido e obrigatorio';
  end if;
  if coalesce(p_workbook_sha256, '') !~ '^[0-9a-f]{64}$' then raise exception 'sha256 do workbook invalido'; end if;
  if p_size_bytes is null or p_size_bytes <= 0 then raise exception 'tamanho do workbook invalido'; end if;
  if jsonb_typeof(p_tabelas) <> 'array' or jsonb_typeof(p_linhas_origem) <> 'array'
     or jsonb_typeof(p_linhas_preco) <> 'array' then
    raise exception 'tabelas, linhas de origem e linhas de preco devem ser listas';
  end if;
  if jsonb_array_length(p_tabelas) <> 1 or jsonb_array_length(p_linhas_origem) = 0
     or jsonb_array_length(p_linhas_preco) = 0 or jsonb_array_length(p_linhas_preco) > 10000 then
    raise exception 'importacao XLSX deve conter exatamente uma worksheet e entre 1 e 10000 linhas de preco';
  end if;
  if length(btrim(coalesce(p_motivo, ''))) < 10 then raise exception 'motivo deve ter ao menos 10 caracteres'; end if;

  v_actor := public.current_actor_id();
  v_payload_hash := md5(jsonb_build_object(
    'tipo', 'price_list_xlsx_stage', 'file_name', btrim(p_file_name), 'sha256', lower(p_workbook_sha256),
    'size_bytes', p_size_bytes, 'tabelas', p_tabelas, 'linhas_origem', p_linhas_origem,
    'linhas_preco', p_linhas_preco, 'motivo', btrim(p_motivo)
  )::text);
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  perform pg_advisory_xact_lock(hashtextextended(lower(p_workbook_sha256), 0));
  select * into v_existing from public.com_lista_preco_importacoes where idempotency_key = p_idempotency_key;
  if found then
    if v_existing.payload_hash is distinct from v_payload_hash or v_existing.created_by is distinct from v_actor then
      raise exception 'chave de idempotencia reutilizada com conteudo diferente';
    end if;
    return jsonb_build_object('importacao_id', v_existing.id, 'status', v_existing.status,
      'total_linhas', v_existing.total_linhas, 'linhas_validas', v_existing.linhas_validas,
      'linhas_com_erro', v_existing.linhas_com_erro, 'idempotente', true);
  end if;

  select coalesce(table_payload.value->'metadata_json'->'alertas', '[]'::jsonb) into v_alertas
    from jsonb_array_elements(p_tabelas) table_payload;
  select importacao.* into v_existing
    from public.com_lista_preco_importacoes importacao
    join public.source_workbooks workbook on workbook.id = importacao.workbook_id
   where workbook.sha256 = lower(p_workbook_sha256)
   order by importacao.id
   limit 1;
  if found then
    insert into public.com_lista_preco_import_requisicoes(idempotency_key, tipo_operacao, importacao_id, actor_id, payload_hash)
    values (p_idempotency_key, 'stage', v_existing.id, v_actor, v_payload_hash)
    on conflict (idempotency_key) do nothing;
    perform public.log_audited_rpc_change(
      'pedidos', 'com_lista_preco_importacoes', v_existing.id::text,
      'pedidos.lista_preco_importacao_repetida', 'pedidos.price_lists.import.stage', v_context, null,
      jsonb_build_object('workbook_repetido', true, 'sha256', lower(p_workbook_sha256)),
      jsonb_build_object('motivo', 'mesmo workbook nao gerou staging duplicado'), 'database_rpc'
    );
    return jsonb_build_object('importacao_id', v_existing.id, 'status', v_existing.status,
      'total_linhas', v_existing.total_linhas, 'linhas_validas', v_existing.linhas_validas,
      'linhas_com_erro', v_existing.linhas_com_erro, 'idempotente', false,
      'workbook_repetido', true, 'alertas', v_alertas || jsonb_build_array('Esta planilha ja foi importada.'));
  end if;

  insert into public.source_workbooks(file_name, sha256, size_bytes, metadata_json, created_by)
  values (btrim(p_file_name), lower(p_workbook_sha256), p_size_bytes, jsonb_build_object('kind', 'price_list_xlsx'), v_actor)
  on conflict (sha256) do nothing;
  select id into v_workbook_id from public.source_workbooks where sha256 = lower(p_workbook_sha256);
  insert into public.migration_batches(workbook_id, status, notes, created_by, updated_by)
  values (v_workbook_id, 'completed', 'Staging governado de listas de preco XLSX', v_actor, v_actor)
  returning id into v_batch_id;

  for v_tabela in select value from jsonb_array_elements(p_tabelas)
  loop
    if jsonb_typeof(v_tabela) <> 'object' or nullif(btrim(v_tabela->>'table_key'), '') is null
       or nullif(btrim(v_tabela->>'sheet_name'), '') is null or nullif(btrim(v_tabela->>'table_name'), '') is null
       or nullif(btrim(v_tabela->>'ref'), '') is null then
      raise exception 'tabela de origem invalida';
    end if;
    insert into public.source_tables(workbook_id, sheet_name, table_name, ref, header_row, data_first_row,
      data_last_row, column_count, row_count, metadata_json)
    values (v_workbook_id, btrim(v_tabela->>'sheet_name'), btrim(v_tabela->>'table_name'), btrim(v_tabela->>'ref'),
      nullif(v_tabela->>'header_row', '')::integer, nullif(v_tabela->>'data_first_row', '')::integer,
      nullif(v_tabela->>'data_last_row', '')::integer, coalesce(nullif(v_tabela->>'column_count', '')::integer, 0),
      coalesce(nullif(v_tabela->>'row_count', '')::integer, 0), coalesce(v_tabela->'metadata_json', '{}'::jsonb))
    on conflict (workbook_id, sheet_name, table_name, ref) do nothing;
  end loop;

  for v_linha_origem in select value from jsonb_array_elements(p_linhas_origem)
  loop
    if jsonb_typeof(v_linha_origem) <> 'object' or nullif(btrim(v_linha_origem->>'table_key'), '') is null
       or nullif(btrim(v_linha_origem->>'row_key'), '') is null or coalesce(v_linha_origem->>'row_hash', '') !~ '^[0-9a-f]{64}$'
       or jsonb_typeof(v_linha_origem->'payload_json') <> 'object' then
      raise exception 'linha bruta de origem invalida';
    end if;
    select table_row.id into v_table_id
      from public.source_tables table_row
      join jsonb_array_elements(p_tabelas) candidate on candidate->>'table_key' = v_linha_origem->>'table_key'
     where table_row.workbook_id = v_workbook_id
       and table_row.sheet_name = candidate->>'sheet_name'
       and table_row.table_name = candidate->>'table_name'
       and table_row.ref = candidate->>'ref';
    if v_table_id is null then raise exception 'linha aponta para tabela de origem inexistente'; end if;
    insert into public.source_rows(table_id, excel_row_number, row_index, row_hash, payload_json, formulas_json)
    values (v_table_id, nullif(v_linha_origem->>'excel_row_number', '')::integer,
      nullif(v_linha_origem->>'row_index', '')::integer, v_linha_origem->>'row_hash',
      v_linha_origem->'payload_json', coalesce(v_linha_origem->'formulas_json', '{}'::jsonb))
    on conflict (table_id, row_index, row_hash) do nothing;
  end loop;

  insert into public.com_lista_preco_importacoes(
    idempotency_key, workbook_id, batch_id, payload_hash, status, created_by
  ) values (p_idempotency_key, v_workbook_id, v_batch_id, v_payload_hash, 'blocked', v_actor)
  returning id into v_importacao_id;

  for v_linha_preco in select value from jsonb_array_elements(p_linhas_preco)
  loop
    v_total := v_total + 1;
    v_status := 'linha_invalida'; v_erro := null; v_produto_id := null; v_apresentacao_id := null;
    v_produto_ids := null; v_apresentacao_ids := null; v_candidatos := '[]'::jsonb;
    if jsonb_typeof(v_linha_preco) <> 'object'
       or nullif(btrim(v_linha_preco->>'source_table_key'), '') is null
       or nullif(btrim(v_linha_preco->>'source_row_key'), '') is null
       or nullif(btrim(v_linha_preco->>'coluna_produto'), '') !~ '^[A-Z]+$'
       or nullif(btrim(v_linha_preco->>'coluna_embalagem'), '') !~ '^[A-Z]+$'
       or nullif(btrim(v_linha_preco->>'coluna_preco'), '') !~ '^[A-Z]+$'
       or nullif(btrim(v_linha_preco->>'celula_preco'), '') !~ '^[A-Z]+[1-9][0-9]*$' then
      raise exception 'lineage de linha de preco invalida';
    end if;
    select source_row.id, source_row.excel_row_number, source_row.payload_json
      into v_source_row_id, v_source_excel_row, v_source_payload
      from public.source_rows source_row
      join public.source_tables source_table on source_table.id = source_row.table_id
      join jsonb_array_elements(p_linhas_origem) raw
        on raw->>'row_key' = v_linha_preco->>'source_row_key'
       and raw->>'table_key' = v_linha_preco->>'source_table_key'
      join jsonb_array_elements(p_tabelas) candidate
        on candidate->>'table_key' = v_linha_preco->>'source_table_key'
     where source_table.workbook_id = v_workbook_id
       and source_table.sheet_name = candidate->>'sheet_name'
       and source_table.table_name = candidate->>'table_name'
       and source_table.ref = candidate->>'ref'
       and source_row.row_index = nullif(raw->>'row_index', '')::integer
       and source_row.row_hash = raw->>'row_hash';
    if v_source_row_id is null then raise exception 'linha de preco sem linha bruta de origem'; end if;
    if v_linha_preco->>'celula_preco' is distinct from (v_linha_preco->>'coluna_preco') || v_source_excel_row::text then
      raise exception 'celula de preco diverge da linha de origem';
    end if;
    begin
      v_prazo := nullif(v_linha_preco->>'prazo_dias', '')::integer;
      if v_source_payload ->> (v_linha_preco->>'coluna_preco') is distinct from v_linha_preco->>'valor_bruto_texto'
         or v_source_payload ->> (v_linha_preco->>'coluna_produto') is distinct from v_linha_preco->>'produto_bruto'
         or v_source_payload ->> (v_linha_preco->>'coluna_embalagem') is distinct from v_linha_preco->>'embalagem_bruta'
         or (v_linha_preco->>'coluna_grupo' is not null and v_source_payload ->> (v_linha_preco->>'coluna_grupo') is distinct from v_linha_preco->>'grupo_bruto') then
        raise exception 'linha de preco diverge da celula fonte';
      end if;
      v_valor_normalizado := public.normalizar_com_lista_preco_valor_bruto(v_source_payload ->> (v_linha_preco->>'coluna_preco'));
      if v_linha_preco->>'valor_bruto_normalizado' is distinct from v_valor_normalizado then
        raise exception 'valor normalizado diverge da celula fonte';
      end if;
      v_valor := public.parse_com_lista_preco_valor_bruto(v_valor_normalizado);
    exception when others then
      get stacked diagnostics v_erro = message_text;
      v_prazo := null; v_valor := null; v_status := 'valor_invalido';
    end;
    if v_prazo is null or v_prazo < 0 then v_status := 'prazo_invalido'; v_erro := 'prazo deve ser inteiro nao negativo'; end if;
    if v_valor is null or v_valor <= 0 or round(v_valor, 2) <= 0 then
      v_status := 'valor_invalido';
      v_erro := coalesce(v_erro, 'valor deve resultar em ao menos um centavo por litro');
    end if;
    v_produto_norm := public.normalize_catalog_term(v_linha_preco->>'produto_bruto');
    v_embalagem_norm := public.normalize_catalog_term(v_linha_preco->>'embalagem_bruta');
    if v_produto_norm is null or v_embalagem_norm is null then
      v_status := 'linha_invalida'; v_erro := 'produto e embalagem sao obrigatorios';
    elsif v_status = 'linha_invalida' then
      select array_agg(product.id order by product.id) into v_produto_ids
        from public.cad_produtos_base product
       where product.status = 'active'
         and (product.nome_norm = v_produto_norm or public.normalize_catalog_term(product.codigo_produto) = v_produto_norm);
      if coalesce(cardinality(v_produto_ids), 0) = 0 then
        v_status := 'produto_nao_encontrado'; v_erro := 'produto nao encontrado';
      elsif cardinality(v_produto_ids) > 1 then
        v_status := 'produto_ambiguo'; v_erro := 'produto ambiguo';
      else
        v_produto_id := v_produto_ids[1];
        select array_agg(presentation.id order by presentation.id) into v_apresentacao_ids
          from public.cad_produto_embalagens presentation
          join public.cad_embalagens package on package.id = presentation.embalagem_id
         where presentation.produto_id = v_produto_id and presentation.status = 'active' and package.status = 'active'
           and (public.normalize_catalog_term(presentation.codigo_item) = v_embalagem_norm
             or package.descricao_norm = v_embalagem_norm
             or public.normalize_catalog_term(package.codigo_legado) = v_embalagem_norm);
        if coalesce(cardinality(v_apresentacao_ids), 0) = 0 then
          v_status := 'apresentacao_nao_encontrada'; v_erro := 'apresentacao nao encontrada para o produto';
        elsif cardinality(v_apresentacao_ids) > 1 then
          v_status := 'apresentacao_ambigua'; v_erro := 'apresentacao ambigua para o produto';
        else
          v_apresentacao_id := v_apresentacao_ids[1]; v_status := 'valid';
          if exists (
            select 1
              from public.com_lista_preco_import_linhas line
             where line.importacao_id = v_importacao_id
               and line.produto_embalagem_id = v_apresentacao_id
               and line.prazo_dias = v_prazo
               and line.status_reconciliacao = 'valid'
          ) then
            v_status := 'duplicidade_preco';
            v_erro := 'faixa de preco duplicada para a mesma apresentacao';
          end if;
        end if;
      end if;
    end if;
    v_candidatos := jsonb_build_object('produto_ids', coalesce(to_jsonb(v_produto_ids), '[]'::jsonb),
      'produto_embalagem_ids', coalesce(to_jsonb(v_apresentacao_ids), '[]'::jsonb));
    insert into public.com_lista_preco_import_linhas(
      importacao_id, source_row_id, coluna_produto, coluna_embalagem, coluna_grupo, coluna_preco, celula_preco,
      prazo_dias, grupo_bruto, produto_bruto, embalagem_bruta,
      valor_bruto_texto, valor_bruto, valor_normalizado, valor_centavos_por_litro,
      produto_id, produto_embalagem_id, status_reconciliacao, motivo_erro, candidatos_json
    ) values (
      v_importacao_id, v_source_row_id, v_linha_preco->>'coluna_produto', v_linha_preco->>'coluna_embalagem',
      nullif(v_linha_preco->>'coluna_grupo', ''), v_linha_preco->>'coluna_preco', v_linha_preco->>'celula_preco',
      coalesce(v_prazo, 0), nullif(btrim(v_linha_preco->>'grupo_bruto'), ''),
      nullif(btrim(v_linha_preco->>'produto_bruto'), ''), nullif(btrim(v_linha_preco->>'embalagem_bruta'), ''),
      nullif(btrim(v_linha_preco->>'valor_bruto_texto'), ''), v_valor,
      case when v_status = 'valid' then round(v_valor, 2) end,
      case when v_status = 'valid' then (round(v_valor, 2) * 100)::bigint end,
      v_produto_id, v_apresentacao_id, v_status, v_erro, v_candidatos
    );
    if v_status = 'valid' then v_validas := v_validas + 1; else v_erros := v_erros + 1; end if;
  end loop;

  update public.com_lista_preco_importacoes
     set total_linhas = v_total, linhas_validas = v_validas, linhas_com_erro = v_erros,
         status = case when v_erros = 0 then 'ready' else 'blocked' end
   where id = v_importacao_id;
  insert into public.com_lista_preco_import_requisicoes(idempotency_key, tipo_operacao, importacao_id, actor_id, payload_hash)
  values (p_idempotency_key, 'stage', v_importacao_id, v_actor, v_payload_hash);
  perform public.log_audited_rpc_change(
    'pedidos', 'com_lista_preco_importacoes', v_importacao_id::text,
    'pedidos.lista_preco_importacao_staged', 'pedidos.price_lists.import.stage', v_context, null,
    jsonb_build_object('status', case when v_erros = 0 then 'ready' else 'blocked' end,
      'total_linhas', v_total, 'linhas_validas', v_validas, 'linhas_com_erro', v_erros),
    jsonb_build_object('batch_id', v_batch_id, 'workbook_id', v_workbook_id), 'database_rpc'
  );
  return jsonb_build_object('importacao_id', v_importacao_id, 'status', case when v_erros = 0 then 'ready' else 'blocked' end,
    'total_linhas', v_total, 'linhas_validas', v_validas, 'linhas_com_erro', v_erros, 'idempotente', false,
    'workbook_repetido', false, 'alertas', v_alertas);
end;
$$;

create or replace function public.apply_com_lista_preco_import_idempotente(
  p_idempotency_key uuid, p_importacao_id bigint, p_versao_id bigint,
  p_vigencia_inicio date, p_vigencia_fim date, p_descricao text, p_regras jsonb, p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_context jsonb;
  v_actor uuid;
  v_payload_hash text;
  v_existing public.com_lista_preco_import_requisicoes%rowtype;
  v_import public.com_lista_preco_importacoes%rowtype;
  v_items jsonb;
  v_result bigint;
begin
  v_context := public.begin_audited_rpc('pedidos.price_lists.import.apply', 'pedidos',
    'com_lista_preco_import_aplicacoes', 'change_type', jsonb_build_object('correlation_id', coalesce(p_idempotency_key::text, 'missing')));
  if p_idempotency_key is null or p_importacao_id is null or p_versao_id is null then raise exception 'chave, importacao e versao sao obrigatorias'; end if;
  if jsonb_typeof(p_regras) <> 'array' then raise exception 'regras devem ser informadas explicitamente como lista'; end if;
  if length(btrim(coalesce(p_motivo, ''))) < 10 then raise exception 'motivo deve ter ao menos 10 caracteres'; end if;
  v_actor := public.current_actor_id();
  v_payload_hash := md5(jsonb_build_object('tipo', 'price_list_import_apply', 'importacao_id', p_importacao_id,
    'versao_id', p_versao_id, 'vigencia_inicio', p_vigencia_inicio, 'vigencia_fim', p_vigencia_fim,
    'descricao', nullif(btrim(p_descricao), ''), 'regras', p_regras, 'motivo', btrim(p_motivo))::text);
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text, 0));
  select * into v_existing from public.com_lista_preco_import_requisicoes where idempotency_key = p_idempotency_key;
  if found then
    if v_existing.tipo_operacao <> 'apply' or v_existing.actor_id is distinct from v_actor
       or v_existing.payload_hash is distinct from v_payload_hash then raise exception 'chave de idempotencia reutilizada com conteudo diferente'; end if;
    return v_existing.versao_id;
  end if;
  select * into v_import from public.com_lista_preco_importacoes where id = p_importacao_id for update;
  if not found then raise exception 'importacao de lista nao encontrada'; end if;
  if v_import.status <> 'ready' or v_import.linhas_com_erro <> 0 then
    raise exception 'importacao possui linhas nao conciliadas; nao pode aplicar';
  end if;
  if exists (select 1 from public.com_lista_preco_import_aplicacoes where importacao_id = p_importacao_id)
     or exists (select 1 from public.com_lista_preco_import_aplicacoes where versao_id = p_versao_id) then
    raise exception 'importacao ou versao ja foi aplicada';
  end if;
  select jsonb_agg(jsonb_build_object('produto_embalagem_id', grouped.produto_embalagem_id, 'precos', grouped.precos)
    order by grouped.produto_embalagem_id) into v_items
  from (
    select line.produto_embalagem_id,
      jsonb_agg(jsonb_build_object('prazo_dias', line.prazo_dias, 'valor_centavos_por_litro', line.valor_centavos_por_litro)
        order by line.prazo_dias) as precos
    from public.com_lista_preco_import_linhas line
   where line.importacao_id = p_importacao_id and line.status_reconciliacao = 'valid'
   group by line.produto_embalagem_id
  ) grouped;
  if v_items is null then raise exception 'importacao nao possui linhas validas para aplicar'; end if;
  v_result := public.replace_com_lista_preco_rascunho_idempotente(
    p_idempotency_key, p_versao_id, p_vigencia_inicio, p_vigencia_fim, p_descricao, v_items, p_regras, p_motivo
  );
  insert into public.com_lista_preco_import_aplicacoes(importacao_id, versao_id, applied_by, motivo)
  values (p_importacao_id, v_result, v_actor, btrim(p_motivo));
  update public.com_lista_preco_importacoes set status = 'applied', applied_at = clock_timestamp() where id = p_importacao_id;
  insert into public.com_lista_preco_import_requisicoes(idempotency_key, tipo_operacao, importacao_id, versao_id, actor_id, payload_hash)
  values (p_idempotency_key, 'apply', p_importacao_id, v_result, v_actor, v_payload_hash);
  perform public.log_audited_rpc_change('pedidos', 'com_lista_preco_import_aplicacoes', p_importacao_id::text,
    'pedidos.lista_preco_importacao_aplicada', 'pedidos.price_lists.import.apply', v_context, null,
    jsonb_build_object('versao_id', v_result), jsonb_build_object('source', 'apply_com_lista_preco_import_idempotente'), 'database_rpc');
  return v_result;
end;
$$;

create or replace view public.com_lista_preco_import_resumo
with (security_invoker = true)
as
select importacao.id, importacao.batch_id, workbook.file_name, workbook.sha256 as workbook_sha256,
  importacao.status, importacao.total_linhas, importacao.linhas_validas, importacao.linhas_com_erro,
  importacao.created_at, importacao.applied_at
from public.com_lista_preco_importacoes importacao
join public.source_workbooks workbook on workbook.id = importacao.workbook_id;

alter table public.com_lista_preco_importacoes enable row level security;
alter table public.com_lista_preco_import_linhas enable row level security;
alter table public.com_lista_preco_import_requisicoes enable row level security;
alter table public.com_lista_preco_import_aplicacoes enable row level security;
create policy "governed read price list imports" on public.com_lista_preco_importacoes for select to authenticated
  using (public.can_current_user('pedidos.price_lists.view'));
create policy "governed read price list import lines" on public.com_lista_preco_import_linhas for select to authenticated
  using (public.can_current_user('pedidos.price_lists.view'));
create policy "governed read price list import requests" on public.com_lista_preco_import_requisicoes for select to authenticated
  using (public.can_current_user('pedidos.price_lists.view'));
create policy "governed read price list import applications" on public.com_lista_preco_import_aplicacoes for select to authenticated
  using (public.can_current_user('pedidos.price_lists.view'));

revoke all on table public.com_lista_preco_importacoes, public.com_lista_preco_import_linhas,
  public.com_lista_preco_import_requisicoes, public.com_lista_preco_import_aplicacoes from public, anon, authenticated;
grant select on public.com_lista_preco_importacoes, public.com_lista_preco_import_linhas,
  public.com_lista_preco_import_requisicoes, public.com_lista_preco_import_aplicacoes, public.com_lista_preco_import_resumo to authenticated;
revoke all on function public.parse_com_lista_preco_valor_bruto(text) from public, anon, authenticated;
revoke all on function public.stage_com_lista_preco_xlsx_import_idempotente(uuid, text, text, bigint, jsonb, jsonb, jsonb, text) from public, anon;
revoke all on function public.apply_com_lista_preco_import_idempotente(uuid, bigint, bigint, date, date, text, jsonb, text) from public, anon;
grant execute on function public.stage_com_lista_preco_xlsx_import_idempotente(uuid, text, text, bigint, jsonb, jsonb, jsonb, text) to authenticated;
grant execute on function public.apply_com_lista_preco_import_idempotente(uuid, bigint, bigint, date, date, text, jsonb, text) to authenticated;

comment on table public.com_lista_preco_import_linhas is
  'Staging append-only de linhas de preco XLSX; preserva origem e bloqueia aplicacao quando qualquer linha nao reconciliar.';
comment on function public.apply_com_lista_preco_import_idempotente(uuid, bigint, bigint, date, date, text, jsonb, text) is
  'Aplica apenas importacao integralmente reconciliada em versao rascunho, sem inferir regras comerciais.';
comment on function public.stage_com_lista_preco_xlsx_import_idempotente(uuid, text, text, bigint, jsonb, jsonb, jsonb, text) is
  'Registra staging append-only de XLSX e reconcilia produto e apresentacao sem criar cadastros automaticamente.';
