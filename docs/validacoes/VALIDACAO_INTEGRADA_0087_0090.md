# Validação integrada 0087 a 0090

Data: 2026-07-22  
Branch: `feature/0044-production-module-release`  
Commit: `6802d62`

## Escopo

- lote PA único por Ordem de Envase;
- atribuição flexível de comissão no pedido;
- cálculo de garantias com unidades operacionais por litro;
- restauração controlada das RPCs auditadas da importação histórica de MP;
- compatibilidade dos smokes antigos com os contratos governados atuais.

## Gates aprovados

O GitHub Actions `29928630391` concluiu com sucesso:

- `web-contract`;
- `python-tests`;
- `database-contract`;
- reconstrução limpa de todas as migrations;
- cadeia industrial integrada;
- atribuição de comissão e cadeia comercial integrada;
- importação histórica de MP;
- catálogos, embalagens, logística e contratos históricos;
- Romaneio e Segurança.

## Aplicação no staging

O ledger remoto estava sincronizado até `0086`. O dry-run listou somente:

1. `0087_packaging_single_pa_lot.sql`;
2. `0088_order_commission_assignment.sql`;
3. `0089_pcp_guarantee_per_liter_units.sql`;
4. `0090_restore_historical_mp_audited_rpc_access.sql`.

As quatro migrations foram aplicadas sem reset. A consulta posterior do ledger
confirmou todas até `0090`. O aviso final do CLI ocorreu apenas na geração do
cache local `pg-delta`; não alterou o resultado remoto confirmado pelo ledger.

## Saúde

- `/api/health`: `status=ok` e `backendConfigured=true`;
- `/login`: HTTP 200;
- Git local/remoto: sincronização `0/0`;
- Preview do projeto Vercel correto `elite-system-staging`: sucesso para
  `6802d62`;
- domínio estável ainda não promovido e permanece no release `0dd79bd`.

## Restrições preservadas

- nenhuma alteração em `main`;
- nenhuma publicação em produção real;
- nenhum reset ou remoção de dados;
- nenhuma credencial ou dado operacional versionado;
- RPCs restauradas continuam exigindo usuário autenticado, permissão atômica e
  auditoria; `anon` e `PUBLIC` permanecem negados.
