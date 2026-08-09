-- F1.1 corrective migration: DEC-010 made product group relational, while the
-- operational product RPC still populated only the compatibility text cache.

create or replace function public.create_cad_produto_base(
  p_codigo_produto text,
  p_nome text,
  p_nome_norm text,
  p_status text default 'active',
  p_grupo text default null,
  p_densidade_kg_l numeric default null,
  p_reg_mapa text default null,
  p_ncm text default null,
  p_ibama text default null,
  p_ads text default null,
  p_payload_origem_json jsonb default '{}'::jsonb,
  p_prazo_validade_meses integer default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid;
  v_produto_id bigint;
  v_grupo_id bigint;
  v_grupo_codigo text;
  v_permission_context jsonb;
  v_after jsonb;
begin
  v_permission_context := public.begin_audited_rpc(
    'cadastros.produtos.create',
    'cadastros',
    'cad_produtos_base',
    'change_type',
    jsonb_build_object('operation', 'create_with_initial_validity')
  );

  if nullif(trim(p_codigo_produto), '') is null then
    raise exception 'codigo_produto is required';
  end if;
  if nullif(trim(p_nome), '') is null then
    raise exception 'nome is required';
  end if;
  if p_status not in ('active', 'inactive', 'pending_review') then
    raise exception 'invalid status';
  end if;
  if p_densidade_kg_l is not null and p_densidade_kg_l <= 0 then
    raise exception 'densidade_kg_l must be greater than zero';
  end if;
  if p_prazo_validade_meses is not null
     and (p_prazo_validade_meses < 1 or p_prazo_validade_meses > 240) then
    raise exception 'prazo_validade_meses must be between 1 and 240';
  end if;

  if nullif(trim(p_grupo), '') is not null then
    select product_group.id, product_group.codigo
      into v_grupo_id, v_grupo_codigo
      from public.cad_grupos_produto product_group
     where product_group.codigo_norm = public.normalize_catalog_term(p_grupo)
       and product_group.status = 'active';

    if not found then
      raise exception 'unknown or inactive product group: %', p_grupo;
    end if;
  end if;

  v_actor := public.current_actor_id();

  insert into public.cad_produtos_base(
    codigo_produto,
    nome,
    nome_norm,
    status,
    grupo,
    grupo_id,
    densidade_kg_l,
    prazo_validade_meses,
    reg_mapa,
    ncm,
    ibama,
    ads,
    payload_origem_json,
    created_by,
    updated_by
  ) values (
    upper(trim(p_codigo_produto)),
    trim(p_nome),
    trim(p_nome_norm),
    p_status,
    v_grupo_codigo,
    v_grupo_id,
    p_densidade_kg_l,
    p_prazo_validade_meses,
    nullif(trim(p_reg_mapa), ''),
    nullif(trim(p_ncm), ''),
    nullif(trim(p_ibama), ''),
    nullif(trim(p_ads), ''),
    coalesce(p_payload_origem_json, '{}'::jsonb),
    v_actor,
    v_actor
  )
  returning id into v_produto_id;

  v_after := jsonb_build_object(
    'codigo_produto', upper(trim(p_codigo_produto)),
    'nome', trim(p_nome),
    'status', p_status,
    'grupo_id', v_grupo_id,
    'grupo', v_grupo_codigo,
    'prazo_validade_meses', p_prazo_validade_meses
  );

  perform public.log_audited_rpc_change(
    'cadastros',
    'cad_produtos_base',
    v_produto_id::text,
    'cadastros.produto_base_created',
    'cadastros.produtos.create',
    v_permission_context,
    null,
    v_after,
    jsonb_build_object(
      'source', 'create_cad_produto_base',
      'initial_validity_atomic', true,
      'product_group_relational', true
    )
  );

  return v_produto_id;
end;
$$;

comment on function public.create_cad_produto_base(
  text, text, text, text, text, numeric, text, text, text, text, jsonb, integer
) is
  'Atomically creates a product with validity and resolves its active relational product group.';
