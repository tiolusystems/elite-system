# ADR-012 - Parcelas e posicoes financeira/fiscal legadas

Status: aceita e implementada por `DEC-009`.

## Contexto

O Excel possui ate doze vencimentos por pedido, um status geral de recebimento,
valores de comissao paga e uma referencia textual de NF. A fonte nao informa
eventos nem datas suficientes para criar recebimentos, pagamentos de comissao
ou documentos fiscais completos.

Repetir vencimentos em colunas no pedido viola normalizacao. Transformar
status ou saldo em evento operacional fabricaria uma historia que a fonte nao
prova.

## Decisao

- plano de pagamento e versionado em `fin_pedido_planos_pagamento`;
- cada vencimento ocupa uma linha de `fin_pedido_parcelas`;
- status recebido vira snapshot em `fin_recebimento_posicoes_historicas`;
- comissao paga vira snapshot em `fin_comissao_posicoes_historicas`;
- NF incompleta fica em `fat_referencias_fiscais_historicas`;
- nenhum snapshot promove dado para ledger ou documento operacional.

## Ownership e dependencias

| Contrato | Proprietario | Dependencias |
|---|---|---|
| plano e parcelas | `financeiro` | `pedidos` |
| posicao recebida | `financeiro` | `pedidos` |
| posicao de comissao paga | `financeiro` | `pedidos`, pessoas comerciais |
| referencia fiscal incompleta | `faturamento` | `pedidos` |
| origem e rastreio | `auditoria/migracao` | workbook, tabela e linha |

Pedidos nao recebe colunas repetidas. Faturamento nao escreve no financeiro, e
financeiro nao cria NF. Cada dominio permanece proprietario de seus fatos.

## Chaves naturais e idempotencia

- plano operacional: pedido + versao;
- plano historico: batch + linha;
- parcela: plano + numero;
- parcela historica: batch + linha + numero;
- posicao recebida: batch + linha + pedido;
- posicao de comissao: batch + linha + comissionado;
- referencia fiscal: pedido + referencia normalizada, com batch + linha para
  rastreio da fonte.

## Campos obrigatorios

- pedido, versao e autor no plano;
- plano, numero e vencimento na parcela;
- texto original no status de recebimento;
- comissionado e valor pago informado na posicao de comissao;
- pedido e referencia original na posicao fiscal;
- `excel_legado`, batch, linha, `pending_review` e ator `Migracao Historica` em
  todo fato importado.

## Campos opcionais

- valor previsto de parcela, pois a fonte fornece vencimentos sem rateio
  confiavel;
- vigencia do plano quando a fonte a declarar;
- classificacao normalizada do status recebido;
- data da posicao financeira ou de comissao;
- data de emissao da referencia fiscal.

Ausencia permanece nula. `created_at` e data tecnica de gravacao, nunca data
de recebimento, pagamento ou emissao.

## Pendentes de revisao

- toda posicao historica de recebimento;
- toda comissao paga sem evento/data comprovados;
- toda referencia fiscal sem chave, tipo, emissao, itens e valor completos;
- plano historico cujo valor das parcelas nao foi declarado;
- status legado sem classificacao aprovada.

## Temporalidade

Planos usam versao e vigencia. Uma nova versao substitui a anterior no read
model sem reescrever fatos. O historico importado permanece pendente e nunca e
selecionado como plano operacional atual.

## Integridade e seguranca

- parcela deve compartilhar origem, batch, linha e revisao com o plano;
- fatos novos sao append-only e sem escrita direta de `authenticated`;
- lineage confere se batch e linha pertencem ao mesmo workbook;
- ledgers operacionais e documentos fiscais nao recebem backfill;
- read model atual considera somente `sistema` e `approved`.

## Backfill

Nenhum registro e criado. `condicao_pagamento`, recebimentos, liberacoes,
movimentos de comissao e notas existentes permanecem inalterados. A migration
somente publica os contratos relacionais para a futura importacao.

## Fora do escopo

- importar o workbook;
- classificar automaticamente status legado;
- dividir valor do pedido entre vencimentos;
- inventar data de recebimento ou pagamento;
- transformar referencia fiscal em NF oficial;
- alterar telas, Suporte, MFA ou UI de OP.

## Rollback

Antes de dependencias, restaurar backup do banco de teste e voltar ao commit
anterior a `0055`. Depois de dados importados, rollback destrutivo e proibido;
uma migration corretiva deve preservar posições e origem.

## Consequencias

- elimina as doze colunas repetidas do destino relacional;
- separa agenda financeira de evento de recebimento;
- separa saldo informado de pagamento de comissao comprovado;
- mantem NF incompleta fora do dossie fiscal oficial;
- permite reconciliar o Excel sem contaminar operacao corrente.
