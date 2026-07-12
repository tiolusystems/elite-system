# Elite System - plano de evolucao do Suporte

Data: 2026-07-12
Decisao proprietaria: `DEC-001`
Estado: arquitetura autorizada; implementacao ainda nao iniciada

## 1. Objetivo do Suporte

Oferecer uma area autenticada para ajuda, orientacoes e solicitacoes, permitindo
que o usuario registre uma necessidade, acompanhe seu andamento e consulte o
historico sem depender de conversa externa ou conhecimento tecnico.

Suporte organiza a comunicacao. Ele nao substitui as regras, alçadas ou RPCs do
dominio responsavel pela acao solicitada.

## 2. Usuarios atendidos

- usuarios humanos autenticados e com perfil ativo;
- administradores responsaveis pelo atendimento inicial;
- futuros atendentes internos, quando essa funcao existir formalmente;
- auditoria, apenas conforme alçada de leitura definida para o historico.

Ator de sistema, usuario anonimo e conta sem perfil ativo nao abrem solicitacao
operacional.

## 3. Ownership entre core e seguranca

| Responsabilidade | Proprietario |
|---|---|
| portal `/suporte`, orientacoes, abertura e acompanhamento | `core` |
| classificacao, status, mensagens e historico da solicitacao | `core` |
| identidade, usuario, e-mail, MFA, sessao e recuperacao | `seguranca` |
| autorizacao e execucao de acao sensivel | `seguranca` |
| auditoria da acao sensivel | `seguranca` |
| referencia entre solicitacao e evento sensivel | contrato entre `core` e `seguranca` |

O `core` nunca altera diretamente tabela ou credencial de `seguranca`. Quando a
solicitacao exigir acao sensivel, o portal chama o contrato governado do dominio
`seguranca` e apenas referencia seu resultado auditavel.

## 4. Escopo da fase S0

- area autenticada apresentada como **Ajuda e Solicitacoes**;
- orientacoes curtas para problemas comuns;
- abertura de solicitacao tipada;
- descricao e contexto fornecidos pelo usuario;
- acompanhamento por status;
- historico cronologico dentro do sistema;
- tratamento inicial pela Administracao do sistema;
- direcionamento de troca de e-mail para o fluxo governado de `seguranca`;
- captura automatica de contexto tecnico nao secreto.

## 5. Fora do escopo da fase S0

- modulo autonomo `suporte`;
- caixa postal, envio ou recebimento de e-mail;
- chat em tempo real, WhatsApp, telefone ou rede social;
- equipe dedicada, plantao ou escala de atendimento;
- SLA publico ou prazo contratual;
- bot, IA de atendimento ou resposta automatica;
- integracao com ferramenta externa de help desk;
- alteracao direta de identidade, credencial, estoque, pedido ou qualquer fato
  operacional pelo registro de suporte;
- anexos arbitrarios antes de politica de seguranca, tamanho e retencao.

## 6. Fluxo da solicitacao

| Status | Significado | Responsavel pelo proximo passo |
|---|---|---|
| `abertura` | rascunho ainda nao enviado | usuario solicitante |
| `recebida` | solicitacao registrada e disponivel para triagem | Administracao do sistema |
| `em_analise` | responsavel iniciou diagnostico ou encaminhamento | Administracao do sistema |
| `aguardando_usuario` | falta confirmacao ou informacao do solicitante | usuario solicitante |
| `resolvida` | resposta ou acao concluida e historico preservado | nenhum, salvo reabertura futura governada |
| `cancelada` | solicitacao encerrada sem execucao | Administracao ou solicitante, conforme regra futura |

Transicoes devem ser fechadas e auditadas. A implementacao S0 definira a tabela
de transicoes antes de permitir mudanca de status.

## 7. Tipos de solicitacao

| Tipo | Exemplos | Dominio executor quando houver acao |
|---|---|---|
| conta e seguranca | troca de e-mail, acesso, MFA, sessao | `seguranca` |
| erro | falha de tela, validacao ou processamento | modulo onde ocorreu |
| duvida | orientacao de uso ou regra exibida | `core` ou modulo relacionado |
| dados/operacao | divergencia ou pedido de verificacao | dominio proprietario do dado |
| melhoria | sugestao de processo ou interface | triagem arquitetonica antes de implementar |

## 8. Operacao sem e-mail

Na S0 nao existe canal de suporte por e-mail. A abertura, resposta,
complementacao e consulta acontecem dentro do Elite System. Nao sera exibido
endereco ficticio, promessa de notificacao externa ou mensagem de e-mail
enviado.

## 9. Operacao sem equipe dedicada

Enquanto nao houver equipe formal, a Administracao do sistema faz a triagem e o
acompanhamento. A interface deve dizer quem possui o proximo passo, sem sugerir
central, atendente exclusivo ou disponibilidade permanente.

## 10. Ausencia de SLA publico

A fase S0 nao publica prazo de primeira resposta, solucao ou disponibilidade.
Tempos internos podem ser medidos para conhecer a demanda, mas nao constituem
SLA. Um SLA somente podera existir apos capacidade, horario, responsavel e
processo de escalonamento formalmente aprovados.

