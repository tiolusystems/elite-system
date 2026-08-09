import Link from "next/link";
import type { ReactNode } from "react";

import { ProductionShell } from "@/app/producao/production-shell";

type ManualSectionProps = {
  id: string;
  icon: string;
  title: string;
  route: string;
  purpose: string;
  children: ReactNode;
};

type ManualStepProps = {
  number: number;
  title: string;
  children: ReactNode;
};

const ROUTES = [
  { href: "#visao-geral", icon: "👀", title: "Visão geral", route: "/producao" },
  { href: "#formulas", icon: "🧪", title: "Fórmulas", route: "/producao/formulas" },
  { href: "#garantias", icon: "📋", title: "Garantias", route: "/producao/garantias" },
  { href: "#ordens", icon: "🏭", title: "Ordens", route: "/producao/ordens" },
  { href: "#cq", icon: "✅", title: "CQ e finalização", route: "/producao/qualidade" },
  { href: "#envase", icon: "📦", title: "OP MAPA e envase", route: "/producao/envase" },
  { href: "#estoque", icon: "🗃️", title: "Lotes e estoque", route: "/producao/estoque" },
  { href: "#transformacoes", icon: "🔁", title: "Transformações", route: "/producao/transformacoes" },
  { href: "#impressoes", icon: "🖨️", title: "Impressões", route: "OP e Envase" },
  { href: "#problemas", icon: "🆘", title: "Problemas comuns", route: "O que verificar" }
];

