# ADR-013 - Base unica por litro, custos e garantias por lote

## Contexto

Formulas, planejamento de OP, reservas, custos e garantias precisam usar a
mesma escala. Bases por massa final, batelada, reator ou quantidade fixa criam
resultados diferentes para a mesma receita e dificultam reconciliacao.

## Decisao

Toda formula operacional da Elite representa a quantidade necessaria para
produzir `1 L` de produto final. As unidades admitidas sao:

- `kg/L produzido` para materiais controlados em massa;
- `L/L produzido` para materiais controlados em volume;
- `UN/L produzido` para embalagens e seus componentes.

A necessidade da OP sera calculada por `quantidade_por_litro x
volume_planejado_da_OP`. Formula nunca referencia lote. A OP congela a versao
da formula e registra lotes reservados e consumidos.

Para cada apresentacao, a necessidade da embalagem e derivada da capacidade:
uma embalagem de 5 L corresponde a `0,2 UN/L`; uma de 20 L, a `0,05 UN/L`.
O banco preserva o valor numerico normalizado. A interface pode tambem mostrar
"1 unidade para cada 5 litros". Nenhum arredondamento silencioso e permitido;
o plano de embalamento precisa resultar em unidades inteiras.

## Formula versionada

- append-only, sem edicao direta ou exclusao;
- alteracao cria nova versao com justificativa;
- permissoes distintas para criar e ativar versao;
- diff, autor, data e historico integral consultaveis;
- nova ativacao nao altera OP anterior;
- a interface usa "Criar nova versao a partir desta".

## FIFO e lotes

A sugestao padrao usa lotes disponiveis por primeiro movimento de entrada, com
desempate deterministico, distribuindo a necessidade por quantos lotes forem
necessarios. Isso nao e desvio. Ignorar saldo de lote mais antigo exige
permissao e justificativa auditada. Lotes bloqueados, esgotados ou cancelados
nao participam. Bloqueio posterior a reserva invalida a reserva e impede o
inicio da OP ate substituicao explicita.

## Custos

O custo planejado soma a quantidade reservada por lote multiplicada pelo custo
unitario congelado do lote. O custo final usa a quantidade efetivamente
consumida. O snapshot preserva unidade, conversao, origem, data e moeda;
alteracoes futuras de preco nao recalculam OP historica.

## Garantias

O sistema preservara memoria de calculo por lote antes da totalizacao e
apresentara:

1. garantia nominal da formula;
2. garantia prevista com lotes reservados;
3. garantia final com lotes consumidos.

Garantia ausente nao equivale a zero. O calculo fica incompleto e identifica os
lotes sem informacao. O fechamento compara volume, densidade, massa, consumo,
custo e garantias previstos e realizados. Divergencia entre massa informada e
`densidade x volume`, acima da tolerancia governada, gera pendencia de CQ.

## Limite da migration 0068

A 0068 implementa somente Produtos, apresentacoes, embalagens e composicao
versionada de embalagens, incluindo a base `UN/L`. Nao modifica formula, OP,
reservas, estoque, custos ou garantias. Esses contratos terao pacote estrutural
proprio depois do fechamento da 0068.

## Reator

Capacidade volumetrica e massica, disponibilidade, compatibilidade e limite de
volume da OP ficam como evolucao futura. Reator nao define a base da formula.

## Consequencias

- uma unica escala elimina interpretacoes concorrentes;
- OP e rastreabilidade por lote ficam reproduziveis;
- dados legados sem base comprovada permanecem em revisao;
- conversao historica nunca e inferida silenciosamente;
- arredondamento de embalagem precisa ser decisao operacional explicita.

## Reversao arquitetural

Reverter exige nova decisao formal e nova migration. Dados historicos
registrados em base por litro nao podem ser reinterpretados ou sobrescritos.
