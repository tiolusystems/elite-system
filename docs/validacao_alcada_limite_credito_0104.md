# Validacao 0104 - Alcada atomica de limite de credito

## Regra validada

- revisar pedido bloqueado continua exigindo `pedidos.credit.review`;
- alterar o limite cadastral exige exclusivamente
  `financeiro.credit_limits.adjust`;
- papel organizacional nao concede a nova alcada;
- aprovacao excepcional de pedido nao modifica o limite permanente;
- a permissao nova nasce bloqueada e depende de decisao individual de
  Seguranca.

## Auditoria anterior do staging

| Usuario | Papel | Revisar pedido | Alterar limite legado | Origem |
| --- | --- | --- | --- | --- |
| Luciano Machado | admin | permitido | permitido | padrao da acao |

- `pedidos.credit.review` tinha `default_allowed = true`;
- `pedidos.credit.limit.adjust` tinha `default_allowed = true`;
- nao havia override positivo explicito para a permissao legada;
- nenhuma autorizacao foi migrada automaticamente.

## Estado depois da 0104

| Usuario | Papel | Revisar pedido | Alterar limite | Origem da nova permissao |
| --- | --- | --- | --- | --- |
| Luciano Machado | admin | permitido | bloqueado | padrao da acao |

- a nova action key pertence ao modulo Financeiro e tem padrao bloqueado;
- a action key legada permanece apenas para preservar historico, com padrao
  bloqueado, e nao autoriza mais a RPC;
- usuarios efetivamente autorizados a alterar limite depois da correcao: zero;
- uma futura concessao deve ser individual e auditada na tela de Seguranca.

## Banco e seguranca

- migration: `0104_separate_credit_limit_adjust_permission.sql`;
- dry-run do staging listou somente a 0104;
- ledger do staging confirmado ate a 0104;
- a RPC idempotente exige exclusivamente a nova action key;
- advisory lock, justificativa, evento append-only e auditoria antes/depois
  foram preservados;
- escrita direta permanece revogada;
- `anon` e `PUBLIC` nao executam a operacao;
- nenhum dado operacional foi criado no staging.

## Testes

- instalacao limpa `0001 -> 0104` em ambiente `elite-validation-*`;
- upgrade descartavel `0103 -> 0104`;
- smoke SQL: `PG_VALIDATE_0104_CREDIT_LIMIT_ATOMIC_PERMISSION_OK`;
- upgrade SQL: `PG_VALIDATE_UPGRADE_0103_TO_0104_OK`;
- gerente, Financeiro e Administrativo sem a action key: alteracao negada;
- revisor de pedido sem a nova key: revisao permitida e limite negado;
- titular da nova key sem revisao: limite permitido e revisao negada;
- retirada do override: proxima alteracao negada;
- retry com a mesma chave: nenhum evento duplicado;
- auditoria registra usuario, justificativa, valor anterior e valor novo;
- CI integral `29968432605`: `database-contract`, `python-tests` e
  `web-contract` aprovados.

## Frontend e staging

- Clientes mostra o credito em modo somente leitura para o usuario sem alcada;
- campos de alteracao e botao de gravacao nao sao renderizados sem permissao;
- Seguranca mostra a acao em Financeiro como `Bloqueado`, com origem
  `Padrao da acao` e controle individual;
- Pedidos nao possui formulario de alteracao permanente de limite;
- deployment ativo: `dpl_CFaYp26oLuHCaKFozVPYDxUR1yZh`;
- deployment anterior preservado para rollback:
  `dpl_2giG9SPHUSXN1eXLiswxrjRZagAE`;
- `/api/health`: `status=ok` e `backendConfigured=true`;
- login, Clientes, Seguranca e Pedidos foram verificados no staging autenticado.

## Observacao operacional

O rollout do modulo Financeiro permaneceu desabilitado no staging. A 0104 nao
ativou modulo, nao concedeu alcada e nao alterou producao. Para permitir uma
alteracao real, Seguranca deve conceder a action key individualmente e o modulo
Financeiro deve estar liberado no ambiente correspondente.
