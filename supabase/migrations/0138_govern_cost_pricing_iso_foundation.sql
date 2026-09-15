-- PRC-01: governed cost and pricing foundation. No commercial price-list publication.

insert into public.sys_modules(module_key, display_name, description, owner_domain, is_core, sort_order)
values ('precificacao', 'Formacao de custos e precos', 'Politicas, cenarios, memoria de calculo, revisao e dossie', 'precificacao', false, 850)
on conflict (module_key) do update set display_name=excluded.display_name, description=excluded.description,
  owner_domain=excluded.owner_domain, is_core=excluded.is_core, sort_order=excluded.sort_order;

insert into public.sys_module_routes(route_prefix, module_key, match_children)
values ('/custos-precos', 'precificacao', true)
on conflict (route_prefix) do update set module_key=excluded.module_key, match_children=excluded.match_children;

insert into public.sys_module_dependencies(module_key, depends_on_module_key, minimum_access, required, reason)
values
  ('precificacao','core','read_write',true,'Formacao de precos exige sessao e runtime central'),
  ('precificacao','seguranca','read_only',true,'Politicas, calculos e revisoes exigem ator e alcada'),
  ('precificacao','cadastros','read_only',true,'Cenario referencia produto e apresentacao governados'),
  ('precificacao','pcp','read_only',false,'Composicao tecnica pode fornecer origem de custo sem escrita cruzada'),
  ('precificacao','estoque','read_only',false,'Custos por lote podem fornecer origem sem alterar movimento fisico')
on conflict (module_key, depends_on_module_key) do update set minimum_access=excluded.minimum_access,
  required=excluded.required, reason=excluded.reason;

insert into public.permission_actions(action_key,module,description,default_allowed,sort_order,runtime_module_key,runtime_access_kind)
values
  ('precificacao.view','precificacao','Consultar custos, cenarios, calculos e dossies',false,850,'precificacao','read'),
  ('precificacao.policy.manage','precificacao','Criar politica versionada de formacao de preco',false,851,'precificacao','write'),
  ('precificacao.policy.review','precificacao','Aprovar ou rejeitar politica de formacao de preco',false,852,'precificacao','write'),
  ('precificacao.scenario.manage','precificacao','Criar cenario com fontes e substituicoes congeladas',false,853,'precificacao','write'),
  ('precificacao.calculate','precificacao','Calcular memoria de custo e precos por prazo',false,854,'precificacao','write'),
  ('precificacao.calculation.review','precificacao','Aprovar ou rejeitar calculo sem publicar lista',false,855,'precificacao','write')
on conflict (action_key) do update set module=excluded.module,description=excluded.description,
  default_allowed=excluded.default_allowed,sort_order=excluded.sort_order,
  runtime_module_key=excluded.runtime_module_key,runtime_access_kind=excluded.runtime_access_kind;

create table public.prc_politicas (
  id bigint generated always as identity primary key,
  codigo text not null unique check (codigo ~ '^[A-Z0-9][A-Z0-9_-]{2,39}$'),
  nome text not null check (length(btrim(nome)) between 3 and 120),
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp()
);

create table public.prc_politica_versoes (
  id bigint generated always as identity primary key,
  politica_id bigint not null references public.prc_politicas(id) on delete restrict,
  versao integer not null check (versao > 0),
  metodo text not null check (metodo in ('margem_liquida','markup')),
  lucro_minimo numeric(12,8),
  markup numeric(12,8),
  juros_mensais numeric(12,8) not null check (juros_mensais >= 0),
  arredondamento text not null default 'HALF_UP' check (arredondamento='HALF_UP'),
  casas_decimais integer not null default 2 check (casas_decimais=2),
  documento_json jsonb not null check (jsonb_typeof(documento_json)='object'),
  documento_sha256 text not null check (documento_sha256 ~ '^[0-9a-f]{64}$'),
  motivo text not null check (length(btrim(motivo)) >= 10),
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  unique(politica_id,versao),
  check ((metodo='margem_liquida' and lucro_minimo >= 0 and lucro_minimo < 1 and markup is null)
      or (metodo='markup' and markup >= 0 and lucro_minimo is null))
);

