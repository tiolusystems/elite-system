import Link from "next/link";
import { notFound } from "next/navigation";

import { getRomaneioDashboard } from "@/lib/romaneios";

export default async function ImprimirRomaneioPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const dashboard = await getRomaneioDashboard();
  const romaneio = dashboard.romaneios.find((entry) => entry.id === Number(id));
  if (!romaneio) notFound();

  return (
    <main className="print-document">
      <header>
        <div><strong>Elite Agrociências</strong><h1>Romaneio {romaneio.codigoRomaneio}</h1></div>
        <Link className="secondary-button print-hidden" href="/romaneios">Voltar</Link>
      </header>
      <section className="print-summary">
        <p><strong>Pedido:</strong> {romaneio.pedidoLabel}</p><p><strong>Cliente:</strong> {romaneio.clienteNome}</p>
        <p><strong>Data:</strong> {romaneio.dataRomaneio}</p><p><strong>Status:</strong> {romaneio.status}</p>
        <p><strong>Entregador:</strong> {romaneio.logistics?.entregadorNome ?? "Pendente"}</p>
        <p><strong>Veículo:</strong> {romaneio.logistics?.veiculoLabel ?? "Pendente"}</p>
        <p><strong>NF:</strong> {romaneio.fiscalDocuments.map((document) => document.numberLabel).join(", ") || "Pendente"}</p>
      </section>
      <table><thead><tr><th>Produto e embalagem</th><th>Quantidade</th><th>Lotes reservados</th></tr></thead>
        <tbody>{romaneio.items.map((item) => <tr key={item.id}><td>{item.itemLabel}</td><td>{format(item.quantidadeRomaneada)}</td><td>{item.reservations.filter((reservation) => ["ativa", "baixada"].includes(reservation.status)).map((reservation) => `${reservation.loteLabel}: ${format(reservation.quantidadeReservada)}`).join("; ") || "Pendente"}</td></tr>)}</tbody>
      </table>
      <section className="print-summary">
        <p><strong>Volume líquido:</strong> {format(romaneio.carga?.volumeLiquidoL)} L</p>
        <p><strong>Volumes logísticos:</strong> {format(romaneio.carga?.volumesLogisticos)}</p>
        <p><strong>Peso líquido:</strong> {format(romaneio.carga?.pesoLiquidoKg)} kg</p>
        <p><strong>Peso bruto:</strong> {format(romaneio.carga?.pesoBrutoKg)} kg</p>
      </section>
      {romaneio.carga?.pendencias.length ? <p><strong>Cálculo pendente:</strong> {romaneio.carga.pendencias.join(", ")}.</p> : null}
      <p className="print-hidden">Use a opção Imprimir do navegador. O documento pode ser emitido antes ou depois da NF.</p>
      <footer className="print-document-footer">
        <p><strong>Emitido no sistema por:</strong> {romaneio.emissorNome}</p>
        <p><strong>Registro original:</strong> {formatDateTime(romaneio.createdAt)}</p>
        <p><strong>Impresso em:</strong> {formatDateTime(new Date().toISOString())}</p>
        <p>Elite System · documento gerado eletronicamente</p>
      </footer>
    </main>
  );
}

function format(value: number | null | undefined) {
  return value === null || value === undefined ? "Pendente" : new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 3 }).format(value);
}

function formatDateTime(value: string) {
  return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short" }).format(new Date(value));
}
