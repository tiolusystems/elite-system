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
