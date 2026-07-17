# Validacao 0065 - Pessoas e vinculos comerciais

## Escopo

A migration `0065_govern_commercial_people_relationships.sql` governa a
identidade comercial, a revisao de possiveis duplicidades, os vinculos
temporais com areas comerciais e a reativacao. O pacote nao modifica contas,
convites, perfis de autenticacao ou outras funcoes do dominio Seguranca.

## Contratos validados

- homonimos sao permitidos somente depois de preflight, confirmacao e motivo;
- codigo legado preenchido permanece absolutamente unico apos normalizacao;
- aliases iguais podem pertencer a pessoas diferentes, mas nao se repetem na
  mesma pessoa;
- a RPC de criacao adquire lock transacional e recalcula os candidatos;
- areas comerciais sao relacionadas por ID e possuem vigencia sem exclusao do
  historico;
- area inativa vinculada continua legivel e nao pode receber novo vinculo;
- reativacao preserva a pessoa e nao reabre vinculos encerrados;
- escrita direta permanece revogada e as RPCs negam `PUBLIC` e `anon`;
- confirmacoes, vinculos, encerramentos e reativacoes produzem auditoria.

## Ambientes descartaveis

Foram usados projetos independentes do runtime ativo:

- `elite-validation-people-upgrade`: instalacao ate `0064`, seguida da
  aplicacao isolada da `0065`;
- `elite-validation-people-clean`: instalacao limpa de toda a cadeia ate
  `0065`.

Os dois projetos possuem identificadores, containers, volumes e portas
proprios. Nenhum `db reset` foi executado e o projeto `elite-system` nao foi
alterado.

## Resultados PostgreSQL

- upgrade `0064 -> 0065`: aprovado;
- instalacao limpa ate `0065`: aprovada;
- smoke `commercial_people_governance.sql`: aprovado nos dois ambientes;
- lint PostgreSQL: aprovado, sem erro;
- concorrencia: duas criacoes simultaneas da mesma identidade resultaram em
  um registro; a segunda chamada recalculou os candidatos e foi recusada;
- marcador do smoke: `PG_VALIDATE_0065_WITH_SMOKE_OK`.

## Resultados da interface

- desktop `1366 x 768`: consulta, filtros, pessoa selecionada e acoes visiveis;
- mobile `390 x 844`: lista e formulario responsivos, sem rolagem horizontal;
- formulario: tipo, vendedor responsavel, papeis e areas usam valores
  controlados ou relacionamentos por ID;
- nenhum enum cru, underscore operacional ou erro tecnico apareceu na tela;
- o arquivo global de estilos foi validado sem BOM antes de `:root`, mantendo
  os tokens visuais ativos no navegador.

## Publicacao

A aplicacao no staging somente pode ocorrer depois do commit, push, deploy do
frontend e comparacao do ledger remoto. Se existir migration pendente de outro
dominio, a aplicacao deve ser interrompida em vez de usar `db push`
indiscriminadamente.
