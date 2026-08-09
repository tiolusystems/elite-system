# ADR-006 - Perfis combinaveis com permissoes atomicas

Data: 2026-07-12
Status: autorizado
Decisao relacionada: `DEC-005`

## Contexto

O modelo inicial usa um papel principal em `user_profiles.role` e overrides por
usuario. Esse desenho foi suficiente para bootstrap, mas nao representa pessoas
que acumulam responsabilidades, como producao e estoque, nem oferece uma matriz
reutilizavel para equipes.

O sistema precisa preservar conta individual, default deny, auditoria e
validacao no banco. Perfil nao pode ser apenas menu ou cargo textual.

## Decisao

Sera adotado um modelo em que:

- cada pessoa possui conta individual;
- perfil e conjunto versionado de permissoes atomicas;
- usuario pode receber varios perfis simultaneamente;
- autorizacao efetiva e calculada no banco;
- backend e RPC validam a permissao antes da operacao;
- interface apenas reflete a autorizacao efetiva;
- contas funcionais compartilhadas sao proibidas;
- acoes criticas permanecem auditadas e receberao reautenticacao/MFA quando o
  contrato correspondente estiver disponivel.

Os sete perfis iniciais sao:

1. Administrador;
2. PCP / Producao;
3. Estoque;
4. Comercial / Pedidos;
5. Expedicao / Faturamento;
6. Financeiro / Recebimentos e Comissoes;
7. Consulta / Auditoria.

## Alternativas consideradas

### Um papel unico por usuario

Rejeitada como modelo final. Nao representa acumulacao de responsabilidades e
estimula papeis excessivamente poderosos.

### Permissao somente por usuario

Rejeitada como padrao principal. Gera configuracao repetitiva, dificil de
auditar e sujeita a divergencia entre pessoas com a mesma funcao.

### Contas compartilhadas por setor

Rejeitada. Elimina autoria real, enfraquece MFA, dificulta desligamento e viola
a rastreabilidade exigida.

### Perfis combinaveis com overrides individuais

Escolhida. Reutiliza conjuntos coerentes, permite excecao controlada e preserva
default deny e auditoria por pessoa.

## Consequencias

Positivas:

- menor duplicacao de configuracao;
- combinacao explicita de responsabilidades;
- onboarding e desligamento mais consistentes;
- auditoria de atribuicao e permissao efetiva;
- interface e backend consultam a mesma fonte.

Custos:

- exige migration relacional e reconciliacao do papel atual;
- exige versao e lifecycle dos perfis;
- exige funcao unica de calculo efetivo;
- exige UI administrativa para atribuicao multipla;
- exige testes de conflito, zero-grant e escalada.

## Invariantes

- nenhuma permissao nasce de nome de tela ou cargo textual;
- permissao ausente e negada;
- deny individual prevalece sobre grants combinados;
- perfil inativo e usuario inativo nao concedem acesso;
- acao sensivel continua validando dominio, estado e escopo;
- service role permanece somente em boundary server-only;
- o ultimo administrador capaz nao pode ser removido por acidente;
- alteracao de privilegio sempre e auditada.

## Implementacao futura

A implementacao sera tarefa separada e devera apresentar antes da migration:

- schema relacional proposto;
- compatibilidade com `user_profiles.role` e overrides atuais;
- action keys de cada perfil;
- regra de conflito e calculo efetivo;
- plano de backfill e rollback;
- smokes de usuario combinado, zero-grant e tentativa de escalada;
- pontos que exigirao `aal2`.

## Rollback arquitetural

Durante a transicao, `user_profiles.role` permanece disponivel como
compatibilidade. Se a migration de perfis combinaveis falhar na homologacao:

1. bloquear novas atribuicoes;
2. preservar tabelas e logs para diagnostico;
3. restaurar leitura efetiva pelo contrato anterior;
4. reconciliar cada usuario com snapshot anterior;
5. corrigir por nova migration, sem editar migration aplicada;
6. nunca reativar conta compartilhada ou liberar default allow.

## Evidencia relacionada

A matriz conceitual e os criterios de aceite estao em
`docs/seguranca/00_MATRIZ_INICIAL_PERFIS_PERMISSOES.md`.
