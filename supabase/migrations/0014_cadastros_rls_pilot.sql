insert into public.permission_actions(action_key, module, description, default_allowed, sort_order)
values
  ('cadastros.clientes.create', 'cadastros', 'Criar clientes', true, 63),
  ('cadastros.pessoas.create', 'cadastros', 'Criar pessoas comerciais', true, 64),
  ('cadastros.materias_primas.create', 'cadastros', 'Criar materias-primas', true, 65),
  ('cadastros.produtos.create', 'cadastros', 'Criar produtos base PA/PI', true, 66),
  ('cadastros.produtos.validity.set', 'cadastros', 'Definir prazo de validade do produto', true, 67),
  ('cadastros.embalagens.create', 'cadastros', 'Criar embalagens', true, 68),
  ('cadastros.produto_embalagens.create', 'cadastros', 'Criar item vendavel produto + embalagem', true, 69),
  ('cadastros.conversoes_unidade_mp.create', 'cadastros', 'Criar conversao de unidade de MP', true, 70)
on conflict (action_key) do update set
  module = excluded.module,
  description = excluded.description,
  default_allowed = excluded.default_allowed,
  sort_order = excluded.sort_order;

drop policy if exists "authenticated full master data access" on public.cad_clientes;
drop policy if exists "authenticated full property access" on public.cad_cliente_propriedades;
drop policy if exists "authenticated full document access" on public.cad_cliente_documentos;
drop policy if exists "authenticated full contact access" on public.cad_cliente_contatos;
drop policy if exists "authenticated full commercial person access" on public.cad_pessoas_comerciais;
drop policy if exists "authenticated full alias access" on public.cad_pessoa_aliases;
drop policy if exists "authenticated full client seller access" on public.cad_cliente_vendedores;
drop policy if exists "authenticated full raw material access" on public.cad_materias_primas;
drop policy if exists "authenticated full unit conversion access" on public.cad_conversoes_unidade_mp;
drop policy if exists "authenticated full product access" on public.cad_produtos_base;
drop policy if exists "authenticated full package access" on public.cad_embalagens;
drop policy if exists "authenticated full product package access" on public.cad_produto_embalagens;
drop policy if exists "authenticated full vehicle access" on public.cad_veiculos;
drop policy if exists "authenticated full product guarantee access" on public.cad_garantias_produto_mapa;
drop policy if exists "authenticated full mp lot guarantee access" on public.cad_garantias_lote_mp;
drop policy if exists "authenticated full credit limit access" on public.cad_limites_credito_cliente;
drop policy if exists "authenticated full validation issue access" on public.cadastro_validation_issues;
drop policy if exists "authenticated full commercial area access" on public.cad_areas_comerciais;
drop policy if exists "authenticated full commercial area membership access" on public.cad_pessoa_areas_comerciais;

drop policy if exists "authenticated read cad_clientes" on public.cad_clientes;
drop policy if exists "authenticated read cad_cliente_propriedades" on public.cad_cliente_propriedades;
drop policy if exists "authenticated read cad_cliente_documentos" on public.cad_cliente_documentos;
drop policy if exists "authenticated read cad_cliente_contatos" on public.cad_cliente_contatos;
drop policy if exists "authenticated read cad_pessoas_comerciais" on public.cad_pessoas_comerciais;
drop policy if exists "authenticated read cad_pessoa_aliases" on public.cad_pessoa_aliases;
drop policy if exists "authenticated read cad_cliente_vendedores" on public.cad_cliente_vendedores;
drop policy if exists "authenticated read cad_materias_primas" on public.cad_materias_primas;
drop policy if exists "authenticated read cad_conversoes_unidade_mp" on public.cad_conversoes_unidade_mp;
drop policy if exists "authenticated read cad_produtos_base" on public.cad_produtos_base;
drop policy if exists "authenticated read cad_embalagens" on public.cad_embalagens;
drop policy if exists "authenticated read cad_produto_embalagens" on public.cad_produto_embalagens;
drop policy if exists "authenticated read cad_veiculos" on public.cad_veiculos;
drop policy if exists "authenticated read cad_garantias_produto_mapa" on public.cad_garantias_produto_mapa;
drop policy if exists "authenticated read cad_garantias_lote_mp" on public.cad_garantias_lote_mp;
drop policy if exists "authenticated read cad_limites_credito_cliente" on public.cad_limites_credito_cliente;
drop policy if exists "authenticated read cadastro_validation_issues" on public.cadastro_validation_issues;
drop policy if exists "authenticated read cad_areas_comerciais" on public.cad_areas_comerciais;
drop policy if exists "authenticated read cad_pessoa_areas_comerciais" on public.cad_pessoa_areas_comerciais;

