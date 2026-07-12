# Matriz Excel para schema do Elite System

Status: gate arquitetonico T2, levantado em 2026-07-12.

O workbook real nao pertence ao repositorio. Esta matriz registra somente nomes
de abas, tabelas e colunas. Nenhum valor operacional foi versionado.

## Legenda

| Codigo | Tratamento |
|---|---|
| `D` | destino direto existente |
| `T` | destino existente, com conversao, agrupamento ou resolucao de identidade |
| `R` | valor derivado usado apenas na reconciliacao |
| `P` | dado deve ficar pendente ate resolucao humana ou regra aprovada |
| `B` | bloqueio: falta destino relacional ou contrato indispensavel |
| `S` | preservado no source ledger, sem gerar fato operacional |

Independentemente do codigo, todo valor analisado deve ser preservado em
`source_workbooks`, `source_tables` e `source_rows`. A relacao com o registro
aplicado deve ser gravada em `imported_records`. Assim, `R`, `P`, `B` e `S` nao
significam descarte.

A cobertura mecanica completa permanece fora do repositorio, em
`01-original/analise-importacao-local/02_COBERTURA_TODAS_COLUNAS.csv`: 3.095
referencias de coluna, incluindo colunas usadas fora de tabelas estruturadas,
todas com status, destino e regra. O gerador local terminou com zero coluna sem
classificacao (`review_required = 0`). O arquivo nao pode ser enviado ao Git
porque contem nomes de abas associados a dados mestres.

## Cobertura comum das formulas

As abas 1 e 3 a 120 possuem 119 tabelas de formula. Os nomes variam, mas as
colunas abaixo cobrem todas as assinaturas encontradas.

| Origem | Destino candidato | Codigo | Regra |
|---|---|---:|---|
| nome da aba | `cad_produtos_base.id` | `T` | resolver produto por nome/alias; duplicatas `(2)` nunca criam produto automaticamente |
| nome da tabela e linha | source ledger | `D` | preservar `sheet`, `table`, `ref` e linha Excel |
| `MATÉRIA PRIMA` | `pcp_formula_itens.materia_prima_id` | `T` | resolver por SKU, nome e alias aprovado |
| `Und/L` | `pcp_formula_itens.quantidade` e `unidade` | `B` | representa concentracao por litro; o schema nao explicita a base de rendimento da formula |
| `QUANTIDADE`, `PRODUÇÃO`, `SIMULA`, `PRODUZIR` | quantidade de batelada | `R` | valor dependente do volume simulado; reconciliar contra `Und/L` |
| `Unidade` | `pcp_formula_itens.unidade` | `T` | canonicalizar unidade; hoje o banco aceita texto livre |
| `SEQ`, `OBS` | etapa e ordem de adicao | `B` | 994 linhas preenchidas; 245 usam texto/fase e nao cabem em uma simples ordem numerica |
| `Lote` | nenhum campo da formula | `R` | lote corrente do estoque, nao componente permanente da receita |
| `R$/L`, `R$/batelada`, `R$/Und` | custo recalculado | `R` | reconciliar com movimentos e valores de MP |
| `% Partic. Form.`, `% Partic. R$/L` | memoria de calculo | `R` | derivar da formula e do custo vigente |
| `ESTOQUE MP`, `ESTOQUE MATÉRIA PRIMA` | views de saldo MP | `R` | snapshot derivado |
| `STATUS`, `STATUS MP` | validacao derivada | `R` | recalcular no sistema |
| `Coluna1`, `Coluna2` | source ledger | `S` | cabecalho residual sem contrato de negocio |

Foram localizadas 1.293 linhas de componentes. Quarenta possuem materia-prima,
mas nao possuem nem quantidade de batelada nem `Und/L`; devem virar pendencia,
nunca quantidade inventada.

## Cobertura comum das garantias

Ha 112 tabelas de garantias ligadas a formulas. O primeiro cabecalho varia com
o nome do produto.

| Origem | Destino candidato | Codigo | Regra |
|---|---|---:|---|
| primeira coluna (`Garantias...`) | catalogo de nutriente | `B` | o workbook possui catalogo proprio, mas o banco repete `nutriente text` sem FK |
| `PP (%/L)` | garantia/especificacao por produto | `B` | falta distinguir garantia calculada da formula e garantia documental MAPA |
| `PV (Kg/L)` | garantia/especificacao por produto | `B` | mesma classificacao obrigatoria de fonte e finalidade |
| `Kg Total`, `Ideal`, `Coluna1` | memoria/reconciliacao | `R` | nao promover a fato sem semantica aprovada |

