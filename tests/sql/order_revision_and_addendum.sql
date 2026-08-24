\set ON_ERROR_STOP on
begin;

-- ORD-01 0136. This is a complete materializable contract, never a partial
-- placeholder. It exercises canonicalization and fail-closed shape validation.
do $$
declare
  v_base jsonb := jsonb_build_object(
    'schema_version', 1,
    'pedido_id', 1,
    'f2b_document', jsonb_build_object('pedido', jsonb_build_object('pedido_id', 1), 'versao_comercial', jsonb_build_object('numero', 1)),
    'f2a_comparison', jsonb_build_object(
      'itens', jsonb_build_array(jsonb_build_object(
        'pedido_item_id', 1, 'produto_embalagem_id', 1, 'origem_comercial_id', 1, 'cliente_id', 1,
        'data_comercial', '2026-08-23', 'pmp_dias', 0, 'lista_id', 1, 'lista_versao_id', 1,
        'publicacao_id', 1, 'regra_id', 1, 'prazo_faixa_dias', 0, 'unidade_precificacao_id', 1,
        'quantidade_apresentacoes', 100, 'quantidade_unidade_precificacao_por_apresentacao', 1,
        'quantidade_unidade_precificacao', 100, 'preco_referencia_centavos_por_unidade_precificacao', 100,
        'preco_praticado_centavos_por_unidade_precificacao', 100, 'diferenca_centavos_por_unidade_precificacao', 0,
        'percentual_diferenca', 0, 'valor_referencia_centavos', 10000, 'valor_praticado_centavos', 10000,
        'impacto_financeiro_centavos', 0, 'classificacao', 'AT_REFERENCE'
      )),
      'totais', jsonb_build_object('total_referencia_centavos', 10000, 'total_praticado_centavos', 10000)
    ),
    'financial_condition', jsonb_build_object(
      'plano_pagamento_id', 1, 'versao', 1, 'pmp_dias', 0, 'valor_total_centavos', 10000,
      'parcelas', jsonb_build_array(jsonb_build_object(
        'numero_parcela', 1, 'forma_pagamento', 'pix', 'valor_centavos', 10000,
        'data_vencimento', '2026-08-23', 'dias_prazo', 0
      ))
    )
  );
  v_result jsonb;
  v_alias_financial jsonb;