create table public.prc_politica_revisoes (
  id bigint generated always as identity primary key,
  politica_versao_id bigint not null references public.prc_politica_versoes(id) on delete restrict,
  decisao text not null check (decisao in ('APPROVED','REJECTED')),
  justificativa text not null check (length(btrim(justificativa)) >= 10),
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  unique(politica_versao_id)
);

create table public.prc_cenarios (
  id bigint generated always as identity primary key,
  politica_versao_id bigint not null references public.prc_politica_versoes(id) on delete restrict,
  produto_embalagem_id bigint not null references public.cad_produto_embalagens(id) on delete restrict,
  nome text not null check (length(btrim(nome)) between 3 and 120),
  motivo text not null check (length(btrim(motivo)) >= 10),
  correlation_id text not null check (length(btrim(correlation_id)) >= 8),
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp()
);

create table public.prc_cenario_componentes (
  id bigint generated always as identity primary key,
  cenario_id bigint not null references public.prc_cenarios(id) on delete restrict,
  campo text not null check (campo in ('materia_prima','embalagem','custo_pontuacao_vendedor','custo_pontuacao_revenda','premiacao_revenda','premio_producao','frete','comissao','risco','marketing','tributacao')),
  valor numeric(20,8) not null check (valor >= 0),
  unidade text not null check (unidade in ('BRL_L','FRACAO')),
  source_kind text not null check (source_kind in ('system','substituicao_manual','fixture_validacao')),
  source_reference text not null check (length(btrim(source_reference)) >= 3),
  source_effective_date date not null,
  reason text not null check (length(btrim(reason)) >= 10),
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  unique(cenario_id,campo),
  check ((campo in ('comissao','risco','marketing','tributacao') and unidade='FRACAO' and valor < 1)
      or (campo not in ('comissao','risco','marketing','tributacao') and unidade='BRL_L'))
);

create table public.prc_calculos (
  id bigint generated always as identity primary key,
  cenario_id bigint not null references public.prc_cenarios(id) on delete restrict,
  politica_versao_id bigint not null references public.prc_politica_versoes(id) on delete restrict,
  politica_documento_sha256 text not null check (politica_documento_sha256 ~ '^[0-9a-f]{64}$'),
  metodo text not null check (metodo in ('margem_liquida','markup')),
  custo_base_exato numeric(30,12) not null,
  preco_vista_exato numeric(30,12) not null,
  preco_vista numeric(20,2) not null check (preco_vista > 0),
  cmv_percentual numeric(20,8) not null,
  contribuicao_liquida numeric(20,8) not null,
  intermediarios_json jsonb not null check (jsonb_typeof(intermediarios_json)='object'),
  arredondamento text not null check (arredondamento='HALF_UP'),
  casas_decimais integer not null check (casas_decimais=2),
  motivo text not null check (length(btrim(motivo)) >= 10),
  correlation_id text not null check (length(btrim(correlation_id)) >= 8),
  result_sha256 text not null check (result_sha256 ~ '^[0-9a-f]{64}$'),
  created_by uuid not null references public.user_profiles(id) on delete restrict,
  calculated_at timestamptz not null default clock_timestamp()
);

create table public.prc_calculo_componentes (
  id bigint generated always as identity primary key,
  calculo_id bigint not null references public.prc_calculos(id) on delete restrict,
  cenario_componente_id bigint not null references public.prc_cenario_componentes(id) on delete restrict,
  campo text not null,
  valor numeric(20,8) not null,
  unidade text not null,
  source_kind text not null,
  source_reference text not null,
  source_effective_date date not null,
  reason text not null,
  unique(calculo_id,campo)
);

create table public.prc_calculo_precos_prazo (
  id bigint generated always as identity primary key,
  calculo_id bigint not null references public.prc_calculos(id) on delete restrict,
  parcela_n integer not null check (parcela_n between 1 and 18),
  prazo_dias integer not null check (prazo_dias between 30 and 540 and prazo_dias % 30 = 0),
  preco_exato numeric(30,12) not null,
  preco numeric(20,2) not null check (preco > 0),
  unique(calculo_id,parcela_n), unique(calculo_id,prazo_dias),
  check (prazo_dias=parcela_n*30)
);

