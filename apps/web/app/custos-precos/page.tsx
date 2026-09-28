import { redirect } from "next/navigation";

import { PricingCalculationForm, PricingPolicyForm, PricingReviewForm, PricingScenarioForm } from "./pricing-action-forms";
import { getPricingAccess, getPricingWorkspace, type PricingWorkspace } from "@/lib/cost-pricing";
import styles from "./pricing.module.css";

type StageState = "available" | "waiting" | "approved" | "empty";

export default async function CostPricingPage() {
  const access = await getPricingAccess();
  if (!access.view) redirect("/modulo-indisponivel?module=precificacao&reason=permission");

  const workspace = await getPricingWorkspace();
  const data = workspace.data;
  if (!data) return <main className={styles.workspace}>
    <WorkspaceHeader />
    <section className={styles.band} aria-live="assertive"><div className="notice-panel warning" role="alert"><strong>Consulta indisponivel</strong><span>{workspace.error ?? "Nao foi possivel carregar a formacao de custos e precos."}</span></div></section>
  </main>;

  const approvedVersions = data.politicas.flatMap((policy) => policy.versoes.map((version) => ({ ...version, policy }))).filter((version) => version.status === "APPROVED");
  const calculations = data.cenarios.flatMap((scenario) => scenario.calculos.map((calculation) => ({ ...calculation, scenario })));
  const pendingPolicyVersions = data.politicas.flatMap((policy) => policy.versoes.filter((version) => version.status === "PENDING").map((version) => ({ ...version, policy })));
  const pendingCalculations = calculations.filter((calculation) => calculation.status === "PENDING");
  const approvedCalculations = calculations.filter((calculation) => calculation.status === "APPROVED");
  const workflow = buildWorkflow(data, approvedVersions.length, calculations.length, approvedCalculations.length, pendingPolicyVersions.length + pendingCalculations.length);

  return <main className={styles.workspace}>
    <WorkspaceHeader />
    <section className={styles.workspaceStatus} aria-label="Progresso da formacao de custos e precos">
      <div><span className="eyebrow">Etapa atual</span><strong>{workflow.current.title}</strong><p>{workflow.current.detail}</p></div>
      <div className={styles.workspaceStatusFacts}><span>Politicas <strong>{data.politicas.length}</strong></span><span>Cenarios <strong>{data.cenarios.length}</strong></span><span>Calculos <strong>{calculations.length}</strong></span></div>
    </section>

    <div className={styles.workspaceLayout}>
      <nav className={styles.workflowRail} aria-label="Etapas da formacao de custos e precos"><ol>{workflow.stages.map((stage, index) => <li key={stage.href} className={styles[`stage${stage.state}`]}><a href={stage.href} aria-current={stage.current ? "step" : undefined}><span>{index + 1}</span><strong>{stage.title}</strong><small>{stage.label}</small></a></li>)}</ol></nav>

      <div className={styles.workflowMain}>
        <section className={styles.workflowStage} id="base-custo" aria-labelledby="base-custo-title">
          <StageHeading id="base-custo-title" number="1" title="Produto e base de custo" description="O produto e a apresentacao definem o objeto da formacao. Custos e referencias permanecem rastreaveis em cada cenario." state="Disponivel no cenario" />
          <div className={styles.costBaseState}><div><span className="status-chip">Custo tecnico automatico ainda nao calculado</span><h3>Base de custo governada</h3><p>A composicao automatica por formula, valoracao e embalagem ainda nao esta disponivel no contrato atual. Enquanto isso, cada cenario usa substituicao manual governada, registrada com origem, data e justificativa.</p></div><dl><div><dt>Apresentacoes elegiveis</dt><dd>{data.apresentacoes.length}</dd></div><div><dt>Origem atual</dt><dd>Substituicao manual</dd></div></dl></div>
        </section>

        <section className={styles.workflowStage} id="politica" aria-labelledby="politica-title">
          <StageHeading id="politica-title" number="2" title="Politica comercial" description="Define metodo, margem ou markup, juros, versionamento e aprovacao antes do uso no cenario." state={approvedVersions.length ? "Politica aprovada disponivel" : data.politicas.length ? "Aguardando aprovacao" : "Aguardando criacao"} />
          {access.policy ? <PricingPolicyForm policies={data.politicas.map((policy) => ({ id: policy.id, label: `${policy.codigo} - ${policy.nome}` }))} /> : <Permission />}
        </section>

        <section className={styles.workflowStage} id="cenario" aria-labelledby="cenario-title">
          <StageHeading id="cenario-title" number="3" title="Cenario" description="Relaciona uma politica aprovada ao produto e apresentacao, congela a origem da base de custo e registra componentes comerciais." state={!approvedVersions.length ? "Depende de politica aprovada" : !data.apresentacoes.length ? "Depende de apresentacao cadastrada" : data.cenarios.length ? "Cenarios disponiveis" : "Pronto para criar"} />
          {!access.scenario ? <Permission /> : !approvedVersions.length ? <Empty text="Aprove uma politica antes de congelar um cenario." /> : !data.apresentacoes.length ? <Empty text="Cadastre uma apresentacao de produto antes de criar um cenario." /> : <PricingScenarioForm policies={approvedVersions.map((version) => ({ id: version.id, label: `${version.policy.codigo} - versao ${version.versao}` }))} presentations={data.apresentacoes.map((item) => ({ id: item.id, label: `${item.codigo} - ${item.produto} / ${item.apresentacao}` }))} />}
        </section>

        <section className={styles.workflowStage} id="precos-prazos" aria-labelledby="precos-prazos-title">
          <StageHeading id="precos-prazos-title" number="4" title="Precos e prazos" description="A memoria de calculo transforma o cenario congelado em preco a vista, CMV, contribuicao e os 18 prazos. Valores ausentes bloqueiam o calculo." state={!data.cenarios.length ? "Depende de cenario" : calculations.length ? "Memorias registradas" : "Pronto para calcular"} />
          {data.cenarios.length ? <div className={styles.calculationList}>{data.cenarios.map((scenario) => <article className={styles.calculationCard} key={scenario.id}><div><h3>{scenario.nome}</h3><p>{scenario.motivo}</p><span className="status-chip">{scenario.componentes.some((component) => component.source_kind === "substituicao_manual") ? "Base manual governada" : "Fontes congeladas"}</span></div>{access.calculate ? <PricingCalculationForm scenarioId={scenario.id} /> : <Permission />}</article>)}</div> : <Empty text="Nenhum cenario congelado." />}
          <div className={styles.priceResults} aria-label="Memoria de calculo">{calculations.length ? calculations.map((calculation) => <article className={styles.priceResult} key={calculation.id}><div className={styles.priceResultHeading}><div><h3>{calculation.scenario.nome}</h3><span className={`status-chip ${calculation.status === "APPROVED" ? "ativo" : ""}`}>{status(calculation.status)}</span></div><small>Memoria de calculo</small></div><dl><div><dt>Preco a vista</dt><dd>{money(calculation.preco_vista)}</dd></div><div><dt>CMV</dt><dd>{percent(calculation.cmv_percentual)}</dd></div><div><dt>Contribuicao liquida</dt><dd>{money(calculation.contribuicao_liquida)}</dd></div></dl><div className={styles.terms} aria-label="Precos por prazo">{calculation.prazos.map((term) => <span key={term.prazo_dias}><small>{term.prazo_dias} dias</small><strong>{money(term.preco)}</strong></span>)}</div></article>) : <Empty text="Nenhuma memoria de calculo foi registrada." />}</div>
        </section>

        <section className={styles.workflowStage} id="revisao-dossie" aria-labelledby="revisao-dossie-title">
          <StageHeading id="revisao-dossie-title" number="5" title="Revisao e dossie" description="Revisao e aprovacao sao segregadas. O historico e documentos preservam o que foi decidido sem transformar dados tecnicos em tela principal." state={pendingPolicyVersions.length || pendingCalculations.length ? "Pendencias para aprovacao" : approvedCalculations.length ? "Documentos aprovados disponiveis" : "Sem pendencias"} />
          <div className={styles.reviewDossierGrid}>
            <section className={styles.reviewPanel} aria-labelledby="pendencias-title"><h3 id="pendencias-title">Pendencias para aprovacao</h3><p>Quem criou a politica, o cenario ou o calculo nao pode aprovar o proprio trabalho.</p><div className={styles.cards}>{!pendingPolicyVersions.length && !pendingCalculations.length ? <Empty text="Nenhuma politica ou calculo aguarda revisao." /> : null}{pendingPolicyVersions.map((version) => <article key={`p-${version.id}`}><h4>{version.policy.nome} - versao {version.versao}</h4><p>Metodo: {label(version.metodo)}</p>{access.policyReview ? <PricingReviewForm id={version.id} kind="policy" /> : <Permission />}</article>)}{pendingCalculations.map((calculation) => <article key={`c-${calculation.id}`}><h4>{calculation.scenario.nome}</h4><p>Preco a vista {money(calculation.preco_vista)}; calculo aguardando decisao.</p>{access.calculationReview ? <PricingReviewForm id={calculation.id} kind="calculation" /> : <Permission />}</article>)}</div></section>
            <section className={styles.dossierPanel} aria-labelledby="dossie-title"><h3 id="dossie-title">Historico e documentos</h3><p>O dossie reune resultados aprovados, exportacoes e detalhe de auditoria recolhido.</p>{calculations.length ? calculations.map((calculation) => <article className={styles.dossier} key={calculation.id}><div><h4>{calculation.scenario.nome}</h4><span className={`status-chip ${calculation.status === "APPROVED" ? "ativo" : ""}`}>{status(calculation.status)}</span></div><details><summary>Detalhe de auditoria</summary><p>Registro calculado em {dateTime(calculation.calculated_at)}. Identificador tecnico {calculation.result_sha256.slice(0, 12)}.</p></details>{calculation.status === "APPROVED" ? <div className={styles.exports}><a className="secondary-button" href={`/custos-precos/export/${calculation.id}/xlsx`}>Baixar XLSX</a><a className="secondary-button" href={`/custos-precos/export/${calculation.id}/pdf`}>Baixar PDF</a></div> : null}</article>) : <Empty text="O dossie ficara disponivel quando houver memoria de calculo." />}</section>
          </div>
        </section>
      </div>

      <aside className={styles.workspaceContext} aria-label="Resumo do processo"><strong>Proximo responsavel</strong><span>{workflow.current.owner}</span><hr /><strong>Publicacao comercial</strong><span>Fora desta etapa</span><hr /><strong>Processo</strong><span>Governado e auditavel</span></aside>
    </div>
  </main>;
}

