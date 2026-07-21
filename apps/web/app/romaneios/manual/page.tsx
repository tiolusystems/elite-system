import Link from "next/link";

export default function ManualRomaneioPage() {
  const steps = [
    ["Escolha o pedido", "Na tela de Romaneio, selecione um pedido com saldo a entregar."],
    ["Selecione os produtos", "Marque apenas os produtos desta entrega e informe a quantidade individual de cada um."],
    ["Grave o romaneio", "A consulta de produtos, peso e volumes não grava. Use Gravar romaneio quando a seleção estiver correta."],
    ["Reserve por lote", "Escolha o produto do romaneio. O sistema mostrará somente lotes compatíveis e seus saldos disponíveis."],
    ["Complete a separação", "Se necessário, distribua a quantidade entre vários lotes do mesmo produto."],
    ["Imprima", "O romaneio pode ser impresso após a reserva ou depois da informação fiscal."],
    ["Informe entrega e NF", "Informe entregador, veículo e a nota fiscal. A confirmação fiscal consolida a baixa física do estoque."],
    ["Confira o resultado", "Verifique volumes, pesos, lotes, saldo reservado e situação do romaneio antes de finalizar."]
  ];
  return (
    <main className="workspace dashboard-workspace manual-page">
      <div className="dashboard-header"><div><span className="eyebrow">manual operacional</span><h1>Como fazer um romaneio</h1><p className="muted">Fluxo do pedido com saldo até a baixa fiscal do estoque.</p></div><Link className="primary-button" href="/romaneios">Voltar ao Romaneio</Link></div>
      <section className="manual-steps">{steps.map(([title, detail], index) => <article className="panel manual-step" key={title}><span>{index + 1}</span><div><h2>{title}</h2><p>{detail}</p></div></article>)}</section>
      <section className="notice-panel warning"><strong>Regra principal</strong><span>Pedido aberto não baixa estoque. Reserva reduz o saldo disponível. A baixa física ocorre somente com a confirmação fiscal governada.</span></section>
    </main>
  );
}
