import { randomUUID } from "node:crypto";
import Link from "next/link";

import {
  assignRomaneioLogisticsAction,
  cancelRomaneioAction,
  confirmRomaneioAction,
  correctExternalFiscalReferenceAction,
  removeRomaneioLogisticsAction,
  registerExternalFiscalReferenceAction,
  reverseRomaneioAction
} from "@/app/romaneios/actions";
import { RomaneioPreparation } from "@/app/romaneios/romaneio-preparation";
import { EntityLookup } from "@/app/corporate-search/entity-lookup";
import { ActiveFilterChips, AdvancedFilterPanel, FilterActions, FilterToolbar, SearchField } from "@/app/corporate-search/search-controls";
import {
  DataTable,
  type DataTableColumn,
  PaginationBar,
  PrimarySecondaryCell,
  StatusBadge
} from "@/app/operational-table/operational-table";
import {
  getRomaneioDashboard,
  type RomaneioItem,
  type RomaneioLookupOption,
  type RomaneioLookups,
  type RomaneioRecord
} from "@/lib/romaneios";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function RomaneiosPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const result = singleValue(params.result);
  const statusView = singleValue(params.status) ?? null;
  const mode = singleValue(params.modo) === "consulta" ? "consulta" : "planejar";
  const query = singleValue(params.busca)?.trim() ?? "";
  const page = positiveInteger(singleValue(params.pagina)) ?? 1;
  const selectedRomaneioId = positiveInteger(singleValue(params.selecionado));
  const filters = parseConsultationFilters(params, statusView, query);
  const dashboard = await getRomaneioDashboard({
    page,
    pageSize: mode === "consulta" ? 20 : 50,
    status: mode === "consulta" ? statusView : null,
    query: mode === "consulta" ? query : null,
    clientId: filters.clientId,
    orderId: filters.orderId,
    propertyId: filters.propertyId,
    shipmentId: filters.shipmentId,
    fiscalReference: filters.fiscalReference,
    startDate: filters.startDate,
    endDate: filters.endDate,
    courierId: filters.courierId,
    vehicleId: filters.vehicleId,
    productId: filters.productId,
    finishedLotId: filters.finishedLotId
  });
  const formMessage = messageForResult(result);
  const selectedRomaneio = dashboard.romaneios.find((romaneio) => romaneio.id === selectedRomaneioId) ?? null;

  return (
    <main className="app-shell">
      <section className="workspace dashboard-workspace">
        <div className="dashboard-header">
          <div>
            <span className="eyebrow">expedição controlada</span>
            <h1>Romaneio e separação por lote</h1>
            <p className="muted">
              Comece pelo pedido com saldo, selecione os produtos e reserve somente os lotes necessários.
            </p>
          </div>
          <div className="toolbar-actions" aria-label="Acoes de romaneio">
            <Link className={mode === "planejar" ? "secondary-button" : "primary-button"} href={mode === "planejar" ? "/romaneios?modo=consulta" : "/romaneios"}>
              {mode === "planejar" ? "Consultar Romaneios" : "Planejar carga"}
            </Link>
          </div>
        </div>

        <nav className="romaneio-workflow-tabs" aria-label="Etapas do Romaneio">
          <Link href="/romaneios" aria-current={mode === "planejar" ? "page" : undefined}>
            <span>Pedidos com saldo</span>
            <strong>{numberOrDash(dashboard.metrics.pedidosComPendencia)}</strong>
          </Link>
          <Link href="/romaneios?modo=consulta&status=romaneios-rascunho#romaneios" aria-current={statusView === "romaneios-rascunho" ? "page" : undefined}>
            <span>Rascunhos</span>
            <strong>{numberOrDash(dashboard.metrics.romaneiosRascunho)}</strong>
          </Link>
          <Link href="/romaneios?modo=consulta&status=romaneios-separacao#romaneios" aria-current={statusView === "romaneios-separacao" ? "page" : undefined}>
            <span>Em separação</span>
            <strong>{numberOrDash(dashboard.metrics.romaneiosSeparacao)}</strong>
          </Link>
          <Link href="/romaneios?modo=consulta&status=romaneios-finalizados#romaneios" aria-current={statusView === "romaneios-finalizados" ? "page" : undefined}>
            <span>Encerrados</span>
            <strong>{numberOrDash(dashboard.metrics.romaneiosEncerrados)}</strong>
          </Link>
        </nav>

        {dashboard.error ? (
          <section className="notice-panel warning" role="status">
            <strong>Conexao pendente</strong>
            <span>{dashboard.error}</span>
          </section>
        ) : null}

        {formMessage ? (
          <section className={`notice-panel ${formMessage.kind}`} role="status">
            <strong>{formMessage.title}</strong>
            <span>{formMessage.detail}</span>
          </section>
        ) : null}

        {mode === "planejar" ? (
          <RomaneioPreparation pendingItems={dashboard.pendingItems} romaneios={dashboard.romaneios} />
        ) : (
          <section className="panel" id="romaneios" aria-labelledby="romaneios-title">
            <div className="panel-header">
              <div>
                <h2 id="romaneios-title">Consultar Romaneios</h2>
                <p className="muted">Abra somente a situação e o Romaneio que deseja operar.</p>
              </div>
              <span className="pill">{dashboard.pagination.total} registro(s)</span>
            </div>
            <FilterToolbar action="/romaneios">
              <input type="hidden" name="modo" value="consulta" />
              <SearchField name="busca" label="Cliente, pedido ou Romaneio" defaultValue={query} placeholder="Nome, documento, pedido, destino ou código" wide />
              <label><span>Situação</span><select name="status" defaultValue={statusView ?? ""}><option value="">Todas</option><option value="romaneios-rascunho">Rascunhos</option><option value="romaneios-separacao">Em separação</option><option value="romaneios-finalizados">Encerrados</option></select></label>
              <AdvancedFilterPanel open={hasAdvancedFilters(filters)} activeCount={advancedFilterCount(filters)}>
                <EntityLookup entity="clientes" name="cliente" labelName="cliente_label" label="Cliente" placeholder="Abra a lista ou pesquise" defaultValue={filters.clientId} defaultLabel={filters.clientLabel} />
                <EntityLookup entity="pedidos-romaneio" name="pedido" labelName="pedido_label" label="Pedido" placeholder="Abra a lista ou pesquise" defaultValue={filters.orderId} defaultLabel={filters.orderLabel} />
                <EntityLookup entity="propriedades" name="propriedade" labelName="propriedade_label" label="Propriedade ou destino" placeholder="Abra a lista ou pesquise" defaultValue={filters.propertyId} defaultLabel={filters.propertyLabel} contextId={filters.clientId} />
                <EntityLookup entity="romaneios" name="romaneio" labelName="romaneio_label" label="Romaneio" placeholder="Abra a lista ou pesquise" defaultValue={filters.shipmentId} defaultLabel={filters.shipmentLabel} />
                <EntityLookup entity="pessoas" name="entregador" labelName="entregador_label" label="Entregador" placeholder="Abra a lista ou pesquise" defaultValue={filters.courierId} defaultLabel={filters.courierLabel} />
                <EntityLookup entity="veiculos" name="veiculo" labelName="veiculo_label" label="Veículo" placeholder="Abra a lista ou pesquise" defaultValue={filters.vehicleId} defaultLabel={filters.vehicleLabel} />
                <EntityLookup entity="produtos" name="produto" labelName="produto_label" label="Produto" placeholder="Abra a lista ou pesquise" defaultValue={filters.productId} defaultLabel={filters.productLabel} />
                <EntityLookup entity="lotes-pa" name="lote" labelName="lote_label" label="Lote PA" placeholder="Abra a lista ou pesquise" defaultValue={filters.finishedLotId} defaultLabel={filters.finishedLotLabel} />
                <label><span>NF de remessa</span><input name="referencia" defaultValue={filters.fiscalReference} placeholder="Número emitido externamente" /></label>
                <label><span>Data inicial</span><input type="date" name="inicio" defaultValue={filters.startDate} /></label>
                <label><span>Data final</span><input type="date" name="fim" defaultValue={filters.endDate} /></label>
              </AdvancedFilterPanel>
              <FilterActions clearHref="/romaneios?modo=consulta#romaneios" submitLabel="Pesquisar" />
            </FilterToolbar>
            <ActiveFilterChips filters={activeRomaneioFilters(filters)} clearHref="/romaneios?modo=consulta#romaneios" />
            {dashboard.romaneios.length ? (
              <RomaneioConsultationTable romaneios={dashboard.romaneios} filters={filters} page={dashboard.pagination.page} />
            ) : (
              <div className="empty-state compact-empty"><strong>Nenhum Romaneio encontrado</strong><span>Revise os filtros ou consulte outro período.</span></div>
            )}
            <PaginationBar page={dashboard.pagination.page} pageCount={dashboard.pagination.totalPages} total={dashboard.pagination.total} previousHref={dashboard.pagination.page > 1 ? consultationHref(filters, dashboard.pagination.page - 1) : null} nextHref={dashboard.pagination.page < dashboard.pagination.totalPages ? consultationHref(filters, dashboard.pagination.page + 1) : null} />
            {selectedRomaneio ? (
              <section className="romaneio-consultation-detail" id="romaneio-detalhe" aria-label={`Detalhes do Romaneio ${selectedRomaneio.codigoRomaneio}`}>
                <RomaneioCard romaneio={selectedRomaneio} lookups={dashboard.lookups} expanded />
              </section>
            ) : null}
          </section>
        )}
      </section>
    </main>
  );
}

