-- Corrige duas lacunas de leitura da rastreabilidade:
-- 1. a referencia fiscal e destino documental do pedido/romaneio;
-- 2. o caminho recursivo do recolhimento deve anexar um no por vez.

create or replace view public.rel_rastreabilidade_arestas
with (security_invoker = true)
as
with expedicao_liquida as (
  select
    movimento.romaneio_id,
    movimento.lote_pa_id,
    sum(movimento.quantidade) as quantidade,
    max(movimento.created_at) as evento_em,
    max(movimento.id) as registro_id
  from public.exp_romaneio_movimentos_pa movimento
  where movimento.lote_pa_id is not null
  group by movimento.romaneio_id, movimento.lote_pa_id
)
select
  consumo.tipo_componente::text as origem_tipo,
  coalesce(consumo.lote_mp_id, consumo.lote_pi_id, consumo.lote_pa_id) as origem_id,
  coalesce(lote_mp.codigo_lote, lote_pi.codigo_lote, lote_pa.codigo_lote)::text as origem_codigo,
  'OP'::text as destino_tipo,
  ordem.id as destino_id,
  ordem.codigo_op::text as destino_codigo,
  consumo.quantidade_consumida::numeric as quantidade,
  coalesce(
    componente.unidade,
    case when consumo.tipo_componente = 'MP' then 'UN_BASE' else 'UN' end
  )::text as unidade,
  consumo.created_at as evento_em,
  'consumo_real'::text as evento,
  'pcp_op_consumos_componentes'::text as registro_fonte,
  consumo.id as registro_id,
  true as ativo
from public.pcp_op_consumos_componentes consumo
join public.pcp_ordens_producao ordem on ordem.id = consumo.op_id
join public.pcp_op_componentes_planejados componente on componente.id = consumo.op_componente_id
left join public.est_lotes_mp lote_mp on lote_mp.id = consumo.lote_mp_id
left join public.est_lotes_pi lote_pi on lote_pi.id = consumo.lote_pi_id
left join public.est_lotes_pa lote_pa on lote_pa.id = consumo.lote_pa_id

union all

select
  'OP', ordem.id, ordem.codigo_op,
  gerado.tipo_produto, coalesce(gerado.lote_pi_id, gerado.lote_pa_id),
  coalesce(lote_pi.codigo_lote, lote_pa.codigo_lote),
  gerado.quantidade, case when gerado.tipo_produto = 'PI' then 'L' else 'UN' end,
  gerado.created_at, 'producao_lote', 'pcp_op_produtos_gerados', gerado.id,
  gerado.status_lote <> 'cancelado'
from public.pcp_op_produtos_gerados gerado
join public.pcp_ordens_producao ordem on ordem.id = gerado.op_id
left join public.est_lotes_pi lote_pi on lote_pi.id = gerado.lote_pi_id
left join public.est_lotes_pa lote_pa on lote_pa.id = gerado.lote_pa_id

union all

select
  reserva.tipo_reserva,
  coalesce(reserva.lote_pi_id, reserva.lote_mp_id),
  coalesce(lote_pi.codigo_lote, lote_mp.codigo_lote),
  'ENVASE', ordem.id, ordem.codigo_ordem,
  reserva.quantidade_reservada,
  case when reserva.tipo_reserva = 'PI' then 'L' else 'UN' end,
  reserva.updated_at, 'consumo_envase', 'pcp_ordem_envase_reservas', reserva.id,
  reserva.status = 'consumida'
from public.pcp_ordem_envase_reservas reserva
join public.pcp_ordens_envase ordem on ordem.id = reserva.ordem_envase_id
left join public.est_lotes_pi lote_pi on lote_pi.id = reserva.lote_pi_id
left join public.est_lotes_mp lote_mp on lote_mp.id = reserva.lote_mp_id
where reserva.status in ('consumida', 'estornada')

union all

select
  'ENVASE', ordem.id, ordem.codigo_ordem,
  'PA', lote.id, lote.codigo_lote,
  gerado.quantidade, 'UN', gerado.created_at,
  'producao_envase', 'pcp_ordem_envase_lotes_pa', gerado.id,
  lote.status <> 'cancelado'
from public.pcp_ordem_envase_lotes_pa gerado
join public.pcp_ordens_envase ordem on ordem.id = gerado.ordem_envase_id
join public.est_lotes_pa lote on lote.id = gerado.lote_pa_id

union all

select
  'PA', lote.id, lote.codigo_lote,
  'ROMANEIO', romaneio.id, romaneio.codigo_romaneio,
  greatest(expedicao.quantidade, 0), 'UN', expedicao.evento_em,
  case when expedicao.quantidade > 0 then 'expedicao_confirmada' else 'expedicao_estornada' end,
  'exp_romaneio_movimentos_pa', expedicao.registro_id,
  expedicao.quantidade > 0
from expedicao_liquida expedicao
join public.est_lotes_pa lote on lote.id = expedicao.lote_pa_id
join public.exp_romaneios romaneio on romaneio.id = expedicao.romaneio_id

union all

