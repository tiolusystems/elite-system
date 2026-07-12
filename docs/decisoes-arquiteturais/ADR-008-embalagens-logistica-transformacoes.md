# ADR-008 - Embalagens, logistica e transformacoes relacionais

Status: aceita e implementada por `DEC-008`.

## Contexto

O schema possuia identidade de embalagem, relacao produto-embalagem,
conversoes textuais de unidade e romaneio. Faltavam composicao versionada,
tara, cubagem, atribuicao de entregador/veiculo e um fato relacional para
transformacoes entre PA e PI. O Excel possui esses dados de forma parcial e
nao prova todas as transformacoes.

## Decisao

O contrato fica dividido por ownership:

| Contrato | Proprietario | Dependencias |
|---|---|---|
| unidade, conversao, embalagem, versao e BOM | `cadastros` | `core`, `seguranca` |
| atribuicao de entregador e veiculo | `expedicao` | `cadastros`, `pedidos` |
| transformacao, origem, destino e perda | `estoque` | `cadastros`, `pcp` |

`cad_embalagem_versoes` guarda tara, cubagem e vigencia.
`cad_embalagem_componentes` liga cada versao a MP, quantidade e unidade por
FK. Ativacao e desativacao sao eventos append-only feitos por ator humano.

`exp_romaneio_logistica_eventos` registra atribuicao/remocao sem sobrescrever
o romaneio. O read model atual deriva o ultimo evento aprovado.

`est_transformacoes` e cabecalho. Origens e destinos usam tabelas separadas,
com FKs exclusivas para lote PA ou lote PI. Perdas sao fatos proprios. Nenhum
desses registros gera movimento de estoque automaticamente nesta decisao.

## Chaves naturais e idempotencia

- versao: embalagem + numero da versao;
- componente: versao + materia-prima;
- conversao: MP + unidade origem + unidade destino + inicio da vigencia;
- fato historico: `source_batch_id` + `source_row_id` + dimensao do fato;
- cada atribuicao logistica historica tem uma unica origem batch/linha;
- transformacao historica tem uma unica origem batch/linha/tipo, e seus
  participantes repetem a linhagem com a identidade do lote.

## Campos obrigatorios

- FKs canonicas de unidade em embalagem, conversao, BOM e transformacao;
- quantidade positiva em componente, origem, destino e perda;
- origem e destino de transformacao ligados a exatamente uma familia PA/PI;
- evidencia descrita para transformacao comprovada ou inferida;
- ator, origem, batch e linha em todo fato `excel_legado`;
- `pending_review` em todo registro historico com efeito potencial na operacao.

## Campos opcionais

- tara e cubagem quando a fonte nao as informa;
- vigencia quando a data original nao pode ser provada;
- veiculo ou entregador isoladamente numa atribuicao parcial;
- data da atribuicao ou transformacao historica quando ausente;
- perda, porque nem toda transformacao possui perda registrada.

Ausencia permanece nula. O sistema nao inventa peso, cubagem, data, veiculo,
entregador, perda ou fator de conversao.

## Pendentes de revisao

- unidade desconhecida criada pelo backfill;
- capacidade de veiculo sem unidade;
- BOM, medida logistica ou conversao vinda do Excel;
- atribuicao historica ainda nao confirmada;
- qualquer transformacao inferida.

Transformacao inferida e estruturalmente impedida de ficar `approved`.

## Backfill

1. unidades textuais existentes sao resolvidas contra o catalogo da DEC-007;
2. termo desconhecido vira unidade `pending_review`, preservando o texto;
3. embalagem e conversao recebem FKs canonicas;
4. registros preexistentes sem classificacao recebem origem `sistema`;
5. conversoes existentes recebem `approved` sem alterar fator ou vigencia;
6. nenhuma versao/BOM e criada a partir de `volume_litros`, pois esse campo nao
   prova tara, cubagem ou composicao;
7. nenhum evento logistico ou transformacao e fabricado no backfill.

## Regras temporais

Conversoes e versoes possuem vigencia. Alteracao cria nova versao ou nova
linha, nunca edita o fato anterior. Atribuicao logistica e ledger de eventos.
Transformacao e seus participantes sao append-only.

## Integridade e seguranca

- dados consultaveis usam FKs e tabelas, nao JSON;
- escrita direta de `authenticated` fica revogada nas novas tabelas;
- RLS libera somente leitura para perfil ativo;
- ativacao de embalagem exige perfil humano ativo;
- atribuicao aprovada de entregador exige papel `entregador` vigente;
- historico exige ator `Migracao Historica` e batch/linha do mesmo workbook;
- read models operacionais excluem pendencias e inferencias.

## Fora do escopo

- decidir se a embalagem e baixada na OP, no envase ou no romaneio;
- gerar movimentos PA/PI ou consumo de embalagem a partir da transformacao;
- calcular peso total do romaneio sem uma regra homologada para a unidade da
  quantidade comercial;
- criar UI, RPC de aprovacao ou importador.

Esses itens nao bloqueiam o contrato relacional e nao sao antecipados.

## Rollback

Antes de dados dependentes, restaurar o backup do banco de teste e voltar ao
commit anterior a `0051`. Rollback manual segue a ordem inversa:

1. views, policies e triggers;
2. tabelas de transformacao e evento logistico;
3. ativacoes, componentes e versoes de embalagem;
4. FKs e colunas adicionadas aos cadastros e romaneios.

Depois de fatos dependentes, rollback destrutivo e proibido. A correcao deve
ser nova migration de compatibilidade, preservando todo ledger.

## Consequencias

- custo de embalagem podera ser recalculado pela BOM e preco de MP;
- peso/cubagem passam a ter versao e vigencia;
- romaneio pode ter historico de entregador e veiculo;
- PA/PI pode ser rastreado por transformacao sem editar saldo;
- o importador podera registrar incerteza sem transforma-la em operacao.
