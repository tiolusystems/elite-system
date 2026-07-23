import { getRuntimeStatus } from "@/lib/runtime";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type RomaneioLookupOption = {
  id: number;
  label: string;
  detail: string | null;
};

export type RomaneioPendingItem = {
  pedidoItemId: number;
  pedidoId: number;
  codigoPedido: string;
  clienteNome: string;
  produtoEmbalagemId: number;
  itemLabel: string;
  quantidadePedido: number;
  quantidadeConfirmada: number;
  quantidadeEmSeparacao: number;
  quantidadePendente: number;
  quantidadeComprometida: number;
  quantidadeDisponivelRomaneio: number;
  quantidadeExcedente: number;
  volumeUnitarioL: number | null;
  unidadesPorVolume: number | null;
  densidadeReferenciaKgL: number | null;
  taraVolumeKg: number | null;
};

export type RomaneioReservation = {
  id: number;
  romaneioItemId: number;
  lotePaId: number;
  loteLabel: string;
  quantidadeReservada: number;
  status: string;
  createdAt: string;
};

export type RomaneioItem = {
  id: number;
  romaneioId: number;
  pedidoItemId: number;
  produtoEmbalagemId: number;
  itemLabel: string;
  lotePaRef: string | null;
  quantidadeRomaneada: number;
  quantidadeReservada: number;
  status: string;
  reservations: RomaneioReservation[];
};

export type RomaneioMovement = {
  id: number;
  romaneioId: number;
  romaneioItemId: number;
  loteLabel: string;
  tipoMovimento: string;
  quantidade: number;
  createdAt: string;
};

export type RomaneioLogistics = {
  eventId: number;
  entregadorId: number | null;
  entregadorNome: string | null;
  veiculoId: number | null;
  veiculoLabel: string | null;
  occurredAt: string;
};

export type RomaneioFiscalDocument = {
  id: number;
  numberLabel: string;
  type: string;
  status: string;
  issuedAt: string;
  value: number;
};

export type RomaneioRecord = {
  id: number;
  codigoRomaneio: string;
  pedidoId: number;
  pedidoLabel: string;
  clienteNome: string;
  tipoSeparacao: string;
  status: string;
  dataRomaneio: string;
  observacao: string | null;
  confirmadoAt: string | null;
  canceladoAt: string | null;
  estornadoAt: string | null;
  createdAt: string;
  emissorNome: string;
  items: RomaneioItem[];
  movements: RomaneioMovement[];
  logistics: RomaneioLogistics | null;
  fiscalDocuments: RomaneioFiscalDocument[];
  simpleBillingReferences: RomaneioFiscalDocument[];
  carga: {
    volumeLiquidoL: number;
    volumesLogisticos: number | null;
    pesoLiquidoKg: number | null;
    pesoBrutoKg: number | null;
    pendencias: string[];
  } | null;
};

export type RomaneioAvailableLot = {
  id: number;
  produtoEmbalagemId: number;
  itemLabel: string;
  codigoLote: string;
  status: string;
  saldoFisico: number;
  quantidadeReservada: number;
  saldoDisponivel: number;
  dataValidade: string | null;
  updatedAt: string;
};

export type RomaneioLookups = {
  pendingItems: RomaneioLookupOption[];
  romaneiosAbertos: RomaneioLookupOption[];
  romaneioItemsAbertos: RomaneioLookupOption[];
  lotesPa: RomaneioLookupOption[];
  entregadores: RomaneioLookupOption[];
  veiculos: RomaneioLookupOption[];
};

export type RomaneioDashboard = {
  metrics: {
    pedidosComPendencia: number | null;
    itensPendentes: number | null;
    romaneiosRascunho: number | null;
    romaneiosSeparacao: number | null;
    romaneiosConfirmados: number | null;
    quantidadePendente: number | null;
    quantidadeDisponivelRomaneio: number | null;
  };
  lookups: RomaneioLookups;
  pendingItems: RomaneioPendingItem[];
  romaneios: RomaneioRecord[];
  availableLots: RomaneioAvailableLot[];
  source: "supabase" | "not_configured" | "error";
  error: string | null;
};

