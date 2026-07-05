# Decisao - composicao de RPC auditada

Data: 2026-07-05

## Decisao

Uma RPC de camada superior pode chamar uma RPC de camada inferior que ja segue o contrato auditado, desde que isso seja uma decisao explicita de negocio.

Nesses casos, a regra e:

1. A chamada exige a uniao das alcadas envolvidas.
2. Cada evento de negocio grava seu proprio registro em `action_logs`.
3. Os logs devem ser correlacionaveis por um identificador comum ou por chaves operacionais inequivotas.
4. A RPC externa deve documentar quais permissoes internas ela depende.

## Exemplo validado

`gerar_lote_mp_from_imp_nfe_item` usa duas camadas:

| Camada | Action key | Motivo |
|---|---|---|
| Importacao XML | `importacao.nfe_xml.generate_mp_lot` | Aprova a transformacao do item XML conferido em lote MP. |
| Estoque MP | `estoque.mp.lots.create` | Cria o lote fisico e o movimento de entrada no livro de estoque. |

Isso gera dois logs:

| Log | Entidade | Como correlacionar |
|---|---|---|
| `importacao.nfe_xml.generate_mp_lot` | `imp_nfe_xml_itens` | `metadata_json.lote_mp_id` e `metadata_json.origem_ref`. |
| `estoque.mp.lots.create` | `est_lotes_mp` | `entity_id = lote_mp_id` e `metadata_json.origem_ref`. |

Portanto, e intencional que um usuario precise das duas alcadas para concluir a operacao. Se ele tiver permissao de importacao, mas nao tiver permissao de criar lote MP, a operacao deve falhar sem criar vinculo, sem mudar status do item XML e sem criar movimento de estoque.

## Padrao para proximas RPCs compostas

Quando uma RPC composta gerar mais de um efeito auditavel, ela deve criar um `correlation_id` antes da primeira mudanca.

Formato recomendado:

```text
<dominio>:<entidade>:<id>:<evento>
```

Exemplos:

```text
importacao_xml:item:123:generate_mp_lot
pcp_op:456:finish
romaneio:789:confirm
```

O `correlation_id` deve aparecer:

- no `permission_context` da RPC externa;
- no `metadata_json` da RPC externa;
- no `metadata_json` de cada log interno criado diretamente pela RPC composta;
- no `origem_ref` ou campo equivalente das RPCs internas antigas que ainda nao aceitam metadata arbitraria.

Quando a RPC interna ja retorna uma entidade clara, como `create_est_lote_mp` retornando `lote_mp_id`, a correlacao por entidade tambem deve ser mantida, mas nao substitui o `correlation_id` para novos fluxos complexos.

## Regra para `finalizar_pcp_op`

`finalizar_pcp_op` deve usar `correlation_id = 'pcp_op:' || p_op_id || ':finish'`.

Todos os logs gerados durante a mesma finalizacao devem carregar esse valor:

- log externo de `pcp.op.finish`;
- consumos de MP;
- consumos de PA;
- consumos de PI;
- entradas de PA;
- entradas de PI;
- registros de CQ;
- produtos gerados.

Se a finalizacao chamar RPCs internas ja auditadas, as permissoes internas continuam obrigatorias. A finalizacao de OP nao deve esconder uma baixa de estoque ou uma entrada de lote atras de uma permissao generica de PCP.

## O que nao fazer

- Nao suprimir log interno apenas para reduzir volume de auditoria.
- Nao transformar varios movimentos fisicos em um unico log resumido sem livro de movimento.
- Nao depender apenas da ordem temporal dos logs para reconstruir uma operacao composta.
- Nao criar action key generica que autorize todos os efeitos fisicos da OP.
