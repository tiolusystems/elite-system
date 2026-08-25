import { randomUUID } from "node:crypto";

import Link from "next/link";
import { redirect } from "next/navigation";

import { PriceListImportPanel } from "@/app/pedidos/listas-precos/price-list-import-panel";
import { getPriceListAccess, getPriceListAnalysis, getPriceListWorkspace } from "@/lib/price-lists";

import styles from "./price-lists.module.css";

type SearchParams = Record<string, string | string[] | undefined>;

export default async function PriceListsPage({ searchParams }: { searchParams?: Promise<SearchParams> }) {
  const params = searchParams ? await searchParams : {};
  const access = await getPriceListAccess();
  if (!access.view) redirect("/modulo-indisponivel?module=pedidos&reason=permission");
  const selectedAnalysisId = Number(single(params.analise) ?? 0);
  const [workspaceResult, analysisResult] = await Promise.all([
    getPriceListWorkspace(),
    selectedAnalysisId > 0 ? getPriceListAnalysis(selectedAnalysisId) : Promise.resolve({ data: null, error: null }),
  ]);
  const workspace = workspaceResult.data;
  const analysis = analysisResult.data;

  return (
    <main className={styles.workspace}>
      <header className={styles.heading}>
        <div>
          <span className="eyebrow">Comercial</span>
          <h1>Listas de precos</h1>
          <p>Importe, confira e publique versoes governadas sem substituir o historico comercial.</p>
        </div>
        {access.analyze ? <a className="secondary-button" href="/pedidos/listas-precos/modelo" download>Baixar modelo XLSX</a> : null}
      </header>

      {workspaceResult.error ? <div className="notice-panel warning" role="alert"><strong>Consulta indisponivel</strong><span>{workspaceResult.error}</span></div> : null}
      {analysisResult.error ? <div className="notice-panel warning" role="alert"><strong>Analise indisponivel</strong><span>{analysisResult.error}</span></div> : null}

      <section className={styles.metrics} aria-label="Resumo das listas">
        <Metric label="Listas cadastradas" value={workspace?.listas.length ?? 0} />
        <Metric label="Versoes publicadas" value={workspace?.listas.reduce((total, list) => total + list.versoes.filter((version) => version.situacao === "PUBLICADA" || version.situacao === "SUBSTITUIDA").length, 0) ?? 0} />
        <Metric label="Analises bloqueadas" value={workspace?.analises.filter((item) => item.status === "blocked").length ?? 0} />
        <Metric label="Analises prontas" value={workspace?.analises.filter((item) => item.status === "ready" && !item.publicacao_id).length ?? 0} />
      </section>

      <section className={styles.band} id="importar">
        <div className={styles.sectionHeading}>
          <div><h2>Importar nova versao</h2><p>Use o modelo oficial. O envio apenas analisa; nenhuma lista e publicada nesta etapa.</p></div>
          <span className="status-chip">XLSX ate 10 MB</span>
        </div>
        {access.analyze ? (
          <PriceListImportPanel
            analysis={analysis}
            analyzeRequestKey={randomUUID()}
            publishRequestKey={randomUUID()}
            canPublish={access.publish}
          />
        ) : (
          <div className="permission-state"><strong>Importacao indisponivel</strong><span>Sua conta pode consultar, mas nao possui alcada para analisar planilhas.</span></div>
        )}
      </section>

      <section className={styles.band} id="listas">
        <div className={styles.sectionHeading}><div><h2>Listas ativas e historico</h2><p>Cada publicacao permanece imutavel e a versao anterior continua consultavel.</p></div></div>
        {workspace?.listas.length ? <div className={styles.listTable}>
          <div className={styles.listHead}><span>Lista</span><span>Abrangencia</span><span>Vigencia</span><span>Versao</span><span>Situacao</span><span>Publicacao</span></div>
          {workspace.listas.flatMap((list) => list.versoes.map((version) => (
            <article key={`${list.codigo}-${version.numero}`}>
              <div><strong>{list.codigo}</strong><span>{list.nome}</span></div>
              <span>{list.descricao || "Abrangencia governada pelas regras da versao"}</span>
              <span>{date(version.vigencia_inicio)} a {version.vigencia_fim ? date(version.vigencia_fim) : "sem termino"}</span>
              <strong>v{version.numero}</strong>
              <span className={`status-chip ${version.situacao === "PUBLICADA" ? "ativo" : ""}`}>{situationLabel(version.situacao)}</span>
              <span>{version.published_at ? `${dateTime(version.published_at)}${version.published_by ? ` por ${version.published_by}` : ""}` : "Ainda nao publicada"}</span>
            </article>
          )))}</div> : <div className="empty-state"><strong>Nenhuma lista cadastrada</strong><span>Baixe o modelo e analise a primeira versao para iniciar o historico.</span></div>}
      </section>

      <section className={styles.band} id="analises">
        <div className={styles.sectionHeading}><div><h2>Analises recentes</h2><p>Retome uma conferencia sem reenviar a mesma planilha.</p></div></div>
        {workspace?.analises.length ? <div className={styles.analysisList}>{workspace.analises.map((item) => (
          <Link href={`/pedidos/listas-precos?analise=${item.id}#importar`} key={item.id}>
            <div><strong>{item.codigo_lista}</strong><span>{item.nome_lista}</span></div>
            <span>{item.total_linhas} linhas</span>
            <span>{item.linhas_aviso} avisos</span>
            <span>{item.linhas_erro} erros</span>
            <span className={`status-chip ${item.publicacao_id ? "ativo" : ""}`}>{item.publicacao_id ? "Publicada" : item.status === "ready" ? "Pronta" : "Bloqueada"}</span>
          </Link>
        ))}</div> : <div className="empty-state"><strong>Nenhuma analise registrada</strong><span>O historico de conferencias aparecera aqui.</span></div>}
      </section>
    </main>
  );
}

function Metric({ label, value }: { label: string; value: number }) {
  return <div><span>{label}</span><strong>{value}</strong></div>;
}

function single(value: string | string[] | undefined) { return Array.isArray(value) ? value[0] : value; }
function date(value: string) { return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(`${value}T12:00:00-03:00`)); }
function dateTime(value: string) { return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(value)); }
function situationLabel(value: string) { return ({ PUBLICADA: "Publicada", SUBSTITUIDA: "Substituida", RETIRADA: "Retirada", RASCUNHO: "Rascunho" } as Record<string, string>)[value] ?? value; }
