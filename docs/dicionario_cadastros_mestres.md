# Dicionario de cadastros mestres

Versao: 0.3
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

Decisao de modelagem: cadastros nao serao tratados como simples listas. Eles carregam regras operacionais de cliente, comissao, estoque, producao, garantias e rastreabilidade. Quando uma regra puder mudar ao longo do tempo, a regra deve ser versionada e auditada, nao sobrescrita silenciosamente.

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

Finalidade: identificar o grupo/cliente comercial unico, suas propriedades/fazendas, CNPJs, contatos, enderecos, vendedores vinculados e como pedidos historicos se conectam ao cadastro.

Decisao: cliente nao pode ser duplicado. Quando houver duplicidade historica, o sistema deve apoiar analise e unificacao, preservando os registros originais e gravando a decisao em auditoria.

| Campo operacional | Origem atual no Excel | Obrigatorio | Observacao |
|---|---|---:|---|
| `codigo_legado` | `CODIGO` | Sim, se existir | Chave historica do sistema legado. |
| `nome` | `CLIENTES` | Sim | Nome principal do cliente. |
| `apelidos` | Novo | Nao | Grafias usadas em pedido/importacao. |
| `vendedor_cadastrou` | `Vendedor que Cadastrou` | Nao | Deve virar vinculo com `Vendedor`. |
| `vendedor_atende` | `Vendedor que Atende` | Nao | Deve virar vinculo com `Vendedor`. |
| `status` | `A/I` | Sim | Normalizar para status padrao. |
| `cidade` | `CIDADE` | Sim | Cidade minima do cadastro. |
| `uf` | `UF` | Sim | UF minima do cadastro. |
| `valor_total_compras` | `VALOR TOTAL DE COMPRAS` | Nao | Valor historico/analitico, nao deve ser editado como saldo manual. |

Subcadastros previstos:

| Subcadastro | Uso |
|---|---|
| `ClientePropriedade` | Fazenda/propriedade vinculada ao mesmo cliente, podendo ter CNPJ distinto. |
| `ClienteDocumento` | CNPJ/CPF/IE por cliente ou propriedade. |
| `ClienteEndereco` | Endereco de entrega, cobranca ou outro tipo. Endereco completo nao e obrigatorio inicialmente. |
| `ClienteContato` | Contatos multiplos: gerente, compras, financeiro, proprietario, operacional etc. |
| `ClienteVendedor` | Mais de um vendedor/agente vinculado ao cliente, com vigencia e status. |
| `ClienteUnificacao` | Registro auditado de duplicidades analisadas e unificadas. |

Regras iniciais:

- `nome` nao pode ficar vazio.
- `cidade` e `uf` sao obrigatorios no cadastro operacional.
- `codigo_legado` nao deve duplicar quando preenchido, salvo em processo de unificacao.
- duplicidade por nome, documento, propriedade ou grafia semelhante deve gerar fila de revisao.
- clientes duplicados devem ser unificados por ferramenta propria, nunca apagados manualmente.
- cliente inativo nao deve entrar em novo pedido sem permissao.
- alteracao de vendedor de atendimento deve gerar auditoria.
- cliente pode ter mais de um vendedor ativo.
- cliente pode ter mais de uma fazenda/propriedade e mais de um CNPJ.
- cliente pode ter mais de um contato com papel diferente.

Perguntas para revisao:

- Onde estao hoje CNPJ/CPF/IE e enderecos completos?
- Quais tipos de contato precisam aparecer na primeira tela?
- O vendedor pode ser vinculado ao cliente inteiro, a uma propriedade ou a ambos?
- Qual deve ser o fluxo de aprovacao para unificar clientes duplicados?

## Pessoa comercial, vendedor e comissionado

Fonte historica principal: tabela `Tabela153241`.

Objetos de dominio previstos: `PessoaComercial`, `PapelPessoa`, `VinculoAgente`, `Comissionado`, `GerenteComercial`, `RegiaoAtuacao`.

Finalidade: controlar vendedores, agentes, tecnicos de campo, funcionarios, comissionados e entregadores quando a mesma pessoa puder exercer mais de uma funcao.

Decisao: vendedor, agente, tecnico de campo, funcionario e entregador nao devem ser modelados como tabelas totalmente separadas sem necessidade. O cadastro principal deve ser uma pessoa/entidade com papeis. Isso permite que um vendedor tambem seja entregador, sem concluir que todo entregador e vendedor.

