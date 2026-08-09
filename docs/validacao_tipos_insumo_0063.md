# Validação 0063 - Tipos de insumo

Data: 2026-07-17

## Escopo

- catálogo relacional `cad_tipos_insumo`;
- FK opcional de matéria-prima para tipo governado;
- preservação do texto legado, sem inferência;
- RLS de menor privilégio e RPCs auditadas;
- tela PT-BR para consulta, cadastro, edição e controle de situação;
- classificação manual e auditada da matéria-prima.

## Ambiente descartável

Os testes de banco foram executados exclusivamente no projeto
`elite-validation-tipos-insumo`, com container e volume próprios. O runtime
local ativo `elite-system` não foi parado, resetado ou migrado.

## Evidências

- instalação limpa da cadeia até 0063: aprovada;
- upgrade de 0062 para 0063: aprovado;
- texto legado preservado e `tipo_insumo_id = null`: aprovado;
- fila `pending_review` para legado não classificado: aprovada;
- classificação por inferência: zero;
- smoke SQL: `PG_VALIDATE_0063_WITH_SMOKE_OK`;
- lint PostgreSQL em nível de erro: sem achados;
- ESLint dirigido: aprovado;
- TypeScript `--noEmit --incremental false`: aprovado;
- build Next.js de produção em cópia descartável: aprovado.
- instalação limpa pelo `pnpm-lock.yaml` e build Turbopack equivalente ao
  ambiente Vercel: aprovados;
- migration 0063 registrada no Supabase cloud `elite-system-staging`, sem
  aplicar a migration paralela 0062.

## Cenário pela interface

Com ator sintético individual e banco descartável:

1. login autenticado e ambiente Teste identificados;
2. catálogo inicialmente vazio e uma MP legada pendente exibidos;
3. tipo criado com código, nome, descrição, ordem e motivo;
4. tipo editado com motivo;
5. tipo inativado e reativado sem exclusão física;
6. MP legada permaneceu sem classificação automática;
7. seletor relacional apresentou somente o tipo governado ativo.

O smoke SQL comprovou também a atribuição da FK, o `before_json`/`after_json`,
a negação anônima, a rejeição de FK inexistente e o bloqueio de exclusão.

## Limitação do ambiente

O teste estático em Python não foi executado porque não existe runtime Python
instalado ou fornecido pelo projeto nesta máquina. A limitação não foi tratada
como aprovação silenciosa. O mesmo contrato foi coberto por smoke SQL, lint,
TypeScript e build; o teste Python permanece pronto para o CI.

## Segurança de dados

Foram utilizados apenas dados sintéticos no ambiente descartável. Nenhuma
credencial, captura, workbook, dump, dado de homologação ou dado operacional
integra esta entrega.
