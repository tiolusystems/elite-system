# UX-SYS-01 — Sistema Canônico de Interface

## Objetivo

Fazer o Elite System inteiro parecer e se comportar como um único produto,
sem alterar regras de negócio, dados, RLS, alçadas ou contratos de domínio.

A interface deve reduzir memória, dúvida e risco operacional. A pessoa deve
entender onde está, o que pode fazer, o que aconteceu e qual é o próximo passo.

## Referência interna

Produção é o benchmark interno de comunicação operacional já homologado.
Cadastros contribui com separação entre consulta, ficha e novo registro.
Romaneio contribui com pesquisa, filtros, tabela, paginação e operação contextual.
Pedidos preserva o fluxo guiado quando a tarefa realmente possui etapas.

Nenhuma dessas telas é copiada integralmente. O padrão canônico extrai o que
funciona melhor em cada uma.

## Contrato transversal

Objetos canônicos iniciais:

- `PageWorkspace`: largura e área operacional;
- `PageHeader`: contexto, título, explicação e ações;
- `DomainNavigation`: navegação consistente entre áreas do mesmo domínio;
- `DomainShell`: composição canônica da página de domínio;
- `Panel`: agrupamento operacional;
- `FormSection`: agrupamento de formulário;
- `EmptyState`, `ErrorState` e `PermissionState`: estados explicativos.

Pesquisa, lookup, filtros, tabelas e paginação continuam usando os componentes
corporativos já existentes e serão incorporados ao mesmo contrato por etapas.

## Arquétipos de tela

1. Catálogo: consultar, abrir ficha e criar/manter cadastro.
2. Fila operacional: pesquisar/filtrar, selecionar registro e operar.
3. Processo guiado: executar etapas explícitas quando a ordem importa.
4. Workspace de domínio: navegar entre áreas relacionadas sem trocar de linguagem.
5. Documento: impressão/exportação, separado da interface operacional.

Padronização não significa tornar fluxos diferentes visualmente idênticos.
Significa que objetos equivalentes se comportam e se comunicam da mesma maneira.

## Regras de comunicação

- ação importante usa texto; ícone isolado não é suficiente;
- cor nunca é a única forma de transmitir situação;
- bloqueio explica causa e próximo passo;
- erro informa se houve ou não efeito parcial;
- ação destrutiva ou irreversível deixa a consequência explícita;
- vocabulário operacional permanece em PT-BR simples;
- telas não inventam botão, cabeçalho, navegação ou estado quando já existe objeto canônico.

## Ordem de migração

1. Fundação canônica.
2. Financeiro como primeiro consumidor.
3. Pedidos.
4. Produção.
5. Cadastros e Romaneio.
6. Revisão transversal e remoção das implementações duplicadas.

## Limites desta primeira entrega

A primeira entrega cria `DomainNavigation` e `DomainShell` e migra o shell de
Financeiro. Não altera formulários financeiros, banco, migrations, permissões,
RPCs, cálculos, dados, impressão ou regras de negócio.

O objetivo é provar a fundação antes de ampliar a migração.
