# ORD-01 - Fase 1A.1 - Listas de preco canonicas

## Entrega

A tranche 1A.1 estabelece somente a fundacao governada de listas de preco:

- identidade estavel da lista e versoes de trabalho;
- cobertura explicita por apresentacao (`cad_produto_embalagens.id`);
- faixas normalizadas, incluindo `0` para pagamento a vista;
- preco em centavos de BRL por litro, sempre maior que zero;
- regras de elegibilidade e escopos relacionais;
- publicacao imutavel e lifecycle append-only;
- RLS, permissoes default deny, auditoria, idempotencia e concorrencia.

Nao fazem parte desta tranche: XLSX, staging, PMP, resolucao de lista, Pedido,
desconto, credito, COMM, overprice, participantes ou campanhas.

## Invariantes

`com_lista_preco_publicacoes` e a unica fonte canonica do fato de publicacao.
O ledger `com_lista_preco_lifecycle_eventos` registra somente fatos posteriores:
sucessao e retirada. Nao existe um segundo evento `published`.

Depois da publicacao, a versao, sua cobertura, precos, regras e escopos nao
aceitam insercao, alteracao ou exclusao. Correcao exige nova versao. Sucessao e
retirada criam fatos append-only, sem atualizar um status historico.

A primeira publicacao pode ter vigencia historica para bootstrap. Uma sucessora
operacional nao pode retroagir em relacao a data comercial da Elite, calculada
explicitamente no fuso `America/Sao_Paulo`.

A cobertura e independente dos precos:

- apresentacao ausente da cobertura: a lista nao sera candidata;
- apresentacao coberta sem faixa aplicavel: configuracao incompleta e futuro
  resolver deve falhar fechado, sem buscar fallback silencioso.

## Escopos

Cada regra usa AND entre dimensoes e OR entre valores da mesma dimensao. Uma
dimensao sem valores funciona como curinga. Regras distintas sao alternativas.

As relacoes usam FKs reais para origem comercial, atribuicao historica de
pessoa/papel, area comercial, cliente, produto e apresentacao. UF e valor
controlado pela lista oficial de siglas. Nao existem `scope_type`, `entity_id`
generico, texto livre de entidade ou JSON como armazenamento relacional.

O escopo de pessoa referencia `cad_pessoa_papeis.id`. Isso permite que uma
pessoa participe em capacidades diferentes sem criar tabelas rigidas para
agente, vendedor, gerente ou futuros papeis governados.

Origem comercial possui inicialmente `direto_elite` e `agente`. Ela sera fato
explicito da operacao em fase posterior; relacionamentos cadastrais nao a
determinam retroativamente. Natureza do cliente e tipo de operacao nao foram
incluidos porque ainda nao ha catalogo canonico comprovado para esta fundacao.

## Unidade comercial e prazos

O preco publicado usa `valor_centavos_por_litro bigint`. O valor `3126`
representa `R$ 31,26/L`. `prazo_dias` e nao negativo; `0` significa a vista.
Adicionar prazo nao exige coluna nova.

Na futura 1A.2, o staging preservara o valor bruto `numeric`. A publicacao fara
`numeric -> round(valor, 2) -> centavos`, sem `float`, `double` ou JavaScript
`Number` como fonte canonica.

A UI atual de Pedidos trata `quantidade` como numero de apresentacoes e calcula
volume por `quantidade * volume_litros`. Nenhum Pedido e migrado nesta tranche.
As fases posteriores deverao distinguir quantidade de apresentacoes, volume por
apresentacao, litros totais, preco por litro e valor total.

## Integracoes posteriores

- 1A.2: ingestao, staging e reconciliacao de XLSX contra apresentacoes reais;
- 1B: condicao financeira, parcelas, datas e PMP;
- 1C: elegibilidade, especificidade, prioridade, faixa e referencia vencedora;
- 1D: snapshot do Pedido, origem explicita e participantes de ORD;
- COMM: consumo posterior de participacoes e politicas remuneratorias;
- overprice: referencia tecnica opcional, independente da unica referencia
  comercial vencedora, conforme politica futura.
