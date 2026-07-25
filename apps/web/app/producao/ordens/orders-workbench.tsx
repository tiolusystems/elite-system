import { randomUUID } from "node:crypto";

import Link from "next/link";

import {
  cancelPcpOpAction,
  createPcpOpAction,
  reservePcpComponentFifoAction,
  reservePcpComponentAction,
  startPcpOpAction
} from "@/app/pcp/actions";
import type {
  PcpAvailableLot,
  PcpDashboard,
  PcpOpComponent,
  PcpOrderCapabilities,
  PcpRecentOp
} from "@/lib/pcp";
import {
  componentStatusLabel,
  componentTypeLabel,
  formulaPurposeLabel,
  orderStatusLabel,
  orderTypeLabel,
  productionStatusLabel,
  unitLabel
} from "@/lib/production-labels";

export function OrdersWorkbench({
  dashboard,
  orders,
  capabilities,
  startCreating = false
}: {
  dashboard: PcpDashboard;
  orders: PcpRecentOp[];
  capabilities: PcpOrderCapabilities;
  startCreating?: boolean;
}) {
  const opRequestKey = randomUUID();
  const operationalFormulas = dashboard.formulaVersions.filter(
    (formula) => formula.tipoReceita === "producao"
      && formula.baseCalculo === "por_litro"
      && formula.isActive
  );

  if (startCreating) {
    return (
      <section className="two-column production-primary-grid order-create-workflow" id="nova-op">
        <section className="panel form-panel" aria-labelledby="nova-op-title">
          <div className="panel-header">
            <div>
              <span className="eyebrow">Planejamento</span>
              <h2 id="nova-op-title">Abrir ordem de produção</h2>
            </div>
            <span className="pill">fórmula vigente</span>
          </div>
          <form action={createPcpOpAction}>
            <input type="hidden" name="idempotency_key" value={opRequestKey} />
            <div className="form-grid">
              <label className="wide-field">
                Fórmula operacional
                <select name="formula_versao_id" defaultValue="" required>
                  <option value="">Selecione a fórmula</option>
                  {operationalFormulas.map((formula) => (
                    <option key={formula.id} value={formula.id}>
                      {formula.produtoLabel} - versão {formula.versao} - base de 1 L
                    </option>
                  ))}
                </select>
              </label>
              <label>
                Finalidade da OP
                <select name="tipo_op" defaultValue="estoque">
                  <option value="estoque">Produção para estoque</option>
                  <option value="experimental">Experimental</option>
                  <option value="desenvolvimento">Desenvolvimento</option>
                  <option value="reprocessamento">Reprocessamento</option>
                </select>
              </label>
              <label>
                Volume planejado (L)
                <input name="quantidade_planejada" inputMode="decimal" placeholder="Ex.: 1.000" required />
              </label>
              <label className="full-field">
                Observação operacional
                <input name="observacao" placeholder="Prioridade ou instrução complementar" />
              </label>
            </div>
            <div className="form-footer">
              <span>O sistema multiplica cada quantidade por litro pelo volume planejado. Abrir a OP não baixa estoque.</span>
              <button className="primary-button" type="submit" disabled={operationalFormulas.length === 0}>Abrir OP</button>
            </div>
            {operationalFormulas.length === 0 ? (
              <p className="field-note warning-text">Nenhuma fórmula operacional vigente e revisada está disponível.</p>
            ) : null}
          </form>
        </section>

        <section className="panel order-formula-reference" aria-labelledby="order-formula-reference-title">
          <div className="panel-header">
            <div>
              <span className="eyebrow">Referências permitidas</span>
              <h2 id="order-formula-reference-title">Fórmulas vigentes</h2>
            </div>
            <span className="pill">{operationalFormulas.length} disponível(is)</span>
          </div>
          {operationalFormulas.length > 0 ? (
            <div className="order-formula-list">
              {operationalFormulas.map((formula) => (
                <article key={formula.id}>
                  <strong>{formula.produtoLabel}</strong>
                  <span>{formulaPurposeLabel(formula.tipoReceita)} · versão {formula.versao}</span>
                  <small>{formula.components.length} componente(s) por litro</small>
                </article>
              ))}
            </div>
          ) : (
            <div className="empty-state compact">
              <strong>Fórmula operacional necessária</strong>
              <span>Crie, revise e ative a fórmula antes de planejar a produção.</span>
            </div>
          )}
          <Link className="secondary-button" href="/producao/formulas">Consultar fórmulas</Link>
        </section>
      </section>
    );
  }

  const hasAnyOperationalCapability = Object.values(capabilities).some(Boolean);
  return (
    <>
      {!hasAnyOperationalCapability ? (
        <div className="notice-panel warning order-readonly-notice" role="status">
          <strong>Consulta disponível em modo somente leitura</strong>
          <span>Você não possui alçada para abrir, reservar, iniciar ou cancelar ordens. As ações não são exibidas.</span>
        </div>
      ) : null}

      <section className="panel" id="ops" aria-labelledby="orders-title">
        <div className="panel-header">
          <div>
            <span className="eyebrow">Consulta operacional</span>
            <h2 id="orders-title">Fila de ordens</h2>
          </div>
          <span className="pill">{orders.length} resultado(s)</span>
        </div>
        {orders.length > 0 ? (
          <div className="pcp-op-list">
            {orders.map((op, index) => (
              <PlanningOrderCard
                key={op.id}
                op={op}
                availableLots={dashboard.availableLots}
                capabilities={capabilities}
                defaultOpen={index === 0 && ["draft", "planned", "in_process"].includes(op.status)}
                returnTo="ordens"
              />
            ))}
          </div>
        ) : (
          <div className="empty-state">
            <strong>Nenhuma OP encontrada</strong>
            <span>Revise os filtros ou abra uma nova ordem.</span>
          </div>
        )}
      </section>
    </>
  );
}