A aba `Garantias.Tabela180.Garantias` contem 61 entradas e deve alimentar um
catalogo normalizado. Uma tabela de formula possui nutrientes sem valor PP/PV.

## Cadastros mestres

### `CADASTRO MATÉRIA PRIMA.CADASTRO_MATERIA_PRIMA`

| Coluna Excel | Destino | Codigo | Regra |
|---|---|---:|---|
| `MATÉRIA PRIMA` | `cad_materias_primas.nome` | `D` | nome normalizado e alias |
| `IBAMA` | `cad_materias_primas.ibama` | `D` | preservar texto original no payload |
| `id_sku_mp` | `codigo_legado`, alias e `sku_corrigido` | `T` | nunca copiar nome como SKU definitivo; 141 preenchidos e 139 distintos |
| `TIPO` | `cad_materias_primas.tipo` | `T` | mapear dominio fechado |
| `ESTOQUE MÍNIMO` | `cad_materias_primas.estoque_minimo` | `D` | unidade depende da unidade base |
| `R$ Estoque Mínimo` | reconciliacao | `R` | quantidade minima vezes custo vigente |
| `R$/Und` | `est_mp_historico_precos` | `R` | preco deve nascer de movimento de aquisicao, nao do cadastro |
| `Densidade` | `cad_materias_primas.densidade` | `D` | positivo quando informado |
| `Código ADS` | `cad_materias_primas.codigo_ads` | `D` | normalizar numero/texto |
| `Ativo/Inativo` | `cad_materias_primas.status` | `T` | mapear para `active`/`inactive`/`pending_review` |
| `NCM` | `cad_materias_primas.ncm` | `T` | preservar zeros e validar oito digitos quando aplicavel |
| `UNIDADE ADOTADA` | `cad_materias_primas.unidade_base_estoque` | `T` | canonicalizar; catalogo de unidades ainda e decisao estrutural |

### `tbl_cadastro_pa.RELACAO_PRODUTOS`

| Coluna Excel | Destino | Codigo | Regra |
|---|---|---:|---|
| `Grupo` | `cad_produtos_base.grupo` | `D` | normalizar sem perder rotulo original |
| `RELAÇÃO DE PRODUTOS` | `cad_produtos_base.nome` | `D` | codigo de produto nao existe no Excel e precisa de regra deterministica aprovada |
| `DENSIDADE Kg/L` | `cad_produtos_base.densidade_kg_l` | `T` | formulas/erros viram pendencia |
| `CUSTO MP` | reconciliacao de formula | `R` | nunca importar como preco mestre |
| `Reg MAPA` | `cad_produtos_base.reg_mapa` | `D` | preservar formato original |
| `pH` | especificacao tecnica do produto | `B` | nao existe tabela de especificacoes/faixas; CQ mede pH, mas nao guarda a especificacao mestre |
| `IBAMA` | `cad_produtos_base.ibama` | `D` | validar formato sem fabricar valor |
| `ADS` | `cad_produtos_base.ads` | `D` | preservar zeros |
| `NCM` | `cad_produtos_base.ncm` | `T` | validar formato quando informado |

### `RELAÇÃO CLIENTES.CLIENTES`

| Coluna Excel | Destino | Codigo | Regra |
|---|---|---:|---|
| `CLIENTES` | `cad_clientes.nome` | `D` | deduplicacao obrigatoria antes de aplicar |
| `CÓDIGO` | `cad_clientes.codigo_legado` | `D` | duplicatas viram pendencia |
| `Vendedor que Cadastrou` | vinculo cliente/pessoa com papel `cadastrou` | `B` | `cad_cliente_vendedores` nao distingue o tipo do vinculo |
| `Vendedor que Atende` | `cad_cliente_vendedores.pessoa_id` | `T` | vinculo ativo apos resolucao da pessoa |
| `A/I` | `cad_clientes.status` | `T` | mapear dominio |
| `CONTATO` | `cad_cliente_contatos` | `P` | campo mistura formatos; separar nome, papel, telefone e email apenas quando seguro |
| `CIDADE` | `cad_clientes.cidade` | `T` | normalizar municipio |
| `UF` | `cad_clientes.uf` | `P` | somente 33 de 344 linhas possuem UF; inferencia exige tabela confiavel e confirmacao |
| `VALOR TOTAL DE COMPRAS` | relatorio de vendas | `R` | reconciliar com pedidos ativos |

### `VENDEDORES.Tabela153241`

