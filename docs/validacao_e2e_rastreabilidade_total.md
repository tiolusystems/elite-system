# Validacao E2E-01 + TRACE-01

## Atualizacao da revisao integral em 2026-07-25

- baseline funcional recuperado: `4a47ca4`;
- correcoes publicadas para a revisao transversal: `c860d49` e `28ef700`;
- CI do `28ef700`: `30139897844`, com `python-tests`, `web-contract` e
  `database-contract` aprovados;
- as correcoes retiram IDs tecnicos da consulta de rastreabilidade e deixam
  valores ausentes como “Nao informado”, sem converter ausencia em zero;
- o fallback de situacao de lote agora e “Situacao nao reconhecida”, sem
  expor enum desconhecido;
- manuais de Garantias, CQ, Envase, Estoque, Transformacoes e Rastreabilidade
  foram ampliados em PT-BR;
- nenhuma migration, RPC, view, RLS, banco ou dado operacional foi alterado
  neste bloco;
- o deployment estavel ainda e `dpl_G8XBztHpeaRjYzPSYVpcYYSLAZR4`, baseado no
  `9e56e15`; nao foi substituido porque nao ha deployment Vercel criado para
  `28ef700` nesta sessao;
- a revisao integral permanece **APROVADA COM RESSALVAS**: os contratos SQL e
  smokes descartaveis anteriores estao aprovados, mas a cadeia completa ainda
  precisa percorrer toda a interface real e o novo frontend precisa ser
  publicado no projeto `elite-system-staging`.

## Identificacao

- `run_id`: `E2E-01-TRACE-01-20260724`;
- data: 2026-07-24;
- ambientes executados: `elite-validation-*` descartaveis e staging, sem dados
  reais;
- branch: `work/ux-clients-macrociclo`;
- HEAD de partida: `490480904d2f19263811e4443a0f571ac2fc3817`;
- HEAD validado e publicado: `1f9200a40be98e8234985b00e9a147c03e1f1d3d`;
- branch remota: `origin/feature/0044-production-module-release`;
- ledger de staging observado antes do bloco: `0001` a `0104`;
- ledger de staging depois do bloco: `0001` a `0106`;
- Preview Vercel correto:
  `elite-system-staging-a95dewtgy-luciano21.vercel.app`;
- dominio estavel preservado: `elite-system-staging.vercel.app`.

## Resultado executivo

**APROVADO COM RESSALVAS.**

Instalacao limpa, upgrades dirigidos, quatro cadeias SQL, Playwright em cinco
resolucoes, CI e aplicacao unitaria no staging foram comprovados. A cadeia
industrial e comercial fechou no PostgreSQL descartavel, com rastreabilidade e
conciliacao derivadas dos fatos operacionais.

A ressalva permanece porque o navegador ainda nao executa toda a cadeia
industrial, fiscal externa, financeira e de comissoes. O Playwright atravessa
a fronteira real da aplicacao para cadastro e primeira entrada valorizada de
MP, alem de validar rotas, shell, manuais e separacao de alcadas. As demais
etapas foram comprovadas pelas RPCs reais no PostgreSQL descartavel.

As migrations `0105` e `0106` foram aplicadas separadamente no staging depois
da CI verde. Os smokes remotos usaram transacao, dados sinteticos e rollback.
Nenhum dado real foi lido, criado ou alterado.

## Contratos implementados no candidato local

### Entrada operacional de estoque

A migration candidata `0105_operational_stock_entry_external_fiscal_refs.sql`:

- cria entrada de MP idempotente com lote, movimento fisico e camada de custo
  na mesma transacao;
- exige separadamente `estoque.mp.lots.create` e
  `estoque.mp.acquisition_value.register`;
- registra mercadoria, frete, DIFAL, outras despesas, documento e lote do
  fornecedor;
- rejeita payload diferente com a mesma chave;
- mantem escrita direta revogada.

A tela `/producao/estoque` recebeu o formulario governado para essa operacao.

### Referencias fiscais externas

O Elite nao emite nota fiscal. A migration candidata `0105` e a tela de
Romaneio registram somente:

