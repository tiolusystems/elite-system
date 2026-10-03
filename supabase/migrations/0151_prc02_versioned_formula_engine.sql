-- PRC-02B: deterministic, versioned formula engine in shadow mode.
-- PRC-01 remains the only official pricing calculation.

insert into public.permission_actions(
  action_key, module, description, default_allowed, sort_order,
  runtime_module_key, runtime_access_kind
)
values
  ('precificacao.formula.manage', 'precificacao', 'Criar grades e versoes de formulas declarativas', false, 856, 'precificacao', 'write'),
  ('precificacao.formula.review', 'precificacao', 'Aprovar ou rejeitar versoes de formulas declarativas', false, 857, 'precificacao', 'write'),
  ('precificacao.formula.lifecycle', 'precificacao', 'Ativar, retirar e registrar evidencia de formulas declarativas', false, 858, 'precificacao', 'write')
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order,
  runtime_module_key = excluded.runtime_module_key,
  runtime_access_kind = excluded.runtime_access_kind;

create sequence public.prc_formula_codigo_seq
  as bigint minvalue 1 maxvalue 99999999 no cycle;
create sequence public.prc_grade_prazo_codigo_seq
  as bigint minvalue 1 maxvalue 99999999 no cycle;

revoke all on sequence public.prc_formula_codigo_seq from public, anon, authenticated;
revoke all on sequence public.prc_grade_prazo_codigo_seq from public, anon, authenticated;

create table public.prc_formula_parametros (
  id bigint generated always as identity primary key,
  codigo text not null unique check (codigo ~ '^[a-z][a-z0-9_]{2,63}$'),
  nome text not null check (length(btrim(nome)) between 3 and 120),
  semantic_type text not null check (semantic_type in ('money_rate','fraction','scalar','period','duration')),
  unit_code text not null check (unit_code in ('BRL_L','FRACTION','SCALAR','PERIOD','DAY')),
  created_at timestamptz not null default clock_timestamp(),
  check (
    (semantic_type = 'money_rate' and unit_code = 'BRL_L') or
    (semantic_type = 'fraction' and unit_code = 'FRACTION') or
    (semantic_type = 'scalar' and unit_code = 'SCALAR') or
    (semantic_type = 'period' and unit_code = 'PERIOD') or
    (semantic_type = 'duration' and unit_code = 'DAY')
  )
);

insert into public.prc_formula_parametros(codigo, nome, semantic_type, unit_code)
values
  ('materia_prima', 'Materia-prima', 'money_rate', 'BRL_L'),
  ('embalagem', 'Embalagem', 'money_rate', 'BRL_L'),
  ('custo_pontuacao_vendedor', 'Custo de pontuacao do vendedor', 'money_rate', 'BRL_L'),
  ('custo_pontuacao_revenda', 'Custo de pontuacao da revenda', 'money_rate', 'BRL_L'),
  ('premiacao_revenda', 'Premiacao da revenda', 'money_rate', 'BRL_L'),
  ('premio_producao', 'Premio de producao', 'money_rate', 'BRL_L'),
  ('frete', 'Frete', 'money_rate', 'BRL_L'),
  ('comissao', 'Comissao', 'fraction', 'FRACTION'),
  ('risco', 'Risco', 'fraction', 'FRACTION'),
  ('marketing', 'Marketing', 'fraction', 'FRACTION'),
  ('tributacao', 'Tributacao', 'fraction', 'FRACTION'),
  ('lucro_minimo', 'Lucro minimo', 'fraction', 'FRACTION'),
  ('markup', 'Markup', 'fraction', 'FRACTION'),
  ('juros_mensais', 'Juros mensais', 'fraction', 'FRACTION');

create table public.prc_grade_prazos (
  id bigint generated always as identity primary key,
  codigo text not null unique check (codigo ~ '^PRZ-[0-9]{8}$'),
  nome text not null check (length(btrim(nome)) between 3 and 120),
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp()
);

create table public.prc_grade_prazo_versoes (
  id bigint generated always as identity primary key,
  grade_id bigint not null references public.prc_grade_prazos(id) on delete restrict,
  versao integer not null check (versao > 0),
  documento_json jsonb not null check (jsonb_typeof(documento_json) = 'object'),
  documento_sha256 text not null check (documento_sha256 ~ '^[0-9a-f]{64}$'),
  motivo text not null check (length(btrim(motivo)) >= 10),
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  unique (grade_id, versao)
);

create table public.prc_grade_prazo_itens (
  id bigint generated always as identity primary key,
  grade_versao_id bigint not null references public.prc_grade_prazo_versoes(id) on delete restrict,
  ordem integer not null check (ordem > 0),
  prazo_dias integer not null check (prazo_dias > 0),
  fator_periodo numeric(30,12) not null check (fator_periodo > 0),
  unique (grade_versao_id, ordem),
  unique (grade_versao_id, prazo_dias)
);

create table public.prc_formula_perfis (
  id bigint generated always as identity primary key,
  codigo text not null unique check (codigo ~ '^FML-[0-9]{8}$'),
  nome text not null check (length(btrim(nome)) between 3 and 120),
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp()
);

create table public.prc_formula_versoes (
  id bigint generated always as identity primary key,
  formula_id bigint not null references public.prc_formula_perfis(id) on delete restrict,
  versao integer not null check (versao > 0),
  grade_versao_id bigint not null references public.prc_grade_prazo_versoes(id) on delete restrict,
  formula_vista_ast jsonb not null check (jsonb_typeof(formula_vista_ast) = 'object'),
  formula_prazo_ast jsonb not null check (jsonb_typeof(formula_prazo_ast) = 'object'),
  arredondamento text not null check (arredondamento = 'HALF_UP'),
  casas_decimais integer not null check (casas_decimais between 0 and 8),
  avaliador_versao text not null check (avaliador_versao = 'prc-formula-ast-v1'),
  documento_json jsonb not null check (jsonb_typeof(documento_json) = 'object'),
  documento_sha256 text not null check (documento_sha256 ~ '^[0-9a-f]{64}$'),
  motivo text not null check (length(btrim(motivo)) >= 10),
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  unique (formula_id, versao)
);

