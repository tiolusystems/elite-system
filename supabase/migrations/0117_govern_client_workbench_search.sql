-- Server-side customer search for the canonical master-data workbench.
-- The function is SECURITY INVOKER so every source table keeps enforcing its
-- existing RLS policy for the authenticated session.

create or replace function public.normalize_client_search_text(p_value text)
returns text
language sql
immutable
parallel safe
set search_path = public
as $$
  select nullif(
    regexp_replace(
      translate(
        lower(coalesce(p_value, '')),
        'áàâãäéèêëíìîïóòôõöúùûüçñ',
        'aaaaaeeeeiiiiooooouuuucn'
      ),
      '[^a-z0-9]+',
      '',
      'g'
    ),
    ''
  )
$$;

revoke all on function public.normalize_client_search_text(text)
  from public, anon;
grant execute on function public.normalize_client_search_text(text)
  to authenticated;

create or replace function public.consultar_cad_clientes_paginada(
  p_busca text default null,
  p_situacao text default null,
  p_ordenacao text default 'nome_asc',
  p_limite integer default 25,
  p_offset integer default 0
)
returns table (
  cliente_id bigint,
  codigo_legado text,
  nome text,
  cidade text,
  uf text,
  situacao text,
  apelidos_json jsonb,
  valor_total_compras numeric,
  razao_social text,
  nome_fantasia text,
  documento_principal text,
  propriedades_total bigint,
  total_registros bigint
)
language sql
stable
security invoker
set search_path = public
as $$
  with filtered as (
    select
      client.id,
      client.codigo_legado,
      client.nome,
      client.cidade,
      client.uf,
      client.status,
      client.apelidos_json,
      client.valor_total_compras,
      identification.razao_social,
      identification.nome_fantasia,
      primary_document.numero as documento_principal,
      (
        select count(*)
          from public.cad_cliente_propriedades property_count
         where property_count.cliente_id = client.id
      ) as propriedades_total
      from public.cad_clientes client
      left join public.cad_cliente_identificacoes identification
        on identification.cliente_id = client.id
      left join lateral (
        select customer_document.numero
          from public.cad_cliente_documentos customer_document
         where customer_document.cliente_id = client.id
         order by
           case customer_document.tipo
             when 'cnpj' then 1
             when 'cpf' then 2
             when 'ie' then 3
             else 4
           end,
           customer_document.id
         limit 1
      ) primary_document on true
     where public.current_actor_id() is not null
       and (
         nullif(btrim(p_situacao), '') is null
         or client.status = btrim(p_situacao)
       )
       and (
         public.normalize_client_search_text(p_busca) is null
         or public.normalize_client_search_text(client.nome)
              like '%' || public.normalize_client_search_text(p_busca) || '%'
         or public.normalize_client_search_text(client.codigo_legado)
              like '%' || public.normalize_client_search_text(p_busca) || '%'
         or public.normalize_client_search_text(client.cidade)
              like '%' || public.normalize_client_search_text(p_busca) || '%'
         or public.normalize_client_search_text(client.uf)
              like '%' || public.normalize_client_search_text(p_busca) || '%'
         or public.normalize_client_search_text(identification.razao_social)
              like '%' || public.normalize_client_search_text(p_busca) || '%'
         or public.normalize_client_search_text(identification.nome_fantasia)
              like '%' || public.normalize_client_search_text(p_busca) || '%'
         or exists (
           select 1
             from jsonb_array_elements_text(
               case
                 when jsonb_typeof(client.apelidos_json) = 'array'
                   then client.apelidos_json
                 else '[]'::jsonb
               end
             ) alias_value
            where public.normalize_client_search_text(alias_value)
                    like '%' || public.normalize_client_search_text(p_busca) || '%'
         )
         or exists (
           select 1
             from public.cad_cliente_documentos customer_document
            where customer_document.cliente_id = client.id
              and public.normalize_client_search_text(customer_document.numero)
                    like '%' || public.normalize_client_search_text(p_busca) || '%'
         )
         or exists (
           select 1
             from public.cad_cliente_propriedades property
            where property.cliente_id = client.id
              and (
                public.normalize_client_search_text(property.nome)
                  like '%' || public.normalize_client_search_text(p_busca) || '%'
                or public.normalize_client_search_text(property.cnpj)
                  like '%' || public.normalize_client_search_text(p_busca) || '%'
                or public.normalize_client_search_text(property.cidade)
                  like '%' || public.normalize_client_search_text(p_busca) || '%'
                or public.normalize_client_search_text(property.uf)
                  like '%' || public.normalize_client_search_text(p_busca) || '%'
              )
         )
         or exists (
           select 1
             from public.cad_cliente_estabelecimentos establishment
            where establishment.cliente_id = client.id
              and public.normalize_client_search_text(establishment.nome)
                    like '%' || public.normalize_client_search_text(p_busca) || '%'
         )
         or exists (
           select 1
             from public.cad_cliente_contatos contact
            where contact.cliente_id = client.id
              and (
                public.normalize_client_search_text(contact.telefone)
                  like '%' || public.normalize_client_search_text(p_busca) || '%'
                or public.normalize_client_search_text(contact.email)
                  like '%' || public.normalize_client_search_text(p_busca) || '%'
              )
         )
         or exists (
           select 1
             from public.cad_cliente_enderecos address
            where address.cliente_id = client.id
              and (
                public.normalize_client_search_text(address.cep)
                  like '%' || public.normalize_client_search_text(p_busca) || '%'
                or public.normalize_client_search_text(address.cidade)
                  like '%' || public.normalize_client_search_text(p_busca) || '%'
                or public.normalize_client_search_text(address.uf)
                  like '%' || public.normalize_client_search_text(p_busca) || '%'
              )
         )
       )
  )
  select
    filtered.id,
    filtered.codigo_legado,
    filtered.nome,
    filtered.cidade,
    filtered.uf,
    filtered.status,
    filtered.apelidos_json,
    filtered.valor_total_compras,
    filtered.razao_social,
    filtered.nome_fantasia,
    filtered.documento_principal,
    filtered.propriedades_total,
    count(*) over ()
    from filtered
   order by
     case when p_ordenacao = 'nome_desc'
       then public.normalize_client_search_text(filtered.nome)
     end desc nulls last,
     case when p_ordenacao <> 'nome_desc'
       then public.normalize_client_search_text(filtered.nome)
     end asc nulls last,
     filtered.id asc
   limit greatest(1, least(coalesce(p_limite, 25), 50))
  offset greatest(coalesce(p_offset, 0), 0)
$$;

revoke all on function public.consultar_cad_clientes_paginada(
  text, text, text, integer, integer
) from public, anon;
grant execute on function public.consultar_cad_clientes_paginada(
  text, text, text, integer, integer
) to authenticated;

comment on function public.consultar_cad_clientes_paginada(
  text, text, text, integer, integer
) is
  'Pesquisa e pagina clientes visiveis para a sessao sem ampliar RLS nem carregar fichas relacionadas em lote.';
