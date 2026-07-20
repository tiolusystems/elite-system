-- Security gate: close direct table writes and RPC exposure in public.

do $security_gate$
declare
  v_relation record;
  v_function record;
  v_missing text[];
  v_authenticated_rpc_names text[] := array[
    'activate_cad_tipo_insumo',
    'activate_pcp_formula_versao',
    'add_exp_romaneio_item',
    'authorize_security_auth_user_provision',
    'calcular_pcp_garantias_op',
    'can_current_user',
    'cancelar_exp_romaneio',
    'cancelar_pcp_op',
    'clear_security_permission_override',
    'close_cad_pessoa_area_comercial',
    'complete_security_email_change_request',
    'confirm_imp_nfe_item_match',
    'confirmar_exp_romaneio',
    'create_cad_cliente',
    'create_cad_conversao_unidade_mp',
    'create_cad_embalagem',
    'create_cad_materia_prima',
    'create_cad_materia_prima_governada',
    'create_cad_pessoa_comercial',
    'create_cad_produto_base',
    'create_cad_produto_embalagem',
    'create_cad_tipo_insumo',
    'create_com_pedido_operacional',
    'create_com_pedido_troca',
    'create_exp_romaneio',
    'create_pcp_formula_versao',
    'create_pcp_op',
    'deactivate_cad_cliente',
    'deactivate_cad_materia_prima',
    'deactivate_cad_pessoa_comercial',
    'deactivate_cad_tipo_insumo',
    'estornar_exp_romaneio',
    'finalizar_pcp_op',
    'find_cad_materia_prima_possible_duplicates',
    'find_cad_pessoa_possible_duplicates',
    'gerar_lote_mp_from_imp_nfe_item',
    'get_current_route_module_access',
    'get_security_approved_own_email_change',
    'get_security_own_email_change_request',
    'ignore_imp_nfe_xml_item',
    'iniciar_pcp_op',
    'liberar_pcp_lote_bloqueado',
    'link_cad_pessoa_area_comercial',
    'list_security_effective_permissions',
    'list_security_email_change_requests',
    'list_security_user_profiles',
    'list_system_module_runtime',
    'log_permission_denied',
    'log_rpc_failed',
    'mark_security_email_change_confirmation_pending',
    'reactivate_cad_pessoa_comercial',
    'record_security_auth_user_invitation_sent',
    'record_security_own_password_changed',
    'registrar_com_pedido_decisao_credito',
    'registrar_com_recebimento',
    'registrar_est_reserva_pa',
    'registrar_exp_romaneio_logistica_atribuicao',
    'registrar_exp_romaneio_logistica_remocao',
    'registrar_pcp_garantia_lote_mp',
    'registrar_pcp_garantia_produto',
    'request_security_own_email_change',
    'require_current_user_permission',
    'reservar_pcp_op_componente',
    'review_security_email_change_request',
    'set_cad_materia_prima_tipo',
    'set_security_permission_override',
    'set_system_module_rollout',
    'set_system_runtime_environment',
    'stage_imp_nfe_xml',
    'stage_imp_nfe_xml_item',
    'update_cad_cliente',
    'update_cad_materia_prima_identity',
    'update_cad_materia_prima_regulatory',
    'update_cad_materia_prima_sku',
    'update_cad_materia_prima_stock_policy',
    'update_cad_materia_prima_technical_governada',
    'update_cad_pessoa_comercial_identity',
    'update_cad_pessoa_comercial_role',
    'update_cad_tipo_insumo',
    'upsert_security_user_profile'
  ];
begin
  for v_relation in
    select c.oid, c.relname, c.relkind
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relkind in ('r', 'p')
  loop
    execute format(
      'revoke insert, update, delete, truncate, references, trigger on table public.%I from public, anon, authenticated',
      v_relation.relname
    );
  end loop;

  for v_relation in
    select c.oid, c.relname
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relkind = 'S'
  loop
    execute format(
      'revoke all privileges on sequence public.%I from public, anon, authenticated',
      v_relation.relname
    );
  end loop;

  for v_function in
    select p.oid
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
  loop
    execute format(
      'revoke execute on function %s from public, anon, authenticated',
      v_function.oid::regprocedure
    );
  end loop;

  select array_agg(expected_name order by expected_name)
    into v_missing
    from unnest(v_authenticated_rpc_names) expected_name
   where not exists (
     select 1
       from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname = expected_name
   );

  if v_missing is not null then
    raise exception 'authenticated RPC allowlist references missing functions: %', v_missing;
  end if;

  for v_function in
    select p.oid
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = any(v_authenticated_rpc_names)
  loop
    execute format(
      'grant execute on function %s to authenticated',
      v_function.oid::regprocedure
    );
  end loop;
end;
$security_gate$;

alter default privileges for role postgres in schema public
  revoke insert, update, delete, truncate, references, trigger on tables from public, anon, authenticated;

alter default privileges for role postgres in schema public
  revoke all privileges on sequences from public, anon, authenticated;

alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated;

comment on schema public is
  'Exposed API schema. Tables are read-only to API roles; writes use explicitly granted audited RPCs.';
