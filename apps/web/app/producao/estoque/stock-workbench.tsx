import Link from "next/link";

import { releaseBlockedLotAction } from "@/app/pcp/actions";
import type { PcpAvailableLot } from "@/lib/pcp";

export type LotValidity = "vencido" | "vence_30_dias" | "vigente" | "sem_validade";

export function StockWorkbench({ lots, today }: { lots: PcpAvailableLot[]; today: string }) {
  if (lots.length === 0) {
    return (
      <section className="empty-state" id="lotes">
        <strong>Nenhum lote encontrado</strong>
        <span>Revise os filtros ou registre uma entrada de estoque.</span>
      </section>
    );
  }

  return (
    <section className="inventory-lot-grid" id="lotes" aria-label="Lotes de materia-prima, produto acabado e intermediario">
      {lots.map((lot) => {
        const validity = getLotValidity(lot, today);
        const canRelease = lot.status === "bloqueado" && (lot.tipo === "PA" || lot.tipo === "PI");
        const canTransform = lot.status === "disponivel" && lot.saldoDisponivel > 0;

        return (
          <article className="inventory-lot-card" key={`${lot.tipo}-${lot.id}`}>
            <div className="inventory-lot-heading">
              <div>
                <span className="eyebrow">{lot.tipo} - lote {lot.id}</span>
                <h2>{lot.codigoLote}</h2>
                <p>{lot.targetLabel}</p>
              </div>
              <span className={`status-chip ${lot.status}`}>{statusLabel(lot.status)}</span>
            </div>

            <div className="inventory-balance-grid" aria-label={`Saldos do lote ${lot.codigoLote}`}>
              <div><span>Fisico</span><strong>{formatNumber(lot.saldoFisico)}</strong></div>
              <div><span>Reservado</span><strong>{formatNumber(lot.quantidadeReservada)}</strong></div>
              <div><span>Disponivel</span><strong>{formatNumber(lot.saldoDisponivel)}</strong></div>
            </div>

            <dl className="inventory-lot-facts">
              <div>
                <dt>Validade</dt>
                <dd>
                  <span className={`status-chip validity-${validity}`}>{validityLabel(validity)}</span>
                  <small>{formatDate(lot.dataValidade)}</small>
                </dd>
              </div>
              <div><dt>Origem</dt><dd>{lot.origemRef ?? "Nao informada"}</dd></div>
              <div><dt>Atualizacao</dt><dd>{formatDateTime(lot.updatedAt)}</dd></div>
            </dl>

            <div className="inventory-lot-actions">
              {canRelease ? (
                <form className="inventory-release-form" action={releaseBlockedLotAction}>
                  <input type="hidden" name="tipo_lote" value={lot.tipo} />
                  <input type="hidden" name="lote_id" value={lot.id} />
                  <label>
                    Motivo da liberacao
                    <input name="motivo" placeholder="Laudo, analise ou decisao tecnica" required />
                  </label>
                  <button className="secondary-button" type="submit">Liberar lote</button>
                </form>
              ) : null}
              {canTransform ? (
                <Link
                  className="secondary-button"
                  href={`/producao/transformacoes?source_type=${lot.tipo}&source_lot_id=${lot.id}#nova-transformacao`}
                >
                  Planejar transformacao
                </Link>
              ) : null}
              {lot.status === "bloqueado" && lot.tipo === "MP" ? (
                <span className="field-note warning-text">MP bloqueada exige decisao tecnica fora da liberacao de PA/PI.</span>
              ) : null}
            </div>
          </article>
        );
      })}
    </section>
  );
}

export function getLotValidity(lot: Pick<PcpAvailableLot, "dataValidade">, today: string): LotValidity {
  if (!lot.dataValidade) return "sem_validade";
  const days = differenceInDays(lot.dataValidade, today);
  if (days < 0) return "vencido";
  if (days <= 30) return "vence_30_dias";
  return "vigente";
}

function differenceInDays(date: string, today: string): number {
  const target = Date.parse(`${date}T00:00:00Z`);
  const origin = Date.parse(`${today}T00:00:00Z`);
  return Math.floor((target - origin) / 86_400_000);
}

function statusLabel(value: string): string {
  return ({
    disponivel: "Disponivel",
    bloqueado: "Bloqueado",
    esgotado: "Esgotado",
    cancelado: "Cancelado"
  } as Record<string, string>)[value] ?? value;
}

function validityLabel(value: LotValidity): string {
  return {
    vencido: "Vencido",
    vence_30_dias: "Vence em 30 dias",
    vigente: "Vigente",
    sem_validade: "Sem validade"
  }[value];
}

function formatNumber(value: number): string {
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 6 }).format(value);
}

function formatDate(value: string | null): string {
  if (!value) return "-";
  const [year, month, day] = value.slice(0, 10).split("-");
  return `${day}/${month}/${year}`;
}

function formatDateTime(value: string): string {
  if (!value) return "-";
  return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short" }).format(new Date(value));
}
