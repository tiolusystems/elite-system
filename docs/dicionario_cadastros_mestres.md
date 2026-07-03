# Dicionario de cadastros mestres

Versao: 0.1
Data: 2026-07-03

## Objetivo

Definir, antes de criar telas e tabelas definitivas, quais dados pertencem a cada cadastro mestre do Elite System.

Este documento e a ponte entre o sistema legado em Excel e o software novo. Ele deve ser revisado em linguagem operacional antes de virar migration, repository, service ou tela.

## Regra de implantacao

Nenhum cadastro mestre deve ser implementado como tabela definitiva sem:

1. campos definidos neste dicionario;
2. origem historica identificada quando vier do Excel;
3. regra de obrigatoriedade;
4. regra de duplicidade;
5. regra de status ativo/inativo;
6. vinculos com outros modulos conhecidos;
7. testes automatizados;
8. gravacao auditada por service com usuario executor;
9. validacao em banco descartavel antes de qualquer dado real.

## Campos tecnicos comuns

Todos os cadastros operacionais devem ter campos tecnicos padronizados.

| Campo | Obrigatorio | Uso |
|---|---:|---|
| `id` | Sim | Identificador interno do software. |
| `codigo_legado` | Quando existir | Codigo original vindo do Excel legado. |
| `source_row_id` | Quando importado | Linha bruta preservada em `source_rows`. |
| `source_batch_id` | Quando importado | Rodada de migracao que criou o registro. |
| `status` | Sim | `active`, `inactive` ou equivalente aprovado. |
| `created_at` | Sim | Data/hora de criacao. |
| `updated_at` | Sim | Data/hora da ultima alteracao. |
| `created_by` | Sim para operacao | Usuario que criou. |
| `updated_by` | Sim para operacao | Usuario que alterou. |
| `payload_origem_json` | Quando importado | Snapshot dos dados originais relevantes. |

Regra: nao excluir fisicamente cadastro em operacao normal. Inativar, corrigir ou unificar com auditoria.

## Status padrao

Padrao inicial:

- `active`: cadastro pode ser usado.
- `inactive`: cadastro preservado, mas nao deve entrar em novas operacoes.
- `pending_review`: cadastro importado, mas precisa revisao antes de uso operacional.

O Excel usa textos como `A/I`, `Ativo/Inativo` e equivalentes. A migracao deve normalizar isso sem perder o texto original.

## Cliente

Fonte historica principal: tabela `CLIENTES`.

Objeto de dominio: `Cliente`.

Finalidade: identificar quem compra, quem recebe atendimento comercial e como pedidos historicos se conectam ao cadastro.

| Campo operacional | Origem atual no Excel | Obrigatorio | Observacao |
|---|---|---:|---|
| `codigo_legado` | `CODIGO` | Sim, se existir | Chave historica do sistema legado. |
| `nome` | `CLIENTES` | Sim | Nome principal do cliente. |
| `apelidos` | Novo | Nao | Grafias usadas em pedido/importacao. |
| `vendedor_cadastrou` | `Vendedor que Cadastrou` | Nao | Deve virar vinculo com `Vendedor`. |
| `vendedor_atende` | `Vendedor que Atende` | Nao | Deve virar vinculo com `Vendedor`. |
| `status` | `A/I` | Sim | Normalizar para status padrao. |
| `contato` | `CONTATO` | Nao | Texto livre inicialmente. |
| `cidade` | `CIDADE` | Nao | Pode virar cadastro de apoio depois. |
| `uf` | `UF` | Nao | Validar UF brasileira quando preenchida. |
| `valor_total_compras` | `VALOR TOTAL DE COMPRAS` | Nao | Valor historico/analitico, nao deve ser editado como saldo manual. |

Regras iniciais:

- `nome` nao pode ficar vazio.
- `codigo_legado` nao deve duplicar quando preenchido.
- duplicidade por nome deve gerar alerta, nao bloqueio automatico sem revisao.
- cliente inativo nao deve entrar em novo pedido sem permissao.
- alteracao de vendedor de atendimento deve gerar auditoria.

Perguntas para revisao:

- Existe CNPJ/CPF fora das tabelas ja mapeadas?
- Existe endereco completo ou so cidade/UF?
- Cliente pode ter mais de um contato?
- Cliente pode ter mais de um vendedor ativo?
- Como tratar clientes duplicados do historico?

## Vendedor

Fonte historica principal: tabela `Tabela153241`.

Objeto de dominio: `Vendedor`.

Finalidade: controlar atendimento comercial, comissao e correspondencia de nomes vindos de pedidos/importacoes.