create table public.prc_calculo_decisoes (
  id bigint generated always as identity primary key,
  calculo_id bigint not null references public.prc_calculos(id) on delete restrict,
  decisao text not null check (decisao in ('APPROVED','REJECTED')),
  justificativa text not null check (length(btrim(justificativa)) >= 10),
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  unique(calculo_id)
);

create table public.prc_requisicoes (
  idempotency_key uuid primary key,
  request_type text not null check (request_type in ('policy','policy_review','scenario','calculation','calculation_review')),
  actor_id uuid not null references public.user_profiles(id) on delete restrict,
  payload_sha256 text not null check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  result_id bigint not null,
  created_at timestamptz not null default clock_timestamp()
);

create or replace function public.prevent_prc_fact_changes() returns trigger language plpgsql set search_path=public as $$
begin raise exception 'fato de formacao de custos e precos e append-only'; end; $$;

do $$ declare v_table text; begin
  foreach v_table in array array['prc_politicas','prc_politica_versoes','prc_politica_revisoes','prc_cenarios','prc_cenario_componentes','prc_calculos','prc_calculo_componentes','prc_calculo_precos_prazo','prc_calculo_decisoes','prc_requisicoes'] loop
    execute format('create trigger %I before update or delete on public.%I for each row execute function public.prevent_prc_fact_changes()', 'trg_'||v_table||'_append_only', v_table);
    execute format('create trigger %I before truncate on public.%I for each statement execute function public.prevent_prc_fact_changes()', 'trg_'||v_table||'_no_truncate', v_table);
    execute format('alter table public.%I enable row level security', v_table);
    execute format('revoke all on table public.%I from public, anon, authenticated', v_table);
  end loop;
end $$;

create or replace function public.prc_sha256(p_value jsonb) returns text language sql immutable set search_path=public as $$
  select encode(extensions.digest(convert_to(p_value::text,'UTF8'),'sha256'),'hex');
$$;

create or replace function public.prc_idempotent_result(p_key uuid,p_type text,p_payload jsonb)
returns bigint language plpgsql security definer set search_path=public as $$
declare v_req public.prc_requisicoes%rowtype; v_actor uuid:=public.current_actor_id(); v_hash text:=public.prc_sha256(p_payload);
begin
  if p_key is null then raise exception 'chave de idempotencia e obrigatoria'; end if;
  select * into v_req from public.prc_requisicoes where idempotency_key=p_key;
  if not found then return null; end if;
  if v_req.actor_id is distinct from v_actor or v_req.request_type<>p_type or v_req.payload_sha256<>v_hash then
    raise exception 'chave de idempotencia reutilizada com requisicao divergente';
  end if;
  return v_req.result_id;
end $$;

