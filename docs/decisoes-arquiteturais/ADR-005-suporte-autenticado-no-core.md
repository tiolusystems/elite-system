# ADR-005 - Suporte autenticado no core

Data: 2026-07-12
Status: autorizado
Decisao relacionada: `DEC-001`

## Contexto

O Elite System precisa retirar solicitacoes de conta da tela publica de login e
oferecer ao usuario autenticado um local claro para ajuda, abertura e
acompanhamento. Ainda nao existe equipe de suporte, canal de e-mail, SLA, fila
madura ou dominio operacional que justifique um modulo autonomo.

Ao mesmo tempo, troca de e-mail, MFA, sessoes, recuperacao e privilegios sao
acoes sensiveis e ja pertencem ao dominio `seguranca`. Mover sua regra para um
novo portal criaria duplicidade e enfraqueceria o boundary aprovado.

## Decisao

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

Esta ADR autoriza a arquitetura. Ela nao implementa rota, navegacao, banco,
RPC, autenticacao ou fluxo funcional.

## Alternativas consideradas

### Criar modulo autonomo suporte agora

Rejeitada nesta fase. Criaria catalogo, dependencias, action keys, rollout e
ownership antes de existir operacao autonoma suficiente.

### Colocar todo o suporte em seguranca

Rejeitada. Duvidas, erros, melhorias e solicitacoes operacionais nao sao todas
responsabilidade de identidade e acesso. Isso ampliaria indevidamente o dominio
`seguranca`.

### Usar somente e-mail ou ferramenta externa

Rejeitada na S0. Nao ha e-mail ou equipe dedicada, e o usuario perderia a visao
integrada do andamento dentro do sistema.

### Subarea autenticada do core com delegacao sensivel

Escolhida. Usa o shell e a sessao existentes, preserva o ownership de
`seguranca` e permite evolucao baseada em demanda real.

## Por que core e o proprietario inicial

- `core` ja governa sessao, painel, health-check e runtime central;
- o portal e uma capacidade transversal de navegacao e acompanhamento;
- S0 nao possui ciclo operacional independente;
- orientacoes, abertura e historico sao comuns aos demais modulos;
- evita criar dependencia nova para cada modulo que possa receber solicitacao.

## Por que seguranca continua dona das acoes sensiveis

- identidade e credencial pertencem ao Supabase Auth e a `seguranca`;
- alçadas e auditoria administrativa ja possuem RPCs e invariantes maduras;
- o portal nao deve obter service role nem escrita direta em tabelas sensiveis;
- uma solicitacao nao equivale a autorizacao para executar a acao;
- a auditoria sensivel precisa permanecer na fonte canonica.

## Por que nao criar modulo suporte agora

Nao existem ainda equipe, demanda medida, SLA, canal, automacao, fila ou
responsabilidade autonoma. Um modulo agora seria uma divisao tecnica sem
boundary de negocio real e aumentaria custo de seguranca, testes e rollout.

## Consequencias

Positivas:

- um ponto autenticado e compreensivel para o usuario;
- separacao clara entre pedido de ajuda e execucao sensivel;
- nenhuma nova dependencia modular na S0;
- evolucao incremental e auditavel;
- troca futura para modulo proprio permanece possivel.

Custos e limites:

- Administracao do sistema assume triagem inicial;
- nao existe notificacao externa ou SLA;
- `core` precisa manter o portal generico e nao absorver regra dos dominios;
- contratos de delegacao devem evitar escrita cruzada.

## Criterios de reavaliacao

Reavaliar modulo autonomo quando os criterios do plano de evolucao forem
atendidos, especialmente:

- equipe ou funcao formal de atendimento;
- volume recorrente mensurado;
- fila, prioridade e ownership independentes;
- SLA ou metas internas aprovadas;
- e-mail, canais ou automacoes proprias;
- ciclo de dados e relatorios autonomo.

A reavaliacao exige nova ADR e autorizacao para mudar a arvore arquitetonica.

## Rollback arquitetural

Se a subarea no `core` se mostrar inadequada antes de entrar em operacao:

1. manter `seguranca` e seus fluxos sensiveis inalterados;
2. retirar a futura rota e navegacao do `core` por mudanca versionada;
3. preservar historico ja registrado e seus identificadores;
4. desabilitar novas aberturas sem apagar eventos;
5. aprovar nova ADR para modulo proprio ou ferramenta externa;
6. migrar referencias por contrato auditado, com reconciliacao e rollback.

Rollback nunca autoriza apagar historico nem mover credencial para outro
dominio.
