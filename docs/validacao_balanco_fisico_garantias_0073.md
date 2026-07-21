# Validação do balanço físico de garantias - 0073

Data: 2026-07-21

## Regra validada

A garantia calculada de uma OP operacional usa fatos físicos por lote:

1. quantidade efetivamente consumida;
2. garantia vigente do lote consumido;
3. densidade vigente do lote, quando for necessária conversão entre massa e volume;
4. massa e volume finais registrados no CQ.

Percentual é armazenado em pontos percentuais: `12` representa `12%`. Valores
acima de `100%` são recusados. Garantia percentual fecha contra a massa final;
garantia em `kg/L` fecha contra o volume final.

Quando faltar garantia do lote ou densidade necessária, o resultado numérico
fica nulo e a pendência é registrada. A densidade genérica do cadastro da MP
não é usada como substituta silenciosa.

## Persistência e segurança

- nova tabela append-only `cad_lote_mp_parametros_tecnicos`;
- FK obrigatória para `est_lotes_mp`;
- histórico encadeado por `supersedes_id`;
- escrita somente pela RPC auditada `registrar_pcp_parametros_lote_mp`;
- leitura somente para usuário autenticado ativo;
- `anon` e `PUBLIC` sem execução da RPC;
- `authenticated` sem `INSERT`, `UPDATE` ou `DELETE` direto;
- cálculo versionado com método `balanco_fisico_v1` e evidências em
  `base_calculo_json`.

## Ambientes descartáveis

### Upgrade 0072 -> 0073

Container: `supabase_db_elite-validation-real-production`.

Resultado:

- migration aplicada sem erro;
- smoke transacional aprovado;
- dados reais descartáveis preexistentes preservados durante o upgrade;
- runtime local ativo, staging e produção não foram acessados.

### Instalação limpa 0001 -> 0073

Projeto: `elite-validation-0073-clean`.

Container e volume exclusivos:

- `supabase_db_elite-validation-0073-clean`;
- `supabase_db_elite-validation-0073-clean-data`.

A trava `assert-disposable-supabase-target.ps1` retornou
`ELITE_DISPOSABLE_TARGET_OK` antes da criação. As 71 migrations versionadas
foram instaladas em ordem e o processo terminou com
`PG_CLEAN_INSTALL_0001_0073_OK`.

## Cenários comprovados

- garantia de lote `10%`, consumo real de `10 kg` e massa CQ de `10 kg` gera
  resultado `10%`;
- resultado compara corretamente contra mínimo MAPA;
- recálculo cria nova versão sem alterar a anterior;
- percentual `101%` é recusado;
- consumo em litros com garantia percentual e sem densidade do lote gera
  `base_incompleta`, sem valor calculado;
- lote sem garantia gera `sem_dados_lote`, sem valor calculado;
- ID do parâmetro de densidade e todos os insumos usados ficam no JSON de base;
- gravações e cálculos geram auditoria;
- escrita direta e acesso anônimo permanecem negados.

O smoke usa transação com `ROLLBACK` e retorna
`PG_PRODUCTION_MODULE_RELEASE_OK`.

## Gates de aplicação

- ESLint: aprovado;
- TypeScript `--noEmit`: aprovado;
- build Next.js: aprovado, 29 páginas geradas;
- testes dirigidos de Produção: 25/25 aprovados;
- `plpgsql_check` nas duas funções novas: zero ocorrências; a tentativa de
  `supabase db lint` não alcançou a porta interna não publicada do container,
  portanto não foi usada como falsa evidência de aprovação;
- `git diff --check`: aprovado.

A suíte geral executou 452 testes e encontrou três falhas preexistentes, fora
do escopo da 0073: contrato textual antigo de Romaneio, contrato da assinatura
institucional anterior e uma expectativa anterior de Cadastros. Nenhuma delas
foi causada pelos arquivos deste pacote; não foram corrigidas para evitar
mistura de escopo.

## Gate de staging

O dry-run mostrou exclusivamente `0073_pcp_physical_guarantee_balance.sql`.
A migration foi aplicada sem reset e o ledger passou a mostrar 0073 local e
remota. O aviso posterior de cache `pg-delta` da CLI não afetou a aplicação e o
ledger foi consultado novamente como verificação independente.

O Preview Vercel do projeto `elite-system-staging`, vinculado ao commit
`bf136b3`, foi promovido para `elite-system-staging.vercel.app`. Resultado:

- `/api/health`: `status=ok`, `backendConfigured=true`;
- sessão autenticada abriu `/producao/garantias`;
- commit `bf136b3` visível no shell;
- cadastro da base física e histórico de densidades presentes;
- assinatura `by ☧ SYSTEMS` preservada;
- viewport 390 x 844 sem rolagem horizontal.

Nenhum dado sintético foi criado no staging durante esse smoke.
