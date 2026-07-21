import Link from "next/link";
import type { ReactNode } from "react";

type CatalogRoute = "overview" | "units" | "input-types" | "materials" | "packages" | "products";

const CATALOG_LINKS: Array<{ key: CatalogRoute; href: string; label: string }> = [
  { key: "overview", href: "/cadastros/tecnicos", label: "Visão geral" },
  { key: "units", href: "/cadastros/unidades", label: "Unidades" },
  { key: "input-types", href: "/cadastros/tipos-insumo", label: "Tipos de insumo" },
  { key: "materials", href: "/cadastros/materias-primas", label: "Matérias-primas" },
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

export function CatalogShell({ active, title, description, source, actions, children }: CatalogShellProps) {
  const activeLabel = CATALOG_LINKS.find((item) => item.key === active)?.label ?? "Cadastros técnicos";

  return (
    <main className="workspace technical-workspace">
        <nav className="catalog-tabs catalog-tabs-desktop" aria-label="Cadastros técnicos">
          {CATALOG_LINKS.map((item) => (
            <Link key={item.key} href={item.href} aria-current={active === item.key ? "page" : undefined}>
              {item.label}
            </Link>
          ))}
          <Link href="/producao/formulas">Fórmulas</Link>
        </nav>

        <details className="catalog-tabs-mobile">
          <summary>
            <span>Cadastros técnicos</span>
            <strong>{activeLabel}</strong>
          </summary>
          <nav className="catalog-tabs" aria-label="Cadastros técnicos">
            {CATALOG_LINKS.map((item) => (
              <Link key={item.key} href={item.href} aria-current={active === item.key ? "page" : undefined}>
                {item.label}
              </Link>
            ))}
            <Link href="/producao/formulas">Fórmulas</Link>
          </nav>
        </details>

        <div className="toolbar technical-toolbar">
          <div>
            <span className="eyebrow">Cadastros técnicos</span>
            <h1>{title}</h1>
            <p className="muted">{description}</p>
          </div>
          {actions ? <div className="toolbar-actions">{actions}</div> : null}
        </div>

        {source === "not_configured" ? (
          <div className="notice-panel warning" role="alert">
            <strong>Banco não configurado</strong>
            <span>Os catálogos técnicos ficam disponíveis quando o ambiente Supabase estiver ativo.</span>
          </div>
        ) : null}
        {source === "error" ? (
          <div className="notice-panel warning" role="alert">
            <strong>Não foi possível carregar os cadastros</strong>
            <span>Tente novamente. Se o problema continuar, acione o administrador do sistema.</span>
          </div>
        ) : null}

        {children}
    </main>
  );
}

const FEEDBACK: Record<string, { kind: "ok" | "warning"; title: string; detail: string }> = {
  mp_created: { kind: "ok", title: "Matéria-prima salva", detail: "SKU, unidade e dados técnicos foram registrados." },
  mp_identity_updated: { kind: "ok", title: "Identidade atualizada", detail: "Nome e tipo foram auditados." },
  mp_sku_updated: { kind: "ok", title: "SKU atualizado", detail: "A troca do código operacional foi auditada." },
  mp_technical_updated: { kind: "ok", title: "Dados técnicos atualizados", detail: "Unidade e densidade foram auditadas." },
  mp_stock_policy_updated: { kind: "ok", title: "Política de estoque atualizada", detail: "O estoque mínimo foi registrado." },
  mp_regulatory_updated: { kind: "ok", title: "Dados regulatórios atualizados", detail: "NCM, IBAMA e ADS foram auditados." },
  mp_deactivated: { kind: "ok", title: "Matéria-prima desativada", detail: "O histórico foi preservado." },
  input_type_created: { kind: "ok", title: "Tipo de insumo criado", detail: "O registro foi salvo e auditado." },
  input_type_updated: { kind: "ok", title: "Tipo de insumo atualizado", detail: "As alterações foram registradas no histórico." },
  input_type_activated: { kind: "ok", title: "Tipo de insumo ativado", detail: "O tipo voltou a ficar disponível para novas classificações." },
  input_type_deactivated: { kind: "ok", title: "Tipo de insumo inativado", detail: "Vínculos históricos foram preservados." },
  material_input_type_saved: { kind: "ok", title: "Classificação atualizada", detail: "O tipo de insumo da matéria-prima foi registrado." },
  produto_created: { kind: "ok", title: "Produto salvo", detail: "O produto-base está disponível para fórmulas e embalagens." },
  produto_identity_updated: { kind: "ok", title: "Identidade atualizada", detail: "Código, nome e grupo foram registrados na auditoria." },
  produto_technical_updated: { kind: "ok", title: "Dados técnicos atualizados", detail: "Densidade e validade foram registradas." },
  produto_regulatory_updated: { kind: "ok", title: "Dados regulatórios atualizados", detail: "MAPA, NCM, IBAMA e ADS foram registrados." },
  produto_deactivated: { kind: "ok", title: "Produto desativado", detail: "O histórico e as apresentações anteriores foram preservados." },
  produto_reactivated: { kind: "ok", title: "Produto reativado", detail: "O produto voltou a ficar disponível para novas operações." },
  embalagem_created: { kind: "ok", title: "Embalagem salva", detail: "A embalagem foi registrada no catálogo técnico." },
  embalagem_identity_updated: { kind: "ok", title: "Identidade atualizada", detail: "A descrição foi alterada sem perder o histórico." },
  embalagem_physical_updated: { kind: "ok", title: "Capacidade atualizada", detail: "Unidade, volume e controle de estoque foram registrados." },
  embalagem_deactivated: { kind: "ok", title: "Embalagem desativada", detail: "Composições e usos históricos foram preservados." },
  embalagem_reactivated: { kind: "ok", title: "Embalagem reativada", detail: "A embalagem voltou ao catálogo operacional." },
  apresentacao_deactivated: { kind: "ok", title: "Apresentação desativada", detail: "Pedidos anteriores continuam rastreáveis." },
  apresentacao_reactivated: { kind: "ok", title: "Apresentação reativada", detail: "Produto e embalagem ativos permitem novo uso comercial." },
  embalagem_version_created: { kind: "ok", title: "Nova versão criada", detail: "A necessidade da embalagem foi normalizada em UN/L." },
  embalagem_component_added: { kind: "ok", title: "Componente adicionado", detail: "A quantidade por litro foi registrada na versão em revisão." },
  embalagem_component_removed: { kind: "ok", title: "Componente removido", detail: "A decisão foi auditada sem apagar o registro." },
  embalagem_version_approved: { kind: "ok", title: "Versão aprovada", detail: "A composição está pronta para ativação." },
  embalagem_version_rejected: { kind: "ok", title: "Versão rejeitada", detail: "O histórico da revisão foi preservado." },
  embalagem_version_activated: { kind: "ok", title: "Versão ativada", detail: "Esta composição passa a ser a referência atual." },
  embalagem_version_deactivated: { kind: "ok", title: "Versão desativada", detail: "A composição permanece no histórico." },
  item_vendavel_created: { kind: "ok", title: "Item vendável salvo", detail: "Produto e embalagem foram vinculados." },
  apresentacao_logistics_updated: { kind: "ok", title: "Volumes configurados", detail: "A apresentação já pode calcular volumes logísticos no romaneio." },
  conversion_created: { kind: "ok", title: "Conversão salva", detail: "A regra de unidade foi registrada com vigência." },
  duplicated: { kind: "warning", title: "Registro duplicado", detail: "Já existe um cadastro com a mesma chave." },
  not_allowed: { kind: "warning", title: "Sem alçada", detail: "O usuário atual não possui a permissão exigida." },
  not_configured: { kind: "warning", title: "Ambiente indisponível", detail: "O Supabase não está configurado neste ambiente." },
  missing_mp_required: { kind: "warning", title: "Campos obrigatórios", detail: "Informe MP, nome, SKU, unidade e motivo quando solicitado." },
  missing_product_required: { kind: "warning", title: "Campos obrigatorios", detail: "Informe codigo e nome do produto." },
  missing_package_required: { kind: "warning", title: "Campos obrigatorios", detail: "Informe descricao e unidade da embalagem." },
  missing_package_stock_item: { kind: "warning", title: "MP obrigatoria", detail: "Embalagem com estoque deve estar vinculada a uma MP." },
  missing_sale_item_required: { kind: "warning", title: "Campos obrigatorios", detail: "Informe produto, embalagem e codigo do item." },
  missing_conversion_required: { kind: "warning", title: "Campos obrigatorios", detail: "Informe MP, unidades e fator." },
  invalid_positive_number: { kind: "warning", title: "Valor inválido", detail: "Use um número maior que zero." },
  invalid_non_negative_number: { kind: "warning", title: "Valor inválido", detail: "Use zero ou um número positivo." },
  invalid_ncm: { kind: "warning", title: "NCM inválido", detail: "O NCM deve ter oito dígitos." },
  invalid_sku: { kind: "warning", title: "SKU inválido", detail: "O SKU não pode conter espaços." },
  invalid_input_type: { kind: "warning", title: "Tipo indisponível", detail: "Selecione um tipo de insumo ativo." },
  invalid_value: { kind: "warning", title: "Valor inválido", detail: "Revise os campos informados." },
  not_found: { kind: "warning", title: "Registro não encontrado", detail: "Atualize a página e tente novamente." },
  operation_failed: { kind: "warning", title: "Operação não concluída", detail: "Não foi possível salvar. Tente novamente ou acione o administrador." },
  invalid_unit_conversion: { kind: "warning", title: "Conversão inválida", detail: "Origem e destino devem ser diferentes." },
  invalid_date_range: { kind: "warning", title: "Vigência inválida", detail: "A data final não pode ser anterior à inicial." },
  missing_product_maintenance: { kind: "warning", title: "Dados incompletos", detail: "Informe código, nome e motivo da alteração." },
  invalid_product_maintenance: { kind: "warning", title: "Dados técnicos inválidos", detail: "Revise densidade, validade e motivo." },
  missing_package_maintenance: { kind: "warning", title: "Dados incompletos", detail: "Informe descrição e motivo da alteração." },
  invalid_package_maintenance: { kind: "warning", title: "Capacidade inválida", detail: "Use unidade UN, capacidade positiva e MP quando controlar estoque." },
  invalid_component_un_l: { kind: "warning", title: "Quantidade inválida", detail: "Informe componente, quantidade UN/L positiva e motivo." },
  invalid_review: { kind: "warning", title: "Revisão inválida", detail: "Selecione uma decisão e informe o motivo." },
  missing_reason: { kind: "warning", title: "Motivo obrigatório", detail: "Explique por que esta alteração está sendo realizada." }
};

export function CatalogFeedback({ result }: { result: string | null }) {
  if (!result) return null;
  const feedback = FEEDBACK[result] ?? {
    kind: "warning" as const,
    title: "Operação não concluída",
    detail: "Não foi possível concluir a ação. Atualize a página e tente novamente."
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
    pending_review: "Em revisão",
    approved: "Aprovado",
    rejected: "Rejeitado"
  };
  return labels[value] ?? "Situação não reconhecida";
}

export function singleParam(value: string | string[] | undefined): string | null {
  if (Array.isArray(value)) return value[0] ?? null;
  return value ?? null;
}
