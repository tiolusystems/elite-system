import Link from "next/link";

import { ProductionShell } from "@/app/producao/production-shell";

const STEPS = [
  {
    title: "1. Conferir os cadastros",
    detail: "Confirme matéria-prima, unidade, produto PI/PA, apresentação e embalagem antes de criar receitas.",
    href: "/cadastros/tecnicos",
    action: "Abrir cadastros técnicos"
  },
  {
    title: "2. Registrar garantias",
    detail: "Cadastre a garantia declarada do produto e, quando houver laudo, a garantia analisada por lote de matéria-prima.",
    href: "/producao/garantias",
    action: "Abrir garantias"
  },
  {
    title: "3. Criar e ativar a fórmula de produção",
    detail: "A fórmula operacional orienta reserva e consumo de MP. Uma nova versão preserva todas as anteriores.",
    href: "/producao/formulas",
    action: "Abrir fórmulas"
  },
  {
    title: "4. Abrir a OP e reservar lotes",
    detail: "A OP copia os componentes da fórmula. A reserva reduz o disponível, mas ainda não baixa o saldo físico.",
    href: "/producao/ordens",
    action: "Abrir ordens"
  },
  {
    title: "5. Produzir, registrar CQ e finalizar",
    detail: "Informe processo, participantes e CQ. A finalização consome os lotes reservados e gera PI; reprovação mantém o lote bloqueado.",
    href: "/producao/qualidade",
    action: "Abrir CQ e finalização"
  },
  {
    title: "6. Emitir OP MAPA e Ordem de Envase",
    detail: "Depois da liberação do PI, a fórmula MAPA documental gera a Ordem de Envase. O envase consome PI e embalagens e cria o PA.",
    href: "/producao/envase",
    action: "Abrir OP MAPA e envase"
  },
  {
    title: "7. Conferir lotes e estoque",
    detail: "Valide saldos físicos, reservados e disponíveis por MP, PI e PA, preservando a rastreabilidade até a OP de origem.",
    href: "/producao/estoque",
    action: "Abrir lotes e estoque"
  }
];

export default function ProductionManualPage() {
  return (
    <ProductionShell
      active="manual"
      title="Como operar a Produção"
      description="Sequência operacional da matéria-prima ao produto acabado, com pontos de controle e rastreabilidade."
      source="supabase"
      error={null}
    >
      <section className="manual-steps" aria-label="Etapas da produção">
        {STEPS.map((step) => (
          <article className="panel manual-step" key={step.title}>
            <div>
              <h2>{step.title}</h2>
              <p>{step.detail}</p>
              <Link className="secondary-button" href={step.href}>{step.action}</Link>
            </div>
          </article>
        ))}
      </section>

      <section className="notice-panel warning">
        <strong>Dois fluxos, duas responsabilidades</strong>
        <span>A fórmula de produção movimenta MP e gera PI. A fórmula MAPA é documental e somente dispara a Ordem de Envase, que consome PI e embalagens para gerar PA.</span>
      </section>

      <section className="notice-panel ok">
        <strong>Regra de estoque</strong>
        <span>Reserva não baixa saldo físico. A baixa de MP acontece na finalização da OP; a baixa de PI e embalagens acontece na finalização do envase.</span>
      </section>
    </ProductionShell>
  );
}
