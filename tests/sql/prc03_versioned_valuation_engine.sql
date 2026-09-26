\set ON_ERROR_STOP on
begin;

insert into auth.users(id,email) values
  ('15200000-0000-4000-8000-000000000001','prc03-manager@test.invalid'),
  ('15200000-0000-4000-8000-000000000002','prc03-reviewer@test.invalid'),
  ('15200000-0000-4000-8000-000000000003','prc03-denied@test.invalid');
insert into public.user_profiles(id,display_name,role,status) values
  ('15200000-0000-4000-8000-000000000001','PRC03 Manager','admin','active'),
  ('15200000-0000-4000-8000-000000000002','PRC03 Reviewer','admin','active'),
  ('15200000-0000-4000-8000-000000000003','PRC03 Denied','comercial','active');
insert into public.user_permission_overrides(user_id,action_key,allowed,updated_by) values
  ('15200000-0000-4000-8000-000000000001','precificacao.valuation.manage',true,'15200000-0000-4000-8000-000000000001'),
  ('15200000-0000-4000-8000-000000000001','precificacao.valuation.lifecycle',true,'15200000-0000-4000-8000-000000000001'),
  ('15200000-0000-4000-8000-000000000001','precificacao.valuation.execute',true,'15200000-0000-4000-8000-000000000001'),
  ('15200000-0000-4000-8000-000000000001','system.admin',true,'15200000-0000-4000-8000-000000000001'),
  ('15200000-0000-4000-8000-000000000002','precificacao.valuation.review',true,'15200000-0000-4000-8000-000000000001');
select set_config('request.jwt.claim.sub','15200000-0000-4000-8000-000000000001',true);
select public.set_system_runtime_environment('test','test_reset','PRC-03 disposable smoke')
  where public.current_system_environment()='unconfigured';
select public.set_system_module_rollout('test','precificacao','technical_validation','read_write','technical_validation','PRC-03 disposable smoke');

do $security$
begin
  if exists(select 1 from public.permission_actions where action_key like 'precificacao.valuation.%' and default_allowed) then
    raise exception 'permissao PRC-03 nao e default deny';
  end if;
  if has_schema_privilege('authenticated','precificacao_internal','usage')
     or has_function_privilege('authenticated','precificacao_internal.prc_valoracao_versao_sha256(bigint)','execute')
     or has_table_privilege('authenticated','public.prc_valoracao_snapshots','select')
     or has_table_privilege('authenticated','public.prc_valoracao_versoes','insert') then
    raise exception 'RLS/default-deny/helper privado PRC-03 falhou';
  end if;
  if not has_function_privilege('authenticated','public.executar_prc_valoracao_idempotente(uuid,bigint,bigint,text)','execute') then
    raise exception 'RPC governada PRC-03 indisponivel';
  end if;
end $security$;

insert into public.cad_materias_primas(sku_corrigido,nome,nome_norm,unidade_base_estoque,status,created_by)
values
  ('PRC03-WEIGHTED','MP PRC03 Weighted','mp prc03 weighted','kg','active','15200000-0000-4000-8000-000000000001'),
  ('PRC03-RESERVED','MP PRC03 Reserved','mp prc03 reserved','kg','active','15200000-0000-4000-8000-000000000001'),
  ('PRC03-MIXED','MP PRC03 Mixed','mp prc03 mixed','kg','active','15200000-0000-4000-8000-000000000001'),
  ('PRC03-EXPIRED','MP PRC03 Expired','mp prc03 expired','kg','active','15200000-0000-4000-8000-000000000001'),
  ('PRC03-UNIT','MP PRC03 Unit','mp prc03 unit','kg','active','15200000-0000-4000-8000-000000000001'),
  ('PRC03-LATEST-GLOBAL','MP PRC03 Latest Global','mp prc03 latest global','kg','active','15200000-0000-4000-8000-000000000001');

create function pg_temp.mp(p_sku text) returns bigint language sql stable as $$
  select id from public.cad_materias_primas where sku_corrigido=p_sku
