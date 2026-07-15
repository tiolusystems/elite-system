# Validacao do fluxo integral de Producao

Data: 2026-07-15
Ambiente: Supabase local, somente dados sinteticos de homologacao
Migration: `0058_restore_production_catalog_view_access.sql`

## Escopo

Esta validacao cobre exclusivamente:

`produto -> formula -> OP -> reserva -> inicio -> CQ -> finalizacao -> lote PI`

Nao foram iniciados `F1.2d`, `I2`, transformacoes ou novas telas.

## Causa do bloqueio

- as views `cad_garantias_produto_mapa_atuais` e
  `cad_garantias_lote_mp_atuais` pertencem a `postgres` e usam
  `security_invoker=true`;
- as tabelas-base `cad_garantias_produto_mapa` e
  `cad_garantias_lote_mp` mantem RLS habilitada e politica de leitura para
  `authenticated` condicionada a `current_actor_id() is not null`;
- a migration `0050_relational_commercial_catalogs.sql` recriou as duas views
  depois do contrato original da `0044`, mas nao restaurou `GRANT SELECT`;
- por isso, o usuario autenticado ativo recebia
  `permission denied for view cad_garantias_produto_mapa_atuais` antes que a
  RLS da tabela-base pudesse ser avaliada;
- `apps/web/lib/pcp.ts` consome as duas views com o cliente de sessao do
  Supabase. Nao existe `service_role` no cliente.

## Correcao aplicada

A `0058` revoga os privilegios das views de `PUBLIC`, `anon` e
`authenticated`, e concede somente `SELECT` a `authenticated`. A migration
tambem falha se alguma view deixar de usar `security_invoker=true`.

Estado validado apos a correcao:

- `authenticated`: `SELECT` nas duas views;
- `anon` e `PUBLIC`: sem `SELECT`;
- tabelas-base: RLS ativa;
- usuario de teste: `Luciano Machado`, perfil `admin`, status `active`;
- smoke SQL: `PG_PRODUCTION_CATALOG_VIEW_ACCESS_OK`.

## Cenario funcional executado

1. Produto sintetico `9058`, validade de 24 meses.
2. MP e lote sinteticos com entrada inicial de 100 kg.
3. Formula de producao v1 com 10 kg da MP, ativada pela interface.
4. OP `OP-20260715-0000001`, tipo estoque, quantidade planejada 10.
5. Reserva de 10 kg: fisico 100, reservado 10, disponivel 90.
6. Inicio da OP: status `in_process`, sem baixa fisica antecipada.
7. CQ aprovado: pH 6.5, densidade 1 kg/L, volume 10 L, massa 10 kg,
   temperatura 25 C e participantes identificados.
8. Finalizacao em transacao unica: consumo de 10 kg e entrada de 10 unidades
   do PI.
9. Lote automatico `PI-20260715-0000001`, status `disponivel`.

## Reconciliacao

| Fato | Antes | Depois | Resultado |
| --- | ---: | ---: | --- |
| Saldo fisico MP | 100 | 90 | correto |
| Reserva ativa MP | 10 | 0 | correta |
| Saldo disponivel MP | 90 | 90 | correto |
| Movimento MP | entrada 100 | consumo -10 | append-only |
| Saldo fisico PI | 0 | 10 | correto |
| Movimento PI | 0 | entrada producao +10 | append-only |
| OP | `in_process` | `completed` | correto |
| CQ | nao informado | `aprovado` | correto |

A reserva terminou como `baixada`, o componente como `consumed` e o consumo
registrado foi 10. Os eventos `pcp.op_finished`, `pcp.cq_recorded`,
`estoque.mp_consumed_by_op` e `estoque.pi_entry_from_op` foram gravados com
status `success` e o mesmo `correlation_id`: `pcp_op:1:finish`.

## Evidencia visual

- produto de teste no cadastro tecnico;
- painel antes do fluxo;
- formula v1 ativa;
- OP aberta;
- reserva do lote;
- OP em processo;
- dados de processo e CQ;
- lote PI disponivel;
- painel final sem OP aberta.

As capturas ficam no artefato local de validacao e nao sao versionadas com
dados operacionais.

