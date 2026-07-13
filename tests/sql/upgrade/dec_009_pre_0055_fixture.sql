do $$
declare
  v_actor uuid := public.historical_migration_actor_id();
  v_client_id bigint;
  v_person_id bigint;
  v_order_id bigint;
begin
  insert into public.cad_clientes(
    nome, nome_norm, cidade, uf, status, apelidos_json, payload_origem_json,
    created_by, updated_by, origem_dados
  ) values (
    'Cliente upgrade DEC-009', 'cliente upgrade dec-009', 'Campinas', 'SP',
    'active', '[]'::jsonb, '{}'::jsonb, v_actor, v_actor, 'sistema'
  ) returning id into v_client_id;

  insert into public.cad_pessoas_comerciais(
    nome, nome_norm, papeis_json, status, payload_origem_json,
    created_by, updated_by, origem_dados
  ) values (
    'Vendedor upgrade DEC-009', 'vendedor upgrade dec-009', '["vendedor"]'::jsonb,
    'active', '{}'::jsonb, v_actor, v_actor, 'sistema'
  ) returning id into v_person_id;

  insert into public.com_pedidos(
    codigo_pedido, cliente_id, tipo_pedido, status, data_pedido,
    condicao_pagamento, origem_canal, valor_total,
    created_by, updated_by, origem_dados
  ) values (
    'DEC009-UPGRADE', v_client_id, 'venda', 'fulfilled', current_date,
    '30/60', 'interno', 1000, v_actor, v_actor, 'sistema'
  ) returning id into v_order_id;

  insert into public.com_pedido_comissionados(
    pedido_id, pessoa_id, papel_comissao, percentual_comissao,
    valor_base, valor_previsto, status, created_by, updated_by
  ) values (
    v_order_id, v_person_id, 'vendedor', 5, 1000, 50,
    'paga', v_actor, v_actor
  );
end;
$$;