function RomaneioConsultationTable({ romaneios, filters, page }: { romaneios: RomaneioRecord[]; filters: RomaneioConsultationFilters; page: number }) {
  const columns: Array<DataTableColumn<RomaneioRecord>> = [
    {
      key: "romaneio",
      label: "Romaneio",
      width: "17%",
      render: (romaneio) => <PrimarySecondaryCell primary={romaneio.codigoRomaneio} secondary={separationTypeLabel(romaneio.tipoSeparacao)} />
    },
    {
      key: "pedido",
      label: "Pedido e cliente",
      width: "25%",
      render: (romaneio) => <PrimarySecondaryCell primary={orderCode(romaneio.pedidoLabel)} secondary={romaneio.clienteNome} />
    },
    {
      key: "carga",
      label: "Carga",
      width: "15%",
      render: (romaneio) => <PrimarySecondaryCell primary={`${numberOrDash(romaneio.carga?.volumeLiquidoL ?? null)} L`} secondary={`${numberOrDash(romaneio.carga?.volumesLogisticos ?? null)} volume(s)`} />
    },
    {
      key: "situacao",
      label: "Situação",
      width: "13%",
      render: (romaneio) => <StatusBadge status={romaneio.status}>{romaneioStatusLabel(romaneio.status)}</StatusBadge>
    },
    {
      key: "data",
      label: "Data",
      width: "12%",
      render: (romaneio) => formatDate(romaneio.dataRomaneio)
    },
    {
      key: "entrega",
      label: "Entrega",
      width: "12%",
      render: (romaneio) => <PrimarySecondaryCell primary={romaneio.logistics?.entregadorNome ?? "A definir"} secondary={romaneio.logistics?.veiculoLabel ?? "Veículo não informado"} />
    },
    {
      key: "acao",
      label: "Ação",
      width: "6%",
      align: "end",
      render: (romaneio) => <Link className="secondary-button compact" href={romaneioDetailHref(filters, page, romaneio.id)}>Abrir</Link>
    }
  ];

  return <DataTable caption="Romaneios encontrados" columns={columns} rows={romaneios} rowKey={(romaneio) => romaneio.id} />;
}

