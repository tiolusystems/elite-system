# Elite System - decisoes pendentes

Atualizado em: 2026-07-15

## Regra

Somente decisoes que exigem Luciano ficam aqui. Uma tarefa nao pode alterar a
arvore arquitetonica enquanto sua decisao estiver `pendente`.

Estados permitidos: `pendente`, `autorizada`, `implementada`, `cancelada`.

## Decisoes sob governanca

| ID | Decisao | Recomendacao tecnica | Impacto | Estado |
|---|---|---|---|---|
| `DEC-002` | Fluxo MFA TOTP | QR Code TOTP padrao, compativel com Google Authenticator em Android/iOS, Apple Passwords, Microsoft Authenticator e equivalentes; exigir AAL2 no banco | boundary Auth, login, recuperacao e RPCs criticas | pendente |
| `DEC-003` | Aprovacao da troca de email do proprio administrador | com dois administradores, proibir autoaprovacao; enquanto houver apenas um, exigir MFA e reautenticacao forte | governanca e continuidade administrativa | pendente |
| `DEC-004` | Politica Auth de producao | senha forte, CAPTCHA, sessoes limitadas, SMTP corporativo e confirmacao adequada de email antes da internet | configuracao Supabase cloud e UX de acesso | pendente |
| `DEC-006` | Representacao de formulas e OP historicas do Excel | criar base de rendimento e etapas/fases da formula; usar referencia historica explicitamente desconhecida quando a versao nao puder ser provada; nunca ligar silenciosamente a formula atual; classificar saida PA/PI antes de gerar estoque | PCP, formulas, CQ, lotes e movimentos PA/PI | implementada |
| `DEC-007` | Catalogos tecnicos e especificacoes | normalizar nutrientes por FK, governar unidades/aliases e criar especificacoes versionadas de produto para pH e demais faixas; separar garantia calculada da garantia documental MAPA | cadastros tecnicos, formulas, garantias e CQ | implementada |
| `DEC-008` | Embalagem, composicao e logistica | criar BOM versionada de embalagem, peso, cubagem e vinculo de entregador/veiculo ao romaneio; transformacao historica somente quando comprovada ou marcada como inferida | embalagem, custo, estoque PA/PI, romaneio e expedicao | implementada |
| `DEC-009` | Parcelas e posicao financeira/fiscal legada | criar parcelas normalizadas e eventos/snapshots de abertura para status recebido, comissao paga e referencia de NF incompleta, sem fabricar datas ou recebimentos | pedidos, faturamento, financeiro e comissoes | implementada |
| `DEC-010` | Campanhas, pontos e premiacao | criar campanhas e regras versionadas, ledger append-only de pontos/premios e vouchers; nao misturar premiacao com comissao | comercial, metas, financeiro e auditoria | implementada |
| `DEC-011` | Papeis do vinculo cliente-vendedor | distinguir no relacionamento quem cadastrou, quem atende e demais papeis, com vigencia e auditoria | cadastros, visibilidade comercial e pedidos | implementada |
| `DEC-012` | Corte e inventario fisico de abertura | definir data de corte, data e responsaveis da contagem, depositos, criterio de aprovacao e tratamento dos movimentos durante o inventario; o Excel sera apenas comparador | ativacao dos saldos operacionais de MP, PI, PA, embalagens e outros insumos | pendente |
| `DEC-013` | Escala operacional da formula na OP | definir se a formula representa lote padrao absoluto ou base proporcional; se proporcional, definir rendimento-base, unidade da OP, perdas e arredondamentos antes de alterar quantidades dos componentes | formulas, OP, reservas, consumo, CQ, custos e lotes gerados | pendente |

## Decisoes autorizadas aguardando implementacao

### DEC-001 - Suporte autenticado no core

Estado: `autorizada`

“Suporte será inicialmente uma subárea autenticada do core, acessível pela
rota /suporte e apresentada como Ajuda e Solicitações. O core será responsável
pelo portal, orientações, registro, acompanhamento e histórico. Ações sensíveis
de identidade, troca de e-mail, MFA, sessões, recuperação e privilégios
permanecerão pertencendo a segurança. Não haverá módulo autônomo suporte nesta
fase. A criação de módulo próprio será reavaliada quando houver equipe,
demanda recorrente, SLA, e-mail, filas, automações e responsabilidades
autônomas suficientes. Enquanto não houver e-mail ou equipe dedicada, o
acompanhamento ocorrerá dentro do sistema, sob responsabilidade da
Administração do sistema e sem SLA público.”

Documentos: `docs/suporte/00_PLANO_EVOLUCAO_SUPORTE.md` e
`docs/decisoes-arquiteturais/ADR-005-suporte-autenticado-no-core.md`.

### DEC-005 - Matriz inicial de perfis e permissoes

Estado: `autorizada`

Autorizada a criacao dos seguintes perfis iniciais:

- Administrador;
- PCP / Producao;
- Estoque;
- Comercial / Pedidos;
- Expedicao / Faturamento;
- Financeiro / Recebimentos e Comissoes;
- Consulta / Auditoria.

Cada pessoa tera conta individual. Perfis serao conjuntos de permissoes
atomicas e poderao ser combinados por usuario. Nao havera contas funcionais
compartilhadas.

A autorizacao deve ser validada no backend e no banco, nao apenas pela
visibilidade da interface. Operacoes financeiras, cancelamentos, estornos,
pagamentos de comissao e mudancas de privilegio deverao ser auditadas e, quando
disponivel, protegidas por reautenticacao/MFA.

Documentos: `docs/seguranca/00_MATRIZ_INICIAL_PERFIS_PERMISSOES.md` e
`docs/decisoes-arquiteturais/ADR-006-perfis-combinaveis-permissoes-atomicas.md`.

## Decisoes ja confirmadas

- solicitacao de troca de email nao pertence a tela publica de login;
- ela deve ser acessada em area autenticada de Suporte;
- Suporte S0 pertence ao `core`; acoes sensiveis permanecem em `seguranca`;
- nao sera criado modulo autonomo `suporte` nesta fase;
- os sete perfis iniciais serao combinacoes de permissoes atomicas por conta individual;
- contas funcionais compartilhadas sao proibidas;
- autorizacao efetiva pertence ao backend e ao banco, nunca somente a interface;
- alteracao da arvore exige autorizacao previa;
- GitHub recebe somente codigo e documentacao, nunca dados operacionais.

## Limite funcional vigente da DEC-013

Enquanto a decisao estiver pendente, a OP copia as quantidades absolutas da
formula versionada. O campo `quantidade_planejada` e apenas referencia da OP e
nao escala componentes, reservas, consumos ou saidas. A interface de
transformacoes nao solicita quantidade de escala para evitar uma promessa que
o contrato atual do banco nao cumpre. Isso nao bloqueia a execucao do lote
padrao definido pela formula.

## Manutencao

Ao obter uma decisao:

1. mudar o estado para `autorizada`;
2. registrar a opcao aprovada de forma literal;
3. implementar em tarefa separada;
4. mudar para `implementada` somente depois da validacao;
5. refletir a proxima tarefa em `docs/01_ESTADO_ATUAL.md`.
