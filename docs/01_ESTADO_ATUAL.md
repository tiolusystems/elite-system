# Elite System - estado atual

Atualizado em: 2026-07-22

## Referencia vigente

- branch de desenvolvimento publicada: `feature/0044-production-module-release`;
- commit funcional e documental publicado: `3abb5e0`;
- Supabase de homologacao: ledger alinhado de `0001` a `0103`;
- frontend estavel: `https://elite-system-staging.vercel.app`;
- backend de staging: `/api/health` com `status=ok` e `backendConfigured=true`;
- deployment estavel de staging: `dpl_DPowRqN9P66VtZxbXc9pbvTGmTxU`;
- producao real e `main`: nao alteradas;
- PWA: adiada.

## Estado tecnico comprovado

O pipeline integral do commit `3abb5e0` esta aprovado na execucao
`29943476990`:

- ESLint, TypeScript e build Next.js;
- testes Python e contratos estaticos;
- reconstrucao PostgreSQL limpa com todas as migrations;
- lint do schema e geracao do contrato TypeScript;
- smokes transacionais das cadeias industrial e comercial;
- RLS, grants minimos e escrita operacional somente por RPC;
- importacao historica de materias-primas;
- catalogos tecnicos, embalagens e logistica;
- Romaneio, leitura RLS e fronteiras administrativas de Seguranca.

As migrations `0091` a `0103` foram aplicadas no Supabase de staging somente
depois de CI aprovada e dry-run controlado. O ultimo dry-run listou exclusivamente:

- `0097_manager_decision_request_idempotency.sql`;
- `0098_romaneio_request_idempotency.sql`;
- `0099_packaging_issue_request_idempotency.sql`;
- `0100_exchange_order_request_idempotency.sql`;
- `0101_commission_assignment_request_idempotency.sql`.

Um segundo dry-run listou exclusivamente
`0102_fiscal_request_idempotency.sql` antes de sua aplicacao.
O dry-run seguinte listou exclusivamente
`0103_govern_product_groups.sql` antes de sua aplicacao.

O ledger remoto confirmou `0103` e o health-check permaneceu saudavel depois da
aplicacao. O aviso de cache `pg-delta` da CLI ocorreu depois da execucao SQL e
nao alterou o ledger nem a disponibilidade do backend.

## Tarefa concluida mais recente

Governanca relacional de grupos de produto e eliminacao das interfaces
concorrentes da Central de Cadastros:

- Central de Cadastros atua como portal para Materias-primas, Produtos,
  Embalagens e catalogos tecnicos;
- Produtos usa exclusivamente `grupo_id` para novos vinculos;
- grupos inativos permanecem legiveis no historico e nao podem receber novos
  produtos;
- criacao, edicao, inativacao e reativacao de grupos sao auditadas;
- rotulos operacionais em PT-BR sao centralizados e enums internos nao sao
  exibidos diretamente;
- rota canonica `/cadastros/grupos-produto` possui busca, filtros, manutencao,
  historico e manual contextual.

O fechamento anterior de idempotencia permanece vigente para:

- recebimento financeiro;
- pagamento e ajuste de comissao;
- criacao de pedido por vendedor;
- criacao de formula e OP;
- ajuste de limite e decisao gerencial;
- criacao de rascunho de Romaneio;
- emissao conjunta de OP MAPA e Ordem de Envase;
- criacao de pedido de troca;
- atribuicao manual de comissao;
- emissao de NF e estorno pos-pagamento com devolucao fisica.

Cada operacao usa chave de requisicao, trava transacional, reaproveitamento do
resultado em retry identico e rejeicao quando a mesma chave chega com payload
divergente. As tabelas de requisicao nao foram abertas para leitura direta dos
papeis da API.

## Validacao desta tarefa

- CI integral do commit `3abb5e0` aprovada nos jobs `database-contract`,
  `python-tests` e `web-contract`;
- instalacao limpa, upgrade `0102` para `0103`, concorrencia e smokes
  PostgreSQL executados em ambientes `elite-validation-*`;
