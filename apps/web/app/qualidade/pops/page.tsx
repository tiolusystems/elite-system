import Link from "next/link";

import {
  createControlledProcedureVersionAction,
  publishControlledProcedureVersionAction,
  setControlledProcedureApplicabilityAction,
  setControlledProcedureStateAction
} from "@/app/qualidade/pops/actions";
import { EmptyState, PageHeader, PageWorkspace, Panel, PermissionState } from "@/app/workspace-components";
import {
  getControlledProcedureWorkbench,
  type ControlledProcedureApplicability,
  type ControlledProcedureVersion
} from "@/lib/controlled-procedures";
import { getPcpDashboard } from "@/lib/pcp";

type SearchParams = Record<string, string | string[] | undefined>;

const STAGES = [
  ["producao", "Producao"],
  ["separacao_mp", "Separacao de materia-prima"],
  ["conferencia_mp", "Conferencia de materia-prima"],
  ["formulacao", "Formulacao"],
  ["amostragem", "Amostragem"],
  ["controle_qualidade", "Controle de Qualidade"],
  ["limpeza_equipamento", "Limpeza de equipamento"],
  ["liberacao_equipamento", "Liberacao de equipamento"],
  ["envase", "Envase"]
] as const;

export default async function ControlledProceduresPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const [workbench, dashboard] = await Promise.all([
    getControlledProcedureWorkbench(),
    getPcpDashboard()
  ]);
  const selectedId = Number(singleParam(params.selected) ?? "");
  const selected = workbench.versions.find((version) => version.versionId === selectedId) ?? null;
  const currentByPop = currentVersions(workbench.versions);
  const activeApplications = workbench.applicabilities.filter((item) => item.status === "active");

  return (
    <PageWorkspace className="controlled-procedures-workspace">
      <PageHeader
        eyebrow="Qualidade e documentos controlados"
        title="POPs e documentos controlados"
        description="Procedimentos versionados que orientam a producao e permanecem congelados em cada Ordem de Producao."
        actions={<Link className="secondary-button" href="/producao/qualidade">Abrir Controle de Qualidade</Link>}
      />
      <Feedback result={singleParam(params.result)} />

      <section className="technical-kpis" aria-label="Resumo dos procedimentos">
        <article><span>Procedimentos</span><strong>{currentByPop.length}</strong><small>Codigos controlados.</small></article>
        <article><span>Ativos</span><strong>{currentByPop.filter((item) => item.popStatus === "active").length}</strong><small>Disponiveis para novos vinculos.</small></article>
        <article><span>Versoes publicadas</span><strong>{workbench.versions.filter((item) => item.versionStatus === "published").length}</strong><small>Historico imutavel.</small></article>
        <article><span>Aplicacoes vigentes</span><strong>{activeApplications.length}</strong><small>Processos e formulas vinculados.</small></article>
      </section>

      <Panel className="controlled-procedure-catalog" >
        <div className="panel-header">
          <div><span className="eyebrow">Consulta</span><h2 id="catalogo-pops">Procedimentos cadastrados</h2></div>
          <span className="pill">{workbench.versions.length} versao(oes)</span>
        </div>
        {workbench.error ? (
          <PermissionState
            title="Catalogo indisponivel"
            description="Nao foi possivel consultar os procedimentos com a sessao atual."
          />
        ) : currentByPop.length === 0 ? (
          <EmptyState
            title="Nenhum POP cadastrado"
            description="O primeiro procedimento deve ser criado por uma pessoa com alcada especifica."
          />
        ) : (
          <div className="catalog-record-list">
            {currentByPop.map((version) => (
              <article className="catalog-record" key={version.popId}>
                <div>
                  <span><small>{version.code}</small><strong>{version.title}</strong></span>
                  <span className={`status-chip ${version.popStatus}`}>{popStatusLabel(version.popStatus)}</span>
                </div>
                <p>{version.purpose}</p>
                <div className="tag-row">
                  <span className="tag">Revisao {version.revision}</span>
                  <span className="tag">Vigencia {dateLabel(version.effectiveFrom)}</span>
                  <span className="tag">{version.applicabilityCount} aplicacao(oes)</span>
                </div>
                <div className="catalog-record-actions">
                  <span>{version.documentReference}</span>
                  <Link href={`/qualidade/pops?selected=${version.versionId}#detalhe-pop`}>Abrir procedimento</Link>
                </div>
              </article>
            ))}
          </div>
        )}
      </Panel>

      {selected ? (
        <Panel className="controlled-procedure-detail">
          <div className="panel-header" id="detalhe-pop">
            <div><span className="eyebrow">{selected.code}</span><h2>{selected.title}</h2></div>
            <span className={`status-chip ${selected.versionStatus}`}>{versionStatusLabel(selected.versionStatus)}</span>
          </div>
          <div className="detail-grid">
            <Detail label="Revisao" value={selected.revision} />
            <Detail label="Vigencia" value={dateLabel(selected.effectiveFrom)} />
            <Detail label="Referencia documental" value={selected.documentReference} />
            <Detail label="Situacao do POP" value={popStatusLabel(selected.popStatus)} />
          </div>
          <div className="controlled-procedure-content">
            <strong>Finalidade</strong><p>{selected.purpose}</p>
            <strong>Conteudo controlado</strong><p>{selected.content}</p>
          </div>
          <VersionHistory versions={workbench.versions.filter((item) => item.popId === selected.popId)} />
          <div className="controlled-procedure-actions">
            {selected.versionStatus === "draft" && workbench.capabilities.canPublish ? (
              <form action={publishControlledProcedureVersionAction}>
                <input type="hidden" name="pop_versao_id" value={selected.versionId} />
                <label>Justificativa da publicacao<input name="justificativa" minLength={10} required /></label>
                <button className="primary-button" type="submit">Publicar versao</button>
              </form>
            ) : null}
            {selected.versionStatus === "published" && workbench.capabilities.canManageState ? (
              <form action={setControlledProcedureStateAction}>
                <input type="hidden" name="pop_id" value={selected.popId} />
                <input type="hidden" name="active" value={selected.popStatus === "active" ? "false" : "true"} />
                <label>Justificativa<input name="motivo" minLength={10} required /></label>
                <button className="secondary-button" type="submit">
                  {selected.popStatus === "active" ? "Inativar POP" : "Ativar POP"}
                </button>
              </form>
            ) : null}
          </div>
        </Panel>
      ) : null}

      {workbench.capabilities.canManageApplicability ? (
        <Panel className="form-panel" >
          <div className="panel-header"><div><span className="eyebrow">Processos</span><h2 id="aplicabilidade">Aplicacao dos POPs</h2></div></div>
          <form action={setControlledProcedureApplicabilityAction}>
            <div className="form-grid">
              <label>Versao publicada<select name="pop_versao_id" defaultValue="" required><option value="">Selecione</option>{workbench.versions.filter((item) => item.versionStatus === "published" && item.popStatus === "active").map((item) => <option value={item.versionId} key={item.versionId}>{item.code} - {item.title} / revisao {item.revision}</option>)}</select></label>
              <label>Etapa<select name="etapa" defaultValue="" required><option value="">Selecione</option>{STAGES.map(([value, label]) => <option value={value} key={value}>{label}</option>)}</select></label>
              <label>Formula especifica<select name="formula_versao_id" defaultValue=""><option value="">Todas as formulas aplicaveis</option>{dashboard.formulaVersions.map((formula) => <option value={formula.id} key={formula.id}>{formula.produtoLabel} / {formula.tipoReceita === "mapa" ? "MAPA documental" : "Producao"} v{formula.versao}</option>)}</select></label>
              <label>Ordem de exibicao<input name="ordem_exibicao" type="number" min="0" defaultValue="0" required /></label>
              <label className="form-grid-wide">Justificativa<input name="motivo" minLength={10} required /></label>
            </div>
            <div className="form-footer"><span>O vinculo passa a valer somente para novas OPs.</span><button className="primary-button" type="submit">Vincular procedimento</button></div>
          </form>
          <ApplicabilityList items={activeApplications} versions={workbench.versions} formulas={dashboard.formulaVersions} />
        </Panel>
      ) : null}

      {workbench.capabilities.canCreateVersion ? (
        <Panel className="form-panel">
          <div className="panel-header"><div><span className="eyebrow">Nova revisao</span><h2 id="novo-pop">Cadastrar procedimento</h2></div></div>
          <form action={createControlledProcedureVersionAction}>
            <div className="form-grid">
              <label>POP existente<select name="pop_id" defaultValue=""><option value="">Novo codigo</option>{currentByPop.map((item) => <option value={item.popId} key={item.popId}>{item.code} - {item.title}</option>)}</select></label>
              <label>Codigo<input name="codigo" maxLength={50} required /></label>
              <label>Titulo<input name="titulo" required /></label>
              <label>Revisao<input name="revisao" required /></label>
              <label>Inicio da vigencia<input name="vigencia_inicio" type="date" required /></label>
              <label>Referencia documental<input name="referencia_documental" required /></label>
              <label className="form-grid-wide">Finalidade<textarea name="finalidade" required /></label>
              <label className="form-grid-wide">Conteudo controlado<textarea name="conteudo" rows={8} required /></label>
              <label className="form-grid-wide">Justificativa da versao<input name="justificativa" minLength={10} required /></label>
            </div>
            <div className="form-footer"><span>A versao publicada nao pode ser editada. Correcoes geram nova revisao.</span><button className="primary-button" type="submit">Salvar versao em rascunho</button></div>
          </form>
        </Panel>
      ) : (
        <PermissionState
          title="Consulta liberada"
          description="Sua conta pode consultar os POPs, mas nao possui alcada para criar ou alterar documentos controlados."
        />
      )}
    </PageWorkspace>
  );
}