Tipos comerciais previstos:

| Tipo | Descricao | Pode receber comissao |
|---|---|---:|
| `funcionario_elite` | Pessoa do time interno Elite. | Sim |
| `agente_vinculado` | Agente com vinculo a outro vendedor do time Elite. | Sim |
| `agente_direto_elite` | Agente direto da Elite. | Sim |
| `vendedor_direto_elite` | Vendedor de venda direta Elite. | Sim |
| `tecnico_campo` | Tecnico que faz aplicacoes e pode receber comissao por aplicacao, produto desenvolvido ou parcela de receita. | Sim |
| `entregador` | Pessoa que faz entrega. Nao e vendedor por ser entregador. | Nao por entrega, salvo se tambem tiver papel comercial aprovado. |
| `gerente` | Pessoa que gerencia vendedores, clientes, regioes ou campanhas. | Sim |
| `vendedor_gerente` | Pessoa que vende diretamente e tambem recebe regra gerencial. | Sim |

| Campo operacional | Origem atual no Excel | Obrigatorio | Observacao |
|---|---|---:|---|
| `codigo_legado` | Novo | Nao | Pode ser criado se o Excel nao possuir codigo estavel. |
| `nome` | `FUNCIONARIO` | Sim | Nome principal da pessoa. |
| `apelidos` | Novo | Nao | Nomes curtos usados na operacao. |
| `grafias_incorretas` | Novo | Nao | Ajuda a migracao a reconhecer nomes digitados errado. |
| `tipo_comercial` | Novo | Sim para comissionado | Um dos tipos comerciais previstos. |
| `papeis` | `Funcao` + novo | Sim | Pode incluir vendedor, agente, tecnico, entregador, funcionario etc. |
| `vendedor_responsavel_id` | Novo | Quando agente vinculado | Vendedor Elite responsavel por agente vinculado. |
| `status` | `Ativo/Inativo` | Sim | Normalizar para status padrao. |
| `admissao` | `Admissao` | Nao | Data historica. |
| `demissao` | `Demissao` | Nao | Data historica. |
| `vendas_historicas` | `Vendas` | Nao | Indicador historico; nao substituir relatorio calculado. |
| `bonificacoes_historicas` | `Bonificacoes` | Nao | Indicador historico; nao substituir relatorio calculado. |

Regras iniciais:

- `nome` nao pode ficar vazio.
- vendedor/agente/tecnico inativo nao deve ser sugerido para novo pedido.
- apelidos e grafias incorretas nao podem apontar para mais de um vendedor sem revisao.
- mudanca de status deve ser auditada.
- entregador nunca vira vendedor automaticamente.
- vendedor pode acumular papel de entregador.
- entregador pode ou nao ser funcionario Elite.
- agente vinculado deve apontar para um vendedor responsavel do time Elite.
- tecnico de campo pode receber comissao por aplicacao, desenvolvimento de produto ou parcela da receita.
- gerente pode receber comissao sobre vendedores especificos, regioes de atuacao, clientes sob gestao ou campanhas.
- vendedor/gerente pode acumular comissao propria de venda e comissao gerencial, conforme regra aprovada.

## Comissionamento

Objeto de dominio previsto: `ComissaoPedido`, `RegraComissao`, `CampanhaComercial`, `MetaComissao`, `PremioCampanha`, `ContaCorrenteComissao`, `ComissaoRecebimento`.

Decisao: em um pedido podem existir varios comissionados, cada um com comissao distinta. A comissao e informada na insercao do pedido, mas a liberacao/pagamento depende do recebimento parcial ou integral do cliente.

Campos previstos em `ComissaoPedido`:

| Campo | Obrigatorio | Uso |
|---|---:|---|
| `pedido_id` | Sim | Pedido que gerou a comissao. |
| `comissionado_id` | Sim | Pessoa que recebe. |
| `tipo_comissionado` | Sim | Vendedor, agente, tecnico de campo etc. |
| `base_calculo` | Sim | Valor ou quantidade base da comissao. |
| `percentual` | Quando percentual | Percentual aplicado. |
| `valor_fixo` | Quando fixo | Valor fixo combinado. |
| `condicao_pagamento` | Sim | Recebimento parcial, recebimento integral ou regra aprovada. |
| `status` | Sim | Prevista, liberada, paga, estornada. |
| `campanha_id` | Nao | Campanha vigente aplicada, quando houver. |
| `origem_regra` | Sim | Pedido, gerente, campanha, tecnico, ajuste etc. |

