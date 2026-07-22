# Elite System - estado atual

Atualizado em: 2026-07-22

## Referencia vigente

- branch: `feature/0044-production-module-release`;
- ultima entrega publicada: continuidade de leitura RLS restaurada no commit
  `eb5a218`, sobre Pessoas e vinculos `8ae5904`;
- entrega atual: Produção liberada no staging para validação de negócio, com
  rótulos PT-BR centralizados em Fórmulas, Garantias, Ordens e CQ e manual
  contextual da cadeia MP -> PI -> envase -> PA;
- ultima migration validada em PostgreSQL descartável: `0084_complete_customer_master_data.sql`;
- ultima migration no staging confirmada por ledger: `0082_stock_product_packaging_drilldown.sql`;
- ambiente ativo: Supabase local para teste e Supabase staging para
  homologacao;
- publicacao externa: staging ativo em
  `https://elite-system-staging.vercel.app`;
- cloud: frontend staging na Vercel e PostgreSQL staging no Supabase, sem dados
  operacionais reais;
- GitHub: codigo e documentacao somente; push depende de autorizacao.

## Tarefa concluida mais recente

Conciliação de garantias históricas:

- cálculos PP/PV do Excel passam a ter fonte relacional própria, vinculada ao
  lote de migração e à linha original;
- revisão classifica nutriente e unidades por IDs governados, ou mantém a linha
  pendente/descartada com justificativa;
- decisões são append-only e auditadas; nenhuma delas promove automaticamente
  garantia MAPA, garantia de lote, resultado de OP ou saldo;
- migration 0074 e smoke transacional foram aprovados somente em containers
  descartáveis `elite-validation-*`; a 0074 foi publicada e aplicada
  isoladamente no staging, com health-check saudável.

## Tarefa concluída em validação local

DEC-013 - reserva FIFO governada:

- a OP pode reservar automaticamente um componente nos lotes mais antigos;
- falta de saldo em um lote distribui a necessidade pelos lotes seguintes;
- escolha manual fora do FIFO exige alçada específica e justificativa;
- a decisão e a ordem FIFO ficam persistidas e auditadas;
- uma trava transacional por componente impede duas reservas concorrentes de
  decidirem sobre a mesma disponibilidade simultaneamente;
- instalação limpa 0001 -> 0076 e smoke transacional foram aprovados somente no
  container e volume descartáveis `elite-validation-0076-clean`;
- migration 0076 aplicada isoladamente e confirmada no ledger do staging;
- frontend compilado localmente, mas o novo Preview não foi promovido porque a
  Vercel falhou antes do build com `Resource provisioning failed`; o deployment
  estável anterior permanece saudável e conectado ao backend de staging.

## Tarefa atual

Recuperação transversal de UX e ficha completa de Clientes:

- o shell autenticado passa a ser a única fonte de cabeçalho, marca, menu,
  ambiente, usuário e rodapé;
- todas as rotas operacionais publicadas possuem manual contextual centralizado;
- Clientes passa a ter consulta por seções para identificação, documentos,
  estabelecimentos, propriedades, endereços, contatos, comercial, crédito e
  histórico, sem transformar o cadastro em um formulário único;
- crédito permanece pertencendo ao Financeiro e somente é consultado em
  Cadastros;
- a migration 0084 é integralmente aditiva, mantém escrita somente por RPC e
  foi aprovada em instalação limpa 0001 -> 0084 e upgrade 0083 -> 0084 somente
  em containers e volumes `elite-validation-*`;
- staging somente será atualizado depois de gates técnicos, ledger controlado
  e smoke autenticado.

## Entrega industrial anterior

DEC-013 - custo direto industrial por camadas:

- entradas da mesma MP/lote com preços diferentes permanecem separadas;
- uma OP gera um único produto e lote PI;
- perda de processo e perda de estoque possuem fatos e custos distintos;
- PI recebe custo das MP; PA recebe PI mais embalagens do envase;
- custos operacionais e indiretos permanecem fora do escopo;
- instalação limpa e smoke funcional da migration 0077 foram aprovados apenas
  em `elite-validation-0077-final`, com container e volume próprios.
