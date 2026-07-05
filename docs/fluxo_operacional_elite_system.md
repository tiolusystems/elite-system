# Fluxo operacional canonico do Elite System

Data da decisao: 2026-07-04

## Decisao

A construcao do Elite System deve seguir a sequencia real de operacao da empresa, nao apenas a ordem tecnica das migrations.

O sistema nasce dos cadastros e segue ate pedido, formulacao, CQ, baixas, romaneio, financeiro, simulacao, estoque regulador e relatorios rastreaveis.

## Sequencia operacional

1. Cadastro de usuarios.
2. Cadastro de MP e embalagens.
3. Cadastro de PA.
4. Formulas de PA e PI.
5. Cadastro de clientes.
6. Cadastro de pedidos.
7. Formulacao.
8. CQ.
9. Baixa de insumos.
10. Romaneio e entregador.
11. Baixa de produtos.
12. Faturamento e NF.
13. Atualizacao de status de todas as dependencias.
14. Recebimentos e comissoes.
15. Simulador de producao com base em historico ou alimentacao manual.
16. Estoque regulador de PA, PI e MP.
17. Relatorios de vendas por vendedor, periodo, cliente e produto.
18. Rastreabilidade de lotes MP, PA e PI.

## Dependencias de construcao

Usuarios:

- login;
- senha;
- alçadas;
- rastreio de acao por usuario.

Cadastros tecnicos:

- MP;
- embalagens;
- PA;
- PI;
- produto + embalagem;
- importacao semiautomatica de NF XML para entrada de MP;
- prazo de validade;
- garantias;
- formulas.

Comercial:

- cliente;
- propriedade/fazenda do cliente;
- pedido;
- sequencia de pedido por propriedade quando aplicavel;
- vendedor/comissionados;
- Kanban por vendedor, gerente vinculado e area comercial;
- credito;
- status do pedido.

PCP:

- formulacao;
- OP;
- reserva de insumos;
- CQ;
- baixa de MP/PA/PI consumido;
- geracao de PA/PI.

Expedicao:

- romaneio;
- lote separado;
- entregador;
- baixa de produto acabado;
- status de entrega.

Faturamento:

- NF por romaneio;
- NF por simples faturamento direto do pedido;
- NF de remessa dependente da NF de simples faturamento quando o pedido usar esse fluxo;
- dossie fiscal no corpo do pedido por relacionamento/view, sem duplicar campos fiscais em `com_pedidos`;
- cancelamento, carta de correcao, substituicao e NF complementar por eventos;
- `romaneio_id` nullable quando nao houver remessa fisica associada;
- decisao canonica em `docs/decisao_faturamento_notas_fiscais.md`.

Financeiro:

- recebimento parcial ou integral;
- comissao proporcional;
- abatimento por devolucao;
- status financeiro do pedido.

Estoque regulador:

- saldo minimo ou alvo de PA, PI e MP;
- necessidade de producao;
- necessidade de compra;
- vencimento;
- reprocessamento.

Relatorios:

- vendas por vendedor;
- vendas por periodo;
- vendas por cliente;
- vendas por produto;
- rastreabilidade lote MP -> OP -> PA/PI -> romaneio -> cliente;
- saldos e vencimentos;
- comissoes;
- reconciliacao contra historico Excel.

## Implicacao pratica

A proxima codificacao deve priorizar as telas e fluxos que destravam esta ordem:

1. Usuarios/alçadas visiveis no app web.
2. Estoque/cadastros tecnicos MP, embalagens, PA e PI.
3. Importacao semiautomatica de NF XML para MP, com conferencia e geracao auditada de lote.
4. Pedido por cliente/propriedade, sequencia propria e Kanban comercial.
5. Formulas PA/PI.
6. PCP/formulacao/CQ.
7. Romaneio com entregador e baixa de produto.
8. Atualizacao de status encadeada.
9. Faturamento/NF como evento fiscal auditavel.
10. Recebimentos/comissoes.
11. Simulador e estoque regulador.
12. Relatorios de venda e rastreabilidade.

Essa sequencia passa a ser a referencia para decidir proximos passos e evitar construir telas fora da ordem operacional.
