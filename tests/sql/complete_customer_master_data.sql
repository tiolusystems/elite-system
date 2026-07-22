\set ON_ERROR_STOP on
begin;

do $customer$
declare
  v_actor uuid := '00000000-0000-4000-8000-000000000084';
  v_denied uuid := '00000000-0000-4000-8000-000000000085';
  v_client bigint; v_property bigint; v_establishment bigint; v_address bigint; v_document bigint;
begin
  insert into auth.users(id, email)
  values
    (v_actor, 'customer-smoke@example.invalid'),
    (v_denied, 'customer-denied@example.invalid')
  on conflict(id) do nothing;

  insert into public.user_profiles(id,display_name,role,status) values(v_actor,'Customer Smoke','admin','active'),(v_denied,'Denied Customer','auditoria','active')
  on conflict(id) do update set status='active';
  insert into public.user_permission_overrides(user_id,action_key,allowed,updated_by)
  select v_actor,action_key,true,v_actor from public.permission_actions on conflict(user_id,action_key) do update set allowed=true;
  insert into public.user_permission_overrides(user_id,action_key,allowed,updated_by)
  select v_denied,action_key,false,v_actor from public.permission_actions where action_key like 'cadastros.clientes.%'
  on conflict(user_id,action_key) do update set allowed=false;
  perform set_config('request.jwt.claim.sub',v_actor::text,true);
  perform public.set_system_runtime_environment(
    'test',
    'test_reset',
    'Smoke transacional da migration 0084'
  );

  v_client:=public.create_cad_cliente('Cliente Sintetico 0084','CLIENTE SINTETICO 0084','Campinas','SP','active','CLI-0084','[]','{}');
  perform public.upsert_cad_cliente_identificacao(v_client,'juridica','Cliente Sintetico 0084 Ltda','Cliente 0084','ativa','2020-01-01','0111301',null,'contribuinte','documento','2026-07-22','Cadastro sintetico');
  v_document:=public.create_cad_cliente_documento(v_client,'cnpj','12.345.678/0001-95',null,'Documento sintetico');
  perform public.create_cad_cliente_contato(v_client,'Contato Sintetico','Compras','11999990000','sintetico@example.invalid',null);
  v_property:=public.create_cad_cliente_propriedade(v_client,'Fazenda Sintetica',null,'Campinas','SP');
  v_establishment:=public.create_cad_cliente_estabelecimento(v_client,'Matriz Sintetica','matriz');
  v_address:=public.create_cad_cliente_endereco(v_client,'fiscal','Rua de Teste','Campinas','SP','13000000','100',null,'Centro',v_establishment,null);

  if not exists(select 1 from public.cad_cliente_identificacoes where cliente_id=v_client and tipo_pessoa='juridica') then raise exception 'identificacao nao persistiu'; end if;
  if not exists(select 1 from public.cad_cliente_enderecos where id=v_address and estabelecimento_id=v_establishment) then raise exception 'endereco relacional nao persistiu'; end if;
  if (select numero_norm from public.cad_cliente_documentos where id=v_document) <> '12345678000195' then raise exception 'documento nao normalizado'; end if;
  if (select count(*) from public.action_logs where entity_id in (v_document::text,v_address::text)) < 2 then raise exception 'auditoria ausente'; end if;

  begin perform public.create_cad_cliente_documento(v_client,'cnpj','12345678000195',null,'Duplicado'); raise exception 'documento duplicado aceito'; exception when unique_violation then null; end;
  begin perform public.create_cad_cliente_endereco(v_client,'fiscal','Rua X','Campinas','SP','123',null,null,null,null,v_property); raise exception 'cep invalido aceito'; exception when others then if sqlerrm not like '%cep invalido%' then raise; end if; end;

  perform set_config('request.jwt.claim.sub',v_denied::text,true);
  begin perform public.create_cad_cliente_contato(v_client,'Negado','Compras','1100000000',null,null); raise exception 'usuario sem permissao aceito'; exception when others then if sqlerrm not like 'not allowed:%' then raise; end if; end;
end $customer$;

set local role authenticated;
do $direct$
begin
  begin insert into public.cad_cliente_estabelecimentos(cliente_id,nome,nome_norm,tipo,created_by,updated_by) values(1,'Direto','DIRETO','matriz','00000000-0000-4000-8000-000000000084','00000000-0000-4000-8000-000000000084'); raise exception 'escrita direta aceita'; exception when insufficient_privilege then null; end;
end $direct$;
reset role;

select 'PG_VALIDATE_0084_WITH_SMOKE_OK' as result;
rollback;