- numero da NF de simples faturamento no pedido-mae;
- numero da NF de remessa no Romaneio;
- correcao de numero com motivo, valor anterior e valor novo;
- itens operacionais associados ao documento externo.

Registrar a referencia nao movimenta estoque e nao libera comissao. A baixa
fisica continua ocorrendo somente na confirmacao governada do Romaneio.

### Rastreabilidade derivada

A migration candidata `0106_total_lot_traceability.sql` nao cria uma segunda
escrituracao. Ela deriva arestas dos fatos existentes:

`MP/embalagem -> OP -> PI -> Envase -> PA -> Romaneio -> Pedido -> cliente/propriedade`.

Foram adicionados:

- views somente leitura de arestas, lotes, destinos e conciliacao;
- consulta para frente e para tras;
- simulacao de recolhimento sem efeito operacional;
- produto, saldo PA atual e contatos dos destinos impactados;
- exportacao CSV auditada com ambiente, usuario, data, filtros e divergencias;
- permissoes atomicas, bloqueadas por padrao;
- rota canonica `/qualidade/rastreabilidade` e manual contextual.

## Usuarios e alcadas do ensaio reproduzivel

O bootstrap de navegador cria contas sinteticas individuais para:

- Administracao de Seguranca;
- Cadastros;
- vendedor;
- revisao de pedido;
- alteracao individual de limite;
- Estoque;
- Producao;
- CQ;
- Romaneio/Expedicao;
- referencia fiscal externa;
- recebimentos e comissoes.

O runtime descartavel nasce fechado. O bootstrap tecnico cria as identidades no
Auth, materializa perfis e alcadas no PostgreSQL descartavel e chama
`set_system_runtime_environment` com o ator de Seguranca identificado. As
operacoes funcionais seguintes usam sessoes autenticadas pela aplicacao. Nao ha
configuracao direta do ledger operacional.

## Automacao preparada

O workflow manual `Operational E2E and traceability`:

1. cria projeto isolado `elite-validation-e2e-<run_id>`;
2. instala todas as migrations desde zero;
3. executa as cadeias SQL industrial, comercial, referencias externas e
   rastreabilidade;
4. cria Auth e contas sinteticas individuais;
5. inicia Next.js apontando apenas para o Supabase descartavel;
6. executa navegador em cinco resolucoes;
7. publica capturas, videos e traces apenas como artefatos da CI;
8. elimina o ambiente descartavel no encerramento.

O navegador cobre login, shell, rotas canonicas, ausencia de rolagem
horizontal, separacao das alcadas de credito e uma operacao real:

`Cadastros cria MP -> Estoque pesquisa MP -> registra lote, documento e custo`.

Essa automacao foi executada localmente contra Supabase descartavel. Foram
aprovados 15 cenarios de navegador: tres fluxos em cinco resolucoes, sem retry
utilizado.

## Gates realizados

| Gate | Resultado |
| --- | --- |
| `python -m unittest discover -s tests -p "test*.py"` | 608 testes OK |
| ESLint de `app`, `lib`, `e2e` e Playwright | OK |
| TypeScript `--noEmit` | OK |
| Next.js build | OK, 33 paginas geradas |
| `git diff --check` | OK |
| Varredura de arquivos proibidos | OK; somente `.env.example` rastreado |
| Instalacao limpa `0001 -> 0106` | OK em `elite-validation-e2e-20260724-01` |
| Upgrade `0066 -> 0067` | OK em `elite-validation-u67-20260724-01` |
| Upgrade `0104 -> 0105 -> 0106` | OK e unitario em `elite-validation-upgrade-20260724-01` |
| Smokes SQL 0105/industrial/comercial/0106 | OK |
| Playwright full-stack | 15/15 OK em cinco resolucoes |
| CI remota | run `30103390325`: tres jobs OK |
| Aplicacao no staging | `0105` e `0106` aplicadas unitariamente |
| Smoke online | health `ok`, backend configurado e login HTTP 200 |

## Sequencia operacional e reconciliacao

