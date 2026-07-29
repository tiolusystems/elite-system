# Elite System - decisoes pendentes

Atualizado em: 2026-07-28

## Regra

Este arquivo contem somente decisoes ainda dependentes de Luciano. Decisoes
implementadas permanecem nos ADRs, migrations, testes e no historico
`docs/historico/02_DECISOES_ATE_2026-07-28.md`.

Estados permitidos: `pendente` e `autorizada`.

| ID | Decisao | Impacto | Estado |
|---|---|---|---|
| `DEC-002` | Fluxo MFA TOTP | login, recuperacao e RPCs criticas | pendente |
| `DEC-003` | Aprovacao da troca de e-mail do proprio administrador | governanca e continuidade administrativa | pendente |
| `DEC-004` | Politica Auth de producao | configuracao Supabase de producao, CAPTCHA, SMTP e sessoes | pendente |
| `DEC-005` | Ativacao operacional dos sete perfis combinaveis ja desenhados | composicao de permissoes atomicas por conta individual | autorizada |
| `DEC-012` | Corte e inventario fisico de abertura | ativacao de saldos oficiais de MP, PI, PA e embalagens | pendente |

## Limites vigentes

- nenhuma dessas decisoes pode ser implementada por inferencia dentro do
  `OPS-GATE-01`;
- importacao historica e ativacao de saldos permanecem bloqueadas ate
  `DEC-012`;
- politica Auth de producao nao altera o ambiente local ou o staging sem gate
  proprio;
- perfis nunca substituem a verificacao de alçada atomica no backend e no
  banco;
- contas compartilhadas continuam proibidas.

## Manutencao

Quando Luciano decidir um item:

1. registrar a opcao aprovada no ADR correspondente;
2. executar em tarefa separada;
3. validar backend, banco e interface;
4. retirar o item deste arquivo somente depois da entrega comprovada;
5. preservar a decisao implementada no ADR e no historico Git.
