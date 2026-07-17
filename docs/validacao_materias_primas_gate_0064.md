# Validacao 0064 - Gate tecnico de materias-primas

Data: 2026-07-17

## Modelo relacional comprovado

- `cad_tipos_insumo.id` e a PK do catalogo; `cad_materias_primas.tipo_insumo_id`
  referencia essa PK sem `ON DELETE CASCADE` e o trigger bloqueia exclusao fisica.
- `idx_cad_materias_tipo_insumo` atende classificacao e revisao.
- `cad_materias_primas.unidade_base_estoque_id` e FK obrigatoria para
  `cad_unidades_medida.id`; criacao e edicao recebem o ID, nao texto livre.
- `cad_materias_primas_sku_norm_key` impede SKU equivalente por caixa, espaco
  ou formatacao, inclusive em transacoes simultaneas.
- RLS permite leitura somente a perfil autenticado ativo. Escrita direta fica
  revogada; RPCs auditadas validam as permissoes atomicas de Cadastros.
- `tipo` permanece apenas como legado congelado para reconciliacao. Nao e
  enviado pela tela, alterado por RPC ou consultado como fonte operacional.
- Nenhum backfill de tipo foi inferido; ausencia permanece pendente de revisao.

## Duplicidade

Antes da criacao, `find_cad_materia_prima_possible_duplicates` retorna registros
com mesmo nome normalizado ou codigo legado. O operador ve SKU, nome, tipo,
unidade e motivos. Prosseguir exige confirmacao e justificativa, registradas em
`action_logs`. Nome nao possui UNIQUE global.

Fabricante, concentracao, pureza e especificacao nao foram inventados porque
esses campos ainda nao integram o cadastro atual.

## Validacao descartavel

Projeto: `elite-validation-tipos-insumo`, container e volume exclusivos.
O runtime ativo `elite-system` permaneceu em execucao e nao foi migrado.

- upgrade 0063 para 0064: aprovado;
- instalacao limpa da cadeia ate 0064: migrations aprovadas; o CLI aguardou o
  Storage alem do timeout, que ficou `healthy` em seguida;
- smoke transacional: `PG_VALIDATE_0063_WITH_SMOKE_OK`;
- ID inexistente e tipo inativo em novo vinculo: recusados;
- vinculo antigo com tipo inativo: legivel;
- exclusao de tipo usado: recusada;
- usuario sem permissao, `anon` e `PUBLIC`: recusados;
- SKU exato, variacao de caixa/espaco/formatacao: recusados;
- concorrencia: duas gravacoes simultaneas, uma aprovada, uma recusada e um
  unico registro persistido (`CONCURRENCY_0064 success=1 failed=1 persisted=1`);
- homonimo sem confirmacao: recusado; confirmacao motivada: auditada;
- PostgreSQL lint em nivel de erro: sem achados;
- 27 testes dirigidos de Cadastros: aprovados;
- ESLint, TypeScript e build Next.js: aprovados;
- `git diff --check` e varredura de segredos/arquivos proibidos: aprovados.

## Resultado

Tipos de Insumo e Materias-primas atendem ao gate tecnico 0064. A interface
permanece visualmente homologada por Luciano e o macrociclo UX-01C pode seguir.