export function PlanningOrderCard({
  op,
  availableLots,
  returnTo,
  capabilities,
  defaultOpen = false
}: {
  op: PcpRecentOp;
  availableLots: PcpAvailableLot[];
  returnTo: "ordens" | "transformacoes";
  capabilities: PcpOrderCapabilities;
  defaultOpen?: boolean;
}) {
  const canReserve = capabilities.canReserve && (op.status === "draft" || op.status === "planned");
  const reservationComplete = op.components.length > 0 && op.components.every(
    (component) => component.quantidadeReservada >= component.quantidadePlanejada && component.status === "reserved"
  );
  const canStart = capabilities.canStart
    && (op.status === "draft" || op.status === "planned")
    && reservationComplete;
  const canCancel = capabilities.canCancel && (op.status === "draft" || op.status === "planned");
  const reservedComponents = op.components.filter(
    (component) => component.quantidadeReservada >= component.quantidadePlanejada && component.status === "reserved"
  ).length;
  const plannedTotal = op.components.reduce((total, component) => total + component.quantidadePlanejada, 0);
  const reservedTotal = op.components.reduce((total, component) => total + component.quantidadeReservada, 0);

  return (
    <details className={`pcp-op-card order-record op-${op.status}`} id={`op-${op.id}`} open={defaultOpen || undefined}>
      <summary className="order-record-summary">
        <span className="order-record-identity">
          <strong>{op.codigoOp}</strong>
          <small>{op.produtoLabel}</small>
        </span>
        <span className="order-record-volume">
          <strong>{op.quantidadePlanejada === null ? "-" : `${formatNumber(op.quantidadePlanejada)} L`}</strong>
          <small>volume planejado</small>
        </span>
        <span className="order-record-reservation">
          <strong>{reservedComponents} de {op.components.length}</strong>
          <small>componentes reservados</small>
        </span>
        <span className={`status-chip ${op.status}`}>{orderStatusLabel(op.status)}</span>
        <span className="order-record-expand">Ver detalhes</span>
      </summary>

      <div className="order-record-detail">
        <div className="order-record-context">
          <div>
            <span>Finalidade</span>
            <strong>{orderTypeLabel(op.tipoOp)}</strong>
          </div>
          <div>
            <span>Fórmula</span>
            <strong>Operacional vinculada</strong>
          </div>
          <div>
            <span>Criada em</span>
            <strong>{shortDate(op.createdAt)}</strong>
          </div>
          <div>
            <span>CQ</span>
            <strong>{productionStatusLabel(op.cqStatus)}</strong>
          </div>
        </div>

        <div className="order-reservation-overview" aria-label="Cobertura dos componentes">
          <div>
            <span>Necessário</span>
            <strong>{formatNumber(plannedTotal)}</strong>
          </div>
          <div>
            <span>Reservado</span>
            <strong>{formatNumber(reservedTotal)}</strong>
          </div>
          <div>
            <span>Pendente</span>
            <strong>{formatNumber(Math.max(plannedTotal - reservedTotal, 0))}</strong>
          </div>
          <p>Os componentes podem usar unidades diferentes; confira cada item abaixo antes de iniciar.</p>
        </div>

        <section className="pcp-subsection" aria-label={`Componentes da ${op.codigoOp}`}>
          <div className="pcp-subsection-title">
            <strong>Componentes e reservas</strong>
            <span>{op.components.length} item(ns)</span>
          </div>
          {op.components.length > 0 ? (
            <div className="pcp-component-list">
              {op.components.map((component) => (
                <PlanningComponentRow
                  key={component.id}
                  component={component}
                  canReserve={canReserve}
                  canOverrideFifo={capabilities.canOverrideFifo}
                  availableLots={availableLots}
                  returnTo={returnTo}
                />
              ))}
            </div>
          ) : (
            <div className="empty-state compact-empty">
              <strong>Sem componentes operacionais</strong>
              <span>Esta ordem não possui componentes de estoque.</span>
            </div>
          )}
        </section>

        {op.outputs.length > 0 ? (
          <section className="pcp-subsection" aria-label={`Saídas da ${op.codigoOp}`}>
            <div className="pcp-subsection-title">
              <strong>Lotes gerados</strong>
              <span>{op.outputs.length} saída(s)</span>
            </div>
            <div className="tag-row">
              {op.outputs.map((output) => (
                <span className="tag" key={output.id}>
                  {output.tipoProduto} {output.loteLabel}: {formatNumber(output.quantidade)} · {productionStatusLabel(output.statusLote)}
                </span>
              ))}
            </div>
          </section>
        ) : null}

        <div className="pcp-op-actions planning-actions">
          {(op.status === "draft" || op.status === "planned") && !reservationComplete ? (
            <div className="workflow-callout neutral" role="status">
              <strong>Conclua as reservas antes de iniciar</strong>
              <span>Complete todos os componentes antes do início. Reservar reduz o disponível, mas não baixa o saldo físico.</span>
            </div>
          ) : null}
          {canStart ? (
            <form className="compact-action-form" action={startPcpOpAction}>
              <input type="hidden" name="op_id" value={op.id} />
              <input type="hidden" name="return_to" value={returnTo} />
              <input name="observacao" placeholder="Observação de início" />
              <button className="primary-button" type="submit">Iniciar OP</button>
            </form>
          ) : null}
          {canCancel ? (
            <form className="compact-action-form" action={cancelPcpOpAction}>
              <input type="hidden" name="op_id" value={op.id} />
              <input type="hidden" name="return_to" value={returnTo} />
              <input name="motivo" placeholder="Motivo do cancelamento" required />
              <button className="secondary-button" type="submit">Cancelar OP</button>
            </form>
          ) : null}
          {op.status === "in_process" ? (
            <Link
              className="primary-button"
              href={returnTo === "transformacoes" ? "/producao/qualidade?tipo=reprocessamento#cq-pendente" : "/producao/qualidade#cq-pendente"}
            >
              Registrar CQ e finalizar
            </Link>
          ) : null}
        </div>
      </div>
    </details>
  );
}

