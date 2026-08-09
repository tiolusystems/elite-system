-- Paginated stock search: never load the full lot ledger into an operational screen.

create or replace function public.consultar_est_estoque_lotes(
  p_busca text default null,
  p_familia text default 'all',
  p_status text default 'com_saldo',
  p_validade text default 'all',
  p_limite integer default 24,
  p_offset integer default 0
)
returns table (
  lote_id bigint,
  familia text,
  alvo_id bigint,
  alvo_label text,
  codigo_lote text,
  status text,
  saldo_fisico numeric,
  quantidade_reservada numeric,
  saldo_disponivel numeric,
  data_validade date,
  origem_ref text,
  created_at timestamptz,
  updated_at timestamptz,
  total_count bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_busca text := lower(nullif(btrim(p_busca), ''));
  v_limite integer := least(greatest(coalesce(p_limite, 24), 1), 100);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
begin
  if p_familia not in ('all', 'MP', 'PA', 'PI') then raise exception 'invalid stock family'; end if;
  if p_status not in ('all', 'com_saldo', 'disponivel', 'bloqueado', 'esgotado', 'cancelado') then raise exception 'invalid stock status'; end if;
  if p_validade not in ('all', 'vencido', 'vence_30_dias', 'vigente', 'sem_validade') then raise exception 'invalid lot validity'; end if;
  if not (
    public.can_current_user('estoque.mp.view')
    or public.can_current_user('estoque.pa.view')
    or public.can_current_user('estoque.pi.view')
  ) then raise exception 'not allowed: estoque.view'; end if;

  return query
  with catalogo(lote_id, familia, alvo_id, alvo_label, codigo_lote, status, saldo_fisico,
                quantidade_reservada, saldo_disponivel, data_validade, origem_ref, created_at, updated_at) as (
    select saldo.lote_mp_id, 'MP'::text, saldo.materia_prima_id,
           concat_ws(' - ', materia.sku_corrigido, materia.nome), saldo.codigo_lote,
           saldo.status, saldo.saldo_fisico, saldo.quantidade_reservada, saldo.saldo_disponivel,
           saldo.data_validade, saldo.origem_ref, saldo.created_at, saldo.updated_at
      from public.est_lotes_mp_saldos saldo
      join public.cad_materias_primas materia on materia.id = saldo.materia_prima_id
     where public.can_current_user('estoque.mp.view')
    union all
    select saldo.lote_pa_id, 'PA'::text, saldo.produto_embalagem_id,
           concat_ws(' - ', apresentacao.codigo_item, produto.nome, embalagem.descricao), saldo.codigo_lote,
           saldo.status, saldo.saldo_fisico, saldo.quantidade_reservada, saldo.saldo_disponivel,
           saldo.data_validade, saldo.origem_ref, saldo.created_at, saldo.updated_at
      from public.est_lotes_pa_saldos saldo
      join public.cad_produto_embalagens apresentacao on apresentacao.id = saldo.produto_embalagem_id
      join public.cad_produtos_base produto on produto.id = apresentacao.produto_id
      join public.cad_embalagens embalagem on embalagem.id = apresentacao.embalagem_id
     where public.can_current_user('estoque.pa.view')
    union all
    select saldo.lote_pi_id, 'PI'::text, saldo.produto_id,
           concat_ws(' - ', produto.codigo_produto, produto.nome), saldo.codigo_lote,
           saldo.status, saldo.saldo_fisico, saldo.quantidade_reservada, saldo.saldo_disponivel,
           saldo.data_validade, saldo.origem_ref, saldo.created_at, saldo.updated_at
      from public.est_lotes_pi_saldos saldo
      join public.cad_produtos_base produto on produto.id = saldo.produto_id
     where public.can_current_user('estoque.pi.view')
  ), filtrado as (
    select * from catalogo lote
     where (p_familia = 'all' or lote.familia = p_familia)
       and (p_status = 'all' or (p_status = 'com_saldo' and lote.saldo_fisico > 0) or lote.status = p_status)
       and (p_validade = 'all'
         or (p_validade = 'sem_validade' and lote.data_validade is null)
         or (p_validade = 'vencido' and lote.data_validade < current_date)
         or (p_validade = 'vence_30_dias' and lote.data_validade between current_date and current_date + 30)
         or (p_validade = 'vigente' and lote.data_validade > current_date + 30))
       and (v_busca is null or lower(concat_ws(' ', lote.alvo_label, lote.codigo_lote, lote.origem_ref)) like '%' || v_busca || '%')
  )
  select lote_id, familia, alvo_id, alvo_label, codigo_lote, status, saldo_fisico, quantidade_reservada,
         saldo_disponivel, data_validade, origem_ref, created_at, updated_at, count(*) over ()
    from filtrado
   order by updated_at desc, familia, lote_id desc
   limit v_limite offset v_offset;
end;
$$;

revoke all on function public.consultar_est_estoque_lotes(text, text, text, text, integer, integer) from public, anon;
grant execute on function public.consultar_est_estoque_lotes(text, text, text, text, integer, integer) to authenticated;

comment on function public.consultar_est_estoque_lotes(text, text, text, text, integer, integer) is
  'Consulta paginada de lotes por familia e permissao, sem carregar o livro inteiro no frontend.';
