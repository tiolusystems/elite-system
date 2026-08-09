-- Product -> packaging -> lot drill-down for high-volume stock operation.

create or replace function public.consultar_est_estoque_produtos(
  p_busca text,
  p_familia text default 'all',
  p_limite integer default 30
)
returns table (familia text, produto_id bigint, codigo text, nome text, apresentacoes bigint, lotes_disponiveis bigint)
language sql stable security definer set search_path = public
as $$
  with itens as (
    select 'MP'::text familia, materia.id produto_id, materia.sku_corrigido codigo, materia.nome,
           1::bigint apresentacoes, count(*)::bigint lotes_disponiveis
      from public.est_lotes_mp_saldos saldo join public.cad_materias_primas materia on materia.id = saldo.materia_prima_id
     where public.can_current_user('estoque.mp.view') and saldo.saldo_disponivel > 0
     group by materia.id, materia.sku_corrigido, materia.nome
    union all
    select 'PI', produto.id, produto.codigo_produto, produto.nome, 1::bigint, count(*)::bigint
      from public.est_lotes_pi_saldos saldo join public.cad_produtos_base produto on produto.id = saldo.produto_id
     where public.can_current_user('estoque.pi.view') and saldo.saldo_disponivel > 0
     group by produto.id, produto.codigo_produto, produto.nome
    union all
    select 'PA', produto.id, produto.codigo_produto, produto.nome,
           count(distinct apresentacao.id)::bigint, count(*)::bigint
      from public.est_lotes_pa_saldos saldo
      join public.cad_produto_embalagens apresentacao on apresentacao.id = saldo.produto_embalagem_id
      join public.cad_produtos_base produto on produto.id = apresentacao.produto_id
     where public.can_current_user('estoque.pa.view') and saldo.saldo_disponivel > 0
     group by produto.id, produto.codigo_produto, produto.nome
  )
  select item.familia, item.produto_id, item.codigo, item.nome, item.apresentacoes, item.lotes_disponiveis
    from itens item
   where nullif(btrim(p_busca), '') is not null
     and (p_familia = 'all' or item.familia = p_familia)
     and lower(concat_ws(' ', item.codigo, item.nome)) like '%' || lower(btrim(p_busca)) || '%'
   order by item.nome, item.familia
   limit least(greatest(coalesce(p_limite, 30), 1), 100)
$$;

create or replace function public.consultar_est_estoque_apresentacoes(p_produto_id bigint)
returns table (apresentacao_id bigint, codigo text, descricao text, lotes_disponiveis bigint, saldo_disponivel numeric)
language sql stable security definer set search_path = public
as $$
  select apresentacao.id, apresentacao.codigo_item, embalagem.descricao,
         count(*)::bigint, sum(saldo.saldo_disponivel)
    from public.est_lotes_pa_saldos saldo
    join public.cad_produto_embalagens apresentacao on apresentacao.id = saldo.produto_embalagem_id
    join public.cad_embalagens embalagem on embalagem.id = apresentacao.embalagem_id
   where public.can_current_user('estoque.pa.view')
     and apresentacao.produto_id = p_produto_id
     and saldo.saldo_disponivel > 0
   group by apresentacao.id, apresentacao.codigo_item, embalagem.descricao
   order by embalagem.descricao
$$;

create or replace function public.consultar_est_estoque_lotes_alvo(
  p_familia text, p_alvo_id bigint, p_limite integer default 24, p_offset integer default 0
)
returns table (
  lote_id bigint, familia text, alvo_id bigint, alvo_label text, codigo_lote text, status text,
  saldo_fisico numeric, quantidade_reservada numeric, saldo_disponivel numeric, data_validade date,
  origem_ref text, created_at timestamptz, updated_at timestamptz, total_count bigint
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if p_familia not in ('MP', 'PA', 'PI') or p_alvo_id is null then raise exception 'invalid stock target'; end if;
  if not public.can_current_user('estoque.' || lower(p_familia) || '.view') then raise exception 'not allowed: estoque.view'; end if;
  return query
  with lotes(lote_id, familia, alvo_id, alvo_label, codigo_lote, status, saldo_fisico,
             quantidade_reservada, saldo_disponivel, data_validade, origem_ref, created_at, updated_at) as (
    select saldo.lote_mp_id, 'MP'::text, saldo.materia_prima_id, concat_ws(' - ', materia.sku_corrigido, materia.nome),
           saldo.codigo_lote, saldo.status, saldo.saldo_fisico, saldo.quantidade_reservada, saldo.saldo_disponivel,
           saldo.data_validade, saldo.origem_ref, saldo.created_at, saldo.updated_at
      from public.est_lotes_mp_saldos saldo join public.cad_materias_primas materia on materia.id = saldo.materia_prima_id
     where p_familia = 'MP' and saldo.materia_prima_id = p_alvo_id and saldo.saldo_disponivel > 0
    union all
    select saldo.lote_pa_id, 'PA', saldo.produto_embalagem_id, concat_ws(' - ', apresentacao.codigo_item, produto.nome, embalagem.descricao),
           saldo.codigo_lote, saldo.status, saldo.saldo_fisico, saldo.quantidade_reservada, saldo.saldo_disponivel,
           saldo.data_validade, saldo.origem_ref, saldo.created_at, saldo.updated_at
      from public.est_lotes_pa_saldos saldo join public.cad_produto_embalagens apresentacao on apresentacao.id = saldo.produto_embalagem_id
      join public.cad_produtos_base produto on produto.id = apresentacao.produto_id join public.cad_embalagens embalagem on embalagem.id = apresentacao.embalagem_id
     where p_familia = 'PA' and saldo.produto_embalagem_id = p_alvo_id and saldo.saldo_disponivel > 0
    union all
    select saldo.lote_pi_id, 'PI', saldo.produto_id, concat_ws(' - ', produto.codigo_produto, produto.nome),
           saldo.codigo_lote, saldo.status, saldo.saldo_fisico, saldo.quantidade_reservada, saldo.saldo_disponivel,
           saldo.data_validade, saldo.origem_ref, saldo.created_at, saldo.updated_at
      from public.est_lotes_pi_saldos saldo join public.cad_produtos_base produto on produto.id = saldo.produto_id
     where p_familia = 'PI' and saldo.produto_id = p_alvo_id and saldo.saldo_disponivel > 0
  )
  select lote_id, familia, alvo_id, alvo_label, codigo_lote, status, saldo_fisico, quantidade_reservada, saldo_disponivel,
         data_validade, origem_ref, created_at, updated_at, count(*) over ()
    from lotes order by updated_at desc limit least(greatest(coalesce(p_limite,24),1),100) offset greatest(coalesce(p_offset,0),0);
end;
$$;

revoke all on function public.consultar_est_estoque_produtos(text,text,integer) from public, anon;
revoke all on function public.consultar_est_estoque_apresentacoes(bigint) from public, anon;
revoke all on function public.consultar_est_estoque_lotes_alvo(text,bigint,integer,integer) from public, anon;
grant execute on function public.consultar_est_estoque_produtos(text,text,integer) to authenticated;
grant execute on function public.consultar_est_estoque_apresentacoes(bigint) to authenticated;
grant execute on function public.consultar_est_estoque_lotes_alvo(text,bigint,integer,integer) to authenticated;
