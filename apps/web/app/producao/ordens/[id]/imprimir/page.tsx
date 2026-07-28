import Link from "next/link";
import { notFound } from "next/navigation";

import { PrintButton } from "@/app/producao/ordens/[id]/imprimir/print-button";
import { getOpControlledProcedures } from "@/lib/controlled-procedures";
import type { PcpOpParticipant, PcpOpReservation } from "@/lib/pcp";
import { getPcpOrderPrintData } from "@/lib/pcp";
import { orderStatusLabel, unitLabel } from "@/lib/production-labels";

export default async function PrintProductionOrderPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const orderId = Number.parseInt(id, 10);
  if (!Number.isInteger(orderId) || orderId <= 0) notFound();

  const [order, procedures] = await Promise.all([
    getPcpOrderPrintData(orderId),
    getOpControlledProcedures(orderId)
  ]);
  if (!order) notFound();

  const materials = order.components.filter((component) => component.tipoComponente === "MP");
  const formulaVersion = formulaVersionLabel(order.formulaLabel);
  const signatures = signatureRows(order.participants);

  return (
    <main className="production-order-print-sheet">
      <div className="production-order-print-actions print-hidden">
        <Link className="secondary-button" href={`/producao/ordens#op-${order.id}`}>Voltar</Link>
        <PrintButton />
      </div>

      <header className="production-order-print-header">
        <div>
          <strong>ELITE AGROCIÊNCIAS</strong>
          <span>Elite System</span>
        </div>
        <div>
          <h1>ORDEM DE PRODUÇÃO</h1>
          <strong>{order.codigoOp}</strong>
        </div>
      </header>

      <section className="production-order-print-grid">
        <PrintField label="Produto" value={order.produtoLabel} />
        <PrintField label="Fórmula" value={formulaVersion.formula} />
        <PrintField label="Versão" value={formulaVersion.version} />
        <PrintField
          label="Volume planejado"
          value={order.quantidadePlanejada === null ? "Não informado" : `${format(order.quantidadePlanejada)} L`}
        />
        <PrintField label="Revisão vigente" value={formulaVersion.version} />
        <PrintField label="Situação" value={orderStatusLabel(order.status)} />
      </section>

      <section className="production-order-print-section">
        <h2>Procedimentos aplicaveis</h2>
        {procedures.length > 0 ? (
          <table className="production-order-procedure-table">
            <thead>
              <tr>
                <th>Codigo</th>
                <th>Titulo</th>
                <th>Revisao</th>
                <th>Vigencia</th>
              </tr>
            </thead>
            <tbody>
              {procedures.map((procedure) => (
                <tr key={procedure.id}>
                  <td>{procedure.code}</td>
                  <td>{procedure.title}</td>
                  <td>{procedure.revision}</td>
                  <td>{dateOnly(procedure.effectiveFrom)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : (
          <p className="production-order-print-note">
            Nenhum procedimento estava vinculado quando esta OP foi aberta.
          </p>
        )}
      </section>

      <section className="production-order-print-section">
        <h2>Matérias-primas e lotes separados</h2>
        {materials.length > 0 ? (
          <table className="production-order-material-table">
            <thead>
              <tr>
                <th>Matéria-prima</th>
                <th>Código</th>
                <th>Total previsto</th>
                <th>Unidade</th>
                <th>Lote separado</th>
                <th>Quantidade separada</th>
                <th>Quantidade utilizada</th>
                <th>Desvio</th>
                <th>Rubrica</th>
              </tr>
            </thead>
            <tbody>
              {materials.flatMap((component) => {
                const identity = componentIdentity(component.targetLabel);
                const rows = component.reservations.length > 0
                  ? component.reservations
                  : [null];
                return rows.map((reservation, index) => (
                  <tr
                    className={index === 0 ? "production-order-component-main" : "production-order-component-lot"}
                    key={`${component.id}-${reservation?.id ?? "pending"}`}
                  >
                    <td>{index === 0 ? identity.name : ""}</td>
                    <td>{index === 0 ? identity.code : ""}</td>
                    <td>{index === 0 ? format(component.quantidadePlanejada) : ""}</td>
                    <td>{index === 0 ? unitLabel(component.unidade) : ""}</td>
                    <td>{reservation?.loteLabel ?? "A separar"}</td>
                    <td>{reservation ? format(reservation.quantidadeReservada) : "________________"}</td>
                    <td>{usedQuantity(reservation)}</td>
                    <td>{deviation(reservation)}</td>
                    <td>____________</td>
                  </tr>
                ));
              })}
            </tbody>
          </table>
        ) : (
          <div className="empty-state compact">
            <strong>Nenhuma matéria-prima vinculada</strong>
            <span>Revise a fórmula operacional antes de executar esta ordem.</span>
          </div>
        )}
      </section>

      <section className="production-order-print-section">
        <h2>Assinaturas físicas</h2>
        <p className="production-order-print-note">
          A assinatura manuscrita confirma a execução física e não substitui o participante registrado no sistema.
        </p>
        <div className="production-order-signatures">
          {signatures.map((signature) => (
            <div key={signature.key}>
              <span>________________________________________</span>
              <strong>{signature.role}</strong>
              <small>{signature.name}</small>
            </div>
          ))}
        </div>
      </section>

      <footer className="production-order-print-footer">
        <span>Documento operacional gerado pelo Elite System.</span>
        <span>Impressão: {dateTime(new Date().toISOString())}</span>
      </footer>
    </main>
  );
}

function PrintField({ label, value }: { label: string; value: string }) {
  return <div><span>{label}</span><strong>{value}</strong></div>;
}

function componentIdentity(label: string): { code: string; name: string } {
  const separator = label.indexOf(" - ");
  if (separator < 0) return { code: "Não informado", name: label };
  return { code: label.slice(0, separator), name: label.slice(separator + 3) };
}

function formulaVersionLabel(label: string): { formula: string; version: string } {
  const match = label.match(/^(.*?)\s*\/\s*.*?\sv(\d+)$/i);
  return match
    ? { formula: match[1].trim(), version: `Versão ${match[2]}` }
    : { formula: label, version: "Revisão não identificada" };
}

function usedQuantity(reservation: PcpOpReservation | null): string {
  if (!reservation || reservation.quantidadeUtilizada === null) return "________________";
  return format(reservation.quantidadeUtilizada);
}

function deviation(reservation: PcpOpReservation | null): string {
  if (!reservation || reservation.quantidadeUtilizada === null) return "________________";
  return format(reservation.quantidadeUtilizada - reservation.quantidadeReservada);
}

function signatureRows(participants: PcpOpParticipant[]) {
  const byRole = (role: string) => participants.filter((item) => item.papel === role).sort((a, b) => a.ordem - b.ordem);
  const rows = [
    signature("separador", "Separador", byRole("separador_mp")[0]),
    signature("conferente", "Conferente", byRole("conferente_mp")[0]),
    ...formulatorSignatures(byRole("formulador")),
    signature("cq", "Responsável pelo CQ", byRole("responsavel_cq")[0]),
    signature("liberacao", "Responsável pela liberação", byRole("responsavel_liberacao")[0])
  ];
  return rows;
}

function formulatorSignatures(participants: PcpOpParticipant[]) {
  if (participants.length === 0) return [signature("formulador", "Formulador", undefined)];
  return participants.map((participant, index) => signature(
    `formulador-${participant.id}`,
    index === 0 ? "Formulador principal" : `Formulador ${index + 1}`,
    participant
  ));
}

function signature(key: string, role: string, participant: PcpOpParticipant | undefined) {
  return { key, role, name: participant?.nome ?? "A definir no sistema" };
}

function format(value: number): string {
  return new Intl.NumberFormat("pt-BR", { minimumFractionDigits: 3, maximumFractionDigits: 3 }).format(value);
}

function dateTime(value: string): string {
  return new Intl.DateTimeFormat("pt-BR", {
    dateStyle: "short",
    timeStyle: "short",
    timeZone: "America/Sao_Paulo"
  }).format(new Date(value));
}

function dateOnly(value: string): string {
  return new Intl.DateTimeFormat("pt-BR", {
    timeZone: "America/Sao_Paulo"
  }).format(new Date(`${value}T12:00:00-03:00`));
}