create table public.prc_formula_versao_parametros (
  id bigint generated always as identity primary key,
  formula_versao_id bigint not null references public.prc_formula_versoes(id) on delete restrict,
  parametro_id bigint not null references public.prc_formula_parametros(id) on delete restrict,
  ordem integer not null check (ordem > 0),
  unique (formula_versao_id, parametro_id),
  unique (formula_versao_id, ordem)
);

create table public.prc_formula_revisoes (
  id bigint generated always as identity primary key,
  formula_versao_id bigint not null references public.prc_formula_versoes(id) on delete restrict,
  decisao text not null check (decisao in ('PENDING','APPROVED','REJECTED')),
  justificativa text not null check (length(btrim(justificativa)) >= 10),
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp()
);

create unique index uq_prc_formula_revisao_final
  on public.prc_formula_revisoes(formula_versao_id)
  where decisao in ('APPROVED','REJECTED');

create table public.prc_formula_lifecycle_eventos (
  id bigint generated always as identity primary key,
  formula_versao_id bigint not null references public.prc_formula_versoes(id) on delete restrict,
  estado text not null check (estado in ('ACTIVE','SUPERSEDED','WITHDRAWN')),
  justificativa text not null check (length(btrim(justificativa)) >= 10),
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp()
);

create table public.prc_formula_shadow_execucoes (
  id bigint generated always as identity primary key,
  formula_versao_id bigint not null references public.prc_formula_versoes(id) on delete restrict,
  official_calculo_id bigint references public.prc_calculos(id) on delete restrict,
  entradas_json jsonb not null check (jsonb_typeof(entradas_json) = 'object'),
  entradas_sha256 text not null check (entradas_sha256 ~ '^[0-9a-f]{64}$'),
  resultado_json jsonb not null check (jsonb_typeof(resultado_json) = 'object'),
  resultado_sha256 text not null check (resultado_sha256 ~ '^[0-9a-f]{64}$'),
  motivo text not null check (length(btrim(motivo)) >= 10),
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp()
);

create table public.prc_formula_promocao_evidencias (
  id bigint generated always as identity primary key,
  formula_versao_id bigint not null references public.prc_formula_versoes(id) on delete restrict,
  shadow_execucao_id bigint not null references public.prc_formula_shadow_execucoes(id) on delete restrict,
  evidencia_sha256 text not null check (evidencia_sha256 ~ '^[0-9a-f]{64}$'),
  responsavel_id uuid not null references public.user_profiles(id) on delete restrict,
  justificativa text not null check (length(btrim(justificativa)) >= 10),
  created_at timestamptz not null default clock_timestamp(),
  unique (formula_versao_id, shadow_execucao_id)
);

alter table public.prc_requisicoes
  drop constraint if exists prc_requisicoes_request_type_check;
alter table public.prc_requisicoes
  add constraint prc_requisicoes_request_type_check check (request_type in (
    'policy','policy_review','scenario','calculation','calculation_review',
    'formula_grid','formula_version','formula_review','formula_lifecycle','formula_shadow'
  ));

create schema if not exists precificacao_internal;
revoke all on schema precificacao_internal from public, anon, authenticated;

create or replace function precificacao_internal.prc_decimal(p_value jsonb)
returns numeric
language plpgsql immutable
set search_path = pg_catalog
as $$
declare
  v_text text;
begin
  if jsonb_typeof(p_value) <> 'string' then
    raise exception 'decimal deve ser string canonica';
  end if;
  v_text := p_value #>> '{}';
  if length(v_text) > 64 then raise exception 'decimal excede tamanho maximo'; end if;
  if v_text !~ '^-?(0|[1-9][0-9]*)(\.[0-9]+)?$' then
    raise exception 'decimal canonico invalido';
  end if;
  return v_text::numeric;
exception when numeric_value_out_of_range then
  raise exception 'decimal fora do limite';
end $$;

create or replace function precificacao_internal.prc_formula_inferir_unidade(
  p_node jsonb,
  p_parametros jsonb,
  p_variaveis jsonb,
  p_depth integer default 1
)
returns text
language plpgsql immutable
set search_path = pg_catalog, precificacao_internal
as $$
declare
  v_kind text;
  v_code text;
  v_op text;
  v_left text;
  v_right text;
  v_args jsonb;
  v_unit text;
