import { calculateOpGuaranteesAction, finishPcpOpAction } from "@/app/pcp/actions";
import { OutputRows } from "@/app/pcp/production-editors";
import type { PcpLookups, PcpRecentOp } from "@/lib/pcp";
import { productionStatusLabel, unitLabel } from "@/lib/production-labels";

export function QualityWorkbench({ inProcess, completed, lookups }: { inProcess: PcpRecentOp[]; completed: PcpRecentOp[]; lookups: PcpLookups }) {
  return (
    <>
      <section className="notice-panel quality-rule-panel">
        <strong>Resultado físico preservado</strong>
        <span>CQ bloqueado ou reprovado finaliza o fato produtivo e gera lote bloqueado para decisão auditada posterior.</span>
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
            <span>As ordens iniciadas aparecem aqui para registro e finalização.</span>
          </div>
        )}
      </section>

      <section className="panel" id="historico-cq" aria-labelledby="quality-history-title">
        <div className="panel-header">
          <h2 id="quality-history-title">Finalizações recentes</h2>
          <span className="pill">{completed.length} registro(s)</span>
        </div>
        {completed.length > 0 ? (
          <div className="operation-card-grid quality-history-grid">
            {completed.map((op) => <CompletedQualityCard key={op.id} op={op} />)}
          </div>
        ) : (
          <div className="empty-state">
            <strong>Sem finalizações recentes</strong>
            <span>O histórico de produto gerado e garantias calculadas aparecerá aqui.</span>
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
        <span className="tag">Produto: {op.produtoLabel}</span>
        <span className="tag">Componentes: {op.components.length}</span>
        <span className="tag">Planejado: {formatNumber(planned)}</span>
        <span className="tag">Reservado: {formatNumber(reserved)}</span>
        <span className="tag">Iniciada: {shortDate(op.startedAt)}</span>
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
      <ProcedureChecks op={op} />
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
        <label>
          Responsável pelo CQ
          <select name="responsavel_cq_pessoa_id" defaultValue="" required>
            <option value="">Selecione</option>
            {lookups.pessoas.map((option) => <option key={option.id} value={option.id}>{option.label}</option>)}
          </select>
        </label>
        <label>
          Responsável pela liberação
          <select name="responsavel_liberacao_pessoa_id" defaultValue="" required>
            <option value="">Selecione</option>
            {lookups.pessoas.map((option) => <option key={option.id} value={option.id}>{option.label}</option>)}
          </select>
        </label>
        <label className="wide-field">
          Observação final
          <input name="observacao_finalizacao" placeholder="Ocorrências, desvios ou informação complementar" />
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
  const historyState = qualityHistoryState(op);

  return (
    <article className="module-card quality-history-card">
      <div className="module-card-main">
        <h3>{op.codigoOp}</h3>
        <span>{op.produtoLabel} / {shortDate(op.completedAt)}</span>
      </div>
      <div className="module-card-meta">
        <span className={`status-chip ${historyState.className}`}>{historyState.label}</span>
        <strong>{lotCountLabel(op.outputs.length)}</strong>
      </div>
      <div className="tag-row">
        {op.outputs.map((output) => (
          <span className="tag" key={output.id}>{output.tipoProduto} {formatNumber(output.quantidade)} - {output.loteLabel} / {productionStatusLabel(output.statusLote)}</span>
        ))}
        {op.outputs.length === 0 ? <span className="tag">Sem lote de saída registrado</span> : null}
      </div>
      {op.participants.length > 0 ? (
        <div className="quality-participant-history" aria-label="Participantes registrados">
          {op.participants.map((participant) => (
            <span key={participant.id}>
              <strong>{participantRoleLabel(participant.papel, participant.ordem)}:</strong> {participant.nome}
            </span>
          ))}
        </div>
      ) : null}
      {op.procedures.length > 0 ? (
        <div className="quality-procedure-history" aria-label="Procedimentos observados">
          <strong>Procedimentos aplicados</strong>
          {op.procedures.map((procedure) => (
            <span key={procedure.id}>
              {procedure.code} / revisao {procedure.revision}: {procedure.cqResult ? cqProcedureResultLabel(procedure.cqResult) : "Sem registro de execucao"}
            </span>
          ))}
        </div>
      ) : null}
      {historyState.needsReview ? (
        <div className="notice-panel warning compact" role="status">
          <strong>Registro histórico preservado</strong>
          <span>Esta OP não possui CQ e um único lote de saída conforme o contrato atual. Consulte a auditoria antes de qualquer decisão.</span>
        </div>
      ) : null}
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
          <input name="justificativa" placeholder="Motivo do cálculo ou recálculo" required />
          <button className="secondary-button" type="submit">Calcular garantias</button>
        </form>
      ) : null}
    </article>
  );
}

