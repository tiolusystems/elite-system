import { randomUUID } from "node:crypto";
import Link from "next/link";

import {
  assignRomaneioLogisticsAction,
  cancelRomaneioAction,
  confirmRomaneioAction,
  correctExternalFiscalReferenceAction,
  createRomaneioAction,
  removeRomaneioLogisticsAction,
  registerExternalFiscalReferenceAction,
  reserveRomaneioPaLotAction,
  reverseRomaneioAction
} from "@/app/romaneios/actions";
import { RomaneioPreparation } from "@/app/romaneios/romaneio-preparation";
import {
  getRomaneioDashboard,
  type RomaneioItem,
  type RomaneioLookupOption,
  type RomaneioLookups,
  type RomaneioPendingItem,
  type RomaneioRecord
} from "@/lib/romaneios";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function RomaneiosPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const dashboard = await getRomaneioDashboard();
  const result = singleValue(params.result);
  const statusView = singleValue(params.status) ?? null;
  const formMessage = messageForResult(result);

  return (
    <main className="app-shell">
      <section className="workspace dashboard-workspace">
        <div className="dashboard-header">
          <div>
            <span className="eyebrow">baixa PA controlada</span>
            <h1>Romaneio e separacao por lote</h1>
            <p className="muted">
              Pedido aberto nao baixa estoque. Romaneio reserva lote PA em separacao e confirma a baixa apenas no
              fechamento.
            </p>
          </div>
          <div className="toolbar-actions" aria-label="Acoes de romaneio">
            <Link className="secondary-button contextual-help-link" href="/romaneios/manual" aria-label="Abrir ajuda do Romaneio">
              <span aria-hidden="true">?</span> Ajuda
            </Link>
            <a className="secondary-button" href="#novo-romaneio">
              Iniciar separação
            </a>
          </div>
        </div>

        <section className="kpi-grid" aria-label="Resumo romaneio">
          <a className="kpi-card romaneio-kpi accent-blue" href="#novo-romaneio">
            <span>Pedidos com pendencia</span>
            <strong>{valueOrDash(dashboard.metrics.pedidosComPendencia)}</strong>
            <p>{valueOrDash(dashboard.metrics.itensPendentes)} item(ns) com saldo a separar.</p>
          </a>
          <Link className="kpi-card romaneio-kpi accent-amber" href="/romaneios?status=romaneios-rascunho#romaneios-rascunho">
            <span>Em rascunho</span>
            <strong>{valueOrDash(dashboard.metrics.romaneiosRascunho)}</strong>
            <p>Ainda sem baixa de estoque.</p>
          </Link>
          <Link className="kpi-card romaneio-kpi accent-green" href="/romaneios?status=romaneios-separacao#romaneios-separacao">
            <span>Em separacao</span>
            <strong>{valueOrDash(dashboard.metrics.romaneiosSeparacao)}</strong>
            <p>Com lote reservado ou aguardando completar reserva.</p>
          </Link>
          <a className="kpi-card romaneio-kpi accent-red" href="#novo-romaneio">
            <span>Livre para novo romaneio</span>
            <strong>{valueOrDash(dashboard.metrics.quantidadeDisponivelRomaneio)}</strong>
            <p>Ja desconta rascunhos, separacoes e confirmacoes ativas.</p>
          </a>
        </section>

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

        <nav className="romaneio-mode-navigation" aria-label="Modos do Romaneio">
          <a className="primary-button" href="#novo-romaneio">Planejar carga</a>
          <a className="secondary-button" href="#romaneios">Consultar romaneios</a>
        </nav>

        <RomaneioPreparation pendingItems={dashboard.pendingItems} romaneios={dashboard.romaneios} />

        <section className="panel form-panel legacy-romaneio-ui" aria-hidden="true" aria-labelledby="novo-romaneio-title">
          <div className="panel-header">
            <div>
              <h2 id="novo-romaneio-title">Pedidos com saldo a entregar</h2>
              <p className="muted">Abra um pedido, marque os produtos e informe a quantidade de cada item. Consultar não grava.</p>
            </div>
            <span className="pill">gravação explícita</span>
          </div>
          {groupPendingByOrder(dashboard.pendingItems).map(([pedidoId, items]) => (
            <details className="romaneio-order" key={pedidoId}>
              <summary>
                <strong>{items[0].codigoPedido}</strong>
                <span>{items[0].clienteNome}</span>
                <span>{items.length} produto(s) com saldo</span>
              </summary>
              <form action={createRomaneioAction}>
                <input type="hidden" name="pedido_id" value={pedidoId} />
                <div className="romaneio-order-items">
                  {items.map((item) => (
                    <label className="romaneio-order-item" key={item.pedidoItemId}>
                      <input type="checkbox" name="pedido_item_id" value={item.pedidoItemId} />
                      <span>
                        <strong>{item.itemLabel}</strong>
                        <small>Saldo livre: {numberOrDash(item.quantidadeDisponivelRomaneio)}</small>
                      </span>
                      <input name={`quantidade_${item.pedidoItemId}`} inputMode="decimal" min="0" max={item.quantidadeDisponivelRomaneio} step="any" placeholder="Quantidade" />
                    </label>
                  ))}
                </div>
                <div className="form-footer">
                  <span>Nenhum estoque é alterado antes da reserva por lote.</span>
                  <button className="primary-button" type="submit" disabled={dashboard.lookups.pendingItems.length === 0}>Gravar romaneio</button>
                </div>
              </form>
            </details>
          ))}
          {dashboard.pendingItems.length === 0 ? <p className="muted">Nenhum item com saldo livre para novo romaneio.</p> : null}
        </section>

        <section className="two-column legacy-romaneio-ui" aria-hidden="true">
          <section className="panel form-panel" id="reservar-lote" aria-labelledby="reservar-lote-title">
            <div className="panel-header">
              <h2 id="reservar-lote-title">Reservar lote PA</h2>
              <span className="pill">multilote</span>
            </div>
            <form action={reserveRomaneioPaLotAction}>
              <div className="form-grid romaneio-form-grid">
                <label className="wide-field">
                  Item do romaneio
                  <select name="romaneio_item_id" defaultValue="" required>
                    <option value="" disabled>
                      Selecione o item a reservar
                    </option>
                    <LookupSelectOptions options={dashboard.lookups.romaneioItemsAbertos} />
                  </select>
                </label>
                <label className="wide-field">
                  Lote PA
                  <select name="lote_pa_id" defaultValue="" required>
                    <option value="" disabled>
                      Selecione um lote disponivel
                    </option>
                    <LookupSelectOptions options={dashboard.lookups.lotesPa} />
                  </select>
                </label>
                <label>
                  Quantidade
                  <input name="quantidade_reservada" inputMode="decimal" placeholder="opcional" />
                </label>
              </div>
              <div className="form-footer">
                <span>A reserva reduz disponibilidade, mas a baixa fisica so ocorre ao confirmar o romaneio.</span>
                <button className="primary-button" type="submit">
                  Reservar
                </button>
              </div>
            </form>
          </section>

          <section className="panel" aria-labelledby="pendencias-title">
            <div className="panel-header">
              <h2 id="pendencias-title">Itens pendentes</h2>
              <span className="pill">{dashboard.pendingItems.length} item(ns)</span>
            </div>
            {dashboard.pendingItems.length > 0 ? (
              <div className="module-list">
                {dashboard.pendingItems.slice(0, 10).map((item) => (
                  <PendingItemCard key={item.pedidoItemId} item={item} />
                ))}
              </div>
            ) : (
              <div className="empty-state">
                <strong>Sem pendencias carregadas</strong>
                <span>Pedidos abertos com saldo a separar aparecerao aqui.</span>
              </div>
            )}
          </section>
        </section>

        <section className="panel" id="romaneios" aria-labelledby="romaneios-title">
          <div className="panel-header">
            <h2 id="romaneios-title">Consultar romaneios</h2>
            <span className="pill">{dashboard.romaneios.length} registro(s)</span>
          </div>
          <RomaneioStatusGroups romaneios={dashboard.romaneios} lookups={dashboard.lookups} activeGroup={statusView} />
        </section>

        <section className="panel legacy-romaneio-ui" aria-hidden="true" aria-labelledby="lotes-pa-title">
          <div className="panel-header">
            <h2 id="lotes-pa-title">Lotes PA disponiveis</h2>
            <span className="pill">{dashboard.availableLots.length} lote(s)</span>
          </div>
          {dashboard.availableLots.length > 0 ? (
            <div className="table-scroll">
              <table className="data-table">
                <thead>
                  <tr>
                    <th>Lote</th>
                    <th>Produto</th>
                    <th>Status</th>
                    <th>Saldo</th>
                    <th>Reservado</th>
                    <th>Disponivel</th>
                    <th>Validade</th>
                  </tr>
                </thead>
                <tbody>
                  {dashboard.availableLots.slice(0, 80).map((lot) => (
                    <tr key={lot.id}>
                      <td>
                        <strong>{lot.codigoLote}</strong>
                        <span className="table-subtext">id {lot.id}</span>
                      </td>
                      <td>{lot.itemLabel}</td>
                      <td>
                        <span className={`status-chip ${lot.status}`}>{lotStatusLabel(lot.status)}</span>
                      </td>
                      <td>{numberOrDash(lot.saldoFisico)}</td>
                      <td>{numberOrDash(lot.quantidadeReservada)}</td>
                      <td>{numberOrDash(lot.saldoDisponivel)}</td>
                      <td>{lot.dataValidade ?? "-"}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : (
            <div className="empty-state">
              <strong>Sem lote PA carregado</strong>
              <span>Lotes disponiveis aparecem apos producao ou entrada PA.</span>
            </div>
          )}
        </section>
      </section>
    </main>
  );
}

function RomaneioStatusGroups({ romaneios, lookups, activeGroup }: { romaneios: RomaneioRecord[]; lookups: RomaneioLookups; activeGroup: string | null }) {
  const groups = [
    { id: "romaneios-rascunho", label: "Rascunhos", statuses: ["draft"] },
    { id: "romaneios-separacao", label: "Em separação", statuses: ["separacao"] },
    { id: "romaneios-finalizados", label: "Finalizados, cancelados e estornados", statuses: ["confirmado", "cancelado", "estornado"] }
  ];
  return (
    <div className="romaneio-status-groups">
      {groups.map((group) => {
        const records = romaneios.filter((romaneio) => group.statuses.includes(romaneio.status));
        return (
          <details className="romaneio-status-group" id={group.id} key={group.id} open={activeGroup === group.id}>
            <summary><strong>{group.label}</strong><span>{records.length} registro(s)</span></summary>
            {records.length ? <div className="romaneio-list">{records.map((romaneio) => <RomaneioCard key={romaneio.id} romaneio={romaneio} lookups={lookups} />)}</div> : <div className="empty-state compact-empty"><strong>Nenhum registro</strong><span>Não há romaneios nesta situação.</span></div>}
          </details>
        );
      })}
    </div>
  );
}

function PendingItemCard({ item }: { item: RomaneioPendingItem }) {
  return (
    <article className="module-card">
      <div className="module-card-main">
        <h3>{item.codigoPedido}</h3>
        <span>{item.clienteNome}</span>
      </div>
      <div className="module-card-meta">
        <span>livre</span>
        <strong>{numberOrDash(item.quantidadeDisponivelRomaneio)}</strong>
      </div>
      <p>{item.itemLabel}</p>
      <div className="tag-row">
        <span className="tag">pedido: {numberOrDash(item.quantidadePedido)}</span>
        <span className="tag">confirmado: {numberOrDash(item.quantidadeConfirmada)}</span>
        <span className="tag">comprometido: {numberOrDash(item.quantidadeComprometida)}</span>
        <span className="tag">pendente de atendimento: {numberOrDash(item.quantidadePendente)}</span>
      </div>
    </article>
  );
}

function RomaneioCard({ romaneio, lookups }: { romaneio: RomaneioRecord; lookups: RomaneioLookups }) {
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
    <article className={`romaneio-card romaneio-${romaneio.status}`}>
      <div className="romaneio-header">
        <div>
          <h3>{romaneio.codigoRomaneio}</h3>
          <p>{romaneio.pedidoLabel}</p>
        </div>
        <div className="romaneio-meta">
          <span className={`status-chip ${romaneio.status}`}>{romaneioStatusLabel(romaneio.status)}</span>
          <strong>{separationTypeLabel(romaneio.tipoSeparacao)}</strong>
        </div>
      </div>
      <div className="tag-row">
        <span className="tag">cliente: {romaneio.clienteNome}</span>
        <span className="tag">data: {romaneio.dataRomaneio}</span>
        <span className="tag">itens: {romaneio.items.length}</span>
        <span className="tag">litros: {numberOrDash(romaneio.carga?.volumeLiquidoL ?? null)}</span>
        <span className="tag">volumes: {numberOrDash(romaneio.carga?.volumesLogisticos ?? null)}</span>
        <span className="tag">peso líquido: {numberOrDash(romaneio.carga?.pesoLiquidoKg ?? null)} kg</span>
        <span className="tag">peso bruto: {numberOrDash(romaneio.carga?.pesoBrutoKg ?? null)} kg</span>
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
  );
}

function RomaneioItemRow({ item }: { item: RomaneioItem }) {
  return (
    <div className="romaneio-item-row">
      <div>
        <strong>{item.itemLabel}</strong>
        <span>
          item {item.id} / lote {item.lotePaRef ?? "-"}
        </span>
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

function valueOrDash(value: number | null): string {
  return value === null ? "sem conexao" : numberOrDash(value);
}

function numberOrDash(value: number | null): string {
  if (value === null) {
    return "-";
  }
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 4 }).format(value);
}

function groupPendingByOrder(items: RomaneioPendingItem[]): Array<[number, RomaneioPendingItem[]]> {
  const grouped = new Map<number, RomaneioPendingItem[]>();
  for (const item of items.filter((entry) => entry.quantidadeDisponivelRomaneio > 0)) {
    grouped.set(item.pedidoId, [...(grouped.get(item.pedidoId) ?? []), item]);
  }
  return [...grouped.entries()];
}

function labelFromMap(value: string, labels: Record<string, string>): string {
  return labels[value] ?? "Estado nao reconhecido";
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
  return labelFromMap(value, { ativa: "Ativa", baixada: "Baixada", liberada: "Liberada" });
}

function lotStatusLabel(value: string): string {
  return labelFromMap(value, { disponivel: "Disponivel", bloqueado: "Bloqueado", vencido: "Vencido" });
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
  return labelFromMap(value, { saida_romaneio: "Saida por romaneio", estorno_saida: "Estorno de saida" });
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
      title: "Entrega atribuida",
      detail: "Entregador e veiculo foram vinculados ao romaneio com historico auditavel."
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
    save_failed: {
      kind: "warning",
      title: "Falha ao salvar",
      detail: "A acao nao foi concluida. Verifique banco, permissao e logs."
    }
  };
  return messages[result] ?? messages.save_failed;
}
