create or replace function public.resolver_com_referencia_comercial(
  p_data_comercial date, p_pmp_dias numeric, p_origem_comercial_id bigint, p_area_comercial_id bigint,
  p_uf text, p_cliente_id bigint, p_pessoa_papel_ids bigint[], p_produto_embalagem_id bigint
)
returns table(
  lista_id bigint, versao_id bigint, publicacao_id bigint, regra_id bigint, produto_id bigint,
  produto_embalagem_id bigint, data_comercial date, pmp_dias numeric, prazo_faixa_dias integer,
  preco_referencia_centavos_por_litro bigint, prioridade integer, especificidade integer
)
language plpgsql volatile security definer set search_path = public
as $$
declare v_referencia record; v_codigo text;
begin
  perform public.require_current_user_permission('pedidos.price_reference.resolve');
  select * into v_referencia from public.resolver_com_referencia_comercial_unidade(
    p_data_comercial, p_pmp_dias, p_origem_comercial_id, p_area_comercial_id, p_uf,
    p_cliente_id, p_pessoa_papel_ids, p_produto_embalagem_id
  );
  select unidade.codigo into v_codigo
    from public.cad_unidades_medida unidade
   where unidade.id = v_referencia.unidade_precificacao_id;
  if lower(coalesce(v_codigo, '')) <> 'l'
     or v_referencia.preco_referencia_centavos_por_litro is null then
    raise exception 'referencia comercial usa unidade generica; utilize o resolvedor de unidade comercial';
  end if;
  lista_id := v_referencia.lista_id; versao_id := v_referencia.versao_id;
  publicacao_id := v_referencia.publicacao_id; regra_id := v_referencia.regra_id;
  produto_id := v_referencia.produto_id; produto_embalagem_id := v_referencia.produto_embalagem_id;
  data_comercial := v_referencia.data_comercial; pmp_dias := v_referencia.pmp_dias;
  prazo_faixa_dias := v_referencia.prazo_faixa_dias;
  preco_referencia_centavos_por_litro := v_referencia.preco_referencia_centavos_por_litro;
  prioridade := v_referencia.prioridade; especificidade := v_referencia.especificidade;
  return next;
end;
$$;
revoke all on function public.resolver_cad_pessoa_cadeia_comercial(bigint, date)
  from public, anon, authenticated;
