insert into public.permission_actions(action_key, module, description, default_allowed, sort_order, runtime_module_key, runtime_access_kind)
values
  ('cadastros.clientes.identification.manage', 'cadastros', 'Manter identificacao empresarial do cliente', true, 120, 'cadastros', 'write'),
  ('cadastros.clientes.documents.manage', 'cadastros', 'Manter documentos do cliente', true, 121, 'cadastros', 'write'),
  ('cadastros.clientes.contacts.manage', 'cadastros', 'Manter contatos do cliente', true, 122, 'cadastros', 'write'),
  ('cadastros.clientes.properties.manage', 'cadastros', 'Manter propriedades e estabelecimentos do cliente', true, 123, 'cadastros', 'write'),
  ('cadastros.clientes.addresses.manage', 'cadastros', 'Manter enderecos do cliente', true, 124, 'cadastros', 'write')
on conflict (action_key) do update set description=excluded.description, runtime_module_key=excluded.runtime_module_key, runtime_access_kind=excluded.runtime_access_kind;

create table public.cad_cliente_identificacoes (
  id bigint generated always as identity primary key,
  cliente_id bigint not null unique references public.cad_clientes(id) on delete restrict,
  tipo_pessoa text not null,
  razao_social text,
  nome_fantasia text,
  situacao_cadastral text not null default 'nao_verificada',
  data_abertura date,
  cnae_principal text,
  regime_tributario text,
  condicao_contribuinte text,
  fonte_informacao text not null default 'informado_cliente',
  data_consulta date,
  payload_fonte_json jsonb not null default '{}'::jsonb,
  created_by uuid not null references public.user_profiles(id),
  updated_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cad_cliente_identificacoes_tipo_check check (tipo_pessoa in ('fisica','juridica')),
  constraint cad_cliente_identificacoes_situacao_check check (situacao_cadastral in ('ativa','inativa','suspensa','baixada','nao_verificada')),
  constraint cad_cliente_identificacoes_fonte_check check (fonte_informacao in ('informado_cliente','documento','excel_legado','consulta_futura')),
  constraint cad_cliente_identificacoes_payload_check check (jsonb_typeof(payload_fonte_json) = 'object')
);

create table public.cad_cliente_estabelecimentos (
  id bigint generated always as identity primary key,
  cliente_id bigint not null references public.cad_clientes(id) on delete restrict,
  nome text not null,
  nome_norm text not null,
  tipo text not null,
  status text not null default 'active',
  created_by uuid not null references public.user_profiles(id),
  updated_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cad_cliente_estabelecimentos_tipo_check check (tipo in ('matriz','filial','loja','revenda','unidade_operacional')),
  constraint cad_cliente_estabelecimentos_status_check check (status in ('active','inactive','pending_review')),
  constraint cad_cliente_estabelecimentos_key unique (cliente_id, nome_norm)
);

create table public.cad_cliente_enderecos (
  id bigint generated always as identity primary key,
  cliente_id bigint not null references public.cad_clientes(id) on delete restrict,
  estabelecimento_id bigint references public.cad_cliente_estabelecimentos(id) on delete restrict,
  propriedade_id bigint references public.cad_cliente_propriedades(id) on delete restrict,
  tipo text not null,
  cep text,
  cep_norm text,
  logradouro text not null,
  numero text,
  complemento text,
  bairro text,
  cidade text not null,
  uf text not null,
  status text not null default 'active',
  fonte_informacao text not null default 'informado_cliente',
  created_by uuid not null references public.user_profiles(id),
  updated_by uuid not null references public.user_profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cad_cliente_enderecos_tipo_check check (tipo in ('fiscal','cobranca','entrega','correspondencia')),
  constraint cad_cliente_enderecos_uf_check check (char_length(uf)=2),
  constraint cad_cliente_enderecos_cep_check check (cep_norm is null or cep_norm ~ '^[0-9]{8}$'),
  constraint cad_cliente_enderecos_status_check check (status in ('active','inactive','pending_review')),
  constraint cad_cliente_enderecos_fonte_check check (fonte_informacao in ('informado_cliente','documento','excel_legado','consulta_futura'))
);