begin
  if p_depth > 32 then raise exception 'AST excede profundidade maxima'; end if;
  if jsonb_typeof(p_node) <> 'object' then raise exception 'no AST deve ser objeto'; end if;
  v_kind := p_node->>'kind';

  if v_kind = 'constant' then
    if p_node - array['kind','value','unit'] <> '{}'::jsonb then raise exception 'chave AST desconhecida'; end if;
    perform precificacao_internal.prc_decimal(p_node->'value');
    v_unit := p_node->>'unit';
    if v_unit not in ('BRL_L','FRACTION','SCALAR','PERIOD','DAY') then raise exception 'unidade incompativel'; end if;
    return v_unit;
  elsif v_kind = 'parameter' then
    if p_node - array['kind','code'] <> '{}'::jsonb then raise exception 'chave AST desconhecida'; end if;
    v_code := p_node->>'code';
    v_unit := p_parametros->>v_code;
    if v_unit is null then raise exception 'parametro nao declarado: %', v_code; end if;
    return v_unit;
  elsif v_kind = 'variable' then
    if p_node - array['kind','name'] <> '{}'::jsonb then raise exception 'chave AST desconhecida'; end if;
    v_code := p_node->>'name';
    v_unit := p_variaveis->>v_code;
    if v_unit is null then raise exception 'variavel nao permitida: %', v_code; end if;
    return v_unit;
  elsif v_kind <> 'operation' then
    raise exception 'tipo de no AST invalido';
  end if;

  if p_node - array['kind','op','args'] <> '{}'::jsonb then raise exception 'chave AST desconhecida'; end if;
  v_op := p_node->>'op';
  if v_op not in ('add','sub','mul','div','pow') then raise exception 'operador AST invalido'; end if;
  v_args := p_node->'args';
  if jsonb_typeof(v_args) <> 'array' or jsonb_array_length(v_args) <> 2 then
    raise exception 'operacao AST exige dois argumentos';
  end if;
  v_left := precificacao_internal.prc_formula_inferir_unidade(v_args->0, p_parametros, p_variaveis, p_depth + 1);
  v_right := precificacao_internal.prc_formula_inferir_unidade(v_args->1, p_parametros, p_variaveis, p_depth + 1);

  if v_op in ('add','sub') then
    if v_left <> v_right then raise exception 'unidade incompativel em %', v_op; end if;
    return v_left;
  elsif v_op = 'mul' then
    if v_left = 'SCALAR' then return v_right; end if;
    if v_right = 'SCALAR' then return v_left; end if;
    if v_left = 'FRACTION' and v_right in ('FRACTION','BRL_L') then return v_right; end if;
    if v_right = 'FRACTION' and v_left in ('FRACTION','BRL_L') then return v_left; end if;
    raise exception 'unidade incompativel em mul';
  elsif v_op = 'div' then
    if v_left = v_right then return 'SCALAR'; end if;
    if v_right in ('SCALAR','FRACTION') and v_left in ('BRL_L','FRACTION','SCALAR') then return v_left; end if;
    raise exception 'unidade incompativel em div';
  else
    if v_left not in ('FRACTION','SCALAR') or v_right not in ('SCALAR','PERIOD') then
      raise exception 'unidade incompativel em pow';
    end if;
    return v_left;
  end if;
end $$;

create or replace function precificacao_internal.validar_prc_formula_ast(
  p_ast jsonb,
  p_parametros jsonb,
  p_variaveis jsonb default '{}'::jsonb
)
returns text
language plpgsql immutable
set search_path = pg_catalog, precificacao_internal
as $$
declare
  v_nodes integer;
  v_depth integer;
  v_unit text;
begin
  if jsonb_typeof(p_ast) <> 'object' or p_ast - array['schema','result_unit','root'] <> '{}'::jsonb then
    raise exception 'documento AST invalido';
  end if;
  if p_ast->>'schema' <> 'prc-formula-ast-v1' then raise exception 'schema AST invalido'; end if;
  if octet_length(p_ast::text) > 262144 then raise exception 'AST excede tamanho maximo'; end if;
  if jsonb_typeof(p_parametros) <> 'object'
     or (select count(*) from jsonb_object_keys(p_parametros)) > 64 then
    raise exception 'contrato de parametros invalido';
  end if;
  if jsonb_typeof(coalesce(p_variaveis, '{}'::jsonb)) <> 'object' then raise exception 'contrato de variaveis invalido'; end if;

  with recursive nodes(node, depth) as (
    select p_ast->'root', 1
    union all
    select child.value, nodes.depth + 1
      from nodes
      cross join lateral jsonb_array_elements(
        case when jsonb_typeof(nodes.node->'args') = 'array' then nodes.node->'args' else '[]'::jsonb end
      ) child
  )
  select count(*), max(depth) into v_nodes, v_depth from nodes;
  if v_nodes > 512 then raise exception 'AST excede quantidade maxima de nos'; end if;
  if v_depth > 32 then raise exception 'AST excede profundidade maxima'; end if;

  v_unit := precificacao_internal.prc_formula_inferir_unidade(
    p_ast->'root', p_parametros, coalesce(p_variaveis, '{}'::jsonb), 1
  );
  if v_unit <> p_ast->>'result_unit' then raise exception 'unidade incompativel no resultado'; end if;
  return v_unit;
end $$;

create or replace function precificacao_internal.prc_formula_avaliar_no(
  p_node jsonb,
  p_valores jsonb,
  p_variaveis jsonb,
  p_depth integer default 1
)
returns numeric
language plpgsql immutable
set search_path = pg_catalog, precificacao_internal
as $$
declare
  v_kind text := p_node->>'kind';
  v_op text;
  v_left numeric;
  v_right numeric;
  v_result numeric;
  v_value jsonb;
begin
  if p_depth > 32 then raise exception 'AST excede profundidade maxima'; end if;
  if v_kind = 'constant' then
    return precificacao_internal.prc_decimal(p_node->'value');
  elsif v_kind = 'parameter' then
    v_value := p_valores->(p_node->>'code');
    if v_value is null then raise exception 'valor de parametro ausente: %', p_node->>'code'; end if;
    return precificacao_internal.prc_decimal(v_value);
  elsif v_kind = 'variable' then
    v_value := p_variaveis->(p_node->>'name');
    if v_value is null then raise exception 'valor de variavel ausente: %', p_node->>'name'; end if;
    return precificacao_internal.prc_decimal(v_value);
  end if;

  v_op := p_node->>'op';
  v_left := precificacao_internal.prc_formula_avaliar_no(p_node->'args'->0, p_valores, p_variaveis, p_depth + 1);
  v_right := precificacao_internal.prc_formula_avaliar_no(p_node->'args'->1, p_valores, p_variaveis, p_depth + 1);
  if v_op = 'add' then v_result := v_left + v_right;
  elsif v_op = 'sub' then v_result := v_left - v_right;
  elsif v_op = 'mul' then v_result := v_left * v_right;
  elsif v_op = 'div' then
    if v_right = 0 then raise exception 'divisao por zero'; end if;
    v_result := v_left / v_right;
  elsif v_op = 'pow' then
    if abs(v_right) > 32 then raise exception 'expoente excede limite'; end if;
    if (v_left = 0 and v_right <= 0) or (v_left < 0 and v_right <> trunc(v_right)) then
      raise exception 'potencia fora do dominio numerico';
    end if;
    begin
      v_result := power(v_left, v_right);
    exception when others then
      raise exception 'potencia fora do dominio numerico';
    end;
  else
    raise exception 'operador AST invalido';
  end if;
  return v_result;
