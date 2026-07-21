# Governanca de dados e linguagem PT-BR - UX-01C

## Finalidade

Este documento e um gate obrigatorio das telas de Cadastros do Elite System.
Ele integra o plano UX-01C e nao cria fase paralela, modulo novo ou mudanca na
ordem vigente.

Cada etapa UX-01C inventaria e corrige somente os campos da tela em trabalho.
O inventario de um modulo diferente fica proibido ate a respectiva etapa.

## Politica de linguagem PT-BR

- Todo texto apresentado ao usuario deve estar em portugues do Brasil.
- Rotulos devem usar o termo operacional conhecido pela Elite, sem nomes de
  tabela, coluna, RPC, enum, chave estrangeira ou detalhe do PostgreSQL.
- Identificadores tecnicos podem permanecer no backend, URL, banco e logs, mas
  nao podem aparecer como texto de interface.
- Mensagens de erro devem explicar o problema e a acao possivel, sem revelar
  SQL, stack trace, policy RLS ou mensagem bruta do provedor.
- Siglas reconhecidas pelo dominio, como CNPJ, CPF, NCM, MAPA, MP, PA e PI,
  podem ser exibidas com seu significado contextual quando necessario.

## Valor interno e rotulo exibido

Valor interno e rotulo sao contratos diferentes.

Exemplo:

| Valor interno | Rotulo PT-BR |
|---|---|
| `active` | Ativo |
| `inactive` | Inativo |
| `pending_review` | Em revisao |

Regras:

- manter valores internos estaveis sempre que eles forem validos;
- traduzir de forma centralizada na camada de apresentacao por mapeamento
  fechado e testado;
- nunca montar o rotulo substituindo underscores por espacos;
- valor sem rotulo governado deve falhar de forma visivel no teste, em vez de
  ser exibido cru;
- alteracao de valor interno, enum ou constraint exige avaliacao de impacto e,
  quando aplicavel, migration autorizada.

## Classificacao dos campos

Todo campo da tela em trabalho deve pertencer a uma destas classes:

Para o gate executivo, a classificacao primaria e obrigatoriamente uma entre:
`Texto livre`, `Valor controlado`, `Relacionamento` ou `Calculado`. As classes
mais especificas abaixo detalham validacao e apresentacao sem criar uma quinta
categoria primaria.

| Classe | Uso correto |
|---|---|
| Identificador | Codigo estavel, gerado ou informado conforme regra de negocio |
| Catalogo controlado | Valor controlado cuja fonte de verdade e governada |
| Relacionamento | Selecao de outra entidade por ID/FK, nunca por texto interpretado |
| Estruturado | Valor controlado como data, documento, telefone, e-mail, unidade ou numero |
| Booleano | Valor controlado apresentado como checkbox ou controle equivalente |
| Texto livre justificado | Texto livre cujo vocabulario nao pode ser fechado |
| Derivado | Calculado e apresentado como somente leitura |
| Auditoria | Autor, data, origem e historico; normalmente nao editavel pelo usuario |

## Matriz obrigatoria por tela

Antes de alterar uma tela de Cadastros, criar no documento da etapa uma matriz
somente com os campos dessa tela:

| Campo | Finalidade | Tipo atual | Tipo correto | Fonte de verdade | Dependencias | Valor interno | Rotulo PT-BR | Migration? |
|---|---|---|---|---|---|---|---|---|
| Exemplo | Explicar o uso operacional | Texto/select/etc. | Classe governada | Tabela, regra ou usuario | Entidade/regra relacionada | Valor persistido | Texto exibido | Nao/Sim/Decisao pendente |

Se a fonte de verdade ou regra relacional nao existir, preencher `Decisao
pendente`, registrar a lacuna e interromper a alteracao de schema.

## Listas inteligentes

- Usar lista somente quando houver catalogo ou relacionamento governado.
- A opcao deve carregar `{ id, label }`; o ID e o valor persistido e o rotulo e
  apenas apresentacao.
- Proibir interpretacao de strings como `123 | nome` para recuperar IDs.
- Busca deve aceitar nome, codigo e aliases governados quando disponiveis.
- Resultados devem identificar homonimos com contexto suficiente.
- Listas dependentes devem respeitar o contexto selecionado na lista pai,
  consultar pelas chaves relacionais e limpar selecao filha que se torne
  invalida quando o contexto mudar.
- Listas extensas devem ter busca, estado carregando, vazio, erro e sem
  permissao.
- Itens inativos nao entram em novas operacoes, mas continuam visiveis no
  historico quando necessario.
- Nao criar opcao, catalogo ou relacionamento automaticamente a partir do texto
  digitado.

## Campos livres

Texto livre e permitido somente quando o conteudo e genuinamente aberto, como
observacao ou detalhe complementar.

- Nao usar texto livre para status, papel, UF, unidade, tipo de documento,
  motivo padronizado ou relacionamento.
- Definir finalidade, tamanho, obrigatoriedade e tratamento de espacos.
- Motivo com opcao `Outro` exige detalhe complementar.
- Texto livre nao pode alterar alçada, classificacao ou relacionamento por
  inferencia.

## Relacionamentos

