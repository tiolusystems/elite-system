import Link from "next/link";

import {
  calculateOpGuaranteesAction,
  cancelPcpOpAction,
  createPcpOpAction,
  releaseBlockedLotAction,
  reservePcpComponentAction,
  startPcpOpAction
} from "@/app/pcp/actions";
import { FormulaWorkbench } from "@/app/producao/formulas/formula-workbench";
import { GuaranteeWorkbench } from "@/app/producao/garantias/guarantee-workbench";
import { QualityFinishForm } from "@/app/producao/qualidade/quality-workbench";
import {
  getPcpDashboard,
  type PcpAvailableLot,
  type PcpLookups,
  type PcpOpComponent,
  type PcpRecentOp
} from "@/lib/pcp";
import { getRuntimeStatus } from "@/lib/runtime";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function PcpPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const runtime = getRuntimeStatus();
  const dashboard = await getPcpDashboard();
  const result = singleValue(params.result);
  const formMessage = messageForResult(result);
  const today = new Date().toISOString().slice(0, 10);

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <strong>Elite System</strong>
          <span>Producao</span>
        </div>
        <nav className="topnav" aria-label="Modulos principais">
          <Link href="/">Inicio</Link>
          <a href="/modulos">Modulos</a>
          <a href="/cadastros">Cadastros</a>
          <a href="/pedidos">Pedidos</a>
          <a href="/kanban">Kanban</a>
          <a href="/importacao-xml">XML MP</a>
          <a href="/producao" aria-current="page">
            Producao
          </a>
          <a href="/romaneios">Romaneio</a>
          <a href="/relatorios">Relatorios</a>
          <a href="/seguranca">Seguranca</a>
          <a href="/login">Login</a>
        </nav>
      </header>

      <aside className={`db-banner ${runtime.isOperationalDatabase ? "operational" : ""}`}>
        <strong>{runtime.databaseLabel}</strong>
        <span>{runtime.databaseWarning}</span>
        <span className="pill">{runtime.databaseMode}</span>
      </aside>

      <section className="workspace dashboard-workspace">
        <div className="dashboard-header">
          <div>
            <span className="eyebrow">producao auditavel</span>
            <h1>Producao</h1>
            <p className="muted">
              Formula versionada, OP operacional ou MAPA documental, reserva de MP/PA/PI, baixa no encerramento e
              geracao de lotes PA/PI.
            </p>
          </div>
          <div className="toolbar-actions" aria-label="Acoes de producao">
            <a className="secondary-button" href="#nova-formula">
              Nova formula
            </a>
            <a className="secondary-button" href="#nova-op">
              Nova OP
            </a>
            <a className="primary-button" href="#ops">
              Executar OP
            </a>
          </div>
        </div>

        <nav className="production-nav" aria-label="Fluxo do modulo Producao">
          <a href="#base-tecnica">Base tecnica</a>
          <a href="#formulas">Formulas</a>
          <a href="#garantias">Garantias</a>
          <a href="#ops">Ordens</a>
          <a href="#transformacoes">Transformacoes</a>
          <a href="#lotes">CQ e lotes</a>
        </nav>

        <section className="kpi-grid" aria-label="Resumo da producao">
          <article className="kpi-card accent-blue">
            <span>Formulas versionadas</span>
            <strong>{valueOrDash(dashboard.metrics.formulasVersionadas)}</strong>
            <p>{valueOrDash(dashboard.metrics.formulasAtivas)} ativa(s) para producao ou MAPA.</p>
          </article>
          <article className="kpi-card accent-amber">
            <span>OP abertas</span>
            <strong>{valueOrDash(dashboard.metrics.opsAbertas)}</strong>
            <p>Rascunho, planejada ou em processo.</p>
          </article>
          <article className="kpi-card accent-green">
            <span>Em processo</span>
            <strong>{valueOrDash(dashboard.metrics.opsEmProcesso)}</strong>
            <p>OP iniciada aguardando CQ e finalizacao.</p>
          </article>
          <article className="kpi-card accent-red">
            <span>Lotes bloqueados</span>
            <strong>{valueOrDash(dashboard.metrics.lotesBloqueados)}</strong>
            <p>PA, PI ou MP que pedem decisao de CQ/producao.</p>
          </article>
        </section>

        <section className="production-flow" id="base-tecnica" aria-labelledby="base-tecnica-title">
          <div>
            <span className="eyebrow">fontes unicas</span>
            <h2 id="base-tecnica-title">Base tecnica da producao</h2>
          </div>
          <div className="production-flow-links">
            <a href="/cadastros#nova-mp">Materias-primas</a>
            <a href="/cadastros#novo-produto">Produtos PA e PI</a>
            <a href="/cadastros#nova-embalagem">Embalagens</a>
            <a href="/cadastros#novo-item-vendavel">Produto e embalagem</a>
          </div>
        </section>

        {dashboard.error ? (
          <section className="notice-panel warning" role="status">
            <strong>Conexao pendente</strong>
            <span>{dashboard.error}</span>
          </section>
        ) : null}

        {formMessage ? (
          <section className={`notice-panel ${formMessage.kind}`} role="status">
            <strong>{formMessage.title}</strong>
            <span>{formMessage.detail}</span>
          </section>
        ) : null}

        <FormulaWorkbench dashboard={dashboard} includeActive={false} />

        <section className="two-column">
          <section className="panel form-panel" id="nova-op" aria-labelledby="nova-op-title">
            <div className="panel-header">
              <h2 id="nova-op-title">Abrir OP</h2>
              <span className="pill">reserva antes da baixa</span>
            </div>
            <form action={createPcpOpAction}>
              <div className="form-grid">
                <label className="wide-field">
                  Formula
                  <select name="formula_versao_id" defaultValue="" required>
                    <option value="">Selecione a formula</option>
                    {dashboard.lookups.formulas.map((option) => (
                      <option key={option.id} value={option.id}>
                        {option.label} - {option.detail}
                      </option>
                    ))}
                  </select>
                </label>
                <label>
                  Tipo OP
                  <select name="tipo_op" defaultValue="estoque">
                    <option value="estoque">estoque</option>
                    <option value="experimental">experimental</option>
                    <option value="desenvolvimento">desenvolvimento</option>
                    <option value="reprocessamento">reprocessamento</option>
                    <option value="mapa_documental">mapa documental</option>
                  </select>
                </label>
                <label>
                  Quantidade planejada
                  <input name="quantidade_planejada" inputMode="decimal" placeholder="opcional" />
                </label>
                <label className="full-field">
                  Observacao
                  <input name="observacao" placeholder="Lote de producao, prioridade, observacao operacional" />
                </label>
              </div>
              <div className="form-footer">
                <span>OP MAPA documental encerra sem estoque. OP operacional copia os componentes da formula.</span>
                <button className="primary-button" type="submit">
                  Abrir OP
                </button>
              </div>
            </form>
          </section>

          <section className="panel" aria-labelledby="formulas-ativas-title">
            <div className="panel-header">
              <h2 id="formulas-ativas-title">Formulas ativas</h2>
              <span className="pill">{dashboard.activeFormulas.length} ativa(s)</span>
            </div>
            {dashboard.activeFormulas.length > 0 ? (
              <div className="module-list">
                {dashboard.activeFormulas.map((formula) => (
                  <article className="module-card" key={`${formula.produtoId}-${formula.tipoReceita}`}>
                    <div className="module-card-main">
                      <h3>{formula.produtoLabel}</h3>
                      <span>
                        {formula.tipoReceita} v{formula.versao} / ativada em {shortDate(formula.ativadaAt)}
                      </span>
                    </div>
                    <div className="module-card-meta">
                      <span>formula</span>
                      <strong>{formula.formulaVersionId}</strong>
                    </div>
                    <p>{formula.motivoAtivacao}</p>
                  </article>
                ))}
              </div>
            ) : (
              <div className="empty-state">
                <strong>Nenhuma formula ativa</strong>
                <span>Ative uma versao antes de tratar a receita como vigente.</span>
              </div>
            )}
          </section>
        </section>

        <GuaranteeWorkbench dashboard={dashboard} today={today} />

        <section className="panel" id="ops" aria-labelledby="ops-title">
          <div className="panel-header">
            <h2 id="ops-title">Ordens de producao</h2>
            <span className="pill">{dashboard.recentOps.length} recente(s)</span>
          </div>
          {dashboard.recentOps.length > 0 ? (
            <div className="pcp-op-list">
              {dashboard.recentOps.slice(0, 16).map((op) => (
                <OpCard key={op.id} op={op} lookups={dashboard.lookups} availableLots={dashboard.availableLots} />
              ))}
            </div>
          ) : (
            <div className="empty-state">
              <strong>Sem OP cadastrada</strong>
              <span>Abra uma OP para criar componentes planejados e seguir para reserva, CQ e estoque.</span>
            </div>
          )}
        </section>

        <section className="two-column" id="transformacoes" aria-label="Transformacoes e reprocessamentos">
          <section className="panel form-panel" aria-labelledby="nova-transformacao-title">
            <div className="panel-header">
              <h2 id="nova-transformacao-title">Nova transformacao</h2>
              <span className="pill">OP de reprocessamento</span>
            </div>
            <form action={createPcpOpAction}>
              <input type="hidden" name="tipo_op" value="reprocessamento" />
              <div className="form-grid">
                <label className="wide-field">
                  Formula de transformacao
                  <select name="formula_versao_id" defaultValue="" required>
                    <option value="">Selecione</option>
                    {dashboard.lookups.formulas.filter((option) => option.label.includes("/ producao ")).map((option) => (
                      <option key={option.id} value={option.id}>{option.label}</option>
                    ))}
                  </select>
                </label>
                <label>
                  Quantidade planejada
                  <input name="quantidade_planejada" inputMode="decimal" />
                </label>
                <label className="full-field">
                  Justificativa operacional
                  <input name="observacao" placeholder="PA para PI, PI para PA, reenvasamento ou reprocessamento" required />
                </label>
              </div>
              <button className="primary-button" type="submit">Abrir transformacao</button>
            </form>
          </section>
          <section className="panel" aria-labelledby="transformacoes-title">
            <div className="panel-header">
              <h2 id="transformacoes-title">Fila de transformacoes</h2>
              <span className="pill">{valueOrDash(dashboard.metrics.transformacoesAbertas)} aberta(s)</span>
            </div>
            <div className="module-list">
              {dashboard.recentOps.filter((op) => op.tipoOp === "reprocessamento").slice(0, 8).map((op) => (
                <article className="module-card" key={op.id}>
                  <div className="module-card-main"><h3>{op.codigoOp}</h3><span>{op.formulaLabel}</span></div>
                  <div className="module-card-meta"><span>{op.status}</span><strong>{op.id}</strong></div>
                  <p>{op.observacao ?? "Sem observacao"}</p>
                </article>
              ))}
              {dashboard.recentOps.every((op) => op.tipoOp !== "reprocessamento") ? (
                <div className="empty-state"><strong>Sem transformacoes</strong><span>Abra uma OP de reprocessamento para consumir PA, PI ou MP e gerar novo PA/PI.</span></div>
              ) : null}
            </div>
          </section>
        </section>

        <section className="panel" id="lotes" aria-labelledby="lotes-title">
          <div className="panel-header">
            <h2 id="lotes-title">Lotes da producao</h2>
            <span className="pill">{dashboard.availableLots.length} lote(s)</span>
          </div>
          {dashboard.availableLots.length > 0 ? (
            <div className="table-scroll">
              <table className="data-table pcp-lot-table">
                <thead>
                  <tr>
                    <th>Tipo</th>
                    <th>Lote</th>
                    <th>Item</th>
                    <th>Status</th>
                    <th>Saldo</th>
                    <th>Reservado</th>
                    <th>Disponivel</th>
                    <th>Validade</th>
                    <th>Acao</th>
                  </tr>
                </thead>
                <tbody>
                  {dashboard.availableLots.slice(0, 80).map((lot) => (
                    <tr key={`${lot.tipo}-${lot.id}`}>
                      <td>{lot.tipo}</td>
                      <td>
                        <strong>{lot.codigoLote}</strong>
                        <span className="table-subtext">id {lot.id}</span>
                      </td>
                      <td>{lot.targetLabel}</td>
                      <td>
                        <span className={`status-chip ${lot.status}`}>{lot.status}</span>
                      </td>
                      <td>{numberOrDash(lot.saldoFisico)}</td>
                      <td>{numberOrDash(lot.quantidadeReservada)}</td>
                      <td>{numberOrDash(lot.saldoDisponivel)}</td>
                      <td>{lot.dataValidade ?? "-"}</td>
                      <td>
                        {lot.status === "bloqueado" && (lot.tipo === "PA" || lot.tipo === "PI") ? (
                          <form className="compact-action-form" action={releaseBlockedLotAction}>
                            <input type="hidden" name="tipo_lote" value={lot.tipo} />
                            <input type="hidden" name="lote_id" value={lot.id} />
                            <input name="motivo" placeholder="Motivo da liberacao" required />
                            <button className="secondary-button" type="submit">Liberar</button>
                          </form>
                        ) : "-"}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : (
            <div className="empty-state">
              <strong>Sem lotes carregados</strong>
              <span>Lotes de MP, PA e PI aparecem aqui apos entradas e producao.</span>
            </div>
          )}
        </section>
      </section>
    </main>
  );
}

function OpCard({ op, lookups, availableLots }: { op: PcpRecentOp; lookups: PcpLookups; availableLots: PcpAvailableLot[] }) {
  const canReserve = op.status === "draft" || op.status === "planned";
  const canStart = op.status === "draft" || op.status === "planned";
  const canFinish = op.status === "planned" || op.status === "in_process";
  const canCancel = op.status === "draft" || op.status === "planned";

  return (
    <article className={`pcp-op-card op-${op.status}`}>
      <div className="pcp-op-header">
        <div>
          <h3>{op.codigoOp}</h3>
          <p>{op.formulaLabel}</p>
        </div>
        <div className="pcp-op-meta">
          <span className={`status-chip ${op.status}`}>{op.status}</span>
          <strong>{op.tipoOp}</strong>
        </div>
      </div>

      <div className="tag-row">
        <span className="tag">qtd: {op.quantidadePlanejada === null ? "-" : numberOrDash(op.quantidadePlanejada)}</span>
        <span className="tag">criada: {shortDate(op.createdAt)}</span>
        <span className="tag">CQ: {op.cqStatus ?? "-"}</span>
      </div>

      <section className="pcp-subsection" aria-label={`Componentes da ${op.codigoOp}`}>
        <div className="pcp-subsection-title">
          <strong>Componentes planejados</strong>
          <span>{op.components.length} item(ns)</span>
        </div>
        {op.components.length > 0 ? (
          <div className="pcp-component-list">
            {op.components.map((component) => (
              <OpComponentRow key={component.id} component={component} canReserve={canReserve} availableLots={availableLots} />
            ))}
          </div>
        ) : (
          <div className="empty-state compact-empty">
            <strong>Sem componentes</strong>
            <span>OP MAPA documental ou formula sem componente operacional.</span>
          </div>
        )}
      </section>

      {op.outputs.length > 0 ? (
        <section className="pcp-subsection" aria-label={`Produtos gerados da ${op.codigoOp}`}>
          <div className="pcp-subsection-title">
            <strong>Produtos gerados</strong>
            <span>{op.outputs.length} lote(s)</span>
          </div>
          <div className="tag-row">
            {op.outputs.map((output) => (
              <span className="tag" key={output.id}>
                {output.tipoProduto} {numberOrDash(output.quantidade)} - {output.loteLabel} / {output.statusLote}
              </span>
            ))}
          </div>
        </section>
      ) : null}

      {op.guaranteeResults.length > 0 ? (
        <section className="pcp-subsection" aria-label={`Garantias calculadas da ${op.codigoOp}`}>
          <div className="pcp-subsection-title">
            <strong>Garantias calculadas</strong>
            <span>versao {Math.max(...op.guaranteeResults.map((result) => result.calculoVersao))}</span>
          </div>
          <div className="guarantee-result-grid">
            {op.guaranteeResults.map((result) => (
              <div className="guarantee-result" key={result.id}>
                <span>{result.produtoLabel} / {result.nutriente}</span>
                <strong>{result.valorCalculado === null ? "-" : numberOrDash(result.valorCalculado)} {result.unidade}</strong>
                <span className={`status-chip ${result.statusResultado}`}>{result.statusResultado}</span>
              </div>
            ))}
          </div>
        </section>
      ) : null}

      <div className="pcp-op-actions">
        {canStart ? (
          <form className="compact-action-form" action={startPcpOpAction}>
            <input type="hidden" name="op_id" value={op.id} />
            <input name="observacao" placeholder="Observacao de inicio" />
            <button className="secondary-button" type="submit">
              Iniciar
            </button>
          </form>
        ) : null}

        {canCancel ? (
          <form className="compact-action-form" action={cancelPcpOpAction}>
            <input type="hidden" name="op_id" value={op.id} />
            <input name="motivo" placeholder="Motivo do cancelamento" required />
            <button className="secondary-button" type="submit">
              Cancelar
            </button>
          </form>
        ) : null}
      </div>

      {canFinish ? <QualityFinishForm opId={op.id} lookups={lookups} /> : null}
      {op.status === "completed" && op.tipoOp !== "mapa_documental" ? (
        <form className="compact-action-form guarantee-calculate-form" action={calculateOpGuaranteesAction}>
          <input type="hidden" name="op_id" value={op.id} />
          <input name="justificativa" placeholder="Motivo do calculo ou recalculo" required />
          <button className="secondary-button" type="submit">Calcular garantias</button>
        </form>
      ) : null}
    </article>
  );
}

function OpComponentRow({ component, canReserve, availableLots }: { component: PcpOpComponent; canReserve: boolean; availableLots: PcpAvailableLot[] }) {
  const remaining = Math.max(component.quantidadePlanejada - component.quantidadeReservada, 0);
  const compatibleLots = availableLots.filter(
    (lot) => lot.tipo === component.tipoComponente && lot.targetId === component.targetId && lot.status === "disponivel" && lot.saldoDisponivel > 0
  );

  return (
    <div className="pcp-op-component">
      <div>
        <strong>
          {component.tipoComponente} - {component.targetLabel}
        </strong>
        <span>
          planejado {numberOrDash(component.quantidadePlanejada)} {component.unidade ?? ""} / reservado{" "}
          {numberOrDash(component.quantidadeReservada)}
        </span>
      </div>
      <span className={`status-chip ${component.status}`}>{component.status}</span>
      {component.reservations.length > 0 ? (
        <div className="tag-row">
          {component.reservations.map((reservation) => (
            <span className="tag" key={reservation.id}>
              {reservation.loteLabel}: {numberOrDash(reservation.quantidadeReservada)} / {reservation.status}
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
                <option key={lot.id} value={lot.id}>{lot.codigoLote} - disponivel {numberOrDash(lot.saldoDisponivel)}</option>
              ))}
            </select>
          </label>
          <label>
            Quantidade
            <input name="quantidade_reservada" inputMode="decimal" defaultValue={numberInputValue(remaining)} />
          </label>
          <label className="wide-field">
            Observacao
            <input name="observacao" placeholder="Opcional" />
          </label>
          <button className="secondary-button" type="submit">
            Reservar
          </button>
        </form>
      ) : null}
    </div>
  );
}

function singleValue(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

function valueOrDash(value: number | null): string {
  return value === null ? "sem conexao" : String(value);
}

function numberOrDash(value: number | null): string {
  if (value === null) {
    return "-";
  }
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 4 }).format(value);
}

function numberInputValue(value: number): string {
  return String(Number(value.toFixed(6)));
}

function shortDate(value: string | null): string {
  return value ? value.slice(0, 10) : "-";
}

function messageForResult(result: string | undefined): { kind: "ok" | "warning"; title: string; detail: string } | null {
  if (!result) {
    return null;
  }
  const messages: Record<string, { kind: "ok" | "warning"; title: string; detail: string }> = {
    formula_created: {
      kind: "ok",
      title: "Formula criada",
      detail: "Uma nova versao append-only foi registrada com hash e justificativa."
    },
    formula_activated: {
      kind: "ok",
      title: "Formula ativada",
      detail: "A versao foi marcada como vigente para o produto e tipo de receita."
    },
    op_created: {
      kind: "ok",
      title: "OP aberta",
      detail: "A ordem foi criada. OP operacional copiou os componentes planejados."
    },
    component_reserved: {
      kind: "ok",
      title: "Componente reservado",
      detail: "A reserva foi registrada sem baixa fisica de estoque."
    },
    op_started: {
      kind: "ok",
      title: "OP iniciada",
      detail: "A ordem passou para producao com reservas completas."
    },
    op_finished: {
      kind: "ok",
      title: "OP finalizada",
      detail: "CQ registrado, insumos baixados e lotes PA/PI gerados."
    },
    op_cancelled: {
      kind: "ok",
      title: "OP cancelada",
      detail: "Reservas ativas foram liberadas com motivo auditado."
    },
    product_guarantee_registered: {
      kind: "ok",
      title: "Garantia do produto registrada",
      detail: "A nova versao entrou no historico append-only sem alterar a declaracao anterior."
    },
    mp_lot_guarantee_registered: {
      kind: "ok",
      title: "Garantia do lote registrada",
      detail: "O resultado do fornecedor ou laboratorio foi vinculado ao lote de materia-prima."
    },
    guarantees_calculated: {
      kind: "ok",
      title: "Garantias calculadas",
      detail: "O calculo ponderado usou os lotes efetivamente consumidos e foi congelado em nova versao."
    },
    blocked_lot_released: {
      kind: "ok",
      title: "Lote liberado",
      detail: "A liberacao de CQ foi registrada com autor, motivo e estado anterior/posterior."
    },
    not_configured: {
      kind: "warning",
      title: "Supabase nao configurado",
      detail: "Configure o banco antes de operar Producao."
    },
    missing_formula_required: {
      kind: "warning",
      title: "Formula incompleta",
      detail: "Produto, tipo e justificativa sao obrigatorios."
    },
    missing_formula_components: {
      kind: "warning",
      title: "Componente obrigatorio",
      detail: "Formula de producao precisa de pelo menos um componente."
    },
    invalid_component_row: {
      kind: "warning",
      title: "Componente invalido",
      detail: "Revise tipo, item e quantidade dos componentes da formula."
    },
    invalid_output_row: {
      kind: "warning",
      title: "Produto gerado invalido",
      detail: "Revise tipo, item e quantidade dos outputs da OP."
    },
    missing_op_required: {
      kind: "warning",
      title: "OP incompleta",
      detail: "Informe uma formula ou OP valida."
    },
    invalid_mapa_formula: {
      kind: "warning",
      title: "Formula MAPA obrigatoria",
      detail: "OP MAPA documental exige receita do tipo MAPA."
    },
    invalid_operational_formula: {
      kind: "warning",
      title: "Formula de producao obrigatoria",
      detail: "OP operacional exige receita do tipo producao."
    },
    missing_reservation_required: {
      kind: "warning",
      title: "Reserva incompleta",
      detail: "Informe componente e lote compativel."
    },
    reservation_mismatch: {
      kind: "warning",
      title: "Reserva divergente",
      detail: "A reserva precisa fechar exatamente a quantidade planejada para iniciar/finalizar."
    },
    insufficient_stock: {
      kind: "warning",
      title: "Saldo insuficiente",
      detail: "O lote escolhido nao tem saldo disponivel suficiente."
    },
    missing_full_reservation: {
      kind: "warning",
      title: "Reserva incompleta",
      detail: "Todos os componentes precisam estar integralmente reservados."
    },
    missing_finish_required: {
      kind: "warning",
      title: "CQ incompleto",
      detail: "Informe pessoas do processo e dados obrigatorios de CQ."
    },
    invalid_participants: {
      kind: "warning",
      title: "Equipe de producao invalida",
      detail: "Separador, conferente e formuladores devem ser pessoas ativas cadastradas."
    },
    missing_guarantee_required: {
      kind: "warning",
      title: "Garantia incompleta",
      detail: "Revise item, nutriente, valor, unidade, fonte, data e justificativa."
    },
    invalid_guarantee_type: {
      kind: "warning",
      title: "Classificacao de garantia invalida",
      detail: "Use um limite e uma fonte previstos pelo contrato regulatorio."
    },
    invalid_guarantee_range: {
      kind: "warning",
      title: "Faixa de garantia invalida",
      detail: "Somente limite do tipo faixa aceita valor maximo, que deve ser maior ou igual ao inicial."
    },
    missing_guarantee_document: {
      kind: "warning",
      title: "Documento obrigatorio",
      detail: "Garantia de laboratorio ou fornecedor exige laudo, certificado ou documento de referencia."
    },
    missing_guarantee_calculation: {
      kind: "warning",
      title: "Calculo incompleto",
      detail: "Informe a OP finalizada e a justificativa do calculo."
    },
    invalid_guarantee_op: {
      kind: "warning",
      title: "OP sem base para calculo",
      detail: "A OP precisa estar finalizada, ser operacional e possuir produto gerado."
    },
    invalid_guarantee: {
      kind: "warning",
      title: "Garantia rejeitada",
      detail: "O banco recusou dados ausentes, incompativeis ou fora do contrato de garantia."
    },
    missing_release_required: {
      kind: "warning",
      title: "Liberacao incompleta",
      detail: "Selecione um lote PA/PI bloqueado e informe o motivo da liberacao."
    },
    missing_cq_numbers: {
      kind: "warning",
      title: "CQ numerico incompleto",
      detail: "pH, densidade, volume, massa e temperatura sao obrigatorios."
    },
    missing_outputs: {
      kind: "warning",
      title: "Produto gerado obrigatorio",
      detail: "Finalizacao operacional precisa gerar pelo menos PA ou PI."
    },
    already_finished: {
      kind: "warning",
      title: "OP ja encerrada",
      detail: "Esta OP ja possui resultado de CQ registrado."
    },
    invalid_status: {
      kind: "warning",
      title: "Status nao permite",
      detail: "O status atual da OP ou do lote nao permite esta acao."
    },
    permission_denied: {
      kind: "warning",
      title: "Alcada bloqueada",
      detail: "O usuario atual nao tem permissao para esta acao."
    },
    save_failed: {
      kind: "warning",
      title: "Falha ao salvar",
      detail: "A acao nao foi concluida. Verifique banco, permissao e logs."
    }
  };
  return messages[result] ?? messages.save_failed;
}
