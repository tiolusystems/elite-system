# Validacao da migration 0032 - metas event ledger contract

Data da validacao: 2026-07-05

## Objetivo

Validar o primeiro contrato operacional de metas comerciais.

Escopo:

- criar `axis = target_event`;
- criar periodos customizados de meta;
- criar ledger append-only de movimentos de meta;
- criar lock tecnico por pessoa + periodo para o futuro motor de faixas;
- manter saldo de meta como view derivada, nao campo editavel;
- registrar venda aberta, cancelamento, devolucao e ajuste manual por RPC auditada;
- manter devolucao com motivo `qualidade` sem penalizacao de meta.

## Decisoes confirmadas

- Meta e faixa nao sao liberacao financeira.
- Recebimento continua controlando quando comissao e liberada.
- Meta usa vendido ativo.
- Pedido entra na meta apenas quando estiver `open`.
- Venda aberta usa a data do pedido para escolher o periodo.
- Cancelamento e devolucao abatem no periodo do evento, sem reabrir o periodo original.
- Devolucao por qualidade nao penaliza vendedor.
- Ajuste manual de meta exige motivo padronizado; `outro` exige detalhe.
- A tabela de lock por pessoa + periodo nao armazena saldo.

## Entrega tecnica

Migration: `supabase/migrations/0032_metas_event_ledger_contract.sql`.

Entregue:

- `com_meta_periodos`;
- `com_meta_pessoa_periodo_locks`;
- `com_meta_movimentos`;
- view `com_meta_saldos_pessoa_periodo`;
- `upsert_com_meta_periodo(...)`;
- `registrar_com_meta_venda_aberta(...)`;
- `registrar_com_meta_cancelamento_pedido(...)`;
- `registrar_com_meta_devolucao_nf(...)`;
- `registrar_com_meta_ajuste_manual(...)`.

## Fora desta etapa

- chamada automatica do ledger pelas RPCs de pedido;
- chamada automatica do ledger pela RPC de estorno pos-pagamento;
- motor de faixa de comissao com fracionamento por volume acumulado;
- telas de cadastro/consulta de periodos e saldos de meta.

Motivo: o acoplamento automatico deve vir depois do cadastro dos periodos customizados para evitar que criacao ou cancelamento de pedidos falhe por ausencia de periodo configurado.

## Validacao executada

Comandos:

```text
python -m unittest tests.test_metas_ledger_contract
python -m unittest discover -s tests -p "test*.py"
pnpm --dir apps/web lint
pnpm --dir apps/web build
```

Validacao em PostgreSQL descartavel:

```text
PG_VALIDATE_0032_WITH_SMOKE_OK
```

Smoke `.tools/smoke_metas_0032.sql` validou:

- periodo customizado criado por RPC auditada;
- pedido `open` de venda registrado como movimento positivo de meta;
- segunda tentativa de registrar a mesma venda falha sem duplicar movimento;
- cancelamento gera movimento negativo no periodo do evento;
- devolucao por motivo comercial gera movimento negativo;
- devolucao por qualidade retorna zero movimento e registra auditoria sem penalizacao;
- ajuste manual exige motivo padronizado e registra movimento append-only;
- tentativa de `UPDATE` direto no ledger falha pelo trigger append-only;
- saldo de meta e derivado pela view `com_meta_saldos_pessoa_periodo`.