- Relacoes consultaveis devem usar tabelas, chaves estrangeiras e vigencia
  quando a relacao mudar ao longo do tempo.
- O frontend envia o identificador estavel; o backend valida existencia,
  status e permissao.
- JSON e texto nao substituem relacao que precise de filtro, integridade,
  historico ou auditoria.
- Remocao visual nao apaga historico; desativacao, encerramento de vigencia ou
  reversao seguem o contrato do dominio.
- Falta de tabela, FK, cardinalidade ou regra de vigencia e lacuna
  arquitetural: documentar e pedir decisao antes de criar migration.

## Opcao Outro

`Outro` nao e atalho para inventar catalogo.

- so aparece quando a regra de negocio admite categoria residual;
- usa valor interno governado, por exemplo `outro`, e rotulo `Outro`;
- exige justificativa registrada e estado de revisao quando utilizado;
- nao cria automaticamente novo item no catalogo;
- recorrencia de detalhes iguais deve gerar proposta de evolucao do catalogo,
  nunca promocao automatica;
- quando a regra nao admite residual, a opcao deve ser ausente.

## Lacunas e mudancas de schema

Ao encontrar catalogo ou relacionamento ausente:

1. manter o backend e os valores existentes estaveis;
2. registrar campo, regra, impacto e fonte de verdade ausente;
3. indicar ownership e dependencias;
4. apresentar a decisao necessaria a Luciano;
5. nao criar migration, tabela, enum ou FK sem autorizacao proporcional.

Dados ausentes nunca devem ser inventados para liberar uma tela.

## Testes obrigatorios

Cada etapa UX-01C deve incluir testes que falhem quando a tela apresentar:

- underscores em valores de negocio;
- enums ou status crus em ingles;
- nomes de tabela, coluna, RPC ou identificador tecnico;
- mensagem bruta do banco, Supabase ou framework;
- relacionamento obtido por parsing de texto;
- campo livre onde a matriz determina catalogo governado.

Os testes devem preservar os valores internos e validar os rotulos PT-BR.

## Gate por etapa UX-01C

Antes de codificar:

1. inventariar somente os campos da tela atual;
2. classificar cada campo;
3. identificar fonte de verdade e dependencias;
4. registrar valor interno e rotulo PT-BR;
5. apontar lacunas e migrations eventualmente necessarias;
6. obter decisao antes de mudar schema ou arquitetura.

Durante a implementacao:

- corrigir linguagem e controles dentro da etapa vigente;
- preservar backend e valores internos sempre que possivel;
- nao ampliar a revisao para outros modulos.

## Criterios de homologacao

Uma tela de Cadastros somente pode ser homologada quando:

- todos os campos visiveis constam na matriz da etapa;
- rotulos, opcoes, ajuda e mensagens estao em PT-BR operacional;
- nenhum identificador tecnico aparece ao usuario;
- listas usam fontes governadas e IDs estaveis;
- listas dependentes respeitam o contexto e as chaves relacionais;
- campos livres possuem justificativa registrada;
- relacionamentos respeitam cardinalidade, vigencia e ownership;
- lacunas de schema estao decididas ou explicitamente bloqueadas;
- estados carregando, vazio, erro, sem permissao e sucesso foram testados;
- testes automatizados de linguagem e controles passaram;
- responsividade e fluxo funcional foram demonstrados;
- Luciano realizou homologacao visual e funcional explicita antes do commit.

## Aplicacao imediata

O primeiro uso desta governanca foi ampliado por autorizacao para o macrociclo
UX-01C completo. O inventario consolidado vigente esta em
`docs/UX01C_INVENTARIO_CONSOLIDADO.md` e abrange somente os grupos de
Cadastros. A implementacao permanece bloqueada no gate estrutural registrado
nesse documento; nenhum catalogo, relacionamento ou regra ausente pode ser
inventado pela interface.

## Evolucao segura dos cadastros

- Campo estrutural novo exige regra definida, ownership, tipo, impacto
  historico e backfill sem dados inventados.
- Campo controlado aponta para catalogo governado ou constraint fechada; o
  frontend envia ID ou valor interno e exibe rotulo PT-BR.
- Relacionamento consultavel exige PK, FK, cardinalidade, comportamento de
  exclusao, indice, RLS, grants e RPC auditada. Texto e JSON nao substituem FK.
- Campos complementares configuraveis poderao existir futuramente apenas para
  informacao auxiliar e nao critica, apos decisao arquitetural especifica.
- Campos configuraveis ficam proibidos para SKU, unidade, tipo de insumo,
  identidade fiscal, estoque, formula, garantia, permissao, comissao ou dado
  usado em integridade, calculo, rastreabilidade ou conformidade.
- Nao sera criado construtor generico de campos nesta fase.
- Toda extensao segue `migration -> RPC -> interface -> testes -> staging`.

## Governanca documental por fluxo

Cada tela ou fluxo homologavel deve atualizar seu manual operacional no mesmo
pacote. O manual combina processo, referencia da tela, permissoes, excecoes,
estados e limitacoes. Nao se documenta funcionalidade planejada como se estivesse
disponivel. O indice e o gate documental ficam em `docs/manuais/README.md`.
