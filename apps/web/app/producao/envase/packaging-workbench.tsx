import { randomUUID } from "node:crypto";
import Link from "next/link";
import { finishPackagingAction, issuePackagingOrderAction, reservePackagingAction, startPackagingAction } from "@/app/producao/envase/actions";
import type { PackagingComponent, PackagingOrder, PackagingOrdersData } from "@/lib/packaging-orders";

export function PackagingWorkbench({ data }: { data: PackagingOrdersData }) {
  const issueRequestKey = randomUUID();
  return <>
    <section className="panel form-panel" id="emitir">
      <div className="panel-header"><h2>Emitir OP MAPA e Ordem de Envase</h2><span className="pill">emissão conjunta</span></div>
      <form action={issuePackagingOrderAction}>
        <input type="hidden" name="idempotency_key" value={issueRequestKey} />
        <div className="form-grid">
          <label className="wide-field">Fórmula MAPA ativa<select name="formula_mapa_versao_id" defaultValue="" required><option value="">Selecione</option>{data.formulas.map((item) => <option key={item.id} value={item.id}>{item.label}</option>)}</select></label>
          <label className="wide-field">Lote PI liberado<select name="lote_pi_origem_id" defaultValue="" required><option value="">Selecione</option>{data.piLots.map((item) => <option key={item.id} value={item.id}>{item.label} - {item.detail}</option>)}</select></label>
          <label className="wide-field">Produto e embalagem<select name="produto_embalagem_id" defaultValue="" required><option value="">Selecione</option>{data.presentations.map((item) => <option key={item.id} value={item.id}>{item.label}</option>)}</select></label>
          <label>Volume a envasar (L)<input name="volume_planejado_l" inputMode="decimal" required /></label>
          <label className="full-field">Observação<input name="observacao" placeholder="Instrução documental ou operacional" /></label>
        </div>
        <div className="form-footer"><span>O sistema valida produto, PI, apresentação e composição de embalagens antes de emitir.</span><button className="primary-button" type="submit">Emitir documentos</button></div>
      </form>
    </section>

    <section className="panel" id="ordens-envase">
      <div className="panel-header"><h2>Ordens de Envase</h2><span className="pill">{data.pagination.total} ordem(ns)</span></div>
      {data.orders.length ? <div className="packaging-order-list">{data.orders.map((order) => <PackagingOrderCard key={order.id} order={order} mpLots={data.mpLots} />)}</div> : <div className="empty-state"><strong>Nenhuma ordem emitida</strong><span>Emita a primeira OP MAPA com sua Ordem de Envase.</span></div>}
    </section>
  </>;
}

function PackagingOrderCard({ order, mpLots }: { order: PackagingOrder; mpLots: PackagingOrdersData["mpLots"] }) {
  const canPrepare = ["emitida", "em_separacao"].includes(order.status);
  const reservationsComplete = order.components.length > 0 && order.components.every(
    (component) => component.reservedQuantity >= component.plannedQuantity
  );
  const reservedComponents = order.components.filter(
    (component) => component.reservedQuantity >= component.plannedQuantity
  ).length;
  return <article className="pcp-op-card packaging-order-card">
    <div className="pcp-op-header"><div><h3>{order.code}</h3><p>{order.productName} / {order.packageName}</p></div><div className="pcp-op-meta"><span className={`status-chip ${order.status}`}>{statusLabel(order.status)}</span><strong>{order.mapaOpCode}</strong></div></div>
    <div className="tag-row"><span className="tag">PI {order.piLotCode}</span><span className="tag">{number(order.plannedVolume)} L</span><span className="tag">{number(order.plannedFinishedPackages)} unidade(s) PA</span><span className="tag">embalagens: {reservedComponents} de {order.components.length} completas</span><span className="tag">emitida por {order.issuerName}</span></div>
    <section className="pcp-subsection"><div className="pcp-subsection-title"><strong>Embalagens previstas</strong><span>{order.components.length} componente(s)</span></div>{order.components.map((component) => <PackagingComponentRow key={component.id} component={component} mpLots={mpLots} canReserve={canPrepare} />)}</section>
    {order.outputs.length ? <section className="pcp-subsection"><div className="pcp-subsection-title"><strong>Lote PA gerado</strong><span>{order.outputs.length}</span></div><div className="tag-row">{order.outputs.map((output) => <span className="tag" key={output.id}>{output.lotLabel}: {number(output.quantity)}</span>)}</div></section> : null}
    <div className="pcp-op-actions planning-actions">
      <Link className="secondary-button" href={`/producao/envase/${order.id}/imprimir`} target="_blank">Imprimir ordem</Link>
      {canPrepare && !reservationsComplete ? <div className="workflow-callout neutral" role="status"><strong>Conclua a separação das embalagens</strong><span>Reserve integralmente cada componente antes de iniciar o envase.</span></div> : null}
      {canPrepare && reservationsComplete ? <form action={startPackagingAction}><input type="hidden" name="ordem_envase_id" value={order.id} /><button className="primary-button" type="submit">Iniciar envase</button></form> : null}
    </div>
    {order.status === "em_envase" ? <FinishForm order={order} /> : null}
  </article>;
}