function buildWorkflow(data: PricingWorkspace, approvedVersions: number, calculations: number, approvedCalculations: number, pendingReviews: number) {
  const stages: Array<{ href: string; title: string; label: string; state: StageState; current: boolean }> = [
    { href: "#base-custo", title: "Produto e base de custo", label: "Contexto atual", state: data.apresentacoes.length ? "available" : "empty", current: false },
    { href: "#politica", title: "Politica comercial", label: approvedVersions ? "Aprovada" : data.politicas.length ? "Em revisao" : "Aguardando", state: approvedVersions ? "approved" : data.politicas.length ? "waiting" : "empty", current: false },
    { href: "#cenario", title: "Cenario", label: data.cenarios.length ? "Disponivel" : approvedVersions ? "Pronto" : "Dependente", state: data.cenarios.length ? "available" : approvedVersions ? "waiting" : "empty", current: false },
    { href: "#precos-prazos", title: "Precos e prazos", label: calculations ? "Registrados" : data.cenarios.length ? "Pronto" : "Dependente", state: calculations ? "available" : data.cenarios.length ? "waiting" : "empty", current: false },
    { href: "#revisao-dossie", title: "Revisao e dossie", label: pendingReviews ? "Pendente" : approvedCalculations ? "Aprovado" : "Sem pendencias", state: pendingReviews ? "waiting" : approvedCalculations ? "approved" : "empty", current: false },
  ];
  const current = stages.find((stage) => stage.state === "waiting") ?? stages.find((stage) => stage.state === "empty") ?? stages[4];
  current.current = true;
  const detail = current.href === "#base-custo" ? "Cadastre uma apresentacao para preparar o objeto da formacao." : current.href === "#politica" ? "Crie ou aprove uma politica comercial para seguir." : current.href === "#cenario" ? "Congele o cenario com a base manual governada." : current.href === "#precos-prazos" ? "Calcule a memoria para obter precos e prazos." : pendingReviews ? "Uma pessoa com alcada de revisao deve registrar a decisao." : "O processo nao possui pendencias de revisao.";
  const owner = current.href === "#base-custo" ? "Equipe de Cadastros" : current.href === "#revisao-dossie" && pendingReviews ? "Revisor de precificacao" : "Gestor de precificacao";
  return { stages, current: { ...current, detail, owner } };
}

