# ADR-014 - Fluxo PI, CQ, PA e OP MAPA

## Contexto

Fórmula de produção e fórmula MAPA possuem finalidades diferentes. Usar a
mesma composição ou permitir que a OP MAPA movimente estoque mistura fato
industrial com documentação regulatória.

## Decisão

1. A fórmula de produção governa a OP física e o consumo dos lotes de MP.
2. A primeira saída da produção é PI.
3. O PI somente pode ser envasado depois de liberado pelo CQ.
4. A OP MAPA é documental e funciona como gatilho para a emissão simultânea de
   uma Ordem de Envase operacional vinculada.
5. A fórmula MAPA é documental, independente da fórmula real de produção.
6. A composição MAPA pode declarar componentes sem vínculo obrigatório com os
   lotes efetivamente usados.
7. A OP MAPA não consome novamente as MP da fórmula produtiva.
8. A Ordem de Envase vinculada à OP MAPA baixa o PI liberado e as embalagens.
9. A Ordem de Envase gera os lotes PA, sempre rastreados até a OP MAPA que a
   originou, e esses lotes alimentam o estoque disponível para romaneio.
10. Relatórios gerenciais devem permitir filtro explícito por PI e PA.

## Documento operacional de envase

A Ordem de Envase é emitida junto com a OP MAPA e deve apresentar:

- número e vínculo da OP MAPA;
- lote de origem PI, previamente liberado pelo CQ;
- lote ou lotes de destino PA;
- produto e apresentação de destino;
- relação das embalagens e respectivas quantidades;
- campos para assinatura física dos operadores no documento impresso;
- data e hora de início e de fim da operação;
- usuário emissor, data/hora de emissão e terminal emissor.

As assinaturas dos operadores são físicas e não são substituídas por credenciais
digitais. A Ordem de Envase é emitida por um único usuário autenticado e mantém
referência auditável ao evento de emissão. Identidade, sessão, terminal, endereço
IP e geolocalização são governados globalmente pelo domínio Segurança/Sessões;
não constituem um fluxo de aprovação próprio do envase.

## Invariantes

- OP física não pode disponibilizar PA antes do CQ do PI;
- envase não pode consumir PI bloqueado, reprovado ou sem saldo disponível;
- baixa de embalagem ocorre no envase, não na produção do PI;
- componentes declarados na fórmula MAPA não geram baixa das MP produtivas;
- lote PA nasce identificado pela Ordem de Envase e pela OP MAPA de origem e
  somente então pode alimentar romaneio;
- emissão da OP MAPA e criação da Ordem de Envase são atômicas;
- início, fim e identificação do emissor não podem ser retroeditados;
- a mesma reserva de PI ou embalagem não pode ser consumida duas vezes;
- relatórios não podem somar PI e PA sem expor a família filtrada;
- toda ligação produção -> PI -> CQ -> OP MAPA/envase -> PA é auditável.

## Impacto técnico pendente

O schema atual já distingue receita `producao` e `mapa`, possui PI, PA, CQ,
movimentos e OP documental. Ainda é necessário endurecer a máquina de estados
e criar o vínculo transacional que obrigará a sequência descrita nesta decisão,
incluindo baixa de embalagem e criação do lote PA pela OP MAPA.
Essa alteração exigirá migration, testes de concorrência e smoke completo antes
de staging.
