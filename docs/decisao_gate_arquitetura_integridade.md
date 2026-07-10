# Decisao - gate de arquitetura e integridade

Data: 2026-07-10

## Decisao central

O Elite System permanece um monolito modular em Next.js, Supabase e PostgreSQL. Nao sera dividido em microservicos nesta fase. A complexidade operacional ainda cabe em uma unica aplicacao e em uma unica transacao PostgreSQL, mas cada dominio deve possuir suas tabelas, suas RPCs de escrita e contratos estaveis para integracoes.

O objetivo nao e eliminar dependencias reais do negocio. O objetivo e impedir dependencia escondida, escrita cruzada sem contrato e relacao que dependa apenas da disciplina da tela.

## Regra de dependencia

Fluxo de escrita aprovado:

```text
pagina -> Server Action -> caso de uso/RPC auditada -> API do dominio -> tabelas do dominio
```

Fluxo de leitura aprovado:

```text
pagina -> modulo de consulta -> view/read model com RLS -> tabelas permitidas
```

Uma tela nao escreve em tabela. Um dominio nao deve conhecer o formato interno da tabela de outro dominio quando uma API interna estavel puder representar a operacao.

Operacoes compostas, como finalizar OP ou confirmar romaneio, continuam atomicas. A orquestracao pode coordenar varios dominios na mesma transacao, mas os efeitos de estoque, fiscal e financeiro devem migrar gradualmente para helpers internos pertencentes a esses dominios.

## Formas normais

Tabelas operacionais canonicas devem buscar 3FN:

- uma linha representa uma entidade ou evento bem definido;
- listas operacionais ficam em tabelas filhas, nao em texto ou JSON;
- identificadores relacionados usam FK tipada;
- campo repetido e derivavel so permanece quando existe motivo auditavel e constraint que impeca divergencia.

JSON continua permitido para linha bruta importada, payload externo, snapshot `before/after`, memoria de calculo, metadata de auditoria e cache de compatibilidade documentado. JSON nao pode ser a unica fonte de verdade de papeis, participantes, itens, lotes ou relacao que exija integridade referencial.

## Migration 0039

`0039_rls_direct_write_gate.sql`:

- remove policies legadas `FOR ALL` de PCP, romaneio, importacao e auditoria;
- mantem leitura para perfil ativo;
- revoga `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `REFERENCES` e `TRIGGER` de `authenticated` em todas as tabelas publicas;
- revoga acesso de tabela de `anon`;
- define o mesmo padrao restritivo para tabelas futuras criadas por `postgres`;
- preserva escrita operacional apenas por RPC `SECURITY DEFINER` auditada.

Autonomia inicial por checkbox continua existindo. Autonomia significa poder executar RPC autorizada, nunca poder contornar auditoria com DML direto.

## Migration 0040

`0040_relational_integrity_normalization.sql`:

- vincula `source_row_id` e `source_batch_id` por FK e valida a mesma linhagem;
- substitui a referencia textual de garantia MP por `lote_mp_id bigint` com FK, preservando `lote_mp_ref_legado` apenas para reconciliacao;
- cria `cad_pessoa_papeis` com vigencia e historico de ativacao;
- cria `pcp_op_cq_participantes` com uma linha por separador, conferente ou formulador;
- torna a unidade-base de estoque MP imutavel depois do primeiro movimento;
- adiciona FKs compostas para impedir combinacoes incoerentes entre lote/produto, pedido/item, romaneio/item, NF/item e OP/reserva/consumo;
- adiciona indices de suporte aos novos vinculos.

## Compatibilidade historica

`papeis_json`, `formuladores_json`, `separador_mp` e `conferente_mp` permanecem para compatibilidade e snapshot. Triggers expandem os valores para tabelas relacionais. A retirada desses campos so ocorrera depois da homologacao das telas que selecionarao pessoas por ID.

Garantias antigas sem lote resolvido aparecem em `cad_garantias_lote_mp_pendentes_vinculo`. Participantes de CQ ainda sem usuario/pessoa resolvido aparecem em `pcp_op_cq_participantes_pendentes_vinculo`. Dado legado incompleto fica visivel; o sistema nao inventa o vinculo.

## Divida arquitetural declarada

Ainda existem orquestradores SQL antigos que conhecem tabelas de mais de um dominio, principalmente:

- finalizacao de OP escrevendo movimentos de estoque;
- confirmacao/estorno de romaneio escrevendo movimentos de estoque;
- estorno pos-pagamento coordenando fiscal, estoque e metas.

Esses fluxos estao transacionais, auditados e protegidos por constraints, mas o proximo refactor deve extrair APIs internas de estoque, fiscal e metas. A mudanca sera feita por contrato e regressao, sem reescrever os fluxos de uma vez.

## Dependencias de software

Dependencias web deixam de usar `latest`. Versoes exatas e `pnpm` ficam declarados em `package.json` e verificados com lockfile congelado.

O CI passa a validar separadamente testes Python; install congelado, lint e build Next.js; e Supabase descartavel com migrations do zero, seed, lint SQL, smoke de integridade e geracao oficial dos tipos TypeScript do banco.

O arquivo de tipos sera incorporado ao cliente em commit proprio depois de gerado pelo CI. A maquina local nao consegue usar o gerador oficial enquanto o Docker estiver parado.
