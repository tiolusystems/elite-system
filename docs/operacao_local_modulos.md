# Operacao local dos modulos

Data: 2026-07-10

## Objetivo

Permitir validacao progressiva dos modulos em um banco local identificado como teste, enquanto outros modulos continuam em construcao. Este procedimento nao e producao e nao substitui Supabase cloud de homologacao.

## Controles

- migrations aplicadas pelo Supabase local;
- ambiente do banco nasce `unconfigured`;
- primeiro administrador criado uma unica vez por `service_role`;
- nenhuma chave, senha, banco ou dado de teste entra no Git;
- `.env.local`, logs e PIDs ficam em caminhos ignorados;
- modulo incompleto continua bloqueado pelo gate central da migration `0041`;
- toda promocao de ambiente ou modulo gera evento append-only e `action_logs`.

## Iniciar

Na raiz do repositorio:

```powershell
.\iniciar-elite-local.cmd
```

O script:

1. inicia o Docker Desktop se necessario;
2. inicia o Supabase local e aplica migrations;
3. gera `apps/web/.env.local` com chaves locais, sem versiona-las;
4. inicia Next.js em `http://127.0.0.1:3000`;
5. so termina com sucesso quando `/api/health` responde.

## Primeiro administrador

Executar apenas uma vez no banco novo:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\bootstrap-local-admin.ps1 -Email "admin@elite.local" -DisplayName "Administrador Elite"
```

O script gera uma senha temporaria forte, cria o usuario no Auth local e chama `bootstrap_first_system_admin`. A RPC:

- aceita somente JWT `service_role`;
- verifica a ausencia de qualquer perfil humano;
- usa lock transacional contra duas inicializacoes concorrentes;
- cria perfil `admin`, ativo e nao-sistema;
- grava auditoria sem email e sem credencial;
- fecha definitivamente o bootstrap depois do primeiro perfil humano.

A senha aparece uma unica vez no terminal local. O primeiro login exige troca.

## Abrir modulos para teste

1. entrar em `http://127.0.0.1:3000/login`;
2. trocar a senha temporaria;
3. abrir `/modulos`;
4. mudar o ambiente autoritativo de `unconfigured` para `test` com motivo `test_reset`;
5. validar os modulos na ordem documentada em `operacao_gradual_modulos.md`.

Em `test`, a linha de base permite exercitar os modulos codificados, ainda marcados como `technical_validation`. Isso nao os promove para homologacao ou producao.

## Parar

Parar somente o Next.js, preservando o Supabase ativo:

```powershell
.\parar-elite-local.cmd
```

Parar tambem o Supabase, preservando o fluxo normal de backup local da CLI:

```powershell
.\parar-elite-local.cmd -StopSupabase
```

O script nunca usa `--no-backup`.

## Limite para varias maquinas

Este banco local serve para validacao nesta maquina. Operacao simultanea em quatro maquinas exige um projeto Supabase cloud de teste/homologacao e o frontend publicado na Vercel. As mesmas migrations e o mesmo gate de modulos serao usados; chaves cloud nao devem ser copiadas para documentos ou commits.

## Decisoes pendentes para Luciano

Estas decisoes nao bloqueiam os testes locais, mas devem ser confirmadas antes do piloto cloud:

1. email e nome do primeiro administrador humano de homologacao;
2. provedor/webhook que enviara senhas temporarias por email;
3. primeiro modulo de negocio promovido para `business_validation` (recomendacao tecnica: `cadastros` antes de `pedidos`);
4. retencao de backup e frequencia do teste de restore no Supabase cloud;
5. pessoas que assinam a homologacao funcional de cada modulo.