| Coluna Excel | Destino | Codigo | Regra |
|---|---|---:|---|
| `FUNCIONÁRIO` | `cad_pessoas_comerciais.nome` | `D` | uma pessoa por identidade, aliases separados |
| `Função` | `cad_pessoa_papeis.papel` | `P` | somente 10 de 45 linhas possuem funcao; mapear papel comercial, nao role Auth |
| `Ativo/Inativo` | `cad_pessoas_comerciais.status` | `T` | mapear dominio |
| `Admissão`, `Demissão` | vigencia do vinculo/papel | `T` | nao confundir relacao trabalhista com privilegio de login |
| `Intervalo Dias`, `Intervalo Meses`, `Intervalo anos` | nenhum fato | `R` | derivados de admissao/demissao |
| `Vendas`, `Bonificações` | relatorio comercial | `R` | recalcular dos pedidos |

### `VEÍCULOS.Tabela153`

| Coluna Excel | Destino | Codigo |
|---|---|---:|
| `VEÍCULO` | `cad_veiculos.descricao` e `codigo_legado` | `D` |
| `PLACA` | `cad_veiculos.placa` | `T` |

## Embalagens

As onze tabelas `CUSTO_*` possuem `Material`, `R$/Und`/`R$/Item` e `R$/L`.
`PESO_EMBALAGENS` possui `EMBALAGENS`, `Kg` e `Volume m³`.

| Origem | Destino candidato | Codigo | Regra |
|---|---|---:|---|
| nome da tabela `CUSTO_*` | `cad_embalagens` | `T` | identificar configuracao comercial de embalagem |
| `Material` | composicao/BOM da embalagem | `B` | nao existe relacao embalagem-componente com quantidade e vigencia |
| `R$/Und`, `R$/Item`, `R$/L` | custo derivado | `R` | recalcular por componentes e precos de MP |
| `PESO_EMBALAGENS.EMBALAGENS` | `cad_embalagens` | `T` | resolver configuracao |
| `PESO_EMBALAGENS.Kg` | tara/peso logistico | `B` | `cad_embalagens` nao possui peso |
| `PESO_EMBALAGENS.Volume m³` | cubagem logistica | `B` | `cad_embalagens` nao possui cubagem externa |

## Movimentos de materia-prima

### `ENTRADAS_MP.ENTRADAS_MP`

| Coluna Excel | Destino | Codigo |
|---|---|---:|
| `DATA` | `est_movimentos_mp_valores.data_documento` e movimento | `D` |
| `ORIGEM (NF)` | `documento_ref`/`origem_ref` | `T` |
| `MATÉRIA PRIMA` | `cad_materias_primas.id` | `T` |
| `LOTE` | `est_lotes_mp.codigo_lote_legado` | `T` |
| `QUANTIDADE` | `est_movimentos_mp.quantidade` | `T` |
| `Densidade` | snapshot no payload e validacao do cadastro | `T` |
| `UNIDADE PADRÃO` | `est_movimentos_mp_valores.unidade_origem` e conversao | `T` |
| `CUSTO` | `valor_materia_prima` | `T` |
| `FRETE R$/Kg(L)(UND)` | `frete` | `T` |
| `Dif. ICMS` | `difal_icms` | `D` |
| `VALOR` | memoria/reconciliacao | `R` |
| `Custo Total (MP+IMP+Frete)` | `custo_total_legado` | `D` |
| `SALDO LOTE` | `saldo_lote_legado` | `D` |
| `R$/UND Média Ponderada` | `custo_medio_ponderado_legado` | `D` |
| `TIPO` | payload/validacao da MP | `R` |

### `SAÍDAS_MP.SAÍDAS_MP`

| Coluna Excel | Destino | Codigo |
|---|---|---:|
| `DATA` | `est_movimentos_mp.created_at`/data de evento importado | `T` |
| `LOTE OP` | `pcp_ordens_producao.codigo_op` | `T` |
| `MATÉRIA PRIMA` | `est_movimentos_mp.materia_prima_id` | `T` |
| `QUANTIDADE` | movimento de consumo MP | `D` |
| `LOTE` | `est_movimentos_mp.lote_mp_id` | `T` |
| `NOME PRODUTO`, `Qt_Prod`, `Und_L` | memoria e reconciliacao da OP | `R` |
| `ANOTAÇÃO` | `est_movimentos_mp.observacao` | `D` |

## Producao e produto acabado

### `LOTES_PRODUÇÃO.PRODUCAO_LOTES`

