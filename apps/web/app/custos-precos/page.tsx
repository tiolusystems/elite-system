import { redirect } from "next/navigation";

import { PricingCalculationForm, PricingPolicyForm, PricingReviewForm, PricingScenarioForm } from "./pricing-action-forms";
import { getPricingAccess, getPricingWorkspace } from "@/lib/cost-pricing";
import styles from "./pricing.module.css";

export default async function CostPricingPage() {
  const access = await getPricingAccess();
  if (!access.view) redirect("/modulo-indisponivel?module=precificacao&reason=permission");

  const workspace = await getPricingWorkspace();
  const data = workspace.data;
  if (!data) return <main className={styles.workspace}>
    <WorkspaceHeader />
    <section className={styles.band} aria-live="assertive"><div className="notice-panel warning" role="alert"><strong>Consulta indisponivel</strong><span>{workspace.error ?? "Nao foi possivel carregar a formacao de custos e precos."}</span></div></section>
  </main>;
  const approvedVersions = data?.politicas
    .flatMap((policy) => policy.versoes.map((version) => ({ ...version, policy })))
    .filter((version) => version.status === "APPROVED") ?? [];
  const calculations = data?.cenarios.flatMap((scenario) => scenario.calculos.map((calculation) => ({ ...calculation, scenario }))) ?? [];
  const pendingPolicyVersions = data?.politicas.flatMap((policy) => policy.versoes.filter((version) => version.status === "PENDING").map((version) => ({ ...version, policy }))) ?? [];
  const pendingCalculations = calculations.filter((calculation) => calculation.status === "PENDING");
  const approvedCalculations = calculations.filter((calculation) => calculation.status === "APPROVED");

  return <main className={styles.workspace}>
    <WorkspaceHeader />
    <section className={styles.summary} aria-label="Etapa atual"><div><span>Politicas</span><strong>{data?.politicas.length ?? 0}</strong></div><div><span>Cenarios</span><strong>{data?.cenarios.length ?? 0}</strong></div><div><span>Calculos</span><strong>{data?.cenarios.reduce((total, scenario) => total + scenario.calculos.length, 0) ?? 0}</strong></div><div><span>Publicacao comercial</span><strong>Fora desta etapa</strong></div></section>

    <nav className={styles.tabs} aria-label="Areas da formacao"><a href="#custos">Custos e referencias</a><a href="#cenarios">Cenarios</a><a href="#memoria">Memoria de calculo</a><a href="#revisao">Revisao e aprovacao</a><a href="#dossie">Dossie</a></nav>

    <section className={styles.band} id="custos"><div className={styles.sectionHeading}><div><h2>Custos e referencias</h2><p>A politica define o metodo e o arredondamento. Cada cenario congela a origem de todos os componentes.</p></div><span>Proximo responsavel: gestor de precificacao</span></div>
      {access.policy ? <PricingPolicyForm policies={data.politicas.map((policy) => ({ id: policy.id, label: `${policy.codigo} - ${policy.nome}` }))} /> : <Permission />}
    </section>

    <section className={styles.band} id="cenarios"><div className={styles.sectionHeading}><div><h2>Cenarios</h2><p>Substituicoes manuais afetam somente o novo cenario e nunca sobrescrevem custo, formula ou estoque.</p></div><span>11 componentes obrigatorios</span></div>
      {!access.scenario ? <Permission /> : !approvedVersions.length ? <Empty text="Aprove uma politica antes de congelar um cenario." /> : !data?.apresentacoes.length ? <Empty text="Cadastre uma apresentacao de produto antes de criar um cenario." /> : <PricingScenarioForm policies={approvedVersions.map((version) => ({ id: version.id, label: `${version.policy.codigo} - versao ${version.versao}` }))} presentations={data.apresentacoes.map((item) => ({ id: item.id, label: `${item.codigo} - ${item.produto} / ${item.apresentacao}` }))} />}
    </section>

    <section className={styles.band} id="memoria"><div className={styles.sectionHeading}><div><h2>Memoria de calculo</h2><p>O banco calcula o preco a vista, CMV, contribuicao e os 18 prazos. Valores ausentes bloqueiam o calculo.</p></div></div>
      {data?.cenarios.length ? <div className={styles.cards}>{data.cenarios.map((scenario) => <article key={scenario.id}><h3>{scenario.nome}</h3><p>{scenario.motivo}</p><span className="status-chip">{scenario.componentes.some((component) => component.source_kind === "substituicao_manual") ? "Possui substituicao manual" : "Fontes congeladas"}</span>{access.calculate ? <PricingCalculationForm scenarioId={scenario.id} /> : <Permission />}</article>)}</div> : <Empty text="Nenhum cenario congelado." />}
    </section>

    <section className={styles.band} id="revisao"><div className={styles.sectionHeading}><div><h2>Revisao e aprovacao</h2><p>Quem criou a politica, o cenario ou o calculo nao pode aprovar o proprio trabalho.</p></div><span>Segregacao obrigatoria</span></div><div className={styles.cards}>
      {!pendingPolicyVersions.length && !pendingCalculations.length ? <Empty text="Nenhuma politica ou calculo aguarda revisao." /> : null}
      {pendingPolicyVersions.map((version) => <article key={`p-${version.id}`}><h3>{version.policy.nome} - versao {version.versao}</h3><p>Metodo: {label(version.metodo)}</p>{access.policyReview ? <PricingReviewForm id={version.id} kind="policy" /> : <Permission />}</article>)}
      {pendingCalculations.map((calculation) => <article key={`c-${calculation.id}`}><h3>{calculation.scenario.nome}</h3><p>Preco a vista {money(calculation.preco_vista)}; calculo aguardando decisao.</p>{access.calculationReview ? <PricingReviewForm id={calculation.id} kind="calculation" /> : <Permission />}</article>)}
    </div></section>

    <section className={styles.band} id="dossie"><div className={styles.sectionHeading}><div><h2>Dossie</h2><p>Versoes, fontes, resultados e historico permanecem reproduziveis. O detalhe tecnico fica recolhido.</p></div></div>{calculations.length ? calculations.map((calculation) => <article className={styles.dossier} key={calculation.id}><div><h3>{calculation.scenario.nome}</h3><span className={`status-chip ${calculation.status === "APPROVED" ? "ativo" : ""}`}>{status(calculation.status)}</span></div><dl><div><dt>Preco a vista</dt><dd>{money(calculation.preco_vista)}</dd></div><div><dt>CMV</dt><dd>{percent(calculation.cmv_percentual)}</dd></div><div><dt>Contribuicao liquida</dt><dd>{money(calculation.contribuicao_liquida)}</dd></div><div><dt>Versao do calculo</dt><dd>{calculation.id}</dd></div></dl><div className={styles.terms}>{calculation.prazos.map((term) => <span key={term.prazo_dias}><small>{term.prazo_dias} dias</small><strong>{money(term.preco)}</strong></span>)}</div><details><summary>Detalhe de auditoria</summary><p>Registro calculado em {dateTime(calculation.calculated_at)}. Identificador tecnico {calculation.result_sha256.slice(0, 12)}.</p></details></article>) : <Empty text="Nenhuma memoria de calculo foi registrada." />}</section>
    <section className={styles.band} aria-label="Exportacoes aprovadas"><div className={styles.sectionHeading}><div><h2>Exportacoes aprovadas</h2><p>Os documentos sao gerados somente do snapshot imutavel aprovado.</p></div></div>{approvedCalculations.length ? approvedCalculations.map((calculation) => <div key={calculation.id} className={styles.exports}><a className="secondary-button" href={`/custos-precos/export/${calculation.id}/xlsx`}>Baixar XLSX</a><a className="secondary-button" href={`/custos-precos/export/${calculation.id}/pdf`}>Baixar PDF</a></div>) : <Empty text="As exportacoes ficam disponiveis depois da aprovacao do calculo." />}</section>
  </main>;
}

function WorkspaceHeader() { return <header className={styles.heading}><div><span className="eyebrow">Precificacao</span><h1>Formacao de custos e precos</h1><p>Construa cenarios auditaveis sem alterar custos reais, estoque ou listas comerciais.</p></div><span className="status-chip">Fundacao ISO</span></header>; }
function Permission() { return <div className="permission-state"><strong>Acao indisponivel</strong><span>Sua conta pode consultar, mas nao possui a alcada desta etapa.</span></div>; }
function Empty({ text }: { text: string }) { return <div className="empty-state"><strong>Nenhum registro</strong><span>{text}</span></div>; }
function label(value: string) { return value === "margem_liquida" ? "Margem liquida" : "Markup"; }
function status(value: string) { return value === "APPROVED" ? "Aprovado" : value === "REJECTED" ? "Rejeitado" : "Aguardando revisao"; }
function money(value: number) { return new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL", minimumFractionDigits: 2 }).format(value); }
function percent(value: number) { return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 2 }).format(value) + "%"; }
function dateTime(value: string) { return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(value)); }