create or replace function public.salvar_prc_politica_versao_idempotente(p_key uuid,p_codigo text,p_nome text,p_metodo text,p_lucro_minimo numeric,p_markup numeric,p_juros_mensais numeric,p_motivo text)
returns bigint language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb; v_actor uuid; v_payload jsonb; v_existing bigint; v_policy public.prc_politicas%rowtype; v_version integer; v_doc jsonb; v_id bigint;
begin
  v_ctx:=public.begin_audited_rpc('precificacao.policy.manage','precificacao','prc_politica_versoes','change_type',jsonb_build_object('correlation_id',p_key::text)); v_actor:=public.current_actor_id();
  v_payload:=jsonb_build_object('codigo',upper(btrim(p_codigo)),'nome',btrim(p_nome),'metodo',p_metodo,'lucro_minimo',p_lucro_minimo,'markup',p_markup,'juros_mensais',p_juros_mensais,'motivo',btrim(p_motivo));
  v_existing:=public.prc_idempotent_result(p_key,'policy',v_payload); if v_existing is not null then return v_existing; end if;
  if p_metodo not in ('margem_liquida','markup') or p_juros_mensais is null or p_juros_mensais<0 or length(btrim(coalesce(p_motivo,'')))<10 then raise exception 'politica invalida'; end if;
  select * into v_policy from public.prc_politicas where codigo=upper(btrim(p_codigo));
  if not found then insert into public.prc_politicas(codigo,nome,created_by) values(upper(btrim(p_codigo)),btrim(p_nome),v_actor) returning * into v_policy;
  elsif v_policy.nome<>btrim(p_nome) then raise exception 'codigo de politica ja possui outro nome'; end if;
  perform pg_advisory_xact_lock(hashtextextended('prc-policy:'||v_policy.id::text,0));
  select coalesce(max(versao),0)+1 into v_version from public.prc_politica_versoes where politica_id=v_policy.id;
  v_doc:=jsonb_build_object('schema','prc-policy-v1','politica_id',v_policy.id,'codigo',v_policy.codigo,'nome',v_policy.nome,'versao',v_version,'metodo',p_metodo,'lucro_minimo',p_lucro_minimo,'markup',p_markup,'juros_mensais',p_juros_mensais,'arredondamento','HALF_UP','casas_decimais',2);
  insert into public.prc_politica_versoes(politica_id,versao,metodo,lucro_minimo,markup,juros_mensais,documento_json,documento_sha256,motivo,created_by)
  values(v_policy.id,v_version,p_metodo,p_lucro_minimo,p_markup,p_juros_mensais,v_doc,public.prc_sha256(v_doc),btrim(p_motivo),v_actor) returning id into v_id;
  insert into public.prc_requisicoes values(p_key,'policy',v_actor,public.prc_sha256(v_payload),v_id,clock_timestamp());
  perform public.log_audited_rpc_change('precificacao','prc_politica_versoes',v_id::text,'precificacao.politica_versao_criada','precificacao.policy.manage',v_ctx,null,v_doc,jsonb_build_object('motivo',btrim(p_motivo)),'database_rpc'); return v_id;
end $$;

create or replace function public.decidir_prc_politica_versao_idempotente(p_key uuid,p_versao_id bigint,p_decisao text,p_justificativa text)
returns bigint language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb; v_actor uuid; v_payload jsonb; v_existing bigint; v_version public.prc_politica_versoes%rowtype; v_id bigint;
begin
  v_ctx:=public.begin_audited_rpc('precificacao.policy.review','precificacao','prc_politica_revisoes','status_transition',jsonb_build_object('correlation_id',p_key::text)); v_actor:=public.current_actor_id();
  v_payload:=jsonb_build_object('versao_id',p_versao_id,'decisao',upper(p_decisao),'justificativa',btrim(p_justificativa)); v_existing:=public.prc_idempotent_result(p_key,'policy_review',v_payload); if v_existing is not null then return v_existing; end if;
  select * into v_version from public.prc_politica_versoes where id=p_versao_id; if not found then raise exception 'versao de politica inexistente'; end if;
  if v_version.created_by=v_actor then raise exception 'criador nao pode aprovar ou rejeitar a propria politica'; end if;
  if upper(p_decisao) not in ('APPROVED','REJECTED') or length(btrim(coalesce(p_justificativa,'')))<10 then raise exception 'decisao de politica invalida'; end if;
  insert into public.prc_politica_revisoes(politica_versao_id,decisao,justificativa,actor_id) values(p_versao_id,upper(p_decisao),btrim(p_justificativa),v_actor) returning id into v_id;
  insert into public.prc_requisicoes values(p_key,'policy_review',v_actor,public.prc_sha256(v_payload),v_id,clock_timestamp());
  perform public.log_audited_rpc_change('precificacao','prc_politica_revisoes',v_id::text,'precificacao.politica_revisada','precificacao.policy.review',v_ctx,null,jsonb_build_object('decisao',upper(p_decisao)),jsonb_build_object('politica_versao_id',p_versao_id,'justificativa',btrim(p_justificativa)),'database_rpc'); return v_id;
end $$;

