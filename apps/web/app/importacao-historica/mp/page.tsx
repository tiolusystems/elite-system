import Link from "next/link";

import { getRuntimeStatus } from "@/lib/runtime";

import { WorkbookAnalysisWorkspace } from "./workbook-analysis";

export const dynamic = "force-dynamic";

export default function HistoricalWorkbookPage() {
  const runtime = getRuntimeStatus();

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <strong>Elite System</strong>
          <span>Importação histórica</span>
        </div>
        <nav className="topnav" aria-label="Módulos principais">
          <Link href="/">Início</Link>
          <Link href="/modulos">Módulos</Link>
          <Link href="/cadastros">Cadastros</Link>
          <Link href="/importacao-xml">XML MP</Link>
          <Link href="/importacao-historica/mp" aria-current="page">Excel histórico</Link>
          <Link href="/producao">Produção</Link>
          <Link href="/relatorios">Relatórios</Link>
          <Link href="/seguranca">Segurança</Link>
        </nav>
      </header>

      <aside className={`db-banner ${runtime.isOperationalDatabase ? "operational" : ""}`}>
        <strong>{runtime.databaseLabel}</strong>
        <span>Análise local e somente leitura. O banco é usado apenas para validar a permissão do usuário.</span>
        <span className="pill">{runtime.databaseMode}</span>
      </aside>

      <WorkbookAnalysisWorkspace />
    </main>
  );
}