begin
  v_base := jsonb_set(v_base, '{f2b_document,itens}', v_base->'f2a_comparison'->'itens');
  v_base := jsonb_set(v_base, '{f2b_document,comparacao_comercial}', v_base->'f2a_comparison');
  if to_regclass('public.com_pedido_contrato_geneses') is null
     or to_regclass('public.com_pedido_revisoes_governadas') is null
     or to_regclass('public.com_pedido_revisao_eventos') is null
     or to_regclass('public.com_pedido_revisao_itens') is null
     or to_regclass('public.com_pedido_revisao_materializacoes') is null then
    raise exception 'ORD0136 schema missing';
  end if;
  if has_function_privilege('anon', 'public.solicitar_com_pedido_revisao_idempotente(uuid,bigint,jsonb)', 'EXECUTE')
     or has_function_privilege('anon', 'public.efetivar_com_pedido_revisao_idempotente(uuid,bigint,jsonb)', 'EXECUTE')
     or has_function_privilege('anon', 'public.encerrar_com_pedido_revisao_idempotente(uuid,bigint,text,text)', 'EXECUTE') then
    raise exception 'revision RPC must be default deny for anon';
  end if;
  if exists (
    select 1
      from pg_proc proc
      join pg_namespace ns on ns.oid = proc.pronamespace
     where ns.nspname = 'public'
       and (proc.proname like '%draft%' or proc.proname like '%legacy_0136%' or proc.proname like '%versioned_0136%')
  ) then
    raise exception 'obsolete 0136 draft implementation remains in pg_proc';
  end if;
  if exists (
    select 1
      from pg_proc proc
      join pg_namespace ns on ns.oid = proc.pronamespace
      cross join lateral aclexplode(coalesce(proc.proacl, acldefault('f', proc.proowner))) privilege
     where ns.nspname = 'public'
       and proc.proname in (
         'materializar_com_pedido_revisao_pre_efetiva',
         'materializar_com_pedido_contrato_genese',
         'materializar_com_pedido_contrato_genese_apos_efetividade'
       )
       and privilege.grantee = 0
       and privilege.privilege_type = 'EXECUTE'
  )
     or has_function_privilege('anon', 'public.materializar_com_pedido_revisao_pre_efetiva(bigint)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.materializar_com_pedido_revisao_pre_efetiva(bigint)', 'EXECUTE')
     or has_function_privilege('anon', 'public.materializar_com_pedido_contrato_genese(bigint)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.materializar_com_pedido_contrato_genese(bigint)', 'EXECUTE') then
    raise exception 'internal revision materializer is executable by an application role';
  end if;
  if has_table_privilege('authenticated', 'public.com_pedido_revisoes_governadas', 'INSERT')
     or has_table_privilege('authenticated', 'public.com_pedido_revisao_eventos', 'INSERT')
     or has_table_privilege('authenticated', 'public.com_pedido_revisao_itens', 'INSERT')
     or has_table_privilege('authenticated', 'public.com_pedido_revisao_materializacoes', 'INSERT') then
    raise exception 'revision facts must not be writable directly';
  end if;

  v_alias_financial := jsonb_set(v_base->'financial_condition', '{pmp_dias}', '1');
  v_alias_financial := jsonb_set(v_alias_financial, '{parcelas,0,dias_prazo}', '1');
  v_alias_financial := jsonb_set(v_alias_financial, '{parcelas,0,data_vencimento}', '"2026-08-24"');
  v_result := public.ord01_apply_com_pedido_contract_delta(
    v_base, jsonb_build_object('condicao_financeira', v_alias_financial)
  );
  if v_result ? 'condicao_financeira' or v_result->'financial_condition'->>'pmp_dias' <> '1' then
    raise exception 'financial alias was not canonicalized';
  end if;
  begin
    perform public.ord01_apply_com_pedido_contract_delta(v_base, jsonb_build_object(
      'financial_condition', v_base->'financial_condition', 'condicao_financeira', jsonb_build_object('parcelas', '[]'::jsonb)
    ));
    raise exception 'alias conflict was accepted';
  exception when others then
    if sqlerrm not like '%aliases financeiros conflitantes%' then raise; end if;
  end;
  begin
    perform public.ord01_apply_com_pedido_contract_delta(v_base, jsonb_build_object('f2a_comparison', jsonb_build_object('itens', '[]'::jsonb, 'totais', '{}'::jsonb)));
    raise exception 'incomplete nested replacement was accepted';
  exception when others then
    if sqlerrm not like '%resultado contratual incompleto ou nao materializavel%' then raise; end if;
  end;
  begin
    perform public.ord01_apply_com_pedido_contract_delta(v_base, jsonb_build_object(
      'f2a_comparison', jsonb_set(v_base->'f2a_comparison', '{itens,0,quantidade_unidade_precificacao}', '99'),
      'f2b_document', jsonb_set(
        v_base->'f2b_document', '{comparacao_comercial}',
        jsonb_set(v_base->'f2a_comparison', '{itens,0,quantidade_unidade_precificacao}', '99')
      )
    ));
    raise exception 'unmaterializable item quantity was accepted';
  exception when others then
    if sqlerrm not like '%item incompleto ou invalido%' then raise; end if;
  end;
  begin
    perform public.ord01_apply_com_pedido_contract_delta(v_base, jsonb_build_object('pedido_efetivado_em', '2026-08-23'));
    raise exception 'prohibited delta field was accepted';
  exception when others then
    if sqlerrm not like '%campo de delta contratual nao governado%' then raise; end if;
  end;
  if exists (
    select 1 from pg_proc proc join pg_namespace ns on ns.oid = proc.pronamespace
     where ns.nspname = 'public' and proc.proname = 'resolver_com_pedido_contrato_vigente'
       and proc.provolatile <> 's'
  ) then raise exception 'public contract resolver must be stable'; end if;
  if not exists (select 1 from pg_trigger where tgname = 'trg_com_pedido_revisao_itens_append_only')
     or not exists (select 1 from pg_trigger where tgname = 'trg_com_pedido_revisao_materializacoes_append_only') then
    raise exception 'versioned materialization append-only guard missing';
  end if;
end $$;

-- Reuse the real F2B fixture without its rollback. The revision test therefore
-- starts from an authenticated blocked sale with frozen F1B/F1D/F2A/F2B facts.
\set f2c_fixture true
\ir order_seller_commercial_confirmation.sql

