import Image from "next/image";
import Link from "next/link";
import { notFound } from "next/navigation";

import { OrderContractPrintButton } from "@/app/pedidos/[id]/contrato/print-button";
import { SignatureEvidencePanel } from "@/app/pedidos/[id]/contrato/signature-evidence-panel";
import { getOrderSignatureWorkspace } from "@/lib/orders";

export default async function OrderContractPage({ params, searchParams }: { params: Promise<{ id: string }>; searchParams?: Promise<Record<string, string | string[] | undefined>> }) {
  const { id } = await params;
  const workspace = await getOrderSignatureWorkspace(Number(id));
  if (!workspace) notFound();
  const contract = workspace.contract;
  const query = searchParams ? await searchParams : {};
  const signatureResult = Array.isArray(query.assinatura) ? query.assinatura[0] : query.assinatura;

  const primaryContact = contract.client.contacts[0] ?? null;
  const cpfCnpj = contract.client.documents.find((item) => ["cpf", "cnpj"].includes(item.type));
  const stateRegistration = contract.client.documents.find((item) => item.type === "ie");
  const deliveryPlace = contract.client.propertyName ?? contract.client.name;
  const deliveryCity = contract.client.propertyCity ?? contract.client.city;
  const deliveryState = contract.client.propertyState ?? contract.client.state;

  return (
    <main className="order-contract-document">
      <div className="order-contract-actions print-hidden">
        <Link className="secondary-button" href="/pedidos">Voltar aos pedidos</Link>
        <OrderContractPrintButton />
      </div>

      <section className="order-contract-page">
        <ContractHeader page={1} />
        <h1>Contrato de Compra e Venda de Insumos Agrícolas</h1>
        <section className="order-contract-grid order-contract-order-data">
          <Field label="Data do pedido" value={date(contract.orderDate)} />
          <Field label="Pedido nº" value={contract.code} />
          <Field label="Data para entrega" value={contract.deliveryDate ? date(contract.deliveryDate) : "Não informada"} />
          <Field label="Tipo de pedido" value={orderType(contract.type)} />
          <Field label="Vencimento(s)" value={contract.paymentTerms ?? "Não informado"} wide />
          <Field label="Forma de pagamento" value={contract.paymentTerms ?? "Não informada"} wide />
          <Field label="Vendedor" value={contract.sellerName ?? "Não informado"} wide />
          <Field label="Cliente" value={contract.client.name} wide />
          <Field label="Endereço NF" value="Não informado no cadastro atual" wide />
          <Field label="Município / UF" value={`${contract.client.city} / ${contract.client.state}`} />
          <Field label="CEP" value="Não informado" />
          <Field label="Endereço de entrega" value={deliveryPlace} wide />
          <Field label="Município / UF" value={`${deliveryCity} / ${deliveryState}`} />
          <Field label="CEP" value="Não informado" />
          <Field label="CNPJ / CPF" value={cpfCnpj?.number ?? "Não informado"} />
          <Field label="Inscrição" value={stateRegistration?.number ?? "Não informada"} />
          <Field label="E-mail" value={primaryContact?.email ?? "Não informado"} />
          <Field label="Telefone(s)" value={primaryContact?.phone ?? "Não informado"} />
        </section>

        <section className="order-contract-products">
          <h2>Detalhamento dos produtos do contrato</h2>
          <table>
            <thead><tr><th>Produtos</th><th>Embalagem</th><th>Quantidade</th><th>R$/litro ou unidade</th><th>Preço total</th></tr></thead>
            <tbody>
              {contract.items.map((item) => (
                <tr key={item.id}><td>{item.product}</td><td>{item.packaging}</td><td>{number(item.quantity)}</td><td>{money(item.unitPrice)}</td><td>{money(item.total)}</td></tr>
              ))}
              <tr className="order-contract-total"><td colSpan={2}>Totais</td><td>{number(contract.items.reduce((sum, item) => sum + item.quantity, 0))}</td><td></td><td>{money(contract.total)}</td></tr>
            </tbody>
          </table>
        </section>

        <section className="order-contract-load-summary" aria-label="Resumo físico do pedido">
          <Field label="Litros totais" value={metric(contract.totalVolumeLiters, "L")} />
          <Field label="Volumes totais" value={metric(contract.totalLogisticVolumes, "volume(s)")} />
          <Field label="Peso bruto total" value={metric(contract.totalGrossWeightKg, "kg")} />
        </section>

        <section className="order-contract-approval">
          <Field label="Aprovado por" value={contract.approvedBy ?? "Aprovação gerencial registrada no sistema"} />
          <Field label="Data da aprovação" value={contract.approvedAt ? dateTime(contract.approvedAt) : "Registrada no histórico do pedido"} />
        </section>
        <ContractFooter page={1} />
      </section>

      <section className="order-contract-page">
        <ContractHeader page={2} />
        <section className="order-contract-buyer">
          <Field label="Comprador" value={primaryContact?.name ?? contract.client.name} wide />
          <Field label="Cargo" value={primaryContact?.role ?? "Não informado"} />
          <Field label="CPF/RG" value="Não informado" />
          <Field label="WhatsApp" value={primaryContact?.phone ?? "Não informado"} />
          <Field label="E-mail" value={primaryContact?.email ?? "Não informado"} />
        </section>
        <div className="order-contract-signature"><span></span><strong>Assinatura do comprador/proprietário</strong></div>
        <section className="order-contract-observation"><strong>Observações</strong><p>{contract.observation ?? "Sem observações comerciais."}</p></section>
        <Terms sections={contract.terms} />
        <ContractFooter page={2} />
      </section>
      <SignatureEvidencePanel workspace={workspace} result={signatureResult} />
    </main>
  );
}

