import Link from "next/link";

import {
  cancelPcpOpAction,
  createPcpOpAction,
  reservePcpComponentFifoAction,
  reservePcpComponentAction,
  startPcpOpAction
} from "@/app/pcp/actions";
import type { PcpAvailableLot, PcpDashboard, PcpOpComponent, PcpRecentOp } from "@/lib/pcp";
import { componentTypeLabel, productionStatusLabel, unitLabel } from "@/lib/production-labels";

export function OrdersWorkbench({ dashboard, orders }: { dashboard: PcpDashboard; orders: PcpRecentOp[] }) {
  return (
    <>
      <section className="two-column production-primary-grid">
        <section className="panel form-panel" id="nova-op" aria-labelledby="nova-op-title">
          <div className="panel-header">
            <h2 id="nova-op-title">Abrir ordem de producao</h2>
            <span className="pill">formula vigente</span>
          </div>
          <form action={createPcpOpAction}>
            <div className="form-grid">
              <label className="wide-field">
                Formula
                <select name="formula_versao_id" defaultValue="" required>
                  <option value="">Selecione a formula</option>
                  {dashboard.formulaVersions
                    .filter((formula) => formula.tipoReceita === "producao" && formula.baseCalculo === "por_litro" && formula.isActive)
                    .map((formula) => (
                    <option key={formula.id} value={formula.id}>{formula.produtoLabel} - versão {formula.versao} - base 1 L</option>
                  ))}
                </select>
              </label>
              <label>
                Tipo de OP
                <select name="tipo_op" defaultValue="estoque">
                  <option value="estoque">Producao para estoque</option>
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
                Observacao operacional
                <input name="observacao" placeholder="Prioridade, lote planejado ou instrucao complementar" />
              </label>
            </div>
            <div className="form-footer">
              <span>O sistema multiplica cada quantidade por litro pelo volume planejado. A baixa acontece somente na finalizacao.</span>
              <button className="primary-button" type="submit">Abrir OP</button>
            </div>
          </form>
        </section>

        <section className="panel" aria-labelledby="active-formulas-title">
          <div className="panel-header">
            <h2 id="active-formulas-title">Formulas disponiveis</h2>
            <span className="pill">{dashboard.activeFormulas.length} ativa(s)</span>
          </div>
          {dashboard.activeFormulas.length > 0 ? (
            <div className="module-list compact-module-list">
              {dashboard.activeFormulas.map((formula) => (
                <article className="module-card" key={`${formula.produtoId}-${formula.tipoReceita}`}>
                  <div className="module-card-main">
                    <h3>{formula.produtoLabel}</h3>
                    <span>{formula.tipoReceita} v{formula.versao}</span>
                  </div>
                  <div className="module-card-meta"><span>formula</span><strong>{formula.formulaVersionId}</strong></div>
                  <p>{formula.motivoAtivacao}</p>
                </article>
              ))}
            </div>
          ) : (
            <div className="empty-state">
              <strong>Nenhuma formula ativa</strong>
              <span>Ative uma formula antes de abrir uma OP operacional.</span>
              <Link className="secondary-button" href="/producao/formulas">Ir para formulas</Link>
            </div>
          )}
        </section>
      </section>

      <section className="panel" id="ops" aria-labelledby="orders-title">
        <div className="panel-header">
          <h2 id="orders-title">Fila de ordens</h2>
          <span className="pill">{orders.length} resultado(s)</span>
        </div>
        {orders.length > 0 ? (
          <div className="pcp-op-list">
            {orders.map((op) => (
              <PlanningOrderCard key={op.id} op={op} availableLots={dashboard.availableLots} returnTo="ordens" />
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
  returnTo
}: {
  op: PcpRecentOp;
  availableLots: PcpAvailableLot[];
  returnTo: "ordens" | "transformacoes";
}) {
  const canReserve = op.status === "draft" || op.status === "planned";
  const canStart = op.status === "draft" || op.status === "planned";
  const canCancel = op.status === "draft" || op.status === "planned";

  return (
    <article className={`pcp-op-card op-${op.status}`} id={`op-${op.id}`}>
      <div className="pcp-op-header">
        <div>
          <h3>{op.codigoOp}</h3>
          <p>{op.formulaLabel}</p>
        </div>
        <div className="pcp-op-meta">
          <span className={`status-chip ${op.status}`}>{statusLabel(op.status)}</span>
          <strong>{opTypeLabel(op.tipoOp)}</strong>
        </div>
      </div>

      <div className="tag-row">
        <span className="tag">volume planejado: {op.quantidadePlanejada === null ? "-" : `${formatNumber(op.quantidadePlanejada)} L`}</span>
        <span className="tag">criada: {shortDate(op.createdAt)}</span>
        <span className="tag">CQ: {op.cqStatus ?? "nao informado"}</span>
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
                availableLots={availableLots}
                returnTo={returnTo}
              />
            ))}
          </div>
        ) : (
          <div className="empty-state compact-empty">
            <strong>Sem componentes operacionais</strong>
            <span>OP MAPA documental ou formula sem componente de estoque.</span>
          </div>
        )}
      </section>

      {op.outputs.length > 0 ? (
        <section className="pcp-subsection" aria-label={`Saidas da ${op.codigoOp}`}>
          <div className="pcp-subsection-title">
            <strong>Lotes gerados</strong>
            <span>{op.outputs.length} saida(s)</span>
          </div>
          <div className="tag-row">
            {op.outputs.map((output) => (
              <span className="tag" key={output.id}>
                {output.tipoProduto} {output.loteLabel}: {formatNumber(output.quantidade)} / {productionStatusLabel(output.statusLote)}
              </span>
            ))}
          </div>
        </section>
      ) : null}

      <div className="pcp-op-actions planning-actions">
        {canStart ? (
          <form className="compact-action-form" action={startPcpOpAction}>
            <input type="hidden" name="op_id" value={op.id} />
            <input type="hidden" name="return_to" value={returnTo} />
            <input name="observacao" placeholder="Observacao de inicio" />
            <button className="primary-button" type="submit">Iniciar OP</button>
          </form>
        ) : null}
        {canCancel ? (
          <form className="compact-action-form" action={cancelPcpOpAction}>
            <input type="hidden" name="op_id" value={op.id} />
            <input type="hidden" name="return_to" value={returnTo} />
            <input name="motivo" placeholder="Motivo do cancelamento" required />
            <button className="secondary-button" type="submit">Cancelar</button>
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
    </article>
  );
}

function PlanningComponentRow({
  component,
  canReserve,
  availableLots,
  returnTo
}: {
  component: PcpOpComponent;
  canReserve: boolean;
  availableLots: PcpAvailableLot[];
  returnTo: "ordens" | "transformacoes";
}) {
  const remaining = Math.max(component.quantidadePlanejada - component.quantidadeReservada, 0);
  const compatibleLots = availableLots.filter(
    (lot) => lot.tipo === component.tipoComponente
      && lot.targetId === component.targetId
      && lot.status === "disponivel"
      && lot.saldoDisponivel > 0
  ).sort((left, right) => left.entryAt.localeCompare(right.entryAt) || left.id - right.id);

  return (
    <div className="pcp-op-component">
      <div>
        <strong>{componentTypeLabel(component.tipoComponente)} - {component.targetLabel}</strong>
        <span>
          planejado {formatNumber(component.quantidadePlanejada)} {unitLabel(component.unidade)} / reservado {formatNumber(component.quantidadeReservada)}
        </span>
      </div>
      <span className={`status-chip ${component.status}`}>{componentStatusLabel(component.status)}</span>
      {component.reservations.length > 0 ? (
        <div className="tag-row">
          {component.reservations.map((reservation) => (
            <span className="tag" key={reservation.id}>
              {reservation.loteLabel}: {formatNumber(reservation.quantidadeReservada)} / {productionStatusLabel(reservation.status)}
            </span>
          ))}
        </div>
      ) : null}
      {canReserve && remaining > 0 ? (
        <div className="pcp-reservation-actions">
          <form action={reservePcpComponentFifoAction} className="pcp-fifo-action">
            <input type="hidden" name="op_componente_id" value={component.id} />
            <input type="hidden" name="return_to" value={returnTo} />
            <button className="primary-button" type="submit" disabled={compatibleLots.length === 0}>Reservar automaticamente por FIFO</button>
            <span>Usa primeiro os lotes mais antigos e distribui a necessidade quando preciso.</span>
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
                    <option key={lot.id} value={lot.id}>{index === 0 ? "FIFO recomendado - " : ""}{lot.codigoLote} - disponível {formatNumber(lot.saldoDisponivel)}</option>
                  ))}
                </select>
              </label>
              <label>
                Quantidade
                <input name="quantidade_reservada" inputMode="decimal" defaultValue={inputNumber(remaining)} required />
              </label>
              <label className="wide-field">
                Justificativa do desvio
                <input name="observacao" placeholder="Obrigatória ao ignorar o FIFO" />
              </label>
              <button className="secondary-button" type="submit" disabled={compatibleLots.length === 0}>Reservar lote selecionado</button>
              {compatibleLots.length === 0 ? <span className="field-note warning-text">Nenhum lote compatível disponível.</span> : null}
            </form>
          </details>
        </div>
      ) : null}
    </div>
  );
}

function statusLabel(value: string): string {
  return ({ draft: "Rascunho", planned: "Planejada", in_process: "Em processo", completed: "Finalizada", cancelled: "Cancelada" } as Record<string, string>)[value] ?? value;
}

function componentStatusLabel(value: string): string {
  return ({ pending: "Pendente", partial: "Parcial", reserved: "Reservado", consumed: "Consumido" } as Record<string, string>)[value] ?? value;
}

function opTypeLabel(value: string): string {
  return ({ estoque: "Estoque", experimental: "Experimental", desenvolvimento: "Desenvolvimento", reprocessamento: "Reprocessamento", mapa_documental: "MAPA documental" } as Record<string, string>)[value] ?? value;
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