- migration 0077 aplicada isoladamente no staging e confirmada no ledger;
- backend do staging saudável; o frontend estável ainda exibe o release
  `bf136b3` e aguarda promoção do commit `49518b7`.

## Próxima tarefa

Homologar visualmente no staging o shell unificado, os manuais contextuais e a
ficha completa de Clientes; depois retomar a sequência operacional aprovada sem
antecipar a PWA.

## Entrega anterior

DEC-013 - escala operacional da fórmula:

- novas fórmulas de produção usam base explícita de 1 L;
- componentes aceitam somente kg/L produzido, L/L produzido ou UN/L produzido;
- a OP exige volume planejado em litros e congela quantidade por litro, volume,
  unidade e total calculado;
- fórmulas legadas permanecem legíveis, sem conversão silenciosa, e exigem nova
  versão revisada antes de abrir OP;
- a OP MAPA permanece documental e continua sendo emitida com a Ordem de Envase.

Validacao com recorte real do Tio Lu System:

- workbook real analisado e mantido fora do Git;
- banco PostgreSQL isolado `elite-validation-real-production` reconstruido da
  migration 0001 ate a 0072, sem tocar runtime ativo, staging ou producao;
- recorte industrial real rastreado ate workbook, aba e linha, com uma MP,
  duas entradas de lote, dez consumos e uma OP historica;
- reconciliacao de entradas, consumos e saldo aprovada, com um lote esgotado e
  outro disponivel; valores reais permanecem somente no ambiente descartavel;
- natureza PA/PI, grupo relacional e codigo operacional do produto permanecem
  pendentes de revisao; nenhum valor ausente foi promovido como fato;
- a carga real revelou e a migration 0072 corrige a validacao de linhagem entre
  `source_rows`, `source_tables`, `source_workbooks` e `migration_batches`;
- a migration 0072 foi publicada, aplicada isoladamente no staging e confirmada
  no ledger; o health-check permaneceu saudavel e nenhum frontend foi alterado;
- uma formula historica do recorte real foi preservada como `pending_review`,
  sem ativacao automatica;
- garantias sem classificacao inequivoca de nutriente, unidade e natureza foram
  registradas como pendencias; nenhuma garantia ambigua foi promovida;
- o risco de superestimação do cálculo anterior foi corrigido pela migration
  0073: o resultado passa a fechar massa/volume dos lotes consumidos contra o
  CQ final, com densidade versionada por lote;
- lote sem garantia ou sem densidade necessária gera pendência explícita e
  valor calculado nulo; nenhuma estimativa silenciosa é aceita;
- instalação limpa 0001 -> 0073, upgrade 0072 -> 0073, smoke SQL, ESLint,
  TypeScript, build e 25 testes dirigidos foram aprovados em ambientes
  descartáveis;
- a 0073 foi publicada, aplicada isoladamente no staging e confirmada no
  ledger; o frontend `bf136b3` foi promovido para o domínio estável de
  homologação, com health-check saudável e validação responsiva sem rolagem
  horizontal em 390 x 844.

Romaneio consultivo e retomada da cadeia industrial:

- Romaneio `3b12101` publicado no staging com pedido, seleção individual de
  produtos, quantidade parcial, prévia sem gravação, botão explícito de
  rascunho, consulta contextual de lotes e manual por tarefa;
- homologação do Romaneio permanece provisória até o ensaio com dados reais;
- Produção passou de bloqueada para Validação de negócio com leitura e escrita
  por evento auditado no rollout do staging;
- códigos internos de unidade, componente e resultado permanecem estáveis no
  banco, mas deixam de aparecer crus nas telas operacionais de Produção;
- nenhuma migration ou regra de cálculo foi criada: garantias continuam sendo
  calculadas no CQ a partir dos lotes efetivamente consumidos.
- cenário sintético no staging criou e ativou a fórmula operacional v1 e abriu
  a OP `OP-20260721-0000001`; a reserva foi corretamente bloqueada porque ainda
  não existe lote de MP com saldo, sem criação artificial de estoque;
