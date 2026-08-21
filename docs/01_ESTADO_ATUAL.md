# Elite System - estado atual

Atualizado em: 2026-08-18

## Referencia vigente

- branch: `work/orders-rules-review-20260813`;
- HEAD local e remoto antes da tranche local: `d379f3080fadc0bcafa412f43172c31dcd5928c6`;
- sincronizacao local/remoto antes da tranche local: `0/0`;
- producao real, `main`, PWA, staging e bancos persistentes: inalterados nesta tranche.

O estado detalhado acumulado ate esta data foi preservado em
`docs/historico/01_ESTADO_ATUAL_ATE_2026-07-28.md`. O Git e os documentos de
validacao preservam as evidencias anteriores.

## Tarefa em execucao

`ORD-01 F2B - revisao comercial do vendedor`, implementada localmente e pendente de revisao antes do commit.

### Estado local ORD-01 F2B

- a proposta permanece somente no navegador enquanto e editada; a previsualizacao do banco nao cria pedido nem rascunho persistente;
- a confirmacao final vincula o hash exato da previsualizacao e cria atomicamente pedido bloqueado, condicao financeira, referencias 1D/1E, fatos F2A e versao comercial F2B;
- item abaixo da referencia permanece visivel mesmo quando o resultado liquido do pedido e positivo e exige justificativa unica e confirmacao explicita do vendedor;
- a decisao de credito antiga nao abre vendas F2B; aprovacao de desconto, assinatura do comprador e efetividade permanecem fatos futuros e independentes;
- a versao comercial congela documento canonico e SHA-256, sem usar os campos legados de preco como fonte;
- validacoes locais aprovadas incluem instalacao limpa ate 0131, smoke dirigido, regressoes 1B/1D/1E/F2A e dos gates de Pedido, contratos Python, lint, TypeScript, build e Playwright nas cinco resolucoes;
- proximo objetivo apos aprovacao e commit: ORD-01 F2C, decisao governada de desconto; nao implementar nesta entrega.

Matriz vigente:

- `docs/validacoes/OPS_GATE_01_MATRIZ.md`.

## Entregas historicas preservadas

### Pedidos

- `6fd77b7` reorganizou a criacao na sequencia Cliente, Local, Itens,
  Programacao, Revisao e Liberacao;
- `7f50fee` separou consulta gerencial de criacao pelo vendedor: a conta sem
  identidade comercial vinculada nao recebe formulario que o banco recusaria;
- o staging mostra orientacao em PT-BR e preserva a consulta da carteira;
- nenhuma alcada foi ampliada e nenhuma migration foi criada.

### Manuais e inventario

- manuais operacionais genericos foram substituidos por sequencias,
  bloqueios, efeitos e historico especificos;
- o teste de cobertura descobre as rotas publicadas em `page.tsx`;
- a matriz OPS-GATE-01 inventaria paginas, route handlers e 121 Server Actions.

### Clientes

- a busca deixou de depender do recorte previamente carregado e passou a ser
  paginada, normalizada e executada no servidor;
- lista, ficha cadastral e novo cliente sao modos separados na mesma rota
  canonica, sem interface concorrente;
- a ficha utiliza a largura operacional disponivel e carrega relacoes somente
  para o cliente selecionado;
- a migration `0117` adicionou apenas a RPC de leitura governada, sem alterar
  dados, tabelas ou contratos de escrita;
- o contexto de busca e preservado ao abrir a ficha e ao retornar para a lista.

### Cadastros canonicos

- Materias-primas, Produtos PA/PI, Embalagens, Grupos de produto, Tipos de
  insumo e Unidades seguem o mesmo contrato visual homologado em Clientes;
- consulta, ficha e novo cadastro sao modos exclusivos, sem formularios
  concorrentes ou paineis laterais comprimindo a area operacional;
- a Central e a visao de Cadastros tecnicos direcionam explicitamente para as
  rotas canonicas e para o modo de novo cadastro;
- a terminologia de Unidades foi simplificada para o operador, sem alterar os
  valores internos ou contratos do banco;
- nenhuma migration, regra de negocio ou permissao foi alterada.

### Financeiro operacional

