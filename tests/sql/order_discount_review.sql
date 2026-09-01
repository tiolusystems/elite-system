\set ON_ERROR_STOP on
-- Reuse the authenticated F2B fixture so F2C exercises the canonical order,
-- snapshot, comparison and manager-gate contracts in one transaction.
-- Cases: BELOW_REFERENCE, mixed below and above, idempotency, outside order scope,
-- append-only, L and kg/un, direct write.
\set f2c_fixture true
\ir order_seller_commercial_confirmation.sql

set local role postgres;
select set_config('request.jwt.claim.sub', '13100000-0000-4000-8000-000000000003', true);
insert into public.cad_cliente_contatos(cliente_id, nome, papel, email, status, created_by, updated_by)
select client_id, 'Contato comprador F2C', 'proprietario', 'comprador-f2c@test.invalid', 'active',
  '13100000-0000-4000-8000-000000000003', '13100000-0000-4000-8000-000000000003'
from (select client_id from f2b_context) fixture;
create temporary table f2c_signature_context(contact_id bigint) on commit drop;
insert into f2c_signature_context(contact_id)
select id from public.cad_cliente_contatos where email = 'comprador-f2c@test.invalid';
grant select on f2c_signature_context to authenticated;
insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
select user_id, action_key, true, '13100000-0000-4000-8000-000000000003'::uuid
from unnest(array['pedidos.buyer_signature.view', 'pedidos.buyer_signature.submit']) action_key
cross join (values ('13100000-0000-4000-8000-000000000001'::uuid)) users(user_id)
union all
select user_id, action_key, true, '13100000-0000-4000-8000-000000000003'::uuid
from unnest(array['pedidos.buyer_signature.view', 'pedidos.buyer_signature.review']) action_key
cross join (values ('13100000-0000-4000-8000-000000000004'::uuid)) users(user_id)
on conflict (user_id, action_key) do update set allowed = excluded.allowed, updated_by = excluded.updated_by;

select set_config('request.jwt.claim.sub', '13100000-0000-4000-8000-000000000001', true);
set local role authenticated;
do $$
declare
  v f2b_context%rowtype;
  v_no_discount_proposal jsonb;
  v_no_discount_preview jsonb;
  v_no_discount_result jsonb;
  v_rejected_result jsonb;
  v_mixed_hash text;
  v_no_discount_hash text;
  v_rejected_hash text;
  v_documento_sha256 text;
  v_discount_decision_id bigint;
  v_credit_decision_id bigint;
  v_evidence_id bigint;
  v_contact_id bigint;
  v_no_discount_order bigint;
  v_no_discount_confirmation bigint;
  v_rejected_order bigint;
