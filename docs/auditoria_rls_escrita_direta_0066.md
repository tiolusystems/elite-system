# Gate critico de RLS e escrita direta - migration 0066

Data: 2026-07-20

## Isolamento

- worktree: limpa a partir do commit publicado `8ae5904`;
- branch: `security-critical-rls-direct-write`;
- migration local preservada `0062`: ausente deste worktree e nao aplicada;
- staging: consultado somente em transacao read-only;
- dados usados nos smokes: exclusivamente sinteticos em projetos
  `elite-validation-*`.

## Estado efetivo encontrado no staging

- ledger remoto mais recente: `0065`;
- tabelas no schema `public`: 132;
- tabelas sem RLS: 0;
- tabelas criticas: 0;
- tabelas com politica latente de escrita: 0;
- tabelas com escrita direta para `anon`: 0;
- tabelas com escrita direta para `authenticated`: 0;
- tabelas com escrita direta para `PUBLIC`: 0;
- todas as politicas efetivas encontradas nas tabelas eram `SELECT`;
- proprietario efetivo das tabelas e funcoes da aplicacao: `postgres`.

O apontamento externo de combinacao atual entre grants diretos e politicas de
escrita foi um falso positivo para o estado final efetivo do staging. Ele
identificou, contudo, uma lacuna real no contrato de funcoes: grants padrao
permitiam que funcoes novas nascessem executaveis por papeis da Data API e
havia exposicao historica ampla de RPCs.

## Correcao

`0066_close_direct_write_and_rpc_exposure.sql`:

- revoga escrita direta de `PUBLIC`, `anon` e `authenticated` em todas as
  tabelas publicas;
- revoga acesso direto a sequences para os mesmos papeis;
- revoga `EXECUTE` global e concede novamente somente a allowlist explicita de
  RPCs autenticadas governadas;
- preserva `postgres`, `service_role` e os contratos internos;
- fecha os default privileges de objetos futuros cujo proprietario real das
  migrations da aplicacao e `postgres`;
- nao altera regra funcional de nenhum modulo.

Os default privileges de plataforma pertencentes a `supabase_admin` nao podem
ser alterados por uma migration executada como `postgres`. Eles nao governam
os objetos atuais da aplicacao, todos pertencentes a `postgres`; o gate exige
zero exposicao efetiva nos objetos existentes e defaults seguros para o owner
real das migrations da aplicacao.

## Provas descartaveis

- upgrade `0065 -> 0066`: aprovado;
- instalacao limpa `0001 -> 0066`: aprovada;
- gate estrutural: `ELITE_SECURITY_ZERO_DIRECT_WRITE_GATE_OK`;
- sweep sem concessoes: `ZERO_GRANT_SWEEP_OK`, 79 alvos e 79 negacoes;
- Data API: `ELITE_DATA_API_NON_BYPASS_OK`, 99 tentativas, 11 dominios e tres
  contextos;
- fingerprints dos 11 dominios antes/depois: identicos;
- RPC governada com permissao valida: `PG_VALIDATE_0065_WITH_SMOKE_OK`;
- testes estaticos da correcao: 3 aprovados;
- suite Python: 397 aprovados e uma falha preexistente fora do escopo no
  contrato visual `createMateriaPrimaAction`;
- ESLint: aprovado;
- build Next.js: aprovado, 25 paginas estaticas geradas e rotas dinamicas
  compiladas.

Dominios cobertos pela prova HTTP: Cadastros, Pedidos, Estoque, PCP, Producao,
Romaneio, Faturamento, Financeiro, Metas, Importacao e Seguranca. Contextos:
anonimo, autenticado ativo sem concessoes e autenticado com permissoes
operacionais normais.

## Situacao de publicacao

A migration 0066 ainda nao foi aplicada ao staging. UX-01C e a promocao do
Preview permanecem pausados ate commit, push, aplicacao isolada da 0066,
repeticao da auditoria read-only, health-check e smoke final.