- o manual de Produção registra a sequência operacional e a separação entre a
  fórmula que consome MP e gera PI e a fórmula MAPA documental que dispara o
  envase para gerar PA.

Continuidade de leitura RLS `0067`:

- `authenticated` recuperou somente `EXECUTE` no helper de leitura
  `current_actor_id()`;
- `anon` e `PUBLIC` permanecem negados;
- escrita direta continua revogada;
- a migration foi aplicada e validada no staging antes da retomada do UX-01C.

Entrega funcional anterior:

UX-01C.3 - Pessoas e vinculos comerciais:

- homonimos sao revisados, confirmados com justificativa e auditados;
- codigo legado possui unicidade normalizada e criacao concorrente protegida;
- aliases iguais podem pertencer a pessoas distintas sem repeticao interna;
- areas comerciais usam relacionamentos por ID e vigencia temporal;
- desativacao e reativacao preservam o historico e nao reabrem vinculos;
- interface PT-BR oferece consulta, filtros, criacao, edicao e gestao dos
  vinculos sem expor enums ou erros tecnicos;
- instalacao limpa, upgrade, smoke e concorrencia foram validados somente em
  projetos descartaveis `elite-validation-*`.

Entrega institucional paralela - assinatura da desenvolvedora:

- assinatura reutilizavel `by ☧ SYSTEMS` aplicada exclusivamente nos creditos
  de desenvolvedor ja existentes nos rodapes publico e autenticado;
- identidade, paleta, tipografia, navegacao, favicon e componentes operacionais
  do Elite System preservados;
- nenhum ativo raster ou SVG, dependencia, banco, migration, Supabase, regra de
  negocio ou seguranca foi alterado;
- teste de contrato, ESLint, build Next.js e verificacao visual desktop/mobile
  aprovados; captura do rodape autenticado depende de sessao real e nao foi
  obtida por contorno de autenticacao;
- nenhum rebranding foi realizado.

Entrega anterior:

UX-01C.4 - Tipos de insumo e classificacao de materias-primas:

- catalogo relacional, FK opcional, RLS e seis RPCs auditadas na migration 0063;
- texto legado preservado e bloqueado para novas escritas operacionais;
- nenhuma classificacao historica foi inferida;
- fila de revisao explicita para materias-primas sem decisao humana;
- tela PT-BR permite criar, editar, ativar, inativar e classificar por ID;
- instalacao limpa, upgrade e smoke ocorreram somente em ambiente descartavel;
- runtime local ativo e dados existentes permaneceram intactos.
- unidade base passou a ser enviada por FK de catalogo;
- SKU possui unicidade normalizada e protecao concorrente no banco;
- homonimos exigem revisao, confirmacao motivada e auditoria.

Entrega de base:

UX-01C.1 - Central de Cadastros:

- `/cadastros` organiza os dados mestres em oito grupos funcionais;
- busca, grupo ativo, retorno a visao geral e acao contextual usam a mesma rota;
- somente o conteudo do grupo selecionado permanece visivel;
- os formularios existentes preservam as Server Actions e contratos auditados;
- os estados da central usam linguagem operacional;
- responsividade validada nas resolucoes previstas, sem rolagem horizontal;
- nenhuma migration, RPC, RLS, tabela ou regra de negocio foi alterada;
- nenhum dado operacional, workbook ou captura foi adicionado ao Git.

## Validacao desta tarefa

Fluxo PI -> OP MAPA -> Envase -> PA em validação local:

- migrations propostas `0069` e `0070` separam OP MAPA documental da Ordem de
  Envase operacional;
- OP MAPA não pode mais ser criada isoladamente pelo fluxo genérico de OP;
- emissão conjunta exige fórmula MAPA ativa, lote PI liberado, apresentação do
  mesmo produto e composição de embalagens aprovada;
- emissão reserva PI sem baixar estoque; embalagens são reservadas por lote;
- início exige reservas integrais; finalização baixa PI e embalagens e gera um
  ou mais lotes PA na mesma transação;