function PlanningComponentRow({
  component,
  canReserve,
  canOverrideFifo,
  availableLots,
  returnTo
}: {
  component: PcpOpComponent;
  canReserve: boolean;
  canOverrideFifo: boolean;
  availableLots: PcpAvailableLot[];
  returnTo: "ordens" | "transformacoes";
}) {
  const remaining = Math.max(component.quantidadePlanejada - component.quantidadeReservada, 0);
  const targetLots = availableLots.filter(
    (lot) => lot.tipo === component.tipoComponente && lot.targetId === component.targetId
  ).sort((left, right) => left.entryAt.localeCompare(right.entryAt) || left.id - right.id);
  const compatibleLots = targetLots.filter(
    (lot) => lot.status === "disponivel" && lot.saldoDisponivel > 0
  );
  const totalAvailable = compatibleLots.reduce((total, lot) => total + lot.saldoDisponivel, 0);
  const shortage = Math.max(remaining - totalAvailable, 0);
  const progress = component.quantidadePlanejada > 0
    ? Math.min((component.quantidadeReservada / component.quantidadePlanejada) * 100, 100)
    : 0;

  return (
    <article className="pcp-op-component">
      <div className="order-component-heading">
        <div>
          <strong>{componentTypeLabel(component.tipoComponente)} · {component.targetLabel}</strong>
          <span>{unitLabel(component.unidade)}</span>
        </div>
        <span className={`status-chip ${component.status}`}>{componentStatusLabel(component.status)}</span>
      </div>

      <div className="order-component-balance">
        <div><span>Necessário</span><strong>{formatNumber(component.quantidadePlanejada)}</strong></div>
        <div><span>Reservado</span><strong>{formatNumber(component.quantidadeReservada)}</strong></div>
        <div><span>Pendente</span><strong>{formatNumber(remaining)}</strong></div>
        <div><span>Disponível</span><strong>{formatNumber(totalAvailable)}</strong></div>
        <progress value={progress} max={100} aria-label={`${formatNumber(progress)}% reservado`} />
      </div>

      {component.reservations.length > 0 ? (
        <div className="order-current-reservations">
          <strong>Reservas atuais</strong>
          <div className="tag-row">
            {component.reservations.map((reservation) => (
              <span className="tag" key={reservation.id}>
                {reservation.loteLabel}: {formatNumber(reservation.quantidadeReservada)} · {productionStatusLabel(reservation.status)}
              </span>
            ))}
          </div>
        </div>
      ) : null}

      <details className="order-lot-availability">
        <summary>Consultar lotes deste componente ({targetLots.length})</summary>
        {targetLots.length > 0 ? (
          <div className="order-lot-table" role="table" aria-label={`Lotes de ${component.targetLabel}`}>
            <div className="order-lot-row order-lot-head" role="row">
              <span role="columnheader">Prioridade</span>
              <span role="columnheader">Lote</span>
              <span role="columnheader">Validade</span>
              <span role="columnheader">Físico</span>
              <span role="columnheader">Reservado</span>
              <span role="columnheader">Disponível</span>
              <span role="columnheader">Situação</span>
            </div>
            {targetLots.map((lot) => {
              const fifoPosition = compatibleLots.findIndex((candidate) => candidate.id === lot.id);
              return (
                <div className="order-lot-row" role="row" key={`${lot.tipo}-${lot.id}`}>
                  <span role="cell">{fifoPosition >= 0 ? fifoPosition + 1 : "-"}</span>
                  <strong role="cell">{lot.codigoLote}</strong>
                  <span role="cell">{shortDate(lot.dataValidade)}</span>
                  <span role="cell">{formatNumber(lot.saldoFisico)}</span>
                  <span role="cell">{formatNumber(lot.quantidadeReservada)}</span>
                  <span role="cell">{formatNumber(lot.saldoDisponivel)}</span>
                  <span role="cell">{productionStatusLabel(lot.status)}</span>
                </div>
              );
            })}
          </div>
        ) : (
          <div className="empty-state compact">
            <strong>Nenhum lote cadastrado</strong>
            <span>Registre ou libere um lote compatível antes de reservar.</span>
          </div>
        )}
      </details>

      {remaining > 0 && shortage > 0 ? (
        <div className="notice-panel warning compact order-stock-shortage" role="status">
          <strong>Saldo insuficiente</strong>
          <span>Faltam {formatNumber(shortage)} {unitLabel(component.unidade)} para cobrir este componente.</span>
        </div>
      ) : null}

      {canReserve && remaining > 0 ? (
        <div className="pcp-reservation-actions">
          <form action={reservePcpComponentFifoAction} className="pcp-fifo-action">
            <input type="hidden" name="op_componente_id" value={component.id} />
            <input type="hidden" name="return_to" value={returnTo} />
            <button className="primary-button" type="submit" disabled={shortage > 0 || compatibleLots.length === 0}>
              Reservar automaticamente por FIFO
            </button>
            <span>Distribui a pendência entre os lotes mais antigos disponíveis.</span>
          </form>
          <details className="pcp-manual-reservation">
            <summary>Selecionar lote manualmente</summary>
            <form className="inline-form-grid pcp-reserve-form" action={reservePcpComponentAction}>
              <input type="hidden" name="op_componente_id" value={component.id} />
              <input type="hidden" name="tipo_componente" value={component.tipoComponente} />
              <input type="hidden" name="return_to" value={returnTo} />
              <label className="wide-field">
                Lote de {componentTypeLabel(component.tipoComponente).toLowerCase()}
                <select name="lote_id" defaultValue="" required>
                  <option value="">Selecione</option>
                  {compatibleLots.map((lot, index) => (
                    <option key={lot.id} value={lot.id} disabled={index > 0 && !canOverrideFifo}>
                      {index === 0 ? "FIFO recomendado · " : "Fora do FIFO · "}
                      {lot.codigoLote} · disponível {formatNumber(lot.saldoDisponivel)}
                    </option>
                  ))}
                </select>
              </label>
              <label>
                Quantidade
                <input name="quantidade_reservada" inputMode="decimal" defaultValue={inputNumber(remaining)} required />
              </label>
              {canOverrideFifo ? (
                <label className="wide-field">
                  Justificativa do desvio
                  <input name="observacao" minLength={10} placeholder="Obrigatória ao ignorar o FIFO" />
                </label>
              ) : (
                <p className="field-note wide-field">Sua alçada permite reservar pelo FIFO, mas não ignorar a prioridade dos lotes.</p>
              )}
              <button className="secondary-button" type="submit" disabled={compatibleLots.length === 0}>Reservar lote selecionado</button>
              {compatibleLots.length === 0 ? <span className="field-note warning-text">Nenhum lote compatível disponível.</span> : null}
            </form>
          </details>
        </div>
      ) : null}
    </article>
  );
}

function formatNumber(value: number): string {
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 6 }).format(value);
}

function inputNumber(value: number): string {
  return Number.isInteger(value) ? String(value) : value.toFixed(6).replace(/0+$/, "").replace(/\.$/, "");
}

function shortDate(value: string | null): string {
  if (!value) return "-";
  return new Intl.DateTimeFormat("pt-BR").format(new Date(value));
}
