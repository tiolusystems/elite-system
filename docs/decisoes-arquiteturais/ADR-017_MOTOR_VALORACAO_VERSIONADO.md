# ADR-017 - Motor de valoracao versionado (PRC-03)

Status: ativo para o motor de valoracao versionado introduzido pela migration
0152. PRC-01 continua a formacao oficial de custos e precos; PRC-03 somente
produz snapshots de valoracao governados e nao altera fatos de outros dominios.

## Fronteiras

`SOURCE` identifica um fato e sua proveniencia; `VALUATION METHOD` seleciona
e agrega fatos elegiveis; `PRICING FORMULA` combina valores ja valorados. Os
dominios Estoque e PCP continuam donos de movimentos, reservas, saldos, custos
e alocacoes. Cadastros continua dono de MP, unidades e composicao de embalagem.
Precificacao so obtem leitura governada e grava seus proprios contratos e
snapshots; nao corrige fatos de outros dominios nem escreve neles. PRC-01
continua oficial; PRC-02 permanece motor shadow de formulas. Nenhum resultado
PRC-03 substitui automaticamente a entrada PRC-01 ou promove PRC-02.

## Fatos existentes e seus limites

- `cad_materias_primas.unidade_base_estoque` define a unidade base da MP;
  conversoes de Cadastros exigem unidade, fator e vigencia aprovados.
- `est_lotes_mp_saldos` (0070) soma movimentos e subtrai reservas ativas de
  PCP/envase; expõe `saldo_fisico`, `quantidade_reservada` e
  `saldo_disponivel`. E uma view do estado corrente, nao uma serie temporal.
- Lote MP (0009) tem status `disponivel`, `bloqueado`, `esgotado` ou
  `cancelado`, e `data_validade`. Movimento de MP tem quantidade e instante.
- `est_movimentos_mp_valores` (0045) armazena quantidade base, moeda ISO de
  tres letras e custo de aquisicao unitario. Ausencia de valor nao vira zero.
- `est_movimentos_mp_custo_alocacoes` (0077) consome camadas por FIFO dentro
  do lote, ordenadas por instante/ID de entrada. `est_movimentos_mp_custos_atuais`
  mostra quantidade de saida ainda sem custo; nao e saldo valorado disponivel.
- Reserva FIFO de PCP (0076) escolhe lotes por primeira entrada, mas reserva
  quantidade no lote, sem alocacao por camada de aquisicao. Portanto somar
  saldos de camadas e subtrair reservas sem uma regra de atribuicao seria
  incorreto. Nao contar reservas duas vezes.
- `cad_embalagem_versoes` e `cad_embalagem_componentes_atuais` (0051,
  endurecidas em 0139) expressam BOM versionada/aprovada e componentes MP com
  unidades; nao sao uma segunda fonte de preco de aquisicao.

## Politica e metodos

Politica tem ID estavel, versoes append-only com documento/hash, autor,
revisao segregada e lifecycle proprio. Aprovacao nao pode ser do autor.
`ACTIVE` significa elegivel para valoracao, nunca promocao de formula ou preco
oficial. Na 0152, a policy fixa fonte permitida, metodo, base temporal corrente
e comportamento para ausencia de validade. Vigencia de policy, unidade/moeda
de saida configuraveis e regra de arredondamento permanecem fora do escopo
atual; nao sao inferidas pelo motor. Requisicoes idempotentes e auditadas nao
aceitam SQL, JavaScript, `eval` ou metodo livre.

Allowlist inicial:

| Metodo | Regra |
|---|---|
| `WEIGHTED_AVAILABLE_BALANCE` | default Elite: soma(qtd disponivel por camada * custo unitario) / soma(qtd disponivel), sem media de medias |
| `LATEST_ELIGIBLE_ACQUISITION` | ultima camada elegivel por instante de entrada, ID do movimento e ID do valor, com desempate deterministico |
| `APPROVED_MANUAL_REFERENCE` | ultima referencia manual aprovada e vigente, versionada, sem fingir origem system |