| Campo operacional | Origem atual no Excel | Obrigatorio | Observacao |
|---|---|---:|---|
| `codigo_legado` | Novo | Nao | Pode ser criado se o Excel nao possuir codigo estavel. |
| `nome` | `FUNCIONARIO` | Sim | Nome principal do vendedor/funcionario. |
| `apelidos` | Novo | Nao | Nomes curtos usados na operacao. |
| `grafias_incorretas` | Novo | Nao | Ajuda a migracao a reconhecer nomes digitados errado. |
| `funcao` | `Funcao` | Nao | Deve indicar se e vendedor, entregador, administrativo etc. |
| `status` | `Ativo/Inativo` | Sim | Normalizar para status padrao. |
| `admissao` | `Admissao` | Nao | Data historica. |
| `demissao` | `Demissao` | Nao | Data historica. |
| `vendas_historicas` | `Vendas` | Nao | Indicador historico; nao substituir relatorio calculado. |
| `bonificacoes_historicas` | `Bonificacoes` | Nao | Indicador historico; nao substituir relatorio calculado. |

Regras iniciais:

- `nome` nao pode ficar vazio.
- vendedor inativo nao deve ser sugerido para novo pedido.
- apelidos e grafias incorretas nao podem apontar para mais de um vendedor sem revisao.
- mudanca de status deve ser auditada.

Perguntas para revisao:

- Vendedor e funcionario sao o mesmo cadastro?
- Entregador deve ficar em vendedor/funcionario ou em cadastro separado?
- Comissao fica no vendedor, no produto, no pedido ou em regra propria?

## Materia-prima

Fonte historica principal: tabela `CADASTRO_MATERIA_PRIMA`.

Objeto de dominio: `MateriaPrima`.

Finalidade: controlar insumos, estoque minimo, unidade, custo historico e identificadores regulatórios.

| Campo operacional | Origem atual no Excel | Obrigatorio | Observacao |
|---|---|---:|---|
| `codigo_legado` | `id_sku_mp` | Sim, se existir | Pode virar SKU principal. |
| `nome` | `MATERIA PRIMA` | Sim | Nome do insumo. |
| `tipo` | `TIPO` | Nao | Grupo ou classificacao operacional. |
| `unidade_adotada` | `UNIDADE ADOTADA` | Sim | Unidade de controle do estoque. |
| `densidade` | `Densidade` | Nao | Necessaria para conversoes quando aplicavel. |
| `estoque_minimo` | `ESTOQUE MINIMO` | Nao | Parametro operacional de compras/alerta. |
| `valor_estoque_minimo` | `R$ Estoque Minimo` | Nao | Valor historico/analitico. |
| `custo_unitario` | `R$/Und` | Nao | Historico; custo definitivo sera tratado em formacao de custos. |
| `ibama` | `IBAMA` | Nao | Campo regulatorio. |
| `ncm` | `NCM` | Nao | Campo fiscal/classificacao. |
| `codigo_ads` | `Codigo ADS` | Nao | Identificador operacional/regulatorio. |
| `status` | `Ativo/Inativo` | Sim | Normalizar para status padrao. |

Regras iniciais:

- `nome` nao pode ficar vazio.
- `codigo_legado`/SKU nao deve duplicar quando preenchido.
- unidade deve ser preenchida antes de movimentar estoque.
- materia-prima inativa nao deve entrar em nova compra/producao sem permissao.
- densidade deve ser positiva quando preenchida.

Perguntas para revisao:

- SKU da materia-prima e o campo `id_sku_mp`?
- Unidade adotada pode mudar com estoque existente?
- Existem conversoes oficiais entre kg, litro e unidade?

## Produto acabado

Fonte historica principal: tabela `RELACAO_PRODUTOS`.

Objeto de dominio: `Produto`.

Finalidade: controlar o produto vendido/produzido, seus identificadores regulatorios e atributos usados em pedido, producao, estoque PA e romaneio.

| Campo operacional | Origem atual no Excel | Obrigatorio | Observacao |
|---|---|---:|---|
| `codigo_legado` | Novo ou a definir | Nao | Precisa validar se existe codigo estavel fora do nome. |
| `nome` | `RELACAO DE PRODUTOS` | Sim | Nome principal do produto. |
| `grupo` | `Grupo` | Nao | Familia ou classificacao. |
| `densidade_kg_l` | `DENSIDADE Kg/L` | Nao | Usada em conversoes e producao. |
| `custo_mp_historico` | `CUSTO MP` | Nao | Historico; custo definitivo fica para modulo de custos. |
| `reg_mapa` | `Reg MAPA` | Nao | Campo regulatorio. |
| `ph` | `pH` | Nao | Campo tecnico do produto. |
| `ibama` | `IBAMA` | Nao | Campo regulatorio. |
| `ads` | `ADS` | Nao | Identificador operacional/regulatorio. |
| `ncm` | `NCM` | Nao | Campo fiscal/classificacao. |
| `status` | Novo | Sim | Produto precisa poder ser inativado. |

Regras iniciais:

