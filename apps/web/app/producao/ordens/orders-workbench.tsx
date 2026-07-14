import Link from "next/link";

import {
  cancelPcpOpAction,
  createPcpOpAction,
  reservePcpComponentAction,
  startPcpOpAction
} from "@/app/pcp/actions";
import type { PcpAvailableLot, PcpDashboard, PcpOpComponent, PcpRecentOp } from "@/lib/pcp";

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
                  {dashboard.lookups.formulas.map((option) => (
                    <option key={option.id} value={option.id}>{option.label} - {option.detail}</option>
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
                  <option value="mapa_documental">MAPA documental</option>
                </select>
              </label>
              <label>
                Quantidade planejada
                <input name="quantidade_planejada" inputMode="decimal" placeholder="Opcional" />
              </label>
              <label className="full-field">
                Observacao operacional
                <input name="observacao" placeholder="Prioridade, lote planejado ou instrucao complementar" />
              </label>
            </div>
            <div className="form-footer">
              <span>A OP reserva componentes; a baixa acontece somente na finalizacao.</span>
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
              <PlanningOrderCard key={op.id} op={op} availableLots={dashboard.availableLots} />
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

function PlanningOrderCard({ op, availableLots }: { op: PcpRecentOp; availableLots: PcpAvailableLot[] }) {
  const canReserve = op.status === "draft" || op.status === "planned";
  const canStart = op.status === "draft" || op.status === "planned";
  const canCancel = op.status === "draft" || op.status === "planned";

  return (
    <article className={`pcp-op-card op-${op.status}`}>
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
        <span className="tag">planejado: {op.quantidadePlanejada === null ? "-" : formatNumber(op.quantidadePlanejada)}</span>
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

      <div className="pcp-op-actions planning-actions">
        {canStart ? (
          <form className="compact-action-form" action={startPcpOpAction}>
            <input type="hidden" name="op_id" value={op.id} />
            <input name="observacao" placeholder="Observacao de inicio" />
            <button className="primary-button" type="submit">Iniciar OP</button>
          </form>
        ) : null}
        {canCancel ? (
          <form className="compact-action-form" action={cancelPcpOpAction}>
            <input type="hidden" name="op_id" value={op.id} />
            <input name="motivo" placeholder="Motivo do cancelamento" required />
            <button className="secondary-button" type="submit">Cancelar</button>
          </form>
        ) : null}
        {op.status === "in_process" ? (
          <Link className="primary-button" href="/pcp#ops">Registrar CQ e finalizar</Link>
        ) : null}
      </div>
    </article>
  );
}

function PlanningComponentRow({
  component,
  canReserve,
  availableLots
}: {
  component: PcpOpComponent;
  canReserve: boolean;
  availableLots: PcpAvailableLot[];
}) {
  const remaining = Math.max(component.quantidadePlanejada - component.quantidadeReservada, 0);
  const compatibleLots = availableLots.filter(
    (lot) => lot.tipo === component.tipoComponente
      && lot.targetId === component.targetId
      && lot.status === "disponivel"
      && lot.saldoDisponivel > 0
  );

  return (
    <div className="pcp-op-component">
      <div>
        <strong>{component.tipoComponente} - {component.targetLabel}</strong>
        <span>
          planejado {formatNumber(component.quantidadePlanejada)} {component.unidade ?? ""} / reservado {formatNumber(component.quantidadeReservada)}
        </span>
      </div>
      <span className={`status-chip ${component.status}`}>{componentStatusLabel(component.status)}</span>
      {component.reservations.length > 0 ? (
        <div className="tag-row">
          {component.reservations.map((reservation) => (
            <span className="tag" key={reservation.id}>
              {reservation.loteLabel}: {formatNumber(reservation.quantidadeReservada)} / {reservation.status}
            </span>
          ))}
        </div>
      ) : null}
      {canReserve && remaining > 0 ? (
        <form className="inline-form-grid pcp-reserve-form" action={reservePcpComponentAction}>
          <input type="hidden" name="op_componente_id" value={component.id} />
          <input type="hidden" name="tipo_componente" value={component.tipoComponente} />
          <label className="wide-field">
            Lote {component.tipoComponente}
            <select name="lote_id" defaultValue="" required>
              <option value="">Selecione</option>
              {compatibleLots.map((lot) => (
                <option key={lot.id} value={lot.id}>{lot.codigoLote} - disponivel {formatNumber(lot.saldoDisponivel)}</option>
              ))}
            </select>
          </label>
          <label>
            Quantidade
            <input name="quantidade_reservada" inputMode="decimal" defaultValue={inputNumber(remaining)} required />
          </label>
          <label className="wide-field">
            Observacao
            <input name="observacao" placeholder="Opcional" />
          </label>
          <button className="secondary-button" type="submit" disabled={compatibleLots.length === 0}>Reservar</button>
          {compatibleLots.length === 0 ? <span className="field-note warning-text">Nenhum lote compativel disponivel.</span> : null}
        </form>
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