export default function ProductionManualPage() {
  return (
    <ProductionShell
      active="manual"
      title="Manual operacional da Produção"
      description="Guia passo a passo para operar o módulo de Produção. Use este manual mesmo sem conhecimento prévio de PCP, estoque, fórmulas ou controle de qualidade."
      source="supabase"
      error={null}
    >
      <section className="notice-panel warning" aria-labelledby="manual-read-first">
        <strong id="manual-read-first">⚠️ Leia antes de operar</strong>
        <span>
          No Elite System, criar, ativar, reservar, iniciar, finalizar, liberar e cancelar são ações diferentes.
          Algumas ações mudam estoque e histórico. Leia o aviso da tela antes de confirmar.
        </span>
      </section>

      <section className="panel" aria-labelledby="manual-index-title">
        <div className="panel-header">
          <div>
            <span className="eyebrow">📍 Índice</span>
            <h2 id="manual-index-title">Encontre a tela que você está usando</h2>
            <p className="muted">Clique no assunto para abrir a explicação completa.</p>
          </div>
        </div>
        <div className="operation-card-grid">
          {ROUTES.map((item) => (
            <article className="operation-stage-card is-operational" key={item.href}>
              <h3>{item.icon} {item.title}</h3>
              <p>{item.route}</p>
              <a href={item.href}>Ver como usar</a>
            </article>
          ))}
        </div>
      </section>

      <section className="panel" aria-labelledby="manual-flow-title">
        <div className="panel-header">
          <div>
            <span className="eyebrow">➡️ Fluxo normal</span>
            <h2 id="manual-flow-title">Da matéria-prima ao produto acabado</h2>
          </div>
        </div>
        <ol className="transformation-steps">
          <li><span>01</span><div><strong>Cadastros e garantias</strong><small>Confira produtos, MPs, unidades, nutrientes, apresentações, garantias e densidades.</small></div></li>
          <li><span>02</span><div><strong>Fórmula</strong><small>Crie a versão, confira e depois ative a versão que deve valer.</small></div></li>
          <li><span>03</span><div><strong>OP</strong><small>Abra a ordem, confira o volume e reserve os lotes necessários.</small></div></li>
          <li><span>04</span><div><strong>Produção</strong><small>Inicie somente depois que todos os componentes estiverem reservados.</small></div></li>
          <li><span>05</span><div><strong>CQ e PI</strong><small>Registre processo, pessoas e CQ. A finalização gera o lote PI.</small></div></li>
          <li><span>06</span><div><strong>Envase e PA</strong><small>Use PI liberado, fórmula MAPA e embalagens para gerar o lote PA.</small></div></li>
          <li><span>07</span><div><strong>Estoque</strong><small>Consulte físico, reservado e disponível e preserve a rastreabilidade dos lotes.</small></div></li>
        </ol>
      </section>

      <ManualSection
        id="visao-geral"
        icon="👀"
        title="Visão geral"
        route="/producao"
        purpose="Mostrar para a supervisão onde existem pendências. Não é uma tela para lançar produção."
      >
        <h3>O que você vê</h3>
        <div className="operational-summary">
          <div><dt>OPs aguardando preparo</dt><dd>Ordens ainda em rascunho ou planejadas.</dd></div>
          <div><dt>Produções em andamento</dt><dd>OPs iniciadas que ainda precisam terminar ou passar pelo CQ.</dd></div>
          <div><dt>Componentes sem reserva</dt><dd>Itens da OP que ainda não têm lote reservado suficiente.</dd></div>
          <div><dt>Lotes bloqueados</dt><dd>Lotes que não podem ser usados até uma decisão técnica.</dd></div>
        </div>
        <div className="notice-panel ok">
          <strong>✅ O que fazer</strong>
          <span>Use os atalhos da tela para abrir Ordens, CQ ou Estoque. O número do indicador apenas mostra onde existe trabalho pendente.</span>
        </div>
        <p><strong>Se você não vê esta tela:</strong> provavelmente seu usuário não possui a alçada de supervisão. Isso pode ser normal.</p>
      </ManualSection>

      <ManualSection
        id="formulas"
        icon="🧪"
        title="Fórmulas"
        route="/producao/formulas"
        purpose="Criar e consultar versões de fórmulas de produção e fórmulas documentais MAPA."
      >
        <div className="notice-panel warning">
          <strong>⚠️ Criar versão NÃO é ativar versão</strong>
          <span>
            Quando você clica em Criar versão, a fórmula é salva, mas ainda não está valendo.
            Para usar a nova versão em produção, você precisa conferir os componentes e depois clicar em Ativar esta versão.
          </span>
        </div>

        <h3>🔎 Se a fórmula que você acabou de criar “sumiu”</h3>
        <p>
          A tela abre mostrando <strong>Somente vigentes</strong>. Uma versão nova e ainda não ativada não aparece nesse filtro.
          No campo <strong>Exibir</strong>, escolha <strong>Todas as versões</strong>. Depois abra <strong>Ver detalhes</strong>.
        </p>

        <h3>Produção operacional x Documentação MAPA</h3>
        <div className="two-column">
          <article className="panel">
            <h4>🏭 Produção operacional</h4>
            <p>É a receita usada pela fábrica.</p>
            <p>Representa os componentes necessários para produzir <strong>1 litro</strong>.</p>
            <p>A OP multiplica essas quantidades pelo volume planejado.</p>
          </article>
          <article className="panel">
            <h4>📄 Documentação MAPA</h4>
            <p>É a referência documental usada no fluxo MAPA/envase.</p>
            <p>Os componentes declarados são documentais.</p>
            <p>Essa fórmula não movimenta estoque sozinha.</p>
          </article>
        </div>

        <h3>Como criar uma fórmula</h3>
        <ManualStep number={1} title="Escolha o Produto PA ou PI">
          <p>Abra a lista e clique no produto correto. Não basta digitar o nome: selecione a opção da lista.</p>
        </ManualStep>
        <ManualStep number={2} title="Escolha a finalidade">
          <p>Use Produção operacional para receita de fábrica. Use Documentação MAPA apenas para o fluxo documental.</p>
        </ManualStep>
        <ManualStep number={3} title="Informe os componentes">
          <p>
            Primeiro escolha o Tipo: MP, PA ou PI. Depois escolha o Item, informe Quantidade e Unidade.
            Uma fórmula operacional aceita até 6 componentes exibidos.
          </p>
          <p>
            Para produção, use as unidades governadas por litro produzido: kg/L produzido, L/L produzido ou UN/L produzido.
          </p>
        </ManualStep>
        <ManualStep number={4} title="Escreva a justificativa">
          <p>Explique por que a versão está sendo criada. Evite textos genéricos como “ajuste” sem explicar o que mudou.</p>
        </ManualStep>
        <ManualStep number={5} title="Clique em Criar versão">
          <p>A nova versão é gravada. Nenhuma versão antiga é apagada ou alterada.</p>
        </ManualStep>
        <ManualStep number={6} title="Confira a versão criada">
          <p>
            Escolha Todas as versões, abra Ver detalhes e confira produto, finalidade, versão, componentes,
            quantidades, unidades, justificativa e observação.
          </p>
        </ManualStep>
        <ManualStep number={7} title="Ative a versão">
          <p>
            Se tudo estiver correto, clique em Ativar esta versão, informe o motivo e confirme.
            A versão passa a ser a referência vigente daquele produto e daquela finalidade.
          </p>
        </ManualStep>

        <div className="notice-panel warning">
          <strong>⚠️ Fórmula antiga sem base por litro comprovada</strong>
          <span>
            Se a versão estiver marcada como histórica/legada sem base por litro comprovada, ela não deve ser usada para abrir nova OP.
            Crie uma versão revisada por 1 litro e ative essa nova versão.
          </span>
        </div>

        <h3>🔁 Criar nova versão a partir de uma existente</h3>
        <p>
          Abra a versão e clique em Criar nova versão a partir desta. O sistema copia os dados para facilitar a revisão.
          A fórmula antiga continua preservada. Confira tudo antes de salvar.
        </p>

        <h3>🆘 A fórmula não aparece ao abrir uma OP</h3>
        <p>
          Verifique três coisas: ela precisa ser <strong>Produção operacional</strong>, estar com
          <strong> base por litro revisada</strong> e estar <strong>Vigente</strong>.
        </p>
      </ManualSection>

      <ManualSection
        id="garantias"
        icon="📋"
        title="Garantias e conformidade"
        route="/producao/garantias"
        purpose="Registrar garantias de produto, análise por lote de MP, densidade do lote e revisar referências históricas."
      >
        <h3>Garantia declarada do produto</h3>
        <p>
          Selecione Produto, Nutriente, Limite, Valor, Unidade e Fonte. Informe vigência e documento quando aplicável.
          A justificativa é obrigatória.
        </p>
        <p>
          O Limite pode ser Mínimo, Máximo, Faixa ou Declarado. Se escolher Faixa, informe também o valor máximo.
        </p>

        <h3>Garantia analisada do lote de MP</h3>
        <p>
          Escolha o lote exato de matéria-prima. A análise pertence àquele lote.
          Informe nutriente, valor, unidade, fonte, data, documento e justificativa.
        </p>

        <h3>Base física do lote de MP</h3>
        <p>
          Informe a densidade real do lote em kg/L. Ela é usada quando o sistema precisa converter litros e quilogramas.
        </p>

        <div className="notice-panel warning">
          <strong>📎 Documento pode ser obrigatório</strong>
          <span>Quando a fonte for Laboratório ou Fornecedor, informe o documento de referência. Não mude a fonte apenas para evitar o documento.</span>
        </div>

        <h3>Conciliação do histórico</h3>
        <p>
          Esta parte serve para classificar dados antigos importados. Classificar, manter pendente ou descartar uma referência
          histórica não cria uma nova garantia operacional e não movimenta estoque.
        </p>

        <h3>O que conferir no final da tela</h3>
        <p>Confira Garantias vigentes, Densidades vigentes por lote e os resultados de garantia já calculados.</p>
      </ManualSection>

      <ManualSection
        id="ordens"
        icon="🏭"
        title="Ordens de Produção e reservas"
        route="/producao/ordens e /producao/ordens/[id]"
        purpose="Abrir OP, reservar lotes, iniciar produção, cancelar quando permitido e consultar o andamento."
      >
        <h3>Fila de ordens</h3>
        <p>
          Você pode buscar por código da OP, fórmula ou produto. Também pode filtrar por Situação e Finalidade.
          O botão Abrir OP aparece somente para quem possui alçada.
        </p>

        <h3>Abrir nova OP</h3>
        <p>
          Escolha a Fórmula operacional, a Finalidade da OP e informe o Volume planejado em litros.
          O sistema calcula os componentes multiplicando a fórmula por 1 L pelo volume informado.
        </p>
        <div className="notice-panel ok">
          <strong>✅ Abrir OP não baixa estoque</strong>
          <span>A abertura cria o planejamento da produção. O saldo físico ainda não é reduzido.</span>
        </div>

        <h3>📦 Reservar componentes</h3>
        <p>
          Abra a OP. Para cada componente, confira Necessário, Reservado, Pendente e Disponível.
          Depois escolha os lotes que serão usados.
        </p>
        <div className="operational-summary">
          <div><dt>Físico</dt><dd>Tudo o que existe fisicamente no lote.</dd></div>
          <div><dt>Reservado</dt><dd>Parte já comprometida para ordens.</dd></div>
          <div><dt>Disponível</dt><dd>Parte que ainda pode ser reservada.</dd></div>
        </div>

        <h3>⏱️ FIFO</h3>
        <p>
          O sistema prioriza lotes mais antigos compatíveis. Ignorar essa prioridade depende de alçada específica e exige justificativa.
        </p>

        <div className="notice-panel warning">
          <strong>⚠️ Reservar NÃO é consumir</strong>
          <span>Reservar reduz o disponível, mas o saldo físico só é baixado no momento previsto pela finalização da OP.</span>
        </div>

        <h3>▶️ Iniciar OP</h3>
        <p>
          O botão aparece quando todos os componentes estão integralmente reservados e o usuário possui permissão.
          Antes de iniciar, confira produto, fórmula, volume e lotes.
        </p>

        <h3>✖️ Cancelar OP</h3>
        <p>
          O cancelamento exige motivo e só aparece em estados permitidos. Não faça ajuste manual de estoque para compensar um cancelamento.
        </p>

        <h3>🔎 Abrir OP</h3>
        <p>
          Na tela de detalhe você confere fórmula, reservas, componentes, lotes, situação e saída gerada.
          É a tela correta para trabalhar em uma OP específica.
        </p>

        <h3>🖨️ Imprimir OP</h3>
        <p>
          A impressão traz produto, fórmula, versão, volume, situação, POPs aplicáveis, MPs, lotes separados,
          quantidade prevista, utilizada, desvios e campos para assinaturas.
        </p>
      </ManualSection>

      <ManualSection
        id="cq"
        icon="✅"
        title="Controle de Qualidade e finalização"
        route="/producao/qualidade e /producao/qualidade/[id]"
        purpose="Registrar o que realmente aconteceu na produção, o resultado do CQ e finalizar a OP."
      >
        <h3>Fila operacional x Histórico</h3>
        <p>
          A Fila operacional mostra OPs <strong>Em processo</strong> que aguardam CQ.
          O Histórico mostra OPs já finalizadas. Uma OP finalizada não deve aparecer na fila operacional.
        </p>

        <h3>🧪 Abrir CQ</h3>
        <p>
          Abra somente a OP que você vai analisar. Se a OP ainda não foi iniciada, volte para Ordens.
          Se já foi finalizada, consulte o Histórico.
        </p>

        <h3>Procedimentos aplicáveis</h3>
        <p>
          Os POPs aplicáveis ficam congelados na OP. Para cada procedimento, registre Conforme, Desvio ou Não conforme.
          Se houver desvio ou não conformidade, descreva a ocorrência e a ação corretiva quando existir.
        </p>

        <h3>Dados que precisam ser informados</h3>
        <div className="operational-summary">
          <div><dt>Resultado CQ</dt><dd>Aprovado, Bloqueado ou Reprovado.</dd></div>
          <div><dt>pH</dt><dd>Valor medido.</dd></div>
          <div><dt>Densidade kg/L</dt><dd>Densidade real da produção.</dd></div>
          <div><dt>Volume L</dt><dd>Volume real produzido.</dd></div>
          <div><dt>Massa kg</dt><dd>Massa real produzida.</dd></div>
          <div><dt>Temperatura °C</dt><dd>Temperatura registrada no CQ.</dd></div>
        </div>

        <h3>👥 Participantes</h3>
        <p>
          Informe Separador de MP, Conferente de MP, Formulador principal, formuladores adicionais quando houver,
          Responsável pelo CQ e Responsável pela liberação.
        </p>
        <p>Não troque os papéis das pessoas apenas para conseguir finalizar o formulário.</p>

        <h3>📦 Produto gerado</h3>
        <p>
          A OP normal gera um único lote PI do produto da fórmula. O código do lote é automático.
          A quantidade acompanha o volume real registrado no CQ.
        </p>

        <div className="notice-panel warning">
          <strong>⚠️ Finalizar OP muda estoque e histórico</strong>
          <span>
            Ao finalizar, o sistema registra CQ e participantes, consome os lotes relacionados e gera o lote PI.
            Não use Finalizar OP apenas para “passar para a próxima tela”.
          </span>
        </div>

        <h3>Resultado do CQ</h3>
        <p><strong>✅ Aprovado:</strong> o produto segue o fluxo previsto.</p>
        <p><strong>🔒 Bloqueado:</strong> o lote existe, mas não pode ser usado até uma decisão posterior.</p>
        <p><strong>❌ Reprovado:</strong> o produto não foi aprovado pelo CQ.</p>

        <h3>Calcular garantias</h3>
        <p>
          No histórico é possível calcular ou recalcular garantias com justificativa.
          O cálculo usa os lotes realmente consumidos, garantias vigentes, densidades necessárias e dados reais do CQ.
        </p>
      </ManualSection>

      <ManualSection
        id="envase"
        icon="📦"
        title="OP MAPA e Ordem de Envase"
        route="/producao/envase"
        purpose="Usar PI liberado e embalagens para gerar o produto acabado PA."
      >
        <h3>Antes de emitir</h3>
        <p>
          Você precisa de Fórmula MAPA ativa, lote PI liberado, Produto e embalagem corretos e Volume a envasar.
        </p>

        <h3>Emitir documentos</h3>
        <p>
          Selecione a Fórmula MAPA, o lote PI, a apresentação e o volume. O sistema valida a compatibilidade antes de emitir.
        </p>

        <h3>Reservar embalagens</h3>
        <p>
          Reserve os lotes de embalagem até completar todos os componentes previstos.
          O envase não deve começar com embalagem pendente.
        </p>

        <h3>▶️ Iniciar envase</h3>
        <p>O botão aparece quando as reservas necessárias estão completas e a ordem está no estado correto.</p>

        <h3>✅ Finalizar e gerar PA</h3>
        <p>
          A finalização consome PI e embalagens e cria um único lote PA para a apresentação escolhida.
        </p>

        <div className="notice-panel warning">
          <strong>⚠️ PI não é PA</strong>
          <span>A produção gera PI. O envase consome PI e embalagens e gera PA.</span>
        </div>
      </ManualSection>

      <ManualSection
        id="estoque"
        icon="🗃️"
        title="Lotes e estoque"
        route="/producao/estoque"
        purpose="Consultar lotes e saldos, registrar entrada valorizada de MP e encaminhar lotes para liberação ou transformação."
      >
        <h3>🔎 Pesquise primeiro</h3>
        <p>
          Digite produto, matéria-prima, SKU ou código. Use o filtro Família para limitar a MP, PI ou PA.
          Para PA, escolha também a apresentação antes de ver os lotes.
        </p>

        <h3>Entenda os três saldos</h3>
        <div className="operational-summary">
          <div><dt>Físico</dt><dd>Tudo o que existe no lote.</dd></div>
          <div><dt>Reservado</dt><dd>Quantidade já separada para ordens.</dd></div>
          <div><dt>Disponível</dt><dd>Quantidade que ainda pode ser usada em nova reserva.</dd></div>
        </div>
        <p><strong>Para uma nova reserva, olhe o Disponível, não apenas o Físico.</strong></p>

        <h3>Entrada de matéria-prima</h3>
        <p>
          Ao selecionar uma MP, você pode registrar lote do fornecedor, quantidade, unidade, qualidade, fabricação,
          validade, documento, valor da MP, frete, DIFAL, outras despesas e observação.
        </p>
        <p>O sistema cria lote, entrada física e camada de custo na mesma transação.</p>

        <h3>DIFAL</h3>
        <p>
          Informe a situação correta: Não aplicável, Informado ou Pendente de revisão.
          Quando houver pendência, registre o motivo e a UF quando aplicável.
        </p>

        <h3>🔒 Lote bloqueado</h3>
        <p>
          PA ou PI bloqueado pode apresentar ação de liberação, sempre com motivo.
          MP bloqueada exige decisão técnica por fluxo próprio.
        </p>

        <h3>🔁 Planejar transformação</h3>
        <p>
          Um lote disponível com saldo pode ser enviado para Transformações. O sistema leva o lote escolhido como origem da operação.
        </p>
      </ManualSection>

      <ManualSection
        id="transformacoes"
        icon="🔁"
        title="Transformações e reprocessamentos"
        route="/producao/transformacoes"
        purpose="Executar reprocessamentos e transformações com rastreabilidade de origem, reserva, CQ, consumo e novo lote."
      >
        <p>
          Use esta área para operações como reprocessamento, PA para PI, PI para PA ou outras transformações previstas.
          A transformação é uma OP governada, não um ajuste manual de saldo.
        </p>

        <h3>Lote de origem</h3>
        <p>
          Quando você chega pelo Estoque, a tela mostra o lote selecionado e o saldo disponível.
          Se o lote estiver bloqueado, ele precisa ser liberado pelo fluxo correto antes de ser usado.
        </p>

        <h3>Planejar transformação</h3>
        <p>
          Escolha uma fórmula compatível, informe o volume e escreva a justificativa operacional.
          A justificativa deve dizer o que realmente será feito.
        </p>

        <h3>Executar</h3>
        <p>
          Depois siga o mesmo fluxo governado de uma OP: reserva, início, CQ e finalização.
          O novo lote fica ligado à OP e aos lotes consumidos.
        </p>

        <div className="notice-panel warning">
          <strong>⚠️ Transformação não é ajuste de estoque</strong>
          <span>Não use reprocessamento para esconder divergência de estoque.</span>
        </div>
      </ManualSection>

      <ManualSection
        id="impressoes"
        icon="🖨️"
        title="Documentos impressos"
        route="/producao/ordens/[id]/imprimir e /producao/envase/[id]/imprimir"
        purpose="Gerar documentos físicos de execução sem substituir o registro eletrônico."
      >
        <h3>Ordem de Produção</h3>
        <p>
          Mostra produto, fórmula, versão, volume, situação, POPs, MPs, lotes, quantidades, desvios e assinaturas.
        </p>
        <h3>Ordem de Envase</h3>
        <p>
          Mostra OP MAPA, fórmula MAPA, produto, apresentação, PI de origem, volume, quantidade PA,
          embalagens, lotes reservados, destino PA e campos de execução.
        </p>
        <div className="notice-panel ok">
          <strong>✍️ Papel e sistema trabalham juntos</strong>
          <span>A assinatura no papel não substitui usuários, participantes, estados e movimentos registrados no Elite System.</span>
        </div>
      </ManualSection>

      <section className="panel" id="problemas" aria-labelledby="manual-troubleshooting-title">
        <div className="panel-header">
          <div>
            <span className="eyebrow">🆘 Ajuda rápida</span>
            <h2 id="manual-troubleshooting-title">Problemas comuns</h2>
          </div>
          <a className="text-link" href="#manual-index-title">Voltar ao índice</a>
        </div>
        <div className="table-scroll">
          <table className="data-table">
            <thead><tr><th>O que aconteceu</th><th>O que verificar</th></tr></thead>
            <tbody>
              <tr><td>Criei uma fórmula e ela sumiu.</td><td>Em Fórmulas, mude Exibir para Todas as versões. Criar não significa ativar.</td></tr>
              <tr><td>A fórmula não aparece ao abrir OP.</td><td>Confirme: Produção operacional, base por litro revisada e versão vigente.</td></tr>
              <tr><td>Não consigo iniciar a OP.</td><td>Confira se todos os componentes estão totalmente reservados e se você possui alçada.</td></tr>
              <tr><td>O lote tem saldo físico, mas não pode ser reservado.</td><td>Confira saldo disponível, reservas existentes, situação do lote e compatibilidade.</td></tr>
              <tr><td>A OP não aparece no CQ.</td><td>Ela precisa estar Em processo. Finalizadas ficam no Histórico.</td></tr>
              <tr><td>O PI não aparece para envase.</td><td>Confira se o lote PI está liberado e corresponde ao produto esperado.</td></tr>
              <tr><td>Não consigo liberar uma MP bloqueada.</td><td>A liberação direta do Estoque é para PA/PI. MP segue decisão técnica própria.</td></tr>
              <tr><td>Um botão não aparece.</td><td>Confira o estado do registro e sua alçada. O sistema oculta ações não permitidas.</td></tr>
            </tbody>
          </table>
        </div>
      </section>

      <section className="panel" aria-labelledby="manual-glossary-title">
        <div className="panel-header">
          <div>
            <span className="eyebrow">📖 Palavras do sistema</span>
            <h2 id="manual-glossary-title">Glossário simples</h2>
          </div>
        </div>
        <dl className="operational-summary">
          <div><dt>MP</dt><dd>Matéria-prima.</dd></div>
          <div><dt>PI</dt><dd>Produto intermediário produzido antes do envase.</dd></div>
          <div><dt>PA</dt><dd>Produto acabado, pronto na apresentação comercial.</dd></div>
          <div><dt>OP</dt><dd>Ordem de Produção.</dd></div>
          <div><dt>OP MAPA</dt><dd>Documento do fluxo MAPA ligado ao envase.</dd></div>
          <div><dt>FIFO</dt><dd>Prioridade para usar primeiro os lotes compatíveis mais antigos.</dd></div>
          <div><dt>Vigente</dt><dd>Versão que está valendo agora.</dd></div>
          <div><dt>Histórico</dt><dd>Versão antiga preservada para consulta.</dd></div>
          <div><dt>Reservar</dt><dd>Separar saldo para uma ordem sem baixar o físico ainda.</dd></div>
          <div><dt>Consumir</dt><dd>Baixar fisicamente a quantidade usada.</dd></div>
          <div><dt>Alçada</dt><dd>Permissão que define quais ações o usuário pode executar.</dd></div>
          <div><dt>Base por litro</dt><dd>Composição calculada para produzir 1 L.</dd></div>
        </dl>
      </section>

      <section className="notice-panel ok">
        <strong>✅ Regra final</strong>
        <span>
          Se tiver dúvida, não tente “forçar” a próxima etapa. Confira a situação atual, leia o aviso da tela
          e registre o que realmente aconteceu. O histórico existe para preservar quem fez, quando fez e qual foi o resultado.
        </span>
      </section>
    </ProductionShell>
  );
}

function ManualSection({ id, icon, title, route, purpose, children }: ManualSectionProps) {
  return (
    <section className="panel" id={id} aria-labelledby={`${id}-title`}>
      <div className="panel-header">
        <div>
          <span className="eyebrow">{icon} Manual da tela</span>
          <h2 id={`${id}-title`}>{title}</h2>
          <p className="muted">{route}</p>
        </div>
        <a className="text-link" href="#manual-index-title">Voltar ao índice</a>
      </div>
      <p><strong>Para que serve:</strong> {purpose}</p>
      {children}
      <div className="manual-route-actions">
        <Link className="secondary-button" href={route.startsWith("/") && !route.includes(" e ") ? route : "/producao"}>
          Abrir área de Produção
        </Link>
      </div>
    </section>
  );
}

function ManualStep({ number, title, children }: ManualStepProps) {
  return (
    <article className="panel">
      <div className="panel-header">
        <div>
          <span className="eyebrow">Passo {number}</span>
          <h4>{title}</h4>
        </div>
      </div>
      {children}
    </article>
  );
}
