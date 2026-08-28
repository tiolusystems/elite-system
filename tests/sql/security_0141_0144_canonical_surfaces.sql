\set ON_ERROR_STOP on
begin;
do $$
declare v_signature text; v_signatures text[];
begin
  v_signatures := ARRAY[
    'public.prevent_com_lista_preco_import_fact_changes()',
    'public.normalizar_com_lista_preco_valor_bruto(text)',
    'public.ord01_comparacao_original_persistida(bigint)',
    'public.ord01_revision_current_pre_effective_state(bigint)',
    'public.ord01_revision_impact_mask(jsonb,jsonb)',
    'public.avaliar_com_pedido_efetividade(bigint)',
    'public.ord01_contract_genesis_state(bigint)',
    'public.resolver_cad_pessoa_cadeia_comercial(bigint,date)'
  ];
  if (select count(*) from public.security_sql_surface_contracts) <> 8 then
    raise exception 'canonical SQL surface inventory is incomplete';
  end if;
  if exists (
    select 1
      from public.security_sql_surface_contracts contract
     where to_regprocedure(contract.function_signature) is null
  ) then
    raise exception 'canonical SQL surface inventory contains an orphan signature';
  end if;
  foreach v_signature in array v_signatures loop
    if has_function_privilege('public', v_signature, 'EXECUTE')
       or has_function_privilege('anon', v_signature, 'EXECUTE')
       or has_function_privilege('authenticated', v_signature, 'EXECUTE') then
      raise exception 'private function remains executable by an API role: %', v_signature;
    end if;
  end loop;
  if exists (
    select 1
      from (values
        ('public.consultar_cad_clientes_paginada(text,text,text,integer,integer)'),
        ('public.buscar_exp_romaneios_paginada(text,bigint,bigint,bigint,bigint,text,date,date,text[],bigint,bigint,bigint,bigint,integer,integer)'),
        ('public.consultar_est_estoque_pa_posicao(date)')
      ) expected(function_signature)
      left join public.security_sql_surface_contracts contract using (function_signature)
     where contract.surface is distinct from 'GOVERNED_READ_INVOKER_RLS'
        or contract.read_only is distinct from true
        or contract.rls_preserved is distinct from true
        or contract.explicit_contract is distinct from true
  ) then
    raise exception 'invoker RLS read classification is incomplete';
  end if;
  foreach v_signature in array ARRAY[
    'public.consultar_cad_clientes_paginada(text,text,text,integer,integer)',
    'public.buscar_exp_romaneios_paginada(text,bigint,bigint,bigint,bigint,text,date,date,text[],bigint,bigint,bigint,bigint,integer,integer)',
    'public.consultar_est_estoque_pa_posicao(date)'
  ] loop
    if has_function_privilege('public', v_signature, 'EXECUTE')
       or has_function_privilege('anon', v_signature, 'EXECUTE')
       or not has_function_privilege('authenticated', v_signature, 'EXECUTE') then
      raise exception 'invoker read ACL is incorrect: %', v_signature;
    end if;
    if (select prosecdef from pg_proc where oid = v_signature::regprocedure) then
      raise exception 'invoker read unexpectedly became SECURITY DEFINER: %', v_signature;
    end if;
  end loop;
  if exists (
    select 1
      from public.security_sql_surface_contracts contract
     where contract.surface = 'GOVERNED_RPC_DEFINER'
       and (not contract.read_only or not contract.explicit_contract)
  ) then
    raise exception 'definer read contract is not explicit and read-only';
  end if;
  foreach v_signature in array ARRAY[
    'public.consultar_com_carteira_clientes(text)',
    'public.consultar_com_pedidos_aprovacao()',
    'public.consultar_com_carteira_clientes_paginada(text,integer,integer)'
  ] loop
    if has_function_privilege('public', v_signature, 'EXECUTE')
       or has_function_privilege('anon', v_signature, 'EXECUTE')
       or not has_function_privilege('authenticated', v_signature, 'EXECUTE') then
      raise exception 'governed definer read ACL is incorrect: %', v_signature;
    end if;
    if not (select prosecdef from pg_proc where oid = v_signature::regprocedure) then
      raise exception 'governed definer read is not SECURITY DEFINER: %', v_signature;
    end if;
  end loop;
  if not has_function_privilege('authenticated',
    'public.resolver_com_referencia_comercial(date,numeric,bigint,bigint,text,bigint,bigint[],bigint)',
    'EXECUTE') then
    raise exception 'commercial resolver lost authenticated access';
  end if;
  if not (select prosecdef from pg_proc where oid =
    'public.resolver_com_referencia_comercial(date,numeric,bigint,bigint,text,bigint,bigint[],bigint)'::regprocedure) then
    raise exception 'commercial resolver is not SECURITY DEFINER';
  end if;
end;
$$;
rollback;
\echo ELITE_CANONICAL_SQL_SURFACES_OK
