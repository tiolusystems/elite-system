import Link from "next/link";
import { notFound } from "next/navigation";
import { PrintButton } from "@/app/producao/envase/[id]/imprimir/print-button";
import { getPackagingOrdersData } from "@/lib/packaging-orders";

export default async function PrintPackagingOrderPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const orderId = Number.parseInt(id, 10);
  const data = await getPackagingOrdersData();
  const order = data.orders.find((item) => item.id === orderId);
  if (!order) notFound();
  return <main className="packaging-print-sheet">
    <div className="packaging-print-actions print-hidden"><Link className="secondary-button" href="/producao/envase">Voltar</Link><PrintButton /></div>
    <header className="packaging-print-header"><div><strong>ELITE AGROCIÊNCIAS</strong><span>Elite System</span></div><div><h1>ORDEM DE ENVASE</h1><strong>{order.code}</strong></div></header>
    <section className="packaging-print-grid">
      <PrintField label="OP MAPA" value={order.mapaOpCode} />
      <PrintField label="Fórmula MAPA" value={`Versão ${order.formulaVersion}`} />
      <PrintField label="Produto" value={order.productName} />
      <PrintField label="Apresentação" value={`${order.saleItemCode} / ${order.packageName}`} />
      <PrintField label="Lote origem PI" value={order.piLotCode} />
      <PrintField label="Volume planejado" value={`${format(order.plannedVolume)} L`} />
      <PrintField label="Quantidade PA" value={`${format(order.plannedFinishedPackages)} unidade(s)`} />
      <PrintField label="Situação" value={statusLabel(order.status)} />
    </section>
    <section className="packaging-print-section"><h2>Embalagens e insumos do envase</h2><table><thead><tr><th>Material</th><th>Por litro</th><th>Planejado</th><th>Lote reservado</th></tr></thead><tbody>{order.components.map((component) => <tr key={component.id}><td>{component.materialLabel}</td><td>{format(component.quantityPerLiter)} {component.unitLabel}</td><td>{format(component.plannedQuantity)} {component.unitLabel}</td><td>{component.reservations.map((item) => `${item.lotLabel}: ${format(item.quantity)}`).join("; ") || "A separar"}</td></tr>)}</tbody></table></section>
    <section className="packaging-print-section"><h2>Lotes destino PA</h2>{order.outputs.length ? <table><thead><tr><th>Lote</th><th>Quantidade</th></tr></thead><tbody>{order.outputs.map((output) => <tr key={output.id}><td>{output.lotLabel}</td><td>{format(output.quantity)}</td></tr>)}</tbody></table> : <div className="packaging-print-lines"><span>Lote PA: ____________________________________</span><span>Quantidade: _________________________________</span></div>}</section>
    <section className="packaging-print-section packaging-print-lines"><h2>Execução física</h2><span>Data: ____/____/________</span><span>Hora de início: ______:______</span><span>Hora de término: ______:______</span></section>
    <section className="packaging-signatures"><div><span>________________________________________</span><strong>Operador</strong></div><div><span>________________________________________</span><strong>Conferente</strong></div></section>
    <footer className="packaging-print-footer"><div><strong>Emitido por:</strong> {order.issuerName}</div><div><strong>Data e hora:</strong> {dateTime(order.issuedAt)}</div><div><strong>Terminal:</strong> {order.terminal}</div><div><strong>Observação:</strong> {order.observation || "Sem observação"}</div><p>As assinaturas dos operadores são físicas. A emissão eletrônica pertence ao usuário autenticado identificado acima.</p></footer>
  </main>;
}

function PrintField({ label, value }: { label: string; value: string }) { return <div><span>{label}</span><strong>{value}</strong></div>; }
function format(value: number): string { return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 3 }).format(value); }
function dateTime(value: string): string { return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "medium", timeZone: "America/Sao_Paulo" }).format(new Date(value)); }
function statusLabel(value: string): string { return ({ emitida: "Emitida", em_separacao: "Em separação", em_envase: "Em envase", finalizada: "Finalizada", cancelada: "Cancelada" } as Record<string, string>)[value] ?? "Estado não reconhecido"; }