## 11. Informacoes tecnicas capturadas automaticamente

Quando disponiveis e necessarias ao diagnostico:

- usuario e perfil autenticado;
- data, hora e fuso;
- rota e modulo onde a solicitacao foi aberta;
- ambiente e versao/commit da aplicacao;
- navegador, sistema operacional e classe de dispositivo;
- codigo de erro seguro e correlation id existente;
- estado de conectividade informado pela aplicacao.

Nunca capturar senha, token, cookie, chave, segredo, conteudo integral de XML,
dado comercial desnecessario ou valor sensivel de formulario. Diagnostico
adicional depende de finalidade clara e minimizacao de dados.

## 12. Politica de auditoria e historico

- abertura e cada transicao registram ator, data e motivo;
- resposta e complemento preservam autoria;
- historico concluido nao e reescrito para ocultar evento anterior;
- correcao gera novo evento;
- acao sensivel mantem auditoria no dominio `seguranca`;
- a solicitacao referencia o evento sensivel sem copiar credencial ou segredo;
- exclusao fisica nao faz parte da S0; retencao futura exige politica aprovada;
- leitura segue perfil, ownership e necessidade operacional.

## 13. Roadmap

| Fase | Capacidade |
|---|---|
| `S0` suporte basico | portal autenticado, orientacoes, solicitacao, status e historico interno |
| `S1` operacao interna | responsavel, prioridade interna, fila, categorias maduras, busca e metricas |
| `S2` seguranca e comunicacao | MFA/AAL2 para acoes criticas, notificacoes governadas, SMTP e politica de sessao |
| `S3` central de atendimento | equipe, horarios, SLA aprovado, escalonamento, automacoes e possivel modulo autonomo |
| `S4` mobile/multicanal | experiencia mobile consolidada e canais externos integrados com identidade e historico unificados |

## 14. Gatilhos para avancar entre fases

| Avanco | Gatilhos objetivos minimos |
|---|---|
| `S0 -> S1` | demanda recorrente medida; volume que exige fila; responsaveis definidos; categorias e prioridades revisadas |
| `S1 -> S2` | DEC-002, DEC-003 e DEC-004 resolvidas; SMTP e politicas Auth homologados; recuperacao testada sem lockout |
| `S2 -> S3` | equipe ou funcao dedicada; horario e capacidade definidos; SLA aprovado; regras de escalonamento; volume sustentado |
| `S3 -> S4` | processo estavel; necessidade multicanal comprovada; identidade entre canais; politica de privacidade e retencao; capacidade de suporte mobile |

Avanco nao ocorre apenas por data ou desejo visual. Cada gatilho precisa de
evidencia e autorizacao quando alterar a arquitetura.

## 15. Dependencias de decisoes abertas

- `DEC-002`: define cadastro, desafio, recuperacao e exigencia de MFA TOTP;
- `DEC-003`: define autoaprovacao e continuidade da conta administrativa;
- `DEC-004`: define senha, CAPTCHA, sessao, SMTP e confirmacao de e-mail para
  producao.

S0 pode registrar e acompanhar solicitacoes sem resolver essas decisoes. A
execucao de acao sensivel continua limitada ao contrato atual de `seguranca`.

## 16. Criterios para modulo autonomo suporte

A proposta de modulo proprio so pode ser aberta quando houver, em conjunto:

- equipe ou funcao de atendimento formal;
- demanda recorrente e volume mensurado;
- fila e ownership independentes do painel geral;
- SLA ou metas internas aprovadas;
- e-mail/canais e automacoes proprias;
- dados, regras e relatorios com ciclo de vida autonomo;
- dependencias e action keys que justifiquem boundary separado;
- custo de manter a subarea no `core` maior que o custo de separacao.

Se esses criterios nao existirem, Suporte permanece subarea do `core`.

## 17. Riscos e nao objetivos

Riscos principais:

- transformar suporte em atalho para burlar alçadas;
- prometer atendimento que a operacao ainda nao consegue sustentar;
- capturar dados tecnicos ou comerciais em excesso;
- duplicar fatos de `seguranca` no `core`;
- criar fila sem responsavel real;
- antecipar integracoes antes de estabilizar o processo interno.

Nao e objetivo da S0 resolver incidentes automaticamente, substituir auditoria,
administrar credenciais, operar outros modulos ou criar uma central comercial.

## 18. Criterios de aceite da implementacao basica

- `/suporte` exige sessao e perfil ativo;
- nome visivel **Ajuda e Solicitacoes**;
- portal pertence ao `core`, sem chave de modulo `suporte`;
- tipos e status seguem este documento;
- usuario abre, acompanha e complementa sua solicitacao;
- Administracao visualiza e conduz a triagem;
- troca de e-mail sai da tela publica de login e aparece como solicitacao;
- acao de identidade continua executada somente por `seguranca`;
- historico e transicoes sao auditaveis;
- contexto tecnico exclui credenciais e segredos;
- estados vazios explicam o que ocorreu e quem executa o proximo passo;
- desktop e mobile passam por validacao visual;
- nenhum texto promete e-mail, equipe dedicada ou SLA;
- testes de rota, ownership, permissao e transicao passam antes do commit.