- Visao financeira, Comissionamento, Recebimentos, Comissoes e Relatorio a
  pagar usam rotas separadas e navegacao condicionada a alcadas atomicas;
- os indicadores sao calculados sobre toda a base autorizada e nao sobre a
  pagina de detalhes;
- recebimentos pesquisam pedido, cliente, documento, referencia fiscal e
  local de entrega, com referencia documental obrigatoria na gravacao;
- conta corrente, pagamentos e ajustes permanecem fluxos distintos, auditados
  e idempotentes;
- a migration aditiva `0118` organiza consultas, grants minimos e o contrato
  de recebimento sem alterar fatos financeiros existentes;
- o pacote foi aplicado unitariamente no Supabase de staging e permanece
  protegido pelas alcadas atomicas existentes.

### Filas operacionais e Seguranca urgente

- CQ e Ordens usam consulta paginada no servidor e detalhe separado;
- Romaneio consulta por codigo e situacao, pagina 20 registros e carrega itens,
  reservas, logistica, fiscal e movimentos somente para os IDs exibidos;
- Envase consulta por codigo e situacao, pagina 20 ordens e carrega componentes,
  reservas e lotes PA somente para a pagina atual;
- a tela de Seguranca esclarece que bloquear a conta selecionada nao equivale a
  alterar alcadas e nao exclui pessoa, permissoes ou historico;
- a reformulacao integral do ciclo de vida de usuarios continua reservada ao
  `SEC-UX`.

## Validacao historica preservada

- CI `30472806418`: aprovada;
- instalacao limpa `0001` a `0117`: aprovada no job `database-contract`;
- smokes SQL de integridade, rollout, industrial, comercial, estoque,
  Romaneio, Seguranca e importacoes: aprovados;
- regressao Python completa: 695 testes aprovados;
- E2E `30473086759`: aprovado em `1920 x 1080`, `1366 x 768`,
  `768 x 1024`, `390 x 844` e `360 x 800`;
- TypeScript, ESLint e build Next.js: aprovados;
- o smoke anterior de Pedidos confirmou o SHA `8d677ae` e o estado
  `Consulta disponivel, criacao indisponivel` para conta sem identidade de
  vendedor.
- `/api/health`: `status=ok` e `backendConfigured=true`;
- cinco verificacoes responsivas adicionais no staging nao encontraram
  rolagem horizontal, erro tecnico ou divergencia do SHA;
- o smoke autenticado de Clientes confirmou busca por codigo, abertura da
  ficha sem lista lateral, retorno preservando o filtro, novo cadastro isolado
  e SHA `6d5f782`;
- o smoke autenticado dos cadastros canonicos confirmou consulta, criacao e
  ficha em modos exclusivos, sem rolagem horizontal ou erro tecnico, no SHA
  `35a1633`;
- a migration de leitura `0117` foi aplicada unitariamente no staging.
- regressao final local: 705 testes Python, ESLint, TypeScript e build aprovados;
- migration `0118`: instalacao limpa e upgrade `0117 -> 0118` aprovados no
  projeto, container e volume `elite-validation-finance-0118-clean`;
- smoke `PG_FINANCE_OPS_GATE_01B_OK` aprovou RLS, grants, escrita direta
  negada, busca integral, referencia documental, idempotencia e alcadas;
- Playwright financeiro: 15 cenarios aprovados nas cinco resolucoes, sem
  rolagem horizontal no corpo ou na navegacao do dominio.

## Classificacao historica preservada

`OPS-GATE-01`: tecnicamente aprovado.

`OPS-02`: tecnicamente concluido com as ressalvas de `SEC-UX` registradas na
matriz. Nenhuma nova regra de negocio ou migration foi criada neste fechamento.

Todas as rotas e acoes publicadas estao classificadas na matriz. As funcoes
futuras permanecem bloqueadas de forma explicita. Os defeitos P1 encontrados
foram corrigidos; nenhum P0 permaneceu aberto.

O sistema esta protegido contra o catalogo de erros humanos previsiveis
testados. Isso nao constitui declaracao de infalibilidade.

## Proxima tarefa

Revisar e integrar a ORD-01 F2B. Depois da aprovacao e do commit, planejar a
ORD-01 F2C: decisao governada de desconto. Nao iniciar a F2C nesta entrega.
