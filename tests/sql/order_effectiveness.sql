\set ON_ERROR_STOP on
\set f2c_fixture 1
\ir order_seller_commercial_confirmation.sql

-- Reutiliza a fixture governada de F2B e executa os gates em uma transacao
-- descartavel, sem duplicar cadastros ou persistir dados sintéticos.
do $$
declare
  v f2b_context%rowtype;
  v_contact_id bigint;
begin
  select * into v from f2b_context;
  insert into public.cad_cliente_contatos(
    cliente_id, propriedade_id, nome, papel, email, status, created_by, updated_by
  ) values (
    v.client_id, v.property_id, 'Contato efetividade 0135', 'comprador',
    'efetividade-0135@test.invalid', 'active',
    '13100000-0000-4000-8000-000000000003',
    '13100000-0000-4000-8000-000000000003'
  ) returning id into v_contact_id;
  insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
  select '13100000-0000-4000-8000-000000000001'::uuid, action_key, true,
         '13100000-0000-4000-8000-000000000003'::uuid
    from unnest(array[
      'pedidos.buyer_signature.view', 'pedidos.buyer_signature.submit',
      'pedidos.buyer_signature.review'
    ]) action_key
  on conflict (user_id, action_key) do update set allowed = excluded.allowed,
    updated_by = excluded.updated_by;
  create temporary table effectiveness_fixture(
    mixed_order_id bigint not null,
    mixed_confirmation_id bigint not null,
    mixed_hash text not null,
    contact_id bigint not null,
    no_discount_order_id bigint,
    no_discount_confirmation_id bigint,
    no_discount_hash text,
    reverse_order_id bigint,
    reverse_confirmation_id bigint,
    reverse_hash text,
    rejected_order_id bigint,
    rejected_confirmation_id bigint,
    rejected_hash text
  ) on commit drop;
  insert into effectiveness_fixture(mixed_order_id, mixed_confirmation_id, mixed_hash, contact_id)
  values (
    v.order_id, v.confirmation_id,
    (select documento_canonico_sha256 from public.com_pedido_confirmacoes_comerciais where id = v.confirmation_id),
    v_contact_id
  );
  grant select, update on effectiveness_fixture to authenticated;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '13100000-0000-4000-8000-000000000001', true);

do $$
declare
  v f2b_context%rowtype;
  v_proposal jsonb;
  v_preview jsonb;
  v_result jsonb;
begin
  select * into v from f2b_context;
  v_proposal := jsonb_set(
    jsonb_set(
      jsonb_set(v.proposal, '{itens,0,preco_praticado_centavos_por_unidade_precificacao}', '100'),
      '{itens,1,preco_praticado_centavos_por_unidade_precificacao}', '100'
    ),
    '{parcelas,0,valor_centavos}', '4000'
  );
  v_preview := public.prever_com_revisao_comercial_venda(v_proposal);
  if (v_preview->>'complete_for_confirmation')::boolean is not true
     or (v_preview->>'possui_desconto')::boolean is true then
    raise exception 'fixture sem desconto nao ficou completa';
  end if;
  v_result := public.confirmar_com_revisao_comercial_venda_idempotente(
    '13500000-0000-0000-0000-000000000001', v_proposal,
    v_preview->>'preview_hash', null, false
  );
  update effectiveness_fixture
     set no_discount_order_id = (v_result->>'pedido_id')::bigint,
         no_discount_confirmation_id = (v_result->>'confirmacao_comercial_id')::bigint,
         no_discount_hash = v_result->>'documento_canonico_sha256';

  v_result := public.confirmar_com_revisao_comercial_venda_idempotente(
    '13500000-0000-0000-0000-000000000002', v_proposal,
    v_preview->>'preview_hash', null, false
  );
  update effectiveness_fixture
     set reverse_order_id = (v_result->>'pedido_id')::bigint,
         reverse_confirmation_id = (v_result->>'confirmacao_comercial_id')::bigint,
         reverse_hash = v_result->>'documento_canonico_sha256';

  v_proposal := v.proposal;
  v_preview := public.prever_com_revisao_comercial_venda(v_proposal);
  v_result := public.confirmar_com_revisao_comercial_venda_idempotente(
    '13500000-0000-0000-0000-000000000003', v_proposal,
    v_preview->>'preview_hash', 'Desconto rejeitado no smoke de efetividade.', true
  );
  update effectiveness_fixture
     set rejected_order_id = (v_result->>'pedido_id')::bigint,
         rejected_confirmation_id = (v_result->>'confirmacao_comercial_id')::bigint,
         rejected_hash = v_result->>'documento_canonico_sha256';
