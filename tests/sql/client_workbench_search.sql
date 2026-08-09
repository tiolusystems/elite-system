\set ON_ERROR_STOP on
begin;

do $$
begin
  if not has_function_privilege(
    'authenticated',
    'public.consultar_cad_clientes_paginada(text,text,text,integer,integer)',
    'EXECUTE'
  ) then
    raise exception 'authenticated cannot execute governed client search';
  end if;
  if has_function_privilege(
    'anon',
    'public.consultar_cad_clientes_paginada(text,text,text,integer,integer)',
    'EXECUTE'
  ) or has_function_privilege(
    'public',
    'public.consultar_cad_clientes_paginada(text,text,text,integer,integer)',
    'EXECUTE'
  ) then
    raise exception 'client search is exposed to anon or PUBLIC';
  end if;
  if (
    select procedure.prosecdef
      from pg_proc procedure
      join pg_namespace namespace on namespace.oid = procedure.pronamespace
     where namespace.nspname = 'public'
       and procedure.proname = 'consultar_cad_clientes_paginada'
       and pg_get_function_identity_arguments(procedure.oid) =
         'p_busca text, p_situacao text, p_ordenacao text, p_limite integer, p_offset integer'
  ) then
    raise exception 'client search must remain SECURITY INVOKER';
  end if;
  if has_table_privilege('authenticated', 'public.cad_clientes', 'INSERT')
     or has_table_privilege('authenticated', 'public.cad_clientes', 'UPDATE')
     or has_table_privilege('authenticated', 'public.cad_clientes', 'DELETE') then
    raise exception 'client search migration expanded direct write access';
  end if;
end
$$;

insert into auth.users(id, email)
values ('11700000-0000-4000-8000-000000000001', 'client-search-0117@test.invalid');

insert into public.user_profiles(id, display_name, role, status)
values (
  '11700000-0000-4000-8000-000000000001',
  'Consulta Clientes 0117',
  'comercial',
  'active'
);

insert into public.cad_clientes(
  codigo_legado, nome, nome_norm, cidade, uf, status, apelidos_json, created_by
) values (
  'LEG-0117',
  'Árvore Agrícola 0117',
  'ARVORE AGRICOLA 0117',
  'São José do Rio Preto',
  'SP',
  'active',
  '["Fazenda São João", "Grafia Histórica 0117"]',
  '11700000-0000-4000-8000-000000000001'
);

insert into public.cad_clientes(nome, nome_norm, cidade, uf, status, created_by)
select
  'Cliente Pagina ' || lpad(series::text, 3, '0') || ' 0117',
  'CLIENTE PAGINA ' || lpad(series::text, 3, '0') || ' 0117',
  'Campinas',
  'SP',
  case when series = 275 then 'inactive' else 'active' end,
  '11700000-0000-4000-8000-000000000001'
from generate_series(1, 275) series;

insert into public.cad_cliente_identificacoes(
  cliente_id, tipo_pessoa, razao_social, nome_fantasia, situacao_cadastral,
  fonte_informacao, created_by, updated_by
)
select
  id, 'juridica', 'Razão Social Campo 0117', 'Fantasia Verde 0117', 'ativa',
  'documento', '11700000-0000-4000-8000-000000000001',
  '11700000-0000-4000-8000-000000000001'
from public.cad_clientes where codigo_legado = 'LEG-0117';

insert into public.cad_cliente_documentos(
  cliente_id, tipo, numero, numero_norm, created_by
)
select id, 'cnpj', '11.700.000/0001-17', '11700000000117',
       '11700000-0000-4000-8000-000000000001'
from public.cad_clientes where codigo_legado = 'LEG-0117';

insert into public.cad_cliente_documentos(
  cliente_id, tipo, numero, numero_norm, created_by
)
select id, 'ie', 'IE-0117.445', 'IE0117445',
       '11700000-0000-4000-8000-000000000001'
from public.cad_clientes where codigo_legado = 'LEG-0117';

insert into public.cad_cliente_propriedades(
  cliente_id, nome, cnpj, cnpj_norm, cidade, uf, status, created_by
)
select id, 'Sítio Horizonte 0117', '11.700.000/0002-06', '11700000000206',
       'Ribeirão Preto', 'SP', 'active',
       '11700000-0000-4000-8000-000000000001'
from public.cad_clientes where codigo_legado = 'LEG-0117';

