-- A carga do romaneio deve usar a densidade real do CQ da OP que gerou o PI
-- consumido no envase. Mantem o caminho direto para lotes PA historicos.

create or replace view public.exp_romaneio_carga_resumo
with (security_invoker = true)
as
with item_base as (
  select
    item.id as romaneio_item_id, item.romaneio_id, item.quantidade_romaneada,
    embalagem.volume_litros, apresentacao.unidades_por_volume_logistico,
    versao.peso_tara_kg
  from public.exp_romaneio_itens item
  join public.cad_produto_embalagens apresentacao on apresentacao.id = item.produto_embalagem_id
  join public.cad_embalagens embalagem on embalagem.id = apresentacao.embalagem_id
  left join public.cad_embalagem_configuracoes_atuais versao on versao.embalagem_id = embalagem.id
  where item.status not in ('cancelado', 'estornado')
), lote_pa_densidades as (
  select distinct on (origem.lote_pa_id)
    origem.lote_pa_id,
    origem.densidade_kg_l
  from (
    select
      produto_pa.lote_pa_id,
      cq.densidade_kg_l,
      1 as prioridade,
      cq.id as cq_id
    from public.pcp_ordem_envase_lotes_pa produto_pa
    join public.pcp_ordens_envase envase
      on envase.id = produto_pa.ordem_envase_id
    join public.pcp_op_produtos_gerados produto_pi
      on produto_pi.lote_pi_id = envase.lote_pi_origem_id
     and produto_pi.tipo_produto = 'PI'
    join public.pcp_op_cq_resultados cq
      on cq.op_id = produto_pi.op_id

    union all

    select
      produto_pa.lote_pa_id,
      cq.densidade_kg_l,
      2 as prioridade,
      cq.id as cq_id
    from public.pcp_op_produtos_gerados produto_pa
    join public.pcp_op_cq_resultados cq
      on cq.op_id = produto_pa.op_id
    where produto_pa.tipo_produto = 'PA'
      and produto_pa.lote_pa_id is not null
  ) origem
  order by origem.lote_pa_id, origem.prioridade, origem.cq_id desc
), item_massas as (
  select
    base.romaneio_item_id,
    sum(reserva.quantidade_reservada) as quantidade_com_densidade,
    sum(
      reserva.quantidade_reservada
      * base.volume_litros
      * densidade.densidade_kg_l
    ) as peso_liquido_kg
  from item_base base
  join public.est_reservas_pa reserva
    on reserva.romaneio_item_id = base.romaneio_item_id
   and reserva.status in ('ativa', 'baixada')
  join lote_pa_densidades densidade
    on densidade.lote_pa_id = reserva.lote_pa_id
  group by base.romaneio_item_id
)
select
  romaneio.id as romaneio_id,
  coalesce(sum(base.quantidade_romaneada * base.volume_litros), 0) as volume_liquido_l,
  case when count(*) filter (where base.unidades_por_volume_logistico is null) > 0 then null
       else sum(ceil(base.quantidade_romaneada / base.unidades_por_volume_logistico)) end as volumes_logisticos,
  case when count(*) filter (where coalesce(massas.quantidade_com_densidade, 0) <> base.quantidade_romaneada) > 0 then null
       else sum(massas.peso_liquido_kg) end as peso_liquido_kg,
  case when count(*) filter (
         where coalesce(massas.quantidade_com_densidade, 0) <> base.quantidade_romaneada
            or base.peso_tara_kg is null or base.unidades_por_volume_logistico is null
       ) > 0 then null
       else sum(massas.peso_liquido_kg)
          + sum(ceil(base.quantidade_romaneada / base.unidades_por_volume_logistico) * base.peso_tara_kg) end as peso_bruto_kg,
  count(*) filter (where base.unidades_por_volume_logistico is null) as itens_sem_volume_configurado,
  count(*) filter (where coalesce(massas.quantidade_com_densidade, 0) <> base.quantidade_romaneada) as itens_sem_densidade,
  count(*) filter (where base.peso_tara_kg is null) as itens_sem_tara
from public.exp_romaneios romaneio
join item_base base on base.romaneio_id = romaneio.id
left join item_massas massas on massas.romaneio_item_id = base.romaneio_item_id
group by romaneio.id;

revoke all on public.exp_romaneio_carga_resumo from public, anon, authenticated;
grant select on public.exp_romaneio_carga_resumo to authenticated;

comment on view public.exp_romaneio_carga_resumo is
  'Resumo calculado da carga. PA de envase usa a densidade real do CQ da OP operacional que gerou o PI; valores ausentes nao sao inventados.';