$$;
create function pg_temp.add_layer(p_mp bigint,p_lot text,p_qty numeric,p_unit_cost numeric,p_currency text,p_expiry date default null,p_unit text default 'kg',p_entry_at timestamptz default null,p_lot_created_at timestamptz default null)
returns bigint language plpgsql as $$
declare v_lot bigint; v_move bigint; v_value bigint;
begin
  select id into v_lot
    from public.est_lotes_mp
   where materia_prima_id=p_mp and codigo_lote=p_lot;
  if v_lot is null then
    insert into public.est_lotes_mp(materia_prima_id,codigo_lote,status,data_validade,created_by,created_at,updated_at)
    values(p_mp,p_lot,'disponivel',p_expiry,'15200000-0000-4000-8000-000000000001',coalesce(p_lot_created_at,clock_timestamp()),coalesce(p_lot_created_at,clock_timestamp())) returning id into v_lot;
  end if;
  insert into public.est_movimentos_mp(lote_mp_id,materia_prima_id,tipo_movimento,quantidade,origem_modulo,origem_tabela,origem_id,created_by,created_at)
  values(v_lot,p_mp,'entrada_compra',p_qty,'estoque','prc03_smoke',p_lot,'15200000-0000-4000-8000-000000000001',coalesce(p_entry_at,clock_timestamp())) returning id into v_move;
  insert into public.est_movimentos_mp_valores(movimento_mp_id,quantidade_origem,unidade_origem,quantidade_base,moeda,valor_materia_prima,frete,difal_icms,difal_status,outras_despesas,origem_dados,created_by)
  values(v_move,p_qty,p_unit,p_qty,p_currency,p_qty*p_unit_cost,0,0,'not_applicable',0,'sistema','15200000-0000-4000-8000-000000000001') returning id into v_value;
  return v_lot;
end;
$$;

select pg_temp.add_layer(pg_temp.mp('PRC03-WEIGHTED'),'PRC03-W1',10,10,'BRL',null);
select pg_temp.add_layer(pg_temp.mp('PRC03-WEIGHTED'),'PRC03-W2',10,20,'BRL',null);
select pg_temp.add_layer(pg_temp.mp('PRC03-RESERVED'),'PRC03-R1',10,10,'BRL',null);
select pg_temp.add_layer(pg_temp.mp('PRC03-RESERVED'),'PRC03-R1',20,20,'BRL',null);
select pg_temp.add_layer(pg_temp.mp('PRC03-MIXED'),'PRC03-M1',10,10,'BRL',null);
select pg_temp.add_layer(pg_temp.mp('PRC03-MIXED'),'PRC03-M2',10,20,'USD',null);
select pg_temp.add_layer(pg_temp.mp('PRC03-EXPIRED'),'PRC03-E1',10,10,'BRL',current_date-1);
select pg_temp.add_layer(pg_temp.mp('PRC03-UNIT'),'PRC03-U1',10,10,'BRL',null,'g');
-- The late acquisition belongs to older lot A. Lot B was created later, but
-- its acquisition predates A's late layer, so lot iteration cannot choose it.
select pg_temp.add_layer(pg_temp.mp('PRC03-LATEST-GLOBAL'),'PRC03-LG-A',10,10,'BRL',null,'kg',transaction_timestamp()-interval '3 days',transaction_timestamp()-interval '3 days');
select pg_temp.add_layer(pg_temp.mp('PRC03-LATEST-GLOBAL'),'PRC03-LG-B',10,20,'BRL',null,'kg',transaction_timestamp()-interval '2 days',transaction_timestamp()-interval '2 days');
select pg_temp.add_layer(pg_temp.mp('PRC03-LATEST-GLOBAL'),'PRC03-LG-A',10,30,'BRL',null,'kg',transaction_timestamp()-interval '1 day',transaction_timestamp()-interval '3 days');

-- A real consumption allocates cost through the existing 0077 FIFO trigger.
insert into public.est_movimentos_mp(lote_mp_id,materia_prima_id,tipo_movimento,quantidade,origem_modulo,origem_tabela,origem_id,created_by)
select l.id,l.materia_prima_id,'consumo_op',-2,'pcp','prc03_smoke','consumo-r1','15200000-0000-4000-8000-000000000001'
  from public.est_lotes_mp l where l.codigo_lote='PRC03-R1';

