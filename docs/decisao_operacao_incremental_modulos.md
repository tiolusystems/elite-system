# Decisao de operacao incremental por modulos

Data: 2026-07-10

## Objetivo

Permitir que modulos tecnicamente prontos sejam usados e homologados enquanto os demais continuam em construcao, sem transformar o frontend em fonte de verdade e sem espalhar condicionais por todas as telas e RPCs.

## Decisao

O PostgreSQL e a fonte autoritativa do ambiente, do estagio de cada modulo, do modo de acesso e das dependencias. O Next.js apenas consulta esse contrato e apresenta o resultado.

O controle possui quatro partes:

1. catalogo estatico de modulos e rotas;
2. grafo relacional de dependencias obrigatorias ou opcionais;
3. eventos append-only de ambiente e de rollout;
4. gate central aplicado por `require_current_user_permission` a todas as action keys.

Nao havera `if modulo ativo` copiado em cada Server Action. Toda action key passa a declarar `runtime_module_key` e `runtime_access_kind` no catalogo de permissoes.

## Ambientes

Valores permitidos:

- `unconfigured`: estado inicial seguro; somente `core` e `seguranca` ficam acessiveis;
- `development`: desenvolvimento local;
- `test`: banco descartavel ou oficial de testes;
- `staging`: homologacao de negocio;
- `production`: banco operacional.

Um banco novo nasce como `unconfigured`. A variavel `ELITE_DATABASE_MODE` continua sendo um aviso visual, mas nao libera escrita. A mudanca do ambiente autoritativo ocorre por RPC auditada e exige `system.admin`.

## Estagios do modulo

- `construction`
- `technical_validation`
- `business_validation`
- `pilot`
- `operational`
- `suspended`

Modos de acesso:

- `disabled`
- `read_only`
- `read_write`

Regras:

- desenvolvimento e teste podem exercitar modulos em validacao tecnica;
- homologacao exige ao menos `business_validation` para escrita;
- producao exige `operational` para escrita;
- `suspended` nunca permite acesso;
- `core` nao pode ser desligado;
- dependencia obrigatoria insuficiente bloqueia o modulo dependente, mesmo que ele esteja configurado como ativo;
- desligar uma dependencia em emergencia e permitido e bloqueia automaticamente os dependentes.

## Historico imutavel

`sys_runtime_environment_events` e `sys_module_rollout_events` sao append-only. O estado atual e uma view derivada do ultimo evento. Correcao gera evento novo; nao edita o anterior.

Toda mudanca administrativa tambem entra em `action_logs`, com autor, motivo, antes, depois e action key.

## Rotas e falha segura

Rotas operacionais precisam existir em `sys_module_routes`. Rota autenticada sem registro e negada por padrao. A tela de indisponibilidade explica o bloqueio sem expor dados internos.

Rotas de bootstrap:

- `/`
- `/modulos`
- `/modulo-indisponivel`
- `/seguranca`
- `/login/trocar-senha`

As rotas publicas permanecem limitadas a login, assets e health-check.

## Linha de base da migration

- `core` e `seguranca`: operacionais em todos os ambientes;
- demais modulos existentes: escrita habilitada apenas em `development` e `test`, com estagio `technical_validation`;
- `staging` e `production`: desabilitados ate promocao auditada;
- ambiente corrente: `unconfigured`.

Essa configuracao prepara a operacao gradual sem declarar que telas ainda nao homologadas estao prontas para producao.

## Processo de promocao

1. migrations e testes passam no CI;
2. modulo opera no banco de teste;
3. reconciliacoes e cenarios de negocio sao conferidos;
4. modulo passa para `business_validation` em homologacao;
5. piloto controlado e executado;
6. somente depois o modulo recebe `operational` e `read_write` em producao.

Cada promocao exige motivo e deixa evento imutavel.

## Limite desta etapa

Este gate controla liberacao, dependencia e acesso. Ele nao substitui a extracao das APIs internas de estoque, fiscal e metas definida em `matriz_propriedade_modulos.md`; essa extracao continua sendo o proximo trabalho de reducao de acoplamento interno.