create index idx_cad_cliente_estabelecimentos_cliente on public.cad_cliente_estabelecimentos(cliente_id, status);
create index idx_cad_cliente_enderecos_cliente on public.cad_cliente_enderecos(cliente_id, status, tipo);
create index idx_cad_cliente_enderecos_cep on public.cad_cliente_enderecos(cep_norm) where cep_norm is not null;

create trigger trg_cad_cliente_identificacoes_updated_at before update on public.cad_cliente_identificacoes for each row execute function public.touch_updated_at();
create trigger trg_cad_cliente_estabelecimentos_updated_at before update on public.cad_cliente_estabelecimentos for each row execute function public.touch_updated_at();
create trigger trg_cad_cliente_enderecos_updated_at before update on public.cad_cliente_enderecos for each row execute function public.touch_updated_at();

alter table public.cad_cliente_identificacoes enable row level security;
alter table public.cad_cliente_estabelecimentos enable row level security;
alter table public.cad_cliente_enderecos enable row level security;

create policy "authenticated read cad_cliente_identificacoes" on public.cad_cliente_identificacoes for select to authenticated using (public.current_actor_id() is not null);
create policy "authenticated read cad_cliente_estabelecimentos" on public.cad_cliente_estabelecimentos for select to authenticated using (public.current_actor_id() is not null);
create policy "authenticated read cad_cliente_enderecos" on public.cad_cliente_enderecos for select to authenticated using (public.current_actor_id() is not null);

revoke all on public.cad_cliente_identificacoes, public.cad_cliente_estabelecimentos, public.cad_cliente_enderecos from public, anon;
revoke insert, update, delete, truncate on public.cad_cliente_identificacoes, public.cad_cliente_estabelecimentos, public.cad_cliente_enderecos from authenticated;
grant select on public.cad_cliente_identificacoes, public.cad_cliente_estabelecimentos, public.cad_cliente_enderecos to authenticated;

create or replace function public.normalize_customer_document(p_value text) returns text language sql immutable parallel safe set search_path=public as $$
  select nullif(regexp_replace(coalesce(p_value,''), '[^0-9A-Za-z]+', '', 'g'), '')
$$;
revoke all on function public.normalize_customer_document(text) from public, anon, authenticated;

create or replace function public.assert_customer_relation(p_cliente_id bigint, p_propriedade_id bigint default null, p_estabelecimento_id bigint default null)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not exists(select 1 from public.cad_clientes where id=p_cliente_id) then raise exception 'cliente nao localizado'; end if;
  if p_propriedade_id is not null and not exists(select 1 from public.cad_cliente_propriedades where id=p_propriedade_id and cliente_id=p_cliente_id) then raise exception 'propriedade nao pertence ao cliente'; end if;
  if p_estabelecimento_id is not null and not exists(select 1 from public.cad_cliente_estabelecimentos where id=p_estabelecimento_id and cliente_id=p_cliente_id) then raise exception 'estabelecimento nao pertence ao cliente'; end if;
end; $$;
revoke all on function public.assert_customer_relation(bigint,bigint,bigint) from public, anon, authenticated;

