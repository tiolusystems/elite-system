import Link from "next/link";
import { redirect } from "next/navigation";

import { FinanceWorkspace } from "@/app/pedidos/financeiro/finance-workspace";
import { getFinanceAccess } from "@/lib/finance";
import { manualForPath, type RouteManual } from "@/lib/manuals";

const TOPICS = [
  { id: "visao-geral", icon: "👀", title: "Visão financeira", route: "/pedidos/financeiro" },
  { id: "comissionamento", icon: "🤝", title: "Comissionamento", route: "/pedidos/financeiro/comissionamento" },
  { id: "recebimentos", icon: "💰", title: "Recebimentos", route: "/pedidos/financeiro/recebimentos" },
  { id: "comissoes", icon: "🧾", title: "Comissões", route: "/pedidos/financeiro/comissoes" },
  { id: "relatorio", icon: "📊", title: "Relatório de comissões", route: "/pedidos/financeiro/comissoes/relatorio" },
] as const;

export default async function FinanceManualPage() {
  const access = await getFinanceAccess();
  if (!access.any) redirect("/modulo-indisponivel?module=financeiro&reason=permission");

  const topics = TOPICS.map((topic) => ({ ...topic, manual: requiredManual(topic.route) }));

  return (
    <FinanceWorkspace
      access={access}
      current="manual"
      eyebrow="Ajuda operacional"
      title="Como operar o Financeiro"
      description="Guia das telas financeiras, com sequência de trabalho, consequências de cada ação, bloqueios e registros gerados."
    >
      <section className="notice-panel warning" aria-labelledby="finance-manual-read-first">
        <strong id="finance-manual-read-first">⚠️ Leia antes de registrar movimentos</strong>
        <span>
          Consultar não altera valores. Definir comissão, registrar recebimento, pagar comissão e fazer ajuste
          são operações diferentes e geram fatos auditáveis. Confira pessoa, pedido, valor, data e referência antes de confirmar.
        </span>
      </section>

      <section className="panel" aria-labelledby="finance-manual-index-title">
        <div className="panel-header">
          <div>
            <span className="eyebrow">📍 Índice</span>
            <h2 id="finance-manual-index-title">Encontre a tela que você está usando</h2>
            <p className="muted">O botão “Ajuda desta tela” abre diretamente o assunto correspondente.</p>
          </div>
        </div>
        <div className="operation-card-grid finance-manual-index-grid">
          {topics.map((topic) => (
            <article className="operation-stage-card is-operational finance-manual-topic-card" key={topic.id}>
              <div className="finance-manual-topic-heading">
                <span className="finance-manual-topic-icon" aria-hidden="true">{topic.icon}</span>
                <h3>{topic.title}</h3>
              </div>
              <p className="finance-manual-topic-purpose">{topic.manual.purpose}</p>
              <a className="finance-manual-topic-link" href={`#${topic.id}`}>Ver como usar</a>
            </article>
          ))}
        </div>
      </section>

      <section className="panel" aria-labelledby="finance-manual-flow-title">
        <div className="panel-header">
          <div>
            <span className="eyebrow">➡️ Fluxo normal</span>
            <h2 id="finance-manual-flow-title">Da venda liberada ao pagamento da comissão</h2>
          </div>
        </div>
        <ol className="transformation-steps">
          <li><span>01</span><div><strong>Definir comissionamento</strong><small>Depois da liberação do pedido e antes do primeiro recebimento.</small></div></li>
          <li><span>02</span><div><strong>Registrar recebimento</strong><small>Confirme o valor efetivamente recebido e a referência documental. A comissão é liberada proporcionalmente.</small></div></li>
          <li><span>03</span><div><strong>Pagar comissão</strong><small>Abra a conta da pessoa, confira o saldo liberado e registre o pagamento até o valor disponível.</small></div></li>
        </ol>
      </section>

      {topics.map((topic) => (
        <ManualSection key={topic.id} id={topic.id} icon={topic.icon} title={topic.title} route={topic.route} manual={topic.manual} />
      ))}

      <section className="panel" id="problemas" aria-labelledby="finance-troubleshooting-title">
        <div className="panel-header">
          <div><span className="eyebrow">🆘 Ajuda rápida</span><h2 id="finance-troubleshooting-title">Problemas comuns</h2></div>
          <a className="text-link" href="#finance-manual-index-title">Voltar ao índice</a>
        </div>
        <div className="table-scroll">
          <table className="data-table">
            <thead><tr><th>O que aconteceu</th><th>O que verificar</th></tr></thead>
            <tbody>
              <tr><td>O pedido não aparece no comissionamento.</td><td>Confirme se está liberado e se ainda não recebeu nenhum valor.</td></tr>
              <tr><td>Não consigo registrar o recebimento.</td><td>Confira saldo aberto, valor, data, referência documental e sua alçada.</td></tr>
              <tr><td>O valor da comissão ainda não está liberado.</td><td>Comissão prevista não é saldo disponível. A liberação ocorre proporcionalmente ao recebimento registrado.</td></tr>
              <tr><td>Não consigo pagar toda a comissão prevista.</td><td>O pagamento usa o saldo efetivamente liberado da conta corrente, não apenas o valor previsto.</td></tr>
              <tr><td>Preciso corrigir uma comissão antiga.</td><td>Não altere o movimento anterior. Use ajuste excepcional somente com alçada e justificativa formal.</td></tr>
              <tr><td>O botão de uma operação não aparece.</td><td>As ações dependem de alçada individual e do estado atual do registro.</td></tr>
              <tr><td>Preciso trabalhar os dados no Excel.</td><td>No relatório, use Exportar → Excel (.xlsx). CSV permanece como alternativa técnica.</td></tr>
            </tbody>
          </table>
        </div>
      </section>

      <section className="notice-panel ok">
        <strong>✅ Regra final</strong>
        <span>
          Antes de confirmar uma operação financeira, confira o fato real e o documento que o comprova.
          O sistema preserva os movimentos anteriores e registra novos eventos para manter a trilha de auditoria.
        </span>
      </section>
    </FinanceWorkspace>
  );
}