- documento imprimível registra OP MAPA, PI origem, PA destino, embalagens,
  campos de horários e assinaturas físicas, usuário, data, hora e terminal;
- login, IP, terminal ampliado e geolocalização permanecem responsabilidade
  global de Segurança/Sessões, sem múltiplos logins no Envase;
- relatórios de estoque permitem filtrar MP, PI e PA;
- instalação limpa `0001 -> 0070`, upgrade `0068 -> 0070` e smoke transacional
  foram aprovados somente em containers `elite-validation-*`;
- runtime local ativo, staging e produção não receberam as migrations;
- interface, TypeScript, ESLint, build e testes dirigidos foram aprovados; falta
  homologação visual e funcional antes de commit ou publicação.

Pacote `0068` em execucao, ainda nao homologado:

- contrato de produto, apresentacao e embalagem limitado ao dominio Cadastros;
- embalagens novas exigem unidade `UN` e capacidade positiva em litros;
- necessidade da embalagem e derivada numericamente em `UN/L`;
- versoes, revisoes, remocoes e ativacoes preservam historico append-only;
- formula, OP, FIFO, custos e garantias por lote permanecem fora da `0068`;
- instalacao limpa `0001 -> 0068` aprovada em `elite-validation-0068`;
- upgrade isolado `0067 -> 0068` aprovado em
  `elite-validation-0068-upgrade`;
- smoke transacional aprovado nos dois ambientes com
  `PG_VALIDATE_0068_WITH_SMOKE_OK` e `ROLLBACK`;
- runtime ativo, staging e producao nao foram migrados, resetados ou usados
  nos testes destrutivos;
- 16 testes de contrato/UX, ESLint, TypeScript e build Next.js passaram;
- estados de carregamento, vazio, erro, sucesso e sem permissao possuem contrato
  visual/operacional no fluxo;
- o manual operacional do fluxo foi criado;
- cenario funcional local concluido com produto, embalagem, apresentacao e
  composicao sinteticos;
- versao de composicao criada, aprovada e ativada, com `0,2 UN/L` comprovado
  para embalagem de 5 litros;
- capturas aprovadas tecnicamente em `1920 x 1080`, `1366 x 768`,
  `768 x 1024`, `390 x 844` e `360 x 800`, sem rolagem horizontal;
- defeito de compressao dos campos de composicao foi corrigido antes do gate;
- manuais de Produtos/Apresentacoes/Embalagens e Unidades/Conversoes integram
  o mesmo pacote documental.

Validacao concluida anterior:

- smoke visual de Pessoas revelou regressao de leitura apos a `0066`;
- causa confirmada: `authenticated` perdeu `EXECUTE` sobre
  `current_actor_id()`, helper exigido pelas policies RLS de leitura;
- frontend `f70bfbe` foi revertido no staging conforme gate de rollback;
- `0067` restaura somente o helper autenticado e amplia o gate para dependencias
  de policies;
- instalacao limpa e upgrade `0066 -> 0067` aprovados em projetos, containers
  e volumes independentes `elite-validation-*`;
- gates finais aprovados: escrita direta continua negada e leitura autenticada
  voltou a funcionar nos dominios representativos;
- detalhes: `docs/auditoria_rls_continuidade_leitura_0067.md`.

Validacao anterior da `0066`:

- auditoria somente leitura do staging: 132 tabelas publicas, todas com RLS,
  zero escrita direta para `anon`, `authenticated` ou `PUBLIC` e zero politica
  permissiva de escrita residual;
- instalacao limpa `0001` a `0066` e upgrade `0065 -> 0066`: aprovados somente
  em projetos `elite-validation-*`;
- gate de metadados: aprovado;
- sweep zero-grant: 79 de 79 RPCs negadas com auditoria;
- Data API: 99 tentativas de escrita em 11 dominios e tres contextos, sem
  alteracao dos fingerprints;
- smoke de RPC governada com permissao valida: aprovado;
- ESLint e build Next.js: aprovados;
- staging recebeu exclusivamente a migration 0066; a auditoria final read-only,
  o gate SQL, o health-check e a resposta da tela de login foram aprovados;