function RomaneioCard({ romaneio, lookups, expanded = false }: { romaneio: RomaneioRecord; lookups: RomaneioLookups; expanded?: boolean }) {
  const statusAllowsConfirmation = romaneio.status === "draft" || romaneio.status === "separacao";
  const canCancel = romaneio.status === "draft" || romaneio.status === "separacao";
  const canReverse = romaneio.status === "confirmado";
  const canManageLogistics = ["draft", "separacao", "confirmado"].includes(romaneio.status);
  const reservationsComplete =
    romaneio.items.length > 0 &&
    romaneio.items.every((item) => item.quantidadeReservada >= item.quantidadeRomaneada);
  const logisticsComplete = Boolean(romaneio.logistics?.entregadorId && romaneio.logistics?.veiculoId);
  const shippingReferences = romaneio.fiscalDocuments.filter((document) => document.status === "emitida");
  const activeSimpleReference = romaneio.simpleBillingReferences.find((document) => document.status === "emitida") ?? null;
  const canConfirm = statusAllowsConfirmation && reservationsComplete && logisticsComplete && shippingReferences.length > 0;

  return (
    <details className={`romaneio-record romaneio-${romaneio.status}`} open={expanded}>
      <summary>
        <span>
          <strong>{romaneio.codigoRomaneio}</strong>
          <small>{romaneio.pedidoLabel} · {romaneio.clienteNome}</small>
        </span>
        <span className={`status-chip ${romaneio.status}`}>{romaneioStatusLabel(romaneio.status)}</span>
        <strong>{separationTypeLabel(romaneio.tipoSeparacao)}</strong>
      </summary>
      <article className="romaneio-card">
      <div className="tag-row">
        <span className="tag">Data: {romaneio.dataRomaneio}</span>
        <span className="tag">Itens: {romaneio.items.length}</span>
        <span className="tag">Litros: {numberOrDash(romaneio.carga?.volumeLiquidoL ?? null)}</span>
        <span className="tag">Volumes: {numberOrDash(romaneio.carga?.volumesLogisticos ?? null)}</span>
        <span className="tag">Peso líquido: {numberOrDash(romaneio.carga?.pesoLiquidoKg ?? null)} kg</span>
        <span className="tag">Peso bruto: {numberOrDash(romaneio.carga?.pesoBrutoKg ?? null)} kg</span>
      </div>
      {romaneio.carga?.pendencias.length ? <p className="muted">Cálculo pendente: {romaneio.carga.pendencias.join(", ")}.</p> : null}

      <section className="romaneio-subsection">
        <div className="romaneio-subsection-title">
          <strong>Itens</strong>
          <span>romaneado x reservado</span>
        </div>
        {romaneio.items.length > 0 ? (
          <div className="romaneio-item-list">
            {romaneio.items.map((item) => (
              <RomaneioItemRow key={item.id} item={item} />
            ))}
          </div>
        ) : (
          <div className="empty-state compact-empty">
            <strong>Sem item</strong>
            <span>Adicione itens pendentes ao romaneio.</span>
          </div>
        )}
      </section>

      <section className="romaneio-subsection">
        <div className="romaneio-subsection-title">
          <strong>Entrega e expedicao</strong>
          <span>{romaneio.logistics ? "atribuicao ativa" : "a definir"}</span>
        </div>
        {romaneio.logistics ? (
          <div className="tag-row">
            <span className="tag">entregador: {romaneio.logistics.entregadorNome ?? "nao atribuido"}</span>
            <span className="tag">veiculo: {romaneio.logistics.veiculoLabel ?? "nao atribuido"}</span>
          </div>
        ) : (
          <p className="muted">Nenhum entregador ou veiculo foi atribuido a este romaneio.</p>
        )}
        {canManageLogistics ? (
          <div className="romaneio-actions">
            <form className="compact-action-form logistics-assignment-form" action={assignRomaneioLogisticsAction}>
              <input type="hidden" name="romaneio_id" value={romaneio.id} />
              <label>
                Entregador
                <select name="entregador_id" defaultValue={romaneio.logistics?.entregadorId ?? ""}>
                  <option value="">Sem entregador</option>
                  <LookupSelectOptions options={lookups.entregadores} />
                </select>
              </label>
              <label>
                Veiculo
                <select name="veiculo_id" defaultValue={romaneio.logistics?.veiculoId ?? ""}>
                  <option value="">Sem veiculo</option>
                  <LookupSelectOptions options={lookups.veiculos} />
                </select>
              </label>
              <button className="secondary-button" type="submit">
                {romaneio.logistics ? "Atualizar entrega" : "Atribuir entrega"}
              </button>
            </form>
            {romaneio.logistics ? (
              <form className="compact-action-form" action={removeRomaneioLogisticsAction}>
                <input type="hidden" name="romaneio_id" value={romaneio.id} />
                <input name="motivo" placeholder="Motivo da remocao" required />
                <button className="secondary-button" type="submit">
                  Remover atribuicao
                </button>
              </form>
            ) : null}
          </div>
        ) : null}
      </section>

      <section className="romaneio-subsection">
        <div className="romaneio-subsection-title">
          <strong>Referências fiscais externas</strong>
          <span>
            {romaneio.fiscalDocuments.length > 0
              ? `${romaneio.fiscalDocuments.length} referência(s) de remessa`
              : romaneio.status === "confirmado"
                ? "baixa confirmada"
                : "referência de remessa pendente"}
          </span>
        </div>
        {romaneio.fiscalDocuments.length > 0 ? (
          <div className="tag-row">
            {romaneio.fiscalDocuments.map((document) => (
              <span className="tag" key={document.id}>
                {fiscalDocumentTypeLabel(document.type)}: {document.numberLabel} / {fiscalStatusLabel(document.status)}
              </span>
            ))}
          </div>
        ) : (
          <p className="muted">
            {romaneio.status === "confirmado"
              ? "A confirmação do Romaneio consolidou a baixa física. A referência apenas identifica o documento externo."
              : "Registre o número da NF de remessa emitida fora do Elite. Registrar o número não baixa estoque nem libera comissão."}
          </p>
        )}
        {activeSimpleReference ? <p className="field-note"><strong>NF de simples faturamento do pedido-mãe:</strong> {activeSimpleReference.numberLabel}</p> : null}
        {statusAllowsConfirmation ? <div className="romaneio-actions">
          {!activeSimpleReference ? <form className="compact-action-form" action={registerExternalFiscalReferenceAction}>
            <input type="hidden" name="idempotency_key" value={randomUUID()} />
            <input type="hidden" name="pedido_id" value={romaneio.pedidoId} />
            <input type="hidden" name="tipo" value="simples_faturamento" />
            <strong>NF de simples faturamento do pedido</strong>
            <input name="numero" placeholder="Número da nota fiscal" required />
            <input name="serie" placeholder="Série (opcional)" />
            <input name="data_documento" type="date" required />
            <input name="motivo" placeholder="Motivo do registro" minLength={5} required />
            <button className="secondary-button" type="submit">Registrar número da nota fiscal</button>
          </form> : null}
          <form className="compact-action-form" action={registerExternalFiscalReferenceAction}>
            <input type="hidden" name="idempotency_key" value={randomUUID()} />
            <input type="hidden" name="pedido_id" value={romaneio.pedidoId} />
            <input type="hidden" name="romaneio_id" value={romaneio.id} />
            <strong>NF de remessa deste Romaneio</strong>
            <select name="tipo" defaultValue={activeSimpleReference ? "remessa_vinculada" : "remessa_total"}>
              <option value="remessa_total">Nota única de remessa</option>
              {activeSimpleReference ? <option value="remessa_vinculada">Remessa vinculada ao simples faturamento</option> : null}
            </select>
            {activeSimpleReference ? <input type="hidden" name="referencia_pai_id" value={activeSimpleReference.id} /> : null}
            <input name="numero" placeholder="Número da nota fiscal" required />
            <input name="serie" placeholder="Série (opcional)" />
            <input name="data_documento" type="date" required />
            <input name="motivo" placeholder="Motivo do registro" minLength={5} required />
            <button className="secondary-button" type="submit">Registrar referência de remessa</button>
          </form>
        </div> : null}
        {romaneio.fiscalDocuments.map((document) => <details key={`correction-${document.id}`} className="compact-disclosure">
          <summary>Corrigir número {document.numberLabel}</summary>
          <form className="compact-action-form" action={correctExternalFiscalReferenceAction}>
            <input type="hidden" name="idempotency_key" value={randomUUID()} />
            <input type="hidden" name="nota_fiscal_id" value={document.id} />
            <input name="numero_novo" placeholder="Novo número" required />
            <input name="serie_nova" placeholder="Nova série" />
            <input name="motivo" placeholder="Motivo detalhado da correção" minLength={10} required />
            <button className="secondary-button" type="submit">Corrigir referência</button>
          </form>
        </details>)}
      </section>

      {romaneio.movements.length > 0 ? (
        <section className="romaneio-subsection">
          <div className="romaneio-subsection-title">
            <strong>Movimentos PA</strong>
            <span>{romaneio.movements.length} movimento(s)</span>
          </div>
          <div className="tag-row">
            {romaneio.movements.slice(0, 8).map((movement) => (
              <span className="tag" key={movement.id}>
                {movementTypeLabel(movement.tipoMovimento)}: {numberOrDash(movement.quantidade)} / {movement.loteLabel}
              </span>
            ))}
          </div>
        </section>
      ) : null}

      <div className="romaneio-actions">
        {statusAllowsConfirmation && !canConfirm ? (
          <div className="notice-panel warning romaneio-confirmation-checklist" role="status">
            <strong>Antes da baixa de estoque</strong>
            <span>{reservationsComplete ? "Reserva completa" : "1. Reserve todos os produtos por lote"}</span>
            <span>{logisticsComplete ? "Entregador e veiculo informados" : "2. Informe entregador e veiculo"}</span>
            <span>{shippingReferences.length > 0 ? "Referência de remessa registrada" : "3. Registre a referência fiscal externa"}</span>
          </div>
        ) : null}
        {canConfirm ? (
          <form className="compact-action-form" action={confirmRomaneioAction}>
            <input type="hidden" name="romaneio_id" value={romaneio.id} />
            <select name="nota_fiscal_id" defaultValue="" required>
              <option value="" disabled>Selecione a referência de remessa</option>
              {shippingReferences.map((document) => (
                <option key={document.id} value={document.id}>{document.numberLabel}</option>
              ))}
            </select>
            <button className="primary-button" type="submit">
              Confirmar Romaneio e baixar estoque
            </button>
          </form>
        ) : null}
        {statusAllowsConfirmation ? <Link className="secondary-button" href={`/romaneios/${romaneio.id}/imprimir`}>Imprimir romaneio</Link> : null}
        {canCancel ? (
          <form className="compact-action-form" action={cancelRomaneioAction}>
            <input type="hidden" name="romaneio_id" value={romaneio.id} />
            <input name="motivo" placeholder="Motivo do cancelamento" required />
            <button className="secondary-button" type="submit">
              Cancelar
            </button>
          </form>
        ) : null}
        {canReverse ? (
          <form className="compact-action-form" action={reverseRomaneioAction}>
            <input type="hidden" name="romaneio_id" value={romaneio.id} />
            <input name="motivo" placeholder="Motivo do estorno" required />
            <button className="secondary-button" type="submit">
              Estornar
            </button>
          </form>
        ) : null}
      </div>
      </article>
    </details>
  );
}