const EMPTY_LOOKUPS: RomaneioLookups = {
  pendingItems: [],
  romaneiosAbertos: [],
  romaneioItemsAbertos: [],
  lotesPa: [],
  entregadores: [],
  veiculos: []
};

export async function getRomaneioDashboard(): Promise<RomaneioDashboard> {
  const runtime = getRuntimeStatus();
  if (!runtime.supabaseConfigured) {
    return emptyDashboard("not_configured", null);
  }

  try {
    const supabase = await createSupabaseServerClient();
    const produtoEmbalagensPromise = (async () => {
      const completeResult = await supabase
        .from("cad_produto_embalagens")
        .select(
          "id,codigo_item,status,produto_id,embalagem_id,unidades_por_volume_logistico,cad_produtos_base(codigo_produto,nome,densidade_kg_l),cad_embalagens(descricao,volume_litros,unidade)"
        )
        .limit(500);

      if (!completeResult.error?.message.includes("unidades_por_volume_logistico")) {
        return completeResult;
      }

      // Durante upgrade controlado, a tela continua consultiva e marca a
      // configuracao logistica como pendente em vez de ocultar todo o painel.
      return supabase
        .from("cad_produto_embalagens")
        .select(
          "id,codigo_item,status,produto_id,embalagem_id,cad_produtos_base(codigo_produto,nome,densidade_kg_l),cad_embalagens(descricao,volume_litros,unidade)"
        )
        .limit(500);
    })();
    const cargasPromise = (async () => {
      const result = await supabase
        .from("exp_romaneio_carga_resumo")
        .select("romaneio_id,volume_liquido_l,volumes_logisticos,peso_liquido_kg,peso_bruto_kg,itens_sem_volume_configurado,itens_sem_densidade,itens_sem_tara")
        .limit(200);

      if (result.error?.message.includes("exp_romaneio_carga_resumo")) {
        return { data: [], error: null };
      }

      return result;
    })();
    const [
      pendingBalances,
      orders,
      clientes,
      produtoEmbalagens,
      configuracoesEmbalagem,
      romaneios,
      romaneioItems,
      reservas,
      movimentos,
      lotesPa,
      logisticaAtual,
      pessoasComerciais,
      papeisAtivos,
      veiculos,
      notasFiscais,
      cargas,
      usuarios
    ] = await Promise.all([
      supabase
        .from("exp_pedido_item_romaneio_saldos")
        .select(
          "pedido_item_id,pedido_id,produto_embalagem_id,quantidade_pedido,quantidade_confirmada,quantidade_em_separacao,quantidade_pendente,quantidade_comprometida,quantidade_disponivel_romaneio,quantidade_excedente"
        )
        .gt("quantidade_pendente", 0)
        .limit(300),
      supabase
        .from("com_pedidos")
        .select("id,codigo_pedido,cliente_id,tipo_pedido,status,data_pedido,valor_total")
        .in("status", ["open", "fulfilled"])
        .order("data_pedido", { ascending: false })
        .limit(300),
      supabase.from("cad_clientes").select("id,nome,cidade,uf").limit(500),
      produtoEmbalagensPromise,
      supabase
        .from("cad_embalagem_configuracoes_atuais")
        .select("embalagem_id,peso_tara_kg")
        .limit(500),
      supabase
        .from("exp_romaneios")
        .select(
          "id,codigo_romaneio,pedido_id,tipo_separacao,status,data_romaneio,observacao,confirmado_at,cancelado_at,estornado_at,created_by,created_at"
        )
        .order("created_at", { ascending: false })
        .limit(80),
      supabase
        .from("exp_romaneio_itens")
        .select(
          "id,romaneio_id,pedido_id,pedido_item_id,produto_embalagem_id,lote_pa_id,lote_pa_ref,quantidade_romaneada,quantidade_reservada,status,created_at"
        )
        .order("created_at", { ascending: false })
        .limit(600),
      supabase
        .from("est_reservas_pa")
        .select("id,lote_pa_id,romaneio_id,romaneio_item_id,produto_embalagem_id,quantidade_reservada,status,created_at")
        .order("created_at", { ascending: false })
        .limit(600),
      supabase
        .from("exp_romaneio_movimentos_pa")
        .select("id,romaneio_id,romaneio_item_id,lote_pa_ref,lote_pa_id,tipo_movimento,quantidade,created_at")
        .order("created_at", { ascending: false })
        .limit(600),
      supabase
        .from("est_lotes_pa_saldos")
        .select(
          "lote_pa_id,produto_embalagem_id,codigo_lote,status,data_validade,saldo_fisico,quantidade_reservada,saldo_disponivel,updated_at"
        )
        .order("updated_at", { ascending: false })
        .limit(400),
      supabase
        .from("exp_romaneio_logistica_atual")
        .select("romaneio_id,entregador_id,veiculo_id,ocorrido_em,evento_id")
        .limit(200),
      supabase
        .from("cad_pessoas_comerciais")
        .select("id,nome,tipo_comercial,status")
        .eq("status", "active")
        .order("nome", { ascending: true })
        .limit(500),
      supabase
        .from("cad_pessoas_comerciais_papeis_ativos")
        .select("pessoa_id,papel,vigencia_inicio")
        .eq("papel", "entregador")
        .limit(500),
      supabase
        .from("cad_veiculos")
        .select("id,descricao,placa,status,capacidade")
        .eq("status", "active")
        .order("descricao", { ascending: true })
        .limit(300),
      supabase
        .from("fat_notas_fiscais")
        .select("id,pedido_id,romaneio_id,numero,serie,tipo,status_atual,data_emissao,valor_nf,origem_registro")
        .eq("origem_registro", "externa")
        .order("data_emissao", { ascending: false })
        .limit(300),
      cargasPromise,
      supabase.from("user_profiles").select("id,display_name").limit(500)
    ]);

    const orderRows = rows(orders);
    const clienteMap = new Map(rows(clientes).map((row) => [Number(row.id), String(row.nome)]));
    const orderMap = new Map(orderRows.map((row) => [Number(row.id), mapOrder(row, clienteMap)]));
    const productPackageMap = new Map(rows(produtoEmbalagens).map((row) => [Number(row.id), packageLabel(row)]));
    const tareByPackageId = new Map(rows(configuracoesEmbalagem).map((row) => [Number(row.embalagem_id), nullableNumber(row.peso_tara_kg)]));
    const productPackageMetrics = new Map(rows(produtoEmbalagens).map((row) => {
      const product = firstNested(row.cad_produtos_base);
      const packaging = firstNested(row.cad_embalagens);
      return [Number(row.id), {
        volumeUnitarioL: packaging ? nullableNumber(packaging.volume_litros) : null,
        unidadesPorVolume: nullableNumber(row.unidades_por_volume_logistico),
        densidadeReferenciaKgL: product ? nullableNumber(product.densidade_kg_l) : null,
        taraVolumeKg: tareByPackageId.get(Number(row.embalagem_id)) ?? null
      }] as const;
    }));
    const lotRows = rows(lotesPa);
    const availableLots = lotRows.map((row) => mapLot(row, productPackageMap));
    const lotMap = new Map(availableLots.map((lot) => [lot.id, `${lot.codigoLote} - ${lot.itemLabel}`]));
    const personRows = rows(pessoasComerciais);
    const personMap = new Map(personRows.map((row) => [Number(row.id), String(row.nome)]));
    const courierIds = new Set(rows(papeisAtivos).map((row) => Number(row.pessoa_id)));
    const vehicleRows = rows(veiculos);
    const vehicleMap = new Map(vehicleRows.map((row) => [Number(row.id), vehicleLabel(row)]));
    const logisticsByRomaneio = new Map(
      rows(logisticaAtual).map((row) => {
        const romaneioId = Number(row.romaneio_id);
        const entregadorId = nullableNumber(row.entregador_id);
        const veiculoId = nullableNumber(row.veiculo_id);
        return [
          romaneioId,
          {
            eventId: Number(row.evento_id),
            entregadorId,
            entregadorNome: entregadorId ? personMap.get(entregadorId) ?? `entregador ${entregadorId}` : null,
            veiculoId,
            veiculoLabel: veiculoId ? vehicleMap.get(veiculoId) ?? `veiculo ${veiculoId}` : null,
            occurredAt: String(row.ocorrido_em)
          } satisfies RomaneioLogistics
        ] as const;
      })
    );
    const fiscalDocumentsByRomaneio = groupBy(
      rows(notasFiscais).filter((row) => row.romaneio_id != null).map(mapFiscalDocument),
      (document) => document.romaneioId
    );
    const simpleReferencesByOrder = groupBy(
      rows(notasFiscais).filter((row) => row.tipo === "simples_faturamento").map(mapFiscalDocument),
      (document) => document.pedidoId
    );
    const cargaByRomaneio = new Map(rows(cargas).map((row) => [Number(row.romaneio_id), mapCarga(row)]));
    const userNameById = new Map(rows(usuarios).map((row) => [String(row.id), String(row.display_name)]));

    const pendingItems = rows(pendingBalances)
      .map((row) => mapPendingItem(row, orderMap, productPackageMap, productPackageMetrics))
      .sort((left, right) => right.quantidadePendente - left.quantidadePendente);
    const allocatableItems = pendingItems.filter((item) => item.quantidadeDisponivelRomaneio > 0);

    const reservationsByItem = groupBy(
      rows(reservas).map((row) => mapReservation(row, lotMap)),
      (reservation) => reservation.romaneioItemId
    );
    const itemsByRomaneio = groupBy(
      rows(romaneioItems).map((row) => mapRomaneioItem(row, productPackageMap, reservationsByItem)),
      (item) => item.romaneioId
    );
    const movementsByRomaneio = groupBy(
      rows(movimentos).map((row) => mapMovement(row, lotMap)),
      (movement) => movement.romaneioId
    );

    const romaneioRecords = rows(romaneios).map((row) => {
      const id = Number(row.id);
      const order = orderMap.get(Number(row.pedido_id));
      return {
        id,
        codigoRomaneio: String(row.codigo_romaneio),
        pedidoId: Number(row.pedido_id),
        pedidoLabel: order?.label ?? `pedido ${row.pedido_id}`,
        clienteNome: order?.clienteNome ?? "cliente nao carregado",
        tipoSeparacao: String(row.tipo_separacao),
        status: String(row.status),
        dataRomaneio: String(row.data_romaneio),
        observacao: nullableString(row.observacao),
        confirmadoAt: nullableString(row.confirmado_at),
        canceladoAt: nullableString(row.cancelado_at),
        estornadoAt: nullableString(row.estornado_at),
        createdAt: String(row.created_at),
        emissorNome: userNameById.get(String(row.created_by)) ?? "Usuario nao identificado",
        items: itemsByRomaneio.get(id) ?? [],
        movements: movementsByRomaneio.get(id) ?? [],
        logistics: logisticsByRomaneio.get(id) ?? null,
        fiscalDocuments: (fiscalDocumentsByRomaneio.get(id) ?? []).map((document) => ({
          id: document.id,
          numberLabel: document.numberLabel,
          type: document.type,
          status: document.status,
          issuedAt: document.issuedAt,
          value: document.value
        })),
        simpleBillingReferences: (simpleReferencesByOrder.get(Number(row.pedido_id)) ?? []).map((document) => ({
          id: document.id,
          numberLabel: document.numberLabel,
          type: document.type,
          status: document.status,
          issuedAt: document.issuedAt,
          value: document.value
        })),
        carga: cargaByRomaneio.get(id) ?? null
      } satisfies RomaneioRecord;
    });

    const openRomaneios = romaneioRecords.filter((romaneio) => ["draft", "separacao"].includes(romaneio.status));
    const openItems = openRomaneios.flatMap((romaneio) => romaneio.items.filter((item) => ["draft", "reservado"].includes(item.status)));
    const firstError = firstResponseError([
      pendingBalances,
      orders,
      clientes,
      produtoEmbalagens,
      configuracoesEmbalagem,
      romaneios,
      romaneioItems,
      reservas,
      movimentos,
      lotesPa,
      logisticaAtual,
      pessoasComerciais,
      papeisAtivos,
      veiculos,
      notasFiscais,
      cargas,
      usuarios
    ]);

    return {
      metrics: {
        pedidosComPendencia: new Set(pendingItems.map((item) => item.pedidoId)).size,
        itensPendentes: pendingItems.length,
        romaneiosRascunho: romaneioRecords.filter((romaneio) => romaneio.status === "draft").length,
        romaneiosSeparacao: romaneioRecords.filter((romaneio) => romaneio.status === "separacao").length,
        romaneiosConfirmados: romaneioRecords.filter((romaneio) => romaneio.status === "confirmado").length,
        quantidadePendente: pendingItems.reduce((sum, item) => sum + item.quantidadePendente, 0),
        quantidadeDisponivelRomaneio: allocatableItems.reduce(
          (sum, item) => sum + item.quantidadeDisponivelRomaneio,
          0
        )
      },
      lookups: {
        pendingItems: allocatableItems.map((item) => ({
          id: item.pedidoItemId,
          label: `${item.codigoPedido} - ${item.clienteNome} - ${item.itemLabel}`,
          detail: `livre ${numberText(item.quantidadeDisponivelRomaneio)} / pendente ${numberText(item.quantidadePendente)}`
        })),
        romaneiosAbertos: openRomaneios.map((romaneio) => ({
          id: romaneio.id,
          label: `${romaneio.codigoRomaneio} - ${romaneio.pedidoLabel}`,
          detail: `${romaneio.status} / ${romaneio.items.length} item(ns)`
        })),
        romaneioItemsAbertos: openItems.map((item) => ({
          id: item.id,
          label: `${item.itemLabel}`,
          detail: `romaneio ${item.romaneioId} / romaneado ${numberText(item.quantidadeRomaneada)} / reservado ${numberText(item.quantidadeReservada)}`
        })),
        lotesPa: availableLots
          .filter((lot) => lot.status === "disponivel" && lot.saldoDisponivel > 0)
          .map((lot) => ({
            id: lot.id,
            label: `${lot.codigoLote} - ${lot.itemLabel}`,
            detail: `disp ${numberText(lot.saldoDisponivel)} / val ${lot.dataValidade ?? "-"}`
          })),
        entregadores: personRows
          .filter((row) => courierIds.has(Number(row.id)))
          .map((row) => ({
            id: Number(row.id),
            label: String(row.nome),
            detail: nullableString(row.tipo_comercial)
          })),
        veiculos: vehicleRows.map((row) => ({
          id: Number(row.id),
          label: vehicleLabel(row),
          detail:
            row.capacidade === null || row.capacidade === undefined
              ? null
              : `capacidade ${numberText(Number(row.capacidade))}`
        }))
      },
      pendingItems,
      romaneios: romaneioRecords,
      availableLots,
      source: firstError ? "error" : "supabase",
      error: firstError
    };
  } catch (error) {
    return emptyDashboard("error", error instanceof Error ? error.message : "Erro desconhecido");
  }
}