function currentVersions(versions: ControlledProcedureVersion[]): ControlledProcedureVersion[] {
  const byPop = new Map<number, ControlledProcedureVersion>();
  for (const version of versions) {
    if (!byPop.has(version.popId) || (version.versionStatus === "published" && byPop.get(version.popId)?.versionStatus !== "published")) {
      byPop.set(version.popId, version);
    }
  }
  return [...byPop.values()];
}

function VersionHistory({ versions }: { versions: ControlledProcedureVersion[] }) {
  return (
    <div className="record-history">
      <h3>Historico de versoes</h3>
      {versions.map((item) => (
        <Link href={`/qualidade/pops?selected=${item.versionId}#detalhe-pop`} key={item.versionId}>
          <span>Revisao {item.revision}</span>
          <strong>{versionStatusLabel(item.versionStatus)}</strong>
          <small>{dateLabel(item.effectiveFrom)}</small>
        </Link>
      ))}
    </div>
  );
}

function ApplicabilityList({ items, versions, formulas }: { items: ControlledProcedureApplicability[]; versions: ControlledProcedureVersion[]; formulas: Array<{ id: number; produtoLabel: string; versao: number }> }) {
  if (items.length === 0) return <EmptyState title="Nenhuma aplicacao vigente" description="Vincule uma versao publicada a uma etapa ou formula." />;
  return <div className="catalog-record-list">{items.map((item) => {
    const version = versions.find((entry) => entry.versionId === item.versionId);
    const formula = formulas.find((entry) => entry.id === item.formulaVersionId);
    return (
      <article className="catalog-record" key={`${item.versionId}-${item.stage}-${item.formulaVersionId ?? "all"}`}>
        <div>
          <strong>{version ? `${version.code} - ${version.title}` : "Procedimento controlado"}</strong>
          <span className="status-chip active">Vigente</span>
        </div>
        <p>{stageLabel(item.stage)} / {formula ? `${formula.produtoLabel} v${formula.versao}` : "Aplicacao geral"}</p>
        <form action={setControlledProcedureApplicabilityAction} className="controlled-procedure-unlink">
          <input type="hidden" name="pop_versao_id" value={item.versionId} />
          <input type="hidden" name="etapa" value={item.stage} />
          <input type="hidden" name="formula_versao_id" value={item.formulaVersionId ?? ""} />
          <input type="hidden" name="ordem_exibicao" value={item.displayOrder} />
          <input type="hidden" name="active" value="false" />
          <label>Justificativa para encerrar<input name="motivo" minLength={10} required /></label>
          <button className="secondary-button" type="submit">Encerrar vinculo</button>
        </form>
      </article>
    );
  })}</div>;
}

