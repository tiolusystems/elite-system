# Auditoria transversal de UX, navegacao, manuais e Clientes

## Escopo e baseline

- Baseline: `556746c`, branch publicada `feature/0044-production-module-release`.
- Ambiente de publicacao: projeto Vercel privado `elite-system-staging` e Supabase de homologacao.
- Esta auditoria nao autoriza nem usa dados operacionais reais.

## Achados de UX e navegacao

1. O `AuthenticatedAppShell` ja possui marca, cabecalho, sidebar, usuario, ambiente e rodape.
2. Dez rotas ainda renderizavam `topbar`/`topnav` locais. O CSS ocultava esses elementos somente quando filhos diretos de uma estrutura especifica, criando acoplamento fragil ao DOM.
3. Uma falha ou ausencia do catalogo de rollout reduzia a navegacao ao nucleo sem explicar os modulos indisponiveis.
4. Nao havia componente canonico para cabecalho, acoes, painel, formulario e estados operacionais.
5. Os manuais existentes estavam concentrados em Pedidos, Producao e Romaneio e exigiam sair da tela.

## Achados de Clientes

| Estrutura existente | Interface atual | Lacuna |
|---|---|---|
| `cad_clientes` | nome, municipio, UF, codigo legado e aliases | falta ficha por secoes e identificacao empresarial |
| `cad_cliente_documentos` | nao integrada | documentos e situacao documental |
| `cad_cliente_contatos` | nao integrada | contatos ativos/inativos e papel |
| `cad_cliente_propriedades` | consulta parcial | manutencao e detalhe governados |
| `cad_cliente_vendedores` e areas | leitura parcial | historico comercial e vigencia |
| `cad_limites_credito_cliente` | aparece em Pedidos | resumo e historico na ficha, sem mover ownership do Financeiro |
| `action_logs` | nao integrado | linha do tempo cadastral auditavel |

## Contrato adotado

- Somente o shell global controla navegacao e identidade.
- Rotas usam componentes canônicos de workspace e estados.
- Modulo indisponivel por rollout permanece visivel e explicado; ocultacao continua reservada a permissao.
- Manual contextual abre sobre a operacao e e coberto por registro central e teste.
- Clientes sera consulta primeiro, com manutencao explicita por secao.
- Credito permanece propriedade do Financeiro; Cadastros apenas consulta e direciona a acao governada.

## Riscos e ordem de correcao

1. Remover menus locais e o seletor CSS fragil.
2. Consolidar componentes, tokens e responsividade.
3. Cobrir rotas operacionais com manuais contextuais.
4. Integrar estruturas relacionais existentes de Clientes.
5. Criar contrato aditivo apenas para identificacao empresarial, estabelecimentos e enderecos que nao possuem destino relacional adequado.

## Resultado do macrociclo

- shell e navegacao autenticada unificados no commit `09ad95d`;
- manuais contextuais disponiveis em todas as rotas publicadas, com instrucoes
  operacionais especificas no commit `82a2774`;
- ficha completa de Clientes governada nos commits `b3fe59a` e `e7bc24f`;
- Pedido unificado por tipo, sempre bloqueado ate liberacao, com PDF protegido e
  totais fisicos derivados nos commits `40429a7`, `c38511e`, `c431f2d` e
  `9f9d044`;
- staging com health `ok`, backend configurado e rota de Pedidos protegida;
- 511 testes aprovados; nenhum dado operacional, segredo ou workbook foi
  versionado.

PWA permanece adiada. A sequencia retorna a Formula, Garantias, OP, CQ, Envase,
OP MAPA e Estoque, usando os contratos e manuais agora consolidados.

## Atualizacao da revisao integral em 2026-07-25

Esta auditoria foi revisitada a partir do bloco publicado na branch
`feature/0044-production-module-release`. Os commits funcionais desta revisao
sao `c860d49`, `28ef700` e `e7b9599`; os commits documentais e de contrato de
manuais sao `8209dcf` e `7700287`.

Foram confirmados:

- shell unico e navegacao estavel nas rotas canonicas;
- manuais registrados para as rotas operacionais publicadas;
- estados de estoque e rastreabilidade sem exibicao deliberada de IDs;
- filtros de cliente, pedido, romaneio e recolhimento por valores apresentados,
  resolvidos internamente antes das RPCs governadas;
- ausencia de migration, alteracao de banco, RLS, RPC ou regra de negocio nesta
  revisao.

O CI `30140598039` foi acionado para o commit `e7b9599`. A classificacao desta
revisao permanece **aprovado com ressalvas** ate a publicacao do frontend no
projeto correto `elite-system-staging` e a execucao da cadeia completa pelo
navegador. Os smokes SQL e os contratos de banco existentes continuam sendo
validacoes de contrato; nao substituem o ensaio operacional full-stack.
