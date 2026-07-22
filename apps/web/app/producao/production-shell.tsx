import Link from "next/link";
import type { ReactNode } from "react";


export type ProductionRoute =
  | "overview"
  | "formulas"
  | "garantias"
  | "ordens"
  | "qualidade"
  | "envase"
  | "estoque"
  | "transformacoes"
  | "manual";

const PRODUCTION_LINKS: Array<{ key: ProductionRoute; href: string; label: string }> = [
  { key: "overview", href: "/producao", label: "Visao geral" },
  { key: "formulas", href: "/producao/formulas", label: "Formulas" },
  { key: "garantias", href: "/producao/garantias", label: "Garantias" },
  { key: "ordens", href: "/producao/ordens", label: "Ordens" },
  { key: "qualidade", href: "/producao/qualidade", label: "CQ e finalizacao" },
  { key: "envase", href: "/producao/envase", label: "OP MAPA e envase" },
  { key: "estoque", href: "/producao/estoque", label: "Lotes e estoque" },
  { key: "transformacoes", href: "/producao/transformacoes", label: "Transformacoes" },
  { key: "manual", href: "/producao/manual", label: "Como operar" }
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
  return (
    <main className="app-shell">
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
  mp_lot_parameters_registered: { kind: "ok", title: "Base física registrada", detail: "A densidade vigente do lote foi versionada e auditada." },
  op_created: { kind: "ok", title: "OP aberta", detail: "Componentes planejados foram copiados da formula vigente." },
  component_reserved_fifo: { kind: "ok", title: "Reserva FIFO concluida", detail: "A necessidade foi distribuida pelos lotes mais antigos disponiveis." },
  fifo_override_requires_justification: { kind: "warning", title: "Justificativa obrigatoria", detail: "Para ignorar um lote mais antigo, informe o motivo e tenha a alcada especifica." },
  legacy_formula_requires_review: { kind: "warning", title: "Formula antiga nao revisada", detail: "Crie e ative uma nova versao operacional na base de 1 litro antes de abrir a OP." },
  invalid_formula_unit: { kind: "warning", title: "Unidade invalida", detail: "Use kg/L produzido, L/L produzido ou UN/L produzido na formula operacional." },
  component_reserved: { kind: "ok", title: "Lote reservado", detail: "A reserva reduziu o saldo disponivel sem baixar o saldo fisico." },
  op_started: { kind: "ok", title: "OP iniciada", detail: "A ordem passou para execucao industrial." },
  op_cancelled: { kind: "ok", title: "OP cancelada", detail: "As reservas relacionadas foram tratadas pelo fluxo auditado." },
  op_finished: { kind: "ok", title: "OP finalizada", detail: "Consumos, CQ e lotes gerados foram gravados na mesma transacao." },
  packaging_order_issued: { kind: "ok", title: "Ordem emitida", detail: "A OP MAPA e a Ordem de Envase foram emitidas juntas." },
  packaging_reserved: { kind: "ok", title: "Embalagem reservada", detail: "O lote foi reservado para esta Ordem de Envase." },
  packaging_started: { kind: "ok", title: "Envase iniciado", detail: "A ordem passou para execucao operacional." },
  packaging_finished: { kind: "ok", title: "Envase finalizado", detail: "PI e embalagens foram baixados e o lote PA foi criado." },
  missing_packaging_issue: { kind: "warning", title: "Emissao incompleta", detail: "Informe formula MAPA, lote PI, apresentacao e volume." },
  missing_packaging_reservation: { kind: "warning", title: "Reserva incompleta", detail: "Informe ordem, componente, lote e quantidade." },
  missing_packaging_outputs: { kind: "warning", title: "Lotes PA obrigatorios", detail: "Informe ao menos um lote PA e distribua toda a quantidade planejada." },
  operation_failed: { kind: "warning", title: "Operação não concluída", detail: "Revise os dados e a situação atual da ordem. Nenhum movimento parcial foi mantido." },
  guarantees_calculated: { kind: "ok", title: "Garantias calculadas", detail: "O resultado foi versionado a partir dos lotes efetivamente consumidos." },
  blocked_lot_released: { kind: "ok", title: "Lote liberado", detail: "A decisao foi registrada com autor, motivo e estado anterior e posterior." },
  not_allowed: { kind: "warning", title: "Sem alcada", detail: "O usuario atual nao possui a permissao exigida." },
  not_configured: { kind: "warning", title: "Ambiente indisponivel", detail: "O Supabase nao esta configurado neste ambiente." },
  missing_formula_required: { kind: "warning", title: "Campos obrigatorios", detail: "Informe produto, tipo e justificativa." },
  invalid_formula_type: { kind: "warning", title: "Tipo invalido", detail: "Use formula de producao ou MAPA documental." },
  missing_formula_components: { kind: "warning", title: "Componentes obrigatorios", detail: "Formula de producao exige ao menos um componente." },
  invalid_component_row: { kind: "warning", title: "Componente invalido", detail: "Revise tipo, item, quantidade e unidade do componente." },
  missing_activation_required: { kind: "warning", title: "Ativacao incompleta", detail: "Informe a formula e o motivo da ativacao." },
  missing_guarantee_required: { kind: "warning", title: "Campos obrigatorios", detail: "Preencha item, nutriente, valor, unidade e justificativa." },
  missing_lot_parameters: { kind: "warning", title: "Base física incompleta", detail: "Informe lote, densidade, data de referência e justificativa." },
  invalid_guarantee_type: { kind: "warning", title: "Classificacao invalida", detail: "Revise limite ou fonte da garantia." },
  missing_guarantee_document: { kind: "warning", title: "Documento obrigatorio", detail: "Informe o documento exigido para esta origem." },
  invalid_guarantee_range: { kind: "warning", title: "Faixa invalida", detail: "O valor maximo deve ser igual ou maior que o minimo." },
  missing_op_required: { kind: "warning", title: "OP incompleta", detail: "Informe a formula ou a ordem exigida pela operacao." },
  invalid_op_type: { kind: "warning", title: "Tipo de OP invalido", detail: "Selecione um tipo de ordem previsto no processo." },
  missing_reservation_required: { kind: "warning", title: "Reserva incompleta", detail: "Informe componente, lote e quantidade." },
  invalid_component_type: { kind: "warning", title: "Componente invalido", detail: "A reserva aceita somente MP, PA ou PI." },
  invalid_positive_number: { kind: "warning", title: "Quantidade invalida", detail: "Informe um numero maior que zero." },
  missing_cancel_required: { kind: "warning", title: "Cancelamento incompleto", detail: "Informe a OP e o motivo do cancelamento." },
  missing_finish_required: { kind: "warning", title: "Finalizacao incompleta", detail: "Informe OP, separador, conferente e ao menos um formulador." },
  invalid_cq_status: { kind: "warning", title: "Resultado de CQ invalido", detail: "Use aprovado, bloqueado ou reprovado." },
  missing_cq_numbers: { kind: "warning", title: "Dados de processo incompletos", detail: "Informe pH, densidade, volume, massa e temperatura." },
  missing_outputs: { kind: "warning", title: "Produto gerado obrigatório", detail: "Informe o único lote PI gerado pela OP." },
  single_output_required: { kind: "warning", title: "Uma unica saida", detail: "Cada OP gera exatamente um lote de um unico produto." },
  missing_release_required: { kind: "warning", title: "Liberacao incompleta", detail: "Informe um lote PA ou PI bloqueado e o motivo da liberacao." },
  invalid_participants: { kind: "warning", title: "Participantes invalidos", detail: "Separador, conferente e formuladores devem estar ativos." },
  invalid_output_row: { kind: "warning", title: "Saida invalida", detail: "Revise tipo, produto e quantidade da saida." },
  missing_guarantee_calculation: { kind: "warning", title: "Calculo incompleto", detail: "Informe a OP e a justificativa do calculo." },
  invalid_historical_review: { kind: "warning", title: "Revisao incompleta", detail: "Escolha uma decisao e informe uma justificativa com pelo menos 10 caracteres." },
  missing_historical_catalogs: { kind: "warning", title: "Classificacao incompleta", detail: "Para classificar, selecione o nutriente e as duas unidades governadas." },
  historical_guarantee_reviewed: { kind: "ok", title: "Revisao registrada", detail: "A classificacao historica foi auditada sem criar garantia operacional." }
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
