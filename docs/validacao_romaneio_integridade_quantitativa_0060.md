# Validacao 0060 - integridade quantitativa do Romaneio

## Escopo

Correcao localizada no dominio `expedicao`. A regra preserva a arquitetura
`tela -> Server Action -> RPC auditada -> PostgreSQL` e nao move ownership de
Pedido ou Estoque.

## Falha reproduzida

No staging, um item de pedido com toda a quantidade ja distribuida entre dois
romaneios em rascunho ainda aparecia na tela com o valor integral como
`quantidade_pendente`. A soma persistida dos romaneios nao excedia o pedido,
pois a RPC antiga ja fazia uma verificacao adicional, mas o read model ignorava
rascunhos e separacoes ao calcular o saldo oferecido para uma nova operacao.

Consequencias observadas:

- a tela oferecia novamente um item sem saldo livre;
- o usuario era induzido a tentar uma quantidade impossivel;
- `pendente de atendimento` e `disponivel para novo romaneio` eram tratados
  como se fossem o mesmo conceito;
- a defesa dependia da implementacao de cada RPC, sem uma trava agregada na
  tabela de itens do romaneio.

## Causa e contrato corrigido

A view original calculava:

`quantidade_pendente = quantidade_pedido - quantidade_confirmada`.

Esse numero continua valido para acompanhamento do atendimento, mas nao para
criar outra separacao. A 0060 formaliza:

`quantidade_comprometida = draft + separacao + confirmado`.

`quantidade_disponivel_romaneio = quantidade_pedido - quantidade_comprometida`.

Somente `quantidade_disponivel_romaneio` alimenta os seletores de nova
separacao. Cancelamento ou estorno deixam de compor o compromisso e liberam o
saldo correspondente.

## Defesas

1. Preflight da migration interrompe o upgrade se ja existir item operacional
   com quantidade ativa acima do pedido.
2. A view separa pendencia, compromisso, saldo livre e eventual excedente.
3. Trigger no PostgreSQL trava a linha do item de pedido e rejeita `insert` ou
   `update` que ultrapasse a quantidade pedida, inclusive fora da RPC.
4. `create_exp_romaneio` e `add_exp_romaneio_item` validam o saldo livre depois
   de obter os locks e registram auditoria com `before/after` e
   `correlation_id`.
5. Romaneio nasce somente em rascunho. Reserva de lote passa obrigatoriamente
   por `registrar_est_reserva_pa`.
6. A RPC textual antiga `registrar_exp_romaneio_separacao` nao e mais
   executavel pelos papeis da API.
7. As RPCs operacionais de Romaneio removem `EXECUTE` de `PUBLIC` e `anon`.
8. A view usa `security_invoker` e permanece disponivel apenas para usuario
   autenticado sujeito a RLS.

## Smoke transacional

O teste `tests/sql/romaneio_quantity_integrity_contract.sql` cobre:

- ator sem alçada negado antes da validacao de parametros;
- duas separacoes parciais que fecham exatamente o pedido;
- terceira separacao excedente negada pela RPC;
- gravacao direta excedente negada pelo trigger;
- cancelamento liberando o saldo comprometido;
- nova separacao usando apenas o saldo liberado;
- ACL anonima negada e RPC legada indisponivel;
- log auditado da criacao.

Marcador esperado no PostgreSQL descartavel:
`PG_VALIDATE_0060_WITH_SMOKE_OK`.

## Resultado

- migrations `0001` a `0060` instaladas do zero no projeto isolado
  `elite-validation-0060`;
- smoke 0060: `PG_VALIDATE_0060_WITH_SMOKE_OK`;
- regressao do bloco 0059: `PG_VALIDATE_0059_WITH_SMOKE_OK`;
- zero grant sweep: `66/66` RPCs negadas ao ator sem alçada;
- 14 testes estaticos dirigidos de Romaneio: aprovados;
- lint PostgreSQL: nenhum erro de schema;
- ESLint completo: aprovado;
- TypeScript sem emissao: aprovado;
- build Next.js: aprovado, com 24 paginas e `/romaneios` presente;
- `git diff --check`: aprovado;
- runtime local ativo `elite-system`: nao resetado, migrado ou alterado;
- staging: nao alterado nesta tarefa ate autorizacao de publicacao.

O primeiro sweep foi executado ainda com o banco descartavel em estado
`unconfigured` e parou corretamente no gate de runtime de duas RPCs de
auditoria. Depois de configurar explicitamente o mesmo banco descartavel como
`test`, o sweep passou `66/66`. Isso foi precondicao de ambiente, nao correcao
de codigo.

Nenhum dado de staging, credencial, workbook, dump ou informacao comercial
integra esta evidencia.