function mapOrder(row: Record<string, unknown>, clienteMap: Map<number, string>) {
  const clienteNome = clienteMap.get(Number(row.cliente_id)) ?? `cliente ${row.cliente_id}`;
  return {
    id: Number(row.id),
    label: `${row.codigo_pedido} - ${clienteNome}`,
    clienteNome,
    status: String(row.status)
  };
}

function mapCarga(row: Record<string, unknown>) {
  const pendencias: string[] = [];
  if (Number(row.itens_sem_volume_configurado) > 0) pendencias.push("configuração de volumes");
  if (Number(row.itens_sem_densidade) > 0) pendencias.push("densidade do lote");
  if (Number(row.itens_sem_tara) > 0) pendencias.push("tara da embalagem");
  return {
    volumeLiquidoL: Number(row.volume_liquido_l ?? 0),
    volumesLogisticos: nullableNumber(row.volumes_logisticos),
    pesoLiquidoKg: nullableNumber(row.peso_liquido_kg),
    pesoBrutoKg: nullableNumber(row.peso_bruto_kg),
    pendencias
  };
}

function mapPendingItem(
  row: Record<string, unknown>,
  orderMap: Map<number, { id: number; label: string; clienteNome: string; status: string }>,
  productPackageMap: Map<number, string>,
  productPackageMetrics: Map<number, { volumeUnitarioL: number | null; unidadesPorVolume: number | null; densidadeReferenciaKgL: number | null; taraVolumeKg: number | null }>
): RomaneioPendingItem {
  const pedidoId = Number(row.pedido_id);
  const order = orderMap.get(pedidoId);
  const produtoEmbalagemId = Number(row.produto_embalagem_id);
  const metrics = productPackageMetrics.get(produtoEmbalagemId);
  return {
    pedidoItemId: Number(row.pedido_item_id),
    pedidoId,
    codigoPedido: order?.label.split(" - ")[0] ?? `pedido ${pedidoId}`,
    clienteNome: order?.clienteNome ?? "cliente nao carregado",
    produtoEmbalagemId,
    itemLabel: productPackageMap.get(produtoEmbalagemId) ?? `item ${produtoEmbalagemId}`,
    quantidadePedido: Number(row.quantidade_pedido ?? 0),
    quantidadeConfirmada: Number(row.quantidade_confirmada ?? 0),
    quantidadeEmSeparacao: Number(row.quantidade_em_separacao ?? 0),
    quantidadePendente: Number(row.quantidade_pendente ?? 0),
    quantidadeComprometida: Number(row.quantidade_comprometida ?? 0),
    quantidadeDisponivelRomaneio: Number(row.quantidade_disponivel_romaneio ?? 0),
    quantidadeExcedente: Number(row.quantidade_excedente ?? 0),
    volumeUnitarioL: metrics?.volumeUnitarioL ?? null,
    unidadesPorVolume: metrics?.unidadesPorVolume ?? null,
    densidadeReferenciaKgL: metrics?.densidadeReferenciaKgL ?? null,
    taraVolumeKg: metrics?.taraVolumeKg ?? null
  };
}

