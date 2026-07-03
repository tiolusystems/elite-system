# Elite System Web

Aplicacao Next.js do Elite System.

## Stack

- Next.js com App Router e TypeScript.
- Supabase como backend inicial.
- PostgreSQL como banco de producao.
- Vercel como deploy do frontend.

## Configuracao local

Copie `.env.example` para `.env.local` e configure as variaveis do projeto Supabase.

```powershell
npm install
npm run dev
```

Abra `http://localhost:3000`.

## Telas

- `/` e `/cadastros`: tela operacional de cadastros mestres.
- A tela mostra a condicao visual/analitica do banco conforme `ELITE_DATABASE_MODE`.
- Quando Supabase estiver configurado, a tela tenta carregar contagens das tabelas `cad_*` e alertas pendentes de `cadastro_validation_issues`.

## Regra de seguranca

Nao versionar `.env.local`, chaves, dumps, bancos ou dados comerciais. A tela inicial mostra a condicao do banco para evitar confundir local, teste, homologacao e producao.