set local role postgres;
insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
select user_id, action_key, true, '13100000-0000-4000-8000-000000000003'::uuid
from unnest(array[
  'pedidos.revision.request', 'pedidos.revision.effectuate',
  'pedidos.revision.view',
  'pedidos.buyer_signature.view', 'pedidos.buyer_signature.submit'
]) action_key
cross join (values ('13100000-0000-4000-8000-000000000001'::uuid)) actor(user_id)
union all
select user_id, action_key, true, '13100000-0000-4000-8000-000000000003'::uuid
from unnest(array[
  'pedidos.credit.review', 'pedidos.buyer_signature.view', 'pedidos.buyer_signature.review'
]) action_key
cross join (values ('13100000-0000-4000-8000-000000000004'::uuid)) actor(user_id)
on conflict (user_id, action_key) do update set allowed = excluded.allowed, updated_by = excluded.updated_by;

insert into public.cad_cliente_contatos(cliente_id, propriedade_id, nome, papel, email, status, created_by, updated_by)
select client_id, property_id, 'Contato revisao 0136', 'comprador',
       'revisao-0136@test.invalid', 'active',
       '13100000-0000-4000-8000-000000000003',
       '13100000-0000-4000-8000-000000000003'
from f2b_context;
reset role;

create temporary table revision_fixture(
  pedido_id bigint not null,
  contato_id bigint not null,
  h0_hash text not null,
  h1_id bigint,
  h1_hash text,
  h1_effective_at timestamptz,
  h2_id bigint
) on commit drop;

grant select, update on table revision_fixture to authenticated;

insert into revision_fixture(pedido_id, contato_id, h0_hash)
select context.order_id, contact.id,
       public.ord01_revision_current_contract_state(context.order_id)->>'contract_state_sha256'
  from f2b_context context
  join public.cad_cliente_contatos contact
    on contact.cliente_id = context.client_id
   and contact.email = 'revisao-0136@test.invalid';

set local role authenticated;
select set_config('request.jwt.claim.sub', '13100000-0000-4000-8000-000000000001', true);
do $$
declare
  v record;
  v_projection jsonb;
  v_state jsonb;
  v_comparison jsonb;
  v_item jsonb;
  v_document jsonb;
  v_delta jsonb;
  v_revision_id bigint;
begin
  select * into v from revision_fixture;
  v_state := public.consultar_com_pedido_contrato_vigente(v.pedido_id)->'contract_state';
  v_comparison := v_state->'f2a_comparison';
  v_item := v_comparison#>'{itens,0}';
  v_item := jsonb_set(v_item, '{quantidade_apresentacoes}', to_jsonb(100));
  v_item := jsonb_set(v_item, '{quantidade_unidade_precificacao}', to_jsonb(2000));
  v_item := jsonb_set(v_item, '{preco_praticado_centavos_por_unidade_precificacao}', to_jsonb(100));
  v_item := jsonb_set(v_item, '{diferenca_centavos_por_unidade_precificacao}', to_jsonb(0));
  v_item := jsonb_set(v_item, '{percentual_diferenca}', to_jsonb(0));
  v_item := jsonb_set(v_item, '{valor_referencia_centavos}', to_jsonb(200000));
  v_item := jsonb_set(v_item, '{valor_praticado_centavos}', to_jsonb(200000));
  v_item := jsonb_set(v_item, '{impacto_financeiro_centavos}', to_jsonb(0));
  v_item := jsonb_set(v_item, '{classificacao}', to_jsonb('AT_REFERENCE'::text));
  v_comparison := jsonb_set(v_comparison, '{itens,0}', v_item);
  v_comparison := jsonb_set(v_comparison, '{totais}', jsonb_build_object(
    'total_referencia_centavos', 202000,
    'total_praticado_centavos', 202400,
    'descontos_brutos_centavos', 0,
    'overprice_bruto_centavos', 400,
    'resultado_liquido_centavos', 400,
    'percentual_resultado_liquido', round(400::numeric * 100 / 202000, 6)
  ));
  v_document := v_state->'f2b_document';
  v_document := jsonb_set(v_document, '{itens,0,quantidade_apresentacoes}', to_jsonb(100));
  v_document := jsonb_set(v_document, '{itens,0,quantidade_unidade_precificacao}', to_jsonb(2000));
  v_document := jsonb_set(v_document, '{itens,0,preco_praticado_centavos_por_unidade_precificacao}', to_jsonb(100));
  v_document := jsonb_set(v_document, '{itens,0,diferenca_centavos_por_unidade_precificacao}', to_jsonb(0));
  v_document := jsonb_set(v_document, '{itens,0,percentual_diferenca}', to_jsonb(0));
  v_document := jsonb_set(v_document, '{itens,0,valor_referencia_centavos}', to_jsonb(200000));
  v_document := jsonb_set(v_document, '{itens,0,valor_praticado_centavos}', to_jsonb(200000));
  v_document := jsonb_set(v_document, '{itens,0,impacto_financeiro_centavos}', to_jsonb(0));
  v_document := jsonb_set(v_document, '{itens,0,classificacao}', to_jsonb('AT_REFERENCE'::text));
  v_document := jsonb_set(v_document, '{versao_comercial,justificativa_comercial}', 'null'::jsonb);
  v_document := jsonb_set(v_document, '{versao_comercial,descontos_confirmados}', 'false'::jsonb);
  v_document := jsonb_set(v_document, '{comparacao_comercial}', v_comparison);
  v_delta := jsonb_build_object('f2a_comparison', v_comparison, 'f2b_document', v_document);
  v_revision_id := public.solicitar_com_pedido_revisao_idempotente(
    '13600000-0000-4000-8000-000000000001', v.pedido_id, v_delta
  );
  if public.solicitar_com_pedido_revisao_idempotente(
    '13600000-0000-4000-8000-000000000001', v.pedido_id, v_delta
  ) <> v_revision_id then
    raise exception 'retry identico da revisao nao retornou H1';
  end if;
  begin
    perform public.materializar_com_pedido_revisao_pre_efetiva(v_revision_id);
    raise exception 'materializador interno foi invocado diretamente';
  exception when insufficient_privilege then null;
  end;
  if (public.consultar_com_pedido_contrato_vigente(v.pedido_id)->>'sequence')::integer <> 0 then
    raise exception 'revisao pendente alterou a projecao H0';
  end if;
  begin
    insert into public.fin_pedido_planos_pagamento(
      pedido_id, versao, vigencia_inicio, review_status, origem_dados, data_base,
      valor_total_centavos, pmp_dias, created_by
    ) values (v.pedido_id, 999, current_date, 'approved', 'sistema', current_date, 1, 0, auth.uid());
    raise exception 'INSERT financeiro ordinario foi aceito';
  exception when insufficient_privilege then null;
  end;
  update revision_fixture
     set h1_id = v_revision_id;
