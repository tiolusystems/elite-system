# Decisao - finalizacao de OP no PCP

Data: 2026-07-05

## Objetivo

Fixar as decisoes de negocio e arquitetura antes de migrar `finalizar_pcp_op` para o contrato auditado com `begin_audited_rpc(...)`, `log_audited_rpc_change(...)` e `correlation_id`.

## Decisoes

### 1. Transacao unica

`finalizar_pcp_op` deve continuar executando em uma unica transacao PostgreSQL.

Se qualquer etapa falhar, toda a finalizacao deve ser revertida:

- CQ;
- consumo de MP;
- consumo de PA;
- consumo de PI;
- baixa de reservas;
- criacao de lote PA;
- criacao de lote PI;
- produtos gerados;
- status da OP.

Nao deve existir finalizacao parcial persistida.

### 2. Ordem de validacao e lock

A migration deve reduzir tempo de lock e risco de deadlock seguindo esta ordem:

1. validar parametros basicos antes de qualquer escrita;
2. travar a OP por `for update`;
3. validar status da OP e CQ duplicado;
4. validar todas as reservas planejadas antes de qualquer movimento de estoque;
5. validar todos os outputs PA/PI antes de qualquer movimento de estoque;
6. travar reservas ativas em ordem deterministica;
7. executar consumos;
8. gerar entradas PA/PI;
9. atualizar status da OP;
10. gravar logs auditados com o mesmo `correlation_id`.

Ordem deterministica de lock para reservas:

```text
op_componente_id, id
```

Quando for necessario travar lotes diretamente, a ordem deve ser por familia e id:

```text
MP -> PA -> PI
```

### 3. Comportamento do CQ

CQ e parte da finalizacao. O produto ja foi fisicamente produzido quando a OP e finalizada.

Por isso:

- `cq_status = aprovado` em OP normal gera lote `disponivel`;
- `cq_status = bloqueado` gera lote `bloqueado`;
- `cq_status = reprovado` gera lote `bloqueado`;
- OP `experimental` ou `desenvolvimento` gera lote `bloqueado` mesmo com CQ aprovado;
- OP `mapa_documental` nao gera estoque.

Reprovar CQ nao deve apagar o fato fisico da producao. O lote nasce bloqueado para decisao posterior: liberacao, reprocessamento, analise, descarte ou ajuste operacional auditado.

Se o negocio decidir futuramente que CQ reprovado deve abortar a geracao de lote, isso sera uma mudanca de regra de negocio, nao apenas ajuste de auditoria.

### 4. Idempotencia

`finalizar_pcp_op` nao deve ser idempotente no sentido de "executar duas vezes e retornar o mesmo resultado".

Ela deve ser segura contra repeticao:

- primeira chamada valida finaliza a OP;
- segunda chamada para a mesma OP deve falhar antes de novo consumo ou nova entrada;
- nenhum movimento de estoque deve ser duplicado;
- nenhum produto gerado deve ser duplicado;
- nenhum CQ duplicado deve ser criado.
- a rejeicao de estado deve ser auditada como status `failed`, nao como `denied`.

As travas atuais sao:

- `pcp_ordens_producao.status` deve estar em `planned` ou `in_process`;
- `pcp_op_cq_resultados.op_id` e unico;
- a funcao verifica se ja existe CQ para a OP.

A migration auditada deve manter essas travas e o smoke deve testar tentativa de segunda finalizacao.

`denied` fica reservado para falta de alcada. Se o usuario tinha permissao, mas a OP ja estava finalizada, o evento e uma rejeicao de regra de negocio e deve aparecer em `action_logs` como `failed`, com `metadata_json.reason` ou `metadata_json.error_message` suficiente para identificar `op_already_finished`.

### 5. Correlacao de logs

Toda finalizacao deve criar:

```text
correlation_id = 'pcp_op:' || p_op_id || ':finish'
```

Esse valor deve aparecer em todos os logs gerados pela mesma finalizacao:

- log externo de `pcp.op.finish`;
- log de CQ;
- logs de consumo MP/PA/PI;
- logs de entrada PA/PI;
- logs de produtos gerados.

### 6. Quem libera lote bloqueado

Nao se "libera a OP" depois da finalizacao. A OP permanece `completed`, porque ela registra o fato historico de que a producao foi concluida.

O que fica bloqueado e o lote PA/PI gerado pela OP.

O lote bloqueado deve ser liberado por CQ, qualidade ou gestor tecnico com alcada especifica:

```text
pcp.blocked_lot.release
```

A permissao antiga `pcp.experimental.release` fica como legado de nomenclatura. Ela nao representa mais todo o caso de uso, porque lote tambem pode estar bloqueado por CQ `bloqueado` ou `reprovado`, nao apenas por OP experimental/desenvolvimento.

A liberacao deve exigir motivo e atualizar tanto o lote fisico (`est_lotes_pa` ou `est_lotes_pi`) quanto o produto gerado da OP (`pcp_op_produtos_gerados.status_lote`).

## Testes obrigatorios da migration

O smoke da migration de `finalizar_pcp_op` deve validar:

1. caminho feliz com consumo MP e entrada PA/PI;
2. OP experimental/desenvolvimento gerando lote bloqueado;
3. CQ reprovado gerando lote bloqueado;
4. segunda chamada de finalizacao falhando sem duplicar movimentos;
5. falha em etapa posterior revertendo consumo ja tentado;
6. todos os logs da finalizacao com o mesmo `correlation_id`;
7. negativa de permissao interna de estoque sem alteracao persistida;
8. concorrencia simples: duas tentativas de finalizar a mesma OP nao duplicam estoque.
9. tentativa repetida registra falha de negocio como `failed`, nao como `denied`;
10. liberacao de lote bloqueado exige `pcp.blocked_lot.release` e atualiza `pcp_op_produtos_gerados.status_lote`.

## O que nao fazer

- Nao aceitar finalizacao parcial.
- Nao deixar CQ reprovado gerar lote disponivel.
- Nao duplicar consumo por retry, duplo clique ou retry de rede.
- Nao trocar varias permissoes fisicas por uma permissao generica.
- Nao depender apenas de ordem temporal dos logs para reconstruir a OP.