create or replace function public.criar_prc_cenario_idempotente(p_key uuid,p_politica_versao_id bigint,p_produto_embalagem_id bigint,p_nome text,p_motivo text,p_componentes jsonb)
returns bigint language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb; v_actor uuid; v_payload jsonb; v_existing bigint; v_id bigint; v_item jsonb; v_count integer:=0; v_expected text[]:=array['materia_prima','embalagem','custo_pontuacao_vendedor','custo_pontuacao_revenda','premiacao_revenda','premio_producao','frete','comissao','risco','marketing','tributacao']; v_field text; v_unit text; v_source text;
begin
  v_ctx:=public.begin_audited_rpc('precificacao.scenario.manage','precificacao','prc_cenarios','field_risk',jsonb_build_object('correlation_id',p_key::text)); v_actor:=public.current_actor_id();
  v_payload:=jsonb_build_object('politica_versao_id',p_politica_versao_id,'produto_embalagem_id',p_produto_embalagem_id,'nome',btrim(p_nome),'motivo',btrim(p_motivo),'componentes',p_componentes); v_existing:=public.prc_idempotent_result(p_key,'scenario',v_payload); if v_existing is not null then return v_existing; end if;
  if not exists(select 1 from public.prc_politica_revisoes where politica_versao_id=p_politica_versao_id and decisao='APPROVED') then raise exception 'politica precisa estar aprovada'; end if;
  if not exists(select 1 from public.cad_produto_embalagens where id=p_produto_embalagem_id) then raise exception 'apresentacao inexistente'; end if;
  if jsonb_typeof(p_componentes)<>'array' or jsonb_array_length(p_componentes)<>11 or length(btrim(coalesce(p_motivo,'')))<10 then raise exception 'cenario exige os 11 componentes e motivo'; end if;
  insert into public.prc_cenarios(politica_versao_id,produto_embalagem_id,nome,motivo,correlation_id,created_by) values(p_politica_versao_id,p_produto_embalagem_id,btrim(p_nome),btrim(p_motivo),p_key::text,v_actor) returning id into v_id;
  for v_item in select value from jsonb_array_elements(p_componentes) loop
    v_field:=v_item->>'campo'; v_unit:=v_item->>'unidade'; v_source:=v_item->>'source_kind';
    if not (v_field=any(v_expected)) or (v_item->>'valor') is null or (v_item->>'valor')::numeric<0 then raise exception 'componente invalido ou ausente'; end if;
    if (v_field=any(array['comissao','risco','marketing','tributacao']) and (v_unit<>'FRACAO' or (v_item->>'valor')::numeric>=1))
       or (not (v_field=any(array['comissao','risco','marketing','tributacao'])) and v_unit<>'BRL_L') then raise exception 'unidade de componente incompativel'; end if;
    if v_source not in ('system','substituicao_manual','fixture_validacao') or length(btrim(coalesce(v_item->>'source_reference','')))<3 or nullif(v_item->>'source_effective_date','') is null or length(btrim(coalesce(v_item->>'reason','')))<10 then raise exception 'fonte de componente incompleta'; end if;
    insert into public.prc_cenario_componentes(cenario_id,campo,valor,unidade,source_kind,source_reference,source_effective_date,reason,actor_id)
    values(v_id,v_field,(v_item->>'valor')::numeric,v_unit,v_source,btrim(v_item->>'source_reference'),(v_item->>'source_effective_date')::date,btrim(v_item->>'reason'),v_actor); v_count:=v_count+1;
  end loop;
  if v_count<>11 then raise exception 'cenario incompleto'; end if;
  insert into public.prc_requisicoes values(p_key,'scenario',v_actor,public.prc_sha256(v_payload),v_id,clock_timestamp());
  perform public.log_audited_rpc_change('precificacao','prc_cenarios',v_id::text,'precificacao.cenario_criado','precificacao.scenario.manage',v_ctx,null,jsonb_build_object('politica_versao_id',p_politica_versao_id,'produto_embalagem_id',p_produto_embalagem_id,'componentes',v_count),jsonb_build_object('motivo',btrim(p_motivo)),'database_rpc'); return v_id;