end $$;

reset role;

do $$
declare
  v record;
begin
  select * into v from revision_fixture;
  if not exists (
    select 1 from public.com_pedido_revisao_itens item
     where item.revisao_id = v.h1_id
       and item.quantidade_apresentacoes = 100
       and item.quantidade_unidade_precificacao = 2000
  ) then
    raise exception 'H1 nao materializou a quantidade comercial 100';
  end if;
  update revision_fixture
     set h1_hash = (select resulting_contract_state_sha256 from public.com_pedido_revisoes_governadas where id = v.h1_id)
   where pedido_id = v.pedido_id;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '13100000-0000-4000-8000-000000000001', true);
do $$
declare
  v record;
  v_document jsonb;
  v_evidence_id bigint;
begin
  select * into v from revision_fixture;
  v_document := public.consultar_com_pedido_documento_assinavel(v.pedido_id);
  v_evidence_id := public.registrar_com_pedido_assinatura_evidencia_idempotente(
    '13600000-0000-4000-8000-000000000010', v.pedido_id,
    (v_document->>'confirmacao_comercial_id')::bigint,
    v_document->>'documento_canonico_sha256', 'external_digital', v.contato_id,
    'pending/13100000-0000-4000-8000-000000000001/13600000-0000-4000-8000-000000000010/' || repeat('e', 64),
    repeat('e', 64), 'application/pdf', 10, 'REV-0136-H1', clock_timestamp()
  );
  update revision_fixture set h1_effective_at = null where pedido_id = v.pedido_id;
  if (select status from public.com_pedidos where id = v.pedido_id) <> 'blocked' then
    raise exception 'evidencia pendente abriu H1';
  end if;
end $$;

reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '13100000-0000-4000-8000-000000000004', true);
do $$
declare
  v record;
  v_evidence_id bigint;
begin
  select * into v from revision_fixture;
  select evidencia_id into v_evidence_id
    from public.consultar_com_pedido_assinaturas(v.pedido_id)
   order by evidencia_id desc limit 1;
  perform public.decidir_com_pedido_assinatura_idempotente(
    '13600000-0000-4000-8000-000000000011', v_evidence_id, 'ACCEPTED', null
  );
  perform public.registrar_com_pedido_decisao_credito(
    v.pedido_id, 'liberado', null, 202400, 0, 'Credito H1 para smoke de revisao.'
  );
end $$;

reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '13100000-0000-4000-8000-000000000001', true);
do $$
declare
  v record;
begin
  select * into v from revision_fixture;
  perform public.efetivar_com_pedido_revisao_idempotente(
    '13600000-0000-4000-8000-000000000012', v.h1_id, '{}'::jsonb
  );