## Limites desta homologacao

- o caminho homologado gerou PI; o caminho PA com embalagem nao foi repetido;
- CQ bloqueado/reprovado ja possui contrato, mas nao foi o resultado deste
  cenario;
- transformacoes PA/PI, reenvasamento e reprocessamento pertencem a `F1.2d` e
  nao foram iniciados;
- a homologacao ocorreu no ambiente local de teste, nao no staging.

## Gates de fechamento

- 8 testes direcionados da `0058` e da trava de ambiente: aprovados;
- smoke de permissionamento: `PG_PRODUCTION_CATALOG_VIEW_ACCESS_OK`;
- teste do alvo ativo: bloqueado com
  `ELITE_DESTRUCTIVE_VALIDATION_BLOCKED`;
- lint PostgreSQL: nenhum erro de schema;
- ESLint direcionado aos 7 arquivos TypeScript/TSX alterados: aprovado;
- TypeScript com `--noEmit`: aprovado;
- `git diff --check`: aprovado imediatamente antes do commit.

## Incidente de ambiente

### Comando causador

O incidente comecou ao executar o equivalente a:

```powershell
.\.tools\supabase-cli\supabase.exe db reset --db-url "<URL do PostgreSQL local ativo>"
```

A URL foi omitida deste documento para nao registrar credencial. O destino era
o PostgreSQL do projeto ativo `elite-system`, nao um projeto descartavel.

### Esperado e observado

- esperado: aplicar a cadeia `0001` a `0058` em banco isolado, sem tocar no
  runtime usado pela aplicacao e pela sessao autenticada;
- observado: o reset atingiu o banco local ativo. O container deixou de
  representar o estado anterior e o runtime precisou ser reconstruido;
- impacto real: interrupcao do login, perda da sessao e necessidade de refazer
  o ambiente local antes de continuar o E2E;
- dados operacionais perdidos: nenhum. Antes do incidente nao existiam produto,
  MP, formula, OP, lote ou movimento operacional no banco local;
- dados locais perdidos: conta/sessao local anterior e seus registros locais de
  auditoria/rollout, todos pertencentes ao ambiente de teste;
- dados preservados: codigo, migrations, documentacao, workbook fora do Git,
  staging Supabase/Vercel e todos os ambientes cloud. Nenhum banco cloud foi
  alterado.

### Recuperacao e tempo

- volumes remanescentes foram inspecionados antes de qualquer descarte e nao
  continham uma recuperacao compativel do estado ativo;
- o Supabase local foi reconstruido pelas migrations `0001` a `0058`;
- a conta administrativa foi restaurada por
  `scripts/bootstrap-local-admin.ps1`, seguida da definicao pessoal da senha;
- o ambiente foi novamente declarado como teste por acao auditada;
- tempo tecnico mensuravel: aproximadamente 20 minutos, das 09:35 as 09:55
  (America/Sao_Paulo), entre a falha e o bootstrap administrativo;
- tempo decorrido ate a retomada autenticada: aproximadamente 3 h 36 min, ate
  13:11, incluindo a etapa manual de definicao da senha.

### Causa tecnica

`--db-url` recebeu a URL do banco em uso. O comando nao possuia isolamento por
projeto/container/volume e o repositorio nao tinha uma trava que comparasse o
alvo com o `project_id` ativo. A validacao tratou um destino persistente como
descartavel.

### Prevencao permanente

- `scripts/assert-disposable-supabase-target.ps1` le o `project_id` ativo e
  bloqueia esse alvo mesmo com autorizacao explicita;
- somente projetos `elite-validation-*`, com container e volume proprios, sao
  aceitos para validacao destrutiva;
- falta de autorizacao explicita tambem aborta;
- `tests/test_disposable_supabase_validation_guard.py` prova os caminhos de
  bloqueio e o unico caminho descartavel aceito;
- `AGENTS.md` torna a verificacao obrigatoria para agentes e desenvolvedores;
- nenhuma validacao pode executar reset, start de validacao ou migration
  destrutiva contra o runtime em uso sem autorizacao nominal para aquela
  operacao e ambiente.