function RomaneioItemRow({ item }: { item: RomaneioItem }) {
  return (
    <div className="romaneio-item-row">
      <div>
        <strong>{item.itemLabel}</strong>
        <span>{item.lotePaRef ? `Lote: ${item.lotePaRef}` : "Lote ainda não reservado"}</span>
      </div>
      <span className={`status-chip ${item.status}`}>{romaneioItemStatusLabel(item.status)}</span>
      <div className="tag-row">
        <span className="tag">romaneado: {numberOrDash(item.quantidadeRomaneada)}</span>
        <span className="tag">reservado: {numberOrDash(item.quantidadeReservada)}</span>
        {item.reservations.map((reservation) => (
          <span className="tag" key={reservation.id}>
            {reservation.loteLabel}: {numberOrDash(reservation.quantidadeReservada)} / {reservationStatusLabel(reservation.status)}
          </span>
        ))}
      </div>
    </div>
  );
}

function LookupSelectOptions({ options }: { options: RomaneioLookupOption[] }) {
  return (
    <>
      {options.map((option) => (
        <option key={`${option.id}-${option.label}`} value={option.id}>
          {option.detail ? `${option.label} - ${option.detail}` : option.label}
        </option>
      ))}
    </>
  );
}

function singleValue(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

function numberOrDash(value: number | null): string {
  if (value === null) {
    return "-";
  }
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 4 }).format(value);
}

