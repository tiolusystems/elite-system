# ORD-01 - Fase 1E - Unidade comercial de precificacao

## Decisao

A unidade comercial pertence ao item versionado da lista de preco, nao a apresentacao fisica. Uma mesma apresentacao pode ser coberta por listas ou versoes diferentes em litro, quilograma ou unidade, conforme a regra comercial vencedora.

Cada item generico congela `unidade_precificacao_id` do catalogo `cad_unidades_medida` e `quantidade_unidade_precificacao_por_apresentacao`. O preco generico e inteiro em centavos de BRL por essa unidade. A quantidade precificavel e sempre `quantidade_apresentacoes x fator_por_apresentacao`.

## Compatibilidade

Os contratos BRL/L das fases 1A a 1D permanecem legados e consultaveis. A migration normaliza conteudo BRL/L existente quando a apresentacao possui capacidade positiva conhecida, congelando unidade `L`, fator e preco generico identico ao preco legado. Conteudo antigo sem fator seguro permanece consultavel, mas falha fechado no resolvedor generico.

O XLSX atual continua R$/L. A entrada legada aceita somente por compatibilidade e, antes da persistencia, e normalizada para unidade `L`, fator atual positivo da apresentacao e espelho exato entre preco legado e preco generico. A criacao operacional posterior a 0129 nao produz item sem unidade ou fator. Para `kg`, `un` ou outra unidade cadastrada, o campo legado por litro fica nulo e nao pode ser reutilizado como preco de outra unidade.

Um item sem unidade e fator somente e reconhecido como entrada legada quando todas as linhas de preco informam `valor_centavos_por_litro` e nenhuma informa o campo generico. Preco generico sem unidade e fator e bloqueado; o sistema nao infere `L` a partir do preco.

## Normalizacao de checksum de publicacao

Quando a migration 0129 normaliza deterministicamente uma versao BRL/L ja publicada, ela preserva a identidade da publicacao, `published_at`, ator, lifecycle e todos os fatos comerciais. Somente o `conteudo_hash` e recomposto a partir do documento canonico posterior a evolucao de schema. O bypass temporario do guard append-only ocorre exclusivamente dentro desse bloco da migration e e restaurado tambem em caso de erro; nao ha republicacao, evento de lifecycle novo ou mutacao de regra de negocio.

## Historico e fronteira

Nao ha conversao automatica entre unidades. O fator e informado no contexto versionado da lista e o snapshot do pedido congela unidade, fator e preco resolvido. O resolvedor consome exclusivamente o fator congelado no item da versao publicada; alteracoes futuras de cadastro ou embalagem nao reinterpretam lista, pedido ou snapshot. Esta tranche nao implementa preco praticado, desconto, credito, aprovacao, comissao ou calculo monetario do pedido.
