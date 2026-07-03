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
- `/pedidos`: primeira tela operacional de pedidos, com rascunho auditavel, item vendavel, comissao prevista, decisao de credito, recebimento parcial e liberacao proporcional de comissao.
- A tela mostra a condicao visual/analitica do banco conforme `ELITE_DATABASE_MODE`.
- Quando Supabase estiver configurado, a tela tenta carregar contagens das tabelas `cad_*` e alertas pendentes de `cadastro_validation_issues`.
- Preview sem Node.js: abra `apps/web/preview/cadastros.html` diretamente no navegador.
- Preview de pedidos sem Node.js: abra `apps/web/preview/pedidos.html` diretamente no navegador.
- Os formularios de cliente, pessoa comercial, materia-prima, produto-base, embalagem, item vendavel e conversao de MP usam Server Actions e funcoes PostgreSQL auditaveis; nao gravar diretamente em tabelas `cad_*` pela UI.
- Vendedores responsaveis, MPs, produtos e embalagens usam seletores pesquisaveis com ID embutido para reduzir erro de digitacao em vinculos.
- As telas usam CSS responsivo para acesso em desktop, notebook, tablet e celular pelo navegador.

## Regra de seguranca

Nao versionar `.env.local`, chaves, dumps, bancos ou dados comerciais. A tela inicial mostra a condicao do banco para evitar confundir local, teste, homologacao e producao.