end $$;

do $$
declare
  v record;
  v_evidence_id bigint;
begin
  select * into v from effectiveness_fixture;
  v_evidence_id := public.registrar_com_pedido_assinatura_evidencia_idempotente(
    '13500000-0000-4000-8000-000000000010', v.mixed_order_id,
    v.mixed_confirmation_id, v.mixed_hash, 'external_digital', v.contact_id,
    'pending/13100000-0000-4000-8000-000000000001/13500000-0000-4000-8000-000000000010/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', repeat('a', 64), 'application/pdf', 10, 'REF-0135-MIXED', timestamptz '2000-01-01 00:00:00+00'
  );
  if (select status from public.consultar_com_pedido_assinaturas(v.mixed_order_id) where evidencia_id = v_evidence_id) <> 'PENDING' then
    raise exception 'evidencia de assinatura nao permaneceu pendente antes da revisao';
  end if;
  perform public.decidir_com_pedido_assinatura_idempotente(
    '13500000-0000-4000-8000-000000000011', v_evidence_id, 'ACCEPTED', null
  );
  if (select status from public.com_pedidos where id = v.mixed_order_id) <> 'blocked' then
    raise exception 'assinatura aceita sem credito abriu pedido';
  end if;
  if (select pedido_efetivado_em from public.com_pedidos where id = v.mixed_order_id) is not null then
    raise exception 'assinatura aceitou efetividade retroativa';
  end if;
  -- Retry: a mesma chave passa pelo wrapper novamente e não cria nova efetividade.
  perform public.decidir_com_pedido_assinatura_idempotente(
    '13500000-0000-4000-8000-000000000011', v_evidence_id, 'ACCEPTED', null
  );
end $$;

do $$
declare
  v record;
  v_evidence_id bigint;
begin
  select * into v from effectiveness_fixture;
  -- Sem BELOW_REFERENCE, assinatura aceita + credito liberado e suficiente.
  v_evidence_id := public.registrar_com_pedido_assinatura_evidencia_idempotente(
    '13500000-0000-0000-0000-000000000012', v.no_discount_order_id,
    v.no_discount_confirmation_id, v.no_discount_hash, 'external_digital', v.contact_id,
    'pending/13100000-0000-4000-8000-000000000001/13500000-0000-0000-0000-000000000012/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', repeat('b', 64), 'application/pdf', 10, 'REF-0135-NODISCOUNT', timestamptz '2000-01-01 00:00:00+00'
  );
  perform public.decidir_com_pedido_assinatura_idempotente(
    '13500000-0000-0000-0000-000000000013', v_evidence_id, 'ACCEPTED', null
  );
  if (select status from public.com_pedidos where id = v.no_discount_order_id) <> 'blocked' then
    raise exception 'assinatura sem credito abriu venda sem desconto';
  end if;
end $$;

do $$
declare
  v record;
  v_evidence_id bigint;
begin
  select * into v from effectiveness_fixture;
  v_evidence_id := public.registrar_com_pedido_assinatura_evidencia_idempotente(
    '13500000-0000-0000-0000-000000000016', v.rejected_order_id,
    v.rejected_confirmation_id, v.rejected_hash, 'external_digital', v.contact_id,
    'pending/13100000-0000-4000-8000-000000000001/13500000-0000-0000-0000-000000000016/dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd', repeat('d', 64), 'application/pdf', 10, 'REF-0135-REJECTED', timestamptz '2000-01-01 00:00:00+00'
  );
  perform public.decidir_com_pedido_assinatura_idempotente(
    '13500000-0000-0000-0000-000000000017', v_evidence_id, 'ACCEPTED', null
  );
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '13100000-0000-4000-8000-000000000004', true);

