# Politica de backup no GitHub

## Decisao

O Elite System deve ter backup no GitHub, mas o Git nao deve receber dados reais. Mesmo em repositorio privado, o versionamento fica restrito a codigo, testes, schemas e documentacao tecnica sem historico comercial.

## O que entra no Git

- Codigo-fonte.
- Documentacao tecnica sem valores reais.
- Planos de construcao.
- Schemas de banco.
- Scripts de migracao.
- Testes automatizados.
- Workflows de CI.

## O que nao entra no Git

- Workbooks Excel.
- Bancos SQLite gerados em `data/`.
- Extracoes JSON, CSV, TSV, parquet ou dumps.
- Relatorios de auditoria com valores reais.
- Prints, anexos e backups com clientes, pedidos, estoque, producao ou faturamento.
- Credenciais.
- Tokens.
- Senhas.

## Fluxo de backup

1. Trabalhar em commits pequenos.
2. Rodar testes locais.
3. Commitar com mensagem clara.
4. Conferir `git status --short --ignored`.
5. Fazer push somente do repositorio de codigo.
6. Manter dados reais em backup local separado.
7. Usar tags para marcos:
   - `migration-audit-v1`
   - `cadastros-v1`
   - `comercial-v1`
   - `estoque-v1`
   - `producao-v1`
8. Manter branch principal sempre executavel.

## CI minimo

O GitHub Actions deve rodar:

```powershell
python -m unittest discover -s tests -v
```

## Regra de seguranca

Nunca fazer push de dados reais. Se um arquivo de dados entrar no historico local por engano, recriar o historico antes de qualquer push.

## Status atual

- Git local reinicializado em `04-sistema`, separado das pastas locais com planilha e extracoes.
- `data/` e `outputs/` estao ignorados.
- A politica vigente e codigo no Git; dados reais ficam fora.