exception when numeric_value_out_of_range or division_by_zero then
  raise exception 'resultado numerico invalido';
end $$;

create or replace function precificacao_internal.avaliar_prc_formula_ast(
  p_ast jsonb,
  p_valores jsonb,
  p_variaveis jsonb default '{}'::jsonb
)
returns numeric
language plpgsql immutable
set search_path = pg_catalog, precificacao_internal
as $$
begin
  if jsonb_typeof(p_valores) <> 'object' or jsonb_typeof(coalesce(p_variaveis, '{}'::jsonb)) <> 'object' then
    raise exception 'valores de avaliacao invalidos';
  end if;
  return precificacao_internal.prc_formula_avaliar_no(
    p_ast->'root', p_valores, coalesce(p_variaveis, '{}'::jsonb), 1
  );
end $$;

create or replace function precificacao_internal.prc_formula_estado_atual(p_formula_versao_id bigint)
returns text
language sql stable
set search_path = pg_catalog, public
as $$
  select estado
    from public.prc_formula_lifecycle_eventos
   where formula_versao_id = p_formula_versao_id
   order by id desc
   limit 1
$$;

create or replace function precificacao_internal.prc_grade_sha256(p_grade_versao_id bigint)
returns text language plpgsql stable set search_path=pg_catalog,public as $$
declare
  v_grade public.prc_grade_prazo_versoes%rowtype;
  v_item jsonb;
  v_count integer;
begin
  select * into v_grade from public.prc_grade_prazo_versoes where id=p_grade_versao_id;
  if not found then raise exception 'grade inexistente'; end if;
  if v_grade.documento_sha256 is distinct from public.prc_sha256(v_grade.documento_json) then
    raise exception 'hash da grade divergente';
  end if;
  if v_grade.documento_json->>'schema' is distinct from 'prc-term-grid-v1'
     or (v_grade.documento_json->>'grade_id')::bigint is distinct from v_grade.grade_id
     or (v_grade.documento_json->>'versao')::integer is distinct from v_grade.versao
     or jsonb_typeof(v_grade.documento_json->'items') is distinct from 'array' then
    raise exception 'documento da grade divergente';
  end if;
  select count(*) into v_count from public.prc_grade_prazo_itens where grade_versao_id=p_grade_versao_id;
  if v_count<>jsonb_array_length(v_grade.documento_json->'items') then raise exception 'itens da grade divergentes'; end if;
  for v_item in select value from jsonb_array_elements(v_grade.documento_json->'items') loop
    if not exists (
      select 1 from public.prc_grade_prazo_itens i
       where i.grade_versao_id=p_grade_versao_id
         and i.ordem=(v_item->>'ordem')::integer
         and i.prazo_dias=(v_item->>'prazo_dias')::integer
         and i.fator_periodo=(v_item->>'fator_periodo')::numeric
    ) then raise exception 'itens da grade divergentes'; end if;
  end loop;
  return v_grade.documento_sha256;
end $$;

create or replace function public.salvar_prc_grade_prazo_versao_idempotente(
  p_key uuid,
  p_grade_id bigint,
  p_nome text,
  p_itens jsonb,
  p_motivo text
)
returns bigint
language plpgsql security definer
set search_path = public
as $$
declare
  v_ctx jsonb;
  v_actor uuid;
  v_payload jsonb;
  v_existing bigint;
  v_grade public.prc_grade_prazos%rowtype;
  v_versao integer;
  v_doc jsonb;
  v_id bigint;
  v_codigo_num bigint;
  v_count integer;