-- The existing saldo view deducts this active reservation. The lot has two
-- acquisition layers, so PRC-03 must allocate the reservation FIFO in memory.
insert into public.cad_produtos_base(codigo_produto,nome,nome_norm,status,created_by)
values('1520','Produto PRC03','produto prc03','active','15200000-0000-4000-8000-000000000001');
insert into public.pcp_formula_versoes(produto_id,tipo_receita,versao,justificativa,entry_hash,created_by)
select id,'producao',1,'Fixture de reserva PRC-03','0000000000000000000000000000000000000000000000000000000000000000','15200000-0000-4000-8000-000000000001'
  from public.cad_produtos_base where codigo_produto='1520';
insert into public.pcp_ordens_producao(codigo_op,formula_versao_id,tipo_op,status,quantidade_planejada,created_by)
select 'PRC03-OP-RES',id,'experimental','planned',10,'15200000-0000-4000-8000-000000000001' from public.pcp_formula_versoes where justificativa='Fixture de reserva PRC-03';
insert into public.pcp_op_componentes_planejados(op_id,tipo_componente,materia_prima_id,quantidade_planejada,unidade)
select o.id,'MP',pg_temp.mp('PRC03-RESERVED'),10,'kg' from public.pcp_ordens_producao o where o.codigo_op='PRC03-OP-RES';
insert into public.pcp_op_reservas_componentes(op_id,op_componente_id,tipo_componente,lote_mp_id,quantidade_reservada,status,created_by)
select o.id,c.id,'MP',l.id,10,'ativa','15200000-0000-4000-8000-000000000001'
  from public.pcp_ordens_producao o
  join public.pcp_op_componentes_planejados c on c.op_id=o.id
  join public.est_lotes_mp l on l.codigo_lote='PRC03-R1'
 where o.codigo_op='PRC03-OP-RES';

select set_config('request.jwt.claim.sub','15200000-0000-4000-8000-000000000001',true);
do $prc03$
declare
  v_weighted bigint; v_latest bigint; v_latest_global bigint; v_reserved bigint; v_manual_policy bigint; v_ref bigint; v_snapshot bigint; v_retry bigint;
  v_before_stock bigint; v_after_stock bigint; v_sha text; v_failed boolean;