function Detail({ label, value }: { label: string; value: string }) {
  return <div><span>{label}</span><strong>{value}</strong></div>;
}

function Feedback({ result }: { result: string | null }) {
  if (!result) return null;
  const messages: Record<string, [string, string]> = {
    version_created: ["Versao salva", "A revisao permanece em rascunho ate a publicacao auditada."],
    version_published: ["Versao publicada", "O conteudo publicado ficou imutavel."],
    pop_activated: ["POP ativado", "O procedimento pode receber novos vinculos."],
    pop_deactivated: ["POP inativado", "OPs historicas preservam a versao congelada."],
    applicability_added: ["Aplicacao registrada", "Novas OPs congelarao esta versao quando o contexto corresponder."],
    applicability_removed: ["Aplicacao encerrada", "OPs ja abertas nao foram alteradas."],
    permission_denied: ["Sem alcada", "Sua conta nao pode executar esta operacao."],
    duplicate: ["Registro duplicado", "Revise o codigo ou a revisao informada."],
    missing_required: ["Campos obrigatorios", "Preencha todos os dados do documento e a justificativa."],
    missing_reason: ["Justificativa obrigatoria", "Informe uma justificativa com pelo menos 10 caracteres."]
  };
  const [title, detail] = messages[result] ?? ["Operacao nao concluida", "Revise os dados ou procure uma pessoa com a alcada necessaria."];
  return <div className={`notice-panel ${result.includes("created") || result.includes("published") || result.includes("activated") || result.includes("added") ? "ok" : "warning"}`} role="status"><strong>{title}</strong><span>{detail}</span></div>;
}

function popStatusLabel(value: string): string {
  return value === "active" ? "Ativo" : "Inativo";
}

function versionStatusLabel(value: string): string {
  return value === "published" ? "Publicada" : "Rascunho";
}

function stageLabel(value: string): string {
  return STAGES.find(([key]) => key === value)?.[1] ?? "Etapa nao reconhecida";
}

function dateLabel(value: string): string {
  return new Intl.DateTimeFormat("pt-BR").format(new Date(`${value}T12:00:00`));
}

function singleParam(value: string | string[] | undefined): string | null {
  return Array.isArray(value) ? value[0] ?? null : value ?? null;
}
