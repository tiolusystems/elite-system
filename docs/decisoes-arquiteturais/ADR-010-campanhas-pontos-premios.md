# ADR-010 - Campanhas, pontos, premios e vouchers

Status: aceita e implementada por `DEC-010`.

## Contexto

O Excel registra NF, produto, litros, grupo, pontos e valor de premio. O banco
ja possuia meta e comissao, mas campanha nao e nenhum desses dois conceitos.
Usar `campanha_ref` textual ou lancar premio na conta corrente de comissao
eliminaria a origem da regra e misturaria obrigacoes diferentes.

## Decisao

`metas` possui campanha, versao, regra, recompensa, elegibilidade, pontos,
premios e vouchers. `financeiro` possui somente os eventos de pagamento de
premio monetario. `cadastros` possui o grupo canonico do produto.

| Contrato | Proprietario | Dependencias |
|---|---|---|
| `cad_grupos_produto` | `cadastros` | produtos e campanhas |
| campanha, versao, regra, elegibilidade | `metas` | cadastros |
| pontos, premio e voucher | `metas` | pedidos, faturamento |
| pagamento monetario do premio | `financeiro` | metas |

Configuracao:

- `com_campanhas`;
- `com_campanha_versoes`;
- `com_campanha_regras`;
- `com_campanha_regra_recompensas`;
- `com_campanha_elegibilidades`;
- `com_campanha_versao_ativacoes`.

Fatos:

- `com_campanha_pontos_movimentos`;
- `com_campanha_premios` e `com_campanha_premio_eventos`;
- `com_campanha_vouchers` e `com_campanha_voucher_eventos`;
- `fin_campanha_premio_pagamentos`.

## Chaves naturais e idempotencia

- grupo e campanha: codigo normalizado;
- versao: campanha + numero;
- regra: versao + codigo;
- recompensa: regra + tipo;
- elegibilidade: versao + escopo + identidade;
- historico: batch + linha + pessoa/produto/tipo do fato.

Os fatos e configuracoes versionadas sao append-only. Correcao gera nova
versao, estorno ou evento.

## Campos obrigatorios

- versao, regra, limiar e base (`volume_litros` ou `valor_venda`);
- recompensa tipada: pontos, monetario, voucher de viagem ou beneficio;
- elegibilidade global, por pessoa, area ou cliente;
- pessoa e pontos assinados no ledger;
- pessoa e tipo no premio;
- ator e integridade referencial;
- batch, linha e `Migracao Historica` para `excel_legado`.

## Campos opcionais

- produto ou grupo; ambos nulos significam regra global;
- limite maximo da faixa;
- data de competencia historica, quando ausente;
- codigo e validade do voucher, quando nao informados;
- valor em voucher/beneficio nao monetario;
- referencia relacional da campanha na comissao antiga.

Ausencia permanece nula. Nenhuma data, codigo, regra, premio ou pagamento e
inventado.

## Pendentes de revisao

- toda campanha/regra/fato importado do Excel;
- grupo textual nao resolvido;
- regra sem periodo ou elegibilidade comprovados;
- pontos sem pessoa/NF/produto reconciliados;
- premio pago sem data/evento financeiro comprovado;
- voucher sem codigo ou validade.

Pendencias nao entram em saldo, configuracao atual ou fluxo financeiro.

## Ativacao e simultaneidade

Ativacao exige perfil humano ativo, campanha ativa, versao aprovada com datas,
ao menos uma regra/recompensa aprovada e elegibilidade aprovada. Campanhas
distintas podem estar vigentes simultaneamente. A versao historica importada
nao pode ser ativada automaticamente.

## Separacao de comissao

Pontos, premios, vouchers e pagamento de premio nunca geram movimento em
`fin_comissao_movimentos`. `com_pedido_comissionados.campanha_versao_id` pode
documentar que uma regra de campanha originou percentual de comissao, mas o
valor da premiacao permanece nos ledgers da campanha.

## Backfill

1. `cad_produtos_base.grupo` gera catalogo canonico por termo existente;
2. produto recebe `grupo_id` sem alterar o texto de compatibilidade;
3. nenhuma campanha e criada a partir do simples nome de grupo;
4. `campanha_ref` antigo nao e convertido sem identidade comprovada;
5. nenhum ponto, premio, voucher ou pagamento e fabricado.

## Fora do escopo

- motor automatico de calculo/fracionamento de campanha;
- regra combinada grupo + meta;
- UI, RPC de manutencao ou aprovacao;
- emissao real de voucher ou integracao de viagem;
- pagamento bancario;
- importacao do workbook real.

## Rollback

Antes de fatos dependentes, restaurar backup e voltar ao commit anterior a
`0053`. Remocao manual segue views, triggers, ledgers, configuracoes, FK da
comissao e catalogo de grupo.

Com fatos existentes, rollback destrutivo e proibido. Nova migration deve
preservar pontos, premios, vouchers e pagamentos.

## Consequencias

- varias campanhas podem coexistir sem colisao;
- grupo e regra passam a ser consultaveis por FK;
- saldo de pontos e derivado de eventos;
- premio possui ciclo de vida proprio;
- pagamento monetario fica sob ownership financeiro;
- comissao permanece um ledger independente.
