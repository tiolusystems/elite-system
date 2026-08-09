-- Align client search with the same seller/team scope already used by orders.

create or replace function public.consultar_com_carteira_clientes(p_busca text default null)
returns table (
  vinculo_id bigint, cliente_id bigint, cliente_nome text, propriedade_id bigint,
  propriedade_nome text, vendedor_id bigint, vendedor_nome text,
  limite_disponivel numeric, status_credito text
)
language sql
stable
security definer
set search_path = public
as $$
  select relation.id,
         client.id,
         client.nome,
         property.id,
         property.nome,
         seller.id,
         seller.nome,
         credit.limite_disponivel,
         coalesce(credit.status_credito, 'pendente_aprovacao')
    from public.cad_cliente_vendedores relation
    join public.cad_cliente_vinculo_papeis role_catalog
      on role_catalog.id = relation.papel_vinculo_id
     and role_catalog.concede_visibilidade = true
    join public.cad_clientes client
      on client.id = relation.cliente_id
     and client.status = 'active'
    join public.cad_pessoas_comerciais seller
      on seller.id = relation.pessoa_id
     and seller.status = 'active'
    left join public.cad_cliente_propriedades property
      on property.id = relation.propriedade_id
     and property.status = 'active'
    left join lateral (
      select limits.limite_disponivel, limits.status_credito
        from public.cad_limites_credito_cliente limits
       where limits.cliente_id = client.id
       order by limits.updated_at desc, limits.id desc
       limit 1
    ) credit on true
   where relation.status = 'active'
     and (relation.vigencia_inicio is null or relation.vigencia_inicio <= current_date)
     and (relation.vigencia_fim is null or relation.vigencia_fim >= current_date)
     and (
       relation.pessoa_id = public.current_commercial_person_id()
       or public.current_user_manages_seller(relation.pessoa_id)
     )
     and char_length(trim(coalesce(p_busca, ''))) >= 2
     and client.nome ilike '%' || trim(p_busca) || '%'
   order by client.nome, property.nome nulls first, seller.nome
   limit 80
$$;

revoke all on function public.consultar_com_carteira_clientes(text) from public, anon;
grant execute on function public.consultar_com_carteira_clientes(text) to authenticated;

comment on function public.consultar_com_carteira_clientes(text) is
  'Pesquisa clientes da carteira do vendedor autenticado e, para gerentes, das carteiras subordinadas. Exige ao menos dois caracteres.';
