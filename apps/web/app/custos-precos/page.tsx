import { redirect } from "next/navigation";

import { PricingCalculationForm, PricingPolicyForm, PricingReviewForm, PricingScenarioForm } from "./pricing-action-forms";
import { getPricingAccess, getPricingWorkspace, type PricingWorkspace } from "@/lib/cost-pricing";
import styles from "./pricing.module.css";

type SearchParams = { etapa?: string | string[] };
type WorkflowStageId = "base-custo" | "politica" | "cenario" | "precos-prazos" | "revisao-dossie";
type StageState = "complete" | "available" | "waiting" | "blocked" | "quiet";

const WORKFLOW_STAGE_IDS: WorkflowStageId[] = ["base-custo", "politica", "cenario", "precos-prazos", "revisao-dossie"];

export default async function CostPricingPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const access = await getPricingAccess();
  if (!access.view) redirect("/modulo-indisponivel?module=precificacao&reason=permission");

  const workspace = await getPricingWorkspace();
  const data = workspace.data;
  if (!data) return <main className={styles.workspace}>
    <WorkspaceHeader facts={{ policies: 0, scenarios: 0, calculations: 0 }} />
    <section className={styles.unavailable} aria-live="assertive"><div className="notice-panel warning" role="alert"><strong>Consulta indisponivel</strong><span>{workspace.error ?? "Nao foi possivel carregar a formacao de custos e precos."}</span></div></section>
  </main>;

  const approvedVersions = data.politicas.flatMap((policy) => policy.versoes.map((version) => ({ ...version, policy }))).filter((version) => version.status === "APPROVED");
  const calculations = data.cenarios.flatMap((scenario) => scenario.calculos.map((calculation) => ({ ...calculation, scenario })));
  const pendingPolicyVersions = data.politicas.flatMap((policy) => policy.versoes.filter((version) => version.status === "PENDING").map((version) => ({ ...version, policy })));
  const pendingCalculations = calculations.filter((calculation) => calculation.status === "PENDING");
  const approvedCalculations = calculations.filter((calculation) => calculation.status === "APPROVED");
  const workflow = buildWorkflow(data, approvedVersions.length, calculations.length, approvedCalculations.length, pendingPolicyVersions.length + pendingCalculations.length);
  const selectedStage = normalizeStage(params.etapa, workflow.current.id);
  const selectedStageInfo = workflow.stages.find((stage) => stage.id === selectedStage) ?? workflow.current;

  const stageContent = selectedStage === "base-custo" ? <CostBaseStage presentations={data.apresentacoes.length} />
    : selectedStage === "politica" ? <PolicyStage access={access.policy} policies={data.politicas.map((policy) => ({ id: policy.id, label: `${policy.codigo} - ${policy.nome}` }))} approvedVersions={approvedVersions.length} policiesCount={data.politicas.length} />
      : selectedStage === "cenario" ? <ScenarioStage access={access.scenario} approvedVersions={approvedVersions} presentations={data.apresentacoes} />
        : selectedStage === "precos-prazos" ? <PricesStage access={access.calculate} scenarios={data.cenarios} calculations={calculations} />
          : <ReviewStage access={access} pendingPolicyVersions={pendingPolicyVersions} pendingCalculations={pendingCalculations} calculations={calculations} approvedCalculations={approvedCalculations} />;

  return <main className={styles.workspace}>
    <WorkspaceHeader facts={{ policies: data.politicas.length, scenarios: data.cenarios.length, calculations: calculations.length }} />
    <WorkflowStepper stages={workflow.stages} selectedStage={selectedStage} currentStage={workflow.current.id} />
    <div className={styles.workspaceLayout}>
      <section className={styles.activeStage} aria-labelledby={`${selectedStage}-title`}>
        <StageHeading stage={selectedStageInfo} number={String(WORKFLOW_STAGE_IDS.indexOf(selectedStage) + 1)} />
        <div className={styles.stageBody}>{stageContent}</div>
      </section>
      <WorkflowContext current={workflow.current} selectedStage={selectedStageInfo} />
    </div>
  </main>;
}

function CostBaseStage({ presentations }: { presentations: number }) {
  return <div className={styles.costBaseState}>
    <div><span className="status-chip">Custo tecnico automatico ainda nao calculado</span><h3>Base de custo atual</h3><p>A composicao automatica por formula, valoracao e embalagem ainda nao esta disponivel. Os cenarios usam substituicao manual governada, com origem, data e justificativa registradas.</p></div>
    <dl><div><dt>Apresentacoes elegiveis</dt><dd>{presentations}</dd></div><div><dt>Fonte atual</dt><dd>Substituicao manual governada</dd></div></dl>
  </div>;
}

