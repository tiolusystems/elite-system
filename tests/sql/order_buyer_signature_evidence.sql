\set ON_ERROR_STOP on
begin;
\set f2b_fixture true
\set f2c_fixture true
\ir order_seller_commercial_confirmation.sql

do $$
begin
  if not exists (select 1 from public.permission_actions where action_key = 'pedidos.buyer_signature.view' and default_allowed = false)
     or not exists (select 1 from public.permission_actions where action_key = 'pedidos.buyer_signature.submit' and default_allowed = false)
     or not exists (select 1 from public.permission_actions where action_key = 'pedidos.buyer_signature.review' and default_allowed = false) then
    raise exception 'alçadas SIG01 devem nascer bloqueadas';
  end if;
  if (select public from storage.buckets where id = 'order-signature-evidence') is distinct from false then
    raise exception 'bucket SIG01 deve permanecer privado';
  end if;
  if has_table_privilege('authenticated', 'public.com_pedido_assinatura_evidencias', 'SELECT')
     or has_table_privilege('authenticated', 'public.com_pedido_assinatura_evidencias', 'INSERT')
     or has_table_privilege('authenticated', 'public.com_pedido_assinatura_decisoes', 'UPDATE') then
    raise exception 'fatos SIG01 foram expostos por grant direto';
  end if;
end $$;

set local role postgres;
select set_config('request.jwt.claim.sub', '13100000-0000-4000-8000-000000000003', true);
insert into public.cad_cliente_contatos(cliente_id, nome, papel, email, status, created_by, updated_by)
select client_id, 'Contato comprador SIG01', 'proprietario', 'comprador-sig01@test.invalid', 'active',
  '13100000-0000-4000-8000-000000000003', '13100000-0000-4000-8000-000000000003'
from (select client_id from f2b_context) fixture;
insert into public.user_permission_overrides(user_id, action_key, allowed, updated_by)
select user_id, action_key, true, '13100000-0000-4000-8000-000000000003'::uuid
from unnest(array[
  'pedidos.buyer_signature.view', 'pedidos.buyer_signature.submit'
]) action_key
cross join (values ('13100000-0000-4000-8000-000000000001'::uuid)) users(user_id)
union all
select user_id, action_key, true, '13100000-0000-4000-8000-000000000003'::uuid
from unnest(array['pedidos.buyer_signature.view', 'pedidos.buyer_signature.review']) action_key
cross join (values ('13100000-0000-4000-8000-000000000004'::uuid)) users(user_id)
on conflict (user_id, action_key) do update set allowed = excluded.allowed, updated_by = excluded.updated_by;

set local role authenticated;
select set_config('request.jwt.claim.sub', '13100000-0000-4000-8000-000000000001', true);
do $$
declare
  v f2b_context%rowtype;
  v_contact_id bigint;
  v_doc jsonb;
  v_evidence_id bigint;
  v_signed_at timestamptz := clock_timestamp();
begin
  select * into v from f2b_context;
  select id into v_contact_id from public.cad_cliente_contatos where cliente_id = v.client_id and email = 'comprador-sig01@test.invalid';
  v_doc := public.consultar_com_pedido_documento_assinavel(v.order_id);
  if (v_doc->>'confirmacao_comercial_id')::bigint <> v.confirmation_id
     or v_doc->>'documento_canonico_sha256' is null then raise exception 'documento SIG01 nao esta vinculado a F2B'; end if;
  begin
    perform public.registrar_com_pedido_assinatura_evidencia_idempotente(
      '13300000-0000-4000-8000-000000000009', v.order_id, v.confirmation_id,
      v_doc->>'documento_canonico_sha256', 'integrated_api', v_contact_id, null,
      repeat('a', 64), null, null, 'EXT-SIG01-FUTURO', clock_timestamp());
    raise exception 'fonte futura foi aceita na operacao manual';
  exception when others then
    if position('fonte de assinatura manual invalida' in lower(sqlerrm)) = 0 then raise; end if;
  end;
  v_evidence_id := public.registrar_com_pedido_assinatura_evidencia_idempotente(
    '13300000-0000-4000-8000-000000000001', v.order_id, v.confirmation_id,
    v_doc->>'documento_canonico_sha256', 'external_digital', v_contact_id,
    'pending/13100000-0000-4000-8000-000000000001/13300000-0000-4000-8000-000000000001/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    repeat('a', 64), null, null, 'EXT-SIG01-001', v_signed_at);
  if (select status from public.consultar_com_pedido_assinaturas(v.order_id) where evidencia_id = v_evidence_id) <> 'PENDING' then
    raise exception 'upload ou referencia de assinatura nao deve equivaler a aceite';
  end if;
  if public.registrar_com_pedido_assinatura_evidencia_idempotente(
    '13300000-0000-4000-8000-000000000001', v.order_id, v.confirmation_id,
    v_doc->>'documento_canonico_sha256', 'external_digital', v_contact_id,
    'pending/13100000-0000-4000-8000-000000000001/13300000-0000-4000-8000-000000000001/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    repeat('a', 64), null, null, 'EXT-SIG01-001', v_signed_at) <> v_evidence_id then
    raise exception 'retry identico de evidencia nao retornou o mesmo fato';
  end if;
  if (select status from public.com_pedidos where id = v.order_id) <> 'blocked' then raise exception 'SIG01 alterou o pedido'; end if;
end $$;

select set_config('request.jwt.claim.sub', '13100000-0000-4000-8000-000000000004', true);
do $$
declare
  v f2b_context%rowtype;
  v_evidence_id bigint;
  v_decision_id bigint;
begin
  select * into v from f2b_context;
  select evidencia_id into v_evidence_id from public.consultar_com_pedido_assinaturas(v.order_id) limit 1;
  v_decision_id := public.decidir_com_pedido_assinatura_idempotente(
    '13300000-0000-4000-8000-000000000002', v_evidence_id, 'ACCEPTED', 'Evidencia conferida pelo revisor SIG01.'
  );
  if (select status from public.consultar_com_pedido_assinaturas(v.order_id) where evidencia_id = v_evidence_id) <> 'ACCEPTED' then raise exception 'aceite SIG01 nao foi registrado'; end if;
  if (select status from public.com_pedidos where id = v.order_id) <> 'blocked' then raise exception 'aceite SIG01 abriu o pedido'; end if;
  if public.decidir_com_pedido_assinatura_idempotente('13300000-0000-4000-8000-000000000002', v_evidence_id, 'ACCEPTED', 'Evidencia conferida pelo revisor SIG01.') <> v_decision_id then raise exception 'retry identico de decisao nao retornou o mesmo fato'; end if;
  begin
    perform public.decidir_com_pedido_assinatura_idempotente('13300000-0000-4000-8000-000000000003', v_evidence_id, 'REJECTED', 'Outra decisao');
    raise exception 'segunda decisao foi aceita';
  exception when others then
    if position('ja decidida' in lower(sqlerrm)) = 0 then raise; end if;
  end;
end $$;

set local role postgres;
do $$
declare v f2b_context%rowtype;
begin
  select * into v from f2b_context;
  begin
    update public.com_pedido_assinatura_evidencias set fonte = 'gov_br' where pedido_id = v.order_id;
    raise exception 'evidencia SIG01 aceitou UPDATE';
  exception when others then
    if position('append-only' in lower(sqlerrm)) = 0 then raise; end if;
  end;
  begin
    truncate public.com_pedido_assinatura_evidencias cascade;
    raise exception 'evidencia SIG01 aceitou TRUNCATE';
  exception when others then
    if position('append-only' in lower(sqlerrm)) = 0 then raise; end if;
  end;
end $$;
rollback;
