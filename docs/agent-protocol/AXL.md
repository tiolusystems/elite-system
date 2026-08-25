# AXL/1

AXL (Agent Execution Language) e uma DSL de execucao entre GPT e Codex. Nao e
linguagem de programacao, nao substitui decisoes de negocio e nao oculta regras
materiais definidas por Luciano.

## Estrutura obrigatoria

```text
TASK <nome e resultado delimitado>
STATE <baseline verificavel: branch, HEAD, arvore, ambiente>
RULE <invariantes e decisoes humanas aplicaveis>
EXEC <menor delta completo e correto>
VERIFY <evidencias proporcionais exigidas>
REPORT <fatos, arquivos, resultados e pendencias>
STOP <limite explicito; ex.: before=commit>
```

`STATE` descreve fatos verificaveis, nunca suposicoes. `VERIFY` deve listar
comandos ou evidencias esperadas. `REPORT` distingue executado, nao executado,
bloqueado e pendente. Sem evidencia, nao ha afirmacao de execucao, teste,
commit, push ou deploy.

## Operadores

| Operador | Significado |
|---|---|
| `=` | invariante ou estado exigido |
| `!` | proibido |
| `+` | adicionar |
| `~` | mudanca compativel |
| `@` | escopo |
| `#` | referencia versionada |
| `>` | precedencia |
| `?` | decisao ainda nao resolvida |

## Risco

| Nivel | Tipo |
|---|---|
| `R0` | documentacao ou ajuste trivial |
| `R1` | mudanca local |
| `R2` | mudanca de dominio |
| `R3` | integridade ou transacao |
| `R4` | seguranca, financeiro ou autorizacao |

O nivel orienta leitura, validacao e revisao. Ele nao autoriza ampliar escopo.
Todo bloco deve buscar o `smallest_complete_correct_delta`, aplicar
`proportional_validation` e encerrar no `STOP` declarado.

## Limites

- Regras de negocio e decisoes humanas permanecem legiveis em portugues.
- AXL pode ser compacto e tecnico, mas deve apontar para a regra humana que o
  fundamenta.
- Historico Git e a fonte de verdade da implementacao publicada; narrativa de
  chat nao substitui commit, diff, teste ou CI.
