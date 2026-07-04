import {
  activatePcpFormulaAction,
  cancelPcpOpAction,
  createPcpFormulaAction,
  createPcpOpAction,
  finishPcpOpAction,
  reservePcpComponentAction,
  startPcpOpAction
} from "@/app/pcp/actions";
import {
  getPcpDashboard,
  type PcpAvailableLot,
  type PcpFormulaVersion,
  type PcpLookupOption,
  type PcpLookups,
  type PcpOpComponent,
  type PcpRecentOp
} from "@/lib/pcp";
import { getRuntimeStatus } from "@/lib/runtime";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function PcpPage({ searchParams }: { searchParams?: SearchParams | Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const runtime = getRuntimeStatus();
  const dashboard = await getPcpDashboard();
  const result = singleValue(params.result);
  const formMessage = messageForResult(result);

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <strong>Elite System</strong>
          <span>PCP e producao</span>
        </div>
        <nav className="topnav" aria-label="Modulos principais">
          <a href="/">Inicio</a>
          <a href="/cadastros">Cadastros</a>
          <a href="/pedidos">Pedidos</a>
          <a href="/kanban">Kanban</a>
          <a href="/importacao-xml">XML MP</a>
          <a href="/pcp" aria-current="page">
            PCP
          </a>
          <a href="/romaneios">Romaneio</a>
          <a href="/relatorios">Relatorios</a>
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
            <h1>PCP, formulas, OP e CQ</h1>
            <p className="muted">
              Formula versionada, OP operacional ou MAPA documental, reserva de MP/PA/PI, baixa no encerramento e
              geracao de lotes PA/PI.
            </p>
          </div>
          <div className="toolbar-actions" aria-label="Acoes do PCP">
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

        <LookupDatalists lookups={dashboard.lookups} availableLots={dashboard.availableLots} />

        <section className="kpi-grid" aria-label="Resumo PCP">
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
            <p>PA, PI ou MP que pedem decisao de CQ/PCP.</p>
          </article>
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

        <section className="two-column">
          <section className="panel form-panel" id="nova-formula" aria-labelledby="nova-formula-title">
            <div className="panel-header">
              <h2 id="nova-formula-title">Nova versao de formula</h2>
              <span className="pill">append-only</span>
            </div>
            <form action={createPcpFormulaAction}>
              <div className="form-grid">
                <label className="wide-field">
                  Produto PA/PI
                  <input name="produto_id" list="pcp-produtos-options" placeholder="Buscar produto" required />
                </label>
                <label>
                  Tipo receita
                  <select name="tipo_receita" defaultValue="producao">
                    <option value="producao">producao</option>
                    <option value="mapa">mapa documental</option>
                  </select>
                </label>
                <label className="wide-field">
                  Justificativa
                  <input name="justificativa" placeholder="Motivo da criacao ou alteracao da formula" required />
                </label>
                <label className="full-field">
                  Observacao
                  <input name="observacao" placeholder="Opcional" />
                </label>
              </div>
              <div className="pcp-component-editor" aria-label="Componentes da formula">
                {Array.from({ length: 6 }, (_, index) => (
                  <FormulaComponentRow key={index + 1} index={index + 1} />
                ))}
              </div>
              <div className="form-footer">
                <span>Formula de producao exige componente. Formula MAPA pode ser apenas documental.</span>
                <button className="primary-button" type="submit">
                  Criar versao
                </button>
              </div>
            </form>
          </section>

          <section className="panel" id="formulas" aria-labelledby="formulas-title">
            <div className="panel-header">
              <h2 id="formulas-title">Formulas recentes</h2>
              <span className="pill">{dashboard.formulaVersions.length} versao(oes)</span>
            </div>
            {dashboard.formulaVersions.length > 0 ? (
              <div className="module-list">
                {dashboard.formulaVersions.slice(0, 10).map((formula) => (
                  <FormulaCard key={formula.id} formula={formula} />
                ))}
              </div>
            ) : (
              <div className="empty-state">
                <strong>Sem formulas carregadas</strong>
                <span>Quando Supabase estiver configurado, as formulas versionadas aparecerao aqui.</span>
              </div>
            )}
          </section>
        </section>

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
                  <input name="formula_versao_id" list="pcp-formulas-options" placeholder="Buscar formula" required />
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

        <section className="panel" id="ops" aria-labelledby="ops-title">
          <div className="panel-header">
            <h2 id="ops-title">Ordens de producao</h2>
            <span className="pill">{dashboard.recentOps.length} recente(s)</span>
          </div>
          {dashboard.recentOps.length > 0 ? (
            <div className="pcp-op-list">
              {dashboard.recentOps.slice(0, 16).map((op) => (
                <OpCard key={op.id} op={op} />
              ))}
            </div>
          ) : (
            <div className="empty-state">
              <strong>Sem OP cadastrada</strong>
              <span>Abra uma OP para criar componentes planejados e seguir para reserva, CQ e estoque.</span>
            </div>
          )}
        </section>

        <section className="panel" aria-labelledby="lotes-title">
          <div className="panel-header">
            <h2 id="lotes-title">Lotes disponiveis para PCP</h2>
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

function FormulaComponentRow({ index }: { index: number }) {
  return (
    <div className="pcp-component-row">
      <span className="pcp-row-index">{index}</span>
      <label>
        Tipo
        <select name={`component_${index}_tipo`} defaultValue="">
          <option value="">ignorar</option>
          <option value="MP">MP</option>
          <option value="PA">PA</option>
          <option value="PI">PI</option>
        </select>
      </label>
      <label className="wide-field">
        Item
        <input
          name={`component_${index}_target_id`}
          list="pcp-component-target-options"
          placeholder="MP: materia-prima / PA: produto+embalagem / PI: produto"
        />
      </label>
      <label>
        Quantidade
        <input name={`component_${index}_quantidade`} inputMode="decimal" />
      </label>
      <label>
        Unidade
        <input name={`component_${index}_unidade`} placeholder="KG, L, UN" />
      </label>
      <label className="wide-field">
        Observacao
        <input name={`component_${index}_observacao`} placeholder="Opcional" />
      </label>
    </div>
  );
}

function FormulaCard({ formula }: { formula: PcpFormulaVersion }) {
  return (
    <article className="module-card">
      <div className="module-card-main">
        <h3>{formula.produtoLabel}</h3>
        <span>
          {formula.tipoReceita} v{formula.versao} / {shortDate(formula.createdAt)}
        </span>
      </div>
      <div className="module-card-meta">
        <span>{formula.isActive ? "ativa" : "versao"}</span>
        <strong>{formula.id}</strong>
      </div>
      <p>{formula.justificativa}</p>
      <div className="tag-row">
        {formula.components.length > 0 ? (
          formula.components.slice(0, 6).map((component) => (
            <span className="tag" key={component.id}>
              {component.tipoComponente} {numberOrDash(component.quantidade)} {component.unidade ?? ""} -{" "}
              {component.targetLabel}
            </span>
          ))
        ) : (
          <span className="tag">sem componentes operacionais</span>
        )}
      </div>
      {!formula.isActive ? (
        <form className="compact-action-form" action={activatePcpFormulaAction}>
          <input type="hidden" name="formula_versao_id" value={formula.id} />
          <input name="motivo" placeholder="Motivo para ativar esta versao" required />
          <button className="secondary-button" type="submit">
            Ativar
          </button>
        </form>
      ) : null}
    </article>
  );
}

function OpCard({ op }: { op: PcpRecentOp }) {
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
              <OpComponentRow key={component.id} component={component} canReserve={canReserve} />
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

      {canFinish ? <FinishOpForm opId={op.id} /> : null}
    </article>
  );
}

function OpComponentRow({ component, canReserve }: { component: PcpOpComponent; canReserve: boolean }) {
  const remaining = Math.max(component.quantidadePlanejada - component.quantidadeReservada, 0);
  const lotDatalistId =
    component.tipoComponente === "MP"
      ? "pcp-lotes-mp-options"
      : component.tipoComponente === "PA"
        ? "pcp-lotes-pa-options"
        : "pcp-lotes-pi-options";

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
            <input name="lote_id" list={lotDatalistId} placeholder="Buscar lote disponivel" required />
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

function FinishOpForm({ opId }: { opId: number }) {
  return (
    <form className="pcp-finish-form" action={finishPcpOpAction}>
      <input type="hidden" name="op_id" value={opId} />
      <div className="pcp-subsection-title">
        <strong>Finalizacao com CQ</strong>
        <span>baixa insumos e gera lotes</span>
      </div>
      <div className="form-grid pcp-cq-grid">
        <label>
          CQ
          <select name="cq_status" defaultValue="aprovado">
            <option value="aprovado">aprovado</option>
            <option value="bloqueado">bloqueado</option>
            <option value="reprovado">reprovado</option>
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
          <input name="separador_mp" required />
        </label>
        <label>
          Conferente MP
          <input name="conferente_mp" required />
        </label>
        <label className="wide-field">
          Formuladores
          <input name="formuladores" placeholder="Separe por virgula" required />
        </label>
        <label className="wide-field">
          Observacao
          <input name="observacao_finalizacao" placeholder="Opcional" />
        </label>
      </div>
      <div className="pcp-output-editor" aria-label="Produtos gerados">
        {Array.from({ length: 3 }, (_, index) => (
          <OutputRow key={index + 1} index={index + 1} />
        ))}
      </div>
      <div className="form-footer compact-footer">
        <span>PA usa produto+embalagem. PI usa produto base. O lote e automatico.</span>
        <button className="primary-button" type="submit">
          Finalizar OP
        </button>
      </div>
    </form>
  );
}

function OutputRow({ index }: { index: number }) {
  return (
    <div className="pcp-output-row">
      <span className="pcp-row-index">{index}</span>
      <label>
        Saida
        <select name={`output_${index}_tipo`} defaultValue="">
          <option value="">ignorar</option>
          <option value="PA">PA</option>
          <option value="PI">PI</option>
        </select>
      </label>
      <label className="wide-field">
        Produto gerado
        <input name={`output_${index}_target_id`} list="pcp-output-target-options" placeholder="PA: item vendavel / PI: produto" />
      </label>
      <label>
        Quantidade
        <input name={`output_${index}_quantidade`} inputMode="decimal" />
      </label>
      <label className="wide-field">
        Observacao
        <input name={`output_${index}_observacao`} placeholder="Opcional" />
      </label>
    </div>
  );
}

function LookupDatalists({ lookups, availableLots }: { lookups: PcpLookups; availableLots: PcpAvailableLot[] }) {
  return (
    <>
      <LookupDatalist id="pcp-produtos-options" options={lookups.produtos} />
      <LookupDatalist id="pcp-component-target-options" options={lookups.componentTargets} />
      <LookupDatalist id="pcp-output-target-options" options={lookups.outputTargets} />
      <LookupDatalist id="pcp-formulas-options" options={lookups.formulas} />
      <LookupDatalist id="pcp-ops-options" options={lookups.ops} />
      <LookupDatalist id="pcp-lotes-mp-options" options={lotOptions(availableLots, "MP")} />
      <LookupDatalist id="pcp-lotes-pa-options" options={lotOptions(availableLots, "PA")} />
      <LookupDatalist id="pcp-lotes-pi-options" options={lotOptions(availableLots, "PI")} />
    </>
  );
}

function LookupDatalist({ id, options }: { id: string; options: PcpLookupOption[] }) {
  return (
    <datalist id={id}>
      {options.map((option) => (
        <option key={`${id}-${option.id}-${option.label}`} value={lookupValue(option)} />
      ))}
    </datalist>
  );
}

function lotOptions(lots: PcpAvailableLot[], tipo: "MP" | "PA" | "PI"): PcpLookupOption[] {
  return lots
    .filter((lot) => lot.tipo === tipo && lot.status === "disponivel" && lot.saldoDisponivel > 0)
    .map((lot) => ({
      id: lot.id,
      label: `${lot.codigoLote} - ${lot.targetLabel}`,
      detail: `disp ${numberOrDash(lot.saldoDisponivel)} / val ${lot.dataValidade ?? "-"}`
    }));
}

function lookupValue(option: PcpLookupOption): string {
  return option.detail ? `${option.id} | ${option.label} | ${option.detail}` : `${option.id} | ${option.label}`;
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
    not_configured: {
      kind: "warning",
      title: "Supabase nao configurado",
      detail: "Configure o banco antes de operar PCP."
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
