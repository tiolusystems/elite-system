# Fórmulas e garantias

## Conciliar cálculos históricos do Excel

1. Acesse **Produção > Garantias > Conciliação do histórico**.
2. Confira produto, termo original, valores PP/PV e a linha de origem.
3. Quando a correspondência for segura, escolha **Classificar** e selecione o
   nutriente e as duas unidades nos catálogos governados.
4. Se houver dúvida, escolha **Manter pendente** e explique o motivo.
5. Se a linha for apenas cálculo auxiliar sem utilidade futura, escolha
   **Descartar como referência** e justifique.

A revisão preserva o valor exatamente como veio do Excel. Ela não transforma o
cálculo em garantia documental MAPA, garantia analisada de lote, resultado de OP
ou saldo de estoque. Essa promoção exige outro ato de negócio e outra fonte
documental. Nenhum termo ambíguo é classificado automaticamente.

## Finalidade

Este fluxo define o que será produzido, quais componentes serão necessários e
quais garantias o produto deve atender. Fórmula, garantia e resultado calculado
são históricos versionados: uma correção cria nova versão, sem alterar o fato
anterior.

## Pré-requisitos

- matéria-prima ativa, com SKU e unidade base;
- produto PA ou PI ativo;
- nutrientes e unidades aprovados nos cadastros técnicos;
- lotes de MP disponíveis para registrar resultados por lote;
- alçada para criar ou ativar fórmula e registrar garantias.

## Criar fórmula de produção

Toda nova fórmula operacional usa uma base única de **1 L de produto
produzido**. Isso significa que a quantidade de cada componente informa quanto
é necessário para produzir exatamente 1 L, nas unidades controladas:

- `kg/L produzido` para insumos medidos em massa;
- `L/L produzido` para insumos medidos em volume;
- `UN/L produzido` para componentes contados em unidades.

1. Acesse **Produção > Fórmulas**.
2. Acione **Nova versão**.
3. Selecione o produto PA ou PI.
4. Em **Finalidade da receita**, escolha **Produção operacional**.
5. Informe a justificativa da versão.
6. Para cada componente, escolha MP, PA ou PI.
7. Selecione o item pelo cadastro, nunca digitando seu identificador.
8. Informe a quantidade necessária para 1 L e selecione a unidade governada.
9. Salve a versão.
10. No histórico, informe o motivo e ative a versão que poderá abrir OP.

Criar ou ativar fórmula não reserva e não baixa estoque. A reserva acontece na
OP; a baixa ocorre somente na finalização da OP, com os lotes efetivamente
consumidos.

Fórmulas operacionais criadas antes desta regra continuam no histórico, mas não
são convertidas automaticamente. Para utilizá-las em uma nova OP, crie e ative
uma nova versão revisada na base de 1 L.

## Abrir uma OP pelo volume planejado

1. Acesse **Produção > Ordens e reservas**.
2. Selecione uma fórmula operacional ativa e revisada na base de 1 L.
3. Informe o **volume planejado (L)** da produção.
4. Escolha o tipo de OP e confirme a abertura.

O sistema calcula cada necessidade pela regra:

`quantidade do componente por litro × volume planejado da OP`

Exemplo: uma fórmula com `0,25 kg/L produzido`, em uma OP de `1.000 L`,
planeja `250 kg` daquele componente. A OP congela a versão da fórmula, a
quantidade por litro, o volume e o total calculado. Alterações futuras da
fórmula não mudam a OP já aberta.

## Reserva FIFO

1. Na OP aberta, acione **Reservar automaticamente por FIFO** em cada componente.
2. O sistema usa primeiro o lote disponível com entrada mais antiga.
3. Se um lote não cobrir toda a necessidade, o restante segue para o próximo.
4. Confira os lotes e quantidades reservados antes de iniciar a produção.

Na seleção manual, o primeiro lote aparece como **FIFO recomendado**. Ignorar
um lote mais antigo exige alçada específica e justificativa. O desvio fica
registrado na reserva e na auditoria. Lotes bloqueados, cancelados, esgotados ou
sem saldo não participam da sugestão.

## Criar fórmula e OP documental MAPA

1. Selecione **Documentação MAPA** na finalidade.
2. Informe produto, justificativa e observação documental.
3. Se necessário, registre a composição declarada. Ela não precisa refletir
   lotes ou variações reais de MP.