insert into public.cad_cliente_estabelecimentos(
  cliente_id, nome, nome_norm, tipo, status, created_by, updated_by
)
select id, 'Loja Centro 0117', 'loja centro 0117', 'loja', 'active',
       '11700000-0000-4000-8000-000000000001',
       '11700000-0000-4000-8000-000000000001'
from public.cad_clientes where codigo_legado = 'LEG-0117';

insert into public.cad_cliente_contatos(
  cliente_id, nome, papel, telefone, email, status, created_by, updated_by
)
select id, 'Contato 0117', 'Compras', '(17) 99999-0117',
       'compras0117@example.invalid', 'active',
       '11700000-0000-4000-8000-000000000001',
       '11700000-0000-4000-8000-000000000001'
from public.cad_clientes where codigo_legado = 'LEG-0117';

insert into public.cad_cliente_enderecos(
  cliente_id, tipo, cep, cep_norm, logradouro, cidade, uf, status,
  fonte_informacao, created_by, updated_by
)
select id, 'fiscal', '15000-117', '15000117', 'Rua Teste 0117',
       'São José do Rio Preto', 'SP', 'active', 'documento',
       '11700000-0000-4000-8000-000000000001',
       '11700000-0000-4000-8000-000000000001'
from public.cad_clientes where codigo_legado = 'LEG-0117';

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '11700000-0000-4000-8000-000000000001',
  true
);

do $$
declare
  search_term text;
  total bigint;
  page_rows bigint;
begin
  foreach search_term in array array[
    'arvore',
    'sao joao',
    'LEG0117',
    'razao social',
    'fantasia verde',
    '11700000000117',
    'IE0117445',
    'sitio horizonte',
    '11700000000206',
    'loja centro',
    '17999990117',
    'compras0117@example.invalid',
    '15000117',
    'sao jose'
  ]
  loop
    if not exists (
      select 1
        from public.consultar_cad_clientes_paginada(
          search_term, null, 'nome_asc', 25, 0
        )
       where codigo_legado = 'LEG-0117'
    ) then
      raise exception 'client search did not match %', search_term;
    end if;
  end loop;

  select max(total_registros), count(*)
    into total, page_rows
    from public.consultar_cad_clientes_paginada(
      '0117', null, 'nome_asc', 25, 0
    );
  if total <> 276 or page_rows <> 25 then
    raise exception 'first page or total is invalid: total %, rows %', total, page_rows;
  end if;

  select count(*) into page_rows
    from public.consultar_cad_clientes_paginada(
      '0117', null, 'nome_asc', 25, 25
    );
  if page_rows <> 25 then
    raise exception 'second page is invalid: rows %', page_rows;
  end if;

  select count(*) into page_rows
    from public.consultar_cad_clientes_paginada(
      '0117', null, 'nome_asc', 25, 250
    );
  if page_rows <> 25 then
    raise exception 'records beyond the old 250 limit are missing: rows %', page_rows;
  end if;

  select count(*) into page_rows
    from public.consultar_cad_clientes_paginada(
      '0117', null, 'nome_asc', 25, 275
    );
  if page_rows <> 1 then
    raise exception 'last partial page is invalid: rows %', page_rows;
  end if;

  if not exists (
    select 1
      from public.consultar_cad_clientes_paginada(
        'Cliente Pagina 275', null, 'nome_asc', 25, 0
      )
     where nome = 'Cliente Pagina 275 0117'
  ) then
    raise exception 'client beyond the old 250 limit was not found';
  end if;

  if exists (
    select 1
      from public.consultar_cad_clientes_paginada(
        '0117', 'inactive', 'nome_asc', 25, 0
      )
     where situacao <> 'inactive'
  ) then
    raise exception 'status filter returned another status';
  end if;

  if (
    select nome
      from public.consultar_cad_clientes_paginada(
        'Cliente Pagina', null, 'nome_desc', 25, 0
      )
     limit 1
  ) <> 'Cliente Pagina 275 0117' then
    raise exception 'descending order is not predictable';
  end if;
end
$$;

reset role;

insert into auth.users(id, email)
values ('11700000-0000-4000-8000-000000000002', 'client-search-denied-0117@test.invalid');

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '11700000-0000-4000-8000-000000000002',
  true
);

do $$
begin
  if exists (
    select 1
      from public.consultar_cad_clientes_paginada(
        null, null, 'nome_asc', 25, 0
      )
  ) then
    raise exception 'authenticated account without an active profile enumerated clients';
  end if;
end
$$;

rollback;