begin
  v_ctx := public.begin_audited_rpc('precificacao.formula.manage','precificacao','prc_grade_prazo_versoes','change_type',jsonb_build_object('correlation_id',p_key::text));
  v_actor := public.current_actor_id();
  v_payload := jsonb_build_object('grade_id',p_grade_id,'nome',case when p_grade_id is null then btrim(p_nome) else null end,'itens',p_itens,'motivo',btrim(p_motivo));
  perform public.prc_lock_idempotency_key(p_key);
  v_existing := public.prc_idempotent_result(p_key,'formula_grid',v_payload);
  if v_existing is not null then return v_existing; end if;
  if jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) < 1 or jsonb_array_length(p_itens) > 120 then raise exception 'grade de prazos invalida'; end if;
  if length(btrim(coalesce(p_motivo,''))) < 10 then raise exception 'motivo invalido'; end if;

  if p_grade_id is null then
    if length(btrim(coalesce(p_nome,''))) not between 3 and 120 then raise exception 'nome da grade invalido'; end if;
    begin v_codigo_num := nextval('public.prc_grade_prazo_codigo_seq');
    exception when sqlstate '2200H' then raise exception 'codigo de grade esgotado'; end;
    insert into public.prc_grade_prazos(codigo,nome,created_by)
    values(format('PRZ-%s',lpad(v_codigo_num::text,8,'0')),btrim(p_nome),v_actor)
    returning * into v_grade;
  else
    select * into v_grade from public.prc_grade_prazos where id = p_grade_id;
    if not found then raise exception 'grade inexistente'; end if;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('prc-grid:'||v_grade.id::text,0));
  select coalesce(max(versao),0)+1 into v_versao from public.prc_grade_prazo_versoes where grade_id=v_grade.id;

  with itens as (
    select value, ordinality::integer ordem_real
      from jsonb_array_elements(p_itens) with ordinality
  )
  select count(*) into v_count
    from itens
   where jsonb_typeof(value)='object'
     and (value->>'ordem')::integer=ordem_real
     and (value->>'prazo_dias')::integer>0
     and (value->>'fator_periodo')::numeric>0;
  if v_count <> jsonb_array_length(p_itens) then raise exception 'itens da grade invalidos'; end if;
  if (select count(distinct (value->>'prazo_dias')::integer) from jsonb_array_elements(p_itens)) <> v_count then raise exception 'prazo duplicado'; end if;

  v_doc := jsonb_build_object('schema','prc-term-grid-v1','grade_id',v_grade.id,'codigo',v_grade.codigo,'nome',v_grade.nome,'versao',v_versao,'items',p_itens);
  insert into public.prc_grade_prazo_versoes(grade_id,versao,documento_json,documento_sha256,motivo,created_by)
  values(v_grade.id,v_versao,v_doc,public.prc_sha256(v_doc),btrim(p_motivo),v_actor) returning id into v_id;
  insert into public.prc_grade_prazo_itens(grade_versao_id,ordem,prazo_dias,fator_periodo)
  select v_id,(value->>'ordem')::integer,(value->>'prazo_dias')::integer,(value->>'fator_periodo')::numeric
    from jsonb_array_elements(p_itens);
  insert into public.prc_requisicoes values(p_key,'formula_grid',v_actor,public.prc_sha256(v_payload),v_id,clock_timestamp());
  perform public.log_audited_rpc_change('precificacao','prc_grade_prazo_versoes',v_id::text,'precificacao.grade_prazo_versao_criada','precificacao.formula.manage',v_ctx,null,v_doc,jsonb_build_object('motivo',btrim(p_motivo)),'database_rpc');
  return v_id;
end $$;

create or replace function public.salvar_prc_formula_versao_idempotente(
  p_key uuid,
  p_formula_id bigint,
  p_nome text,
  p_formula_vista_ast jsonb,
  p_formula_prazo_ast jsonb,
  p_parametros text[],
  p_grade_versao_id bigint,
  p_casas_decimais integer,
  p_motivo text
)
returns bigint
language plpgsql security definer
set search_path = public
as $$
declare
  v_ctx jsonb;
  v_actor uuid;
  v_payload jsonb;
  v_existing bigint;
  v_formula public.prc_formula_perfis%rowtype;
  v_versao integer;
  v_codigo_num bigint;
  v_contract jsonb;
  v_refs text[];
  v_params text[];
  v_doc jsonb;
  v_grid_sha text;
  v_id bigint;