create policy "authenticated read cad_clientes" on public.cad_clientes
for select to authenticated using (public.current_actor_id() is not null);
create policy "authenticated read cad_cliente_propriedades" on public.cad_cliente_propriedades
for select to authenticated using (public.current_actor_id() is not null);
create policy "authenticated read cad_cliente_documentos" on public.cad_cliente_documentos
for select to authenticated using (public.current_actor_id() is not null);
create policy "authenticated read cad_cliente_contatos" on public.cad_cliente_contatos
for select to authenticated using (public.current_actor_id() is not null);
create policy "authenticated read cad_pessoas_comerciais" on public.cad_pessoas_comerciais
for select to authenticated using (public.current_actor_id() is not null);
create policy "authenticated read cad_pessoa_aliases" on public.cad_pessoa_aliases
for select to authenticated using (public.current_actor_id() is not null);
create policy "authenticated read cad_cliente_vendedores" on public.cad_cliente_vendedores
for select to authenticated using (public.current_actor_id() is not null);
create policy "authenticated read cad_materias_primas" on public.cad_materias_primas
for select to authenticated using (public.current_actor_id() is not null);
create policy "authenticated read cad_conversoes_unidade_mp" on public.cad_conversoes_unidade_mp
for select to authenticated using (public.current_actor_id() is not null);
create policy "authenticated read cad_produtos_base" on public.cad_produtos_base
for select to authenticated using (public.current_actor_id() is not null);
create policy "authenticated read cad_embalagens" on public.cad_embalagens
for select to authenticated using (public.current_actor_id() is not null);
create policy "authenticated read cad_produto_embalagens" on public.cad_produto_embalagens
for select to authenticated using (public.current_actor_id() is not null);
create policy "authenticated read cad_veiculos" on public.cad_veiculos
for select to authenticated using (public.current_actor_id() is not null);
create policy "authenticated read cad_garantias_produto_mapa" on public.cad_garantias_produto_mapa
for select to authenticated using (public.current_actor_id() is not null);
create policy "authenticated read cad_garantias_lote_mp" on public.cad_garantias_lote_mp
for select to authenticated using (public.current_actor_id() is not null);
create policy "authenticated read cad_limites_credito_cliente" on public.cad_limites_credito_cliente
for select to authenticated using (public.current_actor_id() is not null);
create policy "authenticated read cadastro_validation_issues" on public.cadastro_validation_issues
for select to authenticated using (public.current_actor_id() is not null);
create policy "authenticated read cad_areas_comerciais" on public.cad_areas_comerciais
for select to authenticated using (public.current_actor_id() is not null);
create policy "authenticated read cad_pessoa_areas_comerciais" on public.cad_pessoa_areas_comerciais
for select to authenticated using (public.current_actor_id() is not null);

grant select on
  public.cad_clientes,
  public.cad_cliente_propriedades,
  public.cad_cliente_documentos,
  public.cad_cliente_contatos,
  public.cad_pessoas_comerciais,
  public.cad_pessoa_aliases,
  public.cad_cliente_vendedores,
  public.cad_materias_primas,
  public.cad_conversoes_unidade_mp,
  public.cad_produtos_base,
  public.cad_embalagens,
  public.cad_produto_embalagens,
  public.cad_veiculos,
  public.cad_garantias_produto_mapa,
  public.cad_garantias_lote_mp,
  public.cad_limites_credito_cliente,
  public.cadastro_validation_issues,
  public.cad_areas_comerciais,
  public.cad_pessoa_areas_comerciais