begin
  v_weighted:=public.salvar_prc_valoracao_versao_idempotente('15200000-0000-4000-8000-000000000011',null,'Peso disponivel','STOCK_ACQUISITION_LAYER','WEIGHTED_AVAILABLE_BALANCE','ALLOW_UNKNOWN',null,'Criar politica de saldo ponderado');
  if (select decisao from public.prc_valoracao_revisoes where valoracao_versao_id=v_weighted order by id limit 1)<>'PENDING' then raise exception 'politica nao iniciou pending'; end if;
  v_failed:=false;
  begin perform public.alterar_prc_valoracao_lifecycle_idempotente('15200000-0000-4000-8000-000000000012',v_weighted,'ACTIVE','Ativacao sem aprovacao deve falhar'); exception when others then v_failed:=position('aprovada' in sqlerrm)>0; end;
  if not v_failed then raise exception 'APPROVED foi confundido com ACTIVE'; end if;
  perform set_config('request.jwt.claim.sub','15200000-0000-4000-8000-000000000002',true);
  perform public.revisar_prc_valoracao_versao_idempotente('15200000-0000-4000-8000-000000000013',v_weighted,'APPROVED','Revisao segregada da politica ponderada');
  perform set_config('request.jwt.claim.sub','15200000-0000-4000-8000-000000000001',true);
  perform public.alterar_prc_valoracao_lifecycle_idempotente('15200000-0000-4000-8000-000000000014',v_weighted,'ACTIVE','Ativar politica ponderada aprovada');
  select count(*) into v_before_stock from public.est_movimentos_mp;
  v_snapshot:=public.executar_prc_valoracao_idempotente('15200000-0000-4000-8000-000000000015',v_weighted,pg_temp.mp('PRC03-WEIGHTED'),'Valoracao ponderada com duas camadas');
  v_retry:=public.executar_prc_valoracao_idempotente('15200000-0000-4000-8000-000000000015',v_weighted,pg_temp.mp('PRC03-WEIGHTED'),'Valoracao ponderada com duas camadas');
  select count(*) into v_after_stock from public.est_movimentos_mp;
  if v_retry<>v_snapshot or v_before_stock<>v_after_stock then raise exception 'idempotencia ou isolamento de estoque falhou'; end if;
  if (select quantidade_total from public.prc_valoracao_snapshots where id=v_snapshot)<>20
     or (select custo_unitario_exato from public.prc_valoracao_snapshots where id=v_snapshot)<>15
     or (select count(*) from public.prc_valoracao_snapshot_camadas where snapshot_id=v_snapshot)<>2 then raise exception 'weighted available de multiplas camadas falhou'; end if;
  if (select count(*) from public.prc_valoracao_snapshot_exclusoes where snapshot_id=v_snapshot and reason_code='EXPIRY_UNKNOWN_ALLOWED')<>2 then raise exception 'validade NULL permitida nao foi congelada'; end if;
  v_retry:=public.executar_prc_valoracao_idempotente('15200000-0000-4000-8000-000000000016',v_weighted,pg_temp.mp('PRC03-WEIGHTED'),'Determinismo com nova chave idempotente');
  if (select result_sha256 from public.prc_valoracao_snapshots where id=v_snapshot) is distinct from
     (select result_sha256 from public.prc_valoracao_snapshots where id=v_retry) then
    raise exception 'determinismo matematico falhou: % <> %',
      (select result_sha256 from public.prc_valoracao_snapshots where id=v_snapshot),
      (select result_sha256 from public.prc_valoracao_snapshots where id=v_retry);
  end if;

  v_latest:=public.salvar_prc_valoracao_versao_idempotente('15200000-0000-4000-8000-000000000017',null,'Ultima aquisicao','STOCK_ACQUISITION_LAYER','LATEST_ELIGIBLE_ACQUISITION','ALLOW_UNKNOWN',null,'Criar politica de ultima aquisicao');
  perform set_config('request.jwt.claim.sub','15200000-0000-4000-8000-000000000002',true);
  perform public.revisar_prc_valoracao_versao_idempotente('15200000-0000-4000-8000-000000000018',v_latest,'APPROVED','Revisao segregada da ultima aquisicao');
  perform set_config('request.jwt.claim.sub','15200000-0000-4000-8000-000000000001',true);
  perform public.alterar_prc_valoracao_lifecycle_idempotente('15200000-0000-4000-8000-000000000019',v_latest,'ACTIVE','Ativar ultima aquisicao aprovada');
  v_snapshot:=public.executar_prc_valoracao_idempotente('15200000-0000-4000-8000-000000000020',v_latest,pg_temp.mp('PRC03-WEIGHTED'),'Escolher camada elegivel mais recente');
  if (select custo_unitario_exato from public.prc_valoracao_snapshots where id=v_snapshot)<>20 then raise exception 'latest eligible acquisition falhou'; end if;

  v_latest_global:=public.salvar_prc_valoracao_versao_idempotente('15200000-0000-4000-8000-000000000036',null,'Ultima aquisicao global','STOCK_ACQUISITION_LAYER','LATEST_ELIGIBLE_ACQUISITION','ALLOW_UNKNOWN',null,'Criar politica para ordem global de aquisicao');
  perform set_config('request.jwt.claim.sub','15200000-0000-4000-8000-000000000002',true);
  perform public.revisar_prc_valoracao_versao_idempotente('15200000-0000-4000-8000-000000000037',v_latest_global,'APPROVED','Revisao segregada da ordem global de aquisicao');
  perform set_config('request.jwt.claim.sub','15200000-0000-4000-8000-000000000001',true);
  perform public.alterar_prc_valoracao_lifecycle_idempotente('15200000-0000-4000-8000-000000000038',v_latest_global,'ACTIVE','Ativar politica para ordem global de aquisicao');
  v_snapshot:=public.executar_prc_valoracao_idempotente('15200000-0000-4000-8000-000000000039',v_latest_global,pg_temp.mp('PRC03-LATEST-GLOBAL'),'Escolher camada tardia no lote mais antigo');
  if (select custo_unitario_exato from public.prc_valoracao_snapshots where id=v_snapshot)<>30
     or (select (documento_json #>> '{result,layers,0,lote_mp_id}')::bigint from public.prc_valoracao_snapshots where id=v_snapshot)
        <> (select id from public.est_lotes_mp where codigo_lote='PRC03-LG-A') then
    raise exception 'latest eligible acquisition nao aplicou a ordenacao global entrada/movimento/valor';
  end if;

  v_reserved:=public.salvar_prc_valoracao_versao_idempotente('15200000-0000-4000-8000-000000000021',null,'Reserva FIFO','STOCK_ACQUISITION_LAYER','WEIGHTED_AVAILABLE_BALANCE','ALLOW_UNKNOWN',null,'Criar politica para reserva FIFO');
  perform set_config('request.jwt.claim.sub','15200000-0000-4000-8000-000000000002',true);
  perform public.revisar_prc_valoracao_versao_idempotente('15200000-0000-4000-8000-000000000022',v_reserved,'APPROVED','Revisao segregada da reserva FIFO');
  perform set_config('request.jwt.claim.sub','15200000-0000-4000-8000-000000000001',true);
  perform public.alterar_prc_valoracao_lifecycle_idempotente('15200000-0000-4000-8000-000000000023',v_reserved,'ACTIVE','Ativar politica de reserva FIFO');
  v_snapshot:=public.executar_prc_valoracao_idempotente('15200000-0000-4000-8000-000000000024',v_reserved,pg_temp.mp('PRC03-RESERVED'),'Reconciliar reserva atravessando camadas');
  if (select quantidade_total from public.prc_valoracao_snapshots where id=v_snapshot)<>18
     or (select custo_unitario_exato from public.prc_valoracao_snapshots where id=v_snapshot)<>20
     or (select sum(quantidade_reservada_atribuida) from public.prc_valoracao_snapshot_camadas where snapshot_id=v_snapshot)<>10 then
    raise exception 'reserva FIFO ou reconciliacao de saldo disponivel falhou: quantidade %, custo %, reserva %',
      (select quantidade_total from public.prc_valoracao_snapshots where id=v_snapshot),
      (select custo_unitario_exato from public.prc_valoracao_snapshots where id=v_snapshot),
      (select sum(quantidade_reservada_atribuida) from public.prc_valoracao_snapshot_camadas where snapshot_id=v_snapshot);
  end if;

  begin
    perform public.executar_prc_valoracao_idempotente('15200000-0000-4000-8000-000000000025',v_weighted,pg_temp.mp('PRC03-MIXED'),'Moedas mistas devem falhar fechado');
    raise exception 'moedas mistas deveriam falhar fechado';
  exception when others then
    if position('mixed_currency' in sqlerrm)=0 then raise; end if;
  end;
end $prc03$;

-- Explicit negative cases use isolated subtransactions so the successful facts remain inspectable.
do $negative$
declare v_policy bigint; v_failed boolean; v_ref bigint; v_manual bigint; v_snapshot bigint; v_read jsonb;
begin
  select id into v_policy from public.prc_valoracao_versoes where valuation_method='WEIGHTED_AVAILABLE_BALANCE' order by id limit 1;
  v_failed:=false; begin perform public.executar_prc_valoracao_idempotente('15200000-0000-4000-8000-000000000026',v_policy,pg_temp.mp('PRC03-EXPIRED'),'Lote vencido deve bloquear'); exception when others then v_failed:=position('vencido' in sqlerrm)>0; end;
  if not v_failed then raise exception 'lote disponivel vencido foi aceito'; end if;
  v_failed:=false; begin perform public.executar_prc_valoracao_idempotente('15200000-0000-4000-8000-000000000027',v_policy,pg_temp.mp('PRC03-UNIT'),'Unidade incompativel deve bloquear'); exception when others then v_failed:=position('unidade' in sqlerrm)>0; end;
  if not v_failed then raise exception 'unidade incompativel foi aceita'; end if;

  v_manual:=public.salvar_prc_valoracao_versao_idempotente('15200000-0000-4000-8000-000000000028',null,'Referencia manual','APPROVED_MANUAL_REFERENCE','APPROVED_MANUAL_REFERENCE','ALLOW_UNKNOWN','MARKET','Criar politica para referencia manual');
  perform set_config('request.jwt.claim.sub','15200000-0000-4000-8000-000000000002',true);
  perform public.revisar_prc_valoracao_versao_idempotente('15200000-0000-4000-8000-000000000029',v_manual,'APPROVED','Revisao segregada da politica manual');
  perform set_config('request.jwt.claim.sub','15200000-0000-4000-8000-000000000001',true);
  perform public.alterar_prc_valoracao_lifecycle_idempotente('15200000-0000-4000-8000-000000000030',v_manual,'ACTIVE','Ativar politica manual aprovada');
  v_ref:=public.salvar_prc_valoracao_referencia_versao_idempotente('15200000-0000-4000-8000-000000000031',null,pg_temp.mp('PRC03-WEIGHTED'),'MARKET','BRL','kg',17,current_date,transaction_timestamp()-interval '1 day',null,'Pesquisa de mercado','DOC-PRC03','Criar referencia manual versionada');
  v_failed:=false; begin perform public.executar_prc_valoracao_idempotente('15200000-0000-4000-8000-000000000032',v_manual,pg_temp.mp('PRC03-WEIGHTED'),'Referencia pending deve bloquear'); exception when others then v_failed:=position('unica' in sqlerrm)>0; end;
  if not v_failed then raise exception 'referencia pending foi aceita'; end if;
  perform set_config('request.jwt.claim.sub','15200000-0000-4000-8000-000000000002',true);
  perform public.revisar_prc_valoracao_referencia_idempotente('15200000-0000-4000-8000-000000000033',v_ref,'APPROVED','Revisao segregada da referencia manual');
  perform set_config('request.jwt.claim.sub','15200000-0000-4000-8000-000000000001',true);
  perform public.alterar_prc_valoracao_referencia_lifecycle_idempotente('15200000-0000-4000-8000-000000000034',v_ref,'ACTIVE','Ativar referencia manual aprovada');
  v_snapshot:=public.executar_prc_valoracao_idempotente('15200000-0000-4000-8000-000000000035',v_manual,pg_temp.mp('PRC03-WEIGHTED'),'Usar uma referencia manual aprovada');
  if (select custo_unitario_exato from public.prc_valoracao_snapshots where id=v_snapshot)<>17 then raise exception 'manual approved nao foi utilizada'; end if;
  v_read:=public.consultar_prc_valoracao_snapshot(v_snapshot);
  if v_read->>'documento_sha256' is distinct from (select documento_sha256 from public.prc_valoracao_snapshots where id=v_snapshot) then
    raise exception 'leitura governada nao devolveu snapshot integro';
  end if;
  v_failed:=false; begin update public.prc_valoracao_snapshots set result_sha256='0' where id=v_snapshot; exception when others then v_failed:=position('append-only' in sqlerrm)>0; end;
  if not v_failed then raise exception 'snapshot permitiu update'; end if;
  alter table public.prc_valoracao_snapshots disable trigger trg_prc_valoracao_snapshots_append_only;
  update public.prc_valoracao_snapshots
     set documento_json=jsonb_set(documento_json,'{evaluation,tampered}',to_jsonb(true),true)
   where id=v_snapshot;
  alter table public.prc_valoracao_snapshots enable trigger trg_prc_valoracao_snapshots_append_only;
  v_failed:=false;
  begin
    perform public.consultar_prc_valoracao_snapshot(v_snapshot);
  exception when others then
    v_failed:=position('hash integral do snapshot de valoracao diverge' in sqlerrm)>0;
  end;
  if not v_failed then raise exception 'adulteracao de metadado do snapshot nao falhou fechado'; end if;
end $negative$;

do $acl$
begin
  if has_schema_privilege('public','precificacao_internal','usage')
     or has_function_privilege('anon','public.executar_prc_valoracao_idempotente(uuid,bigint,bigint,text)','execute')
     or has_function_privilege('anon','public.consultar_prc_valoracao_snapshot(bigint)','execute')
     or has_table_privilege('authenticated','public.prc_valoracao_referencias','select') then
    raise exception 'ACL PRC-03 excedeu a superficie governada';
  end if;
end $acl$;

rollback;
\echo PG_PRC03_VERSIONED_VALUATION_ENGINE_OK