create or replace function public.upsert_cad_cliente_identificacao(
 p_cliente_id bigint, p_tipo_pessoa text, p_razao_social text default null, p_nome_fantasia text default null,
 p_situacao_cadastral text default 'nao_verificada', p_data_abertura date default null, p_cnae_principal text default null,
 p_regime_tributario text default null, p_condicao_contribuinte text default null, p_fonte_informacao text default 'informado_cliente',
 p_data_consulta date default null, p_motivo text default null
) returns bigint language plpgsql security definer set search_path=public as $$
declare v_actor uuid; v_context jsonb; v_before jsonb; v_after jsonb; v_id bigint;
begin
  if nullif(btrim(p_motivo),'') is null then raise exception 'motivo obrigatorio'; end if;
  perform public.assert_customer_relation(p_cliente_id);
  v_context:=public.begin_audited_rpc('cadastros.clientes.identification.manage','cadastros','cad_cliente_identificacoes','field_risk',jsonb_build_object('cliente_id',p_cliente_id));
  v_actor:=public.current_actor_id();
  select to_jsonb(i),i.id into v_before,v_id from public.cad_cliente_identificacoes i where cliente_id=p_cliente_id for update;
  insert into public.cad_cliente_identificacoes(cliente_id,tipo_pessoa,razao_social,nome_fantasia,situacao_cadastral,data_abertura,cnae_principal,regime_tributario,condicao_contribuinte,fonte_informacao,data_consulta,created_by,updated_by)
  values(p_cliente_id,p_tipo_pessoa,nullif(btrim(p_razao_social),''),nullif(btrim(p_nome_fantasia),''),p_situacao_cadastral,p_data_abertura,nullif(btrim(p_cnae_principal),''),nullif(btrim(p_regime_tributario),''),nullif(btrim(p_condicao_contribuinte),''),p_fonte_informacao,p_data_consulta,v_actor,v_actor)
  on conflict(cliente_id) do update set tipo_pessoa=excluded.tipo_pessoa,razao_social=excluded.razao_social,nome_fantasia=excluded.nome_fantasia,situacao_cadastral=excluded.situacao_cadastral,data_abertura=excluded.data_abertura,cnae_principal=excluded.cnae_principal,regime_tributario=excluded.regime_tributario,condicao_contribuinte=excluded.condicao_contribuinte,fonte_informacao=excluded.fonte_informacao,data_consulta=excluded.data_consulta,updated_by=v_actor
  returning id into v_id;
  select to_jsonb(i) into v_after from public.cad_cliente_identificacoes i where id=v_id;
  perform public.log_audited_rpc_change('cadastros','cad_cliente_identificacoes',v_id::text,'upsert','cadastros.clientes.identification.manage',v_context,v_before,v_after,jsonb_build_object('motivo',p_motivo)); return v_id;
end; $$;

create or replace function public.create_cad_cliente_documento(p_cliente_id bigint,p_tipo text,p_numero text,p_propriedade_id bigint default null,p_motivo text default null)
returns bigint language plpgsql security definer set search_path=public as $$
declare v_context jsonb; v_id bigint; v_norm text;
begin
  if nullif(btrim(p_motivo),'') is null then raise exception 'motivo obrigatorio'; end if;
  perform public.assert_customer_relation(p_cliente_id,p_propriedade_id); v_norm:=public.normalize_customer_document(p_numero);
  if v_norm is null then raise exception 'numero obrigatorio'; end if;
  if p_tipo='cpf' and v_norm !~ '^[0-9]{11}$' then raise exception 'cpf invalido'; end if;
  if p_tipo='cnpj' and v_norm !~ '^[0-9]{14}$' then raise exception 'cnpj invalido'; end if;
  v_context:=public.begin_audited_rpc('cadastros.clientes.documents.manage','cadastros','cad_cliente_documentos','change_type',jsonb_build_object('cliente_id',p_cliente_id));
  insert into public.cad_cliente_documentos(cliente_id,propriedade_id,tipo,numero,numero_norm,created_by) values(p_cliente_id,p_propriedade_id,p_tipo,btrim(p_numero),upper(v_norm),public.current_actor_id()) returning id into v_id;
  perform public.log_audited_rpc_change('cadastros','cad_cliente_documentos',v_id::text,'create','cadastros.clientes.documents.manage',v_context,null,(select to_jsonb(d) from public.cad_cliente_documentos d where id=v_id),jsonb_build_object('motivo',p_motivo)); return v_id;
