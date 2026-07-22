import { calculateOpGuaranteesAction, finishPcpOpAction } from "@/app/pcp/actions";
import { OutputRows } from "@/app/pcp/production-editors";
import type { PcpLookups, PcpRecentOp } from "@/lib/pcp";
import { productionStatusLabel, unitLabel } from "@/lib/production-labels";

export function QualityWorkbench({ inProcess, completed, lookups }: { inProcess: PcpRecentOp[]; completed: PcpRecentOp[]; lookups: PcpLookups }) {
  return (
    <>
      <section className="notice-panel quality-rule-panel">
        <strong>Resultado fisico preservado</strong>
        <span>CQ bloqueado ou reprovado finaliza o fato produtivo e gera lote bloqueado para decisao auditada posterior.</span>
      </section>

      <section className="panel" id="cq-pendente" aria-labelledby="quality-pending-title">
        <div className="panel-header">
          <h2 id="quality-pending-title">OP aguardando CQ</h2>
          <span className="pill">{inProcess.length} em processo</span>
        </div>
        {inProcess.length > 0 ? (
          <div className="pcp-op-list quality-op-list">
            {inProcess.map((op) => (
              <QualityOrderCard key={op.id} op={op} lookups={lookups} />
            ))}
          </div>
        ) : (
          <div className="empty-state">
            <strong>Nenhuma OP aguardando CQ</strong>
            <span>As ordens iniciadas aparecem aqui para registro e finalizacao.</span>
          </div>
        )}
      </section>

      <section className="panel" id="historico-cq" aria-labelledby="quality-history-title">
        <div className="panel-header">
          <h2 id="quality-history-title">Finalizacoes recentes</h2>
          <span className="pill">{completed.length} registro(s)</span>
        </div>
        {completed.length > 0 ? (
          <div className="operation-card-grid quality-history-grid">
            {completed.map((op) => <CompletedQualityCard key={op.id} op={op} />)}
          </div>
        ) : (
          <div className="empty-state">
            <strong>Sem finalizacoes recentes</strong>
            <span>O historico de produto gerado e garantias calculadas aparecera aqui.</span>
          </div>
        )}
      </section>
    </>
  );
}

function QualityOrderCard({ op, lookups }: { op: PcpRecentOp; lookups: PcpLookups }) {
  const reserved = op.components.reduce((total, component) => total + component.quantidadeReservada, 0);
  const planned = op.components.reduce((total, component) => total + component.quantidadePlanejada, 0);

  return (
    <article className="pcp-op-card quality-op-card">
      <div className="pcp-op-header">
        <div>
          <h3>{op.codigoOp}</h3>
          <p>{op.formulaLabel}</p>
        </div>
        <div className="pcp-op-meta">
          <span className="status-chip in_process">Em processo</span>
          <strong>{opTypeLabel(op.tipoOp)}</strong>
        </div>
      </div>
      <div className="tag-row">
        <span className="tag">produto: {op.produtoLabel}</span>
        <span className="tag">componentes: {op.components.length}</span>
        <span className="tag">planejado: {formatNumber(planned)}</span>
        <span className="tag">reservado: {formatNumber(reserved)}</span>
        <span className="tag">iniciada: {shortDate(op.startedAt)}</span>
      </div>
      <QualityFinishForm op={op} lookups={lookups} />
    </article>
  );
}

