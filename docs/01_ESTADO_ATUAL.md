# Elite System - estado atual

Atualizado em: 2026-07-22

## Referência vigente

- branch de desenvolvimento: `feature/0044-production-module-release`;
- commit publicado e aprovado pela CI: `6802d62`;
- Supabase de homologação: ledger confirmado de `0001` a `0090`;
- frontend estável: `https://elite-system-staging.vercel.app`;
- release ainda servido pelo domínio estável: `0dd79bd`;
- Preview Vercel de `6802d62`: compilado com sucesso no projeto privado
  `elite-system-staging`, aguardando promoção autenticada;
- produção real e `main`: não alteradas;
- PWA: adiada.

## Estado técnico comprovado

O pipeline integral do commit `6802d62` está aprovado:

- ESLint e build Next.js;
- testes Python;
- reconstrução PostgreSQL limpa com todas as migrations;
- lint do schema e geração do contrato TypeScript;
- smokes de arquitetura, rollout e administrador inicial;
- cadeia industrial integrada;
- cadeia comercial integrada;
- importação histórica de matérias-primas;
- catálogos técnicos, embalagens e logística;
- contratos históricos DEC-006 a DEC-011;
- Romaneio, leitura RLS e fronteiras administrativas de Segurança.

As migrations abaixo foram aplicadas no Supabase de staging somente após
dry-run que listou exclusivamente essas quatro:

- `0087_packaging_single_pa_lot.sql`;
- `0088_order_commission_assignment.sql`;
- `0089_pcp_guarantee_per_liter_units.sql`;
- `0090_restore_historical_mp_audited_rpc_access.sql`.

Após a aplicação, o ledger remoto confirmou `0090`, `/api/health` respondeu
`status=ok` com `backendConfigured=true` e `/login` respondeu HTTP 200.

## Fluxos funcionais disponíveis

### Cadastros

- Clientes e ficha relacional completa;
- Pessoas e vínculos comerciais;
- Matérias-primas e tipos de insumo;
- Produtos, apresentações e embalagens;
- catálogos técnicos, unidades, garantias e logística;
- governança PT-BR e manuais contextuais.

### Produção e estoque

- fórmula operacional com base por litro;
- garantias documentais e cálculo físico por lote consumido;
- OP, reserva FIFO, início, CQ e finalização;
- um produto e um lote PI por OP;
- OP MAPA documental e Ordem de Envase;
- um lote PA por envase/apresentação;
- custo por camada de entrada de MP;
- perda de processo separada de perda de estoque;
- custo PI por MP e custo PA por PI mais embalagens;
- relatórios com filtro MP, PI e PA.

### Comercial, expedição e financeiro

- pedidos de Venda, Bonificação, Mostruário e Troca;
- todo pedido nasce bloqueado e depende de decisão superior;
- PDF liberado somente após aprovação, em A4 paisagem;
- totais de litros, volumes e peso bruto derivados;
- comissionados flexíveis por pedido: vendedor, agente, gerente ou outro;
- bonificação e mostruário sem comissão;
- recebimento, liberação proporcional, pagamento e ajuste de comissão;
- Romaneio por pedido, item, quantidade parcial, lote e embalagem;
- reserva sem baixa física e baixa consolidada pela informação fiscal.

### Importação histórica

- análise e homologação das fontes sem escrita;
- staging e mapeamento de MP auditados;
- custos de aquisição com mercadoria, frete, DIFAL e despesas separados;
- rastreabilidade por workbook, tabela e linha;
- aplicação integral do workbook continua condicionada à homologação das fontes
  e ao corte físico de abertura.

## Segurança vigente

- contas individuais e escrita sensível por RPC auditada;
- RLS e menor privilégio;
- escrita direta revogada;
- fatos históricos append-only;
- `anon` e `PUBLIC` sem execução das RPCs operacionais;
- convite, recuperação de senha e troca administrativa de e-mail governados;
- assinatura institucional `by ☧ SYSTEMS` preservada.

## Decisões ainda bloqueantes

- `DEC-002`: MFA TOTP e exigência de AAL2;
- `DEC-003`: autoaprovação de troca de e-mail do único administrador;
- `DEC-004`: política Auth de produção, SMTP corporativo e CAPTCHA;
- `DEC-012`: corte e inventário físico de abertura.

Essas decisões não bloqueiam desenvolvimento e homologação no staging, mas
bloqueiam entrada segura em produção real ou ativação de saldos oficiais.

## Próxima ação

1. Promover o Preview `6802d62` para o domínio estável de staging usando sessão
   autenticada da Vercel.
2. Executar smoke autenticado de Produção, Pedidos, comissões e importação.
3. Corrigir somente lacunas objetivas encontradas no staging.
4. Preparar o corte físico `DEC-012` antes de ativar saldos reais.

Não reaplicar migrations, não resetar banco e não alterar produção real.
