# Decisao arquitetural - POPs e documentos controlados

## Estado

Decisao aprovada por Luciano para implementacao futura. Este documento define
propriedade, versionamento e vinculos, mas nao cria nesta etapa o catalogo, a
rota ou o schema dos POPs.

## Propriedade e localizacao

Os Procedimentos Operacionais Padrao pertencem ao dominio `pcp`, na fronteira
de Controle de Qualidade.

Localizacao funcional prevista:

`Controle -> Qualidade -> POPs e documentos controlados`

A rota canonica sera definida somente depois do inventario das rotas e
contratos vigentes. Nao sera criado um novo modulo.

## Documento controlado

Cada POP devera possuir, no minimo:

- codigo;
- titulo;
- finalidade;
- revisao;
- data de vigencia;
- situacao;
- referencia documental;
- autor;
- historico de versoes.

Uma versao publicada e imutavel. Correcao gera nova versao. Nao ha exclusao
fisica. Ativacao e inativacao exigem usuario autenticado, alcada especifica,
justificativa e auditoria. Versoes anteriores permanecem consultaveis.

## Vinculos

Um processo pode utilizar um ou mais POPs. O inventario tecnico devera
identificar os vinculos aplicaveis a:

- formula operacional;
- tipo de processo;
- producao;
- separacao e conferencia de materia-prima;
- formulacao;
- amostragem;
- Controle de Qualidade;
- limpeza e liberacao de equipamento;
- envase.

O contrato nao sera reduzido a uma coluna `pop_id` quando a relacao for
muitos-para-muitos. Nenhuma estrutura concorrente sera criada antes do
inventario.

## Congelamento na Ordem de Producao

Ao abrir uma OP, o sistema devera congelar as versoes dos POPs aplicaveis
naquele momento. Revisoes futuras nao alteram OP aberta, iniciada ou
finalizada.

O historico da OP preservara:

- codigo do POP;
- titulo;
- revisao;
- vigencia utilizada.

Na impressao da OP sera exibida apenas a secao `Procedimentos aplicaveis`, com
esses quatro dados. O texto integral do POP permanece no cadastro controlado.

## Controle de Qualidade

O detalhe do CQ exibira os POPs aplicaveis somente para consulta. A execucao
podera registrar:

- procedimento observado;
- etapa ou controle relacionado;
- conformidade;
- desvio;
- nao conformidade;
- observacao;
- acao corretiva, quando contratada.

O editor de POP nao pertence a tela de execucao do CQ.

Separador, conferente, formuladores, responsavel pelo CQ e responsavel pela
liberacao permanecem pessoas previamente cadastradas e ativas, vinculadas por
`pessoa_id`. Nome livre, JSON e lista textual nao sao fonte operacional.
Assinatura fisica complementa, mas nao substitui, o participante digital.

## Manual e POP

O manual contextual explica como operar o Elite System. O POP determina como
executar o processo industrial ou de qualidade. Um documento nao substitui o
outro.

## Gate de implementacao

Antes de implementar POPs:

1. inventariar tabelas, RPCs, documentos, rotas e vinculos existentes;
2. confirmar a rota canonica;
3. identificar lacunas sem inventar schema por conveniencia;
4. propor, se necessario, um pacote estrutural minimo, aditivo e proprio;
5. manter o trabalho separado do UX-01H - Romaneio.