begin
  v_ctx := public.begin_audited_rpc('precificacao.formula.manage','precificacao','prc_formula_versoes','change_type',jsonb_build_object('correlation_id',p_key::text));
  v_actor := public.current_actor_id();
  v_params := array(select distinct lower(btrim(x)) from unnest(coalesce(p_parametros,array[]::text[])) x order by 1);
  v_payload := jsonb_build_object('formula_id',p_formula_id,'nome',case when p_formula_id is null then btrim(p_nome) else null end,'formula_vista_ast',p_formula_vista_ast,'formula_prazo_ast',p_formula_prazo_ast,'parametros',to_jsonb(v_params),'grade_versao_id',p_grade_versao_id,'casas_decimais',p_casas_decimais,'motivo',btrim(p_motivo));
  perform public.prc_lock_idempotency_key(p_key);
  v_existing := public.prc_idempotent_result(p_key,'formula_version',v_payload);
  if v_existing is not null then return v_existing; end if;
  if cardinality(v_params) < 1 or cardinality(v_params) > 64 then raise exception 'contrato de parametros invalido'; end if;
  if p_casas_decimais not between 0 and 8 or length(btrim(coalesce(p_motivo,''))) < 10 then raise exception 'configuracao de formula invalida'; end if;
  v_grid_sha := precificacao_internal.prc_grade_sha256(p_grade_versao_id);
  select jsonb_object_agg(p.codigo,p.unit_code order by p.codigo) into v_contract
    from public.prc_formula_parametros p where p.codigo=any(v_params);
  if (select count(*) from jsonb_object_keys(coalesce(v_contract,'{}'::jsonb))) <> cardinality(v_params) then raise exception 'parametro de formula inexistente'; end if;

  perform precificacao_internal.validar_prc_formula_ast(p_formula_vista_ast,v_contract,'{}'::jsonb);
  perform precificacao_internal.validar_prc_formula_ast(p_formula_prazo_ast,v_contract,jsonb_build_object('cash_price','BRL_L','spot_price','BRL_L','term_period','PERIOD','term_days','DAY'));
  if p_formula_vista_ast->>'result_unit' <> 'BRL_L' or p_formula_prazo_ast->>'result_unit' <> 'BRL_L' then raise exception 'unidade incompativel no resultado'; end if;

  with recursive nodes(node) as (
    select p_formula_vista_ast->'root' union all
    select child.value from nodes cross join lateral jsonb_array_elements(case when jsonb_typeof(nodes.node->'args')='array' then nodes.node->'args' else '[]'::jsonb end) child
  ), nodes2(node) as (
    select p_formula_prazo_ast->'root' union all
    select child.value from nodes2 cross join lateral jsonb_array_elements(case when jsonb_typeof(nodes2.node->'args')='array' then nodes2.node->'args' else '[]'::jsonb end) child
  )
  select array(select distinct code from (select node->>'code' code from nodes where node->>'kind'='parameter' union all select node->>'code' from nodes2 where node->>'kind'='parameter') q order by code) into v_refs;
  if v_refs is distinct from v_params then raise exception 'parametros declarados divergem da AST'; end if;

  if p_formula_id is null then
    if length(btrim(coalesce(p_nome,''))) not between 3 and 120 then raise exception 'nome da formula invalido'; end if;
    begin v_codigo_num:=nextval('public.prc_formula_codigo_seq');
    exception when sqlstate '2200H' then raise exception 'codigo de formula esgotado'; end;
    insert into public.prc_formula_perfis(codigo,nome,created_by)
    values(format('FML-%s',lpad(v_codigo_num::text,8,'0')),btrim(p_nome),v_actor) returning * into v_formula;
  else
    select * into v_formula from public.prc_formula_perfis where id=p_formula_id;
    if not found then raise exception 'formula inexistente'; end if;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('prc-formula:'||v_formula.id::text,0));
  select coalesce(max(versao),0)+1 into v_versao from public.prc_formula_versoes where formula_id=v_formula.id;
  v_doc:=jsonb_build_object('schema','prc-formula-v1','evaluator','prc-formula-ast-v1','formula_id',v_formula.id,'codigo',v_formula.codigo,'nome',v_formula.nome,'versao',v_versao,'parameters',v_contract,'cash_formula',p_formula_vista_ast,'term_formula',p_formula_prazo_ast,'term_grid_version_id',p_grade_versao_id,'term_grid_sha256',v_grid_sha,'rounding','HALF_UP','decimal_places',p_casas_decimais);
  insert into public.prc_formula_versoes(formula_id,versao,grade_versao_id,formula_vista_ast,formula_prazo_ast,arredondamento,casas_decimais,avaliador_versao,documento_json,documento_sha256,motivo,created_by)
  values(v_formula.id,v_versao,p_grade_versao_id,p_formula_vista_ast,p_formula_prazo_ast,'HALF_UP',p_casas_decimais,'prc-formula-ast-v1',v_doc,public.prc_sha256(v_doc),btrim(p_motivo),v_actor) returning id into v_id;
  insert into public.prc_formula_versao_parametros(formula_versao_id,parametro_id,ordem)
  select v_id,p.id,row_number() over(order by p.codigo)::integer from public.prc_formula_parametros p where p.codigo=any(v_params);
  insert into public.prc_formula_revisoes(formula_versao_id,decisao,justificativa,actor_id)
  values(v_id,'PENDING','Versao criada e pendente de revisao segregada',v_actor);
  insert into public.prc_requisicoes values(p_key,'formula_version',v_actor,public.prc_sha256(v_payload),v_id,clock_timestamp());
  perform public.log_audited_rpc_change('precificacao','prc_formula_versoes',v_id::text,'precificacao.formula_versao_criada','precificacao.formula.manage',v_ctx,null,v_doc,jsonb_build_object('motivo',btrim(p_motivo)),'database_rpc');
  return v_id;
end $$;

create or replace function public.revisar_prc_formula_versao_idempotente(p_key uuid,p_formula_versao_id bigint,p_decisao text,p_justificativa text)
returns bigint language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb; v_actor uuid; v_payload jsonb; v_existing bigint; v_version public.prc_formula_versoes%rowtype; v_id bigint; v_decision text:=upper(btrim(p_decisao));
begin
  v_ctx:=public.begin_audited_rpc('precificacao.formula.review','precificacao','prc_formula_revisoes','status_transition',jsonb_build_object('correlation_id',p_key::text)); v_actor:=public.current_actor_id();
  v_payload:=jsonb_build_object('formula_versao_id',p_formula_versao_id,'decisao',v_decision,'justificativa',btrim(p_justificativa)); perform public.prc_lock_idempotency_key(p_key); v_existing:=public.prc_idempotent_result(p_key,'formula_review',v_payload); if v_existing is not null then return v_existing; end if;
  if v_decision not in ('APPROVED','REJECTED') or length(btrim(coalesce(p_justificativa,'')))<10 then raise exception 'revisao de formula invalida'; end if;
  select * into v_version from public.prc_formula_versoes where id=p_formula_versao_id; if not found then raise exception 'versao de formula inexistente'; end if;
  if v_version.created_by=v_actor then raise exception 'autor nao pode aprovar ou rejeitar a propria formula'; end if;
  if exists(select 1 from public.prc_formula_revisoes where formula_versao_id=p_formula_versao_id and decisao in ('APPROVED','REJECTED')) then raise exception 'formula ja revisada'; end if;
  insert into public.prc_formula_revisoes(formula_versao_id,decisao,justificativa,actor_id) values(p_formula_versao_id,v_decision,btrim(p_justificativa),v_actor) returning id into v_id;
  insert into public.prc_requisicoes values(p_key,'formula_review',v_actor,public.prc_sha256(v_payload),v_id,clock_timestamp());
  perform public.log_audited_rpc_change('precificacao','prc_formula_revisoes',v_id::text,'precificacao.formula_revisada','precificacao.formula.review',v_ctx,null,jsonb_build_object('formula_versao_id',p_formula_versao_id,'decisao',v_decision),jsonb_build_object('justificativa',btrim(p_justificativa)),'database_rpc'); return v_id;
end $$;