function PolicyStage({ access, policies, approvedVersions, policiesCount }: { access: boolean; policies: Array<{ id: number; label: string }>; approvedVersions: number; policiesCount: number }) {
  return <>{!access ? <Permission /> : <PricingPolicyForm policies={policies} />}<div className={styles.stageFootnote}>{approvedVersions ? "Uma politica aprovada ja pode ser usada em novos cenarios." : policiesCount ? "Aprove uma versao pendente para liberar os cenarios." : "Crie a primeira politica comercial para iniciar o fluxo."}</div></>;
}

function ScenarioStage({ access, approvedVersions, presentations }: { access: boolean; approvedVersions: Array<{ id: number; versao: number; policy: { codigo: string } }>; presentations: Array<{ id: number; codigo: string; produto: string; apresentacao: string }> }) {
  if (!access) return <Permission />;
  if (!approvedVersions.length) return <Empty title="Cenario ainda bloqueado" text="Aprove uma politica para liberar esta etapa." />;
  if (!presentations.length) return <Empty title="Apresentacao ainda ausente" text="Cadastre uma apresentacao de produto antes de congelar um cenario." />;
  return <PricingScenarioForm policies={approvedVersions.map((version) => ({ id: version.id, label: `${version.policy.codigo} - versao ${version.versao}` }))} presentations={presentations.map((item) => ({ id: item.id, label: `${item.codigo} - ${item.produto} / ${item.apresentacao}` }))} />;
}

function PricesStage({ access, scenarios, calculations }: { access: boolean; scenarios: PricingWorkspace["cenarios"]; calculations: Array<{ id: number; status: string; preco_vista: number; cmv_percentual: number; contribuicao_liquida: number; prazos: Array<{ prazo_dias: number; preco: number }>; scenario: { id: number; nome: string; motivo: string; componentes: Array<{ source_kind: string }> } }> }) {
  return <div className={styles.pricesWorkspace}>
    {scenarios.length ? <div className={styles.calculationList}>{scenarios.map((scenario) => <article className={styles.calculationCard} key={scenario.id}><div><h3>{scenario.nome}</h3><p>{scenario.motivo}</p><span className="status-chip">{scenario.componentes.some((component) => component.source_kind === "substituicao_manual") ? "Base manual governada" : "Fontes congeladas"}</span></div>{access ? <PricingCalculationForm scenarioId={scenario.id} /> : <Permission />}</article>)}</div> : <Empty title="Calculo ainda nao disponivel" text="Crie e congele um cenario antes de calcular." />}
    {calculations.length ? <div className={styles.priceResults} aria-label="Memoria de calculo">{calculations.map((calculation) => <article className={styles.priceResult} key={calculation.id}><div className={styles.priceResultHeading}><div><h3>{calculation.scenario.nome}</h3><span className={`status-chip ${calculation.status === "APPROVED" ? "ativo" : ""}`}>{status(calculation.status)}</span></div><small>Resultado comercial</small></div><div className={styles.priceKpis}><div className={styles.pricePrimary}><span>Preco a vista</span><strong>{money(calculation.preco_vista)}</strong></div><div><span>CMV</span><strong>{percent(calculation.cmv_percentual)}</strong></div><div><span>Contribuicao liquida</span><strong>{money(calculation.contribuicao_liquida)}</strong></div></div><div className={styles.terms} aria-label="Precos por prazo">{calculation.prazos.map((term) => <span key={term.prazo_dias}><small>{term.prazo_dias} dias</small><strong>{money(term.preco)}</strong></span>)}</div></article>)}</div> : null}
  </div>;
}

