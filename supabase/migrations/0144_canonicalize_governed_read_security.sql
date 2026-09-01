create table public.security_sql_surface_contracts (
  function_signature text primary key,
  surface text not null check (surface in (
    'GOVERNED_RPC_DEFINER','GOVERNED_READ_INVOKER_RLS','PRIVATE_HELPER',
    'TRIGGER_HELPER','GOVERNED_SCOPE_HELPER','READ_SUPPORT_HELPER'
  )),
  read_only boolean not null,
  rls_preserved boolean not null,
  explicit_contract boolean not null,
  authorization_marker text not null,
  dependency_tables text[] not null default '{}',
  notes text not null default '',
  created_at timestamptz not null default clock_timestamp()
);
alter table public.security_sql_surface_contracts enable row level security;
revoke all on table public.security_sql_surface_contracts from public, anon, authenticated;
insert into public.security_sql_surface_contracts
  (function_signature,surface,read_only,rls_preserved,explicit_contract,authorization_marker,dependency_tables,notes)
values
 ('public.current_user_manages_seller(bigint)','GOVERNED_SCOPE_HELPER',true,true,true,'current_commercial_person_id|current_user_is_admin','{}','scope helper used by policies'),
 ('public.consultar_com_carteira_clientes(text)','GOVERNED_RPC_DEFINER',true,true,true,'current_commercial_person_id|current_user_manages_seller','{com_pedidos,cad_clientes}','scoped read'),
 ('public.consultar_com_pedidos_aprovacao()','GOVERNED_RPC_DEFINER',true,true,true,'current_user_manages_seller','{com_pedidos}','scoped read'),
 ('public.consultar_com_carteira_clientes_paginada(text,integer,integer)','GOVERNED_RPC_DEFINER',true,true,true,'current_commercial_person_id|current_user_manages_seller','{com_pedidos,cad_clientes}','scoped read'),
 ('public.consultar_cad_clientes_paginada(text,text,text,integer,integer)','GOVERNED_READ_INVOKER_RLS',true,true,true,'current_actor_id','{cad_clientes,cad_cliente_identificacoes,cad_cliente_documentos,cad_cliente_propriedades}','RLS read'),
 ('public.buscar_exp_romaneios_paginada(text,bigint,bigint,bigint,bigint,text,date,date,text[],bigint,bigint,bigint,bigint,integer,integer)','GOVERNED_READ_INVOKER_RLS',true,true,true,'current_actor_id','{exp_romaneios,com_pedidos,cad_clientes}','RLS read'),
 ('public.consultar_est_estoque_pa_posicao(date)','GOVERNED_READ_INVOKER_RLS',true,true,true,'RLS','{est_lotes_pa,est_movimentos_pa,est_reservas_pa,cad_produto_embalagens,cad_embalagens}','RLS read'),
 ('public.normalize_client_search_text(text)','READ_SUPPORT_HELPER',true,true,true,'immutable','{}','read support helper');

do $$
declare
  v_signature text;
begin
  for v_signature in
    select function_signature
      from public.security_sql_surface_contracts
  loop
    if to_regprocedure(v_signature) is null then
      raise exception 'canonical SQL surface references missing function: %', v_signature;
    end if;
  end loop;
end;
$$;
