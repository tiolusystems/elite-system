# Padrão de pesquisa e filtros

Este documento define o contrato visual e funcional de pesquisa do Elite System.
O padrão reduz listas extensas, evita memorização de códigos e mantém RLS e
alçadas como fonte de autorização.

## Escolha do controle

| Situação | Controle | Comportamento |
| --- | --- | --- |
| Lista pequena, estática e integralmente conhecida | `select` | Carrega todas as opções, com rótulos em PT-BR. |
| Lista curta que admite digitação e seleção local | `EntityCombobox` | Filtra opções já governadas e armazena o ID. |
| Entidade relacional ou catálogo crescente | `EntityLookup` | Consulta paginada no servidor, mostra dados humanos e armazena o ID. |
| Critérios opcionais de uma consulta | `AdvancedFilterPanel` | Mantém a pesquisa principal visível e recolhe critérios menos frequentes. |

Texto livre não substitui relacionamento. Quando a operação depende de uma
entidade, o valor persistido ou enviado ao servidor é sempre seu ID.

## EntityLookup

- Abre a primeira página ao receber foco ou ao acionar o botão de consulta.
- Digitar é opcional e reinicia a consulta na primeira página.
- Exibe rótulo principal, informações de contexto e situação traduzida.
- Possui paginação dentro do painel; a página seguinte continua consultando o servidor.
- A seleção preenche um campo oculto com o ID e preserva o rótulo apenas para apresentação.
- `Enter` seleciona, setas movimentam o foco, `Esc` fecha e o botão Limpar remove a seleção.
- Erros são apresentados em PT-BR e não expõem SQL, RPC, tabela ou identificador técnico.

## Dimensões e espaçamento

- Altura mínima de campo e botão: `44 px`.
- Rótulo sempre acima do controle e associado por `htmlFor`.
- Largura mínima útil no desktop: `16 rem`; o grid pode expandir sem deformar o campo.
- Painel de resultados: até `42 rem` no desktop e até `60%` da altura da janela.
- No celular, o painel ocupa a largura útil com margem de `8 px` e permanece dentro do viewport.
- Áreas de toque, paginação e ações mantêm pelo menos `44 px` de altura.

## Paginação e ordenação

- Consultas relacionais usam páginas de 10 a 25 registros.
- Tabelas operacionais usam paginação no servidor e não carregam toda a base no navegador.
- Catálogos são ordenados alfabeticamente quando não existe prioridade operacional.
- Pedidos e Romaneios usam data decrescente e ID decrescente como desempate, pois os registros recentes são o primeiro contexto operacional.
- Alterar filtros reinicia a tabela na primeira página.
- Filtros ativos são visíveis e podem ser removidos individualmente.

## Mobile e teclado

- A barra de filtros passa de colunas para uma única coluna conforme a largura disponível.
- Tabelas viram linhas operacionais empilhadas; não criam rolagem horizontal no `body`.
- O painel avançado permanece recolhível e informa quantos critérios estão ativos.
- Ordem de tabulação: pesquisa principal, situação, filtros avançados, pesquisar e limpar.
- O estado de foco deve permanecer visível em campos, resultados e paginação.

## Segurança

- Toda chamada exige sessão autenticada.
- A API não amplia acesso: consultas usam o cliente autenticado e respeitam RLS e alçadas existentes.
- Lookups retornam somente a página autorizada; `PUBLIC` e `anon` não recebem acesso adicional.
- Filtros nunca substituem validação do servidor ou permissão da operação final.
- Respostas usam `Cache-Control: private, no-store`.

## Aplicação em Romaneios

A consulta de Romaneios oferece pesquisa principal por cliente, documento,
pedido, destino ou código. Os filtros relacionais abrangem cliente, pedido,
propriedade, produto, lote PA, entregador e veículo. Situação, período e NF de
remessa usam controles próprios.

O resultado é ordenado do Romaneio mais recente para o mais antigo e apresenta,
sem IDs técnicos: Romaneio, pedido, cliente, carga, situação, data, entregador e
veículo. Abrir um resultado revela as operações já governadas, sem alterar as
regras de reserva, expedição, cancelamento ou estorno.