function mapRomaneioItem(
  row: Record<string, unknown>,
  productPackageMap: Map<number, string>,
  reservationsByItem: Map<number, RomaneioReservation[]>
): RomaneioItem {
  const produtoEmbalagemId = Number(row.produto_embalagem_id);
  const id = Number(row.id);
  return {
    id,
    romaneioId: Number(row.romaneio_id),
    pedidoItemId: Number(row.pedido_item_id),
    produtoEmbalagemId,
    itemLabel: productPackageMap.get(produtoEmbalagemId) ?? `item ${produtoEmbalagemId}`,
    lotePaRef: nullableString(row.lote_pa_ref),
    quantidadeRomaneada: Number(row.quantidade_romaneada ?? 0),
    quantidadeReservada: Number(row.quantidade_reservada ?? 0),
    status: String(row.status),
    reservations: reservationsByItem.get(id) ?? []
  };
}

function mapReservation(row: Record<string, unknown>, lotMap: Map<number, string>): RomaneioReservation {
  const lotePaId = Number(row.lote_pa_id);
  return {
    id: Number(row.id),
    romaneioItemId: Number(row.romaneio_item_id),
    lotePaId,
    loteLabel: lotMap.get(lotePaId) ?? `lote ${lotePaId}`,
    quantidadeReservada: Number(row.quantidade_reservada ?? 0),
    status: String(row.status),
    createdAt: String(row.created_at)
  };
}

