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
12. Atualizacao de status de todas as dependencias.
13. Recebimentos e comissoes.
14. Simulador de producao com base em historico ou alimentacao manual.
15. Estoque regulador de PA, PI e MP.
16. Relatorios de vendas por vendedor, periodo, cliente e produto.
17. Rastreabilidade de lotes MP, PA e PI.

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
- prazo de validade;
- garantias;
- formulas.

Comercial:

- cliente;
- pedido;
- vendedor/comissionados;
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
3. Formulas PA/PI.
4. PCP/formulacao/CQ.
5. Romaneio com entregador e baixa de produto.
6. Atualizacao de status encadeada.
7. Recebimentos/comissoes.
8. Simulador e estoque regulador.
9. Relatorios de venda e rastreabilidade.

Essa sequencia passa a ser a referencia para decidir proximos passos e evitar construir telas fora da ordem operacional.
