# Validacao da idempotencia operacional - migrations 0091 a 0102

Data: 2026-07-22

## Objetivo

Impedir que duplo clique, retry de rede ou duas chamadas concorrentes criem
efeitos fisicos ou financeiros duplicados. O contrato usa uma chave UUID por
intencao do operador, validada novamente no PostgreSQL.

## Operacoes protegidas

| Migration | Operacao | Resultado reaproveitado no retry |
| --- | --- | --- |
| 0091 | Registro de recebimento | recebimento criado |
| 0092 | Pagamento de comissao | evento financeiro criado |
| 0093 | Ajuste manual de comissao | evento financeiro criado |
| 0094 | Pedido enviado pelo vendedor | pedido criado |
| 0095 | Ordem de producao | OP criada |
| 0096 | Formula operacional | versao criada |
| 0097 | Decisao gerencial e limite de credito | decisao ou snapshot criado |
| 0098 | Rascunho de Romaneio | Romaneio criado |
| 0099 | OP MAPA e Ordem de Envase | par documental criado |
| 0100 | Pedido de troca | pedido de troca criado |
| 0101 | Atribuicao manual de comissao | comissionado criado ou revisado |
| 0102 | Emissao fiscal | nota fiscal criada |
| 0102 | Estorno pos-pagamento | NF de devolucao e retorno de estoque criados |

## Contrato comum

- a interface gera uma chave UUID antes do envio;
- a Server Action valida e encaminha essa chave;
- a RPC adquire trava transacional por ator e chave;
- retry com o mesmo payload retorna o resultado original;
- reutilizacao da chave com payload diferente e rejeitada;
- a RPC antiga sem chave deixa de ser executavel por `authenticated`, `anon` e
  `PUBLIC`;
- a implementacao interna continua inacessivel aos papeis da API;
- tabelas internas de requisicao nao sao abertas para escrita ou leitura direta;
- efeitos operacionais continuam sujeitos a permissao, RLS e auditoria.

## Evidencias

- CI GitHub Actions do commit `54d18c9`: concluida com sucesso;
- testes Python de contrato: aprovados;
- ESLint, TypeScript e build Next.js: aprovados;
- migrations instaladas do zero em PostgreSQL descartavel pela CI;
- smokes SQL cobrem retry identico, payload divergente e privilegios;
- dry-run remoto listou somente `0097` a `0101` antes da ultima aplicacao;
- ledger do Supabase de staging alinhado ate `0102`;
- `https://elite-system-staging.vercel.app/api/health`: `status=ok` e
  `backendConfigured=true` depois da aplicacao.

## Idempotencia natural mantida

A importacao XML de NF-e nao recebeu outra tabela de requisicao porque ja possui
chave de acesso normalizada unica, item unico por NF e um unico lote de MP por
item. Essa combinacao impede duplicacao do fato de origem no banco.

Confirmacao, cancelamento e reversao de Romaneio continuam governados por estado
e locks das linhas operacionais. Uma segunda chamada encontra o estado ja
consumido e falha antes de repetir a baixa fisica.

## Decisao fiscal ainda pendente

O novo ponto de entrada idempotente impede duplicacao por retry mesmo quando a
chave de NF-e ainda nao foi informada. Quando a chave existe, o indice unico
continua fornecendo uma segunda protecao pela identidade fiscal externa.

Permanece uma decisao fiscal, que nao foi alterada silenciosamente:
definir se o sistema admite rascunho sem chave ou se toda emissao definitiva
deve exigir chave de NF-e. Ate essa decisao, a interface atual nao oferece uma
criacao fiscal livre.

## Limites

- nenhum dado comercial real foi criado;
- nenhuma migration foi aplicada em producao real;
- `main` nao foi alterada;
- o frontend mais recente ainda depende de nova janela de deploy da Vercel;
- o backend de staging esta atualizado e saudavel ate `0102`.
