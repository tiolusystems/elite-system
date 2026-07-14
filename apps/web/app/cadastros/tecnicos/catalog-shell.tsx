import Link from "next/link";
import type { ReactNode } from "react";

import { getRuntimeStatus } from "@/lib/runtime";

type CatalogRoute = "overview" | "units" | "materials" | "packages" | "products";

const CATALOG_LINKS: Array<{ key: CatalogRoute; href: string; label: string }> = [
  { key: "overview", href: "/cadastros/tecnicos", label: "Visao geral" },
  { key: "units", href: "/cadastros/unidades", label: "Unidades" },
  { key: "materials", href: "/cadastros/materias-primas", label: "Materias-primas" },
  { key: "packages", href: "/cadastros/embalagens", label: "Embalagens" },
  { key: "products", href: "/cadastros/produtos", label: "Produtos PA/PI" }
];

type CatalogShellProps = {
  active: CatalogRoute;
  title: string;
  description: string;
  source: "supabase" | "not_configured" | "error";
  error: string | null;
  actions?: ReactNode;
  children: ReactNode;
};

export function CatalogShell({ active, title, description, source, error, actions, children }: CatalogShellProps) {
  const runtime = getRuntimeStatus();

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <strong>Elite System</strong>
          <span>Cadastros tecnicos</span>
        </div>
        <nav className="topnav" aria-label="Modulos principais">
          <Link href="/">Inicio</Link>
          <Link href="/modulos">Modulos</Link>
          <Link href="/cadastros" aria-current="page">Cadastros</Link>
          <Link href="/pedidos">Pedidos</Link>
          <Link href="/producao">Producao</Link>
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

      <section className="workspace technical-workspace">
        <nav className="catalog-tabs" aria-label="Cadastros tecnicos">
          {CATALOG_LINKS.map((item) => (
            <Link key={item.key} href={item.href} aria-current={active === item.key ? "page" : undefined}>
              {item.label}
            </Link>
          ))}
          <Link href="/producao#formulas">Formulas e OP</Link>
        </nav>

        <div className="toolbar technical-toolbar">
          <div>
            <span className="eyebrow">Base industrial</span>
            <h1>{title}</h1>
            <p className="muted">{description}</p>
          </div>
          {actions ? <div className="toolbar-actions">{actions}</div> : null}
        </div>

        {source === "not_configured" ? (
          <div className="notice-panel warning">
            <strong>Banco nao configurado</strong>
            <span>Os catalogos tecnicos ficam disponiveis quando o ambiente Supabase estiver ativo.</span>
          </div>
        ) : null}
        {source === "error" ? (
          <div className="notice-panel warning">
            <strong>Falha ao carregar catalogos</strong>
            <span>{error ?? "Nao foi possivel consultar o banco."}</span>
          </div>
        ) : null}

        {children}
      </section>
    </main>
  );
}

const FEEDBACK: Record<string, { kind: "ok" | "warning"; title: string; detail: string }> = {
  mp_created: { kind: "ok", title: "Materia-prima salva", detail: "SKU, unidade e dados tecnicos foram registrados." },
  mp_identity_updated: { kind: "ok", title: "Identidade atualizada", detail: "Nome e tipo foram auditados." },
  mp_sku_updated: { kind: "ok", title: "SKU atualizado", detail: "A troca do codigo operacional foi auditada." },
  mp_technical_updated: { kind: "ok", title: "Dados tecnicos atualizados", detail: "Unidade e densidade foram auditadas." },
  mp_stock_policy_updated: { kind: "ok", title: "Politica de estoque atualizada", detail: "O estoque minimo foi registrado." },
  mp_regulatory_updated: { kind: "ok", title: "Dados regulatorios atualizados", detail: "NCM, IBAMA e ADS foram auditados." },
  mp_deactivated: { kind: "ok", title: "Materia-prima desativada", detail: "O historico foi preservado." },
  produto_created: { kind: "ok", title: "Produto salvo", detail: "O produto-base esta disponivel para formulas e embalagens." },
  embalagem_created: { kind: "ok", title: "Embalagem salva", detail: "A embalagem foi registrada no catalogo tecnico." },
  item_vendavel_created: { kind: "ok", title: "Item vendavel salvo", detail: "Produto e embalagem foram vinculados." },
  conversion_created: { kind: "ok", title: "Conversao salva", detail: "A regra de unidade foi registrada com vigencia." },
  duplicated: { kind: "warning", title: "Registro duplicado", detail: "Ja existe um cadastro com a mesma chave." },
  not_allowed: { kind: "warning", title: "Sem alcada", detail: "O usuario atual nao possui a permissao exigida." },
  not_configured: { kind: "warning", title: "Ambiente indisponivel", detail: "O Supabase nao esta configurado neste ambiente." },
  missing_mp_required: { kind: "warning", title: "Campos obrigatorios", detail: "Informe MP, nome, SKU, unidade e motivo quando solicitado." },
  missing_product_required: { kind: "warning", title: "Campos obrigatorios", detail: "Informe codigo e nome do produto." },
  missing_package_required: { kind: "warning", title: "Campos obrigatorios", detail: "Informe descricao e unidade da embalagem." },
  missing_package_stock_item: { kind: "warning", title: "MP obrigatoria", detail: "Embalagem com estoque deve estar vinculada a uma MP." },
  missing_sale_item_required: { kind: "warning", title: "Campos obrigatorios", detail: "Informe produto, embalagem e codigo do item." },
  missing_conversion_required: { kind: "warning", title: "Campos obrigatorios", detail: "Informe MP, unidades e fator." },
  invalid_positive_number: { kind: "warning", title: "Valor invalido", detail: "Use um numero maior que zero." },
  invalid_non_negative_number: { kind: "warning", title: "Valor invalido", detail: "Use zero ou um numero positivo." },
  invalid_ncm: { kind: "warning", title: "NCM invalido", detail: "O NCM deve ter oito digitos." },
  invalid_sku: { kind: "warning", title: "SKU invalido", detail: "O SKU nao pode conter espacos." },
  invalid_unit_conversion: { kind: "warning", title: "Conversao invalida", detail: "Origem e destino devem ser diferentes." },
  invalid_date_range: { kind: "warning", title: "Vigencia invalida", detail: "A data final nao pode ser anterior a inicial." }
};

export function CatalogFeedback({ result }: { result: string | null }) {
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

export function StatusChip({ value }: { value: string }) {
  return <span className={`status-chip ${value}`}>{statusLabel(value)}</span>;
}

function statusLabel(value: string): string {
  const labels: Record<string, string> = {
    active: "Ativo",
    inactive: "Inativo",
    pending_review: "Em revisao",
    approved: "Aprovado",
    rejected: "Rejeitado"
  };
  return labels[value] ?? value;
}

export function singleParam(value: string | string[] | undefined): string | null {
  if (Array.isArray(value)) return value[0] ?? null;
  return value ?? null;
}