function ContractHeader({ page }: { page: number }) {
  return <header className="order-contract-header"><Image src="/brand/elite-agrociencias-logo.png" alt="Elite Agrociências" width={180} height={58} priority={page === 1} /><div><strong>ELITE IND. COM. LTDA</strong><span>faturamento@eliteagrociencias.com.br</span><span>(17) 98189-0402</span></div></header>;
}

function ContractFooter({ page }: { page: number }) {
  return <footer className="order-contract-footer"><strong>WWW.ELITEAGROCIENCIAS.COM.BR</strong><span>CNPJ: 57.138.778/0001-89 · Reg. MAPA EP: SP 006812-8R</span><span>Rua Oreste Francisco Pereira, 173 - DI 2 - CEP 14.781-163 - Barretos/SP</span><span>Página {page} de 2</span></footer>;
}

function Field({ label, value, wide = false }: { label: string; value: string; wide?: boolean }) {
  return <div className={wide ? "order-contract-field is-wide" : "order-contract-field"}><span>{label}</span><strong>{value}</strong></div>;
}

function Terms({ sections }: { sections: Array<{ titulo: string; texto: string }> }) {
  return <section className="order-contract-terms"><h2>Informativo sobre troca, devolução, cancelamento de pedidos e atrasos em pagamentos</h2>{sections.map((section, index) => <div key={`${section.titulo}-${index}`}><h3>{index + 1}. {section.titulo}</h3><p>{section.texto}</p></div>)}</section>;
}
/*
function LegacyTerms() {
  return <section className="order-contract-terms"><h2>Informativo sobre troca, devolução, cancelamento de pedidos e atrasos em pagamentos</h2>
    <h3>1. Escopo e natureza</h3><p>Aplica-se às operações de venda e fornecimento de insumos agrícolas realizadas com produtores rurais (PF/PJ), revendas, distribuidores e cooperativas agropecuárias. Relação comercial/profissional no âmbito do agronegócio. O e-mail corporativo cadastrado é canal de comunicação e não constitui aceite ou assinatura. O aceite do comprador será comprovado exclusivamente por evidência de assinatura registrada e aceita no Elite System. Prazos contados em dias corridos após o aceite do pedido, encerrando às 23:59 (fuso America/Sao_Paulo). Se, excepcionalmente, houver enquadramento como relação de consumo, prevalecerão as normas específicas aplicáveis.</p>
    <h3>2. Troca e devolução</h3><p>Não aceitamos devoluções em nenhuma hipótese. Constatada não conformidade em lote, o produto será substituído por outro idêntico. A constatação poderá ocorrer por laudo interno da VENDEDORA ou por laboratório indicado/aceito pela VENDEDORA.</p>
    <h3>3. Ciência e consentimento</h3><p>Ao assinar por meio de evidência registrada e aceita no Elite System, o CLIENTE declara ciência e concordância integral com este informativo e com as demais condições do pedido. O envio de e-mail, isoladamente, não produz aceite.</p>
    <h3>4. Cancelamento de pedidos (simples faturamento - sem remessa)</h3><p>Base de cálculo: valor líquido do pedido (sem tributos recuperáveis e sem frete). Cancelamento até 3 dias após o aceite: multa compensatória de 5%. Do 4º ao 10º dia: multa de 10%. A partir do 11º dia, havendo programação de produção (OP emitida, reserva/compra de insumos, logística agendada): multa de 15%. Havendo execução parcial (OP iniciada, insumo específico já incorporado ao processo ou serviço técnico iniciado): multa de 20%. Produtos/projetos customizados ou com insumo não reaproveitável: multa de até 25%, mediante comprovação documental. Se houver sinal (arras), aplica-se o maior entre a perda do sinal e a multa acima, sem cumulação pelo mesmo fato. O cancelamento deve ser solicitado por e-mail institucional indicado no cabeçalho do pedido. A VENDEDORA responderá com o enquadramento, memória de cálculo e instruções de compensação. Quando o prejuízo efetivo superar a multa pactuada, poderá ser cobrada indenização suplementar limitada ao excedente comprovado.</p>
    <h3>5. Atrasos em pagamentos</h3><p>Atraso superior a 5 dias implicará protesto do título e negativação automática. Encargos por atraso: multa de 2% sobre o valor em aberto e juros de 0,03% ao dia de atraso.</p>
    <h3>6. Tratamento fiscal (simples faturamento)</h3><p>A emissão de NF-e de simples faturamento não implica entrega física. Em caso de cancelamento, as partes firmarão distrato comercial. O procedimento fiscal (cancelamento ou manutenção da NF-e de simples faturamento) seguirá a legislação da UF do remetente, sendo adotada a providência cabível e comunicada ao CLIENTE.</p>
    <h3>7. Fundamentação e alcance</h3><p>Multa compensatória e arras pactuadas conforme legislação civil aplicável; perdas e danos suplementares quando cabíveis e comprovados. Este informativo aplica-se às relações comerciais com produtores rurais, revendas, distribuidores e cooperativas, sem prejuízo de normas específicas eventualmente incidentes.</p>
    <h3>8. Solução de controvérsias</h3><p>As partes buscarão solução amigável e, não sendo possível, elegem o foro da comarca de Barretos/SP, com renúncia a qualquer outro, por mais privilegiado que seja.</p>
    <h3>9. Disposições finais</h3><p>Este informativo integra o Pedido de Venda, cujo número consta no cabeçalho do documento. Comunicações oficiais devem ocorrer exclusivamente pelo e-mail institucional indicado no cabeçalho do pedido.</p>
  </section>;
 }*/

function date(value: string) { return new Intl.DateTimeFormat("pt-BR", { timeZone: "UTC" }).format(new Date(`${value}T00:00:00Z`)); }
function dateTime(value: string) { return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short" }).format(new Date(value)); }
function number(value: number) { return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 3 }).format(value); }
function money(value: number) { return new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(value); }
function metric(value: number | null, unit: string) { return value === null ? "Pendente de cadastro logístico" : `${number(value)} ${unit}`; }
function orderType(value: string) { return ({ venda: "Venda", bonificacao: "Bonificação", troca: "Troca", mostruario: "Mostruário" } as Record<string, string>)[value] ?? "Pedido comercial"; }
