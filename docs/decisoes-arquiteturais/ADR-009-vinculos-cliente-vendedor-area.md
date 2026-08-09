# ADR-009 - Vinculos temporais cliente, vendedor e area

Status: aceita e implementada por `DEC-011`.

## Contexto

`cad_cliente_vendedores` identificava cliente, pessoa e vigencia, mas nao
distinguia quem cadastrou de quem atende. Areas comerciais ligavam pessoas a
regioes, sem relacionar a area ao cliente/propriedade. O Excel possui as duas
pessoas em colunas diferentes e nao pode ser importado apagando essa semantica.

## Decisao

`cadastros` continua proprietario de todos os vinculos. `pedidos` apenas
referencia o vinculo exato usado na criacao do pedido.

O catalogo `cad_cliente_vinculo_papeis` define:

| Codigo | Uso | Concede visibilidade atual |
|---|---|---:|
| `cadastrou` | fato de quem cadastrou | nao |
| `atende` | atendimento comercial | sim |
| `gerencia` | gestao da conta | sim |
| `apoio` | apoio comercial | sim |

O papel de negocio nao e `user_profiles.role` e nao concede privilegio Auth.

`cad_cliente_vendedores` recebe FK de papel, escopo opcional por propriedade,
vigencia e linhagem. `cad_cliente_areas_comerciais` relaciona cliente ou
propriedade a uma area com vigencia. Pessoa e area continuam em
`cad_pessoa_areas_comerciais`.

`cad_cliente_visibilidade_comercial_atual` deriva vinculos diretos e por area.
Ele e fonte relacional para futuras policies, nunca substituto da autorizacao
no backend e no banco.

## Ownership e dependencias

| Contrato | Proprietario | Consumidores |
|---|---|---|
| papeis e vinculo cliente/pessoa | `cadastros` | `pedidos`, `relatorios` |
| vinculo cliente/area e pessoa/area | `cadastros` | `pedidos`, `metas` |
| referencia do vinculo no pedido | `pedidos` | `expedicao`, `faturamento` |

## Chaves naturais e idempotencia

- papel: codigo normalizado;
- cliente/pessoa: cliente + propriedade global/especifica + pessoa + papel +
  inicio de vigencia;
- cliente/area: cliente + propriedade global/especifica + area + inicio;
- pessoa/area: pessoa + area + papel na area + inicio;
- historico: batch + linha + identidades relacionais do fato.

O banco bloqueia periodos ativos sobrepostos para a mesma relacao.

## Campos obrigatorios

- cliente, pessoa e papel no vinculo direto;
- cliente e area no vinculo regional;
- propriedade pertencente ao mesmo cliente, quando informada;
- status e atores;
- batch, linha e ator `Migracao Historica` para `excel_legado`;
- papel comercial ativo para novo vinculo operacional ativo.

## Campos opcionais

- propriedade, quando o vinculo vale para o cliente inteiro;
- inicio/fim de vigencia quando ausentes na fonte;
- referencia do vinculo no pedido historico, quando nao puder ser provada.

Ausencia permanece nula. O sistema nao escolhe vendedor, propriedade, area ou
data por inferencia silenciosa.

## Pendentes de revisao

- todo vinculo importado do Excel;
- pessoa nao resolvida ou sem papel comercial comprovado;
- area/regiao sem identidade canonica;
- sobreposicao ou conflito entre vendedores historicos;
- pedido antigo cujo vinculo exato nao puder ser provado.

Pendencia nao aparece nos read models atuais e nao concede visibilidade.

## Backfill

1. registros antigos de `cad_cliente_vendedores` recebem papel `atende`, pois
   essa era a semantica unica da tabela anterior;
2. origem nao classificada de registros preexistentes passa a `sistema`;
3. areas e vinculos pessoa/area existentes preservam status e vigencia;
4. nenhuma area de cliente e criada por inferencia;
5. pedidos existentes ficam sem `cliente_vendedor_vinculo_id` quando o vinculo
   exato nao pode ser provado.

## Integridade e auditoria

- FKs compostas impedem propriedade de outro cliente;
- pedido com referencia exige o mesmo cliente, vendedor e propriedade;
- novo vinculo ativo exige papel comercial vigente;
- periodos ativos duplicados ou sobrepostos sao bloqueados;
- relacoes temporais nao aceitam `DELETE` ou `TRUNCATE`;
- encerramento altera vigencia/status por futura RPC auditada;
- historico pendente nao pode ser promovido por update;
- tabelas e views sao relacionais, sem JSON de permissoes.

## Fora do escopo

- alterar RLS de clientes/pedidos para consumir o novo read model;
- criar tela ou RPC de manutencao/aprovacao dos vinculos;
- deduplicar clientes ou vendedores;
- importar dados reais do workbook;
- definir comissao ou campanha a partir do vinculo.

## Rollback

Antes de dados dependentes, restaurar o backup de teste e voltar ao commit
anterior a `0052`. O rollback manual remove views/triggers, FK do pedido,
tabela cliente/area e colunas/indices novos na ordem inversa.

Depois de pedidos referenciando vinculos, rollback destrutivo e proibido. Uma
migration de compatibilidade deve preservar a referencia e o historico.

## Consequencias

- as duas colunas do Excel deixam de disputar um unico campo;
- cliente pode ter varios vendedores e escopo por propriedade;
- regioes passam a relacionar cliente e equipe temporalmente;
- pedido novo pode registrar qual autorizacao comercial estava vigente;
- politica futura podera consultar uma fonte relacional unica.