function labelFromMap(value: string, labels: Record<string, string>): string {
  return labels[value] ?? "Estado não reconhecido";
}

function romaneioStatusLabel(value: string): string {
  return labelFromMap(value, {
    draft: "Rascunho",
    separacao: "Em separacao",
    confirmado: "Confirmado",
    cancelado: "Cancelado",
    estornado: "Estornado"
  });
}

function separationTypeLabel(value: string): string {
  return labelFromMap(value, { parcial: "Parcial", total: "Total" });
}

function romaneioItemStatusLabel(value: string): string {
  return labelFromMap(value, {
    draft: "Rascunho",
    reservado: "Reservado",
    confirmado: "Confirmado",
    cancelado: "Cancelado",
    estornado: "Estornado"
  });
}

function reservationStatusLabel(value: string): string {
  return labelFromMap(value, {
    ativa: "Ativa",
    baixada: "Baixada",
    liberada: "Liberada",
    estornada: "Estornada"
  });
}

function fiscalStatusLabel(value: string): string {
  return labelFromMap(value, { emitida: "Ativa", cancelada: "Cancelada", substituida: "Substituída" });
}

function fiscalDocumentTypeLabel(value: string): string {
  return labelFromMap(value, {
    remessa_total: "Remessa total",
    simples_faturamento: "Simples faturamento",
    remessa_vinculada: "Remessa vinculada",
    complementar: "Complementar",
    devolucao: "Devolucao"
  });
}

