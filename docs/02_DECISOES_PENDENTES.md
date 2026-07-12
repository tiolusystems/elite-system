# Elite System - decisoes pendentes

Atualizado em: 2026-07-12

## Regra

Somente decisoes que exigem Luciano ficam aqui. Uma tarefa nao pode alterar a
arvore arquitetonica enquanto sua decisao estiver `pendente`.

Estados permitidos: `pendente`, `autorizada`, `implementada`, `cancelada`.

## Decisoes abertas

| ID | Decisao | Recomendacao tecnica | Impacto | Estado |
|---|---|---|---|---|
| `DEC-001` | Onde Suporte pertence na arvore e qual sera sua rota autenticada | primeiro avaliar uma subarea de `seguranca` ou `core`; criar modulo `suporte` somente se houver funcoes proprias suficientes | rota, navegacao, ownership e catalogo modular | pendente |
| `DEC-002` | Fluxo MFA TOTP | QR Code TOTP padrao, compativel com Google Authenticator em Android/iOS, Apple Passwords, Microsoft Authenticator e equivalentes; exigir AAL2 no banco | boundary Auth, login, recuperacao e RPCs criticas | pendente |
| `DEC-003` | Aprovacao da troca de email do proprio administrador | com dois administradores, proibir autoaprovacao; enquanto houver apenas um, exigir MFA e reautenticacao forte | governanca e continuidade administrativa | pendente |
| `DEC-004` | Politica Auth de producao | senha forte, CAPTCHA, sessoes limitadas, SMTP corporativo e confirmacao adequada de email antes da internet | configuracao Supabase cloud e UX de acesso | pendente |

## Decisoes ja confirmadas

- solicitacao de troca de email nao pertence a tela publica de login;
- ela deve ser acessada em area autenticada de Suporte;
- alteracao da arvore exige autorizacao previa;
- GitHub recebe somente codigo e documentacao, nunca dados operacionais.

## Manutencao

Ao obter uma decisao:

1. mudar o estado para `autorizada`;
2. registrar a opcao aprovada de forma literal;
3. implementar em tarefa separada;
4. mudar para `implementada` somente depois da validacao;
5. refletir a proxima tarefa em `docs/01_ESTADO_ATUAL.md`.
