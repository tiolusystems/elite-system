import Link from "next/link";
import type { ReactNode } from "react";

import { getRuntimeStatus } from "@/lib/runtime";

export type ProductionRoute = "overview" | "formulas" | "garantias" | "ordens" | "qualidade" | "estoque";

const PRODUCTION_LINKS: Array<{ key: ProductionRoute; href: string; label: string }> = [
  { key: "overview", href: "/producao", label: "Visao geral" },
  { key: "formulas", href: "/producao/formulas", label: "Formulas" },
  { key: "garantias", href: "/producao/garantias", label: "Garantias" },
  { key: "ordens", href: "/producao/ordens", label: "Ordens" },
  { key: "qualidade", href: "/pcp#ops", label: "CQ e finalizacao" },
  { key: "estoque", href: "/pcp#lotes", label: "Lotes e transformacoes" }
];

type ProductionShellProps = {
  active: ProductionRoute;
  title: string;
  description: string;
  source: "supabase" | "not_configured" | "error";
  error: string | null;
  actions?: ReactNode;
  children: ReactNode;
};

export function ProductionShell({
  active,
  title,
  description,
  source,
  error,
  actions,
  children
}: ProductionShellProps) {
  const runtime = getRuntimeStatus();

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <strong>Elite System</strong>
          <span>Producao</span>
        </div>
        <nav className="topnav" aria-label="Modulos principais">
          <Link href="/">Inicio</Link>
          <Link href="/modulos">Modulos</Link>
          <Link href="/cadastros">Cadastros</Link>
          <Link href="/pedidos">Pedidos</Link>
          <Link href="/producao" aria-current="page">Producao</Link>
          <Link href="/romaneios">Romaneio</Link>
          <Link href="/relatorios">Relatorios</Link>
          <Link href="/seguranca">Seguranca</Link>
        </nav>
      </header>

      <aside className={`db-banner ${runtime.isOperationalDatabase ? "operational" : ""}`}>
        <strong>{runtime.databaseLabel}</strong>
        <span>{runtime.databaseWarning}</span>
        <span className="pill">{runtime.databaseMode}</span>
      </aside>

      <section className="workspace technical-workspace production-workspace">
        <nav className="catalog-tabs production-tabs" aria-label="Areas de Producao">
          {PRODUCTION_LINKS.map((item) => (
            <Link key={item.key} href={item.href} aria-current={active === item.key ? "page" : undefined}>
              {item.label}
            </Link>
          ))}
        </nav>

        <div className="toolbar technical-toolbar">
          <div>
            <span className="eyebrow">Operacao industrial</span>
            <h1>{title}</h1>
            <p className="muted">{description}</p>
          </div>
          {actions ? <div className="toolbar-actions">{actions}</div> : null}
        </div>

        {source === "not_configured" ? (
          <div className="notice-panel warning">
            <strong>Banco nao configurado</strong>
            <span>O modulo de Producao fica disponivel quando o ambiente Supabase estiver ativo.</span>
          </div>
        ) : null}
        {source === "error" ? (
          <div className="notice-panel warning">
            <strong>Falha ao carregar Producao</strong>
            <span>{error ?? "Nao foi possivel consultar o banco."}</span>
          </div>
        ) : null}

        {children}
      </section>
    </main>
  );
}

const FEEDBACK: Record<string, { kind: "ok" | "warning"; title: string; detail: string }> = {
  formula_created: { kind: "ok", title: "Formula criada", detail: "A nova versao foi registrada sem alterar o historico." },
  formula_activated: { kind: "ok", title: "Formula ativada", detail: "A versao passou a ser a referencia vigente." },
  product_guarantee_registered: { kind: "ok", title: "Garantia registrada", detail: "A versao declarada do produto foi salva." },
  mp_lot_guarantee_registered: { kind: "ok", title: "Analise registrada", detail: "A garantia do lote de materia-prima foi salva." },
  op_created: { kind: "ok", title: "OP aberta", detail: "Componentes planejados foram copiados da formula vigente." },
  component_reserved: { kind: "ok", title: "Lote reservado", detail: "A reserva reduziu o saldo disponivel sem baixar o saldo fisico." },
  op_started: { kind: "ok", title: "OP iniciada", detail: "A ordem passou para execucao industrial." },
  op_cancelled: { kind: "ok", title: "OP cancelada", detail: "As reservas relacionadas foram tratadas pelo fluxo auditado." },
  not_allowed: { kind: "warning", title: "Sem alcada", detail: "O usuario atual nao possui a permissao exigida." },
  not_configured: { kind: "warning", title: "Ambiente indisponivel", detail: "O Supabase nao esta configurado neste ambiente." },
  missing_formula_required: { kind: "warning", title: "Campos obrigatorios", detail: "Informe produto, tipo e justificativa." },
  invalid_formula_type: { kind: "warning", title: "Tipo invalido", detail: "Use formula de producao ou MAPA documental." },
  missing_formula_components: { kind: "warning", title: "Componentes obrigatorios", detail: "Formula de producao exige ao menos um componente." },
  invalid_component_row: { kind: "warning", title: "Componente invalido", detail: "Revise tipo, item, quantidade e unidade do componente." },
  missing_activation_required: { kind: "warning", title: "Ativacao incompleta", detail: "Informe a formula e o motivo da ativacao." },
  missing_guarantee_required: { kind: "warning", title: "Campos obrigatorios", detail: "Preencha item, nutriente, valor, unidade e justificativa." },
  invalid_guarantee_type: { kind: "warning", title: "Classificacao invalida", detail: "Revise limite ou fonte da garantia." },
  missing_guarantee_document: { kind: "warning", title: "Documento obrigatorio", detail: "Informe o documento exigido para esta origem." },
  invalid_guarantee_range: { kind: "warning", title: "Faixa invalida", detail: "O valor maximo deve ser igual ou maior que o minimo." },
  missing_op_required: { kind: "warning", title: "OP incompleta", detail: "Informe a formula ou a ordem exigida pela operacao." },
  invalid_op_type: { kind: "warning", title: "Tipo de OP invalido", detail: "Selecione um tipo de ordem previsto no processo." },
  missing_reservation_required: { kind: "warning", title: "Reserva incompleta", detail: "Informe componente, lote e quantidade." },
  invalid_component_type: { kind: "warning", title: "Componente invalido", detail: "A reserva aceita somente MP, PA ou PI." },
  invalid_positive_number: { kind: "warning", title: "Quantidade invalida", detail: "Informe um numero maior que zero." },
  missing_cancel_required: { kind: "warning", title: "Cancelamento incompleto", detail: "Informe a OP e o motivo do cancelamento." }
};

export function ProductionFeedback({ result }: { result: string | null }) {
  if (!result) return null;
  const feedback = FEEDBACK[result] ?? {
    kind: "warning" as const,
    title: "Operacao nao concluida",
    detail: `Codigo retornado: ${result}`
  };

  return (
    <div className={`notice-panel ${feedback.kind === "ok" ? "ok" : "warning"}`} role="status">
      <strong>{feedback.title}</strong>
      <span>{feedback.detail}</span>
    </div>
  );
}

export function singleProductionParam(value: string | string[] | undefined): string | null {
  if (Array.isArray(value)) return value[0] ?? null;
  return value ?? null;
}