begin
  select * into v from f2b_context;
  v_no_discount_proposal := jsonb_set(jsonb_set(jsonb_set(v.proposal, '{itens,0,preco_praticado_centavos_por_unidade_precificacao}', '100'::jsonb), '{itens,1,preco_praticado_centavos_por_unidade_precificacao}', '120'::jsonb), '{parcelas,0,valor_centavos}', '4400'::jsonb);
  v_no_discount_preview := public.prever_com_revisao_comercial_venda(v_no_discount_proposal);
  v_no_discount_result := public.confirmar_com_revisao_comercial_venda_idempotente('13100000-0000-4000-8000-000000000030', v_no_discount_proposal, v_no_discount_preview->>'preview_hash', null, false);
  v_no_discount_order := (v_no_discount_result->>'pedido_id')::bigint;
  v_no_discount_confirmation := (v_no_discount_result->>'confirmacao_comercial_id')::bigint;
  v_no_discount_hash := encode(extensions.digest(convert_to(public.consultar_com_comparacao_comercial_pedido(v_no_discount_order)::text, 'UTF8'), 'sha256'), 'hex');
  begin
    perform public.registrar_com_pedido_decisao_desconto_idempotente('13100000-0000-4000-8000-000000000031', v_no_discount_order, v_no_discount_confirmation, v_no_discount_hash, 'REJECTED', 'Nao ha desconto comercial neste pedido.');
    raise exception 'pedido sem desconto aceitou revisao';
  exception when others then
    if position('nao possui desconto comercial pendente' in lower(sqlerrm)) = 0 then raise exception 'pedido sem desconto falhou pelo motivo incorreto: %', sqlerrm; end if;
  end;

  v_rejected_result := public.confirmar_com_revisao_comercial_venda_idempotente('13100000-0000-4000-8000-000000000032', v.proposal, v.preview->>'preview_hash', 'Desconto rejeitado no teste dirigido.', true);
  v_rejected_order := (v_rejected_result->>'pedido_id')::bigint;
  v_mixed_hash := encode(extensions.digest(convert_to(public.consultar_com_comparacao_comercial_pedido(v.order_id)::text, 'UTF8'), 'sha256'), 'hex');
  v_rejected_hash := encode(extensions.digest(convert_to(public.consultar_com_comparacao_comercial_pedido((v_rejected_result->>'pedido_id')::bigint)::text, 'UTF8'), 'sha256'), 'hex');
  v_documento_sha256 := public.consultar_com_confirmacao_comercial_pedido(v.order_id)->>'documento_canonico_sha256';
  select contact_id into v_contact_id from f2c_signature_context;
  perform set_config('request.jwt.claim.sub', '13100000-0000-4000-8000-000000000004', true);
  if not exists (select 1 from public.consultar_com_pedidos_revisao_desconto() where pedido_id = v.order_id and decisao is null) then
    raise exception 'pedido misto abaixo/acima deveria estar pendente de revisao';
  end if;
  if (select count(*) from public.consultar_com_pedidos_revisao_desconto() where pedido_id = v.order_id) <> 1 then
    raise exception 'fila F2C nao e uma fila somente de pendencias';
  end if;

  v_credit_decision_id := public.registrar_com_pedido_decisao_gerencial_idempotente(
    '13100000-0000-4000-8000-000000000040', v.order_id, 'liberado',
    'Credito reconhecido antes da aprovacao de desconto.'
  );
  if not exists (
    select 1 from public.com_pedido_credito_decisoes decision
     where decision.id = v_credit_decision_id
       and decision.confirmacao_comercial_id = v.confirmation_id
       and decision.documento_comercial_sha256 = v_documento_sha256
       and decision.status_resultante = 'blocked'
  ) then raise exception 'credito independente nao foi vinculado a F2B mantendo o pedido bloqueado'; end if;
  if (select status from public.com_pedidos where id = v.order_id) <> 'blocked'
     or (select pedido_efetivado_em from public.com_pedidos where id = v.order_id) is not null
     or not ((public.consultar_com_pedido_efetividade(v.order_id)->'pending_conditions') ? 'APROVACAO_DESCONTO') then
    raise exception 'credito antes de F2C nao preservou o bloqueio de efetividade';
  end if;

  perform set_config('request.jwt.claim.sub', '13100000-0000-4000-8000-000000000001', true);
  v_evidence_id := public.registrar_com_pedido_assinatura_evidencia_idempotente(
    '13100000-0000-4000-8000-000000000041', v.order_id, v.confirmation_id,
    v_documento_sha256, 'external_digital', v_contact_id,
    'pending/13100000-0000-4000-8000-000000000001/13100000-0000-4000-8000-000000000041/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    repeat('b', 64), null, null, 'F2C-SIG-001', clock_timestamp()
  );
  perform set_config('request.jwt.claim.sub', '13100000-0000-4000-8000-000000000004', true);
  perform public.decidir_com_pedido_assinatura_idempotente(
    '13100000-0000-4000-8000-000000000042', v_evidence_id, 'ACCEPTED', null
  );
  if (select status from public.com_pedidos where id = v.order_id) <> 'blocked'
     or not ((public.consultar_com_pedido_efetividade(v.order_id)->'pending_conditions') ? 'APROVACAO_DESCONTO') then
    raise exception 'assinatura aceita nao pode atravessar F2C pendente';
  end if;

  begin
    perform public.registrar_com_pedido_decisao_desconto_idempotente('13100000-0000-4000-8000-000000000033', v.order_id, v.confirmation_id, repeat('0', 64), 'APPROVED', 'Fingerprint deliberadamente incorreto.');
    raise exception 'fingerprint divergente foi aceito';
  exception when others then
    if position('fingerprint da comparacao comercial divergente' in lower(sqlerrm)) = 0 then raise exception 'fingerprint divergente falhou pelo motivo incorreto: %', sqlerrm; end if;
  end;

  v_discount_decision_id := public.registrar_com_pedido_decisao_desconto_idempotente('13100000-0000-4000-8000-000000000034', v.order_id, v.confirmation_id, v_mixed_hash, 'APPROVED', 'Aprovacao do desconto misto F2C.');
  if public.registrar_com_pedido_decisao_desconto_idempotente('13100000-0000-4000-8000-000000000034', v.order_id, v.confirmation_id, v_mixed_hash, 'APPROVED', 'Aprovacao do desconto misto F2C.') <> v_discount_decision_id then raise exception 'retry identico nao retornou o mesmo fato'; end if;
  begin
    perform public.registrar_com_pedido_decisao_desconto_idempotente('13100000-0000-4000-8000-000000000034', v.order_id, v.confirmation_id, v_mixed_hash, 'APPROVED', 'Payload divergente para retry.');
    raise exception 'retry divergente foi aceito';
  exception when others then
    if position('payload divergente' in lower(sqlerrm)) = 0 then raise exception 'retry divergente falhou pelo motivo incorreto: %', sqlerrm; end if;
  end;
  if not exists (
    select 1 from public.com_pedido_credito_decisoes
     where id = v_credit_decision_id
       and confirmacao_comercial_id = v.confirmation_id
       and documento_comercial_sha256 = v_documento_sha256
  ) then raise exception 'aprovacao F2C alterou ou invalidou o fato de credito vigente'; end if;
  if (select status from public.com_pedidos where id = v.order_id) <> 'open'
     or (select pedido_efetivado_em from public.com_pedidos where id = v.order_id) is null then
    raise exception 'pedido nao efetivou somente apos todos os gates da versao F2B';
  end if;

  perform public.registrar_com_pedido_decisao_desconto_idempotente('13100000-0000-4000-8000-000000000039', v_rejected_order, (v_rejected_result->>'confirmacao_comercial_id')::bigint, v_rejected_hash, 'REJECTED', 'Desconto rejeitado de forma explicita.');
  if exists (select 1 from public.consultar_com_pedidos_revisao_desconto() where pedido_id = v_rejected_order) then raise exception 'decisao rejeitada voltou a aparecer como pendencia'; end if;
  begin
    perform public.registrar_com_pedido_decisao_desconto_idempotente(
      '13100000-0000-4000-8000-000000000035', v_rejected_order,
      (v_rejected_result->>'confirmacao_comercial_id')::bigint, v_rejected_hash,
      'APPROVED', 'Segunda chave na mesma versao rejeitada.'
    );
    raise exception 'segunda chave na mesma versao foi aceita';
  exception when unique_violation then null;
  end;
  if public.registrar_com_pedido_decisao_gerencial_idempotente(
    '13100000-0000-4000-8000-000000000037', v_rejected_order, 'liberado',
    'Credito permanece independente de desconto rejeitado.'
  ) is null then raise exception 'credito independente rejeitado nao foi registrado'; end if;
  if (select status from public.com_pedidos where id = v_rejected_order) <> 'blocked'
     or (select pedido_efetivado_em from public.com_pedidos where id = v_rejected_order) is not null then
    raise exception 'desconto rejeitado nao pode efetivar pedido';
  end if;