function ProcedureChecks({ op }: { op: PcpRecentOp }) {
  if (op.procedures.length === 0) {
    return (
      <div className="notice-panel compact" role="status">
        <strong>Nenhum POP congelado nesta OP</strong>
        <span>A ordem preserva esse fato historico. Vinculos criados depois nao alteram a OP.</span>
      </div>
    );
  }

  return (
    <fieldset className="form-section quality-procedure-checks">
      <legend>Procedimentos aplicaveis</legend>
      <p className="muted">Registre a observancia das versoes congeladas quando a OP foi aberta.</p>
      {op.procedures.map((procedure) => (
        <div className="quality-procedure-check" key={procedure.id}>
          <input type="hidden" name="pop_snapshot_id" value={procedure.id} />
          <input type="hidden" name={`pop_etapa_${procedure.id}`} value={procedure.stage} />
          <div>
            <strong>{procedure.code} - {procedure.title}</strong>
            <span>Revisao {procedure.revision} / vigencia {shortDate(procedure.effectiveFrom)}</span>
          </div>
          <label>
            Resultado
            <select name={`pop_resultado_${procedure.id}`} defaultValue="conforme">
              <option value="conforme">Conforme</option>
              <option value="desvio">Desvio</option>
              <option value="nao_conforme">Nao conforme</option>
            </select>
          </label>
          <label>
            Observacao
            <input name={`pop_observacao_${procedure.id}`} placeholder="Obrigatoria para desvio ou nao conformidade" />
          </label>
          <label>
            Acao corretiva
            <input name={`pop_acao_${procedure.id}`} placeholder="Quando houver acao contratada" />
          </label>
        </div>
      ))}
    </fieldset>
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
  if (!value) return "Revisão necessária";
  return ({ aprovado: "Aprovado", bloqueado: "Bloqueado", reprovado: "Reprovado" } as Record<string, string>)[value]
    ?? "Situação não reconhecida";
}

function qualityHistoryState(op: PcpRecentOp): { className: string; label: string; needsReview: boolean } {
  if (!op.cqStatus || op.outputs.length !== 1) {
    return { className: "pending_review", label: "Revisão necessária", needsReview: true };
  }
  return { className: op.cqStatus, label: cqStatusLabel(op.cqStatus), needsReview: false };
}

function lotCountLabel(count: number): string {
  if (count === 0) return "Nenhum lote";
  if (count === 1) return "1 lote";
  return `${count} lotes`;
}

function participantRoleLabel(role: string, order: number): string {
  return ({
    separador_mp: "Separador",
    conferente_mp: "Conferente",
    formulador: order === 1 ? "Formulador principal" : `Formulador ${order}`,
    responsavel_cq: "Responsável pelo CQ",
    responsavel_liberacao: "Responsável pela liberação"
  } as Record<string, string>)[role] ?? "Participante";
}

function cqProcedureResultLabel(value: string): string {
  return ({
    conforme: "Conforme",
    desvio: "Desvio",
    nao_conforme: "Nao conforme"
  } as Record<string, string>)[value] ?? "Resultado nao reconhecido";
}