- `nome` nao pode ficar vazio.
- duplicidade por nome deve gerar alerta.
- produto inativo nao deve entrar em novo pedido, producao ou romaneio.
- densidade deve ser positiva quando preenchida.
- custo de MP importado e informativo ate o modulo de custos ser definido.

Perguntas para revisao:

- Produto possui codigo proprio alem do nome?
- Embalagem pertence ao produto ou ao pedido?
- Produto pode ter varias embalagens possiveis?
- Produto tem formula unica ou varias fichas tecnicas por versao?

## Veiculo

Fonte historica principal: tabela `Tabela153`.

Objeto de dominio: `Veiculo`.

Finalidade: apoiar romaneio/expedicao quando a planilha canonica exigir veiculo ou entrega.

| Campo operacional | Origem atual no Excel | Obrigatorio | Observacao |
|---|---|---:|---|
| `codigo_legado` | Novo | Nao | Criar se necessario. |
| `descricao` | `VEICULO` | Sim | Nome/identificacao do veiculo. |
| `placa` | `PLACA` | Nao | Deve ser normalizada se usada operacionalmente. |
| `status` | Novo | Sim | Ativo/inativo. |
| `capacidade` | Novo | Nao | So criar se for usado no romaneio/carga. |

Regras iniciais:

- `descricao` nao pode ficar vazia.
- `placa` nao deve duplicar quando preenchida.
- veiculo inativo nao deve ser usado em nova expedicao.

Perguntas para revisao:

- Veiculo e obrigatorio no romaneio atual?
- Capacidade, peso ou volume existem na planilha `ROMANEIO` canonica?
- Entregador fica vinculado ao veiculo ou ao romaneio?

## Embalagem

Fonte historica atual: aparece em pedidos e saidas de PA como `EMB.` / `EMBALAGEM`.

Objeto de dominio previsto: `Embalagem`.

Finalidade: padronizar embalagem usada em pedido, produto, estoque PA e romaneio.

| Campo operacional | Origem atual no Excel | Obrigatorio | Observacao |
|---|---|---:|---|
| `codigo_legado` | A definir | Nao | Ainda nao ha tabela de cadastro mapeada. |
| `descricao` | `EMB.` / `EMBALAGEM` | Sim | Pode nascer da ocorrencia historica. |
| `capacidade` | A definir | Nao | Validar se existe em alguma tabela. |
| `unidade` | A definir | Nao | Litro, kg, unidade etc. |
| `status` | Novo | Sim | Ativa/inativa. |

Regras iniciais:

- nao criar cadastro definitivo de embalagem sem revisar as ocorrencias do historico;
- descricao duplicada com grafias diferentes deve gerar fila de revisao;
- embalagem inativa nao deve entrar em pedido novo.

Perguntas para revisao:

- Existe uma tabela de embalagens no Excel?
- Embalagem define quantidade/capacidade ou e apenas texto de pedido?
- Embalagem afeta estoque PA ou apenas faturamento/expedicao?

## Garantia

Fonte historica: pendente de identificacao.

Objeto de dominio previsto: `Garantia`.

Finalidade: ainda precisa definicao operacional antes de modelagem.

Possibilidades a validar:

- garantia comercial do pedido;
- garantia de produto/lote;
- garantia regulatoria;
- garantia financeira;
- outro uso especifico do sistema legado.

Regra: nao codar `Garantia` antes de entender o significado operacional no Excel.

Perguntas para revisao:

- Onde aparece garantia no sistema legado?
- Ela se vincula a cliente, produto, pedido, lote ou entrega?
- Gera prazo, bloqueio, documento ou apenas observacao?

## Cadastros de apoio previstos

Estes cadastros podem ser necessarios, mas nao devem roubar prioridade dos mestres:

- cidades/UF;
- unidades de medida;
- grupos de produto;
- tipos de materia-prima;
- status padronizados;
- tipos de pedido;
- funcoes de funcionario;
- aliases/grafias para importacao.

## Auditorias de cadastros

Cada cadastro deve ter, no minimo:

- contagem Excel x sistema;
- duplicidade de codigo legado;
- duplicidade provavel por nome normalizado;
- registros ativos sem campo obrigatorio;
- registros usados em pedidos/estoque/producao sem cadastro mestre;
- registros inativos usados em operacao nova;
- alteracoes manuais com usuario, antes/depois e motivo quando aplicavel.

## Ordem de implementacao recomendada

1. Revisar este dicionario com o usuario.
2. Ajustar perguntas em aberto.
3. Criar objetos de dominio em `elite_system/domain/cadastros.py`.
4. Criar validators puros.
5. Criar migrations em banco descartavel.
6. Criar repositories com `actor_user_id`.
7. Criar services auditaveis.
8. Criar tela inicial de cadastros.
9. Rodar reconciliacao contra Excel.
10. So entao considerar o bloco de cadastros pronto.
