# Manuais operacionais do Elite System

## Objetivo

Os manuais acompanham a construcao do sistema. Uma tela ou fluxo nao pode ser
considerado concluido quando a operacao homologada nao estiver documentada.

## Organizacao

Cada entrega deve possuir, quando aplicavel:

1. **manual por processo**, explicando a tarefa do inicio ao resultado;
2. **referencia por tela**, explicando campos, estados e acoes;
3. **permissoes**, indicando quem pode consultar ou alterar;
4. **excecoes**, explicando cancelamento, estorno, reativacao e correcao;
5. **evidencia**, com rota, resultado esperado e limitacoes vigentes.

O manual descreve somente comportamento existente e homologado. Funcionalidade
planejada deve aparecer identificada como futura, sem instrucoes que levem o
operador a acreditar que ela ja esta disponivel.

## Gate documental por tela

Antes da homologacao final, confirmar:

- finalidade e publico da tela;
- caminho de navegacao;
- pre-requisitos e permissoes;
- procedimento de consulta, criacao e alteracao;
- campos obrigatorios e relacionamentos;
- estados de sucesso, vazio, erro, bloqueio e sem permissao;
- comportamento desktop, notebook e mobile;
- procedimento de cancelamento, inativacao ou reversao, quando existir;
- limitacoes e proxima evolucao;
- versao/commit em que o comportamento foi validado.

## Indice vigente

| Dominio | Manual | Estado |
|---|---|---|
| Cadastros | `cadastros/PRODUTOS_APRESENTACOES_EMBALAGENS.md` | Validado localmente no UX-01C |
| Unidades e conversoes | `cadastros/UNIDADES_CONVERSOES.md` | Manual do contrato existente; gate visual pendente |
| Clientes e propriedades | A criar no fechamento do UX-01C | Pendente |
| Pessoas e vinculos | A criar no fechamento do UX-01C | Pendente |
| Formulas e garantias | `producao/FORMULAS_GARANTIAS.md` | Em validação local |
| OP MAPA e Ordem de Envase | `producao/ORDEM_ENVASE.md` | Em validação local |
| Producao | Complemento no fechamento do fluxo de OP | Parcial |
| Ordens | A criar no UX-01F | Pendente |
| Qualidade | A criar no UX-01G | Pendente |
| Romaneio | A criar no UX-01H | Pendente |
| Pedidos e aprovacao | `pedidos/PEDIDOS_E_APROVACAO.md` | Implementado e validado tecnicamente na 0078 |

## Manutencao

Mudanca funcional exige atualizacao do manual no mesmo pacote. Capturas podem
ser usadas na homologacao, mas permanecem fora do Git quando contiverem sessao,
identidade, dados de teste ou qualquer informacao operacional.
