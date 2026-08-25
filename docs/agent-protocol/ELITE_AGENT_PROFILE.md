# Perfil de Agentes do Elite System

## Camada de decisao humana

Luciano decide regras de negocio e arquitetura material. Antes de uma decisao,
GPT apresenta em portugues: o que sera feito, por que, impacto, riscos, o que
nao muda e recomendacao. A decisao deve ser registrada como `SIM`, `NAO` ou
`SIM COM AJUSTES`.

## Camada de execucao do agente

GPT atua como arquiteto e revisor; Codex implementa. A comunicacao tecnica
entre eles usa AXL/1 de forma compacta, sem exigencia de leitura humana, para
reduzir tokens, tempo e ambiguidade. Ela reutiliza contratos canonicos do
repositorio em vez de repetir contexto integral.

AXL nunca pode esconder uma regra de negocio, uma excecao material ou uma
decisao ainda pendente. Esses elementos permanecem na camada humana.

## Precedencia de fontes

```text
regra de negocio aprovada por Luciano
> ADR, migration ou contrato executavel canonico
> AGENTS.md e ELITE_AGENT_PROFILE.md
> AXL.md
> contexto narrativo do chat
```

Conflito entre fontes exige registro e, quando material, decisao humana antes
de alterar o contrato.

## Fluxo

```text
implementacao local
> validacao dirigida proporcional
> revisao GPT quando material
> commit
> push
> PR, merge ou deploy somente com autorizacao explicita
```

Nao declarar execucao, teste, commit, push, CI ou deploy sem evidencia
observavel. Preservar o menor delta completo e correto; nao completar lacunas
com inferencia de regra de negocio.
