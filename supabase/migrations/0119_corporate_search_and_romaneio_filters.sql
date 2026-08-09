-- OPS-02A: paginated, human-oriented Romaneio consultation.
-- Read-only and SECURITY INVOKER: existing RLS remains authoritative.

create or replace function public.buscar_exp_romaneios_paginada(
  p_busca text default null,
  p_cliente_id bigint default null,
  p_pedido_id bigint default null,
  p_propriedade_id bigint default null,
  p_romaneio_id bigint default null,
  p_referencia_fiscal text default null,
  p_data_inicio date default null,
  p_data_fim date default null,
  p_statuses text[] default null,
  p_entregador_id bigint default null,
  p_veiculo_id bigint default null,
  p_produto_id bigint default null,
  p_lote_pa_id bigint default null,
  p_limite integer default 20,
  p_offset integer default 0
)
returns table (
  id bigint,
  codigo_romaneio text,
  pedido_id bigint,
  tipo_separacao text,
  status text,
  data_romaneio date,
  observacao text,
  confirmado_at timestamptz,
  cancelado_at timestamptz,
  estornado_at timestamptz,
  created_by uuid,
  created_at timestamptz,
  total_registros bigint
)
language sql
stable
security invoker
set search_path = public
as $$
  with filtered as (
    select shipment.*
      from public.exp_romaneios shipment
      join public.com_pedidos orders on orders.id = shipment.pedido_id
      join public.cad_clientes customer on customer.id = orders.cliente_id
      left join public.cad_cliente_identificacoes identification
        on identification.cliente_id = customer.id
      left join public.cad_cliente_propriedades property
        on property.id = orders.propriedade_id
      left join public.exp_romaneio_logistica_atual logistics
        on logistics.romaneio_id = shipment.id
     where public.current_actor_id() is not null
       and (p_cliente_id is null or orders.cliente_id = p_cliente_id)
       and (p_pedido_id is null or orders.id = p_pedido_id)
       and (p_propriedade_id is null or orders.propriedade_id = p_propriedade_id)
       and (p_romaneio_id is null or shipment.id = p_romaneio_id)
       and (p_data_inicio is null or shipment.data_romaneio >= p_data_inicio)
       and (p_data_fim is null or shipment.data_romaneio <= p_data_fim)
       and (p_statuses is null or cardinality(p_statuses) = 0 or shipment.status = any(p_statuses))
       and (p_entregador_id is null or logistics.entregador_id = p_entregador_id)
       and (p_veiculo_id is null or logistics.veiculo_id = p_veiculo_id)
       and (
         public.normalize_client_search_text(p_busca) is null
         or public.normalize_client_search_text(shipment.codigo_romaneio)
              like '%' || public.normalize_client_search_text(p_busca) || '%'
         or public.normalize_client_search_text(orders.codigo_pedido)
              like '%' || public.normalize_client_search_text(p_busca) || '%'
         or public.normalize_client_search_text(customer.nome)
              like '%' || public.normalize_client_search_text(p_busca) || '%'
         or public.normalize_client_search_text(identification.razao_social)
              like '%' || public.normalize_client_search_text(p_busca) || '%'
         or public.normalize_client_search_text(identification.nome_fantasia)
              like '%' || public.normalize_client_search_text(p_busca) || '%'
         or public.normalize_client_search_text(property.nome)
              like '%' || public.normalize_client_search_text(p_busca) || '%'
         or exists (
           select 1
             from public.cad_cliente_documentos document
            where document.cliente_id = customer.id
              and public.normalize_client_search_text(document.numero)
                    like '%' || public.normalize_client_search_text(p_busca) || '%'
         )
       )
       and (
         public.normalize_client_search_text(p_referencia_fiscal) is null
         or exists (
           select 1
             from public.fat_notas_fiscais invoice
            where invoice.romaneio_id = shipment.id
              and invoice.origem_registro = 'externa'
              and public.normalize_client_search_text(
                    coalesce(invoice.numero, '') || coalesce(invoice.serie, '')
                  ) like '%' || public.normalize_client_search_text(p_referencia_fiscal) || '%'
         )
       )
       and (
         p_produto_id is null
         or exists (
           select 1
             from public.exp_romaneio_itens shipment_item
             join public.cad_produto_embalagens presentation
               on presentation.id = shipment_item.produto_embalagem_id
            where shipment_item.romaneio_id = shipment.id
              and presentation.produto_id = p_produto_id
         )
       )
       and (
         p_lote_pa_id is null
         or exists (
           select 1
             from public.est_reservas_pa reservation
            where reservation.romaneio_id = shipment.id
              and reservation.lote_pa_id = p_lote_pa_id
         )
         or exists (
           select 1
             from public.exp_romaneio_movimentos_pa movement
            where movement.romaneio_id = shipment.id
              and movement.lote_pa_id = p_lote_pa_id
         )
       )
  ), counted as (
    select filtered.*, count(*) over() as row_count
      from filtered
  )
  select
    counted.id,
    counted.codigo_romaneio,
    counted.pedido_id,
    counted.tipo_separacao,
    counted.status,
    counted.data_romaneio,
    counted.observacao,
    counted.confirmado_at,
    counted.cancelado_at,
    counted.estornado_at,
    counted.created_by,
    counted.created_at,
    counted.row_count
  from counted
  order by counted.data_romaneio desc, counted.id desc
  limit least(greatest(coalesce(p_limite, 20), 1), 50)
  offset greatest(coalesce(p_offset, 0), 0)
$$;

revoke all on function public.buscar_exp_romaneios_paginada(
  text, bigint, bigint, bigint, bigint, text, date, date, text[], bigint,
  bigint, bigint, bigint, integer, integer
) from public, anon;

grant execute on function public.buscar_exp_romaneios_paginada(
  text, bigint, bigint, bigint, bigint, text, date, date, text[], bigint,
  bigint, bigint, bigint, integer, integer
) to authenticated;

comment on function public.buscar_exp_romaneios_paginada(
  text, bigint, bigint, bigint, bigint, text, date, date, text[], bigint,
  bigint, bigint, bigint, integer, integer
) is
  'Consulta paginada de Romaneios por critérios humanos e relacionais; SECURITY INVOKER preserva RLS.';