- ledger de staging confirmado ate `0103`, sem reaplicacao na retomada;
- health-check de staging saudavel depois da aplicacao;
- smoke autenticado confirmou Central, Produtos, Grupos, historico e manual;
- grupo e produto sinteticos foram inativados pelo fluxo governado, sem apagar
  o historico;
- nenhum dado real, reset ou alteracao em producao.

## Fluxos funcionais disponiveis

### Cadastros

- Clientes e ficha relacional completa;
- Pessoas e vinculos comerciais;
- Materias-primas e tipos de insumo;
- Produtos, apresentacoes e embalagens;
- catalogos tecnicos, unidades, garantias e logistica;
- governanca PT-BR e manuais contextuais.

### Producao e estoque

- formula operacional com base por litro;
- garantias documentais e calculo fisico por lote consumido;
- OP, reserva FIFO, inicio, CQ e finalizacao;
- um produto e um lote PI por OP;
- OP MAPA documental e Ordem de Envase;
- um lote PA por envase/apresentacao;
- custo por camada de entrada de MP;
- perda de processo separada de perda de estoque;
- custo PI por MP e custo PA por PI mais embalagens;
- relatorios com filtro MP, PI e PA.

### Comercial, expedicao e financeiro

- pedidos de Venda, Bonificacao, Mostruario e Troca;
- todo pedido nasce bloqueado e depende de decisao superior;
- PDF liberado somente depois da aprovacao, em A4 paisagem;
- totais de litros, volumes e peso bruto derivados;
- comissionados flexiveis por pedido: vendedor, agente, gerente ou outro;
- bonificacao e mostruario sem comissao;
- recebimento, liberacao proporcional, pagamento e ajuste de comissao;
- Romaneio por pedido, item, quantidade parcial, lote e embalagem;
- reserva sem baixa fisica e baixa consolidada pela informacao fiscal.

### Importacao fiscal e historica

- XML de NF-e possui chave de acesso normalizada unica;
- cada item XML pode originar somente um lote de MP;
- analise e homologacao funcional das fontes historicas sem escrita;
- staging e mapeamento de MP auditados;
- custos de aquisicao com mercadoria, frete, DIFAL e despesas separados;
- rastreabilidade por workbook, tabela e linha;
- aplicacao integral do workbook continua condicionada a homologacao das fontes
  e ao corte fisico de abertura.

## Seguranca vigente

- contas individuais e escrita sensivel por RPC auditada;
- RLS e menor privilegio;
- escrita direta revogada;
- fatos historicos append-only;
- `anon` e `PUBLIC` sem execucao das RPCs operacionais;
- convite, recuperacao de senha e troca administrativa de e-mail governados;
- assinatura institucional `by ☧ SYSTEMS` preservada.

## Decisoes ainda bloqueantes

- `DEC-002`: MFA TOTP e exigencia de AAL2;
- `DEC-003`: autoaprovacao de troca de e-mail do unico administrador;
- `DEC-004`: politica Auth de producao, SMTP corporativo e CAPTCHA;
- `DEC-012`: corte e inventario fisico de abertura;
- emissao fiscal sem chave de NF-e: definir se o fluxo admite rascunho fiscal ou
  se toda emissao definitiva deve exigir chave fiscal antes de ganhar uma chave
  de requisicao propria.

Essas decisoes nao bloqueiam desenvolvimento e homologacao no staging, mas
bloqueiam entrada segura em producao real ou ativacao de saldos oficiais.

## Proxima tarefa

1. Retomar o macrociclo UX-01C a partir do staging validado, sem recriar os
   contratos de Grupos de produto.
2. Executar smoke autenticado de Producao, Pedidos, comissoes e Romaneio no
   frontend promovido.
3. Continuar a auditoria de idempotencia somente em eventos que criam efeito
   fisico, fiscal ou financeiro; nao envolver atualizacoes naturalmente
   serializadas por estado.
4. Preparar o corte fisico `DEC-012` antes de ativar saldos reais.

## Tarefa seguinte

Concluir a homologacao funcional do workbook e executar a etapa I2 somente para
fontes aprovadas, mantendo a importacao operacional bloqueada ate essa decisao.

Nao reaplicar migrations, nao resetar banco e nao alterar producao real.