function WorkspaceHeader() { return <header className={styles.heading}><div><span className="eyebrow">Precificacao</span><h1>Formacao de custos e precos</h1><p>Organize a base de custo, a politica comercial, o cenario e a memoria de calculo em um processo governado e auditavel.</p></div><span className="status-chip">Processo governado</span></header>; }
function StageHeading({ id, number, title, description, state }: { id: string; number: string; title: string; description: string; state: string }) { return <div className={styles.sectionHeading}><div className={styles.stageTitle}><span>{number}</span><div><h2 id={id}>{title}</h2><p>{description}</p></div></div><small>{state}</small></div>; }
function Permission() { return <div className="permission-state"><strong>Acao indisponivel</strong><span>Sua conta pode consultar, mas nao possui a alcada desta etapa.</span></div>; }
function Empty({ text }: { text: string }) { return <div className="empty-state"><strong>Nenhum registro</strong><span>{text}</span></div>; }
function label(value: string) { return value === "margem_liquida" ? "Margem liquida" : "Markup"; }
function status(value: string) { return value === "APPROVED" ? "Aprovado" : value === "REJECTED" ? "Rejeitado" : "Aguardando revisao"; }
function money(value: number) { return new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL", minimumFractionDigits: 2 }).format(value); }
function percent(value: number) { return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 2 }).format(value) + "%"; }
function dateTime(value: string) { return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(value)); }