end $$;

reset role;

do $$
declare
  v record;
begin
  select * into v from revision_fixture;
  if (select status from public.com_pedidos where id = v.pedido_id) <> 'open'
     or (select pedido_efetivado_em from public.com_pedidos where id = v.pedido_id) is null then
    raise exception 'H1 com gates completos nao efetivou o pedido';
  end if;
  update revision_fixture
     set h1_effective_at = (select pedido_efetivado_em from public.com_pedidos where id = v.pedido_id)
   where pedido_id = v.pedido_id;
end $$;

set constraints trg_com_pedido_contrato_genese_apos_efetividade immediate;

set local role authenticated;
select set_config('request.jwt.claim.sub', '13100000-0000-4000-8000-000000000001', true);
do $$
declare
  v record;
  v_projection jsonb;
  v_state jsonb;
  v_comparison jsonb;
  v_item jsonb;
  v_document jsonb;
  v_delta jsonb;
  v_h2_id bigint;
begin
  select * into v from revision_fixture;
  v_projection := public.consultar_com_pedido_contrato_vigente(v.pedido_id);
  v_state := v_projection->'contract_state';
  if (v_projection->>'sequence')::integer <> 1
     or (v_projection->'source_facts'->>'revisao_id')::bigint is distinct from v.h1_id then
    raise exception 'cadeia H0 -> H1 nao preservou os fatos versionados';
  end if;
  v_comparison := v_state->'f2a_comparison';
  v_item := v_comparison#>'{itens,0}';
  v_item := jsonb_set(v_item, '{quantidade_apresentacoes}', to_jsonb(120));
  v_item := jsonb_set(v_item, '{quantidade_unidade_precificacao}', to_jsonb(2400));
  v_item := jsonb_set(v_item, '{valor_referencia_centavos}', to_jsonb(240000));
  v_item := jsonb_set(v_item, '{valor_praticado_centavos}', to_jsonb(240000));
  v_comparison := jsonb_set(v_comparison, '{itens,0}', v_item);
  v_comparison := jsonb_set(v_comparison, '{totais}', jsonb_build_object(
    'total_referencia_centavos', 242000,
    'total_praticado_centavos', 242400,
    'descontos_brutos_centavos', 0,
    'overprice_bruto_centavos', 400,
    'resultado_liquido_centavos', 400,
    'percentual_resultado_liquido', round(400::numeric * 100 / 242000, 6)
  ));
  v_document := v_state->'f2b_document';
  v_document := jsonb_set(v_document, '{itens,0,quantidade_apresentacoes}', to_jsonb(120));
  v_document := jsonb_set(v_document, '{itens,0,quantidade_unidade_precificacao}', to_jsonb(2400));
  v_document := jsonb_set(v_document, '{itens,0,valor_referencia_centavos}', to_jsonb(240000));
  v_document := jsonb_set(v_document, '{itens,0,valor_praticado_centavos}', to_jsonb(240000));
  v_document := jsonb_set(v_document, '{comparacao_comercial}', v_comparison);
  v_delta := jsonb_build_object('f2a_comparison', v_comparison, 'f2b_document', v_document);
  v_h2_id := public.solicitar_com_pedido_revisao_idempotente(
    '13600000-0000-4000-8000-000000000020', v.pedido_id, v_delta
  );
  update revision_fixture set h2_id = v_h2_id where pedido_id = v.pedido_id;
end $$;

reset role;

do $$
declare
  v record;
begin
  select * into v from revision_fixture;
  if not exists (
    select 1 from public.com_pedido_revisoes_governadas h2
    join public.com_pedido_revisoes_governadas h1 on h1.id = v.h1_id
     where h2.id = v.h2_id and h2.tipo = 'aditivo'
       and h2.sequence = 2 and h2.base_sequence = 1
       and h2.base_contract_state_sha256 = h1.resulting_contract_state_sha256
       and h2.resulting_contract_state_json#>>'{f2a_comparison,itens,0,quantidade_apresentacoes}' = '120'
  ) then
    raise exception 'H2 nao foi ancorado exatamente em H1';
  end if;
  if (public.resolver_com_pedido_contrato_vigente(v.pedido_id)#>>'{contract_state,f2a_comparison,itens,0,quantidade_apresentacoes}') <> '100'
     or (select pedido_efetivado_em from public.com_pedidos where id = v.pedido_id) is distinct from v.h1_effective_at then
    raise exception 'aditivo pendente alterou contrato vigente ou efetividade original';
  end if;
end $$;

rollback;