function mapMovement(row: Record<string, unknown>, lotMap: Map<number, string>): RomaneioMovement {
  const lotePaId = nullableNumber(row.lote_pa_id);
  return {
    id: Number(row.id),
    romaneioId: Number(row.romaneio_id),
    romaneioItemId: Number(row.romaneio_item_id),
    loteLabel: lotePaId ? lotMap.get(lotePaId) ?? `lote ${lotePaId}` : nullableString(row.lote_pa_ref) ?? "lote textual",
    tipoMovimento: String(row.tipo_movimento),
    quantidade: Number(row.quantidade ?? 0),
    createdAt: String(row.created_at)
  };
}

function mapFiscalDocument(row: Record<string, unknown>): RomaneioFiscalDocument & { romaneioId: number; pedidoId: number } {
  const number = nullableString(row.numero);
  const series = nullableString(row.serie);
  return {
    id: Number(row.id),
    romaneioId: Number(row.romaneio_id),
    pedidoId: Number(row.pedido_id),
    numberLabel: number ? `${number}${series ? ` / serie ${series}` : ""}` : "numero pendente",
    type: String(row.tipo),
    status: String(row.status_atual),
    issuedAt: String(row.data_emissao),
    value: Number(row.valor_nf ?? 0)
  };
}

function mapLot(row: Record<string, unknown>, productPackageMap: Map<number, string>): RomaneioAvailableLot {
  const produtoEmbalagemId = Number(row.produto_embalagem_id);
  return {
    id: Number(row.lote_pa_id),
    produtoEmbalagemId,
    itemLabel: productPackageMap.get(produtoEmbalagemId) ?? `item ${produtoEmbalagemId}`,
    codigoLote: String(row.codigo_lote),
    status: String(row.status),
    saldoFisico: Number(row.saldo_fisico ?? 0),
    quantidadeReservada: Number(row.quantidade_reservada ?? 0),
    saldoDisponivel: Number(row.saldo_disponivel ?? 0),
    dataValidade: nullableString(row.data_validade),
    updatedAt: String(row.updated_at ?? "")
  };
}