- detalhes: `docs/auditoria_rls_escrita_direta_0066.md`.

Validacao anterior da UX-01C.3:

- smoke SQL 0065 em instalacao limpa e upgrade: aprovado;
- lock concorrente: uma criacao persistida e a concorrente recusada apos
  recalculo de candidatos;
- lint PostgreSQL: aprovado;
- ESLint, TypeScript, build Next.js e 46 testes dirigidos: aprovados;
- desktop `1366 x 768` e mobile `390 x 844`: aprovados sem rolagem horizontal;
- runtime Supabase ativo nao foi parado, resetado, migrado ou alterado;
- capturas de homologacao permanecem fora do repositorio.

## Estado funcional resumido

- `core` e `seguranca`: operacionais no banco de teste;
- `cadastros`: primeira fatia industrial publicada no staging e aguardando
  homologacao funcional de Luciano;
- `pcp`: Formulas, Garantias, Ordens, Reservas, CQ, Finalizacao, Lotes, Estoque
  e Transformacoes separados em telas operacionais e publicados no staging;
- `estoque`: consulta operacional por lote e movimentos auditados integrados ao
  fluxo de OP; ativacao do saldo real continua dependente da `DEC-012`;
- contratos relacionais `DEC-006` a `DEC-011`: implementados;
- analise, classificacao e homologacao funcional do Excel: disponiveis
  localmente e sem escrita;
- mapa visual de implantacao: disponivel em `/modulos`;
- decisoes funcionais de Luciano: ainda nao preenchidas; I2 bloqueada;
- carga bruta, simulacao, aplicacao e reconciliacao: pendentes;
- homologacao cloud: ambiente ativo, com login e banco declarando `staging`;
- `expedicao`: Bloco 6 publicado; homologacao encontrou a falha quantitativa e
  fica bloqueada ate a publicacao e revalidacao da 0060;
- producao cloud: continua bloqueada por homologacao, backup, monitoramento,
  migracao historica ensaiada, seguranca externa e piloto;
- Auth: convite e troca de email governados; MFA obrigatorio ainda pendente.

O estado executavel de maturidade permanece no PostgreSQL e na tela
`/modulos`. Este resumo nao substitui o ledger de rollout.

## Proxima tarefa

Fechar o contrato de calculo de garantias por balanco de massa/volume, com
unidades canonicas, densidade, tratamento explicito de lote sem garantia e
snapshot auditavel dos insumos efetivamente consumidos.

## Tarefa seguinte

Reexecutar com dados reais revisados o fluxo Formula operacional -> OP ->
reserva -> CQ -> garantia calculada -> lote PI. Depois homologar Envase + OP
MAPA -> baixa de PI e embalagens -> lote PA e os relatorios separados por MP,
PI e PA. Veiculos e logistica deixam de ser prioridade imediata.

## Sequencia vigente

Concluir o UX-01C como um unico macrociclo, sem gates intermediarios entre
Clientes, Pessoas, Materias-primas, Produtos, Embalagens, Logistica, Tecnicos e
Validacao. Depois da autorizacao estrutural: migrations proporcionais por
ownership, implementacao integrada, testes dirigidos e gate visual conjunto.
UX-01D a UX-01H permanecem posteriores e nao devem ser iniciados.

## Tarefas temporariamente adiadas

- Suporte S0 (`DEC-001`);
- MFA TOTP (`DEC-002` a `DEC-004`);
- implementacao dos perfis combinaveis (`DEC-005`).

Essas tarefas permanecem autorizadas ou pendentes conforme
`docs/02_DECISOES_PENDENTES.md`, mas nao bloqueiam `C1`, `F1` ou `H1`.

## Regra de manutencao

Ao fechar qualquer tarefa, substituir neste arquivo:

- tarefa concluida mais recente;
- validacao e resultado;
- proxima tarefa;
- tarefa seguinte;
- nova decisao bloqueante, quando houver.

Nao transformar este documento em diario. O historico pertence ao Git.