end $$;

create or replace function public.calcular_prc_cenario_idempotente(p_key uuid,p_cenario_id bigint,p_motivo text)
returns bigint language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb; v_actor uuid; v_payload jsonb; v_existing bigint; v_s public.prc_cenarios%rowtype; v_p public.prc_politica_versoes%rowtype; v_base numeric; v_comm numeric; v_tax numeric; v_marketing numeric; v_risk numeric; v_den numeric; v_cash_exact numeric; v_cash numeric; v_cmv numeric; v_contrib numeric; v_doc jsonb; v_hash text; v_id bigint; v_exact numeric; v_component public.prc_cenario_componentes%rowtype;
begin
  v_ctx:=public.begin_audited_rpc('precificacao.calculate','precificacao','prc_calculos','field_risk',jsonb_build_object('correlation_id',p_key::text)); v_actor:=public.current_actor_id();
  v_payload:=jsonb_build_object('cenario_id',p_cenario_id,'motivo',btrim(p_motivo)); v_existing:=public.prc_idempotent_result(p_key,'calculation',v_payload); if v_existing is not null then return v_existing; end if;
  select * into v_s from public.prc_cenarios where id=p_cenario_id; if not found then raise exception 'cenario inexistente'; end if;
  select * into v_p from public.prc_politica_versoes where id=v_s.politica_versao_id; if not found or not exists(select 1 from public.prc_politica_revisoes where politica_versao_id=v_p.id and decisao='APPROVED') then raise exception 'politica aprovada ausente'; end if;
  if (select count(*) from public.prc_cenario_componentes where cenario_id=p_cenario_id)<>11 then raise exception 'componente ausente bloqueia calculo'; end if;
  select sum(valor) filter(where campo in ('materia_prima','embalagem','custo_pontuacao_vendedor','custo_pontuacao_revenda','premiacao_revenda','premio_producao','frete')),
    max(valor) filter(where campo='comissao'),max(valor) filter(where campo='tributacao'),max(valor) filter(where campo='marketing'),max(valor) filter(where campo='risco')
    into v_base,v_comm,v_tax,v_marketing,v_risk from public.prc_cenario_componentes where cenario_id=p_cenario_id;
  if v_base is null or v_comm is null or v_tax is null or v_marketing is null or v_risk is null then raise exception 'fonte ausente bloqueia calculo'; end if;
  v_den:=1-v_comm-v_tax-v_marketing-case when v_p.metodo='margem_liquida' then v_p.lucro_minimo else 0 end; if v_den<=0 then raise exception 'denominador deve ser positivo'; end if;
  if v_p.metodo='margem_liquida' then v_cash_exact:=v_base/v_den; else v_cash_exact:=v_base*(1+v_p.markup)/(1-v_comm-v_tax-v_marketing); end if;
  v_cash:=round(v_cash_exact,2); v_cmv:=round(((select sum(valor) from public.prc_cenario_componentes where cenario_id=p_cenario_id and campo in ('materia_prima','embalagem'))/v_cash)*100,8);
  v_contrib:=round(v_cash-v_base-(v_cash*v_comm)-(v_cash*v_tax)-(v_cash*v_marketing),8);
  v_doc:=jsonb_build_object('schema','prc-calculation-v1','cenario_id',p_cenario_id,'politica_documento_sha256',v_p.documento_sha256,'metodo',v_p.metodo,'custo_base_exato',v_base::text,'preco_vista_exato',v_cash_exact::text,'preco_vista',v_cash::text,'cmv_percentual',v_cmv::text,'contribuicao_liquida',v_contrib::text,'arredondamento','HALF_UP','casas_decimais',2);
  v_hash:=public.prc_sha256(v_doc);
  insert into public.prc_calculos(cenario_id,politica_versao_id,politica_documento_sha256,metodo,custo_base_exato,preco_vista_exato,preco_vista,cmv_percentual,contribuicao_liquida,intermediarios_json,arredondamento,casas_decimais,motivo,correlation_id,result_sha256,created_by)
  values(p_cenario_id,v_p.id,v_p.documento_sha256,v_p.metodo,v_base,v_cash_exact,v_cash,v_cmv,v_contrib,v_doc,'HALF_UP',2,btrim(p_motivo),p_key::text,v_hash,v_actor) returning id into v_id;
  for v_component in select * from public.prc_cenario_componentes where cenario_id=p_cenario_id order by campo loop insert into public.prc_calculo_componentes(calculo_id,cenario_componente_id,campo,valor,unidade,source_kind,source_reference,source_effective_date,reason) values(v_id,v_component.id,v_component.campo,v_component.valor,v_component.unidade,v_component.source_kind,v_component.source_reference,v_component.source_effective_date,v_component.reason); end loop;
  for v_n in 1..18 loop v_exact:=v_cash + v_cash*(((1+v_p.juros_mensais)^v_n-1)+v_risk)/(1-v_comm-v_tax-v_marketing); insert into public.prc_calculo_precos_prazo(calculo_id,parcela_n,prazo_dias,preco_exato,preco) values(v_id,v_n,v_n*30,v_exact,round(v_exact,2)); end loop;
  insert into public.prc_requisicoes values(p_key,'calculation',v_actor,public.prc_sha256(v_payload),v_id,clock_timestamp());
  perform public.log_audited_rpc_change('precificacao','prc_calculos',v_id::text,'precificacao.calculo_registrado','precificacao.calculate',v_ctx,null,v_doc,jsonb_build_object('motivo',btrim(p_motivo),'result_sha256',v_hash),'database_rpc'); return v_id;
