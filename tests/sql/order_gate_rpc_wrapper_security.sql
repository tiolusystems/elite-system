\set ON_ERROR_STOP on

-- 0140 closes the ACL inherited by the implementation helpers renamed in 0135.
do $$
declare
  v_discount_wrapper oid;
  v_signature_wrapper oid;
  v_discount_helper oid;
  v_signature_helper oid;
  v_definition text;
  v_definitions text[];
begin
  v_definitions := ARRAY[pg_get_functiondef(v_discount_wrapper), pg_get_functiondef(v_signature_wrapper)];
  select p.oid into v_discount_wrapper
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'registrar_com_pedido_decisao_desconto_idempotente'
     and pg_get_function_identity_arguments(p.oid) = 'p_idempotency_key uuid, p_pedido_id bigint, p_confirmacao_comercial_id bigint, p_comparacao_sha256 text, p_decisao text, p_justificativa text';
  select p.oid into v_signature_wrapper
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'decidir_com_pedido_assinatura_idempotente'
     and pg_get_function_identity_arguments(p.oid) = 'p_idempotency_key uuid, p_evidencia_id bigint, p_decisao text, p_justificativa text';
  select p.oid into v_discount_helper
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'registrar_com_pedido_decisao_desconto_idempotente_impl_0135';
  select p.oid into v_signature_helper
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'decidir_com_pedido_assinatura_idempotente_impl_0135';

  if v_discount_wrapper is null or v_signature_wrapper is null
     or v_discount_helper is null or v_signature_helper is null then
    raise exception '0140 order gate functions are incomplete';
  end if;
  if not has_function_privilege('authenticated', v_discount_wrapper, 'EXECUTE')
     or not has_function_privilege('authenticated', v_signature_wrapper, 'EXECUTE') then
    raise exception 'canonical order gate wrappers are not authenticated entrypoints';
  end if;
  if has_function_privilege('public', v_discount_helper, 'EXECUTE')
     or has_function_privilege('anon', v_discount_helper, 'EXECUTE')
     or has_function_privilege('authenticated', v_discount_helper, 'EXECUTE')
     or has_function_privilege('public', v_signature_helper, 'EXECUTE')
     or has_function_privilege('anon', v_signature_helper, 'EXECUTE')
     or has_function_privilege('authenticated', v_signature_helper, 'EXECUTE') then
    raise exception 'private order gate helper remains executable by an application role';
  end if;
  foreach v_definition in array v_definitions loop
    if v_definition !~* 'security definer'
       or v_definition !~* 'search_path\s*=\s*public'
       or v_definition !~* 'require_current_user_permission' then
      raise exception 'order gate wrapper is missing hardened security contract';
    end if;
  end loop;
  if strpos(lower(pg_get_functiondef(v_signature_wrapper)), 'require_current_user_permission')
     > strpos(lower(pg_get_functiondef(v_signature_wrapper)), 'decidir_com_pedido_assinatura_idempotente_impl_0135') then
    raise exception 'signature wrapper reads/executes the helper before authorization';
  end if;
end
$$;

-- Direct application-role calls to the private helpers must fail at the ACL
-- boundary, independently of their internal implementation.
set role authenticated;
do $$
begin
  begin
    perform public.registrar_com_pedido_decisao_desconto_idempotente_impl_0135(
      '14000000-0000-4000-8000-000000000001', 0, 0, repeat('0', 64), 'APPROVED', 'nao deve executar'
    );
    raise exception 'authenticated invoked private discount helper';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.decidir_com_pedido_assinatura_idempotente_impl_0135(
      '14000000-0000-4000-8000-000000000002', 0, 'ACCEPTED', null
    );
    raise exception 'authenticated invoked private signature helper';
  exception when insufficient_privilege then null;
  end;
end
$$;
reset role;

select '0140 order gate wrapper security contract passed' as order_gate_rpc_wrapper_security;