function movementTypeLabel(value: string): string {
  return labelFromMap(value, {
    baixa: "Baixa física",
    estorno: "Estorno da baixa",
    saida_romaneio: "Saída por Romaneio",
    estorno_saida: "Estorno da saída"
  });
}

function positiveInteger(value: string | undefined): number | null {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
}

type RomaneioConsultationFilters = {
  query: string; status: string | null;
  clientId: number | null; clientLabel: string;
  orderId: number | null; orderLabel: string;
  propertyId: number | null; propertyLabel: string;
  shipmentId: number | null; shipmentLabel: string;
  courierId: number | null; courierLabel: string;
  vehicleId: number | null; vehicleLabel: string;
  productId: number | null; productLabel: string;
  finishedLotId: number | null; finishedLotLabel: string;
  fiscalReference: string; startDate: string; endDate: string;
};

function parseConsultationFilters(params: SearchParams, status: string | null, query: string): RomaneioConsultationFilters {
  return {
    query, status,
    clientId: positiveInteger(singleValue(params.cliente)), clientLabel: singleValue(params.cliente_label) ?? "",
    orderId: positiveInteger(singleValue(params.pedido)), orderLabel: singleValue(params.pedido_label) ?? "",
    propertyId: positiveInteger(singleValue(params.propriedade)), propertyLabel: singleValue(params.propriedade_label) ?? "",
    shipmentId: positiveInteger(singleValue(params.romaneio)), shipmentLabel: singleValue(params.romaneio_label) ?? "",
    courierId: positiveInteger(singleValue(params.entregador)), courierLabel: singleValue(params.entregador_label) ?? "",
    vehicleId: positiveInteger(singleValue(params.veiculo)), vehicleLabel: singleValue(params.veiculo_label) ?? "",
    productId: positiveInteger(singleValue(params.produto)), productLabel: singleValue(params.produto_label) ?? "",
    finishedLotId: positiveInteger(singleValue(params.lote)), finishedLotLabel: singleValue(params.lote_label) ?? "",
    fiscalReference: singleValue(params.referencia)?.trim() ?? "",
    startDate: singleValue(params.inicio) ?? "",
    endDate: singleValue(params.fim) ?? ""
  };
}

function consultationHref(filters: RomaneioConsultationFilters, page = 1, omit?: keyof RomaneioConsultationFilters): string {
  const params = new URLSearchParams({ modo: "consulta" });
  const pairedKeys: Partial<Record<keyof RomaneioConsultationFilters, keyof RomaneioConsultationFilters>> = {
    clientId: "clientLabel", orderId: "orderLabel", propertyId: "propertyLabel",
    shipmentId: "shipmentLabel", courierId: "courierLabel", vehicleId: "vehicleLabel",
    productId: "productLabel", finishedLotId: "finishedLotLabel"
  };
  const entries: Array<[keyof RomaneioConsultationFilters, string, string | number | null]> = [
    ["query", "busca", filters.query], ["status", "status", filters.status],
    ["clientId", "cliente", filters.clientId], ["clientLabel", "cliente_label", filters.clientLabel],
    ["orderId", "pedido", filters.orderId], ["orderLabel", "pedido_label", filters.orderLabel],
    ["propertyId", "propriedade", filters.propertyId], ["propertyLabel", "propriedade_label", filters.propertyLabel],
    ["shipmentId", "romaneio", filters.shipmentId], ["shipmentLabel", "romaneio_label", filters.shipmentLabel],
    ["courierId", "entregador", filters.courierId], ["courierLabel", "entregador_label", filters.courierLabel],
    ["vehicleId", "veiculo", filters.vehicleId], ["vehicleLabel", "veiculo_label", filters.vehicleLabel],
    ["productId", "produto", filters.productId], ["productLabel", "produto_label", filters.productLabel],
    ["finishedLotId", "lote", filters.finishedLotId], ["finishedLotLabel", "lote_label", filters.finishedLotLabel],
    ["fiscalReference", "referencia", filters.fiscalReference], ["startDate", "inicio", filters.startDate], ["endDate", "fim", filters.endDate]
  ];
  for (const [key, name, value] of entries) {
    if (key !== omit && key !== (omit ? pairedKeys[omit] : undefined) && value !== null && value !== "") params.set(name, String(value));
  }
  if (page > 1) params.set("pagina", String(page));
  return `/romaneios?${params.toString()}#romaneios`;
}