create or replace function public.alterar_prc_formula_lifecycle_idempotente(p_key uuid,p_formula_versao_id bigint,p_acao text,p_justificativa text)
returns bigint language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb; v_actor uuid; v_payload jsonb; v_existing bigint; v_version public.prc_formula_versoes%rowtype; v_current bigint; v_id bigint; v_action text:=upper(btrim(p_acao));
begin
  v_ctx:=public.begin_audited_rpc('precificacao.formula.lifecycle','precificacao','prc_formula_lifecycle_eventos','status_transition',jsonb_build_object('correlation_id',p_key::text)); v_actor:=public.current_actor_id();
  v_payload:=jsonb_build_object('formula_versao_id',p_formula_versao_id,'acao',v_action,'justificativa',btrim(p_justificativa)); perform public.prc_lock_idempotency_key(p_key); v_existing:=public.prc_idempotent_result(p_key,'formula_lifecycle',v_payload); if v_existing is not null then return v_existing; end if;
  if v_action not in ('ACTIVE','WITHDRAWN') or length(btrim(coalesce(p_justificativa,'')))<10 then raise exception 'acao de lifecycle invalida'; end if;
  select * into v_version from public.prc_formula_versoes where id=p_formula_versao_id; if not found then raise exception 'versao de formula inexistente'; end if;
  perform pg_advisory_xact_lock(hashtextextended('prc-formula-lifecycle:'||v_version.formula_id::text,0));
  if v_action='ACTIVE' then
    if not exists(select 1 from public.prc_formula_revisoes where formula_versao_id=p_formula_versao_id and decisao='APPROVED') then raise exception 'somente formula aprovada pode ser ativada'; end if;
    if exists(select 1 from public.prc_formula_lifecycle_eventos where formula_versao_id=p_formula_versao_id and estado in ('SUPERSEDED','WITHDRAWN')) then raise exception 'formula historica nao pode ser reativada'; end if;
    select fv.id into v_current from public.prc_formula_versoes fv where fv.formula_id=v_version.formula_id and fv.id<>p_formula_versao_id and precificacao_internal.prc_formula_estado_atual(fv.id)='ACTIVE' order by fv.id desc limit 1;
    if v_current is not null then insert into public.prc_formula_lifecycle_eventos(formula_versao_id,estado,justificativa,actor_id) values(v_current,'SUPERSEDED','Substituida atomicamente por nova versao ativa',v_actor); end if;
    if precificacao_internal.prc_formula_estado_atual(p_formula_versao_id)='ACTIVE' then raise exception 'formula ja esta ativa'; end if;
  else
    if precificacao_internal.prc_formula_estado_atual(p_formula_versao_id)<>'ACTIVE' then raise exception 'somente formula ativa pode ser retirada'; end if;
  end if;
  insert into public.prc_formula_lifecycle_eventos(formula_versao_id,estado,justificativa,actor_id) values(p_formula_versao_id,v_action,btrim(p_justificativa),v_actor) returning id into v_id;
  insert into public.prc_requisicoes values(p_key,'formula_lifecycle',v_actor,public.prc_sha256(v_payload),v_id,clock_timestamp());
  perform public.log_audited_rpc_change('precificacao','prc_formula_lifecycle_eventos',v_id::text,'precificacao.formula_lifecycle_alterado','precificacao.formula.lifecycle',v_ctx,null,jsonb_build_object('formula_versao_id',p_formula_versao_id,'estado',v_action),jsonb_build_object('justificativa',btrim(p_justificativa)),'database_rpc'); return v_id;
end $$;