function packageLabel(row: Record<string, unknown>): string {
  const produto = firstNested(row.cad_produtos_base);
  const embalagem = firstNested(row.cad_embalagens);
  const produtoLabel = produto ? `${produto.codigo_produto ?? ""} ${produto.nome ?? ""}`.trim() : `produto ${row.produto_id}`;
  const embalagemLabel = embalagem ? `${embalagem.descricao ?? ""}`.trim() : `embalagem ${row.embalagem_id}`;
  return `${row.codigo_item ?? "sem item"} - ${produtoLabel} / ${embalagemLabel}`;
}

function vehicleLabel(row: Record<string, unknown>): string {
  const plate = nullableString(row.placa);
  return plate ? `${row.descricao} - ${plate}` : String(row.descricao);
}

function rows(response: { data: unknown[] | null; error: { message: string } | null }): Array<Record<string, unknown>> {
  return response.error ? [] : ((response.data ?? []) as Array<Record<string, unknown>>);
}

function firstResponseError(responses: Array<{ error: { message: string } | null }>): string | null {
  return responses.find((response) => response.error)?.error?.message ?? null;
}

function groupBy<T, K>(items: T[], keyFor: (item: T) => K): Map<K, T[]> {
  const grouped = new Map<K, T[]>();
  for (const item of items) {
    const key = keyFor(item);
    const existing = grouped.get(key) ?? [];
    existing.push(item);
    grouped.set(key, existing);
  }
  return grouped;
}

function firstNested(value: unknown): Record<string, unknown> | null {
  if (Array.isArray(value)) {
    return (value[0] as Record<string, unknown> | undefined) ?? null;
  }
  if (value && typeof value === "object") {
    return value as Record<string, unknown>;
  }
  return null;
}

function nullableString(value: unknown): string | null {
  return value === null || value === undefined ? null : String(value);
}

function nullableNumber(value: unknown): number | null {
  return value === null || value === undefined ? null : Number(value);
}

function numberText(value: number): string {
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 4 }).format(value);
}

function emptyDashboard(source: RomaneioDashboard["source"], error: string | null): RomaneioDashboard {
  return {
    metrics: {
      pedidosComPendencia: null,
      itensPendentes: null,
      romaneiosRascunho: null,
      romaneiosSeparacao: null,
      romaneiosConfirmados: null,
      quantidadePendente: null,
      quantidadeDisponivelRomaneio: null
    },
    lookups: EMPTY_LOOKUPS,
    pendingItems: [],
    romaneios: [],
    availableLots: [],
    source,
    error
  };
}