Regras iniciais:

- pedido pode ter multiplas comissoes.
- comissao nao deve ser paga apenas por pedido emitido; depende de recebimento parcial ou integral.
- recebimento parcial libera apenas a parcela proporcional ou regra aprovada.
- ferramenta de recebimento deve calcular comissao ao lancar valores recebidos de cada cliente.
- bonificacao nao gera comissao.
- devolucao abate comissao.
- se a comissao ja foi paga e houver devolucao, o valor deve ser abatido de comissoes futuras.
- comissao pode ser variavel por pessoa.
- podem existir travas individuais por meta, periodo e campanha.
- pode haver mais de uma campanha vigente.
- campanhas podem gerar aumento de percentual, premio, voucher de viagem ou outro beneficio.
- toda alteracao de comissao deve ser auditada com antes/depois, autor e motivo.

Detalhamento: `docs/escopo_comissoes_recebimentos_credito.md`.

Perguntas para revisao:

- Comissao parcial e sempre proporcional ao valor recebido?
- Tecnico de campo recebe por produto desenvolvido, por aplicacao, por receita ou por combinacao?
- Campanhas podem acumular entre si ou ha prioridade?
- Voucher de viagem deve ser tratado como valor financeiro, premio nao financeiro ou ambos?
- Recebimento sera lancado por pedido, NF/parcela ou cliente?
- Como compensar comissao negativa quando houver devolucao depois de pagamento?

## Credito do cliente e pedido por vendedor

Objetos de dominio previstos: `LimiteCreditoCliente`, `AnaliseCreditoPedido`, `PedidoRascunhoVendedor`, `AprovacaoPedido`.

Finalidade: permitir que vendedores preencham pedidos diretamente pelo sistema, com alcadas, consulta de limite de credito, inadimplencia e bloqueios operacionais.

Decisao: vendedor pode ter acesso ao sistema para preencher pedido, mas com permissao limitada. Ele nao deve alterar limite de credito, regra de comissao ou aprovar bloqueios sem alcada.

Campos previstos em `LimiteCreditoCliente`:

| Campo | Obrigatorio | Uso |
|---|---:|---|
| `cliente_id` | Sim | Cliente analisado. |
| `limite_manual` | Nao | Limite definido por usuario autorizado. |
| `limite_calculado` | Nao | Limite sugerido por regra de credito/inadimplencia. |
| `limite_disponivel` | Sim | Limite disponivel no momento do pedido. |
| `status_credito` | Sim | Liberado, reduzido, bloqueado, pendente aprovacao. |
| `motivo` | Nao | Motivo de reducao/bloqueio. |
| `updated_by` | Sim | Usuario responsavel pela ultima decisao. |

Regras iniciais:

- vendedor so ve clientes autorizados para ele.
- vendedor pode criar pedido em rascunho e enviar para aprovacao.
- ao inserir pedido, o sistema deve mostrar limite de credito e alerta de inadimplencia conforme alcada.
- inadimplencia pode reduzir limite ou bloquear pedido.
- pedido acima do limite nao deve ser aprovado automaticamente.
- gerente/financeiro/comercial autorizado pode aprovar excecao conforme alcada.
- aprovacao excepcional de pedido nao modifica o limite permanente do cliente.
- alteracao de limite pertence ao Financeiro e exige permissao individual
  explicita, nunca inferida do papel organizacional.
- revisar pedido e manter limite cadastral sao alcadas independentes.
- a analise de credito usada no pedido deve ficar gravada como snapshot auditavel.

Detalhamento: `docs/escopo_comissoes_recebimentos_credito.md`.

## Materia-prima

Fonte historica principal: tabela `CADASTRO_MATERIA_PRIMA`.

Objeto de dominio: `MateriaPrima`.

Finalidade: controlar insumos, estoque minimo, unidade, custo historico e identificadores regulatórios.

Decisao: `id_sku_mp` deveria ser codigo unico, mas foi usado em parte com nomes de materia-prima. Portanto, ele deve entrar como dado legado para saneamento, nao como SKU confiavel definitivo.