function ManualSection({ id, icon, title, route, manual }: { id: string; icon: string; title: string; route: string; manual: RouteManual }) {
  return (
    <section className="panel" id={id} aria-labelledby={`${id}-title`}>
      <div className="panel-header finance-manual-panel-header">
        <div className="finance-manual-section-heading">
          <span className="finance-manual-section-icon" aria-hidden="true">{icon}</span>
          <div>
            <span className="eyebrow">Manual da tela</span>
            <h2 id={`${id}-title`}>{title}</h2>
          </div>
        </div>
        <a className="text-link" href="#finance-manual-index-title">Voltar ao índice</a>
      </div>
      <p><strong>Para que serve:</strong> {manual.purpose}</p>
      <div className="two-column">
        <ManualList title="Antes de começar" items={manual.before} />
        <ManualList title="O que acontece depois" items={manual.after} />
      </div>
      <h3>Como executar</h3>
      <ol className="transformation-steps">
        {manual.steps.map((step, index) => (
          <li key={step}><span>{String(index + 1).padStart(2, "0")}</span><div><strong>{step}</strong></div></li>
        ))}
      </ol>
      <div className="two-column">
        <ManualList title="Quem pode executar" items={manual.roles} />
        <ManualList title="Erros e bloqueios" items={manual.blockers} />
      </div>
      <ManualList title="Dados e histórico gerados" items={manual.records} />
      <div className="manual-route-actions"><Link className="secondary-button" href={route}>Abrir esta tela</Link></div>
    </section>
  );
}

function ManualList({ title, items }: { title: string; items: string[] }) {
  return <article className="panel"><h3>{title}</h3><ul>{items.map((item) => <li key={item}>{item}</li>)}</ul></article>;
}

function requiredManual(route: string): RouteManual {
  const manual = manualForPath(route);
  if (!manual || manual.route !== route) throw new Error(`Manual financeiro ausente para ${route}.`);
  return manual;
}
