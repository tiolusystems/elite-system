# Decisao de stack web e cloud

Data da decisao: 2026-07-03

## Decisao

O Elite System sera construido como aplicacao web cloud-first:

- Banco principal: PostgreSQL.
- Backend inicial: Supabase.
- Frontend: Next.js com App Router e TypeScript.
- Deploy do frontend: Vercel.
- Deploy do banco/backend: Supabase.

O codigo Python atual continua como nucleo de migracao, auditoria, reconciliacao e ferramentas internas. Ele nao sera descartado. A funcao dele e proteger o historico importado do Excel e validar o que entra no PostgreSQL.

## Justificativa

Supabase reduz complexidade inicial porque entrega PostgreSQL, autenticacao, politicas de acesso, storage e APIs geradas sobre o banco. Isso permite avancar no software operacional sem criar, neste momento, uma camada completa de backend do zero.

FastAPI com Uvicorn e ORM fica reservado para quando houver necessidade real de servicos proprios:

- regra de negocio complexa demais para ficar em SQL, triggers ou server actions;
- integracoes externas;
- rotinas longas de importacao;
- processamento assicrono;
- auditorias pesadas;
- isolamento maior entre app e banco.

Aplicativo desktop em C# com Avalonia fica fora da primeira entrega. Ele pode ser avaliado depois, se houver necessidade de operacao offline, integracao local forte ou uma experiencia desktop nativa.

## Arquitetura definida

```text
Usuario
  -> Next.js / Vercel
  -> Supabase Auth
  -> Supabase PostgreSQL
  -> Tabelas operacionais, permissoes e action_logs

Python interno
  -> importacao Excel
  -> reconciliacao
  -> auditoria
  -> carga controlada para PostgreSQL
```

## Regras obrigatorias

- Nenhum dado real no Git.
- Segredos ficam em `.env.local`, Vercel ou Supabase, nunca versionados.
- Toda tela deve exibir a condicao do banco quando estiver em ambiente local, teste ou homologacao.
- Toda acao operacional relevante deve gravar auditoria.
- O historico bruto importado do Excel continua preservado.
- Antes de migrar dados reais para Supabase, rodar teste em projeto/banco descartavel.

## Pastas

```text
apps/web/              # Next.js
supabase/migrations/   # migrations PostgreSQL/Supabase
elite_system/          # nucleo Python de migracao e auditoria
docs/                  # decisoes, arquitetura e evidencias
```

## Proxima sequencia tecnica

1. Criar projeto Supabase de teste.
2. Rodar migrations iniciais em banco descartavel.
3. Ligar Next.js ao Supabase com variaveis de ambiente.
4. Recriar tela de login e alcadas no Next.js.
5. Migrar cadastros mestres para PostgreSQL.
6. Validar importacao historica contra o PostgreSQL.