function hasAdvancedFilters(filters: RomaneioConsultationFilters): boolean {
  return Boolean(filters.clientId || filters.orderId || filters.propertyId || filters.shipmentId || filters.courierId || filters.vehicleId || filters.productId || filters.finishedLotId || filters.fiscalReference || filters.startDate || filters.endDate);
}

function advancedFilterCount(filters: RomaneioConsultationFilters): number {
  return [
    filters.clientId,
    filters.orderId,
    filters.propertyId,
    filters.shipmentId,
    filters.courierId,
    filters.vehicleId,
    filters.productId,
    filters.finishedLotId,
    filters.fiscalReference,
    filters.startDate,
    filters.endDate
  ].filter(Boolean).length;
}

function romaneioDetailHref(filters: RomaneioConsultationFilters, page: number, romaneioId: number): string {
  const base = consultationHref(filters, page).split("#")[0];
  return `${base}&selecionado=${romaneioId}#romaneio-detalhe`;
}

function orderCode(label: string): string {
  return label.split(" - ")[0] || label;
}

function formatDate(value: string): string {
  const date = new Date(`${value}T12:00:00`);
  return Number.isNaN(date.valueOf()) ? value : new Intl.DateTimeFormat("pt-BR").format(date);
}

function activeRomaneioFilters(filters: RomaneioConsultationFilters) {
  const pairs: Array<{ key: keyof RomaneioConsultationFilters; label: string; value: string }> = [
    { key: "query", label: "Pesquisa", value: filters.query },
    { key: "status", label: "Situação", value: filters.status ? ({ "romaneios-rascunho": "Rascunhos", "romaneios-separacao": "Em separação", "romaneios-finalizados": "Encerrados" } as Record<string, string>)[filters.status] ?? filters.status : "" },
    { key: "clientId", label: "Cliente", value: filters.clientLabel },
    { key: "orderId", label: "Pedido", value: filters.orderLabel },
    { key: "propertyId", label: "Destino", value: filters.propertyLabel },
    { key: "shipmentId", label: "Romaneio", value: filters.shipmentLabel },
    { key: "courierId", label: "Entregador", value: filters.courierLabel },
    { key: "vehicleId", label: "Veículo", value: filters.vehicleLabel },
    { key: "productId", label: "Produto", value: filters.productLabel },
    { key: "finishedLotId", label: "Lote PA", value: filters.finishedLotLabel },
    { key: "fiscalReference", label: "NF de remessa", value: filters.fiscalReference },
    { key: "startDate", label: "Desde", value: filters.startDate },
    { key: "endDate", label: "Até", value: filters.endDate }
  ];
  return pairs.filter((item) => item.value).map((item) => ({ label: item.label, value: item.value, href: consultationHref(filters, 1, item.key) }));
}

