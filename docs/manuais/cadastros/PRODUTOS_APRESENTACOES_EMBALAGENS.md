# Produtos, apresentacoes e embalagens

## Estado deste manual

Manual do fluxo validado funcionalmente e visualmente no ambiente local com a
migration `0068`. Ele somente se torna operacional oficial depois do commit,
publicacao controlada, aplicacao exclusiva da migration e smoke no staging.

## Conceitos

- **Produto**: identidade tecnica/comercial do PA ou PI, com codigo entre
  `0001` e `9999`, nome, grupo, validade, densidade e dados regulatorios.
- **Embalagem**: recipiente fisico governado, sempre controlado em unidade
  (`UN`) e com capacidade positiva em litros.
- **Apresentacao**: relacao entre um produto e uma embalagem. E o item vendavel.
- **Composicao da embalagem**: lista versionada de insumos de embalagem,
  normalizada em unidades por litro de produto acabado (`UN/L`).

Um produto de 5 L e outro de 20 L nao devem ser duplicados apenas por causa da
embalagem. O sistema mantem um produto e cria duas apresentacoes, cada uma
ligada a sua embalagem. Novo produto somente e criado quando sua identidade
tecnica, regulatoria ou comercial for realmente diferente.

## Permissoes

Consulta depende de acesso autenticado a Cadastros. Criacao, alteracao por eixo,
inativacao, reativacao, revisao e ativacao usam permissoes atomicas proprias e
RPCs auditadas. Ausencia de alcada deve bloquear a acao sem exibir erro tecnico.

## Consultar e alterar um produto

1. Acesse **Cadastros > Produtos e apresentacoes**.
2. Pesquise pelo codigo ou nome.
3. Abra o produto desejado.
4. Altere somente o painel correspondente:
   - identidade: codigo, nome e grupo;
   - dados tecnicos: densidade e validade;
   - dados regulatorios: MAPA, NCM, IBAMA e ADS;
   - situacao: ativar ou inativar com motivo.
5. Informe o motivo da alteracao.
6. Confirme a operacao e verifique a mensagem de sucesso.

O produto nao e apagado para corrigir cadastro. Alteracoes ficam registradas
com autor, data, eixo alterado, estado anterior e estado posterior.

## Cadastrar um produto

1. Acesse **Cadastros > Produtos e apresentacoes**.
2. Acione **Novo produto**.
3. Informe codigo de quatro digitos e nome.
4. Selecione um grupo ativo, quando aplicavel.
5. Salve.
6. Abra o produto criado para completar dados tecnicos e regulatorios.

O banco recusa codigo duplicado mesmo quando a diferenca for apenas formatacao,
espaco ou caixa. Codigo e nome nao devem ser inventados para completar historico.

## Cadastrar uma embalagem

1. Acesse **Cadastros > Embalagens e conversoes**.
2. Acione **Nova embalagem**.
3. Informe descricao e capacidade em litros.
4. A unidade operacional sera `UN`.
5. Indique se a embalagem controla estoque.
6. Quando controlar estoque, selecione a materia-prima correspondente por ID.
7. Salve e abra a embalagem criada.

Uma embalagem operacional sem capacidade positiva nao pode ser criada. Materia-
prima inativa permanece legivel em vinculo historico, mas nao pode ser escolhida
em novo vinculo.

## Criar uma apresentacao

1. Abra **Produtos e apresentacoes**.
2. Selecione o produto.
3. Acione **Nova apresentacao**.
4. Selecione uma embalagem ativa.
5. Informe o codigo unico da apresentacao.
6. Salve.

O relacionamento e gravado pelos IDs do produto e da embalagem. Nome digitado
livremente nao substitui o relacionamento. Para vender o mesmo produto em outra
capacidade, crie outra apresentacao; nao duplique o produto.

## Criar e ativar uma composicao de embalagem

1. Abra a embalagem.
2. Crie uma nova versao informando vigencia, tara, cubagem e justificativa.
3. Confira o valor calculado de embalagem por litro:
   - 5 L = `0,2 UN/L`;
   - 20 L = `0,05 UN/L`.
4. Inclua os componentes selecionando materias-primas ativas.
5. Informe cada quantidade numerica em `UN/L`.
6. Envie a versao para aprovacao ou rejeicao, sempre com motivo.
7. Ative somente uma versao aprovada e completa.

Revisao, remocao de componente e ativacao sao eventos append-only. O sistema nao
sobrescreve a versao original. Uma correcao estrutural exige nova versao.

## Estados esperados

- **Vazio**: orienta criar o primeiro registro sem mostrar tabela tecnica.
- **Carregando**: preserva o espaco da tela e informa a operacao em andamento.
- **Sucesso**: identifica o registro e a acao concluida.
- **Erro**: apresenta mensagem operacional em PT-BR, sem SQL, RPC ou Supabase.
- **Sem permissao**: informa que a alcada nao permite a acao.
- **Inativo**: continua consultavel, mas nao aparece em novos relacionamentos.

## O que nao pertence a esta entrega

- formula de produto em `kg/L` ou `L/L`;
- selecao FIFO de lotes;
- custo por lote;
- garantias por lote;
- reservas e consumo da OP;
- arredondamento e planejamento integral de embalagens na producao;
- clonagem integral de produto;
- PDF, assinatura eletronica ou integracao com `gov.br`.

Esses fluxos terao pacotes e manuais proprios nas fases de Formulas, Ordens,
Qualidade, Pedidos e Romaneio.

## Cenario local validado

Em 20/07/2026 foi executado, somente com dados sinteticos:

1. produto `9068 - HML Produto UX0068`;
2. embalagem `HML Embalagem UX0068 5 L`;
3. apresentacao comercial `9068-5L`;
4. versao de composicao criada, revisada, aprovada e ativada;
5. necessidade derivada de `0,2 UN/L` para a embalagem de 5 litros;
6. componente sintetico registrado em `0,2 UN/L`.

O fluxo foi conferido em `1920 x 1080`, `1366 x 768`, `768 x 1024`,
`390 x 844` e `360 x 800`, sem rolagem horizontal. As capturas permanecem fora
do Git.