| Campo operacional | Origem atual no Excel | Obrigatorio | Observacao |
|---|---|---:|---|
| `codigo_legado` | `id_sku_mp` | Sim, se existir | Campo legado a sanear; nao confiar como codigo definitivo sem revisao. |
| `sku_corrigido` | Novo | Sim no cadastro final | Codigo unico corrigido da materia-prima. |
| `nome` | `MATERIA PRIMA` | Sim | Nome do insumo. |
| `tipo` | `TIPO` | Nao | Grupo ou classificacao operacional. |
| `unidade_base_estoque` | `UNIDADE ADOTADA` | Sim | Unidade atual de controle do estoque, normalmente padronizada. |
| `densidade` | `Densidade` | Nao | Necessaria para conversoes quando aplicavel. |
| `estoque_minimo` | `ESTOQUE MINIMO` | Nao | Parametro operacional de compras/alerta. |
| `valor_estoque_minimo` | `R$ Estoque Minimo` | Nao | Valor historico/analitico. |
| `custo_unitario` | `R$/Und` | Nao | Snapshot historico do cadastro; nao substitui o historico de aquisicoes. |
| `ibama` | `IBAMA` | Nao | Campo regulatorio. |
| `ncm` | `NCM` | Nao | Campo fiscal/classificacao. |
| `codigo_ads` | `Codigo ADS` | Nao | Identificador operacional/regulatorio. |
| `status` | `Ativo/Inativo` | Sim | Normalizar para status padrao. |

Subcadastros previstos:

| Subcadastro | Uso |
|---|---|
| `MateriaPrimaUnidadeHistorico` | Guarda mudancas de unidade ao longo do tempo, com vigencia. |
| `ConversaoUnidadeMP` | Conversoes aprovadas: saca, ton, tonelada, t, kg, litro, unidade etc. |
| `MateriaPrimaGarantia` | Garantias declaradas do insumo por cadastro ou padrao. |
| `LoteMateriaPrimaGarantia` | Garantias por lote, vindas de fornecedor ou laboratorio. |
| `MateriaPrimaSaneamentoSKU` | Fila de correcao de `id_sku_mp` usado como nome. |
| `MateriaPrimaIdentificadorOrigem` | Aliases de nome, codigo legado e codigo de fornecedor ligados a MP canonica. |
| `MateriaPrimaHistoricoAquisicao` | Preco, frete, DIFAL, total e valor unitario por entrada/lote, sem sobrescrever historia. |

Regras iniciais:

- `nome` nao pode ficar vazio.
- `sku_corrigido` deve ser unico no cadastro final.
- `id_sku_mp` legado pode duplicar ou conter nome; isso gera fila de saneamento.
- unidade deve ser preenchida antes de movimentar estoque.
- unidade pode mudar ao longo do tempo, mas a mudanca deve criar historico com vigencia.
- materia-prima inativa nao deve entrar em nova compra/producao sem permissao.
- densidade deve ser positiva quando preenchida.
- XML/NF pode vir com unidades diferentes, como saca, ton, toneladas, t e kg; a entrada deve converter para unidade base por regra aprovada.
- se o XML nao trouxer informacao suficiente para converter, o sistema deve pedir correcao manual assistida e registrar a decisao.
- quando a MP vier de fora de SP, o diferencial de aliquota de ICMS aplicavel compoe o custo de aquisicao; valor da MP, frete e DIFAL permanecem separados e auditaveis.
- a UF do emitente nao gera valor tributario por inferencia: o DIFAL deve vir do documento/importacao ou de confirmacao manual auditada.

Contrato da migracao historica: `docs/decisao_migracao_historica_materias_primas.md`.

Perguntas para revisao:

- Qual formato do `sku_corrigido`: numerico, prefixo MP, ou outro?
- Qual unidade base preferencial por tipo de MP?
- Saca sempre tem o mesmo peso ou depende da MP/fornecedor?
- Garantias de MP entram pelo fornecedor, por laudo de laboratorio, manualmente ou pelos tres caminhos?

## Produto acabado

Fonte historica principal: tabela `RELACAO_PRODUTOS`.

Objeto de dominio: `Produto`.

Finalidade: controlar o produto vendido/produzido, seus identificadores regulatorios e atributos usados em pedido, producao, estoque PA e romaneio.

Decisao: produto precisa ter codigo. O produto pode ter varias embalagens, e o pedido vende a combinacao produto + embalagem. O cadastro deve separar produto base, apresentacao comercial e item de estoque.

Objetos previstos:

| Objeto | Uso |
|---|---|
| `ProdutoBase` | Produto tecnico/regulatorio sem embalagem especifica. |
| `ProdutoEmbalagem` | Combinacao vendavel: produto + embalagem. |
| `ItemEstoquePA` | Codigo de estoque para produto acabado disponivel. |
| `ItemEstoquePI` | Codigo de produto intermediario usado em outras formulas ou embalagens. |

O codigo de PA/PI pode ser exclusivamente numerico, por exemplo `0001` ate `9999`, desde que seja unico e auditado.

| Campo operacional | Origem atual no Excel | Obrigatorio | Observacao |
|---|---|---:|---|
| `codigo_legado` | Novo ou a definir | Nao | Precisa validar se existe codigo historico fora do nome. |
| `codigo_produto` | Novo | Sim | Codigo unico do produto base. |
| `nome` | `RELACAO DE PRODUTOS` | Sim | Nome principal do produto. |
| `grupo` | `Grupo` | Nao | Familia ou classificacao. |
| `densidade_kg_l` | `DENSIDADE Kg/L` | Nao | Usada em conversoes e producao. |
| `prazo_validade_meses` | Novo | Nao | Prazo padrao de validade do PA/PI em meses; usado para gerar validade de lote e relatorios de vencimento/reprocessamento. |
| `custo_mp_historico` | `CUSTO MP` | Nao | Historico; custo definitivo fica para modulo de custos. |
| `reg_mapa` | `Reg MAPA` | Nao | Campo regulatorio. |
| `ph` | `pH` | Nao | Campo tecnico do produto. |
| `ibama` | `IBAMA` | Nao | Campo regulatorio. |
| `ads` | `ADS` | Nao | Identificador operacional/regulatorio. |
| `ncm` | `NCM` | Nao | Campo fiscal/classificacao. |
| `status` | Novo | Sim | Produto precisa poder ser inativado. |

Subcadastros previstos:

| Subcadastro | Uso |
|---|---|
| `ProdutoEmbalagem` | Define quais embalagens podem ser vendidas para cada produto. |
| `FormulaProduto` | Formula editavel e versionada do produto. |
| `ReceitaProducao` | Receita usada para produzir. |
| `ReceitaMapa` | Receita/documentacao que fica registrada para MAPA. |
| `GarantiaProdutoMapa` | Garantias declaradas no registro do MAPA. |
| `TransformacaoPA_PI` | Conversoes auditadas entre PA, PI e embalagens. |

Regras iniciais:

- `nome` nao pode ficar vazio.
- `codigo_produto` deve ser unico.
- codigo de PA/PI deve ser unico quando criado.
- duplicidade por nome deve gerar alerta.
- produto inativo nao deve entrar em novo pedido, producao ou romaneio.
- densidade deve ser positiva quando preenchida.
- prazo de validade em meses, quando preenchido, deve ser positivo e auditavel.
- custo de MP importado e informativo ate o modulo de custos ser definido.
- produto pode ter varias embalagens.
- pedido deve informar produto + embalagem vendida.
- PA pode nascer diretamente de producao ou de transformacao/embalagem de PI.
- PI pode ser usado em outras formulas ou embalado para virar PA.
- transformacao entre PA e PI deve gerar movimento auditado, nunca ajuste manual solto.

Perguntas para revisao:

- Codigo de produto deve ser numerico, alfanumerico ou separado por tipo PA/PI?
- A numeracao `0001` a `9999` vale para PA e PI juntos ou separadamente?
- Quais produtos atuais ja sao PI mesmo aparecendo como produto?
- Produto + embalagem deve ter codigo proprio diferente do produto base?

## Formula e receita

Objetos de dominio previstos: `FormulaProduto`, `FormulaVersao`, `FormulaItem`, `ReceitaProducao`, `ReceitaMapa`.

Finalidade: controlar formulas editaveis por versao, justificativa, autor, garantias e diferenca entre a receita operacional e a receita documentada para MAPA.

Decisao: formula nunca deve ser sobrescrita sem rastro. Qualquer modificacao deve gerar nova versao com autor, data/hora, justificativa e hash encadeado. O efeito desejado e equivalente a uma trilha imutavel: uma vez registrada, a versao anterior nao deve ser alterada.

Campos previstos em `FormulaVersao`:

| Campo | Obrigatorio | Uso |
|---|---:|---|
| `produto_id` | Sim | Produto base da formula. |
| `versao` | Sim | Numero ou codigo da versao. |
| `tipo_receita` | Sim | `producao` ou `mapa`. |
| `status` | Sim | Rascunho, ativa, substituida, cancelada. |
| `justificativa` | Sim para alteracao | Motivo tecnico/operacional da mudanca. |
| `created_by` | Sim | Autor da versao. |
| `entry_hash` | Sim | Hash da versao. |
| `previous_hash` | Sim quando houver | Hash da versao anterior. |

Regras iniciais:

- produto pode ter mais de uma receita.
- deve existir distincao entre receita que vai para producao e receita documentada para MAPA.
- alteracao de formula exige justificativa.
- formula usada em ordem de producao deve apontar para uma versao fixa.
- formula pode considerar PA, PI e MP como componentes, se aprovado.
- alteracao de garantia ou lote de MP nao deve reescrever a formula historica; deve gerar calculo/resultado vinculado ao lote ou ordem.

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

## Entregador

Objeto de dominio previsto: `Entregador` como papel de `PessoaComercial` ou `PessoaOperacional`.

Finalidade: identificar quem executa entrega/expedicao sem misturar esse papel com venda ou comissao comercial.

Decisoes:

- entregador nunca sera considerado vendedor apenas por ser entregador;
- vendedor pode tambem atuar como entregador;
- entregador pode ou nao ser funcionario Elite;
- entrega nao gera comissao comercial automaticamente;
- se a mesma pessoa tiver papel de vendedor e entregador, as regras devem separar claramente entrega, venda e comissao.

Campos previstos:

| Campo | Obrigatorio | Uso |
|---|---:|---|
| `pessoa_id` | Sim | Pessoa vinculada ao papel de entregador. |
| `funcionario_elite` | Sim | Indica se pertence ao time Elite. |
| `status` | Sim | Ativo/inativo. |
| `observacao` | Nao | Restricoes operacionais, quando houver. |

## Embalagem

Fonte historica atual: existe tabela de embalagens e tambem aparece em pedidos e saidas de PA como `EMB.` / `EMBALAGEM`.

Objeto de dominio previsto: `Embalagem`.

Finalidade: padronizar embalagem usada em pedido, produto, estoque PA, estoque de insumos e romaneio.

Decisao: embalagem define quantidade/volume em litros e deve ser monitorada como insumo. Ela tambem pode participar de transformacoes de estoque, por exemplo um PA em embalagem de 20L pode ser convertido para 4 unidades de 5L ou outra quantidade auditada.

| Campo operacional | Origem atual no Excel | Obrigatorio | Observacao |
|---|---|---:|---|
| `codigo_legado` | A definir | Nao | Ainda nao ha tabela de cadastro mapeada. |
| `descricao` | `EMB.` / `EMBALAGEM` | Sim | Pode nascer da ocorrencia historica. |
| `volume_litros` | Tabela de embalagens | Sim quando embalagem liquida | Quantidade/volume da embalagem. |
| `unidade` | Tabela de embalagens | Sim | Litro, unidade etc. |
| `controla_estoque` | Novo | Sim | Indica se embalagem baixa estoque de insumos. |
| `materia_prima_id` | Novo | Quando controla estoque | Vinculo com item de estoque/insumo da embalagem. |
| `status` | Novo | Sim | Ativa/inativa. |

Regras iniciais:

- embalagem e cadastro proprio e tambem pode ser insumo controlado no estoque;
- descricao duplicada com grafias diferentes deve gerar fila de revisao;
- embalagem inativa nao deve entrar em pedido novo.
- produto pode ter varias embalagens possiveis.
- pedido deve gravar a embalagem vendida.
- transformacao de PA 20L para 5L, ou similar, deve ser um processo auditado com origem, destino, quantidade e perdas quando houver.

Perguntas para revisao:

- Qual tabela atual e a fonte canonica de embalagens?
- Toda embalagem controla estoque ou algumas sao apenas descricao comercial?
- Embalagem usada em producao deve ser baixada junto da ordem de producao, do envase ou do romaneio?

## Garantia

Fonte historica: registro do produto no MAPA, garantias de MP por fornecedor/lote, analises de laboratorio e informacao manual autorizada.

Objetos de dominio previstos: `GarantiaNutriente`, `GarantiaProdutoMapa`, `GarantiaMateriaPrima`, `GarantiaLoteMateriaPrima`, `GarantiaProdutoCalculada`.