create or replace function public.executar_prc_formula_shadow_idempotente(p_key uuid,p_formula_versao_id bigint,p_valores jsonb,p_official_calculo_id bigint,p_motivo text)
returns bigint language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb; v_actor uuid; v_payload jsonb; v_existing bigint; v_version public.prc_formula_versoes%rowtype; v_grid_sha text; v_contract jsonb; v_expected text[]; v_actual text[]; v_cash numeric; v_terms jsonb:='[]'::jsonb; v_item public.prc_grade_prazo_itens%rowtype; v_term numeric; v_result jsonb; v_id bigint;
begin
  v_ctx:=public.begin_audited_rpc('precificacao.formula.manage','precificacao','prc_formula_shadow_execucoes','field_risk',jsonb_build_object('correlation_id',p_key::text)); v_actor:=public.current_actor_id();
  v_payload:=jsonb_build_object('formula_versao_id',p_formula_versao_id,'valores',p_valores,'official_calculo_id',p_official_calculo_id,'motivo',btrim(p_motivo)); perform public.prc_lock_idempotency_key(p_key); v_existing:=public.prc_idempotent_result(p_key,'formula_shadow',v_payload);
  if jsonb_typeof(p_valores)<>'object' or length(btrim(coalesce(p_motivo,'')))<10 then raise exception 'entrada shadow invalida'; end if;
  select * into v_version from public.prc_formula_versoes where id=p_formula_versao_id; if not found then raise exception 'versao de formula inexistente'; end if;
  v_grid_sha:=precificacao_internal.prc_grade_sha256(v_version.grade_versao_id);
  if v_version.documento_sha256 is distinct from public.prc_sha256(v_version.documento_json)
     or (v_version.documento_json->>'term_grid_version_id')::bigint is distinct from v_version.grade_versao_id
     or v_version.documento_json->>'term_grid_sha256' is distinct from v_grid_sha
     or v_version.documento_json->'cash_formula' is distinct from v_version.formula_vista_ast
     or v_version.documento_json->'term_formula' is distinct from v_version.formula_prazo_ast then
    raise exception 'hash ou documento da formula divergente';
  end if;
  if v_existing is not null then return v_existing; end if;
  if precificacao_internal.prc_formula_estado_atual(p_formula_versao_id)<>'ACTIVE' then raise exception 'somente formula ativa pode executar shadow'; end if;
  select jsonb_object_agg(p.codigo,p.unit_code order by p.codigo),array_agg(p.codigo order by p.codigo) into v_contract,v_expected from public.prc_formula_versao_parametros vp join public.prc_formula_parametros p on p.id=vp.parametro_id where vp.formula_versao_id=p_formula_versao_id;
  select array_agg(key order by key) into v_actual from jsonb_object_keys(p_valores) key;
  if v_actual is distinct from v_expected then raise exception 'valores devem corresponder exatamente aos parametros declarados'; end if;
  perform precificacao_internal.validar_prc_formula_ast(v_version.formula_vista_ast,v_contract,'{}'::jsonb);
  perform precificacao_internal.validar_prc_formula_ast(v_version.formula_prazo_ast,v_contract,jsonb_build_object('cash_price','BRL_L','spot_price','BRL_L','term_period','PERIOD','term_days','DAY'));
  v_cash:=precificacao_internal.avaliar_prc_formula_ast(v_version.formula_vista_ast,p_valores,'{}'::jsonb);
  for v_item in select * from public.prc_grade_prazo_itens where grade_versao_id=v_version.grade_versao_id order by ordem loop
    v_term:=precificacao_internal.avaliar_prc_formula_ast(v_version.formula_prazo_ast,p_valores,jsonb_build_object('cash_price',v_cash::text,'spot_price',v_cash::text,'term_period',v_item.fator_periodo::text,'term_days',v_item.prazo_dias::text));
    v_terms:=v_terms||jsonb_build_array(jsonb_build_object('order',v_item.ordem,'days',v_item.prazo_dias,'period_factor',v_item.fator_periodo::text,'exact',v_term::text,'commercial',round(v_term,v_version.casas_decimais)::text));
  end loop;
  v_result:=jsonb_build_object('schema','prc-formula-shadow-v1','formula_version_id',v_version.id,'formula_sha256',v_version.documento_sha256,'term_grid_version_id',v_version.grade_versao_id,'term_grid_sha256',v_grid_sha,'cash',jsonb_build_object('exact',v_cash::text,'commercial',round(v_cash,v_version.casas_decimais)::text),'terms',v_terms);
  insert into public.prc_formula_shadow_execucoes(formula_versao_id,official_calculo_id,entradas_json,entradas_sha256,resultado_json,resultado_sha256,motivo,actor_id) values(p_formula_versao_id,p_official_calculo_id,p_valores,public.prc_sha256(p_valores),v_result,public.prc_sha256(v_result),btrim(p_motivo),v_actor) returning id into v_id;
  insert into public.prc_requisicoes values(p_key,'formula_shadow',v_actor,public.prc_sha256(v_payload),v_id,clock_timestamp());
  perform public.log_audited_rpc_change('precificacao','prc_formula_shadow_execucoes',v_id::text,'precificacao.formula_shadow_executada','precificacao.formula.manage',v_ctx,null,v_result,jsonb_build_object('motivo',btrim(p_motivo)),'database_rpc'); return v_id;
end $$;

do $$ declare v_table text; begin
  foreach v_table in array array[
    'prc_formula_parametros','prc_grade_prazos','prc_grade_prazo_versoes','prc_grade_prazo_itens',
    'prc_formula_perfis','prc_formula_versoes','prc_formula_versao_parametros','prc_formula_revisoes',
    'prc_formula_lifecycle_eventos','prc_formula_shadow_execucoes','prc_formula_promocao_evidencias'
  ] loop
    execute format('create trigger %I before update or delete on public.%I for each row execute function public.prevent_prc_fact_changes()', 'trg_'||v_table||'_append_only', v_table);
    execute format('create trigger %I before truncate on public.%I for each statement execute function public.prevent_prc_fact_changes()', 'trg_'||v_table||'_no_truncate', v_table);
    execute format('alter table public.%I enable row level security', v_table);
    execute format('revoke all on table public.%I from public, anon, authenticated', v_table);
  end loop;
end $$;

revoke all on all functions in schema precificacao_internal from public, anon, authenticated;
revoke all on function public.salvar_prc_grade_prazo_versao_idempotente(uuid,bigint,text,jsonb,text) from public, anon, authenticated;
revoke all on function public.salvar_prc_formula_versao_idempotente(uuid,bigint,text,jsonb,jsonb,text[],bigint,integer,text) from public, anon, authenticated;
revoke all on function public.revisar_prc_formula_versao_idempotente(uuid,bigint,text,text) from public, anon, authenticated;
revoke all on function public.alterar_prc_formula_lifecycle_idempotente(uuid,bigint,text,text) from public, anon, authenticated;
revoke all on function public.executar_prc_formula_shadow_idempotente(uuid,bigint,jsonb,bigint,text) from public, anon, authenticated;
grant execute on function public.salvar_prc_grade_prazo_versao_idempotente(uuid,bigint,text,jsonb,text) to authenticated;
grant execute on function public.salvar_prc_formula_versao_idempotente(uuid,bigint,text,jsonb,jsonb,text[],bigint,integer,text) to authenticated;
grant execute on function public.revisar_prc_formula_versao_idempotente(uuid,bigint,text,text) to authenticated;
grant execute on function public.alterar_prc_formula_lifecycle_idempotente(uuid,bigint,text,text) to authenticated;
grant execute on function public.executar_prc_formula_shadow_idempotente(uuid,bigint,jsonb,bigint,text) to authenticated;

comment on table public.prc_formula_perfis is 'Stable identities for declarative PRC formulas. Codes are database-issued.';
comment on table public.prc_formula_versoes is 'Append-only typed formula versions; PRC-01 remains authoritative.';
comment on table public.prc_formula_lifecycle_eventos is 'Append-only operational lifecycle. ACTIVE, SUPERSEDED and WITHDRAWN are separate from review.';
comment on table public.prc_formula_promocao_evidencias is 'Foundation for explicit human promotion evidence. No automatic promotion surface exists.';
