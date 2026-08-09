# ADR-011 - Formulas e OP historicas

Status: aceita e implementada por `DEC-006`.

## Contexto

O Excel informa componentes por unidade/litro e sequencia/fase, mas nao declara
formalmente a base de rendimento. O historico de producao nao identifica qual
versao da formula foi usada e nao classifica de forma confiavel a saida como
PA, PI ou PA embalado. Ligar tudo a formula atual fabricaria rastreabilidade.

## Decisao

`pcp` possui os novos contratos:

- `pcp_formula_rendimentos`;
- `pcp_formula_etapas`;
- `pcp_formula_item_etapas`;
- `pcp_formula_referencias_historicas`;
- `pcp_op_saidas_historicas`;
- `pcp_op_cq_historico_parcial`.

Formula, item, rendimento e etapa carregam origem e linha. A OP possui
`produto_id` e exatamente uma referencia: `formula_versao_id` comprovada ou
`formula_referencia_historica_id` explicitamente desconhecida.

## Ownership e dependencias

| Contrato | Proprietario | Dependencias |
|---|---|---|
| formula, rendimento e etapas | `pcp` | `cadastros` |
| OP e referencia historica | `pcp` | `cadastros` |
| CQ parcial e saida historica | `pcp` | `cadastros`, `estoque` |
| lote/movimento futuro | `estoque` | classificacao aprovada no PCP |

## Chaves naturais e idempotencia

- formula: produto + tipo de receita + versao;
- rendimento: uma linha por versao;
- etapa: versao + sequencia;
- item/etapa: um vinculo por item;
- referencia desconhecida: batch + linha + produto;
- OP: codigo e batch + linha;
- saida/CQ: batch + linha + natureza ou OP.

## Campos obrigatorios

- base, unidade, rendimento, unidade e natureza no rendimento;
- sequencia e fase/instrucao na etapa;
- produto em toda OP;
- exatamente uma referencia de formula;
- evidencia textual para versao desconhecida;
- quantidade/unidade na saida;
- batch, linha e ator `Migracao Historica` no legado.

## Campos opcionais

- ordem numerica quando a fonte possui apenas texto/fase;
- tipo OP normalizado, preservando `tipo_op_legado`;
- lote relacional enquanto existe apenas codigo legado;
- temperatura, massa, volume, participantes e demais CQ ausentes;
- natureza PA/PI enquanto a fonte nao a prova.

Ausencia permanece nula ou `nao_classificada`; nunca recebe valor corrente.

## Pendentes de revisao

- toda formula e OP importada;
- rendimento com natureza nao determinada;
- linha sem quantidade/Und-L;
- referencia de formula desconhecida;
- tipo OP nao mapeado;
- saida sem natureza PA/PI;
- CQ incompleto.

## Regra de formula desconhecida

OP `excel_legado` so pode apontar para formula tambem importada e pendente ou
para `pcp_formula_referencias_historicas`. Ela nunca pode apontar para formula
`sistema`, ainda que essa seja a versao ativa atual. OP viva nao pode usar
referencia desconhecida.

## Saida e estoque

`pcp_op_saidas_historicas` aceita `PA`, `PI` ou `nao_classificada`. A ultima
nao aceita embalagem ou lote. Nenhuma delas cria lote ou movimento nesta
decisao. A classificacao e reconciliacao devem ocorrer antes de uma futura RPC
auditada gerar efeitos fisicos.

## CQ parcial

A tabela parcial aceita somente medidas realmente existentes. Pelo menos uma
medida/observacao deve existir. Campos ausentes nao sao copiados do produto,
formula atual ou outra OP.

## Backfill

1. formula/itens existentes recebem origem `sistema` e `approved`;
2. `created_by` do item herda o autor da versao quando existente;
3. OP existente recebe produto derivado por FK da propria formula;
4. OP existente continua com formula comprovada;
5. nenhum rendimento, etapa, referencia desconhecida, saida ou CQ e criado
   automaticamente.

## Integridade e seguranca

- filho de formula deve compartilhar origem/batch da versao;
- saida/CQ deve compartilhar origem/batch da OP;
- formula historica/pending nao pode ser ativada;
- estado de OP historica e imutavel;
- fatos novos sao append-only e sem escrita direta de `authenticated`;
- read models operacionais excluem historico pendente.

## Fora do escopo

- mapear os seis textos observados de tipo OP;
- aprovar formula/OP importada;
- completar CQ ausente;
- classificar automaticamente PA/PI;
- criar lotes/movimentos;
- alterar UI ou construir o importador.

## Rollback

Antes de dependencias, restaurar backup e voltar ao commit anterior a `0054`.
Depois de OPs/saidas historicas, rollback destrutivo e proibido; nova migration
de compatibilidade deve preservar as referencias explicitas.

## Consequencias

- concentracao passa a ter base/rendimento consultavel;
- texto de fase nao e reduzido a numero;
- versao desconhecida vira fato explicito;
- OP historica nao contamina o fluxo vivo;
- saida e CQ incompletos podem ser preservados sem fabricar estoque.