function ReviewStage({ access, pendingPolicyVersions, pendingCalculations, calculations, approvedCalculations }: { access: Awaited<ReturnType<typeof getPricingAccess>>; pendingPolicyVersions: Array<{ id: number; versao: number; metodo: string; policy: { nome: string } }>; pendingCalculations: Array<{ id: number; preco_vista: number; scenario: { nome: string } }>; calculations: Array<{ id: number; status: string; calculated_at: string; result_sha256: string; scenario: { nome: string } }>; approvedCalculations: Array<{ id: number; scenario: { nome: string } }> }) {
  const hasPendingReview = pendingPolicyVersions.length > 0 || pendingCalculations.length > 0;
  return <div className={styles.reviewWorkspace}>
    <section className={styles.reviewSection} aria-labelledby="pendencias-title"><div className={styles.reviewSectionHeading}><div><span className="eyebrow">Prioridade</span><h3 id="pendencias-title">Pendencias para aprovacao</h3></div><p>Quem criou a politica, o cenario ou o calculo nao pode aprovar o proprio trabalho.</p></div><div className={styles.reviewQueue}>{!hasPendingReview ? <Empty title={calculations.length ? "Sem pendencias de revisao" : "Revisao ainda bloqueada"} text={calculations.length ? "Nao ha decisao aguardando uma pessoa revisora." : "Calcule uma memoria e envie-a para aprovacao para liberar esta etapa."} /> : null}{pendingPolicyVersions.map((version) => <article key={`p-${version.id}`}><div><h4>{version.policy.nome} - versao {version.versao}</h4><p>Metodo: {label(version.metodo)}</p></div>{access.policyReview ? <PricingReviewForm id={version.id} kind="policy" /> : <Permission />}</article>)}{pendingCalculations.map((calculation) => <article key={`c-${calculation.id}`}><div><h4>{calculation.scenario.nome}</h4><p>Preco a vista {money(calculation.preco_vista)}; calculo aguardando decisao.</p></div>{access.calculationReview ? <PricingReviewForm id={calculation.id} kind="calculation" /> : <Permission />}</article>)}</div></section>
    <section className={styles.reviewSection} aria-labelledby="historico-title"><div className={styles.reviewSectionHeading}><div><span className="eyebrow">Rastreabilidade</span><h3 id="historico-title">Historico e documentos</h3></div><p>O dossie preserva o que foi decidido, com o detalhe de auditoria disponivel quando necessario.</p></div>{calculations.length ? <div className={styles.historyList}>{calculations.map((calculation) => <article key={calculation.id}><div><h4>{calculation.scenario.nome}</h4><span className={`status-chip ${calculation.status === "APPROVED" ? "ativo" : ""}`}>{status(calculation.status)}</span></div><details><summary>Detalhe de auditoria</summary><p>Registro calculado em {dateTime(calculation.calculated_at)}. Referencia de auditoria {calculation.result_sha256.slice(0, 12)}.</p></details></article>)}</div> : <Empty title="Historico ainda indisponivel" text="A memoria aparece depois que um cenario for calculado." />}</section>
    <section className={styles.approvedDocuments} aria-labelledby="documentos-title"><div className={styles.reviewSectionHeading}><div><span className="eyebrow">Entrega</span><h3 id="documentos-title">Documentos aprovados</h3></div><p>Os arquivos ficam disponiveis somente depois da aprovacao do calculo.</p></div>{approvedCalculations.length ? approvedCalculations.map((calculation) => <div className={styles.approvedDocumentRow} key={`approved-${calculation.id}`}><span>{calculation.scenario.nome}</span><div className={styles.exports}><a className="secondary-button" href={`/custos-precos/export/${calculation.id}/xlsx`}>Baixar XLSX</a><a className="secondary-button" href={`/custos-precos/export/${calculation.id}/pdf`}>Baixar PDF</a></div></div>) : <Empty title="Sem documentos aprovados" text="Os arquivos aparecem depois da aprovacao do calculo." />}</section>
  </div>;
}

function buildWorkflow(data: PricingWorkspace, approvedVersions: number, calculations: number, approvedCalculations: number, pendingReviews: number) {
  const currentId: WorkflowStageId = pendingReviews ? "revisao-dossie" : !approvedVersions ? "politica" : !data.cenarios.length ? "cenario" : !calculations ? "precos-prazos" : "revisao-dossie";
  const stages: Array<{ id: WorkflowStageId; title: string; description: string; label: string; state: StageState }> = [
    { id: "base-custo", title: "Produto e base de custo", description: "Consulte as apresentacoes e a fonte de custo permitida para o cenario.", label: data.apresentacoes.length ? "Disponivel" : "Bloqueada", state: data.apresentacoes.length ? "available" : "blocked" },
    { id: "politica", title: "Politica comercial", description: "Crie ou versione uma politica governada antes de usa-la em cenarios.", label: approvedVersions ? "Concluida" : data.politicas.length ? "Em aprovacao" : "Disponivel", state: approvedVersions ? "complete" : data.politicas.length ? "waiting" : "available" },
    { id: "cenario", title: "Cenario", description: "Congele a base manual governada e os componentes comerciais do produto.", label: data.cenarios.length ? "Concluida" : approvedVersions ? "Pronta" : "Bloqueada", state: data.cenarios.length ? "complete" : approvedVersions ? "available" : "blocked" },
    { id: "precos-prazos", title: "Precos e prazos", description: "Calcule e consulte o preco a vista, indicadores e prazos comerciais.", label: calculations ? "Concluida" : data.cenarios.length ? "Pronta" : "Bloqueada", state: calculations ? "complete" : data.cenarios.length ? "available" : "blocked" },
    { id: "revisao-dossie", title: "Revisao e dossie", description: "Decida pendencias e consulte o historico com documentos aprovados.", label: pendingReviews ? "Em aprovacao" : approvedCalculations ? "Sem pendencias" : "Bloqueada", state: pendingReviews ? "waiting" : approvedCalculations ? "quiet" : "blocked" },
  ];
  const current = stages.find((stage) => stage.id === currentId)!;
  const detail = currentId === "revisao-dossie" && pendingReviews ? "Registre a decisao de aprovacao ou rejeicao pendente." : currentId === "politica" ? "Crie ou aprove uma politica comercial para seguir." : currentId === "cenario" ? "Congele um cenario com a base de custo governada." : currentId === "precos-prazos" ? "Calcule a memoria para obter precos e prazos." : "Acompanhe o dossie e os documentos aprovados.";
  return { stages, current: { ...current, detail, owner: currentId === "revisao-dossie" && pendingReviews ? "Revisor de precificacao" : "Gestor de precificacao" } };
}

