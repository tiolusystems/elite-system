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

## Regra de seguranca

Nao versionar `.env.local`, chaves, dumps, bancos ou dados comerciais. A tela inicial mostra a condicao do banco para evitar confundir local, teste, homologacao e producao.