4. Salve a versão.

A fórmula MAPA não é cópia da fórmula de produção. Seus componentes declarados
não geram reserva ou consumo das MP usadas na produção. Depois da liberação do
PI pelo CQ, a emissão da OP MAPA gera simultaneamente uma Ordem de Envase. É a
Ordem de Envase que baixa o PI e as embalagens e gera os lotes de PA disponíveis
para romaneios.

## Sequência física obrigatória

1. A OP de produção usa a fórmula operacional.
2. Os lotes de MP são reservados.
3. Ao finalizar a produção, os lotes efetivamente usados são consumidos.
4. O resultado entra como PI e aguarda CQ.
5. Somente PI liberado pelo CQ pode seguir para envase.
6. A OP MAPA referencia o produto e dispara a Ordem de Envase na mesma emissão.
7. A Ordem de Envase informa lote PI de origem, apresentação de destino e embalagens.
8. O documento impresso traz campos para assinaturas físicas dos operadores.
9. A Ordem é emitida pelo usuário autenticado e registra a identificação da sessão.
10. A finalização baixa PI e embalagens sem consumir novamente as MP produtivas.
11. A Ordem de Envase gera os lotes PA vinculados à OP MAPA e disponíveis para romaneio.

## Conteúdo da Ordem de Envase

- OP MAPA de origem;
- lote PI de origem;
- lote ou lotes PA de destino;
- apresentação e relação de embalagens;
- campos para assinaturas físicas dos operadores;
- início e fim da operação;
- emissor, data, hora e terminal de emissão.

Terminal, IP e geolocalização pertencem ao controle global de sessões do Elite
System. A Ordem de Envase apenas referencia o evento auditável da sessão do
usuário que a emitiu.

## Registrar garantia declarada do produto

1. Acesse **Produção > Garantias**.
2. Selecione produto, nutriente e regra: mínimo, máximo, faixa ou declarado.
3. Informe valor e unidade usando os catálogos governados.
4. Informe fonte, vigência, documento e justificativa.
5. Registre a versão.

Nova declaração substitui a referência vigente sem apagar a declaração anterior.

## Registrar garantia de lote de MP

1. Selecione o lote real de matéria-prima.
2. Selecione nutriente e unidade.
3. Informe valor, fonte, data de referência, documento e justificativa.
4. Registre a análise.

Fornecedor e laboratório exigem documento de referência. Garantia manual exige
autor e justificativa auditável.

## Cálculo na OP

Depois que a OP é finalizada, o sistema usa os lotes e quantidades efetivamente
consumidos. Quando a mesma MP vier de vários lotes, cada garantia participa
proporcionalmente à quantidade consumida daquele lote. O resultado é comparado
à garantia vigente do produto e fica versionado na OP.

Resultado ausente ou inconclusivo não deve ser inventado. O lote gerado pode
permanecer bloqueado para análise, reprocessamento, descarte ou liberação
auditada.

## Rastreabilidade

O caminho auditável é:

`fórmula de produção -> OP -> reserva MP -> consumo MP -> PI -> CQ -> OP MAPA/envase -> baixa embalagem -> lote PA -> romaneio`

## Erros operacionais

- produto não aparece: revise situação do cadastro;
- MP não aparece: revise SKU, situação e classificação;
- nutriente ou unidade não aparece: o catálogo ainda não está ativo;
- fórmula sem componente: produção operacional exige ao menos um item;
- documento obrigatório: informe laudo, certificado ou registro;
- sem alçada: solicite a permissão ao administrador.

## Limitações atuais

- esta entrega governa a criação e consulta; a simulação prévia de formulação e
  custo será uma ferramenta separada, sem alterar a fórmula publicada;
- o fluxo estrutural de OP MAPA e Envase já exige PI liberado, composição de
  embalagens aprovada e geração governada dos lotes PA; cancelamento e estorno
  específicos da Ordem de Envase serão tratados em evolução própria;
- o primeiro filtro gerencial por família foi incorporado aos relatórios de
  vencimento e reprocessamento; movimentos e produção ainda serão ampliados;
- fórmulas combinadas por garantia-alvo ainda dependem de regra funcional futura;
- custos por lote e DIFAL pertencem ao bloco de custo de MP, não à garantia.
