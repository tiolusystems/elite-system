# Validacao - mapa arquitetural e linha de trabalho

Data: 2026-07-11

## Escopo

- fonte de orientacao em `docs/arquitetura/ARQUITETURA_GERAL.md`;
- contrato de execucao em `AGENTS.md`;
- catalogo executavel em `apps/web/lib/system-map.ts`;
- mapa visual e fluxos na tela `/modulos`;
- progresso da home derivado da maturidade registrada no PostgreSQL;
- teste contra divergencia entre documentacao, catalogo web e `sys_modules`.

## Resultado

- teste direcionado `test_architecture_navigation_contract.py`: 5 testes OK;
- suite Python completa: 215 testes OK;
- ESLint dos arquivos TypeScript alterados: OK;
- ESLint web completo: OK;
- build Next.js com TypeScript: OK;
- health-check local: `status=ok`, backend configurado;
- ambiente autoritativo consultado no PostgreSQL: `test`;
- `core` e `seguranca`: `operational/read_write`;
- `cadastros`, `estoque` e `pcp`: `business_validation/read_write`;
- demais modulos: `technical_validation/read_write` no ambiente de teste.

## Validacao visual

A rota `/modulos` foi solicitada no navegador local. O guard redirecionou corretamente para `/login/trocar-senha?next=%2Fmodulos`, pois o administrador ainda precisa concluir a troca obrigatoria de senha.

O controle de seguranca nao foi contornado e o perfil nao foi alterado apenas para obter captura. A inspecao visual autenticada em desktop e mobile deve ocorrer depois da troca de senha, sem exigir alteracao adicional de codigo.

## Validacoes deliberadamente nao repetidas

Nao houve migration SQL neste bloco. Por isso, reset completo do Supabase, lint PostgreSQL e smokes de banco nao foram repetidos localmente. O CI continua executando esses gates no push e deve ser a evidencia final do commit.

## Contratos fixados

1. Tarefa local comeca pelo mapa, nao por inventario completo.
2. Leitura amplia apenas pelas dependencias declaradas.
3. Comando nao se repete sem mudanca de entrada, codigo, banco, ambiente ou gate final.
4. Percentual visual arbitrario nao representa progresso.
5. Maturidade vem dos ledgers do PostgreSQL e usa estados objetivos.
6. Mudanca estrutural atualiza catalogo web, mapa humano e teste de sincronismo.
