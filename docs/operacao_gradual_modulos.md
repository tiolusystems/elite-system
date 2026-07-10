# Operacao gradual dos modulos

Data: 2026-07-10

## Objetivo

Colocar modulos tecnicamente prontos em teste e homologacao enquanto outros continuam em construcao, sem liberar acidentalmente uma rotina incompleta no banco operacional.

## Pre-requisitos

1. migrations `0001` a `0041` aplicadas no projeto Supabase de teste;
2. usuario Supabase Auth com `user_profiles.status = 'active'`;
3. administrador com `system.admin`;
4. variaveis server-side e publicas configuradas no Next.js;
5. banco de teste separado do futuro banco operacional.

## Primeira inicializacao

O procedimento repetivel para subir Supabase, gerar o ambiente local ignorado pelo Git e criar o primeiro administrador esta em `operacao_local_modulos.md`.

Um banco novo nasce em `unconfigured`. Nesse estado:

- login, troca de senha, seguranca, inicio e `/modulos` continuam acessiveis;
- cadastros, pedidos, PCP, estoque, romaneio e demais modulos ficam bloqueados;
- nenhuma variavel do frontend consegue contornar o bloqueio.

Procedimento:

1. entrar com usuario administrador;
2. abrir `/modulos`;
3. conferir se `ELITE_DATABASE_MODE` e o ambiente declarado pelo banco coincidem;
4. selecionar `Teste` como ambiente autoritativo;
5. registrar motivo `Configuracao inicial`;
6. abrir os modulos para cenarios com dados de teste.

A linha de base de `test` permite escrita nos modulos ja codificados, todos ainda identificados como `technical_validation`. Isso permite testar fluxos completos sem declarar producao pronta.

## Ordem recomendada de homologacao

1. `seguranca`
2. `cadastros`
3. `pedidos`
4. `estoque`
5. `pcp`
6. `expedicao`
7. `importacao`
8. `faturamento`
9. `financeiro`
10. `metas`
11. `relatorios` e `auditoria`

O banco valida dependencias. Por exemplo, PCP nao pode receber escrita em homologacao se estoque estiver bloqueado; romaneio depende de pedidos e estoque.

## Preparar ambiente futuro sem troca-lo

Na tela `/modulos`, o seletor `Visualizar` permite abrir `development`, `test`, `staging` ou `production` sem mudar o ambiente ativo.

Isso permite preparar homologacao e producao com antecedencia. A troca do ambiente autoritativo e uma acao separada e auditada.

## Promocao

### Homologacao

Para `read_write` em `staging`, o modulo precisa estar em:

- `business_validation`;
- `pilot`; ou
- `operational`.

Ativar primeiro as dependencias obrigatorias, depois o modulo dependente.

### Producao

Para `read_write` em `production`, o modulo precisa estar em `operational`. O sistema rejeita `technical_validation` e `business_validation` com escrita em producao.

Promocao minima:

1. testes e CI verdes;
2. reconciliacao aplicavel aprovada;
3. cenarios de negocio assinados na homologacao;
4. backup e restore do Supabase testados;
5. motivo `Liberacao de producao` registrado;
6. ambiente ativo alterado somente depois da conferencia.

## Somente leitura

`read_only` libera consulta, mas bloqueia action keys classificadas como escrita. O bloqueio ocorre em `require_current_user_permission`, dentro do banco, e nao depende de botao desabilitado no navegador.

## Incidente e rollback

Em incidente:

1. abrir `/modulos`;
2. registrar `suspended` + `disabled` com motivo `Incidente`;
3. dependentes sao bloqueados automaticamente;
4. preservar eventos e logs para investigacao;
5. corrigir por migration ou codigo versionado;
6. registrar novo evento de restauracao; nunca editar o evento anterior.

Desligar uma dependencia e permitido para resposta rapida. O acesso efetivo dos dependentes cai para bloqueado mesmo que a configuracao anterior deles fosse `read_write`.

## O que ja pode acontecer em paralelo

- time de negocio testa cadastros no banco de teste;
- desenvolvimento continua pedidos, PCP ou relatorios;
- um modulo incompleto permanece bloqueado em homologacao/producao;
- migrations continuam unicas e ordenadas;
- cada action key nova precisa declarar modulo proprietario e natureza `read` ou `write`.

## O que ainda impede operacao real

- projeto Supabase cloud de teste ainda precisa receber as migrations;
- login e telas precisam de homologacao com usuarios reais de teste;
- backup e restore cloud precisam ser exercitados;
- modulos precisam de validacao de negocio antes de `operational`;
- dados historicos so entram pelo projeto especifico de importacao e reconciliacao.

Esta etapa prepara operacao incremental; nao autoriza usar banco de producao antes desses controles.
