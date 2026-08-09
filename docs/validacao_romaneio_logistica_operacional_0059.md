# Validacao - Romaneio e logistica operacional 0059

Data: 2026-07-15

## Escopo

O Bloco 6 permanece no modulo proprietario `expedicao`, com dependencias ja
aprovadas de `pedidos` e `estoque`. Esta entrega nao criou modulo, rota ou
dependencia nova.

Foram completadas as lacunas operacionais que ja tinham contrato relacional na
DEC-008:

- atribuicao auditada de entregador e/ou veiculo ao romaneio;
- remocao auditada sem apagar eventos anteriores;
- leitura do estado atual derivado do ledger append-only;
- selecao exclusiva de pessoa ativa com papel relacional `entregador` vigente;
- selecao exclusiva de veiculo ativo;
- indicacao, no romaneio, dos documentos fiscais existentes ou da pendencia de
  faturamento depois da confirmacao;
- substituicao dos `datalist` que interpretavam texto por `select` com IDs
  relacionais reais.

## Contrato de seguranca

- actions `romaneios.logistics.assign` e `romaneios.logistics.remove`;
- ownership de runtime: `expedicao`, escrita;
- RPCs `security definer` passam por `begin_audited_rpc` antes de validar
  parametros ou ler tabelas operacionais;
- escrita direta em `exp_romaneio_logistica_eventos` continua revogada;
- eventos continuam protegidos pelo trigger append-only da DEC-008;
- RPCs sao executaveis por `authenticated` e nao por `anon`/`PUBLIC`;
- `correlation_id`: `romaneio:<id>:logistics`.

## Regras validadas

1. Somente romaneio `draft`, `separacao` ou `confirmado` aceita atribuicao ou
   remocao logistica.
2. Atribuicao exige entregador ou veiculo.
3. Entregador precisa estar ativo e possuir papel `entregador` ativo e vigente.
4. Veiculo precisa estar ativo.
5. Repetir a mesma atribuicao e rejeitado sem gerar evento duplicado.
6. Remocao exige motivo e atribuicao ativa.
7. Atualizacao ou exclusao de evento anterior permanece proibida.
8. Informacao fiscal e somente leitura; nenhuma regra de NF foi movida para
   Expedicao.

## Validacao executada

- teste de contrato Python: `8/8` aprovado;
- TypeScript `--noEmit --incremental false`: aprovado;
- ESLint direcionado aos quatro arquivos TypeScript alterados: aprovado, sem
  warning;
- build de producao Next.js 16.2.10: aprovado, com 24 paginas geradas e a rota
  `/romaneios` presente;
- instalacao limpa das migrations `0001` a `0059` no projeto separado
  `elite-validation-0059`: aprovada;
- container e volume usados: `supabase_db_elite-validation-0059`, sem contato
  com `supabase_db_elite-system`;
- smoke transacional: `PG_VALIDATE_0059_WITH_SMOKE_OK`;
- lint PostgreSQL: nenhum erro de schema;
- `git diff --check`: aprovado no fechamento.
- commit `c54c328` publicado na branch privada
  `feature/0044-production-module-release`;
- migration 0059 registrada no Supabase cloud `elite-system-staging`;
- build da Vercel concluido e alias atualizado em
  `https://elite-system-staging.vercel.app`;
- `/api/health` respondeu `status=ok` com backend configurado;
- `/romaneios` respondeu `307` para o login quando acessado sem sessao.

O sweep global default-deny foi executado no banco descartavel ainda declarado
como `unconfigured`. Ele encontrou duas dividas anteriores e fora deste escopo
em RPCs de importacao (`approve_migration_mp_mapping` e
`register_migration_mp_acquisition_value`), bloqueadas pelo gate do modulo
`auditoria`. O ator sem grants da propria 0059 foi testado no smoke e recebeu
`not allowed: romaneios.logistics.assign` antes da validacao de parametros.

## Homologacao visual

A composicao local foi conferida em desktop e em viewport mobile de 390 x 844:
sem rolagem horizontal, sem `datalist` e com os formularios reorganizados para
a largura disponivel. Esta evidencia valida o layout, mas nao substitui o
cenario funcional autenticado no banco de staging.

Pendente no staging com usuario autenticado. O gate visual deve confirmar:

1. criacao total e parcial;
2. inclusao de varios itens;
3. reserva de um ou varios lotes PA;
4. atribuicao e remocao de entregador/veiculo;
5. confirmacao com baixa PA;
6. indicacao de pendencia/documento fiscal;
7. cancelamento e estorno;
8. desktop e mobile sem rolagem horizontal incoerente.

Nenhum dado operacional, workbook, credencial ou captura local integra esta
entrega.