| Coluna Excel | Destino candidato | Codigo | Regra |
|---|---|---:|---|
| `DATA` | data da OP/lote | `D` | preservar data historica |
| `LOTE` | lote gerado | `T` | codigo legado e codigo canonico separados |
| `PRODUTO` | `cad_produtos_base.id` | `T` | resolver por nome/alias |
| `QUANTIDADE PRODUZIDA` | produto gerado e movimento de entrada | `T` | unidade e natureza PA/PI nao estao declaradas |
| `CUSTO MP`, `R$/L` | reconciliacao de custo | `R` | nao gerar custo contabil inventado |
| `Densidade OP`, `Ph` | CQ historico parcial | `P` | faltam temperatura, massa, participantes e demais campos exigidos no CQ vivo |
| `STATUS MP`, `OP IMPRESSA` | metadata/status legado | `T` | mapa fechado a definir |
| `TIPO OP` | `pcp_ordens_producao.tipo_op` | `T` | mapear seis valores observados |
| `REG MAPA`, `IBAMA` | reconciliacao com produto | `R` | derivados no workbook |

Bloqueios: `pcp_ordens_producao.formula_versao_id` e obrigatorio, mas o log nao
identifica a versao historica; a saida nao informa se e PA, PI ou PA embalado.
Nao e permitido ligar todas as OPs a formula atual nem inventar transformacoes.

### `SAÍDAS PA.SAIDAS_PA`

| Coluna Excel | Destino | Codigo |
|---|---|---:|
| `DATA SAÍDA` | movimento PA/data de expedicao | `D` |
| `ID_pedido` | `com_pedidos.codigo_legado` | `T` |
| `NOME CLIENTE` | reconciliacao do pedido | `R` |
| `PRODUTO` | `cad_produtos_base.id` | `T` |
| `EMBALAGEM` | `cad_produto_embalagens.id` | `T` |
| `QUANTIDADE BAIXADA` | `est_movimentos_pa.quantidade` | `D` |
| `LOTE` | `est_lotes_pa.codigo_lote_legado` | `T` |
| `Entregador` | atribuicao de entrega/romaneio | `B` |
| `Tipo`, `REG MAPA` | reconciliacao com pedido/produto | `R` |

`exp_romaneios` nao possui relacao com entregador ou veiculo. A origem tambem
nao registra a transformacao historica de granel/PI para PA embalado.

## Pedidos, fiscal, recebimentos e comissoes

### `PEDIDOS_RESUMO.GESTÃO_PEDIDOS`

| Coluna Excel | Destino | Codigo |
|---|---|---:|
| `DATA PEDIDO` | `com_pedidos.data_pedido` | `D` |
| `DATA DA ENTREGA` | previsao ou fato de entrega | `P` |
| `Vencimento 01` a `Vencimento 12` | parcelas do pedido | `B` |
| `STATUS RECEBIMENTO` | posicao financeira legada | `B` |
| `Nº PEDIDO` | `sequencia_propriedade`/codigo legado | `P` |
| `ID_pedido` | `com_pedidos.codigo_pedido` e `codigo_legado` | `T` |
| `NF` | referencia fiscal legada | `B` |
| `STATUS ENTREGA` | status de pedido/expedicao | `T` |
| `TIPO` | `tipo_pedido` e `tipo_item` | `T` |
| `CLIENTE` | `cliente_id` | `T` |
| `PRODUTO` | produto de `produto_embalagem_id` | `T` |
| `EMB.` | embalagem de `produto_embalagem_id` | `T` |
| `ENTREGAR LITROS` | saldo de expedicao | `R` |
| `LITROS` | `com_pedido_itens.quantidade` | `T` |
| `ENTREGUE LITROS` | movimentos PA/romaneios | `R` |
| `R$/L` | `com_pedido_itens.valor_unitario` | `D` |
| `R$ TOTAL` | `valor_total` do item/pedido | `T` |
| `VENDEDOR 1` a `VENDEDOR 4` | `com_pedido_comissionados.pessoa_id` | `T` |
| `%COMISSÃO 1` a `%COMISSÃO 4` | `percentual_comissao` congelado | `D` |
| `R$ COMISSÃO 1` a `R$ COMISSÃO 4` | `valor_previsto`/reconciliacao | `T` |
| `R$ COMISSÃO PAGO1` a `PAGO4` | saldo inicial de comissao paga | `B` |
| `R$ COMISSÃO PAGAR1` a `PAGAR4` | saldo derivado | `R` |
| `PREMIAÇÃO PRODUÇÃO` | campanha/premiacao | `B` |
| `PREMIAÇÃO REVENDA/VENDEDOR` | campanha/premiacao | `B` |

As doze datas de vencimento nao cabem em `com_pedidos.condicao_pagamento` sem
repeticao e perda de estrutura. A NF antiga possui numero, mas nao fornece de
forma confiavel todos os campos obrigatorios de `fat_notas_fiscais`. O status
de recebimento e os valores de comissao paga nao possuem eventos/datas de
recebimento suficientes para fabricar `com_recebimentos`.