end $$;

create or replace function public.decidir_prc_calculo_idempotente(p_key uuid,p_calculo_id bigint,p_decisao text,p_justificativa text)
returns bigint language plpgsql security definer set search_path=public as $$
declare v_ctx jsonb; v_actor uuid; v_payload jsonb; v_existing bigint; v_calc public.prc_calculos%rowtype; v_s public.prc_cenarios%rowtype; v_id bigint;
begin
  v_ctx:=public.begin_audited_rpc('precificacao.calculation.review','precificacao','prc_calculo_decisoes','status_transition',jsonb_build_object('correlation_id',p_key::text)); v_actor:=public.current_actor_id();
  v_payload:=jsonb_build_object('calculo_id',p_calculo_id,'decisao',upper(p_decisao),'justificativa',btrim(p_justificativa)); v_existing:=public.prc_idempotent_result(p_key,'calculation_review',v_payload); if v_existing is not null then return v_existing; end if;
  select * into v_calc from public.prc_calculos where id=p_calculo_id; if not found then raise exception 'calculo inexistente'; end if; select * into v_s from public.prc_cenarios where id=v_calc.cenario_id;
  if v_actor=v_calc.created_by or v_actor=v_s.created_by then raise exception 'criador do cenario ou calculo nao pode aprovar o proprio calculo'; end if;
  if upper(p_decisao) not in ('APPROVED','REJECTED') or length(btrim(coalesce(p_justificativa,'')))<10 then raise exception 'decisao de calculo invalida'; end if;
  insert into public.prc_calculo_decisoes(calculo_id,decisao,justificativa,actor_id) values(p_calculo_id,upper(p_decisao),btrim(p_justificativa),v_actor) returning id into v_id;
  insert into public.prc_requisicoes values(p_key,'calculation_review',v_actor,public.prc_sha256(v_payload),v_id,clock_timestamp());
  perform public.log_audited_rpc_change('precificacao','prc_calculo_decisoes',v_id::text,'precificacao.calculo_revisado','precificacao.calculation.review',v_ctx,null,jsonb_build_object('decisao',upper(p_decisao)),jsonb_build_object('calculo_id',p_calculo_id,'justificativa',btrim(p_justificativa)),'database_rpc'); return v_id;
end $$;