end; $$;

create or replace function public.create_cad_cliente_contato(p_cliente_id bigint,p_nome text,p_papel text,p_telefone text default null,p_email text default null,p_propriedade_id bigint default null)
returns bigint language plpgsql security definer set search_path=public as $$
declare v_context jsonb; v_id bigint;
begin
  perform public.assert_customer_relation(p_cliente_id,p_propriedade_id); if nullif(btrim(p_nome),'') is null or nullif(btrim(p_papel),'') is null then raise exception 'nome e papel obrigatorios'; end if;
  if nullif(btrim(p_telefone),'') is null and nullif(btrim(p_email),'') is null then raise exception 'telefone ou email obrigatorio'; end if;
  v_context:=public.begin_audited_rpc('cadastros.clientes.contacts.manage','cadastros','cad_cliente_contatos','change_type',jsonb_build_object('cliente_id',p_cliente_id));
  insert into public.cad_cliente_contatos(cliente_id,propriedade_id,nome,papel,telefone,email,status,created_by,updated_by) values(p_cliente_id,p_propriedade_id,btrim(p_nome),btrim(p_papel),nullif(btrim(p_telefone),''),lower(nullif(btrim(p_email),'')),'active',public.current_actor_id(),public.current_actor_id()) returning id into v_id;
  perform public.log_audited_rpc_change('cadastros','cad_cliente_contatos',v_id::text,'create','cadastros.clientes.contacts.manage',v_context,null,(select to_jsonb(c) from public.cad_cliente_contatos c where id=v_id)); return v_id;
end; $$;

create or replace function public.create_cad_cliente_propriedade(p_cliente_id bigint,p_nome text,p_cnpj text default null,p_cidade text default null,p_uf text default null)
returns bigint language plpgsql security definer set search_path=public as $$
declare v_context jsonb; v_id bigint; v_cnpj text;
begin
  perform public.assert_customer_relation(p_cliente_id); if nullif(btrim(p_nome),'') is null then raise exception 'nome obrigatorio'; end if; v_cnpj:=public.normalize_customer_document(p_cnpj);
  if v_cnpj is not null and v_cnpj !~ '^[0-9]{14}$' then raise exception 'cnpj invalido'; end if;
  v_context:=public.begin_audited_rpc('cadastros.clientes.properties.manage','cadastros','cad_cliente_propriedades','change_type',jsonb_build_object('cliente_id',p_cliente_id));
  insert into public.cad_cliente_propriedades(cliente_id,nome,cnpj,cnpj_norm,cidade,uf,status,created_by,updated_by) values(p_cliente_id,btrim(p_nome),nullif(btrim(p_cnpj),''),v_cnpj,nullif(btrim(p_cidade),''),upper(nullif(btrim(p_uf),'')),'active',public.current_actor_id(),public.current_actor_id()) returning id into v_id;
  perform public.log_audited_rpc_change('cadastros','cad_cliente_propriedades',v_id::text,'create','cadastros.clientes.properties.manage',v_context,null,(select to_jsonb(p) from public.cad_cliente_propriedades p where id=v_id)); return v_id;
end; $$;

create or replace function public.create_cad_cliente_estabelecimento(p_cliente_id bigint,p_nome text,p_tipo text)
returns bigint language plpgsql security definer set search_path=public as $$
declare v_context jsonb; v_id bigint;
begin
  perform public.assert_customer_relation(p_cliente_id); if nullif(btrim(p_nome),'') is null then raise exception 'nome obrigatorio'; end if;
  v_context:=public.begin_audited_rpc('cadastros.clientes.properties.manage','cadastros','cad_cliente_estabelecimentos','change_type',jsonb_build_object('cliente_id',p_cliente_id));
  insert into public.cad_cliente_estabelecimentos(cliente_id,nome,nome_norm,tipo,status,created_by,updated_by) values(p_cliente_id,btrim(p_nome),public.normalize_catalog_term(p_nome),p_tipo,'active',public.current_actor_id(),public.current_actor_id()) returning id into v_id;
  perform public.log_audited_rpc_change('cadastros','cad_cliente_estabelecimentos',v_id::text,'create','cadastros.clientes.properties.manage',v_context,null,(select to_jsonb(e) from public.cad_cliente_estabelecimentos e where id=v_id)); return v_id;
