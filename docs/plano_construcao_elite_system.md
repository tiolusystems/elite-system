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

Status atual:

- Dicionario inicial de cadastros criado em `docs/dicionario_cadastros_mestres.md`.
- Dicionario evoluido para incluir papeis de vendedor/agente/tecnico/entregador, multiplos comissionados por pedido, cliente unico com propriedades/CNPJs, saneamento de SKU de MP, conversoes XML/NF, produto + embalagem, PA/PI, formulas versionadas e garantias MAPA.
- Regras de comissao, recebimento, devolucao, credito e pedido por vendedor documentadas em `docs/escopo_comissoes_recebimentos_credito.md`.
- Modelos de dominio de cadastros criados em `elite_system/domain/cadastros.py`.
- Validators puros de cadastros criados em `elite_system/validators/cadastros.py`.
- Schema SQLite operacional de cadastros criado com tabelas `cad_*`, preservando as tabelas historicas importadas do Excel.
- Migration Supabase/PostgreSQL de cadastros criada em `supabase/migrations/0002_master_data_foundation.sql`.
- Repositories e services auditaveis de cadastros criados em `elite_system/repositories/cadastros_repository.py` e `elite_system/services/cadastros.py`.
- Testes de cadastros preparados para rodar em banco temporario descartavel.
- Primeira tela de cadastros mestres criada em `apps/web/app/cadastros/page.tsx`, com condicao visual/analitica do banco, modulos `cad_*`, contagens Supabase quando configurado e fila de validacao.
- Pendencia: validar migrations em runtime Python/PostgreSQL disponivel antes de usar em qualquer dado real.

## Bloco 3 - Comercial

Objetivo: substituir `GESTÃO_PEDIDOS` por modulo operacional.

Entregas:

- Pedido.
- Itens do pedido.
- Tipo: venda, bonificacao, devolucao.
- Status de entrega.
- Vendedores e comissoes.
- Faturamento.
- Lancamento de recebimentos.
- Calculo de comissoes por recebimento.
- Pedido preenchido por vendedor com alcadas.
- Analise de credito e inadimplencia no pedido.

Auditorias:

- Total de pedidos.
- Faturamento total.
- Faturamento vendas.
- Pedidos em aberto.
- Entregue x a entregar.
- Comissao prevista x liberada x paga.
- Devolucao abatendo comissao.
- Comissao negativa compensada em futuras.
- Pedido bloqueado por credito/inadimplencia.

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

## Bloco 6 - Romaneio

Objetivo: substituir a planilha `ROMANEIO` canonica por fluxo operacional, sem transformar outras planilhas com nome parecido em codigo desnecessario.

Entregas:

- Escolha de pedido a separar.
- Separacao total ou parcial.
- Busca de lotes disponiveis de PA.
- Reserva de lote quando aplicavel.
- Confirmacao de romaneio.
- Baixa de PA gerada por romaneio confirmado.
- Comunicacao do romaneio para faturamento.
- Comunicacao do romaneio para expedicao.

Auditorias:

- Pedido x romaneio x saida PA.
- Lote x produto.
- Quantidade romaneada.
- Quantidade pendente por pedido.
- Baixa de estoque PA por romaneio confirmado.

Fora do escopo inicial:

- montagem completa de carga;
- roteirizacao;
- frota;
- fiscal completo;
- outras planilhas chamadas romaneio sem mapeamento aprovado.

Status atual:

- Modelos de dominio do romaneio criados em `elite_system/domain/romaneio.py`.
- Servico puro de romaneio criado em `elite_system/services/romaneio.py`.
- Fluxos cobertos por teste: separacao parcial, reserva, cancelamento, confirmacao com baixa de PA e estorno.

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
2. Revisar e aprovar `docs/dicionario_cadastros_mestres.md` v0.3.
3. Validar migrations de cadastros em banco descartavel/local quando houver runtime Python disponivel.
4. Criar projeto Supabase de teste e aplicar migrations de seguranca/cadastros.
5. Instalar dependencias do `apps/web` e validar Next.js local.
6. Ligar login Supabase no Next.js.
7. Ativar gravacao segura dos formularios de cadastros mestres.
8. Classificar causas das diferencas de reconciliacao.