## Romaneio

### `ROMANEIO (2).ROMANEIO96`

| Coluna Excel | Destino | Codigo |
|---|---|---:|
| `DATA` | `exp_romaneios.data_romaneio` | `T` |
| `CLIENTE`, `PEDIDO` | pedido relacionado | `T` |
| `ROMANEIO` | `exp_romaneios.codigo_romaneio` | `T` |
| `PRODUTOS`, `EMBALAGEM` | `exp_romaneio_itens.produto_embalagem_id` | `T` |
| `QUANTIDADE` | `quantidade_romaneada` | `T` |
| `LOTES` | reservas/lotes PA | `P` |
| `Kg Emb`, `Volumes`, `Peso Líquido`, `Peso Bruto`, `Volume m³` | calculo logistico | `B` |

A tabela e um snapshot corrente com formulas, nao um livro historico completo.
Os calculos logisticos dependem do peso e da cubagem de embalagem ausentes.

## Pontuacao, campanhas e premiacao

| Origem | Destino candidato | Codigo |
|---|---|---:|
| `Pontuação.Tabela278.NOTA FISCAL` | nota fiscal | `T` |
| `Pontuação.Tabela278.Produto` | produto | `T` |
| `Pontuação.Tabela278.Litros` | fato de campanha | `R` |
| `Pontuação.Tabela278.Grupo` | grupo/regra | `T` |
| `Pontuação.Tabela279.Grupo` | campanha/faixa | `B` |
| `Pontuação.Tabela279.Litros` | limiar da regra | `B` |
| `Pontuação.Tabela279.Pontos Revenda` | regra de pontos | `B` |
| `Pontuação.Tabela279.Valor Prêmio a Pagar` | premio gerado | `B` |

O banco possui ledger de metas, mas nao possui cadastro versionado de campanha,
regra de pontos, premio ou voucher. Esses conceitos nao sao comissao.

## Relatorios, saldos e simulacao

As abas/tabelas abaixo nao geram fatos. Todas as colunas ficam no source ledger
e alimentam reconciliacao:

- `ANÁLISE ESTOQUE`, `ANÁLISE PEDIDOS`, `ANÁLISE RESULTADOS`,
  `ANÁLISE PRODUÇÃO`, `ANÁLISE_ENT_MP`, `ANÁLISE SAÍDAS PA` e
  `ANÁLISE SAÍDAS MP`;
- `PEDIDOS RELATÓRIOS` e a aba auxiliar `d`;
- `CONTROLE DE ESTOQUE PA`, `CONTROLE DE ESTOQUE MP`,
  `POSIÇÃO ESTOQUE MP PERÍODO`, `POSIÇÃO ESTOQUE PA PERÍODO`,
  `POSIÇÃO LOTES MP` e `POSIÇÃO LOTES PA`;
- `Simulação Produção.SIMULA_PRODUCAO` e
  `Simulação Produção.SIMULA_PRODUCAO_PARAMETRO`;
- `ANOTAÇÕES` e `Índice` ficam preservadas como documento/source ledger;
- `Planilha1` esta vazia e permanece registrada no inventario.

O relatorio de reconciliacao deve comparar, no minimo, pedidos, faturamento,
entradas MP, saidas MP, saidas PA, producao e saldos de estoque.

## Lacunas bloqueantes consolidadas

1. **Formula e OP historica**: base de rendimento, etapas/fases, versao historica
   desconhecida e classificacao PA/PI/embalado.
2. **Catalogos tecnicos**: nutrientes sem FK, unidade livre e falta de
   especificacao de produto para pH/faixas.
3. **Embalagem e expedicao**: BOM de embalagem, peso, cubagem, transformacao e
   vinculo de entregador/veiculo.
4. **Financeiro/fiscal legado**: parcelas, posicao recebida sem evento detalhado,
   comissao paga sem evento e NF apenas referenciada.
5. **Campanhas/premiacao**: regras de pontos, premios e vouchers sem destino.
6. **Vinculo comercial do cliente**: `cadastrou` e `atende` nao sao papeis
   distintos no relacionamento atual.

## Politica recomendada

- nao enfraquecer tabelas vivas com dados inventados;
- criar contratos explicitos para legado e manter incerteza visivel;
- fatos derivados do Excel servem para reconciliacao, nunca para duplicar
  movimentos;
- inferencia inevitavel deve produzir pendencia ou evento marcado como
  `inferido`, com regra, autor e justificativa;
- a aplicacao integral continua bloqueada ate autorizacao das decisoes acima.