end; $$;

create or replace function public.create_cad_cliente_endereco(p_cliente_id bigint,p_tipo text,p_logradouro text,p_cidade text,p_uf text,p_cep text default null,p_numero text default null,p_complemento text default null,p_bairro text default null,p_estabelecimento_id bigint default null,p_propriedade_id bigint default null)
returns bigint language plpgsql security definer set search_path=public as $$
declare v_context jsonb; v_id bigint; v_cep text;
begin
  perform public.assert_customer_relation(p_cliente_id,p_propriedade_id,p_estabelecimento_id); if nullif(btrim(p_logradouro),'') is null or nullif(btrim(p_cidade),'') is null then raise exception 'logradouro e cidade obrigatorios'; end if; v_cep:=public.normalize_customer_document(p_cep);
  if v_cep is not null and v_cep !~ '^[0-9]{8}$' then raise exception 'cep invalido'; end if;
  v_context:=public.begin_audited_rpc('cadastros.clientes.addresses.manage','cadastros','cad_cliente_enderecos','change_type',jsonb_build_object('cliente_id',p_cliente_id));
  insert into public.cad_cliente_enderecos(cliente_id,estabelecimento_id,propriedade_id,tipo,cep,cep_norm,logradouro,numero,complemento,bairro,cidade,uf,status,created_by,updated_by) values(p_cliente_id,p_estabelecimento_id,p_propriedade_id,p_tipo,nullif(btrim(p_cep),''),v_cep,btrim(p_logradouro),nullif(btrim(p_numero),''),nullif(btrim(p_complemento),''),nullif(btrim(p_bairro),''),btrim(p_cidade),upper(btrim(p_uf)),'active',public.current_actor_id(),public.current_actor_id()) returning id into v_id;
  perform public.log_audited_rpc_change('cadastros','cad_cliente_enderecos',v_id::text,'create','cadastros.clientes.addresses.manage',v_context,null,(select to_jsonb(a) from public.cad_cliente_enderecos a where id=v_id)); return v_id;
end; $$;

revoke all on function public.upsert_cad_cliente_identificacao(bigint,text,text,text,text,date,text,text,text,text,date,text) from public,anon;
revoke all on function public.create_cad_cliente_documento(bigint,text,text,bigint,text) from public,anon;
revoke all on function public.create_cad_cliente_contato(bigint,text,text,text,text,bigint) from public,anon;
revoke all on function public.create_cad_cliente_propriedade(bigint,text,text,text,text) from public,anon;
revoke all on function public.create_cad_cliente_estabelecimento(bigint,text,text) from public,anon;
revoke all on function public.create_cad_cliente_endereco(bigint,text,text,text,text,text,text,text,text,bigint,bigint) from public,anon;
grant execute on function public.upsert_cad_cliente_identificacao(bigint,text,text,text,text,date,text,text,text,text,date,text) to authenticated;
grant execute on function public.create_cad_cliente_documento(bigint,text,text,bigint,text) to authenticated;
grant execute on function public.create_cad_cliente_contato(bigint,text,text,text,text,bigint) to authenticated;
grant execute on function public.create_cad_cliente_propriedade(bigint,text,text,text,text) to authenticated;
grant execute on function public.create_cad_cliente_estabelecimento(bigint,text,text) to authenticated;
grant execute on function public.create_cad_cliente_endereco(bigint,text,text,text,text,text,text,text,text,bigint,bigint) to authenticated;