O default Elite so considera MP ativa, lote `disponivel`, nao vencido em
`as_of`, `saldo_disponivel > 0`, custo conhecido, unidade convertivel e uma
unica moeda compativel. Ausencia, custo pendente, unidade sem conversao,
moedas mistas ou saldo insuficiente falham fechado, com motivo, nao geram
valor zero. Politica de validade para lote sem `data_validade` e cutoff de
`as_of` historico dependem de decisao explicita. A view corrente nao prova
estado em data passada; ate existir replay temporal governado, a RPC deve
recusar `as_of` historico em vez de atribuir saldo atual ao passado.

Para saldo corrente, o motor parte do residual por camada: quantidade de
entrada menos alocacoes de saida registradas. Reconciliar a soma residual do
lote com `saldo_fisico`; divergencia ou custo pendente bloqueia. Reservas
ativas deduzem do residual, nunca do saldo ja disponivel outra vez. A 0152
atribui a reserva FIFO entre camadas do lote, na mesma ordenacao de consumo da
0077, sem gravar alocacao de reserva em Estoque. O snapshot persiste inclusive
camada integralmente reservada com disponibilidade zero e registra a linhagem
e as quantidades usadas; as reconciliacoes fisica e disponivel falham fechado.

## Fontes e unidades

O catalogo distingue `STOCK_ACQUISITION_LAYER`,
`APPROVED_MANUAL_MARKET`, `APPROVED_STANDARD_COST` e
`APPROVED_REPLACEMENT_COST`. Apenas o primeiro tem fato canônico existente
nos objetos acima; as demais fontes sao contratos futuros, nao aliases para
valor enviado pelo caller. Referencia manual exige ID/versao, documento de
origem, data de referencia, moeda, unidade, valor, ator, motivo e aprovador
distinto, sem UPDATE/DELETE. Nao confundir referencia manual aprovada com
fato real de Estoque.

Na 0152 a saida e `{currency, base_unit, unit_cost, quantity, total_cost}`
com `numeric` decimal canonico. A moeda e a unidade refletem os fatos elegiveis
da fonte: unidade base vem da MP e conversao vigente/aprovada de Cadastros;
sem ela, falha. Nao ha FX implicito, moeda de saida independente, unidade de
saida independente ou politica de arredondamento configuravel nesta tranche.
Moedas diferentes nao se somam. Preco por litro exige conversao/quantidade
propria de formula ou embalagem, nunca alteracao silenciosa da unidade de
valoracao.

## Snapshot e reprodutibilidade

Snapshot append-only `prc-valuation-v1`: ID/versao/hash da politica,
fonte, metodo, MP, `as_of`, moeda, unidade base, quantidade, custo unitario
exato, total exato, IDs de lotes/movimentos/valores/alocacoes usados, lista
ordenada de camadas com quantidade e custo, lista de exclusoes com motivo
(bloqueio, vencimento, reserva, custo ausente), ator e timestamp capturados
uma vez, hashes de entrada e de saida. Decimal e texto canonico; arrays
ordenados por lote/entrada/valor/ID. Hash SHA-256 cobre o documento completo
persistido e e revalidado na leitura. Mudanca futura de politica ou Estoque
nao reescreve o resultado historico. A superficie de leitura e governada,
sem SELECT direto da aplicacao em fatos privados.

## Embalagem

Uma futura rodada usa BOM aprovada de Cadastros para quantidades de MP por
embalagem e aplica uma valoracao PRC a cada MP referenciada. A identidade de
cada componente deve incluir `embalagem_versao_id` e `materia_prima_id`. O
mesmo custo de MP nao pode aparecer como fonte distinta de embalagem e
materia-prima no mesmo agregado. A unidade do componente e convertida antes
de multiplicar; faltas bloqueiam. Nao implementar agora agregacao final
`BRL/L`, precos, interface ou alteracao na formula PRC-01/PRC-02.

## Decisoes pendentes e gates

Luciano e os donos de Estoque/PCP precisam confirmar: (1) criterio para lote
sem validade; (2) historico `as_of` e fuso/cutoff; (3) governanca e prioridade
das fontes manual, padrao e reposicao; (4) aprovadores e vigencias dessas
referencias. A reserva FIFO multicamada ja integra o contrato vigente da 0152:
os consumos reais reconstroem primeiro as camadas remanescentes, a reserva e
aplicada em seguida e a valoracao usa somente a disponibilidade resultante.
Nenhuma lacuna autoriza fallback permissivo.
Implementacao, SQL runtime, aprovacao humana e promocao sao gates separados.
