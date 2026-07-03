# Plano de construcao do Elite System

## Bloco 0 - Governanca, GitHub e seguranca

Objetivo: garantir que cada evolucao tenha backup e rastro.

Entregas:

- Repositorio Git local.
- Repositorio GitHub privado.
- Branch principal protegida.
- Commits pequenos por bloco.
- CI rodando testes em cada push.
- Regra: nao publicar dados comerciais no Git.

Status atual:

- Repositorio local sera inicializado nesta etapa.
- Workflow de CI sera criado em `.github/workflows/ci.yml`.

## Bloco 1 - Nucleo de migracao e auditoria

Objetivo: preservar historico do Excel e validar importacao.

Entregas:

- Camada bruta: workbook, tabelas e linhas originais.
- Camada normalizada inicial.
- Issues de migracao.
- Reconciliacoes de valores.

Status atual:

- Importador Excel implementado.
- Auditoria de contagem implementada.
- Auditoria de valores implementada.
- Auditoria de saldo por materia-prima e produto implementada em tabela de detalhes.
- Tabelas de usuarios, login por senha e log de acoes implementadas.
- Permissoes implementadas com autonomia total inicial e overrides por perfil/usuario.
- Tela administrativa local de usuarios/alcadas implementada com login, checks e aviso visual/analitico de banco local ou descartavel.
- Etapa 2 validada em banco descartavel, com evidencia em `docs/validacao_etapa_2_checks_db_descartavel.md`.
- Stack web/cloud definida: PostgreSQL, Supabase, Next.js e Vercel.
- Base inicial Next.js criada em `apps/web`.
- Migration inicial Supabase criada em `supabase/migrations`.
- Pendencia conhecida: classificar automaticamente a causa de cada diferenca.

## Bloco 2 - Cadastros mestres

Objetivo: transformar cadastros em telas e regras confiaveis.

Entregas:

- Clientes.
- Vendedores.
- Materias-primas.
- Produtos.
- Veiculos.
- Embalagens.
- Garantias.
- Validacoes de duplicidade, status e campos obrigatorios.

Auditorias:

- Contagem por cadastro.
- Duplicidade de codigos.
- Itens usados em pedidos/producao sem cadastro.

## Bloco 3 - Comercial

Objetivo: substituir `GESTÃO_PEDIDOS` por modulo operacional.

Entregas:

- Pedido.
- Itens do pedido.
- Tipo: venda, bonificacao, devolucao.
- Status de entrega.
- Vendedores e comissoes.
- Faturamento.

Auditorias:

- Total de pedidos.
- Faturamento total.
- Faturamento vendas.
- Pedidos em aberto.
- Entregue x a entregar.

## Bloco 4 - Estoque MP e PA

Objetivo: fechar saldos e movimentos.

Entregas:

- Entradas MP.
- Saidas MP.
- Saidas PA.
- Lotes MP.
- Lotes PA.
- Inventario.
- Ajustes manuais auditados.

Auditorias:

- Saldo MP por materia-prima.
- Saldo PA por produto.
- Saldo por lote.
- Diferencas de inventario.

## Bloco 5 - Producao

Objetivo: transformar fichas e lotes em processo de producao.

Entregas:

- Ficha tecnica.
- Formula por produto.
- Ordem de producao.
- Baixa automatica de MP.
- Custo de producao.
- Simulacao de producao e compras.

Auditorias:

- Quantidade produzida.
- Custo MP.
- Consumo teorico x consumo baixado.
- Produtos sem formula valida.

## Bloco 6 - Expedicao e romaneio

Objetivo: substituir romaneio Excel por fluxo operacional.

Entregas:

- Montagem de carga.
- Romaneio.
- Lotes por entrega.
- Peso liquido, peso bruto, volumes e m3.
- Veiculo e entregador.

Auditorias:

- Pedido x saida PA.
- Lote x produto.
- Quantidade embarcada.

## Bloco 7 - Relatorios e dashboards

Objetivo: recriar analises do Excel com consultas rastreaveis.

Entregas:

- Dashboard comercial.
- Dashboard estoque.
- Dashboard producao.
- Ranking de clientes.
- Relatorio de pedidos pendentes.
- Relatorio de compras/necessidade MP.

## Bloco 8 - Banco em nuvem

Objetivo: sair de SQLite local para PostgreSQL/Supabase sem perder auditoria.

Entregas:

- Projeto Supabase de teste.
- Schema PostgreSQL em migrations versionadas.
- Supabase Auth ligado aos perfis do sistema.
- Row Level Security revisado por tabela.
- Migração de dados.
- Backup automatizado.
- Credenciais por ambiente.
- Restore testado.
- Login multiusuario validado contra ambiente cloud.
- `action_logs` protegido por permissao e backup.

## Bloco 9 - App operacional

Objetivo: entregar o sistema para uso diario.

Entregas:

- App web Next.js.
- Deploy Vercel.
- Integracao Supabase.
- Login e perfis.
- Telas completas.
- Empacotamento inicial via Edge app mode.
- Manual operacional.
- Homologacao visual e funcional.

## Sequencia imediata

1. Configurar GitHub privado somente com codigo.
2. Criar projeto Supabase de teste e aplicar migration inicial.
3. Instalar dependencias do `apps/web` e validar Next.js local.
4. Ligar login Supabase no Next.js.
5. Classificar causas das diferencas de reconciliacao.
6. Criar modelos de dominio para cadastros.
7. Criar repositories para cadastros com `actor_user_id`.
8. Criar primeira tela de cadastros mestres.