function PackagingComponentRow({ component, mpLots, canReserve }: { component: PackagingComponent; mpLots: PackagingOrdersData["mpLots"]; canReserve: boolean }) {
  const remaining = Math.max(component.plannedQuantity - component.reservedQuantity, 0);
  const compatible = mpLots.filter((lot) => lot.targetId === component.materialId);
  return <div className="pcp-op-component"><div><strong>{component.materialLabel}</strong><span>planejado {number(component.plannedQuantity)} {component.unitLabel} / reservado {number(component.reservedQuantity)}</span></div>{component.reservations.length ? <div className="tag-row">{component.reservations.map((reservation) => <span className="tag" key={reservation.id}>{reservation.lotLabel}: {number(reservation.quantity)}</span>)}</div> : null}{canReserve && remaining > 0 ? <form className="inline-form-grid pcp-reserve-form" action={reservePackagingAction}><input type="hidden" name="embalagem_planejada_id" value={component.id} /><label className="wide-field">Lote da embalagem<select name="lote_mp_id" defaultValue="" required><option value="">Selecione</option>{compatible.map((lot) => <option key={lot.id} value={lot.id}>{lot.label} - {lot.detail}</option>)}</select></label><label>Quantidade<input name="quantidade" inputMode="decimal" defaultValue={inputNumber(remaining)} required /></label><button className="secondary-button" type="submit" disabled={!compatible.length}>Reservar</button></form> : null}</div>;
}

function FinishForm({ order }: { order: PackagingOrder }) {
  return <form className="packaging-finish-form" action={finishPackagingAction}><input type="hidden" name="ordem_envase_id" value={order.id} /><div className="panel-header"><h4>Gerar lote PA</h4><span className="pill">quantidade obrigatória: {number(order.plannedFinishedPackages)}</span></div><div className="form-grid"><div className="packaging-output-row"><label>Quantidade do lote PA<input name="lote_pa_quantidade" inputMode="decimal" defaultValue={inputNumber(order.plannedFinishedPackages)} required /></label><label>Identificação do lote<input name="lote_pa_observacao" placeholder="Referência operacional opcional" /></label></div><label className="full-field">Observação final<input name="observacao" /></label></div><div className="form-footer"><span>Esta ordem gera um único lote PA para a apresentação selecionada.</span><button className="primary-button" type="submit">Finalizar e gerar PA</button></div></form>;
}
function statusLabel(value: string): string { return ({ emitida: "Emitida", em_separacao: "Em separação", em_envase: "Em envase", finalizada: "Finalizada", cancelada: "Cancelada" } as Record<string, string>)[value] ?? "Estado não reconhecido"; }
function number(value: number): string { return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 3 }).format(value); }
function inputNumber(value: number): string { return String(value).replace(".", ","); }