Finalidade: controlar os valores declarados no registro do produto no MAPA e comparar/calcular as garantias do produto final conforme as garantias das materias-primas usadas.

Decisao: garantias dos fertilizantes sao valores declarados no registro do produto no MAPA e devem atender maximos ou minimos. O sistema deve permitir informar garantias manualmente ou calcular de acordo com garantias do lote de MP. Quando um produto acabado usar mais de um lote da mesma MP, as garantias por lote devem ser consideradas no resultado final.

Campos previstos em `GarantiaProdutoMapa`:

| Campo | Obrigatorio | Uso |
|---|---:|---|
| `produto_id` | Sim | Produto registrado. |
| `nutriente` | Sim | Nutriente/componente garantido. |
| `tipo_limite` | Sim | Minimo, maximo, faixa ou declarado. |
| `valor` | Sim | Valor da garantia. |
| `unidade` | Sim | %, g/L, kg/t ou unidade aprovada. |
| `fonte` | Sim | MAPA, manual, laboratorio, fornecedor ou calculado. |
| `vigencia_inicio` | Sim | Inicio da validade. |
| `vigencia_fim` | Nao | Fim da validade, quando substituida. |

Campos previstos em `GarantiaLoteMateriaPrima`:

| Campo | Obrigatorio | Uso |
|---|---:|---|
| `materia_prima_id` | Sim | MP do lote. |
| `lote_mp_id` | Sim | Lote da MP. |
| `nutriente` | Sim | Nutriente/componente analisado. |
| `valor` | Sim | Valor informado ou analisado. |
| `unidade` | Sim | Unidade da garantia. |
| `fonte` | Sim | Fornecedor, laboratorio ou manual. |
| `documento_referencia` | Nao | Laudo, XML, certificado ou observacao. |
| `created_by` | Sim | Usuario que informou. |

Regras iniciais:

- garantia manual exige autor e justificativa.
- garantia de laboratorio deve aceitar documento/laudo de referencia.
- garantia do fornecedor pode vir do lote ou certificado.
- calculo do produto final deve considerar proporcao usada de cada MP e cada lote.
- se a mesma MP entrar com mais de um lote, calcular por lote e nao por media simples do cadastro.
- resultado calculado deve ser gravado como evidencia, sem apagar valores de origem.
- divergencia contra limite MAPA deve bloquear ou alertar conforme regra aprovada.
- mudanca de garantia gera nova versao auditada, nao sobrescrita silenciosa.

Perguntas para revisao:

- Quais nutrientes/garantias sao obrigatorios hoje por tipo de produto?
- O limite MAPA e sempre minimo/maximo ou existem faixas?
- Qual tolerancia tecnica usar antes de bloquear producao?
- O laudo de laboratorio sera anexo no sistema ou apenas referencia textual inicialmente?

## Cadastros de apoio previstos

Estes cadastros podem ser necessarios, mas nao devem roubar prioridade dos mestres:

- cidades/UF;
- unidades de medida;
- grupos de produto;
- tipos de materia-prima;
- status padronizados;
- tipos de pedido;
- funcoes de funcionario;
- aliases/grafias para importacao;
- papeis de pessoa;
- tipos de comissionado;
- campanhas comerciais;
- metas e premios;
- conversoes de unidade;
- nutrientes/garantias;
- tipos de receita/formula;
- motivos de alteracao de formula;
- tipos de transformacao PA/PI.

## Auditorias de cadastros

Cada cadastro deve ter, no minimo:

- contagem Excel x sistema;
- duplicidade de codigo legado;
- duplicidade provavel por nome normalizado;
- registros ativos sem campo obrigatorio;
- registros usados em pedidos/estoque/producao sem cadastro mestre;
- registros inativos usados em operacao nova;
- alteracoes manuais com usuario, antes/depois e motivo quando aplicavel.
- comissoes de pedido com multiplos comissionados e condicao de recebimento;
- campanhas simultaneas aplicadas ao mesmo pedido;
- clientes duplicados e decisoes de unificacao;
- conversoes de unidade aplicadas em entradas por XML/NF;
- mudancas de unidade de MP com vigencia;
- formulas alteradas com justificativa e hash encadeado;
- garantias calculadas por lote de MP e comparadas contra MAPA;
- transformacoes entre PA, PI e embalagens.

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