do $$
declare
  v record;
begin
  select * into v from effectiveness_fixture;
  -- Ordem reversa: credito reconhecido primeiro ainda deixa a venda bloqueada.
  perform public.registrar_com_pedido_decisao_credito(
    v.reverse_order_id, 'liberado', null, 10000, 0, 'Credito primeiro no smoke'
  );
  if not exists (
    select 1 from public.com_pedido_credito_decisoes decision
     where decision.pedido_id = v.reverse_order_id and decision.decisao = 'liberado'
  ) then
    raise exception 'credito primeiro nao registrou o fato';
  end if;
  if (select status from public.com_pedidos where id = v.reverse_order_id) <> 'blocked' then
    raise exception 'credito reconhecido primeiro abriu pedido';
  end if;
  perform public.registrar_com_pedido_decisao_credito(
    v.rejected_order_id, 'liberado', null, 10000, 0, 'Credito antes de F2C rejeitado'
  );
  if not exists (
    select 1 from public.com_pedido_credito_decisoes decision
     where decision.pedido_id = v.rejected_order_id and decision.decisao = 'liberado'
  ) then
    raise exception 'credito da ordem rejeitada nao registrou o fato';
  end if;
  -- Uma rejeicao F2C e terminal para a versao, portanto permanece bloqueada.
  perform public.registrar_com_pedido_decisao_desconto_idempotente(
    '13500000-0000-0000-0000-000000000021', v.rejected_order_id,
    v.rejected_confirmation_id,
    (select comparacao_sha256 from public.consultar_com_pedidos_revisao_desconto() where pedido_id = v.rejected_order_id),
    'REJECTED', 'Desconto rejeitado no teste comportamental.'
  );
  if (select status from public.com_pedidos where id = v.rejected_order_id) <> 'blocked' then
    raise exception 'F2C rejeitado alterou efetividade';
  end if;
  if (select pedido_efetivado_em from public.com_pedidos where id = v.rejected_order_id) is not null then
    raise exception 'F2C rejeitado produziu efetividade';
  end if;
  begin
    perform public.registrar_com_pedido_decisao_credito(
      v.mixed_order_id, 'liberado', null, 10000, 0, 'Credito sem aprovacao F2C'
    );
    if (select status from public.com_pedidos where id = v.mixed_order_id) <> 'blocked' then
      raise exception 'credito sem F2C abriu pedido';
    end if;
    if not exists (
      select 1 from public.com_pedido_credito_decisoes decision
       where decision.pedido_id = v.mixed_order_id and decision.decisao = 'liberado'
    ) then
      raise exception 'credito sem F2C nao registrou o fato';
    end if;
  exception when others then
    raise;
  end;
end $$;

reset role;
do $$
declare
  v record;
begin
  select * into v from effectiveness_fixture;
  -- O alvo ainda esta blocked: a mutacao direta deve ser recusada pelo guard.
  begin
    update public.com_pedidos set status = 'open' where id = v.reverse_order_id;
    raise exception 'blocked -> open direto foi aceito';
  exception when others then
    if position('efetivacao governada' in lower(sqlerrm)) = 0 then
      raise exception 'bypass direto falhou pelo motivo incorreto: %', sqlerrm;
    end if;
  end;
  -- O pedido sem F2B vigente representa a fronteira executavel para fatos
  -- antigos: ausencia de versao corrente nunca libera efetividade.
  if (select status from public.com_pedidos where id = (select legacy_order_id from f2b_context)) <> 'blocked'
     or (select pedido_efetivado_em from public.com_pedidos where id = (select legacy_order_id from f2b_context)) is not null then
    raise exception 'fato sem F2B corrente nao permaneceu bloqueado';
  end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '13100000-0000-4000-8000-000000000001', true);

do $$
declare
  v record;
  v_evidence_id bigint;
