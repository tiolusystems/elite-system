import Link from "next/link";

export default function ManualPedidosPage() {
  return (
    <main className="orders-workspace manual-content">
      <header className="orders-heading"><div><span className="eyebrow">Manual operacional</span><h1>Pedidos e aprovação</h1><p>Passo a passo para vendedor e gerente.</p></div><Link className="secondary-button" href="/pedidos">Voltar aos pedidos</Link></header>
      <section className="panel"><div className="panel-header"><h2>Vendedor</h2></div><ol className="manual-steps"><li>Pesquise o cliente em <strong>Minha carteira</strong>.</li><li>Selecione cliente ou propriedade e confira o limite.</li><li>Informe produto, apresentação, quantidade, valor e data.</li><li>Clique em <strong>Enviar para liberação</strong>.</li><li>Acompanhe a situação no histórico.</li></ol></section>
      <section className="panel"><div className="panel-header"><h2>Gerente</h2></div><ol className="manual-steps"><li>Abra <strong>Liberações gerenciais</strong>.</li><li>Confira cliente, vendedor, pedido e crédito.</li><li>Quando necessário, registre novo limite com justificativa.</li><li>Informe a justificativa da decisão.</li><li>Clique em <strong>Liberar</strong> ou <strong>Reprovar</strong>.</li></ol></section>
      <section className="notice-panel"><strong>Regra de acesso</strong><span>Vendedores veem a própria carteira. Gerentes veem também os vendedores subordinados. Toda decisão fica auditada.</span></section>
    </main>
  );
}