export function QualityFinishForm({ op, lookups }: { op: PcpRecentOp; lookups: PcpLookups }) {
  return (
    <form className="pcp-finish-form" action={finishPcpOpAction}>
      <input type="hidden" name="op_id" value={op.id} />
      <div className="pcp-subsection-title">
        <strong>Dados de processo e CQ</strong>
        <span>baixa insumos e gera um lote na mesma transação</span>
      </div>
      <div className="form-grid pcp-cq-grid">
        <label>
          Resultado CQ
          <select name="cq_status" defaultValue="aprovado">
            <option value="aprovado">Aprovado</option>
            <option value="bloqueado">Bloqueado</option>
            <option value="reprovado">Reprovado</option>
          </select>
        </label>
        <label>
          pH
          <input name="ph" inputMode="decimal" required />
        </label>
        <label>
          Densidade kg/L
          <input name="densidade_kg_l" inputMode="decimal" required />
        </label>
        <label>
          Volume L
          <input name="volume_l" inputMode="decimal" required />
        </label>
        <label>
          Massa kg
          <input name="massa_kg" inputMode="decimal" required />
        </label>
        <label>
          Temperatura C
          <input name="temperatura_c" inputMode="decimal" required />
        </label>
        <label>
          Separador MP
          <select name="separador_pessoa_id" defaultValue="" required>
            <option value="">Selecione</option>
            {lookups.pessoas.map((option) => <option key={option.id} value={option.id}>{option.label}</option>)}
          </select>
        </label>
        <label>
          Conferente MP
          <select name="conferente_pessoa_id" defaultValue="" required>
            <option value="">Selecione</option>
            {lookups.pessoas.map((option) => <option key={option.id} value={option.id}>{option.label}</option>)}
          </select>
        </label>
        <label>
          Formulador principal
          <select name="formulador_1_pessoa_id" defaultValue="" required>
            <option value="">Selecione</option>
            {lookups.pessoas.map((option) => <option key={option.id} value={option.id}>{option.label}</option>)}
          </select>
        </label>
        <label>
          Formulador 2
          <select name="formulador_2_pessoa_id" defaultValue="">
            <option value="">Nenhum</option>
            {lookups.pessoas.map((option) => <option key={option.id} value={option.id}>{option.label}</option>)}
          </select>
        </label>
        <label>
          Formulador 3
          <select name="formulador_3_pessoa_id" defaultValue="">
            <option value="">Nenhum</option>
            {lookups.pessoas.map((option) => <option key={option.id} value={option.id}>{option.label}</option>)}
          </select>
        </label>
        <label className="wide-field">
          Observacao final
          <input name="observacao_finalizacao" placeholder="Ocorrencias, desvios ou informacao complementar" />
        </label>
      </div>
      <OutputRows
        defaultQuantity={op.quantidadePlanejada}
        fixedProduct={{ id: op.produtoId, label: op.produtoLabel }}
        targets={{ produtos: lookups.produtos, produtoEmbalagens: lookups.produtoEmbalagens }}
      />
      <div className="form-footer compact-footer">
        <span>A OP gera um único lote do produto da fórmula. O código do lote é automático e único.</span>
        <button className="primary-button" type="submit">Finalizar OP</button>
      </div>
    </form>
  );
}

function CompletedQualityCard({ op }: { op: PcpRecentOp }) {
  return (
    <article className="module-card quality-history-card">
      <div className="module-card-main">
        <h3>{op.codigoOp}</h3>
        <span>{op.produtoLabel} / {shortDate(op.completedAt)}</span>
      </div>
      <div className="module-card-meta">
        <span className={`status-chip ${op.cqStatus ?? "completed"}`}>{cqStatusLabel(op.cqStatus)}</span>
        <strong>{op.outputs.length} lote(s)</strong>
      </div>
      <div className="tag-row">
        {op.outputs.map((output) => (
          <span className="tag" key={output.id}>{output.tipoProduto} {formatNumber(output.quantidade)} - {output.loteLabel} / {productionStatusLabel(output.statusLote)}</span>
        ))}
        {op.outputs.length === 0 ? <span className="tag">sem saida fisica</span> : null}
      </div>
      {op.guaranteeResults.length > 0 ? (
        <div className="guarantee-result-grid">
          {op.guaranteeResults.map((result) => (
            <div className="guarantee-result" key={result.id}>
              <span>{result.nutriente}</span>
              <strong>{result.valorCalculado === null ? "-" : formatNumber(result.valorCalculado)} {unitLabel(result.unidade)}</strong>
              <span className={`status-chip ${result.statusResultado}`}>{productionStatusLabel(result.statusResultado)}</span>
            </div>
          ))}
        </div>
      ) : null}
      {op.tipoOp !== "mapa_documental" ? (
        <form className="compact-action-form guarantee-calculate-form" action={calculateOpGuaranteesAction}>
          <input type="hidden" name="op_id" value={op.id} />
          <input name="justificativa" placeholder="Motivo do calculo ou recalculo" required />
          <button className="secondary-button" type="submit">Calcular garantias</button>
        </form>
      ) : null}
    </article>
  );
}

function formatNumber(value: number): string {
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 6 }).format(value);
}

function shortDate(value: string | null): string {
  if (!value) return "-";
  return new Intl.DateTimeFormat("pt-BR").format(new Date(value));
}

function opTypeLabel(value: string): string {
  return ({
    estoque: "Produção para estoque",
    experimental: "Experimental",
    desenvolvimento: "Desenvolvimento",
    reprocessamento: "Reprocessamento",
    mapa_documental: "MAPA documental"
  } as Record<string, string>)[value] ?? "Tipo não reconhecido";
}

function cqStatusLabel(value: string | null): string {
  if (!value) return "Finalizada";
  return ({ aprovado: "Aprovado", bloqueado: "Bloqueado", reprovado: "Reprovado" } as Record<string, string>)[value]
    ?? "Situação não reconhecida";
}