begin
  select * into v from effectiveness_fixture;
  -- Fechamento da ordem reversa: assinatura aceita depois do credito abre.
  v_evidence_id := public.registrar_com_pedido_assinatura_evidencia_idempotente(
    '13500000-0000-0000-0000-000000000014', v.reverse_order_id,
    v.reverse_confirmation_id, v.reverse_hash, 'external_digital', v.contact_id,
    'pending/13100000-0000-4000-8000-000000000001/13500000-0000-0000-0000-000000000014/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc', repeat('c', 64), 'application/pdf', 10, 'REF-0135-REVERSE', timestamptz '2000-01-01 00:00:00+00'
  );
  perform public.decidir_com_pedido_assinatura_idempotente(
    '13500000-0000-0000-0000-000000000015', v_evidence_id, 'ACCEPTED', null
  );
  if (select status from public.com_pedidos where id = v.reverse_order_id) <> 'open' then
    raise exception 'assinatura aceita depois do credito nao abriu pedido';
  end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '13100000-0000-4000-8000-000000000004', true);

do $$
declare
  v record;
begin
  select * into v from effectiveness_fixture;
  perform public.registrar_com_pedido_decisao_credito(
    v.no_discount_order_id, 'liberado', null, 10000, 0, 'Credito sem desconto'
  );
  if (select status from public.com_pedidos where id = v.no_discount_order_id) <> 'open' then
    raise exception 'credito + assinatura sem desconto nao abriu pedido';
  end if;
end $$;

do $$
declare
  v record;
  v_credit_id bigint;
begin
  select * into v from effectiveness_fixture;
  perform public.registrar_com_pedido_decisao_desconto_idempotente(
    '13500000-0000-0000-0000-000000000020', v.mixed_order_id,
    v.mixed_confirmation_id,
    (select comparacao_sha256 from public.consultar_com_pedidos_revisao_desconto() where pedido_id = v.mixed_order_id),
    'APPROVED', 'Aprovacao F2C para liberar o teste de efetividade.'
  );
  if (select status from public.com_pedidos where id = v.mixed_order_id) <> 'open' then
    raise exception 'F2C + credito + assinatura nao abriu pedido';
  end if;
  if (select pedido_efetivado_em from public.com_pedidos where id = v.mixed_order_id) is null then
    raise exception 'pedido aberto sem timestamp de efetividade';
  end if;
  perform set_config('request.jwt.claim.sub', '13100000-0000-4000-8000-000000000001', true);
  if not exists (
    select 1
      from public.com_pedidos order_row
      join lateral public.consultar_com_pedido_assinaturas(order_row.id) evidence on true
     where order_row.id = v.mixed_order_id
       and order_row.pedido_efetivado_em > evidence.declarado_assinado_em
  ) then
    raise exception 'efetividade dependeu do horario declarado da assinatura';
  end if;
end $$;

reset role;

do $$
declare v record;
begin
  select * into v from effectiveness_fixture;
  if (select count(*) from public.action_logs event
       where event.entity_type = 'com_pedidos'
         and event.entity_id = v.mixed_order_id::text
         and event.action = 'pedidos.pedido_efetivado') <> 1 then
    raise exception 'efetividade gerou mais de um evento de auditoria';
  end if;
end $$;

do $$
declare
  v record;
begin
  select * into v from effectiveness_fixture;
  begin
    update public.com_pedidos set pedido_efetivado_em = clock_timestamp() where id = v.mixed_order_id;
    raise exception 'mutacao do timestamp de efetividade foi aceita';
  exception when others then
    if position('imutavel' in lower(sqlerrm)) = 0 then
      raise exception 'mutacao do timestamp falhou pelo motivo incorreto: %', sqlerrm;
    end if;
  end;
  if public.com_pedido_efetividade_estado(v.mixed_order_id)->>'credit_decision_id' is null
     or public.com_pedido_efetividade_estado(v.mixed_order_id)->>'signature_evidence_id' is null
     or public.com_pedido_efetividade_estado(v.mixed_order_id)->>'signature_decision_id' is null
     or public.com_pedido_efetividade_estado(v.mixed_order_id)->>'discount_decision_id' is null
     or public.com_pedido_efetividade_estado(v.mixed_order_id)->>'current_f2b_confirmation_id' <> v.mixed_confirmation_id::text then
    raise exception 'estado de efetividade nao expoe IDs exatos dos gates';
  end if;
end $$;

rollback;