end
$$;

select set_config('request.jwt.claim.sub', '13100000-0000-4000-8000-000000000002', true);
set local role authenticated;
do $$
declare v f2b_context%rowtype;
begin
  select * into v from f2b_context;
  begin
    perform public.registrar_com_pedido_decisao_desconto_idempotente('13100000-0000-4000-8000-000000000038', v.order_id, v.confirmation_id, v.preview->>'preview_hash', 'APPROVED', 'Usuario sem permissao F2C.');
    raise exception 'usuario sem permissao registrou decisao';
  exception when others then
    if position('not allowed' in lower(sqlerrm)) = 0 then raise; end if;
  end;
end
$$;
reset role;

select set_config('request.jwt.claim.sub', '13100000-0000-4000-8000-000000000004', true);
set local role authenticated;
do $$
begin
  begin
    perform public.registrar_com_pedido_decisao_desconto_idempotente('13100000-0000-4000-8000-000000000041', 999999999, 999999999, repeat('0', 64), 'APPROVED', 'Pedido fora do escopo operacional.');
    raise exception 'pedido fora do escopo aceitou decisao';
  exception when others then
    if position('fora do escopo' in lower(sqlerrm)) = 0 then raise exception 'escopo falhou pelo motivo incorreto: %', sqlerrm; end if;
  end;
end
$$;
reset role;

set local role authenticated;
do $$
begin
  if has_table_privilege('authenticated', 'public.com_pedido_decisoes_desconto', 'INSERT') or has_table_privilege('authenticated', 'public.com_pedido_decisoes_desconto', 'UPDATE') or has_table_privilege('authenticated', 'public.com_pedido_decisoes_desconto', 'DELETE') then raise exception 'escrita direta no fato F2C esta aberta'; end if;
  begin
    insert into public.com_pedido_decisoes_desconto(pedido_id, confirmacao_comercial_id, comparacao_sha256, decisao, justificativa, decided_by)
    values (0, 0, repeat('0', 64), 'REJECTED', 'Escrita direta proibida.', auth.uid());
    raise exception 'INSERT direto no fato F2C foi aceito';
  exception when insufficient_privilege then null; end;
  begin
    update public.com_pedido_decisoes_desconto set justificativa = 'alteracao direta.';
    raise exception 'UPDATE direto no fato F2C foi aceito';
  exception when insufficient_privilege then null; end;
  begin
    delete from public.com_pedido_decisoes_desconto;
    raise exception 'DELETE direto no fato F2C foi aceito';
  exception when insufficient_privilege then null; end;
  begin
    truncate public.com_pedido_decisoes_desconto;
    raise exception 'TRUNCATE direto no fato F2C foi aceito';
  exception when insufficient_privilege then null; end;
end
$$;
reset role;

rollback;
select 'F2C behavioral smoke passed: pending queue, no-discount refusal, approval gate, rejection, fingerprint, idempotency, scope, and direct-write protections' as f2c_smoke;
