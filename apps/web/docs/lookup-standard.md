# Elite System — padrão de buscas e seleções

## Objetivo

Nenhuma tela deve inventar seu próprio comportamento de busca de entidades.

O sistema passa a trabalhar com um primitivo único, `SmartLookup`, configurado por contrato e por fonte de dados.

## Tipos de campo

1. **Texto livre** — informação que não referencia um registro do sistema.
2. **Número / data** — entrada tipada, sem lookup.
3. **Select fixo** — conjunto pequeno e estável de valores de domínio, como status de CQ.
4. **Lookup de seleção** — o valor válido precisa ser um registro existente; o formulário envia o ID.
5. **Busca com sugestões** — o usuário pode digitar livremente, mas recebe sugestões de registros conhecidos.

## Fontes

- `local`: opções já carregadas pela página.
- `remote`: consulta paginada em `/api/lookups/[entity]`.

## Registro central

As fontes remotas reconhecidas ficam em `lib/corporate-lookups.ts`, por meio de `CORPORATE_LOOKUP_CONTRACTS`.

Cada contrato declara:

- rótulo funcional;
- comportamento principal (`selection` ou `search`);
- domínio (`corporate` ou `production`).

## Regras de UX

- abrir a lista ao receber foco;
- permitir digitação para refinar;
- suportar teclado (setas, Enter e Escape);
- exibir estado de carregamento;
- exibir erro recuperável;
- permitir limpeza explícita;
- nunca enviar texto visual no lugar do ID quando o campo é referência de entidade;
- manter `select` simples quando o conjunto é pequeno, fixo e governado.

## Produção — primeira migração

A primeira migração cobre:

- busca de OPs em Ordens;
- busca de OPs no CQ;
- busca do catálogo de Fórmulas;
- busca de Ordens de Envase;
- busca de Produto/MP em Estoque;
- busca de Transformações;
- Produto e Lotes de MP em Garantias;
- participantes do CQ;
- Fórmula MAPA, Lote PI, apresentação e Lote de embalagem no Envase;
- Fórmula de reprocessamento em Transformações;
- seletores já padronizados anteriormente em Fórmulas e Ordens passam a usar o mesmo núcleo por compatibilidade.

## Critérios para próximas migrações

Antes de substituir um campo:

1. identificar se é texto livre, domínio fixo, entidade ou busca;
2. confirmar qual valor o backend espera (ID, código ou texto);
3. confirmar a fonte e a regra de autorização;
4. confirmar dependências de contexto;
5. adicionar o contrato remoto apenas quando a lista não estiver disponível localmente;
6. validar lint, build e fluxo funcional antes de integrar.

## Proibições

- não criar novos `datalist` para entidades;
- não criar um terceiro combobox independente;
- não trocar `select` fixo por lookup sem ganho funcional;
- não carregar catálogos grandes inteiros no navegador apenas para obter autocomplete;
- não contornar RLS ou regras de autorização na API de lookup.

<!-- LOOKUP_PRODUCTION_AUTH_GUARD -->
## Autorização de lookups operacionais

Lookups remotos com `scope: "production"` são defesa em profundidade: além de exigir sessão autenticada, a rota `/api/lookups/[entity]` deve confirmar o acesso vigente ao módulo `/producao` por `get_current_route_module_access`.

Regras:

- autenticação isolada não autoriza consulta operacional;
- o frontend não é fronteira de segurança;
- RLS permissiva para `authenticated` não substitui o guard de módulo;
- falha do contrato de autorização deve negar a consulta, nunca liberar por fallback;
- novos scopes operacionais devem declarar e aplicar o respectivo guard antes de consultar dados.

<!-- LOOKUP_COMMERCIAL_PORTFOLIO -->
## Pesquisa de clientes em Pedidos

A tela de Pedidos usa o contrato remoto `clientes-carteira`, em modo `search`.

Esse contrato não consulta o cadastro corporativo irrestrito de clientes. A fonte é a RPC governada `consultar_com_carteira_clientes_paginada`, preservando carteira própria, equipe autorizada e regras comerciais vigentes.

A rota de lookup também exige disponibilidade do módulo Comercial (`/pedidos`). O autocomplete é uma conveniência de interface; a autorização de negócio continua sendo validada no servidor nas operações de pedido.

<!-- LOOKUP_SEARCH_FIRST_UX -->
## Interação search-first

Campos de busca remota seguem um padrão de baixa fricção:

- a lupa é um indicador visual, não um segundo botão de ação;
- o campo não abre estado vazio antes do mínimo de caracteres configurado;
- `Enter` executa a pesquisa normal do formulário;
- a escolha de uma sugestão pode submeter o formulário quando `submitOnSelect` estiver habilitado;
- o botão de limpar permanece disponível quando há conteúdo;
- paginação interna só aparece quando existe outra página real.

Pedidos usa mínimo de 2 caracteres e submissão automática ao escolher uma sugestão. O botão externo `Pesquisar` foi removido por redundância.

<!-- LOOKUP_MIN_QUERY_POLICY -->
## Política de abertura da lista

O SmartLookup abre por padrão ao receber foco, inclusive com consulta vazia (`minQueryLength = 0`). Esse é o comportamento esperado para campos em que a lista completa ou os primeiros registros ajudam a seleção.

Quando uma tela precisa evitar consultas amplas ou estados vazios prematuros, ela define explicitamente um mínimo maior. Pedidos usa `minQueryLength={2}` e, portanto, só abre sugestões a partir de dois caracteres.

A regra deve ser configurada por contexto; não deve existir um mínimo global que silenciosamente remova listas suspensas de outros consumidores.

<!-- LOOKUP_CONTEXTUAL_ACTION -->
## Ação contextual ao escolher sugestão

`SmartSearchField` pode receber `onOptionSelect` quando a escolha de um registro possui uma ação contextual inequívoca.

No Controle de Qualidade, escolher uma OP na lista abre diretamente `/producao/qualidade/{opId}`. A busca textual por `Enter` ou pelo botão do formulário continua disponível para consultas amplas.

A navegação não é comportamento global do SmartLookup: cada consumidor deve declarar explicitamente sua ação.

<!-- LOOKUP_CQ_STATE_SCOPE -->
## Escopo de OP no Controle de Qualidade

O lookup genérico `ops-producao` permanece disponível para consumidores que precisam pesquisar ordens independentemente da etapa.

O Controle de Qualidade usa contratos próprios, alinhados à mesma regra da tabela da tela:

- `ops-cq-fila`: somente OP com `status = in_process`;
- `ops-cq-historico`: somente OP com `status = completed`.

A aba ativa determina qual lookup é usado. Assim, uma OP finalizada não aparece como sugestão na fila operacional, e uma OP ainda em processo não aparece como sugestão no histórico.

<!-- LOOKUP_SELECTION_DISCLOSURE -->
## Affordance de busca e seleção

Os dois modos do SmartLookup têm interação visual distinta:

- `search`: usa ícone de busca decorativo e aceita pesquisa textual;
- `selection`: usa acionador explícito de lista (`▾`), além de abrir ao focar ou clicar no campo.

Campos de seleção de entidades existentes não devem depender apenas do foco para revelar que possuem uma lista disponível.