function messageForResult(result: string | undefined): { kind: "ok" | "warning"; title: string; detail: string } | null {
  if (!result) {
    return null;
  }
  const messages: Record<string, { kind: "ok" | "warning"; title: string; detail: string }> = {
    external_reference_registered: {
      kind: "ok",
      title: "Referência fiscal registrada",
      detail: "O número externo foi vinculado sem movimentar estoque ou liberar comissão."
    },
    external_reference_corrected: {
      kind: "ok",
      title: "Referência fiscal corrigida",
      detail: "O valor anterior e o novo foram preservados na auditoria."
    },
    missing_external_reference: {
      kind: "warning",
      title: "Referência incompleta",
      detail: "Informe tipo, número, data e motivo do registro."
    },
    missing_external_reference_parent: {
      kind: "warning",
      title: "Vínculo do documento pendente",
      detail: "Selecione a referência de simples faturamento do mesmo pedido."
    },
    missing_external_reference_correction: {
      kind: "warning",
      title: "Correção incompleta",
      detail: "Informe novo número e motivo detalhado."
    },
    external_reference_invalid: {
      kind: "warning",
      title: "Referência fiscal incompatível",
      detail: "O documento precisa pertencer ao mesmo pedido e Romaneio."
    },
    external_reference_repeated_payload: {
      kind: "warning",
      title: "Solicitação já utilizada",
      detail: "Atualize a página antes de registrar dados diferentes."
    },
    romaneio_created: {
      kind: "ok",
      title: "Romaneio criado",
      detail: "O romaneio foi criado em rascunho, sem baixa de estoque."
    },
    romaneio_item_added: {
      kind: "ok",
      title: "Item adicionado",
      detail: "O item foi incluido no romaneio sem movimentar PA."
    },
    lot_reserved: {
      kind: "ok",
      title: "Lote reservado",
      detail: "A reserva foi registrada. A baixa fisica ainda depende da confirmacao."
    },
    logistics_assigned: {
      kind: "ok",
      title: "Dados de entrega atualizados",
      detail: "As informações selecionadas foram vinculadas ao romaneio com histórico auditável."
    },
    logistics_removed: {
      kind: "ok",
      title: "Atribuicao removida",
      detail: "A remocao foi registrada sem apagar o historico anterior."
    },
    romaneio_confirmed: {
      kind: "ok",
      title: "Romaneio confirmado",
      detail: "A baixa de PA foi registrada por lote reservado."
    },
    romaneio_cancelled: {
      kind: "ok",
      title: "Romaneio cancelado",
      detail: "Reservas ativas foram liberadas antes da confirmacao."
    },
    romaneio_reversed: {
      kind: "ok",
      title: "Romaneio estornado",
      detail: "A reversao auditada devolveu o saldo ao lote PA."
    },
    not_configured: {
      kind: "warning",
      title: "Supabase nao configurado",
      detail: "Configure o banco antes de operar romaneios."
    },
    missing_romaneio_required: {
      kind: "warning",
      title: "Romaneio incompleto",
      detail: "Informe item pendente, separacao e quantidade."
    },
    missing_add_item_required: {
      kind: "warning",
      title: "Item incompleto",
      detail: "Informe romaneio, item do pedido e quantidade."
    },
    missing_reservation_required: {
      kind: "warning",
      title: "Reserva incompleta",
      detail: "Informe item do romaneio e lote PA."
    },
    missing_logistics_required: {
      kind: "warning",
      title: "Entrega incompleta",
      detail: "Selecione ao menos um entregador ou um veiculo."
    },
    missing_logistics_removal_required: {
      kind: "warning",
      title: "Remocao incompleta",
      detail: "Informe o motivo para remover a atribuicao atual."
    },
    logistics_already_active: {
      kind: "warning",
      title: "Atribuicao sem alteracao",
      detail: "O entregador e o veiculo selecionados ja estao ativos neste romaneio."
    },
    invalid_logistics_actor: {
      kind: "warning",
      title: "Entrega indisponivel",
      detail: "O entregador precisa estar ativo nessa funcao e o veiculo precisa estar ativo."
    },
    missing_logistics_assignment: {
      kind: "warning",
      title: "Sem atribuicao ativa",
      detail: "Este romaneio nao possui entregador ou veiculo para remover."
    },
    logistics_incomplete_for_issue: {
      kind: "warning",
      title: "Entrega incompleta",
      detail: "Informe entregador e veículo antes de confirmar a expedição e baixar o estoque."
    },
    invoice_link_mismatch: {
      kind: "warning",
      title: "Referência fiscal não pertence ao romaneio",
      detail: "Selecione uma referência fiscal externa registrada para este mesmo pedido e romaneio."
    },
    invoice_not_ready: {
      kind: "warning",
      title: "Referência fiscal pendente",
      detail: "A baixa exige o número da NF de remessa emitida externamente e vinculada ao romaneio."
    },
    invoice_items_mismatch: {
      kind: "warning",
      title: "Itens da referência fiscal divergentes",
      detail: "Produtos e quantidades associados à referência fiscal precisam coincidir com o romaneio."
    },
    load_measurements_pending: {
      kind: "warning",
      title: "Medidas da carga pendentes",
      detail: "Complete volumes logísticos, densidades e taras antes da baixa do estoque."
    },
    duplicated_item: {
      kind: "warning",
      title: "Item duplicado",
      detail: "Este item ja existe neste romaneio."
    },
    exceeds_pending: {
      kind: "warning",
      title: "Quantidade excede saldo livre",
      detail: "A quantidade romaneada nao pode ultrapassar o pedido menos os demais romaneios ativos."
    },
    reservation_mismatch: {
      kind: "warning",
      title: "Reserva nao fecha",
      detail: "A soma das reservas precisa fechar a quantidade romaneada antes de confirmar."
    },
    insufficient_stock: {
      kind: "warning",
      title: "Saldo PA insuficiente",
      detail: "O lote escolhido nao tem disponibilidade suficiente."
    },
    lot_product_mismatch: {
      kind: "warning",
      title: "Lote incompativel",
      detail: "O lote PA precisa ser do mesmo produto/embalagem do item."
    },
    invalid_status: {
      kind: "warning",
      title: "Status nao permite",
      detail: "O status atual do pedido, romaneio ou lote nao permite esta acao."
    },
    permission_denied: {
      kind: "warning",
      title: "Alcada bloqueada",
      detail: "O usuario atual nao tem permissao para esta acao."
    },
    module_unavailable: {
      kind: "warning",
      title: "Módulo responsável indisponível",
      detail: "Esta ação depende de um módulo que ainda não foi liberado no ambiente de homologação."
    },
    save_failed: {
      kind: "warning",
      title: "Falha ao salvar",
      detail: "A acao nao foi concluida. Verifique banco, permissao e logs."
    }
  };
  return messages[result] ?? messages.save_failed;
}