function normalizeStage(value: SearchParams["etapa"], fallback: WorkflowStageId): WorkflowStageId {
  return typeof value === "string" && WORKFLOW_STAGE_IDS.includes(value as WorkflowStageId) ? value as WorkflowStageId : fallback;
}

function WorkspaceHeader({ facts }: { facts: { policies: number; scenarios: number; calculations: number } }) { return <header className={styles.heading}><div><span className="eyebrow">Precificacao</span><h1>Formacao de custos e precos</h1><p>Organize a base de custo, a politica comercial e a memoria de calculo em um fluxo objetivo.</p></div><dl className={styles.headerFacts}><div><dt>Politicas</dt><dd>{facts.policies}</dd></div><div><dt>Cenarios</dt><dd>{facts.scenarios}</dd></div><div><dt>Calculos</dt><dd>{facts.calculations}</dd></div></dl></header>; }
function WorkflowStepper({ stages, selectedStage, currentStage }: { stages: Array<{ id: WorkflowStageId; title: string; label: string; state: StageState }>; selectedStage: WorkflowStageId; currentStage: WorkflowStageId }) { return <nav className={styles.workflowStepper} aria-label="Etapas da formacao de custos e precos"><ol>{stages.map((stage, index) => <li key={stage.id} data-state={stage.state}><a href={`/custos-precos?etapa=${stage.id}`} aria-current={stage.id === selectedStage ? "step" : undefined}><span className={styles.stepNumber}>{index + 1}</span><span><strong>{stage.title}</strong><small>{stage.label}</small>{stage.id === currentStage && stage.id !== selectedStage ? <em>Etapa atual do processo</em> : null}</span></a></li>)}</ol></nav>; }
function WorkflowContext({ current, selectedStage }: { current: { id: WorkflowStageId; title: string; label: string; detail: string; owner: string }; selectedStage: { id: WorkflowStageId; title: string; label: string } }) { return <aside className={styles.workspaceContext} aria-label="Contexto da etapa"><div><span>Etapa atual do processo</span><strong>{current.title}</strong></div><div><span>Proxima acao</span><strong>{current.detail}</strong></div><div><span>Responsavel</span><strong>{current.owner}</strong></div><div><span>Situacao</span><strong>{current.label}</strong></div>{selectedStage.id !== current.id ? <small>Voce esta consultando: {selectedStage.title}.</small> : <small>Fluxo governado.</small>}</aside>; }
function StageHeading({ stage, number }: { stage: { id: WorkflowStageId; title: string; description: string; label: string }; number: string }) { return <div className={styles.stageHeading}><div className={styles.stageTitle}><span>{number}</span><div><p className="eyebrow">Etapa selecionada</p><h2 id={`${stage.id}-title`}>{stage.title}</h2><p className={styles.stageDescription}>{stage.description}</p></div></div><span className="status-chip">{stage.label}</span></div>; }
function Permission() { return <div className="permission-state"><strong>Acao indisponivel</strong><span>Sua conta pode consultar, mas nao possui a alcada desta etapa.</span></div>; }
function Empty({ title, text }: { title: string; text: string }) { return <div className={styles.emptyState}><strong>{title}</strong><span>{text}</span></div>; }
function label(value: string) { return value === "margem_liquida" ? "Margem liquida" : "Markup"; }
function status(value: string) { return value === "APPROVED" ? "Aprovado" : value === "REJECTED" ? "Rejeitado" : "Aguardando revisao"; }
function money(value: number) { return new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL", minimumFractionDigits: 2 }).format(value); }
function percent(value: number) { return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 2 }).format(value) + "%"; }
function dateTime(value: string) { return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(value)); }
