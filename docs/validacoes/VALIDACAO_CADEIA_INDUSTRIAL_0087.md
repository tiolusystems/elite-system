# Validação da cadeia industrial integrada 0087

## Objetivo

Provar numa única transação o fluxo:

`cadastros -> fórmula operacional -> OP -> reserva -> produção -> CQ -> lote PI -> OP MAPA + Envase -> embalagem -> lote PA -> relatórios`

Todos os dados do cenário são sintéticos e a execução termina com `ROLLBACK`.

## Regra consolidada

- a OP operacional gera exatamente um produto e um lote PI;
- o volume efetivo do CQ define a quantidade do PI;
- CQ aprovado libera o PI para Envase;
- a OP MAPA é documental e nasce junto da Ordem de Envase;
- o Envase só inicia com PI e embalagens integralmente reservados;
- cada Ordem de Envase finalizada gera exatamente um lote PA;
- o custo direto do PA soma PI e embalagens, sem custo operacional ou indireto;
- PI e PA aparecem nos relatórios por família e o PA aparece na posição em litros e volumes.

## Evidência automatizada

- `tests/sql/production_end_to_end_chain.sql`: cenário transacional completo;
- `tests/test_production_end_to_end_chain_contract.py`: cobertura estrutural e ligação ao CI;
- `tests/sql/pcp_mapa_packaging_order_foundation.sql`: smoke de Envase atualizado para um lote PA;
- `supabase/migrations/0087_packaging_single_pa_lot.sql`: trava do banco contra múltiplos lotes PA na mesma Ordem de Envase.

## Gates locais

- 522 testes Python: aprovados;
- ESLint: aprovado;
- TypeScript `--noEmit`: aprovado;
- build Next.js: aprovado;
- `git diff --check`: aprovado.

## PostgreSQL descartável

A workdir temporária `elite-validation-0087-chain` foi preparada com projeto,
portas, container e volume próprios. A proteção
`ELITE_DISPOSABLE_TARGET_OK` foi aprovada. A inicialização do Supabase não foi
executada porque a aprovação automática da ferramenta expirou duas vezes.

O smoke integrado foi ligado ao job `database-contract` do CI. A migration só
pode ser aplicada ao staging depois de o CI reconstruir todas as migrations e
executar `PG_PRODUCTION_END_TO_END_CHAIN_OK` num Supabase descartável.

## Proibições preservadas

- nenhum reset no runtime ativo;
- nenhum dado real ou operacional;
- nenhuma aplicação em produção real;
- nenhuma escrita direta liberada;
- nenhuma alteração em `main`.