create or replace function public.consultar_prc_workspace() returns jsonb language plpgsql security definer set search_path=public as $$
begin
  perform public.begin_audited_rpc('precificacao.view','precificacao','prc_workspace','own_any','{}'::jsonb);
  return jsonb_build_object(
    'politicas',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'codigo',p.codigo,'nome',p.nome,'versoes',(select coalesce(jsonb_agg(jsonb_build_object('id',v.id,'versao',v.versao,'metodo',v.metodo,'juros_mensais',v.juros_mensais,'documento_sha256',v.documento_sha256,'status',coalesce(r.decisao,'PENDING'),'created_at',v.created_at) order by v.versao desc),'[]'::jsonb) from public.prc_politica_versoes v left join public.prc_politica_revisoes r on r.politica_versao_id=v.id where v.politica_id=p.id)) order by p.codigo) from public.prc_politicas p),'[]'::jsonb),
    'cenarios',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'nome',s.nome,'produto_embalagem_id',s.produto_embalagem_id,'politica_versao_id',s.politica_versao_id,'motivo',s.motivo,'created_at',s.created_at,'componentes',(select jsonb_agg(to_jsonb(c) order by c.campo) from public.prc_cenario_componentes c where c.cenario_id=s.id),'calculos',(select coalesce(jsonb_agg(jsonb_build_object('id',k.id,'metodo',k.metodo,'preco_vista',k.preco_vista,'cmv_percentual',k.cmv_percentual,'contribuicao_liquida',k.contribuicao_liquida,'result_sha256',k.result_sha256,'status',coalesce(d.decisao,'PENDING'),'calculated_at',k.calculated_at,'prazos',(select jsonb_agg(jsonb_build_object('prazo_dias',t.prazo_dias,'preco',t.preco) order by t.prazo_dias) from public.prc_calculo_precos_prazo t where t.calculo_id=k.id)) order by k.id desc),'[]'::jsonb) from public.prc_calculos k left join public.prc_calculo_decisoes d on d.calculo_id=k.id where k.cenario_id=s.id)) order by s.id desc) from public.prc_cenarios s),'[]'::jsonb),
    'apresentacoes',coalesce((select jsonb_agg(jsonb_build_object('id',pe.id,'codigo',pe.codigo_item,'produto',p.nome,'apresentacao',e.descricao) order by p.nome,e.descricao) from public.cad_produto_embalagens pe join public.cad_produtos_base p on p.id=pe.produto_id join public.cad_embalagens e on e.id=pe.embalagem_id where pe.status='active'),'[]'::jsonb),
    'publication_enabled',false
  );
end $$;

revoke all on function public.prevent_prc_fact_changes() from public,anon,authenticated;
revoke all on function public.prc_sha256(jsonb) from public,anon,authenticated;
revoke all on function public.prc_idempotent_result(uuid,text,jsonb) from public,anon,authenticated;
revoke all on function public.salvar_prc_politica_versao_idempotente(uuid,text,text,text,numeric,numeric,numeric,text) from public,anon;
revoke all on function public.decidir_prc_politica_versao_idempotente(uuid,bigint,text,text) from public,anon;
revoke all on function public.criar_prc_cenario_idempotente(uuid,bigint,bigint,text,text,jsonb) from public,anon;
revoke all on function public.calcular_prc_cenario_idempotente(uuid,bigint,text) from public,anon;
revoke all on function public.decidir_prc_calculo_idempotente(uuid,bigint,text,text) from public,anon;
revoke all on function public.consultar_prc_workspace() from public,anon;
grant execute on function public.salvar_prc_politica_versao_idempotente(uuid,text,text,text,numeric,numeric,numeric,text) to authenticated;
grant execute on function public.decidir_prc_politica_versao_idempotente(uuid,bigint,text,text) to authenticated;
grant execute on function public.criar_prc_cenario_idempotente(uuid,bigint,bigint,text,text,jsonb) to authenticated;
grant execute on function public.calcular_prc_cenario_idempotente(uuid,bigint,text) to authenticated;
grant execute on function public.decidir_prc_calculo_idempotente(uuid,bigint,text,text) to authenticated;
grant execute on function public.consultar_prc_workspace() to authenticated;

comment on function public.consultar_prc_workspace() is 'Dossie governado PRC-01; nao publica lista comercial nem executa pagamento.';