to authenticated;

revoke insert, update, delete on
  public.cad_clientes,
  public.cad_cliente_propriedades,
  public.cad_cliente_documentos,
  public.cad_cliente_contatos,
  public.cad_pessoas_comerciais,
  public.cad_pessoa_aliases,
  public.cad_cliente_vendedores,
  public.cad_materias_primas,
  public.cad_conversoes_unidade_mp,
  public.cad_produtos_base,
  public.cad_embalagens,
  public.cad_produto_embalagens,
  public.cad_veiculos,
  public.cad_garantias_produto_mapa,
  public.cad_garantias_lote_mp,
  public.cad_limites_credito_cliente,
  public.cadastro_validation_issues,
  public.cad_areas_comerciais,
  public.cad_pessoa_areas_comerciais
from authenticated;

create or replace function public.create_cad_cliente(
  p_nome text,
  p_nome_norm text,
  p_cidade text,
  p_uf text,
  p_status text default 'active',
  p_codigo_legado text default null,
  p_apelidos_json jsonb default '[]'::jsonb,
  p_payload_origem_json jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_cliente_id bigint;
begin
  perform public.require_current_user_permission('cadastros.clientes.create');
  if nullif(trim(p_nome), '') is null then
    raise exception 'nome is required';
  end if;
  if nullif(trim(p_cidade), '') is null then
    raise exception 'cidade is required';
  end if;
  if char_length(trim(p_uf)) <> 2 then
    raise exception 'uf must have exactly two letters';
  end if;
  if p_status not in ('active', 'inactive', 'pending_review') then
    raise exception 'invalid status';
  end if;

  v_actor := public.current_actor_id();

  insert into public.cad_clientes(
    codigo_legado,
    nome,
    nome_norm,
    cidade,
    uf,
    status,
    apelidos_json,
    payload_origem_json,
    created_by,
    updated_by
  )
  values (
    nullif(trim(p_codigo_legado), ''),
    trim(p_nome),
    trim(p_nome_norm),
    trim(p_cidade),
    upper(trim(p_uf)),
    p_status,
    coalesce(p_apelidos_json, '[]'::jsonb),
    coalesce(p_payload_origem_json, '{}'::jsonb),
    v_actor,
    v_actor
  )
  returning id into v_cliente_id;

  perform public.log_audit_event(
    'cadastros',
    'cad_clientes',
    v_cliente_id::text,
    'cadastros.cliente_created',
    'cadastros.clientes.create',
    'success',
    null,
    jsonb_build_object('nome', trim(p_nome), 'cidade', trim(p_cidade), 'uf', upper(trim(p_uf)), 'status', p_status),
    jsonb_build_object('alcada_usada', 'cadastros.clientes.create'),
    'database_rpc',
    jsonb_build_object('source', 'create_cad_cliente')
  );

  return v_cliente_id;
end;
$$;

create or replace function public.create_cad_pessoa_comercial(
  p_nome text,
  p_nome_norm text,
  p_papeis_json jsonb,
  p_status text default 'active',
  p_tipo_comercial text default null,
  p_codigo_legado text default null,
  p_vendedor_responsavel_id bigint default null,
  p_apelidos_json jsonb default '[]'::jsonb,
  p_grafias_incorretas_json jsonb default '[]'::jsonb,
  p_payload_origem_json jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_pessoa_id bigint;
  v_alias text;
begin
  perform public.require_current_user_permission('cadastros.pessoas.create');
  if nullif(trim(p_nome), '') is null then
    raise exception 'nome is required';
  end if;
  if p_papeis_json is null or jsonb_array_length(p_papeis_json) = 0 then
    raise exception 'papeis_json must have at least one item';
  end if;
  if p_status not in ('active', 'inactive', 'pending_review') then
    raise exception 'invalid status';
  end if;
  if p_tipo_comercial is not null and p_tipo_comercial not in (
    'funcionario_elite',
    'agente_vinculado',
    'agente_direto_elite',
    'vendedor_direto_elite',
    'tecnico_campo',
    'entregador',
    'gerente',
    'vendedor_gerente'
  ) then
    raise exception 'invalid tipo_comercial';
  end if;
  if p_tipo_comercial = 'agente_vinculado' and p_vendedor_responsavel_id is null then
    raise exception 'vendedor_responsavel_id is required';
  end if;

  v_actor := public.current_actor_id();

  insert into public.cad_pessoas_comerciais(
    codigo_legado,
    nome,
    nome_norm,
    tipo_comercial,
    papeis_json,
    status,
    vendedor_responsavel_id,
    apelidos_json,
    grafias_incorretas_json,
    payload_origem_json,
    created_by,
    updated_by
  )
  values (
    nullif(trim(p_codigo_legado), ''),
    trim(p_nome),
    trim(p_nome_norm),
    p_tipo_comercial,
    p_papeis_json,
    p_status,
    p_vendedor_responsavel_id,
    coalesce(p_apelidos_json, '[]'::jsonb),
    coalesce(p_grafias_incorretas_json, '[]'::jsonb),
    coalesce(p_payload_origem_json, '{}'::jsonb),
    v_actor,
    v_actor
  )
  returning id into v_pessoa_id;

  insert into public.cad_pessoa_aliases(pessoa_id, alias, alias_norm, tipo)
  values (v_pessoa_id, trim(p_nome), trim(p_nome_norm), 'nome');

  for v_alias in select jsonb_array_elements_text(coalesce(p_apelidos_json, '[]'::jsonb))
  loop
    insert into public.cad_pessoa_aliases(pessoa_id, alias, alias_norm, tipo)
    values (v_pessoa_id, trim(v_alias), upper(trim(v_alias)), 'apelido');
  end loop;

  for v_alias in select jsonb_array_elements_text(coalesce(p_grafias_incorretas_json, '[]'::jsonb))
  loop
    insert into public.cad_pessoa_aliases(pessoa_id, alias, alias_norm, tipo)
    values (v_pessoa_id, trim(v_alias), upper(trim(v_alias)), 'grafia_incorreta');
  end loop;

  perform public.log_audit_event(
    'cadastros',
    'cad_pessoas_comerciais',
    v_pessoa_id::text,
    'cadastros.pessoa_comercial_created',
    'cadastros.pessoas.create',
    'success',
    null,
    jsonb_build_object('nome', trim(p_nome), 'tipo_comercial', p_tipo_comercial, 'status', p_status, 'papeis', p_papeis_json),
    jsonb_build_object('alcada_usada', 'cadastros.pessoas.create'),
    'database_rpc',
    jsonb_build_object('source', 'create_cad_pessoa_comercial')
  );

  return v_pessoa_id;
end;
$$;

create or replace function public.create_cad_materia_prima(
  p_nome text,
  p_nome_norm text,
  p_sku_corrigido text,
  p_unidade_base_estoque text,
  p_status text default 'active',
  p_codigo_legado text default null,
  p_tipo text default null,
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
  v_materia_prima_id bigint;
begin
  perform public.require_current_user_permission('cadastros.materias_primas.create');
  if nullif(trim(p_nome), '') is null then
    raise exception 'nome is required';
  end if;
  if nullif(trim(p_sku_corrigido), '') is null then
    raise exception 'sku_corrigido is required';
  end if;
  if nullif(trim(p_unidade_base_estoque), '') is null then
    raise exception 'unidade_base_estoque is required';
  end if;
  if p_status not in ('active', 'inactive', 'pending_review') then
    raise exception 'invalid status';
  end if;
  if p_densidade is not null and p_densidade <= 0 then
    raise exception 'densidade must be greater than zero';
  end if;
  if p_estoque_minimo is not null and p_estoque_minimo < 0 then
    raise exception 'estoque_minimo must be greater than or equal to zero';
  end if;

  v_actor := public.current_actor_id();

  insert into public.cad_materias_primas(
    codigo_legado,
    sku_corrigido,
    nome,
    nome_norm,
    unidade_base_estoque,
    status,
    tipo,
    densidade,
    estoque_minimo,
    ncm,
    ibama,
    codigo_ads,
    payload_origem_json,
    created_by,
    updated_by
  )
  values (
    nullif(trim(p_codigo_legado), ''),
    upper(trim(p_sku_corrigido)),
    trim(p_nome),
    trim(p_nome_norm),
    upper(trim(p_unidade_base_estoque)),
    p_status,
    nullif(trim(p_tipo), ''),
    p_densidade,
    p_estoque_minimo,
    nullif(trim(p_ncm), ''),
    nullif(trim(p_ibama), ''),
    nullif(trim(p_codigo_ads), ''),
    coalesce(p_payload_origem_json, '{}'::jsonb),
    v_actor,
    v_actor
  )
  returning id into v_materia_prima_id;

  perform public.log_audit_event(
    'cadastros',
    'cad_materias_primas',
    v_materia_prima_id::text,
    'cadastros.materia_prima_created',
    'cadastros.materias_primas.create',
    'success',
    null,
    jsonb_build_object('nome', trim(p_nome), 'sku_corrigido', upper(trim(p_sku_corrigido)), 'unidade_base_estoque', upper(trim(p_unidade_base_estoque)), 'status', p_status),
    jsonb_build_object('alcada_usada', 'cadastros.materias_primas.create'),
    'database_rpc',
    jsonb_build_object('source', 'create_cad_materia_prima')
  );

  return v_materia_prima_id;
end;
$$;

create or replace function public.create_cad_produto_base(
  p_codigo_produto text,
  p_nome text,
  p_nome_norm text,
  p_status text default 'active',
  p_grupo text default null,
  p_densidade_kg_l numeric default null,
  p_reg_mapa text default null,
  p_ncm text default null,
  p_ibama text default null,
  p_ads text default null,
  p_payload_origem_json jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_produto_id bigint;
begin
  perform public.require_current_user_permission('cadastros.produtos.create');
  if nullif(trim(p_codigo_produto), '') is null then
    raise exception 'codigo_produto is required';
  end if;
  if nullif(trim(p_nome), '') is null then
    raise exception 'nome is required';
  end if;
  if p_status not in ('active', 'inactive', 'pending_review') then
    raise exception 'invalid status';
  end if;
  if p_densidade_kg_l is not null and p_densidade_kg_l <= 0 then
    raise exception 'densidade_kg_l must be greater than zero';
  end if;

  v_actor := public.current_actor_id();

  insert into public.cad_produtos_base(
    codigo_produto,
    nome,
    nome_norm,
    status,
    grupo,
    densidade_kg_l,
    reg_mapa,
    ncm,
    ibama,
    ads,
    payload_origem_json,
    created_by,
    updated_by
  )
  values (
    upper(trim(p_codigo_produto)),
    trim(p_nome),
    trim(p_nome_norm),
    p_status,
    nullif(trim(p_grupo), ''),
    p_densidade_kg_l,
    nullif(trim(p_reg_mapa), ''),
    nullif(trim(p_ncm), ''),
    nullif(trim(p_ibama), ''),
    nullif(trim(p_ads), ''),
    coalesce(p_payload_origem_json, '{}'::jsonb),
    v_actor,
    v_actor
  )
  returning id into v_produto_id;

  perform public.log_audit_event(
    'cadastros',
    'cad_produtos_base',
    v_produto_id::text,
    'cadastros.produto_base_created',
    'cadastros.produtos.create',
    'success',
    null,
    jsonb_build_object('codigo_produto', upper(trim(p_codigo_produto)), 'nome', trim(p_nome), 'status', p_status),
    jsonb_build_object('alcada_usada', 'cadastros.produtos.create'),
    'database_rpc',
    jsonb_build_object('source', 'create_cad_produto_base')
  );

  return v_produto_id;
end;
$$;

create or replace function public.set_cad_produto_prazo_validade(
  p_produto_id bigint,
  p_prazo_validade_meses integer,
  p_motivo text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_before jsonb;
begin
  perform public.require_current_user_permission('cadastros.produtos.validity.set');
  if p_produto_id is null or p_produto_id <= 0 then
    raise exception 'produto_id is required';
  end if;
  if p_prazo_validade_meses is not null and (p_prazo_validade_meses < 1 or p_prazo_validade_meses > 240) then
    raise exception 'prazo_validade_meses must be between 1 and 240';
  end if;
  if nullif(trim(p_motivo), '') is null then
    raise exception 'motivo is required';
  end if;

  select jsonb_build_object('prazo_validade_meses', prazo_validade_meses, 'updated_at', updated_at)
    into v_before
    from public.cad_produtos_base
   where id = p_produto_id
   for update;

  if not found then
    raise exception 'produto not found';
  end if;

  v_actor := public.current_actor_id();

  update public.cad_produtos_base
     set prazo_validade_meses = p_prazo_validade_meses,
         updated_by = v_actor
   where id = p_produto_id;

  perform public.log_audit_event(
    'cadastros',
    'cad_produtos_base',
    p_produto_id::text,
    'cadastros.produto_prazo_validade_set',
    'cadastros.produtos.validity.set',
    'success',
    v_before,
    jsonb_build_object('prazo_validade_meses', p_prazo_validade_meses, 'motivo', trim(p_motivo)),
    jsonb_build_object('alcada_usada', 'cadastros.produtos.validity.set'),
    'database_rpc',
    jsonb_build_object('source', 'set_cad_produto_prazo_validade')
  );

  return p_produto_id;
end;
$$;

create or replace function public.create_cad_embalagem(
  p_descricao text,
  p_descricao_norm text,
  p_unidade text,
  p_status text default 'active',
  p_codigo_legado text default null,
  p_volume_litros numeric default null,
  p_controla_estoque boolean default false,
  p_materia_prima_id bigint default null,
  p_payload_origem_json jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_embalagem_id bigint;
begin
  perform public.require_current_user_permission('cadastros.embalagens.create');
  if nullif(trim(p_descricao), '') is null then
    raise exception 'descricao is required';
  end if;
  if nullif(trim(p_unidade), '') is null then
    raise exception 'unidade is required';
  end if;
  if p_status not in ('active', 'inactive', 'pending_review') then
    raise exception 'invalid status';
  end if;
  if p_volume_litros is not null and p_volume_litros <= 0 then
    raise exception 'volume_litros must be greater than zero';
  end if;
  if coalesce(p_controla_estoque, false) and p_materia_prima_id is null then
    raise exception 'materia_prima_id is required when controla_estoque is true';
  end if;

  v_actor := public.current_actor_id();

  insert into public.cad_embalagens(
    codigo_legado,
    descricao,
    descricao_norm,
    unidade,
    volume_litros,
    controla_estoque,
    materia_prima_id,
    status,
    created_by,
    updated_by
  )
  values (
    nullif(trim(p_codigo_legado), ''),
    trim(p_descricao),
    trim(p_descricao_norm),
    upper(trim(p_unidade)),
    p_volume_litros,
    coalesce(p_controla_estoque, false),
    p_materia_prima_id,
    p_status,
    v_actor,
    v_actor
  )
  returning id into v_embalagem_id;

  perform public.log_audit_event(
    'cadastros',
    'cad_embalagens',
    v_embalagem_id::text,
    'cadastros.embalagem_created',
    'cadastros.embalagens.create',
    'success',
    null,
    jsonb_build_object('descricao', trim(p_descricao), 'unidade', upper(trim(p_unidade)), 'controla_estoque', coalesce(p_controla_estoque, false), 'materia_prima_id', p_materia_prima_id, 'status', p_status),
    jsonb_build_object('alcada_usada', 'cadastros.embalagens.create'),
    'database_rpc',
    jsonb_build_object('source', 'create_cad_embalagem', 'payload_origem', coalesce(p_payload_origem_json, '{}'::jsonb))
  );

  return v_embalagem_id;
end;
$$;

create or replace function public.create_cad_produto_embalagem(
  p_produto_id bigint,
  p_embalagem_id bigint,
  p_codigo_item text,
  p_status text default 'active'
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_produto_embalagem_id bigint;
begin
  perform public.require_current_user_permission('cadastros.produto_embalagens.create');
  if p_produto_id is null or p_produto_id <= 0 then
    raise exception 'produto_id is required';
  end if;
  if p_embalagem_id is null or p_embalagem_id <= 0 then
    raise exception 'embalagem_id is required';
  end if;
  if nullif(trim(p_codigo_item), '') is null then
    raise exception 'codigo_item is required';
  end if;
  if p_status not in ('active', 'inactive', 'pending_review') then
    raise exception 'invalid status';
  end if;

  v_actor := public.current_actor_id();

  insert into public.cad_produto_embalagens(produto_id, embalagem_id, codigo_item, status, created_by, updated_by)
  values (p_produto_id, p_embalagem_id, upper(trim(p_codigo_item)), p_status, v_actor, v_actor)
  returning id into v_produto_embalagem_id;

  perform public.log_audit_event(
    'cadastros',
    'cad_produto_embalagens',
    v_produto_embalagem_id::text,
    'cadastros.produto_embalagem_created',
    'cadastros.produto_embalagens.create',
    'success',
    null,
    jsonb_build_object('produto_id', p_produto_id, 'embalagem_id', p_embalagem_id, 'codigo_item', upper(trim(p_codigo_item)), 'status', p_status),
    jsonb_build_object('alcada_usada', 'cadastros.produto_embalagens.create'),
    'database_rpc',
    jsonb_build_object('source', 'create_cad_produto_embalagem')
  );

  return v_produto_embalagem_id;
end;
$$;

create or replace function public.create_cad_conversao_unidade_mp(
  p_materia_prima_id bigint,
  p_unidade_origem text,
  p_unidade_destino text,
  p_fator numeric,
  p_vigencia_inicio date default null,
  p_vigencia_fim date default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_conversao_id bigint;
begin
  perform public.require_current_user_permission('cadastros.conversoes_unidade_mp.create');
  if p_materia_prima_id is null or p_materia_prima_id <= 0 then
    raise exception 'materia_prima_id is required';
  end if;
  if nullif(trim(p_unidade_origem), '') is null then
    raise exception 'unidade_origem is required';
  end if;
  if nullif(trim(p_unidade_destino), '') is null then
    raise exception 'unidade_destino is required';
  end if;
  if upper(trim(p_unidade_origem)) = upper(trim(p_unidade_destino)) then
    raise exception 'unidade_origem and unidade_destino must be different';
  end if;
  if p_fator is null or p_fator <= 0 then
    raise exception 'fator must be greater than zero';
  end if;
  if p_vigencia_inicio is not null and p_vigencia_fim is not null and p_vigencia_fim < p_vigencia_inicio then
    raise exception 'vigencia_fim must be greater than or equal to vigencia_inicio';
  end if;

  v_actor := public.current_actor_id();

  insert into public.cad_conversoes_unidade_mp(
    materia_prima_id,
    unidade_origem,
    unidade_destino,
    fator,
    vigencia_inicio,
    vigencia_fim,
    created_by
  )
  values (
    p_materia_prima_id,
    upper(trim(p_unidade_origem)),
    upper(trim(p_unidade_destino)),
    p_fator,
    p_vigencia_inicio,
    p_vigencia_fim,
    v_actor
  )
  returning id into v_conversao_id;

  perform public.log_audit_event(
    'cadastros',
    'cad_conversoes_unidade_mp',
    v_conversao_id::text,
    'cadastros.conversao_unidade_mp_created',
    'cadastros.conversoes_unidade_mp.create',
    'success',
    null,
    jsonb_build_object('materia_prima_id', p_materia_prima_id, 'unidade_origem', upper(trim(p_unidade_origem)), 'unidade_destino', upper(trim(p_unidade_destino)), 'fator', p_fator, 'vigencia_inicio', p_vigencia_inicio, 'vigencia_fim', p_vigencia_fim),
    jsonb_build_object('alcada_usada', 'cadastros.conversoes_unidade_mp.create'),
    'database_rpc',
    jsonb_build_object('source', 'create_cad_conversao_unidade_mp')
  );

  return v_conversao_id;
end;
$$;
