# Validacao Supabase/PostgreSQL descartavel

Data: 2026-07-03

## Objetivo

Validar que a estrutura PostgreSQL/Supabase do Elite System aplica sem erro e que o fluxo estrutural de romaneio respeita as regras criticas, sem usar dados reais e sem tocar em banco operacional.

## Ferramentas habilitadas

- Supabase CLI local em `.tools/supabase-cli/supabase.exe`.
- Versao validada: `2.109.0`.
- PostgreSQL local descartavel criado em `.tools/pg-validate`.
- Porta do banco descartavel: `55432`.

As pastas `.tools/` e dados locais seguem ignorados pelo Git.

## Preparacao do banco descartavel

O banco descartavel recebeu apenas compatibilidade minima para migrations Supabase:

- schema `auth`;
- tabela `auth.users`;
- funcao `auth.uid()` retornando `null`;
- roles `authenticated`, `anon` e `service_role`.

Isso permitiu validar as migrations sem instalar Docker/Supabase local completo.

## Resultado das migrations

Migrations aplicadas em ordem no banco descartavel:

- `0001_security_audit_foundation.sql`;
- `0002_master_data_foundation.sql`;
- `0003_commercial_orders_foundation.sql`;
- `0004_order_credit_gate.sql`;
- `0005_order_receipts_commissions.sql`;
- `0006_romaneio_foundation.sql`.

Resultado: todas aplicaram com sucesso via `psql -v ON_ERROR_STOP=1`.

## Validacao adicional - estoque PA por lote

Data/hora local: 2026-07-03 23:33 -03:00.

Banco descartavel complementar:

- Pasta: `.tools/pg-validate-0007`.
- Porta: `55433`.
- Sem dados reais.

Migrations aplicadas em ordem:

- `0001_security_audit_foundation.sql`;
- `0002_master_data_foundation.sql`;
- `0003_commercial_orders_foundation.sql`;
- `0004_order_credit_gate.sql`;
- `0005_order_receipts_commissions.sql`;
- `0006_romaneio_foundation.sql`;
- `0007_pa_stock_lots_foundation.sql`.

Resultado: todas aplicaram com sucesso via `psql -v ON_ERROR_STOP=1`.

Smoke test `smoke_pa_0007`:

- criou cadastros minimos;
- criou lote PA com 10 unidades;
- criou pedido aberto de 6 unidades;
- criou romaneio total em rascunho;
- reservou 6 unidades do lote;
- validou saldo fisico 10, reserva 6 e saldo disponivel 4;
- confirmou romaneio;
- validou `saida_romaneio` de -6 em `est_movimentos_pa`;
- validou pedido `fulfilled`;
- estornou romaneio;
- validou saldo restaurado para 10 e pedido reaberto como `open`;
- tentou reservar 11 unidades com saldo disponivel 10;
- validou erro esperado de saldo insuficiente.
- tentou confirmar romaneio com apenas `lote_pa_ref` textual e sem reserva real;
- validou bloqueio esperado: reserva PA ativa obrigatoria antes da confirmacao;
- tentou editar diretamente `est_movimentos_pa`;
- validou bloqueio append-only do livro de movimentos PA.
- cancelou romaneio com reserva ativa;
- validou reserva `liberada` e saldo disponivel restaurado;
- registrou ajuste manual negativo e positivo em PA;
- validou saldo de PA apos os ajustes auditados.

Resultado: passou.

## Smoke test funcional

Fluxo positivo validado:

1. Criar cliente de teste.
2. Criar vendedor de teste.
3. Criar produto, embalagem e item vendavel de teste.
4. Criar pedido.
5. Liberar credito.
6. Criar romaneio em rascunho.
7. Registrar separacao com lote PA.
8. Confirmar romaneio.
9. Verificar movimento de baixa PA.
10. Verificar pedido `fulfilled` quando romaneio total fecha o saldo.
11. Estornar romaneio.
12. Verificar movimento inverso de estorno.
13. Verificar pedido reaberto como `open`.

Resultado: fluxo completo passou.

## Testes negativos

Regras negativas validadas:

- romaneio acima do saldo pendente falha com `romaneio exceeds pending order quantity`;
- confirmacao de romaneio falha se o pedido deixa de estar `open`.

Resultado: travas passaram.

## Limites da validacao

- `supabase db lint` conectou ao banco descartavel, mas falhou ao habilitar `pgsql_check`, extensao nao disponivel no PostgreSQL vanilla instalado localmente.
- Docker nao esta disponivel/rodando nesta sessao, entao `supabase start`, `migration list --local` e `db reset` da stack local Supabase nao foram executados.
- Nenhum dado real foi usado.
