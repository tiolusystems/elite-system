# ADR-007 - Catalogos tecnicos normalizados

Status: aceita e implementada por `DEC-007`.

## Contexto

O workbook legado possui unidades, nutrientes, garantias e pH como textos
livres. O schema anterior repetia `nutriente text` e `unidade text` em fatos de
cadastros e PCP. Isso permitia grafias divergentes, impedia FKs e misturava
garantia documental MAPA com valor calculado.

## Decisao

`cadastros` passa a possuir os catalogos canonicos:

- `cad_unidades_medida` e `cad_unidade_aliases`;
- `cad_nutrientes` e `cad_nutriente_aliases`;
- `cad_parametros_tecnicos`;
- `cad_especificacao_produto_versoes`;
- `cad_especificacao_produto_parametros`;
- `cad_especificacao_produto_ativacoes`.

Os textos antigos continuam como cache de compatibilidade, mas a identidade
consultavel passa a ser FK. Garantias, formulas, resultados de garantia da OP e
MP recebem as novas referencias tipadas.

## Ownership e dependencias

| Contrato | Proprietario | Consumidores |
|---|---|---|
| unidades, aliases, nutrientes e parametros | `cadastros` | `pcp`, `estoque`, `importacao` |
| especificacoes de produto | `cadastros` | `pcp` e `relatorios` |
| garantia documental MAPA | `cadastros`, compatibilidade em `cad_garantias_produto_mapa` | `pcp` |
| garantia calculada da OP | `pcp` | `relatorios` |

`pcp` nao cria identidades tecnicas por escrita direta. Ele referencia os
catalogos publicados por `cadastros`.

## Chaves naturais e idempotencia

- unidade: `normalize_catalog_term(codigo)`;
- alias de unidade: termo normalizado + contexto;
- nutriente: nome normalizado;
- alias de nutriente: termo normalizado + contexto;
- parametro: codigo normalizado;
- versao de especificacao: produto + tipo + versao;
- parametro de especificacao: versao + parametro;
- historico Excel: indices unicos por `source_batch_id`, `source_row_id` e a
  dimensao necessaria do fato.

## Obrigatorios, opcionais e pendentes

Obrigatorios:

- identidade canonica, status, ator e timestamps;
- FKs de unidade/nutriente nos fatos onde o texto e obrigatorio;
- origem, batch e linha para qualquer registro `excel_legado`;
- `Migracao Historica` como `created_by` de registro historico;
- faixa numerica coerente ou valor informativo, nunca ambos.

Opcionais:

- simbolo do nutriente;
- vigencia quando o contrato nao tiver data conhecida;
- unidade em parametro adimensional;
- supersessao quando a origem nao informa a versao anterior.

Pendentes de revisao:

- unidade ou nutriente desconhecido encontrado no legado;
- especificacao criada do Excel;
- garantia calculada que estava misturada na tabela MAPA.

Nenhum desses registros entra em read model operacional antes de aprovacao.

## Separacao MAPA e calculado

`cad_garantias_produto_mapa_atuais` passa a mostrar somente
`natureza = mapa_documental` e `review_status = approved`.

Valores antigos com `fonte = calculado` recebem natureza
`calculada_formula_legada`, ficam `pending_review` e aparecem somente em
`cad_garantias_produto_calculadas_pendentes`. Resultados novos de calculo
permanecem sob ownership do PCP.

## Ativacao humana

Especificacoes sao append-only. A view atual exige um evento em
`cad_especificacao_produto_ativacoes`. O ator `Migracao Historica`, por ser nao
humano, e impedido por trigger de criar esse evento.

## Backfill

1. unidades tecnicas comuns sao semeadas como referencia de sistema;
2. `N/Nitrogenio`, ja usado pelo contrato de garantia do PCP, e a unica
   referencia de nutriente semeada; o dicionario comercial do Excel nao entra
   no Git nem e promovido automaticamente;
3. textos existentes sao deduplicados por termo normalizado;
4. termo ja conhecido como alias nao cria outra unidade;
5. termos desconhecidos nascem `pending_review`;
6. FKs sao preenchidas e validadas antes de se tornarem obrigatorias;
7. triggers de append-only sao suspensos apenas durante o backfill da migration
   e reativados na mesma transacao.

O backfill nao usa nem incorpora valores do workbook real.

## Contrato historico comum

`enforce_historical_record_contract` exige para `excel_legado`:

- `source_batch_id` e `source_row_id` juntos;
- batch e linha pertencentes ao mesmo workbook;
- `created_by` igual ao ator `migracao_historica`;
- status de revisao definido pelo trigger da tabela.

Esse helper e reutilizavel pelas decisoes T3 seguintes.

## Rollback

Rollback operacional preferido: restaurar backup do banco de teste e voltar ao
commit anterior a `0050`. Nao existe down migration automatica.

Rollback estrutural manual somente e permitido antes de dados dependentes:

1. remover views e triggers novos;
2. remover FKs/colunas adicionadas aos fatos existentes;
3. remover tabelas de especificacao, aliases e catalogos na ordem inversa;
4. restaurar as views de garantia da migration `0044`.

Depois de dados reais, rollback destrutivo e proibido; deve haver migration de
compatibilidade e restauracao ensaiada.

## Consequencias

- grafias passam por aliases governados;
- formulas e garantias deixam de depender apenas de texto;
- o importador integral podera registrar pendencias sem promover historico;
- telas futuras precisarao de operacao auditada para aprovar catalogos e ativar
  especificacoes;
- `DEC-008` deve usar `cad_unidades_medida` nas conversoes e embalagens.