| Etapa | Esperado | Realizado neste run |
| --- | --- | --- |
| Cadastros e entrada MP/embalagem | telas, RPC, RLS e auditoria | Playwright e SQL aprovados |
| Formula, OP, consumo, CQ e PI | cadeia transacional existente | cadeia SQL integrada aprovada |
| Envase, OP MAPA e PA | custo PI + embalagens e genealogia | cadeia SQL integrada aprovada |
| Pedido e credito | pedido bloqueado e alcadas separadas | cadeia comercial e Playwright aprovados |
| Romaneio e referencia externa | parcial, multilote, logistica e baixa unica | cadeia comercial e smoke 0105 aprovados |
| Recebimento e comissao | liberacao proporcional e pagamento idempotente | cadeia comercial aprovada |
| Rastreabilidade e recall | frente, tras, clientes e contatos | smoke 0106 aprovado |
| Conciliacao MP, PI e PA | fatos reconciliaveis e divergencias visiveis | consultas derivadas aprovadas |

Nao existem IDs de entidades persistidas para relatar. Os ambientes
descartaveis foram identificados por `elite-validation-*`; os smokes de staging
terminaram em rollback e confirmaram zero perfis e zero MPs sinteticas
residuais.

## Falhas encontradas e corrigidas localmente

- rota de rastreabilidade nao registrada no rollout modular;
- runtime descartavel nao era configurado por RPC antes do navegador;
- workflow usava opcao inexistente do pnpm;
- teste SQL usava papel de usuario inexistente;
- Romaneio ainda exibia vocabulario de emissao em mensagens antigas;
- recall nao mostrava produto, estoque atual ou contatos;
- CSV nao continha ambiente, usuario, filtros e divergencias.
- campo de senha incluia o botao Mostrar em seu nome acessivel;
- MP sem lote nao aparecia para registrar sua primeira entrada;
- consulta governada de lotes tinha ambiguidade entre colunas de retorno;
- bootstrap E2E tentava ler tabelas endurecidas com `service_role`;
- Playwright antigo travava a descoberta sob Node 24;
- assertions da genealogia confundiam codigo informado com codigo governado do
  lote.

## Pendencias obrigatorias

1. ampliar o Playwright para executar a cadeia industrial e comercial completa
   pela interface, nao apenas a primeira entrada de MP;
2. executar no staging um ensaio `HOM-E2E-*` persistente e neutraliza-lo pelos
   fluxos governados quando a homologacao operacional exigir IDs visiveis;
3. remover a integracao residual do projeto Vercel incorreto `elite-system`,
   cujo status falha sem afetar `elite-system-staging`;
4. manter a PWA bloqueada ate a homologacao.

## Evidencia de preservacao

- `main`: nao alterada;
- producao real: nao alterada;
- staging: somente migrations `0105` e `0106`, aplicadas unitariamente;
- migrations aplicadas: `0105` e `0106`;
- deploy correto: Preview Vercel do commit `1f9200a` concluido;
- dominio estavel: saudavel, sem promocao manual neste bloco;
- dados reais: nenhum;
- integracoes SEFAZ, banco, SMTP ou servicos externos: nenhuma.

## Atualizacao da revisao integral em 2026-07-25

O bloco posterior acrescentou o commit funcional `e7b9599`, que restaura os
filtros de cliente, pedido, romaneio e recolhimento por valores apresentados,
sem expor IDs tecnicos na interface. A resolucao usa as tabelas submetidas a
RLS antes de chamar as RPCs de leitura. Nenhuma migration ou alteracao de banco
foi criada nesta revisao.

O CI do commit `e7b9599` passou no run `30140598039`; o commit documental
`bf6c074` passou no run `30140733341`. O deployment estavel
continua no projeto de staging conhecido, com rollback preservado; o novo
frontend ainda nao foi promovido porque nao ha deployment verificavel do SHA
novo no projeto Vercel correto. A cadeia full-stack completa pelo navegador
continua pendente, assim como a reconciliacao operacional feita a partir da
interface. Portanto, o resultado consolidado permanece **APROVADO COM
RESSALVAS**, sem declarar homologacao visual de Luciano.