select
  'ROMANEIO', romaneio.id, romaneio.codigo_romaneio,
  'PEDIDO', pedido.id, pedido.codigo_pedido,
  null::numeric, null::text, romaneio.created_at,
  'romaneio_do_pedido', 'exp_romaneios', romaneio.id,
  romaneio.status not in ('cancelado', 'estornado')
from public.exp_romaneios romaneio
join public.com_pedidos pedido on pedido.id = romaneio.pedido_id

union all

select
  'PEDIDO', pedido.id, pedido.codigo_pedido,
  'CLIENTE', cliente.id, cliente.nome,
  null::numeric, null::text, pedido.created_at,
  'pedido_do_cliente', 'com_pedidos', pedido.id,
  pedido.status <> 'cancelled'
from public.com_pedidos pedido
join public.cad_clientes cliente on cliente.id = pedido.cliente_id

union all

select
  'PEDIDO', pedido.id, pedido.codigo_pedido,
  'PROPRIEDADE', propriedade.id, propriedade.nome,
  null::numeric, null::text, pedido.created_at,
  'pedido_da_propriedade', 'com_pedidos', pedido.id,
  pedido.status <> 'cancelled'
from public.com_pedidos pedido
join public.cad_cliente_propriedades propriedade on propriedade.id = pedido.propriedade_id

union all

select
  case when nota.romaneio_id is null then 'PEDIDO' else 'ROMANEIO' end,
  coalesce(nota.romaneio_id, nota.pedido_id),
  coalesce(romaneio.codigo_romaneio, pedido.codigo_pedido),
  'REFERENCIA_FISCAL', nota.id, concat_ws('-', nota.numero, nullif(nota.serie, '')),
  nota.valor_nf, 'BRL', nota.created_at,
  'referencia_fiscal_externa', 'fat_notas_fiscais', nota.id,
  nota.status_atual = 'emitida'
from public.fat_notas_fiscais nota
join public.com_pedidos pedido on pedido.id = nota.pedido_id
left join public.exp_romaneios romaneio on romaneio.id = nota.romaneio_id
where nota.origem_registro = 'externa';

revoke all on public.rel_rastreabilidade_arestas from public, anon, authenticated;

comment on view public.rel_rastreabilidade_arestas is
  'Genealogia derivada. Referencias fiscais externas sao destinos documentais do pedido ou romaneio e nao movimentam estoque.';

create or replace function public.simular_rel_recolhimento(
  p_tipo_lote text,
  p_lote_id bigint
)
returns table(
  lote_pa_id bigint, codigo_lote text,
  produto text, status_lote text, saldo_fisico numeric,
  romaneio_id bigint, codigo_romaneio text,
  pedido_id bigint, codigo_pedido text,
  cliente_id bigint, cliente_nome text,
  propriedade_id bigint, propriedade_nome text,
  quantidade numeric, expedido_em timestamptz,
  referencia_fiscal_id bigint, referencia_fiscal text,
  contatos jsonb
)
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_current_user_permission('qualidade.rastreabilidade.recall_simulate');
  if upper(btrim(coalesce(p_tipo_lote, ''))) not in ('MP', 'PI', 'PA', 'EMBALAGEM') then
    raise exception 'invalid recall lot type';
  end if;
  if p_lote_id is null or p_lote_id <= 0 then
    raise exception 'recall lot is required';
  end if;

  return query
  with recursive descendentes(tipo, id, caminho) as (
    select
      upper(btrim(p_tipo_lote)),
      p_lote_id,
      array[upper(btrim(p_tipo_lote)) || ':' || p_lote_id]::text[]

    union all

    select
      edge.destino_tipo,
      edge.destino_id,
      array_append(
        descendentes.caminho,
        edge.destino_tipo || ':' || edge.destino_id::text
      )
    from descendentes
    join public.rel_rastreabilidade_arestas edge
      on edge.origem_tipo = descendentes.tipo
     and edge.origem_id = descendentes.id
    where edge.ativo
      and cardinality(descendentes.caminho) < 12
      and not (
        edge.destino_tipo || ':' || edge.destino_id::text = any(descendentes.caminho)
      )
  ), lotes_pa as (
    select distinct descendentes.id as lote_pa_id
    from descendentes
    where descendentes.tipo = 'PA'
  )
  select
    destino.lote_pa_id, destino.codigo_lote,
    destino.produto, destino.status_lote, destino.saldo_fisico,
    destino.romaneio_id, destino.codigo_romaneio,
    destino.pedido_id, destino.codigo_pedido,
    destino.cliente_id, destino.cliente_nome,
    destino.propriedade_id, destino.propriedade_nome,
    destino.quantidade, destino.expedido_em,
    destino.referencia_fiscal_id, destino.referencia_fiscal,
    destino.contatos
  from public.rel_rastreabilidade_destinos_cliente destino
  join lotes_pa on lotes_pa.lote_pa_id = destino.lote_pa_id
  order by destino.expedido_em, destino.romaneio_id;
end;
$$;

revoke all on function public.simular_rel_recolhimento(text, bigint)
  from public, anon, authenticated;
grant execute on function public.simular_rel_recolhimento(text, bigint)
  to authenticated;

comment on function public.simular_rel_recolhimento(text, bigint) is
  'Simula destinos ativos de um lote por genealogia derivada, sem bloquear, editar ou movimentar estoque.';
